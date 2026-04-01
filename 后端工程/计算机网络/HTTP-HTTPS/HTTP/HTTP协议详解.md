---
tags:
  - 计算机网络/HTTP
  - 面试题
created: 2026-03-17
---

# HTTP 协议详解

## 一、HTTP 报文结构

HTTP 报文分为**请求报文**和**响应报文**两种，都由以下三部分构成：
- **起始行**（Start Line）：描述请求或响应的基本信息
- **头部字段**（Header）：key-value 形式的附加信息
- **消息正文**（Body）：实际传输的数据（可选）

### 1.1 请求报文

```
GET /index.html HTTP/1.1          ← 请求行（方法 + URI + 版本）
Host: www.example.com             ← 请求头字段
Accept: text/html
Connection: keep-alive
                                  ← 空行（必须有）
[请求体，GET 通常为空]
```

**请求行**包含三部分：
- **请求方法**：GET、POST、PUT、DELETE 等
- **请求 URI**：要访问的资源路径
- **HTTP 版本**：如 HTTP/1.1、HTTP/2

### 1.2 响应报文

```
HTTP/1.1 200 OK                   ← 状态行（版本 + 状态码 + 状态描述）
Content-Type: text/html           ← 响应头字段
Content-Length: 1024
Connection: keep-alive
                                  ← 空行
<html>...</html>                  ← 响应体
```

## 二、HTTP 请求方法

| 方法 | 含义 | 安全 | 幂等 | 可缓存 |
|------|------|:----:|:----:|:------:|
| **GET** | 获取资源 | ✅ | ✅ | ✅ |
| **HEAD** | 获取报文首部（无响应体） | ✅ | ✅ | ✅ |
| **POST** | 提交数据，创建资源 | ❌ | ❌ | 条件 |
| **PUT** | 替换目标资源（完整更新） | ❌ | ✅ | ❌ |
| **PATCH** | 部分修改资源 | ❌ | ❌ | ❌ |
| **DELETE** | 删除资源 | ❌ | ✅ | ❌ |
| **OPTIONS** | 查询服务器支持的方法（常用于 CORS 预检） | ✅ | ✅ | ❌ |
| **CONNECT** | 建立隧道连接（代理 HTTPS） | ❌ | ❌ | ❌ |
| **TRACE** | 追踪请求路径（调试用，存在安全风险） | ✅ | ✅ | ❌ |

> **安全**：不修改服务器资源状态
> **幂等**：多次相同请求，结果一致

## 三、URI 与 URL

- **URI**（Uniform Resource Identifier）：统一资源标识符，用于标识资源
- **URL**（Uniform Resource Locator）：统一资源定位符，URI 的子集，还包含定位信息

**URL 格式**：
```
scheme://host:port/path?query#fragment

https://www.example.com:443/search?q=http#section1
  ↑         ↑          ↑      ↑       ↑       ↑
协议      主机名       端口   路径   查询参数  锚点
```

## 四、HTTP 内容协商

客户端和服务端通过 Header 协商传输内容的格式、语言、编码等。

| 请求头 | 响应头 | 说明 |
|--------|--------|------|
| `Accept` | `Content-Type` | 数据格式（MIME 类型） |
| `Accept-Encoding` | `Content-Encoding` | 压缩方式（gzip、br 等） |
| `Accept-Language` | `Content-Language` | 语言 |
| `Accept-Charset` | `Content-Type; charset=` | 字符集 |

## 五、Cookie 机制

HTTP 本身是无状态的，Cookie 用于在客户端存储状态信息。

**工作流程：**
1. 服务器响应报文中通过 `Set-Cookie` 字段设置 Cookie
2. 浏览器保存 Cookie，后续请求自动在 `Cookie` 字段中携带
3. 服务器读取 Cookie，获取客户端状态

```http
# 响应
Set-Cookie: session_id=abc123; Path=/; HttpOnly; Secure; Max-Age=3600

# 后续请求自动携带
Cookie: session_id=abc123
```

**Cookie 常用属性：**

| 属性 | 说明 |
|------|------|
| `Max-Age` / `Expires` | 有效期 |
| `Domain` | 适用域名 |
| `Path` | 适用路径 |
| `HttpOnly` | 禁止 JS 访问（防 XSS） |
| `Secure` | 仅 HTTPS 传输 |
| `SameSite` | 控制跨站发送（防 CSRF） |

## 六、持久连接（Keep-Alive）

**问题**：HTTP/1.0 每次请求都要新建 TCP 连接，开销大

**解决**：HTTP/1.1 默认开启持久连接，复用 TCP 连接

```
HTTP/1.1 前:  请求1[TCP建立→HTTP→TCP断开] 请求2[TCP建立→HTTP→TCP断开]
HTTP/1.1 后:  [TCP建立] 请求1→响应1 请求2→响应2 请求3→响应3 [TCP断开]
```

**管线化（Pipelining）**：HTTP/1.1 支持在等待响应之前发送多个请求，但存在**队头阻塞**问题（服务器必须按顺序响应）。

## 相关笔记

- [[什么是HTTP]]
- [[HTTP常见状态码]]
- [[HTTP常见字段]]
- [[Get和Post区别]]
