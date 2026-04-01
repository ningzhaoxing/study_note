---
tags:
  - AI-Agent
  - 工具调用
  - Skill
  - MCP
  - Function-Call
  - 面试
  - 系统设计
aliases:
  - 工具抽象
  - Function Call
  - Skill中间件
  - Tool Use
---

# Agent 能力体系 - 工具抽象

> 核心思路：工具是 Agent 与外部世界交互的桥梁。从 Function Call 到 Skill 到 MCP，是工具抽象层次不断提升的演进过程：**调用 → 封装 → 协议化**。

## 1. 工具调用（Function Call / Tool Use）基础

### 工具的本质

LLM 本身只能处理文本，无法直接查数据库、调 API、写文件。工具调用让 LLM 能够**声明意图**，由外部系统**执行操作**并将结果返回给 LLM。

### 工具定义三要素

```go
// 工具定义：名称 + 描述 + 参数 Schema
type ToolDefinition struct {
    Name        string          `json:"name"`        // 工具唯一标识
    Description string          `json:"description"` // 告诉LLM这个工具"能做什么"（最关键！）
    Parameters  ParameterSchema `json:"parameters"`  // JSON Schema 格式的参数定义
}

// 示例：资产查询工具
var assetQueryTool = ToolDefinition{
    Name:        "query_assets",
    Description: "查询指定项目下的所有资产信息，包括服务、数据库、外部接口等。当用户想了解系统中有哪些组件时使用此工具。",
    Parameters: ParameterSchema{
        Type: "object",
        Properties: map[string]Property{
            "project_id": {
                Type:        "string",
                Description: "项目唯一标识符",
            },
            "asset_type": {
                Type:        "string",
                Enum:        []string{"service", "database", "api", "all"},
                Description: "资产类型过滤，默认为all",
            },
        },
        Required: []string{"project_id"},
    },
}
```

### LLM 工具选择机制

LLM 通过 Description 理解工具的用途，在推理时决定调用哪个工具：

```
System Prompt:
  你可以使用以下工具：
  - query_assets: 查询项目资产...
  - analyze_risk: 分析资产风险...
  - generate_attack_tree: 生成攻击树...

User: "帮我分析P001项目的风险"

LLM决策过程：
  1. 我需要先知道P001有哪些资产 → 调用 query_assets
  2. 拿到资产列表后，对每个资产分析风险 → 调用 analyze_risk
  3. 汇总结果输出
```

> 关键点：**Description 的质量直接决定工具被正确调用的概率**。描述要清晰说明"何时用"而不只是"做什么"。

### 执行-回传流程

```
LLM生成 ToolCall → 系统解析并执行 → 将结果作为 ToolMessage 追加到上下文 → LLM继续推理
```

```go
// 标准工具调用流程
type ToolCallResult struct {
    ToolCallID string `json:"tool_call_id"` // 与LLM输出的call_id对应
    Content    string `json:"content"`      // 工具执行结果（通常是JSON字符串）
}

// 追加到消息历史
messages = append(messages, Message{
    Role:       "tool",
    ToolCallID: call.ID,
    Content:    result,
})
```

---

## 2. Skill：工具的领域化封装

### Skill 是什么

Skill 是对 Tool 的**业务语义封装**。如果说 Tool 是"原子操作"（查一张表），那么 Skill 是"业务能力"（完成一个业务流程）。

```
Tool（原子）：  query_database(sql)
Skill（领域）： get_asset_vulnerabilities(asset_id)
                  → 内部实现：query_database + call_nvd_api + filter_by_severity
```

### Skill 按业务模块组织（AIcanTARA 示例）

