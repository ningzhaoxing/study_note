# 题目

![image-20240506213055371](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240506213055371.png)

# 思路分析

贪心思路。要尽可能占最多的线段，那么我们每次应该选择最边缘的坐标保证不会影响到其他线段。

可以对线段的左端点进行排序，如果左端点相等，优先占领右端点小的线段，所以再给右端点进行排序。

由于当两个线段左端点相等时，我们需要将线段的左端点进行更新(右移一位)，重新进行排序。所以可以通过**优先队列**来维护线段的优先性，来模拟这个过程。

**需要注意的是：**在对线段左端点进行更新的同时，要注意线段的长度，如果线段的长度为0，则无法将左端点右移，则此端点无法被占领。

## AC代码

```c++
#include <bits/stdc++.h>
using namespace std;
const int MAXN=3e5+10;
int n;
struct node
{
    int l,r;
    bool operator < (const node &a) const {
        if (l==a.l) return r>a.r;
        return l>a.l;
    }
}a[MAXN];


void solve()
{
    cin>>n;
    priority_queue<node>q;
    for(int i = 1; i <= n ; i ++){
        cin>>a[i].l>>a[i].r;
        q.push(a[i]);
    }

    int ans=0,tmp=0;
    node nd;
    while(!q.empty()) {
        nd=q.top();q.pop();
        if (nd.l>tmp) {
            ans++;
            tmp=nd.l;
        }else if (nd.l+1<=nd.r) {
            nd.l=tmp+1;
            q.push(nd);
        }
    }
    cout << ans << endl;
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



