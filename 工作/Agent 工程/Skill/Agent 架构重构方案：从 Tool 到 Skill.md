## 1. 概述

本文档分析了将 TARA 系统中的三个核心 Agent（Asset Identification、Damage Scenario、Threat Scenario）从基于 Tool 的架构重构为基于 Skill 的架构的方案、收益和实施路线。

### 1.1 重构目标

- 提升代码复用性和可维护性
- 减少工具数量和代码重复
- 增强 Agent 的组合能力和灵活性
- 降低长期维护成本

### 1.2 涉及文件

- [asset_identification_agent_v2.go](../service/agent/asset_identification_agent_v2.go) (174 lines)
- [damage_scenario_agent.go](../service/agent/damage_scenario_agent.go) (6010 lines)
- [threat_scenario_agent.go](../service/agent/threat_scenario_agent.go) (1745 lines)

## 2. 当前架构分析

### 2.1 Tool 分布统计

| Agent | Tool 数量 | 主要功能 |
|-------|----------|---------|
| AssetIdentificationAgent | 10+ | 资产识别、安全属性分析 |
| DamageScenarioAgent | 15+ | 损害场景生成、影响评估、CAL分析 |
| ThreatScenarioAgent | 9+ | 威胁场景生成、攻击可行性评估 |
| **总计** | **34+** | - |

### 2.2 代码重复问题

以下 Tool 在多个 Agent 中重复实现：

```
get_project_assumptions → 3个Agent中重复
search_xxx_patterns → 相似的搜索逻辑
find_unprocessed_xxx → 相似的查询逻辑
```

### 2.3 当前架构特点

**优点：**
- 细粒度控制：每个 Tool 职责单一
- 灵活组合：Agent 可以自由选择 Tool
- 易于调试：Tool 级别的日志和监控

**缺点：**
- 工具数量过多（34+ tools）
- 代码重复率高（约30%的工具逻辑重复）
- 维护成本高：修改一个功能需要同步多个 Tool
- 缺乏高层抽象：难以复用完整的业务流程

## 3. Skill 架构设计

### 3.1 Skill 接口定义

```go
// Skill 代表一个可复用的高层能力单元
type Skill interface {
	// Name 返回 Skill 的唯一标识
	Name() string
	// Description 返回 Skill 的功能描述
	Description() string
	// Execute 执行 Skill 的核心逻辑
	Execute(ctx context.Context, input SkillInput) (SkillOutput, error)
	// GetTools 返回 Skill 内部使用的 Tools（可选，用于透明度）
	GetTools() []tool.BaseTool
}
// SkillInput 统一的输入接口
type SkillInput interface {
	Validate() error
}
// SkillOutput 统一的输出接口
type SkillOutput interface {
	GetResult() interface{}
	GetMetadata() map[string]interface{}
}
```

### 3.2 BaseSkill 实现

```go
type BaseSkill struct {
	name        string
	description string
	tools       []tool.BaseTool
	repo        repository.Repository
	logger      *zap.Logger
}
func (s *BaseSkill) Name() string {
	return s.name
}
func (s *BaseSkill) Description() string {
	return s.description
}
func (s *BaseSkill) GetTools() []tool.BaseTool {
	return s.tools
}
```

## 4. 重构方案

### 4.1 方案 A：功能域 Skill（推荐）

将 34+ Tools 重构为 10 个功能域 Skill：

#### 4.1.1 Skill 列表

| Skill 名称 | 封装的 Tools | 功能描述 |
|-----------|-------------|---------|
| **AssetIdentificationSkill** | batch_identify_asset_security_properties, search_assets, get_asset_details | 资产识别和安全属性分析 |
| **DamageScenarioGenerationSkill** | generate_damage_scenario, search_damage_patterns, validate_damage | 损害场景生成和验证 |
| **ImpactAssessmentSkill** | assess_safety_impact, assess_financial_impact, assess_operational_impact, assess_privacy_impact | 多维度影响评估 |
| **CALAnalysisSkill** | analyze_cal, get_cal_history | 网络攻击等级分析 |
| **ThreatScenarioGenerationSkill** | generate_threat_scenario, search_threat_scenarios, validate_threat | 威胁场景生成和验证 |
| **AttackFeasibilitySkill** | assess_attack_feasibility, get_attack_vectors | 攻击可行性评估 |
| **ProjectContextSkill** | get_project_assumptions, get_project_info, update_project_context | 项目上下文管理（共享） |
| **DataQuerySkill** | find_unprocessed_targets, find_unprocessed_damages, query_related_data | 数据查询和过滤（共享） |
| **RAGSearchSkill** | search_knowledge_base, retrieve_similar_cases | RAG 检索（共享） |
| **WorkflowOrchestrationSkill** | orchestrate_tara_workflow, coordinate_agents | 工作流编排 |

#### 4.1.2 代码示例

```go
// AssetIdentificationSkill 实现
type AssetIdentificationSkill struct {
BaseSkill
}
type AssetIdentificationInput struct {
ProjectID string
AssetIDs []string
BatchSize int
}
type AssetIdentificationOutput struct {
Assets []Asset
Metadata map[string]interface{}
}
func (s *AssetIdentificationSkill) Execute(ctx context.Context, input SkillInput) (SkillOutput, error) {
in := input.(*AssetIdentificationInput)
// 内部编排多个 Tools
// 1. 批量识别资产安全属性
properties, err := s.batchIdentifyProperties(ctx, in.AssetIDs)
if err != nil {
return nil, err
}
// 2. 搜索相关资产
relatedAssets, err := s.searchRelatedAssets(ctx, in.ProjectID)
if err != nil {
return nil, err
}
// 3. 获取详细信息
assets, err := s.getAssetDetails(ctx, append(in.AssetIDs, relatedAssets...))
if err != nil {
return nil, err
}
return &AssetIdentificationOutput{
Assets: assets,
Metadata: map[string]interface{}{
"processed_count": len(assets),
"batch_size": in.BatchSize,
},
}, nil
}
```

