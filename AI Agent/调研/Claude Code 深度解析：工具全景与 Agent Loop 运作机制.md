# Claude Code 深度解析：工具全景与 Agent Loop 运作机制

**发布日期**: 2026年2月22日
**作者**: Manus AI

---

## 引言

随着大型语言模型（LLM）应用的演进，我们正从简单的聊天机器人（Chatbots）和僵化的工作流（Workflows）迈向第三个时代：**自主代理（Autonomous Agents）**。在这个新范式中，Anthropic 的 **Claude Code** 成为市场上首个大规模应用的典范，它代表了一种"模型驱动循环"（Model-driven Loop）的架构思想 [2]。与拥有数百个脆弱、特定集成（如 Jira 插件）的传统 Agent 不同，Claude Code 仅依赖一小套（约20个）强大的"能力原语"（Capability Primitives），如 `Bash`、`Grep` 和 `Edit`，通过组合这些基础工具来完成人类工程师可以执行的任何复杂工作流。

本报告旨在深入剖析 Claude Code 的两大核心支柱：其独特的 **Agent Loop 运作机制**以及其完整的**工具库**。通过对官方文档、社区逆向工程成果和 LLM 流量追踪分析的综合研究 [1] [2] [3]，我们将详细解释 Claude Code 如何思考、行动、观察和迭代，并逐一解析其工具箱中每个工具的设计目的、技术实现与具体使用场景。

---

## 第一部分：Agent Loop 运作机制——Claude Code 的"思考"引擎

Claude Code 的核心是一种被称为 **TAOR（Think-Act-Observe-Repeat）** 的模型驱动循环，但其实现远比一个简单的 `while` 循环复杂。整个架构围绕着一个核心理念：**模型是决策的"CEO"，而运行时（Harness）是执行的"身体"** [2]。这个循环并非一成不变，而是根据任务的复杂度和上下文的动态变化，融合了元数据生成、缓存预热、上下文压缩、规划与子任务分派等多种策略。

### 1.1 Agent Loop 的宏观流程

当用户发出一个请求时，Claude Code 的宏观流程可以概括为以下五个主要阶段 [3]：

**阶段一：元数据生成 (Metadata Generation)**。在主任务开始前，Claude Code 会调用一个轻量级、低成本的 LLM（如 Haiku 模型）来执行两个快速的元数据任务：为当前会话生成一个5-10词的标题，并判断用户的最新请求是否开启了一个新话题（如果是，则提取一个2-3词的标题）。这个阶段确保了会话的可追溯性和组织性。

**阶段二：缓存预热 (Cache Warm-up)**。几乎与元数据生成并行，系统会向重量级、高智能的 LLM（如 Opus 或 Sonnet 模型）发送一个包含完整工具列表的"虚拟"请求（例如，用户输入为 `count`，最大输出 token 为1）。此举的目的是预先填充模型的 KV 缓存，使得后续真正的、复杂的工具调用推理能够更快地进行，从而将这部分延迟"隐藏"在元数据生成的过程中。

**阶段三：执行 Agentic Loop (The Core Loop)**。这是任务执行的核心。主 Agent（通常由重量级 LLM 驱动）开始处理用户请求。它在一个循环中不断进行"思考 → 工具调用"的迭代，直到任务完成。如果任务需要，主 Agent 还可以通过 `Task` 工具分派出"子 Agent"来并行处理探索性或复杂的子任务。

**阶段四：结果总结与呈现 (Summarize and Present)**。当循环终止（即模型不再返回工具调用，而是生成纯文本响应）时，Agent 会总结其工作成果，并以清晰、简洁的自然语言形式呈现给用户。

**阶段五：生成后续建议 (Generate Suggestions)**。在某些情况下，Agent 还会根据已完成的任务，为用户提供下一步可能的操作建议，引导对话继续进行。

### 1.2 Agentic Loop 的微观运作：一次"思考-行动"迭代

Agentic Loop 的每一次迭代都遵循着一个严谨的"思考-行动-观察"模式，其核心是模型、工具和上下文之间的持续交互。这个循环会一直持续，直到模型的 `stop_reason` 不再是 `tool_use` 为止 [3]。

