# [Linux]高级IO




# 如果有多个IO需要处理

当一个描述符读，然后又写到另一个描述符时，可以用循环的方式访问阻塞io：
```c
#include <stdio.h>
#include <unistd.h>
#define BUF_SIZE 128

int main(){
	char buf[BUF_SIZE];
	int n;
	while ( n = read(STDIN_FILENO, buf, BUF_SIZE) > 0) {
	        if (write(STDOUT_FILENO, buf, n) != n){
	                fprintf(stderr, "%s\n", "write error!");
	                break;
	        }
	}
	return 0;
}
```

但是如果要从两个fd读的时候，就不能用阻塞io去读了。因为进程阻塞在某个fd的时候，另一个fd即使输入了数据也无法处理。
比如一个telnet程序的输出有两个来源，用户输入回显和远端回包。如果阻塞在等待远端回包，用户输入就不会有回显了。解决这个问题就几种思路：
1. 再fork一个进程，每个进程处理一个fd。这看起来很好，但是处理EOF却成了问题。如果子进程先读到EOF，那么子进程终止，返回SIGCHLD给父进程，然后父进程终止。如果父进程读到EOF，父进程就需要通知子进程结束，此时需要额外的信号（如SIGUSER1）.
2. 用两个线程来处理，每个线程一个fd。同样的，处理线程之间的同步也会变的比较复杂。
3. 用`非阻塞的io`来轮询。先read一个fd，如果没数据立即返回，然后等待若干时间，然后再read下一个fd，直到某个fd有数据读为止。这个方法有两个缺点，一是频繁的read调用浪费了cpu时间，但是大部分时间是没数据读的。二是每次read返回后等待的时间不好确定，太久会读取不及时，太短会使得cpu更加繁忙。
4. 使用`异步IO`。当fd归属的设备准备好的时候，用信号通知处理进程。这个方法有两个缺点，一是信号在不同的系统上实现不同，移植性较差。二是进程收到的信号只有一种（SIGPOLL或者SIGIO），进程无法分辨是哪个fd。

有没有比较完善的方案？io多路复用来了。这种方案会记录一个我们需要的fd的列表，然后我们去查询，当这个列表中有fd有数据时，查询就会返回这个fd。

# IO多路复用：select

`int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);` select 函数提供了查询fd状态的能力。我们传入希望监听的fd，内核告诉我们哪些fd已经有事件发生并返回。
1. 参数 `timeout` 控制愿意等待的时间。timeval为NULL时，select会一直阻塞等待某个fd准备好。（如果接收到信号，select也会提前返回-1，并把errno设为INTR）
2. 参数 `readfds`, `writefds`, `exceptfds` 是我们告诉内核希望监听的fd的指针。如果希望监听某fd的读事件，就加入到`readfds`中。后面两个用于监听写事件和异常事件。
3. 返回时，`readfds`, `writefds`, `exceptfds` 中会留下对应事件已经就绪的fd。此时这些fd是可读的、可写的或发生异常的。
3. 参数 `nfds` 是三个fd集合中的最大值加一，它制定了fd的遍历范围。也可以把它设为`FD_SETSIZE`，一般为1024，但是这样会导致select遍历系统中所有的fd。
4. 返回值：a)如果没有就绪的fd，函数返回0。b)如果有就绪的fd，函数返回就绪的fd数量。c)如果收到信号，返回-1，并把errno设为INTR d)特别地，如果fd到达EOF，函数调用read，然后返回0
5. 函数`pselect`采用了timespec类型的超时设置。此外，还可以设置sigmask用来屏蔽一些信号，防止自己被终止。

`fd_set` 是一个fd的集合。在实现上是一个大bit数组，它只支持赋值操作和下面宏定义的操作：
```c
// 如果fd在fd_set中返回0
int  FD_ISSET(int fd, fd_set *set);

// 初始化fd_set
void FD_ZERO(fd_set *set);
// 设置某个fd
void FD_SET(int fd, fd_set *set);
// 清除某个fd
void FD_CLR(int fd, fd_set *set);
```
下面给了一个select的例子。他会等待输入五秒钟，如果有输入会立马回显。如果超时，则会直接退出。

