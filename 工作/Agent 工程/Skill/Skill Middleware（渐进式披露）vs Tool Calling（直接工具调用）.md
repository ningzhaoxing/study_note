
> [!info] 实验环境
> **模型**：Kimi moonshot-v1-8k　|　**框架**：CloudWeGo Eino v0.8.0-beta.1　|　**测试用例**：10 个

---

## 一、调研背景与目标

### 1.1 背景

在基于 LLM 的 Agent 系统中，让模型按正确顺序调用工具（Skill）是实现复杂业务自动化的核心挑战。目前主流有两种工具暴露范式：

- **Tool Calling（直接工具调用）**：将所有可用工具的完整描述一次性注入上下文，模型直接选择并调用。
- **Skill Middleware（渐进式披露）**：模型只看到工具的名称和摘要描述，需先调用 `skill()` 工具"加载"完整说明文档，再按文档指引执行操作。

渐进式披露来自 Anthropic 官方 Claude 文档中对大量工具场景下的推荐实践，也是 CloudWeGo Eino 框架 ADK 中 Skill Middleware 的设计初衷。

### 1.2 调研目标

在**相同模型、相同任务、相同评分标准**下，对比两种范式的：

1. Skill 命中率（精确调用哪些工具）
2. 调用顺序准确性
3. 综合评分
4. 重复调用 / 稳定性表现
5. 平均响应耗时

---

## 二、场景设计

### 2.1 业务场景

设计一个 **10-Skill 销售数据分析 Pipeline**，模拟从原始数据到结论交付的完整链路：

```text
fetch_data → filter_data ──┬── compute_kpi
                            ├── compare_period   （并行，按需）
                            ├── segment_analysis （并行，按需）
                            └── detect_anomaly ──→ [alert_anomaly]（条件分支）
                                     │
                              export_excel → write_summary → send_email
```

数据层：SQLite，2023 + 2024 两年共 20,000 条记录（各含 50 条注入异常），含 `customer_tier`（VIP/高级/普通）字段。

### 2.2 Skill 定义（10 个）

| 类型  | Skill 名称           | 功能描述                | 主要输入参数                              | 输出文件                      |
| --- | ------------------ | ------------------- | ----------------------------------- | ------------------------- |
| 基础  | `fetch_data`       | 按时间段提取原始记录          | `--start` / `--end`                 | `tmp/raw_sales.json`      |
| 基础  | `filter_data`      | 按区域/类目/金额过滤         | `--region` / `--category`           | `tmp/filtered_sales.json` |
| 分析  | `compute_kpi`      | 计算 Top N 产品、销售额、增长率 | `--top-n`                           | `tmp/kpi.json`            |
| 分析  | `compare_period`   | 同比/环比分析             | `--compare-start` / `--compare-end` | `tmp/comparison.json`     |
| 分析  | `segment_analysis` | 客户等级 × 类目交叉分层       | `--top-n`                           | `tmp/segments.json`       |
| 分析  | `detect_anomaly`   | 3σ 方法检测异常订单         | `--sigma`                           | `tmp/anomalies.json`      |
| 输出  | `alert_anomaly`    | 发送严重异常紧急告警          | `--to` / `--threshold`              | 邮件发送确认                    |
| 输出  | `export_excel`     | 多 Sheet Excel 报告导出  | `--output`                          | `output/*.xlsx`           |
| 输出  | `write_summary`    | 生成文字分析摘要            | `--lang`                            | `output/summary.txt`      |
| 输出  | `send_email`       | 发送完整分析报告邮件          | `--to` / `--subject`                | 邮件发送确认                    |

### 2.3 测试用例集（10 个）

| TC | 描述 | 预期 Skill 链 | 核心考察点 |
|----|------|--------------|----------|
| TC-01 | 全链路 7 步 | fetch→filter→compute_kpi→detect_anomaly→export_excel→write_summary→send_email | 长链路完整性 |
| TC-02 | 4 步基础流程 | fetch→filter→compute_kpi→export_excel | 无关 Skill 跳过 |
| TC-03 | 仅异常检测 | fetch→filter→detect_anomaly | 精确性（跳过 KPI/导出） |
| TC-04 | 仅 KPI 排名 | fetch→filter→compute_kpi | 精确性（跳过异常/导出） |
| TC-05 | 无 Excel 有邮件 | fetch→filter→compute_kpi→detect_anomaly→write_summary→send_email | 输出路径选择 |
| TC-06 | 环比 + 分层 | fetch→filter→compute_kpi→compare_period→segment_analysis | 并行节点识别 |
| TC-07 | 同比 + 导出 | fetch→filter→compute_kpi→compare_period→segment_analysis→export_excel | 跨年对比 + 复杂节点 |
| TC-08 | 条件告警路径 | fetch→filter→detect_anomaly→alert_anomaly | 条件分支（仅告警） |
| TC-09 | 全 10 步完整 Pipeline | fetch→filter→compute_kpi→compare_period→segment_analysis→detect_anomaly→alert_anomaly→export_excel→write_summary→send_email | 最大复杂度 |
| TC-10 | 歧义指令 | fetch→filter→compute_kpi | 时间推断 + 最小 Skill 选择 |

