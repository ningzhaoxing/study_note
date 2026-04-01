# context简介

> - `context`用于在多个`goroutine`中传递上下文信息，且相同的`context`传递给运行在不同`goroutine`中的函数是**并发安全**的。
> - `context`包定义的上下文类型，可以使用`background`、`TODO`创建一个上下文。也可以使用`WithDeadline`、`WithTimeout`、`WithCancel`或`WithValue`创建的修改副本替换它。

因为`context`具有在多个不同`goroutine`中传递上下文信息的性质，所以其常用于并发控制。

下面是对`context`包的详细使用:

# context的使用

## 创建一个context

`context`包提供了两种创建方式:

- `context.Background()`
- `context.TODO()`

> - 前者是上下文的默认值，所有其他的上下文一般都从它衍生而来。
> - 后者是在不确定使用哪种上下文时使用。
> 所以，大多数情况下，都使用`context.Background()`来作为上下文进行传递。

这两种方式创建出来的是根`context`，不具有任何功能。需要根据实际选择`context`包提供的`With`系列函数来解决相应的问题。

下面是`context`包提供的`With`系列函数:

```go
func WithCancel(parent Context) (ctx Context, cancel CancelFunc)
func WithDeadline(parent Context, deadline time.Time) (Context, CancelFunc)
func WithTimeout(parent Context, timeout time.Duration) (Context, CancelFunc)
func WithValue(parent Context, key, val interface{}) Context
```

`context`的衍生具有**树形结构**的特点。

> - 这四个函数所返回的`context`都是基于父级`context`所衍生的。而其返回的`context`依然可以作为父节点，衍生出其他子节点。
> - 如果一个`context`节点被取消，那么从其所衍生出来的`context`子节点都会被取消。


下面是对这些`With`函数的具体使用介绍:

## With系列函数

### WithCancel 取消控制

`WithCancel`的作用是，我们可以通过传递这样的上下文，去控制多个`goroutine`，通过`cancel`函数，在任意时刻让这些`goroutine`取消。

下面是例子:
```go
func main() {  
    ctx, cancel := context.WithCancel(context.Background())  
    go task(ctx)  
    time.Sleep(5 * time.Second)  
    cancel()  
    time.Sleep(time.Second)  
}  
  
func task(ctx context.Context) {  
    for range time.Tick(time.Second) {  
       select {  
       case <-ctx.Done():  
          fmt.Println(ctx.Err())  
          return  
       default:  
          fmt.Println("tasking...")  
       }    
    }
}
```

### 超时控制

一个健壮的程序都是需要设置超时时间的，避免由于服务端长时间响应而消耗资源。所以，一些`web`框架都会采用`WithDeadline`和`WithTimeOut`函数来做超时控制。

 > - `WithDeadline`和`WithTimeout`的作用是一样的，只是传递的时间参数不同而已，它们都会在超过传递的时候后，自动取消`context`。
 > - 需要注意的是，两者也会返回`CancelFunc`的函数，即便是被自动取消，也需要在结束后，手动取消一下，避免消耗不必要的资源。
 
 下面是例子:

```go
func main() {  
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)  
    defer cancel()  
    go task(ctx)  
    time.Sleep(6 * time.Second)  
}  
  
func task(ctx context.Context) {  
    for range time.Tick(time.Second) {  
       select {  
       case <-ctx.Done():  
          fmt.Println(ctx.Err())  
          return  
       default:  
          fmt.Println("tasking...")  
       }    
    }
}
```

### WithValue 携带数据

`WithValue`函数可以返回一个**可携带数据的`context`**，可以用于在多个`goroutine`进行传递。
例如，在日常业务开发中，需要有一个`trace_id`来串联所有日志，那么就可以使用`WithValue`来实现。

> 需要注意的是，通过`WithValue`得到的`context`所携带的数据，是可以传递给从其衍生出来的子节点。简单来说，该`context`的整棵子树都会携带这个数据。

下面是例子:

```go
func main() {  
    ctx := context.WithValue(context.Background(), "key", "value")  
    go task(ctx)  
    time.Sleep(time.Second)  
}  
  
func task(ctx context.Context) {  
    fmt.Println(ctx.Value("key"))  
}
```

使用`WithVlue`的注意事项:
> - 不建议使用`context`携带关键参数，关键参数应该显示的声明出来，而不是隐式处理。`context`最好是携带签名、`trace_id`这类值。
> - 建议`key`采用内置类型。这是为了避免`context`因多个包同时使用`context`而带来冲突。
> - 在获取`value`时，`context`会首先从当前`ctx`中获取，如果没有找到，则会从父级继续查找，直到查找到或者在某个父`context`中返回`nil`。
> - `context`传递的`key``value`键值对是`interface`类型，因此在类型断言时，要考虑程序的健壮性。


# 总结

`context`包在做并发控制上具有相当方便的功能，如在做任务的取消、超时以及传递隐式参数的情境。