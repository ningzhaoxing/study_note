#  Channel

## `Channel`介绍

- 本质上是一个**队列**，数据**先进先出**
- 线程安全，允许并发访问
- 主要用于**协程**之间的通信

## `channel`的基本使用

### 定义`channel`

- 可读可写的`channel`

  `var ch chan [数据类型]`

- 单向`channel`

  `ch := make(chan <- int)`|``ch := make(chan -> int)`

### `channel`基本操 作 读`<- ch`

- 写`ch <-`
- 关闭`close(ch)`

注意：对于`nil channel`有一个特殊情况。当`nil channel`在`select`的某个`case`中时，这个`case`会阻塞，但不会造成死锁。

## 带缓冲和不带缓冲的`channel`

### 不带缓冲区的`channel`

不指定`channel`的长度

`ch := make(chan int)`

### 带缓冲区的`channel`

指定`channel`的长度

## 判断`channel`是否关闭

```go
if v, ok := <-ch; ok {
    fmt.Println(ch)
}
```

- ok为true，读到数据，且`channel`没有关闭
- ok为false，`channel`已关闭，没有数据可读

读到已经关闭的`channel`会读到零值

## `select`的使用

```go
for {
	select {
	case ch <- x:
		x, y = y, x+y
	case <-quit:
		fmt.Println("quit")
		return
	}
}
```

## 使用`channel`的一些场景

### 1. 作为`goroutine`的数据传输管道

```go
package main

import "fmt"

// https://go.dev/tour/concurrency/2
func sums(s []int, c chan int) {
	sum := 0
	for _, v := range s {
		sum += v
	}
	c <- sum
}

func main() {
	s := []int{7, 2, 8, -9, 4, 0}

	c := make(chan int)
	go sums(s[:len(s)/2], c)
	go sums(s[len(s)/2:], c)

	x, y := <-c, <-c // receive from c

	fmt.Println(x, y, x+y)
}
```

利用`goroutine`和`channel`分批求和

### 2. 同步的channel

> 无缓冲区的`channel`可以作为同步数据的管道，起到同步数据的作用

无缓冲区的`channel`需要发送者和消费者一一配对，才能完成发送和接收的操作。

若双方没有同时准备好，`channel`会导致先执行发送或接收的`goroutine`阻塞等待，直到对方做好准备。

```go
package main

import (
	"fmt"
	"time"
)

//https://gobyexample.com/channel-synchronization
func worker(done chan bool) {
	fmt.Println("working...")
	time.Sleep(time.Second)
	fmt.Println("done")

	done <- true
}

func main() {
	done := make(chan bool)
	go worker(done)

	<-done
}
```

> 在同一个`goroutine`中使用无缓冲`channel`(同步地使用)，来发送和接收数据，会导致死锁

### 3. 异步的`channel`

有缓冲区的`channel`可作为异步的`channel`使用

注意事项：

> 1. 如果`channel`中没有值，`channel`为空，那么接收者会被阻塞
>
> 2. 如果`channel`缓冲区满了，那么发送者会被阻塞
>
>    **注意：**有缓冲区的`channel`，用完要`close`，不然处理这个`channel`的`goroutine`会被阻塞，形成死锁。

```go
package main

import (
	"fmt"
)

func main() {
	ch := make(chan int, 4)
	quitChan := make(chan bool)

	go func() {
		for v := range ch {
			fmt.Println(v)
		}
		quitChan <- true // 通知用的channel，表示这里的程序已经执行完了
	}()

	ch <- 1
	ch <- 2
	ch <- 3
	ch <- 4
	ch <- 5

	close(ch)  // 用完关闭channel
	<-quitChan // 接到channel通知后解除阻塞，这也是channel的一种用法
}
```

### 4. `channel`超时处理

`channel`结果 `time`实现超时处理

当一个`channel`读取数据超出一定时间还没有数据来时，可以得到超时通知，防止一直阻塞当前`goroutine`

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	ch := make(chan int)
	quitChan := make(chan bool)

	go func() {
		for {
			select {
			case v := <-ch:
				fmt.Println(v)
			case <-time.After(time.Second * time.Duration(3)):
				quitChan <- true
				fmt.Println("timeout, send notice")
				return
			}
		}
	}()

	for i := 0; i < 4; i++ {
		ch <- i
	}

	<-quitChan // 输出值，相当于收到通知，解除主程阻塞
	fmt.Println("main quit out")
}
```

