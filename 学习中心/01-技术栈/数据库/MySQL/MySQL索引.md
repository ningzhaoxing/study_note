---
tags:
  - MySQL
  - 数据库
  - 索引
  - 面试
aliases:
  - MySQL索引原理
  - B+树索引
  - 覆盖索引
  - 联合索引
created: 2026-03-23
---

# 🗂️ MySQL 索引

> 索引是数据库性能优化的核心手段。理解索引的底层原理，是写出高效 SQL 的前提，也是面试高频考点。

---

## 一、索引的本质与作用

**索引的本质**：索引是一种数据结构，它以额外的存储空间为代价，加速数据的查找操作。本质上是将**无序数据变为有序结构**，从而将全表扫描的 O(n) 查找降低到 O(log n)。

**索引的作用**：
- 加速 `WHERE` 条件筛选
- 加速 `ORDER BY` / `GROUP BY` 排序分组
- 加速 `JOIN` 关联查询的连接条件
- 通过覆盖索引避免回表，减少 I/O

**索引的代价**：
- 占用额外磁盘空间
- 写操作（INSERT / UPDATE / DELETE）时需要维护索引结构，降低写性能

---

## 二、B+ 树索引原理

### 2.1 为什么选 B+ 树？

MySQL InnoDB 使用 **B+ 树**作为索引的底层数据结构。对比其他结构：

| 数据结构           | 查找复杂度        | 问题                                   |
| -------------- | ------------ | ------------------------------------ |
| 二叉搜索树          | O(log n)     | 极端情况退化为链表 O(n)；树高随数据量增大              |
| 平衡二叉树（AVL/红黑树） | O(log n)     | 每个节点只存一个 key，树高大，磁盘 I/O 次数多          |
| B 树（多路平衡）      | O(log n)     | 非叶节点也存数据，导致每页能存的 key 更少，树更高          |
| **B+ 树**       | **O(log n)** | **非叶节点只存 key，叶节点存全部数据并用链表相连，范围查询高效** |
| Hash 表         | O(1)         | 不支持范围查询、排序；哈希冲突；不支持最左前缀              |

### 2.2 B+ 树的核心特性

```
                    [30 | 60]                    ← 非叶节点：只存 key，不存 data
                   /    |    \
          [10|20]    [40|50]    [70|80]          ← 非叶节点
         /  |  \    /  |  \    /  |  \
[1,10] [11,20] [21,30] ... [61,70] [71,80] [81,90]  ← 叶节点：存完整数据，双向链表相连
```

**核心特性：**
1. **非叶节点只存索引 key**，不存数据行，单页能容纳更多 key，树高更低（通常 3~4 层即可支撑千万级数据）
2. **所有数据都在叶节点**，查询路径固定，性能稳定
3. **叶节点通过双向链表相连**，支持高效范围查询（`BETWEEN`、`>`、`<`、`ORDER BY`）
4. **一次磁盘 I/O 读取一页（16KB）**，每层 I/O 一次，3 层树只需 3 次 I/O

### 2.3 树高估算

```
假设每页 16KB，每个 key 占 8B，每个指针占 6B：
非叶节点每页可存：16KB / (8+6)B ≈ 1170 个 key
叶节点每页可存：假设每行数据 1KB，则存 16 条

- 2 层树：1170 × 16 = 18,720 条记录
- 3 层树：1170 × 1170 × 16 ≈ 2,190 万条记录
```

> **结论**：InnoDB 中一棵 3 层 B+ 树可支撑约 **2000 万行**数据，查找只需 **3 次 I/O**。

---

## 三、聚簇索引 vs 非聚簇索引

### 3.1 聚簇索引（Clustered Index）

- **定义**：索引结构和数据行存储在一起。叶节点存储的是**完整数据行**。
- **InnoDB 中**：主键索引即为聚簇索引（若无主键，则选唯一非空索引；若无，则隐式生成 rowid）
- **每张表只有一个聚簇索引**

