# OpenClaw Agent 技术调研

> 仓库：https://github.com/openclaw/openclaw
> 版本：main 分支（2026-03-10）
> 语言：TypeScript (ESM)，Node ≥ 22

---

## 1. 项目定位

OpenClaw 是一个**本地优先的个人 AI 助手框架**，其核心理念是：

- 用户通过已有的聊天渠道（WhatsApp、Telegram、Slack、Discord 等 20+ 平台）与 AI 交互
- 所有数据和记忆存储在本地（Markdown 文件）
- 通过可扩展的 **Skill 系统**来扩展 Agent 能力，而不是拆分成多个独立 Agent
- 单一 Gateway 进程充当控制平面，Pi Agent 是唯一的主执行单元

架构上只有**一个主 Agent（Pi Agent）**，所有专业能力通过 Skill 插件化扩展——这正是"使用 Skill 统一为主 Agent"方案的成熟参考实现。

---

## 2. 整体架构

### 2.1 数据流

```text
用户消息（WhatsApp / Telegram / Slack / Discord / Signal / iMessage / ...）
    │
    ▼
┌──────────────────────────────────┐
│            Gateway               │  ws://127.0.0.1:18789
│          （控制平面）             │
└──────────────┬───────────────────┘
               │
               ├── Pi Agent（主 Agent，每轮执行）
               ├── CLI（openclaw ...）
               ├── WebChat UI
               └── macOS / iOS / Android 节点
```

### 2.2 Pi Agent 每轮执行流程

入口：`src/agents/pi-embedded-runner/run/attempt.ts` → `runEmbeddedAttempt()`

```text
1. 解析 Model + Auth Profile
2. 加载 Bootstrap 文件（AGENTS.md / SOUL.md / MEMORY.md 等）→ 注入 System Prompt
3. 加载 Skills 快照 → 过滤 → 生成 <available_skills> 列表 → 注入 System Prompt
4. 注册工具集（read / write / exec / sessions_spawn / web_search 等）
5. 调用 LLM，流式输出
6. 拦截工具调用块 → 执行工具 → 追加结果到会话记录
7. 循环直到 LLM 不再输出工具调用
```

### 2.3 System Prompt 的三种模式

来源：`src/agents/system-prompt.ts` → `PromptMode`

| 模式        | 适用场景           | 包含内容                                                          |
| --------- | -------------- | ------------------------------------------------------------- |
| `full`    | 主 Agent / 直接对话 | 全部 section（Tooling、Safety、Skills、Memory、Messaging 等）          |
| `minimal` | 子 Agent        | 仅 Tooling、Workspace、Runtime 三个 section                        |
| `none`    | 纯身份声明          | 仅一行 `"You are a personal assistant running inside OpenClaw."` |

子 Agent 使用 `minimal` 模式可以大幅减少 prompt token 开销。

---

## 3. Skill 系统

### 3.1 Skill 的本质

Skill 是**一个目录，内含一个 `SKILL.md` 文件**（可选附带 scripts/references/assets 子目录）。

`SKILL.md` 结构分两部分：

1. **YAML Frontmatter**：元数据，Agent 每轮都会扫描其中的 `name` 和 `description`
2. **Markdown 正文**：执行指南，仅在 Agent 选中该 Skill 后才通过 `read` 工具加载

这种设计实现了**按需延迟加载**：每轮 System Prompt 只注入简短的描述列表（约 100 words/skill），选中后再 `read` 完整正文（可达数千词）。

### 3.2 SKILL.md 完整格式规范

