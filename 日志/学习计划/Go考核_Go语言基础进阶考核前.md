# go.mod

```go
//初始化
go mod init
// 下载依赖到cache
go mod download
// 检查并更新依赖
go mod tidy
// 复制依赖到vendor
go mod vendor
```

## 四大命令

```go
module 指定包名

require 指定第三方依赖

replace 替换require中声明的依赖，使用另外的依赖或版本号

replace 的使用场景
1. 将依赖替换为别的版本
2. 引入本地包替换，进行调试和测试
3. 替换不可载的包，换为其他镜像源
4. 禁止被依赖的情况

exclude 排除第三方依赖
```

# 文件操作

> 文件操作主要使用`os`和`bufio`包，前者是不带缓冲的，后者是带缓冲的。

## 打开文件

```go
// 获取文件指针
os.Open(filename) 返回文件指针和错误，若文件不存在，返回PathError。该文件只能用于读操作。

os.OpenFile(filename, flag, perm) 指定操作模式和权限来打开文件。flag用于选择操作模式，如读、写、读写、追加、不存在创建新文件
```

## os包文件的读写

```go
// 通过指针读
file.Read(b []byte) 会返回读入数据的字节长度和错误。

// 通过指针写
file.Write(b []byte) 返回写入数据字节长度和错误

file.WriteString(s string) 返回字符串长度和错误。直接写入字符串

file.WriteAt(b []byte, off int64) 从指定位置写入数据，off为偏移量。

```

## bufio包文件的读写

```go
// 通过文件指针读
reader := bufio.NewReader(rd io.Reader) eg:file

reader.ReadString(dalim byte) 返回读到的字符串(包括分割符)和错误。
dalim为分隔符，读到哪结束

// 通过文件指针写
bufio.NewWriter(file)
defer writer.Flush()
writer.WritrString(s string)

```

# 单元测试

```go
1. 测试用例的go文件名必须以"xxx_test.go"的格式命名
2. 测试用例函数必须以"TestXxx"开头，一般是Test+被测试函数名，且必须大驼峰命名。但也可以不按照这个命名。
3. TestAdd(t testing *T)形参类型必须是这样的
4. 运行测试用例指令
- go test 运行正确，无日志；错误会输出日志
- go test -v 运行不管正确还是错误，都输出日志
5. t.Fatalf()来格式化错误信息;t.Logf()打印信息日志
```

# 并发

```go
1. 并发与并行的区别
2. 进程、线程与协程的关系
3. 线程协作性能不高的原因
	- 同步锁
	- 线程阻塞状态和可运行状态的切换
	- 上下文切换
4. 协程的解决
	- 由程序控制，不消耗系统资源
	- 协程拥有自己的寄存器上下文和栈
5. 多协程资源竞争问题
	- 使用并发安全的数据结构，如sync.map
	- 使用全局读写锁
	- 使用队列
6. `go`关键字开启协程
```

# 互斥锁

```go
1. 互斥锁 sync.Mutex
2. 读写互斥锁 sync.RWMutex 可以单独获取读锁或写锁。在获取写锁后，无论是获取读锁还是写锁都需要等待，即读锁和写锁是互斥的
3. 任务并发同步 sync.WaitGroup 可以等待被注册的协程执行完成
4. 一次加载 sync.Once 通过once.Do()可以保证程序只被初始化一次。内部包含了一个互斥锁和布尔值。
5. 并发安全版map sync.Map 开箱即用，方法如`Store``Load``LoadOrStore``LoadAndDelete``Delete``Range`
6. 原子操作 atomic包，针对整数数据类型的原子操作，保证并发安全
```
 
# Channel

```go
1. 特点
	1. 用于协程之间的通并发安全
	2. 用于协程之间的通并发安全
2. 定义
	1. 
	2. 双向(可读可写) var ch chan int
	3. 单向(只可读或可写) ch := make(chan <- int) | ch := make(chan -> int)
	4. 带缓冲 ch := make(chan int, 10)
	5. 不带缓冲 ch := make(chan int)
3. 基本操作
	1. 读 <- chan 写 chan <-
	2. 关闭 close(chan)
	3. 判断是否关闭 if v ,ok := <-ch;ok {} ok为false，则说明channel关闭，读到零值
	4. select的使用
4. 同步和异步的channel
	1. 同步的channel是无缓冲的。需要接收和发送双方都准备好才能操作，否则一方会阻塞等待。
	2. 异步的channel是有缓冲的。
5. channel的超时处理
	当channel读取数据超出一定时间，可以通过另一个channel作为通知，防止一直阻塞
6. 如何优雅的关闭channel(遵守单一发送者关闭原则)
	1. 多个接收者和一个发送者。在发送者处理完逻辑后，关闭通道。
	2. 一个接收者和多个发送者。设置额外的channel，用于通知发送者不需要再发送数据了，不用显式地关闭，会被垃圾回收。
7. 多个接收者和多个发送者。引入中间者。通过关闭额外的信号通道，来通知所有接收者和发送者停止工作。
```


# 反射

```go
反射依赖于reflect包

1. 通过reflect.TypeOf获取类型，reflect.ValueOf获取值，reflect.Kind获取种类
2. 通过反射获取值：
	1. v.Kind获取reflect包中本身存在的数据类型，如reflect.Int64。然后v.Int()。
	2. v.Interface() 获取其接口，然后进行类型断言
3. 通过反射改变变量值：
	1. 传入的值必须是指针(地址)
	2. 使用v.Elem()方法获取指针对应的值
	3. v.Elem().SetInt(200)
4. isNil()和isVaild() 
	1. isNil()传入的值必须是引用类型，否则会panic
	2. isVaild()判断一个值是否为零值，除了IsVaild,String,Kind都会painc
5. 结构体反射
	1. 先通过reflect.TypeOf()获取反射对象的信息
	2. 然后可以通过reflect.Type的NumField()和Field()等方法获取结构体成员具体信息
```


# redis基础

```go
1. string类型
	1. set key value 
	2. get key
	3. incr key
	4. decr key
	5. append key value
2. hash类型
	1. 是一个键值对集合，是一个string类型的键值对映射表，最多可存储2^32-1个键值对
	2. hset key field value
	3. hget key field
	4. hgetall key 获取所有字段和值
	5. hdel key field
	6. hexists key field
	7. hkeys key 获取所有字段
	8. hincrby key field increment 为哈希表中指定字段的整数值加上增量
3. List类型
	1. lpush key value 
	2. rpush key value
	3. linsert key before|after pivot value
	4. lpop key value
	5. rpop key value
	6. lrange key start stop
	7. blpop key timeout
	8. brpop key timeout 阻塞读，从左或从右
4. set类型
	1. 是string类型的无序集合
	2. sadd key value
	3. srem key value 移除集合中一个或多个成员
	4. spop key 移除并返回集合中的一个随机元素
	5. smenbers key 
	6. sismenber key value
	7. scard key 获取集合成员数
5. zset类型
	1. 相对于set，每个元素会关联一个double类型的分数
	2. zset通过分数来进行自动排序
	3. zadd key score value
	4. zrem key value
	5. zrange key start stop
	6. zcard key 获取集合成员数
	7. zrank key menber 返回有序结合指定成员的索引
```