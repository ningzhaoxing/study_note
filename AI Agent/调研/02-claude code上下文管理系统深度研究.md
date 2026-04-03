# Claude Code 上下文管理系统深度研究

> 研究对象：Claude Code CLI（Anthropic 官方 Agent 产品）
> 研究视角：Agent 产品设计 / 长对话上下文管理的系统工程
> 研究日期：2026-04-01

---

## 引言：为什么上下文管理是 Agent 产品的生死线

对于任何基于 LLM 的 Agent 产品，上下文窗口（Context Window）既是能力来源，也是最硬的约束。Claude Code 面对的挑战极为典型：

- 用户可能在一个会话中连续工作数小时，产生数百轮对话
- 每轮工具调用（搜索、读取文件、执行命令）都会产生大量输出
- 一个代码文件可能就有上千行，几次读取就能占满大部分 context
- 模型的上下文窗口有限（200K tokens，约相当于 50 万字），但用户的工作没有上限

**如果不做任何管理，一个深度编程会话大约在 20-30 轮对话后就会撞到上下文上限，Agent 直接无法工作。**

Claude Code 为此设计了一套**多层级、纵深防御**的上下文管理体系。本报告将深入剖析这套体系的每个层次、每个机制，以及背后的设计考量。

---

## 第一部分：防线全景——六层纵深防御体系

Claude Code 的上下文管理不是单一机制，而是一个**六层纵深防御体系**，每一层解决不同粒度的问题：

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  第 1 层：源头控制（Source Control）                                   │
│  ─ 工具输出限制、路径相对化、行长截断                                   │
│  ─ 目标：从产生源头就控制信息量                                        │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  第 2 层：大结果外置（Tool Result Persistence）                        │
│  ─ 超大工具结果写入磁盘，只保留 2KB 预览                               │
│  ─ 目标：防止单个工具输出炸掉 context                                  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  第 3 层：读取去重（Read Deduplication）                                │
│  ─ 同一文件重复读取时返回桩消息                                        │
│  ─ 目标：消除多轮对话中的冗余信息                                      │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  第 4 层：微压缩（Microcompaction）                                    │
│  ─ 删除旧的工具结果内容，保留消息结构                                   │
│  ─ 目标：在不丢失对话结构的前提下释放空间                               │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  第 5 层：全量压缩（Full Compaction）                                   │
│  ─ 用 AI 总结整个对话历史，替换原始消息                                 │
│  ─ 目标：在 context 接近上限时进行"大瘦身"                              │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  第 6 层：应急兜底（Reactive Compaction）                               │
│  ─ 当 API 返回 prompt_too_long 错误时紧急截断                          │
│  ─ 目标：最后防线，确保系统不会完全崩溃                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

接下来逐层深入。

---

## 第二部分：第 1 层——源头控制

### 2.1 设计哲学

> **最好的上下文管理是不需要管理——从信息产生的源头就控制好量。**

Claude Code 在每个工具的输出端就设置了多重限制，确保信息进入 context 之前已经被"预处理"过。

### 2.2 工具输出限制一览

| 工具 | 限制机制 | 默认值 | 目的 |
|------|---------|--------|------|
| **Glob** | 最大返回文件数 | 100 个文件 | 防止 `**/*` 之类的通配符返回数万个文件 |
| **Grep** | 默认输出行数上限 | 250 行 | 防止宽泛的正则搜索返回海量匹配 |
| **Grep** | 单行最大长度 | 500 字符 | 过滤掉 minified JS、base64 编码等噪音 |
| **Grep** | 默认输出模式 | `files_with_matches`（仅文件名） | 最轻量的输出，只给文件路径 |
| **Read** | 默认最大行数 | 2,000 行 | 绝大多数源文件都在这个范围内 |
| **Read** | 最大文件体积 | 256 KB | 阻止读取超大文件 |
| **Read** | 最大输出 token | 25,000 tokens | 硬性 token 上限 |
| **Read** | PDF 最大页数 | 20 页/次 | 防止大 PDF 占满 context |

### 2.3 路径相对化

所有工具返回的文件路径都被转换为**相对于当前工作目录的相对路径**：

```
原始路径：/Users/liyuejia/projects/my-app/src/components/Button.tsx
相对化后：src/components/Button.tsx
```

源码实现（`GlobTool.ts:165`）：
```typescript
// Relativize paths under cwd to save tokens (same as GrepTool)
const filenames = files.map(toRelativePath)
```

