---
tags:
  - Go
  - Channel
  - 并发
  - 面试
aliases:
  - Go Channel原理
  - hchan
  - channel底层
created: 2026-03-23
---

# Go Channel 底层原理

> Channel 是 Go 并发模型（CSP）的核心工具：**通过通信来共享内存，而不是通过共享内存来通信**。面试重点：hchan 结构 → 收发流程 → 阻塞/唤醒机制 → 常见使用模式。

---

## 一、核心数据结构

### 1.1 hchan

```go
type hchan struct {
    qcount   uint           // 当前队列中的元素数量
    dataqsiz uint           // 循环队列的容量（make 时指定的缓冲区大小）
    buf      unsafe.Pointer // 指向循环队列的内存（只有缓冲 channel 有）
    elemsize uint16         // 元素大小（字节）
    closed   uint32         // channel 是否已关闭（0: 未关闭, 1: 已关闭）
    elemtype *_type         // 元素类型信息

    sendx uint  // 发送队列的下一个写入位置（循环索引）
    recvx uint  // 接收队列的下一个读取位置（循环索引）

    recvq waitq  // 等待接收的 goroutine 队列（sudog 链表）
    sendq waitq  // 等待发送的 goroutine 队列（sudog 链表）

    lock mutex  // 保护以上所有字段
}
```

### 1.2 循环队列（缓冲区）

缓冲 channel 的数据存在 `buf` 指向的循环队列中：

```
缓冲区（make(chan int, 5)）：
索引:  0    1    2    3    4
buf: [  ] [10] [20] [30] [  ]
      ↑                   ↑
    recvx=1             sendx=4
    （下次读从 [1] 取）  （下次写入 [4]）

qcount = 3（队列中有 3 个元素：10, 20, 30）
```

---

## 二、发送流程（ch <- v）

```
ch <- v

1. 加锁（lock）

2. 是否有等待的接收方（recvq 非空）？
   → YES：直接把 v 拷贝给等待的 goroutine，唤醒它，解锁，返回
           （bypass 缓冲区，直接交付，减少一次内存拷贝）

3. 缓冲区有空间（qcount < dataqsiz）？
   → YES：把 v 写入 buf[sendx]，sendx = (sendx+1) % dataqsiz，qcount++，解锁，返回

4. 缓冲区满（或无缓冲）且无接收方 → 当前 goroutine 阻塞：
   a. 创建 sudog 节点（包含 goroutine 指针 + 待发送数据地址）
   b. 将 sudog 加入 sendq
   c. gopark()：将当前 goroutine 从 Grunning 切换到 Gwaiting
   d. **让出 M（当前 goroutine 挂起，等待接收方唤醒）**
```

---

## 三、接收流程（v := <-ch）

```
v := <-ch

1. 加锁

2. 是否有等待的发送方（sendq 非空）？
   2a. 无缓冲 channel：直接从等待的 sender goroutine 取数据，唤醒 sender
   2b. 有缓冲且 sendq 非空（说明缓冲区已满）：
       从缓冲区头部取出数据（recvx 位置），
       然后把 sendq 中等待的 sender 的数据写入缓冲区尾部（sendx 位置），唤醒 sender

3. 缓冲区有数据（qcount > 0）？
   → YES：从 buf[recvx] 取数据，recvx = (recvx+1) % dataqsiz，qcount--，解锁，返回

4. 没有数据可读 → 当前 goroutine 阻塞：
   a. 创建 sudog 节点（包含 goroutine 指针 + 接收数据地址）
   b. 将 sudog 加入 recvq
   c. gopark()：挂起当前 goroutine

```

---

## 四、关闭 channel（close）

```go
close(ch)
```

关闭流程：
1. 加锁，将 `closed` 置为 1
2. 唤醒所有 **recvq** 中等待的 goroutine（返回零值 + false）
3. 唤醒所有 **sendq** 中等待的 goroutine（会触发 **panic**）
4. 解锁

**关闭 channel 的规则总结**：

| 操作             | 已关闭的 channel        | 未初始化（nil）的 channel |
| -------------- | ------------------- | ------------------ |
| 发送 `ch <- v`   | **panic**           | 永久阻塞               |
| 接收 `<-ch`      | 返回剩余数据或零值（ok=false） | 永久阻塞               |
| 关闭 `close(ch)` | **panic**           | **panic**          |

> **黄金法则**：谁发送，谁关闭。接收方不应关闭 channel（无法判断发送方是否还会发数据）。

---

## 五、有缓冲 vs 无缓冲
 
| 特征 | 无缓冲（make(chan T)） | 有缓冲（make(chan T, N)） |
|-----|---------------------|------------------------|
| 同步方式 | 同步：发送方和接收方**必须同时就绪** | 异步：发送方可以先于接收方运行 |
| 阻塞时机 | 发送：无接收方时阻塞；接收：无发送方时阻塞 | 发送：缓冲满时阻塞；接收：缓冲空时阻塞 |
| 使用场景 | goroutine 同步、确认信号 | 解耦生产者/消费者速率 |

