
> **文档版本**: v1.0

> **创建日期**: 2026-02-28

> **文档状态**: 待评审

> **目标读者**: 测试工程师、后端开发工程师

> **关联文档**: [TARA报告导出优化方案_v1.0.md](./TARA报告导出优化方案_v1.0.md) | [TARA总表重构技术方案_v1.0.md](./TARA总表重构技术方案_v1.0.md)

> **测试项目ID**: `749528030877024256`

  

---

  

## 一、测试范围

  

本计划覆盖 TARA 总表重构的以下能力：

  

| # | 测试能力 | 对应 PRD |

|---|---------|---------|

| 1 | 行展开逻辑（威胁场景 × 损害场景） | §3.7.4 |

| 2 | 最可行攻击路径选择 | §3.7.4、§3.7.5 场景4 |

| 3 | 枚举值映射正确性 | §3.4.2、§3.7 |

| 4 | 风险值计算正确性 | §3.7.4 |

| 5 | 字段对齐（表头与数据列对应） | §3.5 |

| 6 | 特殊场景处理（4种边界条件） | §3.7.5 |

| 7 | Excel 双行表头结构 | §3.7.6 |

  

**不在本次测试范围内：**

- 其他 Sheet（系统建模、损害场景等）的修复内容

- 前端展示逻辑

- 导出接口的权限控制

  

---

  

## 二、测试数据准备

  

### 2.1 标准测试数据集（TEST-001）

  

