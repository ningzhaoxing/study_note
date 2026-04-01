# TARA 总表重构技术方案

> **文档版本**: v1.0
> **创建日期**: 2026-02-28
> **文档状态**: 待评审
> **目标读者**: 后端开发团队
> **关联文档**: [TARA报告导出优化方案_v1.0.md](./TARA报告导出优化方案_v1.0.md)

---

## 一、背景

本文档针对 PRD「TARA 报告导出优化方案 v1.0」中 §3.7（TARA 总表重构）部分，提供详细的技术实现方案。

**核心问题（来自 PRD §3.7.1）：**

| 问题编号 | 问题描述 | 优先级 |
|---------|---------|-------|
| TARA-001 | 1:N、N:N 关系表达混乱 | P0 |
| TARA-002 | 数据字段对应错误 | P0 |
| TARA-003 | 数据重复与遗漏并存 | P0 |

---

## 二、架构设计

### 2.1 模块划分

```
src/modules/tara-export/
├── core/
│   ├── TARASummaryGenerator.ts      // 核心生成器（主入口）
│   ├── BestPathSelector.ts          // 最可行路径选择器
│   ├── RiskCalculator.ts            // 风险值计算器
│   └── EnumMapper.ts                // 枚举值映射器
├── data-access/
│   ├── ThreatSceneRepository.ts     // 威胁场景数据访问
│   ├── DamageSceneRepository.ts     // 损害场景数据访问
│   ├── AttackPathRepository.ts      // 攻击路径数据访问
│   └── RiskTreatmentRepository.ts   // 风险处置数据访问
├── excel/
│   ├── TARASummarySheetBuilder.ts   // Excel Sheet 构建器
│   ├── HeaderBuilder.ts             // 双行表头构建器
│   └── StyleApplier.ts              // 样式应用器
├── types/
│   ├── TARASummaryRow.ts            // 行数据类型定义
│   └── Enums.ts                     // 枚举类型定义
└── utils/
    ├── DataValidator.ts             // 数据验证器
    └── TARASummaryDataLoader.ts     // 批量数据加载器
```

### 2.2 数据流

```
[API 请求 projectId]
        ↓
[TARASummaryDataLoader]  ← 并行批量查询，构建内存索引
        ↓
[BestPathSelector]       ← 为每个威胁场景选择最可行攻击路径
        ↓
[主循环：威胁场景 × 损害场景]
        ↓
[RiskCalculator]         ← 风险值 = 影响等级 × 可行性等级（矩阵查表）
        ↓
[EnumMapper]             ← 映射所有枚举值为展示文本
        ↓
[DataValidator]          ← 验证字段完整性、枚举值合法性
        ↓
[TARASummarySheetBuilder] ← 写入 Excel（双行表头 + 数据行 + 样式）
        ↓
[返回 Excel 文件]
```

---

## 三、核心数据结构

### 3.1 行数据类型定义

```typescript
interface TARASummaryRow {
  // Part A: 资产识别
  assetType: string;              // 系统级资产类型（组件/通道/数据流）
  assetSerialNo: string;          // 资产序号（COMP-1, CH-1, DATAFLOW-1）
  assetName: string;              // 组件级资产名称
  assetProperties: string;        // 资产属性（网络安全属性）

  // Part B: 损害场景
  damageSceneId: string;          // 损害场景ID（DS-1, DS-2...）
  damageSceneDesc: string;        // 损害场景描述

  // Part C: 影响分析
  safetyLevel: string;            // 安全-等级（S0-可忽略 / S1-中等 / S2-重大 / S3-严重）
  safetyValue: number;            // 安全-分值（0/1/2/3）
  financialLevel: string;         // 财务-等级
  financialValue: number;         // 财务-分值
  operationalLevel: string;       // 操作-等级
  operationalValue: number;       // 操作-分值
  privacyLevel: string;           // 隐私-等级
  privacyValue: number;           // 隐私-分值
  impactCalculation: number;      // 影响计算（四维度最大值）
  impactLevel: string;            // 影响等级（可忽略/中等/重大/严重）

  // Part D: 威胁分析
  threatSceneId: string;          // 威胁场景ID（TS-1, TS-2...）
  threatSceneDesc: string;        // 威胁场景描述

  // Part D': 最可行攻击路径（系统自动选取可行性等级最高的那条）
  attackPathId: string;           // 攻击路径ID，带⭐标记（如 AP-2⭐）
  attackPathDesc: string;         // 攻击路径描述（AS-1→AS-2→AS-3 格式）
  elapsedTime: string;            // 运行时间(ET)
  elapsedTimeValue: number;       // 运行时间分值（0/1/2/3/4）
  expertise: string;              // 专业知识(SE)
  expertiseValue: number;         // 专业知识分值（0/1/2/3）
  knowledgeOfItem: string;        // 对目标的了解(KoI)
  knowledgeValue: number;         // 了解程度分值（0/1/2/3）
  windowOfOpportunity: string;    // 操作机会窗口(WoO)
  windowValue: number;            // 窗口分值（0/1/2/3）
  equipment: string;              // 设备(Eq)
  equipmentValue: number;         // 设备分值（0/1/2/3）
  feasibilityCalculation: number; // 攻击可行性计算（分值总和）
  feasibilityLevel: string;       // 攻击可行性等级（高/中/低/极低）

  // Part E: 风险处置
  riskRating: number;             // 风险评级（1-5）
  riskTreatmentStrategy: string;  // 风险处置策略（保留/规避/转移/降低）
  cyberGoalNo: string;            // 网络安全目标编号（CS-GOAL-1...）
  cyberGoal: string;              // 网络安全目标描述
  isAcceptable: string;           // 是否可接受（是/否）
  reason?: string;                // 理由（可选）
}
```