## 使用`channel`的注意事项和死锁分析

### 未初始化的`channel`读写关闭操作

```go
var ch chan int
<-ch  // 未初始化channel读数据会死锁

var ch chan int
ch<-  // 未初始化channel写数据会死锁

var ch chan int
close(ch) // 关闭未初始化channel，触发panic
```

### 已初始化的`channel`读写关闭操作

#### 1. 无缓冲区的`channel`

- 片段1

```go
ch := make(chan int)
ch <- 4

ch := make(chan int)
val, ok := <-ch
```

无缓冲区，且只有写入或读入一方，会产生死锁

- 片段2

```go
   // 代码片段4
   func main() {
   	ch := make(chan int)
   	ch <- 10
   	go readChan(ch)
   	
    time.Sleep(time.Second * 2)
   }
   
   func readChan(ch chan int) {
   	for {
   			val, ok := <-ch
   			fmt.Println("read ch: ", val)
   			if !ok {
   				break
   			}
   		}
 	}
```

该代码片段会报错`fatal error: all goroutines are asleep - deadlock!`

这是因为，往`channel`中写入数据`ch <- 10`，但此时读入数据的还没准备，所以这里写入数据就已经产生死锁。

#### 2. 有缓冲区的`channel`

- 片段1

```go
   // 代码片段2
   func main() {
       ch := make(chan int, 1)
       ch <- 10
       ch <- 10
   }
```

有缓冲区，但`channel`的缓冲区大小只有1，但是写入两个值，且没有读，会产生阻塞。
> 1. 如果`channel`满了，发送者会阻塞
> 2. 如果`channel`空了，接收者会阻塞
> 3. 如果在同一个`goroutine`中，写数据一定要在读数据前
>

## 如何优雅的关闭`channel`

### 情形一：多个接收者和一个发送者

>  在发送者处理完逻辑后，将通道关闭

### 情形二：一个接收者和多个发送者

> 创建一个额外的**信号通道**，用于通知发送者不需要再发送数据了。当该通道不再被任何一个`goroutine`使用时，他将会被垃圾回收，无论是否被关闭。

```go
package main
 
import (
	"log"
	"sync"
)
 
func main() {
 
	cosnt N := 5
	cosnt Max := 60000
	count := 0
 
	dataCh := make(chan int)
	stopCh := make(chan bool)
 
	var wt sync.WaitGroup
	wt.Add(1)
 
	//发送者
	for i := 0; i < N; i++ {
		go func() {
			for {
				select {
				case <-stopCh:
					return
				default:
					count += 1
					dataCh <- count
				}
			}
		}()
	}
 
	//接收者
	go func() {
		defer wt.Done()
		for value := range dataCh {
			if value == Max {
				// 此唯一的接收者同时也是stopCh通道的
				// 唯一发送者。尽管它不能安全地关闭dataCh数
				// 据通道，但它可以安全地关闭stopCh通道。
				close(stopCh)
				return
			}
			log.Println(value)
		}
	}()
 
	wt.Wait()
}
```

### 情形三：多个接收者和多个发送者

引入**中间者**通过关闭额外的信号通道，来通知所有接收者和发送者结束工作。

```go
const Max = 10000
const NumReceivers = 10
const NumSenders = 1000

var wg sync.WaitGroup
var msg string

func main() {
	wg.Add(NumReceivers)

	dataChan := make(chan int)
	stopChan := make(chan bool)
	// 用于告诉中间者需要结束
	toStopChan := make(chan string)

	// 中间调节者
	go func() {
		msg = <-toStopChan
		close(stopChan)
	}()

	// 发送者
	for i := 0; i < NumSenders; i++ {
		go func(id string) {
			for {
				num := rand.Intn(Max)
				if num == 0 {
					select {
					case toStopChan <- "发送者" + id:
					default:
					}
					return
				}

				select {
				case <-stopChan:
					return
				case dataChan <- num:
				}
			}
		}(strconv.Itoa(i))
	}

	// 接收者
	for i := 0; i < NumReceivers; i++ {
		go func(id string) {
			defer wg.Done()
			for {
				select {
				case <-stopChan:
					return
				case num := <-dataChan:
					if num == Max {
						select {
						case toStopChan <- "接收者" + id:
						default:
						}
						return
					}
					log.Print(num)
				}
			}
		}(strconv.Itoa(i))
	}

	wg.Wait()
	log.Print("被" + msg + "终止了")
}
```

