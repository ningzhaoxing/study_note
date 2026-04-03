# Claude Code Sub-Agent 系统设计深度研究

> 研究对象：Claude Code CLI（Anthropic 官方 Agent 产品）
> 研究视角：Agent 产品设计 / 多代理协作架构
> 研究日期：2026-04-01

---

## 引言：为什么需要 Sub-Agent

一个"单体 Agent"面临三个根本性瓶颈：

1. **Context 窗口是有限的**：一个复杂的研究任务可能需要读取 20+ 个文件，而每次读取都消耗数千 tokens。如果所有中间结果都堆积在主对话中，context 很快耗尽。
2. **串行执行效率低下**：搜索文件 A、搜索文件 B、搜索文件 C……如果必须串行完成，用户等待时间线性增长。
3. **专业化需求**：有些任务需要特定的工具集和行为模式——探索代码库不需要编辑工具，规划架构不需要执行工具。

Sub-Agent 系统通过**分身、隔离、并行**三个核心能力，同时解决了这三个问题。

---

## 第一部分：Sub-Agent 系统全景架构

### 1.1 三种代理模式

Claude Code 的 Sub-Agent 系统有三种截然不同的代理模式，每种解决不同层次的问题：

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  模式 1：Fresh Subagent（全新子代理）                               │
│  ─ 从零开始的独立 Agent                                           │
│  ─ 有自己的 System Prompt、工具集、模型                             │
│  ─ 不继承父代理的对话历史                                          │
│  ─ 适合：专业化任务（探索、规划、验证）                               │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  模式 2：Fork（分叉子代理）                                        │
│  ─ 继承父代理的完整对话上下文                                       │
│  ─ 共享父代理的 System Prompt 和工具集                              │
│  ─ 最大化 Prompt Cache 命中率                                     │
│  ─ 适合：需要上下文的研究任务、实施任务                               │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  模式 3：Teammate（团队协作代理）                                   │
│  ─ 在独立终端窗口中运行的自治代理                                    │
│  ─ 通过邮箱系统与其他代理通信                                       │
│  ─ 可以并行长时间运行                                              │
│  ─ 适合：大型工程任务的分工协作                                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 执行模式矩阵

| 维度 | 前台同步 | 后台异步 | Worktree 隔离 | 远程执行 |
|------|---------|---------|--------------|---------|
| **Fresh Subagent** | 阻塞等待结果 | 立即返回 task ID | 独立 Git 工作树 | CCR 远程环境 |
| **Fork** | — | 始终后台 | 可选 | — |
| **Teammate** | — | 始终后台 | 可选 | — |

### 1.3 核心文件架构

```
src/tools/AgentTool/
├── AgentTool.tsx            # 主入口：Agent 工具的完整实现（~58K行）
├── prompt.ts                # Agent 工具的 prompt 生成
├── forkSubagent.ts          # Fork 机制的核心逻辑
├── runAgent.ts              # Agent 运行循环
├── resumeAgent.ts           # 后台 Agent 的恢复逻辑
├── agentToolUtils.ts        # 异步生命周期管理
├── loadAgentsDir.ts         # Agent 定义的加载和注册系统
├── builtInAgents.ts         # 内置 Agent 的注册
├── agentMemory.ts           # Agent 持久化记忆系统
├── agentMemorySnapshot.ts   # 记忆快照机制
├── agentColorManager.ts     # Agent 颜色标识系统
├── agentDisplay.ts          # Agent 显示分组
├── constants.ts             # 常量定义
├── UI.tsx                   # UI 渲染
└── built-in/                # 内置 Agent 定义
    ├── generalPurposeAgent.ts   # 通用代理
    ├── exploreAgent.ts          # 探索代理
    ├── planAgent.ts             # 规划代理
    ├── claudeCodeGuideAgent.ts  # 使用指南代理
    ├── verificationAgent.ts     # 验证代理
    └── statuslineSetup.ts       # 状态栏配置代理
```

---

## 第二部分：Agent 定义系统——"代理是什么"

### 2.1 Agent 定义的三种来源

Claude Code 支持三种 Agent 来源，按优先级从低到高排列：

```
优先级（低→高）：
Built-in → Plugin → User Settings → Project Settings → Flag Settings → Policy Settings
                                                                         ↑
                                                          后面的可以覆盖前面的
```