```yaml
---
name: skill-name           # 必填，Skill 唯一标识
description: "..."         # 必填，触发条件描述（详见下方说明）

# 以下为可选字段
homepage: https://...      # 文档链接
user-invocable: true       # 是否可由用户通过 /命令 触发（默认 true）
disable-model-invocation: false  # 若 true，不出现在 <available_skills> 中（Agent 无法自主调用）

metadata:
  openclaw:
    emoji: "🌤️"           # 展示用 emoji
    always: false          # 若 true，始终注入，不受过滤影响（常驻上下文）
    skillKey: "..."        # 去重用的 key 覆盖
    primaryEnv: "..."      # 该 Skill 主要依赖的环境变量名
    os: ["darwin"]         # 操作系统限制
    requires:
      bins: ["curl"]       # 所有二进制均需存在
      anyBins: ["gh", "git"] # 任意一个存在即可
      env: ["GITHUB_TOKEN"] # 需要的环境变量
      config: ["some.key"]  # 需要的配置 key
    install:               # 自动安装规格
      - id: brew
        kind: brew         # brew | node | go | uv | download
        formula: gh
        bins: ["gh"]
        label: "Install GitHub CLI (brew)"
---
```

### 3.3 description 字段的编写规范

`description` 是 Skill 触发的核心依据，Agent 靠它决定"用不用这个 Skill"。官方规范：

- 说明 Skill **做什么**
- 明确列出 **Use when**（触发场景）
- 明确列出 **NOT for**（反触发场景）
- 包含用户可能使用的自然语言短语

示例（weather skill）：

```text
"Get current weather and forecasts via wttr.in or Open-Meteo.
Use when: user asks about weather, temperature, or forecasts for any location.
NOT for: historical weather data, severe weather alerts, or detailed meteorological analysis.
No API key needed."
```

示例（coding-agent skill）：

```text
"Delegate coding tasks to Codex, Claude Code, or Pi agents via background process.
Use when: (1) building/creating new features or apps, (2) reviewing PRs (spawn in temp dir),
(3) refactoring large codebases, (4) iterative coding that needs file exploration.
NOT for: simple one-liner fixes (just edit), reading code (use read tool),
thread-bound ACP harness requests in chat..."
```

### 3.4 Skill 正文（Markdown Body）的设计约定

正文只在选中后加载，因此可以较为详细。官方推荐结构：

```markdown
# Skill Name

## 核心工作流 / 命令示例

## 注意事项 / Rules

## 高级用法（可拆到 references/ 子文件）
```

官方建议正文保持在 **500 行以内**，超出部分拆到 `references/` 子目录并在正文中加引用链接。

正文中不建议写"When to Use"章节，因为此时 Skill 已被选中，这部分信息对触发无帮助，且占用宝贵的 context 空间。

### 3.5 Skill 目录结构（完整形式）

```text
skill-name/
├── SKILL.md              # 必须
├── scripts/              # 可执行脚本（确定性高的操作）
│   └── rotate_pdf.py
├── references/           # 参考文档（按需 read 加载，不预载入 context）
│   ├── finance.md
│   └── api_docs.md
└── assets/               # 输出资产（模板、图片等，不加载入 context）
    └── template.html
```

**三级渐进式加载（Progressive Disclosure）**：

| 层级 | 内容 | 加载时机 | Token 开销 |
| --- | --- | --- | --- |
| 1. Metadata | name + description | 每轮始终在 context | ~100 words/skill |
| 2. SKILL.md 正文 | 执行指南 | Skill 触发后主动 read | < 5k words |
| 3. Bundled Resources | scripts/references/assets | 按需由 Agent 决定 read | 无上限（脚本可直接执行而不 read） |

---

## 4. Skill 注入机制（System Prompt）

### 4.1 Skills Section 的完整内容

来源：`src/agents/system-prompt.ts` → `buildSkillsSection()`

注入到 System Prompt 的内容如下（含 Agent 遵循的强制规则）：

```text
## Skills (mandatory)
Before replying: scan <available_skills> <description> entries.
- If exactly one skill clearly applies: read its SKILL.md at <location> with `read`, then follow it.
- If multiple could apply: choose the most specific one, then read/follow it.
- If none clearly apply: do not read any SKILL.md.
Constraints: never read more than one skill up front; only read after selecting.
- When a skill drives external API writes, assume rate limits: prefer fewer larger writes,
  avoid tight one-item loops, serialize bursts when possible, and respect 429/Retry-After.

<available_skills>
  <skill name="weather" location="~/.openclaw/skills/weather/SKILL.md">
    <description>Get current weather and forecasts...</description>
  </skill>
  <skill name="github" location="~/.openclaw/skills/github/SKILL.md">
    <description>GitHub operations via `gh` CLI...</description>
  </skill>
  ...
</available_skills>
```

