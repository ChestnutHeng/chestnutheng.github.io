---
title: "[Redis]Redis 应用篇"
date: 2020-09-24T15:57:27+08:00
lastmod: 2020-09-24T15:57:32+08:00
tags: ["Redis", "中间件", "后台"]
categories: ["后台"]
description: "本文介绍了Redis的一些应用，包括分布式锁、消息/延迟队列、hyperloglog、位图、布隆过滤器、限流、地理位置等。"
---



# 分布式锁

## 简单加锁

```
// 思想：利用setnx检测有没有set过，如果set过就表示没有抢到锁
> setnx locker true
OK
// ... do somthing ...
> del locker
```

## 处理set之后进程崩溃的死锁问题

```
// 思想：给锁加上过期时间，即使set之后进程挂掉，也不会死锁
> setnx locker true
OK
> expire locker 5
// ... do somthing ...
> del locker
```

## 处理非原子性问题
setnx之后，expire之前，进程挂了，也会死锁。怎么处理这种情况？
1. 使用redis事务吗？事务里没有if else，要么全部执行，要么全部不执行。需求是setnx成功才执行expire，有依赖关系，没法用事务
2. 使用新的原子命令，如下
```
> set locker true ex5 nx
OK
// ... do somthing ...
> del locker
```

## 处理超时问题

上面的方案设定了超时时间。但是如果少数操作的时间超过了超时时间怎么办？有两个问题：
1. 这个时候其他线程就会抢占到锁，导致资源发生竞争。
2. 如果锁是超时释放的，当前进程处理完操作之后又会释放锁，会把别人的锁释放
我们先来解决问题2。我们可以把locker的value设置为随机数，保证锁只会被当前线程释放。这个操作也要保证原子性，我们用lua脚本实现：
```lua
// del lua
if redis.call("get", key) == tag then
	return redis.call("del", key)
else
	return 0
end
// set java
tag = random.nextint()
if redis.set(key, tag, nx=True, ex=5):
	do_somthing()
	// eval del lua
```

## 获得不了锁的处理

上面介绍了锁的实现，现在我们需要关注获取锁失败的分支。这个时候资源正在被其他过程占用，我们有几个处理办法：
1. 直接抛出异常，比如管理端场景
2. sleep一会重试，但是sleep会阻塞处理线程，并不好
3. 把请求放到一个延时队列，延后处理

# 消息队列

使用list和lpush/rpop，生产者使用lpush推入队列，消费者通过rpop推出队列。因为redis的命令是原子的，所以这里不会有竞争的问题。

我们该什么时候调用pop？
一种常见的方法是pull，定时去消费（pop），比如每隔1s，但是这样消息会有一定的延时
另一种方法是调用b开头的阻塞函数，比如brpop，会阻塞到队列里有消息才会返回。需要注意的是，如果阻塞过久，redis会认为这个网络连接是闲置连接，会断开这些连接，所以客户端里要做好重试

还会有什么问题？
1. 做消费确认ACK比较麻烦，就是不能保证消费者在读取之后，未处理后的宕机问题。导致消息意外丢失。通常需要自己维护一个Pending列表，保证消息的处理确认。
2. 不能广播、分组消费、重复消费

## 多次消费
如果要有多个消费者需要消费同一条消息，list就无法满足。Redis提供了pub/sub模式来解决这一问题。有下面几个操作：
1. SUBSCRIBE，用于订阅信道
2. PUBLISH，向信道发送消息
3. UNSUBSCRIBE，取消订阅

生产者和消费者通过一个队列进行交互。通常会有多个消费者，多个消费者订阅同一个信道，当生产者向信道发布消息时，该信道会立即将消息逐一发布给每个消费者。

优点：
1. 典型的广播模式，一个消息可以发布到多个消费者
2. 多信道订阅，消费者可以同时订阅多个信道，从而接收多类消息
3. 消息即时发送，消息不用等待消费者读取，消费者会自动接收到信道发布的消息

缺点：
1. 消息一旦发布，不能接收。换句话就是发布时若客户端不在线，则消息丢失，不能寻回
2. 不能保证每个消费者接收的时间是一致的
3. 若消费者客户端出现消息积压，到一定程度，会被强制断开，导致消息意外丢失。通常发生在消息的生产远大于消费速度时

可见，Pub/Sub 模式不适合做消息存储，消息积压类的业务，而是擅长处理广播，即时通讯，即时反馈的业务。

## 延时队列

我们实现一个五秒后再处理消息的延时队列。
1. 使用一个zset，score存放到期的时间戳。
2. 然后用一个循环，zrangebyscore查出到期的消息，进行处理，如果没有消息就sleep一小会
3. 如果有消息，用zrem先删除消息，然后再处理，确保只有一个线程处理

