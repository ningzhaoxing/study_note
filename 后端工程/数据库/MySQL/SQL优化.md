# 插入数据优化
插入数据优化有四个方面
## 1. 批量插入数据
在插入数据时，可以一次插入多条数据
`insert into tb values (1,'tom'),(2,'jerry')`

## 2. 手动提交事物
SQL在每条语句后都进行提交会影响整体性能，可以手动提交减轻电脑负担
```mysql
start transaction; 
insert into tb_test values (1,'TOM'),(2,'JERRY')...; 
insert into tb_test values (3,'TaM'),(4,'JyRRY')...; 
insert into tb_test values (5,'TeM'),(6,'JiRRY')...;
commit;
```

## 3. 主键顺序插入
顺序插入主键会减轻SQL排序操作
```mysql
主键插入:1,2,3,6,9
```
## 4. 大批量插入数据
一次性插入超大量数据，`insert`语句性能太低，因此采用`load`方法插入
```mysql
# 客户端连接时，加上参数 --local-infile
mysql --local-infile -u -root -p
# 设置全局参数local-infile为1，开启从本地加载文件导入数据的开关
set global local_infile = 1;
# 执行load指令，将准备好的数据加载到表结构中
load data local infile '/root/sql1.log' into table tb_user fieldsrerminated by ',' lines terminated by '\n';
```

# 主键优化
在InnoDB存储引擎中，表都是索引组织表，即表数据根据主键顺序组织存放的。
## 主键设计原则
- 尽量降低主键长度
- 插入数据时，按主键顺序插入，选择使用AUTO_INCREMENT自增主键
- 尽量不使用UUID做主键或其它自然主键，如身份证号
- 避免对主键的修改
## 页分裂和页合并
### 页分裂
- 主键顺序插入时
	当一个页剩余的内存已经不足以插入新的数据行时，会创建一个新页，将数据行插入新页中
- 主键乱序插入时
	当一个页的内存不足以插入新数据行时，会创建一个新页，并将原页中的部分数据(通常是50%)移动到新页中，然后插入新数据行
如何避免页分裂？
- 主键顺序插入
- 使用自增主键、批量插入等操作
### 页合并
当删除一行记录时，记录不会直接被物理删除，而是记录被标记为删除，并且它的空间允许被其它记录声明使用。
当页中删除的记录达到 `MERGE_THRESHOLD`(默认为页的50%)，InnoDB会开始寻找最靠近的页(前或后)，判断是否进行两个页的合并。
# order by 优化
本质上是通过索引，对数据进行提前排序，如果需要查询，就直接返回排序结果即可。
当没有对应的升序或降序索引，就会每次查询都需要在排序缓冲区排序。

`order by`排序具有两种排序方式：
- `Using filesort`:
	- 通过表的索引或全表扫描，读取满足条件的数据行，然后在排序缓冲区`sortbuffer`中完成排序
	- 所有不是通过索引直接返回排序结果的排序都叫`FileSort`排序
- `Using index`:
	- 通过有序索引顺序扫描直接返回有序数据
	- 不需要额外排序，操作效率高
```mysql
# 没有索引时，根据age、phone排序，会通过 using filesort排序
explain select id,age,phone form tb_user order by age,phone;
# 创建索引,默认按照升序排序
create index idx_user_age_phone_aa on tb_user(age,phone);
# 创建索引升序索引后,根据age,phone升序排序。会通过 using index排序
explain select id,age,phone form tb_user order by age,phone;
# 降序排序。 会通过 using index 排序
explain select id,age,phone form tb_user order by age desc,phone desc; 


# 根据age,phone一个升序一个降序排序。会通过 using filesort排序
explain select id,age,phone form tb_user order by age asc,phone desc; 
# 创建索引,指定为age升序,phone降序
create index idx_user_age_phone_ad on tb_user(age asc,phone desc);
# 根据age,phone一个升序一个降序排序。会通过 using index 排序
explain select id,age,phone form tb_user order by age asc,phone desc;
```

> 注意：如果没有使用覆盖索引，则需要回表查询，会将满足的结果数据放到排序缓冲区排序。

## `order by`优化原则：
- 根据排序字段建立合适的索引
- 多字段排序遵循最左前缀法则
- 尽量使用覆盖索引- 多字段排序, 一个升序一个降序，此时需要注意联合索引在创建时的规则（ASC/DESC）
- 如果不可避免的出现filesort，大数据量排序时，可以适当增大排序缓冲区大小sort_buffer_size(默认256k)

# Group by 优化
借助索引进行优化
```mysql
# 没有索引。会通过 using temporary(临时表) 分组
explain select  profession, count(*) from tb_user group by profession;

# 建立索引
create index idx_user_pro_age_sta on tb_user(profession,age,status);

# 分组查询。 通过index分组
explain select profession,count(*) from tb_user group by profession;
```

遵循最左前缀法则

```mysql
# 不遵循最左前缀法则  会通过 using temporary 分组
explain select age,count(*) from tb_user group by age

# 遵循最左前缀法则
explain select age,count(*) from tb_user where profession = '通信' group by age;
```

# Limit 优化
```mysql
# 当需要获取第900000个数据后的十个数据，就需要完全获取前900000个数据然后丢弃，这会损耗很多时间

# 优化思路
# 通过 select 只获取900000个后十个数据的id
# 然后通过id查询整行数据

explain select * from tb_sku t,(select id from tb_sku order by id limit 900000,10) a where t.id=a.id;
```

# Count 优化
对于`count`操作，不同存储引擎有不同的处理方式：
- MyISAM：磁盘中会存储表的总行数，当执行`count(*)`时直接输出
- InnoDB：需要一行行读取，进行累加
优化思路：
可以使用redis缓存，自己做计数

`count`四种用法：

| count用法   | 含义                                                                                                                                       |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| count(主键) | InnoDB 引擎会遍历整张表，把每一行的 主键id 值都取出来，返回给服务层。 服务层拿到主键后，直接按行进行累加(主键不可能为null)                                                                   |
| count(字段) | 没有not null 约束 : InnoDB 引擎会遍历整张表把每一行的字段值都取出 来，返回给服务层，服务层判断是否为null，不为null，计数累加。 有not null 约束：InnoDB 引擎会遍历整张表把每一行的字段值都取出来，返 回给服务层，直接按行进行累加。 |
| count(1)  | InnoDB 引擎遍历整张表，但不取值。服务层对于返回的每一行，放一个数字“1” 进去，直接按行进行累加。                                                                                    |
| count(*)  | InnoDB引擎并不会把全部字段取出来，而是专门做了优化，不取值，服务层直接按行进行累加。                                                                                            |

> 注意：`count(*)`性能最高，`count(1)`的速度基本接近。

# Update 优化
InnoDB的行锁时针对索引加的锁，不是针对记录加的锁。
并且该索引不能失效，否则会从行锁升级为表锁。

```mysql
# update 操作尽量修改带有索引的字段，这样锁就会变为行锁，提高并发性
# 如果 update 操作的字段没有索引，就会采用表锁，导致整张表都无法改变，降低并发性能

# 采用行锁
update course set name='javaEE' where id=1;

# 采用表锁
update course set name='SpringBoot' where name='PHP'
```
