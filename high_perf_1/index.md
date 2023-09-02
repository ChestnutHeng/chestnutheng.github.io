# [后台]服务端高性能架构之道（系统和服务篇）




如果你在服务端的工区，常常会听到同学们激烈的讨论，包括能不能扛得住xx流量？能不能P99达到x毫秒？某操作能不能立即生效？某服务CPU飙升了，某服务OOM了，某服务超时率暴涨了？
这些灵魂的质问，其实就是在保障服务端的高并发、高性能、高可用、高一致性等等，是我们服务端同学必备的扎实基本功。

# 克服系统瓶颈

服务端的代码都跑在各种版本的Linux之上，所以高性能的第一步要和操作系统打交道。我们的服务需要通过操作系统进行I/O、CPU、内存等等设备的使用，同时在使用各种系统调用时避免各种资源的开销过大。

## 零拷贝

认识零拷贝之前，我们先要对Linux系统I/O机制有一定的了解。当我们执行一个[write(2)](https://man7.org/linux/man-pages/man2/write.2.html)或者[read(2)](https://man7.org/linux/man-pages/man2/read.2.html)的时候（或者recv和send），什么时候操作系统会执行读写操作？什么时候又最终会落到磁盘上？
以一个简单的echo服务器为例，我们模拟下每天都在发生的请求和回包：

```c
sockfd = socket(...); 					//打开socket
buffer = new buffer(...); 				//创建buffer 
while((clientfd = accept(socketfd...)){	// 接收一个请求
	read(clientfd, buffer, ...);        //从文件内容读到buffer中 
	write(clientfd, buffer, ...);       //将buffer中的内容发送到网络
}	
```

看一下这段代码的拷贝流程（下图）：
1. 数据包到达网卡，网卡进行DMA操作，把网卡寄存器的数据拷贝到内核缓冲区
2. CPU把内核缓冲区的数据拷贝到用户空间的缓冲区
3. 用户空间处理buffer中的数据（此处不处理）
4. CPU把用户空间的缓冲区的数据拷贝到内核缓冲区
5. 网卡进行DMA操作，把内核缓冲区的数据拷贝到网卡寄存器，发送出去

整个过程触发了4次拷贝（2次CPU，2次DMA），2次系统调用（对应4次上下文切换）
（注：DMA(Direct Memory Access)， I/O 设备直接访问内存的一个通道，可以完成数据拷贝，使得CPU 不再参与任何拷贝相关的事情，现在几乎所有的设备都有DMA）

![norm copy](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/zerocopy1.jpg)

### 使用mmap
mmap可以把用户空间的内存地址映射到内核空间，这样对用户空间的数据操作可以反映到内核空间，省去了用户空间的一次拷贝：
1. 应用调用mmap，和内核共享缓冲区（只需一次）
2. 数据包到达网卡，网卡进行DMA操作，把网卡寄存器的数据拷贝到内核缓冲区
3. CPU把接收到的内核缓冲区的数据拷贝到发送的内核缓冲区
4. 网卡进行DMA操作，把内核缓冲区的数据拷贝到网卡寄存器，发送出去

整个过程触发了**3次拷贝**（1次CPU，2次DMA），2次系统调用（对应4次上下文切换）
![norm copy](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/zerocopy2.jpg)

### 使用sendfile/splice
 Linux 内核版本 2.1 中实现了一个函数`sendfile(2)`：
 1. 他把`read(2)`和`write(2)`合二为一，成为一次系统调用，实现了把一个文件读取并写到另一个文件的语义
 2. 系统调用中不再切换回用户态，而是在内核空间中直接把数据拷贝过去（2.4 之后这一步支持了DMA拷贝，实现了CPU零拷贝）

我门看下使用sendfile之后的流程：
 ![norm copy](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/zerocopy3_2.jpg)
整个过程触发了**3次拷贝**（0次CPU，3次DMA），**1次系统调用**（对应2次上下文切换）

 Linux 内核版本 2.6 中实现了一个函数`splice(2)`，类似sendfile，但是接收/发送方必须有一个文件是管道，通过管道的方式连接发送方和接收方的内核缓冲区，不再需要拷贝（0次CPU，2次DMA，1次系统调用）

transferTo（内部调用sendfile）的性能对比：
 ![copy](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/zerocopy_prof.jpeg)
 
### 对于我们的启发

1. 零拷贝能带来显著的性能提升，目前kafka，nginx默认都开启了零拷贝（大文件传输可以提升60%以上）
2. 部分场景对时效性或者拷贝次数有严格的要求时（比如数据库、消息队列的实现），可以考虑用mmap或者直接I/O，配合自己实现的缓存替代操作系统的缓存方案
3. 拷贝很可能是CPU消耗的主要原因，比如业务代码中的大结构体复制，所以我们要谨慎控制复制操作，尽量使用指针或者引用类型


## 无锁

多线程、多协程、多机器、多地部署是我们服务端实现高并发和强容灾的必备解决方案，这些方案都有一个共性，把数据或者过程分而治之。问题在于，几乎所有的并发场景都会涉及到数据竞争，涉及到共享数据的地方就会涉及到锁，协程有锁，线程有锁，多机部署的服务有分布式锁。
服务中的锁会带来很多问题，随着并发数量的加大，会带来更大的上下文切换、用户态切换的开销，出现CPU飙升且都在做一些无用功的现象，也会导致性能快速下降，甚至还不如单线程模型的效率高。除此以外，各种锁还会带来很高的复杂度，和并发的复杂度相叠加，非常容易出现死锁和各种并发问题。

因此，我们使用锁一定是去解决某种问题而去用的，能无锁就无锁，能轻量级就轻量级。

### 无锁的替代方案

#### 单线程
最简单的方案就是单线程reactor模式，redis、nginx都用了这种方式来避免加锁带来的损耗和复杂性，适用于功能简单的场景。
![redis ](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/redissingle.png)
如图，redis的单线程模型有这么几个部分：
1. 通过I/O多路复用组件来接收请求
2. 把请求解析为任务放入一个串行的任务队列（队列是无锁的）
3. 事件分派器分发事件，若干个处理/回复/应答的事件处理器会处理

如果把事件分派器设计成多消费者模型呢？这时候队列就要加锁了

####  乐观锁

CAS机制：
三个变量：进行比较的原值A，需要读写的内存位置V，拟写入的新值B
```go
func CompareAndSwapInt64(addr *int64, old, new int64) (swapped bool) 
```

如果内存位置V的值与预期原值A相匹配，那么处理器会自动将该位置值更新为新值B。否则处理器不做任何操作。
需要注意的是，CAS失败的时候需要重试，相当于在用户态自旋，所以在频繁写入的场景CAS并不适合，会有较高的性能损耗


**例子1**：数据库乐观锁
1. 取出记录时，获取当前version
2. 更新时，带上这个version并校验，version不相等则失败，version相等则更新业务字段并给version+1
`update table set name = 'Aron', version = version + 1 where id = #{id} and version = #{version};`

**例子2**：netpoll的轻量级锁，是朴素的if锁的加强版

```go
// 有bug的轻量级锁
if locker == 0 {
    locker = 1
    do somthing...
}

// netpoll的轻量级锁
type locker struct {
   // keychain use for lock/unlock/stop operation by who.
   // 0 means unlock, 1 means locked
   keychain [total]int32
}

func (l *locker) lock(k key) (success bool) {
   return atomic.CompareAndSwapInt32(&l.keychain[k], 0, 1)
}

func (l *locker) unlock(k key) {
   atomic.StoreInt32(&l.keychain[k], 0)
}

func (l *locker) isUnlock(k key) bool {
   return atomic.LoadInt32(&l.keychain[k]) == 0
}
```


#### 无锁结构
开源社区用CAS、搭建了很多无锁的数据结构，包括无锁链表，无锁跳表，无锁队列，无锁的map，无锁的LRU，ringbuffer等等。
* MemSQL, RocksDB 用Lock Free Skip List做索引
* SQL SERVER用Lock Free B+ Tree做索引
* OceanBase 用了大量的无锁queue，无锁容器（B+tree，slide window，hashmap）

除此之外，还有很多近似无锁的结构，大部分情况下都是不需要加锁的：
* go的sync.Map
* java的新版cocurrent map

我们用一个例子来感受下无锁结构的思维：
```c
// 一个无锁队列的入队操作
void queue_enqueue(Queue *q, gpointer data)
{
    Node *node, *tail, *next;
    node = g_slice_new(Node);
    node->data = data;
    node->next = NULL;
	
	// 实际上就做了两步：
    // tail->next = node
    // q->tail = node
    while (TRUE) {
        tail = q->tail;
        next = tail->next;
        if (tail != q->tail)   // tail被修改，重试
            continue;
        if (next != NULL) {    // next被其他线程增加了新节点，更新tail并重试
            CAS(&q->tail, tail, next);
            continue;
        }
        if (CAS(&tail->next, null, node)   // node被添加到队尾，成功
            break;
    }
    CAS(&q->tail, tail, node);    // 给队尾赋值
}
```

有兴趣可以看看《C++ Concurrency In Action》里面有无锁结构的入门。还有一些论文可以参考
[Yet another implementation of a lock-free circular array queue](https://www.codeproject.com/Articles/153898/Yet-another-implementation-of-a-lock-free-circul)

### 更小的锁粒度

#### 原子操作
很多原子操作是CPU指令集直接支持的，大部分语言都会支持一些原子原语，所以会比加锁要快一些（约10%-20%），比如Go里面的：

```go
// 加减
func AddInt32(addr *int32, delta int32) (new int32){}
func AddUintptr(addr *uintptr, delta uintptr) (new uintptr){}
// CAS
func CompareAndSwapInt64(addr *int64, old, new int64) (swapped bool){}
func CompareAndSwapPointer(addr *unsafe.Pointer, old, new unsafe.Pointer) (swapped bool){}
// Load/Store
func LoadInt64(addr *int64) (val int64){}
func LoadPointer(addr *unsafe.Pointer) (val unsafe.Pointer){}
func StoreInt64(addr *int64, val int64){}
func StorePointer(addr *unsafe.Pointer, val unsafe.Pointer){}
// atomic.Value
var config atomic.Value
config.Store(loadConfig())
```

#### 细粒度锁

以一个场景举例：有一些用户信息放在一个很大的内存hashmap里，大约有100w条数据，会不断有请求对这些用户信息读，偶尔写
设计1：（map + lock）插入/更新/读取的时候对整个hashmap加锁
设计2：（shard map+lock）hashmap按照用户id的区间分为10个子hashmap，各自持有一把读写锁，每次操作只锁一个子hashmap
设计3：（cocurrent map）只有哈希冲突发生的时候才会对某个哈希桶加锁，没发生冲突的时候用CAS插入头结点
设计4：（sync.Map）两份存储，一份只使用原子操作的数据，和一份冗余了只读数据的加锁数据，实现一定程度上的读写分离，使得大多数读操作和更新操作是原子操作，写入新数据才加锁

类似mysql的行锁、页锁、表锁，不同的粒度会带来不同的性能，粒度越大，性能越差，粒度越小，实现越复杂


## 序列化

序列化是服务端经常用到的操作，无论是数据存储还是数据交互，都需要对对象进行序列化或者反序列化之后才可以使用。同时，序列化也带来了很多的性能问题，序列化较多的服务中约有10~20的CPU消耗在序列化上，所以，序列化的选型也非常重要。

### 序列化的类型

1. **语言内置类型**，比如java的 `java.io.Serializable` ，go的`encoding/gob`，python的`pickle` 。这种方法非常方便,可以用很少的额外代码实现内存对象的保存与恢复，且性能非常高。这种方法有几个问题
	* 与特定的编程语言深度绑定，没办法做到通用，其他语言不可读
	* 解码过程会把字符串直接实例化为类，会带来安全问题
	* 数据的版本控制/编解码效率/结构大小往往时候才考虑，不规范
2. **可读的文本类型**，比如json，csv和xml。这些编码是文本格式，所以可以直接阅读，在和外部项目组交流的时候非常直观，容易达成共识。同样的，这些方法也有一些问题：
	* 没有固定数据格式，有很多歧义，xml和csv不能区分字符串和数字, json不能区分整数和浮点数
	* 不支持二进制数据，只能通过base64支持，会增大编码大小
	* 太占地方，不够紧凑
3. **二进制类型**， 比如thrift，protobuf，msgpack。这些编码都需要一个模式定义文档（IDL）,用于约束数据类型和数据的行为。这些方法有一些很好的特性：
	* IDL本身就是很好的理解数据格式的文档，而且容易实现版本控制，确保大家用最新的协议
	* IDL可以用来生成静态代码，这样就可以在编译时进行类型检查，鲁棒性更高
	* IDL中可以写详细的验证规则，比如正则匹配，范围匹配
	* 更紧凑，字段名只有编号


### 性能

#### 字节大小
json编码，81个字节
```json
{
     "userName": "Martin",
     "favoriteNumber": 1337,
     "interests": ["daydreaming", "hacking"]
}
```
thrift IDL：
```thrift
struct Person {
    1: required string       userName,
    2: optional i64          favoriteNumber,
    3: optional list<string> interests
}
```
thrift编码，34字节
 ![marshal1](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/marshal1.jpg)
1. 没有字段名，字段名用编号来表示
2. 字段类型和标签号只占用了开头的1个字节
3. 数据都是采用数据长度+数据内容的表示方式，这样-64~63只用一个字节，-8192~8191只占用一个字节，以此类推


#### 速度和资源损耗
速度 protobuf > thrift > json
资源损耗  protobuf < thrift < json
参考benchmark结果：
https://github.com/smallnest/gosercomp
https://github.com/alecthomas/go_serialization_benchmarks


### 选型

一般会有三种情况会使用数据的编解码：
1. 数据库或者其他需要持久化的时候，会把内存对象编码后落入磁盘
2. RPC和REST API，客户端对请求编码，服务器对请求解码、响应并进行编码，再由客户端解码
3. 使用消息队列等异步消息传递的时候，生产者需要编码，消费者需要解码

我们要考虑几个问题：
1. 可读性：编码是否要求易读？是否有手动编写编码的情况？是否要在日志中简便打印？是否有多个团队需要理解编码方式？
2. 性能：是否有频繁的编码行为？编码的对象是不是很大？
3. 可扩展性：编码是否需要经常修改删除，并向前向后兼容？是否需要支持版本控制？
4. 跨语言支持：客户端是否可能会是不同的语言和操作系统？

举例：
1. 抖音用户的视频点赞消息，每天有上亿条
2. 抖音某业务需要在数据库中存储extra字段，作为配置信息
3. 服务端需要提供一个给前端用来查个人主页详情的RPC接口

除了序列化方式之外呢？
1. 序列化/反序列化非常耗时，且重复率高的对象可以缓存起来
2. 即使是json，也有各种针对json场景的极致优化的开源仓库，有时候并不亚于thrift，所以选择lib库很重要
3. 代码中不要做重复的序列化，业务流程上一个优化远远大于基础库的性能优化

# 结合服务特性

## 池化-预先分配和复用

大家一定都用过很多种池子，线程池、协程池、内存池、对象池、连接池等等，其实都是一类思想，就是预先创造并锁定一批资源，在随后的业务过程中不断复用。就像我们作为工程师，在PM眼里也是一个开发池；预先招好一定人数定好一个方向，组成一个池子，然后不断复用我们去接一个一个需求（类似任务队列），这样减少了招人成本（类似线程/链接/内存创建销毁）。

### 内存池

内存分配的系统调用malloc/new和内存释放的系统调用free/delete，会带来很大的性能损耗，重复分配和释放内存会带来很多的消耗和内存碎片。所以，一些需要手动管理内存的语言（C/C++）发展出了tcmalloc等内存池，自动管理内存的语言或者中间件更是直接内置了内存池的实现，如go，java，memcached等等。

#### Go的内存池
我们以go的内存管理中内存池的部分为例，看看内存池有哪些思路：
[Go内存管理](https://draveness.me/golang/docs/part3-runtime/ch07-memory/golang-memory-allocator/)
[Go内存分配那些事](https://segmentfault.com/a/1190000020338427)

分配者按大小分级：
1. Page：操作系统内页的整数倍，一般Page大小是8KB。
2. Span：一组连续的Page被称为Span（2^n个），内存管理的基本单位。
3. ThreadCache：线程内部的cache，不需要加锁，每种大小的空闲内存块以链表的形式连在一起
4. CentralCache：所有线程共享的缓存，和ThreadCache结构相同，但是需要加锁
5. PageHeap：PageHeap是堆内存的抽象，PageHeap存的也是若干链表，链表保存的是Span，当CentralCache没有内存的时，会从PageHeap取，把1个Span拆成若干内存块，添加到对应大小的链表中，当CentralCache内存多的时候，会放回PageHeap

申请者按大小分级：按大小分为
* 微对象	(0, 16B)
*  小对象	[16B, 32KB]
* 大对象	(32KB, +∞) 

小对象：计算对象大小，对应到span class，存入span的空闲内存中。如果内存不够，像CentralCache申请，如果还不够，向PageHeap申请
大对象：直接向PageHeap申请，如果不够像操作系统申请
![mem](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/gomem.png)

总结：Go内存管理的核心在于分级管理（线程本地、线程共用、堆内存、系统内存逐级申请）和分对象管理（对微对象，小对象，大对象做不同的策略），大而全的完成了语言级内存池的任务

#### Bigcache的内存池

我们在优化内存申请/释放时间的时候，如果是针对有内存管理的语言，其实也是在优化gc效率。下面通过Bigcache看下内存池的另一种思路：

```
// cacheShard可以被认为是一个map的一个分片
type cacheShard struct {
  hashmap     map[uint64]uint32        // key对应的value在entries中的起始位置
  entries     queue.BytesQueue         // 实际是[]byte，新数据来了后copy到尾部
}
```
这里面有几个点：
1. 每个`cacheShard`都是一个map中的一个分片，加锁的时候对分片上读写锁
2. 属性`hashmap`存放的是key对应的值的偏移量，而不是值的指针（避免被gc扫描，性能能快出40倍）
3. `entries`是一个非常大的byte数组，存放了map中所有的元素。新加的元素会被放置在byte数组尾部
4. 删除元素后`entries`里会有很多空洞

#### 对于我们的启发
如果我们在Go里面需要设计一个内存缓存，即便是语言层面给我们提供了兜底的内存池，但是还是需要结合使用场景进行缜密的考虑和设计：
1. 直接用go的map：实现最简单，性能最差
2. 改造go的map：改成shard map+读写锁的方式，实现复杂，性能一般
3. 使用sync.Map：开箱即用，实现简单，但是性能和shard map+读写锁差距不明显
4. 使用bigcache或者groupcache：能兼顾锁粒度、gc等多方面的损耗，性能较高


### 对象池

go提供了语言级对象池`sync.Pool` ，可以将暂时不用的对象缓存起来，待下次需要的时候直接使用，不用再次经过内存分配，复用对象的内存，减轻 GC 的压力，提升系统的性能。一般用于多协程需要重复构建的对象，new的代价非常大的时候，我们会使用对象池做对象级的缓存。
一些使用了对象池的组件：
1.  `fmt`包和`encoding/json`包
2.  开源框架`gin`中的`context`
3.  RPC框架`kitex`，比如里面的`RPCInfo`

以gin为例，看看他是如何复用对象的：

```go
engine.pool.New = func() interface{} {
	return engine.allocateContext()
}

func (engine *Engine) allocateContext() *Context {
	return &Context{engine: engine, KeysMutex: &sync.RWMutex{}}
}

// ServeHTTP conforms to the http.Handler interface.
func (engine *Engine) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	c := engine.pool.Get().(*Context)
	c.writermem.reset(w)    //复用对象要清空
	c.Request = req
	c.reset()
	engine.handleHTTPRequest(c)
	engine.pool.Put(c)
}
```
要点：
1. 放入pool的对象会直接复用，gc很高的时候可以用来减少gc负担，rpc收发包的场景有奇效
2. get到的对象有可能是新的，有可能是老的，要么get之后清空，要么put之前清空
3. 用完后一定要put，有存入才有得对象用

初次之外，redis和java都有常量池、unity中也有用于对物体和动画复用的对象池，这种模式还是比较常见的。

### 连接池

连接池广泛用于解决连接的创建/销毁的成本，现在几乎都默认在可以需要长连接的场景中，包括各种数据库的中间件，rpc的长连接，没有特殊的理由，能用就用。自己实现一个连接池是不推荐的，里面还是有不少细节。
我们以`database/sql`中的连接池为例，看下需要考虑哪些内容：
1. 获取连接
	  * 如果连接池不为空，则直接从池子里面获取连接使用即可
	  * 如果连接池为空，且当前连接数>maxConn，则把任务放入等待队列并设置超时时间。
	  * 如果连接池为空，且当前连接数<maxConn，则新建一个新连接。
2. 释放连接
	  * 如果等待队列有任务，把连接交给等待的任务，并pop出来
	  * 等待队列没任务则放回连接池
3. 连接超时
	  * 连接到达maxLifeTime后，连接close掉
4. 连接有效性检测和保活
	  * 每次使用前检测连接是否被关闭，被关闭则重连
	  * 到达mysql的8小时超时连接后，重连

这里面涉及到三个参数：
*  `SetMaxOpenConns` 最大连接数，默认无穷大
*  `SetMaxIdleConns` 最大空闲连接数，默认为2，就是没任务的时候还会有2个链接空闲等待
*  `SetConnMaxLifeTime` 最大链接生存时间

### 线程池

线程也是一种创建和销毁非常消耗资源的结构。因为线程池大家都很熟悉，就不详细展开，想讨论的是一个优秀的线程池应该优化哪些方向。我们看看GMP在Go 1.0时候的版本，非常朴素，和我们手写的第一版线程池非常类似（G是routine，M是工作线程）：
![redis](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/gmp0.png)
* 单一全局互斥锁和集中状态存储的存在，导致所有 goroutine 相关操作，如创建、重新调度等都要上锁；
* routine 传递问题，M 经常在 M 之间传递可运行的 goroutine，这导致调度延迟增大以及额外的性能损耗（比如M'创建了G'，G'是从G中分出来的，G在M上跑，那最好把G'传给M，不然局部性很差，需要拷贝内存）；
* M之间的切换，会带来很多阻塞线程和取消阻塞的系统调用，开销很大

思考：看到过很多同学的做法，我们在routinue调度器上面套一层协程池，把协程抽象为工作线程，把函数抽象为job，这和第一代GMP是非常相似的，比如：
https://github.com/panjf2000/ants

## 缓存-空间换时间

单独作为一节

## 异步-同时执行

### 业务流程

业务流程的异步，核心就一句话，有严格先后调用关系的服务保持顺序执行，对于能够同步执行的所有服务均采用异步化方式处理。这种方法应该从设计之初就注意，确保一个流程的执行时间等于最长同步流程的耗时：
![async_sale](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/async_sale.jpg)
上图介绍了一个简单的售后换货的流程。从商家操作，web页面调用换货接口开始，我们把换货记为四个独立的过程，每个过程都可以并行执行；所有过程执行结束后，返回发货结果。这样，这个接口的耗时就等于处理时间最长的四个过程之一的耗时。
除此之外，其他重要性较低的业务逻辑，统一放在异步流程里执行。我们会发送订单状态转换消息、发货消息、售后单状态转换消息来通知所有有关的下游，让他们去自行消费。

### 并发模型

#### 共享内存
Java、C++、或者Python，他们线程间通信都是通过共享内存的方式来进行的。非常典型的方式就是，在访问共享数据（例如数组、Map、或者某个结构体或对象）的时候，通过锁来访问，因此，在很多时候，衍生出一种方便操作的数据结构，叫做“线程安全的数据结构”。

#### Actor模型
Actor是erlang采用的并发模型。它的基本思想是，每个Actor都有一个专用的MailBox来接收消息。当一个Actor实例向另外一个Actor发消息的时候，并非直接调用Actor的方法，而是把消息传递到对应的MailBox里，就好像邮递员，并不是把邮件直接送到收信人手里，而是放进每家的邮箱，这样邮递员就可以快速的进行下一项工作。
1. Actor用消息取代了函数调用，天生异步
2. Actor内部无锁，Actor之间物理隔离，互相不影响，只通过消息通信
3. Actor是一个简单的对象，占用资源很少，万量级的Actor没有问题
![actor](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/2021/actor.jpeg)

#### CSP
CSP（communicating sequential processes）并发模型是Go使用的一种并发模型。它提倡“不要以共享内存的方式来通信，相反，要通过通信来共享内存”，在Go中的实现就是routine和channel。
Go用到了 CSP 理论中的 Process/Channel（对应到语言中的 goroutine/channel）：这两个并发原语之间没有从属关系， Process 可以订阅任意个 Channel，Channel 也并不关心是哪个 Process 在利用它进行通信；Process 围绕 Channel 进行读写，形成一套有序阻塞和可预测的并发模型。
```text
Worker1 --> Channel --> Worker2
```