```sql
-- InnoDB 主键索引即聚簇索引
CREATE TABLE user (
    id      BIGINT PRIMARY KEY,   -- 聚簇索引
    name    VARCHAR(50),
    age     INT
);
-- 数据行按 id 顺序物理存储在 B+ 树叶节点中
```

### 3.2 非聚簇索引（Secondary Index / 二级索引）

- **定义**：叶节点存储的是**索引列值 + 主键值**，而非完整数据行
- 通过二级索引查找时，先找到主键值，再回到聚簇索引查完整行 —— 即**回表（Back to Primary）**

```
二级索引（name 字段）的 B+ 树叶节点：
[name="Alice" | id=3]
[name="Bob"   | id=1]
[name="Carol" | id=5]
         ↓ 回表
主键聚簇索引查找 id=3 → 完整数据行
```

```sql
-- 查询触发回表
SELECT id, name, age FROM user WHERE name = 'Alice';
-- 先走 name 的二级索引找到 id，再回主键索引查 age
```

### 3.3 回表的代价与优化

回表会导致**两次 B+ 树查询**（二级索引 + 聚簇索引），当回表行数过多时性能急剧下降。

**优化方案**：使用**覆盖索引**（见第四节）

---

## 四、覆盖索引（Covering Index）

**定义**：查询所需的所有列都包含在索引中，无需回表，直接从索引返回结果。

```sql
-- 表结构
CREATE TABLE user (
    id   BIGINT PRIMARY KEY,
    name VARCHAR(50),
    age  INT,
    INDEX idx_name (name)
);

-- ❌ 需要回表：age 不在 idx_name 索引中
SELECT name, age FROM user WHERE name = 'Alice';

-- ✅ 覆盖索引：只查询 id 和 name，都在 idx_name 叶节点中
SELECT id, name FROM user WHERE name = 'Alice';
```

**创建覆盖索引**：将常用查询列加入联合索引

```sql
-- 创建联合索引，覆盖常用查询
ALTER TABLE user ADD INDEX idx_name_age (name, age);

-- ✅ 现在 SELECT name, age 不再回表
SELECT name, age FROM user WHERE name = 'Alice';
```

**EXPLAIN 验证**：`Extra` 列出现 `Using index` 表示使用了覆盖索引

```sql
EXPLAIN SELECT name, age FROM user WHERE name = 'Alice';
-- Extra: Using index  ← 覆盖索引，无回表
```

---

## 五、联合索引与最左前缀原则

### 5.1 联合索引存储结构

联合索引按**多列的组合值**构建 B+ 树，排序规则为：先按第一列排序，第一列相同时按第二列排序，以此类推。

```sql
-- 联合索引 (a, b, c)
-- 叶节点中数据按 a -> b -> c 的顺序排列
INDEX idx_abc (a, b, c)
```

### 5.2 最左前缀原则

使用联合索引时，查询条件必须**从最左列开始，不能跳过中间列**。

```sql
-- 联合索引: idx_name_age_city (name, age, city)

-- ✅ 完全命中索引
SELECT * FROM user WHERE name='Alice' AND age=20 AND city='Beijing';

-- ✅ 命中 (name, age) 两列
SELECT * FROM user WHERE name='Alice' AND age=20;

-- ✅ 命中 (name) 一列
SELECT * FROM user WHERE name='Alice';

-- ✅ 命中 (name)，age 使用范围后 city 索引失效
SELECT * FROM user WHERE name='Alice' AND age>18 AND city='Beijing';
-- 实际：name、age 走索引，city 不走

-- ❌ 不命中：跳过了 name
SELECT * FROM user WHERE age=20 AND city='Beijing';

-- ❌ 不命中：跳过了 name 和 age
SELECT * FROM user WHERE city='Beijing';
```

### 5.3 范围查询对联合索引的影响

```sql
-- 索引: (a, b, c)
-- a 是范围查询，b 和 c 无法使用索引
SELECT * FROM t WHERE a > 1 AND b = 2 AND c = 3;
-- 只有 a 走索引，b、c 不走

-- a 是等值查询，b 是范围查询，c 无法使用索引
SELECT * FROM t WHERE a = 1 AND b > 2 AND c = 3;
-- a、b 走索引，c 不走
```