**效果**：假设一个项目路径前缀平均 40 字符，每次搜索返回 50 个文件，每次节省约 2,000 字符（~500 tokens）。在一个长会话中累计数十次搜索，节省量相当可观。

### 2.4 VCS 目录自动排除

Grep 工具自动排除所有版本控制系统目录：

```typescript
const VCS_DIRECTORIES_TO_EXCLUDE = ['.git', '.svn', '.hg', '.bzr', '.jj', '.sl']
```

**为什么？** `.git` 目录通常包含大量对象文件，搜索它们既无意义又浪费大量 token。

### 2.5 源码注释揭示的设计考量

Grep 工具的 `head_limit` 默认值设置为 250，源码注释如此解释：

```typescript
// Default cap on grep results when head_limit is unspecified.
// Unbounded content-mode greps can fill up to the 20KB persist threshold
// (~6-24K tokens/grep-heavy session).
// 250 is generous enough for exploratory searches while preventing context bloat.
// Pass head_limit=0 explicitly for unlimited.
const DEFAULT_HEAD_LIMIT = 250
```

这段注释揭示了一个关键数据：**一次不加限制的 Grep 搜索就可能产生 6-24K tokens 的输出**，而整个 context 只有 ~180K 有效空间。也就是说，不到 10 次 Grep 就可能占满整个 context。

---

## 第三部分：第 2 层——大结果外置（Tool Result Persistence）

### 3.1 核心机制

当一个工具的输出超过阈值时，系统不是截断它，而是**把完整结果写入磁盘文件，只在 context 中保留一个 2KB 的预览**。

**实现文件**：`src/utils/toolResultStorage.ts`

### 3.2 触发条件

两级预算控制：

**第一级：单工具预算**

每个工具声明自己的 `maxResultSizeChars`（最大结果字符数），超过则触发外置：

| 工具 | maxResultSizeChars | 说明 |
|------|-------------------|------|
| Glob | 100,000 | 文件列表通常不会太大 |
| Grep | 20,000 | 搜索结果较容易膨胀 |
| Bash | 50,000（默认） | Shell 命令输出不可控 |
| Read | **Infinity** | 特殊：永不外置（见下方解释） |

Read 工具的 `maxResultSizeChars` 设为 `Infinity`，源码注释如此解释：

```typescript
// Output is bounded by maxTokens (validateContentTokens). Persisting to a
// file the model reads back with Read is circular — never persist.
maxResultSizeChars: Infinity,
```

**逻辑很严密**：如果把 Read 的结果外置到文件，模型下一步会再用 Read 去读那个文件——形成死循环。因此 Read 工具自身通过 `maxTokens`（25,000 tokens）来控制大小，而不依赖外置机制。

**第二级：单消息聚合预算**

即使每个工具单独不超标，一轮中**并行调用多个工具**的聚合输出也可能超标：

```typescript
MAX_TOOL_RESULTS_PER_MESSAGE_CHARS = 200,000  // 单轮聚合上限 200K 字符
```

当一轮中所有工具输出的总字符数超过 200K 时，系统会从最大的结果开始外置，直到降到预算以内。

### 3.3 外置后的 context 内容

外置后，模型看到的是这样的预览：

```xml
<persisted-output>
Output too large (156.3KB). Full output saved to: /path/to/tool-results/abc123.txt

Preview (first 2.0KB):
[前 2000 字节的内容...]
...
</persisted-output>
```

**关键设计**：
- 模型知道完整结果在哪里（文件路径），如果需要可以用 Read 工具去读
- 预览给出了足够的上下文让模型判断是否需要读取完整内容
- 2KB 预览大约等于 500 tokens，相比原始可能数万 tokens 的输出，压缩率极高

### 3.4 Prompt Cache 稳定性保障

这里有一个极其精妙的设计——**替换决策的不可逆性**：

```typescript
type ContentReplacementState = {
  seenIds: Set<string>          // 已见过的 tool_use_id
  replacements: Map<string, string>  // 已外置的结果的预览内容
}
```

核心规则：
1. **一旦某个工具结果被外置（replaced），它的预览内容会被缓存，后续每轮都重新应用相同的预览**——确保 prompt cache 不会因为替换内容变化而失效
2. **一旦某个工具结果被"看过但未外置"（frozen），它永远不会再被外置**——因为它已经进入了 prompt cache，改变它会导致 cache bust

源码注释直接说明了原因（`toolResultStorage.ts:376-388`）：

