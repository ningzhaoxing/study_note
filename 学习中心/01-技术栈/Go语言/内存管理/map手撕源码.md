# 模型设计

```plantuml
class hmap {
	count int
	B uint8
	noverflow uint16
	
	flags uint8
	
	hash0 uint32
	
	nevacuate uintptr
}

class mapextra {
}

mapextra -->"1...* overflow" bmap
mapextra -->"1...* oldoverflow" bmap
hmap -->"extra" mapextra

class bmap {
	topbits [8]uint8
	keys [8]keytype
	values [8]valuetype
	overflow uintptr
}

hmap --d>"1...* buckets" bmap
hmap --d>"1...* oldBuckets" bmap
hmap --d>"1...* nextOverflow" bmap

```


# map 源码结构

`runtime/map.go:hmap`
```go
type hmap struct {  
    count     int  // map中元素数量，用于 len 操作
    flags     uint8  // 记录 map 当前状态，是否正在写操作
    B         uint8  // 常规桶的个数：2^B
    noverflow uint8  // 溢出桶的大概个数，为什么是大概？
    hash0     uint32  // hash seed
  
    buckets    unsafe.Pointer  // 桶数组地址
    oldbuckets unsafe.Pointer  // 用于扩容时，旧桶数组的地址
    nevacuate  uintptr  // 记录迁移进度，小于这个数的桶索引是迁移完成的
    extra      *mapextra // 保存 map 的可选数据  
}
```

# key 的定位过程
## 将输入域均匀离散到特定范围

通过 **hash 函数** 和 **取模** ，将输入域压缩存储到桶数组中。

## hash 函数

map 创建时，通过 hash 函数和 hash0（seed），计算出 key 的哈希值，共 64 bit 位（64位操作系统）。
## 取模压缩至桶数组

将哈希值对数组长度（2^B）取模选择出放在哪个桶中，即 hash % (2^B)。计算机进行位运算更加高效，于是等价替换为 hash & (2^B -1)


