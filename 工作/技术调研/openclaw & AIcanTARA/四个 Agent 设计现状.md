# 四个 Agent 设计现状

> 文档目的：在"使用 Skill 统一为主 Agent"方案调研中，系统梳理现有四个 Agent 的代码设计与产品定义，为后续方案设计提供基线。
>
> 信息来源：代码调研（`tara/service/agent/`）+ PRD 文档（`AIcanTARA_PM_Context/04_workspace/prd/AI Agent/`）

---

## 一、整体数据流

```text
资产识别 Agent
    ↓ 输出：资产安全属性（C/I/A/NR/Authz/Authn/F）
损害场景 Agent
    ↓ 输出：损害场景描述 + 四维影响等级 + CAL 等级
威胁场景 Agent
    ↓ 输出：威胁场景描述（+ 可选 R155 映射）
攻击树 Agent
    ↓ 输出：攻击树节点（含五维因子）
```

---

## 二、资产识别 Agent

### 2.1 文件清单

| 文件 | 职责 |
| --- | --- |
| `asset_identification_agent.go` | Agent 主体，含构造、工具注册、ReAct 配置 |
| `asset_identification_agent_v2.go` | v2 统一入口 `RunV2()`，保留旧方法向后兼容 |
| `asset_identification_agent_events.go` | SSE 事件流，`EventStreamCombiner` |
| `asset_identification_tools.go` | 5 个工具的实现 |
| `asset_intent_types.go` | 意图类型枚举 |
| `asset_identification_get_failed_items_tool.go` | 获取失败项工具 |
| `batch_identification_tool.go` | 批量识别工具 |

### 2.2 Agent 结构

```go
type AssetIdentificationAgent struct {
    reactAgent           *react.Agent           // Eino ReAct 核心
    chatModel            model.ChatModel
    toolCallingChatModel model.ToolCallingChatModel
    assetRepo            AssetRepository
    projectContextRepo   ProjectContextRepository
    knowledgeRepo        AssetKnowledgeRepository // 可选
    conversationMemory   Memory                   // 多轮对话记忆
    eventCombiner        *EventStreamCombiner     // SSE 流
    retryManager         *EinoRetryManager
    sessionID            string
    currentRoundID       string
}
```

### 2.3 工具列表（5 个）

| 工具名 | 功能 |
| --- | --- |
| `get_project_context` | 获取项目信息、数据流图 |
| `identify_asset_security_properties` | 核心识别工具，调用 LLM 分析安全属性 |
| `batch_identify_asset_security_properties` | v2 批量识别入口 |
| `save_asset_security_properties` | 持久化识别结果 |
| `validate_json_output` | 校验并修正 Agent 输出的 JSON |
| `get_failed_items` | 获取失败项列表（支持重试场景） |

### 2.4 关键设计特点

- **框架**：Eino `react.Agent`，通过 `MessageModifier` 注入 System Prompt
- **记忆**：`conversationMemory`（Memory 接口）+ 外部 `Persister` 持久化，SessionID 绑定
- **事件流**：`EventStreamCombiner` 合并多个事件源，支持 SSE 推送
- **v2 入口**：`RunV2()` 统一调用，旧方法 `BatchIdentifySecurityProperties` / `StreamWithIntent` 保持兼容
- **MaxStep**：默认 15 步

### 2.5 PRD 定义的业务能力

#### 能力1：安全属性识别

- 7 个属性：C（机密性）、I（完整性）、A（可用性）、NR（不可抵赖性）、Authz（可授权）、Authn（真实性）、F（新鲜性）
- 等级：High / Medium / Low / N/A
- 仅处理"安全属性=未设置"的资产

#### 能力2：网络安全相关性分析

- 4 个维度：E/E 相关、车辆安全、用户数据、网络功能
- 派生规则：任一为"是"→ 整体相关；全否→ 不相关

#### 主要用户场景

- 80%：默认引用全量，直接执行
- 15%：调整引用范围（部分资产/特定属性）后执行
- 5%：重试失败项（范围由失败列表决定，不受当前引用影响）
- 咨询：解释识别结果原因

### 2.6 PRD vs 代码的差异点

> ⚠️ PRD 定义 7 个安全属性，但代码中 `SecurityPropertyType` 只有 C/I/A 三种（见 `common_types.go`）。NR/Authz/Authn/F 四个属性在代码层的处理路径待确认。

---

## 三、损害场景 Agent

### 3.1 文件清单

