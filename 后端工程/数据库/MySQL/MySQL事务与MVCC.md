---
tags:
  - MySQL
  - 数据库
  - 事务
  - MVCC
  - 面试
aliases:
  - MySQL事务
  - MVCC机制
  - 隔离级别
  - ReadView
created: 2026-03-23
---

# 🔐 MySQL 事务与 MVCC

> 事务和 MVCC 是 MySQL 面试的必考点。理解 ReadView 的创建时机与可见性规则，是回答"可重复读如何实现"、"MVCC 如何解决幻读"等高频问题的关键。

---

## 一、事务 ACID 特性

| 特性 | 全称 | 含义 | 由什么保证 |
|------|------|------|-----------|
| **A** | Atomicity（原子性） | 事务内所有操作要么全成功，要么全回滚 | **undo log** |
| **C** | Consistency（一致性） | 事务前后数据满足约束，数据库保持一致状态 | AID 共同保证 + 业务逻辑 |
| **I** | Isolation（隔离性） | 并发事务互不干扰 | **锁 + MVCC** |
| **D** | Durability（持久性） | 事务提交后，数据永久保存，崩溃不丢失 | **redo log** |

---

## 二、四种隔离级别

### 2.1 并发问题定义

| 问题 | 定义 |
|------|------|
| **脏读** | 读取到其他事务**未提交**的数据，若对方回滚则数据不存在 |
| **不可重复读** | 同一事务内两次读取同一行，因另一事务**修改并提交**而结果不同 |
| **幻读** | 同一事务内两次查询，因另一事务**插入/删除并提交**而记录数量不同 |

### 2.2 隔离级别对比

| 隔离级别 | 脏读 | 不可重复读 | 幻读 | 说明 |
|---------|------|-----------|------|------|
| **READ UNCOMMITTED**（读未提交） | ✅ 可能 | ✅ 可能 | ✅ 可能 | 最低级别，几乎不用 |
| **READ COMMITTED**（读已提交） | ❌ 解决 | ✅ 可能 | ✅ 可能 | Oracle 默认；每次读取最新快照 |
| **REPEATABLE READ**（可重复读） | ❌ 解决 | ❌ 解决 | ⚠️ 基本解决 | **MySQL 默认**；MVCC + Next-key Lock |
| **SERIALIZABLE**（串行化） | ❌ 解决 | ❌ 解决 | ❌ 解决 | 最高级别，完全串行，性能最差 |

### 2.3 MySQL 默认隔离级别

```sql
-- 查看当前隔离级别
SELECT @@transaction_isolation;
-- 结果：REPEATABLE-READ

-- 修改会话级别
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 修改全局级别
SET GLOBAL TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

> **面试考点**：MySQL 默认是 **REPEATABLE READ（可重复读）**，通过 **MVCC** 解决不可重复读，通过 **Next-key Lock（间隙锁）** 在当前读场景解决幻读。

---

## 三、MVCC 机制详解

**MVCC（Multi-Version Concurrency Control，多版本并发控制）**：通过维护数据的多个历史版本，让读写操作不互相阻塞，实现"快照读"。

### 3.1 关键数据结构

#### 隐藏字段

InnoDB 为每行数据添加两个隐藏字段：

| 隐藏字段 | 大小 | 含义 |
|---------|------|------|
| `trx_id` | 6 bytes | **最近修改该行的事务 ID**（每次修改都更新） |
| `roll_pointer` | 7 bytes | **回滚指针**，指向该行在 undo log 中的上一个版本 |

#### undo log 版本链

每次对某行数据的修改，旧版本数据会写入 undo log，通过 `roll_pointer` 串成**版本链**：

```
当前行（trx_id=5）
    ↓ roll_pointer
undo log 版本（trx_id=3）  ← 事务 3 修改的版本
    ↓ roll_pointer
undo log 版本（trx_id=1）  ← 事务 1 修改的版本（最早版本）
    ↓
