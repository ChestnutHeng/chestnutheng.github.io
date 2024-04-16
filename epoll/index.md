# [后台]在Python中使用epoll




学期初写代理的时候发现阻塞式socket并不能满足需要，多线程也不是一个很好的解决方案。这篇文章系统地介绍了epoll是什么以及如何使用。
<!-- more -->
英文好的同学可以直接看
<a href="http://scotdoyle.com/python-epoll-howto.html">How To Use Linux epoll with Python</a>
本博客的大部分内容都是基于这篇文章的。

## 什么是epoll

（维基百科）
于Linux 2.5.44首度登场的epoll是Linux内核的可扩展I/O事件通知机制。它设计目的只在替换既有POSIX select(2)与poll(2)系统函数，让需要大量操作文件描述符的程序得以发挥更优异的性能(举例来说：旧有的系统函数所花费的时间复杂度为O(n)，epoll则耗时O(1))。epoll与FreeBSD的kqueue类似，底层都是由可配置的操作系统内核对象建构而成，并以文件描述符(file descriptor)的形式呈现于用户空间。


## 为什么使用epoll

首先理解同步异步的概念：
<a href="https://www.zhihu.com/question/19732473/answer/20851256">怎样理解阻塞非阻塞与同步异步的区别？- 知乎</a>


1. 同步与异步
同步和异步关注的是消息通信机制 (synchronous communication/ asynchronous communication)
所谓同步，就是在发出一个调用时，在没有得到结果之前，该调用就不返回。但是一旦调用返回，就得到返回值了。
换句话说，就是由调用者主动等待这个调用的结果。
而异步则是相反，调用在发出之后，这个调用就直接返回了，所以没有返回结果。换句话说，当一个异步过程调用发出后，调用者不会立刻得到结果。而是在调用发出后，被调用者通过状态、通知来通知调用者，或通过回调函数处理这个调用。

2. 阻塞与非阻塞
阻塞和非阻塞关注的是程序在等待调用结果（消息，返回值）时的状态.
阻塞调用是指调用结果返回之前，当前线程会被挂起。调用线程只有在得到结果之后才会返回。
非阻塞调用指在不能立刻得到结果之前，该调用不会阻塞当前线程。

阻塞式socket：
阻塞式socket使用单线程进行通信。主线程创建一个新的socket线程并侦听该socket，它一次性接受所有连接，然后让这个线程与客户端进行交互。因为创建的线程都只和一个客户端通信，所以阻塞并不妨碍其他线程工作
虽然多线程的阻塞式通信编码简单，但是在多线程共享资源时非常困难，在多核下表现也很差

非阻塞的socket：
于是很多替代并发阻塞式socket的方法出现了，例如基于事件系统设计的epoll，它并不会阻塞线程，它可以使用一个线程实现，大大节约了资源.

可见epoll是一个同步的非阻塞解决方案。

## 一般步骤
使用python中的epoll一般有如下步骤：
1. 创建epoll对象
2. 告诉epoll对象监视特定socket上的特定事件
3. 询问epoll对象哪些socket可能有自上次查询以来的指定事件
4. 对这些socket执行一些操作
5. 告诉epoll对象修改要监视的socket和事件的列表
6. 重复步骤3到5直到完成
7. 销毁epoll对象

## 代码实例
epoll设有水平触发和边沿触发两种模式。
1. 在边沿触发操作模式下，socket发生读或写事件后，调用epoll.poll()只会给socket返回一次事件。调用程序必须处理与该事件相关的所有数据。当事件的数据为空时，对socket的继续操作将导致异常。
2. 在水平触发操作模式中，对epoll.poll()的重复调用将导致注册事件的重复通知，直到与该事件相关联的所有数据都已被处理。

边沿触发往往被用于程序员不想使用系统的事件管理机制时。
下面的示例是一个水平触发的典型样例。
需要注意的是，`event & select.EPOLLIN` 表示事件的掩码，当掩码值为0时对应的事件发生。