---

## 三、技术方案

### 3.1 方案 A：Skill Middleware（渐进式披露）

```text
用户指令
   │
   ▼
ADK Agent
   ├── [skill 工具]     ← Skill Middleware 注入，返回完整 SKILL.md 内容
   └── [execute 工具]   ← 自定义工具，执行 python3 脚本
```

**执行流程**：`skill("fetch_data")` 加载文档 → 解析指令 → `execute("python3 /abs/path/fetch.py ...")` → 继续下一个 Skill

**特点**：上下文精简（仅 name+description），SKILL.md 内嵌 Next Step 约束，每步需 2 次 LLM 调用。

### 3.2 方案 B：Tool Calling（直接工具调用）

```text
用户指令
   │
   ▼
ADK Agent
   ├── [fetch_data]  [filter_data]  [compute_kpi]
   ├── [compare_period]  [segment_analysis]  [detect_anomaly]
   └── [alert_anomaly]  [export_excel]  [write_summary]  [send_email]
```

**执行流程**：模型直接调用 `fetch_data(start=..., end=...)` → 工具内部执行 Python 脚本 → 继续下一个工具

**特点**：参数结构化，每步 1 次 LLM 调用，全部 10 个工具 Schema 一次性注入上下文。

### 3.3 评分规则

| 指标 | 计分方式 | 满分 |
|------|---------|------|
| Skill 命中分 | 每命中 1 个预期 Skill 得 1 分 | N（预期 Skill 数） |
| 顺序得分 | 5 条关键依赖约束各 1 分 | 5 |
| **总分** | 命中分 + 顺序得分 | N + 5 |

**5 条顺序约束**：

1. `fetch_data` → `filter_data`
2. `filter_data` → 所有分析节点（`compute_kpi` / `detect_anomaly` / `compare_period` / `segment_analysis`）
3. `detect_anomaly` → `alert_anomaly`
4. 分析节点 → `export_excel` / `write_summary`
5. `write_summary` / `export_excel` → `send_email`

---

## 四、评测结果

### 4.1 用例级详细结果

| TC | 预期 | 模式 A 实际调用链 | A 命中 | A 顺序 | A 总分 | 模式 B 实际调用链 | B 命中 | B 顺序 | B 总分 |
|----|------|----------------|--------|--------|--------|----------------|--------|--------|--------|
| TC-01 | 7 | fetch→filter→compute_kpi→detect→export→summary→email | 7/7 | 5/5 | **12** | fetch→filter→compute_kpi→detect→export→summary→email | 7/7 | 5/5 | **12** |
| TC-02 | 4 | fetch→filter→compute_kpi→export | 4/4 | 5/5 | **9** | fetch→filter→compute_kpi→export | 4/4 | 5/5 | **9** |
| TC-03 | 3 | fetch→filter→detect | 3/3 | 5/5 | **8** | fetch→filter→detect | 3/3 | 5/5 | **8** |
| TC-04 | 3 | fetch→filter→compute_kpi | 3/3 | 5/5 | **8** | fetch→filter→compute_kpi `×3次重复` | 3/3 | 5/5 | **8** |
| TC-05 | 6 | fetch→filter→detect→summary→email（漏 compute_kpi） | 5/6 | 5/5 | **10** | fetch→filter→detect→summary→**compute_kpi**→summary→export→email（乱序+多余） | 6/6 | 4/5 | **10** |
| TC-06 | 5 | fetch→filter→compare→segment→compute_kpi→`export→summary`（多余） | 5/5 | 5/5 | **10** | fetch→`fetch`→filter→compare→segment→`filter→filter`（重复） | 4/5 | 5/5 | **9** |
| TC-07 | 6 | fetch→filter→compare→segment→export（漏 compute_kpi） | 5/6 | 5/5 | **10** | 无限循环 filter→compare `×10+次` ❌ ERROR | 3/6 | 5/5 | **8** |
| TC-08 | 4 | fetch→filter→detect→alert | 4/4 | 5/5 | **9** | fetch→filter→detect→alert | 4/4 | 5/5 | **9** |
| TC-09 | 10 | fetch→filter→compute→compare→segment→detect→alert→export→summary→email ⚠️ERROR后 | 10/10 | 5/5 | **15** | fetch→filter→`fetch→filter`→compute→compare→segment→detect→alert→export→summary→email（重复） | 10/10 | 5/5 | **15** |
| TC-10 | 3 | fetch→filter→compute→`write_summary`（多余） | 3/3 | 5/5 | **8** | fetch→filter→`filter`→compute（重复） | 3/3 | 5/5 | **8** |

