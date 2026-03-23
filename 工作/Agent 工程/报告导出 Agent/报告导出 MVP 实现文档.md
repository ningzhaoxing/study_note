# 报告导出 Agent — MVP 实现方案

> **状态**：设计草案 · **日期**：2026-03-12

---

## 1. 概述

报告导出是一个**独立的 Go Agent**，复用相同的基础设施（Eino ReAct、SmartMemory、ConversationEvent），独立部署和初始化。

**核心流程：**

1. 用户上传自己的 Excel 模板文件，Handler 将文件物理路径传给 Agent
2. Agent 调用 `save_excel_template.py`，在 `sheet_template` 表登记文件，获得 `template_id`
3. Agent 读取模板的列头结构（含列位置），`template_id` 作为后续所有操作的主键
4. Agent 将列头语义映射到 TARA 数据库字段，遇到歧义时向用户澄清
5. Agent 将确认的映射结果保存到 `mapping_result` 表（关联同一 `template_id`）
6. Agent 查询 TARA 业务数据，把数据填入模板文件对应单元格
7. 返回填好数据的文件供下载

> **关键约束**：`sheet_template`（模板文件）与 `mapping_result`（字段映射）是 1:1 关系，以 `template_id` 关联。同一模板第二次导出时可直接复用已保存的映射，跳过澄清步骤。

**MVP 包含：** 完整 MAPPING → FILLING 主流程、6 个 Skill、按业务模块拆分的数据查询脚本

**Post-MVP：** 会话恢复、完整风险链路由、多 Sheet 进度跟踪

### 文件结构

```text
tara/service/agent/ai_report_export/
├── agent.go                         # ReportExportAgent 初始化与 Stream() 入口
├── system_prompt.txt                # Agent 系统提示词（Bootstrap）
└── skills/
    ├── excel-file-operations/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── save_excel_template.py   # 登记上传文件到 sheet_template，返回 template_id
    │       ├── read_excel_schema.py     # 读取列头 + 列索引（按 template_id 查文件路径）
    │       └── write_excel_data.py      # 写入数据行到单元格，返回输出文件路径
    ├── manage-field-mappings/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── save_field_mappings.py
    │       └── get_field_mappings.py
    ├── query-asset-data/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── get_asset_list.py        # 资产与安全属性列表、资产网络安全相关性
    │       └── get_component_list.py    # 组件列表、功能列表
    ├── query-damage-data/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── get_asset_damage.py      # 资产关联损害场景（11列展开模式）
    │       └── get_damage_cal.py        # 损害场景关联CAL分析（9列聚合模式）
    ├── query-threat-data/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── get_damage_threat_attack.py  # 威胁与攻击路径（损害→威胁→攻击路径展开）
    │       ├── get_asset_threat_attack.py   # 资产-威胁与攻击路径（资产→威胁→攻击路径展开）
    │       └── get_threat_r155.py           # 威胁场景R155参考数据（威胁→R155展开）
    └── query-risk-data/
        ├── SKILL.md
        └── scripts/
            ├── get_risk_assessment.py   # 风险评估列表（8列）
            ├── get_security_goals.py    # 网络安全目标列表（2列）
            └── get_security_claims.py   # 网络安全需求列表（2列）
```

---

## 2. 架构

### 技术选型

| 组件 | 选型 |
| --- | --- |
| Agent 框架 | Eino ReAct |
| Skill 运行时 | Eino ADK Skill Middleware（`skill` / `read` / `execute`） |
| Excel 读写 | openpyxl（Python 脚本内使用） |
| 记忆系统 | `SmartMemory`（现有，直接复用） |
| 流式输出 | Eino v0.8 `ChatModelAgentMiddleware`（`WrapInvokableToolCall` / `AfterChatModel` 闭包写 SSEWriter）+ `Agent Callback` + `AsyncIterator` 消费循环转发 LLM 文本 |
| 数据访问 | Python 脚本直连 MySQL（环境变量注入连接信息） |

