---
tags:
  - Go
  - GMP
  - 并发
  - 面试
aliases:
  - GMP模型
  - Go调度器
  - goroutine调度
created: 2026-03-23
---

# GMP 调度模型

> Go 语言实现了用户态的 M:N 协程调度，GMP 是其核心架构。理解 G/M/P 各自的职责、调度策略（抢占、工作窃取、hand-off）是回答 "Go 并发为什么高效" 的关键。

---

## 一、为什么需要 GMP？

### 1.1 线程模型的局限

操作系统线程（OS Thread）存在两个核心问题：
1. **内存开销大**：每个线程默认栈空间 1~8 MB，创建大量线程内存耗尽
2. **上下文切换慢**：线程切换需要陷入内核态，保存/恢复寄存器组，耗时 ~1μs

### 1.2 协程的优势

Go 的 goroutine（协程）是用户态"绿色线程"：
- **初始栈仅 2~8 KB**，按需自动伸缩（最大默认 1 GB）
- **切换在用户态完成**，无需陷入内核，耗时 ~100ns
- **Go runtime 调度器**负责将 N 个 goroutine 映射到 M 个 OS 线程上运行

### 1.3 M:N 调度模型

```
  goroutines (N个)
       ↓  runtime 调度
  OS threads (M个)
       ↓  内核调度
  CPU cores
```

---

## 二、GMP 三个核心组件

### 2.1 G（Goroutine）

一个 `G` 代表一个 goroutine，保存其执行状态：

| 字段 | 含义 |
|-----|------|
| `stack` | goroutine 的栈内存（初始 2KB，动态伸缩） |
| `sched` | 调度信息（PC、SP 等寄存器） |
| `status` | 当前状态（Gidle/Grunnable/Grunning/Gwaiting/Gdead） |
| `m` | 当前绑定的 M（正在运行时） |

**G 的状态流转**：
```
Gidle（刚创建）
   ↓
Grunnable（就绪，等待调度）← 被唤醒后
   ↓ 被 P 调度
Grunning（运行中）
   ↓ 遇到系统调用/阻塞
Gwaiting（等待中）
   ↓ 运行完毕
Gdead（已退出，供复用）
```

### 2.2 M（Machine，OS Thread）

一个 `M` 代表一个 OS 线程，是真正执行代码的实体：

- **M 与 P 绑定**才能运行 goroutine，无 P 的 M 处于休眠状态
- 系统调用时 M 与 P 解绑，系统调用返回后重新尝试获取 P
- **M0**：程序启动时的主线程，负责初始化 runtime 并启动第一个 goroutine

### 2.3 P（Processor，逻辑处理器）

`P` 是调度器的核心，**数量由 `GOMAXPROCS` 控制**（默认等于 CPU 核心数）：

| 职责 | 说明 |
|-----|------|
| **本地运行队列（LRQ）** | 持有等待执行的 G 队列（最多 256 个） |
| **调度决策** | 决定下一个要运行哪个 G |
| **缓存** | 持有 mcache（内存分配缓存），减少全局锁竞争 |

> **P 的数量 = 最大并行度**。4 核 CPU 设置 GOMAXPROCS=4，最多同时有 4 个 M 并行执行 goroutine。

---

## 三、调度策略

### 3.1 Work Stealing（工作窃取）

**问题**：某个 P 的本地队列已空，但其他 P 的队列很满。

**解决**：空闲 P 从其他 P 的本地队列**尾部偷取一半**的 G 来执行。

```
P0（空）  窃取 →  P1（队列满）
                  [G5, G6, G7, G8]
                        ↓ 偷走后半
P0: [G7, G8]    P1: [G5, G6]
```

**意义**：充分利用多核，避免某些 P 空转而另一些 P 繁忙。

### 3.2 Hand Off（移交机制）

**问题**：M 正在运行 G 时发生**系统调用（syscall）**，M 会被阻塞，无法继续调度其他 G。

**解决**：
1. M0 执行 G0 发生系统调用，M0 与 P0 **解绑**
2. P0 找一个空闲的 M1（或新建 M1），M1 与 P0 绑定继续执行其他 G
3. M0 系统调用返回后，G0 进入全局运行队列（GRQ），M0 寻找空闲 P 或休眠

```
          系统调用
M0+P0+G0  →→→  M0（阻塞中，执行syscall）
                P0 移交给新的 M1
               M1+P0（继续执行队列中的其他G）
```

### 3.3 抢占式调度

Go 1.14 之前使用**协作式抢占**：goroutine 只在函数调用时才会被抢占，如果 goroutine 进入无函数调用的死循环，会饿死其他 goroutine。

Go 1.14+ 引入**基于信号的异步抢占（SIGURG）**：
- sysmon 线程定期检查，若 goroutine 运行超过 10ms，发送 SIGURG 信号
- 强制中断当前 goroutine，保存状态，让出 P

