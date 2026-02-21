# Go 基础

## 数据类型

数字类型
包括整型（int）、浮点型（浮点型数float32、float64；实数和虚数complex64\complex128）。
其他数字类型

1. byte(类似uint8)
2. rune(类似int32)
3. unit(32或64为位)
4. int(与uint一样大小)
5. uintptr(无符号整型，用于存放一个指针)
## 变量的声明

1. 用var声明变量
    - 指定变量：`var name type`
    - 不指定变量（系统自动根据值判定变量类型）:`var name`
2. 用:=声明变量
    `intVal := 1`相当于`var intVal int``intVal = 1`
*注意：用var声明过的变量，不能再通过:=声明*
3. Go语言支持多变量声明
    - 非全局变量声明：`var name1,name2 = v1, v2`
    `name1, name2 := v1, v2`
    - 全局变量声明：
    ```var{
        name1 type1
        name2 type2
    }```
    ```
## 常量的声明
1. 显示类型定义：`const b string = "abc"`
2. 隐式类型定义：`const b = "abc"`
Go语言同样支持多常量的声明：
`const name1, name2 = v1, v2`
3. iota
    特殊常量，是可以被编译器修改的常量
    用于const出现后，const中每新增一行常量声明，iota计数一次。

  ```const(
   a=iota
   b
   c
  )```
  `a=0;b=1;c=2
  ```
## 条件语句

1. if语句
```go
if 布尔表达式{
    执行语句
}else{
    执行语句
}
```

2. switch语句

```go
switch var{
	case val1:
		...
	case val2:
		...
	default:
		...
}
```

- *注意：Go语言switch语句匹配项后面不需要再加break*；如果需要执行后面的case，可以使用`fallthrough`。

- var1可以是任何类型，val1和val2可以是**同类型**的任意值；或者最终结果为相同类型的表达式。

3. Type Switch

   用于判断interface变量中实际存储的变量类型。

   Type Switch语法

   ```go
   switch x.(type){
       case type:
       	statement(s)
       case type:
       	statement(s)
       /*可以定义任意个数的case*/
       default:
       	statement(s)
   }
   ```

4. select语句

   没看懂，先放着。

## 循环语句

1. for循环（3种表示方法）

   和c的for一样：

- `for init; condition; post{ }`
  和c的while一样：

- `for condition{ }`

  和c的for(;;)一样：

- `for{ }`

2. for循环的range格式（对slice、map、数组、字符串等进行迭代）

```
for key, value := range oldMap{
	newMap[key] = value
}
//代码种的key和value可以省略
//若只想读取key
for key := range oldMap
//或者
for key,_ := range oldMap
//若只想读取value
for _,value := range oldMap
```

## 函数

1. 函数的定义

```
func function_name(参数列表) 函数返回类型 {
	函数体
}
```

2. Go语言允许函数有多个返回值

```
func swap(x, y string) (string, string) {
	return y,x;
}

a, b := swap("Bob", "Alice")
```

3. 函数作为实参(实际上是嵌套调用函数)

```
//声明函数变量
getSquareRoot := func(x float64) float64 {
	return math.Sqrt(x)
}
//使用函数
fmt.Println(getSquareRoot(9))
```

4. 闭包（匿名函数）

```
func getSequence() func() int {
	i:=0
	return func() int {
		i+=1
		return i
	}
}
```

5. 函数方法（方法就是包含了接受者的函数；函数可以是命名类型或结构体类型的一个值或一个指针）

```go
func (name type) function_name() [return type] {
	函数体
}
//例如
type Circle struct {
	radius float64
}
func (c Circle) getArea() float64 {
	return 3.14 * c.radius * c.radius
}
```

## 数组

1. 数组的声明

`var arrayName [size]dataType`

2. 初始化数组(5种)

- 默认初始化

  `var numbers [5]int`

- 列表初始化

  `var numbers = [5]int{1,2,3,4,5}`

- `:=`声明和初始化

  `numbers := [5]int{1, 2, 3, 4, 5}`

- 数组长度不确定时，用`...`代替数组长度,也可以省略`...`

  `balance := [...]float32{1000.0, 2.0, 3.4, 7.0, 50.0}`

- 通过下标来初始化

  `balance := [5]float32{1:2.0, 3:7.0}`

  

3. 多维数组的声明

   `var name[size1][size2]...[sizen] type`

   二维数组的初始化

   ```
   a := [3][4]int {
   	{0, 1, 2, 3} ,
   	{4, 5, 6, 7} ,
   	{8, 9, 10, 11},
   }
   //最后一行的逗号可以省略
   ```

## 指针

1. 指针变量的声明与赋值

   `var ip *int`

   `ip = &a`

2. 空指针

   ` if(ptr == nil)//判断ptr 是否时空指针` 

