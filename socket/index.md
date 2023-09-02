# [Linux]Linux socket API


## 创建和关闭

`int socket(int domain, int type, int protocol)` 创建一个socket。
1. `domain` 指定了通信的特性。`AF_UNIX` Unix域，`AF_INET` IPv4域。 `AF_INET6` IPv6域。

2. `type` 指定了连接的类型。
`SOCK_STREAM`     有序、可靠、双向、面向连接的字节流 TCP
`SOCK_DGRAM`      不可靠、无连接、固定长度的报文 UDP
`SOCK_SEQPACKET`  固定长度、有序、可靠、双向、面向连接的字节流

3. `protocol` 为0时，选择指定域的默认协议。`AF_INET`域的`SOCK_STREAM`默认的协议为TCP，`SOCK_DGRAM`则为UDP。还有`IPPROTO_ICMP`、`IPPROTO_IP`、`IPPROTO_RAW`等。`SOCK_STREAM`提供字节流服务，所以程序分不出报文的界限。

`int shutdown(int socketfd, int how)` 关闭一个socket。
1. 套接字函数是双向的。可以用这个函数关闭套接字的某个方向的IO。
2. `how`是`SHUT_RD`表示关闭读端，无法从套接字读取数据。`SHUT_WR`是关闭写端，无法向套接字写入数据。`SHUT_RDWR`无法读也无法写。
3. `close()`是一个fd的通用释放函数。他和`shutdown`有何不同？1) `close`要等所有的活动引用关闭后才释放套接字。这使得`dup`之后的套接字必须等待所有的引用释放。但是`shutdown`和引用fd数量无关。2)`shutdown`可以方便地关闭读写的任何一端。


## 网络地址

### 地址的结构体

```
// Linux 套接字
// 这是Linux定义的一个通用结构。所有地址都可以强转为这个结构体，比如IPV4、IPV6等，便于使用。
struct sockaddr {
        u_short sa_family;              /* address family */
        char    sa_data[14];            /* up to 14 bytes of direct address */
};

// IPv4 地址
// 1. in_port_t 是16位的网络序整数，需要htons转换到网络序再赋值
// 2. sin_addr 有几种常见的常量，INADDR_ANY表示所有网卡
sockaddr_in {
    sa_family_t sin_family;
    in_port_t sin_port;			    /* Port number.  (typedef uint16_t in_port_t)*/
    struct in_addr sin_addr;		/* Internet address.  （typedef uint32_t in_addr_t)*/
    unsigned char sin_zero[8];		/* sockaddr 里sa_data定义的14(sa_data)-2(sin_port)-4(sin_addr)=8字节*/
}
```
### 网络序
下面的函数提供了网络序端口和主机序端口（int类型）转换的方法。
`uint32_t htonl(uint32_t hostint32)`返回以网络序（大端序）表示的整数。
`uint16_t htons(uint16_t hostint32)`
`uint32_t ntohl(uint32_t netint32)` 返回以主机序（小端序）表示的整数。
`uint16_t ntohs(uint16_t netint32)`

### 地址和字符串的转换

`const char *inet_ntop(int af, const void *src, char *dst, socklen_t size)`地址到字符串。

`int inet_pton(int af, const char *src, void *dst)` 字符串到地址。
1. 其中，`af`有`AF_INET`和`AF_INET6`两个值。`src`是地址，`dst`是输出的字符串。`size`是字符串大小。
2. 这两个函数的工作是把二进制和字符串互转，例如将串`192.168.33.123` 转为 `1100 0000  1010 1000  0010 0001  0111 1011`。每八位代表IP地址中的一段，比如末尾的`0111 1011`就是`123`。
一个例子：
```c
struct in_addr addr;
if(inet_pton(AF_INET, "127.0.0.1", &addr.s_addr) == 1)
       printf("NetIP: %x\n", addr.s_addr);    //NetIP: 100007f
char str[20];
if(inet_ntop(AF_INET, &addr.s_addr, str, sizeof str))
    printf("StrIP: %s\n", str);    //StrIP: 127.0.0.1
```

一些老的函数，只能用于IPV4：
`in_addr_t inet_addr(const char *cp)` 字符串直接初始化为地址。（仅用于IPV4）

`int inet_aton(const char *cp, struct in_addr *inp)` 字符串到地址。（仅用于IPV4）

`int inet_ntoa(const char *cp, struct in_addr *inp)` 地址到字符串。（仅用于IPV4）

### 地址查询

