---
title: "[Linux]谈一谈并行Counting"
date: 2019-07-26T16:49:50+08:00
lastmod: 2019-07-26T18:26:43+08:00
tags: ["Linux", "perfbook"]
categories: ["后台"]
description: "多线程计数依然是处理多线程问题中最基础的操作之一。本文讨论了简单的并行计数、最终一致的并行计数、有上限的并行计数等，视图从这个最简单的问题中学习并行设计的思维。"
---



# 简单的并行计数

在一个简单的多线程计数程序中，我们假设要每个线程去把sum的值多加100m，同时进行。代码如下：
```c
#include <pthread.h>
#include <stdio.h>

#if 0
  #define ADD_P(x) __sync_fetch_and_add((x), 1)
#else
  #define ADD_P(x) (++(*x))
#endif
#define TC 8

void *thgo(void *arg){
  long i = 1000*1000*100;
  while(i-- > 0){ADD_P((long *)arg);};
  pthread_t me = pthread_self();
  printf("thread sum: %ld tid: %lu \n",  *(long *)arg, (unsigned long)me);
}

int main (){
  long sum = 0;
  pthread_t ths[TC];
  // threads
  for (int i = 0; i < TC; ++i){
      pthread_create(&ths[i], NULL, thgo, &sum);
  }
  // main thread
  thgo(&sum);
  // join
  for (int i = 0; i < TC; ++i){
      pthread_join(ths[i], NULL);
  }
  printf("all final sum : %ld\n", sum);
  return 0;
}
```
如果使用一般的计数，会出现严重的数据踩踏问题，导致结果只能取得一定近似的值：
```
$ time ./t
thread sum_added : 96683538 tid: 139864218973952 
thread sum_added : 97597912 tid: 139864210581248 
thread sum_added : 98631229 tid: 139864202188544 
thread sum_added : 106625687 tid: 139864228308800 
all final sum : 106628420

real  0m1.079s
user  0m4.240s
sys	  0m0.000s
```
如果切换原子原语，性能会下降大约八倍（4个线程，在一亿的计数时）。原因是一个变量被4个线程同时竞争，等待的时间大大加长。
```
thread sum_added : 297410188 tid: 140249129400064 
thread sum_added : 323862913 tid: 140249121007360 
thread sum_added : 325497470 tid: 140249137792768 
thread sum_added : 399999202 tid: 140249147127616 
all final sum : 400000000

real 0m8.323s
user 0m31.044s
sys  0m0.000s
```

<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/count1.png" width="400"></img> 

上面是一个使用原子原语时，线程个数和花费时间的关系。随着线程个数的增多，耗时几乎是等比例增长。

# 经常写计数，偶尔读计数

有一个程序每秒钟处理1亿左右的包，我们需要每五秒查看一下总包长。这是一个典型的经常写计数，偶尔读计数的场景。

## 利用数组分开计数

一个经典的方法是，取消上一节中进程们共享的变量，改为每个进程独有的变量，然后再做加和。在下面的代码中，用线程id作为key，线程自己的计数作为value建立了map，各个线程分别写入自己的计数器内，避免了冲突。伪代码如下：
```python
counts = {}
void write_count(){
   tid = pthread_self()
   counts[tid] += 1
}

long read_count(){
    sum = 0
    for tid, c in counts{
        sum += c
    }
    return sum
}
```
这种方法有两个问题：
1. 读操作时，写操作依然在进行，导致结果不准确。读到的不同线程的计数，介于开始读到读结束的窗口之间。
2. 读操作需要聚合所有线程，对读取端而言比较复杂

## 定时刷新，最终一致

为了解决上述的两个问题，我们设计了最终一致的版本：每隔1ms把所有线程的计数加和，存入全局变量中。这样有两个优点：
1. 不一致窗口最多为1ms
2. 读取的时候只要直接读变量就可以了，不用加和

```python
counts = {}
global_count = 0
void write_count(){
   tid = pthread_self()
   counts[tid] += 1
}

long read_count(){
    return global_count
}

// 另起一个线程用来计数
void eventual_count(){
    for {
        sum = 0
        for tid, c in counts{
            sum += c
        }
        global_count = sum
        sleep 1ms
    }
}
```
Note: 线程数量增多时，`eventual_count`可能会越来越不准确。解决这个问题的方法是对线程分组，每组线程让一个`eventual_count`线程来处理计数，这样每个`eventual_count`线程都不会耗费太多的时间处理。必要的时候，可以采用树状的`eventual_count`线程，层级处理。

## 线程私有的__thread

`__thread` gcc提供的关键字，修饰线程私有的变量。修饰后每个线程都有一份该变量实体，且值互不干扰。
`counter` 是每个线程自己的计数器，long类型。
`counterp` 是一个用于存放线程私有变量指针的数组。初始化时，把线程私有变量的地址写进数组。读取时，读取所有指针的值加和。
``` cpp
unsigned long __thread counter = 0;
unsigned long *counterp[NR_THREADS] = { NULL };
unsigned long finalcount = 0;
DEFINE_SPINLOCK(final_mutex);

void inc_count(void)
{
	counter++;
}

unsigned long read_count(void)
{
	int t;
	unsigned long sum;

	spin_lock(&final_mutex);
	sum = finalcount;
	for_each_thread(t)
		if (counterp[t] != NULL)
			sum += *counterp[t];
	spin_unlock(&final_mutex);
	return sum;
}

void count_register_thread(void)
{
	int idx = smp_thread_id();

	spin_lock(&final_mutex);
	counterp[idx] = &counter;
	spin_unlock(&final_mutex);
}
```

