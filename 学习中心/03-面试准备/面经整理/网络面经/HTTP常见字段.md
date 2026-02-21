- `Host`字段
	客户端发送请求时，用来指定服务器的域名。
- `Content-Length`字段
	服务器在返回数据时，会有 `Content-Length` 字段，表明本次回应的数据长度。
	![[Content-Length字段.png]]
- `Connection`字段
	字段最常用于客户端要求服务器使用「HTTP 长连接」机制，以便其他请求复用。
	![[Connection字段.png]]
- `Content-Type`字段
	用于服务器响应时，告诉客端，本次数据是什么格式。
	客户端请求时，可以用`Accept`字段声明自己可以接受哪些数据格式。
- `Content-Encoding`字段
	表明数据的压缩方法。如`Content-Encoding:gzip`。
	客户端请求时，可以用`Accpet-Encoding`字段声明自己可以接受哪些压缩方法。