```go
// SkillGroup: 资产管理技能集
type AssetSkillGroup struct {
    db     *AssetRepository
    llm    *LLMClient
}

func (g *AssetSkillGroup) Skills() []Skill {
    return []Skill{
        {
            Name:        "list_assets",
            Description: "列出项目中所有资产，支持按类型过滤",
            Handler:     g.ListAssets,
        },
        {
            Name:        "get_asset_detail",
            Description: "获取单个资产的详细信息，包括技术栈、依赖关系、暴露的接口",
            Handler:     g.GetAssetDetail,
        },
        {
            Name:        "identify_asset_from_description",
            Description: "根据自然语言描述识别并匹配已知资产，用于用户模糊表达时",
            Handler:     g.IdentifyAsset,
        },
    }
}

// SkillGroup: 威胁分析技能集
type ThreatSkillGroup struct{}

func (g *ThreatSkillGroup) Skills() []Skill {
    return []Skill{
        {
            Name:        "analyze_threat",
            Description: "对指定资产进行威胁分析，返回STRIDE威胁列表",
            Handler:     g.AnalyzeThreat,
        },
        {
            Name:        "get_attack_tree_template",
            Description: "从Neo4j知识库中检索与资产类型匹配的攻击树模板",
            Handler:     g.GetAttackTreeTemplate,
        },
    }
}
```

### Skill 声明式注册机制

```go
// 技能注册中心
type SkillRegistry struct {
    skills map[string]SkillHandler
    defs   []ToolDefinition
}

func (r *SkillRegistry) Register(group SkillGroup) {
    for _, skill := range group.Skills() {
        r.skills[skill.Name] = skill.Handler
        r.defs = append(r.defs, skill.ToToolDefinition())
    }
}

// Agent 初始化时注册技能
registry := NewSkillRegistry()
registry.Register(&AssetSkillGroup{db: assetRepo})
registry.Register(&ThreatSkillGroup{})
registry.Register(&ReportSkillGroup{})

agent := NewReActAgent(llm, registry)
```

---

## 3. Skill Middleware 架构

### 为什么需要 Skill Middleware

在 AIcanTARA 这样的多 Agent 系统中，多个 Agent 可能需要同样的能力（如"查询资产"）。如果每个 Agent 都独立实现，会造成：
- 代码重复
- 逻辑不一致
- 维护成本高

Skill Middleware 将**横切关注点**（认证、限流、日志、缓存）和**核心业务技能**分离，类似 HTTP 中间件模式。

### 中间件模式实现（Go 风格）

```go
// SkillHandler 函数签名
type SkillHandler func(ctx context.Context, params map[string]any) (string, error)

// SkillMiddleware 包装器
type SkillMiddleware func(next SkillHandler) SkillHandler

// 日志中间件
func LoggingMiddleware(logger *zap.Logger) SkillMiddleware {
    return func(next SkillHandler) SkillHandler {
        return func(ctx context.Context, params map[string]any) (string, error) {
            skillName := ctx.Value("skill_name").(string)
            logger.Info("skill invoked", zap.String("skill", skillName), zap.Any("params", params))

            start := time.Now()
            result, err := next(ctx, params)

            logger.Info("skill completed",
                zap.String("skill", skillName),
                zap.Duration("duration", time.Since(start)),
                zap.Error(err),
            )
            return result, err
        }
    }
}

// 缓存中间件
func CacheMiddleware(cache *redis.Client, ttl time.Duration) SkillMiddleware {
    return func(next SkillHandler) SkillHandler {
        return func(ctx context.Context, params map[string]any) (string, error) {
            cacheKey := buildCacheKey(ctx, params)

            // 尝试命中缓存
            if cached, err := cache.Get(ctx, cacheKey).Result(); err == nil {
                return cached, nil
            }

            result, err := next(ctx, params)
            if err == nil {
                cache.Set(ctx, cacheKey, result, ttl)
            }
            return result, err
        }
    }
}

// 限流中间件
func RateLimitMiddleware(limiter *rate.Limiter) SkillMiddleware {
    return func(next SkillHandler) SkillHandler {
        return func(ctx context.Context, params map[string]any) (string, error) {
            if !limiter.Allow() {
                return "", errors.New("skill rate limit exceeded")
            }
            return next(ctx, params)
        }
    }
}

// 中间件链式组合
func ChainMiddleware(handler SkillHandler, middlewares ...SkillMiddleware) SkillHandler {
    // 逆序包装，使第一个中间件最先执行
    for i := len(middlewares) - 1; i >= 0; i-- {
        handler = middlewares[i](handler)
    }
    return handler
}

// 使用示例：任意 Agent 都可以复用这套装饰好的 Skills
wrappedSkill := ChainMiddleware(
    assetQueryHandler,
    LoggingMiddleware(logger),
    CacheMiddleware(redisClient, 5*time.Minute),
    RateLimitMiddleware(rate.NewLimiter(10, 20)), // 10 req/s, burst 20
)
```