```sql

-- ========================

-- 准备标准测试数据集

-- ========================

  

-- 项目

INSERT INTO projects (id, name) VALUES ('TEST-001', 'TARA总表测试项目');

  

-- 资产（3个）

INSERT INTO assets (id, project_id, type, serial_no, name, properties) VALUES

('COMP-1', 'TEST-001', '组件', 'COMP-1', 'T-BOX', 'INTEGRITY'),

('COMP-2', 'TEST-001', '组件', 'COMP-2', 'ESS', 'AUTHORIZATION'),

('CH-1', 'TEST-001', '通道', 'CH-1', 'T-BOX-ESS通道', 'CONFIDENTIALITY');

  

-- 损害场景（5个）

INSERT INTO damage_scenes (id, asset_id, security_property, description) VALUES

('DS-1', 'COMP-2', 'AUTHORIZATION', '待定义损害场景'),

('DS-2', 'COMP-2', 'CONFIDENTIALITY', '待定义损害场景'),

('DS-3', 'COMP-1', 'INTEGRITY', '待定义损害场景'),

('DS-4', 'COMP-1', 'AVAILABILITY', '待定义损害场景'),

('DS-5', 'CH-1', 'CONFIDENTIALITY', '待定义损害场景');

  

-- 影响评估（对应5个损害场景）

INSERT INTO impact_assessments

(damage_scene_id, safety_level, safety_value, financial_level, financial_value,

operational_level, operational_value, privacy_level, privacy_value, impact_level) VALUES

('DS-1', 'S0',0, 'F0',0, 'O0',0, 'P0',0, 'NEGLIGIBLE'), -- 可忽略

('DS-2', 'S0',0, 'F0',0, 'O0',0, 'P2',2, 'MAJOR'), -- 重大

('DS-3', 'S1',1, 'F1',1, 'O1',1, 'P1',1, 'MODERATE'), -- 中等

('DS-4', 'S2',2, 'F2',2, 'O2',2, 'P2',2, 'MAJOR'), -- 重大

('DS-5', 'S3',3, 'F3',3, 'O3',3, 'P3',3, 'SEVERE'); -- 严重

  

-- 威胁场景（3个）

INSERT INTO threat_scenes (id, project_id, description) VALUES

('TS-1', 'TEST-001', '威胁场景1222'),

('TS-2', 'TEST-001', '威胁场景111'),

('TS-3', 'TEST-001', '威胁场景333');

  

-- 威胁场景与损害场景关联（N:N 关系）

-- TS-1 关联 DS-1, DS-2（1:N 展开测试）

-- TS-2 关联 DS-3

-- TS-3 关联 DS-4, DS-5

INSERT INTO threat_damage_relations (threat_scene_id, damage_scene_id) VALUES

('TS-1', 'DS-1'), ('TS-1', 'DS-2'),

('TS-2', 'DS-3'),

('TS-3', 'DS-4'), ('TS-3', 'DS-5');

  

-- 攻击路径（每个威胁场景3条，各有不同可行性）

INSERT INTO attack_paths

(id, threat_scene_id, description, elapsed_time, elapsed_time_value,

expertise, expertise_value, knowledge_of_item, knowledge_value,

window_of_opportunity, window_value, equipment, equipment_value,

feasibility_level, feasibility_score, created_at) VALUES

-- TS-1 的攻击路径（AP-2 最可行：HIGH, score=12）

('AP-1','TS-1','根节点→节点A→节点B','WITHIN_1_WEEK',1,'PROFICIENT',1,'PUBLIC',0,'EASY',1,'STANDARD',0,'LOW',8, '2024-01-01'),

('AP-2','TS-1','根节点→节点C', 'WITHIN_1_DAY', 0,'LAYMAN', 0,'PUBLIC',0,'UNLIMITED',0,'STANDARD',0,'HIGH',12,'2024-01-02'),

('AP-3','TS-1','根节点→节点D→节点E','WITHIN_1_MONTH',2,'EXPERT', 2,'RESTRICTED',1,'MODERATE',1,'SPECIALIZED',1,'MEDIUM',10,'2024-01-03'),

-- TS-2 的攻击路径（AP-4 最可行：MEDIUM, score=9）

('AP-4','TS-2','步骤1→步骤2', 'WITHIN_1_WEEK',1,'PROFICIENT',1,'PUBLIC',0,'EASY',1,'STANDARD',0,'MEDIUM',9,'2024-01-01'),

('AP-5','TS-2','步骤1→步骤3→步骤4', 'WITHIN_6_MONTHS',3,'EXPERT',2,'CONFIDENTIAL',2,'DIFFICULT',2,'BESPOKE',2,'LOW',7,'2024-01-02'),

-- TS-3 的攻击路径（AP-6 最可行：HIGH, score=13）

('AP-6','TS-3','攻击链A', 'WITHIN_1_DAY', 0,'LAYMAN', 0,'PUBLIC',0,'UNLIMITED',0,'STANDARD',0,'HIGH',13,'2024-01-01'),

('AP-7','TS-3','攻击链B', 'WITHIN_1_DAY', 0,'PROFICIENT',1,'PUBLIC',0,'EASY',1,'STANDARD',0,'HIGH',11,'2024-01-02');

  

-- 风险处置

INSERT INTO risk_treatments

(threat_scene_id, damage_scene_id, strategy, cyber_goal_no, cyber_goal, is_acceptable) VALUES

('TS-1','DS-1','RETAIN', 'CS-GOAL-1','ESS的Authorization-可授权应免受威胁场景1222的影响','是'),

('TS-1','DS-2','REDUCE', 'CS-GOAL-2','ESS的C-机密性应免受威胁场景1222的影响','否'),

('TS-2','DS-3','TRANSFER','CS-GOAL-3','T-BOX的I-完整性应免受威胁场景111的影响','是'),

('TS-3','DS-4','AVOID', 'CS-GOAL-4','T-BOX的A-可用性应免受威胁场景333的影响','否'),

('TS-3','DS-5','REDUCE', 'CS-GOAL-5','T-BOX-ESS通道的C-机密性应免受威胁场景333的影响','否');

```

  

### 2.2 边界测试数据集（TEST-BOUNDARY）

  

```sql

-- 项目
INSERT INTO projects (id, name) VALUES ('TEST-BOUNDARY', '边界测试项目');

-- 独立资产（避免跨项目引用 TEST-001 的数据）
INSERT INTO assets (id, project_id, type, serial_no, name) VALUES
('COMP-B1', 'TEST-BOUNDARY', '组件', 'COMP-B1', '边界测试组件');

-- 场景1：TS-X 无攻击路径
INSERT INTO damage_scenes (id, asset_id, security_property, description)
VALUES ('DS-BX', 'COMP-B1', 'INTEGRITY', '边界测试损害场景');

INSERT INTO threat_scenes (id, project_id, description)
VALUES ('TS-X', 'TEST-BOUNDARY', '无攻击路径的威胁场景');

INSERT INTO threat_damage_relations (threat_scene_id, damage_scene_id)
VALUES ('TS-X', 'DS-BX');

-- 不插入 attack_paths

-- 场景2：DS-Y 无关联威胁场景
INSERT INTO damage_scenes (id, asset_id, security_property, description)
VALUES ('DS-Y', 'COMP-B1', 'INTEGRITY', '无威胁场景的损害场景');

-- 不插入 threat_damage_relations

-- 场景3：TS-SAME 有两条 HIGH 级别路径，分值不同（独立威胁场景，不污染 TEST-001）
INSERT INTO damage_scenes (id, asset_id, security_property, description)
VALUES ('DS-BSAME', 'COMP-B1', 'CONFIDENTIALITY', '用于路径选择测试的损害场景');

INSERT INTO threat_scenes (id, project_id, description)
VALUES ('TS-SAME', 'TEST-BOUNDARY', '用于路径选择测试的威胁场景');

INSERT INTO threat_damage_relations (threat_scene_id, damage_scene_id)
VALUES ('TS-SAME', 'DS-BSAME');

INSERT INTO attack_paths
(id, threat_scene_id, feasibility_level, feasibility_score, created_at, ...) VALUES
('AP-SAME-1', 'TS-SAME', 'HIGH', 10, '2024-01-01', ...), -- 应被淘汰（分值低）
('AP-SAME-2', 'TS-SAME', 'HIGH', 12, '2024-01-02', ...); -- 应被选中（分值更高）

-- 场景4：空项目（TC-B04）
INSERT INTO projects (id, name) VALUES ('TEST-EMPTY', '空项目');

```

  

