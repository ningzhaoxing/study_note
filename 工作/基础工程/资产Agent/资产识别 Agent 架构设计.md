# 资产识别 Agent 架构设计

## 概述

资产识别 Agent 采用**三层显式路由架构**：Handler（数据安全守卫）→ 意图识别层（Classifier）→ 专用 Agent（执行）。

这一设计的核心理念是：**LLM 只负责理解意图，执行路径由 Go 代码控制**。每个 Agent 职责单一，意图识别层与业务逻辑解耦，使得系统在当前模型能力下保持可预测性，同时为未来切换单 Agent 架构预留了清晰的演进路径。

---

## 整体架构

```
用户请求
│
▼
┌─────────────────────────────────────────┐
│ Handler 层（数据安全守卫）               │
│ - 资产列表准备与过滤                     │
│ - 确认状态管理（globalConfirmStore）     │
│ - 数据覆盖安全检查                       │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│ 意图识别层（intent.Classifier）          │
│ 优先级：问句检测 → 关键词 → LLM → 兜底  │
└──────────────────┬──────────────────────┘
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
  consultation   retry   identification
       │           │           │
       ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────────┐
│咨询 Agent│ │识别 Agent│ │  识别 Agent  │
│(MaxStep=5│ │(重试资产)│ │ (全量/新增)  │
│ 2 个工具)│ │          │ │(MaxStep=15)  │
└──────────┘ └──────────┘ └──────────────┘
```

---

## 各层职责

### Handler 层

Handler 是整个流程的入口，承担两个核心职责：

**数据安全守卫**：在进入识别流程前，检查目标资产是否已有识别结果。若存在已有数据，向用户发送确认询问，等待用户明确选择（覆盖全部 / 只处理新的 / 取消），防止意外覆盖。

**确认状态管理**：通过 `globalConfirmStore` 跨请求保存待确认状态。用户的确认回复作为新请求进入时，Handler 优先拦截处理，不经过意图识别层。

```go
// 确认回复优先于意图识别
if pendingStatus := globalConfirmStore.getAndClear(session.SessionID); pendingStatus != nil {
    confirmReply := parseConfirmReply(req.UserMessage, pendingStatus)
    // 直接处理，跳过 Classifier
}
```

### 意图识别层

`intent.Classifier` 是系统中设计最干净的一层，与任何业务逻辑完全解耦。

**四级降级策略**（按优先级）：

| 优先级 | 策略     | 延迟     | 说明                       |
| --- | ------ | ------ | ------------------------ |
| 1   | 问句检测   | <1ms   | 含 `?`/`？` 或问句关键词，直接判定为咨询 |
| 2   | 关键词匹配  | <1ms   | 精确/模糊关键词命中，无需 LLM        |
| 3   | LLM 分类 | ~500ms | 带超时（8s）和重试（2次）           |
| 4   | 兜底     | 0ms    | 返回配置的默认意图                |


**设计亮点**：`chatModel` 为可选参数，传 `nil` 即禁用 LLM，退化为纯规则分类器。`IntentDef` 是纯数据结构，新增意图类型只需传入新的定义，不修改 Classifier 本身。

### 专用 Agent 层

当前有两个专用 Agent：

**AssetIdentificationAgent**
- 工具集：`batch_identify_asset_security_properties`、`get_project_context`、`query_asset_knowledge`、`validate_json_output` 等
- MaxStep：15（支持容错和重试）
- 内置 `EinoRetryManager`，单个资产失败不影响整批
- `UnknownToolsHandler`：处理模型返回空工具名的降级（针对 Qwen 等模型的兼容性）

**AssetConsultationAgent**
- 工具集：仅 2 个（`get_project_context`、`query_asset_knowledge`）
- MaxStep：5（咨询场景步数少）
- 物理上没有写库工具，从根本上杜绝咨询时误操作数据

两者共享同一套 `LongTermMemory` + `Persister` 机制，对话历史跨 Agent 持久化。

---

## 关键设计决策

### 为什么拆成两个 Agent 而不是一个？

识别和咨询的差异足够大，合并会带来实质性问题：

- 工具集合并后，模型在咨询时可能误调用写库工具
- MaxStep 需要取最大值，咨询场景浪费 token
- 系统提示词需要同时覆盖两种模式，变得复杂且容易产生歧义

拆分后，每个 Agent 的工具集、MaxStep、系统提示词都针对单一场景优化。

### 为什么意图识别用 LLM 而不是纯规则？

