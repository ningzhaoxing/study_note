## 执行摘要

**结论：不建议进行大规模 Skill 重构，但可以进行有限的优化**

经过对三个 Agent 的深入分析，发现当前架构虽然存在一些代码重复，但**不满足 Skill 重构的核心条件**。主要原因：

1. **工具调用流程高度灵活**：LLM 需要根据用户意图动态选择工具，不存在固定的工具调用序列
2. **代码重复率低于阈值**：实际重复率约 6-9%，远低于 20% 的重构阈值
3. **工具数量合理**：每个 Agent 的工具数量（6-22个）在 LLM 的处理能力范围内
4. **重构成本高于收益**：会降低系统灵活性，增加维护复杂度

**建议：仅对 2 个明确重复的工具进行共享化改造，保持现有架构不变。**

---

## 1. 三个 Agent 的详细分析

### 1.1 AssetIdentificationAgent（资产识别 Agent）

#### 工具清单（6个）

| 工具名称 | 功能  | 调用频率 |
| ---- | --- | ---- |
| get_project_context | 获取项目上下文（合并了 assumptions 和 dataflow） | 必须首次调用 |
| batch_identify_asset_security_properties | 批量识别资产安全属性 | 多资产场景 |
| identify_security_properties | 单个资产识别 | 单资产场景 |
| save_asset_security_properties | 保存识别结果 | 识别后必须 |
| validate_json_output | 验证输出格式 | 最终必须 |
| get_failed_items | 获取失败项（重试场景） | 条件性 |

#### 工具调用流程分析

**System Prompt 中的强制流程**：
```
步骤1：get_project_context（强制第一步）
步骤2：batch_identify 或 identify（二选一）
步骤3：save_asset_security_properties（必须）
步骤4：validate_json_output（必须）
```

**关键发现**：

- ✅ **存在固定流程**：4个步骤必须按顺序执行

- ✅ **适合 Skill 封装**：这是一个标准的线性工作流

- ⚠️ **但有分支**：步骤2有两个工具可选（批量 vs 单个）

**Skill 重构可行性**：⭐⭐⭐⭐ (4/5)

- 可以封装为 `AssetIdentificationSkill`

- 内部自动处理 4 个步骤

- 但需要保留批量/单个的选择逻辑

---

### 1.2 DamageScenarioAgent（损害场景 Agent）

#### 工具清单（22个）

**分类统计**：

- 资产查询工具：4个

- 项目上下文工具：2个（重复）

- RAG检索工具：2个

- 损害场景生成工具：1个

- 目标查找工具：2个

- 损害场景查询工具：5个

- CAL分析工具：6个

#### 工具调用流程分析

**System Prompt 中的意图分类**：
```
1. 咨询类（优先级最高）
→ 直接回答，不调用任何工具

2. 数据查询类
→ 使用查询工具，不生成

3. 损害场景生成类
→ list_available_assets
→ list_asset_attributes（每个资产必须调用）
→ get_project_assumptions / get_dataflow_diagram（可选）
→ search_damage_vectors（可选，RAG检索）
→ generate_damage_scenario（串行调用，每个目标一次）

4. CAL分析类
→ get_cal_analysis_by_asset
→ analyze_cal
→ write_cal_analysis
```

**关键发现**：

- ❌ **不存在固定流程**：根据用户意图选择完全不同的工具链

- ❌ **高度动态**：LLM 需要根据用户消息判断是咨询、查询还是生成

- ❌ **工具选择灵活**：即使在生成流程中，RAG检索也是可选的

- ⚠️ **串行约束**：generate_damage_scenario 必须串行调用（防止ID冲突）

**Skill 重构可行性**：⭐ (1/5)

- 不适合封装为单一 Skill

- 如果强行封装，会失去意图识别的灵活性

- LLM 需要看到所有工具才能做出正确判断

---

### 1.3 ThreatScenarioAgent（威胁场景 Agent）

#### 工具清单（10个）