> [!warning] 特别说明
> ⚠️ **TC-09 模式 A**：所有 Skill 全部正确执行后，在最终汇总阶段触发 `exceeds max iterations`，Skill 调用层面完全成功。
>
> ❌ **TC-07 模式 B**：陷入 `filter_data` + `compare_period` 无限调用循环，直至 `exceeds max iterations`，任务失败。

### 4.2 汇总对比

| 指标 | Skill Middleware | Tool Calling | 差值 |
|------|----------------|-------------|------|
| 总用例数 | 10 | 10 | — |
| Skill 完全命中用例 | 8 / 10 | 8 / 10 | 持平 |
| 命中率（Skill 级） | **96.1%**（49/51） | 92.2%（47/51） | +3.9% |
| 顺序得分 | **100%**（50/50） | 98%（49/50） | +2% |
| 平均总分 | **9.9** | 9.6 | +0.3 |
| 平均耗时 | **9,756 ms** | 10,288 ms | −532 ms |
| 重复调用次数（合计） | **0** | 14 次 | — |
| 致命循环（ERROR） | **0** | 1（TC-07） | — |

---

## 五、分析

### 5.1 Skill 命中率：Middleware 更精准

Skill Middleware **96.1%** vs Tool Calling **92.2%**。差距主要来自两个用例：

- **TC-06**：Tool Calling 漏掉了 `compute_kpi`，而 Middleware 通过 SKILL.md 的 Next Step 提示完整覆盖了所有节点。
- **TC-07**：Tool Calling 陷入循环崩溃（3/6 命中），Middleware 正常完成（5/6 命中，仅漏 `compute_kpi`）。

两种模式都存在少量**漏调**（TC-05 Middleware 漏 `compute_kpi`、TC-07 两者都漏）和少量**多调**（Middleware TC-06 多调 export/summary，TC-10 多调 `write_summary`），说明对"隐含但预期调用"的 Skill 判断是共性弱点，与 Middleware 或 Tool Calling 模式无关，更多取决于用户指令的明确程度。

### 5.2 顺序准确性：Middleware 完美，Tool Calling 有一次乱序

Middleware 顺序得分 **50/50**（满分），Tool Calling **49/50**。唯一的顺序违规发生在 TC-05：模型在执行 `write_summary` 之后又补调了 `compute_kpi`，随后再次 `write_summary`，破坏了"分析节点→输出节点"的约束。

这符合预期：SKILL.md 在每个 Skill 结尾都明确标注了 `## Next Step`，对顺序有文档级约束；而 Tool Calling 仅依赖系统提示词中的顺序表，一旦模型在中途产生"补充计算"的意图，顺序约束就会被打破。

### 5.3 重复调用：Tool Calling 的核心问题

Tool Calling 出现了 **14 次重复调用**，Middleware 为 **0 次**，这是本次测试最显著的差异：

| 场景 | 重复模式 | 推测原因 |
|------|---------|---------|
| TC-04 | fetch→filter→compute `×3` | 模型对结果不满意，反复重新执行 |
| TC-06 / TC-09 / TC-10 | fetch / filter 重复 | 模型在规划阶段重置上下文，重新从数据获取开始 |
| TC-07 | filter→compare `×10+` ❌ | `compare_period` 返回结果后模型误判为"数据不足"，循环重试，最终耗尽迭代次数 |

Skill Middleware 不出现重复调用的原因：SKILL.md 的 `## Next Step` 指令在每步完成后明确告诉模型"下一步应该做什么"，消除了模型的不确定性。Tool Calling 缺乏这种步骤级引导，模型在多工具环境下更容易陷入自我纠错循环。

### 5.4 响应耗时：Middleware 反而更快

Middleware 平均 **9,756 ms**，Tool Calling **10,288 ms**，前者反而更快。