| 文件 | 职责 |
| --- | --- |
| `damage_scenario_agent.go` | Agent 主体（最复杂，约2000行），含所有意图处理逻辑 |
| `damage_scenario_intent_tools.go` | 意图分类工具 `classify_user_intent` |
| `damage_vector_search_tool.go` | RAG 向量检索工具 |

### 3.2 Agent 结构

```go
type DamageScenarioAgent struct {
    reactAgent          *react.Agent
    chatModel           model.ToolCallingChatModel
    damageRepo          DamageScenarioRepository
    projectContextRepo  ProjectContextRepository
    ragManager          interface{}              // 可选 RAG
    retryManager        *EinoRetryManager
    callbackHandlers    []callbacks.Handler
    memory              Memory
    sessionStateManager DamageScenarioSessionStateManager
}
```

### 3.3 核心枚举与值对象

#### 意图类型（DamageIntentType）

- `damage_generation`：生成损害场景
- `cal_analysis`：CAL 等级分析
- `consultation`：问答咨询
- `confirmation`：等待用户确认（多轮）
- `retry`：重试失败项

#### 影响等级（ImpactLevel）

Severe（严重，4分）> Major（重大，3分）> Moderate（中等，2分）> Negligible（可忽略，1分）

#### 影响维度（ImpactDimension）

Safety / Financial / Operational / Privacy

#### 攻击向量（AttackVector）

Physical / Local / AdjacentNetwork / RemoteNetwork

#### CAL 等级（CALLevel）

CAL1 ~ CAL4

#### ImpactAssessment（不可变值对象）

- 封装四维度影响等级
- `GetMaxLevel()` 获取最高维度
- `ToMap()` 序列化

#### ParsedIntent（结构化意图）

- 含 `NeedConfirmation`，触发多轮确认流
- `ProcessingMode`：ModeProcessAll / ModeProcessNewOnly

#### InteractionState（会话状态）

- 30 分钟过期
- `AwaitingConfirmation` 标记

### 3.4 CAL 查表逻辑（ISO/SAE 21434）

| 影响等级 | 物理 | 本地 | 相邻网络 | 远程网络 |
| --- | --- | --- | --- | --- |
| Severe | CAL2 | CAL2 | CAL3 | CAL4 |
| Major | CAL1 | CAL2 | CAL3 | CAL4 |
| Moderate | CAL1 | CAL1 | CAL2 | CAL3 |
| Negligible | CAL1 | CAL1 | CAL1 | CAL2 |

聚合规则：取该资产所有损害场景的**最高影响等级**，结合资产特征判定攻击向量，交叉查表得 CAL 等级。

### 3.5 关键设计特点

- **最复杂的 Agent**：承担损害生成 + CAL 分析 + 意图分类 + 多轮确认
- **会话状态管理**：`InMemoryDamageScenarioSessionStateManager`，30 分钟过期
- **意图分类工具**：专用 `classify_user_intent` 工具，LLM 驱动分类
- **重试逻辑**：失败列表驱动，不受当前引用范围影响

### 3.6 PRD 定义的业务能力

- **损害场景生成**：遍历"资产×安全属性"组合，只处理无损害场景的条目
- **CAL 分析**：按资产聚合，输出攻击向量 + CAL 等级 + 推理说明

---

## 四、威胁场景 Agent

### 4.1 文件清单

| 文件 | 职责 |
| --- | --- |
| `threat_scenario_agent.go` | Agent 主体（约2500行），含所有业务逻辑 |
| `threat_scenario_agent_tools.go` | 9 个工具的实现 |
| `threat_scenario_agent_impact_filter_helper.go` | 影响等级过滤辅助逻辑 |
| `threat_vector_search_tool.go` | RAG 向量检索工具 |

### 4.2 Agent 结构

```go
type ThreatScenarioAgent struct {
    reactAgent          *react.Agent
    chatModel           model.ToolCallingChatModel
    tools               []*schema.ToolInfo
    threatScenarioRepo  ThreatScenarioRepository
    projectContextRepo  ProjectContextRepository
    ragManager          interface{}              // 可选 RAG
    retryManager        *EinoRetryManager
    callbackHandlers    []callbacks.Handler
    memory              Memory
    sessionStateManager ThreatScenarioSessionStateManager
}
```

### 4.3 核心枚举与值对象

#### AttackFeasibility（攻击可行性）

- VeryHigh（4）/ High（3）/ Medium（2）/ Low（1）
- 注意：攻击可行性**不在生成威胁场景时评估**，由后续攻击树和攻击路径计算得出

#### ThreatScenario（输出值对象）

- projectID, damageID, threatID, assetID, assetName, assetType
- threatScenario（描述）、attackFeasibility、reasoning

