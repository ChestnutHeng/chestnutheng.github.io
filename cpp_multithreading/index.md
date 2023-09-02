# [C++]C++多线程基础


各种锁的基本概念以及在C++里的使用，还有C的一个生产消费模型。
<!-- more -->
### 操作系统的知识

#### 概念
临界区：访问和操作共享数据的代码段
避免死锁：嵌套加锁时按顺序加锁, 防止发生饥饿

原子操作：atomic_t 

#### 自旋锁
自旋锁：请求该锁的线程在等待时自旋（特别耗费处理器时间），所以只能轻量级加锁（一般锁的时间小于上下文切换的开销）。
注意：对数据而不是对代码加锁。

读写自旋锁：读时(允许读，不允许写)，写时（不允许读，不允许写）。
注意：不能把读锁升级为写锁，不然会死锁。读写操作要清晰地分开。

#### 信号量
信号量：请求锁的进程在等待时加入等待队列并睡眠。一般用于长时间加锁（唤醒、睡眠、加入队列都是很大的开销）。
通过P/V或者down()/up()操作来控制允许同时进行的线程数。信号量减一就等同与获取一个锁，锁为负数时线程就会进入等待队列。
0/1信号量（互斥信号量）：只允许同时一个线程执行。
计数信号量：允许同时多个线程执行。
读写信号量：互斥信号量的一种。

#### 互斥体
互斥体(mutex): 可以睡眠的强制互斥锁。比信号量更加首选。

mutex和自旋锁的区别：

|需求|加锁方法|
|:---|:---|
|低开销加锁|优先自旋锁|
|短期加锁|优先自旋锁|
|长期加锁|优先mutex|
|中断上下文加锁|只能自旋锁|
|持有锁时需要睡眠|只能mutex|

### C++11 的线程库

#### std::thread
`std::thread`用于创建一个执行的线程实例，所以它是一切并发编程的基础，使用时需要包含头文件，它提供了很多基本的线程操作，例如`get_id()`来获取所创建线程的线程 ID，例如使用`join()`来加入一个线程等。

#### std::mutex, std::unique_lock, std::lock_guard
使用std::mutex创建互斥体，std::unique_lock上锁。由于C++保证了所有栈对象在声明周期结束时会被销毁，所以这样的代码是异常安全的。无论发生异常还是正常结束，都会自动调用unlock()。
```cpp
#include <iostream>
#include <thread>
#include <mutex>

std::mutex mtx;

void block_area() {
    std::unique_lock<std::mutex> lock(mtx);
    //...临界区
}
int main() {
    std::thread thd1(block_area);
    thd1.join();

    return 0;
}
```

### C加锁示例：生产/消费模型
需求是两个进程维护一片共享内存，里面存十个产品（抽象为长度为10的一个循环队列）。生产者负责生产产品，注意队列满了就不能生产了，这时候进程陷入沉睡；消费者负责消费产品，消费完了队列的产品之后也要陷入沉睡。
Linux端代码如下：
#### consumer.c
```cpp
#define   __LIBRARY__
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <semaphore.h>
#include <sys/ipc.h>
#include <sys/shm.h>

#define   Total        500
#define   BUFFERSIZE   10

int main(){
    int id;
    int get_pos = 0, i;
    int *add;
    sem_t *empty, *full, *mutex;

    empty = (sem_t *)sem_open("empty", O_CREAT, 0777, 10);  //存货>10锁死(锁生产者)
    full  = (sem_t *)sem_open("full", O_CREAT, 0777, 0);    //存货<0锁死(锁消费者)
    mutex = (sem_t *)sem_open("mutex",O_CREAT, 0777, 1);    //锁共享内存(都要锁)

    id = shmget( 555204, BUFFERSIZE*sizeof(int), IPC_CREAT|0666 );//获得共享内存id
	
    add = (int*)shmat(id, NULL, 0);                         //获得对应id的内存的真实地址
	
    for(i = 0; i < Total; i++){
        sem_wait(full);     //拿取前看产品还够不够，如果够，产品-1，不够就睡眠
        sem_wait(mutex);    //操作前锁内存


        printf("%d\n", add[get_pos]);
        fflush(stdout);
        get_pos = ( get_pos + 1 ) % BUFFERSIZE;

        sem_post(mutex);    //解锁内存
        sem_post(empty);    //消费完，产品-1
    }

    sem_unlink("empty");
    sem_unlink("full");
    sem_unlink("mutex");

    return 0;
}
```
#### producer.c

```cpp
#define   __LIBRARY__
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <semaphore.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/sem.h>

#define   Total        500
#define   BUFFERSIZE   10

int main(){
    int id;
    int put_pos = 0, i;
    int *add;
    sem_t *empty, *full, *mutex;

    empty = (sem_t *)sem_open("empty", O_CREAT, 0777, 10);
    full  = (sem_t *)sem_open("full", O_CREAT, 0777, 0);
    mutex = (sem_t *)sem_open("mutex",O_CREAT, 0777, 1);
	
    id = shmget( 555204, BUFFERSIZE*sizeof(int), IPC_CREAT|0666);  
	
    add = (int*)shmat(id, NULL, 0);
	
    for( i = 0 ; i < Total; i++){
            sem_wait(empty);    //生产前看满了没有
            sem_wait(mutex);    //锁共享内存

            add[put_pos] = i;
            put_pos = ( put_pos + 1 ) % BUFFERSIZE;

            sem_post(mutex);    //解锁共享内存
            sem_post(full);     //生产完，产品数量+1
    }
    return 0;
}
```