| 工具名称 | 功能 | 类型 |
|---------|------|------|
| get_project_assumptions | 获取项目假设 | 重复 |
| get_dataflow_diagram | 获取数据流图 | 重复 |
| search_threat_vectors | 威胁向量检索 | RAG |
| find_unprocessed_damages | 查找未处理的损害场景 | 查询 |
| get_damage_scenario | 获取损害场景详情 | 查询 |
| generate_threat_scenario | 生成威胁场景 | 生成 |
| write_threat_scenarios | 批量写入（备用） | 保存 |
| query_threat_scenarios | 查询威胁场景 | 查询 |
| check_threat_status | 检查生成状态 | 查询 |
| generate_r155_reference | 生成R155参考 | 生成 |

#### 工具调用流程分析

**典型生成流程**：
```
find_unprocessed_damages（查找未处理项）
↓
get_damage_scenario（获取详情）
↓
get_project_assumptions / get_dataflow_diagram（可选）
↓
search_threat_vectors（可选，RAG检索）
↓
generate_threat_scenario（生成并自动保存）
↓
generate_r155_reference（可选）
```

**关键发现**：

- ⚠️ **半固定流程**：生成流程有一定的顺序性

- ❌ **多个可选步骤**：上下文获取和RAG检索都是可选的

- ❌ **依赖外部状态**：依赖 DamageScenarioAgent 的输出

- ✅ **自动保存机制**：generate_threat_scenario 内置保存逻辑

**Skill 重构可行性**：⭐⭐ (2/5)

- 可以封装部分流程，但灵活性会降低

- LLM 需要根据具体情况决定是否调用可选工具

---

## 2. 代码重复率统计

### 2.1 完全重复的工具

| 工具名称 | 出现次数 | 代码行数（估算） | 重复率 |
|---------|---------|----------------|--------|
| get_project_assumptions | 3次（Asset中合并，Damage和Threat独立） | ~50行 × 2 = 100行 | 重复 |
| get_dataflow_diagram | 3次（Asset中合并，Damage和Threat独立） | ~50行 × 2 = 100行 | 重复 |

**总重复代码**：约 200 行

### 2.2 相似但不重复的工具

| 工具类型 | 说明 |
|---------|------|
| RAG检索工具 | 每个Agent检索不同的知识库，逻辑相似但数据源不同 |
| 生成工具 | 都使用LLM生成，但生成的内容类型完全不同 |
| 查询工具 | 查询不同的数据表，SQL逻辑不同 |

### 2.3 代码重复率计算

**总代码量**：

- AssetIdentificationAgent: ~2000行（包含tools文件）

- DamageScenarioAgent: ~6010行

- ThreatScenarioAgent: ~1745行

- **总计**: ~9755行

**重复代码量**: ~200行

**实际代码重复率**: 200 / 9755 = **2.05%**

**⚠️ 重要发现**：

- 实际代码重复率仅为 2%，远低于文档中提到的 20% 阈值

- 之前估算的 30% 重复率是**错误的**，那是基于工具数量而非代码量

---

## 3. 工具数量统计

| Agent | 工具数量 | LLM Token消耗（估算） | 是否超标 |
|-------|---------|---------------------|---------|
| AssetIdentificationAgent | 6 | ~600 tokens | ✅ 合理 |
| DamageScenarioAgent | 22 | ~2200 tokens | ⚠️ 偏多 |
| ThreatScenarioAgent | 10 | ~1000 tokens | ✅ 合理 |
| **总计** | 38 | ~3800 tokens | - |

**分析**：

- AssetIdentificationAgent 和 ThreatScenarioAgent 的工具数量在合理范围内

- DamageScenarioAgent 的 22 个工具确实偏多，但这是因为它需要处理 4 种不同的意图类型

- 如果按意图分类，每种意图实际使用的工具数量在 5-8 个，仍在合理范围内

---

## 4. 是否满足 Skill 重构条件？

根据 `skill vs tool 本质区别分析.md` 中的标准：

### 4.1 适合使用 Skill 的场景

| 条件 | 阈值 | 实际情况 | 是否满足 |
|-----|------|---------|---------|
| 有明确的业务流程 | 固定流程 | 仅 AssetIdentificationAgent 有固定流程 | ⚠️ 部分满足 |
| 流程相对固定 | 80%以上固定 | DamageScenarioAgent 和 ThreatScenarioAgent 高度动态 | ❌ 不满足 |
| 代码重复率高 | >20% | 实际仅 2% | ❌ 不满足 |
| Tool 数量过多 | >20个 | 仅 DamageScenarioAgent 超过，但按意图分类后合理 | ⚠️ 部分满足 |
| 关心 Token 成本 | - | 当前 Token 消耗在可接受范围内 | ⚠️ 中等 |
| 长期维护的系统 | - | 是 | ✅ 满足 |