### 架构图

```text
HTTP Handler（file_path + project_id + session_id）
    │
ReportExportAgent.Run()
    ├── system_prompt.txt（Bootstrap：合法字段名列表 + 澄清策略）
    ├── Skill Middleware：6 个 Skill 按需加载
    ├── ReAct Loop：Thought → skill/execute → Observation
    │
    ├── ChatModelAgentMiddleware（Eino v0.8）
    │     ├── WrapInvokableToolCall 闭包：工具调用前后写 SSEWriter
    │     │     （tool_call / tool_result / complete / error）
    │     └── AfterChatModel 闭包：检测澄清模式写 SSEWriter
    │           （clarification_required）
    │
    ├── AsyncIterator[*AgentEvent]（框架内部事件）
    │     └── 消费循环：LLM 文本流 → SSEWriter（agent_thinking / final_answer）
    │
    └── SSEWriter → 前端 SSE
```

---

## 3. Skill 设计

### Skill 1：`excel-file-operations`

对用户上传的模板文件进行所有操作：登记文件、读取列头结构、写入数据。`template_id` 是贯穿整个流程的主键，由本 Skill 的第一个脚本产生。

```text
Use when: 登记上传的模板文件；读取模板列头结构；数据准备完毕需要写入模板文件时
NOT for: 查询业务数据、保存映射关系
```

脚本：

- `save_excel_template.py --file-path <str> --project-id <int> --user-id <int> --session-id <str>`
  将上传文件写入 `sheet_template` 表，**返回 `template_id`**（后续所有脚本均以此为主键）
  输出：`{ "template_id": 42, "file_name": "my_report.xlsx" }`

- `read_excel_schema.py --template-id <int>`
  从 `sheet_template` 查文件路径，读取 Excel 列头结构
  输出：`{ "sheets": [{ "sheetName": "...", "headers": [{"name": "组件名称", "col": 1}, ...] }] }`

- `write_excel_data.py --template-id <int> --sheet-name <str> --data-ref <str>`
  从 `sheet_template` 查文件路径，从 `mapping_result` 查 `tara_field → excel_header → col_index` 映射，逐行读取 `--data-ref` 指定的 JSONL 文件写入单元格（数据不经过 LLM）
  输出：`{ "output_path": "/file/reports/xxx_filled.xlsx", "rows_written": 47 }`

---

### Skill 2：`manage-field-mappings`

保存或查询 LLM 推理出的字段映射结果（`列头名 → TARA 字段名`），写入 `mapping_result` 表。`mapping_result` 通过 `template_id` 与 `sheet_template` 1:1 关联，`(template_id, excel_header)` 唯一索引保证每个列头只有一条映射记录。

```text
Use when: 所有列头映射确认后批量保存；或需要复用已有映射时查询（同一模板第二次导出）
NOT for: 读取模板文件、查询业务数据、写入 Excel
```

脚本：

- `save_field_mappings.py --template-id <int> --mappings '{"列头": "tara_field", ...}'`
  幂等写入：已存在的映射覆盖更新，新增的插入
- `get_field_mappings.py --template-id <int>`
  返回该模板已保存的所有映射；若返回非空，Agent 应优先复用，仅对缺失列头补充澄清

---

### Skill 3：`query-asset-data`

查询资产识别模块与系统建模模块的产出物，返回组件/资产维度的扁平数据行。

```text
Use when: 模板包含资产ID、组件名称、组件类型、安全属性（C/I/A等）、网络安全相关性字段时
NOT for: 损害场景、威胁场景、攻击路径、风险评估相关字段
```

脚本：

- `get_asset_list.py --project-id <int> --session-id <str>`
  查询资产与安全属性列表（6列）和资产网络安全相关性（9列），写入 JSONL Sidecar
  输出：`{ "asset_security": {"data_ref": "/tmp/tara_{sid}_asset_security.jsonl", "total": N, "columns": [...]}, "asset_relevance": {"data_ref": "/tmp/tara_{sid}_asset_relevance.jsonl", "total": N, "columns": [...]} }`