---

## 四、核心算法实现

### 4.1 最可行攻击路径选择算法

**选择规则（按优先级）：**
1. 可行性等级最高（高 > 中 > 低 > 极低）
2. 可行性等级相同时，选择分值最高的
3. 分值也相同时，选择创建时间最早的（保证结果稳定）

```typescript
class BestPathSelector {
  private readonly FEASIBILITY_WEIGHTS = {
    'HIGH': 4,
    'MEDIUM': 3,
    'LOW': 2,
    'VERY_LOW': 1
  };

  selectBestPath(paths: AttackPath[]): AttackPath | null {
    if (!paths || paths.length === 0) return null;
    if (paths.length === 1) return paths[0];

    return paths.reduce((best, current) => {
      const bestWeight = this.FEASIBILITY_WEIGHTS[best.feasibilityLevel];
      const currentWeight = this.FEASIBILITY_WEIGHTS[current.feasibilityLevel];

      // 规则1：比较等级权重
      if (currentWeight !== bestWeight) {
        return currentWeight > bestWeight ? current : best;
      }
      // 规则2：等级相同比较分值
      if (current.feasibilityScore !== best.feasibilityScore) {
        return current.feasibilityScore > best.feasibilityScore ? current : best;
      }
      // 规则3：分值相同选择创建时间更早的
      return current.createdAt < best.createdAt ? current : best;
    });
  }
}
```

### 4.2 风险值计算器

基于 ISO/SAE 21434 风险矩阵（影响等级 × 攻击可行性 → 风险值 1-5）：

```typescript
class RiskCalculator {
  // ISO/SAE 21434 风险矩阵
  private readonly RISK_MATRIX = {
    '严重':   { '高': 5, '中': 4, '低': 3, '极低': 2 },
    '重大':   { '高': 4, '中': 3, '低': 2, '极低': 1 },
    '中等':   { '高': 3, '中': 2, '低': 1, '极低': 1 },
    '可忽略': { '高': 2, '中': 1, '低': 1, '极低': 1 }
  };

  calculateRiskRating(impactLevel: string, feasibilityLevel: string): number {
    const riskValue = this.RISK_MATRIX[impactLevel]?.[feasibilityLevel];
    if (riskValue === undefined) {
      throw new Error(`无效参数: 影响等级=${impactLevel}, 可行性=${feasibilityLevel}`);
    }
    return riskValue;
  }

  // 根据四维度分值计算影响等级（取最大值）
  calculateImpactLevel(s: number, f: number, o: number, p: number): string {
    const max = Math.max(s, f, o, p);
    return ['可忽略', '中等', '重大', '严重'][max] || '可忽略';
  }
}
```

### 4.3 枚举值映射器

> ⚠️ 这是修复「专业知识/设备/操作机会窗口显示"无"」问题的关键模块