关键设计决策：

- `<available_skills>` 只包含 `name`、`location`、`description` 三个字段，其余元数据不进入 prompt
- 路径统一压缩为 `~/` 格式，节省约 400–600 tokens
- **强制规则**：每轮只允许 read 一个 SKILL.md，且必须先选择再 read（懒加载）

### 4.2 Skill 发现与加载优先级

来源：`src/agents/skills/workspace.ts` → `loadSkillEntries()`

优先级从低到高（后者覆盖前者，支持项目级定制）：

1. `skills.load.extraDirs` 配置项（+ 插件 skill 目录）
2. 内置 Skill（随 OpenClaw 二进制打包的官方 skill）
3. 托管 Skill（`~/.openclaw/skills/`）
4. `~/.agents/skills/`（个人全局 skill）
5. `<workspace>/.agents/skills/`（项目级 Agent skill）
6. `<workspace>/skills/`（项目级 skill）

同名 Skill 后者覆盖前者，实现项目级定制化覆盖。

### 4.3 Skill 过滤条件

来源：`filterSkillEntries()` + `shouldIncludeSkill()`

```text
1. OS 限制：metadata.openclaw.os 不匹配当前系统 → 排除
2. 二进制依赖：requires.bins 中有不存在的命令 → 排除
3. 环境变量：requires.env 中有未设置的变量 → 排除
4. 配置 key：requires.config 中有缺失的配置 → 排除
5. Agent 白名单：agents.skillFilter 配置了允许列表 → 只保留列表内的 Skill
6. disable-model-invocation: true → 从 <available_skills> 中排除（但 user-invocable 仍可手动触发）
7. always: true → 跳过以上所有过滤，始终包含
```

### 4.4 数量与大小限制

| 配置参数 | 默认值 |
| --- | --- |
| `maxCandidatesPerRoot` | 300 |
| `maxSkillsLoadedPerSource` | 200 |
| `maxSkillsInPrompt` | 150 |
| `maxSkillsPromptChars` | 30,000 |
| `maxSkillFileBytes` | 256,000 |

---

## 5. TypeScript 类型定义

来源：`src/agents/skills/types.ts`

```typescript
// Skill 安装规格（自动化安装依赖）
type SkillInstallSpec = {
  id?: string;
  kind: "brew" | "node" | "go" | "uv" | "download";
  label?: string;
  bins?: string[];
  os?: string[];
  formula?: string;       // brew
  package?: string;       // node / apt
  module?: string;        // node
  url?: string;           // download
  archive?: string;
  extract?: boolean;
  stripComponents?: number;
  targetDir?: string;
};

// OpenClaw 专属元数据
type OpenClawSkillMetadata = {
  always?: boolean;           // 始终注入，不受过滤影响
  skillKey?: string;          // 去重用的 key 覆盖
  primaryEnv?: string;        // 主要依赖的环境变量名
  emoji?: string;
  homepage?: string;
  os?: string[];
  requires?: {
    bins?: string[];           // 全部需存在
    anyBins?: string[];        // 任意一个存在即可
    env?: string[];            // 需要的环境变量
    config?: string[];         // 需要的配置 key
  };
  install?: SkillInstallSpec[];
};

// 调用策略
type SkillInvocationPolicy = {
  userInvocable: boolean;           // 用户可通过 /命令 触发
  disableModelInvocation: boolean;  // Agent 无法自主调用
};

// 解析后的 Skill 条目（内部表示）
type SkillEntry = {
  skill: Skill;                     // 来自 @mariozechner/pi-coding-agent
  frontmatter: Record<string, string>;
  metadata?: OpenClawSkillMetadata;
  invocation?: SkillInvocationPolicy;
};

// 注入 System Prompt 的快照
type SkillSnapshot = {
  prompt: string;                   // 格式化后的 <available_skills> 块
  skills: Array<{
    name: string;
    primaryEnv?: string;
    requiredEnv?: string[];
  }>;
  skillFilter?: string[];           // Agent 级过滤白名单
  resolvedSkills?: Skill[];
  version?: number;
};
```

