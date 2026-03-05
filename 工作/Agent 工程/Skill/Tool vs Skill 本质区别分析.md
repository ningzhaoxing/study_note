# Tool vs Skill 本质区别分析

## 核心定义

**Tool（工具）**
- 暴露给 LLM 的操作单元
- LLM 可以"看到"并主动选择调用
- 每个 Tool 的描述都会出现在 LLM 的 prompt 中

**Skill（技能）**
- 不暴露给 LLM 的能力单元
- 封装多个 Tool 的组合和执行流程
- LLM 看不到内部实现细节

## 本质区别

### 1. 调用者和可见性

| 维度 | Tool | Skill |
|------|------|-------|
| **LLM 能看到吗？** | ✅ 能看到，在 prompt 中 | ❌ 看不到，只看到 Skill 名称 |
| **LLM 能调用吗？** | ✅ 能直接调用 | ❌ 不能直接调用内部 Tool |
| **谁决定调用？** | LLM 决定 | 代码逻辑决定 |
| **描述位置** | 在 LLM prompt 中 | 在代码注释中 |

### 2. 执行流程对比

**Tool 架构：**
```
用户请求
  ↓
LLM 看到 34 个 Tool
  ↓
LLM 选择 Tool1 → 执行 → 返回结果
  ↓
LLM 看到结果，选择 Tool2 → 执行 → 返回结果
  ↓
LLM 看到结果，选择 Tool3 → 执行 → 返回结果
  ↓
LLM 生成最终回复
```

**Skill 架构：**
```
用户请求
  ↓
LLM 看到 10 个 Skill
  ↓
LLM 选择 Skill1 → 执行
  ├─ 内部自动调用 Tool1
  ├─ 内部自动调用 Tool2
  └─ 内部自动调用 Tool3
  ↓
返回组合结果给 LLM
  ↓
LLM 生成最终回复
```

### 3. Prompt 对比

**Tool 架构的 Prompt：**
```
System: You are a TARA analysis assistant.

Available tools:
[
  {
    "name": "get_project_assumptions",
    "description": "获取项目假设信息...",
    "parameters": {"project_id": "string"}
  },
  {
    "name": "get_project_info",
    "description": "获取项目基本信息...",
    "parameters": {"project_id": "string"}
  },
  ... (32 more tools)
]

Token count: ~3400 tokens
```

**Skill 架构的 Prompt：**
```
System: You are a TARA analysis assistant.

Available tools:
[
  {
    "name": "project_context_skill",
    "description": "管理项目上下文，包括假设、信息和更新",
    "parameters": {"project_id": "string", "action": "string"}
  },
  ... (9 more skills)
]

Token count: ~1000 tokens (节省 70%)
```

## 形象比喻

### Tool = 餐厅菜单
- 顾客（LLM）可以看到所有菜品
- 顾客自己决定点什么菜
- 顾客可以自由组合菜品

### Skill = 套餐
- 顾客（LLM）只看到套餐名称
- 套餐内部包含哪些菜由厨师（代码）决定
- 顾客不需要关心具体细节

## Skill 的本质

**Skill = 多个 Tool 的组合 + 固定的执行流程 + 统一的抽象接口**

```go
// 原来：LLM 看到 3 个独立的 Tool
Tool1: get_project_assumptions
Tool2: get_project_info
Tool3: update_project_context

// 现在：LLM 只看到 1 个 Skill
Skill: project_context_skill
  内部实现：
    - 调用 Tool1
    - 调用 Tool2
    - 调用 Tool3
    - 返回组合后的结果
```

## 主要价值

### 1. Token 节省（70%）

**计算：**
- Tool 架构：34 个 Tool × 100 tokens = 3400 tokens
- Skill 架构：10 个 Skill × 100 tokens = 1000 tokens
- 节省：2400 tokens/请求

**经济效益：**
- 10 轮对话节省：24,000 tokens
- 按 GPT-4 价格（$0.03/1K tokens）：节省 $0.72/对话
- 每天 1000 个对话：每月节省约 $21,600

### 2. 提高 LLM 选择准确率

- 34 个选项 → LLM 容易选错或遗漏
- 10 个选项 → LLM 更容易做出正确选择
- 减少 LLM 的认知负荷

### 3. 减少 LLM 调用次数