```typescript
class EnumMapper {
  // 攻击可行性因子（ISO/SAE 21434 附录F）
  private readonly MAPS = {
    elapsedTime: {
      'WITHIN_1_DAY':     '1天以内',
      'WITHIN_1_WEEK':    '1周以内',
      'WITHIN_1_MONTH':   '1个月以内',
      'WITHIN_6_MONTHS':  '6个月以内',
      'MORE_THAN_6_MONTHS': '超过6个月'
    },
    expertise: {
      'LAYMAN':           '外行',
      'PROFICIENT':       '熟练',
      'EXPERT':           '专家',
      'MULTIPLE_EXPERTS': '多位专家'
    },
    knowledgeOfItem: {
      'PUBLIC':               '公开',
      'RESTRICTED':           '受限',
      'CONFIDENTIAL':         '保密',
      'STRICTLY_CONFIDENTIAL':'严格保密'
    },
    windowOfOpportunity: {
      'UNLIMITED': '无限制',
      'EASY':      '简单',
      'MODERATE':  '中等',
      'DIFFICULT': '困难'
    },
    equipment: {
      'STANDARD':         '标准',
      'SPECIALIZED':      '专用',
      'BESPOKE':          '定制',
      'MULTIPLE_BESPOKE': '多种定制'
    },
    feasibilityLevel: {
      'HIGH':     '高',
      'MEDIUM':   '中',
      'LOW':      '低',
      'VERY_LOW': '极低'
    },
    // 影响评估维度
    safetyLevel:      { 'S0':'S0-可忽略','S1':'S1-中等','S2':'S2-重大','S3':'S3-严重' },
    financialLevel:   { 'F0':'F0-可忽略','F1':'F1-中等','F2':'F2-重大','F3':'F3-严重' },
    operationalLevel: { 'O0':'O0-可忽略','O1':'O1-中等','O2':'O2-重大','O3':'O3-严重' },
    privacyLevel:     { 'P0':'P0-可忽略','P1':'P1-中等','P2':'P2-重大','P3':'P3-严重' },
    impactLevel: {
      'NEGLIGIBLE': '可忽略',
      'MODERATE':   '中等',
      'MAJOR':      '重大',
      'SEVERE':     '严重'
    },
    // 风险处置策略
    riskTreatmentStrategy: {
      'RETAIN':   '保留风险',
      'AVOID':    '规避风险',
      'TRANSFER': '转移风险',
      'REDUCE':   '降低风险'
    },
    // 网络安全属性
    securityProperty: {
      'CONFIDENTIALITY': 'C-机密性',
      'INTEGRITY':       'I-完整性',
      'AVAILABILITY':    'A-可用性',
      'AUTHORIZATION':   'Authorization-可授权',
      'NON_REPUDIATION': 'NR-不可抵赖性'
    }
  };

  map(category: keyof typeof this.MAPS, dbValue: string): string {
    const mapped = this.MAPS[category]?.[dbValue];
    if (!mapped) {
      throw new Error(`枚举映射失败: category=${category}, value=${dbValue}`);
    }
    return mapped;
  }
}
```

---

## 五、数据查询优化

### 5.1 批量加载策略

为减少数据库往返次数，一次性并行查询所有数据，构建内存索引。

```typescript
class TARASummaryDataLoader {
  async loadAllData(projectId: string): Promise<TARASummaryDataSet> {
    // 并行查询所有需要的数据
    const [
      threatScenes,
      damageScenes,
      attackPaths,
      assets,
      impactAssessments,
      riskTreatments,
      threatDamageRelations
    ] = await Promise.all([
      this.threatSceneRepo.findByProjectId(projectId),
      this.damageSceneRepo.findByProjectId(projectId),
      this.attackPathRepo.findByProjectId(projectId),
      this.assetRepo.findByProjectId(projectId),
      this.impactAssessmentRepo.findByProjectId(projectId),
      this.riskTreatmentRepo.findByProjectId(projectId),
      this.threatDamageRelationRepo.findByProjectId(projectId)
    ]);

    return {
      threatScenes,
      damageScenes,
      attackPaths,
      assets,
      impactAssessments,
      riskTreatments,
      threatDamageRelations,
      // 构建内存索引（O(1) 查找）
      attackPathsByThreat:    this.groupBy(attackPaths, 'threatSceneId'),
      impactByDamageSceneId:  this.keyBy(impactAssessments, 'damageSceneId'),
      assetById:              this.keyBy(assets, 'id'),
      damageSceneById:        this.keyBy(damageScenes, 'id'),
      threatDamageMap:        this.buildThreatDamageMap(threatDamageRelations)
    };
  }

  /**
   * 按指定字段分组，返回 Map<key, T[]>（一对多）
   */
  private groupBy<T>(items: T[], key: keyof T): Map<any, T[]> {
    const map = new Map<any, T[]>();
    for (const item of items) {
      const k = item[key];
      if (!map.has(k)) map.set(k, []);
      map.get(k)!.push(item);
    }
    return map;
  }

  /**
   * 按指定字段建立唯一索引，返回 Map<key, T>（一对一）
   */
  private keyBy<T>(items: T[], key: keyof T): Map<any, T> {
    const map = new Map<any, T>();
    for (const item of items) {
      map.set(item[key], item);
    }
    return map;
  }

  /**
   * 构建威胁场景 → 损害场景ID列表 的映射（N:N 关系）
   */
  private buildThreatDamageMap(
    relations: ThreatDamageRelation[]
  ): Map<string, string[]> {
    const map = new Map<string, string[]>();
    for (const rel of relations) {
      if (!map.has(rel.threatSceneId)) map.set(rel.threatSceneId, []);
      map.get(rel.threatSceneId)!.push(rel.damageSceneId);
    }
    return map;
  }
}
```

