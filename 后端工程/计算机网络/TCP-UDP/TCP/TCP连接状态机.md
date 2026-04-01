# TCP 连接状态机

---

## 一、完整状态列表

| 状态 | 描述 |
|------|------|
| **CLOSED** | 初始状态，无连接 |
| **LISTEN** | 服务端监听中，等待连接请求（被动打开） |
| **SYN_SENT** | 客户端已发送 SYN，等待服务端确认 |
| **SYN_RCVD** | 服务端收到 SYN 并回复 SYN+ACK，等待客户端 ACK |
| **ESTABLISHED** | 连接已建立，双方可以正常收发数据 |
| **FIN_WAIT_1** | 主动关闭方已发送 FIN，等待对方 ACK |
| **FIN_WAIT_2** | 主动关闭方收到 ACK，等待对方的 FIN |
| **CLOSE_WAIT** | 被动关闭方收到 FIN 并回复 ACK，等待应用程序调用 close() |
| **CLOSING** | 双方同时发起关闭（同时收到对方 FIN），等待对方 ACK |
| **LAST_ACK** | 被动关闭方已发送 FIN，等待最后一个 ACK |
| **TIME_WAIT** | 主动关闭方发送最后的 ACK，等待 2MSL 确保对方收到 |

---

## 二、状态转换图

### 连接建立（三次握手）

```
客户端                                  服务端
CLOSED                                 CLOSED
  │   主动打开，发送 SYN               │
  │──────────── SYN ──────────────────▶│ LISTEN
  │                                    │ 收到 SYN，回复 SYN+ACK
SYN_SENT                             SYN_RCVD
  │◀─────────── SYN+ACK ──────────────│
  │ 收到 SYN+ACK，回复 ACK            │
  │──────────── ACK ──────────────────▶│
ESTABLISHED                         ESTABLISHED
```

### 连接释放（四次挥手）

```
客户端（主动关闭）                      服务端（被动关闭）
ESTABLISHED                          ESTABLISHED
  │ 应用调用 close()，发送 FIN         │
  │──────────── FIN ──────────────────▶│
FIN_WAIT_1                          CLOSE_WAIT ← 收到FIN，ACK
  │◀─────────── ACK ──────────────────│
FIN_WAIT_2                           │ 应用处理完数据后调用 close()
  │◀─────────── FIN ──────────────────│ LAST_ACK
TIME_WAIT                            │
  │──────────── ACK ──────────────────▶│
  │（等待 2MSL）                       CLOSED
CLOSED
```

---

## 三、CLOSE_WAIT 大量堆积问题

### 现象

服务器上出现大量 **CLOSE_WAIT** 状态的连接，通常是线上故障的信号。

### 原因

CLOSE_WAIT 是被动关闭方收到 FIN 后、发送自己的 FIN 之前的中间状态。

正常情况下该状态持续时间极短（应用程序调用 `close()` 后即转为 LAST_ACK）。

**大量 CLOSE_WAIT 的根本原因：应用程序没有调用 `close()` 关闭连接**，可能因为：
1. 代码中未处理连接关闭逻辑（如忘记在 finally 块中关闭连接）
2. 程序发生异常，未执行到 close() 代码
3. 连接池未正确回收连接
4. 应用处理速度过慢，积压了大量待关闭连接

### 危害

- 每个 CLOSE_WAIT 连接都占用文件描述符
- 文件描述符耗尽 → 无法接受新连接 → 服务不可用

### 排查方法

```bash
# 查看各状态连接数量
netstat -an | awk '/tcp/ {print $6}' | sort | uniq -c

# 查看 CLOSE_WAIT 的连接详情
netstat -anp | grep CLOSE_WAIT
```

---

## 四、FIN_WAIT_2 状态时间限制

`FIN_WAIT_2` 状态表示主动关闭方等待对方的 FIN，若服务端长时间不发 FIN（如应用程序未调用 close()），主动关闭方会永久停留在此状态。

Linux 通过 `tcp_fin_timeout`（默认 60 秒）控制该状态的最大等待时间，超时后连接直接关闭。

---

## 五、同时关闭（CLOSING 状态）

若双方几乎同时发起关闭，双方都收到对方的 FIN 但还未收到 ACK，进入 **CLOSING** 状态。
这是较少见的情况，最终双方都会进入 TIME_WAIT，然后关闭。
