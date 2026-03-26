---
tags:
  - Go
  - 基础语法
  - 面试
aliases:
  - new和make的区别
  - Go内存初始化
created: 2026-03-23
---

# new 和 make 的区别

> 这是 Go 基础面试中高频出现的问题。核心答案：**new 分配内存返回指针，make 初始化引用类型的内部结构**。

---

## 一、new

### 1.1 函数签名

```go
func new(Type) *Type
```

- 接收一个**类型**作为参数
- 为该类型分配一块零值内存
- 返回指向该内存的**指针**

### 1.2 示例

```go
// new(int)：分配一个 int 大小的内存，初始化为 0，返回 *int
p := new(int)
fmt.Println(*p)  // 0
*p = 42
fmt.Println(*p)  // 42

// new(string)
s := new(string)
fmt.Println(*s)  // ""（空字符串，零值）

// new(struct)
type Point struct{ X, Y int }
pt := new(Point)
fmt.Println(*pt)  // {0 0}
pt.X = 10
fmt.Println(*pt)  // {10 0}
```

### 1.3 等价写法

```go
// new(T) 等价于：
var t T
p := &t
```

---

## 二、make

### 2.1 函数签名

```go
func make(t Type, size ...IntegerType) Type
```

- **只能用于**：`slice`、`map`、`channel` 三种类型
- 不仅分配内存，还**初始化内部数据结构**（运行所需的内部状态）
- 返回**值本身**（不是指针）

### 2.2 三种类型的 make

```go
// Slice：make([]T, len, cap)
s := make([]int, 3, 5)
// 内部：分配底层数组（cap=5），设置 len=3，cap=5

// Map：make(map[K]V, hintSize)  hintSize 是可选的初始容量提示
m := make(map[string]int)
m := make(map[string]int, 100)  // 预分配桶，减少扩容
// 内部：初始化 hmap 结构，分配桶数组

// Channel：make(chan T, bufferSize)
ch := make(chan int)      // 无缓冲
ch := make(chan int, 10)  // 缓冲区大小 10
// 内部：初始化 hchan 结构，分配缓冲区
```

### 2.3 为什么 slice/map/chan 必须用 make？

这三种类型都是**引用类型**，其值本身只是一个"header"结构体（包含指针和元数据），不经过 make 初始化，内部指针为 nil，直接使用会 panic：

```go
// slice
var s []int
s = append(s, 1)  // 合法，append 会自动初始化
s[0] = 1          // panic！len=0，下标越界

// map
var m map[string]int
v := m["key"]     // 合法，读 nil map 返回零值
m["key"] = 1      // panic！assignment to entry in nil map

// channel
var ch chan int
ch <- 1            // 永久阻塞（发送到 nil channel）
<-ch               // 永久阻塞（从 nil channel 接收）
```

---

## 三、new vs make 对比

| 维度        | `new`          | `make`                  |
| --------- | -------------- | ----------------------- |
| **适用类型**  | 任意类型           | 仅 slice / map / channel |
| **返回值**   | `*T`（指针）       | `T`（值本身）                |
| **初始化内容** | 零值填充（不初始化内部结构） | 零值 + 内部数据结构初始化          |
| **使用场景**  | 需要指针时          | 需要可用的引用类型时              |

---

## 四、实际使用建议

```go
// new 的使用场景（相对少见）
// 1. 需要某类型的指针且想初始化为零值
p := new(sync.Mutex)  // 等价于 var mu sync.Mutex; &mu

// 2. 链表/树节点创建
node := new(ListNode)
node.Val = 1

// make 的使用场景（更常见）
// 1. 预分配容量的 slice（避免频繁扩容）
s := make([]int, 0, 1000)

// 2. 预分配的 map
m := make(map[string]struct{}, 100)

// 3. goroutine 通信的 channel
done := make(chan struct{})
```

---

## 五、面试高频问题

### Q1：new 和 make 的本质区别？

**答**：
- `new(T)` 只做内存分配，将内存初始化为零值，返回 `*T`。适用于任何类型，但不初始化引用类型的内部结构（如 map 的桶、slice 的数组）。
- `make(T, ...)` 专门用于 slice/map/channel，除了分配内存，还会**初始化内部数据结构**，让其立即可用，返回 `T`（非指针）。

### Q2：为什么 `new(map[string]int)` 得到的 map 不能直接写入？

**答**：`new(map[string]int)` 返回 `*map[string]int`，解引用后得到一个 nil map。nil map 读操作合法（返回零值），但写操作会 panic，因为 nil map 没有初始化内部的桶数组。必须用 `make(map[string]int)` 初始化。

```go
m := new(map[string]int)
(*m)["key"] = 1  // panic: assignment to entry in nil map

*m = make(map[string]int)  // 先 make 再使用
(*m)["key"] = 1  // OK
```

### Q3：`var s []int` 和 `s := make([]int, 0)` 有什么区别？

**答**：
- `var s []int`：nil slice，s == nil 为 true，底层没有分配内存
- `make([]int, 0)`：空 slice，s == nil 为 false，分配了 slice header
- 两者都可以 append，行为一致
- **关键区别**：JSON 序列化时 nil slice 输出 `null`，空 slice 输出 `[]`

---

## 相关链接

- [[go_slience]] - Slice 底层原理与扩容
- [[go_map]] - Map 底层原理
- [[go_channel]] - Channel 初始化与底层原理
- [[内存分配]] - Go 内存分配器架构