### 5.2 SQL 优化（使用窗口函数选取最可行路径）

> ⚠️ **数据库方言说明**：以下 SQL 使用 `DISTINCT ON` 语法，为 **PostgreSQL 专有**。若使用 MySQL / SQL Server，需改用 `ROW_NUMBER() OVER (PARTITION BY ts.id ORDER BY ...)` 窗口函数实现等效逻辑。

```sql
WITH ThreatWithBestPath AS (
  SELECT DISTINCT ON (ts.id)
    ts.id            AS threat_id,
    ts.description   AS threat_desc,
    ap.id            AS best_path_id,
    ap.description   AS best_path_desc,
    ap.elapsed_time,
    ap.expertise,
    ap.knowledge_of_item,
    ap.window_of_opportunity,
    ap.equipment,
    ap.feasibility_level,
    ap.feasibility_score
  FROM threat_scenes ts
  INNER JOIN attack_paths ap ON ts.id = ap.threat_scene_id
  WHERE ts.project_id = :projectId
  ORDER BY ts.id,
    CASE ap.feasibility_level
      WHEN 'HIGH' THEN 4 WHEN 'MEDIUM' THEN 3
      WHEN 'LOW'  THEN 2 WHEN 'VERY_LOW' THEN 1
    END DESC,
    ap.feasibility_score DESC,
    ap.created_at ASC
)
SELECT
  t.*,
  ds.id            AS damage_id,
  ds.description   AS damage_desc,
  ds.security_property,
  a.type           AS asset_type,
  a.serial_no      AS asset_serial_no,
  a.name           AS asset_name,
  ia.safety_level, ia.safety_value,
  ia.financial_level, ia.financial_value,
  ia.operational_level, ia.operational_value,
  ia.privacy_level, ia.privacy_value,
  ia.impact_level,
  rt.risk_rating, rt.strategy,
  rt.cyber_goal_no, rt.cyber_goal,
  rt.is_acceptable, rt.reason
FROM ThreatWithBestPath t
INNER JOIN threat_damage_relations tdr ON t.threat_id = tdr.threat_scene_id
INNER JOIN damage_scenes ds ON tdr.damage_scene_id = ds.id
INNER JOIN assets a ON ds.asset_id = a.id
LEFT  JOIN impact_assessments ia ON ds.id = ia.damage_scene_id
LEFT  JOIN risk_treatments rt
  ON t.threat_id = rt.threat_scene_id AND ds.id = rt.damage_scene_id
ORDER BY t.threat_id, ds.id;
```

---

## 六、Excel 生成详细实现

### 6.1 双行表头规格

根据 PRD §3.7.6，第一行为分组标题（合并单元格），第二行为具体字段：

| 分组（第一行） | 列范围 | 列数 | 包含字段（第二行） |
| ------------- | ------ | ---- | ---------------- |
| 资产识别 | A-D | 4列 | 系统级资产类型、资产序号、组件级资产名称、资产属性 |
| 损害场景 | E-F | 2列 | 损害场景ID、损害场景描述 |
| 影响分析 | G-P | 10列 | Safety(等级/分值)、Financial(等级/分值)、Operational(等级/分值)、Privacy(等级/分值)、影响计算、影响等级 |
| 威胁分析 | Q-R | 2列 | 威胁场景ID、威胁场景描述 |
| 最可行攻击路径 | S-AF | **14列** | 攻击路径ID⭐、攻击路径描述、ET(等级/分值)、SE(等级/分值)、KoI(等级/分值)、WoO(等级/分值)、Eq(等级/分值)、可行性计算、可行性等级 |
| 风险处置 | AG-AL | 6列 | 风险评级、风险处置策略、网络安全目标编号、网络安全目标、是否可接受、理由 |

> ⚠️ **列数说明**：Part D' 共 14 列（对应 PRD §3.7.3 D3-D16），原方案误写为 13 列已修正。

**总计：38列**（4+2+10+2+14+6）

### 6.2 预设列宽

| 列 | 字段 | 宽度 |
|---|------|------|
| A | 系统级资产类型 | 15 |
| B | 资产序号 | 12 |
| C | 组件级资产名称 | 20 |
| D | 资产属性 | 15 |
| E | 损害场景ID | 12 |
| F | 损害场景描述 | 30 |
| G-N | 影响分析等级/分值 | 15/10 |
| O | 影响计算 | 10 |
| P | 影响等级 | 12 |
| Q | 威胁场景ID | 12 |
| R | 威胁场景描述 | 30 |
| S | 攻击路径ID⭐ | 15 |
| T | 攻击路径描述 | 40 |
| U-AD | 五维因子等级/分值 | 15/10 |
| AE | 攻击可行性计算 | 12 |
| AF | 攻击可行性等级 | 15 |
| AG | 风险评级 | 10 |
| AH | 风险处置策略 | 15 |
| AI | 网络安全目标编号 | 18 |
| AJ | 网络安全目标 | 50 |
| AK | 是否可接受 | 12 |
| AL | 理由 | 30 |