一个典型的迭代周期包含四个步骤。首先是**思考 (Think)**：LLM 接收到包含当前任务所需全部信息的上下文——系统提示、`CLAUDE.md` 文件内容、完整的消息历史（包含之前的思考、工具调用和结果）以及可用的工具列表。基于这些信息，模型在 `<thinking>` 标签中形成一个内部思考过程，决定下一步需要采取什么行动。例如："用户想让我添加调试打印。我需要先找到 `LoraConfig` 在哪里被创建和使用。"

其次是**行动 (Act)**：根据思考的结果，模型决定调用一个或多个工具。它会生成一个或多个 `tool_use` 的 JSON 块，其中包含工具名称（如 `Grep`）、唯一的调用 ID（如 `call_g7zm8nbi`）以及所需的参数（如 `pattern: "LoraConfig"`）。Claude Code 的一个显著特点是支持**并行工具调用**：如果多个工具的执行没有依赖关系，模型可以在一个响应中同时发出多个工具调用，以最大化效率。

然后是**观察 (Observe)**：Claude Code 的运行时（Harness）解析模型的响应，捕获 `tool_use` 请求，并在一个安全的沙箱环境中执行这些工具。执行完成后，工具的输出结果（无论是文件列表、代码片段还是命令执行的 stdout/stderr）会被捕获。

最后是**重复 (Repeat)**：运行时将上一步的工具输出结果打包成一个新的用户消息，格式为 `tool_result`，并附上对应的 `tool_use_id`，然后将这个结果连同整个更新后的消息历史再次发送给 LLM。LLM 在接收到新的观察结果后，开始新一轮的"思考-行动-观察"迭代，直到任务最终完成。

下面是一个典型的工具调用链示例，展示了 Agent 如何通过多次迭代完成一个"修复 bug"的任务：

```
用户: "修复这个 bug"
  → [Think] 我需要先找到相关代码
  → [Act]  Glob **/*.py                    → [Observe] 文件列表
  → [Act]  Grep "error_pattern"            → [Observe] 匹配的代码行
  → [Act]  Read /path/to/file.py           → [Observe] 文件完整内容
  → [Act]  Edit /path/to/file.py (修复)     → [Observe] 编辑成功
  → [Act]  Bash "pytest tests/"            → [Observe] 所有测试通过
  → [Result] "已修复 bug，所有测试通过。"
```

### 1.3 上下文管理：应对"上下文衰减"的艺术

LLM 的上下文窗口是其最宝贵的有限资源。随着对话轮次的增加，上下文会迅速膨胀，导致"**上下文衰减**"（Context Rot）——即模型在长上下文中检索和推理信息的能力下降 [1]。Claude Code 通过一套精密的上下文工程策略来应对这一挑战。

| 策略 | 实现机制 | 目的 |
| :--- | :--- | :--- |
| **自动上下文压缩** | 当对话历史接近上下文窗口限制时，系统会调用模型自身对之前的对话进行总结和压缩 [1]。 | 在保留关键决策和信息的同时，释放宝贵的 token 空间，防止"上下文遗忘"。 |
| **分层与持久化内存** | 通过 `CLAUDE.md` 文件实现。系统在每次会话开始时加载一个分层的内存结构，包括组织级、项目级、用户级和自动学习的偏好设置 [2]。 | 确保 Agent 在新会话中"记得"项目背景和用户偏好，避免从零开始。 |
| **子 Agent 上下文隔离** | 对于探索性强或计算密集型的任务，主 Agent 会通过 `Task` 工具派生一个专门的 `Explore` 子 Agent [3]。 | 将这些任务的上下文与主任务隔离，防止其大量的搜索和阅读操作"污染"主循环的上下文窗口。子 Agent 完成后仅返回一个简洁的最终报告。 |
| **高效的工具设计** | 工具被设计为返回 token 高效的信息。例如，`Grep` 工具默认只返回匹配的文件列表（`files_with_matches`），而不是完整的匹配内容。 | 减少工具输出占用的上下文空间，使更多空间留给思考和决策。 |
| **TODO 列表注入** | 在每次工具调用后，系统消息会自动注入当前的 TODO 列表状态 [4]。 | 防止模型在长对话中"忘记"其目标和进度，保持任务聚焦。 |