```typescript
// State must be stable to preserve prompt cache:
//   - seenIds: results that have passed through the budget check (replaced
//     or not). Once seen, a result's fate is frozen for the conversation.
//   - replacements: subset of seenIds that were persisted to disk and
//     replaced with previews, mapped to the exact preview string shown to
//     the model. Re-application is a Map lookup — no file I/O, guaranteed
//     byte-identical, cannot fail.
```

**产品设计启示**：在 Agent 产品中，任何对 context 内容的修改都必须考虑对 prompt cache 的影响。缓存友好的设计可以大幅降低 API 成本。

---

## 第四部分：第 3 层——读取去重（Read Deduplication）

### 4.1 问题背景

在一个长编程会话中，Agent 会反复读取同一个文件：
- 第一次读取来了解代码
- 修改代码后再次读取来验证
- 回答用户问题时再次读取

每次完整读取一个 500 行的源文件约消耗 3,000-5,000 tokens。

### 4.2 解决方案

Read 工具通过 `readFileState` 缓存跟踪每个已读文件的状态：

```typescript
// 已读文件状态
readFileState: Map<filePath, {
  content: string,       // 文件内容
  timestamp: number,     // 上次读取时的 mtime
  offset: number,        // 读取起始行
  limit: number,         // 读取行数
  isPartialView?: boolean // 是否是截断视图
}>
```

**当检测到同一文件被再次读取时**（`FileReadTool.ts:537-573`）：

1. 检查 `readFileState` 中是否有该文件的记录
2. 检查读取范围是否匹配（offset + limit）
3. 通过 `stat()` 获取文件当前 mtime，与缓存的 timestamp 比较
4. 如果文件未修改 → 返回桩消息：

```
File unchanged since last read. The content from the earlier Read tool_result
in this conversation is still current — refer to that instead of re-reading.
```

### 4.3 实际效果

源码注释给出了真实的线上数据（`FileReadTool.ts:528-531`）：

```typescript
// BQ proxy shows ~18% of Read calls are same-file collisions
// (up to 2.64% of fleet cache_creation).
```

**翻译**：
- **18% 的文件读取是重复的**——几乎每 5 次读取就有 1 次是不必要的
- 这些重复读取消耗了**系统总 cache_creation token 的 2.64%**
- 去重机制上线后，这些成本直接被消除

### 4.4 安全边界

去重机制有严格的条件限制：
- 只对 Read 工具自己之前读过的文件做去重（通过 `offset !== undefined` 判断）
- Edit/Write 工具写入文件后也会更新 `readFileState`，但标记为 `offset=undefined`，因此不会触发去重——**确保编辑后的文件一定会被重新读取**

---

## 第五部分：第 4 层——微压缩（Microcompaction）

### 5.1 设计定位

微压缩是一种**轻量级的上下文清理**，它的核心思想是：

> **旧的工具输出内容已经不再需要了，但消息的结构（谁说了什么）仍然有价值。**

因此，微压缩只删除工具结果的**内容**，保留消息的**结构**。

### 5.2 两种实现路径

Claude Code 有两种微压缩机制，分别适用于不同场景：

#### 路径 A：缓存编辑微压缩（Cached Microcompact）

**实现文件**：`src/services/compact/cachedMicrocompact.ts`

**核心思想**：利用 API 的 `cache_edits` 能力，在不失效 prompt cache 的前提下删除旧工具结果。

```
API 请求中附带 cache_edits 指令：
"请删除 tool_use_id=abc123 的结果内容"
→ 服务端从缓存的 prompt 中移除该内容
→ 不需要重新上传整个 prompt
→ Prompt cache 依然有效
```

**触发条件**：基于工具结果的数量阈值（通过 GrowthBook 配置），当累积的工具结果超过阈值时触发，保留最近的 N 个。

**只作用于"可压缩工具"**（`microCompact.ts:41-50`）：

```typescript
const COMPACTABLE_TOOLS = new Set([
  FILE_READ_TOOL_NAME,    // Read
  ...SHELL_TOOL_NAMES,    // Bash, PowerShell
  GREP_TOOL_NAME,         // Grep
  GLOB_TOOL_NAME,         // Glob
  WEB_SEARCH_TOOL_NAME,   // WebSearch
  WEB_FETCH_TOOL_NAME,    // WebFetch
  FILE_EDIT_TOOL_NAME,    // Edit
  FILE_WRITE_TOOL_NAME,   // Write
])
```

**注意**：Agent 工具的结果、用户消息、Task 工具的结果等**不在**可压缩列表中——这些信息被认为是结构性的、不可丢弃的。

#### 路径 B：基于时间的微压缩（Time-Based Microcompact）

