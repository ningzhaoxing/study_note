---
tags:
  - AI-Agent
  - Eino
  - CloudWeGo
  - 面试
  - Go
aliases:
  - Eino框架
  - CloudWeGo Eino
  - Eino ADK
---

# Eino 框架实践

> Eino（CloudWeGo）是字节跳动开源的 Go 语言 AI 应用开发框架，在 AIcanTARA 项目中作为 Agent 工程化底座使用。

---

## 一、Eino 框架概览

### 核心定位

Eino 是一个**组件化、图结构化**的 AI 应用开发框架：
- **组件化**：ChatModel、Retriever、Lambda、OutputParser 等标准组件可自由组合
- **图结构化**：支持将 AI 处理流程定义为 DAG（有向无环图），支持并行、条件分支
- **可观测**：内置 Trace 支持（与 OpenTelemetry 集成）

### 与 LangChain 的区别

| 维度 | Eino（Go） | LangChain（Python） |
|------|-----------|---------------------|
| 语言 | Go | Python |
| 并发模型 | goroutine + channel | asyncio |
| 类型安全 | 强类型（泛型） | 动态类型 |
| 性能 | 高（编译型） | 中（解释型） |
| 生态成熟度 | 较新 | 成熟 |
| 适用场景 | 高并发后端 | 快速原型 |

---

## 二、核心组件

### 2.1 ChatModel（LLM 接入层）

```go
import "github.com/cloudwego/eino/components/model"

// 创建 ChatModel（以 OpenAI 为例）
chatModel, err := openai.NewChatModel(ctx, &openai.ChatModelConfig{
    Model:       "gpt-4o",
    APIKey:      os.Getenv("OPENAI_API_KEY"),
    MaxTokens:   4096,
    Temperature: 0.1, // 降低随机性，提高稳定性
})

// 带工具的 ChatModel
response, err := chatModel.Generate(ctx, messages, model.WithTools(tools))
```

### 2.2 Chain（线性流水线）

Chain 将多个组件串联，上一个组件的输出自动成为下一个组件的输入：

```go
// 攻击树生成 Pipeline（AIcanTARA 项目实际架构）
chain, err := compose.NewChain[*AttackTreeInput, *AttackTreeOutput]().
    AppendRetriever(neo4jTemplateRetriever).   // Step1: 从 Neo4j 检索攻击树模板
    AppendLambda(buildPromptWithTemplate).     // Step2: 将模板注入 Prompt
    AppendChatModel(llmModel).                 // Step3: LLM 生成攻击节点
    AppendLambda(parseAndWriteToNeo4j).        // Step4: 解析并写入 Neo4j
    AppendOutputParser(jsonOutputParser).      // Step5: 格式化输出
    Compile(ctx)

result, err := chain.Invoke(ctx, input)
```

### 2.3 Graph（DAG 图结构，支持分支/并行）

```go
// 创建支持条件分支的图
graph := compose.NewGraph[*AgentState, *AgentOutput]()

// 添加节点
graph.AddLLMNode("llm_node", chatModel)
graph.AddToolsNode("tools_node", toolsExecutor)
graph.AddLambdaNode("end_node", finalProcessor)

// 添加边（条件路由）
graph.AddEdge(compose.START, "llm_node")
graph.AddConditionalEdges("llm_node",
    func(ctx context.Context, state *AgentState) (string, error) {
        if state.IsFinished() {
            return "end_node", nil
        }
        return "tools_node", nil // 有工具调用，继续执行
    },
    map[string]bool{"tools_node": true, "end_node": true},
)
graph.AddEdge("tools_node", "llm_node") // 工具执行后回到 LLM
graph.AddEdge("end_node", compose.END)

// 编译并执行
compiledGraph, _ := graph.Compile(ctx)
result, _ := compiledGraph.Invoke(ctx, initialState)
```

### 2.4 ToolsNode（工具执行节点）