### 1.4 LLM 分层调度策略

Claude Code 并非对所有任务都使用同一个模型，而是采用了一种**分层调度策略**来平衡性能和成本 [3]：

| LLM 层级 | 典型模型 | 使用场景 |
| :--- | :--- | :--- |
| **重量级 (Heavyweight)** | Opus 4.5 / Sonnet | 主 Agent 的核心推理、复杂的代码编辑和决策制定。 |
| **轻量级 (Lightweight)** | Haiku 4.5 | 元数据生成（会话标题、话题检测）、`Explore` 类型的子 Agent、简单的信息提取任务。 |

这种策略使得 Claude Code 能够在保持高质量推理的同时，显著降低 API 调用的成本和延迟。用户在使用 `Task` 工具时，甚至可以通过 `model` 参数手动指定子 Agent 使用的模型层级。

### 1.5 权限与安全系统

Claude Code 围绕工具调用建立了一套多层次的权限和安全机制 [2]，确保 Agent 的行为始终在用户的控制之下。

**工具级权限分类**：每个工具都有明确的权限标记。`Read`、`Glob`、`Grep` 等只读工具不需要权限确认；而 `Bash`、`Write`、`Edit`、`WebFetch` 等涉及修改或外部访问的工具则需要用户批准。

**Bash 命令风险分级**：`Bash` 工具内部实现了一个静态分析层，对每条命令进行风险分级。安全的只读命令（如 `ls`, `cat`, `git status`）可以自动执行，而具有潜在风险的命令（如 `rm -rf`, `git push --force`）则会被拦截并请求用户确认。

**计划模式 (Plan Mode)**：对于复杂任务，Agent 可以进入"计划模式"，先制定详细的执行计划并通过 `ExitPlanMode` 工具提交给用户审批。在此过程中，Agent 会以"语义描述"的方式预先声明其需要的权限（如 `"run tests"` 而非具体的 `npm test` 命令），使权限请求更易于人类理解。

**Hooks 机制**：用户可以配置确定性的脚本钩子（Hooks），在特定的生命周期事件（如文件保存后自动 lint、shell 命令执行前审计）中触发，为 Agent 的行为增加一层额外的、不依赖 LLM 的保障。

### 1.6 循环终止条件

Agent Loop 在以下四种情况下会终止：

1. **自然完成**：模型生成纯文本响应而不包含任何工具调用，表示任务已完成。
2. **最大轮次限制**：达到预设的最大工具调用轮次，防止无限循环（"Runaway Loops"）。
3. **用户中断**：用户通过 `Ctrl+C` 或 `Escape` 主动中断 Agent 的执行。
4. **错误/超时**：工具执行过程中发生不可恢复的错误或超时，Agent 可能会尝试重试或向用户报告问题。

---

## 第二部分：工具全景分析——Claude Code 的"行动"武器库

Claude Code 的工具集遵循"少即是多"的原则，专注于提供基础、通用但功能强大的能力。根据官方文档（v2.1.50）和逆向工程分析 [5] [6]，其完整的工具库包含约 **20 个核心内置工具**，可分为七大类别。下表提供了一个全局概览：

| 类别 | 工具 | 是否需要权限 | 一句话定位 |
| :--- | :--- | :---: | :--- |
| **文件导航** | `ls`, `Glob` | 否 | 浏览和发现项目文件结构 |
| **文件读写** | `Read`, `Write`, `Edit`, `NotebookEdit` | Read否/其余是 | 读取、创建和精确修改代码文件 |
| **代码检索** | `Grep` | 否 | 在代码库中进行高效的正则搜索 |
| **终端执行** | `Bash`, `TaskOutput`, `KillShell` | Bash是/其余否 | 执行任意 shell 命令并管理后台进程 |
| **规划与交互** | `TodoWrite`, `AskUserQuestion`, `ExitPlanMode` | ExitPlanMode是/其余否 | 任务规划、进度跟踪和用户沟通 |
| **子 Agent 与任务** | `Task`, `TaskGet`, `TaskList`, `TaskUpdate` | Task是/其余否 | 委派子任务、查询和管理任务状态 |
| **Web 与外部** | `WebFetch`, `WebSearch`, `MCPSearch`, `LSP`, `Skill` | 大部分是 | 访问外部信息、代码智能和扩展能力 |