`int getaddrinfo(const char *node, const char *service,
	const struct addrinfo *hints,
	struct addrinfo **res);`
1. `node`可以是域名、IP，如 `www.qq.com`
2. `service`可以是`http`或者端口号，其定义在`/etc/services`文件中。这个文件的作用是使程序可以在其代码中进行`getportbyname`接字调用，以了解应使用的端口。例如，POP3电子邮件守护程序将执行`getportbyname(POP3)`，以检索运行POP3的数字110。 
3. `hints` 是一系列选项。`res`是返回的地址结果。我们可以用下面的例子使用它：
```c
#define _POSIX_SOURCE

#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>

#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>

int main(int argc, char **argv)
{
	int status;
	struct addrinfo hints, *res, *this;
	char ipaddr[INET6_ADDRSTRLEN];
	if (argc != 2) {
		fprintf(stderr, "usage: showip hostname\n");
		return 1;
	}
	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_UNSPEC;     /* AF_INET(IPv4) AF_INET6(IPv6) */
	hints.ai_socktype = SOCK_STREAM; /* TCP stream sockets */
	if ((status = getaddrinfo(argv[1], NULL, &hints, &res))) {
		fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(status));
		return 2;
	}
	printf("IP addresses for %s:\n\n", argv[1]);

	for(this = res; this != NULL; this = this->ai_next) {
		void *addr;
		char *ipver;
		if (this->ai_family == AF_INET) { /* IPv4 */
			struct sockaddr_in *ipv4;
			ipv4 = (struct sockaddr_in *)this->ai_addr;
			addr = &(ipv4->sin_addr);
			ipver = "IPv4";
		} else { /* IPv6 */
			struct sockaddr_in6 *ipv6;
			ipv6 = (struct sockaddr_in6 *)this->ai_addr;
			addr = &(ipv6->sin6_addr);
			ipver = "IPv6";
		}
		/* convert the IP to a string and print it */
		inet_ntop(this->ai_family, addr, ipaddr, sizeof(ipaddr));
		printf("%s:\t%s\n", ipver, ipaddr);
	}

	return 0;
}

```

## 绑定端口

` int bind(int sockfd, const struct sockaddr *addr,  socklen_t addrlen)` 服务端给自己绑定一个众所周知的地址。
1. 一个端口一般只能绑定一个socket。
2. 端口号必须大于1024，除非是root用户。

如果没有bind，在connect或者listen时系统会自动bind。这时候可以用其他函数来查询socket的地址。下面两个函数，一个查本地的地址，一个查远端的地址。
`int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen)` 查找一个本地的fd绑定的socket。
`int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen)` 查找一个本地的fd连接的远程socket。
下面这段代码给了一个获取远端socket地址的简短例子。
```c
// client
int rc;
int sockfd;

struct sockaddr_in addr;
addr.sin_addr.s_addr = inet_addr("127.0.0.1");
addr.sin_family = AF_INET;
addr.sin_port = htons(8888);

printf("Server ip=%s port=%d\n", inet_ntoa(addr.sin_addr), ntohs(addr.sin_port));

sockfd = socket(AF_INET, SOCK_STREAM, 0);
rc = connect(sockfd, (const struct sockaddr *)&addr, sizeof(struct sockaddr_in));

struct sockaddr_in svraddr;
socklen_t len = sizeof(struct sockaddr_in);
getsockname(sockfd,(struct sockaddr *)&svraddr, &len);
printf("Local #%d ip=%s port=%d\n", sockfd,
      inet_ntoa(svraddr.sin_addr), ntohs(svraddr.sin_port));

close(sockfd);
```

## 有连接的socket的准备工作

