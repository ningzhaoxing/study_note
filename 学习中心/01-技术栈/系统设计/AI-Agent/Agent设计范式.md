---
tags:
  - AI-Agent
  - 系统设计
  - 面试
  - ReAct
  - Pipeline
  - Multi-Agent
aliases:
  - Agent范式
  - Agent设计模式
  - LLM Agent架构
---

# Agent 设计范式

> 核心思路：Agent = LLM + 工具 + 记忆 + 规划。不同的范式本质上是对"规划-执行"这一循环的不同拆解方式。

## 1. Agent 核心概念

### 四大组成要素

| 要素 | 说明 | 技术实现 |
|------|------|----------|
| **LLM（大脑）** | 负责推理、规划与决策 | ChatModel / Completion API |
| **工具（手脚）** | 与外部世界交互的能力 | Function Call / Tool Use |
| **记忆（状态）** | 跨步骤/跨会话的信息保持 | 上下文/向量库/KV存储 |
| **规划（策略）** | 分解目标、制定执行路径 | ReAct循环/Plan-Execute/CoT |

### Agent 与普通 LLM 调用的本质区别

普通 LLM 调用是**单次请求-响应**，是无状态的。Agent 是**多轮自主循环**，LLM 自己决定下一步做什么、调用什么工具、何时停止。这种"自主性"是 Agent 的核心特征。

```
普通调用：User → LLM → Response（一次性）
Agent：   User → LLM → [决策→工具→观察→决策...] → Final Answer（循环直到完成）
```

---

## 2. ReAct 范式（Reasoning + Acting）

> 论文：ReAct: Synergizing Reasoning and Acting in Language Models（Yao et al., 2022）

### 工作原理

ReAct 将推理（Reasoning）和行动（Acting）**交替进行**，形成 `Thought → Action → Observation` 的循环。

```
用户输入
   ↓
[Thought]  LLM推理：我需要先查询资产列表
   ↓
[Action]   调用工具：query_assets(project_id="P001")
   ↓
[Observation] 工具返回：["服务A", "服务B", "数据库C"]
   ↓
[Thought]  LLM推理：已获得资产列表，现在分析每个资产的风险
   ↓
[Action]   调用工具：analyze_risk(asset="服务A")
   ↓
[Observation] 工具返回：{risk_level: "高", threats: [...]}
   ↓
... 循环直到 LLM 判断任务完成 ...
   ↓
[Final Answer] 输出最终结果
```

### Go 伪代码示意

```go
// ReAct Agent 核心循环
func (a *ReactAgent) Run(ctx context.Context, userInput string) (string, error) {
    messages := []Message{{Role: "user", Content: userInput}}

    for step := 0; step < a.maxSteps; step++ {
        // 1. LLM推理，决定下一步行动
        response, err := a.llm.Generate(ctx, messages)
        if err != nil {
            return "", err
        }

        // 2. 判断是否完成（Final Answer）
        if response.IsFinished() {
            return response.FinalAnswer, nil
        }

        // 3. 解析工具调用意图
        toolCall := response.ToolCall // {name: "query_assets", args: {...}}

        // 4. 执行工具
        observation, err := a.tools.Execute(ctx, toolCall.Name, toolCall.Args)
        if err != nil {
            observation = fmt.Sprintf("工具执行失败: %v", err)
        }

        // 5. 将 Observation 追加到上下文，进入下一轮
        messages = append(messages,
            Message{Role: "assistant", Content: response.Thought + "\n调用: " + toolCall.Name},
            Message{Role: "tool", Content: observation},
        )
    }
    return "", errors.New("超出最大步骤数限制")
}
```

### 优势与劣势

**优势：**
- 推理过程**完全可解释**（每个 Thought 都可记录）
- 适合**多步骤工具调用**，能根据中间结果动态调整策略
- 错误可恢复：工具失败后 LLM 可推理换一种方案

**劣势：**
- 串行执行，延迟较高
- 依赖 LLM 推理能力，弱模型容易陷入循环或幻觉
- Token 消耗随步骤数线性增长

### 适用场景

- **资产识别与风险管理**（AIcanTARA项目）：需要多轮查询，根据资产类型动态选择分析策略
- **客服机器人**：查订单 → 判断状态 → 决定退款/转人工
- **代码 Debug Agent**：运行代码 → 看报错 → 修改 → 重试

---

## 3. Plan-Execute 范式

### 工作原理