---

## 6. 内置 Skill 目录

截至 2026-03 main 分支，官方内置 skill 共 50+ 个：

```text
1password        apple-notes      apple-reminders  bear-notes
blogwatcher      blucli           bluebubbles      camsnap
canvas           clawhub          coding-agent     discord
eightctl         gemini           gh-issues        github
gog              goplaces         healthcheck      himalaya
imsg             mcporter         model-usage      nano-banana-pro
nano-pdf         notion           obsidian         openai-image-gen
openai-whisper   openai-whisper-api  openhue       oracle
ordercli         peekaboo         sag              session-logs
sherpa-onnx-tts  skill-creator    slack            songsee
sonoscli         spotify-player   summarize        things-mac
tmux             trello           video-frames     voice-call
wacli            weather          xurl
```

与 Agent 编排直接相关的关键 skill：

| Skill | 作用 |
| --- | --- |
| `coding-agent` | 委派编码任务给 Codex / Claude Code / Pi / OpenCode |
| `skill-creator` | 创建、编辑、审计新 Skill（自举式元 Skill） |
| `session-logs` | 查看 Pi 会话日志 |

---

## 7. 子 Agent 委派：sessions_spawn 工具

来源：`src/agents/tools/sessions-spawn-tool.ts`

主 Agent 通过 `sessions_spawn` 工具将复杂任务委派给独立的子 Agent：

### 7.1 参数说明

| 参数                   | 类型                         | 说明                                                           |
| -------------------- | -------------------------- | ------------------------------------------------------------ |
| `task`               | string（必填）                 | 子任务描述                                                        |
| `runtime`            | `"subagent"` \| `"acp"`    | subagent = 默认子 Agent；acp = 接入 Codex/Claude Code/Pi 等编码 Agent |
| `agentId`            | string                     | 指定使用哪个已配置的 Agent                                             |
| `mode`               | `"run"` \| `"session"`     | run = 一次性执行后退出；session = 持久线程                                |
| `model`              | string                     | 子 Agent 的模型覆盖                                                |
| `thinking`           | string                     | 思考等级覆盖                                                       |
| `runTimeoutSeconds`  | number                     | 超时时间（秒）                                                      |
| `thread`             | boolean                    | 是否在线程中运行（Discord 等渠道的线程模式）                                   |
| `sandbox`            | `"inherit"` \| `"require"` | 沙箱策略                                                         |
| `cleanup`            | `"keep"` \| `"delete"`     | 任务结束后是否清理子 Agent                                             |
| `attachments`        | array                      | 快照式文件附件，子 Agent 启动时注入（最多 50 个）                               |
| `attachAs.mountPath` | string                     | 子 Agent 视角的附件路径                                              |

### 7.2 完成通知：推送式（非轮询）

这是设计亮点之一。System Prompt 明确规定：

```text
父 Agent 在 spawn 子 Agent 后：
- 不得轮询 sessions_list / sessions_history
- 不得 exec sleep 等待
- 子 Agent 完成后，系统以"用户消息"形式自动推送完成事件给父 Agent
- 父 Agent 追踪"期待的子 Agent key 列表"，收到所有完成事件后才给出最终回复
```

这种推送式设计避免了父 Agent 在等待期间消耗 context 或产生无意义轮询。

### 7.3 子 Agent 深度限制

通过 `DEFAULT_SUBAGENT_MAX_SPAWN_DEPTH`（`src/config/agent-limits.ts`）配置最大嵌套层级，防止无限递归委派。

### 7.4 ACP 模式（对接外部编码 Agent）