### 6.3 打印配置

- 纸张：A4 横向
- 每页重复打印前两行表头
- 自适应宽度，高度不限

---

## 七、行展开逻辑（核心）

对应 PRD §3.7.4，以**「威胁场景 × 损害场景」**为最小粒度：

```typescript
async function generateSummaryData(projectId: string): Promise<TARASummaryRow[]> {
  const data = await loader.loadAllData(projectId);
  const rows: TARASummaryRow[] = [];

  for (const threat of data.threatScenes) {
    // 步骤1：获取最可行攻击路径（无则跳过该威胁场景）
    const allPaths = data.attackPathsByThreat.get(threat.id) || [];
    const bestPath = selector.selectBestPath(allPaths);
    if (!bestPath) {
      logger.warn(`威胁场景 ${threat.id} 无攻击路径，已排除`);
      continue;
    }

    // 步骤2：遍历该威胁场景关联的每个损害场景
    const damageIds = data.threatDamageMap.get(threat.id) || [];
    if (damageIds.length === 0) {
      logger.warn(`威胁场景 ${threat.id} 无关联损害场景，已排除`);
      continue;
    }

    for (const damageId of damageIds) {
      const damage = data.damageSceneById.get(damageId);  // O(1) 查找
      const asset = data.assetById.get(damage.assetId);
      const impact = data.impactByDamageSceneId.get(damageId);

      if (!damage || !asset || !impact) {
        logger.warn(`数据不完整，跳过: damageId=${damageId}`);
        continue;
      }

      // 步骤3：计算风险值
      const impactLevelZh = enumMapper.map('impactLevel', impact.impactLevel);
      const feasibilityLevelZh = enumMapper.map('feasibilityLevel', bestPath.feasibilityLevel);
      const riskRating = riskCalculator.calculateRiskRating(impactLevelZh, feasibilityLevelZh);

      // 步骤4：查询风险处置
      const riskTreatment = data.riskTreatments.find(
        rt => rt.threatSceneId === threat.id && rt.damageSceneId === damageId
      );

      // 步骤5：构建行数据（枚举值全部映射为展示文本）
      rows.push(buildRow(threat, damage, asset, impact, bestPath, riskRating, riskTreatment));
    }
  }

  return rows;
}

/**
 * 构建单行数据
 * 负责将原始数据库对象映射为 TARASummaryRow，所有枚举值在此统一转换
 */
function buildRow(
  threat: ThreatScene,
  damage: DamageScene,
  asset: Asset,
  impact: ImpactAssessment,
  bestPath: AttackPath,
  riskRating: number,
  riskTreatment?: RiskTreatment
): TARASummaryRow {
  return {
    // Part A: 资产识别
    assetType: asset.type,                                                    // 组件/通道/数据流（直接使用，无需映射）
    assetSerialNo: asset.serialNo,                                            // COMP-1, CH-1, DATAFLOW-1
    assetName: asset.name,
    assetProperties: enumMapper.map('securityProperty', damage.securityProperty), // 取损害场景的安全属性

    // Part B: 损害场景
    damageSceneId: damage.id,
    damageSceneDesc: damage.description,

    // Part C: 影响分析
    safetyLevel: enumMapper.map('safetyLevel', impact.safetyLevel),           // S0-可忽略 / S1-中等 / ...
    safetyValue: impact.safetyValue,
    financialLevel: enumMapper.map('financialLevel', impact.financialLevel),
    financialValue: impact.financialValue,
    operationalLevel: enumMapper.map('operationalLevel', impact.operationalLevel),
    operationalValue: impact.operationalValue,
    privacyLevel: enumMapper.map('privacyLevel', impact.privacyLevel),
    privacyValue: impact.privacyValue,
    impactCalculation: Math.max(
      impact.safetyValue,
      impact.financialValue,
      impact.operationalValue,
      impact.privacyValue
    ),
    impactLevel: enumMapper.map('impactLevel', impact.impactLevel),

    // Part D: 威胁分析
    threatSceneId: threat.id,
    threatSceneDesc: threat.description,

    // Part D': 最可行攻击路径（枚举值全部映射）
    attackPathId: `${bestPath.id}⭐`,
    attackPathDesc: bestPath.description,
    elapsedTime: enumMapper.map('elapsedTime', bestPath.elapsedTime),
    elapsedTimeValue: bestPath.elapsedTimeValue,
    expertise: enumMapper.map('expertise', bestPath.expertise),               // ⚠️ 修复"无"的关键
    expertiseValue: bestPath.expertiseValue,
    knowledgeOfItem: enumMapper.map('knowledgeOfItem', bestPath.knowledgeOfItem),
    knowledgeValue: bestPath.knowledgeValue,
    windowOfOpportunity: enumMapper.map('windowOfOpportunity', bestPath.windowOfOpportunity), // ⚠️ 修复"无"的关键
    windowValue: bestPath.windowValue,
    equipment: enumMapper.map('equipment', bestPath.equipment),               // ⚠️ 修复"无"的关键
    equipmentValue: bestPath.equipmentValue,
    feasibilityCalculation: bestPath.feasibilityScore,
    feasibilityLevel: enumMapper.map('feasibilityLevel', bestPath.feasibilityLevel),

    // Part E: 风险处置（风险处置可能尚未填写，字段允许为空）
    riskRating,
    riskTreatmentStrategy: riskTreatment
      ? enumMapper.map('riskTreatmentStrategy', riskTreatment.strategy)
      : '',
    cyberGoalNo: riskTreatment?.cyberGoalNo || '',
    cyberGoal: riskTreatment?.cyberGoal || '',
    isAcceptable: riskTreatment?.isAcceptable || '',
    reason: riskTreatment?.reason
  };
}
```

