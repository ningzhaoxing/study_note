适用于无权图
```go
func bfs(start, n int, g [][]int) []int {  
    dis := make([]int, n)  
    for i := 0; i < len(dis); i++ {  
       dis[i] = -1  
    }  
    q := make([]int, 0)  
    q = append(q, start)  
    dis[start] = 0  
  
    for len(q) > 0 {  
       x := q[0]  
       q = q[1:]  
       for _, y := range g[x] {  
          if dis[y] < 0 {  
             dis[y] = dis[x] + 1  
             q = append(q, y)  
          }  
       }  
    }  
    return dis  
}
```