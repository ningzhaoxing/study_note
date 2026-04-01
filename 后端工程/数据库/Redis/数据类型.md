# 十大数据类型

## string

常用命令:

| 命令               | 含义         |
| ---------------- | ---------- |
| SET key value    | 设置键的值      |
| GET key          | 获取键的值      |
| INCR key         | 将键的值+1     |
| DECR key         | 将键的值-1     |
| APPEND key value | 将值追加道键的值之后 |
## Hash

> hash 是一个键值对集合，类似于一个小型的NoSQL数据库。
> redis hash 是一个string类型的`field`和`value`的映射表，hash特别适合用于对象存储。
> 每个hash最多可以存储 `2^32 -1`个键值对

常用命令:

| 命令                          | 含义                          |
| --------------------------- | --------------------------- |
| HSET key field value        | 设置哈希表中字段的值                  |
| HGET key field              | 获取哈希表中字段的值                  |
| HGETALL key                 | 获取哈希表中所有字段和值                |
| HDEL key filed              | 删除哈希表中的一个或多个字段              |
| HEXISTS key filed           | 查看哈希表中，指定字段是否存在             |
| HKEYS key                   | 获取哈希表中的所有字段                 |
| HINCRBY key filed increment | 为哈希表中指定字段的整数值加上之增量increment |

## List

> redis list 是简单的字符串列表，按照顺序排序。
> 可以添加元素道列表的头部或者尾部。


常用命令:

| 命令                                    | 含义                                             |
| ------------------------------------- | ---------------------------------------------- |
| LPUSH key value                       | 将值插入到列表头部                                      |
| RPUSH key value                       | 将值插入到列表尾部                                      |
| LPOP key                              | 移出并获取列表的第一个元素                                  |
| RPOP key                              | 移出并获取列表中的最后一个元素                                |
| LRANGE key start stop                 | 获取列表中在指定范围内的元素                                 |
| LINSERT key BEFORE\|AFTER pivot value | 在列表的指定元素前或后插入元素                                |
| BLPOP key timeout                     | 移出并获取列表中的第一个元素，如何列表没有元素，会阻塞队列直到等待超时或发现可弹出元素为止  |
| BRPOP key timeout                     | 移出并获取列表中的最后一个元素，如何列表没有元素，会阻塞队列直到等待超时或发现可弹出元素为止 |

> `BLPOP`和`BRPOP`的返回值
> 如果列表为空，则返回一个`nil`。否则，返回一个含有两个元素的列表，第一个是被弹出元素的`key`，第二个是被弹出元素的`val`

## Set

> redis set 是string类型的无序集合
> 通过哈希表实现，增删改复杂度均为O(1)

常用命令

| 命令                   | 含义              |
| -------------------- | --------------- |
| SADD key value       | 向集合添加一个或多个成员    |
| SREM key value       | 移除集合中的一个或多个成员   |
| SMEMBERS key         | 返回集合中的所有成员      |
| SISMENMBER key value | 判断值是否是集合的成员     |
| SCARD key            | 获取集合的成员数        |
| SPOP key             | 移除并返回集合中的一个随机元素 |


## ZSet

> - redis zset和set一样是string类型元素的集合，且不允许重复的成员。
> - 不同的是，每个元素会关联一个`double`的分数。
> - ZSet通过分数来为集合中的成员进行从小到大排序。
> - ZSet的成员是唯一的，但分数`score`可以重复。

常用命令

| 命令                                 | 含义                         |
| ---------------------------------- | -------------------------- |
| ZADD key score value               | 向有序集合添加一个或多个成员，或更新已存在成员的分数 |
| ZRANGE key start stop [WITHSCORES] | 返回指定范围内的成员                 |
| ZREM key value                     | 移除有序集合中的一个或多个成员            |
| ZSCORE key value                   | 返回有序集合中，成员的分数值             |
| ZCARD key                          | 获取有序集合中的成员数                |
| ZRANK key menber                   | 返回有序集合中指定成员索引              |

# go操作redis

## redis 连接池

初始化连接池，流程如下:
1. 实现初始化一定数量的连接，放入连接池
2. 当go需要操作redis时，直接从redis连接池中取出连接即可
3. 这样可以节省临时获取redis连接的时间，提高效率

核心代码:
```go
var pool *redis.Pool
pool = &redis.Pool{
	Maxldle:8,  // 最大空闲连接数
	MaxActive:0,  // 表示和数据库的最大连接数,0表示无限制
	IdleTimeout:100,  // 最大空闲时间
	Dial:func() (redis.Conn, error) {  // 初始化连接池代码
		retuen redis.Dial("tcp", "localhost:6379")
	},
}
c := pool.Get()
pool.Close() //关闭连接池，一旦关闭，则不能从连接池中取出连接
```
