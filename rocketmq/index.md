# [后台]RocketMQ的架构和设计


主要整理文献：
[RocketMQ部署架构和技术架构 - Github](https://github.com/apache/rocketmq/blob/master/docs/cn/design.md)
[RocketMQ关键机制的设计原理 - Github](https://github.com/apache/rocketmq/blob/master/docs/cn/design.md)
[RocketMQ 原理简介 - 淘宝消息中间件项目组](http://gd-rus-public.cn-hangzhou.oss-pub.aliyun-inc.com/attachment/201604/08/20160408165024/RocketMQ_design.pdf)

# 设计理念和部署
## 消息队列需要解决的问题
1. **发布/订阅** 最基础的需求，可以做解耦&聚合，如果用Redis做，不够可靠
2. 支持**优先级队列、延时队列**
3. **顺序消费**，rockmq严格有序
4. 支持**消息过滤**，Producer和consumer共同过滤
5. **持久化** 内存缓存+文件
6. **异常恢复**
broker crash，os crash，掉电 ---保证消息不丢，或者丢失少量数据（依赖刷盘方式是同步还是异步）
磁盘损坏，机器永久损坏  ---通过异步复制，可保证99%的消息不丢
7. **实时性** RocketMQ使用长轮询Pull方式，可保证消息非常实时，消息实时性不低于Push。
8. **At least Once** 和 Exactly Only Once， 至少消费一次且只消费一次
9. broker的**buffer容量问题**。RocketMQ 的内存Buffer持久化在硬盘，抽象成一个无限长度的队列，不管有多少数据进来都能装得下，当然也会定时清理。
10. **回溯消费** 一般是按照时间维度，例如由于 Consumer 系统故障，恢复后需要重新消费 1 小时前的数据，那么 Broker 要提供一种机制，可以按照时间维度来回退消费进度。
RocketMQ 支持按照时间回溯消费，时间维度精确到毫秒，可以向前回溯，也可以向后回溯。
11. **消息堆积** 消息堆积在内存Buffer，一旦超过内存Buffer，可以根据一定的丢弃策略来丢弃消息，对性能影响不大，但是不能堆积太多
消息堆积到持久化存储系统中，例如DB，KV存储，文件记录形式。 当消息不能在内存Cache命中时，要不可避免的访问磁盘，会产生大量读IO，读IO的吞吐量直接决定了消息堆积后的访问能力。
12. **消息重试** 消息重试有两种原因，一种是消息本身处理失败，如编码有问题等，重试永远不会成功。另一部分是处理消息依赖的下游服务暂时不可用，一段时间重试后可以成功。所以可以消极重试，逐步重试增大等待重试间隔。

## RockMQ 模块
<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/rocketmq_architecture_1.png"> </img>

1. **Name Server** ：NameServer是一个非常简单的Topic路由注册中心，其角色类似Dubbo中的zookeeper，支持Broker的动态注册与发现。
(1) 路由管理
Broker管理：NameServer接受Broker集群的注册信息并且保存下来作为路由信息的基本数据。然后提供心跳检测机制，检查Broker是否还存活；
路由信息管理：每个NameServer将保存关于Broker集群的整个路由信息和用于客户端查询的队列信息。然后Producer和Conumser通过NameServer就可以知道整个Broker集群的路由信息，找到对应topic的路由信息，从而进行消息的投递和消费。
(2) 无状态：NameServer通常也是集群的方式部署，各实例间相互不进行信息通讯。它是一个几乎无状态的结点，他们之间互不通信。Broker是向每一台NameServer注册自己的路由信息，所以每一个NameServer实例上面都保存一份完整的路由信息。当某个NameServer因某种原因下线了，Broker仍然可以向其它NameServer同步其路由信息，Producer,Consumer仍然可以动态感知Broker的路由的信息。
(3) 随机选择：客户端连接时，会随机选择。
(4) 长连接：Broker向所有的NameServer结点建立长连接，注册Topic信息。Producer和Consumer也是长连接。

2. **Broker**：处理消息存储，转发等处理的服务器。
(0) 分Group：Broker以group分开，每个group只允许一个master，若干个slave。
(1) 读写分离：只有master才能进行写入操作，slave不允许。
(2) 主从同步：slave从master中同步数据。同步策略取决于master的配置，可以采用同步双写，异步复制两种。
(3) 默认消费：在默认情况下，消费者都从master消费，只有master挂掉或者产生消息堆积了才从slave消费。
Broker有下面几个重要的子模块：
(1) Remoting Module：整个Broker的实体，负责处理来自clients端的请求。
(2) Client Manager：负责管理客户端(Producer/Consumer)和维护Consumer的Topic订阅信息
(3) Store Service：提供方便简单的API接口处理消息存储到物理硬盘和查询功能。
(4) HA Service：高可用服务，提供Master Broker 和 Slave Broker之间的数据同步功能。
(5) Index Service：根据特定的Message key对投递到Broker的消息进行索引服务，以提供消息的快速查询。
3. **Producer**：消息发布的角色，支持分布式集群方式部署。Producer通过MQ的负载均衡模块选择相应的Broker集群队列进行消息投递，投递的过程支持快速失败并且低延迟。和NameServer、master都建立长连接，从NameServer拉取topic信息，给master发送心跳。完全无状态
4. **Consumer**：消息消费的角色，支持分布式集群方式部署。支持以push推，pull拉两种模式对消息进行消费。同时也支持集群方式和广播方式的消费，它提供实时消息订阅机制，可以满足大多数用户的需求。和NameServer、master、slave都建立长连接，从NameServer拉取topic信息，给master、slave发送心跳。主备都可以订阅消息，订阅的对象由broker决定。

## 网络部署特点
1. **NameServer**是一个几乎无状态节点，可集群部署，节点之间无任何信息同步。
2. **Broker**部署相对复杂，Broker分为Master与Slave，一个Master可以对应多个Slave，但是一个Slave只能对应一个Master，Master与Slave 的对应关系通过指定相同的BrokerName，不同的BrokerId 来定义，BrokerId为0表示Master，非0表示Slave。Master也可以部署多个。每个Broker与NameServer集群中的所有节点建立长连接，定时注册Topic信息到所有NameServer。 注意：当前RocketMQ版本在部署架构上支持一Master多Slave，但只有BrokerId=1的从服务器才会参与消息的读负载。
2. **Producer**与NameServer集群中的其中一个节点（随机选择）建立长连接，定期从NameServer获取Topic路由信息，并向提供Topic 服务的Master建立长连接，且定时向Master发送心跳。Producer完全无状态，可集群部署。
3. **Consumer**与NameServer集群中的其中一个节点（随机选择）建立长连接，定期从NameServer获取Topic路由信息，并向提供Topic服务的Master、Slave建立长连接，且定时向Master、Slave发送心跳。Consumer既可以从Master订阅消息，也可以从Slave订阅消息，消费者在向Master拉取消息时，Master服务器会根据拉取偏移量与最大偏移量的距离（判断是否读老消息，产生读I/O），以及从服务器是否可读等因素建议下一次是从Master还是Slave拉取。

## 网络模块的工作流程
1. 启动NameServer，NameServer起来后监听端口，等待Broker、Producer、Consumer连上来，相当于一个路由控制中心。
2. Broker启动，跟所有的NameServer保持长连接，定时发送心跳包。心跳包中包含当前Broker信息(IP+端口等)以及存储所有Topic信息。注册成功后，NameServer集群中就有Topic跟Broker的映射关系。
3. 收发消息前，先创建Topic，创建Topic时需要指定该Topic要存储在哪些Broker上，也可以在发送消息时自动创建Topic。
4. Producer发送消息，启动时先跟NameServer集群中的其中一台建立长连接，并从NameServer中获取当前发送的Topic存在哪些Broker上，轮询从队列列表中选择一个队列，然后与队列所在的Broker建立长连接从而向Broker发消息。
5. Consumer跟Producer类似，跟其中一台NameServer建立长连接，获取当前订阅Topic存在哪些Broker上，然后直接跟Broker建立连接通道，开始消费消息。

## 模块的通信机制
RocketMQ消息队列集群主要包括NameServe、Broker(Master/Slave)、Producer、Consumer4个角色，基本通讯流程如下：
(1) Broker启动后需要完成一次将自己注册至NameServer的操作；随后每隔30s时间定时向NameServer上报Topic路由信息。
(2) 消息生产者Producer作为客户端发送消息时候，需要根据消息的Topic从本地缓存的TopicPublishInfoTable获取路由信息。如果没有则更新路由信息会从NameServer上重新拉取，同时Producer会默认每隔30s向NameServer拉取一次路由信息。
(3) 消息生产者Producer根据2）中获取的路由信息选择一个队列（MessageQueue）进行消息发送；Broker作为消息的接收者接收消息并落盘存储。
(4) 消息消费者Consumer根据2）中获取的路由信息，并再完成客户端的负载均衡后，选择其中的某一个或者某几个消息队列来拉取消息并进行消费。
从上面1）~3）中可以看出在消息生产者, Broker和NameServer之间都会发生通信（这里只说了MQ的部分通信），因此如何设计一个良好的网络通信模块在MQ中至关重要，它将决定RocketMQ集群整体的消息传输能力与最终的性能。

# 消息存储

## 消息存储结构(磁盘)
![File](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/mq_file.png)

(1) **CommitLog**：消息主体以及元数据的存储主体，存储Producer端写入的消息主体内容,消息内容不是定长的。单个文件大小默认1G ，文件名长度为20位，左边补零，剩余为起始偏移量，比如00000000000000000000代表了第一个文件，起始偏移量为0，文件大小为1G=1073741824；当第一个文件写满了，第二个文件为00000000001073741824，起始偏移量为1073741824，以此类推。消息主要是顺序写入日志文件，当文件满了，写入下一个文件；
(2) **ConsumeQueue**：消息消费队列，引入的目的主要是提高消息消费的性能，由于RocketMQ是基于主题topic的订阅模式，消息消费是针对主题进行的，如果要遍历commitlog文件中根据topic检索消息是非常低效的。Consumer即可根据ConsumeQueue来查找待消费的消息。其中，ConsumeQueue（逻辑消费队列）作为消费消息的索引，保存了指定Topic下的队列消息在CommitLog中的起始物理偏移量offset，消息大小size和消息Tag的HashCode值。consumequeue文件可以看成是基于topic的commitlog索引文件，故consumequeue文件夹的组织方式如下：topic/queue/file三层组织结构，具体存储路径为：`$HOME/store/consumequeue/{topic}/{queueId}/{fileName}。同样consumequeue文件采取定长设计，每一个条目共20个字节，分别为8字节的commitlog物理偏移量、4字节的消息长度、8字节tag hashcode，单个文件由30W个条目组成，可以像数组一样随机访问每一个条目，每个ConsumeQueue文件大小约5.72M；
(3) **IndexFile**：索引文件提供了一种可以通过key或时间区间来查询消息的方法。Index文件的存储位置是：$HOME/store/index/{fileName}，文件名fileName是以创建时的时间戳命名的，固定的单个IndexFile文件大小约为400M，一个IndexFile可以保存 2000W个索引，IndexFile的底层存储设计为在文件系统中实现HashMap结构，故rocketmq的索引文件其底层实现为hash索引。（具体的文件设计见下面的**消息查询**）

在上面的RocketMQ的消息存储整体架构图中可以看出，RocketMQ采用的是混合型的存储结构，即为Broker单个实例下所有的队列共用一个日志数据文件（即为CommitLog）来存储。RocketMQ的混合型存储结构(多个Topic的消息实体内容都存储于一个CommitLog中)针对Producer和Consumer分别采用了数据和索引部分相分离的存储结构，Producer发送消息至Broker端，然后Broker端使用同步或者异步的方式对消息刷盘持久化，保存至CommitLog中。只要消息被刷盘持久化至磁盘文件CommitLog中，那么Producer发送的消息就不会丢失。正因为如此，Consumer也就肯定有机会去消费这条消息。当无法拉取到消息后，可以等下一次消息拉取，同时服务端也支持长轮询模式，如果一个消息拉取请求未拉取到消息，Broker允许等待30s的时间，只要这段时间内有新消息到达，将直接返回给消费端。这里，RocketMQ的具体做法是，使用Broker端的后台服务线程—ReputMessageService不停地分发请求并异步构建ConsumeQueue（逻辑消费队列）和IndexFile（索引文件）数据。

## 内存缓存 PageCache
页缓存（PageCache)是OS对文件的缓存，用于加速对文件的读写。一般来说，程序对文件进行顺序读写的速度几乎接近于内存的读写速度，主要原因就是由于OS使用PageCache机制对读写访问操作进行了性能优化，将一部分的内存用作PageCache。对于数据的写入，OS会先写入至Cache内，随后通过异步的方式由pdflush内核线程将Cache内的数据刷盘至物理磁盘上。对于数据的读取，如果一次读取文件时出现未命中PageCache的情况，OS从物理磁盘上访问读取文件的同时，会顺序对其他相邻块的数据文件进行预读取。
在RocketMQ中，ConsumeQueue逻辑消费队列存储的数据较少，并且是顺序读取，在page cache机制的预读取作用下，Consume Queue文件的读性能几乎接近读内存，即使在有消息堆积情况下也不会影响性能。而对于CommitLog消息存储的日志数据文件来说，读取消息内容时候会产生较多的随机访问读取，严重影响性能。如果选择合适的系统IO调度算法，比如设置调度算法为“Deadline”（此时块存储采用SSD的话），随机读的性能也会有所提升。
另外，RocketMQ主要通过MappedByteBuffer对文件进行读写操作。其中，利用了NIO中的FileChannel模型将磁盘上的物理文件直接映射到用户态的内存地址中（这种Mmap的方式减少了传统IO将磁盘文件数据在操作系统内核地址空间的缓冲区和用户应用程序地址空间的缓冲区之间来回进行拷贝的性能开销），将对文件的操作转化为直接对内存地址进行操作，从而极大地提高了文件的读写效率（正因为需要使用内存映射机制，故RocketMQ的文件存储都使用定长结构来存储，方便一次将整个文件映射至内存）。

## 刷盘策略
<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/rocketmq_design_2.png"> </img>

**异步刷盘**：能够充分利用OS的PageCache的优势，只要消息写入PageCache即可将成功的ACK返回给Producer端。消息刷盘采用后台异步线程提交的方式进行，降低了读写延迟，提高了MQ的性能和吞吐量。
**同步刷盘**：与异步刷盘的唯一区别是异步刷盘写完 PAGECACHE 直接返回，而同步刷盘需要等待刷盘完成才返回，同步刷盘流程如下：
(1) 写入PAGECACHE后，线程等待，通知刷盘线程刷盘。
(2) 刷盘线程刷盘后，唤醒前端等待线程，可能是一批线程。
(3) 前端等待线程向用户返回成功。
同步刷盘对MQ消息可靠性来说是一种不错的保障，但是性能上会有较大影响，一般适用于金融业务应用该模式较多。

**异步刷盘的思考**：
在有 RAID 卡，SAS 15000 转磁盘测试顺序写文件，速度可以达到 300M 每秒左右，而线上的网卡一般都为千兆网卡，写磁盘速度明显快于数据网络入口速度，那么是否可以做到写完内存就向用户返回，由后台线程刷盘呢？
(1) 由于磁盘速度大于网卡速度，那么刷盘的进度肯定可以跟上消息的写入速度。
(2) 万一由于此时系统压力过大，可能堆积消息，除了写入 IO，还有读取 IO，万一出现磁盘读取落后情况，会不会导致系统内存溢出，答案是否定的，原因如下：
a) 写入消息到 PAGECACHE 时，如果内存不足，则尝试丢弃干净的 PAGE，腾出内存供新消息使用，策略是 LRU 方式。
b) 如果干净页不足，此时写入 PAGECACHE 会被阻塞，系统尝试刷盘部分数据，大约每次尝试 32 个 PAGE。

## 高并发的队列
<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq_1.png"> </img>
基本的**刷盘流程**：
(1) 所有数据单独存储到一个 Commit Log，完全顺序写，随机读。
(2) 对最终用户展现的队列实际只存储消息在 Commit Log 的位置信息，并且串行方式刷盘。
这样做的**好处**如下：
(1) 队列轻量化，单个队列数据量非常少。
(2) 对磁盘的访问串行化，避免磁盘竟争，不会因为队列增加导致 IOWAIT 增高。
每个方案都有**缺点**，它的缺点如下：
(1) 乱序。写虽然完全是顺序写，但是读却变成了完全的随机读。
(2) 增大开销。读一条消息，会先读 Consume Queue，再读 Commit Log，增加了开销。
(3) 编码复杂。要保证Commit Log 与 Consume Queue 完全的一致，增加了编程的复杂度。
以上**缺点如何克服**：
(1) 随机读，尽可能让读命中 PAGECACHE，减少 IO 读操作，所以内存越大越好。如果系统中堆积的消息过多，
读数据要访问磁盘会不会由于随机读导致系统性能急剧下降，答案是否定的。
a) 访问 PAGECACHE 时，即使只访问 1k 的消息，系统也会提前预读出更多数据，在下次读时，就可能命中内存。
b) 随机访问 Commit Log 磁盘数据，系统 IO 调度算法设置为 NOOP 方式，会在一定程度上将完全的随机读变成顺序跳跃方式，而顺序跳跃方式读较完全的随机读性能会高 5 倍以上。（Noop调度算法也叫作电梯调度算法，它将IO请求放入到一个FIFO队列中，然后逐个执行这些IO请求，当然对于一些在磁盘上连续的IO请求，Noop算法会适当做一些合并。这个调度算法特别适合那些不希望调度器重新组织IO请求顺序的应用。）
另外 4k 的消息在完全随机访问情况下，仍然可以达到 8K 次每秒以上的读性能。
(2) 由于 Consume Queue 存储数据量极少，而且是顺序读，在 PAGECACHE 预读作用下，Consume Queue 的读性能几乎与内存一致，即使堆积情况下。所以可认为 Consume Queue 完全不会阻碍读性能。
(3) Commit Log 中存储了所有的元信息，包含消息体，类似于 Mysql、Oracle 的 redolog，所以只要有 Commit Log 在，Consume Queue 即使数据丢失，仍然可以恢复出来。

## 关于随机读写
全随机写无疑是最慢的写入方式，在logic dump测试中很惊讶的发现，将200M的内存数据随机的写入到100G的磁盘数据里面，竟然要2个小时之多。原因就是虽然只有200M的数据，但实际上却是200万次随机写，根据测试，在2850机器上，这样完全的随机写，r/s 大约在150～350之间，在180机器上，r/s难以达到250，这样计算，难怪需要2～3个小时之久。
如何改进这种单线程随机写慢的问题呢？
一种方法就是尽量将完全随机写变成有序的跳跃随机写。实现方式，可以是简单的在内存中缓存一段时间，然后排序，使得在写盘的时候，不是完全随机的，而是使得磁盘磁头的移动只向一个方向。根据测试，简单的先在内存中排序，竟然直接使得写盘时间缩短到1645秒，磁盘的r/s也因此提升到1000以上。写盘的速度，一下子提高了5倍

## 消息周转的过程
(1)Producer 发送消息，消息从 socket 进入 java 堆。
(2)Producer 发送消息，消息从 java 堆转入 PAGACACHE，物理内存。
(3)Producer 发送消息，由异步线程刷盘，消息从 PAGECACHE 刷入磁盘。
(4)Consumer 拉消息（多数情况），消息直接从 PAGECACHE（数据在物理内存）转入 socket，到达 consumer，不经过 java 堆。这种消费场景最多，线上 96G 物理内存，按照 1K 消息算，可以在物理内存缓存 1 亿条消息。
(5)Consumer 拉消息（少数情况），消息直接从 PAGECACHE（数据在虚拟内存）转入 socket。
(6)Consumer 拉消息（少数情况），由于 Socket 访问了虚拟内存，产生缺页中断，此时会产生磁盘 IO，从磁盘 Load 消息到 PAGECACHE，然后直接从 socket 发出去。

# RockMQ高级特性

## At least Once 和 Exactly Only Once
At least Once 是指每个消息必须投递一次
RocketMQ Consumer 先 pull 消息到本地，消费完成后，才向服务器返回 ack，如果没有消费一定不会 ack 消息，所以 RocketMQ 可以很好的支持此特性。
Exactly Only Once 是指只消费一次，即生产和消费都只能进行一次
在分布式系统环境下，不可避免要产生巨大的开销。所以 RocketMQ 为了追求高性能，并不保证此特性，要求在业务上进行去重，也就是说消费消息要做到幂等性。RocketMQ 虽然不能严格保证不重复，但是正常情况下很少会出现重复发送、消费情况，只有网络异常，Consumer 启停等异常情况下会出现消息重复。

## 顺序消息
一个订单产生了 3 条消息，分别是订单创建，订单付款，订单完成。消费时，要按照这个顺序消费才能有意义。但是同时订单之间是可以并行消费的。所以我们只要保证同一个订单的消息在同一个队列里处理，就可以保证顺序性。
1. 顺序消息
消费消息的顺序要同发送消息的顺序一致，在 RocketMQ 中，主要指的是局部顺序，即一类消息为满足顺序性，必须 Producer 单线程顺序发送，且发送到同一个队列，这样 Consumer 就可以按照 Producer 发送的顺序去消费消息。
2. 普通顺序消息
顺序消息的一种，正常情况下可以保证完全的顺序消息。这种消息需要保证三点：
	* 消息被发送时保持顺序
	* 消息被存储时保持和发送的顺序一致
	* 消息被消费时保持和存储的顺序一致
第一，发送的时候要保持有序，这里rockmq把需要保持顺序的消息哈希到同一个队列（不一定同分区，如图）
第二，落盘的时候有序，msg queue本来就是顺序写
第三，消费的时候有序，如果queue被多个consumer协程消费就会乱序。这里有两种消费模式，一种是consumer msg orderly，在消费队列时会加锁，确保一对一消费。还有一种是consumer msg concurrently，多协程广播消费，就会有问题，所以只能指定单协程。
但是一旦发生通信异常，Broker 重启，由于队列总数发生变化，哈希取模后定位的队列会变化，产生短暂的消息顺序不一致。如果业务能容忍在集群异常情况（如某个 Broker 宕机或者重启）下，消息短暂的乱序，使用普通顺序方式比较合适。
3. 严格顺序消息
顺序消息的一种，无论正常异常情况都能保证顺序，但是牺牲了分布式 Failover 特性，即 Broker 集群中只要有一台机器不可用，则整个集群都不可用，服务可用性大大降低。如果服务器部署为同步双写模式，此缺陷可通过备机自动切换为主避免，不过仍然会存在几分钟的服务不可用。（依赖同步双写，主备自动切换，自动切换功能目前还未实现）
目前已知的应用只有数据库 binlog 同步强依赖严格顺序消息，其他应用绝大部分都可以容忍短暂乱序，推荐使用普通的顺序消息。

## 优先级消息
优先级是指在一个消息队列中，每条消息都有不同的优先级，一般用整数来描述，优先级高的消息先投递。如果要用严格的优先级，则需要按照优先级排序确认消费次序，代价很大。
rocketmq实现的不是严格意义上的优先级，通常将优先级划分为高、中、低，或者再多几个级别。每个优先级可以用不同的 topic 表示，发消息时，指定不同的 topic 来表示优先级，随后优先消费某些topic。这种方式可以解决绝大部分的优先级问题，但是对业务的优先级精确性做了妥协。

## 延迟消息
[RocketMQ源码-RocketMQ延时消息](https://www.cnblogs.com/sunshine-2015/p/9017426.html)
因为按照时间排序的复杂度太高，所以采用了折中的办法，降低延迟消息准确性，分为18个延迟队列（1s, 2s, …, 30min, 1h, 2h）写入
1. 延迟消息正常提交给CommitLog保存
2. 因为是延迟消息，单独写到延时队列专用的topic，这样就不会被马上消费
3. 每一个延时等级对应一个queue，queueId = delayLevel - 1
4. 延时队列调度器轮询查看相应的队列中消息，是否到了要执行的时间
5. 到了执行时间的消息，恢复原来消息的topic和queueId，发给写入普通的消费broker。这样就能正常消费了

## 负载均衡


### 发送消息负载均衡
1. 发送策略：采取轮询的方式，给每个队列依次发送消息。比如有5个队列，可以部署在一台机器或者分别部署在5台机器上，发送消息通过轮询队列的方式发送，每个队列接收平均的消息量。通过增加机器，可以水平扩展队列容量。
2. 退避策略（latencyFaultTolerance）：是指对之前失败的，按一定的时间做退避。例如，如果上次请求的latency超过550Lms，就退避3000Lms；超过1000L，就退避60000L；

### 订阅消息负载均衡
如果有 5 个队列，2 个 consumer，那么第一个 Consumer 消费 3 个队列，第二 consumer 消费 2 个队列。
这样即可达到平均消费的目的，可以水平扩展 Consumer 来提高消费能力。但是 Consumer 数量要小于等于队列数
量，如果 Consumer 超过队列数量，那么多余的 Consumer 将不能消费消息。
如果有 10 个队列，20 个 consumer, 11-20号消费者则不能订阅到消息。
核心设计理念是在一个消息消费队列在同一时间只允许被同一消费组内的一个消费者消费，一个消息消费者能同时消费多个消息队列。一个负载均衡的流程如下：
1. 上报自己：在Consumer启动后，它就会通过定时任务不断地向RocketMQ集群中的所有Broker实例发送心跳包（其中包含了消息消费分组名称、订阅关系集合等信息）。Broker端在收到Consumer的心跳消息后，会将它们都维护在本地缓存变量consumerTable备用。
2. 定时均衡：Consumer中有一个RebalanceService线程，每隔20s执行一次策略。
	(A) 拉取所有queue：获取这个topic的consumer queue集合mqset
	(B) 拉取所有消费者：Consumer使用topic和consumerGroup为参数对broker发起RPC请求，获取broker的consumerTable
	(C) 平均分配：拿到Topic下所有的consumer queue、Consumer Id排序，把queue平均分配给所有的Consumer 。几乎每个consumer都会分到相同数量的queue。
	(D) 改变消费连接：根据新建立的映射关系调整消费者和queue的连接。把分配到的consumer queue集合和正在处理的consumer queue做比对。对于正在处理的但是没有分配到的，移除这些连接；对于分配到没有处理的，连接到这些queue开始消费。其余的不处理。

## 并行消费
单队列并行消费：
单队列并行消费采用滑动窗口方式并行消费，如图所示，3~7 的消息在一个滑动窗口区间，可以有多个线程并行消
费，但是每次提交的 Offset 都是最小 Offset，例如 3 。

## 消息过滤
1. 在 Broker 端进行 Message Tag 比对，先遍历 Consume Queue，如果存储的 Message Tag 与订阅的 Message
Tag 不符合，则跳过，继续比对下一个，符合则传输给 Consumer。注意：Message Tag 是字符串形式，Consume
Queue 中存储的是其对应的 hashcode，比对时也是比对 hashcode。
2. Consumer 收到过滤后的消息后，同样也要执行在 Broker 端的操作，但是比对的是真实的 Message Tag 字
符串，而不是 Hashcode。
为什么过滤要这样做？
1. Hashcode更短。Message Tag 存储 Hashcode，是为了在 Consume Queue 定长方式存储，节约空间。
2. 和Commit Log解耦。过滤过程中不会访问Commit Log数据，可以保证堆积情况下也能高效过滤。
3. 双重保证。即使存在 Hash 冲突，也可以在 Consumer 端进行修正，保证万无一失。

## 消息查询

### A. 按照MessageId查询消息
MessageId的长度总共有16字节，其中包含了消息存储主机地址（IP地址和端口），消息Commit Log offset。
Client端从MessageId中解析出Broker的地址（IP地址和端口）和Commit Log的偏移地址后封装成一个RPC请求后通过Remoting通信层发送（业务请求码：VIEW_MESSAGE_BY_ID）。Broker端走的是QueryMessageProcessor，读取消息的过程用其中的 commitLog offset 和 size 去 commitLog 中找到真正的记录并解析成一个完整的消息返回。

### B. 按照Message Key查询消息
<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/rocketmq_design_13.png"> </img>
Index File由下面几个部分组成：
1. **索引文件头** 存了已用slot个数、已用索引个数、第一个和最后一个消息的落盘时间和在CommitLog的offset
2. **Slot Table** 一个存放指针的哈希表，里面存着指向indexs的地址
3. **Indexs** 索引主体，存放着下面的内容：
	* key hash value: message key的hash值
	* phyOffset: message在CommitLog的物理文件地址, 可以直接查询到该消息(索引的核心机制)
	* timeDiff: message的落盘时间与header里的beginTimestamp的差值(为了节省存储空间，如果直接存message的落盘时间就得8bytes)
	* prevIndex: hash冲突处理的关键之处, 相同hash值上一个消息索引的index
Note: 这个prevIndex是用来解决hash冲突的。如果没有冲突，prevIndex就是0。如果有冲突，slot table的指针会指向比较新的那个indexs的地址，然后把新的indexs的prevIndex写上旧的indexs地址。这样，在遍历的时候，从slot table开始查找，经过一个`key hash slot -> slot value -> curIndex -> prevIndex -> ... -> prevIndex -> 相同的hash value`的链路，最后总会找到相同hash值的key。
Note: 如果在插入Indexs的时候采用append的形式，插入的偏移量：
```文件偏移量=索引文件头长度+Slot Table长度+Indexs个数*单个Indexs大小```

我们看一个通常的插入key的流程：
1. 根据查询的 key 的 hashcode % slotNum 得到具体的槽的位置（slotNum 索引文件slots上限的数目，一般像图中 slotNum=5000000）。
2. 根据 slotValue（slot 位置对应的值）查找到索引项列表的最后一项（slotValue总是指向最新的一个）。
3. 顺着`prevIndex`遍历所有索引项列表，匹配`key hash value`相同的索引项，返回查询时间范围内的结果集（默认一次最大返回的 32 条记录）。

Note: 如果值的`key hash value`值相等但 key 不等，其实这里是检查不出来的。出于性能的考虑冲突的检测放到客户端处理（key 的原始值是存储在消息文件中的，避免对数据文件的解析），客户端比较一次消息体的 key 是否相同。
5. 存储：为了节省空间索引项中存储的时间是时间差值（存储时间-开始时间，开始时间存储在索引文件头中），整个索引文件是定长的，结构也是固定的。索引文件存储结构如上图。

## Pull 和 Push

![long polling](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/longpolling.png)

RocketMQ消息订阅有两种模式，一种是Push模式（MQPushConsumer），即MQServer主动向消费端推送；另外一种是Pull模式（MQPullConsumer），即消费端在需要时，主动到MQServer拉取。但在具体实现时，Push和Pull模式都是采用消费端主动拉取的方式，即consumer轮询从broker拉取消息。区别是：
Push方式里，consumer把轮询过程封装了，并注册MessageListener监听器，取到消息后，唤醒MessageListener的consumeMessage()来消费，对用户而言，感觉消息是被推送过来的。
Pull方式里，取消息的过程需要用户自己写，首先通过打算消费的Topic拿到MessageQueue的集合，遍历MessageQueue集合，然后针对每个MessageQueue批量取消息，一次取完后，记录该队列下一次要取的开始offset，直到取完了，再换另一个MessageQueue。
Push的问题：慢消费。如果消费者的速度比发送者的速度慢很多，势必造成消息在broker的堆积。对于消息量有限且到来的速度不均匀的情况，pull模式比较合适。
Pull的问题：消息延迟和忙等。pull需要轮询，就需要设置一个间隔时间，这个间隔太短就会引起无效的忙等，间隔太长会导致消息延迟。
在RocketMQ里，有一种优化的做法——长轮询 Pull ，来平衡推拉模型各自的缺点。基本思路是：
1. consumer尝试拉取，发现broker上没有消息（有消息就直接返回了）
2. broker不直接返回, 而是把连接挂在那里wait
3. producer如果有新的消息到来，把连接notify起来，返回给consumer
4. 如果没有消息到来，超时后释放链接（比如30s）
缺点：但海量的长连接block对系统的开销还是不容小觑

## 事务消息

### 事务的流程
![flow](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/rocketmq_design_10.png)
MQ也提供了对事务的支持，比如操作A可以放在生产者的本地事务里，操作B可以放在消费者里
1. 发送方向 MQ 服务端发送消息
2. broker将消息持久化成功之后，向发送方 ACK 确认消息已经发送成功，此时消息为prepared状态。
3. 发送方开始执行本地事务逻辑。
4. 发送方根据本地事务执行结果向 broker 提交二次确认（Commit 或是 Rollback）
5. broker 收到 Commit 状态则将半消息标记为可投递，订阅方最终将收到该消息；broker 收到 Rollback 状态则删除prepared的消息，订阅方将不会接受该消息。

补充逻辑
5. 在断网或者是应用重启的特殊情况下，上述步骤4提交的二次确认最终未到达 broker，经过固定时间后 broker 将对该消息发起消息回查。 
6. 发送方收到消息回查后，需要检查对应消息的本地事务执行的最终结果。 发送方根据检查得到的本地事务的最终状态再次提交二次确认，broker 仍按照步骤4对prepare的消息进行操作。

### 事务的实现
![design](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/rockmq/rocketmq_design_12.png)
看一下mq具体处理事务消息的办法，如果一个事务消息被写入：
1. 写入的如果是事务消息，对消息的Topic和Queue等属性进行替换写入half topic，同时将原来的Topic和Queue信息存储到消息的属性中
（正因为消息主题被替换，故消息并不会转发到该原主题的消息消费队列，消费者无法感知消息的存在，不会消费，和延时消息一样的套路）
2. 消息commit或者rollback时，会在op topic中存储一份，表示消息的状态，op topic的消息体是到half topic的索引，便于后面回查
如果是rollback，消息直接设置为回滚，就不会再处理了
3. Commit之后，读取出Half消息，并将Topic和Queue替换成真正的目标的Topic和Queue，然后走普通消息的写入流程

Note：如果commit因为网络等原因失败，Broker端对未确定状态的消息（在half topic不在op topic里的）
发起定时回查，将消息发送到对应的Producer，由Producer根据消息来检查本地事务的状态，进而执行Commit或者Rollback。