- `get_component_list.py --project-id <int> --session-id <str>`
  查询组件列表（4列）和功能列表（5列，含关联组件），写入 JSONL Sidecar
  输出：`{ "components": {"data_ref": "/tmp/tara_{sid}_components.jsonl", "total": N, "columns": [...]}, "functions": {"data_ref": "/tmp/tara_{sid}_functions.jsonl", "total": N, "columns": [...]} }`

---

### Skill 4：`query-damage-data`

查询损害场景模块产出物，支持两种导出视图：展开模式（每行=一条损害场景）和聚合模式（每行=一个资产+最高影响等级+CAL）。

```text
Use when: 模板包含损害场景ID、影响等级、安全/财务/隐私/操作等级、CAL等级字段时
NOT for: 威胁场景、攻击路径、风险处置决策相关字段
```

脚本：

- `get_asset_damage.py --project-id <int> --session-id <str>`
  查询资产关联损害场景（11列，`一个资产 × 一个安全属性 × 一个损害场景 = 一行`展开），写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_asset_damage.jsonl", "total": N, "columns": [...] }`

- `get_damage_cal.py --project-id <int> --session-id <str>`
  查询损害场景关联CAL分析（9列，按资产聚合，每资产取最高影响等级），写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_damage_cal.jsonl", "total": N, "columns": [...] }`

---

### Skill 5：`query-threat-data`

查询威胁场景与攻击路径模块产出物，支持三种导出视图：从损害场景视角展开、从资产视角展开、以及R155参考数据。

```text
Use when: 模板包含威胁场景ID、攻击路径ID、攻击可行性评级、R155编号字段时
NOT for: 资产安全属性、损害场景影响等级、风险评估相关字段
```

脚本：

- `get_damage_threat_attack.py --project-id <int> --session-id <str>`
  威胁与攻击路径数据（9列，`一个损害场景 × 一个威胁场景 × 一个攻击路径 = 一行`展开），写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_damage_threat_attack.jsonl", "total": N, "columns": [...] }`

- `get_asset_threat_attack.py --project-id <int> --session-id <str>`
  资产-威胁与攻击路径数据（9列，`一个资产 × 一个威胁场景 × 一个攻击路径 = 一行`展开），写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_asset_threat_attack.jsonl", "total": N, "columns": [...] }`

- `get_threat_r155.py --project-id <int> --session-id <str>`
  威胁场景R155参考数据（4列，`一个威胁场景 × 一个R155条目 = 一行`展开），写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_threat_r155.jsonl", "total": N, "columns": [...] }`

---

### Skill 6：`query-risk-data`

查询风险管理模块产出物，包括风险评估列表、网络安全目标、网络安全需求，支持从风险评估页面一键连续下载三个文件的场景。

```text
Use when: 模板包含风险值、风险处置决策（Avoid/Reduce/Share/Retain）、网络安全目标ID、网络安全需求ID字段时
NOT for: 损害场景影响等级、威胁场景攻击可行性相关字段
```

脚本：

- `get_risk_assessment.py --project-id <int> --session-id <str>`
  风险评估列表（8列），含威胁/损害场景关联、风险处置决策、网络安全目标ID声明，写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_risk_assessment.jsonl", "total": N, "columns": [...] }`

- `get_security_goals.py --project-id <int> --session-id <str>`
  网络安全目标列表（2列）：安全目标ID + 描述，写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_security_goals.jsonl", "total": N, "columns": [...] }`

- `get_security_claims.py --project-id <int> --session-id <str>`
  网络安全需求列表（2列）：安全声明ID + 描述，写入 JSONL Sidecar
  输出：`{ "data_ref": "/tmp/tara_{sid}_security_claims.jsonl", "total": N, "columns": [...] }`

---

## 4. 业务字段说明

