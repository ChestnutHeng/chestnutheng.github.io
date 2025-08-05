---
title: "[Python]Python版socket十行模板"
date: 2017-01-20T10:15:13+08:00
lastmod: 2017-01-20T10:15:22+08:00
tags: ["Python", " socket"]
categories: ["Python"]
description: "socket十行模板"
---



以下的socket
都是python实现的**服务端接受客户端键盘输入的信息，改为大写返回客户端**的模板
都是**同步、阻塞**的
都会在**数据长度**大于1024时产生错误，请自己写协议
**端口**都是8080，请确保未被占用

## tcp_server.py

6行控制监听的最大tcp链接数。
tcp是有链接的。9行建立链接，10行接受数据，11行发送数据，12行关闭链接。

```python
    import socket

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 8080))
    server.listen(1)

    while True:
        conn, addr = server.accept()
        data_from_client = conn.recv(1024).decode('utf8')
        conn.sendall(data_from_client.upper().encode('utf8'))
        conn.close()
```

## tcp_client.py

5行链接，6行发送数据，7行接收数据，9行关闭链接。

```python
    import socket

    while True:
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.connect(("0.0.0.0", 8080))
        client.sendall(input().encode('utf8'))
        data_from_server = client.recv(1024).decode('utf8')
        print('GET ' + data_from_server)
        client.close()
```

## udp_server.py

8行收，10行发。
需要注意的是，发送时的地址写收数据时得到的地址。

```python
    import socket

    SERVER_ADDR =  ("0.0.0.0", 8080)
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(SERVER_ADDR)

    while True:
        data, client_addr = server.recvfrom(1024)
        sending = data.decode('utf8').upper()
        server.sendto(sending.encode('utf8'), client_addr)
```

## udp_client.py

7行发，8行收。

```python
    import socket

    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    SERVER_ADDR =  ("0.0.0.0", 8080)

    while True:
        server.sendto(input().encode('utf8'), SERVER_ADDR)
        data, addr = server.recvfrom(1024)
        print('GET', data.decode('utf8'))
```

