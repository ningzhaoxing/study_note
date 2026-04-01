 # 原理
当一个网站A使用`Cookie`，存储`Session`或`Token`来用于单点登录和权限操作时。浏览器将`Cookie`存储到浏览器中。当用户在访问另一个网站V时，黑客可以通过伪造表单，向网站A发送修改重要信息(如密码)、支付等操作，浏览器会自动携带Cookie。
在服务端看来这就是一个正常的请求，于是在用户不知情的情况下，做出响应。

## 两个条件
1. 用户访问站点A并产生了`Cookie`
2. 用户没有退出站点A(清除`Cookie`)，就访问了黑客伪造表单的B网站

# 防御措施 

CSRF一般发生在第三方网站，而且攻击者只是冒用登录凭证而不是获取登录凭证数据，所以，可以指定以下防范策略：

- 阻止不明外部域名的访问
	- 同源检测
	- Sanmesite Cookie
- 提交Form表单时，添加本域才能获取的验证信息
	- CSRF token

## 1. 同源检测

`Cookie`的同源和浏览器的同源策略有所区别:

> - 浏览器同源策略：协议、域名和端口号都相同即同源
> - Cookie同源策略：域名相同即同源

在HTTP协议中，每个异步请求都会携带两个`header`，用来标记来源域名：
> - Origin Header
> - Referer Header

这两个`Header`在浏览器发送请求时，大多数情况会自动带上，并不能由前端修改，服务器接收到后，根据这两个`Header`来确定来源的域名。

另外，CSRF大多数情况下来自第三方域名，但并不能排除本域发起。如果攻击者有权限在本域发布评论（含链接、图片等），那么它可以直接在本域发起攻击，这种情况下同源策略无法达到防护的作用。

**综上所述**：同源验证是一个相对简单的防范方法，能够防范绝大多数的CSRF攻击。但这并不是万无一失的，对于安全性要求较高，或者有较多用户输入内容的网站，我们就要对关键的接口做额外的防护措施。

## 2. Samesite Cookie属性

`Cookie`的Sanmesite属性用来限制第三方`Cookie`，从而减少安全风险，它有三个值：

```go
Set-Cookie: SameSite = Strict; // 最为严格，完全禁止跨站点时发送Cookie
Set-Cookie: SameSite = Lax; // 只有GET请求发送
Set-Cookie: SameSite = None; // 关闭SameSite属性，但必须设置Secure属性，如下
```

```go
Set-Cookie: SameSite = None  // 无效
Set-Cookie: SameSite = None; Secure  // 有效
```
设置了`Strict`或`Lax`，基本就能阻止`CSRF`攻击，前提是浏览器支持`SameSite`属性。

## 3. CSRF token

CSRF攻击之所以能够成功是因为服务器把攻击者携带的Cookie当成了正常的用户请求,那么我们可以要求所有用户请求都携带一个无法被攻击者劫持的token,每次请求都携带这个token,服务端通过校验请求是否为正确token,可以防止CSRF攻击。

CSRF token的防护策略分为三步：
1. 将token输出到页面
	首先，用户打开页面的时候，服务器需要给这个用户生成一个Token，该Token通过加密算法对数据进行加密，一般Token都包括随机字符串和时间戳的组合，显然在提交时Token不能再放在Cookie中了，否则又会被攻击者冒用。
2. 请求中携带token
	对于GET请求，将token附在请求地址之后，如：[http://url?token=tokenValue](https://link.segmentfault.com/?enc=kuOx08E7m%2BqUKV7p%2FnjPMA%3D%3D.AzUNzDpDHqBRB5XsRd4N3xMcRkMadeubkti7Puljlw4%3D)  
	对于POST请求，要在Form表单后面加上
```go
	<input type=”hidden” name=”token” value=”tokenvalue”/>
```
3. 服务器验证token是否正确
	服务端拿到客户端给的token后，先解密token，再比对随机字符串是否一致，时间是否有效，如果字符串对比一致且在有效期内，则说明token正确。

# 总结

简单总结一下上文的CSRF攻击的防护策略：

- 自动防护策略：同源检测（`Origin`和`Referer`验证）；
- 主动防护策略：`token`验证以及配合`SameSite`设置；
- 保护页面的幂等性，不要再GET请求中做用户操作

为了更好的防御CSRF，最佳实践应该是结合上面总结的防御措施方式中的优缺点来综合考虑，结合当前Web应用程序自身的情况做合适的选择，才能更好的预防CSRF的发生。