```go
// 无缓冲：用作同步屏障
done := make(chan struct{})
go func() {
    doWork()
    done <- struct{}{}  // 发送完成信号
}()
<-done  // 等待 goroutine 完成

// 有缓冲：用作任务队列（背压控制）
tasks := make(chan Task, 100)
// 生产者
go func() {
    for _, t := range taskList {
        tasks <- t  // 队列满时阻塞，实现背压
    }
    close(tasks)
}()
// 消费者
for t := range tasks {
    process(t)
}
```

---

## 六、常见使用模式

### 6.1 pipeline（数据流水线）

```go
func generate(nums ...int) <-chan int {
    out := make(chan int)
    go func() {
        for _, n := range nums {
            out <- n
        }
        close(out)
    }()
    return out
}

func square(in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        for n := range in {
            out <- n * n
        }
        close(out)
    }()
    return out
}

// 使用
for result := range square(generate(2, 3, 4)) {
    fmt.Println(result)  // 4, 9, 16
}
```

### 6.2 fan-out / fan-in（扇出/扇入）

```go
// fan-out：一个输入 → 多个 worker
func fanOut(in <-chan int, n int) []<-chan int {
    outs := make([]<-chan int, n)
    for i := 0; i < n; i++ {
        outs[i] = worker(in)
    }
    return outs
}

// fan-in：多个输入 → 一个输出
func fanIn(ins ...<-chan int) <-chan int {
    out := make(chan int)
    var wg sync.WaitGroup
    for _, in := range ins {
        wg.Add(1)
        go func(ch <-chan int) {
            defer wg.Done()
            for v := range ch {
                out <- v
            }
        }(in)
    }
    go func() {
        wg.Wait()
        close(out)
    }()
    return out
}
```

### 6.3 done channel（广播取消）

```go
func worker(done <-chan struct{}, id int) {
    for {
        select {
        case <-done:
            fmt.Printf("worker %d stopped\n", id)
            return
        default:
            doWork()
        }
    }
}

done := make(chan struct{})
for i := 0; i < 5; i++ {
    go worker(done, i)
}
close(done)  // 广播：关闭 channel 唤醒所有等待的 goroutine
```

---

## 七、面试高频问题

### Q1：向已关闭的 channel 发送数据会怎样？

**答**：**panic**。`close` 会设置 `hchan.closed = 1`，发送时检测到 `closed == 1` 直接 panic。

### Q2：从已关闭的 channel 接收数据会怎样？

**答**：
- 若缓冲区还有数据，正常返回数据，`ok = true`
- 缓冲区为空，返回类型零值，`ok = false`

```go
ch := make(chan int, 2)
ch <- 1
ch <- 2
close(ch)

v, ok := <-ch  // 1, true
v, ok = <-ch   // 2, true
v, ok = <-ch   // 0, false（channel 已关闭且空）
```

### Q3：nil channel 的行为？

**答**：
- 发送：**永久阻塞**
- 接收：**永久阻塞**
- close：**panic**

> **特殊用途**：在 `select` 中可以将 case 对应的 channel 设为 nil，实现**禁用某个 case**。

```go
// 技巧：禁用 select 的某个 case
var ch1, ch2 chan int
ch1 = make(chan int, 1)
ch1 <- 42

// ch2 是 nil，select 时该 case 永远不会被选中
select {
case v := <-ch1:
    fmt.Println("ch1:", v)
case v := <-ch2:  // 永远不执行（nil channel 阻塞）
    fmt.Println("ch2:", v)
}
```

### Q4：无缓冲 channel 的发送方和接收方是如何同步的？

**答**：无缓冲 channel 的发送和接收必须**同时就绪**。若发送方先到，发送方的 goroutine 进入 `Gwaiting` 状态并挂入 `sendq`，直到接收方到来；接收方发现 `sendq` 非空，直接从发送方的栈上读取数据（**直接内存拷贝，不经过缓冲区**），唤醒发送方，两者同时继续执行。

### Q5：有缓冲 channel 满了之后，再发送数据会怎样？

**答**：发送方 goroutine 进入 `Gwaiting` 状态，加入 `sendq` 队列，挂起等待。直到有接收方取走一个元素，接收方会顺手把 `sendq` 中第一个等待的发送方的数据写入缓冲区，并唤醒该发送方。

---

## 相关链接

- [[select底层实现]] - select 与 channel 的配合
- [[gmp调度模型]] - goroutine 阻塞/唤醒与 GMP 的关系
- [[协程]] - goroutine 生命周期管理
- [[go_map]] - Go 并发安全的另一工具 sync.Map
