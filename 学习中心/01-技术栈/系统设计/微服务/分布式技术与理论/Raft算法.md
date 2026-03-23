Raft算法用于保证分布式环境下多节点数据的一致性。
# 原理
Raft算法的主要思想是一个 **选主(leader selection)** 的算法思想，集群种每个节点都有可能成为三种角色。

## 三种角色

- **leader**
	对客户端通信的入口，对内数据同步的发起者，一个集群通常只有一个leader节点。
- **follower**
	非leader节点，被动接收来自leader的数据请求
- **candidate**
	一种临时角色，只存在于leader选举阶段。
	某个节点想要变为leader，就要发起投票请求(vote)，同时自己变为candidate。
	如果选举成功，则变为leader,否则退回为follower。

## 数据提交过程

分为三个阶段，分别是日志复制和多数节点确认、提交日志、应用状态机。
### 日志复制和多数节点确认

leader从客户端接收到写请求后，会将其封装成*日志条目*， 然后通过`AppendEntries`RPC将日志条目并行发送给所有follower节点。

> - leader维护了每个follower的`nextIndex`，表示下一个要发送给改follower日志索引。
> - leader发送从`nextIndex`开始的日志条目给follower。
> - follower收到日志后，会检查‘
> 	- 前一条日志的`Term`和`Index`是否与本地日志匹配(确保连续性)
> 	- 如果匹配，follower将日志追加到本地日志中，并返回成功
> 	- 若不匹配，则返回失败，leader将`nextIndex`递减并重试，直到找到一致的位置

leader需等待 **多数节点(包括自己)** 确认已成功复制该条目，才可进行下一步提交。

### 日志提交(commit)

- **leader节点提交并发送给follower节点**
	leader确认日志已被大多数节点复制后，会更新本地的`commitIndex`，leader在后续的`AppendEntries`RPC(包括心跳)中，将`commitIndex` 发送给follower节点。
- **follower节点提交**
	follower节点收到`commitIndex`后，会将本地日志中所有`Index`<=`commitIndex`的日志提交。

### 应用状态机

已提交的日志条目会被应用到状态机。
- leader和follower会按`Index`顺序执行日志中的命令
- 执行后更新`lastApplied`
leader在应用状态机后，返回结果给客户端。

## 选举过程

### candidate的诞生

初始状态下，所有节点都是follower，每个follower都有一个*timer*，当follower在*timer*结束也没有收到其它节点的*vote*，该follower就会变成candidate，同时向其它节点发送*vote*。

### 选举规则

#### 大致过程

1. 每个follower每轮只有一次投给candidate的机会。
2. follower采用先来先投票策略
3. 超过半数的follower都认为该candidate适合做leader，那么新的leader产生
4. leader通过心跳联系follower。若在follower的timer期间没有收到leader的心跳，则会认为leader宕机，该follower变为candidate，并开始新的一轮选举。

#### 具体选举过程

当candidate节点向自己发送vote后，会根据条件判断是否进行投票(要保证candidate节点的日志条目要新于自己)

##### follower节点投票规则

- **任期检查**
	如果请求中的`Term`小于自身节点的`Term`，则认为其日志条目还没有自身新，拒绝投票。
- **投票承诺**
	每个节点每轮选举，只能投一票(先到先服务)
- **日志新旧对比**
	- Candidate的最后一条日志的`Term`必须>=接收者最后一条日志的`Term`
	- 若`Term`相同，Candidate的日志`Index`必须>=接收者的日志`Index`

# 各消息体

**vote**
> 1. term，自身处于的选举周期
> 2. lastLogIndex，log中最新的index值
> 3. lastLogTerm，log中最近的index是在哪个term中产生的

**每个节点保存的数据信息**
>1. currentTerm，节点处于的term号
> 2. log[ ]，自身的log集合
> 3. commitIndex，log中最后一个被提交的index值