### 2.1 文件系统与导航 (Filesystem & Navigation)

这是 Agent 与本地开发环境交互的基础，使其能够像人类开发者一样浏览和理解项目结构。

#### `ls` — 目录列表

`ls` 工具列出指定目录的内容，功能上等同于 `ls -F` 命令，会通过在文件名后附加特殊字符来标示文件类型（例如，`/` 表示目录，`*` 表示可执行文件）。它接受两个参数：`path`（目标目录路径，省略则默认为当前工作目录）和 `recursive`（是否递归列出子目录，默认 `false`）。

`ls` 是 Agent 探索未知代码库的第一个工具，通常用于在任务开始时快速了解项目结构、寻找配置文件（如 `package.json`、`Dockerfile`），或验证文件操作是否成功。系统提示词强调，在不确定文件确切位置时，应首先使用 `ls` 或 `Glob` 来定位，而不是盲目地尝试 `Read`。

#### `Glob` — 通配符文件查找

`Glob` 使用类似 shell 的通配符模式在文件系统中查找匹配的文件和目录路径。其必需参数 `pattern` 支持标准的 glob 语法，例如 `**/*.py`（查找所有 Python 文件）或 `src/**/*.{js,ts}`（查找 src 目录下所有的 JS 和 TS 文件）。可选参数 `path` 指定搜索的起始目录。

`Glob` 在系统提示中被定位为代码库探索的关键工具，尤其适用于需要对某一类文件进行批量操作的场景。例如，在开始重构前找到所有的 `.tsx` 组件，或查找命名模式相似的文件（如 `user-*.service.ts`）。它弥补了 `ls` 功能相对单一的不足，提供了更灵活的文件发现能力。

### 2.2 文件内容读写 (File Content I/O)

在定位到文件后，Agent 需要读取其内容以理解代码，并写入新内容或修改现有内容以完成任务。

#### `Read` — 文件读取（多模态）

`Read` 从本地文件系统读取一个文件的内容。这是一个**多模态工具**，不仅能读取文本文件，还能"查看"图片（PNG、JPG 等）、PDF 文件和 Jupyter Notebook（`.ipynb`）。对于文本文件，它返回带行号的内容（类似 `cat -n`），默认读取前 2000 行，超过 2000 字符的行会被截断。可选参数 `offset` 和 `limit` 允许分块读取大文件。

`Read` 是使用频率最高的工具之一。典型场景包括：在 `Grep` 或 `Glob` 找到相关文件后读取其完整内容进行深入分析；查看用户提供的截图以诊断问题；分析 PDF 文档中的需求规范；审查 Jupyter Notebook 中的代码和可视化结果。系统提示词鼓励 Agent "大胆地并行读取多个可能相关的文件"，以加速上下文收集过程。

#### `Write` — 文件写入/创建

`Write` 将指定内容完全覆盖写入一个文件。如果文件不存在，则会创建该文件。它接受两个必需参数：`file_path`（绝对路径）和 `content`（要写入的完整内容）。

由于 `Write` 是一个"破坏性"操作（覆盖全部内容），系统提示词指导 Agent 在进行大规模修改或创建新文件时使用此工具，而对于小范围的精确修改，则优先使用 `Edit`。一个重要的安全机制是：**系统强制要求在执行 `Write` 之前必须先 `Read` 该文件**（如果文件已存在），以确保 Agent 了解文件的当前状态，避免意外覆盖重要内容 [5]。

#### `Edit` — 精确编辑（查找与替换）

