# [后台]负载均衡（二）能力篇




# 名字服务

## 基础设计
[名字服务考虑的基本设计](http://jm.taobao.org/2018/06/26/%E8%81%8A%E8%81%8A%E5%BE%AE%E6%9C%8D%E5%8A%A1%E7%9A%84%E6%9C%8D%E5%8A%A1%E6%B3%A8%E5%86%8C%E4%B8%8E%E5%8F%91%E7%8E%B0/)

客户端发现：
服务提供者的实例在启动时或者位置信息发生变化时会向服务注册表注册自身，在停止时会向服务注册表注销自身，如果服务提供者的实例发生故障，在一段时间内不发送心跳之后，也会被服务注册表注销。
服务消费者的实例会向服务注册表查询服务提供者的位置信息，然后通过这些位置信息直接向服务提供者发起请求。

服务端发现：
第一步与客户端发现相同。
服务消费者不直接向服务注册表查询，也不直接向服务提供者发起请求，而是将对服务提供者的请求发往一个中央路由器或者负载均衡器，中央路由器或者负载均衡器查询服务注册表获取服务提供者的位置信息，并将请求转发给服务提供者。

这两种模式各有利弊，客户端发现模式的优势是，服务消费者向服务提供者发起请求时比服务端发现模式少了一次网络跳转，劣势是服务消费者需要内置特定的服务发现客户端和服务发现逻辑；
服务端发现模式的优势是服务消费者无需内置特定的服务发现客户端和服务发现逻辑，劣势是多了一次网络跳转，并且需要基础设施环境提供中央路由机制或者负载均衡机制。目前客户端发现模式应用的多一些，因为这种模式的对基础设施环境没有特殊的要求，和基础设施环境也没有过多的耦合性。
主调调用被调时，根据被调的名字从服务注册中心获取服务实例列表，包括节点ip、端口、权重、地理位置等；一般采取分钟级别的定时任务去拉取，本地做缓存，异步更新。

实现方式
1. DNS，传播速度太慢，没法发现端口。SkyDNS解决了这个问题，在k8s里大量使用
2. zookeeper或者etcd，如SmartStack，能保证强一致，但是要做很多开发
3. Eureka。Netflix的java生态里的优秀方案
4. Consul，提供服务配置、服务的内存和磁盘监测等


## 服务注册信息

### IP和端口
一个服务端要接入名字服务，必须要先提供自己的IP和端口信息。
IP的获取方法：
1. 通过遍历网卡的方式去获取，找到第一个不为本地环回地址的 IP 地址。dubbo就是这种方法
2. 指定网卡名interfaceName，来获取IP
3. 直接与服务注册中心建立 socket 连接，然后通过socket.getLocalAddress() 这种方式来获取本机的 IP
端口的获取方法：
一般的RPC服务或者Web服务监听的端口都在配置中写好，可以直接获取上报。

### 扩展设计
除了IP和端口，可能还有一些常用的服务信息需要注册上来，提供更高级的功能：
1.支持TLS：想知道某个 HTTP 服务是否开启了 TLS。
2.权重：对相同服务下的不同节点设置不同的权重，进行流量调度。
3.环境分配：将服务分成预发环境和生产环境，方便进行AB Test功能。
4.机房：不同机房的服务注册时加上机房的标签，以实现同机房优先的路由规则。

## 无损注册/下线
虽然服务注册一般发生在服务的启动阶段，但是细分的话，服务注册应该在服务已经完全启动成功，并准备对外提供服务之后才能进行注册。
1.有些 RPC 框架自身提供了方法来判断服务是否已经启动完成，如 Thrift ，我们可以通过 Server.isServing() 来判断。
2.有一些 RPC 框架本身没有提供服务是否启动完成的方式，这时我们可以通过检测端口是否已经处于监听状态来判断。
3.而对于 HTTP 服务，服务是否启动完毕也可以通过端口是否处于监听状态来判断。
下线也是一样的，可以注册服务下线的回调，或者监听服务下线的信号，或者做健康检查

## 健康检查
客户端主动心跳上报健康：
1. 客户端每隔一定时间主动发送“心跳”的方式来向服务端表明自己的服务状态正常，心跳可以是 TCP 的形式，也可以是 HTTP 的形式。
2. 也可以通过维持客户端和服务端的一个 socket 长连接自己实现一个客户端心跳的方式。
客户端的健康检查只能表明网络可达，不能代表服务可用。服务端的健康检查可以准确获得服务的健康状态：
1. 服务端调用服务发布者某个 HTTP 接口来完成健康检查。
2. 对于没有提供 HTTP 服务的 RPC 应用，服务端调用服务发布者的接口来完成健康检查。
3. 可以通过执行某个脚本的形式来进行综合检查，覆盖多个场景。
服务端检查也有问题，一个是调用服务的方式不通用，需要额外实现，还有就是服务注册中心可能和服务的网络不互通。

## 节点变化通知
当服务有节点退出或新的节点加入时，订阅者如何及时收到通知？经典的push和pull的问题
1. Push 的经典实现有两种，基于 socket 长连接的 notify，典型的实现如 zookeeper；另一种为 HTTP 连接所使用 Long Polling。
但是基于 socket 长连接的 notify 和基于 HTTP 协议的 Long Polling 都会存在notify消息丢失的问题。
2. Pull 的定时轮询也需要支持，要选好查询的间隔时间，在服务性能和业务规模之间权衡
3. 还有一种真push，客户端开启一个 UDP server，服务注册中心通过 UDP 的方式进行数据推送，当然这个也受限于网络的连通性

## 容灾
客户端容灾：
首先，本地内存缓存，当运行时与服务注册中心的连接丢失或服务注册中心完全宕机，仍能正常地调用服务。
然后，本地缓存文件，当应用与服务注册中心发生网络分区或服务注册中心完全宕机后，应用进行了重启操作，内存里没有数据，此时应用可以通过读取本地缓存文件的数据来获取到最后一次订阅到的内容。
最后，本地容灾文件夹。正常的情况下，容灾文件夹内是没有内容的。当服务端完全宕机且长时间不能恢复，同时服务提供者又发生了很大的变更时，运维可以通过在容灾文件夹内手动添加文件的方式来开启本地容灾。此时客户端会忽略原有的本地缓存文件，只从本地容灾文件中读取配置。
服务端容灾：
由于地址服务是无状态的，服务端容灾可以做的很薄，主要有两点：新的服务端加入，地址服务器会更新并和其他地址服务器保持同步；服务端删除，地址服务器能保证快速删除。

# 熔断 

## 熔断器模式
[熔断器模式](https://martinfowler.com/bliki/CircuitBreaker.html)是一种用于故障恢复的设计模式，也常用在负载均衡中。它可以防止一个应用不断地去尝试一个很可能失败的操作，避免服务持续过载。他由几个状态组成：
1. 关闭(Closed)：默认情况下Circuit Breaker是关闭的，此时允许操作执行。Circuit Breaker内部记录着最近失败的次数，如果对应的操作执行失败，次数就会续一次。如果在某个时间段内，失败次数（或者失败比率）达到阈值，Circuit Breaker会转换到开启(Open)状态。
2. 开启(Open)：在此状态下，执行对应的操作将会立即失败并且立即抛出异常。在开启状态中，Circuit Breaker会启用一个超时计时器，设这个计时器的目的是给集群相应的时间来恢复故障。当计时器时间到的时候，Circuit Breaker会转换到半开启(Half-Open)状态。
3. 半开启(Half-Open)：在此状态下，Circuit Breaker 会允许执行一定数量的操作。如果所有操作全部成功，Circuit Breaker就会假定故障已经恢复，它就会转换到关闭状态，并且重置失败次数。如果其中 任意一次 操作失败了，Circuit Breaker就会认为故障仍然存在，所以它会转换到开启状态并再次开启计时器（再给系统一些时间使其从失败中恢复）。

我们可以借鉴此设计模式设计一种负载均衡的熔断策略：
请求失败比例过高熔断：当服务端在上一个时间窗（比如10秒）内，成功的请求量小于最低请求量要求requestVolumeThreshold（默认100个），且成功率小于最低成功率errorThresholdPercentage（比如50%），服务端就会进入隔离状态，熔断器开启。
请求连续失败熔断：当服务端在上一个时间窗（比如10秒）内，连续失败的请求超过连续失败上限bound2（默认10个），服务器进入隔离状态，熔断器开启
熔断隔离时间sleepWindowInMilliseconds：默认隔离30s，支持可配置。

## 熔断器发现-时间窗上报
要想再问题发生的时候熔断，首先要发现问题。我们看看Hystrix的熔断器模型怎么收集上报：
![Hystrix的时间窗](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/lb2_1.png)
Hystrix滑动窗口策略，以秒为单位来统计请求处理情况，上面每个格子代表1秒，格子中的数据就是1秒内各请求的处理结果，称为一个桶。
我们假设每次决策都以最近的十个桶来决定是否熔断，比如失败率超过50%就熔断。这10秒就是一个滑动窗口，每经过一秒，最老的一个桶就会被丢弃，同时增加一个新的桶。
![Hystrix的结构](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/lb2_2.png)

## 熔断器恢复-探针
熔断器在半开状态时，如果用请求来检测服务可用，那么还是会有一些请求会丢失的风险。一种比较好的办法是使用探针来检测服务的可用性。探针一般有TCP、UDP、HTTP几种，还要支持用户自定义探针。
主调需要在配置中指定要用的探针类型和探针的使用顺序，在需要探测时会以这个顺序调用探测插件进行探测；只要有一个探测插件成功，就认为服务已经恢复，停止探测。

比如一个udp探针：
* 探测插件名：udp
* 探测请求包：0x0001
* 期望回包：0x000F
* 超时时间：100ms
* 探测次数：5

# 过载保护

[微信的过载保护](https://mp.weixin.qq.com/s/uv4WkTIPvDCFlvKAEXrT2g)
操作系统里有CPU、内存、网卡、磁盘等各种资源，当程序处理海量请求时很容易使得某一种资源到达处理性能瓶颈，从而使得服务的处理能力迅速下降。一般的后台服务可能会有几个下面的瓶颈：
1. CPU，计算密集型服务
2. 内存，内存消耗型服务
3. CPU LOAD，多线程型服务（进程调度频繁导致CPU空跑）
4. IO，包括磁盘IO（比如随机IO导致cache性能下降，机械臂移动频繁，swap频繁），网络IO、网络连接数多的服务（网络拥塞）
这些瓶颈中的某一个因素打破平衡后，会传播和放大（比如用户不断失败重试），形成滚雪球效应，导致整个系统崩溃。此时就需要我们的负载均衡理论来保障系统的可用性。

## 四大方法

### 轻重分离
轻重分离是一种类似高内聚，低耦合的方法论，用来限制服务崩溃的影响扩大。
按服务的重要性对服务分别隔离部署，避免一些不重要的服务影响要重要的服务。服务的隔离最好能做到物理隔离，包括服务器、带宽、IDC级别的隔离。
1. 按重要性分离：比如微博热点出现时大家都去访问某明星的主页，我们尽量只让个人主页服务挂掉，不要影响其他的资讯、推送服务
2. 按部署分离：电信、联通、教育网、海外用户之间的分离
3. 按快慢分离：下载资源服务和资讯页面服务的分离
4. 按set分离用户：按游戏区服、用户uid的哈希值分离，从逻辑分离到物理隔离

### 及早拒绝
问题解决的阶段越早，成本越低，影响越小的一种思想。
原则：前端保护后端，后端不信任前端。
1. 前后端要交流：后端把自己的负载情况也报告给前端
2. 前端收到后端的负载情况后，要用正确的策略调度后端，后端负载满时不再发起请求
3. 后端接到前端的请求后，如果自己负载很高，要拒绝发来的新请求
这里面有两个关键点：
* 高负载识别 负载能力需要一些具体的指标来识别，比如包量、并发连接数
* 拒绝方法 拒绝的时候要有降级策略，用有损服务和柔性可用来保障体验

### 量力而为
每个服务要先做好自我保护，再考虑对关联系统的保护。
对自己的保护需要做好过载监控要做好告警机制，比如在系统负载达到70%的时候发出预警，在后台负载90%的时候启动过载保护

### 动态调节
结合上面的三个方法，持续监控服务过载状态，形成一个良性的正反馈循环：
业务正常状态-> 过载保护状态 -> 业务灰度恢复 -> 业务正常状态

## LB和过载保护
LB和容灾解决的是大容量业务的平行扩展及可用性问题，在做好容量管理的前提下具备一定的应对突发流量的能力（因为具备一定的资源冗余），但是LB只做到流量的均衡分布处理，却没有实现流量超出系统总体容量时的保护、控制。
WRR仅仅实现了根据运营配置的静态负载均衡策略，当集群中某个节点过载时，不能及时调整负载均衡策略以保护该节点，使得过载节点雪上加霜最终假死，更可怕的是节点假死（或者某节点故障）后，LB会马上摘除该节点，并把该节点的负载分担到其它正常节点上，从而可能造成正常节点的过载，如此循环往复，过载不断扩散，最终使得系统整体雪崩。
我们可以优化一下LB的机制，把过载时多出来的请求直接抛弃掉。但是该机制还未能很好的解决过载的源头问题，即用户失去耐心后的无效请求倍增的滚雪球效应，同时也未能给用户较好的有损体验。
还有一种方法是一损俱损，当整个后台集群不可用时，LB把所有的机器都返回，这样在极端情况下也能保障系统的部分可用性。

## 请求队列和过载保护
实现请求队列的目的是通过非阻塞方式实现异步系统，优化系统架构，从而提升系统性能。
异步系统的问题是在分层系统中，各层次所维护的请求/响应队列与原始请求发起方失去了直接的联系，这就造成队列数据有效性（通常是采用轮询超时的方式处理）无法保障。
当过载发生时，用户不断的刷新请求，这也就意味着此时系统请求队列中大部分访问请求已经无效（用户用新的刷新访问代替了上一次的访问请求），但此时队列中的“无效访问请求“尚未超出设定的超时阀值，后端系统（往往是系统的瓶颈所在）还在按FIFO的原则继续处理，这样的结果是：
1) 系统的宝贵资源都用来处理无效的访问请求，极大的浪费了资源；
2) 用户得不到及时的反馈，不断的刷新访问请求，导致滚雪球效应；
3) 请求的涌入使得瓶颈资源无法处理，LB作出调度使得过载扩散，导致多米诺骨牌效应；
从以上分析我们可知，请求队列机制无法及时剔除无效数据，从而控制雪球的增长，也无法控制过载的扩散，故 有了请求队列，仍然需要丰富的过载保护机制