### 4.2 方案 B：工作流 Skill

将完整的业务流程封装为端到端的 Skill：

| Skill 名称 | 功能描述 |
|-----------|---------|
| **CompleteAssetAnalysisSkill** | 完整的资产识别和分析流程 |
| **CompleteDamageAnalysisSkill** | 完整的损害场景生成和评估流程 |
| **CompleteThreatAnalysisSkill** | 完整的威胁场景生成和评估流程 |

**方案对比：**

- 方案 A：更灵活，适合需要细粒度控制的场景
- 方案 B：更简洁，适合标准化流程

**推荐：方案 A**，因为 TARA 流程需要灵活性和可扩展性。

## 5. 收益分析

### 5.1 量化指标

| 指标 | 重构前 | 重构后 | 改善幅度 |
|-----|-------|-------|---------|
| Tool/Skill 总数 | 34+ | 10 | ↓ 70% |
| 代码重复率 | ~30% | <5% | ↓ 83% |
| 平均维护成本 | 高 | 低 | ↓ 66% |
| Agent 复用能力 | 低 | 高 | ↑ 300% |
| 新功能开发时间 | 基准 | -40% | ↓ 40% |

### 5.2 定性收益

**开发效率：**

- 新增功能时只需扩展 Skill，无需修改多个 Tool
- Skill 可在多个 Agent 间共享，减少重复开发
- 统一的接口降低学习成本

**代码质量：**

- 减少代码重复，提升可维护性
- 高层抽象使业务逻辑更清晰
- 更容易编写单元测试和集成测试

**系统架构：**

- Skill 可独立演进，不影响其他模块
- 支持 Skill 的版本管理和灰度发布
- 为未来的微服务化奠定基础

### 5.3 ROI 估算

**投入：**

- 开发时间：3-4 周（3人团队）
- 测试时间：1-2 周
- 总成本：约 5-6 人周

**回报：**

- 每次功能迭代节省 40% 开发时间
- 维护成本降低 66%
- 预计 3-6 个月收回成本

## 6. 实施路线图

### 6.1 Phase 1：基础设施（1周）

**目标：** 建立 Skill 框架和共享 Skill

**任务：**

1. 定义 Skill 接口和 BaseSkill 实现
2. 实现 3 个共享 Skill：

- ProjectContextSkill
- DataQuerySkill
- RAGSearchSkill

3. 编写单元测试和文档

**交付物：**

- `skill/base.go`
- `skill/project_context_skill.go`
- `skill/data_query_skill.go`
- `skill/rag_search_skill.go`
- 单元测试覆盖率 > 80%

### 6.2 Phase 2：核心 Skill 重构（1.5周）

**目标：** 重构三个 Agent 的核心功能

**任务：**

1. 实现 AssetIdentificationSkill
2. 实现 DamageScenarioGenerationSkill + ImpactAssessmentSkill + CALAnalysisSkill
3. 实现 ThreatScenarioGenerationSkill + AttackFeasibilitySkill
4. 更新 Agent 代码以使用 Skill

**交付物：**

- 7 个核心 Skill 实现
- 更新后的 Agent 代码
- 集成测试

### 6.3 Phase 3：优化和迁移（0.5周）

**目标：** 完成迁移并优化性能

**任务：**

1. 实现 WorkflowOrchestrationSkill
2. 性能测试和优化
3. 文档更新
4. 代码审查和重构

**交付物：**

- 完整的 Skill 体系
- 性能测试报告
- 完整文档

## 7. 风险与建议

### 7.1 风险评估

| 风险 | 影响 | 概率 | 缓解措施 |
|-----|------|------|---------|
| Skill 抽象层次不当 | 高 | 中 | 先实现 Prototype，验证设计 |
| 性能下降 | 中 | 低 | 性能测试，必要时优化 |
| 兼容性问题 | 中 | 中 | 保留旧 Tool，逐步迁移 |
| 学习曲线 | 低 | 高 | 提供培训和文档 |

### 7.2 实施建议

1. **渐进式迁移：** 不要一次性替换所有 Tool，先实现共享 Skill，再逐步迁移核心功能
2. **保持兼容：** 在过渡期保留旧 Tool，确保系统稳定性
3. **充分测试：** 每个 Skill 都要有完整的单元测试和集成测试
4. **文档先行：** 先编写 Skill 设计文档，团队达成共识后再开发
5. **性能监控：** 建立性能基线，重构后持续监控

### 7.3 成功标准

- [ ] 所有 Skill 单元测试覆盖率 > 80%
- [ ] 集成测试通过率 100%
- [ ] 性能不低于重构前（响应时间、吞吐量）
- [ ] 代码重复率 < 5%
- [ ] 团队成员完成 Skill 开发培训

## 8. 附录

### 8.1 参考资料

- Eino Framework 文档
- ISO/SAE 21434 标准
- TARA 方法论

### 8.2 相关代码位置

- Agent 实现：`tara/service/agent/`
- Repository 层：`tara/repository/`
- Tool 定义：各 Agent 文件中的 `newXXXTool()` 函数

---

**文档版本：** v1.0

**创建日期：** 2026-03-03

**最后更新：** 2026-03-03