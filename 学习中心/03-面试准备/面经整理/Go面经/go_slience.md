---
tags:
  - Go
  - Slice
  - 数据结构
  - 面试
aliases:
  - Go Slice原理
  - 切片扩容
  - slice底层
created: 2026-03-23
---

# Go Slice 底层原理

> Slice 是 Go 最常用的序列类型。面试重点：**底层结构三字段 → 扩容策略 → 切片共享陷阱 → append 的内存行为**。

---

## 一、底层数据结构

```go
type slice struct {
    array unsafe.Pointer  // 指向底层数组的指针
    len   int             // 当前元素数量（切片长度）
    cap   int             // 底层数组的容量
}
```

**三个字段的含义**：
- `array`：指向一块连续内存，存放真实数据
- `len`：可读写的元素个数，`s[i]` 要求 `0 <= i < len`
- `cap`：底层数组的总容量，`len <= cap`

```go
s := make([]int, 3, 5)
// array → [0, 0, 0, _, _]
// len = 3, cap = 5

s = s[:5]  // 合法：len 可以扩展到 cap
s = s[:6]  // panic：超出 cap
```

---

## 二、切片的创建方式

```go
// 1. 直接声明（nil slice，len=0, cap=0，array=nil）
var s []int

// 2. 字面量
s := []int{1, 2, 3}  // len=3, cap=3

// 3. make
s := make([]int, 3)     // len=3, cap=3
s := make([]int, 3, 10) // len=3, cap=10

// 4. 截取（共享底层数组！）
a := []int{1, 2, 3, 4, 5}
b := a[1:4]  // len=3, cap=4（从 a[1] 到 a 末尾）
```

---

## 三、append 与扩容

### 3.1 append 的基本行为

```go
s := []int{1, 2, 3}  // len=3, cap=3

// cap 足够时：直接写入，不分配新内存
s = append(s, 4)  // len=4, cap=6（触发扩容，新 cap）

// append 多个元素
s = append(s, 5, 6, 7)

// append 另一个 slice（...展开）
a := []int{8, 9}
s = append(s, a...)
```

### 3.2 扩容策略

**Go 1.18 之前**：
```
if oldCap < 1024:
    newCap = oldCap * 2      // 翻倍
else:
    newCap = oldCap * 1.25   // 1.25 倍增长
    循环直到 newCap >= needed
```

**Go 1.18 之后**（更平滑的增长曲线）：
```
if oldCap < 256:
    newCap = oldCap * 2
else:
    // 从 2x 平滑过渡到 1.25x
    newCap = oldCap
    for newCap < needed:
        newCap += (newCap + 3 * 256) / 4
        // 当 oldCap >> 256 时，约等于 1.25x
        // 当 oldCap ≈ 256 时，接近 2x
```

> **注意**：实际分配的 cap 还会受**内存对齐**调整，不一定等于上述计算值。

### 3.3 扩容时的内存行为

```go
a := []int{1, 2, 3}
b := a  // b 和 a 共享底层数组

a = append(a, 4)  // 触发扩容：a 获得新的底层数组
a[0] = 99

fmt.Println(b[0])  // 输出 1，不是 99！
// b 仍指向旧数组，a 指向新数组，互不影响
```

```go
// 对比：未扩容时修改会互相影响
a := make([]int, 3, 10)  // cap 足够
b := a

a = append(a, 4)  // 不扩容，a 和 b 仍共享底层数组
a[0] = 99
fmt.Println(b[0])  // 输出 99！
```

---

## 四、切片共享陷阱

### 4.1 子切片修改影响原切片

```go
a := []int{1, 2, 3, 4, 5}
b := a[1:3]  // b = [2, 3]，共享 a 的底层数组

b[0] = 99
fmt.Println(a)  // [1 99 3 4 5]，a 也被修改！
```

**解决**：使用 `copy` 创建独立副本
```go
b := make([]int, len(a[1:3]))
copy(b, a[1:3])
b[0] = 99
fmt.Println(a)  // [1 2 3 4 5]，a 不受影响
```

### 4.2 append 导致的意外覆盖

```go
a := make([]int, 3, 5)  // [0, 0, 0], cap=5
b := a[0:2]              // b = [0, 0], cap=5

b = append(b, 100)       // b 的 len=3, cap=5，不扩容
// 写入位置是 a[2]！
fmt.Println(a)  // [0, 0, 100]，a[2] 被修改
```

**解决**：使用完整的三索引切片限制 cap

```go
b := a[0:2:2]  // 第三个 2 限制 b 的 cap=2
b = append(b, 100)  // cap 不足，触发扩容，b 获得新数组
fmt.Println(a)  // [0, 0, 0]，a 不受影响
```

---

## 五、nil slice vs 空 slice

```go
var s1 []int        // nil slice:   len=0, cap=0, s1==nil 为 true
s2 := []int{}       // 空 slice:    len=0, cap=0, s2==nil 为 false
s3 := make([]int,0) // 同上，空 slice

// 两者对 append 操作没有区别
s1 = append(s1, 1)  // 合法
s2 = append(s2, 1)  // 合法

// JSON 序列化不同！
json.Marshal(s1)  // null
json.Marshal(s2)  // []
```

> **实践建议**：若要返回"空列表"给 API 调用方，用 `s := []int{}` 或 `s := make([]int, 0)` 而不是 `var s []int`，避免 JSON 返回 `null`。

---

## 六、面试高频问题

### Q1：slice 的底层结构是什么？

**答**：slice 是一个三字段的结构体：底层数组指针 `array`、长度 `len`、容量 `cap`。它是对底层数组的一个"窗口视图"，多个 slice 可以共享同一底层数组。

### Q2：append 一定会复制元素吗？

**答**：不一定。
- 若 `len < cap`，append 直接在底层数组的 `len` 位置写入新元素，**不复制**，时间复杂度 O(1)
- 若 `len == cap`，触发扩容：分配新数组，将旧数组全部复制过去，时间复杂度 O(n)

append 的均摊时间复杂度是 O(1)（类似动态数组的摊还分析）。

### Q3：如何安全地截取 slice 不影响原 slice？

**答**：两种方式：
1. **`copy` 新 slice**：`b := make([]int, len); copy(b, a[i:j])`，创建独立内存
2. **三索引限制 cap**：`b := a[i:j:j]`，限制 b 的 cap 使 append 时强制扩容，不写回原 slice

### Q4：slice 和 array 的区别？

| 维度 | Array | Slice |
|-----|-------|-------|
| 长度 | 固定，编译期确定 | 动态，运行时可变 |
| 传值 | 值复制（完整拷贝） | 只复制三字段（header），共享底层数组 |
| 类型 | `[3]int` 和 `[4]int` 是不同类型 | 统一为 `[]int` |
| 内存 | 栈上分配（小数组） | header 在栈，底层数组在堆 |

### Q5：为什么 Go 1.18 改变了扩容策略？

**答**：旧策略在 1024 这个临界点有突变（突然从 2x 变为 1.25x），会导致内存使用量的不平滑增长。新策略通过平滑的数学公式，让扩容倍数从 2x 逐渐过渡到 1.25x，内存分配更均匀，减少浪费。

---

## 相关链接

- [[go_map]] - Map 与 Slice 的底层设计对比
- [[内存分配]] - Slice 底层数组的内存分配
- [[内存逃逸]] - Slice 什么情况下逃逸到堆
