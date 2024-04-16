# 



队列是最方便的线程间传递信息的方式。线程间传递信息，难免会引入锁，锁又会带来效率的大幅降低。我们从一个简单的队列开始，看看lock-free的思维如何解决问题。


# 加锁的队列

## api回顾

回顾一下互斥锁和条件变量的用法：
```c++
// 锁：是互斥的。一个线程加锁后其他线程如果试图加锁，会陷入等待。
pthread_mutex_t mutex; //锁
// 给互斥体变量加锁，其他线程执行这里时会卡住
pthread_mutex_lock(&mutex); 
 // 给互斥体变量解除锁
phtread_mutex_unlock(&mutex);


// 条件变量：用条件控制线程是否继续。条件变量不是卡别人的，使用条件卡自己的，等待别人告诉自己可以继续。
pthread_cond_t qready = PTHREAD_COND_INITIALIZER;
pthread_mutex_t qlock = PTHREAD_MUTEX_INITIALIZER;
// wait用来等待条件就绪。如果陷入wait，只能通过别的线程被唤醒。一般情况下，wait会配合while和需要wait的条件使用，避免假死和资源竞争等问题
pthread_cond_wait(&qready, &mutex); 
// signal可以通知一个线程条件已经就绪
pthread_cond_signal(&qready)
// broadcast会通知所有线程就绪。这种通知是顺序进行的，因为只有一个线程可以拿到wait时指定的锁，然后执行完自己的操作，最后unlock，把锁让给下一个线程
pthread_cond_broadcast(&qready)
```
我们可以根据这个用法写一个模板：
```c++
void thread1(){
    pthread_mutex_lock(&lock);
    while(不满足条件，比如队列为空、文件未就绪)
        pthread_cond_wait(&cond, &lock);
    // ... 得到条件了，做一些事情，比如操作文件、推出队列的东西
    pthread_mutex_unlock(&lock);
}
```

## 加锁队列的实现

```c++
// 是否为空
template <typename T>
bool BlockingQueue<T>::IsEmpty(){
    bool rv;
    g_mutex_lock(m_mutex);
    rv = m_theQueue.empty();
    g_mutex_unlock(m_mutex);
    return rv;
}
// 推出元素
template <typename T>
bool BlockingQueue<T>::Push(const T &a_elem){
    g_mutex_lock(m_mutex);
    // 如果队列已满，则等待，直到队列空出位置
    while (m_theQueue.size() >= m_maximumSize){
        g_cond_wait(m_cond, m_mutex);
    }

    bool queueEmpty = m_theQueue.empty();
    m_theQueue.push(a_elem);
    // 如果队列push之前为空，通知其余线程可以继续push
    if (queueEmpty){
        // wake up threads waiting for stuff
        g_cond_broadcast(m_cond);
    }
    g_mutex_unlock(m_mutex);
    return true;
}

template <typename T>
void BlockingQueue<T>::Pop(T &out_data){
    g_mutex_lock(m_mutex);
    // 队列为空则陷入等待，直到队列有元素
    while (m_theQueue.empty()){
        g_cond_wait(m_cond, m_mutex);
    }
    
    bool queueFull = (m_theQueue.size() >= m_maximumSize) ? true : false;
    out_data = m_theQueue.front();
    m_theQueue.pop();
    // 如果队列已经满了，通知其他线程来pop
    if (queueFull){
        // wake up threads waiting for stuff
        g_cond_broadcast(m_cond);
    }
    g_mutex_unlock(m_mutex);
}
```

我们举个例子：
1. 队列`m_maximumSize`为10
2. 连续push 20个消息，后面的10个push线程会卡住在wait
3. 连续pop 10个消息，此时10个消息被pop出去，还有10个push线程卡死在wait（假设pop时有新的push，新的push会直接push进去）
4. 此时队列为空，新来的pop卡死；之前步骤2卡死在push的线程都会被依次唤醒，push直到队列满

# CAS实现的队列
https://www.codeproject.com/Articles/153898/Yet-another-implementation-of-a-lock-free-circul

## CAS回顾

```c++
volatile int a;
a = 1;

// a不等于1的时候会一直循环
// a等于1的时候a会被赋值为2，并返回true
while (!CAS(&a, 1, 2)){
    ;
}
```
