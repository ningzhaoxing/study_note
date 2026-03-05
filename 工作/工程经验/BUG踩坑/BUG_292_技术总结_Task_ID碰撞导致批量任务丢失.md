# 技术总结：Task ID 碰撞导致批量生成任务静默丢失

**关联 Bug**：BUG_292 - AI攻击树批量生成威胁场景时其中一个被跳过
**日期**：2026-02-27
**作者**：宁赵星

---

## 一、问题现象

批量 AI 生成攻击树时，无论选择多少个威胁场景（测试了 11、53、59 个），**总是恰好有 1 个**攻击树未被生成，前端显示为"新增攻击树"按钮状态。被跳过的不是固定位置，表现随机。

---

## 二、根因分析

### 2.1 Task ID 生成方式

问题代码位于 `tara/service/agent/attack_tree/agent.go`，`NewNodeGenerationTask` 函数：

```go
taskID := fmt.Sprintf("gen-%s-%s-%d-%d",
    projectID, threatScenarioID, parentNodeID, time.Now().Unix())
```

`time.Now().Unix()` 返回的是**秒级 Unix 时间戳**，同一秒内生成的 Task ID 末段完全相同。

### 2.2 碰撞如何发生

`SubmitBatchNodeGeneration` 在一个 for 循环中顺序提交所有任务。循环内每次都有 `GetAttackTreeByID` 数据库查询（IO 耗时约几毫秒），整批提交通常在 1 秒内完成。

当循环跨越秒级边界时，**前一秒提交的最后一个任务**和**后一秒提交的第一个任务**，如果恰好 `threatScenarioID` 不同，ID 不会碰撞。但如果两个任务的 `projectID`、`threatScenarioID`、`parentNodeID` 三段完全相同（例如同一个项目下，两次批量提交包含同一个威胁场景），就会碰撞。

更常见的碰撞场景是：**同一秒内提交的两个任务，`threatScenarioID` 不同，但 `parentNodeID` 都是 0**（初始化场景），且 `projectID` 相同——此时 ID 格式为 `gen-{projectID}-{threatScenarioID}-0-{同一秒时间戳}`，由于 `threatScenarioID` 不同，这种情况实际上不会碰撞。

真正的碰撞路径是：**同一个威胁场景被重复提交**（例如用户多次点击批量生成，或前端重复发送请求），两次提交落在同一秒内，产生完全相同的 Task ID。

### 2.3 碰撞后的连锁反应

`SubmitTaskWithContext` 的逻辑：

```go
func (s *TaskService) SubmitTaskWithContext(task common.Task, parentCtx context.Context) (string, context.CancelFunc, error) {
    taskID := task.GetID()

    ctx, cancel := context.WithCancel(parentCtx)

    s.cancelFuncMu.Lock()
    s.cancelFuncs[taskID] = cancel  // ← 任务B的cancel覆盖任务A的cancel
    s.cancelFuncMu.Unlock()

    s.resultsMu.Lock()
    s.results[taskID] = &TaskResult{...}  // ← 任务B的占位覆盖任务A的占位
    s.resultsMu.Unlock()

    // 两个任务都被提交到 worker pool，都会执行
    s.pool.Submit(wrappedTask)
    ...
}
```

碰撞后：

1. 任务 A 和任务 B 都被提交到 worker pool，**都会执行**
2. `results` map 中只有一条记录（任务 B 的占位覆盖了任务 A 的）
3. 任务 A 执行完成，调用 `saveNodes`，在其中读取 `results[taskID]`
4. 若此时任务 B 已完成并更新了 result，`saveNodes` 读到的是任务 B 的数据，任务 A 的节点会被以任务 B 的上下文保存（treeID、threatScenarioID 错误）
5. 更严重的情况：若 `saveNodes` 在 result 被清理后执行，找不到 result 直接 return，**节点完全不写入数据库**

```go
// task_service.go saveNodes 内
result, exists := s.results[taskID]
if !exists {
    s.updateTaskErrorMessage(taskID, "任务结果不存在")
    return  // 静默退出，无任何外部可见的错误
}
```

### 2.4 为什么"总是恰好 1 个"

每次批量提交，碰撞概率取决于是否有重复的威胁场景被提交。在测试场景中，每次批量提交的威胁场景各不相同，`threatScenarioID` 不同导致 ID 不同，正常情况下不会碰撞。

但实际生产中，用户可能对**已有攻击树的威胁场景**再次触发批量生成（补全操作），此时 `parentNodeID` 相同、`threatScenarioID` 相同，同一秒内提交就会碰撞，且每次批量操作中恰好有 1 个场景处于这种状态，所以总是丢 1 个。

---

## 三、修复方案选择

### 候选方案对比

| 方案 | 唯一性保证 | 并发安全 | 可读性 | 备注 |
|------|-----------|---------|--------|------|
| `time.Now().Unix()` | 秒级，**存在碰撞** | 是 | 好 | 当前方案，有 bug |
| `time.Now().UnixNano()` | 纳秒级，极低概率碰撞 | 是 | 好 | 理论上仍可碰撞 |
| `uuid.New()` | 128位随机，碰撞概率可忽略 | 是 | 好 | **选用** |
| 自增计数器 | 进程内唯一 | 需加锁 | 一般 | 重启后重置，不适合 |

选择 UUID 的理由：
- `github.com/google/uuid` 已在项目依赖中（`go.mod` 中已有 `v1.6.0`），无需引入新依赖
- 内部使用 `crypto/rand`，goroutine-safe，批量并发调用无锁竞争，不引入性能瓶颈
- 唯一性从概率上彻底消除碰撞风险，不依赖时间精度

### 最终修复

```go
// 修复前
taskID := fmt.Sprintf("gen-%s-%s-%d-%d",
    projectID, threatScenarioID, parentNodeID, time.Now().Unix())

// 修复后
taskID := fmt.Sprintf("gen-%s-%s-%d-%s",
    projectID, threatScenarioID, parentNodeID, uuid.New().String())
```

**修改文件**：`tara/service/agent/attack_tree/agent.go`，`NewNodeGenerationTask` 函数。

---

## 四、经验沉淀

**用时间戳生成 ID 是一种常见的反模式**，在以下场景中尤其危险：

- 批量提交（循环内快速生成多个 ID）
- 高并发（多个 goroutine 同时生成 ID）
- 重试逻辑（相同参数在短时间内重复提交）

**正确做法**：任务 ID、幂等键等需要唯一性保证的标识符，应使用 UUID 或雪花算法，而不是时间戳。时间戳可以作为 ID 的**前缀**用于排序和可读性，但不能单独作为唯一标识符。

同类风险点可排查：项目中其他使用 `time.Now().Unix()` 或 `time.Now().UnixNano()` 生成 ID 的地方，评估是否存在相同问题。