将任务拆分为**两个独立阶段**：
1. **Plan（规划）**：LLM 先生成完整的执行计划（任务列表）
2. **Execute（执行）**：按计划逐步（或并行）执行，不再让 LLM 临时决策

```
用户输入
   ↓
[Planner LLM]  生成计划：
  Step 1: 查询所有资产
  Step 2: 对每个资产做威胁分析（可并行）
  Step 3: 生成风险汇总报告
   ↓
[Executor]  并行执行 Step2（Worker Pool）
   ↓
[Aggregator]  汇总结果
   ↓
最终输出
```

### 优势与劣势

**优势：**
- 全局规划，各步骤**可并行执行**（性能更高）
- Planner 和 Executor 可以是不同模型（Planner 用强模型，Executor 用弱模型）
- 适合任务边界清晰的场景

**劣势：**
- 规划阶段完成后**缺乏灵活性**（执行中发现问题难以重新规划）
- 需要 LLM 一次性生成高质量计划，对模型要求高

### 适用场景

- **批量分析任务**（如 AIcanTARA 中对多个用户/系统并发分析）
- **报告生成流水线**：数据采集 → 分析 → 格式化 → 输出
- 任务分解结构固定、不需要动态调整的场景

---

## 4. Multi-Agent 范式

### 协调者-执行者模式（Orchestrator-Worker）

```
           ┌─────────────────┐
           │  Orchestrator    │  ← 负责分配任务、汇总结果
           │  (协调Agent)    │
           └────────┬────────┘
                    │ 分派子任务
        ┌───────────┼───────────┐
        ↓           ↓           ↓
   ┌─────────┐ ┌─────────┐ ┌─────────┐
   │ Worker1 │ │ Worker2 │ │ Worker3 │
   │ 资产识别 │ │ 威胁分析 │ │ 报告生成 │
   └─────────┘ └─────────┘ └─────────┘
```

### 水平协作模式（Peer-to-Peer）

多个专业 Agent 平等协作，通过消息传递共享信息，各自负责独立领域，结果互相引用。

适用于：复杂对话系统、多专家会议 Agent

### 优势与劣势

**优势：**
- 专业化分工，每个 Agent 只需掌握一个领域
- 系统可扩展性强（新增 Agent 不影响其他）
- 并行执行，整体吞吐量高

**劣势：**
- 跨 Agent 通信开销
- 一致性难以保证（各 Agent 对同一概念理解可能不同）
- 调试和可观测性复杂

### 适用场景

- **AIcanTARA 多模块 Agent**：资产识别 Agent、威胁建模 Agent、攻击树 Agent 分工协作
- **意图分类 + 执行分离**：分类 Agent 识别意图，路由到对应的专业执行 Agent
- 大型企业知识库问答系统

---

## 5. Pipeline 范式

### 工作原理

将任务定义为**线性的、固定顺序的处理流水线**，每个节点有明确输入输出，节点间数据单向流动。

```
输入
 ↓
[Step 1: 检索模板]    → 从 Neo4j 检索攻击树模板
 ↓
[Step 2: 生成节点]    → LLM 根据模板 + 资产信息生成威胁节点
 ↓
[Step 3: 构建图谱]    → 将生成的节点写入 Neo4j 图数据库
 ↓
[Step 4: 格式化输出]  → 转换为前端可展示格式
 ↓
输出
```

### Go 伪代码示意（Eino Chain 风格）

```go
// Pipeline 定义（Eino Chain 风格）
chain := eino.NewChain[InputType, OutputType]().
    AppendRetriever(neo4jTemplateRetriever).  // Step1: 检索模板
    AppendLambda(buildPromptWithTemplate).    // Step2: 构建Prompt
    AppendChatModel(llmModel).               // Step3: LLM生成节点
    AppendLambda(parseAndWriteToNeo4j).      // Step4: 写入图数据库
    AppendOutputParser(jsonOutputParser)     // Step5: 格式化

result, err := chain.Invoke(ctx, input)
```

### 优势与劣势

**优势：**
- 流程**完全确定性**，易于测试和调试
- 各节点职责单一，可独立替换
- 性能可预测

**劣势：**
- 缺乏灵活性，无法根据中间结果动态分支
- 不适合需要多轮决策的复杂任务

### 适用场景

- **攻击树生成**（AIcanTARA）：固定流程，适合 Pipeline
- RAG（检索增强生成）标准流程
- 文档处理流水线：OCR → 分块 → Embedding → 存储