#### DamageScenarioInfo（输入值对象）

- 私有字段 + getter 方法（不可变）
- impactLevels：四维度影响等级 map

### 4.4 工具列表（9 个）

| 工具名 | 功能 | 说明 |
| --- | --- | --- |
| `get_project_assumptions` | 获取项目假设信息 | 上下文查询 |
| `get_dataflow_diagram` | 获取数据流图 | 上下文查询 |
| `search_threat_scenarios` | RAG 知识库检索 | **仅咨询模式**，生成时不手动调 |
| `find_unprocessed_damages` | 查找未生成威胁的损害场景 | 支持 damage_ids + min_impact_level 过滤 |
| `get_damage_scenario` | 获取单个损害场景详情 | 数据查询 |
| `check_threat_status` | 检查威胁生成状态 | ⚠️ 已废弃，Handler 层处理 |
| `query_threat_scenarios` | 查询已生成的威胁场景 | 数据查询 |
| `generate_threat_scenario` | 生成威胁场景（核心） | **内置 RAG + 自动保存到数据库** |
| `generate_r155_reference` | 生成 R155 映射 | 可选，用户显式要求才调 |

### 4.5 关键设计特点

#### Handler / Agent 职责分离

- Handler 层（`ProcessStream()`）负责：数据状态检查 + 用户确认流
- Agent 层：直接执行生成，不再检查数据状态
- System Prompt 中明确声明 `check_threat_status` 已废弃

#### 影响等级过滤

`find_unprocessed_damages` 的 `min_impact_level` 参数：

- 严重(Severe) > 重大(Major) > 中等(Moderate) > 可忽略(Negligible)
- 支持中文/英文输入

#### 工具自动保存

`generate_threat_scenario` 内部自动入库，Agent 无需额外调 write 工具，减少步骤数。

#### 强身份约束

System Prompt（约500行）有严格角色边界，拒绝跨职责请求。

#### 其他配置

- MaxStep：默认 300 步（支持大批量生成）
- 会话状态：`ThreatScenarioSessionStateManager`，30 分钟过期

### 4.6 Handler 层确认流（ProcessStream() 实现）

```text
1. 从 SessionStateManager 获取历史状态
2. 如果在等待确认，复用上轮上下文
3. 检查 context 是否取消
4. 如有 DamageIDs 且非等待确认状态 → 调用 repo 检查威胁状态
   ├── 有已存在的威胁场景 → 构建 ThreatDataStatus，发送确认事件，return nil（等待用户响应）
   └── 全是新的 → 继续
5. 保存用户消息到 Memory
6. 调用 ReAct Agent（processWithReActAgent）
```

### 4.7 PRD 定义的业务能力

- **威胁场景生成**（核心）：每个损害场景生成 1~N 个威胁，描述必填，R155 映射默认不生成
- **R155 映射**（可选）：用户显式要求才生成，支持事后批量补充
- **咨询问答**：解释威胁原因、攻击路径，不执行生成操作

#### 意图识别（PRD 定义的三类）

| 意图 | 识别方式 | Agent 行为 |
| --- | --- | --- |
| 执行任务 | "生成"/"创建" | 检测数据状态 → 确认/执行 |
| 咨询问答 | "为什么"/"是什么" | 直接回答，不执行 |
| 确认回复 | "是"/"只处理新的" | 根据上下文执行 |

#### 数据状态三种情况

- 情况A（全新）→ 直接执行
- 情况B（全已有）→ 询问是否覆盖
- 情况C（混合）→ "只处理新的 N 个" or "全部覆盖"

AI 入口限制（V1.0）：仅在"损害场景关联威胁场景"子视图下显示，资产关联视角 V2.1 再做。

---

## 五、攻击树 Agent

### 5.1 文件清单（模块化设计）

| 文件 | 职责 |
| --- | --- |
| `attack_tree/agent.go` | 纯业务逻辑，协调各组件（不管任务生命周期） |
| `attack_tree/ai_generator.go` | 封装 Eino Agent，解析 LLM 输出 |
| `attack_tree/attack_ai_context.go` | 收集上下文（祖先链、兄弟节点、关联资产） |
| `attack_tree/service.go` | 编排 Agent + TaskService（对外入口） |
| `attack_tree/task_service.go` | 任务生命周期管理，Worker Pool |
| `attack_tree/prompt_builder.go` | 构建 Prompt |
| `attack_tree/template_retriever.go` | Neo4j 模板检索（接口 + 默认实现） |
| `attack_tree/ai_generator_types.go` | 生成输出类型定义 |

### 5.2 核心结构