```cpp
#include <stdio.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#define TIMEOUT 5       /* select timeout in seconds */
#define BUF_LEN 1024    /* read buffer in bytes */
int main( void )
{
	struct timeval	tv;
	fd_set		readfds;
	int		ret;
/* Wait on stdin for input. */
	FD_ZERO( &readfds );
	FD_SET( STDIN_FILENO, &readfds );
/* Wait up to five seconds. */
	tv.tv_sec	= TIMEOUT;
	tv.tv_usec	= 0;
/* All right, now block! */
	ret = select( STDIN_FILENO + 1,
		      &readfds,
		      NULL,
		      NULL,
		      &tv );
	if ( ret == -1 )
	{
		perror("select");
		return(1);
	} else if ( !ret )
	{
		printf("%d seconds elapsed.\n", TIMEOUT );
		return(0);
	}


/*
 *  * Is our file descriptor ready to read?
 *   * (It must be, as it was the only fd that
 *    * we provided and the call returned
 *     * nonzero, but we will humor ourselves.)
 *      */
	if ( FD_ISSET( STDIN_FILENO, &readfds ) )
	{
		char	buf[BUF_LEN + 1];
		int	len;
/* guaranteed to not block */
		len = read( STDIN_FILENO, buf, BUF_LEN );
		if ( len == -1 )
		{
			perror("read");
			return(1);
		}
		if ( len )
		{
			buf[len] ='\0';
			printf("read: %s \n", buf );
		}
		return(0);
	}
	fprintf( stderr,"This should not happen !\n");
	return(1);
}
```

# IO多路复用：poll

select有一些缺点。由于传入的fd的集合是一个bit数组，所以select必须得从0开始一直扫描到nfds指定的最大值，效率很低。poll优化了select的一些易用性的问题。

```cpp
int poll(struct pollfd *fds, nfds_t nfds, int timeout);

struct pollfd {
    int   fd;         /* file descriptor */
    short events;     /* requested events */
    short revents;    /* returned events */
};

// short events 定义
POLLIN 有数据可读。（和POLLRDNORM | POLLRDBAND 等价）
POLLRDNORM 有正常数据可读。
POLLRDBAND 有优先数据可读。
POLLPRI 有高优先数据可读。
POLLOUT 写操作不会阻塞。（和POLLWRNORM | POLLBAND 等价）
POLLWRNORM 写正常数据不会阻塞。
POLLBAND 写优先数据不会阻塞。
POLLMSG 有一个SIGPOLL消息可用。

POLLER 输入的fd有错误。
POLLHUP fd被挂起。（请注意，文件到达EOF，会返回POLLIN，然后read返回0）
POLLNVAL 输入的fd无效。

POLLIN | POLLPRI 对应select的读事件
POLLOUT | POLLWRBAND 对应select的写事件
```
poll 函数提供了一个select的改进版本。
1. 参数 `fds` 是一个`poolfd`的指针，或者一个数组（同时监听多个fd）。`poolfd`这个结构体包含三个参数，监视的文件描述符`fd`，关注的event事件类型`events`，和内核返回的fd的事件类型`revents` 。
2. 参数 `nfds` 告诉我们需要监听的fd数量，即参数 `fds` 的长度。
3. 参数 `timeout` 告诉我们等待多久超时，单位为ms。为-1时，poll永远不超时。为0时，poll立即返回。为正数时，poll等待对应的毫秒数。

那么到底poll有哪些改进？
1. poll优化了参数。a)无需调用者知道fd最大值加一是什么。b)而且不用每次调用前都初始化select的fdset（select会改变自己的fd集合参数）。
2. poll效率更高。它只会在参数里的几个fd中查询fd状态（这些fd放在也给链表中）。而select必须从0开始查询到fd最大值。因此poll不必局限于文件描述符的数量。
不过，select也提供了更为精确的超时时间，以及更好的可移植性。

下面给出了一个poll的例子。他会检测读写标准输入输出的可用状态并打印。
```c++
#include <stdio.h>
#include <unistd.h>
#include <poll.h>
#define TIMEOUT 5 /* poll timeout, in seconds */
int main( void )
{
	struct pollfd	fds[2];
	int		ret;
	/* watch stdin for input */
	fds[0].fd	= STDIN_FILENO;
	fds[0].events	= POLLIN;
	/* watch stdout for ability to write (almost always true) */
	fds[1].fd	= STDOUT_FILENO;
	fds[1].events	= POLLOUT;
	/* All set, block! */
	ret = poll( fds, 2, TIMEOUT * 1000 );
	if ( ret == -1 )
	{
		perror( "poll" );
		return(1);
	}
	if ( !ret )
	{
		printf( "%d seconds elapsed.\n", TIMEOUT );
		return(0);
	}
	if ( fds[0].revents & POLLIN )
		printf( "stdin is readable\n" );
	if ( fds[1].revents & POLLOUT )
		printf( "stdout is writable\n" );
	return(0);
}
// ./poll 时，poll会发现写此时可用。输出stdout is writable
// ./poll < a.txt poll会发现写此时读写都可用。输出stdout is writable stdin is readable
```


