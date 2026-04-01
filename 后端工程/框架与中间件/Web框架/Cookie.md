在 Internet 中，Cookie 实际上是指小量信息，是由 Web 服务器创建的，将信息存储在用户计算机上（客户端）的数据文件。

一般网络用户习惯用其复数形式 Cookies，指某些网站为了辨别用户身份、进行 Session 跟踪而存储在用户本地终端上的数据，而这些数据通常会经过加密处理。

# Cookie的机制

Cookie 是由服务器端生成，发送给 User-Agent(一般是浏览器),浏览器会将 Cooike 的 key/value 保存到某个目录下的文本文件内。 下次请求同一网站时，就会发送该 Cooike 给服务器。

Cookie 名称和值可以由**服务器端开发自己定义**，这样服务器可以知道该用户是否合法以及是否需要重新登录等。

服务器可以设置或读取 Cookies 中包含的信息，借此**维护用户和服务器会话中的状态**。

总结:
1. 浏览器发送请求时，请求会自动携带 Cookie 数据。
2. 服务端来设置 Cookie 数据。
3. Cookie 是针对**单个域名**的，不同域名之间的 Cookie 是独立的。
4. Cookie 数据可以**配置过期时间**，过期的 Cookie 数据会被系统清除。

# go操作 Cookie

## Cookie

标准库`net/http`中定义了Cookie，它代表一个出现在HTTP响应头中Set-Cookie的值里或者HTTP请求头中Cookie的值的`HTTP cookie`。

```go
type Cookie struct {
    Name       string
    Value      string
    Path       string
    Domain     string
    Expires    time.Time
    RawExpires string
    // MaxAge=0表示未设置Max-Age属性
    // MaxAge<0表示立刻删除该cookie，等价于"Max-Age: 0"
    // MaxAge>0表示存在Max-Age属性，单位是秒
    MaxAge   int
    Secure   bool
    HttpOnly bool
    Raw      string
    Unparsed []string // 未解析的“属性-值”对的原始文本
}
```

## 设置 Cookie

`net/http`包中提供了`SetCookie`函数，它在`w`的头域中添加`Set-Cookie`头，该HTTP头的值为`Cookie`。

`func SetCookie(w ResponseWriter, cookie *Cookie)
`
## 获取 Cookie

`Request`对象拥有两个获取 Cookie 的方法和一个添加 Cookie 的方法:

获取Cookie的两种方法:
```go
// 解析并返回该请求的Cookie头设置的所有cookie
func (r *Request) Cookies() []*Cookie

// 返回请求中名为name的cookie，如果未找到该cookie会返回nil, ErrNoCookie。
func (r *Request) Cookie(name string) (*Cookie, error)
```

添加 Cookie 的方法:

```go
// AddCookie向请求中添加一个cookie。
func (r *Request) AddCookie(c *Cookie)
```

# gin框架操作 Cookie

```go
import (
    "fmt"

    "github.com/gin-gonic/gin"
)

func main() {
    router := gin.Default()
    router.GET("/cookie", func(c *gin.Context) {
        cookie, err := c.Cookie("gin_cookie") // 获取Cookie
        if err != nil {
            cookie = "NotSet"
            // 设置Cookie
            c.SetCookie("gin_cookie", "test", 3600, "/", "localhost", false, true)
        }
        fmt.Printf("Cookie value: %s \n", cookie)
    })

    router.Run()
}
```

# Session

Cookie 虽然解决了 “保持状态” 的需求，但是 Cookie 本身最大支持4096字节，且本身保存在客户端，可能被拦截或窃取。

因此，Session 的出现，它能**支持更多的字节**，并且它**保存在服务器**中，有**较高的安全性**。

由于HTTP协议的无状态特征，服务器根本就不知道访问者是“谁”。因此，Cookie 就起到了**桥接**的作用。
> Cookie 可以作为分辨 Session 的唯一标识 - Session ID
> 用户再次访问该网站后，请求会自带 Cookie 数据(其中包含了 Session ID)，服务端通过 Session ID 找到与之对应的 Session 数据，就知道来的人是“谁”了。

总结而言：Cookie弥补了HTTP无状态的不足，让服务器知道来的人是“谁”；但是Cookie以文本的形式保存在本地，自身安全性较差；
所以我们就通过Cookie识别不同的用户，对应的在服务端为每个用户保存一个Session数据，该Session数据中能够保存具体的用户数据信息。
