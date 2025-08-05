---
title: "[Linux]并行编程：进程、线程和同步"
date: 2019-07-25T15:45:04+08:00
lastmod: 2019-07-25T15:45:09+08:00
tags: ["Linux", "perfbook", "AUPE"]
categories: ["Linux"]
description: "如何进行并行编程？本文给了一些pthead库基本的多进程（fork、wait）、多线程（create、join、mutex、rwlock、cond、barrier）API，和详细的样例帮助理解这些API。"
---



如何进行并行编程？本文给了一些pthead库基本的多进程、多线程API，和详细的样例帮助理解这些API。
本教程基于[AUPE 2013](http://www.apuebook.com/)、 [perfbook](https://mirrors.edge.kernel.org/pub/linux/kernel/people/paulmck/perfbook/perfbook.html)


# Shell中的并行

## 后台执行 &

通过&符号指定实例在后台运行，然后统一等待结束。
```bash
compute_it 1 > 1.out &
compute_it 2 > 2.out &
wait
cat 1.out 2.out
```

## 管道 |

对于一个足够大的输入文件来说，grep模式匹配将与sed编辑和sort处理并行运行。
```bash
grep "$pattern" | sed -e "s/a/b/" | sort
```

# POSIX多进程

下面给出的程序中建立了一个进程，然后修改了x的值并打印，最后父进程等待子进程结束。
## fork
`int fork()`马上创建一个当前进程的子进程。子进程会复制(而不是共享)父进程的堆栈、数据空间、fd。
1. 如果是父进程，`fork`返回子进程的pid。如果是子进程，`fork`返回0。一般用这个区分不同的分支。
2. fork返回负数表示失败。失败的原因可能有：系统有了太多的进程；系统中用户进程数超过了CHILD_MAX。此时返回负数。
3. fork后如果不需要父进程的存储空间会立马调用exec。
4. 使用`fork`一般有两个目的。父进程希望复制自己，或者想执行另外的程序（调用`exec`）
5. 为了避免拷贝成本，出现了写时拷贝技术(Copy-On-Write, COW)，子进程创建后分享父进程的数据，并把内存区域设置为只读。当需要写数据时再为这块数据创建副本。

## vfork
`int vfork()`创建一个子进程，但分享(不复制)父进程的数据。当执行exec时父进程才退出休眠。专为了避免fork的拷贝成本设计。因为share父进程的数据有很大风险，所以man手册里明确说明vfork()之后，子进程只应该调用_exit()或者exec函数族。

## exit
`void exit(int)`退出当前进程。不像return会析构局部变量，弹栈，回到上级函数。如果在子进程的main中调用了return，main会返回两次，导致程序出错。exit不会有这个问题。

## wait
`pid_t wait(int &status)` 阻塞等待任意一个子进程结束
a)如果子进程都在运行则阻塞 
b)如果一个子进程已经终止，内核向父进程发出了SIGCHLD信号，则获得终止状态并立即返回 
c)成功了返回pid，没有子进程，立即出错返回-1
d)子进程状态status可以用四个返回bool的宏 WIFEXITED(int)、WIFEXITSIGNALED(int)、WIFSTOPPED(int)、WIFCONTINUED(int)、来判断属于正常、异常、暂停、暂停后继续的状态。此外还有对应的WEIXTSTATUS(int)返回子进程exit函数的参数、WTERMSIG(int)返回信号编号、WCOREDUMP(int）返回是否生成coredump等。

`pid_t waitpid(pid_t pid, int &status, int option)`等待指定的pid的子进程结束。
a)当`pid=-1`，和`wait`等效。
b)当`option=WNOHANG`，此函数会立即返回不会阻塞。
c)成功了返回pid，没有子进程，立即出错返回-1

