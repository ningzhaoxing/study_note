---
tags:
  - AI/Agent
  - Go
  - eino
  - multi-agent
source: DeepWiki / cloudwego/eino
date: 2026-03-08
---

# cloudwego/eino：多智能体层级架构

> 围绕 `cloudwego/eino` 的 Host Multi-Agent 实现，探讨如何构建"专家下面还有子专家"的层级化多智能体架构。

---

## 核心概念：Host 与 Specialist 的职责分工

在 eino 的 `MultiAgentConfig` 中，**Host** 和 **Specialist** 是两个完全独立的角色：

```go
type MultiAgentConfig struct {
    Host        Host           // 路由决策者
    Specialists []*Specialist  // 任务执行者
}
```

| 角色             | 职责                        | 实现方式                                     |
| -------------- | ------------------------- | ---------------------------------------- |
| **Host**       | 分析用户查询，决定交接给哪个 Specialist | 只能是 `model.ToolCallingChatModel`         |
| **Specialist** | 执行特定领域任务，返回结果             | 可以是 `ChatModel`、`Invokable`、`Streamable` |

**为什么 Host 不能同时作为 Specialist：**
1. **架构分离**：Host 职责是路由，Specialist 职责是执行，混用会导致职责模糊
2. **工具调用机制**：Host 通过 Tool Call 触发 Specialist，若 Host 也是 Specialist 会产生循环依赖
3. **状态管理**：两者在计算图中有不同的状态处理逻辑

---

## 问题场景：需要"专家下面有子专家"的层级结构

```
顶层 Host
├── Specialist A（同时也是子 Host）
│   ├── Sub-Specialist A1
│   └── Sub-Specialist A2
└── Specialist B（同时也是子 Host）
    ├── Sub-Specialist B1
    └── Sub-Specialist B2
```

由于 Host 不能直接作为 Specialist，需要借助以下三种方案来实现。

---

## 三种实现方案

### 方案一：Supervisor 模式（推荐）

**适用场景**：需要清晰的组织架构、严格的通信控制

**工作原理**：
- Supervisor 是**中央协调者**，管理多个 SubAgent
- 每个 SubAgent 被包装后**只能与父级 Supervisor 通信**，子代理之间不能直接对话
- 天然支持多层嵌套

```go
// 1. 创建内层 Supervisor（作为子专家组）
innerSupervisorAgent, err := supervisor.New(ctx, &supervisor.Config{
    Supervisor: innerSupervisorChatAgent,
    SubAgents:  []adk.Agent{workerAgent},
})

// 2. 将内层 Supervisor 包装成具名 Agent，使其可作为外层的 SubAgent
innerSupervisorWrapped := &namedAgent{
    ResumableAgent: innerSupervisorAgent,
    name:           "payment_department",
    description:    "负责所有支付相关操作的部门",
}

// 3. 创建外层 Supervisor，将包装后的内层 Supervisor 作为 SubAgent
outerSupervisorAgent, err := supervisor.New(ctx, &supervisor.Config{
    Supervisor: outerSupervisorChatAgent,
    SubAgents:  []adk.Agent{innerSupervisorWrapped},
})
```

**Supervisor 内部实现机制**：
```go
func New(ctx context.Context, conf *Config) (adk.ResumableAgent, error) {
    subAgents := make([]adk.Agent, 0, len(conf.SubAgents))
    supervisorName := conf.Supervisor.Name(ctx)
    for _, subAgent := range conf.SubAgents {
        // 关键：强制每个子代理只能转移回给父级 Supervisor
        subAgents = append(subAgents, adk.AgentWithDeterministicTransferTo(ctx, &adk.DeterministicTransferConfig{
            Agent:        subAgent,
            ToAgentNames: []string{supervisorName},
        }))
    }
    return adk.SetSubAgents(ctx, conf.Supervisor, subAgents)
}
```

**通信流程**：
```
用户请求
  → 外层 Supervisor 决策
  → 转移给 payment_department（内层 Supervisor 包装体）
  → 内层 Supervisor 决策
  → 转移给具体 Worker
  → Worker 完成后回报给内层 Supervisor
  → 内层 Supervisor 汇总后回报给外层 Supervisor
  → 最终答复用户
```

---

### 方案二：AgentTool 包装（灵活集成）

**适用场景**：需要将现有 Agent 系统集成进另一个 Agent，结构灵活

**工作原理**：
- 将一个完整的 Agent 系统（包括 Host + Specialists）**包装成一个 Tool**
- 外层 Agent 像调用普通工具一样调用这个"Agent 工具"
- 内部 Agent 的 Exit、Transfer 等动作**不会泄漏影响**外部 Agent（作用域隔离）

```go
// 1. 创建子 Host 系统（本身就是一个完整的 Multi-Agent）
subHostMA, err := NewMultiAgent(ctx, &MultiAgentConfig{
    Host:        Host{ToolCallingModel: subHostModel},
    Specialists: []*Specialist{subSpecialist1, subSpecialist2},
})

// 2. 将整个子 Host 系统包装成一个 Tool
subHostTool := adk.NewAgentTool(ctx, subHostMA)

// 3. 在父 Host 中，将这个 Tool 作为一个 Specialist 挂载
parentHostMA, err := NewMultiAgent(ctx, &MultiAgentConfig{
    Host: Host{ToolCallingModel: parentHostModel},
    Specialists: []*Specialist{
        {
            Invokable: subHostTool,
            AgentMeta: AgentMeta{
                Name:        "sub_host_system",
                IntendedUse: "处理特定领域的子任务",
            },
        },
    },
})
```

**注意**：`EmitInternalEvents=true` 时可透传内部事件到外部。

---

### 方案三：DeepAgent SubAgents（任务分发）

**适用场景**：需要智能任务分解与自动分发，希望框架自动协调

**工作原理**：
- DeepAgent 内置 **task 工具**，用于向 SubAgent 分发任务
- 自动生成每个 SubAgent 的工具描述，帮助模型选择合适的子代理
- SubAgent 可以继承父代理的会话值（Session 共享）

```go
deepAgent, err := deep.New(ctx, &deep.Config{
    ChatModel: chatModel,
    SubAgents: []adk.Agent{subAgent1, subAgent2},
    // SubAgents 可以是其他任意 Agent，包括 Supervisor 或 Host 系统
})
```

---

## 三种方案横向对比

| 特性        | Supervisor  | AgentTool    | DeepAgent   |
| --------- | ----------- | ------------ | ----------- |
| **通信控制**  | 严格（只能与父级通信） | 隔离（内部不外泄）    | 宽松（任务分发）    |
| **嵌套深度**  | 支持多层嵌套      | 支持           | 支持          |
| **灵活性**   | 中等          | 高            | 中等          |
| **配置复杂度** | 低（结构预定义）    | 中（手动包装）      | 低（自动协调）     |
| **适用场景**  | 组织架构 / 部门管理 | 跨系统集成 / 功能复用 | 任务分解 / 并行处理 |
| **流式支持**  | ✅           | ✅            | ✅           |
| **中断恢复**  | ✅           | ✅            | ✅           |

---

## 选型建议

- **想要"专家-子专家"的公司组织结构** → **Supervisor 模式**（通信路径最清晰）
- **想把现有 Agent 系统复用进新系统** → **AgentTool 包装**（最灵活，最少侵入）
- **想要框架自动帮你分解任务、选子代理** → **DeepAgent SubAgents**（最省心）

> 💡 对于"专家下面有子专家"这种典型层级场景，**Supervisor 是首选**。测试用例中已验证了 3 层嵌套结构：`headquarters → company_coordinator → payment_department → payment_supervisor → payment_worker`。