```go
// 业务逻辑层（纯）
type AttackTreeAgent struct {
    contextCollector  *AttackAIContext
    templateRetriever TemplateRetriever
    aiGenerator       *AIGenerator
    dao               *dao.AttackTreeV2Dao
}

// 编排层（对外暴露）
type AttackTreeService struct {
    agent       *AttackTreeAgent
    taskService *TaskService
}

// 任务层（并发管理）
type TaskService struct {
    // workerPool 默认 10 个 worker
    // 任务状态: pending → running → completed/failed/cancelled
}
```

### 5.3 生成流程（5 步）

```text
1. AttackAIContext.Get() / GetWithTreeID()
   → 收集：威胁场景描述、根节点、祖先链、当前节点、已有子节点、关联资产

2. TemplateRetriever.Retrieve()
   → Neo4j 查询相似攻击模板（扁平格式：nodes + relationships）

3. buildPromptWithParentID()
   → 组合上下文 + 模板，构建完整 Prompt

4. AIGenerator.Generate()
   → 调用 LLM，输出 GenerateOutput{Nodes, Relationships, AndGroups, Strategy, Confidence}

5. convertFlatOutputToDBNodesWithRelations()
   → 处理父子关系、孤儿节点
   → 在 Description 字段嵌入元数据标记：
     [AI_ID:...] [AI_PARENT:...] [AI_CHILDREN:...] [AI_EDGE_TYPE:...] [AI_ORPHAN:...]
   → TaskService 保存时提取并清理这些标记
```

### 5.4 节点 ID 编码

AI 生成的临时 ID 替换为 `AS-{N}` 格式：

- 查询数据库获取当前项目最大序列号
- 递增分配，确保全局唯一
- 同步替换 relationships 和 and_groups 中的引用

### 5.5 五维因子（攻击可行性评估）

每个攻击步骤节点包含五个维度，映射为数据库枚举索引：

| 维度 | 字段 | 枚举值（举例） |
| --- | --- | --- |
| 耗时（ET） | ElapsedTime | 1天以内→1, 1周以内→2, ... |
| 专业知识（SE） | SpecialistExpertise | 外行→1, 熟练→3, 专家→4 |
| 目标知识（KoI） | KnowledgeOfTOE | 公开→1, 受限→2, 保密→3, 严格保密→4 |
| 操作机会（WoO） | WindowOfOpportunity | 无限制→1, 简单→2, 中等→3, 困难→4 |
| 设备（Eq） | Equipment | 标准→1, 专用→2, 定制→3, 多种定制→4 |

可行性等级计算（`calculateFeasibilityLevelFromWeights`）：

- 将枚举索引转为权重分值，求和
- 总分 ≥ 25 → 极低；≥ 20 → 低；≥ 14 → 中；< 14 → 高

### 5.6 关键设计特点

- **最清晰的职责分离**：Agent（逻辑）/ Service（编排）/ TaskService（并发）三层分离
- **Worker Pool**：默认 10 个并发 worker，支持批量并行生成
- **Auto-Save 选项**：TaskService 可配置自动保存到数据库
- **流式支持**：`AIGenerator.GenerateStream()` 返回事件 channel
- **Context 取消**：支持 `ctx.Done()` 取消进行中的任务
- **全局单例**：TaskService 可作为全局单例使用

### 5.7 PRD 定义的批量生成能力（v1.1）

触发方式：

- 列表外侧多选（只有未创建攻击树的威胁场景可选中）
- 点击「✨ AI批量生成 (N)」按钮 → 二次确认弹窗 → 并行生成

生成内容：从根节点出发，初始结构 1-2 层，AND/OR 结构，预填五维因子

进度外显（两处）：

- 列表中：`✨ AI生成中` 标签（与缩略图解耦的独立组件）
- 画布切换面板：威胁场景项右侧 spinner

失败处理：单个失败 → 该行恢复"未创建"状态，其他继续；Toast 只在相关页面显示

---

## 六、共同设计模式

### 6.1 框架层

| Agent | 框架 | 备注 |
| --- | --- | --- |
| 资产识别 | Eino `react.Agent` | MessageModifier 注入 System Prompt |
| 损害场景 | Eino `react.Agent` | 同上 |
| 威胁场景 | Eino `react.Agent` | MaxStep=300 |
| 攻击树 | Eino ADK / `ChatModelAgent` | 另有自定义 AIGenerator 封装 |

### 6.2 Repository 模式

所有 Agent 通过 Config 注入 Repository 接口：

- `AssetRepository`
- `ProjectContextRepository`
- `DamageScenarioRepository`
- `ThreatScenarioRepository`
- `AttackTreeV2Dao`