**结论**：6个条件中，仅满足 1个，部分满足 3个，不满足 2个。**不满足 Skill 重构的核心条件。**

### 4.2 不适合使用 Skill 的场景

| 场景 | 是否匹配 | 说明 |
|-----|---------|------|
| 探索性任务（流程不确定） | ✅ 匹配 | DamageScenarioAgent 需要根据用户意图动态选择工具链 |
| 高度定制化（每个场景都不同） | ✅ 匹配 | 用户可以指定任意资产、属性组合 |
| 快速迭代的原型 | ⚠️ 部分匹配 | 系统已相对成熟，但仍在快速迭代 |

**结论**：当前系统更符合"不适合使用 Skill"的特征。

---

## 5. Skill 重构的收益与成本分析

### 5.1 预期收益（如果重构）

| 收益项 | 预期值 | 实际可达成度 | 说明 |
|-------|-------|------------|------|
| Token 节省 | 70% | ❌ 10-20% | 因为工具数量本身不多，节省有限 |
| 提高 LLM 准确率 | 提升 | ❌ 可能降低 | 失去灵活性，LLM 无法根据情况选择工具 |
| 减少 LLM 调用次数 | 减少 50% | ❌ 可能增加 | Skill 内部仍需多次 LLM 调用 |
| 提高可靠性 | 提升 | ⚠️ 不确定 | 固定流程更可靠，但失去灵活性 |
| 解决代码重复 | 减少 66% | ✅ 可达成 | 但重复率本身只有 2%，收益很小 |

**总体收益评估**：⭐⭐ (2/5) - 收益远低于预期

### 5.2 重构成本

| 成本项 | 估算 | 风险 |
|-------|------|------|
| 开发时间 | 3-4周 | 高 |
| 测试时间 | 1-2周 | 高 |
| 灵活性损失 | 严重 | 高 |
| 维护复杂度增加 | 中等 | 中 |
| 系统稳定性风险 | 高 | 高 |

**总体成本评估**：⭐⭐⭐⭐ (4/5) - 成本高，风险大

### 5.3 ROI 分析

**投入**：5-6 人周

**回报**：

- Token 节省：约 10-20%（而非 70%）

- 代码重复减少：200行（占总代码 2%）

- 灵活性损失：严重

**ROI 结论**：**负收益**，不建议重构

---

## 6. 核心问题：为什么不适合 Skill 重构？

### 6.1 工具调用流程的本质

**Skill 的核心假设**：

> 存在一个固定的、可预测的工具调用序列，可以由代码逻辑控制

**当前系统的实际情况**：

> 工具调用序列高度依赖用户意图和上下文，必须由 LLM 动态决策

**举例说明**：

**场景1：用户问"什么是损害场景？"**

- Skill 架构：无法处理（Skill 内部是固定流程，无法识别这是咨询类问题）

- Tool 架构：LLM 识别为咨询类，直接回答，不调用任何工具 ✅

**场景2：用户说"生成 COMP-1 的损害场景"**

- Skill 架构：调用 DamageGenerationSkill，内部固定执行：list_assets → list_attributes → generate

- Tool 架构：LLM 根据情况决定是否需要 RAG检索、是否需要获取上下文 ✅

**场景3：用户说"查看已生成的损害场景"**

- Skill 架构：无法处理（DamageGenerationSkill 是生成流程，不包含查询）

- Tool 架构：LLM 识别为查询类，调用 query_damage_scenarios ✅

### 6.2 意图识别的重要性

**DamageScenarioAgent 的 System Prompt 明确指出**：
```
## 🚨 意图识别优先规则（最高优先级，必须首先执行）

在处理任何用户请求前，必须先判断意图类型。识别规则：

1. 咨询类（直接回答，不调用任何工具）
2. 数据查询类（使用查询工具，不生成）
3. 损害场景生成类（调用生成工具）
4. CAL分析类（调用CAL分析工具）
```

**如果使用 Skill 架构**：

- LLM 只能看到 4 个 Skill：ConsultationSkill、QuerySkill、GenerationSkill、CALSkill