**触发条件**：当距离上一次 assistant 消息超过一定时间（可配置的分钟数）时触发。

**设计逻辑**：如果用户长时间没有与 Agent 交互（比如去吃了个午饭回来），服务端的 prompt cache 大概率已经过期了（通常 5 分钟 TTL）。既然 cache 已经冷了，不如趁机清理旧的工具结果。

**实现细节**（`microCompact.ts:401-530`）：

```typescript
// 评估是否触发基于时间的微压缩
function evaluateTimeBasedTrigger(messages, querySource) {
  // 计算距离上一条 assistant 消息的时间间隔
  const gapMinutes = (Date.now() - lastAssistant.timestamp) / 60_000
  // 如果间隔超过阈值，触发微压缩
  if (gapMinutes >= config.gapThresholdMinutes) {
    return { gapMinutes, config }
  }
  return null
}
```

清理时保留最近 N 个工具结果（至少保留 1 个），其余替换为占位符：

```typescript
const TOOL_RESULT_CLEARED_MESSAGE = '[Old tool result content cleared]'
```

### 5.3 产品设计洞察

微压缩体现了一个精妙的**渐进式降级**策略：

1. **信息不是非黑即白的**：旧的 Grep 搜索结果的具体匹配行可能不重要了，但"搜索了什么"这个事实本身仍然重要
2. **cache 友好的清理**：缓存编辑路径通过 API 的 `cache_edits` 能力实现了"不破坏缓存的清理"，这在成本优化上是巨大的
3. **时间窗口利用**：基于时间的触发利用了 cache 自然过期的窗口，避免了"清理本身导致 cache 失效"的矛盾

---

## 第六部分：第 5 层——全量压缩（Full Compaction）

### 6.1 触发时机

全量压缩是"大招"——当 context 用量接近上限时触发。

**关键阈值计算**（`autoCompact.ts:33-49`）：

```typescript
// 有效上下文窗口 = 模型上下文窗口 - 压缩输出预留空间
effectiveContextWindow = contextWindowForModel - 20,000
// 对于 200K 模型：200,000 - 20,000 = 180,000

// 自动压缩触发阈值 = 有效窗口 - 缓冲区
autoCompactThreshold = effectiveContextWindow - 13,000
// 对于 200K 模型：180,000 - 13,000 = 167,000
```

**阈值矩阵**：

| 状态 | 阈值（200K 模型） | 占比 | 行为 |
|------|-------------------|------|------|
| 正常 | < 147,000 | < 82% | 正常工作 |
| 警告 | ≥ 147,000 | ≥ 82% | UI 显示警告 |
| 自动压缩 | ≥ 167,000 | ≥ 93% | 触发全量压缩 |
| 阻塞 | ≥ 177,000 | ≥ 98% | 必须手动 /compact |

### 6.2 压缩算法：AI 驱动的对话摘要

全量压缩的核心是**用 AI 自己总结自己的对话历史**。

**实现文件**：`src/services/compact/compact.ts` + `src/services/compact/prompt.ts`

#### 第一步：预处理

在发送给 AI 总结之前，先做预处理：
- 将所有图片替换为 `[image]` 标记
- 将所有文档替换为 `[document]` 标记
- 移除被重新注入的附件（skill_discovery, skill_listing）
- 执行 PRE_COMPACT 钩子

**为什么要剥离图片？** 源码注释说明：图片的 base64 编码体积巨大（每张约 2KB+ tokens），如果不剥离，压缩请求本身就可能超过 context 上限。

#### 第二步：9 段式结构化总结

AI 被要求按照严格的 9 段结构生成摘要（`prompt.ts:61-143`）：

```
1. Primary Request and Intent  — 用户的所有明确请求和意图
2. Key Technical Concepts      — 讨论到的关键技术概念
3. Files and Code Sections     — 检查/修改/创建的具体文件和代码片段
4. Errors and Fixes            — 遇到的错误和修复方法
5. Problem Solving             — 已解决和正在排查的问题
6. All User Messages           — 所有非工具结果的用户消息
7. Pending Tasks               — 待完成的任务
8. Current Work                — 压缩前正在进行的具体工作
9. Optional Next Step          — 下一步计划（需引用原始对话原文）
```

**为什么要这种结构？** 每一段都对应了 Agent 在压缩后继续工作时需要的一种信息：

- 段 1-2：理解大方向
- 段 3：知道操作过哪些文件
- 段 4：不重蹈覆辙
- 段 5-6：理解用户的反馈
- 段 7-8：知道从哪里继续
- 段 9：直接恢复工作