```c
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <poll.h>
#include <sys/wait.h>
#include <unistd.h>

int x = 0;

// 等待所有的子进程结束
 static __inline__ void waitall(void)
 {
     int pid;
     int status;
     for (;;) {              
         pid = wait(&status);    //sys/wait.h
         if (pid == -1) {
             if (errno == ECHILD)    //errno.h 子进程不存在
                 break;      
             perror("wait");     
             exit(EXIT_FAILURE); 
         }
         poll(NULL, 0, 1);       // 等待1ms
     }                   
 }

int main(int argc, char *argv[])
{
    int pid;
    pid = fork();		// <unistd.h>
    if (pid == 0) { /* child */
        x = 1;                  
        printf("Child process set x=1\n");  
        exit(EXIT_SUCCESS);         //stdlib
    }
    if (pid < 0) { /* parent, upon error */
        perror("fork");   //stdio
        exit(EXIT_FAILURE);    //stdlib
    }
    /* parent */
    waitall(); 
    //父进程一直等待到子进程退出后才调用printf（）。
    //通过不同进程并发地访问printf（）的I/O缓冲区并不简单，最好也不要这么做
    printf("Parent process sees x=%d\n", x);    
    return EXIT_SUCCESS;
}
```

# POSIX多线程

## pthread_create
`int pthread_create(pthread_t tidp, const pthread_attr_t *attr, void *(*start_rtn)(void *), void *arg)`创建一个线程去执行参数`start_rtn`中的函数。该函数参数为`arg`。`tidp`参数则会写入线程的线程ID。
1. 这三个指针都是`restrict`修饰的，代表保证他们不指向同一区域，使得编译器能够优化。
2. `pthread_t`标识线程ID，是一个非负整数。为了移植性不能当`int`处理。`pthread_equal(tid1, tid2)`可以检测两个id是否相等。`pthread_self()`可以获取当前的线程ID。
3. 成功返回0，失败返回 EINVAL、EAGAIN、EPERM。

## pthread_exit
`void pthread_exit(void *status)`提供了一个线程退出的方法。
线程有三种退出方式：
1. 在线程函数中自然返回。返回值是线程的退出码。
2. 被同进程的其他线程取消。此时线程的返回值是`PTHREAD_CANCELED`。
3. 调用`pthread_exit`。返回值会通过参数`status`传出去。


## pthread_join
`int pthread_join(pthread_t thread, void **retval)` 用于在其他线程中等待指定的线程。
1. 该函数会一直卡住，等待ID为参数`thread`的线程退出。
2. `retval`会接收等待的线程返回值。如果不关心返回值直接设为NULL。
3. 成功时返回0，失败时返回EDEADLK、ESRCH、EINVAL。

`void pthread_cleanup_push(void (*routine)(void *), void *arg)`注册一个线程结束时调用的清理函数。参数routine为调用的函数指针，arg为该函数的参数。下面的情况会触发这个清理函数：
a）调用pthread_exit。
b）作为对取消线程请求(pthread_cancel)的响应。
c）以非0参数调用 `pthread_cleanup_pop(int)`。

`pthread_cleanup_pop(int execute)`用于删除清理函数，当`execute`不为0时不会执行清理函数。需要注意此函数和push必须数量相等，不然会报错。

```c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>

int x = 0;
void *mythread(void *arg)
{
    x = 1;
    printf("Child process set x=1\n");
    return NULL;
}

int main(int argc, char *argv[])
{
    int en; 
    pthread_t tid;
    void *vp;
    if ((en = pthread_create(&tid, NULL,mythread, NULL)) != 0) {
        fprintf(stderr, "pthread_join: %s\n", strerror(en));
        exit(EXIT_FAILURE);
    }   
    /* parent */
    if ((en = pthread_join(tid, &vp)) != 0) { 
        fprintf(stderr, "pthread_join: %s\n", strerror(en));
        exit(EXIT_FAILURE);
    }
    printf("Parent process sees x=%d\n", x);
    return EXIT_SUCCESS;
}
```

# POSIX 锁

通常用互斥锁在避免资源间的竞争。当一个资源被锁住时，其他资源如果试图获得锁，他就会等待锁释放再执行。