---

  

## 三、功能测试用例

  

### 3.1 核心功能测试

  

| 用例ID | 测试场景 | 前置条件 | 预期结果 |

|-------|---------|---------|---------|

| **TC-001** | 基本数据导出 | 使用 TEST-001 数据集 | 生成 TARA总表，共5行数据（TS-1×2 + TS-2×1 + TS-3×2） |

| **TC-002** | 行展开：1个威胁场景关联2个损害场景 | TS-1 关联 DS-1, DS-2 | 导出2行，均为 TS-1，但 damageSceneId 分别为 DS-1、DS-2 |

| **TC-003** | 最可行路径选择 | TS-1 有3条路径：AP-1(LOW)、AP-2(HIGH)、AP-3(MEDIUM) | 所有 TS-1 相关行的攻击路径ID 均为 `AP-2⭐` |

| **TC-004** | 同一威胁场景路径信息重复 | TS-1 关联 DS-1, DS-2，最可行路径为 AP-2 | DS-1行和DS-2行的攻击路径信息完全相同 |

| **TC-005** | 风险值计算：可忽略×高=2 | DS-1 影响等级=可忽略，TS-1 最可行路径可行性=高 | DS-1行的风险评级=2 |

| **TC-006** | 风险值计算：重大×高=4 | DS-2 影响等级=重大，TS-1 最可行路径可行性=高 | DS-2行的风险评级=4 |

| **TC-007** | 风险值计算：严重×高=5 | DS-5 影响等级=严重，TS-3 最可行路径可行性=高 | DS-5行的风险评级=5 |

  

### 3.2 枚举值正确性测试

  

| 用例ID | 测试字段 | 错误值（修复前） | 正确值（修复后） |

|-------|---------|--------------|--------------|

| **TC-E01** | 专业知识(SE) | 无 ❌ | 外行 / 熟练 / 专家 / 多位专家 |

| **TC-E02** | 操作机会窗口(WoO) | 无 ❌ | 无限制 / 简单 / 中等 / 困难 |

| **TC-E03** | 设备(Eq) | 无 ❌ | 标准 / 专用 / 定制 / 多种定制 |

| **TC-E04** | 运行时间(ET) | 不到一天 ❌ | 1天以内 / 1周以内 / ... |

| **TC-E05** | 影响等级 | NEGLIGIBLE ❌（原始值） | 可忽略 |

| **TC-E06** | 风险处置策略 | RETAIN ❌（原始值） | 保留风险 |

  

### 3.3 字段对齐测试

  

参照 PRD §3.5 描述，修复前 `威胁场景描述` 列显示了资产名称（如"ESS"）。

  

| 用例ID | 检查列 | 错误场景（修复前） | 正确值（修复后） |

|-------|--------|----------------|--------------|

| **TC-A01** | 威胁场景描述（列18） | 显示 "ESS"（资产名称）❌ | 显示 "威胁场景1222" |

| **TC-A02** | 损害场景ID（列5） | 显示 "威胁场景1222"（威胁场景描述）❌ | 显示 "DS-1" |

| **TC-A03** | 资产名称（列3） | 整体错位，值来自其他字段 ❌ | 显示 "ESS" / "T-BOX" |

  

---

  

## 四、边界条件测试

  

