# 题目

[A-Friendship_2024.5.7 (nowcoder.com)](https://ac.nowcoder.com/acm/contest/82508/A)

![image-20240507210722167](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240507210722167.png)

# 思路分析

求所有符合题意情况的最大值中的最小值；符合题意是指保证图的连通性。那么贪心思路，将所有已存在的关系和可能存在的关系存储起来，利用Kruskal贪心算法每次取权值最小的且不构成回路的边，直到将所有边选完；最后利用并查集判断图的连通性。

需要注意的点：

- 男女因为无法在第二次认识，所以在可能的关系中，若双方为异性则需要跳过。

# 算法复习-Kruskal算法

## 算法步骤

1. 根据边权将所有边进行排序

2. 选择最小边，并同时通过并查集判环

   **并查集如何判环？**

   - 若属于同一集合，则会形成环
   - 若不属于同一集合，则不会形成环

3. 检查终止条件：

   1. 添加的边数等于顶点数-1
   2. 所有边都被考虑过

# AC代码



``` c++
#include <bits/stdc++.h>
using namespace std;
const int MAXN=1e5+10;
int pre[MAXN];

struct edge
{
    int u,v,cost;
    edge(int u,int v,int cost): u(u), v(v), cost(cost){};
};

bool cmp(edge e1, edge e2) {
    return e1.cost < e2.cost;
}

vector<edge> edges;

// 初始化并查集
void init(int n)
{
    for(int i = 1; i <= n; i ++){
        pre[i]=i;
    }
}

//寻找父节点
int find(int x) {
    if (pre[x]==x) return x;
    return pre[x]=find(pre[x]);
}

//合并
void unionsets(int a,int b) {
    a=find(a);
    b=find(b);
    if (a!=b) pre[a]=b;
}


void solve()
{
    int a,b,m,n;
    cin >> a >> b >> n >> m;

    memset(pre,-1,sizeof(pre));
    edges.clear();

    //初始化已经连通的结点
    for(int i = 1; i <= n; i ++){
        int u,v;
        cin >> u >> v;
        edges.push_back(edge(u, v, 0));
    }

    //录入可能连通的结点
    for(int i = 1; i <= m; i ++){
        int u, v, cost;
        cin >> u >> v >> cost;
        //如果为男女则跳过
        if ((u <= a && v > a) || (v <= a && u > a)) continue;
        edges.push_back(edge(u, v, cost));
    }

    // 利用克鲁斯卡尔算法生成最小树
    // 算法步骤：1.对边的权值(代价)进行排序 2.通过并查集判环

    sort(edges.begin(),edges.end(),cmp);

    //初始化并查集
    init(a+b+1);

    int maxn=-1;
    for(int i = 0; i < edges.size(); i ++){
        edge e=edges[i];
        //如果不在同一个集合，即不会形成回路
        if (find(e.u) != find(e.v)) {
            unionsets(e.u, e.v);
            maxn=max(maxn, e.cost);
        }
    }

    //生成树结束后，判断图的连通性。
    //若连通则输出maxn，否则输出-1
    int rt = find(1);
    for(int i = 2; i <= a+b; i ++){
        if (find(i) != rt) {
            cout << -1 << endl;
            return;
        }
    }
    cout << maxn << endl;
}
int main()
{
    ios::sync_with_stdio(false);
    cin.tie(0);
    int t=1;
    cin>>t;
    while(t--) solve();
    return 0;
}
```

