# 最直观的区别

1. get用来获取数据，post用来提交数据
2. get参数有长度限制(受限于url长度，最长2048字节)，而post无限制
3. get请求的数据会附加在url之后，以`?`分割url，多个参数使用`&`连接。而post请求会把数据放在http请求体中。
4. get是明文传输，在url上;post是放在请求体中，但是开发者可以通过抓包看到，也相当于明文了。
5. get请求会保存在浏览器历史记录中，还可能保存在web服务器的日志中。

## 总结

get请求一般用于获取数据，请求数据表现在url上，会保存在浏览器历史记录中；
post请求一般用于提交数据，请求数据放在请求体上，没有特定设置，一般不会保存在浏览器历史记录中。

get和post本质上都是tcp连接，对于安全性只是针对不同的人群(普通用户和开发者)。


# 在RFC层面的区别

## 什么是RFC

Request For Comments（RFC），是一系列以编号排定的文件。文件收集了有关互联网相关信息，以及UNIX和互联网社区的软件文件。

简单来说，RFC 是Internet协议字典，它里面包含了所有互联网技术的规范。

## RFC的三个性质

### 1. safe(安全)

如果客户端向服务器发起的请求如果没有引起服务器端任何的状态变化，那么它就是安全的。
而post请求提交数据就必然会引起服务器端的状态改变。
那么可以说，get请求相对服务器而言是安全的，post则是不安全的。

### 2. idempotent(幂等)

幂等通俗来讲就是指同一个请求执行多次和仅执行一次的效果是完全相等的。
例如get请求用于获取资源，无论执行一次还是执行多次，效果都是完全相等的。
而post请求用户提交资源，会引起服务器端的状态改变。如提交表单，第一次提交成功后，如果第二次再次提交可能会返回不一样的结果。

### 3. cacheeable(可缓存的)

意思就是一个请求是否可以被缓存。绝对多数情况，post是不可缓存的(某些浏览器支持缓存)，但get是可以缓存的。

## 总结

1. get请求获取指定资源，是安全、幂等、可缓存的，且get请求的报文主体一般不用于使用。
2. post请求时根据报文主题来对指定资源做出处理，是不安全、不幂等、不可缓存的(部分情况)。

# 关于post请求是产生一个TCP数据包还是两个 

看到有很多文章说“get产生一个TCP数据包；post产生两个TCP数据包”，对此许多文章众说纷纭。

后来看到一个合理的解释是，
> post请求会先发一个tcp包，把header发过去，然后因为nagle算法的原因，就等待一个tcp的ack，然后再发剩下一个包。

原文在这里，具体解释了post请求比get请求多200ms，原因是ruby的`net::HTTP`库，会将一个http请求拆分，先发送header部分，

而go语言`net/http`库通常是将请求头和请求体一起发送，一般不会拆分，除非请求体非常大，超出了单个TCP包的大小。

```go
func send(ireq *Request, rt RoundTripper, deadline time.Time) (resp *Response, didTimeout func() bool, err error) {   
    if rt == nil {  
       req.closeBody()  
       return nil, alwaysFalse, errors.New("http: no Client.Transport or DefaultTransport")  
    }  
    if req.URL == nil {  
       req.closeBody()  
       return nil, alwaysFalse, errors.New("http: nil Request.URL")  
    }  
    if req.RequestURI != "" {  
       req.closeBody()  
       return nil, alwaysFalse, errors.New("http: Request.RequestURI can't be set in client requests")  
    }  
    // forkReq forks req into a shallow clone of ireq the first  
    // time it's called.    forkReq := func() {  
       if ireq == req {  
          req = new(Request)  
          *req = *ireq // shallow clone  
       }  
    }  

	// 处理请求头
	if req.Header == nil {  
       forkReq()  
       req.Header = make(Header)  
    }  
    if u := req.URL.User; u != nil && req.Header.Get("Authorization") == "" {  
       username := u.Username()  
       password, _ := u.Password()  
       forkReq()  
       req.Header = cloneOrMakeHeader(ireq.Header)  
       req.Header.Set("Authorization", "Basic "+basicAuth(username, password))  
    }  
    if !deadline.IsZero() {  
       forkReq()  
    }    stopTimer, didTimeout := setRequestCancel(req, rt, deadline)  
  
    resp, err = rt.RoundTrip(req)  
    if err != nil {  
       stopTimer()  
       if resp != nil {  
          log.Printf("RoundTripper returned a response & error; ignoring response")  
       }       if tlsErr, ok := err.(tls.RecordHeaderError); ok {  
                  if string(tlsErr.RecordHeader[:]) == "HTTP/" {  
             err = ErrSchemeMismatch  
          }  
       }       return nil, didTimeout, err  
    }  
    if resp == nil {  
       return nil, didTimeout, fmt.Errorf("http: RoundTripper implementation (%T) returned a nil *Response with a nil error", rt)  
    }    
    
    // 处理请求体
    if resp.Body == nil {    
          return nil, didTimeout, fmt.Errorf("http: RoundTripper implementation (%T) returned a *Response with content length %d but a nil Body", rt, resp.ContentLength)  
       }       resp.Body = io.NopCloser(strings.NewReader(""))  
    }    if !deadline.IsZero() {  
       resp.Body = &cancelTimerBody{  
          stop:          stopTimer,  
          rc:            resp.Body,  
          reqDidTimeout: didTimeout,  
       }  
    }    return resp, nil, nil  
}
```
从这段源码中可以看出，客户端发送数据时，`writeRequest`函数负责写入header，而body的写入是在header之后进行的。