NULL
```

```sql
-- 示例：某行数据的修改历史
-- 初始插入（trx_id=1）：name='Alice', age=18
-- 事务 3 修改 age=20（trx_id=3）
-- 事务 5 修改 age=25（trx_id=5）
-- 版本链：age=25(trx_id=5) → age=20(trx_id=3) → age=18(trx_id=1)
```

### 3.2 ReadView（读视图）

ReadView 是事务进行**快照读**时生成的一致性视图，记录了当前活跃（未提交）的事务列表。

**ReadView 的四个关键字段：**

| 字段 | 含义 |
|------|------|
| `m_ids` | 生成 ReadView 时，**当前所有活跃（未提交）事务的 ID 列表** |
| `min_trx_id` | `m_ids` 中的最小值，即最早的活跃事务 ID |
| `max_trx_id` | 生成 ReadView 时，系统下一个将要分配的事务 ID（已分配的最大 ID + 1） |
| `creator_trx_id` | **创建该 ReadView 的事务 ID** |

### 3.3 可见性判断规则

当事务通过版本链查找数据时，对每个版本的 `trx_id` 按以下规则判断是否可见：

```
对于版本链中某个版本的 trx_id：

1. trx_id == creator_trx_id
   → 是自己修改的，✅ 可见

2. trx_id < min_trx_id
   → 该事务在 ReadView 创建前已提交，✅ 可见

3. trx_id >= max_trx_id
   → 该事务在 ReadView 创建后才开启，❌ 不可见

4. min_trx_id <= trx_id < max_trx_id
   → 检查 trx_id 是否在 m_ids 中：
      - 在 m_ids 中：该事务尚未提交，❌ 不可见
      - 不在 m_ids 中：该事务已提交，✅ 可见
```

**遍历逻辑**：从版本链最新版本开始，找到第一个可见版本返回。

```
┌─────────────────────────────────────────────────────────┐
│                   可见性判断流程图                        │
│                                                         │
│  版本链头（最新版本）→ 判断 trx_id                       │
│         ↓                                               │
│  trx_id == creator_trx_id? → Yes → 返回该版本           │
│         ↓ No                                            │
│  trx_id < min_trx_id?      → Yes → 返回该版本           │
│         ↓ No                                            │
│  trx_id >= max_trx_id?     → Yes → 移到下一个旧版本     │
│         ↓ No                                            │
│  trx_id in m_ids?          → Yes → 移到下一个旧版本     │
│                            → No  → 返回该版本           │
└─────────────────────────────────────────────────────────┘
```

### 3.4 RC vs RR 下 ReadView 的创建时机

这是 **RC 和 RR 实现差异的核心**：

| 隔离级别 | ReadView 创建时机 | 效果 |
|---------|----------------|------|
| **READ COMMITTED（RC）** | **每次执行 SELECT 语句时**创建新的 ReadView | 每次都能读到已提交的最新数据 → 解决脏读，但存在不可重复读 |
| **REPEATABLE READ（RR）** | **事务第一次执行 SELECT 时**创建 ReadView，整个事务复用同一个 | 整个事务看到的数据快照固定 → 解决不可重复读 |

**具体示例：**

```
时间线：
T1 (事务1, trx_id=10)          T2 (事务2, trx_id=20)
BEGIN;                          BEGIN;
                                UPDATE user SET age=25 WHERE id=1;
                                -- 未提交
SELECT age FROM user WHERE id=1;
-- RC: 此时生成 ReadView，m_ids=[20]，读到旧版本 age=18
-- RR: 同上

                                COMMIT; -- T2 提交

SELECT age FROM user WHERE id=1;
-- RC: 重新生成 ReadView，m_ids=[]（T2已提交），读到 age=25 ← 不可重复读！
-- RR: 复用第一次的 ReadView，m_ids=[20]，age=25 版本的 trx_id=20 在 m_ids 中，
--     不可见，继续找旧版本 age=18 ← 可重复读！
```

---

## 四、快照读 vs 当前读

| 读类型 | 触发方式 | 是否使用 MVCC | 是否加锁 |
|--------|---------|-------------|---------|
| **快照读（Snapshot Read）** | 普通 `SELECT` | ✅ 是，读历史版本 | ❌ 不加锁 |
| **当前读（Current Read）** | `SELECT ... FOR UPDATE`、`SELECT ... LOCK IN SHARE MODE`、`INSERT`、`UPDATE`、`DELETE` | ❌ 否，读最新版本 | ✅ 加锁 |

```sql
-- 快照读：不加锁，读 ReadView 对应的历史版本
SELECT * FROM user WHERE id = 1;

