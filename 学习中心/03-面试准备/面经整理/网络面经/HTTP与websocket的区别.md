HTTP是半双工的，websocket是全双工的。
服务器主动推送，HTTP只能通过定时轮询或长轮询的方式。
而webscoket可以实现客户端和服务端的全双工通信。

# websocket的建立过程
在 TCP三次握手 建立连接后，先使用HTTP协议通信一次。

然后在HTTP请求里带上 *特殊的header头*
表明浏览器像升级协议为websocket，同时带上一段 **随机生成的base64码**，并发送给服务器。

服务器收到请求后，根据客户端生成的 base64码， 用某个公开的算法变成另一段字符串。

# websocket解决粘包问题