---

## 六、常见索引失效场景（8 个）

> 以下场景会导致索引失效，触发全表扫描，面试高频！

```sql
-- 建表
CREATE TABLE user (
    id       BIGINT PRIMARY KEY,
    name     VARCHAR(50),
    age      INT,
    phone    VARCHAR(20),
    status   INT,
    create_time DATETIME,
    INDEX idx_name (name),
    INDEX idx_age  (age),
    INDEX idx_phone (phone),
    INDEX idx_name_age (name, age)
);
```

### ❌ 场景 1：对索引列使用函数或表达式

```sql
-- 失效：对 name 列使用了函数
SELECT * FROM user WHERE LEFT(name, 3) = 'Ali';

-- 失效：对 age 列进行了计算
SELECT * FROM user WHERE age + 1 = 21;

-- ✅ 正确做法：把计算移到右侧
SELECT * FROM user WHERE age = 20;
```

### ❌ 场景 2：隐式类型转换

```sql
-- phone 是 VARCHAR，传入的是整数，MySQL 会对 phone 列做类型转换
SELECT * FROM user WHERE phone = 13812345678;   -- ❌ 索引失效

-- ✅ 正确：保持类型一致
SELECT * FROM user WHERE phone = '13812345678';
```

### ❌ 场景 3：使用 LIKE 以通配符开头

```sql
-- ❌ 前缀通配符，索引失效（无法利用 B+ 树有序性）
SELECT * FROM user WHERE name LIKE '%Alice%';
SELECT * FROM user WHERE name LIKE '%Alice';

-- ✅ 后缀通配符，可以使用索引
SELECT * FROM user WHERE name LIKE 'Alice%';
```

### ❌ 场景 4：使用 OR 连接非索引列

```sql
-- age 没有索引，OR 导致 name 的索引也失效
SELECT * FROM user WHERE name = 'Alice' OR status = 1;

-- ✅ 两个字段都有索引，OR 可以走索引合并（Index Merge）
SELECT * FROM user WHERE name = 'Alice' OR age = 20;
```

### ❌ 场景 5：违反最左前缀原则（联合索引）

```sql
-- idx_name_age (name, age)
-- ❌ 跳过 name，age 无法单独使用该联合索引
SELECT * FROM user WHERE age = 20;
```

### ❌ 场景 6：使用 IS NOT NULL

```sql
-- ❌ IS NOT NULL 通常无法使用索引（取决于数据分布，大多数行非 NULL 时失效）
SELECT * FROM user WHERE name IS NOT NULL;

-- ✅ IS NULL 通常可以使用索引
SELECT * FROM user WHERE name IS NULL;
```

### ❌ 场景 7：使用 != 或 NOT IN

```sql
-- ❌ 不等于运算符导致索引失效
SELECT * FROM user WHERE age != 20;
SELECT * FROM user WHERE age NOT IN (18, 19, 20);

-- ✅ 等值或 IN 可以使用索引
SELECT * FROM user WHERE age IN (18, 19, 20);
```

### ❌ 场景 8：全表扫描比索引更快（优化器放弃索引）

```sql
-- 当索引选择性极低时（如 status 只有 0/1 两个值，且大量行是同一值），
-- MySQL 优化器判断全表扫描比回表代价更低，主动放弃索引
SELECT * FROM user WHERE status = 1;  -- status 区分度低时失效
```

---

## 七、EXPLAIN 执行计划关键字段

```sql
EXPLAIN SELECT * FROM user WHERE name = 'Alice' AND age = 20;
```

| 字段 | 含义 | 关注点 |
|------|------|--------|
| `id` | 查询序号，id 越大越先执行 | 子查询/联合查询的执行顺序 |
| `select_type` | 查询类型（SIMPLE/PRIMARY/SUBQUERY/DERIVED） | 是否有子查询 |
| `table` | 当前查询的表 | - |
| `type` | **访问类型**（性能关键） | 见下表 |
| `possible_keys` | 可能使用的索引 | 候选索引列表 |
| `key` | **实际使用的索引** | NULL 表示未走索引 |
| `key_len` | 索引使用的字节数 | 判断联合索引用了几列 |
| `rows` | **预估扫描行数** | 越小越好 |
| `Extra` | **额外信息**（重要） | 见下表 |