3. 指针数组

   `var ptr [MAX]*int`

   ptr为整型指针数组。其中的每一个元素都是一个地址，指向了一个值。

4. 指向指针的指针

   `var ptr **int`

## 结构体

1. 结构体的定义

```
type struct_type struct {
	menber de
	menber de
	...
	menber de
}
```

2. 结构体的声明

```
var_name := struct_type {val1, val2, ..., valn}
或
var_name := struct_type {key1:val1, key2:val2,...,keyn:valn}
```

3. 结构体成员的访问

   Go语言访问结构体用`.`操作符

   `结构体.成员名`

4. 结构体指针

   `var struct_p *Books`

   `var book1 Books`

   `book1.结构体成员`

## 切片

Go语言切片是对数组的抽象。可以追加元素，使切片的容量增大。

1. 切片的定义、

- 声明一个未指定大小的数组，切片不需要说明长度

  `var id []type`

- 使用`make()`函数来创建切片

```
var slice1 []type = make([]type, len)
或者
slice1 := make([]type, len)
```

- 指定容量

  `make([]T, len, capacity) //其中capacity为可选参数，len表示切片的初始长度`

2. 切片的初始化

- 直接初始化切片

  `s := []int {1, 2, 3} //[]表示切片类型，{1，2，3}初始化值，其中cap=len=3`

- 初始化切片s，是数组arr的引用

  `s := arr[:]`

- 将arr中下标s到e-1下的元素创建为一个新的切片

  `s := arr[s,e]`

- 默认e时，从第一个到d第e个元素

  `s := arr[:e]`

- 默认s时，从第s个到最后一个元素

  `s := arr[s:]`

- 通过`make()`初始化切片

  `s := make([]int, len, cap)`

3. len()和cap()函数

- 可以通过len()方法获取切片长度
- 通过cap() 函数测量切片最长可以达到多少

4. 空切片

   一个切片在未初始化前默认未nil，长度为0

5. 切片截取

   通过上下限[s,e]来截取切片

   `numbers[s,e]`

6. append()和copy()函数

- append()

  ```
  numbers = append(numbers, 1,2,3,4,...) //项切片添加多个元素
  ```

- copy()

  `copy(numbers1,numbers) //拷贝numbers的内容到numbers1`

## Map集合

1. 定义Map

   1. 使用`make()`函数或使用`map`关键字定义Map

      `map_name := make(map[KeyType]ValyeType, initialCapacity)`

      KeyType是键的类型，ValueType是值的类型，initialCapacity是可选参数，指定map的初始容量。

   2. 使用`map`关键字定义Map

   ```
   m := map[string]int {
   	"apple": 1,
   	"banana": 2,
   }
   ```

2. 操作Map

- 获取元素

```
//获取键值对
v1 := m["apple"]
v2, ok := m["pear"] //如果键不存在， ok的值为false，v2的值为该类型的零值
```

- 修改元素

```
//修改键值对
m["apple"]=5
```

- 获取Map的长度

```go
//获取Map的长度
len := len(m)
```

- 遍历Map

```
for k, v := range m {
	fmt.Println("%s, %d\n",k, v)
}
```

- 删除元素

```
delete(m, "banana")
```

## 接口

1. 接口的定义

```go
//定义接口
type interface_name interface {
	md_name1 [return_type]
	md_name2 [return_type]
	...
	md_namen [return_type]
}
//定义结构体
type struct_name struct {
	//variables
}
```

2. 实现接口的方法

```
func (struct_name_variable struct_name) method_name1() [return_type] {
	方法实现
}
...
```

## 错误处理

Go通过内置的错误接口提供了非常简单的错误处理机制

- error接口

```
type error interface {
	Error() string
}
```

- 通过实现error接口来生成错误信息

  函数通常在最后的返回值中返回错误信息。使用errors.New可返回一个错误信息。

```
func Sqrt(f fkoat64) (float64,error) {
	if f < 0 {
		return 0, errors.New("...")
	}
}
```

