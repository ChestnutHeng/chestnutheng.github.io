---
title: "[C++]C++ 100行实现线程池"
date: 2017-04-07T23:17:54+08:00
lastmod: 2017-04-07T23:17:55+08:00
tags: ["c++", " c++11"]
categories: ["C++"]
---


一个100行左右的简单线程池。用到了std::mutex和std::thread等新特性。
<!-- more -->
## 线程池模型
首先把每个函数抽象为一个任务(Task)，任务的过程就是调用这个Task的run函数。
然后把线程池中的线程封装为一个线程类（Thread），一直等待调度器分配任务（空闲状态），如果有任务分配立即进入忙状态。等任务执行结束再次变为空闲状态。
最后是一个调度器类（TreadPool），包含任务队列（随时添加新任务），和一个包含了Thread的vector（线程池中的线程）。如果任务队列非空，调度器每次从中取出一个任务，然后轮询线程池，搜寻空闲线程并把这个任务交给线程。
模型如下图所示：
<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/tpool.png" ></img>

## 代码实现

下面的代码实现了上述模型。其中Task类通过睡眠一定的秒数模拟任务，可以看到T1先执行完毕（1秒完毕），T2和T3在之后同时完毕，说明调度非常成功。


```c++
//linux, g++ -std=c++14 -o t *.cpp -pthread
#include <queue>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>
#include <unistd.h> 

class Task{
private:
    int no;
public:
    Task(int n){
        no = n;
    }
    //可以继承这个类重写该方法执行任务
    virtual void run(){
        sleep(no); //构造时决定执行几秒，模拟线程运行
        std::cout << no << "T\n";
    }

};

class Thread{
private:
    std::thread _thread;
    bool _isfree;
    Task *_task;
    std::mutex _locker;
public:
    //构造
    Thread() : _isfree(true), _task(nullptr){
        _thread = std::thread(&Thread::run, this);
        _thread.detach(); //放到后台， join是等待线程结束
    }
    //是否空闲
    bool isfree(){
        return _isfree;
    }
    //添加任务
    void add_task(Task *task){
        if(_isfree){
            _locker.lock();
            _task = task;
            _isfree = false;
            _locker.unlock();
        }
    }
    //如果有任务则执行任务，否则自旋
    void run(){
        while(true){
            if(_task){
                _locker.lock();
                _isfree = false;
                _task->run();
                _isfree = true;
                _task = nullptr;
                _locker.unlock();
            }
        }
    }

};

class ThreadPool{
private:
    std::queue<Task *> task_queue;
    std::vector<Thread *> _pool;
    std::mutex _locker;

public:
    //构造线程并后台执行，默认数量为10
    ThreadPool(int n = 10){
        while(n--){
            Thread *t = new Thread();
            _pool.push_back(t);
        }
        std::thread main_thread(&ThreadPool::run, this);
        main_thread.detach();
    }
    //释放线程池
    ~ThreadPool(){
        for(int i = 0;i < _pool.size(); ++i){
            delete _pool[i];
        }
    }
    //添加任务
    void add_task(Task *task){
        _locker.lock();
        task_queue.push(task);
        _locker.unlock();
    }
    //轮询
    void run(){
        while(true){
            _locker.lock();
            if(task_queue.empty()){
                _locker.unlock();
                continue;
            }
            // 寻找空闲线程执行任务
            for(int i = 0; i < _pool.size(); ++i){
                if(_pool[i]->isfree()){
                    _pool[i]->add_task(task_queue.front());
                    task_queue.pop();
                    break;
                }
            }
            _locker.unlock();
        }
    }

};

int main(){
    ThreadPool tp(2);
    
    Task t1(1);
    Task t2(3);
    Task t3(2);

    tp.add_task(&t1);
    tp.add_task(&t2);
    tp.add_task(&t3);
    
    sleep(4);   //等待调度器结束，不然会崩溃
    return 0;
}
```