#### 第三步：Analysis-Summary 双阶段生成

总结 prompt 要求 AI 先进行分析（`<analysis>` 块），再输出摘要（`<summary>` 块）：

```
<analysis>
[AI 的思考过程，确保覆盖了所有要点]
</analysis>

<summary>
1. Primary Request and Intent: ...
2. Key Technical Concepts: ...
...
</summary>
```

**但 `<analysis>` 块在最终存储前会被剥离**（`prompt.ts:311-319`）：

```typescript
function formatCompactSummary(summary: string): string {
  // Strip analysis section — it's a drafting scratchpad that improves summary
  // quality but has no informational value once the summary is written.
  formattedSummary = formattedSummary.replace(/<analysis>[\s\S]*?<\/analysis>/, '')
  // ...
}
```

**设计逻辑**：Analysis 阶段提高了摘要的质量（让 AI "思考"后再输出），但分析过程本身不需要保留在 context 中。这是一种"花费生成 token 来节省 context token"的策略。

#### 第四步：工具使用的完全禁止

压缩 prompt 中有极其强硬的工具使用禁止指令（`prompt.ts:19-26`）：

```
CRITICAL: Respond with TEXT ONLY. Do NOT call any tools.

- Do NOT use Read, Bash, Grep, Glob, Edit, Write, or ANY other tool.
- You already have all the context you need in the conversation above.
- Tool calls will be REJECTED and will waste your only turn — you will fail the task.
- Your entire response must be plain text: an <analysis> block followed by a <summary> block.
```

并且在末尾再次提醒（`prompt.ts:269-272`）：

```
REMINDER: Do NOT call any tools. Respond with plain text only —
an <analysis> block followed by a <summary> block.
Tool calls will be rejected and you will fail the task.
```

**为什么如此强调？** 源码注释揭示了原因：

```typescript
// Aggressive no-tools preamble. The cache-sharing fork path inherits the
// parent's full tool set (required for cache-key match), and on Sonnet 4.6+
// adaptive-thinking models the model sometimes attempts a tool call despite
// the weaker trailer instruction. With maxTurns: 1, a denied tool call means
// no text output → falls through to the streaming fallback (2.79% on 4.6 vs
// 0.01% on 4.5).
```

即：压缩进程继承了主对话的完整工具集（为了 cache 共享），某些模型版本会"忍不住"调用工具，而这在压缩模式下是致命的——一次无效的工具调用就浪费了唯一的输出机会。

### 6.3 压缩后的上下文重建

压缩不仅仅是"删旧换新"，还需要**重建关键上下文**。压缩后会注入以下信息：

| 恢复内容 | 预算限制 | 选择策略 |
|----------|---------|---------|
| 最近读取的文件 | 最多 5 个文件，总计 50K tokens，每个文件 5K tokens | 按最近访问时间排序 |
| 当前计划文件 | 如果处于 plan mode | 完整注入 |
| 已调用的技能 | 每个技能 5K tokens，总计 25K tokens | 按最近调用排序 |
| 异步代理状态 | 运行中/已完成的后台任务 | 全部注入 |
| 工具/MCP 变更 | 自上次以来新增的工具和 MCP 指令 | 增量注入 |
| SESSION_START 钩子 | CLAUDE.md、自定义上下文等 | 重新执行 |

### 6.4 压缩触发后的恢复消息

压缩完成后，模型看到的第一条消息是：

```
This session is being continued from a previous conversation that ran out of context.
The summary below covers the earlier portion of the conversation.

Summary:
1. Primary Request and Intent: [...]
2. Key Technical Concepts: [...]
...

Continue the conversation from where it left off without asking the user any further questions.
Resume directly — do not acknowledge the summary, do not recap what was happening,
do not preface with "I'll continue" or similar.
Pick up the last task as if the break never happened.
```

**关键设计**：明确指示模型"不要废话，直接接着干"。这避免了每次压缩后模型说一大段"好的，根据之前的总结，我现在继续..."的冗余输出。

### 6.5 Prompt-Too-Long 重试机制

如果压缩请求本身也超过了 context 上限（对话实在太长），系统有一个**渐进式丢弃重试机制**：

```
1. 按 API 轮次分组消息（groupMessagesByApiRound）
2. 从最旧的组开始丢弃，直到 token 差额被覆盖
3. 在丢弃的位置插入标记：[earlier conversation truncated for compaction retry]
4. 最多重试 3 次
5. 如果 token 差额无法解析，兜底丢弃 20% 的消息组
```