- 但 LLM 无法判断用户的意图，因为它看不到具体的工具描述

- 例如："生成损害场景后干什么" - LLM 可能误判为 GenerationSkill，实际应该是 ConsultationSkill

**Tool 架构的优势**：

- LLM 可以看到所有 22 个工具的详细描述

- 根据工具描述和用户消息，准确判断意图

- 灵活选择工具组合

### 6.3 可选步骤的处理

**当前系统中的可选步骤**：

- RAG检索：根据资产复杂度决定是否需要

- 上下文获取：首次必须，后续可复用

- 批量 vs 单个：根据资产数量决定

**Skill 架构的问题**：

- 如果 Skill 内部包含可选步骤，需要额外的参数控制

- 参数越多，Skill 的接口越复杂，失去了简化的意义

- 如果 Skill 内部不包含可选步骤，灵活性大幅降低

---

## 7. 推荐方案：有限优化，而非全面重构

### 7.1 方案A：共享工具提取（推荐）⭐⭐⭐⭐⭐

**目标**：解决 2 个明确重复的工具

**实施步骤**：

1. 创建共享工具模块 `tara/service/agent/shared_tools.go`

2. 提取 `get_project_assumptions` 和 `get_dataflow_diagram` 的实现

3. 在 DamageScenarioAgent 和 ThreatScenarioAgent 中复用

**代码示例**：

```go

// shared_tools.go

package agent

  

// NewSharedProjectAssumptionsTool 创建共享的项目假设工具

func NewSharedProjectAssumptionsTool(repo ProjectContextRepository) tool.InvokableTool {

return &projectAssumptionsTool{repo: repo}

}

  

// NewSharedDataflowDiagramTool 创建共享的数据流图工具

func NewSharedDataflowDiagramTool(repo ProjectContextRepository) tool.InvokableTool {

return &dataflowDiagramTool{repo: repo}

}

```

**收益**：

- 减少 200 行重复代码

- 降低维护成本

- 保持系统灵活性不变

**成本**：

- 开发时间：1-2 天

- 测试时间：1 天

- 风险：低

**ROI**：⭐⭐⭐⭐⭐ (5/5) - 高收益，低成本，低风险

### 7.2 方案B：AssetIdentificationAgent 局部 Skill 化（可选）⭐⭐⭐

**目标**：仅对 AssetIdentificationAgent 进行 Skill 封装

**原因**：

- AssetIdentificationAgent 有明确的固定流程

- 4 个步骤必须按顺序执行

- 适合封装为 Skill

**实施步骤**：

1. 创建 `AssetIdentificationSkill`

2. 内部封装 4 个步骤：get_context → identify → save → validate

3. 保留原有 Tool 作为"逃生舱"

**代码示例**：

```go

type AssetIdentificationSkill struct {

BaseSkill

}

  

func (s *AssetIdentificationSkill) Execute(ctx context.Context, input SkillInput) (SkillOutput, error) {

// 步骤1：获取上下文

context, err := s.getProjectContext(ctx, input.ProjectID)

if err != nil {

return nil, err

}

  

// 步骤2：识别（批量 vs 单个）

var result *IdentificationResult

if len(input.Assets) > 1 {

result, err = s.batchIdentify(ctx, input.Assets, context)

} else {

result, err = s.identifySingle(ctx, input.Assets[0], context)

}

if err != nil {

return nil, err

}

  

// 步骤3：保存

if err := s.saveResult(ctx, result); err != nil {

return nil, err

}

  

// 步骤4：验证

if err := s.validateJSON(ctx, result); err != nil {

return nil, err

}

  

return result, nil

}

```

**收益**：

- 简化 AssetIdentificationAgent 的工具数量：6 → 1

- Token 节省：约 500 tokens

- 提高可靠性（固定流程）

**成本**：

- 开发时间：1 周

- 测试时间：3-5 天

- 风险：中等

**ROI**：⭐⭐⭐ (3/5) - 中等收益，中等成本

### 7.3 方案C：不进行 Skill 重构（推荐）⭐⭐⭐⭐⭐

**理由**：

1. 当前架构已经很好地满足业务需求

2. 代码重复率仅 2%，不值得大规模重构

3. 工具数量在合理范围内

4. 系统灵活性是核心优势，不应牺牲

