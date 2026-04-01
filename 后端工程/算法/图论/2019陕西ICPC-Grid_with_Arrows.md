# Grid with Arrows

![image-20240504204742683](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240504204742683.png)

# 题意

一个总规模为n × m 的矩阵，矩阵上的每个位置有其下一位置的信息，询问是否存在一种解法从某一点出发，使得整个矩阵的每个位置都被访问到，如果越界或者遇到重复访问位置的解法被认为失败。

# 解决思路

求是否存在一种解法是从一点出发，可以遍历到整张图。

- 如果入度为0的结点大于1个

  入度为0的结点必定要小于等于1个。因为当入度为0的结点大于1个，那么将会有大于1个结点是无法一次性遍历到的，结果为"No"

- 如果入度为0的结点小于等于1个
  1. 1个：则把该入度为0的结点作为初始点，dfs进行遍历。如果遍历的结点不合法(越界)或者已经遍历过了(循环)，则失败结果为"No"；当遍历完n*m个结点，则成功结果为"Yes"
  2. 0个：则随机选一个结点作为初始结点，dfs进行遍历。遍历判断与上面相同。

所以我们首先要检查入度为0的结点个数，再进行dfs搜索是否可以一次性遍历完所有结点。和欧拉路径相似。

# 技巧与难点

1. 将矩阵压缩为一维矩阵，方便对结点的访问(存储图、入度数量的存储、vis数组)
2. dfs深度搜素遍历欧拉路径
3. 图的存储：因为每个结点的出度为1或0，所以用a数组的下标代表该结点的坐标，若出度为1，则值代表该结点指向的下一个结点的坐标；若出度为0，则代表非法坐标，指向-1。

# AC代码

```c++
#include <bits/stdc++.h> 
#define ll long long 
using namespace std;
const int maxn=1e5+10;
int n,m,cnt,a[maxn],deg[maxn],start,num;
bool vis[maxn];
string s[maxn];
//遍历路径，看是否能遍历整个矩阵
bool dfs(int x,int ans) {
	if (ans == n*m) return 1;
	if (x == -1 || vis[x]) return 0;
	vis[x] = 1;
	return dfs(a[x], ans+1);
}

void solve()
{
	cin>>n>>m;
	for(int i=1;i<=n;i++) cin >> s[i];
	for(int i=1;i<=n;i++) 
		for(int j=1;j<=m;j++) {
			int in,nt=(i-1)*m+j,x=i,y=j;
			cin >> in;
			switch(s[i][j-1]) {
				case 'u':
					nt-=in*m;
					x-=in;
					break;
				case 'd':
					nt+=in*m;
					x+=in;
					break;
				case 'l':
					nt-=in;
					y-=in;
					break;
				default:
					nt+=in;
					y+=in;
					break;
			}
			//判断坐标合法性
			if (x>n || y>m || x<1 || y<1) nt=-1;
			//记录入度
			if (nt != -1) deg[nt]++;
			//将原数组转换为一维数组方便处理
			a[++cnt]=nt;
		}
	for(int i=1;i<=n*m;i++) {
		if (deg[i] == 0) {
			num++;
			start=i;
		}
	}
	if (num > 1) 
		cout<<"No\n";
	else {
		//选择出发点
		if (num<1) {
			start=1;
		}
		dfs(start, 1)?cout << "Yes\n":cout << "No\n";
	}
	//清空相关变量
	memset(vis,0,sizeof(vis));
	memset(deg,0,sizeof(deg));
	start=cnt=num=0;
}
 
int main() {
	ios::sync_with_stdio(0);
	cin.tie(0);
	int T;
	cin>>T;
	while(T--) solve();
	return 0;
}
```