**Built-in（内置）**：代码中硬编码的 Agent 定义，如 Explore、Plan 等
**Plugin（插件）**：通过插件系统动态加载的 Agent
**Custom（自定义）**：用户在 `.claude/agents/` 目录下用 Markdown 文件定义的 Agent

### 2.2 Agent 定义的完整 Schema

每个 Agent 定义包含以下字段（`loadAgentsDir.ts:106-133`）：

```typescript
BaseAgentDefinition = {
  // === 必填字段 ===
  agentType: string         // 唯一标识符，如 "Explore", "Plan"
  whenToUse: string         // 何时使用此 Agent 的描述（给模型看的）

  // === 工具控制 ===
  tools?: string[]          // 允许的工具列表（如 ["Read", "Grep", "Glob"]）
  disallowedTools?: string[] // 禁止的工具列表（如 ["Agent", "Edit", "Write"]）

  // === 模型与行为 ===
  model?: string            // 使用的模型（如 "haiku", "inherit" 继承父代理模型）
  effort?: EffortValue      // 努力程度（影响推理深度）
  maxTurns?: number         // 最大对话轮数
  permissionMode?: PermissionMode // 权限处理模式

  // === 执行模式 ===
  background?: boolean      // 是否始终后台运行
  isolation?: 'worktree' | 'remote' // 隔离模式

  // === 上下文控制 ===
  omitClaudeMd?: boolean    // 是否省略 CLAUDE.md（节省 token）
  initialPrompt?: string    // 首轮预注入的提示
  skills?: string[]         // 预加载的技能

  // === 持久化 ===
  memory?: 'user' | 'project' | 'local' // 持久化记忆范围

  // === 外部集成 ===
  mcpServers?: AgentMcpServerSpec[] // 需要的 MCP 服务器
  hooks?: HooksSettings     // 会话级钩子
}
```

### 2.3 自定义 Agent 的 Markdown 定义格式

用户可以在 `.claude/agents/my-agent.md` 中定义自己的 Agent：

```markdown
---
name: code-reviewer
description: Use this agent to review code changes for quality, security, and best practices.
tools: [Read, Grep, Glob, Bash]
disallowedTools: [Edit, Write, Agent]
model: inherit
memory: project
maxTurns: 20
---

You are a code review specialist. Your role is to analyze code changes
and provide actionable feedback on:
- Code quality and readability
- Security vulnerabilities
- Performance implications
- Adherence to project conventions

Be thorough but concise. Prioritize high-impact findings.
```

**设计洞察**：使用 Markdown + YAML frontmatter 的格式极为精妙：
- Frontmatter 用于结构化配置（工具、模型、记忆等）
- Body 直接就是 System Prompt（纯自然语言）
- 开发者可以用任何文本编辑器编辑
- 可以纳入版本控制，团队共享

### 2.4 六个内置 Agent 的设计分析

| Agent | 定位 | 工具配置 | 模型 | 关键设计决策 |
|-------|------|---------|------|-------------|
| **general-purpose** | 通用万能代理 | `['*']` 全部工具 | 默认子代理模型 | 什么都能做，但不够专业 |
| **Explore** | 代码库快速探索 | 禁止 Agent/Edit/Write/NotebookEdit | 外部 haiku / 内部 inherit | **只读、跳过 CLAUDE.md、用 haiku 求快** |
| **Plan** | 架构规划 | 同 Explore | inherit | **只读、跳过 CLAUDE.md、继承父模型（需要强推理）** |
| **claude-code-guide** | 用户教程 | 有限工具集 | — | 帮助用户学习使用 Claude Code |
| **verification** | 代码验证 | — | — | 实验性，验证代码变更正确性 |
| **statusline-setup** | 状态栏配置 | Read, Edit | — | 配置终端状态栏 |

#### Explore Agent 的设计深入

Explore 是使用频率最高的子代理（源码注释提到 **每周 34M+ 次调用**）。它的每个设计决策都经过精心优化：

**1. 只读模式，严格禁止任何写操作**

System Prompt 中用大写醒目标记（`exploreAgent.ts:26-36`）：

```
=== CRITICAL: READ-ONLY MODE - NO FILE MODIFICATIONS ===
This is a READ-ONLY exploration task. You are STRICTLY PROHIBITED from:
- Creating new files (no Write, touch, or file creation of any kind)
- Modifying existing files (no Edit operations)
...
```