`runtime="acp"` 时，会通过 ACP（Agent Coding Protocol）启动外部编码 Agent：

```text
sessions_spawn(
  task="重构认证模块，移除冗余的 JWT 解码逻辑",
  runtime="acp",
  agentId="claude-code",
  thread=true,
  mode="session"
)
```

子 Agent 的输出可通过 `streamTo: "parent"` 实时回传给父 Agent 展示。

### 7.5 其他会话间通信工具

| 工具 | 作用 |
| --- | --- |
| `sessions_list` | 列出所有活跃会话及元数据 |
| `sessions_history` | 获取指定会话的完整消息记录 |
| `sessions_send` | 向另一会话发送消息（支持 ping-pong 模式） |
| `subagents` | 列出/控制/终止当前请求者的所有子 Agent |
| `agents_list` | 列出 sessions_spawn 可用的 agentId |

---

## 8. Bootstrap 文件：固定上下文注入

来源：`src/agents/bootstrap-files.ts` → `resolveBootstrapFilesForRun()`

每轮执行前，系统自动扫描 Workspace 目录，将以下文件内容注入 System Prompt：

| 文件名 | 作用 |
| --- | --- |
| `AGENTS.md` | Agent 行为规范、项目约定（与 CLAUDE.md 等价，需同时保持软链接） |
| `SOUL.md` | Agent 人格与身份定义 |
| `TOOLS.md` | 外部工具使用提示（不控制工具可用性，仅为指南） |
| `IDENTITY.md` | 身份覆盖 |
| `USER.md` | 用户个人上下文 |
| `HEARTBEAT.md` | 定时任务专用上下文 |
| `BOOTSTRAP.md` | 通用启动上下文 |
| `MEMORY.md` / `memory.md` | 持久记忆文件 |

约束：每个文件最大 2MB，支持按 sessionKey 过滤（不同类型的会话注入不同的 bootstrap 文件集）。

---

## 9. 记忆系统

### 9.1 Memory Recall Section（System Prompt 内容）

来源：`src/agents/system-prompt.ts` → `buildMemorySection()`

```text
## Memory Recall
Before answering anything about prior work, decisions, dates, people, preferences, or todos:
run memory_search on MEMORY.md + memory/*.md;
then use memory_get to pull only the needed lines.
If low confidence after search, say you checked.

Citations: include Source: <path#line> when it helps the user verify memory snippets.
```

### 9.2 记忆工具