# IO多路复用：epoll

select主要缺陷是，对单个进程打开的文件描述是有一定限制的，它由FD_SETSIZE设置，默认值是1024，虽然可以通过编译内核改变，但相对麻烦，另外在检查数组中是否有文件描述需要读写时，采用的是线性扫描的方法，即不管这些socket是不是活跃的，我都轮询一遍，所以效率比较低。
poll本质和select没有区别，但其采用链表存储，解决了select最大连接数存在限制的问题，但其也是采用遍历的方式来判断是否有设备就绪，所以效率比较低，另外一个问题是大量的fd数组在用户空间和内核空间之间来回复制传递（每次调用poll都会拷贝），也浪费了不少性能。
我们用一种新的事件驱动技术epoll来解决上述问题。

## 初始化和注册事件：epoll_create / epoll_ctl

`int epoll_create(int size)` 创建一个epoll实例，返回该实例的fd。
1. 参数`size`为估计的处理fd数量，越精确性能越高。Linux 2.6后不在使用该参数
2. 成功时，返回fd。失败时，返回-1，并设置errno。
3. 返回的fd和要处理的fd没有关联，只是用来调用epoll。

`int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event)` 在一个epoll中添加监听的fd和对应的时间类型
1. 参数`epfd`为上面create返回的epollfd
2. 参数`op`有几个值：`EPOLL_CTL_ADD` 添加fd，`EPOLL_CTL_DEL` 删除fd，`EPOLL_CTL_MOD` 改变fd监听类型。
3. 参数`fd`是监听的fd对象。
4. 参数`event`见下面的代码块。
5. 成功后，epoll_ctl返回0 。失败时，返回-1，并设置errno。

```c++
typedef union epoll_data {
    void        *ptr;
    int          fd;
    __uint32_t   u32;
    __uint64_t   u64;
} epoll_data_t;

struct epoll_event {
    __uint32_t   events;      /* Epoll 事件类型，见下面 */
    epoll_data_t data;        /* 用户存储数据，稍后会返回 */
};

// Epoll 事件类型       
EPOLLIN 文件可读
EPOLLOUT 文件可写
EPOLLPRI 高优先级文件可读
EPOLLET 设置为边沿触发，默认为水平触发。
EPOLLHUP 文件挂起。默认会监听
EPOLLERR 文件出错。默认会监听
EPOLLONESHOT 一次性监听，有事件发生并处理后不再监听该文件。

// 下面是一个关联事件类型的样例
struct epoll_event event;
event.data.fd = fd;
event.events = EPOLLIN | EPOLLOUT;
int ret = epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &event);
if(ret != 0) perror("epoll_ctl")
```

## 监听事件：epoll_wait

`int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout)` 等待某个epoll上的fd发生事件，时限为timeout毫秒。
1. 参数`epfd`为需要等待的epollfd
2. 参数`events`为返回的事件的地址。也可以是一个数组。
3. 参数 `maxevents` 表明返回的事件数量不能超过该值，一般时数组的长度。
4. 参数 `timeout` 告诉我们等待多久超时，单位为ms。为-1时，poll永远不超时。为0时，poll立即返回。为正数时，poll等待对应的毫秒数。

下面时一个完整的wait样例。
```c++
#define MAX_EVENTS 64
struct epoll_event	*events;
int	nr_events, i, epfd;
events = malloc( sizeof(struct epoll_event) * MAX_EVENTS );
if ( !events )
{
	perror( "malloc" );
	return(1);
}
nr_events = epoll_wait( epfd, events, MAX_EVENTS, −1 );
if ( nr_events < 0 )
{
	perror( "epoll_wait" );
	free( events );
	return(1);
}
for ( i = 0; i < nr_events; i++ )
{
	printf( "event=%ld on fd=%d\n",
		events[i].events,
		events[i].data.fd );
	/*
	 * We now can, per events[i].events, operate on
	 * events[i].data.fd without blocking.
	 */
}
free( events )
```