## 声明

```c++
// 声明
pthread_mutex_t mymutex;

// 另一个静态声明+初始化方法，其中INITIALIZER是一个结构体 { { 0, 0, 0, 0, 0, 0, { 0, 0 } } }
pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;
```

## 初始化和释放

`int pthread_mutex_init(pthread_mutex_t *restrict mutex, const pthread_mutexattr_t *restrict attr)` 使用前必须初始化。`mutex`是要初始化的锁。
1. `pthread_mutexattr_t`提供了锁的初始化选项。如果不需要设置为NULL。
2. 成功返回0，失败返回错误码


`int pthread_mutex_destroy(pthread_mutex_t *mutex)`使用后锁必须被摧毁。
1. 成功返回0，失败返回错误码

## 加锁和释放锁

`int pthread_mutex_lock(pthread_mutex_t *mutex)` 占用锁，如果锁被占用，会一直等待
`int pthread_mutex_unlock(pthread_mutex_t *mutex)` 释放锁
1. 成功返回0，失败返回错误码

`int pthread_mutex_trylock(pthread_mutex_t *mutex)` 试图占用锁
a) 如果锁没有被占用，会占用锁并返回0
b) 如果锁已经被占用，会返回`EBUSY`

`int pthread_mutex_timedlock(pthread_mutex_t *restrict mutex, const struct timespec *restrict abs_timeout)` 占用锁，如果锁被占用，会一直等待到`abs_timeout`这个时间点，返回超时
1. `abs_timeout`是绝对时间，是未来的一个时间戳
2. 等待超时后返回`ETIMEDOUT`

```c++
// 声明、初始化
pthread_mutex_t mymutex;
pthread_mutex_init(&mymutex, NULL);

// 锁
pthread_mutex_lock(&mymutex);
// ... do something
pthread_mutex_unlock(&mymutex);

// 销毁
pthread_mutex_destroy(&mymutex);

// 一个超时锁的例子
struct timespec tout;
struct tm *tmp;
char buf[64];
pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_lock(&lock);
printf("mutex is locked\n");
clock_gettime(CLOCK_REALTIME, &tout);
tmp = localtime(&tout.tv_sec);
strftime(buf, sizeof(buf), "%r", tmp);
printf("current time is %s\n", buf);
tout.tv_sec += 10;    /* 10 seconds from now */
/* caution: this could lead to deadlock */
err = pthread_mutex_timedlock(&lock, &tout);
clock_gettime(CLOCK_REALTIME, &tout);
tmp = localtime(&tout.tv_sec);
strftime(buf, sizeof(buf), "%r", tmp);
printf("the time is now %s\n", buf);
```

下面的例子有两个线程。
`lock_reader` 每隔1ms读一次全局变量x的值，用来监测x的变化
`lock_writer` 每5ms把x的值加一
如果两个线程用了一把锁，reader会等待writer写完，再去读，x只被读到一次。
如果两个线程用了两把锁（等于不加锁），writer每次更改x都会被reader读到。