**2. 省略 CLAUDE.md 以节省 token**

```typescript
omitClaudeMd: true,
// Explore is a fast read-only search agent — it doesn't need commit/PR/lint
// rules from CLAUDE.md. The main agent has full context and interprets results.
```

源码注释直接给出了数据：**每周节省 5-15 Gtokens（数十亿 token）**。

**3. 使用 Haiku 模型（外部用户）**

```typescript
model: process.env.USER_TYPE === 'ant' ? 'inherit' : 'haiku',
```

Explore 的任务是搜索文件、读取内容——不需要顶级推理能力，用更快更便宜的 Haiku 模型即可。

**4. 强调速度和并行**

```
NOTE: You are meant to be a fast agent that returns output as quickly as possible.
In order to achieve this you must:
- Make efficient use of the tools...
- Wherever possible you should try to spawn multiple parallel tool calls
```

#### Plan Agent 与 Explore 的差异

Plan 和 Explore 共享相同的工具限制（只读），但有一个关键差异：

```typescript
// Plan Agent
model: 'inherit',  // 继承父代理模型（需要强推理能力来做架构设计）

// Explore Agent
model: process.env.USER_TYPE === 'ant' ? 'inherit' : 'haiku',  // 外部用户用 haiku（求快）
```

**设计逻辑**：探索只需要"找到"，规划需要"理解和设计"。前者可以用小模型加速，后者必须用强模型保证质量。

---

## 第三部分：Fork 机制——"分身术"

### 3.1 Fork 的核心概念

Fork 是 Claude Code 中最精妙的子代理机制。它的核心思想是：

> **与其让一个全新的 Agent 从零开始理解问题，不如"分身"出一个完全继承当前上下文的副本来执行任务。**

### 3.2 Fork vs Fresh Subagent 的本质差异

```
Fresh Subagent（全新代理）：

  父 Agent 的 context:  [系统提示, 用户消息, 工具调用, 对话历史...]
                              │
                              │ 只传递 prompt 参数
                              ▼
  子 Agent 的 context:  [自己的系统提示, prompt 参数]
                         ↑
                        从零开始，什么都不知道


Fork（分叉代理）：

  父 Agent 的 context:  [系统提示, 用户消息, 工具调用, 对话历史...]
                              │
                              │ 完整继承父 context + 追加指令
                              ▼
  子 Agent 的 context:  [父的系统提示(完全相同), 父的完整对话历史, 新的指令]
                         ↑
                        知道一切，只需要新指令
```

### 3.3 Fork 的 Prompt Cache 优化——核心创新

Fork 机制的最大创新在于**Prompt Cache 共享**。这是一个直接影响成本的架构决策。

**原理**：当父 Agent 发起多个并行 Fork 时，所有 Fork 子代理的 API 请求有**完全相同的前缀**（系统提示 + 对话历史），只有末尾的指令不同。

```
Fork Child A 的请求: [系统提示 + 对话历史 + 工具结果占位符 + "请搜索认证模块"]
Fork Child B 的请求: [系统提示 + 对话历史 + 工具结果占位符 + "请搜索数据库模块"]
Fork Child C 的请求: [系统提示 + 对话历史 + 工具结果占位符 + "请搜索日志模块"]
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                      这部分完全相同 → Prompt Cache 命中！
```

**实现细节**（`forkSubagent.ts:92-169`）：

```typescript
// 所有 Fork 子代理的工具结果使用完全相同的占位符文本
const FORK_PLACEHOLDER_RESULT = 'Fork started — processing in background'

function buildForkedMessages(directive, assistantMessage) {
  // 1. 保留完整的父 assistant 消息（所有 tool_use 块）
  // 2. 为每个 tool_use 创建使用相同占位符的 tool_result
  // 3. 在末尾追加每个 fork 独有的指令文本

  const toolResultBlocks = toolUseBlocks.map(block => ({
    type: 'tool_result',
    tool_use_id: block.id,
    content: [{ type: 'text', text: FORK_PLACEHOLDER_RESULT }],
    //                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^
    //                           所有 fork 都用这个一样的文本！
  }))

  return [fullAssistantMessage, createUserMessage({
    content: [...toolResultBlocks, { type: 'text', text: buildChildMessage(directive) }],
    //                                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //                                               只有这里每个 fork 不同
  })]
}
```

