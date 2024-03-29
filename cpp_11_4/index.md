# [C++]C++ 11/14 笔记（四）



本部分介绍了c++11的并发编程。这些笔记是未完成的。
<!-- more -->

语法参考这里：
[现代C++教程](https://changkun.de/modern-cpp/zh-cn/07-thread/index.html)
实现参考这里：
[C++11中的mutex, lock，condition variable实现分析](http://hengyunabc.github.io/cpp11-mutex-lock-condition/)

# std::thread
C++ 11为我们带来了语言级的线程支持，包括线程的创建和等待：
```c++
//g++ -o t main.cpp -lpthread --std=c++11
#include <iostream>
#include <thread>
#include <chrono>

void foo(int sec)
{
    // sleep_for() 休眠sec秒后唤醒
    std::this_thread::sleep_for(std::chrono::seconds(sec));
}

int main()
{
    // join() 阻塞等待线程
    // joinable() 是否可以join（没设置任务函数不可以join）
    std::thread t;
    std::cout << "before starting, joinable: " << t.joinable() << '\n';
    t = std::thread(foo, 1);
    std::cout << "after starting, joinable: " << t.joinable() << '\n';
    t.join();

    // detach() 将当前线程对象所代表的执行实例与该线程对象分离，使得线程的执行可以单独进行。一旦线程执行完毕，它所分配的资源将会被释放。
    // 永远不要用detach()。失去控制的线程会有很多问题
    // get_id() 打印线程id
    std::thread t1(foo, 2);
    std::thread::id t1_id = t1.get_id();
    std::cout << "t1_id: " << t1_id << '\n';
    t1.detach();
}
```

# std::mutex和std::lock_guard同步
有了线程就必然需要锁。我们看一个例子，用RAII 的方式管理线程和锁：
```c++
// g++ -o t th.cpp --std=c++11 -lpthread
int v = 1;
void critical_section(int change_v) {
    static std::mutex mtx;
    std::lock_guard<std::mutex> lock(mtx);
    // 执行竞争操作
    v = change_v;
    // 离开此作用域后 mtx 会被释放
}
int main() {
    std::thread t1(critical_section, 2), t2(critical_section, 3);
    t1.join();
    t2.join();
    std::cout << v << std::endl;
    return 0;
}
```
看看源码，很简单地用构造和析构包了一下锁：
1. 发生异常时也可以析构，所以锁是异常安全的
2. 禁止拷贝构造、赋值
3. 锁状态是`adopt_lock_t`（已获得锁），会调用不加锁的构造函数
```c++
template <class _Mutex>
class lock_guard
{
public:
    typedef _Mutex mutex_type;
private:
    mutex_type& __m_;
public:
    explicit lock_guard(mutex_type& __m)
        : __m_(__m) {__m_.lock();}
    lock_guard(mutex_type& __m, adopt_lock_t)
        : __m_(__m) {}
    ~lock_guard() {__m_.unlock();}
private:
    lock_guard(lock_guard const&);// = delete;
    lock_guard& operator=(lock_guard const&);// = delete;
};
```

# std::unique_lock缩小锁的粒度

lock_guard 是一种RAII的思想管理锁，但是有时候我们需要自己加更小粒度的锁。
1. 同样，构造时加锁，析构时释放锁
2. 提供了lock、unlock、trylock、release等额外的功能，当然，开销也更大

```c++
void critical_section(int change_v) {
    static std::mutex mtx;
    std::unique_lock<std::mutex> lock(mtx);
    // 执行竞争操作
    v = change_v;
    std::cout << v << std::endl;
    // 将锁进行释放
    lock.unlock();

    // 在此期间，任何人都可以抢夺 v 的持有权

    // 开始另一组竞争操作，再次加锁
    lock.lock();
    v += 1;
    // 析构也会自动释放
 }  
```

# std::future 期物
在 C++11 的 `std::future` 被引入之前，并行获取数据的通常的做法是： 创建一个线程 A，在线程 A 里启动任务 B，当准备完毕后发送一个事件，并将结果保存在全局变量中。 而主函数线程 A 里正在做其他的事情，当需要结果的时候，调用一个线程等待函数来获得执行的结果。

而 C++11 提供的 `std::future` 简化了这个流程，可以用来获取异步任务的结果：
1. 使用`packaged_task`把我们的任务函数包起来得到`task`
2. 获得期物`result=task.get_future()`（此时他还没有结果）
3. 在另一个线程中执行`task`
4. 阻塞等待`result.wait()`
5. 获取结果`result.get()`

```c++
#include <iostream>
#include <future>
#include <thread>

int main() {
    // 将一个返回值为7的 lambda 表达式封装到 task 中
    // std::packaged_task 的模板参数为要封装函数的类型
    std::packaged_task<int()> task([](){return 7;});
    // 获得 task 的期物
    std::future<int> result = task.get_future(); 
    // 在一个线程中执行 task
    std::thread(std::move(task)).detach();
    std::cout << "waiting...";
    result.wait(); // 在此设置屏障，阻塞到期物的完成
    // 输出执行结果
    std::cout << "done!" << std:: endl << "future result is " << result.get() << std::endl;
    return 0;
}
```

# 原子操作 std::atomic
C++11 中多线程下共享变量的读写这一问题上，还引入了 std::atomic 模板，使得我们实例化一个原子类型，将一个 原子类型读写操作从一组指令，最小化到单个 CPU 指令。

```c++
#include <atomic>
#include <thread>
#include <iostream>

std::atomic<int> count = {0};

int main() {
    std::thread t1([](){
        count.fetch_add(1);
    });
    std::thread t2([](){
        count++;        // 等价于 fetch_add
        count += 1;     // 等价于 fetch_add
    });
    t1.join();
    t2.join();
    std::cout << count << std::endl;
    return 0;
}
```

# 条件变量 std::condition_variable
条件变量 std::condition_variable 是为了解决死锁而生，当互斥操作不够用而引入的。 比如，线程可能需要等待某个条件为真才能继续执行， 而一个忙等待循环中可能会导致所有其他线程都无法进入临界区使得条件为真时，就会发生死锁。 所以，condition_variable 实例被创建出现主要就是用于唤醒等待线程从而避免死锁。 std::condition_variable的 notify_one() 用于唤醒一个线程； notify_all() 则是通知所有线程。下面是一个生产者和消费者模型的例子：

```c++
#include <queue>
#include <chrono>
#include <mutex>
#include <thread>
#include <iostream>
#include <condition_variable>


int main() {
    std::queue<int> produced_nums;
    std::mutex mtx;
    std::condition_variable cv;
    bool notified = false;  // 通知信号

    // 生产者
    auto producer = [&]() {
        for (int i = 0; ; i++) {
            std::this_thread::sleep_for(std::chrono::milliseconds(900));
            std::unique_lock<std::mutex> lock(mtx);
            std::cout << "producing " << i << std::endl;
            produced_nums.push(i);
            notified = true;
            cv.notify_all(); // 此处也可以使用 notify_one
        }
    };
    // 消费者
    auto consumer = [&]() {
        while (true) {
            std::unique_lock<std::mutex> lock(mtx);
            while (!notified) {  // 避免虚假唤醒
                cv.wait(lock);
            }
            // 短暂取消锁，使得生产者有机会在消费者消费空前继续生产
            lock.unlock();
            std::this_thread::sleep_for(std::chrono::milliseconds(1000)); // 消费者慢于生产者
            lock.lock();
            while (!produced_nums.empty()) {
                std::cout << "consuming " << produced_nums.front() << std::endl;
                produced_nums.pop();
            }
            notified = false;
        }
    };

    // 分别在不同的线程中运行
    std::thread p(producer);
    std::thread cs[2];
    for (int i = 0; i < 2; ++i) {
        cs[i] = std::thread(consumer);
    }
    p.join();
    for (int i = 0; i < 2; ++i) {
        cs[i].join();
    }
    return 0;
}
```

# 内存顺序

两个线程读写临界区变量的时候，虽然加锁可以保证原子操作，但是不能保证原子操作的顺序。一般来讲，我们也不需要关注原子操作的顺序，如果需要关注，那就请用最强的强一致内存模型，而不是像语言那样采用六种顺序模型（工程里会带来不必要的复杂度和错误使用的风险）。
C++11 为了追求极致的性能，实现各种强度要求的一致性，为原子操作定义了六种不同的内存顺序 std::memory_order 的选项，表达了四种多线程间的同步模型
https://www.zhihu.com/question/24301047

## 宽松模型 relaxed
在此模型下，**单个线程内的原子操作都是顺序执行**的，不允许指令重排，但**不同线程间原子操作的顺序是任意**的。类型通过 `std::memory_order_relaxed` 指定。
下面的例子中，每个线程内的`fetch_add`都是顺序执行，但不同线程间的`fetch_add`顺序是乱序的。
```c++
std::atomic<int> counter = {0};
std::vector<std::thread> vt;
for (int i = 0; i < 100; ++i) {
    vt.emplace_back([&](){
        counter.fetch_add(1, std::memory_order_relaxed);
    });
}

for (auto& t : vt) {
    t.join();
}
std::cout << "current counter:" << counter << std::endl;
```

## 释放/消费模型 release/consume
在此模型中，加了一个限制，**任何一次读操作都能读到数据最近一次写入**的数据。
比如线程A写了三次，B线程来读，必须保证B线程看到的是最后一次。A线程写的顺序则不作要求。

```c++
// 初始化为 nullptr 防止 consumer 线程从野指针进行读取
std::atomic<int*> ptr(nullptr);
int v;
std::thread producer([&]() {
    int* p = new int(42);
    v = 1024;
    ptr.store(p, std::memory_order_release);
});
std::thread consumer([&]() {
    int* p;
    while(!(p = ptr.load(std::memory_order_consume)));

    std::cout << "p: " << *p << std::endl;
    std::cout << "v: " << v << std::endl;
});
producer.join();
consumer.join();
```
## 释放/获取模型 release/acquire
在此模型下，我们可以进一步加紧对不同线程间原子操作的顺序的限制。release/acquire模型保证了线程 A 中所有发生在 release x 之前的写操作，对在线程 B acquire x 之后的任何读操作都可见。
`std::memory_order_release`确保了它之后的写行为不会发生在释放操作之前，是一个向前的屏障
`std::memory_order_acquire`确保了它之前的写行为，不会发生在该获取操作之后，是一个向后的屏障
`std::memory_order_acq_rel`则结合了这两者的特点，唯一确定了一个内存屏障，使得当前线程对内存的读写不会被重排到此操作的前后。

## 顺序一致模型 sequential consistency
在此模型下，原子操作满足顺序一致性，进而可能对性能产生损耗。可显式的通过 `std::memory_order_seq_cst` 进行指定。
```c++
std::atomic<int> counter = {0};
std::vector<std::thread> vt;
for (int i = 0; i < 100; ++i) {
    vt.emplace_back([&](){
        counter.fetch_add(1, std::memory_order_seq_cst);
    });
}

for (auto& t : vt) {
    t.join();
}
std::cout << "current counter:" << counter << std::endl;
```

# 实现一个线程池
我们用一个例子[C++11线程池](https://github.com/progschj/ThreadPool/blob/master/ThreadPool.h)学习一下c11提供的这些新特性。