-- 当前读：加锁，读最新提交的数据
SELECT * FROM user WHERE id = 1 FOR UPDATE;       -- X 锁
SELECT * FROM user WHERE id = 1 LOCK IN SHARE MODE; -- S 锁
```

---

## 五、Next-key Lock 解决幻读

**幻读场景**（当前读下）：

```sql
-- 事务 A
BEGIN;
SELECT * FROM user WHERE age > 18 FOR UPDATE;  -- 当前读，加锁
-- 返回 age=20 的行

-- 事务 B（此时）
INSERT INTO user (id, age) VALUES (100, 25);   -- 插入新行
COMMIT;

-- 事务 A 再次查询
SELECT * FROM user WHERE age > 18 FOR UPDATE;  -- 幻读：多出 age=25 的行！
```

**解决方案：Next-key Lock（临键锁）**

Next-key Lock = Record Lock（记录锁）+ Gap Lock（间隙锁）

对 `age > 18 FOR UPDATE` 的加锁范围不仅锁定已有记录，还**锁定记录之间及边界的间隙**，防止其他事务插入新行。

```sql
-- 假设 age 列有索引，现有数据 age: 15, 20, 30
-- SELECT * FROM user WHERE age > 18 FOR UPDATE 会锁定：
-- (18, 20] 的 Next-key Lock
-- (20, 30] 的 Next-key Lock
-- (30, +∞) 的 Next-key Lock
-- 其他事务无法插入 age=25 等值，幻读被阻止
```

> **注意**：MVCC（快照读）在 RR 级别下天然避免幻读（读的是固定快照），但**当前读**（如 `FOR UPDATE`）需要靠 Next-key Lock 防止幻读。

---

## 六、面试高频问题汇总

### Q1：ACID 各由什么机制保证？

**答**：
- **原子性**：undo log（发生错误时利用 undo log 回滚）
- **持久性**：redo log（WAL + crash-safe）
- **隔离性**：锁 + MVCC
- **一致性**：由 AID 三者共同保证，外加业务层约束

### Q2：MySQL 默认隔离级别是什么？为什么？

**答**：默认是 **REPEATABLE READ（可重复读）**。相比 READ COMMITTED，RR 通过 MVCC 解决了不可重复读；相比 SERIALIZABLE，RR 并发性能更好，并通过 Next-key Lock 在大多数场景下也能防止幻读。

### Q3：MVCC 是如何实现可重复读的？

**答**：MVCC 通过以下机制实现：
1. 每行数据记录 `trx_id`（最近修改的事务 ID）和 `roll_pointer`（指向 undo log 中的旧版本）
2. 事务第一次 SELECT 时创建 **ReadView**，记录当前活跃事务列表 `m_ids`
3. 查询时遍历版本链，对每个版本的 `trx_id` 按可见性规则判断
4. **RR 级别下 ReadView 整个事务只创建一次**，因此无论其他事务如何提交，当前事务看到的数据始终是同一个快照，实现可重复读

### Q4：RC 和 RR 的本质区别是什么？

**答**：本质区别在于 **ReadView 的创建时机**：
- RC：每次 SELECT 都创建新的 ReadView，能看到最新已提交数据
- RR：事务首次 SELECT 时创建 ReadView，整个事务复用同一个，保证读取的数据快照不变

### Q5：MVCC 能完全解决幻读吗？

**答**：**不能完全解决**。
- **快照读**（普通 SELECT）：RR 级别下 MVCC 可以避免幻读，因为整个事务读的是固定快照
- **当前读**（FOR UPDATE、INSERT/UPDATE/DELETE）：MVCC 不起作用，需要 **Next-key Lock（间隙锁）** 来阻止其他事务插入，从而防止幻读

### Q6：undo log 和 MVCC 的关系？

**答**：undo log 是 MVCC 的底层存储支撑。每次修改行时，旧版本数据写入 undo log，通过 `roll_pointer` 串成版本链。MVCC 的快照读就是通过遍历这条版本链，找到对当前 ReadView 可见的版本来返回数据。

---

## 相关链接

- [[MySQL索引]]
- [[MySQL日志系统]]
- [[MySQL锁机制]]