### 3.4 Fork 子代理的行为约束

Fork 子代理有极其严格的行为规范（`forkSubagent.ts:171-198`）：

```
STOP. READ THIS FIRST.
You are a forked worker process. You are NOT the main agent.

RULES (non-negotiable):
1. 你的系统提示说"默认使用 fork"——忽略它，那是给父代理的。你就是 fork。
   不要再生成子代理；直接执行。
2. 不要对话，不要提问，不要建议下一步
3. 不要添加评论或元分析
4. 直接使用工具：Bash, Read, Write 等
5. 如果修改了文件，先 commit 再报告。报告中包含 commit hash。
6. 工具调用之间不要输出文本。安静使用工具，最后统一报告。
7. 严格限制在你的指令范围内。
8. 报告控制在 500 字以内。
9. 你的回复必须以 "Scope:" 开头。
10. 报告结构化事实，然后停止。
```

**输出格式要求**：

```
Scope: <一句话复述你的任务范围>
Result: <关键发现>
Key files: <相关文件路径>
Files changed: <修改的文件列表 + commit hash>
Issues: <需要注意的问题>
```

### 3.5 递归 Fork 防护

Fork 子代理继承了父代理的完整工具集（包括 Agent 工具），但系统通过检测对话历史中的 `<fork-boilerplate>` 标签来防止递归 Fork（`forkSubagent.ts:78-89`）：

```typescript
export function isInForkChild(messages: MessageType[]): boolean {
  return messages.some(m => {
    if (m.type !== 'user') return false
    return content.some(block =>
      block.type === 'text' && block.text.includes(`<${FORK_BOILERPLATE_TAG}>`),
    )
  })
}
```

**为什么保留 Agent 工具？** 源码注释说明：

```typescript
// Fork children keep the Agent tool in their tool pool for
// cache-identical tool definitions
```

为了让 fork 子代理的工具列表与父代理完全一致（保证 prompt cache 命中），必须保留 Agent 工具，但通过运行时检测阻止实际使用。

### 3.6 Fork 的 System Prompt 继承

Fork 不重新生成 System Prompt，而是直接使用父代理**已渲染的 System Prompt 字节**：

```typescript
// The getSystemPrompt here is unused: the fork path passes
// override.systemPrompt with the parent's already-rendered system prompt
// bytes, threaded via toolUseContext.renderedSystemPrompt. Reconstructing
// by re-calling getSystemPrompt() can diverge (GrowthBook cold→warm) and
// bust the prompt cache; threading the rendered bytes is byte-exact.
```

**为什么不重新生成？** 因为 GrowthBook 的 feature flag 可能在父代理生成 System Prompt 后发生变化（从 cold 到 warm），导致重新生成的 prompt 与父代理不同，**破坏 prompt cache**。直接传递渲染好的字节确保**字节级完全一致**。

---

## 第四部分：执行模式详解

### 4.1 前台同步执行

```
用户请求 → Agent Tool 调用 → 阻塞等待 → 子代理完成 → 结果返回给父代理
```

**适用场景**：结果是后续步骤的必要输入（如："先搜索这个函数的定义，然后修改它"）

**实现要点**：
- 注册前台任务（`registerAgentForeground()`）
- 创建异步迭代器消费 `runAgent()` 生成器
- 支持中途转后台：如果执行超过 120 秒，自动提升为后台任务

### 4.2 后台异步执行

```
用户请求 → Agent Tool 调用 → 立即返回 task ID + output 文件路径
                                    ↓
                            子代理在后台运行
                                    ↓
                            完成后发送 <task-notification>
                                    ↓
                            父代理收到通知继续工作
```

**适用场景**：结果可以稍后获取，父代理可以同时做其他工作

**通知格式**：

```xml
<task-notification>
  <task-id>agent-123</task-id>
  <status>completed</status>
  <summary>Found 3 authentication vulnerabilities</summary>
  <result>Scope: Security audit of auth module...Result: ...</result>
  <usage>
    <total_tokens>15234</total_tokens>
    <tool_uses>8</tool_uses>
    <duration_ms>12500</duration_ms>
  </usage>
</task-notification>
```

