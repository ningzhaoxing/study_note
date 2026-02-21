[题目链接]([377. 组合总和 Ⅳ - 力扣（LeetCode）](https://leetcode.cn/problems/combination-sum-iv/))
## 解题思路
可以将问题抽象为：
求到达`target`阶楼梯的方案数。
那么，达到`target`阶楼梯的可能情况为`i-nums[j](j>=0 && j<n)`
## 递归公式
$$
dfs(i) = \sum_{j=0}^n dfs(i-nums[j])
$$
$$
f[0]=1
$$

## AC代码
```go
func combinationSum4(nums []int, target int) int {  
    le := len(nums)  
  
    f := make([]int, target+1)  
  
    f[0] = 1  
  
    for i := 0; i <= target; i++ {  
       for j := 0; j < le; j++ {  
          if i-nums[j] >= 0 {  
             f[i] += f[i-nums[j]]  
          }       }    }  
    return f[target]  
}
```