### 6.6 熔断机制

如果压缩连续失败，系统有**熔断保护**（`autoCompact.ts:67-70`）：

```typescript
// Stop trying autocompact after this many consecutive failures.
// BQ 2026-03-10: 1,279 sessions had 50+ consecutive failures (up to 3,272)
// in a single session, wasting ~250K API calls/day globally.
const MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES = 3
```

**背景数据**：在部署熔断之前，有 1,279 个会话出现了连续 50 次以上的压缩失败（最多的一个会话失败了 3,272 次），**每天浪费约 25 万次 API 调用**。3 次熔断阈值直接消灭了这个问题。

---

## 第七部分：第 6 层——应急兜底（Reactive Compaction）

### 7.1 触发场景

当所有主动措施都失效，API 返回 `prompt_too_long`（HTTP 413）错误时，应急兜底启动。

### 7.2 处理策略

应急兜底使用与全量压缩相同的 `truncateHeadForPTLRetry()` 函数：

1. 将消息按 API 轮次分组
2. 从最旧的组开始丢弃
3. 重试 API 调用
4. 最多重试 3 次

这是一种**"宁可丢失信息也不能让系统挂掉"**的兜底策略。

---

## 第八部分：Session Memory Compaction（实验性）

### 8.1 设计思路

传统的全量压缩需要调用 AI 来生成摘要，这本身就消耗时间和 token。Session Memory Compaction 是一种替代方案：

> **如果系统已经在后台持续提取了"会话记忆"，那压缩时直接用这个记忆代替 AI 生成的摘要。**

### 8.2 实现细节

**实现文件**：`src/services/compact/sessionMemoryCompact.ts`

配置参数：

```typescript
DEFAULT_SM_COMPACT_CONFIG = {
  minTokens: 10_000,          // 至少保留最近 10K tokens 的消息
  minTextBlockMessages: 5,     // 至少保留最近 5 条文本消息
  maxTokens: 40_000            // 保留的最近消息上限 40K tokens
}
```

流程：
1. 检查 Session Memory 是否可用
2. 用 Session Memory 作为摘要（替代 AI 生成）
3. 保留最近的消息（在 minTokens 和 maxTokens 之间）
4. 确保不会打断 tool_use/tool_result 配对

### 8.3 优势

- **零额外 API 调用**：不需要像全量压缩那样调用 AI 生成摘要
- **更快**：直接使用已有的会话记忆
- **代价**：摘要质量可能不如专门生成的（因为 Session Memory 是通用提取，不是针对压缩优化的）

---

## 第九部分：Token 计量系统

### 9.1 核心计量函数

整个上下文管理体系的基础是**准确的 token 计量**。

**核心函数**：`tokenCountWithEstimation(messages)` — `src/utils/tokens.ts`

计量逻辑：

```
总 token 数 = 上一次 API 响应的 usage 数据
             + 此后新增消息的粗略估算

其中 API usage = input_tokens
               + cache_creation_input_tokens
               + cache_read_input_tokens
               + output_tokens
```

### 9.2 粗略估算方法

对于还没有发送给 API 的新增消息，使用粗略估算（`src/services/tokenEstimation.ts`）：

```typescript
roughTokenCountEstimation(text, bytesPerToken = 4)
// 默认 4 字节/token

roughTokenCountEstimationForFileType(text, ext)
// JSON 文件用 2 字节/token（因为 JSON 有很多重复结构和分隔符）
```

### 9.3 并行工具调用的特殊处理

当模型并行调用多个工具时，streaming 会生成多条 assistant 消息（相同 `message.id`），中间穿插着 tool_result 消息。`tokenCountWithEstimation` 必须**回溯到第一条同 ID 的 assistant 消息**才能正确计数：

```
assistant (id=X, tool_use: Grep)     ← 回溯到这里
  user (tool_result: Grep result)
assistant (id=X, tool_use: Glob)     ← 不是从这里开始
  user (tool_result: Glob result)
assistant (id=X, tool_use: Read)     ← 最后一条，有 usage 数据
  user (tool_result: Read result)
```

如果从最后一条开始计数，会漏掉中间插入的两个 tool_result 的估算。

---

## 第十部分：Prompt Cache 优化策略

### 10.1 为什么 Prompt Cache 如此重要

在 Claude API 的定价模型中：
- **Cache creation**（首次创建缓存）：正常价格的 **125%**
- **Cache read**（命中缓存）：正常价格的 **10%**
- **Cache miss**（缓存失效需重新创建）：回到 125%