`Edit` 对文件进行精确的、基于查找和替换的行级编辑。这是实现"外科手术式"代码修改的关键工具，也是比 `Write` 更安全、更受推荐的修改方式。它接受 `file_path` 和一个 `edits` 数组，每个编辑操作包含 `find`（要查找的精确文本）和 `replace`（替换后的文本）。

`Edit` 的设计体现了对安全性和可追溯性的重视。它强制 Agent 明确指定要查找的原始内容和替换后的新内容，使变更意图非常清晰。一个重要的约束是：`find` 中的字符串必须在文件中是**唯一匹配**的（除非使用 `replace_all` 标志），这防止了意外的批量替换。与 `Write` 类似，**系统也强制要求在 `Edit` 前先 `Read` 文件** [5]。

#### `NotebookEdit` — Jupyter Notebook 编辑

`NotebookEdit` 专门用于编辑 Jupyter Notebook（`.ipynb`）文件中的单元格。它支持三种操作：`replace`（替换指定单元格的内容）、`insert`（在指定位置插入新单元格）和 `delete`（删除指定单元格）。单元格通过 0 索引的 `cell_number` 来定位。

此工具的存在反映了 Claude Code 对数据科学和机器学习工作流的重视。由于 Notebook 文件的 JSON 结构与普通文本文件不同，使用通用的 `Edit` 或 `Write` 工具来修改它们容易出错，因此需要一个专门的工具来安全地操作其单元格结构。

### 2.3 代码检索 (Code Search)

#### `Grep` — 正则表达式代码搜索

`Grep` 是一个基于 `ripgrep` 的强大代码内容搜索引擎，支持完整的正则表达式语法和多种输出模式。其必需参数 `pattern` 接受正则表达式（如 `"log.*Error"`, `"function\\s+\\w+"`）。

`Grep` 提供了丰富的参数来精确控制搜索行为：

| 参数 | 类型 | 描述 |
| :--- | :--- | :--- |
| `pattern` | string | **必需**。正则表达式搜索模式。 |
| `path` | string | 搜索的文件或目录，默认为当前工作目录。 |
| `glob` | string | 文件过滤的 glob 模式，如 `"*.js"`, `"*.{ts,tsx}"`。 |
| `output_mode` | enum | `"content"` (匹配行+上下文), `"files_with_matches"` (仅文件名，**默认**), `"count"` (匹配计数)。 |
| `-A`, `-B`, `-C` | number | `content` 模式下，显示匹配行之后/之前/周围的上下文行数。 |
| `-i` | boolean | 大小写不敏感搜索。 |
| `type` | string | 按文件类型过滤（如 `js`, `py`, `rust`），比 `glob` 更高效。 |
| `multiline` | boolean | 启用跨行匹配模式。 |
| `head_limit` | number | 限制输出的前 N 行/条目。 |

系统提示词明确指出："**永远使用 `Grep` 工具进行搜索任务，绝不直接调用 `grep` 或 `rg` 作为 Bash 命令**"。这是因为 `Grep` 工具经过了专门的优化，能够正确处理权限和访问问题。其默认的 `files_with_matches` 输出模式也体现了对上下文 token 的节约——先找到文件，再按需 `Read`。

### 2.4 终端与执行 (Terminal & Execution)

#### `Bash` — Shell 命令执行

`Bash` 在一个沙箱化的 shell 环境中执行任意的 shell 命令。这是 Agent 与系统交互的"瑞士军刀"，提供了几乎无限的扩展能力。它接受必需参数 `command` 和可选参数 `timeout`（默认 2 分钟，最大 10 分钟）。

`Bash` 的使用场景极为广泛：运行构建脚本（`npm run build`）、测试套件（`pytest`）、代码格式化工具（`prettier --write .`）；使用 `git` 进行版本控制操作；安装项目依赖；执行数据库迁移；启动开发服务器等。它还支持**后台执行**（通过 `&` 运算符），允许 Agent 启动长时间运行的进程（如开发服务器）而不阻塞主循环。