LLM 做 Mapping 推理时需要知道每个字段的语义，不只是字段名。以下字段信息写入 `system_prompt.txt`。枚举值均为脚本输出后的中文展示值（DB 存储代码值，脚本负责翻译）。

### 损害场景（`damage_record_info`）

| 字段名 | 类型 | 语义描述 |
| --- | --- | --- |
| `damage_id` | string | 损害场景唯一标识符，格式 DS-xxx |
| `damage` | string | 损害场景描述文本（如"ECU 固件被篡改，导致车辆失控"） |
| `safety` | string | 安全影响等级：严重 / 重大 / 中等 / 可忽略 |
| `financial` | string | 财务影响等级：严重 / 重大 / 中等 / 可忽略 |
| `operational` | string | 操作影响等级：严重 / 重大 / 中等 / 可忽略 |
| `privacy` | string | 隐私影响等级：严重 / 重大 / 中等 / 可忽略 |
| `impact` | string | 综合影响等级（CAL 计算基准），取四个维度中的最高值；严重 / 重大 / 中等 / 可忽略 |
| `cal` | string | 网络安全保证等级：CAL 1 / CAL 2 / CAL 3 / CAL 4，由 `impact` 等级推导 |

### 威胁场景（`threat_record_info`）

| 字段名 | 类型 | 语义描述 |
| --- | --- | --- |
| `threat_id` | string | 威胁场景唯一标识符，格式 TS-xxx |
| `threat` | string | 威胁场景描述文本（如"攻击者通过 OBD 接口注入恶意指令"） |
| `risk_value` | int | 风险值（0–100），由影响等级与攻击可行性等级矩阵计算 |
| `risk_treatment_decision` | string | 风险处置决策（DB 值）：REDUCE→降低风险 / AVOID→规避风险 / TRANSFER→转移风险 / RETAIN→保留风险 / SHARE→分担风险 |
| `decision_statement` | string | 风险处置决策说明，对处置原因的文字描述 |
| `r155_ref_groups` | string | UNECE R155 参考分类（JSON 序列化字符串），含威胁类别 / 漏洞 / 攻击方式 |

### 攻击路径（`attack_path_info` / `attack_tree_v2`）

> 各维度 DB 存储整数代码，脚本统一翻译为中文字符串输出。

| 字段名 | 类型 | 语义描述 |
| --- | --- | --- |
| `path_id` | string | 攻击路径唯一标识符 |
| `path_name` | string | 攻击路径名称 |
| `expertise` | string | 所需专业技能等级：外行 / 熟练 / 专家 / 多位专家 |
| `elapsed_time` | string | 所需时间：1天以内 / 1周以内 / 1个月以内 / 6个月以内 / 超过6个月 |
| `knowledge_toe` | string | 对目标系统的知识度：公开 / 受限 / 保密 / 严格保密 |
| `opportunity_window` | string | 攻击机会窗口：无限制 / 简单 / 中等 / 困难 |
| `equipment` | string | 所需设备：标准 / 专用 / 定制 / 多种定制 |
| `attack_feasibility_rating` | string | 五维综合攻击可行性等级：Very Low（极低）/ Low（低）/ Medium（中）/ High（高） |

### 资产 / 组件（`asset_record_info` / `dfd_component`）

| 字段名 | 类型 | 语义描述 |
| --- | --- | --- |
| `component_id` | string | 组件唯一标识符 |
| `component_name` | string | 组件名称（如"TCU"、"OBD 接口"） |
| `component_type` | string | 组件类型：组件 / 通道 / 数据 / 环境 / 功能 / 数据流 |
| `component_desc` | string | 组件描述（可选，部分组件有详细说明） |
| `asset_id` | string | 资产唯一标识符（组件升格为资产后分配） |
| `asset_name` | string | 资产名称 |
| `network_security` | string | 网络安全相关性描述（非空表示该组件为网络安全资产） |

### 网络安全目标（`network_security_target_info`）

| 字段名 | 类型 | 语义描述 |
| --- | --- | --- |
| `network_security_target_id` | string | 网络安全目标唯一标识符，格式 CSG-xxx |
| `network_security_target` | string | 网络安全目标描述文本 |

