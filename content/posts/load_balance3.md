---
title: "[后台]负载均衡 （三）限流篇"
date: 2020-07-27T17:28:37+08:00
lastmod: 2020-07-27T17:28:37+08:00
tags: ["负载均衡", "限流"]
categories: ["后台"]
description: "负载均衡是集群中一个重要的组成部分。这个模块一般集成了名字服务、负载均衡、过载保护、限流等功能。第二部分是针对限流算法和实现的介绍。"
---



# 限流
限流能力是高并发系统中，对于服务提供方的一种保护手段。通过限流功能，我们可以通过控制QPS的方式，以避免被瞬时的流量高峰冲垮，从而保障系统的高可用性。

# 考虑的问题
完成一个限流系统， 我们可以结合场景的需要做下面的考虑
1. 多规则匹配：是否会存在有多重规则的限流？比如有的规则限制每天1000次，有的规则限制每分钟1次？是同时生效还是优先生效某个？
2. 资源类型：能限流什么？QPS，连接数，并发数
3. 全局限流/单机限流：多个服务的实例共享一个全局的流量限额，比如所有机器共享1000QPS。或者单个实例的限流，比如被调限定每台机器不超过1000QPS
4. 限流阈值：单位时间内的最大配额数。是按照每秒种一次，还是按照每分钟60次？
5. 限流处理：客户端如何处理超出限额的请求？超额后直接拒绝，还是超额后进行排队？

抽象出一个方案
接口级别限流：每个接口分配一个appid和key，各自计算各自的配额
多维度限流：支持每秒N次、每分钟N次、每天N次等维度
匀速防刷：假设配置了每分钟60次，依然可能出现第一秒访问了60次用光了配额。匀速防刷可以匀速消耗配额，解决这个问题
多级限流：支持不同的限流规则，并有采用的优先级，采用优先级最高的方案进行限流


# 限流算法

## 固定窗口

固定窗口是在一段时间内可以限制访问次数的方法。
* 将时间划分为多个窗口
* 在每个窗口内每有一次请求就将计数器加一
* 如果计数器超过了限制数量,则本窗口内所有的请求都被丢弃。当时间到达下一个窗口时,计数器重置

这样有一定的限流效果，但是限制住的流量可能是有毛刺的。比如1000次/分钟，可能`00:59`的时候有1000流量，`01:00`的时候也有1000流量，这样这两秒内就有2000流量！
具体实现：用一个变量C标记访问次数，一个事件定时过期，并在过期时把变量C清零：
```go
type FixedWindowCounter struct {
	TimeSlice  time.Duration
	NowCount   int32
	AllowCount int32
}

func (p *FixedWindowCounter) Take() bool {
	once.Do(func() {
		go func() {
			for {
				select {
				case <-time.After(p.TimeSlice):
					atomic.StoreInt32(&p.NowCount, 0)
				}
			}
		}()
	})

	nowCount := atomic.LoadInt32(&p.NowCount)
	if nowCount >= p.AllowCount {
		return false
	}
	if !atomic.CompareAndSwapInt32(&p.NowCount, nowCount, nowCount+1) {
		return false
	}
	return true
}
```

## 滑动窗口
滑动窗口把一个固定窗口划分为多个小区间，以固定的窗口大小在区间上滑动，在一定程度上缓解了固定窗口的毛刺问题（我们假设某一区间qps非常高）。当然性能损耗也比较大。

* 将时间划分为多个区间
* 在每个区间内每有一次请求就将当前区间的计数器加一
* 每经过一个区间的时间,则抛弃窗口中最老的一个区间,并纳入最新的一个区间；
* 如果当前窗口内区间的请求计数总和超过了限制数量,则本窗口内所有的请求都被丢弃

```go
type SlideWindowCounter struct {
	lastWindowCount int32         // 当前区间请求计数
	window          chan int32    // 滑动窗口
	windowSlice     time.Duration // 单区间大小
	nowCount        int32         // 滑动窗口请求计数
	AllowCount      int32         // 滑动窗口内允许的请求数
}

func NewSlideWindowCounter(timeSlice time.Duration,
	windowLen int32, AllowCount int32) *SlideWindowCounter {
	obj := &SlideWindowCounter{
		window:      make(chan int32, windowLen),
		windowSlice: timeSlice / time.Duration(windowLen),
		AllowCount:  AllowCount,
	}
	go obj.sliding()
	return obj
}

func (l *SlideWindowCounter) Take() bool {
	nowCount := atomic.LoadInt32(&l.nowCount)
	if nowCount >= l.AllowCount {
		return false
	}
	if !atomic.CompareAndSwapInt32(&l.nowCount, nowCount, nowCount+1) {
		return false
	}
	// 当前区间的请求数
	atomic.AddInt32(&l.lastWindowCount, 1)
	return true

}

func (l *SlideWindowCounter) sliding() {
	// 窗口没满的时候
	notFull := true
	for notFull {
		select {
		case <-time.After(l.windowSlice):
			// 经过了一个区间的时间，把这个区间的请求数放入窗口，并开始新的区间
			// 等于 l.window <- l.lastWindowCount; l.lastWindowCount = 0
			t := atomic.SwapInt32(&l.lastWindowCount, 0)
			l.window <- t
			if len(l.window) == cap(l.window) {
				notFull = false
			}
		}
	}
	// 窗口满了，开始滑动，每经过一个区间的时间,则抛弃最老的一个区间,并纳入最新的一个区间
	for {
		select {
		case <-time.After(l.windowSlice):
			t := <-l.window
			if t != 0 {
				atomic.AddInt32(&l.nowCount, -t)
			}
			newt := atomic.SwapInt32(&l.lastWindowCount, 0)
			l.window <- newt
		}
	}
}

```