### Skill Middleware 优势

| 优势 | 说明 |
|------|------|
| **核心能力复用** | AssetSkill 注册一次，所有 Agent 共享 |
| **降低接入成本** | 新 Agent 只需声明需要哪些 Skill，中间件自动注入 |
| **关注点分离** | 业务逻辑与日志/缓存/限流解耦 |
| **一致性保证** | 所有 Agent 的 Skill 行为由中间件统一管控 |

---

## 4. MCP（Model Context Protocol）

### MCP 是什么

MCP（Model Context Protocol）是 **Anthropic 于 2024 年提出的开放工具协议标准**，旨在统一 AI 模型与外部工具/资源的交互方式，解决不同 LLM 厂商工具调用接口不兼容的问题。

> 类比：MCP 之于 AI 工具，如同 USB 之于外设——统一接口，即插即用。

### MCP 与 Function Call 的关系

```
Layer 3：MCP Protocol（跨平台协议层）
           ↑ 使用
Layer 2：Skill / Tool 抽象（业务封装层）
           ↑ 基于
Layer 1：Function Call / Tool Use（LLM原生能力）
```

- **Function Call**：各 LLM 厂商的原生工具调用实现（OpenAI/Anthropic/通义等格式各异）
- **Skill**：业务层的工具封装（与具体 LLM 无关）
- **MCP**：更高层的**传输协议标准**，定义 Client-Server 通信方式，Tool 在 MCP Server 中注册，任何支持 MCP 的 Client（不论用哪家 LLM）都能调用

### MCP Server/Client 架构

```
┌─────────────────────────────────────────┐
│           MCP Client（Agent）            │
│  - Claude / GPT / 通义 等任意LLM         │
│  - 通过 MCP 协议发现并调用工具            │
└──────────────────┬──────────────────────┘
                   │ MCP Protocol（JSON-RPC over stdio/SSE）
       ┌───────────┼──────────────┐
       ↓           ↓              ↓
┌──────────┐ ┌──────────┐ ┌──────────────┐
│MCP Server│ │MCP Server│ │ MCP Server   │
│ 资产管理  │ │ 威胁知识库│ │ Neo4j图谱   │
│ (Go实现) │ │ (Python) │ │ (Node.js)   │
└──────────┘ └──────────┘ └──────────────┘
```

### MCP 核心概念

```go
// MCP Server 定义（概念示意）
type MCPServer struct {
    Name    string
    Version string
    Tools   []MCPTool     // 工具列表
    Resources []MCPResource // 资源列表（文件、数据库等）
    Prompts []MCPPrompt   // 预定义 Prompt 模板
}

// MCP Tool 定义（标准化格式）
type MCPTool struct {
    Name        string          `json:"name"`
    Description string          `json:"description"`
    InputSchema json.RawMessage `json:"inputSchema"` // JSON Schema
}

// MCP Client 发现并调用工具
type MCPClient struct {
    transport MCPTransport // stdio / SSE / WebSocket
}

func (c *MCPClient) ListTools(ctx context.Context) ([]MCPTool, error) {
    return c.transport.Request(ctx, "tools/list", nil)
}

func (c *MCPClient) CallTool(ctx context.Context, name string, args map[string]any) (string, error) {
    return c.transport.Request(ctx, "tools/call", map[string]any{
        "name":      name,
        "arguments": args,
    })
}
```

### MCP 适用场景