### 客户端 (socket-connect-write-read-close)
客户端的`write-read`这三步都是默认阻塞的。`socket-connect-close`会立即返回。
`int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen)` 连接一个指定的服务器。
1. 如果socket是`STREAM`或者`SEQPACKET`，那么通信前就要建立连接。当然，也可用于`DGRAM`，虽然没连接，但是这样不用每次都指定一个服务端地址。
2. connect会为`sockfd`指定的socket自动绑定一个端口。
3. connect遇到对方服务器忙时，会立即返回-1。如果此时socket是非阻塞模式，会把errno设为EINPROGRESS。
4. 如果connect失败，该socket可能变成**未定义**的。所以每次失败都必须关闭socket。
5. `addrlen`是前面地址的长度。比如普通的IPv4地址可能是一个`sockaddr_in`的大小。

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main(int argc , char *argv[])
{

    // socket
    int sockfd = 0;
    sockfd = socket(AF_INET , SOCK_STREAM , 0);

    if (sockfd == -1){
        printf("Fail to create a socket.");
    }

    // 服务端的地址
    struct sockaddr_in info;
    bzero(&info,sizeof(info));
    info.sin_family = PF_INET;
    info.sin_addr.s_addr = inet_addr("127.0.0.1");
    info.sin_port = htons(8700);
    
    // connect
    int err = connect(sockfd,(struct sockaddr *)&info,sizeof(info));
    if(err==-1){
        printf("Connection error");
    }
    
    // 发送消息
    char message[] = {"Hi there"};
    char receiveMessage[100] = {};
    send(sockfd,message,sizeof(message),0);
    recv(sockfd,receiveMessage,sizeof(receiveMessage),0);

    printf("%s",receiveMessage);
    printf("close Socket\n");
    close(sockfd);
    return 0;
}
```
### 服务端（socket-bind-listen-accept-read-write-close）
服务端的`accept-read-write`这三步都是默认阻塞的。`socket-bind-listen-close`会立即返回。
`int listen(int sockfd, int backlog)` 使得socket处于可以接收连接的状态。
1. `sockfd` 指明谁在listen。
2. `backlog`提示系统本线程还有多少连接需要建立。系统指定了等待连接的最大数量。如果队列满了，其他连接都会被丢弃。系统默认的net.core.somaxconn为128。

`int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen)` 接受一个连接。
1. `sockfd` 指明谁在accept。
2. `sockaddr`和`addrlen`会填充为接受到的连接地址和长度。（对端的）
3. 如果没有请求过来，会一直阻塞到有请求为止。如果此时socket是非阻塞模式，会立即返回-1，并把errno设为EWOULDBLOCK。

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main(int argc , char *argv[])

{
    //socket
    char inputBuffer[256] = {};
    char message[] = {"Hi,this is server.\n"};
    int sockfd = 0,forClientSockfd = 0;
    sockfd = socket(AF_INET , SOCK_STREAM , 0);

    if (sockfd == -1){
        printf("Fail to create a socket.");
    }

    // bind & listen
    struct sockaddr_in serverInfo,clientInfo;
    int addrlen = sizeof(clientInfo);
    bzero(&serverInfo,sizeof(serverInfo));
    serverInfo.sin_family = PF_INET;
    serverInfo.sin_addr.s_addr = INADDR_ANY;
    serverInfo.sin_port = htons(8700);
    
    bind(sockfd,(struct sockaddr *)&serverInfo,sizeof(serverInfo));
    listen(sockfd,5);
    
    // 收发消息
    while(1){
        forClientSockfd = accept(sockfd,(struct sockaddr*) &clientInfo, &addrlen);
        recv(forClientSockfd,inputBuffer,sizeof(inputBuffer),0);
        send(forClientSockfd,message,sizeof(message),0);
        printf("sended: %s\n", message);
    }
    return 0;
}
```
## 收发数据

`ssize_t send(int sockfd, const void *buf, size_t len, int flags)` 发送数据
1. 尽管可以使用write和read操作socket，但是send提供了更多的选项。
2. `buf`和`len`提供了发送的数据包。
3. `flags`提供了发送的选项。比如`MSG_DONTROUTE`不路由出本地，`MSG_DONTWAIT`允许非阻塞操作, `MSG_EOF` 写完后关闭服务端。
4. `send`会返回发送成功的字节数。如果send成功返回，则表示已经成功发送到了网络驱动程序上。如果失败，返回-1。
5. 对于字节流（TCP）协议，send会阻塞到报文传输完成。对于有报文最大长度限制的协议，send到达限制后会返回-1，设置错误码为EMSGSIZE。

`ssize_t sendto(int sockfd, const void *buf, size_t len, int flags, const struct sockaddr *dest_addr, socklen_t addrlen)` 和`send`功能一样，但是可以指定地址。


`ssize_t recv(int sockfd, void *buf, size_t len, int flags)`  接受数据
1. `buf`和`len`提供了发送的数据包。
2. `flags`提供了发送的选项。比如`MSG_PEEK`只会读取数据，但是不会改动，`MSG_DONTWAIT`允许非阻塞操作, `MSG_EOF` 写完后关闭服务端。
3. `recv`会返回接受到的字节数。如果对端已经调用shutdown或者协议已经自动关闭，recv会返回0。

`ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags, struct sockaddr *src_addr, socklen_t *addrlen)` 可以额外获取发送者的地址。地址会被写入`src_addr`对应的内存中。

