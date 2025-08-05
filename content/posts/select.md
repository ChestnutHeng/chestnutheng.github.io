---
title: "[后台]用select写一个HTTP代理"
date: 2017-01-12T11:23:44+08:00
lastmod: 2017-01-12T11:23:48+08:00
tags: ["socket", "后台"]
categories: ["后台"]
description: "可以通过这个样例学习select。实现了简单的非阻塞的HTTP代理，速度非常快，多线程+select。支持HTTPS。"
---



## 函数说明

<a href="https://docs.python.org/3/library/select.html">18.3. select — Waiting for I/O completion — Python 3.6.0 documentation</a>

### select.select(rlist, wlist, xlist[, timeout])
Unix select()系统调用的一个简单接口。前三个参数是文件描述符（int类型）的序列。
```
    rlist：等待准备读取
    wlist：等待准备写作
    xlist：等待一个异常
```
### 参数说明
在Unix上序列可以为空，但在Windows则不可以。可选的timeout参数将超时指定为浮点数（以秒为单位）。当省略timeout参数时，该函数阻塞，直到至少一个文件描述符已准备好。该值为0时表示轮询从不停止。

### 返回值
准备好的对象列表的三元组（前三个参数的子集）。当超时但没有文件描述符就绪时，返回三个空列表。

### 序列对象
序列中可用的对象类型包括Python文件对象（例如sys.stdin或由open()或os.popen()返回的对象），由socket.socket()返回的socket对象。你也可以自己定义一个类，只要它有一个合适的fileno()方法（返回一个真正的文件描述符，而不只是一个随机整数）。

注意：
Windows上的文件对象不可接受，但socket可以。在Windows上，底层的select()函数由WinSock库提供，不处理不是源自WinSock的文件描述符。

## 实现HTTP代理

代理由两个部分组成：**客户端-代理**的socket，和**代理-Web服务器**的socket。
因为代理像两边接受数据时调用recv方法都会发生阻塞，
所以，在这个样例中，事件循环由两个事件组成：**客户端-代理链接**可以继续接受数据了，和**代理-Web服务器链接**可以接受数据了（指都是代理端）。


```python
    import select
    import socket
    import _thread
    
    BUFF_SIZE = 1024
    
    
    # get http head data from a connection
    def get_post(conn):
        res = b''
        while True:
            res += conn.recv(BUFF_SIZE)
            if b'\r\n\r\n' in res:
                break
        return res
    
    
    class Proxy:
        # init. in_conn: browser-proxy connection, out_conn: proxy-web_server connection
        def __init__(self, conn, timeout):
            self.in_conn = conn
            self.out_conn = None
            self.timeout = timeout
    
            self.run()
    
        # main function
        def run(self):
            action, url, http_ver, req, headers = self.__parse_header()
            # https
            if action in ["CONNECT"]:
                self.in_conn.send(b'HTTP/1.1 200 Connection established\r\nProxy-agent: God Proxy\r\n\r\n')
                self.__connect(headers)
            # http
            else:
                self.__connect(headers)
                self.out_conn.send(req)
            self.event_loop()
            # close connection
            self.in_conn.close()
            self.out_conn.close()
    
        # event loop
        def event_loop(self):
            count = 0
            inputs = [self.in_conn, self.out_conn]
            outputs = []
            while True:
                read_list, _, exception_list = select.select(inputs, outputs, inputs, self.timeout)
                count += 1
                for future_object in read_list:
                    # once could read, receive data
                    data = future_object.recv(1024)
                    if data:
                        # read in_conn's data, send to out_conn or out_conn to in_conn
                        if future_object is self.in_conn:
                            # print(count, 'out conn', data[:10], '...', data[-10:])
                            self.out_conn.sendall(data)
                        else:
                            # print(count, 'in conn', data[:10], '...', data[-10:])
                            self.in_conn.sendall(data)
                if exception_list:
                    break
                # time out
                if count > 100:
                    break
    
        # parse host from url and setting up out_conn socket
        def __connect(self, headers):
            host_list = headers['Host'].split(':')
            host = host_list[0]
            if host_list[-1].isdigit():
                port = int(host_list[1])
            else:
                port = 80
            socket_info = socket.getaddrinfo(host, port)[0]
            self.out_conn = socket.socket(socket_info[0])
            self.out_conn.connect(socket_info[4])
            print('WEB SITE: ', host, socket_info[4])
    
        # get headers from in_conn and parse
        def __parse_header(self):
            req = get_post(self.in_conn)
            str_req = req[:req.find(b'\r\n\r\n')].decode('utf8')
            headers = {}
            lines = str_req.split('\r\n')
            for line in lines[1:]:
                line = line.split(': ')
                headers[line[0]] = line[1]
            action, url, http_ver = lines[0].split()
            return action, url, http_ver, req, headers
    
    
    def main():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
        server_address = ('0.0.0.0', 8899)
        server.bind(server_address)
    
        server.listen(0)
        # 1 connection to 1 thread
        while True:
            conn, addr = server.accept()
            _thread.start_new_thread(Proxy, (conn, 3))
    
    if __name__ == '__main__':
        main()

```