这意味着：**如果每轮对话都能命中 prompt cache，长对话的成本可以降低 90% 以上。** 反过来，如果某个操作导致 cache bust（缓存失效），整个 prompt 需要重新创建，成本暴增。

### 10.2 Claude Code 的 Cache 保护措施

Claude Code 在多个层面保护 prompt cache：

**系统 prompt 分区缓存**（`src/utils/systemPrompt.ts`）：

```typescript
systemPromptSection(name, computeFn)           // 缓存直到 /clear 或 /compact
DANGEROUS_uncachedSystemPromptSection(name, fn) // 每轮重算（会破坏缓存！）
```

设计规则：能缓存的都缓存。只有在别无选择时才用 `DANGEROUS_uncached` 版本。

**Agent 列表外移**：

Agent 工具的 prompt 中包含可用代理列表，这个列表会随 MCP 服务器连接、插件加载等变化。如果放在工具 description 中，每次变化都会导致整个 tool schema 的 cache 失效。

解决方案：将代理列表移到**附件消息**中（`attachments.ts`），工具 description 保持静态。

源码注释（`AgentTool/prompt.ts:48-57`）：

```typescript
// The dynamic agent list was ~10.2% of fleet cache_creation tokens:
// MCP async connect, /reload-plugins, or permission-mode changes
// mutate the list → description changes → full tool-schema cache bust.
```

**翻译**：动态代理列表占了全系统 **10.2% 的 cache_creation token 成本**。外移后这个成本被消除。

**工具结果替换的稳定性**：

如前所述，`ContentReplacementState` 确保每个工具结果的替换决策一旦做出就不可逆。这保证了 prompt 的前缀部分永远不会因为替换策略变化而改变。

### 10.3 Cache 破坏检测

Claude Code 还有一个专门的**缓存破坏检测系统**（`src/services/api/promptCacheBreakDetection.ts`）：

- 记录每次 API 调用的系统 prompt hash、工具 schema hash、模型等
- 对比前后两次调用，检测哪个部分变化导致了 cache bust
- 区分"客户端变更导致的 cache bust"和"TTL 过期导致的 cache miss"
- 将检测结果写入 diff 文件供调试

---

## 第十一部分：关键数据指标与阈值总结

### 11.1 阈值全景

```
200K ─────────────────────────────────────── 模型原始上下文窗口
       │ -20K (output 预留)
180K ─────────────────────────────────────── 有效上下文窗口
       │
177K ─── ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 阻塞限制（必须手动 /compact）
       │ -3K
       │
167K ─────────────────────────────────────── 自动压缩触发点（~93%）
       │ -13K
       │
147K ─── ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ 警告阈值
       │ -20K
       │
  0K ─────────────────────────────────────── 空 context
```

### 11.2 各层限制数据

| 防线层 | 关键限制 | 数值 |
|--------|---------|------|
| 源头控制 | Glob 文件数限制 | 100 |
| 源头控制 | Grep 行数限制 | 250 |
| 源头控制 | Grep 行长限制 | 500 字符 |
| 源头控制 | Read 行数限制 | 2,000 |
| 源头控制 | Read token 限制 | 25,000 |
| 源头控制 | Read 文件大小限制 | 256 KB |
| 大结果外置 | 单工具默认阈值 | 50,000 字符 |
| 大结果外置 | 单轮聚合阈值 | 200,000 字符 |
| 大结果外置 | 外置预览大小 | 2,000 字节 |
| 读取去重 | LRU 缓存容量 | 100 条目 / 25MB |
| 全量压缩 | 触发阈值 | ~167,000 tokens |
| 全量压缩 | 输出预留 | 20,000 tokens |
| 全量压缩 | 最大重试次数 | 3 次 |
| 全量压缩 | 熔断阈值 | 3 次连续失败 |
| 压缩后恢复 | 文件恢复数量 | 最多 5 个 |
| 压缩后恢复 | 文件恢复预算 | 50K tokens / 5K 每文件 |
| 压缩后恢复 | 技能恢复预算 | 25K tokens / 5K 每技能 |
| Session 附件 | 累计附件上限 | 60 KB |

---

## 第十二部分：设计总结与产品启示

### 12.1 核心设计原则

**原则 1：纵深防御，永远有下一道防线**

没有任何单一机制能完美解决上下文管理问题。Claude Code 设计了 6 层防线，每层覆盖不同的场景和粒度。即使某一层失效，下一层仍然能兜底。

**原则 2：渐进式降级，而非断崖式截断**

