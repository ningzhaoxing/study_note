---
tags:
  - AI-Agent
  - 系统设计
  - Memory
  - 面试
aliases:
  - Agent记忆系统
  - 上下文管理
  - Agent Memory
---

# Agent Memory 分层设计

> 面试要点：Memory 是 Agent 实现"跨步骤状态保持"的关键。理解短期/长期记忆的分层设计，以及上下文压缩、重要性评分等工程手段，是 Agent 架构面试的高频考点。

---

## 一、为什么 Agent 需要 Memory？

普通 LLM 是无状态的：每次请求都是独立的，不知道"上一次说了什么"。Agent 需要记忆来支持：

1. **多步骤任务执行**：Step 3 需要知道 Step 1 获取的资产列表
2. **跨会话用户偏好**：知道用户常用的分析模板
3. **避免重复工具调用**：已查询过的数据不重复查询
4. **上下文压缩**：对话轮次多了要避免 Context Window 溢出

---

## 二、Memory 分层架构

```
┌─────────────────────────────────────────────────────────┐
│                    Agent Memory 层次                     │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │              短期记忆（In-Context Memory）        │   │
│  │  • 存储位置：LLM Context Window（消息列表）       │   │
│  │  • 生命周期：单次对话/单次任务执行               │   │
│  │  • 容量限制：受 Context Window 大小约束           │   │
│  │  • 访问速度：最快（直接在 Prompt 中）             │   │
│  └─────────────────────────────────────────────────┘   │
│                         ↕                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │           外部工作记忆（External Working Memory） │   │
│  │  • 存储位置：Redis / 进程内缓存                   │   │
│  │  • 生命周期：会话级或任务级（数小时~数天）         │   │
│  │  • 容量：大（不受 Context 限制）                  │   │
│  │  • 典型内容：工具调用结果、中间计算结果           │   │
│  └─────────────────────────────────────────────────┘   │
│                         ↕                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │              长期记忆（Long-term Memory）         │   │
│  │  • 存储位置：向量数据库（Milvus/Weaviate/pgvector）│  │
│  │  • 生命周期：永久（或按 TTL 管理）                │   │
│  │  • 典型内容：用户偏好、历史项目经验、领域知识     │   │
│  │  • 检索方式：语义相似度搜索                       │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 三、短期记忆：上下文管理

### 3.1 消息列表结构

```go
type Message struct {
    Role    string // "system" | "user" | "assistant" | "tool"
    Content string
    // 可选扩展字段
    ToolCallID string    // 工具调用 ID（tool 类型消息使用）
    Timestamp  time.Time // 时间戳（用于重要性评分）
}

type ConversationMemory struct {
    Messages    []Message
    MaxTokens   int // Context Window 上限
    CurrentSize int // 当前已用 token 数
}
```

### 3.2 上下文压缩策略

当对话轮次增多，Context 接近上限时，需要压缩：

**策略 1：滑动窗口（最简单）**
```go
// 只保留最近 N 轮对话
func (m *ConversationMemory) TrimToWindow(keepLast int) {
    if len(m.Messages) > keepLast {
        // 始终保留 system prompt
        systemMsg := m.Messages[0]
        m.Messages = append([]Message{systemMsg}, m.Messages[len(m.Messages)-keepLast:]...)
    }
}
```

**策略 2：重要性评分保留**
```go
// 计算每条消息的重要性分数
func scoreMessage(msg Message) float64 {
    score := 0.0
    // 1. 工具调用结果：高重要性（包含关键数据）
    if msg.Role == "tool" {
        score += 0.8
    }
    // 2. 最近的消息：高重要性
    timeDelta := time.Since(msg.Timestamp)
    score += math.Max(0, 1.0-timeDelta.Hours()/24) // 24小时内线性衰减
    // 3. 包含关键词：高重要性
    keywords := []string{"错误", "失败", "重要", "注意"}
    for _, kw := range keywords {
        if strings.Contains(msg.Content, kw) {
            score += 0.3
        }
    }
    return score
}
```

**策略 3：摘要压缩（LLM 辅助）**
```go
// 将旧的对话历史用 LLM 压缩成摘要
func (m *ConversationMemory) Summarize(ctx context.Context, llm LLMClient) error {
    oldMessages := m.Messages[:len(m.Messages)/2] // 前一半历史
    summaryPrompt := fmt.Sprintf("请将以下对话历史压缩为200字内的摘要:\n%s", formatMessages(oldMessages))

    summary, _ := llm.Complete(ctx, summaryPrompt)

    // 替换：摘要 + 保留最近一半
    m.Messages = append(
        []Message{{Role: "system", Content: "历史摘要: " + summary}},
        m.Messages[len(m.Messages)/2:]...,
    )
    return nil
}
```

---

## 四、外部工作记忆：Redis 方案

### 4.1 适用场景

- Agent 工具调用结果的临时缓存（避免重复调用）
- Worker Pool 中多个 goroutine 共享的任务状态
- 跨请求的会话状态（如 AIcanTARA 中的分析任务进度）

### 4.2 数据结构设计

```go
// 工具调用结果缓存
type ToolResultCache struct {
    ToolName  string          `json:"tool_name"`
    Args      map[string]any  `json:"args"`
    Result    string          `json:"result"`
    CachedAt  time.Time       `json:"cached_at"`
    TTL       time.Duration   `json:"ttl"`
}