`Bash` 是最强大也最危险的工具，因此有严格的使用规则。系统提示词明确禁止使用 `Bash` 来执行文件操作（如 `cat`, `grep`, `find`, `sed`, `awk`），因为这些操作有专门的、更安全的工具（`Read`, `Grep`, `Glob`, `Edit`）来处理。此外，`Bash` 的输出被限制在约 30,000 字符以内，超出部分会被截断 [5]。

#### `TaskOutput` (原 `BashOutput`) — 获取后台任务输出

`TaskOutput` 用于检索后台运行的 Bash shell 或子 Agent 的输出。当 Agent 通过 `Bash` 启动了一个后台进程（如开发服务器）后，可以使用此工具来查看该进程的最新输出，而无需终止它。它支持增量获取和过滤功能。

此工具的典型场景是：启动一个开发服务器后，检查其启动日志是否正常；或在运行一个长时间的构建任务后，获取其最终输出。

#### `KillShell` — 终止后台 Shell

`KillShell` 通过指定的 Shell ID 终止一个正在运行的后台 Bash shell。这是管理后台进程生命周期的必要工具，确保 Agent 不会留下"僵尸"进程。

### 2.5 规划与用户交互 (Planning & User Interaction)

#### `TodoWrite` — 任务列表管理

`TodoWrite` 创建和更新一个结构化的 JSON 格式的任务列表。每个任务对象包含 `id`、`content`（任务描述）、`status`（`"not_started"`, `"in_progress"`, `"completed"`）和 `priority` 字段。一个重要的约束是：**任何时刻只能有一个任务处于 `in_progress` 状态** [5]，这强制 Agent 聚焦于当前步骤。

`TodoWrite` 是 Agent "思考"过程的外部化体现。在处理复杂任务时，Agent 会首先使用它将任务分解为具体步骤，然后在执行过程中动态更新状态。系统通过在每次工具调用后注入当前的 TODO 列表状态来提醒 Agent 不要"忘记"其目标 [4]，这是一种有效的上下文管理策略。在 UI 中，这些任务会渲染为交互式清单，增加了透明度。

#### `AskUserQuestion` — 用户问答

`AskUserQuestion` 向用户提出一个问题，并暂停执行以等待回答。它支持结构化的多选问题格式（1-4 个问题，每个问题 2-4 个选项），使用户能够快速做出选择 [5]。

此工具用于在信息不足时向用户澄清需求（如"您希望使用 OAuth 还是 JWT？"），或在遇到无法解决的错误时请求指导。系统提示词严格规定了其使用边界：Agent 不应使用它来问"这个计划可以吗？"或"我应该继续吗？"，因为这些是由 `ExitPlanMode` 工具处理的。

#### `ExitPlanMode` — 计划审批

`ExitPlanMode` 在"计划模式"下使用。当 Agent 完成了对任务的规划（通常写入一个计划文件）后，调用此工具向用户提交计划以供审批。其关键参数 `allowedPrompts` 是一个对象数组，声明了计划中需要执行的 `Bash` 命令的"语义描述"（例如 `{"tool": "Bash", "prompt": "run tests"}`）。

这是 Claude Code 权限系统的核心创新。它将权限请求从具体的命令（如 `npm test`）提升到了**语义层面**（如 `"run tests"`），使权限请求更易于人类理解和批准。系统提示词还强调权限应遵循最小权限原则：优先请求 `"read-only"`, `"local"`, `"non-destructive"` 的权限，避免请求过于宽泛的危险权限。

### 2.6 子 Agent 与任务管理 (Sub-agents & Task Management)

#### `Task` — 子 Agent 分派

`Task` 将一个定义好的子任务分派给一个专门的"子 Agent"来执行。这是 Claude Code 实现"受控并行"和上下文隔离的关键。其核心参数包括：

| 参数 | 类型 | 描述 |
| :--- | :--- | :--- |
| `subagent_type` | enum | 子 Agent 的类型：`Explore`（代码库探索，仅有 Glob/Grep/Read/Bash 工具）、通用型（拥有全部工具）等。 |
| `prompt` | string | **必需**。给子 Agent 的自然语言指令。 |
| `model` | enum | 指定子 Agent 使用的 LLM（`"sonnet"`, `"opus"`, `"haiku"`），允许成本和性能的权衡。 |

