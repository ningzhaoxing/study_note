---
tags:
  - 计算机网络/HTTP
  - 面试题
created: 2026-03-17
---

# HTTP 常见字段（Header）

HTTP 头部字段按作用分为四类：**通用首部**、**请求首部**、**响应首部**、**实体首部**。

---

## 一、通用首部（请求/响应都会用）

### `Connection`
控制是否保持持久连接。

```http
Connection: keep-alive   # 保持持久连接（HTTP/1.1 默认）
Connection: close        # 本次请求后关闭连接
```

![[Connection字段.png]]

### `Cache-Control`
控制缓存行为，是最重要的缓存字段。

```http
# 请求端
Cache-Control: no-cache       # 强制向服务器验证缓存（不是不缓存）
Cache-Control: no-store       # 不缓存任何内容
Cache-Control: max-age=3600   # 缓存有效期 3600 秒

# 响应端
Cache-Control: public         # 可被代理服务器缓存
Cache-Control: private        # 只能被浏览器缓存，不允许代理缓存
Cache-Control: no-cache       # 强制重新验证
Cache-Control: max-age=86400  # 缓存有效期 1 天
```

### `Date`
报文创建的日期时间（UTC 格式）。

```http
Date: Tue, 17 Mar 2026 08:00:00 GMT
```

### `Transfer-Encoding`
报文主体的传输编码方式。

```http
Transfer-Encoding: chunked   # 分块传输，不需要提前知道 Content-Length
```

---

## 二、请求首部

### `Host` ⭐
指定请求的服务器域名和端口，**HTTP/1.1 中唯一必须包含的字段**。

```http
Host: www.example.com
Host: www.example.com:8080
```

> 用途：支持同一 IP 上部署多个虚拟主机（Virtual Host）

### `User-Agent`
客户端（浏览器或应用）的标识信息。

```http
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ...
```

### `Accept`
客户端可接受的响应内容类型（MIME 类型）。

```http
Accept: text/html, application/json, */*
Accept: application/json   # 只接受 JSON
```

### `Accept-Encoding`
客户端支持的内容压缩方式。

```http
Accept-Encoding: gzip, deflate, br
```

### `Accept-Language`
客户端偏好的语言。

```http
Accept-Language: zh-CN, zh;q=0.9, en;q=0.8
```

### `Authorization`
携带认证信息（如 Bearer Token、Basic Auth）。

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Authorization: Basic dXNlcjpwYXNzd29yZA==
```

### `Cookie`
携带服务器设置的 Cookie 信息。

```http
Cookie: session_id=abc123; user_id=42
```

### `Referer`
当前请求是从哪个页面跳转过来的。

```http
Referer: https://www.google.com/search?q=http
```

### `If-Modified-Since`
条件请求：只有资源在指定时间之后修改过，才返回新内容，否则返回 304。

```http
If-Modified-Since: Tue, 17 Mar 2026 00:00:00 GMT
```

### `If-None-Match`
条件请求：与 `ETag` 配合，只有 ETag 不匹配时才返回新内容。

```http
If-None-Match: "686897696a7c876b7e"
```

### `Range`
请求资源的部分内容（用于断点续传）。

```http
Range: bytes=0-1023      # 请求前 1024 字节
Range: bytes=1024-       # 请求从第 1025 字节到结尾
```

---

## 三、响应首部

### `Content-Type` ⭐
告知客户端响应体的数据类型。

```http
Content-Type: text/html; charset=UTF-8
Content-Type: application/json; charset=UTF-8
Content-Type: image/png
Content-Type: application/octet-stream   # 二进制流（下载文件）
```

### `Content-Length` ⭐
响应体的字节长度，客户端通过它得知什么时候读完响应体。

```http
Content-Length: 1024
```

![[Content-Length字段.png]]

### `Content-Encoding`
响应体的压缩编码方式。

```http
Content-Encoding: gzip
Content-Encoding: br    # Brotli（比 gzip 压缩率更高）
```

### `Set-Cookie`
服务器设置 Cookie，客户端保存后后续请求自动携带。

```http
Set-Cookie: session_id=abc123; Path=/; HttpOnly; Secure; Max-Age=3600
```

### `Location`
用于重定向时，指明新的 URL。

```http
Location: https://www.new-example.com/
```

### `ETag`
资源的唯一标识符（版本标记），用于缓存验证。

```http
ETag: "686897696a7c876b7e"
```

### `Last-Modified`
资源最后修改时间，与 `If-Modified-Since` 配合实现缓存。

```http
Last-Modified: Tue, 17 Mar 2026 00:00:00 GMT
```

### `Content-Range`
与 206 状态码配合，说明返回的是资源的哪个范围。

```http
Content-Range: bytes 0-1023/4096   # 返回前 1024 字节，总大小 4096
```

### `Access-Control-Allow-Origin`
CORS 跨域响应头，允许指定来源的跨域请求。

```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Origin: https://www.example.com
```

---

## 四、缓存机制总结

```
强缓存（不请求服务器）：
  Cache-Control: max-age=xxx  或  Expires
  → 命中：直接使用缓存（200 from cache）

协商缓存（请求服务器验证）：
  ETag + If-None-Match（优先级更高）
  Last-Modified + If-Modified-Since
  → 未修改：服务器返回 304，客户端用缓存
  → 已修改：服务器返回 200 + 新内容
```

---

## 相关笔记

- [[HTTP协议详解]]
- [[HTTP常见状态码]]
- [[什么是HTTP]]