### 4.3 Worktree 隔离执行

Worktree 隔离让子代理在一个**独立的 Git 工作副本**中操作，确保文件修改不影响主工作区。

**创建流程**：

```
1. 创建 Git 工作树：git worktree add -B <branch> <path> <base>
2. 后处理：
   - 复制 settings.local.json
   - 配置 core.hooksPath 指向主仓库的 hooks
   - 符号链接共享目录（node_modules 等）
   - 复制 .worktreeinclude 文件
```

**变更检测**（完成后）：

```
git status --porcelain     → 检查未提交的变更
git rev-list --count <head>..HEAD  → 检查新的 commit
```

**清理策略**（fail-closed 设计）：
- 如果没有任何变更 → 自动删除工作树和分支
- 如果有变更 → 保留工作树，返回工作树路径和分支名给父代理
- 如果检测失败 → **保留**（宁可保留不需要的，也不丢弃有价值的变更）

**Fork + Worktree 的组合**：

当 Fork 子代理在 Worktree 中运行时，会额外注入一条路径转换提示：

```
You've inherited the conversation context above from a parent agent working in
/Users/user/project. You are operating in an isolated git worktree at
/Users/user/project/.claude/worktrees/feature-123 — same repository, same
relative file structure, separate working copy. Paths in the inherited context
refer to the parent's working directory; translate them to your worktree root.
```

### 4.4 后台 Agent 的恢复机制

后台 Agent 可能因为各种原因中断（进程退出、用户手动停止等）。Claude Code 支持从磁盘恢复：

**恢复流程**（`resumeAgent.ts`）：
1. 从磁盘加载 transcript 和 metadata
2. 过滤消息：移除空白消息、孤立的 thinking 块、未完成的 tool_use
3. 从 sidechain 记录重建 `contentReplacementState`（保证 prompt cache 稳定性）
4. 验证 worktree 是否仍然存在
5. 解析 Agent 类型（fork vs 具名 Agent）
6. 注册为异步任务
7. 用恢复的消息 + 新 prompt 继续运行

---

## 第五部分：Agent 通信系统

### 5.1 通信架构

Sub-Agent 系统有三种通信模式：

```
模式 A：父子直接返回
  父 Agent ──调用──→ 子 Agent ──完成──→ 结果直接返回父 Agent

模式 B：通知机制（后台 Agent）
  父 Agent ──启动──→ 子 Agent（后台运行）
                        │
                        └──完成──→ <task-notification> ──→ 父 Agent

模式 C：邮箱通信（Teammate）
  Agent A ──SendMessage──→ 邮箱文件 ──→ Agent B 读取
  Agent B ──SendMessage──→ 邮箱文件 ──→ Agent A 读取
```

### 5.2 SendMessage 工具

`SendMessage` 工具是 Agent 间通信的核心（`SendMessageTool.ts`）：

**收件人类型**：
- 直接指名：`to: "reviewer"` — 发送给名为 reviewer 的 teammate
- 广播：`to: "*"` — 发送给所有 teammates
- UDS 通信：`to: "uds:/path/to/socket"` — 通过 Unix Domain Socket 发送
- 远程桥接：`to: "bridge:session-id"` — 通过远程控制桥接发送

**消息类型**：
- 普通文本消息（需要 5-10 字的摘要）
- 结构化消息：
  - `shutdown_request` — 请求 teammate 停止工作
  - `shutdown_response` — 同意/拒绝停止
  - `plan_approval_response` — 同意/拒绝计划

**投递机制**：
- 进程内 Agent：通过 `queuePendingMessage()` 排队
- Tmux/iTerm2 Teammate：通过 `writeToMailbox()` 写入文件系统邮箱
- 已停止的 Agent：自动恢复后投递

### 5.3 Coordinator 模式

Coordinator 模式是一种高级多代理编排模式，其中一个"协调者"Agent 指挥多个"工人"Agent：

```
                      ┌─────────────┐
                      │ Coordinator │ ← 与用户交互
                      │  (协调者)    │
                      └──────┬──────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────┴────┐  ┌─────┴────┐  ┌──────┴─────┐
        │ Worker A │  │ Worker B │  │ Worker C   │
        │ (研究)    │  │ (实现)    │  │ (验证)     │
        └──────────┘  └──────────┘  └────────────┘
```