### 网络安全需求（`cybersecurity_claim_info`）

| 字段名 | 类型 | 语义描述 |
| --- | --- | --- |
| `cybersecurity_claim_id` | string | 网络安全需求唯一标识符，格式 CSR-xxx |
| `cybersecurity_claim` | string | 网络安全需求描述文本 |

---

## 5. 数据查询 Skill 实现复杂性说明

4 个数据查询 Skill（Skill 3–6）各自脚本的核心复杂度集中在以下几个方面：

### 5.1 四层数据层级展开（笛卡尔积）

TARA 数据模型是四层嵌套结构：

```text
组件（component）
  └── 损害场景（damage）  [1:N]
        └── 威胁场景（threat）  [1:N]
              └── 攻击路径（attack_path）  [1:N]
```

Skill 5 的脚本（`get_damage_threat_attack.py`、`get_asset_threat_attack.py`）需要做最深层展开：每行输出 = 一条损害/资产 × 一条威胁 × 一条攻击路径的组合。一个威胁有 3 条攻击路径就输出 3 行，本质是笛卡尔积展开，行数 = ∏(各层子节点数)。

| Skill | 脚本 | 展开层数 | 输出行语义 |
| --- | --- | --- | --- |
| Skill 5 | `get_damage_threat_attack.py` | 3 层（损害 → 威胁 → 攻击路径） | 每行 = 一条攻击路径 |
| Skill 5 | `get_asset_threat_attack.py` | 3 层（资产 → 威胁 → 攻击路径） | 每行 = 一条攻击路径 |
| Skill 4 | `get_asset_damage.py` | 2 层（资产 × 安全属性 → 损害） | 每行 = 一条损害场景 |
| Skill 4 | `get_damage_cal.py` | 聚合（按资产） | 每行 = 一个资产 |
| Skill 3 | `get_asset_list.py` | 1 层 | 每行 = 一条资产 |
| Skill 6 | `get_risk_assessment.py` | 1 层 | 每行 = 一条风险记录 |

### 5.2 空值边界处理

层级展开时中间层可能为空：

- 损害场景下无威胁场景 → 该损害行是否输出？
- 威胁场景下无攻击路径 → 该威胁行是否输出？

MVP 约定：使用**内连接语义**，中间层为空则跳过，不输出占位行。空值边界需要专项单测覆盖（Skill 5 两个脚本的空威胁 / 空攻击路径边界）。

### 5.3 各脚本 JOIN 结构差异

每个脚本的 SQL / JOIN 结构独立，不存在统一路由：

- `get_damage_threat_attack.py`：3 表 JOIN（damage + threat + attack_path）
- `get_asset_threat_attack.py`：4 表 JOIN（component + damage + threat + attack_path）
- `get_asset_damage.py`：2 表 JOIN（component/asset × security_attr + damage）
- `get_damage_cal.py`：2 表 JOIN（component + damage），GROUP BY 聚合
- `get_asset_list.py` / `get_component_list.py`：单表或简单 JOIN

### 5.4 字段归一化与枚举翻译

所有脚本输出的 key 必须与 Mapping 后的 TARA 字段名一致：

- **命名风格差异**：DB 列名均为 snake_case，脚本统一归一化输出 snake_case
- **枚举翻译**：影响等级（S/M/Mo/N）、风险处置决策（Avoid/Reduce/Share/Retain）、可行性维度等，DB 存储代码值，报告需中文展示值
- **攻击可行性综合等级**：`attack_feasibility_rating` 由五维原始评分通过查表计算，DB 已存储计算结果，直接读取即可

### 5.5 Data Sidecar 模式（大数据处理）

数据查询脚本可能返回数千行数据，直接写入工具结果会超出 LLM 上下文长度。Data Sidecar 模式将实际数据与 LLM 推理完全隔离：

**原理：**