可测试、可替换，测试时可使用 Mock 实现。

### 6.3 记忆系统

| 接口/实现 | 说明 |
| --- | --- |
| `Memory` 接口 | Add / Retrieve / Persist |
| `InMemory` | 纯内存实现，MaxMsgCount 可配 |
| `ILongTermMemory` | 扩展接口，支持外部 Persister 持久化 |
| `SmartMemory` | 基于 semantic_query 的语义检索 |

会话绑定：`SessionID` = 项目ID + 页面标识 + 账号ID（三维度隔离）

### 6.4 会话状态管理

损害场景 Agent 和威胁场景 Agent 各自有：

- `InMemoryXxxSessionStateManager`：基于 map，RWMutex 保护
- 30 分钟过期（`IsExpired()` 检查）
- `AwaitingConfirmation` 标记多轮确认状态
- `CleanupExpired()` 批量清理过期会话

### 6.5 RAG 集成

| Agent | RAG 实现 | 使用方式 |
| --- | --- | --- |
| 损害场景 | `damage_vector_search_tool.go` | 可选，通过 RAGManager 注入 |
| 威胁场景 | `threat_vector_search_tool.go` | generate 工具内部自动调用；search 工具仅咨询 |
| 攻击树 | `TemplateRetriever`（Neo4j） | 每次生成前必调，检索攻击模板 |

### 6.6 事件流

资产识别 Agent 有专用事件系统：

- `EventEmitter`：单事件源发布
- `EventStreamCombiner`：合并多个发布者
- `EventReplayer`：历史事件回放
- `ConversationEvent`：结构化事件，含类型、内容、元数据

其他 Agent 通过 `callbackHandlers`（Eino callbacks）推送事件，或通过 `chan<- *ThreatEvent` 传递（威胁场景 Agent 的 `ProcessStream`）。

### 6.7 重试机制

- `EinoRetryManager`：可配置最大重试次数、退避策略
- 工具层：`validate_json_output` 用于修正 LLM 的格式错误输出
- 失败列表驱动：重试时范围由上次失败列表决定，不受当前引用影响

---

## 七、PRD vs 代码实现对照

| 维度 | PRD 定义 | 代码实现状态 |
| --- | --- | --- |
| 威胁 Agent：确认流 | Handler 层做数据状态检查和用户确认 | ✅ `ProcessStream()` 第5步已实现 |
| 威胁 Agent：R155 | 用户显式要求才生成 | ✅ `generate_r155_reference` 工具存在 |
| 威胁 Agent：意图识别 | 3 类意图（执行/咨询/确认） | ✅ System Prompt 详细规则 |
| 威胁 Agent：影响等级过滤 | min_impact_level 过滤参数 | ✅ `find_unprocessed_damages` 支持 |
| 攻击树：并行生成 | 多个威胁场景并行独立 | ✅ Worker Pool（默认10并发）|
| 攻击树：进度外显 | 列表标签 + 画布面板 spinner | 后端 TaskService 支持，前端待对接 |
| 资产识别：7 个属性 | C/I/A/NR/Authz/Authn/F | ⚠️ 代码 `SecurityPropertyType` 仅 C/I/A 三种 |
| 损害 Agent：CAL 分析 | 攻击向量 × 影响等级查表 | ✅ `CalLevel` 枚举和查表已实现 |
| 聊天记录：三维度隔离 | 项目 + 页面 + 账号 | ✅ SessionID 拼接规则已实现 |

---

## 八、待厘清问题（调研中发现）

1. **资产识别 7 属性差异**：PRD 定义 7 个，代码只有 3 个。其余 4 个（NR/Authz/Authn/F）是否在其他代码路径处理？还是尚未实现？

2. **威胁场景 `check_threat_status` 工具**：System Prompt 标记为"已废弃，Handler 层已处理"，但工具代码仍存在（`checkThreatStatusTool`）。实际调用链中是否还有路径会用到？

3. **攻击树与上游三个 Agent 的触发关系**：攻击树批量生成（v1.1 PRD）定义了"列表多选触发"，但上游三个 Agent 的 `ProcessStream` / `RunV2` 是否有对应的批量触发入口？当前看到的 `GenerateThreatScenarios` 可批量，但攻击树侧的 `SubmitBatchNodeGeneration` 是否已对接前端？

4. **损害 / 威胁 Agent 会话状态管理器的重复设计**：两个 Agent 各自实现了独立的 `InMemoryXxxSessionStateManager`，有大量重复代码。如果后续统一为主 Agent，这两套状态机如何合并？