**Coordinator 的工作流程**：
1. **Research（研究）**：启动 Worker 搜集信息
2. **Synthesis（综合）**：协调者综合所有 Worker 的发现
3. **Implementation（实现）**：指派 Worker 执行具体变更
4. **Verification（验证）**：指派 Worker 验证变更正确性

**关键原则**：Coordinator 必须**先理解 Worker 的研究结果，然后再指派实施工作**——不能简单地转发任务。

---

## 第六部分：Context 隔离与共享

### 6.1 隔离矩阵

不同代理模式下，各种状态的继承与隔离策略：

| 状态 | Fresh Subagent | Fork | Teammate |
|------|---------------|------|----------|
| **System Prompt** | 自己的 | 父的渲染字节（完全相同） | 自己的 |
| **对话历史** | 空 | 完整继承 | 空 |
| **工具集** | 按定义过滤 | 父的完整工具集 | 按定义过滤 |
| **文件状态缓存** | 克隆自父 | 克隆自父 | 独立 |
| **内容替换状态** | 克隆自父 | 克隆自父 | 独立 |
| **权限拒绝状态** | 新建 | 新建 | 独立 |
| **AbortController** | 子链接到父 | 子链接到父 | 独立 |
| **Prompt Cache** | 独立 | 共享父的 | 独立 |
| **工作目录** | 继承或指定 | 继承或 Worktree | 继承或指定 |
| **CLAUDE.md** | 加载（可省略） | 继承自父 | 加载 |

### 6.2 子代理 Context 创建

`createSubagentContext()` 函数负责创建隔离的子代理上下文（`forkedAgent.ts`）：

**克隆的可变状态**：
- `readFileState`：文件读取缓存（防止子代理和父代理的文件缓存互相干扰）
- `contentReplacementState`：工具结果替换状态（保持 prompt cache 稳定性）

**新建的状态**：
- `nestedMemoryAttachmentTriggers`：新的空集合
- `discoveredSkillNames`：新的空集合
- `localDenialTracking`：新的拒绝追踪

**特殊处理**：
- `shouldAvoidPermissionPrompts: true` — 后台子代理不应该弹出权限提示
- 但 Fork 使用 `permissionMode: 'bubble'` — 权限请求上浮到父终端

### 6.3 为什么 Fork 要克隆 contentReplacementState？

源码注释解释：

```typescript
// The fork needs state identical to the source at fork time so
// enforceToolResultBudget makes the same choices → same wire prefix →
// prompt cache hit. Mutating the clone does not affect the source.
```

Fork 子代理必须对工具结果做出**与父代理完全相同的替换决策**，这样它们发送给 API 的 prompt 前缀才能字节级一致，从而命中 prompt cache。

---

## 第七部分：Agent 记忆系统

### 7.1 三层记忆范围

Agent 可以配置三种持久化记忆范围：

```
User 范围（跨项目共享）
  ~/.claude/agent-memory/<agentType>/MEMORY.md
  适用于：通用偏好、跨项目适用的知识

Project 范围（团队共享）
  <项目>/.claude/agent-memory/<agentType>/MEMORY.md
  适用于：项目特定的约定、团队共享的知识
  纳入版本控制

Local 范围（仅本机）
  <项目>/.claude/agent-memory-local/<agentType>/MEMORY.md
  适用于：本机特有的配置、个人偏好
  不纳入版本控制
```

### 7.2 记忆的加载时机

Agent 的记忆在**生成 System Prompt 时**加载，作为 prompt 的一部分注入：

```typescript
getSystemPrompt: () => {
  if (isAutoMemoryEnabled() && parsed.memory) {
    return systemPrompt + '\n\n' + loadAgentMemoryPrompt(name, parsed.memory)
  }
  return systemPrompt
}
```

### 7.3 记忆快照机制

对于 Project 范围的记忆，Claude Code 支持**记忆快照**——团队可以在项目仓库中放置一个记忆快照，新团队成员克隆仓库后会自动继承：

```
checkAgentMemorySnapshot(agentType, scope)
  → 'initialize': 本地没有记忆，从快照初始化
  → 'prompt-update': 快照比本地记忆更新，提示用户更新
  → 'up-to-date': 无需操作
```

---

## 第八部分：Agent Tool 的 Prompt 设计

