# socket简介

- `Socket`在TCP/IP网络分层中并不存在，是对TCP或UDP的封装。
	>因此，socket实际上是使唤网络上双向通讯的一套API。通常称之为”套接字“。
- `Socket`分类
	- 按连接时间
		- 短链接
		- 长连接(HTTP1.1以后也支持长连接)
	- 按客户端对服务端数量
		- 点对点
		- 点对多
		- 多对多
# go语言对Socket的支持

- `TCPAddr`结构体表示服务器IP和端口
	- IP是`type IP []byte
	- Port是服务器监听的接口
```go
type TCPAddr struct{
	IP IP
	Port int
	Zone string
}
```
- `TCPConn`结构体表示连接，封装了数据读写操作
```go
type TCPConn struct{
	conn
}
```
- `TCPLinster`负责监听服务器端特定端口
```go
type TCPListener struct {
	fd *netDF
}
```
# go实现socket

## Server
```go
func main() {  
    // 1. 创建服务器地址  
    addr, _ := net.ResolveTCPAddr("tcp4", "localhost:8899")  
    // 2. 创建监听器  
    listen, _ := net.ListenTCP("tcp4", addr)  
    // 3. 通过监听器获取客户端传递的数据  
    conn, _ := listen.Accept()  
    // 4. 转换数据  
    b := make([]byte, 1024)  
    p, _ := conn.Read(b)  
    fmt.Println(string(b[:p]))  
    // 5。 关闭连接  
    defer conn.Close()  
}
```
## Clinet

```go
func main() {  
    // 1. 创建服务器地址  
    addr, _ := net.ResolveTCPAddr("tcp4", "localhost:8899")  
  
    // 2. 获取tcp连接  
    conn, _ := net.DialTCP("tcp4", nil, addr)  
  
    // 3. 发送数据  
    conn.Write([]byte("在吗"))  
  
    // 4. 关闭连接  
    defer conn.Close()  
  
}
```