- **跨平台工具集成**：同一套工具（MCP Server）同时服务 Claude Desktop、Cursor、自研 Agent
- **跨模型复用**：团队从 OpenAI 迁移到 Claude 时，工具层零改造
- **工具市场**：标准化使得工具可以像 npm 包一样分发和复用

---

## 5. 三者综合对比

| 维度 | Function Call | Skill | MCP |
|------|--------------|-------|-----|
| **抽象层次** | 低（LLM原生） | 中（业务封装） | 高（协议标准） |
| **跨模型兼容** | 否（各厂商格式不同） | 部分（需适配） | 是（协议统一） |
| **跨平台复用** | 否 | 否 | 是 |
| **实现复杂度** | 低 | 中 | 高 |
| **性能** | 最高（直接调用） | 高（本地函数） | 中（进程间通信） |
| **适用规模** | 单模型单服务 | 多Agent单系统 | 多系统多模型 |
| **标准化程度** | 弱（各厂差异） | 无标准 | 开放标准 |
| **生态支持** | 广泛 | 自建 | 快速增长 |

### 选型建议

```
单一系统 + 单一LLM → Function Call 直接用，成本最低
多Agent系统 + 单一LLM → Skill + Middleware，业务能力复用
多系统/多LLM/需要生态 → MCP，面向未来
```

在 AIcanTARA 项目中，我们采用的是 **Skill + Middleware 架构**（内部多 Agent 共享技能），同时保留了未来迁移到 MCP 的可能性（Skill 的接口设计兼容 MCP Tool Schema）。

---

## 6. 面试高频问题

**Q1：Function Call 和普通 Prompt 让 LLM 输出 JSON 的区别？**

Function Call 是 LLM 原生支持的能力，模型在训练时专门对工具调用进行了微调，输出更稳定可靠。普通 Prompt 让 LLM 输出 JSON 只是文本生成，容易格式错误、幻觉工具名等。另外 Function Call 有明确的 `tool_calls` 字段标识，系统能准确区分"模型在推理"还是"模型在调用工具"。

**Q2：工具 Description 怎么写才好？**

1. 说明**何时用**（触发条件），而不只是功能描述
2. 说明**输出的数据格式**，帮助 LLM 理解后续如何利用结果
3. 说明**不适用场景**（负向说明），减少误调用
4. 避免两个工具 Description 太相似，会导致 LLM 调用混淆

**Q3：你们的 Skill Middleware 和 HTTP 中间件有什么区别？**

本质上是同一种模式（装饰器/责任链）。区别在于：HTTP 中间件处理的是 HTTP 请求/响应，Skill Middleware 处理的是工具调用/返回。我们利用 Go 的函数式特性（`func(next) SkillHandler`），实现了和 `net/http` 中间件完全一致的链式组合风格，团队上手成本极低。

**Q4：MCP 和 OpenAI 的 Function Call 格式有什么不同？**

最主要的区别是**传输层**：Function Call 是在同一个 HTTP 请求内完成的（LLM 返回 tool_call，客户端执行后再次请求 LLM）；MCP 是基于独立进程的 Client-Server 架构，工具运行在独立的 MCP Server 进程中，通过 stdio 或 SSE 通信，支持工具的**独立部署和跨进程调用**。

**Q5：如何处理工具调用失败的情况？**

1. **错误信息回传**：将错误作为 Observation 返回给 LLM，让 LLM 决定是重试还是换方案
2. **重试机制**：在 Middleware 层实现自动重试（有限次数 + 指数退避）
3. **降级策略**：工具不可用时，提示 LLM 基于已有信息给出近似答案
4. **Timeout 控制**：每个工具调用设置 Context Deadline，防止阻塞整个 Agent

---

## 相关链接

- [[Agent设计范式]] - ReAct、Pipeline、Multi-Agent等范式对比
- [[Agent-Memory设计]] - 记忆分层与上下文管理
- [[Eino框架实践]] - CloudWeGo/Eino中的工具注册实践
- [[设计模式/装饰器模式]] - Middleware 的设计模式基础
