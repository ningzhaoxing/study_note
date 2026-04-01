# Redis 快的原因

## 1. 内存数据库

redis 使用内存存储，没有磁盘IO的开销。

## 2. 单线程指令执行

Redis 6.0+ 版本使用多线程进行网络IO，单线程执行。以及 Redis 7.0+ 版本的 AOF 持久化的「AOF重写」是通过 Fork 子进程来处理的，将新生成的重写文件 `fsync` 到磁盘是通过独立的子线程去执行的。
通过单线程进行命令执行，避免了多线程带来的*线程切换开销*和*锁资源竞争*，提高吞吐量和响应速度。

为什么「AOF重写」需要通过独立的子进程来处理而不是线程来处理？

> - **重写耗时极长**：需要遍历 Redis 所有数据，属于 CPU 密集型操作，时间过程会影响到命令执行。
> - **内存密集**：需要读取大量内存数据，若使用线程（共享内存），容易发生内存竞争和数据一致性问题。

## 3. 非阻塞 IO

Redis 使用 **IO 多路复用技术**，允许单个线程同时监听多个网络连接（socket），当某个连接有数据可读/可写时，系统会通知程序处理，避免了为每个连接创建线程的开销。

### 3.1 Redis 的 IO 多路复用实现

Redis 根据不同操作系统选择最优的 IO 多路复用实现：

- **Linux**: `epoll` (性能最好)
- **macOS/BSD**: `kqueue`
- **通用**: `select` / `poll` (兼容性方案)

Redis 在编译时会自动选择当前系统支持的最优方案，代码封装在 `ae.c` (A simple Event-driven programming library) 中。

### 3.2 工作流程

```
1. Redis 启动时创建一个 epoll 实例
2. 将监听 socket 注册到 epoll
3. 进入事件循环：
   ├─ epoll_wait() 阻塞等待事件
   ├─ 有客户端连接 → accept() 并注册新 socket
   ├─ 有数据可读 → 读取命令并执行
   └─ 有数据可写 → 发送响应数据
```

### 3.3 epoll 的底层实现原理

#### 核心数据结构

epoll 在 Linux 内核中维护三个关键数据结构：

1. **红黑树 (RB-Tree)**：存储所有被监听的文件描述符（fd）
2. **就绪链表 (Ready List)**：存储已就绪的 fd（有数据可读/可写）
3. **等待队列 (Wait Queue)**：存储阻塞在 epoll_wait 上的进程

#### 三个核心系统调用

**1. epoll_create()**
```c
int epfd = epoll_create(1024);  // 创建 epoll 实例
```
- 在内核中创建一个 `eventpoll` 对象
- 初始化红黑树和就绪链表
- 返回 epoll 文件描述符

**2. epoll_ctl()**
```c
epoll_ctl(epfd, EPOLL_CTL_ADD, sockfd, &event);  // 注册 fd
```
- `EPOLL_CTL_ADD`：将 fd 添加到红黑树
- `EPOLL_CTL_MOD`：修改 fd 的监听事件
- `EPOLL_CTL_DEL`：从红黑树删除 fd

**关键机制**：注册时会给 fd 绑定一个**回调函数**，当 fd 就绪时，内核会调用这个回调将 fd 加入就绪链表。

**3. epoll_wait()**
```c
int n = epoll_wait(epfd, events, maxevents, timeout);  // 等待事件
```
- 检查就绪链表是否为空
- 为空 → 将当前进程加入等待队列，进入睡眠
- 不为空 → 将就绪的 fd 拷贝到用户空间，返回

#### 事件通知机制

当网卡收到数据时：

```
1. 网卡触发硬件中断
2. CPU 执行中断处理程序
3. 内核将数据从网卡拷贝到内核缓冲区
4. 调用 fd 绑定的回调函数
5. 回调函数将 fd 加入就绪链表
6. 唤醒等待队列中的进程
7. epoll_wait() 返回就绪的 fd 数量
```

#### epoll 的两种触发模式

**LT (Level Triggered) - 水平触发**（默认）
- 只要 fd 缓冲区有数据，epoll_wait 就会返回
- 未处理完的数据下次还会通知
- 更安全，不容易丢失事件

**ET (Edge Triggered) - 边缘触发**
- 只在 fd 状态变化时通知一次
- 必须一次性读完所有数据，否则不会再通知
- 性能更高，但编程复杂

Redis 使用 **LT 模式**，保证数据不丢失。

#### 为什么 epoll 比 select/poll 快？

| 特性 | select/poll | epoll |
|------|-------------|-------|
| **fd 数量限制** | select 限制 1024 | 无限制（受系统资源限制） |
| **数据拷贝** | 每次调用都要拷贝整个 fd 集合到内核 | 只在注册时拷贝一次 |
| **查找就绪 fd** | O(n) 遍历所有 fd | O(1) 直接从就绪链表获取 |
| **内核实现** | 轮询所有 fd | 事件驱动（回调机制） |

**核心优势**：
- **红黑树管理 fd**：增删改查 O(log n)
- **就绪链表**：只返回就绪的 fd，不需要遍历
- **回调机制**：事件驱动，不需要轮询

### 3.4 Redis 中的应用

Redis 的事件循环伪代码：

```c
while (server_running) {
    // 等待事件（默认阻塞）
    int n = epoll_wait(epfd, events, MAX_EVENTS, timeout);

    for (int i = 0; i < n; i++) {
        if (events[i].data.fd == listen_fd) {
            // 新连接
            int client_fd = accept(listen_fd, ...);
            epoll_ctl(epfd, EPOLL_CTL_ADD, client_fd, ...);
        } else {
            // 已有连接的数据
            if (events[i].events & EPOLLIN) {
                // 可读：读取命令并执行
                read_and_execute_command(events[i].data.fd);
            }
            if (events[i].events & EPOLLOUT) {
                // 可写：发送响应
                send_response(events[i].data.fd);
            }
        }
    }
}
```

通过 IO 多路复用，Redis 单线程可以高效处理数万个并发连接，避免了多线程的上下文切换和锁竞争开销。


## 4. 优化的数据结构

Redis 的 String、SortedSet 等优化过的数据结构，应用层可直接使用来提升性能。

## 5. VM 虚拟内存机制