// Redis Key 设计
// agent:session:{sessionID}:tool_cache:{toolName}:{argsHash}
func buildCacheKey(sessionID, toolName string, args map[string]any) string {
    argsJSON, _ := json.Marshal(args)
    argsHash := fmt.Sprintf("%x", md5.Sum(argsJSON))[:8]
    return fmt.Sprintf("agent:session:%s:tool_cache:%s:%s", sessionID, toolName, argsHash)
}
```

---

## 五、长期记忆：向量数据库方案

### 5.1 存储什么？

| 记忆类型 | 内容示例 | 检索方式 |
|---------|---------|---------|
| **用户偏好** | "用户偏好简洁报告风格，不需要详细说明" | 语义相似度 |
| **历史经验** | "项目P001的TARA分析中，ECU类资产的威胁等级普遍偏高" | 关键词 + 语义 |
| **领域知识** | 特定车型的安全规范摘要 | 语义相似度 |
| **失败案例** | "LLM对功能安全和信息安全的边界判断容易混淆" | 语义相似度 |

### 5.2 记忆读写流程

```
写入（记忆形成）：
重要事件发生 → 重要性评分 → 超过阈值 → Embedding → 写入向量DB

读取（记忆检索）：
新任务开始 → 用任务描述做语义检索 → 取 Top-K 相关记忆 → 注入 System Prompt
```

```go
// 记忆写入（带重要性过滤）
func (m *LongTermMemory) Store(ctx context.Context, content string, importance float64) error {
    if importance < m.threshold { // 低重要性不存储
        return nil
    }
    embedding, err := m.embedder.Embed(ctx, content)
    if err != nil {
        return err
    }
    return m.vectorDB.Insert(ctx, MemoryRecord{
        Content:    content,
        Embedding:  embedding,
        Importance: importance,
        CreatedAt:  time.Now(),
    })
}

// 记忆检索
func (m *LongTermMemory) Retrieve(ctx context.Context, query string, topK int) ([]MemoryRecord, error) {
    queryEmbedding, _ := m.embedder.Embed(ctx, query)
    return m.vectorDB.Search(ctx, queryEmbedding, topK)
}
```

---

## 六、AIcanTARA 中的 Memory 设计实践

### 实际问题

AIcanTARA 进行 TARA 分析时，单次任务可能涉及 **50+ 轮工具调用**（资产查询 × 资产数量），直接放在 Context Window 会溢出。

### 解决方案

```
┌─────────────────────────────────────────────────────────────┐
│                    AIcanTARA Memory 架构                     │
│                                                             │
│  Context Window（短期）                                      │
│  ├─ System Prompt（任务指令 + 约束）                         │
│  ├─ 当前轮对话（最近 5 轮）                                  │
│  └─ 关键工具结果摘要（重要性评分 > 0.7 的）                  │
│                                                             │
│  Redis（工作记忆）                                           │
│  ├─ 全量资产列表（避免重复查询）                             │
│  ├─ 已分析资产的中间结果                                     │
│  └─ 任务进度状态（已完成 N/M 个资产）                        │
│                                                             │
│  关键设计：零缓存原则（LLM 输出不缓存，数据查询结果可缓存）   │
└─────────────────────────────────────────────────────────────┘
```

**零缓存原则**：LLM 每次推理的输出**不缓存**（因为可能随模型更新而变化），但工具调用的**原始数据查询结果**可以在 Redis 中缓存（如资产列表、历史攻击树模板）。

---

## 七、面试高频问题

**Q1：Agent 的短期记忆和长期记忆分别如何实现？**

短期记忆直接存储在 LLM 的 Context Window（消息列表）中，受 Token 上限约束，生命周期是单次会话；长期记忆存储在向量数据库中，通过语义检索在需要时注入 Context，生命周期可以很长。

**Q2：Context Window 满了怎么办？**

三种策略：1）滑动窗口，只保留最近 N 轮；2）重要性评分，保留高重要性消息（工具结果、错误信息等）；3）LLM 摘要压缩，将旧历史压缩成摘要。实际工程中通常组合使用：先按重要性保留，再对剩余部分做滑动窗口。

**Q3：为什么不把所有历史都存向量库，全靠检索？**

语义检索有召回率问题，可能遗漏关键细节；工具调用结果通常有结构化依赖（Step 3 需要 Step 1 的确切输出，不是"相似内容"）；而且检索本身有延迟和 Embedding 成本。短期记忆（直接在 Context 中）对于有状态的多步骤任务更可靠。

**Q4：你们项目中的 Memory 设计是什么？**

在 AIcanTARA 中，我们采用了短期 + 工作记忆的两层方案：Context Window 存储当前分析轮次的关键信息，Redis 缓存资产查询结果（避免重复查询），同时坚持"LLM 输出零缓存"原则保证 AI 输出的新鲜度。

---

## 相关链接

- [[Agent设计范式]] - ReAct/Plan-Execute/Multi-Agent
- [[Agent能力体系-工具抽象]] - 工具调用与注册
- [[Eino框架实践]] - Eino 中的 Memory 组件使用