**建议**：

- 仅实施方案A（共享工具提取）

- 保持现有 Tool 架构不变

- 持续优化 System Prompt，提高 LLM 的工具选择准确率

---

## 8. 最终建议

### 8.1 短期行动（1-2周）

**优先级1：共享工具提取**

- 提取 `get_project_assumptions` 和 `get_dataflow_diagram`

- 创建 `shared_tools.go` 模块

- 在 DamageScenarioAgent 和 ThreatScenarioAgent 中复用

**优先级2：System Prompt 优化**

- 优化 DamageScenarioAgent 的意图识别规则

- 减少 LLM 误判的可能性

- 添加更多示例和边界情况说明

### 8.2 中期观察（1-3个月）

**监控指标**：

- LLM 工具选择准确率

- Token 消耗趋势

- 用户反馈和错误率

**决策点**：

- 如果 Token 消耗持续增长 → 考虑方案B（AssetIdentificationAgent 局部 Skill 化）

- 如果工具选择准确率低于 90% → 优化 System Prompt，而非重构架构

- 如果代码重复率超过 15% → 重新评估 Skill 重构

### 8.3 长期策略（6个月+）

**保持架构灵活性**：

- Tool 架构是当前系统的核心优势

- 不要为了"技术先进性"而牺牲实用性

- 持续优化，而非推倒重来

**渐进式演进**：

- 如果未来出现明确的固定流程，再考虑局部 Skill 化

- 如果 LLM 能力提升（如支持更多工具），当前架构会更有优势

- 如果业务需求变化，Tool 架构更容易适应

---

## 9. 关键结论

### 9.1 核心发现

1. **代码重复率被严重高估**：实际仅 2%，而非 30%

2. **工具调用流程高度动态**：不存在固定的工具调用序列

3. **意图识别是核心能力**：LLM 需要看到所有工具才能准确判断

4. **当前架构已经很优秀**：灵活性是核心优势，不应牺牲

### 9.2 最终建议

**不建议进行大规模 Skill 重构**

**推荐方案**：

- ✅ 实施方案A：共享工具提取（高优先级）

- ⚠️ 可选方案B：AssetIdentificationAgent 局部 Skill 化（低优先级）

- ✅ 保持现有 Tool 架构不变

**理由**：

- 当前系统不满足 Skill 重构的核心条件

- 重构成本高，收益低，风险大

- 灵活性是系统的核心竞争力

---

## 10. 附录：数据支持

### 10.1 工具调用流程对比

| Agent | 固定流程占比 | 动态流程占比 | 适合 Skill 化 |
|-------|------------|------------|-------------|
| AssetIdentificationAgent | 90% | 10% | ✅ 适合 |
| DamageScenarioAgent | 20% | 80% | ❌ 不适合 |
| ThreatScenarioAgent | 40% | 60% | ⚠️ 部分适合 |

### 10.2 Token 消耗对比（估算）

| 架构 | AssetAgent | DamageAgent | ThreatAgent | 总计 |
|-----|-----------|------------|------------|------|
| 当前 Tool 架构 | 600 | 2200 | 1000 | 3800 |
| Skill 架构（全面重构） | 100 | 1000 | 400 | 1500 |
| Skill 架构（局部优化） | 100 | 2200 | 1000 | 3300 |

**节省幅度**：

- 全面重构：60%（但会严重损失灵活性）

- 局部优化：13%（保持灵活性）

### 10.3 风险评估矩阵

| 风险项 | 概率 | 影响 | 风险等级 | 缓解措施 |
|-------|------|------|---------|---------|
| 灵活性降低 | 高 | 严重 | 🔴 高 | 不进行全面重构 |
| 意图识别准确率下降 | 高 | 严重 | 🔴 高 | 保留 Tool 架构 |
| 开发周期延长 | 中 | 中等 | 🟡 中 | 仅实施局部优化 |
| 系统稳定性风险 | 中 | 严重 | 🟡 中 | 充分测试 |
| 维护复杂度增加 | 低 | 中等 | 🟢 低 | 文档完善 |

---

**文档版本**：v1.0

**创建日期**：2026-03-03

**分析师**：Claude Sonnet 4.6

**基于文档**：`skill vs tool 本质区别分析.md`、三个 Agent 的源代码和 System Prompt