### type 字段（性能从好到差）

| type 值 | 含义 | 场景 |
|---------|------|------|
| `system` | 表只有一行 | 系统表 |
| `const` | 通过主键/唯一索引等值查询，最多一行 | `WHERE id = 1` |
| `eq_ref` | 联表时被驱动表用主键/唯一索引关联 | JOIN ON 主键 |
| `ref` | 非唯一索引等值查询 | `WHERE name = 'Alice'` |
| `range` | 索引范围扫描 | `BETWEEN`、`>`、`<`、`IN` |
| `index` | 全索引扫描（不扫数据行，只扫索引树） | 覆盖索引全扫 |
| `ALL` | **全表扫描，性能最差** | 无索引或索引失效 |

> 优化目标：至少达到 `range`，最好是 `ref` 或 `const`

### Extra 字段关键值

| Extra 值 | 含义 |
|----------|------|
| `Using index` | **覆盖索引**，无需回表，性能优秀 |
| `Using where` | 在 Server 层对存储引擎返回结果做了额外过滤 |
| `Using index condition` | **索引下推（ICP）**，在存储引擎层过滤，减少回表 |
| `Using filesort` | 无法利用索引排序，需要额外排序操作，需优化 |
| `Using temporary` | 使用了临时表（GROUP BY / DISTINCT），需优化 |
| `Using join buffer` | 关联查询未使用索引，用了 join buffer，需优化 |

---

## 八、面试高频问题汇总

### Q1：为什么 InnoDB 用 B+ 树而不用 B 树？

**答**：B 树的非叶节点也存储数据，导致单页能放的 key 数量更少，树更高，磁盘 I/O 更多。B+ 树非叶节点只存 key，叶节点存所有数据并通过链表相连，优点：
1. 树更矮（3层支撑千万数据），I/O 次数少
2. 叶节点链表支持高效范围查询
3. 查询路径固定，性能稳定

### Q2：聚簇索引和非聚簇索引的区别？

**答**：聚簇索引的叶节点存储完整数据行，数据和索引在一起；非聚簇索引（二级索引）叶节点只存索引列值和主键值。通过二级索引查询时若需要非索引列，需要**回表**到聚簇索引查完整数据，多一次 B+ 树查找。

### Q3：什么是覆盖索引？如何验证？

**答**：查询所需的所有列都在索引中，无需回表，直接从索引树返回结果。通过 `EXPLAIN` 查看 `Extra` 列为 `Using index` 即为覆盖索引。

### Q4：联合索引的最左前缀原则是什么？

**答**：使用联合索引 `(a, b, c)` 时，查询条件必须包含最左列 `a`，才能使用索引。因为联合索引按 `a -> b -> c` 的顺序排列，跳过前缀列则无法利用 B+ 树的有序性定位。

### Q5：什么情况下索引会失效？

**答**：
1. 对索引列使用函数/表达式
2. 隐式类型转换（字段类型与传参类型不一致）
3. LIKE 以 `%` 开头
4. OR 连接了无索引列
5. 违反最左前缀原则
6. IS NOT NULL（视数据分布）
7. 使用 `!=` 或 `NOT IN`
8. 优化器认为全表扫描代价更低

### Q6：EXPLAIN 中 type=ALL 如何优化？

**答**：`type=ALL` 表示全表扫描，优化方向：
1. 检查 `WHERE` 条件列是否有索引
2. 检查是否存在索引失效场景
3. 考虑创建覆盖索引避免回表
4. 分析数据分布，必要时强制使用索引（`FORCE INDEX`）

---

## 相关链接

- [[MySQL事务与MVCC]]
- [[MySQL日志系统]]
- [[MySQL锁机制]]
