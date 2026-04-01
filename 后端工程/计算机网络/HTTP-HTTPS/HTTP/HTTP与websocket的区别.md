---
tags:
  - 计算机网络/HTTP
  - 面试题
created: 2026-03-17
---

# HTTP 与 WebSocket 的区别

## 一、核心区别

| 维度        | HTTP                     | WebSocket                 |
| --------- | ------------------------ | ------------------------- |
| **通信模式**  | 半双工（客户端请求 → 服务器响应）       | **全双工**（双方可随时互发消息）        |
| **连接模式**  | 短连接 / 持久连接（但仍是请求-响应模式）   | 长连接（一次握手，持续通信）            |
| **服务器推送** | ❌ 不支持主动推送                | ✅ 服务器可主动推送                |
| **协议**    | HTTP/1.1, HTTP/2, HTTP/3 | WebSocket（ws:// 或 wss://） |
| **头部开销**  | 每次请求都携带完整 Header（较大）     | 帧头部极小（2~10 字节）            |
| **适用场景**  | 页面加载、RESTful API         | 实时通信（聊天、游戏、行情推送）          |

---

## 二、HTTP 实现"实时推送"的方案（对比）

在 WebSocket 出现之前，HTTP 实现服务器推送有以下几种方式：

### 短轮询（Short Polling）
```
客户端每隔 N 秒发一次请求，询问服务器有没有新数据
缺点：延迟高，大量无效请求，浪费资源
```

### 长轮询（Long Polling）
```
客户端发送请求后，服务器挂起，直到有数据才响应
客户端收到响应后立即再次发请求
缺点：服务器需要维持大量挂起连接，资源消耗大
```

### SSE（Server-Sent Events）
```
HTTP/1.1 的"流式响应"，服务器可以持续发数据
只支持服务器→客户端单向推送
缺点：只能单向，不能客户端→服务器推送
```

> **WebSocket** 真正解决了双向实时通信的问题。

---

## 三、WebSocket 的建立过程

WebSocket 基于 HTTP 协议进行握手升级，建立后使用独立的 WebSocket 协议通信。

### 第 1 步：HTTP 升级握手

客户端发送一个特殊的 HTTP 请求：

```http
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket               ← 升级协议
Connection: Upgrade              ← 连接升级
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==   ← 随机 Base64 码
Sec-WebSocket-Version: 13
```

### 第 2 步：服务器响应（101 Switching Protocols）

```http
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=   ← 服务器计算后返回
```

> `Sec-WebSocket-Accept` = Base64(SHA1(`Sec-WebSocket-Key` + 固定魔法字符串))
> 这个机制用于验证服务端确实支持 WebSocket，防止误连接。

### 第 3 步：升级完成，切换到 WebSocket 协议

```
握手后，HTTP 连接"升级"为 WebSocket 连接
TCP 连接保持不断开
双方可以随时发送数据帧
```

```
客户端                     服务端
  │── HTTP 握手请求 ──────>│
  │<── 101 切换协议 ────── │
  │                        │
  │<──── WS 消息（推送）──── │   ← 服务器主动推送
  │──── WS 消息 ──────────>│   ← 客户端发送
  │<──── WS 消息 ──────────│
  │                        │
  │── WS 关闭帧 ──────────>│
  │<── WS 关闭确认 ────────│
```

---

## 四、WebSocket 帧格式

WebSocket 数据以"帧（Frame）"为单位传输，帧头部极小，开销远低于 HTTP。

```
 0                   1                   2
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |                               |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+-------------------------------+
```

- **FIN**：是否是最后一帧
- **opcode**：帧类型（文本、二进制、Ping、Pong、关闭等）
- **Payload len**：数据长度

### WebSocket 解决粘包问题

- TCP 是流式协议，存在粘包/拆包问题（接收方不知道一条消息的边界）
- WebSocket **在帧头部记录了 Payload 长度**，接收方根据长度字段准确读取完整消息
- 不需要应用层自行实现消息边界处理

---

## 五、WebSocket 的心跳机制

WebSocket 连接长时间不通信，可能被中间的防火墙、NAT 设备断开。

**心跳实现**：
```
客户端/服务端定期发送 Ping 帧
对方收到后回复 Pong 帧
若超时未收到 Pong，则认为连接已断开，主动重连
```

---

## 六、适用场景对比

| 场景 | 推荐协议 | 原因 |
|------|---------|------|
| 普通 Web 页面、RESTful API | HTTP | 无状态，简单高效 |
| 在线聊天室 | WebSocket | 需要双向实时通信 |
| 实时游戏 | WebSocket | 低延迟，频繁双向交互 |
| 股票/行情推送 | WebSocket 或 SSE | 服务器高频推送 |
| 协作文档（多人编辑） | WebSocket | 需要实时同步所有客户端状态 |
| 消息通知（低频） | SSE 或长轮询 | 只需单向推送，成本更低 |

---

## 相关笔记

- [[HTTP协议详解]]
- [[什么是HTTP]]
- [[HTTP与RPC的区别]]