## 边沿触发和水平触发

### 两种触发的区别

epoll默认的工作方式是水平触发。在水平触发模式下，只要满足fd可读/写，每次调用epoll_wait都会返回这个fd。在边沿触发模式下，只有fd从不可读(写)变为可读(写)时，才会返回这个fd。（读缓冲区有数据就是可读，写缓冲区不满就是可写）

考虑下面的情况，两种触发模式的epoll都监听了读缓冲区：
1. 读缓冲区刚开始是空的
2. 读缓冲区写入2KB数据
3. 水平触发和边缘触发模式此时都会发出可读信号
4. 收到信号通知后，读取了1kb的数据，读缓冲区还剩余1KB数据
5. 水平触发会再次进行通知，而边缘触发不会再进行通知
所以，边缘触发需要一次性的把缓冲区的数据读完为止，也就是一直读，直到读到EGAIN为止，EGAIN说明缓冲区已经空了，因为这一点，边缘触发需要设置文件句柄为非阻塞。

```c++
//水平触发LT
ret = read(fd, buf, sizeof(buf));

//边缘触发ET
while(true) {
    ret = read(fd, buf, sizeof(buf);
    if (ret == EAGAIN) break;
}
```

### 两种触发的使用方法

参考 <a href="https://blog.csdn.net/dongfuye/article/details/50880251"> dongyue-epoll LT/ET 深入剖析</a>

LT的处理过程：
. accept一个连接，添加到epoll中监听EPOLLIN事件
. 当EPOLLIN事件到达时，read fd中的数据并处理
. 当需要写出数据时，把数据write到fd中；如果数据较大，无法一次性写出，那么在epoll中监听EPOLLOUT事件
. 当EPOLLOUT事件到达时，继续把数据write到fd中；如果数据写出完毕，那么在epoll中关闭EPOLLOUT事件

ET的处理过程：
. accept一个一个连接，添加到epoll中监听EPOLLIN|EPOLLOUT事件
. 当EPOLLIN事件到达时，read fd中的数据并处理，read需要一直读，直到返回EAGAIN为止
. 当需要写出数据时，把数据write到fd中，直到数据全部写完，或者write返回EAGAIN
. 当EPOLLOUT事件到达时，继续把数据write到fd中，直到数据全部写完，或者write返回EAGAIN

使用ET模式，特定场景下会比LT更快，因为它可以便捷的处理EPOLLOUT事件，省去打开与关闭EPOLLOUT的`epoll_ctl(EPOLL_CTL_MOD)`调用。从而有可能让你的性能得到一定的提升。

例如你需要写出1M的数据，写出到socket 256k时，返回了EAGAIN, 然后：
1. ET模式下，当再次epoll返回EPOLLOUT事件时，继续写出待写出的数据，当没有数据需要写出时，不处理直接略过即可。
2. LT模式则需要先打开EPOLLOUT，当没有数据需要写出时，再关闭EPOLLOUT（否则会一直返回EPOLLOUT事件）

总体来说，ET处理EPOLLOUT方便高效些，LT不容易遗漏事件、不易产生bug如果server的响应通常较小，不会触发EPOLLOUT，那么适合使用LT，例如redis等。而nginx作为高性能的通用服务器，网络流量可以跑满达到1G，这种情况下很容易触发EPOLLOUT，则使用ET。


## 和select/poll 相比

<a href="https://cloud.tencent.com/developer/article/1373483"> 各种IO复用模型的比较-云社区 </a>

epoll和kqueue （FreeBSD上和epoll类似的组件）是更先进的IO复用模型。比起select和poll来说：
1. 没有最大连接数的限制。1G内存，可以打开约10万左右的连接。而且仅仅使用一个文件描述符，就可以管理多个文件描述符。
2. 内核拷贝只在初始化后发生一次。将用户关系的文件描述符的事件存放到内核的一个事件表中（底层采用的是mmap的方式），这样在用户空间和内核空间的copy只需一次。
3. 复杂度O(1)。这种模型里面，采用了类似事件驱动的回调机制或者叫通知机制，在注册fd时加入特定的状态，一旦fd就绪就会主动通知内核。这样以来就避免了select的无脑遍历socket的方法，这种模式下仅仅是活跃的socket连接才会主动通知内核，所以直接将时间复杂度降为O(1)。