**Tool 架构：**
```
User → LLM → Tool1 → LLM → Tool2 → LLM → Tool3 → LLM → Response
(4 次 LLM 调用)
```

**Skill 架构：**
```
User → LLM → Skill(Tool1+Tool2+Tool3) → LLM → Response
(2 次 LLM 调用)
```

**好处：**
- 更快的响应时间
- 更低的延迟
- 更少的 API 调用成本

### 4. 提高可靠性

**Tool 架构：** LLM 可能忘记调用某个 Tool，或调用顺序错误

**Skill 架构：** 代码保证所有步骤都按正确顺序执行

### 5. 解决代码重复

**问题：**
- `get_project_assumptions` 在 3 个 Agent 中重复实现
- 修改一次要改 3 处
- 容易出现不一致

**解决：**
- 1 个 `ProjectContextSkill`
- 3 个 Agent 共享
- 修改一次，全部生效

## 权衡和限制

### Skill 的优势
- ✅ 节省 Token（70%）
- ✅ 提高准确率
- ✅ 减少调用次数
- ✅ 提高可靠性
- ✅ 解决代码重复

### Skill 的劣势
- ❌ 灵活性降低（流程固定）
- ❌ 增加抽象层次
- ❌ 学习曲线（新概念）
- ❌ 调试可能更复杂

### 解决方案：混合架构

```
层次结构：
├── Skill 层（标准流程，80% 场景）
│   ├── 共享 Skill
│   └── 领域 Skill
│
└── Tool 层（灵活组合，20% 场景）
    ├── 原子 Tool
    └── 供 Skill 内部使用
```

**原则：**
- Skill 内部使用 Tool
- Agent 可以选择用 Skill（标准流程）或直接用 Tool（灵活组合）
- 保留 Tool 作为"逃生舱"

## 适用场景

### 适合使用 Skill 的场景
- ✅ 有明确的业务流程
- ✅ 流程相对固定
- ✅ 代码重复率高（>20%）
- ✅ Tool 数量过多（>20 个）
- ✅ 关心 Token 成本
- ✅ 长期维护的系统

### 不适合使用 Skill 的场景
- ❌ 探索性任务（流程不确定）
- ❌ 高度定制化（每个场景都不同）
- ❌ 快速迭代的原型（业务逻辑频繁变化）
- ❌ 短期项目（不值得投入重构成本）

## 实施建议

### 渐进式迁移策略

**Phase 0：快速验证（1-2 天）**
- 只重构最明显的重复（如 `get_project_assumptions`）
- 创建 1 个共享 Skill
- 在 1 个 Agent 中试用
- 评估效果

**Phase 1：解决重复（1 周）**
- 创建 3 个共享 Skill
- 解决主要的代码重复问题
- 代码重复率：30% → 15%

**Phase 2：拆分大文件（1 周）**
- 重构大型 Agent 文件
- 按功能域拆分成多个 Skill

**Phase 3：全面优化（1 周）**
- 完成 Skill 架构
- 优化 LLM prompt
- 性能测试

### 关键原则

1. **不要删除 Tool** - Skill 内部使用 Tool，保持灵活性
2. **渐进式迁移** - 不要一次性全部重构
3. **保留逃生舱** - Agent 可以直接访问 Tool
4. **充分测试** - 每个 Skill 都要有完整测试
5. **先验证再推广** - Phase 0 验证效果后再继续

## 总结

**Skill 的本质：**
> Skill 就是把可以连贯执行业务流程的多个 Tool 组合到一起，封装成一个新的抽象单元，通过这种方式有效节省 Token、提高准确率、减少调用次数，并解决代码重复问题。

**核心价值：**
- 不是为了炫技，而是为了解决实际问题
- 不是完全替代 Tool，而是在 Tool 之上增加一层抽象
- 不是一次性重构，而是渐进式演进

**决策依据：**
- 如果代码重复率 > 20% → 考虑 Skill
- 如果 Tool 数量 > 20 个 → 考虑 Skill
- 如果关心 Token 成本 → 考虑 Skill
- 如果系统长期维护 → 考虑 Skill

---

**文档版本：** v1.0
**创建日期：** 2026-03-03
**基于讨论：** [[Agent 架构重构方案：从 Tool 到 Skill]]