### 8.1 何时用哪种 Agent 的决策指引

Claude Code 在 System Prompt 中为模型提供了清晰的决策指引：

**不应该使用 Agent 的场景**（直接使用 Glob/Grep/Read 更快）：

```
When NOT to use the Agent tool:
- 如果你要读取一个已知路径的文件 → 用 Read
- 如果你在搜索特定类定义如 "class Foo" → 用 Glob
- 如果你在 2-3 个已知文件中搜索代码 → 用 Read
```

**应该使用 Agent 的场景**：

```
For simple, directed codebase searches → 直接用 Glob 或 Grep
For broader codebase exploration and deep research → 用 Agent(Explore)
  注意：Explore 比直接使用 Glob/Grep 更慢，所以只在简单搜索不够用
  或任务明显需要 3 次以上查询时使用。
```

### 8.2 Fork 模式下的 Prompt 设计

Fork 模式有一套完全不同的指导原则：

**何时 Fork**：

```
Fork yourself (omit subagent_type) when the intermediate tool output
isn't worth keeping in your context. The criterion is qualitative —
"will I need this output again" — not task size.

- Research: fork open-ended questions. If research can be broken into
  independent questions, launch parallel forks in one message.
- Implementation: prefer to fork implementation work that requires
  more than a couple of edits.
```

**Fork 的"禁令"**：

```
Don't peek. — 不要读取 Fork 的输出文件！等通知就好。
Don't race. — Fork 完成前不要猜测结果。
```

### 8.3 编写 Agent/Fork Prompt 的指南

Claude Code 对如何为子代理编写 prompt 有详细指导：

**给 Fresh Subagent 的 prompt（完整上下文）**：

```
Brief the agent like a smart colleague who just walked into the room —
it hasn't seen this conversation, doesn't know what you've tried,
doesn't understand why this task matters.

- 解释你想完成什么以及为什么
- 描述你已经了解或排除的东西
- 给足够的周围问题上下文，让 agent 能做判断而不是机械执行
```

**给 Fork 的 prompt（简短指令）**：

```
Since the fork inherits your context, the prompt is a directive —
what to do, not what the situation is. Be specific about scope:
what's in, what's out, what another agent is handling.
Don't re-explain background.
```

---

## 第九部分：Multi-Agent 协作模式

### 9.1 Teammate 产生方式

Teammate 可以通过三种后端产生：

```
┌─────────────────────────────────────────────────────────┐
│ 后端 1：进程内（In-Process）                              │
│ ─ 同一 Node.js 进程                                     │
│ ─ 通过 AsyncLocalStorage 隔离上下文                      │
│ ─ 资源消耗最小                                           │
│ ─ 适合轻量级、短时间的子任务                               │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 后端 2：Tmux 分屏                                       │
│ ─ 在 tmux 窗口中创建新的 pane                            │
│ ─ Leader 在左侧，Teammates 在右侧                       │
│ ─ 用户可以同时看到所有 Agent 的工作                       │
│ ─ 适合需要可视化监控的并行任务                             │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 后端 3：iTerm2 原生分屏                                  │
│ ─ 使用 iTerm2 的原生分屏能力                              │
│ ─ 需要 it2 CLI                                         │
│ ─ 更好的视觉体验                                        │
└─────────────────────────────────────────────────────────┘
```

### 9.2 Team 生命周期

```
TeamCreate → 创建团队上下文（team file + member list）
    │
    ├── SpawnTeammate × N  →  各 teammate 在独立环境中运行
    │       │
    │       ├── Agent 通过 SendMessage 互相通信
    │       ├── Agent 通过 mailbox 文件交换消息
    │       └── Agent 完成后发送 notification
    │
    └── TeamDelete → 清理团队资源
```

### 9.3 Agent 颜色标识

每个 Teammate 被分配一个唯一颜色用于终端显示，帮助用户区分不同 Agent 的输出：

```typescript
export const AGENT_COLORS: readonly AgentColorName[] = [
  'cyan', 'magenta', 'yellow', 'green', 'blue', 'red',
  'white', 'gray', 'brightCyan', 'brightMagenta', ...
]
```

---

## 第十部分：设计总结与产品启示

### 10.1 核心设计原则

**原则 1：Context 隔离是第一优先级**