| 用例ID | 测试场景 | 操作步骤 | 预期结果 |

|-------|---------|---------|---------|

| **TC-B01** | 威胁场景无攻击路径 | 使用 TEST-BOUNDARY，TS-X 无攻击路径 | 导出的 TARA总表中**不包含** TS-X 的任何行 |

| **TC-B02** | 损害场景无威胁场景 | 使用 TEST-BOUNDARY，DS-Y 无关联威胁场景 | 导出的 TARA总表中**不包含** DS-Y 的任何行 |

| **TC-B03** | 多条路径可行性等级相同、分值不同 | 使用 TEST-BOUNDARY，TS-SAME 的 AP-SAME-1(HIGH,score=10) vs AP-SAME-2(HIGH,score=12) | 选中 `AP-SAME-2⭐`（分值更高） |

| **TC-B04** | 空项目（无任何威胁场景） | 使用 TEST-EMPTY 项目导出 | TARA总表仅显示双行表头，无数据行，不报错 |

| **TC-B05** | 项目无网络安全目标 | 风险处置无 cyber_goal | TARA总表相关列为空，不显示错误占位数据 |

| **TC-B06** | 损害场景无影响评估 | DS-Z 未完成影响评估 | 该行跳过，不报系统错误；响应 Header 中 `X-Skipped-Rows` 值 ≥ 1 |

| **TC-B07** | 多条路径可行性等级和分值均相同 | 使用 TEST-BOUNDARY，插入两条 HIGH/score=10 路径，created_at 分别为 2024-01-01、2024-01-02 | 选中 created_at 更早的路径（2024-01-01），结果稳定可复现 |

  

---

  

## 五、Excel 结构验证

  

| 用例ID | 验收项 | 验证方法 | 预期结果 |

|-------|-------|---------|---------|

| **TC-X01** | Sheet 名称 | 打开 Excel 检查 Tab 名称 | 名称为 `TARA总表` |

| **TC-X02** | 双行表头：第一行分组 | 检查第1行 | 包含"资产识别"、"损害场景"、"影响分析"、"威胁分析"、"最可行攻击路径"、"风险处置" |

| **TC-X03** | 双行表头：第二行字段 | 检查第2行 | 包含"系统级资产类型"、"损害场景ID"、"威胁场景ID"、"攻击路径ID⭐"等38个字段 |

| **TC-X04** | 表头合并单元格 | 检查第1行单元格合并 | "资产识别"合并A1:D1，"影响分析"合并G1:P1 等 |

| **TC-X05** | 攻击路径标记 | 检查攻击路径ID列 | 每行攻击路径ID包含⭐标记 |

| **TC-X06** | 冻结行 | 滚动查看 | 前两行表头始终固定 |

| **TC-X07** | 打印设置 | 文件→页面设置 | A4 横向，每页打印表头 |

| **TC-X08** | 总列数 | 统计第2行非空列数 | 共38列 |

  

---

  

## 六、完整数据正确性验证（使用真实项目）

  

使用 PRD 中的测试项目（ID: `749528030877024256`）进行验收：

  

| 验收编号 | 验收项 | 验收标准 | 优先级 |

|---------|-------|---------|-------|

| AC-01 | 行数正确 | 行数 = Σ(每个有效威胁场景关联的损害场景数) | P0 |

| AC-02 | 无重复行 | 每个(威胁场景ID, 损害场景ID)组合唯一 | P0 |

| AC-03 | 无遗漏行 | 所有有攻击路径且有损害场景关联的威胁场景均出现 | P0 |

| AC-04 | 威胁场景描述正确 | 威胁场景描述列不显示资产名称 | P0 |

| AC-05 | 枚举值无"无" | 专业知识/窗口/设备字段无"无"值 | P0 |

| AC-06 | 最可行路径一致 | 同一威胁场景的多行，攻击路径ID相同 | P0 |

| AC-07 | 风险值范围 | 所有风险评级值在 1-5 之间 | P0 |

| AC-08 | 网络安全目标编号 | 格式为 `CS-GOAL-{数字}`，不出现 `CS-Goal-TS-X` 格式 | P0 |

  

---

  

## 七、性能测试

  

| 用例ID | 测试场景 | 数据规模 | 通过标准 |

|-------|---------|---------|---------|

| **TC-P01** | 正常规模导出 | 威胁场景50个，损害场景200个，攻击路径250条 | 完成时间 < 10秒 |