---

## 八、特殊场景处理

对应 PRD §3.7.5：

| 场景 | 处理逻辑 | 实现位置 |
|-----|---------|---------|
| 威胁场景无攻击路径 | `selectBestPath()` 返回 null → 跳过该威胁场景 | BestPathSelector |
| 损害场景无威胁场景 | `threatDamageMap.get()` 为空 → 跳过该损害场景 | generateSummaryData |
| 多损害场景关联同一威胁场景 | 展开为多行，攻击路径信息重复显示 | generateSummaryData 内层循环 |
| 多条路径可行性相同 | 选分值更高的；再相同则选创建时间更早的 | BestPathSelector |

---

## 九、数据验证

导出前执行以下验证，发现 P0 问题时中断并报错：

```typescript
function validateRows(rows: TARASummaryRow[]): ValidationResult {
  const errors: string[] = [];

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const pos = `第${i + 3}行`;

    // 必填字段
    if (!row.threatSceneId)  errors.push(`${pos}: 威胁场景ID为空`);
    if (!row.damageSceneId)  errors.push(`${pos}: 损害场景ID为空`);
    if (!row.attackPathId)   errors.push(`${pos}: 攻击路径ID为空`);

    // 枚举值不得为"无"
    if (row.expertise === '无')           errors.push(`${pos}: 专业知识值为"无"`);
    if (row.windowOfOpportunity === '无') errors.push(`${pos}: 操作机会窗口值为"无"`);
    if (row.equipment === '无')           errors.push(`${pos}: 设备值为"无"`);

    // 风险值范围
    if (row.riskRating < 1 || row.riskRating > 5) {
      errors.push(`${pos}: 风险值 ${row.riskRating} 超出范围[1-5]`);
    }

    // 攻击路径标记
    if (!row.attackPathId.includes('⭐')) {
      errors.push(`${pos}: 攻击路径ID缺少⭐标记`);
    }
  }

  return { isValid: errors.length === 0, errors };
}
```

---

## 十、变更记录

| 版本 | 日期 | 修改人 | 修改内容 |
| ---- | ---- | ------ | -------- |
| v1.0 | 2026-02-28 | - | 初稿，基于 PRD v1.0 编写 |
| v1.1 | 2026-02-28 | - | Review 修正：列数 37→38，Part D' 13→14列，列范围修正；补充 buildRow/groupBy/keyBy 实现；新增 §十一~§十四 |
| v1.2 | 2026-02-28 | - | Review 修正：§6.2 列宽表格 AE/AF 列号偏移修正，补充 AL 列；补充 damageSceneById 内存索引修复 O(n) 查找；ExcelJS headerRow.values 空字符串改为 null；§5.2 补充 PostgreSQL 方言说明 |

---

## 十一、API 接口定义

### 11.1 导出接口

**路径：** `POST /api/projects/{projectId}/reports/export`

**请求参数：**

| 参数 | 位置 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- | ---- |
| projectId | path | string | 是 | 项目ID |
| sheets | body | string[] | 否 | 指定导出的 Sheet，默认全部导出 |

**请求示例：**

```json
{
  "sheets": ["TARA总表"]
}
```

**响应（成功）：**

```http
HTTP 200
Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
Content-Disposition: attachment; filename="TARA报告_{projectName}_{yyyyMMdd}.xlsx"
```

**响应（失败）：**