子 Agent 的设计是 Claude Code 架构的一大亮点 [2]。它们拥有自己的、更精简的系统提示和工具集，并且有**深度限制**（不能再派生自己的子 Agent），从而防止了"Agent 递归爆炸"。子 Agent 是**无状态的**——执行完毕后返回一个单一的最终报告，然后被销毁。这使得主 Agent 可以专注于核心逻辑，而将耗费上下文的探索性工作外包出去。

系统提示词中有一条关键规则："**当探索代码库以收集上下文或回答非针对特定文件/类/函数的问题时，必须使用 `Task` 工具配合 `subagent_type=Explore`，而不是直接运行搜索命令**" [3]。

#### `TaskGet` / `TaskList` / `TaskUpdate` — 任务状态管理

这三个工具构成了一个完整的任务管理 API：

`TaskGet` 用于检索特定任务的完整详情（包括其输出和状态）。`TaskList` 列出所有任务及其当前状态，提供全局视图。`TaskUpdate` 用于更新任务的状态、依赖关系、详细信息，或删除任务。

这些工具使得主 Agent 能够像一个"项目经理"一样，监控和协调多个并行运行的子 Agent 或后台任务，确保整体工作流的有序推进。

### 2.7 Web、代码智能与扩展 (Web, Code Intelligence & Extensions)

#### `WebFetch` — URL 内容获取

`WebFetch` 获取指定 URL 的网页内容，将 HTML 转换为 Markdown 格式，并使用一个小型快速模型进行处理。它内置了 15 分钟的缓存机制，避免对同一 URL 的重复请求。典型使用场景包括：访问 API 文档、阅读博客文章、获取 GitHub issue 的详细信息。

#### `WebSearch` — Web 搜索

`WebSearch` 使用搜索引擎查找与查询相关的信息，支持域名过滤（如仅搜索 `stackoverflow.com`）。查询字符串最少需要 2 个字符。此工具使 Agent 能够获取其内部知识库之外的最新信息，从而解决更广泛的问题。

#### `LSP` — 代码智能（语言服务器协议）

`LSP` 通过语言服务器协议（Language Server Protocol）提供代码智能能力。它在文件编辑后自动报告类型错误和警告，并支持多种导航操作：跳转到定义、查找引用、获取类型信息、列出符号、查找实现和追踪调用层次。此工具需要安装相应的代码智能插件及其语言服务器二进制文件。

`LSP` 的引入标志着 Claude Code 从"基于文本的代码理解"向"基于语义的代码理解"的演进。它使 Agent 能够像 IDE 一样理解代码的结构和类型关系，从而做出更精确的修改。

#### `MCPSearch` — MCP 工具搜索

`MCPSearch` 用于搜索和加载 MCP（Model Context Protocol）工具。MCP 是 Anthropic 推出的一个开放协议，为 AI Agent 提供了一个连接外部服务和工具的通用桥梁。通过 MCP，Claude Code 可以连接到数据库、API、第三方服务等，极大地扩展了其能力边界。

#### `Skill` — 用户自定义技能

`Skill` 用于在主对话中执行用户自定义的"技能"。技能是一种声明式的扩展机制，用户可以通过 `.claude/commands/` 目录下的 Markdown 文件定义自定义的工作流或指令集，而无需编写任何 TypeScript 或 Python 代码。这使得非工程师也能为 Claude Code 添加领域特定的能力。

---

## 第三部分：工具演进与设计哲学

### 3.1 工具命名的演进

通过对比早期版本（2025年4月）和当前版本（v2.1.50）的工具列表 [6]，我们可以观察到 Claude Code 工具命名的简化趋势：

