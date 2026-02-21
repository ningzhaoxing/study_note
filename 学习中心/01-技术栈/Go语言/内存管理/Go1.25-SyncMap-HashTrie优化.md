# 学习前置

## 前缀树（Trie）

前缀树是一种树形数据结构，常用于字符串查找。

**示例：存储 "cat", "car", "dog"**
```
        root
       /    \
      c      d
      |      |
      a      o
     / \     |
    t   r    g
```

**特点：**

- 共享公共前缀
- 查找时间 O(m)，m 是 key 长度
- 不需要哈希函数

## 哈希前缀树

哈希值本身就是一个"数字字符串"

```
hash("apple") = 0x3A7F2B1C (二进制: 00111010 01111111 00101011 00011100)
```

我们可以把这个二进制数字当作"路径"，构建一棵树：
- 每次取几位（比如 4 位）作为分支选择
- 逐层向下，直到找到叶子节点

**这就是哈希前缀树。**

# HashTrieMap

对于 Go 1.25 版本之前，Sync.Map 通过 ReadMap 和 DirtyMap 这样的双 map 结构实现**读写分离**，以达到「读操作」几乎无锁，「写操作」加锁，减少锁竞争以提高并发效率。

但实际上，这种方式优化了读写效率，但从锁的颗粒度上讲依然是对 map 加上了全局锁。
而「哈希前缀树」的通过树形结构分支查找的方式，使我们可以将一个「字符串 Key 」转换为 Hash 值后，对 Hash 值的某一段（这一段作为一个节点）进行加锁。

那么，锁的颗粒度就从 **全局锁 -> 节点锁**。

我们可以进行一个形象的比喻：

> 比如，我们要去停车场停车，我们需要找到我们的停车位。
> Sync.Map 就像这个停车场只有一个入口，需要串行进入。
> 而 HashTrieMap 就像这个停车场有多个入口，每个入口是串行的，但是入口与入口之间是并行的。

## 底层源码分析

核心数据结构：

```go
type HashTrieMap[K comparable, V any] struct {

	inited atomic.Uint32
	
	initMu Mutex
	
	root atomic.Pointer[indirect[K, V]]
	
	keyHash hashFunc
	
	valEqual equalFunc
	
	seed uintptr // 

}
```

