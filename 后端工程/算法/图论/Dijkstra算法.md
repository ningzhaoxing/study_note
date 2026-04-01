# 算法原理
是一种求解 **非负权图** 上单源最短路径的算法。

## 过程
1. 将结点分成两个集合：已确定最短路长度的点集（记为*S*集合）的和未确定最短路长度的点集*T*集合）。一开始所有的点都属于集合。
2. 初始化`dis(s)=0`,其它点的`dis`均为正无穷.
3. 重复一下操作:
	1. 从T集合中,选取一个最短路长度最小的结点,移到S集合中.
	2. 对那些刚被加入S集合的结点的所有出边执行松弛操作
4. 直到T集合为空,算法结束
## 时间复杂度
O(n^2)
## 代码实现

```c++
struct Edge{  
    int v,w;  
};  
vector<Edge> edges[200010]; 
int dis[100010], vis[100010];  
  
struct node {  
    int dis, u;  
    bool operator>(const node& a) const {
	    return dis>a.dis;
    }  
};

priority_queue<node, vector<node>, greater<node>> q;  

void dijkstra(int s) {  
    memset(dis, 0x3f, (n+1)* sizeof(int));  
    memset(vis, 0, (n+1)* sizeof(int));  
    dis[s]=0;  
    // 将起始节点加入S集合  
    q.push({0,s});  
    while(!q.empty()) {  
        // 取出距离s最小的结点  
        int u=q.top().u;  
        q.pop();  
        // 如果该结点已访问过，则跳过  
        if (vis[u]) continue;  
        vis[u]=1;  
        // 遍历该结点相邻结点，进行松弛操作  
        for (auto edge : edges[u]) {  
            int v = edge.v, w = edge.w;  
            if (dis[v] > dis[u] + w) {  
                dis[v] = dis[u] + w;  
                q.push({dis[v], v});  
            }   
        }    
    }
}
```

模板：
```c++
struct DIJ {
    using i64 = long long;
    using PII = pair<i64, i64>;
    vector<i64> dis;
    vector<vector<PII>> G;
 
    DIJ() {}
    DIJ(int n) {
        dis.assign(n + 1, 1e18);
        G.resize(n + 1);
    }
 
    void add(int u, int v, int w) {
        G[u].emplace_back(v, w);
    }
 
    void dijkstra(int s) {
        priority_queue<PII> que;
        dis[s] = 0;
        que.push({0, s});
        while (!que.empty()) {
            auto p = que.top();
            que.pop();
            int u = p.second;
            if (dis[u] < p.first) continue;
            for (auto [v, w] : G[u]) {
                if (dis[v] > dis[u] + w) {
                    dis[v] = dis[u] + w;
                    que.push({ -dis[v], v});
                }
            }
        }
    }
};
```