| 早期名称 (2025.04) | 当前名称 (v2.1.50) | 变化说明 |
| :--- | :--- | :--- |
| `GlobTool` | `Glob` | 去掉 `Tool` 后缀，更简洁 |
| `GrepTool` | `Grep` | 同上 |
| `View` | `Read` | 语义更明确 |
| `dispatch_agent` | `Task` | 更通用的命名 |
| `WebFetchTool` | `WebFetch` | 去掉 `Tool` 后缀 |
| `ReadNotebook` | 合并入 `Read` | `Read` 成为多模态工具 |
| `NotebookEditCell` | `NotebookEdit` | 简化 |
| `BashOutput` | `TaskOutput` | 扩展为通用任务输出 |
| `BatchTool` | 移除（并行调用内置） | 并行工具调用成为原生能力 |

这一演进体现了 Anthropic 的设计哲学：**随着模型能力的增强，运行时（Harness）应该变得更薄** [2]。早期需要显式编排的功能（如 `BatchTool` 的并行执行）现在已经被模型的原生并行工具调用能力所取代。

### 3.2 核心设计原则

通过对 Claude Code 工具集的全面分析，我们可以总结出以下核心设计原则：

**原语优于集成 (Primitives over Integrations)**。Claude Code 不为 Jira、Slack、GitHub 等服务提供专门的工具。相反，它通过 `Bash`（可以调用 `gh` CLI、`curl` 等）和 `WebFetch` 来与这些服务交互。这种方式虽然不如专用集成方便，但提供了无限的灵活性和零维护成本。

**安全优于便利 (Safety over Convenience)**。`Read-before-Write/Edit` 的强制规则、`Bash` 命令的风险分级、`ExitPlanMode` 的语义权限模型——这些设计都在一定程度上牺牲了效率，但换来了更高的安全性和可控性。

**Token 效率优于信息完整 (Token Efficiency over Information Completeness)**。`Grep` 默认返回文件名而非内容、`Read` 限制 2000 行、`Bash` 输出限制 30K 字符——这些限制都是为了保护宝贵的上下文窗口空间。

**模型决策优于硬编码逻辑 (Model Decision over Hardcoded Logic)**。运行时是一个"哑循环"，所有关于"下一步做什么"的决策都由模型做出。这使得系统能够随着模型能力的提升而自然变强，而无需修改代码。

---

## 结论

Claude Code 的架构设计展示了构建高级 AI Agent 的一条清晰而成熟的路径。它通过一个简单而强大的 **TAOR 循环**作为其核心驱动力，并围绕这一循环构建了一套精密的**上下文管理**和**权限控制**机制。其工具集的设计哲学——**拥抱能力原语，而非无限集成**——使其在保持简洁的同时获得了巨大的灵活性和能力。

通过深入理解其 Agent Loop 的运作机制和每一个工具的设计意图，我们不仅能更有效地使用 Claude Code，也能为构建我们自己的下一代 AI Agent 汲取宝贵的经验。无论是 TAOR 循环的简洁性、子 Agent 的上下文隔离策略、还是语义化的权限模型，这些模式都具有高度的可迁移性，值得每一位 AI 工程师深入学习和借鉴。

---

## 参考文献

[1] Anthropic. (2025, September 29). *Effective context engineering for AI agents*. Anthropic. https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

[2] Rungta, V. (2026, February 17). *Claude Code Architecture (Reverse Engineered)*. Chain of Thought. https://vrungta.substack.com/p/claude-code-architecture-reverse

[3] Sung, G. (2026, January 27). *Tracing Claude Code's LLM Traffic: Agentic loop, sub-agents, tool use, prompts*. Medium. https://medium.com/@georgesung/tracing-claude-codes-llm-traffic-agentic-loop-sub-agents-tool-use-prompts-7796941806f5

[4] PromptLayer. (2025, August 29). *Claude Code: Behind-the-scenes of the master agent loop*. PromptLayer Blog. https://blog.promptlayer.com/claude-code-behind-the-scenes-of-the-master-agent-loop/

[5] bgauryy. (2025, October). *Claude Code Internal Tools Implementation*. GitHub Gist. https://gist.github.com/bgauryy/0cdb9aa337d01ae5bd0c803943aa36bd

[6] Kirshatrov, K. (2025, April). *Claude Code Internals*. https://kirshatrov.com/posts/claude-code-internals