## 漏桶
漏桶的思想其实大家都非常熟悉，就是一个用来缓冲的队列。不过，出队的速度是均匀的，比如每秒只出队一百个，就会有一百个请求发出去。入队的速度没有限制，但是如果队列满了，请求就会被抛弃。
漏洞算法其实是一种流量整形算法，
1. 优点：简单、高效，能恰当拦截容量外的暴力流量。
2. 缺点：无法对流量做频率处理。比如:桶设置的过大（比如每秒一百个），桶容量又不可以设置的过小，否则容易卡死正常用户

```go
type LeakyBucket struct {
	TimeSlice  time.Duration
	AllowCount int32       // 上面的时间段内匀速漏出多少请求
	Bucket     chan func() // 桶
}

func NewLeakyBucket(timeSlice time.Duration, bucketSize int, allowCount int32) *LeakyBucket {
	obj := &LeakyBucket{
		TimeSlice:  timeSlice,
		Bucket:     make(chan func(), bucketSize),
		AllowCount: allowCount,
	}
	go func() {
		// 定时漏出去一个请求
		for {
			select {
			case <-time.After(time.Duration(obj.TimeSlice.Nanoseconds() / int64(obj.AllowCount))):
				task := <-obj.Bucket
				task()
			}
		}
	}()
	return obj
}

func (t *LeakyBucket) Take(task func()) bool {
	select {
	case t.Bucket <- task:
		return true
	default:
	}
	return false
}

```

## 令牌桶
令牌桶的思想是在一个桶中按一定速度加入资格，接受流量的时候消耗资格，没有资格则拒绝请求
1. 每秒会有 r 个令牌放入桶中，或者说，每过 1/r 秒桶中增加一个令牌；
2. 桶中最多存放 b 个令牌，如果桶满了，新放入的令牌会被丢弃；
3. 当一个 n 字节的数据包到达时，消耗 n 个令牌，然后发送该数据包；
4. 如果桶中可用令牌小于 n，则该数据包将被缓存或丢弃。
优缺点:
1. 令牌桶的一个好处是可以方便的改变速度。 一旦需要提高速率，则按需提高放入桶中的令牌的速率。
2. 可以限制总请求大小，还限制平均频率大小；能允许某种程度的突发传输
3. 还是容易导致误判等问题

```go
type TokenBucket struct {
	TimeSlice  time.Duration
	AllowCount int32         // 上面的时间段内生成多少个令牌
	Bucket     chan struct{} // 桶
}

func NewTokenBucket(timeSlice time.Duration, bucketSize int, allowCount int32) *TokenBucket {
	obj := &TokenBucket{
		TimeSlice:  timeSlice,
		Bucket:     make(chan struct{}, bucketSize),
		AllowCount: allowCount,
	}
	go func() {
		// 定时漏出去一个令牌
		for {
			select {
			case <-time.After(time.Duration(obj.TimeSlice.Nanoseconds() / int64(obj.AllowCount))):
				obj.Bucket <- struct{}{}
			}
		}
	}()
	return obj
}

func (t *TokenBucket) Take() bool {
	select {
	case <-t.Bucket:
		return true
	default:
	}
	return false
}
```

## 预热桶
在机器刚刚启动时，可能缓存尚未建立，或者正在初始化，直接打入大量请求可能会导致系统崩溃。所以我们需要一个预热的过程，在请求较少时，缓慢放开请求的量级；在请求正常后恢复正常量级。这里就要用到预热桶。

预热桶其实就是令牌桶的升级版，主要区别在于：我们假设系统的阈值QPS为count，在令牌桶中获取单个令牌的时间是固定的1/count 。而从预热桶中获取单个令牌的时间是随着存量令牌的数量而变化的。

我们假设系统刚启动或者长时间没有收到请求处于冷却状态，这个时候令牌达到令牌数上限（饱和状态）。此时从预热桶中获取令牌的时间要比稳定状态要长。随着令牌的减少，获取单个令牌的时间会慢慢变短，最终到达一个稳定值。
所以我们可以设一个函数，获取单个令牌的时间 = k * 1 / QPS

![预热算法](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/lb3_1.jpg)

假设我们用一条垂直于X轴的竖线表示当前的请求状态，竖线从右向左移动时，表示系统接收到请求（预热中），令牌正在被消耗，假设系统连续接收到 k 个请求，获取对应令牌所需要的时间为[令牌数上限-k, 令牌数上限]的定积分，就是包围的面积。
反过来，竖线从左向右移动时，表示系统正在冷却。


## redis实现的简单限流模型
http://doc.redisfans.com/string/incr.html
多机限流的方案中，使用redis的自增incr和过期expire是一种最简单的方案。假设我们要在1秒内限制100次，那么只需要保留一个一秒过期的key，每次incr并判断incr之后的值是否会超过100。
要注意：
1. incr这个操作本身是原子的，并且每次递增后会返回incr的值
2. incr和expire这两个操作必须当一个事务，否则expire失败了，或者incr和expire之间插入的别的incr都会有问题。我们这里用一个lua脚本在redis中EVAL解决这个问题

```lua
local current
current = redis.call("incr",KEYS[1])
if tonumber(current) == 1 then
    redis.call("expire",KEYS[1],1)
end
```