上下文管理的最差策略是"满了就截断"。Claude Code 的做法是：
1. 先在源头控制量（第 1 层）
2. 再外置大块内容（第 2 层）
3. 再消除冗余（第 3 层）
4. 再清理旧内容（第 4 层）
5. 再智能压缩（第 5 层）
6. 最后才是紧急截断（第 6 层）

每一步都在最小化信息损失。

**原则 3：Cache 友好性是成本优化的命脉**

几乎所有设计决策都考虑了对 prompt cache 的影响。替换决策不可逆、系统 prompt 分区缓存、动态列表外移……这些设计每年可能节省数百万美元的 API 成本。

**原则 4：数据驱动的阈值设计**

每一个数字（13K 缓冲区、250 行限制、3 次熔断）都不是拍脑袋定的，而是来自线上数据分析。源码注释中大量引用了 BigQuery（BQ）的数据分析结果。

**原则 5：AI 自总结是压缩的最优解**

用 AI 来总结自己的对话历史，比任何机械性的截断或启发式规则都能更好地保留关键信息。9 段式结构化摘要确保了不同类型的信息都被覆盖。

### 12.2 完整信息流转图

```
         用户输入 + 工具调用
              │
              ▼
    ┌──────────────────┐
    │  第 1 层：源头控制  │  路径相对化、行数限制、行长截断
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────────┐
    │  第 2 层：大结果外置    │  超过 50K 字符 → 写入磁盘 → 2KB 预览
    └────────┬─────────────┘
             │
             ▼
    ┌──────────────────────┐
    │  第 3 层：读取去重      │  同文件重复读取 → 返回 "file_unchanged"
    └────────┬─────────────┘
             │
             ▼
       进入 Context Window
              │
    ┌─────────┴─────────┐
    │  Token 计量系统     │  实时追踪 context 使用量
    └─────────┬─────────┘
              │
         ┌────┴────┐
         │ < 93%?  │─── 是 ──→ 正常继续
         └────┬────┘
              │ 否
              ▼
    ┌──────────────────────┐
    │  第 4 层：微压缩       │  删除旧工具结果内容（保留结构）
    └────────┬─────────────┘
              │
         ┌────┴────┐
         │ 仍然超? │─── 否 ──→ 继续工作
         └────┬────┘
              │ 是
              ▼
    ┌──────────────────────────┐
    │  第 5 层：全量压缩         │  AI 生成 9 段式摘要 → 替换全部历史
    │  (或 Session Memory 压缩) │  → 重建关键上下文（文件、技能、代理）
    └────────┬─────────────────┘
              │
         ┌────┴────┐
         │ 还是超? │─── 否 ──→ 继续工作（从摘要恢复）
         └────┬────┘
              │ 是（压缩本身也超了/失败了）
              ▼
    ┌──────────────────────┐
    │  第 6 层：应急兜底      │  按轮次丢弃最旧消息 → 重试
    │  + 熔断保护            │  连续失败 3 次 → 停止重试
    └──────────────────────┘
```

### 12.3 对 Agent 产品设计的关键启发

1. **上下文管理不是可选项，是必选项**：任何需要长时间交互的 Agent 产品都必须从第一天就设计上下文管理系统。这不是"后期优化"，而是"架构级决策"。

2. **多层防御比单一机制更可靠**：不要试图用一个"完美的压缩算法"解决所有问题。分层设计让每一层都可以独立演进、独立测试、独立降级。

3. **token 经济学贯穿所有设计**：每一个设计决策（路径相对化节省 500 tokens、读取去重节省 2.64% 成本、Agent 列表外移节省 10.2% 成本）都在优化 token 效率。在大规模部署下，1% 的优化就意味着每年数十万美元的成本差异。

4. **AI 自总结是目前最佳的压缩策略**：机械性截断会丢失关键信息，启发式规则难以覆盖所有场景。让 AI 自己总结，同时通过结构化 prompt（9 段式）确保关键信息不遗漏，是目前信息密度最高的压缩方式。

5. **"不可逆决策 + 缓存稳定性"是成本优化的秘钥**：通过确保 prompt 的前缀部分永远不变，最大化 prompt cache 命中率，可以将长对话的 API 成本降低一个数量级。

6. **线上数据驱动的持续调优**：Claude Code 的每一个阈值和开关都可以通过 GrowthBook（远程配置平台）动态调整，并通过遥测事件追踪效果。这使得团队可以在不发版的情况下持续优化上下文管理策略。

---

*下一步研究方向建议：System Prompt 工程设计、权限与安全体系、MCP 生态扩展策略*
