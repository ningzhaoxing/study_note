1. 如何控制协程的退出？
- 使用channel通知退出
```go
// exitChannelFn 单独退出通道关闭通知退出
func exitChannelFn(wg *sync.WaitGroup, taskNo int, dataChan chan int, exitChan chan struct{}) {
    defer wg.Done()

    for {
        select {
        case val, ok := <-dataChan:
            if !ok {
                log.Printf("Task %d channel closed ！！！", taskNo)
                return
            }

            log.Printf("Task %d  revice dataChan %d\n", taskNo, val)

            // 关闭exit通道时，通知退出
        case <-exitChan:
            log.Printf("Task %d  revice exitChan signal!\n", taskNo)
            return
        }
    }

}
```
- 使用content取消或超时通知退出
```go
// contextCancelFn context取消或超时通知退出
func contextCancelFn(wg *sync.WaitGroup, taskNo int, dataChan chan int, ctx context.Context) {
    defer wg.Done()

    for {
        select {
        case val, ok := <-dataChan:
            if !ok {
                log.Printf("Task %d channel closed ！！！", taskNo)
                return
            }

            log.Printf("Task %d  revice dataChan %d\n", taskNo, val)

        // ctx取消或超时，通知退出
        case <-ctx.Done():
            log.Printf("Task %d  revice exit signal!\n", taskNo)
            return
        }
    }

}
```

2. 开启两个协程，让其交替打印一个字符串
```go
var wg sync.WaitGroup  
  
func main() {  
    wg.Add(2)  
    c := make(chan int)  
    s := "abcdefghijk"  
    go printS(c, s)  
    c <- 0  
    go printS(c, s)  
    wg.Wait()  
}  
  
func printS(c chan int, s string) {  
    defer wg.Done()  
    for {
       index, ok := <-c  
       if !ok {  
          return  
       }  
       if index >= len(s) {  
          close(c)  
          return  
       }  
       fmt.Println(string(s[index]))  
       c <- index + 1  
    }  
}
```

1. 启动10个协程对一个变量进行100次递增操作

![[20250221141348.png]]



2. 详细讲讲go语言协程调度的实现原理(GMP调度模型)

3. 单向通道的创建；有缓冲通道和无缓冲通道的区别；如何判断一个通道是否关闭。

4. 如何优雅地关闭通道？
四种情况

6. 如何使用反射将map中的值绑定到对应tag的结构体对象字段上？
```go
type User struct {  
    Id       string `json:"id"`  
    Name     string `json:"name"`  
    Password string `json:"password"`  
}

p := map[string]any{
	"id":"1",
	"name":"jack",
	"password":"123456",
}
```

7. 什么是TCP粘包？如何解决？

8. TCP和UDP的区别？

9. TCP是如何保证可靠性的？
[传输层思维导图](传输层思维导图.md)

1. 单元测试
写一个求参数是否为质数的方法，然后单元测试这个方法是否正确

![[20250221141140.png]]

![[20250221141745.png]]