| 工具 | 作用 |
| --- | --- |
| `memory_search` | 在 MEMORY.md 及 memory/*.md 中语义搜索 |
| `memory_get` | 按行号精准读取记忆片段 |

### 9.3 会话存储与保护

- 会话记录存储为 JSONL：`~/.openclaw/agents/<agentId>/sessions/*.jsonl`
- 写锁保护（`session-write-lock.ts`）：防止多 Agent 并发写冲突
- 损坏修复（`session-transcript-repair.ts` + `session-file-repair.ts`）：启动时自动检测并修复

### 9.4 Context 上下文压缩

来源：`src/agents/compaction.ts`

当 context 接近 window 上限时，系统自动触发压缩：

1. 生成当前会话的文字摘要
2. 用摘要替换早期历史，重新开始会话
3. 对用户透明，不影响正在进行的任务

---

## 10. 工具系统

### 10.1 工具接口定义（AnyAgentTool）

来源：`src/agents/tools/common.ts`

```typescript
type AnyAgentTool = {
  name: string;       // 工具名，LLM 调用时使用（大小写敏感）
  label: string;      // 人类可读标签
  description: string; // 向 LLM 展示的描述
  parameters: TSchema; // TypeBox schema，用于参数校验
  execute: (toolCallId: string, args: unknown) => Promise<unknown>;
};
```

### 10.2 内置工具全集

**文件操作（来自 @mariozechner/pi-coding-agent）：**

```text
read / write / edit / apply_patch / grep / find / ls
```

**Shell 操作：**

```text
exec（支持 PTY、后台、超时）
process（管理后台 exec 会话：list / poll / log / write / submit / kill）
```

**网络：**

```text
web_search（Brave API）
web_fetch（URL 内容抓取）
```

**渠道与 UI：**

```text
browser / canvas / nodes / message / tts / image / pdf
```

**Agent 编排：**

```text
sessions_spawn / sessions_list / sessions_history / sessions_send
subagents / session_status / agents_list / gateway
```

**调度：**

```text
cron（管理定时任务和唤醒事件）
```

### 10.3 工具 Schema 规范（防止 validator 报错）

官方 AGENTS.md 中明确的 TypeBox Schema 限制：

```text
❌ 禁止：Type.Union / anyOf / oneOf / allOf
✅ 替代：stringEnum / optionalStringEnum（Type.Unsafe 枚举）

❌ 禁止：... | null
✅ 替代：Type.Optional(...)

❌ 禁止：format 作为属性名（部分 validator 将其视为保留字）

✅ 要求：顶层 schema 必须是 type: "object" + properties
```

### 10.4 工具执行流水线

来源：`src/agents/tool-policy-pipeline.ts`

```text
LLM 输出工具调用块
    ↓
normalizeToolCallNameForDispatch()（大小写规范化、前缀剥离）
    ↓
allowlist / denylist 过滤
    ↓
sandbox 限制检查
    ↓
before-call hooks
    ↓
tool.execute()
    ↓
结果追加到会话 transcript
    ↓
继续 LLM 循环
```

---

## 11. 多 Agent 路由

### 11.1 渠道路由

在 `openclaw.json` 的 `agents` 配置中，可以将不同渠道/账户/联系人路由到不同的 Agent：

```json
{
  "agents": {
    "work": {
      "workspace": "~/work-workspace",
      "channels": { "slack": { "allowFrom": ["@team"] } }
    },
    "personal": {
      "workspace": "~/personal-workspace",
      "channels": { "telegram": { "allowFrom": ["personal-number"] } }
    }
  }
}
```

每个 Agent 有独立的 Workspace + 独立的会话隔离。

### 11.2 会话隔离维度

| 维度 | 隔离方式 |
| --- | --- |
| 渠道 | 按 channel 类型路由到不同 Agent |
| 账户/联系人 | 按 peer / account 过滤 |
| 会话类型 | main（1:1）/ group（群组）/ subagent（子任务） |

---

## 12. 实际 Skill 示例

### 12.1 weather（极简 skill）

```yaml
---
name: weather
description: "Get current weather and forecasts via wttr.in or Open-Meteo.
  Use when: user asks about weather, temperature, or forecasts for any location.
  NOT for: historical weather data, severe weather alerts, or detailed meteorological analysis.
  No API key needed."
homepage: https://wttr.in/:help
metadata: { "openclaw": { "emoji": "🌤️", "requires": { "bins": ["curl"] } } }
---

# Weather Skill

## Commands

### Current Weather
\`\`\`bash
curl "wttr.in/London?format=3"
\`\`\`

### 3-Day Forecast
\`\`\`bash
curl "wttr.in/London"
\`\`\`
```

### 12.2 coding-agent（复杂 skill，含 PTY 与后台执行模式）

```yaml
---
name: coding-agent
description: 'Delegate coding tasks to Codex, Claude Code, or Pi agents via background process.
  Use when: (1) building/creating new features or apps, (2) reviewing PRs (spawn in temp dir),
  (3) refactoring large codebases, (4) iterative coding that needs file exploration.
  NOT for: simple one-liner fixes (just edit), reading code (use read tool),
  thread-bound ACP harness requests in chat (use sessions_spawn with runtime:"acp" instead),
  or any work in ~/openclaw workspace.'
metadata:
  openclaw:
    emoji: "🧩"
    requires:
      anyBins: ["claude", "codex", "opencode", "pi"]
---
```

正文核心内容：

- 不同编码 Agent 的执行模式（Codex/Pi/OpenCode 需要 `pty:true`；Claude Code 用 `--print --permission-mode bypassPermissions`）
- 后台执行模式：`bash background:true` + `process action:log/poll` 监控
- 平行 worktree 修复多个 Issue 的批量模式
- 完成通知：任务结束后执行 `openclaw system event` 唤醒父 Agent

### 12.3 skill-creator（自举式元 Skill）

```yaml
---
name: skill-creator
description: Create, edit, improve, or audit AgentSkills.
  Use when creating a new skill from scratch or when asked to improve, review,
  audit, tidy up, or clean up an existing skill or SKILL.md file.
  Also use when editing or restructuring a skill directory.
  Triggers on: "create a skill", "author a skill", "tidy up a skill",
  "improve this skill", "review the skill", "audit the skill".
---
```

正文涵盖：Skill 创建的六步流程（理解需求 → 规划资源 → 初始化目录 → 编写内容 → 打包发布 → 迭代）。

---

## 13. 与本项目的关联分析

### 13.1 核心对应关系

| OpenClaw 机制 | 在本项目的对应 |
| --- | --- |
| 一个 Pi Agent + Skill 列表 | 一个主 Agent + 资产/损害/威胁/攻击树等 Skill |
| `description` 驱动 Skill 选择 | 主 Agent 靠意图识别自动路由到相应领域 Skill |
| SKILL.md 正文作为执行指南 | 各领域的 System Prompt 内容迁移进 Skill 文件 |
| `always: true` 常驻 Skill | 项目背景、CAL 规则表、ISO/SAE 21434 标准等公共上下文做成常驻 Skill |
| `sessions_spawn` 委派子 Agent | 批量攻击树生成的 Worker Pool 可转为子 Agent 委派 |
| `minimal` prompt 模式（子 Agent） | 子 Agent 减少 prompt token 开销 |
| Bootstrap 文件（AGENTS.md） | 业务规则、项目标准注入（类比当前各 Agent 的 System Prompt 公共部分） |
| Memory（MEMORY.md） | 替代或补充现有 InMemory / SmartMemory |
| `disable-model-invocation: true` | 对确认类操作（如 AwaitingConfirmation 流程）限制 Agent 自主触发 |

### 13.2 可借鉴的关键设计

#### 1. description 的"正向 + 反向"触发描述

明确写 `Use when:` 和 `NOT for:` 两部分，直接决定 Agent 的 Skill 选择准确率。

#### 2. 三级渐进式加载

每轮只加载 description（~100 words），选中后才 read 正文；大型业务规则（如威胁场景的 R155 映射表）移到 `references/` 子文件，只在需要时加载。

#### 3. 推送式子 Agent 完成通知

父 Agent 不轮询，等待系统推送——适合攻击树批量生成场景（当前是 Worker Pool + SSE 轮询）。

#### 4. `user-invocable` vs `disable-model-invocation` 分离

可以有只允许用户手动触发、不允许 Agent 自主调用的 Skill，对确认类操作有借鉴价值。

#### 5. Skill 覆盖机制（项目级 > 全局）

workspace/skills/ 的 Skill 覆盖全局同名 Skill，适合为不同项目类型定制不同的业务规则。

### 13.3 需要适配的差异

| OpenClaw 假设 | 本项目实际情况 |
| --- | --- |
| Skill 通过 `read` 文件工具加载 | 需要实现等价的 Skill 加载机制（Go 实现，可嵌入为字符串资源） |
| 工具在本地运行（exec / read） | 本项目工具是数据库操作、RAG 检索、外部 API 调用 |
| 记忆基于 Markdown 文件 | 本项目有专门的 ILongTermMemory / SmartMemory / Neo4j |
| 单用户 personal assistant | 本项目是多用户 SaaS，需三维会话隔离（project + page + account） |
| Workspace 是文件系统目录 | 本项目的"工作空间"是数据库中的项目记录，没有文件系统对应物 |
| 50+ 通用 Skill，按需选用 | 本项目 Skill 数量少（4 个领域），但每个 Skill 的业务深度极高 |