```c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <errno.h>
#include <poll.h>
#include <string.h>


#define ACCESS_ONCE(x) (*(volatile typeof(x) *)&(x))
#define READ_ONCE(x) \
            ({ typeof(x) ___x = ACCESS_ONCE(x); ___x; })
#define WRITE_ONCE(x, val) ({ ACCESS_ONCE(x) = (val); })

pthread_mutex_t lock_a = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t lock_b = PTHREAD_MUTEX_INITIALIZER;

int x = 0;

void *lock_reader(void *arg)				
{
	int en;
	int i;
	int newx = -1;
	int oldx = -1;
	pthread_mutex_t *pmlp = (pthread_mutex_t *)arg;

	if ((en = pthread_mutex_lock(pmlp)) != 0) {	
		fprintf(stderr, "lock_reader:pthread_mutex_lock: %s\n",
			strerror(en));
		exit(EXIT_FAILURE);
	}						
	for (i = 0; i < 100; i++){
		newx = READ_ONCE(x);
		if (newx != oldx) {
			printf("lock_reader(): x = %d at %dms\n", newx, i);
		}
		oldx = newx;
		poll(NULL, 0, 1);
	}
        if ((en = pthread_mutex_unlock(pmlp)) != 0) {	
		fprintf(stderr, "lock_reader:pthread_mutex_lock: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}						
	return NULL;
}							

void *lock_writer(void *arg)				
{
	int en;
	int i;
	pthread_mutex_t *pmlp = (pthread_mutex_t *)arg;

	if ((en = pthread_mutex_lock(pmlp)) != 0) {	
		fprintf(stderr, "lock_writer:pthread_mutex_lock: %s\n",
			strerror(en));
		exit(EXIT_FAILURE);
	}						
	for (i = 0; i < 3; i++) {
		WRITE_ONCE(x, READ_ONCE(x) + 1);
		poll(NULL, 0, 5);
	}						
	if ((en = pthread_mutex_unlock(pmlp)) != 0) {	
		fprintf(stderr, "lock_writer:pthread_mutex_lock: %s\n",
			strerror(en));
		exit(EXIT_FAILURE);
	}						
	return NULL;
}							


int main(int argc, char *argv[])
{
	int en;
	pthread_t tid1;
	pthread_t tid2;
	void *vp;


	printf("Creating two threads using same lock:\n");
	en = pthread_create(&tid1, NULL, lock_reader, &lock_a);
	if (en != 0) {
		fprintf(stderr, "pthread_create: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}							
	en = pthread_create(&tid2, NULL, lock_writer, &lock_a);
	if (en != 0) {
		fprintf(stderr, "pthread_create: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}							
	if ((en = pthread_join(tid1, &vp)) != 0) {	
		fprintf(stderr, "pthread_join: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}
	if ((en = pthread_join(tid2, &vp)) != 0) {
		fprintf(stderr, "pthread_join: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}						



	printf("Creating two threads w/different locks:\n");
	x = 0;
	en = pthread_create(&tid1, NULL, lock_reader, &lock_a);
	if (en != 0) {
		fprintf(stderr, "pthread_create: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}
	en = pthread_create(&tid2, NULL, lock_writer, &lock_b);
	if (en != 0) {
		fprintf(stderr, "pthread_create: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}
	if ((en = pthread_join(tid1, &vp)) != 0) {
		fprintf(stderr, "pthread_join: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}
	if ((en = pthread_join(tid2, &vp)) != 0) {
		fprintf(stderr, "pthread_join: %s\n", strerror(en));
		exit(EXIT_FAILURE);
	}


	return EXIT_SUCCESS;
}

// Creating two threads using same lock:
// lock_reader(): x = 0 at 0ms
// Creating two threads w/different locks:
// lock_reader(): x = 0 at 0ms
// lock_reader(): x = 1 at 1ms
// lock_reader(): x = 2 at 5ms
// lock_reader(): x = 3 at 10ms
```

# POSIX 读写锁

和互斥锁类似，读写锁用来专门为读写操作加锁。读写锁有三种状态：
1. 锁未被占用。此时可以读，可以写。
2. 锁被读锁占用（共享锁）。此时可以读，不可以写。
3. 锁被写锁占用（互斥锁）。此时不可读不可写。

```c++
// 初始化锁，参数同互斥锁。
int pthread_rwlock_init(pthread_rwlock_t *restrict rwlock, const pthread_rwlockattr_t *restrict attr)
// 或者
pthread_rwlock_t rwl = PTHREAD_RWLOCK_INITIALIZER;
// 摧毁锁，参数同互斥锁。
int pthread_rwlock_destroy(pthread_rwlock_t *rwlock) 


// 加读锁
pthread_rwlock_rdlock()
pthread_rwlock_tryrdlock()
pthread_rwlock_timedrdlock()
// 加写锁
pthread_rwlock_wrlock()
pthread_rwlock_trywrlock()
pthread_rwlock_timedwrlock() 
// 解锁
int pthread_rwlock_unlock(pthread_rwlock_t *rwlock)
```