纯规则（关键词匹配）覆盖了大多数明确指令，但自然语言的边界情况很多。LLM 作为最后一道兜底，处理规则无法覆盖的模糊表达。同时，问句检测和关键词匹配作为快速路径，避免了大多数请求走 LLM，控制了延迟和成本。

### 为什么确认状态在 Handler 层而不是 Agent 层？

确认流程本质上是一个跨请求的状态机，与 LLM 推理无关。放在 Handler 层：

- 逻辑清晰，不污染 Agent 的推理上下文
- Agent 保持无状态，每次调用独立，便于测试
- 状态管理集中，不会出现 Handler 和 Agent 双轨状态的问题

---

## 当前已知问题

**Agent 创建逻辑泄漏到 Handler**

`executeIdentificationV2` 和 `executeConsultationV2` 中包含完整的 `agent.NewXxxAgent(ctx, config)` 构建代码。更严重的是，在发送确认询问时也创建了一个完整的 `AssetIdentificationAgent` 实例，仅用于生成确认文案，存在不必要的开销。

**路由逻辑固化在 switch-case**

新增意图类型需要修改 Handler 的 switch 分支，Handler 会随业务增长变重。

---

## 未来扩展方向

### 近期：Agent 工厂解耦

将 Agent 的创建逻辑从 Handler 中移出，封装为独立的工厂函数或构建器：

```go
// 目标形态
type AgentFactory interface {
    BuildIdentificationAgent(ctx context.Context, session *StreamSession) (*AssetIdentificationAgent, error)
    BuildConsultationAgent(ctx context.Context, session *StreamSession) (*AssetConsultationAgent, error)
}
```

Handler 只持有工厂引用，不知道 Agent 的构建细节。新增 Agent 类型时，Handler 不需要改动。

### 中期：意图注册表

将 intent → handler 的映射从 switch-case 改为注册表：

```go
type IntentRouter struct {
    routes map[string]IntentHandler
}

func (r *IntentRouter) Register(intent string, handler IntentHandler) {
    r.routes[intent] = handler
}

func (r *IntentRouter) Dispatch(ctx context.Context, intent string, req Request) error {
    return r.routes[intent].Handle(ctx, req)
}
```

新增意图类型只需要 `router.Register("new_intent", newHandler)`，主流程不变。

### 远期：平滑切换单 Agent

当 LLM 能力显著增强（工具调用准确率和多步推理稳定性大幅提升）时，可以将多个专用 Agent 合并为一个 OmniAgent，同时保留 `intent.Classifier` 作为前置快速过滤：

```
用户请求
│
▼
intent.Classifier（快速路径：问句/关键词直接短路）
│
▼
OmniAgent（持有所有工具，自主决策执行路径）
```

由于意图识别层与业务逻辑解耦，`Classifier` 在两种架构下都能复用。切换时只需要：

1. 实现 `OmniAgent`，注册全量工具集
2. 将 `IntentRouter` 的所有路由指向同一个 `OmniAgent`
3. 逐步下线专用 Agent

Handler 层和意图识别层的代码几乎不需要改动。

### 扩展新业务模块的标准路径

基于当前架构，接入新的业务模块（如威胁场景识别）的标准步骤：

1. 在 `intent` 包中定义新的 `IntentDef`
2. 实现专用 Agent（参考 `AssetConsultationAgent` 的结构）
3. 实现 Agent 工厂方法
4. 在 `IntentRouter` 中注册新意图和对应 Handler

每一步改动范围明确，不影响已有模块。

---

## 与损害场景 Agent 的架构对比

| 维度      | 资产 Agent（显式路由）    | 损害场景 Agent（单 Agent） |
| ------- | ----------------- | ------------------- |
| 路由决策者   | Go 代码             | LLM（ReAct 推理）       |
| 工具集     | 按 Agent 隔离（2~3 个） | 集中（~20 个）           |
| MaxStep | 5~15（精确控制）        | 1000（兜底补丁）          |
| 可预测性    | 高                 | 依赖模型能力              |
| 模型升级收益  | 有限（路由逻辑仍需人维护）     | 直接受益                |
| 适合场景    | 边界清晰、数据安全要求高      | 决策复杂、需要灵活组合         |

两种架构没有优劣之分，取决于任务特性和当前模型能力。资产侧的显式路由在当前阶段提供了更强的可控性，而良好的解耦设计确保了未来向单 Agent 架构演进时的切换成本极低。