```go
// 定义工具
type QueryAssetsTool struct{}

func (t *QueryAssetsTool) Info(ctx context.Context) (*schema.ToolInfo, error) {
    return &schema.ToolInfo{
        Name: "query_assets",
        Desc: "查询项目中的所有资产",
        ParamsOneOf: schema.NewParamsOneOfByParams(map[string]*schema.ParameterInfo{
            "project_id": {Type: schema.String, Required: true, Desc: "项目ID"},
        }),
    }, nil
}

func (t *QueryAssetsTool) InvokableRun(ctx context.Context, argumentsInJSON string) (string, error) {
    var args struct {
        ProjectID string `json:"project_id"`
    }
    json.Unmarshal([]byte(argumentsInJSON), &args)
    // 实际查询逻辑...
    assets, err := queryFromDB(ctx, args.ProjectID)
    result, _ := json.Marshal(assets)
    return string(result), err
}
```

---

## 三、AIcanTARA 中的 Eino 应用

### 3.1 Skill Middleware 架构

项目中设计了一套 **Skill Middleware 架构**，实现工具的模块化注册与跨 Agent 复用：

```go
// Skill 接口：每个领域模块实现此接口
type Skill interface {
    Name() string
    Tools() []tool.BaseTool // 该 Skill 提供的工具列表
    Priority() int          // 工具优先级（冲突时使用）
}

// 核心 Skill（所有 Agent 共享）
type CoreSkill struct {
    projectContextTool *ProjectContextTool  // 获取项目上下文
    assetQueryTool     *AssetQueryTool      // 查询资产信息
}

// 声明式注册（在 Agent 构建时）
func BuildAssetAgent(ctx context.Context) (*ReactAgent, error) {
    skills := []Skill{
        NewCoreSkill(),        // 核心能力（项目上下文、资产查询）
        NewAssetAnalyzeSkill(), // 资产分析专用工具
    }

    allTools := collectTools(skills) // 合并所有工具，按 Priority 去重

    return NewReactAgent(ctx, chatModel, allTools)
}
```

**核心设计价值**：
- **跨 Agent 复用**：`ProjectContextTool` 和 `AssetQueryTool` 在资产识别 Agent、风险管理 Agent、攻击树 Agent 中都需要，只需声明使用 `CoreSkill`
- **降低接入成本**：新增 Agent 只需列出需要的 Skill，不需要重新实现工具
- **模块化维护**：更新某个工具只需修改对应 Skill，不影响其他 Agent

### 3.2 Worker Pool 并发模式

```go
// AIcanTARA 多用户并发分析
type AnalysisWorkerPool struct {
    workers   chan struct{}  // 信号量，控制并发数
    taskQueue chan *AnalysisTask
    wg        sync.WaitGroup
}

func (p *AnalysisWorkerPool) Submit(ctx context.Context, task *AnalysisTask) error {
    select {
    case p.workers <- struct{}{}:  // 获取 worker 槽位
        p.wg.Add(1)
        go func() {
            defer func() {
                <-p.workers // 释放 worker 槽位
                p.wg.Done()
            }()
            // 为每个任务创建独立的 Agent 实例（隔离状态）
            agent := buildAgentForTask(ctx, task)
            result, err := agent.Run(ctx, task.Input)
            task.ResultCh <- &TaskResult{Result: result, Err: err}
        }()
        return nil
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

---

## 四、面试高频问题

**Q1：为什么选 Eino 而不是 LangChain？**

项目是 Go 技术栈，Eino 是 Go 原生框架，能充分利用 goroutine 的并发优势（Worker Pool 并发分析）；LangChain 主要是 Python 生态。另外 Eino 的强类型系统在 Go 中能提供更好的编译期检查，减少运行时错误。

**Q2：Eino 的 Chain 和 Graph 分别用在什么场景？**

Chain 用于**线性、固定顺序**的处理流程，如攻击树生成（固定的检索→生成→写库流程）；Graph 用于**需要条件分支或循环**的场景，如 ReAct Agent（根据 LLM 输出决定是调工具还是返回结果，可能多次循环）。

**Q3：Skill Middleware 架构解决了什么问题？**

解决了多 Agent 系统中工具代码重复的问题。在 AIcanTARA 中，资产查询等核心能力被多个 Agent 共用，如果每个 Agent 单独实现一遍，维护成本高且容易不一致。通过 Skill Middleware，核心工具只实现一次，各 Agent 通过声明依赖的 Skill 来获取工具，降低了新 Agent 的接入成本。

---

## 相关链接

- [[Agent设计范式]] - ReAct/Pipeline 等范式在 Eino 中的实现
- [[Agent能力体系-工具抽象]] - Function Call / Skill / MCP
- [[Agent-Memory设计]] - Memory 在 Eino 中的集成