```python
    import socket, select

    EOL1 = b'\n\n'
    EOL2 = b'\n\r\n'
    response  = b'HTTP/1.0 200 OK\r\nDate: Mon, 1 Jan 1996 01:01:01 GMT\r\n'
    response += b'Content-Type: text/plain\r\nContent-Length: 13\r\n\r\n'
    response += b'Hello, world!'

    serversocket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    serversocket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    serversocket.bind(('0.0.0.0', 8080))
    serversocket.listen(1)

    # 由于socket在默认情况下阻塞，因此使用非阻塞（异步）模式
    serversocket.setblocking(0) 

    # 创建一个epoll对象
    # 注册socket的读事件为偏好(读事件会在socket建立链接时发生)
    epoll = select.epoll()
    epoll.register(serversocket.fileno(), select.EPOLLIN)

    try:
       # connections字典将文件描述符（int类型）映射到它们对应的网络连接对象。
       connections = {}; requests = {}; responses = {}
       while True:
          # 查询epoll对象并获取等待时间内发生的事件列表。参数“1”表示可以等待一秒钟。
          events = epoll.poll(1)    
          for fileno, event in events:  # events 是(文件描述符，事件代码）二元组的数组
             # 建立一个新的链接
             if fileno == serversocket.fileno():    
                connection, address = serversocket.accept()
                connection.setblocking(0)   # 设置为非阻塞模式
                epoll.register(connection.fileno(), select.EPOLLIN) # 注册读事件（EPOLLIN）
                connections[connection.fileno()] = connection
                requests[connection.fileno()] = b''
                responses[connection.fileno()] = response
             # 当服务端该收数据（客户端已经发出）
             elif event & select.EPOLLIN:   
                requests[fileno] += connections[fileno].recv(1024)
                if EOL1 in requests[fileno] or EOL2 in requests[fileno]:
                   # 一旦接收到完整的请求，则取消注册读事件并注册写事件（EPOLLOUT）
                   # 将响应数据发送回客户端时可能会发生写事件
                   epoll.modify(fileno, select.EPOLLOUT)    
                   # 打印完整的请求(尽管与客户端的通信是交错的，但是该数据可以被组合并作为整个消息处理)
                   print('-'*40 + '\n' + requests[fileno].decode()[:-2]) 
             # 当服务端该发数据（客户端可以收）
             elif event & select.EPOLLOUT:  
                byteswritten = connections[fileno].send(responses[fileno]) # 一次一次发送响应数据
                responses[fileno] = responses[fileno][byteswritten:]
                if len(responses[fileno]) == 0: # 直到完整响应已传送到OS准备进行传输
                   epoll.modify(fileno, 0)  # 发送完整的响应后，禁止读写事件
                   connections[fileno].shutdown(socket.SHUT_RDWR)   # 关闭连接
             # HUP事件表示客户端socket已经断开连接(不需要注册, 默认发送)
             elif event & select.EPOLLHUP:  
                epoll.unregister(fileno)
                connections[fileno].close()
                del connections[fileno]
    finally:
       # Python将在程序结束时自动关闭socket连接,不需显式关闭
       epoll.unregister(serversocket.fileno())
       epoll.close()
       serversocket.close()
```

## TCP选项

TCP_CORK选项可用于“填满”消息，直到它们准备好发送。 这个选项适用于于使用HTTP 1.1流水线的HTTP服务器。
```
elif event & select.EPOLLIN: 
    ...receive something...
    connections[fileno].setsockopt(socket.IPPROTO_TCP, socket.TCP_CORK, 1)
elif event & select.EPOLLOUT: 
    ...send something...
    connections[fileno].setsockopt(socket.IPPROTO_TCP, socket.TCP_CORK, 0)
```
TCP_NODELAY选项用于告诉操作系统传递给socket.send()的任何数据应立即发送到客户端，而不被操作系统缓冲。 这个选项用于SSH客户端或其他“实时”应用程序。
```
serversocket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
```