# 近似上限的计数

有一些场景需要我们限制计数器的上限，比如限制一个广告曝光的次数。各个线程处理广告的请求，每返回一个广告就给计数器加一，直到总上限到达，就不再返回广告。
比较理想的方案是把任务平均分给每个线程，当他们都达到上限时，认为总上限也已经到达。这样会有几个问题：
1. 每个线程曝光广告的速度不同，可能有点线程很快到达上限了，有的却没有曝光，攒了大量的指标。
2. 这时候如果曝光满了的线程还要继续处理曝光，就要写别的线程的计数器。这会造成昂贵的跨线程通信。

我们可以从上一节的最终一致的方法得到启发，把计数任务分割给各个线程。我们维护一个每个线程的计数器`counter`和每个线程的计数上限`countermax`，以及一个全局的计数器`globalcount`和全局的计数上限`globalcountmax`。
需要注意的是，我们额外引入了一个`globalreserve`。它在数值上是`countermax`的和，用来表示预分配给每个counter的名额，也算在已经用掉的指标里。

这个方法的思想在于，先预分配给每个线程一些指标。如果有一个线程指标都用掉了，那么就收集里面的计数，并给他分配新的指标。直到所有的指标都用尽为止。收集计数的过程，就是`globalize_count`。分配计数的过程，就是`balance_count`。流程如下图

<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/counters_add.png"></img>

<img src="https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/counterflow.png"></img>

这种设计就是一个并行快速路径的例子，这是一种重要的设计模式，适用于下面这种情况：在多数情况没有线程间通信和交互的开销，而偶尔进行的跨进程通信又使用了精心设计的（但是开销仍然很大）全局算法。
在阅读代码之后，还有几点需要思考：

1. 这种计数会有误差。这个方法给每个线程预分配了计数值，但是这些计数值未必有被真实使用。所以最大会有`globalreserve`大小的误差。
2. 在每个线程刚开始计数时，`countermax`被设置为总上限除以线程数的值。此时`globalreserve`和总上限值相等，这意味着最差情况下，如果一直请求某一个特定线程，很快就到达上限了。
3. 我们设置了`MAX_COUNTERMAX`来缓解第二点的问题。这样`globalreserve`不会迅速增长的过大。
4. `countermax`的值直接决定了误差。当离上限还比较远时，可以给每线程变量countermax赋值一个比较大的数，这样对性能和扩展性比较有好处。当靠近上限时，可以给这些countermax赋值一个较小的数，这样可以降低超过`globalcountmax`的风险。
5. 在balance操作的时候，我们把`counter` 设为 `countermax/2`，这样就可以保证，a)每次计数器把计数交还给总数时，至少有一半的计数被使用了。b)加减计数都能在快速路径中 c)第二点的问题得到缓解
6. `MAX_COUNTERMAX` 导致不能进入快速路径的线程增加了，这会导致性能的降低。


```cpp
unsigned long __thread counter = 0;
unsigned long __thread countermax = 0;
unsigned long globalcountmax = 10000;
unsigned long globalcount = 0;
unsigned long globalreserve = 0;
unsigned long *counterp[NR_THREADS] = { NULL };
DEFINE_SPINLOCK(gblcnt_mutex);
#define MAX_COUNTERMAX 100

static void globalize_count(void)
{
	globalcount += counter;
	counter = 0;
	globalreserve -= countermax;
	countermax = 0;
}

static void balance_count(void)
{
	countermax = globalcountmax - globalcount - globalreserve;
	countermax /= num_online_threads();
	if (countermax > MAX_COUNTERMAX)
		countermax = MAX_COUNTERMAX;
	globalreserve += countermax;
	counter = countermax / 2;
	if (counter > globalcount)
		counter = globalcount;
	globalcount -= counter;
}

int add_count(unsigned long delta)
{
	// 减，而不是countermax + delta。防止整形溢出。
	if (countermax - counter >= delta) {
		counter += delta;
		return 1;
	}
	// 所有的全局变量访问都会上锁
	spin_lock(&gblcnt_mutex);
	globalize_count();
	if (globalcountmax - globalcount - globalreserve < delta) {
		spin_unlock(&gblcnt_mutex);
		return 0;
	}
	globalcount += delta;
	balance_count();
	spin_unlock(&gblcnt_mutex);
	return 1;
}

unsigned long read_count(void)
{
	int t;
	unsigned long sum;

	spin_lock(&gblcnt_mutex);
	sum = globalcount;
	for_each_thread(t)
		if (counterp[t] != NULL)
			sum += *counterp[t];
	spin_unlock(&gblcnt_mutex);
	return sum;
}

void count_register_thread(void)
{
	int idx = smp_thread_id();

	spin_lock(&gblcnt_mutex);
	counterp[idx] = &counter;
	spin_unlock(&gblcnt_mutex);
}
```