---

## 6. 各范式对比

| 维度 | ReAct | Plan-Execute | Multi-Agent | Pipeline |
|------|-------|--------------|-------------|----------|
| **灵活性** | 高（动态决策） | 中（规划后固定） | 高（多域协作） | 低（固定流程） |
| **可解释性** | 高（Thought可见） | 中（计划可见） | 低（跨Agent难追踪） | 高（步骤固定） |
| **并行能力** | 低（串行循环） | 高（步骤可并行） | 高（Agent并行） | 中（节点可并行） |
| **实现复杂度** | 低 | 中 | 高 | 低 |
| **适用规模** | 单任务 | 批量任务 | 大型系统 | 固定流程 |
| **Token消耗** | 高（多轮） | 中 | 高（多Agent） | 低 |
| **错误恢复** | 强（可推理重试） | 弱 | 中 | 弱（需重启） |
| **典型场景** | 资产风险分析 | 并发用户分析 | 多模块AIcanTARA | 攻击树生成 |

---

## 7. 实际项目选型思路（AIcanTARA 经验）

### 选型决策树

```
任务结构是否固定？
├─ 是 → 流程是否线性？
│        ├─ 是 → Pipeline（攻击树生成）
│        └─ 否 → Plan-Execute（并发分析）
└─ 否 → 是否涉及多个专业领域？
         ├─ 是 → Multi-Agent（模块协作）
         └─ 否 → ReAct（资产识别/风险管理）
```

### AIcanTARA 项目中的实际组合

在 AIcanTARA 项目中，并非单一使用某种范式，而是**分层组合**：

1. **顶层**：Multi-Agent 协调（意图分类 → 路由到对应子Agent）
2. **资产识别模块**：ReAct（需要多轮工具调用，动态查询）
3. **攻击树生成模块**：Pipeline（固定流程：检索Neo4j模板 → LLM生成 → 写回Neo4j）
4. **并发调度层**：Worker Pool + Plan-Execute（多用户并发分析）
5. **状态机**：15+ 意图分类的多步骤状态机（管理对话流转）

> 关键原则：**能用简单范式解决的，不要用复杂范式**。Pipeline 够用就别上 ReAct；单 Agent 够用就别上 Multi-Agent。

---

## 8. 面试高频问题

**Q1：ReAct 和 Chain-of-Thought（CoT）的区别？**

CoT 是纯推理，没有外部工具调用，所有推理都在 LLM 内部完成。ReAct 在 CoT 的基础上增加了与外部环境的交互（Action + Observation），能获取实时信息、执行真实操作。

**Q2：Multi-Agent 系统如何保证各 Agent 之间的一致性？**

通过共享的状态存储（如 Redis、数据库）、统一的消息格式规范、Orchestrator 负责最终裁决。在 AIcanTARA 项目中，我们用结构化的 JSON 消息格式定义 Agent 间通信协议，避免语义歧义。

**Q3：Pipeline 和 ReAct 你会怎么选？**

看任务是否需要"根据中间结果动态决策"。如果流程固定（如 RAG、攻击树生成），Pipeline 更简单可靠。如果任务需要根据工具返回结果调整策略（如资产风险分析），用 ReAct。实际项目中我们在攻击树生成用了 Pipeline，在资产识别/风险管理用了 ReAct。

**Q4：ReAct Agent 如何防止无限循环？**

1. 设置 `maxSteps` 上限（如最多 10 步）
2. 检测重复 Action（连续两步相同工具调用相同参数则终止）
3. 设置总 Token 预算上限
4. Timeout 机制（context deadline）

**Q5：介绍一下你们项目中的状态机设计？**

在 AIcanTARA 中，我们实现了 15+ 意图分类的多步骤状态机。用户输入经过意图分类后，状态机根据当前对话状态和意图，决定跳转到哪个处理节点。每个状态节点对应一个具体的 Agent 能力（如"查询资产"、"生成威胁"、"导出报告"等），状态转移由规则引擎 + LLM 联合决策，避免纯 LLM 决策的不确定性。

---

## 相关链接

- [[Agent能力体系-工具抽象]] - 工具调用、Skill、MCP协议
- [[Agent-Memory设计]] - 记忆分层与上下文管理
- [[Eino框架实践]] - CloudWeGo/Eino实战
- [[设计模式/综合]] - 设计模式与系统设计综合
