```c++
// 初始化并查集
void init(int n)
{
    for(int i = 1; i <= n; i ++) pre[i]=i;
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
```