| **TC-P02** | 大数据量导出 | 威胁场景200个，损害场景1000个，攻击路径1000条 | 完成时间 < 30秒 |

| **TC-P03** | 数据库查询次数 | 任意规模 | 总查询次数 < 10次（通过 SQL 日志验证） |

| **TC-P04** | 内存峰值 | 大数据量 | 进程内存增量 < 500MB |

| **TC-P05** | Excel 文件大小 | 1000行数据 | 文件大小 < 5MB |

  

---

  

## 八、单元测试要求

  

> 以下测试须由开发工程师在提测前完成，覆盖率要求 > 80%

  

### 8.1 最可行路径选择

  

```typescript

// tests/unit/BestPathSelector.test.ts

  

// ✅ 空路径返回 null

// ✅ 单条路径直接返回

// ✅ 按可行性等级选择：HIGH > MEDIUM > LOW > VERY_LOW

// ✅ 等级相同时按分值选择（高分优先）

// ✅ 等级和分值都相同时按创建时间选择（早的优先）

```

  

### 8.2 风险值计算

  

```typescript

// tests/unit/RiskCalculator.test.ts

  

// ✅ 严重 × 高 = 5

// ✅ 重大 × 中 = 3

// ✅ 中等 × 低 = 1

// ✅ 可忽略 × 极低 = 1

// ✅ 可忽略 × 高 = 2

// ✅ 无效影响等级抛出错误

// ✅ 无效可行性等级抛出错误

```

  

### 8.3 枚举值映射

  

```typescript

// tests/unit/EnumMapper.test.ts

  

// ✅ 所有 expertise 合法枚举值正确映射

// ✅ expertise 映射结果不包含"无"

// ✅ 所有 windowOfOpportunity 合法枚举值正确映射

// ✅ windowOfOpportunity 映射结果不包含"无"

// ✅ 所有 equipment 合法枚举值正确映射

// ✅ equipment 映射结果不包含"无"

// ✅ 非法枚举值抛出错误

```

  

---

  

## 九、测试执行计划

  

| 阶段 | 内容 | 执行人 | 入口标准 | 出口标准 |

|-----|------|-------|---------|---------|

| **阶段1** 单元测试 | §8 中所有单元测试 | 开发工程师 | 代码开发完成 | 单元测试全部通过，覆盖率 > 80% |

| **阶段2** 功能测试 | TC-001 ~ TC-E06、TC-A01 ~ TC-A03 | 测试工程师 | 单元测试通过，部署测试环境 | P0 用例全部通过 |

| **阶段3** 边界测试 | TC-B01 ~ TC-B06 | 测试工程师 | 功能测试通过 | 边界用例全部通过 |

| **阶段4** Excel 验证 | TC-X01 ~ TC-X08 | 测试工程师 | 边界测试通过 | Excel 结构全部符合预期 |

| **阶段5** 验收测试 | AC-01 ~ AC-08，使用真实项目 | 产品经理 + 测试工程师 | Excel 验证通过 | 所有 P0 验收项通过 |

| **阶段6** 性能测试 | TC-P01 ~ TC-P05 | 测试工程师 | 验收通过 | 所有性能指标达标 |

  

---

  

## 十、缺陷评级标准

  

| 等级 | 定义 | 示例 |

|-----|------|------|

| **P0** 阻塞 | 导出结果不可用，核心数据错误 | 威胁场景描述显示资产名称；枚举值为"无" |

| **P1** 严重 | 数据错误但部分可用 | 某条路径选择错误；风险值计算错误 |

| **P2** 一般 | 非核心字段问题 | 列宽不合适；缺少⭐标记 |

| **P3** 轻微 | 样式/格式问题 | 字体不对；边框颜色不对 |

  

**发布标准：P0 + P1 全部修复，P2 修复 > 80%，P3 可遗留。**

  

---

  

## 十一、变更记录

  

| 版本 | 日期 | 修改人 | 修改内容 |

|-----|------|-------|---------|

| v1.0 | 2026-02-28 | - | 初稿，基于 PRD v1.0 及对话中的技术方案编写 |

| v1.1 | 2026-02-28 | - | Review 修正：TC-X03/TC-X08 列数 37→38；TEST-BOUNDARY 独立建项目/资产/损害场景，修复跨项目引用；TC-B03 改用独立威胁场景 TS-SAME；TC-B04 补充 TEST-EMPTY 数据；TC-B06 预期结果明确 X-Skipped-Rows；新增 TC-B07（创建时间决胜用例） |