# POSIX 条件变量
 
 条件变量用来让线程等待某个条件达成。我们在需要等待条件成功的地方加上while和`pthread_cond_wait`，以便于等待条件就绪后继续执行，否则卡在这里；我们在促使条件转为成功的地方加上`pthread_cond_signal`通知条件已经就绪。如果有多个线程在等待条件，可以使用`pthread_cond_broadcast`通知所有线程就绪；但是这种通知是顺序进行的（因为会搭配使用lock，lock会等待），那些醒来后发现条件又不满足的线程会继续进入等待。
 1. 条件变量的访问由互斥量保护，使用时必须加锁
 2. `pthread_cond_wait`在调用时必须在while循环里。由于假醒/多核竞争等原因，内核的建议是我们配套使用while循环 [为什么？](http://blog.vladimirprus.com/2005/07/spurious-wakeups.html)

## 初始化

```c++
// 条件变量使用前也需要初始化，使用完需要释放
pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
int pthread_cond_init(pthread_cond_t *restrict cond, const pthread_condattr_t *restrict attr);
int pthread_cond_destroy(pthread_cond_t *cond);
```

## 等待唤醒
`int pthread_cond_wait(pthread_cond_t *restrict cond, pthread_mutex_t *restrict mutex)` 在`cond`接收到唤醒之前，该函数会一直都待。`mutex`是用来保护该条件变量的锁。
1. 此函数必须用前加锁，用后解锁 <a href="https://stackoverflow.com/questions/4544234/calling-pthread-cond-signal-without-locking-mutex"> 了解为什么？ </a>
2. 本函数首先将当前线程加入到唤醒队列，然后旋即解锁mutex，最后等待被唤醒。被唤醒后，又对mutex加锁（可能是看起来没有对用户的行为作任何的改变）。
3. 2的操作保证了线程在陷入wait后至被加入唤醒队列这段时间内是原子的。如果不加锁，可能唤醒时，等待线程尚未被加入到唤醒队列，就会产生唤醒丢失。
4. 这个锁保证了避免唤醒丢失外，还保证了唤醒前后临界区的其他变量不被操作。

`int pthread_cond_timedwait(pthread_cond_t *restrict cond, thread_mutex_t *restrict mutex,const struct timespec *restrict abstime);` 
1. 在上面函数的基础上增加了绝对超时时间。
2. 如果到达绝对时间还没被唤醒，该函数返回 ETIMEDOUT。

## 通知唤醒
`int pthread_cond_broadcast(pthread_cond_t *cond)` 会唤醒所有该等待`cond`的线程
1. 成功返回0，失败返回错误

`int pthread_cond_signal(pthread_cond_t *cond);` 会唤醒一个等待`cond`的线程
1. 成功返回0，失败返回错误

```c++
#include <pthread.h>

struct msg {
	struct msg *m_next;
	/* ... more stuff here ... */
};
struct msg *workq;
// 信号量的语义是queue已经准备好消费
pthread_cond_t qready = PTHREAD_COND_INITIALIZER;
pthread_mutex_t qlock = PTHREAD_MUTEX_INITIALIZER;

void process_msg(void)
{
	struct msg *mp;
	for (;;) {
		pthread_mutex_lock(&qlock);
		// 这个while可以在queue为空时卡住自己
		while (workq == NULL)
			pthread_cond_wait(&qready, &qlock);
		mp = workq;
		workq = mp->m_next;
		pthread_mutex_unlock(&qlock);
		/* now process the message mp */
		read_map_val_add_process(mp);
	}
}

void enqueue_msg(struct msg *mp)
{
	pthread_mutex_lock(&qlock);
	mp->m_next = workq;
	workq = mp;
	pthread_mutex_unlock(&qlock);
	pthread_cond_signal(&qready);
}
```

# POSIX 屏障
 
屏障保证了一组线程同时到达某一点。在其他所有的线程到达wait之前，先到的线程会休眠并等待，直到大家都到达wait，再继续后面的工作。

```c++

// 初始化屏障，count为必须到达的线程数量。一旦数量满足，就继续运行
int pthread_barrier_init(pthread_barrier_t *restrict barrier,
              const pthread_barrierattr_t *restrict attr, unsigned count);
// 摧毁屏障
int pthread_barrier_destroy(pthread_barrier_t *barrier);

// 到达并等待
int pthread_barrier_wait(pthread_barrier_t *barrier);
```

下面的代码演示了8个线程共同完成100万个数排序的过程。
```c++
#include "apue.h"
#include <pthread.h>
#include <limits.h>
#include <sys/time.h>

#define NTHR   8				/* number of threads */
#define NUMNUM 8000000L			/* number of numbers to sort */
#define TNUM   (NUMNUM/NTHR)	/* number to sort per thread */

long nums[NUMNUM];
long snums[NUMNUM];

pthread_barrier_t b;

#ifdef SOLARIS
#define heapsort qsort
#else
extern int heapsort(void *, size_t, size_t,
                    int (*)(const void *, const void *));
#endif

/*
 * Compare two long integers (helper function for heapsort)
 */
int
complong(const void *arg1, const void *arg2)
{
	long l1 = *(long *)arg1;
	long l2 = *(long *)arg2;

	if (l1 == l2)
		return 0;
	else if (l1 < l2)
		return -1;
	else
		return 1;
}

/*
 * Worker thread to sort a portion of the set of numbers.
 */
void *
thr_fn(void *arg)
{
	long	idx = (long)arg;

	heapsort(&nums[idx], TNUM, sizeof(long), complong);
	pthread_barrier_wait(&b);

	/*
	 * Go off and perform more work ...
	 */
	return((void *)0);
}

/*
 * Merge the results of the individual sorted ranges.
 */
void
merge()
{
	long	idx[NTHR];
	long	i, minidx, sidx, num;

	for (i = 0; i < NTHR; i++)
		idx[i] = i * TNUM;
	for (sidx = 0; sidx < NUMNUM; sidx++) {
		num = LONG_MAX;
		for (i = 0; i < NTHR; i++) {
			if ((idx[i] < (i+1)*TNUM) && (nums[idx[i]] < num)) {
				num = nums[idx[i]];
				minidx = i;
			}
		}
		snums[sidx] = nums[idx[minidx]];
		idx[minidx]++;
	}
}

int
main()
{
	unsigned long	i;
	struct timeval	start, end;
	long long		startusec, endusec;
	double			elapsed;
	int				err;
	pthread_t		tid;

	/*
	 * Create the initial set of numbers to sort.
	 */
	srandom(1);
	for (i = 0; i < NUMNUM; i++)
		nums[i] = random();

	/*
	 * Create 8 threads to sort the numbers.
	 */
	gettimeofday(&start, NULL);
	pthread_barrier_init(&b, NULL, NTHR+1);
	for (i = 0; i < NTHR; i++) {
		err = pthread_create(&tid, NULL, thr_fn, (void *)(i * TNUM));
		if (err != 0)
			err_exit(err, "can't create thread");
	}
	pthread_barrier_wait(&b);
	merge();
	gettimeofday(&end, NULL);

	/*
	 * Print the sorted list.
	 */
	startusec = start.tv_sec * 1000000 + start.tv_usec;
	endusec = end.tv_sec * 1000000 + end.tv_usec;
	elapsed = (double)(endusec - startusec) / 1000000.0;
	printf("sort took %.4f seconds\n", elapsed);
	for (i = 0; i < NUMNUM; i++)
		printf("%ld\n", snums[i]);
	exit(0);
}
```