这与直觉相悖（Middleware 每步需要额外一次 `skill()` 加载调用），原因在于 Tool Calling 的**重复调用**大幅拉升了总耗时：TC-07 耗时 25,513 ms（Middleware 同用例仅 6,664 ms）。如果排除 TC-07 异常值，Tool Calling 在简单用例（TC-03/TC-08/TC-10）的耗时均低于 Middleware，符合"更少 LLM 轮次→更快"的预期。

### 5.5 复杂场景稳定性

TC-09（全 10 步）是最复杂的用例：

- **Middleware**：10/10 Skill 全部按正确顺序执行，触发 ERROR 是在所有工具完成后的最终汇总阶段（超出 ADK 最大迭代次数），属于框架限制而非规划失败。
- **Tool Calling**：重复执行了 fetch/filter，但最终 10/10 Skill 也全部完成，结果正确。

两者在最高复杂度下都能完成任务，但 Middleware 的调用链更整洁（无重复），Tool Calling 则体现出"尝试→重试"的行为模式。

---

## 六、结论与选型建议

### 6.1 综合结论

在 Kimi moonshot-v1-8k 模型、10 步销售分析 Pipeline 场景下：

- **Skill Middleware 综合表现更优**：命中率（96.1% vs 92.2%）、顺序得分（100% vs 98%）、平均总分（9.9 vs 9.6）、稳定性（无重复调用、无循环崩溃）均优于 Tool Calling。
- **最大差距来源于复杂场景**：简单用例（TC-01~TC-04/TC-08）两种模式几乎等价；差距集中在 TC-06/TC-07/TC-09 等需要并行节点识别和多步规划的场景。
- **Tool Calling 的主要风险是重复调用和循环崩溃**：14 次重复调用和 1 次致命循环（TC-07）是系统性问题，在生产环境中可能造成成本失控和任务失败。

### 6.2 选型建议

| 场景特征 | 推荐方案 | 原因 |
|---------|---------|------|
| Skill 数量 > 10 | **Skill Middleware** | 上下文精简，避免 Schema 膨胀影响推理质量 |
| Skill 数量 ≤ 5 且彼此独立 | Tool Calling | 简单场景下两者等价，Tool Calling 延迟更低 |
| Pipeline 有严格顺序依赖 | **Skill Middleware** | SKILL.md 的 Next Step 可内嵌步骤级顺序约束 |
| 有并行节点或条件分支 | **Skill Middleware** | 复杂规划场景下稳定性显著更高 |
| 工具参数需精确提取 | Tool Calling | 结构化 Schema 对参数提取有天然优势 |
| 需要动态热更新工具 | **Skill Middleware** | Backend 可运行时更新，无需重启 Agent |
| 对响应延迟敏感（简单任务） | Tool Calling | 无额外加载轮次，简单场景延迟更低 |

### 6.3 局限性

1. **单模型**：仅测试 Kimi moonshot-v1-8k，结论不代表 GPT-4o / Claude 3.5 等更强模型的表现——更强的推理能力可能显著缩小两者差距
2. **单次运行**：LLM 输出具有随机性，未做多次重复采样，个别用例结论的置信度有限
3. **场景局限**：中文指令 + 销售分析 Pipeline，其他语言和业务域可能有不同结论
4. **框架版本**：基于 Eino v0.8.0-beta.1，正式版行为可能有变化

---

## 七、工程实现概览

### 目录结构

```text
skill_demo/
├── main.go                   # 双模式 Agent 评测入口（SkillDetector 可插拔）
├── skills/                   # 10 个 Skill（每个含 SKILL.md + scripts/）
│   ├── fetch_data/  filter_data/  compute_kpi/  detect_anomaly/
│   ├── compare_period/  segment_analysis/  alert_anomaly/
│   └── export_excel/  write_summary/  send_email/
├── skilltools/
│   └── tools.go              # Tool Calling 模式：10 个 InvokableTool
├── backend/
│   └── local.go              # Skill Middleware 的本地文件系统 Backend
├── executor/
│   └── execute_tool.go       # Skill Middleware 模式的 execute 工具
├── recorder/
│   └── recorder.go           # 评测记录器（5 条顺序约束、Stats 汇总）
├── testcases/
│   └── cases.go              # 10 个标准评测用例
└── data/
    ├── init_db.py            # SQLite mock 数据初始化（2023+2024，20,000 条）
    └── sales.db
```

### 技术栈

| 组件        | 技术选型                                       |
| --------- | ------------------------------------------ |
| LLM 框架    | CloudWeGo Eino v0.8.0-beta.1               |
| Agent 模型  | Kimi moonshot-v1-8k（OpenAI-compatible API） |
| Skill 中间件 | `eino/adk/middlewares/skill`               |
| 数据存储      | SQLite（2023+2024，含 `customer_tier`）        |
| 脚本执行      | Python 3，pandas / openpyxl / smtplib       |
| 评测记录      | 自定义 recorder 包（命中率 + 5 条顺序约束）              |