```text
查询脚本（get_*.py）
  → 将所有数据行写入 /tmp/tara_{session_id}_{script}.jsonl（每行一个 JSON 对象）
  → 只向 LLM 返回元数据：{ "data_ref": "<path>", "total": N, "columns": [...] }

LLM（Agent）
  → 收到 data_ref + columns，知道数据在哪、有哪些列
  → 决定"这份数据对应模板的哪个 Sheet"
  → 调用 write_excel_data.py --data-ref <path>，不传实际数据

write_excel_data.py
  → 从 mapping_result 表读取 tara_field → excel_header → col_index 映射
  → 逐行读取 JSONL，按 tara_field 取值 → 写入对应列
  → 实际数据全程不经过 LLM
```

**JSONL 文件格式：**

每行为一个扁平 JSON 对象，key 为 TARA 字段名（snake_case）：

```json
{"damage_id": "DS-001", "damage": "ECU固件篡改", "safety": "严重", "impact": "严重", "cal": "CAL 4"}
{"damage_id": "DS-002", "damage": "车速数据泄露", "safety": "可忽略", "impact": "重大", "cal": "CAL 3"}
```

**文件命名规则：** `/tmp/tara_{session_id}_{script_suffix}.jsonl`，随 session 生命周期存在，Agent 完成后可清理。

---

### 5.6 Skill 5 多表 JOIN 示例（`get_asset_threat_attack.py`）

```sql
component
  JOIN damage_record_info  ON damage_record_info.component_id = component.component_id
                           AND damage_record_info.project_id  = ?
  JOIN threat_record_info  ON threat_record_info.damage_id    = damage_record_info.damage_id
                           AND threat_record_info.project_id  = ?
  JOIN attack_path_info    ON attack_path_info.threat_id      = threat_record_info.threat_id
                           AND attack_path_info.project_id    = ?
WHERE component.project_id = ?
  AND damage_record_info.status = 0
  AND threat_record_info.status = 0
  AND attack_path_info.status   = 0
```

连接字段需正确处理 `status=0`（正常记录）过滤条件，防止软删除数据混入输出。

---

## 6. Mapping 推理（纯 LLM，无工具）

Mapping 是 LLM 的推理过程，不需要工具调用。LLM 拿到列头列表后，对照 Bootstrap 中的合法字段名列表自行判断映射关系，遇到歧义时向用户提问。

**合法 TARA 字段名（写入 system_prompt.txt）：**

```text
损害场景：damage_id, damage, safety, financial, operational, privacy, impact, cal
威胁场景：threat_id, threat, risk_value, risk_treatment_decision, decision_statement, r155_ref_groups
攻击路径：path_id, path_name, expertise, elapsed_time, knowledge_toe,
          opportunity_window, equipment, attack_feasibility_rating
资产/组件：component_id, component_name, component_type, component_desc,
           asset_id, asset_name, network_security
网络安全目标：network_security_target_id, network_security_target
网络安全需求：cybersecurity_claim_id, cybersecurity_claim
```

**歧义澄清策略（写入 system_prompt.txt）：**

1. 以编号列出候选字段（名称 + 简短描述），等待用户选择
2. 不得自行推断；有多个歧义列头时逐个澄清，不一次全问
3. 所有映射确认后调用 `manage-field-mappings` 保存

---

## 7. 上下文管理（SmartMemory）

使用 `SmartMemory`：多轮澄清过程中模板列头、历史映射结果必须保留，工具调用结果权重 1.5× 确保关键输出在压缩时优先保留。

```go
agent.NewSmartMemory(agent.SmartMemoryConfig{
    MemoryConfig:             agent.MemoryConfig{MaxMsgCount: 50},
    EnableImportanceScoring:  true,
    EnableSemanticRetrieval:  true,
    EnableContextCompression: true,
    CompressionThreshold:     30,
}, persister)
```

---

## 8. SSE 事件机制

事件来自两个来源，最终汇入同一个 `SSEWriter`：