Sub-Agent 系统存在的首要原因是保护主对话的 context 空间。每个子代理的中间结果（搜索输出、文件内容）都在独立的 context 中消耗，只有最终摘要返回给父代理。

**原则 2：专业化 Agent 胜过通用 Agent**

Explore Agent 跳过 CLAUDE.md、用 Haiku 模型、禁止写操作——每个决策都在让它**更快更便宜地做好搜索这一件事**。Plan Agent 继承父模型——因为规划需要强推理能力。通用 Agent 拥有所有工具——因为它需要应对无法预测的任务。

**原则 3：Cache 共享是 Fork 的核心价值**

Fork 的全部设计（相同的 system prompt 字节、相同的工具集、相同的占位符文本）都围绕一个目标：**让多个并行 fork 共享同一个 prompt cache**。在 API 定价模型下，cache read 成本是 cache creation 的 1/12.5，这意味着 Fork 的成本优势随并行度线性增长。

**原则 4：灵活的定义格式降低定制门槛**

Markdown + YAML frontmatter 的 Agent 定义格式让任何开发者都可以在 5 分钟内创建一个自定义 Agent，而不需要编写任何代码。同时支持版本控制共享，让团队可以标准化 Agent 配置。

**原则 5：通信解耦保证可扩展性**

通过文件系统邮箱（而非直接进程间通信）实现 Agent 间消息传递，让系统天然支持跨进程、跨机器的 Agent 协作。已停止的 Agent 收到消息后可以自动恢复——无需调用方关心对方的运行状态。

### 10.2 Sub-Agent 系统的完整决策流

```
                        用户的任务需求
                             │
                  ┌──────────┴──────────┐
                  │ 任务是否需要代理？    │
                  └──────────┬──────────┘
                        │         │
                       否         是
                        │         │
                  直接执行    ┌───┴───────────────────┐
                             │ 需要上下文吗？          │
                             └───┬───────────────────┘
                            │         │
                           否         是
                            │         │
                    ┌───────┴──┐   ┌──┴────────────┐
                    │ Fresh    │   │  Fork         │
                    │ Subagent │   │ （继承 context）│
                    └───┬──────┘   └──┬────────────┘
                        │             │
              ┌─────────┴───┐    ┌────┴────────┐
              │ 需要专业化？  │    │ 需要文件隔离？│
              └─────┬───────┘    └────┬────────┘
                │       │          │       │
               是       否        是       否
                │       │          │       │
            选择专业   通用    Worktree   直接
            Agent    Agent    隔离     Fork
           (Explore, (general-
            Plan)    purpose)

              所有类型都支持：
              ├── 前台同步（等待结果）
              └── 后台异步（立即返回，完成后通知）
```

### 10.3 对 Agent 产品设计的关键启发

1. **Sub-Agent 不只是"多代理"——它是 Context 管理的核心手段**。将复杂任务委派给子代理，本质上是在用独立的 context 空间来"扩展"有限的主 context 窗口。

2. **Fork 机制是一个架构级创新**。通过上下文继承 + prompt cache 共享，Fork 让"分身"的成本远低于"从零开始"。这对于需要大量并行研究的场景（代码审查、影响面分析、架构探索）极具价值。

3. **Agent 的定义应该是声明式的，而非命令式的**。Markdown + frontmatter 的定义方式让 Agent 配置变得简单、可读、可共享。这大幅降低了创建自定义 Agent 的门槛。

4. **专业化 Agent 的关键是"少即是多"**。Explore Agent 的价值不在于它"能做什么"，而在于它"不做什么"——不编辑、不写入、不嵌套调用、不加载 CLAUDE.md。每去掉一个能力，它就变得更快、更便宜、更可靠。

5. **Agent 记忆系统实现了"经验积累"**。三层记忆范围（user/project/local）+ 记忆快照机制，让 Agent 可以跨会话学习，团队可以共享最佳实践。这是从"一次性工具"向"持续成长的助手"的关键转变。

6. **通信系统的设计决定了协作的上限**。文件系统邮箱、消息路由、自动恢复——这些基础设施使得从"单 Agent"扩展到"Agent 团队"成为可能，而不需要重新设计核心架构。

---

*下一步研究方向建议：权限与安全体系、System Prompt 工程、MCP 生态扩展策略、Hooks 系统设计*