---

## 八、工程实践参考：OpenClaw 的混合方案

> [!note] 来源
> 以下内容来自对 [openclaw/openclaw](https://github.com/openclaw/openclaw) 仓库的 DeepWiki 调研（Q&A × 4），用于对照验证本文结论在真实 Agent 产品中的体现。

### 8.1 架构概述

OpenClaw 并非纯粹使用 Skill Middleware 或 Tool Calling，而是采用**混合策略**：

- **一等工具（First-class Tools）**：`browser`、`canvas`、`nodes`、`cron` 等原子操作，通过标准 Function Calling 直接调用，替代了早期的 `openclaw-*` shell skills。
- **Skill 系统**：提供领域工作流指令（GitHub PR 流程、部署流程等），以 [AgentSkills](https://agentskills.io) 兼容格式组织，**按需加载**完整内容。

两套系统互补：Skills 内部驱动 Function Calls 来执行具体操作，模型先决策走哪条路径，再通过 Function Call 落地。

### 8.2 工具调用机制（Function Calling）

工具通过适配器统一转换为 `ToolDefinition` 格式，送入底层 SDK 做标准 function calling：

```typescript
export function toToolDefinitions(tools: AnyAgentTool[]): ToolDefinition[] {
  return tools.map((tool) => ({
    name: tool.name,
    description: tool.description ?? "",
    parameters: tool.parameters,
    execute: async (toolCallId, params, onUpdate, _ctx, signal) => {
      return await tool.execute(toolCallId, params, signal, onUpdate);
    },
  }));
}
```

所有工具均通过 `customTools` 传入，框架不使用任何内置工具，保持完整控制权。多模型提供商（OpenAI、Ollama、Google）均通过此统一接口接入 function calling。

### 8.3 Skill 系统（渐进式披露）

OpenClaw 的 Skill 系统实现了与本文方案 A 相同的**渐进式披露**理念：

| 阶段         | 注入内容                 | 说明             |
| ---------- | -------------------- | -------------- |
| 系统提示（始终存在） | Skill 名称 + 描述 + 文件路径 | 元数据占用上下文极小     |
| 模型触发时（按需）  | 完整 `SKILL.md` 内容     | 通过 `read` 工具加载 |

系统提示中对 Skill 加载的约束逻辑：

```
## Skills (mandatory)
Before replying: scan <available_skills> <description> entries.
- 若恰好一个 skill 明确匹配：用 `read` 工具读取其 SKILL.md，然后遵循。
- 若多个可能匹配：选最具体的一个，读取并遵循。
- 若无明确匹配：不读取任何 SKILL.md。
约束：每次最多预读一个 skill；仅在选定后才读取。
```

### 8.4 Function Calling vs Skill 的决策逻辑

```
接收任务
    │
    ▼
是否为简单原子操作？
    ├── 是 → 直接 Function Call（read / exec / browser 等）
    └── 否 → 是否有匹配的 Skill？
                ├── 是 → read SKILL.md → 按指令执行（内部仍用 Function Call）
                └── 否 → 用 Function Call 组合完成
```

**适用 Function Call 的典型场景**：读取文件、列出目录、执行单条命令、浏览器操作。

**适用 Skill 的典型场景**：GitHub PR 审查流程、部署流程、多步数据分析、需要错误恢复策略的复杂操作。

### 8.5 与本文结论的对照

| 本文结论                                  | OpenClaw 的印证                                      |
| ------------------------------------- | ------------------------------------------------- |
| Skill 数量多时，只注入元数据以避免 Schema 膨胀        | ✅ 系统提示仅注入名称+描述+路径，完整指令按需加载                        |
| Pipeline 有严格顺序依赖时，Skill Middleware 更优 | ✅ GitHub、部署等多步流程均走 Skill，内嵌 Next Step 约束          |
| 原子工具彼此独立时，Tool Calling 延迟更低           | ✅ browser / exec / cron 等直接 Function Call，无额外加载轮次 |
| 生产建议：复杂 → Skill，简单 → Tool Calling     | ✅ OpenClaw 正是按此原则拆分两套系统                           |


> [!tip] 核心启示
> OpenClaw 的实践表明，**两种模式并非互斥**——在同一个 Agent 中，原子工具走 Function Calling，复杂工作流走 Skill Middleware，可以兼得两者的优势：低延迟的原子操作 + 高稳定性的多步规划。