- **Eino 框架事件**：`AsyncIterator[*AgentEvent]`，由框架内部 `cbHandler.Send()` 写入，包含 LLM 文本块和工具结果消息。SSE Handler 消费该迭代器并将 LLM 文本转发给 `SSEWriter`。
- **业务自定义事件**：`ChatModelAgentMiddleware`（Eino v0.8）的 `WrapInvokableToolCall` / `AfterChatModel` 钩子通过闭包直接调用 `SSEWriter`，在工具执行前后或 LLM 响应后写入业务语义事件。

> **与原 EventEmitter 的区别**：`ConversationEvent + SSEWriter` 结构保留不变，但所有调用点集中到 `agent.go` 初始化时构建的 `ChatModelAgentMiddleware` 工厂函数里，不再散落在业务逻辑中。v0.8 的 `Agent Callback` 替代了旧版 `AgentMiddleware`，`WrapInvokableToolCall` 替代了 `WrapToolCall`。

### 事件注入点

| 事件类型 | 注入方式 | 机制 |
| --- | --- | --- |
| `agent_thinking` / `final_answer` | Eino 原生 | `AsyncIterator` 消费循环转发 LLM 文本流到 SSEWriter |
| `tool_call` | `WrapInvokableToolCall` 前置 | 调用 `next(ctx, input)` 前，闭包写 SSEWriter |
| `tool_result` | `WrapInvokableToolCall` 后置 | `next()` 返回后，闭包写 SSEWriter |
| `complete` | `WrapInvokableToolCall` 后置 | 检测到工具名为 `write_excel_data.py` 且成功时写 SSEWriter |
| `clarification_required` | `AfterChatModel` | 检测 LLM 最后一条消息为问句且无工具调用时写 SSEWriter |
| `error` | `WrapInvokableToolCall` / `AfterChatModel` | 工具出错或迭代器 `event.Err != nil` 时写 SSEWriter |

### 事件字段映射（SSE payload）

| 事件 | 业务数据 → SSE 字段 |
| --- | --- |
| `agent_thinking` | 思考文本 → `content` |
| `tool_call` | 工具名/参数 → `metadata["tool_name"]` / `metadata["args"]` |
| `tool_result` | 状态/摘要 → `metadata["status"]` / `metadata["summary"]` |
| `clarification_required` | 提问文本 → `content` |
| `final_answer` | 回复文本 → `content` |
| `complete` | 输出文件路径/行数 → `metadata["output_path"]` / `metadata["rows_written"]` |
| `error` | 描述/错误码 → `error` / `metadata["code"]` |

---

## 9. 文件交付

Agent 完成数据写入后，填好的 Excel 文件通过以下机制交付前端：

### 流程

```text
write_excel_data.py
  → 写入 file/reports/{template_id}_filled.xlsx
  → 将 output_path 更新回 sheet_template 表（按 template_id）
  → 返回 { "output_path": "...", "rows_written": 47 }

WrapToolCall 后置（检测到工具名 = write_excel_data.py 且成功）
  → SSEWriter.Write(complete, {
        "download_url": "/api/report/download/{template_id}",
        "rows_written": 47
     })

前端收到 complete 事件
  → 触发 <a href=download_url download> 或 window.open
```

### Go 下载端点

新增路由（复用现有 JWT 鉴权中间件）：

```text
GET /api/report/download/:template_id
```

处理逻辑：

1. 从 JWT 取 `user_id`，查 `sheet_template` 验证该 `template_id` 属于当前用户
2. 取 `sheet_template.output_path`（`write_excel_data.py` 写入）
3. `c.FileAttachment(outputPath, fileName)` 流式返回文件

`template_id` 本身即是鉴权维度（只有上传该模板的用户可访问），无需额外生成一次性 token。

### `sheet_template` 表新增字段

`output_path`（varchar，nullable）：Agent 写入数据后由 `write_excel_data.py` 更新，记录填好数据的文件路径。该字段同时作为"任务是否完成"的标志位。
