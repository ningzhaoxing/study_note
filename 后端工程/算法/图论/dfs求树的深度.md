```java
public static int dfs(int x) {
	vis[x] = true;
	int maxL = 0;
	for (int nxt : graph[x]) {
		maxL = Math.max(maxL, dfs(nxt)+1);
	}
	return maxL;
}
```