```json
{
  "code": 422,
  "message": "数据验证失败",
  "errors": [
    "第3行: 专业知识值为\"无\"",
    "第5行: 攻击路径ID缺少⭐标记"
  ]
}
```

**错误码：**

| HTTP 状态码 | 说明 |
| ----------- | ---- |
| 400 | 请求参数错误（如 projectId 格式不合法） |
| 404 | 项目不存在 |
| 422 | 数据验证失败，返回具体错误列表 |
| 500 | 服务器内部错误 |
| 504 | 导出超时（数据量过大） |

---

## 十二、错误处理策略

### 12.1 分级处理原则

| 错误类型 | 处理方式 | 是否中断导出 |
| -------- | -------- | ------------ |
| 枚举值映射失败 | 抛出异常，返回 422 | 是 |
| 风险矩阵查表失败 | 抛出异常，返回 422 | 是 |
| 关联数据缺失（资产/影响评估） | 记录 WARN，跳过该行 | 否 |
| 威胁场景无攻击路径 | 记录 WARN，跳过该威胁场景 | 否 |
| 损害场景无威胁关联 | 记录 WARN，跳过该损害场景 | 否 |
| Excel 生成异常 | 记录 ERROR，返回 500 | 是 |
| 导出超时 | 记录 ERROR，返回 504 | 是 |

### 12.2 枚举值映射失败

**场景：** 数据库中存储了映射表中不存在的枚举值（如历史脏数据）。

**处理：**

```typescript
// EnumMapper.map() 抛出异常
throw new Error(`枚举映射失败: category=${category}, value=${dbValue}`);

// 上层捕获后返回 422
{
  "code": 422,
  "message": "枚举值映射失败，请检查数据",
  "errors": ["攻击路径 AP-3 的 expertise 字段值 'UNKNOWN' 无法映射"]
}
```

### 12.3 关联数据缺失（降级处理）

**场景：** 损害场景找不到对应资产，或影响评估未填写。

**处理：**

```typescript
if (!damage || !asset || !impact) {
  logger.warn(`数据不完整，跳过: damageId=${damageId}, ` +
    `hasDamage=${!!damage}, hasAsset=${!!asset}, hasImpact=${!!impact}`);
  continue;  // 跳过该行，不中断整体导出
}
```

**导出完成后**，在响应 Header 中附加跳过记录数：

```http
X-Skipped-Rows: 3
X-Skip-Reason: incomplete-data
```

### 12.4 超时控制

```typescript
// 设置导出超时时间
const EXPORT_TIMEOUT_MS = 60_000;  // 60 秒

const exportPromise = generator.exportToExcel(projectId, workbook);
const timeoutPromise = new Promise((_, reject) =>
  setTimeout(() => reject(new Error('导出超时')), EXPORT_TIMEOUT_MS)
);

await Promise.race([exportPromise, timeoutPromise]);
```

---

## 十三、Excel 样式实现

### 13.1 双行表头构建

```typescript
function buildDoubleHeader(worksheet: Worksheet): void {
  // 第一行：分组标题（合并单元格）
  const groupMerges: Array<[string, string, string]> = [
    ['A1', 'D1',  '资产识别'],
    ['E1', 'F1',  '损害场景'],
    ['G1', 'P1',  '影响分析'],
    ['Q1', 'R1',  '威胁分析'],
    ['S1', 'AF1', '最可行攻击路径'],
    ['AG1','AL1', '风险处置']
  ];

  for (const [start, end, label] of groupMerges) {
    worksheet.mergeCells(`${start}:${end}`);
    const cell = worksheet.getCell(start);
    cell.value = label;
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF4472C4' } };
    cell.font = { bold: true, color: { argb: 'FFFFFFFF' }, size: 11 };
    cell.alignment = { horizontal: 'center', vertical: 'middle' };
  }

  // 第二行：具体字段名
  const fieldHeaders = [
    // Part A
    '系统级资产类型', '资产序号', '组件级资产名称', '资产属性',
    // Part B
    '损害场景ID', '损害场景描述',
    // Part C
    '安全-等级', '安全-分值', '财务-等级', '财务-分值',
    '操作-等级', '操作-分值', '隐私-等级', '隐私-分值',
    '影响计算', '影响等级',
    // Part D
    '威胁场景ID', '威胁场景描述',
    // Part D'
    '攻击路径ID⭐', '攻击路径描述',
    '运行时间(ET)', 'ET分值', '专业知识(SE)', 'SE分值',
    '对目标的了解(KoI)', 'KoI分值', '操作机会窗口(WoO)', 'WoO分值',
    '设备(Eq)', 'Eq分值', '攻击可行性计算', '攻击可行性等级',
    // Part E
    '风险评级', '风险处置策略', '网络安全目标编号',
    '网络安全目标', '是否可接受', '理由'
  ];

  const headerRow = worksheet.getRow(2);
  headerRow.values = [null, ...fieldHeaders];  // 第1列从索引1开始，索引0用null占位
  headerRow.eachCell(cell => {
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFD9E1F2' } };
    cell.font = { bold: true, size: 10 };
    cell.alignment = { horizontal: 'center', vertical: 'middle', wrapText: true };
    cell.border = {
      top: { style: 'thin' }, left: { style: 'thin' },
      bottom: { style: 'thin' }, right: { style: 'thin' }
    };
  });

  // 冻结前两行
  worksheet.views = [{ state: 'frozen', xSplit: 0, ySplit: 2 }];
}
```

