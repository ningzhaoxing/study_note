题目要求：
定义一个`key`为`string`，`value`为`int`类型的`map`，分别表示奖项和对应的权重，请你根据`value`权重设计一个抽奖系统。

我们可以将问题转化为*概率区间映射*问题，通过构建累计权重区间，在区间内生成随机数，选择区间。

具体代码实现：
```go
func WeightedRandomChoice(d map[string]int) (string, error) { 
	// 分别存储区间i对应的key，以及累计权重区间的右端点
    keys := make([]string, 0)  
    sum := make([]int, 0)  
  
    curSum := 0  
    for k, v := range d {  
       curSum += v  
       keys = append(keys, k)  
       sum = append(sum, curSum)  
    }  
    // 在区间中生成随机数
    r := rand.Intn(sum[len(sum)-1])  
    // 通过二分查找随机数掉落在哪个区间
    index := sort.Search(len(sum), func(i int) bool {  
       return sum[i] > r  
    })  
  
    return keys[index], nil  
}  
  
func main() {  
    weights := map[string]int{  
       "Apple":  2,  
       "Banana": 3,  
       "Cherry": 5,  
    }  
  
    result, err := WeightedRandomChoice(weights)  
    if err != nil {  
       fmt.Println("Error:", err)  
       return  
    }  
    fmt.Println("随机选择结果:", result)  
}
```