```python
def delay(msg):
	msg.id = str(uuid.uuid4()) # 保证 value 值唯一
	value = json.dumps(msg)
	retry_ts = time.time() + 5 # 5 秒后重试
	redis.zadd("delay-queue", retry_ts, value)

def loop():
	while True:
		# 最多取 1 条
		values = redis.zrangebyscore("delay-queue", 0, time.time(), start=0, num=1)
		if not values: 
			time.sleep(1) # 延时队列空的，休息 1s
			continue
		value = values[0] # 拿第一条，也只有一条
		success = redis.zrem("delay-queue", value) # 从消息队列中移除该消息
		if success: # 因为有多进程并发的可能，最终只会有一个进程可以抢到消息
			msg = json.loads(value)
			handle_msg(msg) 
```

## Redis Stream

[Redis对消息队列（MQ，Message Queue）的完善实现](http://www.hellokang.net/redis/stream.html)

# hyperloglog 做基数(UV)统计

对于一些网站统计uv的场景，常见的做法用set是记录下访问过站点的uid，然后返回set的大小。
hyperloglog不存储具体的uid，只是做一个数学估计。

每次进来一个数字，我们看他从低位开始全是0的位有多少个。然后取
maxbit = max(maxbit, now0bit)
我们看看一次添加后发生了什么。比如这个命令：

```cpp
PFADD runoobkey "r"
// 第一步，r的二进制为 01110010，得到最后只有1个0
// now0bit=1，maxbit=max(maxbit, now0bit)=1
```

我们会发现maxbit和总共的基数N有一定的关系。多次测试后，发现N和maxbit的关系大概是：
$$N=2^{maxbit}$$
但是这里可能会有很大的误差。只要有一个数字的now0bit非常大，就会把这个估计拉的很远。所以这里要用分组平均一下。
假设我们分为1024个桶，然后对每个桶分别估计的N取调和平均值，这样误差就会比较小。当取1024个桶时，误差大概在10%以内。此时N和maxbit的关系大概是（n=1024）：
$$ N={\frac{n}{\sum_{i=1}^{n}{\frac{1}{maxbit_{i}}}}}$$
Note: redis把数字分为16384(2^14)个桶，每个桶的maxbit占用6bit，所以占用的空间大概为2^14*6/8=12KB，误差在1%以内。

# 位图和布隆过滤器

## 位图
redis提供了位图操作
1. `setbit key offset value` 设置某个位
2. `getbit key offset` 获取某个位
3. `bitcount key start end` 获取某个区间之间的1的数量
4. `bitop and/or/not/xor key1 key2`

数据结构：这里面的存储结构实际上是一个SDS。在Redis Object里有一个char数组buf，里面存放着位信息，每个char能存8个位。在buf数组的末尾有一个`'\0'`表示位图的结尾。

### setbit/getbit

如何实现：setbit和getbit，都只要通过模余运算得到对应的buf下标和位，就可以拿到对应的值。
我们怎么拿到第n位的值？需要一个第n位为1的掩码 `1<<(7 - n)`

```cpp
// getbit
// 计算出 offset 所指定的位所在的字节 = offset/8
byte = bitoffset >> 3;
// 计算出位所在的位置 = offset%8, bitoffset & 0x7得到后三位（offset%8）
bit = 7 - (bitoffset & 0x7);
bitval = ((uint8_t*)buf)[byte] & (1 << bit);

// 第17位为例子 getbit [key] 17
// 除以8得到第几个byte，byte = 17 >> 3 = 2
// 模8取得字节数，取后三位 17 & 0111 = 01 0001 & 0111 = 0001
// 得到掩码 7 - 0001 = 6，1 << 6 = 0100 0000
// 取出第3个字节的第二位 buf[2] & 0100 0000
```

setbit稍微麻烦一些。在设置位的基础上还要考虑到SDS扩容的情况，如果setbit的offset超过了最大值，那么需要进行扩容并把扩好的空间初始化位0。

### bitcount

计算二进制中1的个数，有几种方法：
1. 查表。预处理好0000 0001 ~ 1111 1111 和其中1的个数的映射，比如0000 0001(1)，后面来了直接查表。我们最高可以建16位的表，仅需百KB左右的内存
2. variable-precision swar算法。
```cpp
i = (i & 0x55555555) + ((i >> 1) & 0x55555555);
i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
i = (i & 0x0F0F0F0F) + ((i >> 4) & 0x0F0F0F0F);
i = (i * (0x01010101) >> 24);
return i
```
Redis中，不足128位的bitmap会查表，有一个8位的表查16次；超过8位的，每次载入128位，然后调用四次SWAR算法计算汉明重量。

## 布隆过滤器

布隆过滤器，是用来判断元素在不在set里的一种方法。上面的hyperloglog只能支持count操作，但是不支持contains操作。要大概地判断元素是否出现过就可以用布隆过滤器，他会用很多个哈希函数对元素进行哈希，把对应的位都设置；查找时也同样哈希，并查看对应的位是否被设置。布隆过滤器有一定的概率会把不存在的元素判定为存在（取决于要求的占用空间，），但是存在的元素一定不会判断错。

1. bf.add
2. bf.exists


# 限流

## 简单限流

每一个行为到来时，都维护一次时间窗口。将时间窗口外的记录全部清理掉，只保留窗口内的记录。zset 集合中只有 score 值非常重要，value 值没有特别的意义，只需要保证它是唯一的就可以了（也可以用uuid，这里用了毫秒）。

``` python
# 业务代码 调用这个接口 , 一分钟内只允许最多回复 5 个帖子
can_reply = is_action_allowed("laoqian", "reply", 60, 5)
if can_reply:
	do_reply()

def is_action_allowed(user_id, action_key, period, max_count):
	key = 'hist:%s:%s' % (user_id, action_key)
	now_ts = int(time.time() * 1000) # 毫秒时间戳
	with client.pipeline() as pipe: # client 是 StrictRedis 实例
		# 记录行为
		pipe.zadd(key, now_ts, now_ts) # value 和 score 都使用毫秒时间戳
		# 移除时间窗口之前的行为记录，剩下的都是时间窗口内的
		pipe.zremrangebyscore(key, 0, now_ts - period * 1000)
		# 获取窗口内的行为数量
		pipe.zcard(key)
		# 设置 zset 过期时间，避免冷用户持续占用内存
		# 过期时间应该等于时间窗口的长度，再多宽限 1s
		pipe.expire(key, period + 1)
	# 批量执行
	_, _, current_count, _ = pipe.execute()
	# 比较数量是否超标
	return current_count <= max_count
```


## 漏桶限流 Redis-Cell

Redis4.0之后提供了更好用的限流组件。
`CL.THROTTLE reply 15 30 60 1`
`CL.THROTTLE key 初始容量 次数 秒数 每次加几个资格`
这条命令限定了回复行为的频率为每 60s 最多 30 次(漏水速率)，漏斗的初始容量为 15，也就是说一开始可以连续回复 15 个帖子，然后才开始受漏水速率的影响。返回值也很有用：
参数1： 0 表示允许，1 表示拒绝
参数2： 漏斗容量 capacity
参数3： 漏斗剩余空间 left_quota
参数4： 如果拒绝了，需要多长时间后再试(漏斗有空间了，单位秒)
参数5： 多长时间后，漏斗完全空出来(left_quota==capacity，单位秒)

我们来看漏桶的一个python实现。每个漏桶
1. 会存一个上一次漏水时间；
2. 每次有请求过来就得到`新增资格数=(计算当前时间-上次漏水时间)*每秒加入资格数`，加到剩余空间上，但要保证剩余空间不大于capacity
3. 剩余空间减掉请求的空间，并更新上次漏水时间

```python
import time
class Funnel(object):
	def __init__(self, capacity, leaking_rate):
		self.capacity = capacity # 漏斗容量
		self.leaking_rate = leaking_rate # 漏嘴流水速率
		self.left_quota = capacity # 漏斗剩余空间
		self.leaking_ts = time.time() # 上一次漏水时间
	def make_space(self):
		now_ts = time.time()
		delta_ts = now_ts - self.leaking_ts # 距离上一次漏水过去了多久
		delta_quota = delta_ts * self.leaking_rate # 又可以腾出不少空间了
		if delta_quota < 1: # 腾的空间太少，那就等下次吧
			return
		self.left_quota += delta_quota # 增加剩余空间
		self.leaking_ts = now_ts # 记录漏水时间
		if self.left_quota > self.capacity: # 剩余空间不得高于容量
			self.left_quota = self.capacity
	def watering(self, quota):
		self.make_space()
		if self.left_quota >= quota: # 判断剩余空间是否足够
			self.left_quota -= quota
			return True
		return False

funnels = {} # 所有的漏斗
# capacity 漏斗容量
# leaking_rate 漏嘴流水速率 quota/s
def is_action_allowed(user_id, action_key, capacity, leaking_rate):
	key = '%s:%s' % (user_id, action_key)
	funnel = funnels.get(key)
	if not funnel:
		funnel = Funnel(capacity, leaking_rate)
		funnels[key] = funnel
	return funnel.watering(1)

for i in range(20):
	print is_action_allowed('laoqian', 'reply', 15, 0.5)
```

# GeoHash 附近的人

业务中经常有判断两个地址是否靠近，寻找某个地址周边的餐厅或超市，类似这样的需求。请求量不大时，我们可以用mysql解决，用一个半径圈出范围：
`select id from positions where x0-r < x < x0+r and y0-r < y < y0+r`
请求量比较大时，我们就要借助redis 3.2以后的GeoHash的指令：
```
// 添加地址
geoadd company 116.48105 39.996794 juejin
geoadd company 116.489033 40.007669 meituan
// 列出地址
geodist company juejin meituan km
// 列出某个地址周围20km的最近三个地址
georadiusbymember company juejin 20 km count 3 asc
// 列出某个经纬度附近的三个地址
georadius company 116.514202 39.905409 20 km withdist count 3 asc
```

实际上，GeoHash内部是一个zset，score是经纬度映射到一维后的一个数字。平面上靠的越近，zset中score值也会越接近。那么要怎么做这种映射呢？数学上有很多二位空间到一维空间的映射，参见
https://halfrost.com/go_spatial_search/
https://www.jianshu.com/p/2fd0cf12e5ba