### 13.2 更新后的预设列宽

| 列 | 字段 | 宽度 |
| -- | ---- | ---- |
| A | 系统级资产类型 | 15 |
| B | 资产序号 | 12 |
| C | 组件级资产名称 | 20 |
| D | 资产属性 | 15 |
| E | 损害场景ID | 12 |
| F | 损害场景描述 | 30 |
| G/I/K/M | 影响分析各维度等级 | 15 |
| H/J/L/N | 影响分析各维度分值 | 10 |
| O | 影响计算 | 10 |
| P | 影响等级 | 12 |
| Q | 威胁场景ID | 12 |
| R | 威胁场景描述 | 30 |
| S | 攻击路径ID⭐ | 15 |
| T | 攻击路径描述 | 40 |
| U/W/Y/AA/AC | 五维因子等级 | 15 |
| V/X/Z/AB/AD | 五维因子分值 | 10 |
| AE | 攻击可行性计算 | 12 |
| AF | 攻击可行性等级 | 15 |
| AG | 风险评级 | 10 |
| AH | 风险处置策略 | 15 |
| AI | 网络安全目标编号 | 18 |
| AJ | 网络安全目标 | 50 |
| AK | 是否可接受 | 12 |
| AL | 理由 | 30 |

---

## 十四、性能指标

### 14.1 性能目标

| 指标 | 目标值 | 测试方法 |
| ---- | ------ | -------- |
| 导出时间（正常规模） | < 10 秒 | 50个威胁场景 × 200个损害场景 |
| 导出时间（大规模） | < 30 秒 | 200个威胁场景 × 1000个损害场景 |
| 数据库查询次数 | < 10 次 | SQL 日志统计 |
| 内存峰值 | < 500 MB | 进程内存监控 |
| Excel 文件大小 | < 5 MB（1000行） | 文件大小检查 |

### 14.2 支持的数据规模

| 场景 | 威胁场景数 | 损害场景数 | 预估行数 |
| ---- | ---------- | ---------- | -------- |
| 小型项目 | ≤ 20 | ≤ 50 | ≤ 200 |
| 中型项目 | ≤ 100 | ≤ 300 | ≤ 1500 |
| 大型项目 | ≤ 300 | ≤ 1000 | ≤ 5000 |

---

## 十五、日志记录规范

### 15.1 日志级别

| 级别 | 使用场景 |
| ---- | -------- |
| ERROR | 导出失败、枚举映射失败、Excel 生成异常 |
| WARN | 数据不完整跳过记录、威胁场景无攻击路径 |
| INFO | 导出开始/完成、各阶段数据量统计 |
| DEBUG | 最可行路径选择结果、风险值计算过程 |

### 15.2 关键日志节点

```typescript
// 1. 导出开始
logger.info(`[TARA导出] 开始 projectId=${projectId}`);

// 2. 数据加载完成
logger.info(`[TARA导出] 数据加载完成: 威胁场景=${threatScenes.length}, ` +
  `损害场景=${damageScenes.length}, 攻击路径=${attackPaths.length}`);

// 3. 跳过记录（WARN）
logger.warn(`[TARA导出] 威胁场景 ${threat.id} 无攻击路径，已排除`);
logger.warn(`[TARA导出] 数据不完整跳过: damageId=${damageId}`);

// 4. 数据验证
logger.info(`[TARA导出] 数据验证通过，共 ${rows.length} 行`);

// 5. 导出完成
logger.info(`[TARA导出] 完成 projectId=${projectId}, ` +
  `rows=${rows.length}, duration=${Date.now() - startTime}ms`);
```

---

## 十六、PRD 勘误记录

在技术方案编写过程中，发现 PRD 存在以下需要修正的地方，供 PM 参考：

| 位置 | 问题描述 | 建议修正 |
| ---- | -------- | -------- |
| §3.7.3 Part E | 字段清单只列了 E1-E5（5个字段），遗漏了"理由"字段 | 新增 E6: 理由（可选） |
| §3.7.6 表头设计 | 风险处置分组已包含"理由"，与 §3.7.3 不一致 | 以 §3.7.6 为准，§3.7.3 补充 E6 |