### 3.4 全局队列（GRQ）与 61 轮询机制

除 P 的本地队列外，还有一个**全局运行队列（GRQ）**：

**为什么需要 GRQ？**
- 系统调用返回的 G、被创建的 G 超出 LRQ 上限时放入 GRQ

**61 轮询机制（公平性保障）**：
每执行 **61 次**本地队列调度后，P 必须从 GRQ 取一个 G 执行，避免 GRQ 中的 G 长期饿死。

```go
// 调度循环伪代码
func schedule() {
    if gp == nil {
        // 每 61 次从全局队列取（公平性）
        if _p_.schedtick % 61 == 0 && sched.runqsize > 0 {
            gp = globrunqget(_p_, 1)
        }
    }
    if gp == nil {
        // 从本地队列取
        gp, inheritTime = runqget(_p_)
    }
    if gp == nil {
        // 本地队列空：工作窃取 + 阻塞等待
        gp, inheritTime, _ = findrunnable()
    }
    execute(gp, inheritTime)
}
```

---

## 四、go func() 的完整执行流程

```
go func() { ... }
        ↓
1. runtime 创建 G 对象，初始化栈（2KB）
        ↓
2. 优先放入当前 P 的本地运行队列（LRQ）
   若 LRQ 满（>256），放入全局队列（GRQ）
        ↓
3. 当前 M+P 调度到该 G 时，执行 G 的函数
        ↓
4. G 函数执行完毕 → Gdead 状态，G 对象被复用（goroutine 池）
```

---

## 五、sysmon 监控线程

`sysmon` 是 Go runtime 的后台监控线程，**不需要 P** 即可运行：

| 任务 | 描述 |
|-----|------|
| 抢占检查 | 检测运行超过 10ms 的 goroutine，触发抢占 |
| 网络轮询 | 检查 netpoll 中已就绪的 I/O 事件，唤醒等待的 G |
| 系统调用超时 | 检测阻塞在系统调用超过 20μs 的 M，触发 hand-off |
| GC 检查 | 定期强制执行 GC |

---

## 六、面试高频问题

### Q1：GMP 中 P 的作用是什么？为什么需要 P？

**答**：P 是 G 和 M 之间的中间层，其核心作用有二：
1. **持有本地运行队列**：减少对全局队列的锁竞争，提高调度效率
2. **持有 mcache**：每个 P 有独立的内存分配缓存，无锁分配小对象

如果没有 P，所有 M 直接从全局队列取 G，需要频繁加全局锁，高并发下性能很差。

### Q2：goroutine 泄漏的原因有哪些？如何检测？

**答**：常见原因：
- **Channel 泄漏**：goroutine 阻塞等待一个永远没有数据的 channel（发送方已退出）
- **锁未释放**：goroutine 获取锁后因 panic 等未释放，其他 goroutine 永久阻塞
- **无限循环**：goroutine 进入死循环未退出

**检测方法**：
```go
// 使用 runtime 查看 goroutine 数量
fmt.Println(runtime.NumGoroutine())

// 使用 pprof 分析
import _ "net/http/pprof"
// 访问 /debug/pprof/goroutine?debug=1 查看所有 goroutine 堆栈
```

### Q3：GOMAXPROCS 设置多少合适？

**答**：
- **CPU 密集型任务**：设置为 CPU 核心数（默认值），避免过多 P 导致无谓的上下文切换
- **I/O 密集型任务**：可以适当增大，因为大量 goroutine 会阻塞在 I/O，多 P 能更充分利用 CPU
- 云原生环境注意使用 `runtime.GOMAXPROCS(0)` 结合 `go.uber.org/automaxprocs` 自动适配容器 CPU 配额

### Q4：goroutine 和线程的区别？

| 维度 | goroutine | OS Thread |
|-----|----------|----------|
| 栈大小 | 初始 2~8 KB，动态伸缩 | 固定 1~8 MB |
| 创建开销 | 极小（μs 级） | 较大（ms 级） |
| 切换方式 | 用户态，~100ns | 内核态，~1μs |
| 调度者 | Go runtime | OS 内核 |
| 通信 | Channel（CSP 模型） | 共享内存 + 锁 |

### Q5：work stealing 从队列的哪端偷？为什么？

**答**：从**尾部**偷取。

原因：P 从**头部**取自己的任务（FIFO），而 stealing 从尾部取，这样被偷的任务是"最新入队的"。这有利于**局部性**：最新创建的 G 更可能与当前 P 的工作相关，先执行自己的旧任务，将新任务让给其他 P，减少缓存失效。

---

## 相关链接

- [[垃圾回收GC]] - GC 与 goroutine 的配合（STW、并发标记）
- [[内存分配]] - mcache/mcentral/mheap 与 P 的关系
- [[go_channel]] - goroutine 通信的核心机制
- [[协程]] - goroutine 使用最佳实践
