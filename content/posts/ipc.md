---
title: "[Linux]进程间通信"
date: 2019-08-01T20:26:09+08:00
lastmod: 2019-08-06T20:51:39+08:00
tags: ["Linux", "AUPE"]
categories: ["Linux"]
description: "使用进程间通信来完成信息互换是很常见的场景。本文介绍了指令形式的通信（信号、信号量），文本形式的通信（共享内存，管道，FIFO，Unix域套接字）来完成这一基本的任务。"
---



# 管道
 
管道是进程间通信的最古老方式。它通过共享文件来完成进程间的通信。它有两个局限性：
1. 它是半双工的。数据只能从一个进程流向另一个进程。
2. 通信的进程之间必须另一个进程是fork出来的。通常，一个进程会创建一个管道，然后执行fork，这样管道就会在两个进程之间共享。
FIFO解决了第一种局限性，Unix域套接字解决了第二种。我们先来看管道。

`int pipe(int pipefd[2]);`管道由pipe函数创建。
1. 参数`pipefd`是一个两个元素的数组。`pipefd[0]`用来读，`pipefd[1]`用来写。
2. 成功返回0 。失败返回-1并设置errno。
3. 单进程的管道没有任何用处。在这个函数之后一般会fork，然后一个进程来写`pipefd[1]`，一个进程来读`pipefd[0]`。他们的另一个fd元素将会被关闭。

下面是一段实例, 父进程通过管道向子进程传递了信息，子进程接收并把他们输出：
```c++
#include "apue.h"

int main(void)
{
	int		n;
	int		fd[2];
	pid_t	pid;
	char	line[MAXLINE];

	if (pipe(fd) < 0)
		err_sys("pipe error");
	if ((pid = fork()) < 0) {
		err_sys("fork error");
	} else if (pid > 0) {		/* parent */
		close(fd[0]);
		write(fd[1], "hello world\n", 12);
	} else {					/* child */
		close(fd[1]);
		n = read(fd[0], line, MAXLINE);
		write(STDOUT_FILENO, line, n);
	}
	exit(0);
}
```


`FILE *popen(const char *command, const char *type)` 函数popen执行一个命令，然后返回这个命令的文件指针。
1. `type`参数为'r'，表示这个文件可读，如果是'w'，表示可写。
2. `command`参数是要执行的命令
3. 使用完用`int pclose(FILE *stream)`关闭管道。
4. 这个函数是管道实现的一个例子。它先创建一个管道，然后fork一个子进程，关闭未使用的管道端（读或写），然后在子进程执行命令，最后等待执行完毕。

# FIFO

`int mkfifo(const char *pathname, mode_t mode)`提供了任意进程间通过文件通信的方式。
1. 参数`path`表示管道的路径。
2. 参数`mode`和`open`函数的模式一样。


`int mkfifoat(int dirfd, const char *pathname, mode_t mode)`提供了更多选择的路径控制。

## FIFO用于复制输出流
下面的命令展示了复制输出流的方法。输入文件先到达prog1，然后通过tee命令复制给fifo和prog2。fifo中的数据会流到prog3。
```bash
mkfifo fifo1
prog3 < fifo1 &
prog1 < infile | tee fifo1 |prog2
```

 ## FIFO用于服务端和客户端通信

使用FIFO可以用来做服务端-客户端通信。服务端提供一个FIFO让客户端写入，这样就可以接收到客户端的请求。那么如何响应客户端？可以让客户端在请求中携带进程ID，然后服务端为每个客户端都创建一个FIFO（和客户端约定好路径），然后让客户端从中读取。
这种方法有些问题：
1. 客户端可能随时进程消失，FIFO没有被回收
2. 客户端发起单向调用就终止时，FIFO没有被回收（监听SIGPIPE可以解决）
3. 客户进程从1变成0时，服务端需要处理EOF（请求FIFO可以设为读-写模式解决）

# XSI IPC

## IPC标识符

进行进程间通信，必须要有一个编号来表明所用的资源（IPC对象）是哪个。在Linux中，IPC标识符是一个key_t类型（一般实现为长整型，从0开始分配，每有一个IPC对象就加一，直到最大值后又从0开始）。使用IPC操作必须提供这个IPC标识符，那么不同进程如何共享这个标识符呢？

### ftok

`key_t ftok(const char *pathname, int proj_id)` 通过ftok函数，不同进程可以产生相同的key。
1. 参数 `pathname` 是进程间约定的已经存在的文件路径。
2. 参数 `proj_id` 是约定的0-255的值，也是一个约定的项目id。
3. 事实上，ftok取了`pathname`中文件的设备编号`st_dev`的低8bit、文件iNode`st_ino`的低16bit，和`proj_id`的低8bit合并成了返回的`key_t`值。
4. 这意味着如果文件在使用中被删除并重建，key会发生变化。如果`proj_id`一致，也有可能造成冲突。

### IPC_PRIVATE

`IPC_PRIVATE` 实际上是定义的值是0 。用这个做key时，系统将会产生一个新的IPC对象。一般用于不同进程间不需要约定key的时候，比如父进程在获得对象后传承给子进程。

### IPC 权限

所有的IPC对象都有一个权限字段来标识所属的线程。一般IPC对象只能由创建的进程或者超级权限进程来删除。这个权限信息里记录了一些创建者的信息。uid、gid、mode三个字段可以由用户通过msgctl、shmctl、semctl等函数来修改。修改者必须是创建进程或者超级权限进程。
`mode` 字段有一些特定的值表示权限，类似文件的`chmod`。下面给出了该字段每一位的含义。
```c++
struct ipc_perm {
    key_t          __key;    /* Key supplied to shmget(2) */
    uid_t          uid;      /* Effective UID of owner */
    gid_t          gid;      /* Effective GID of owner */
    uid_t          cuid;     /* Effective UID of creator */
    gid_t          cgid;     /* Effective GID of creator */
    unsigned short mode;     /* Permissions + SHM_DEST and SHM_LOCKED flags */
    unsigned short __seq;    /* Sequence number */
};
// mode字段
0400 用户读
0200 用户写
0040 组读
0020 组写
0004 其他读
0002 其他写
```

### IPC的缺点

1. IPC不会主动回收资源。IPC是系统来维护的，没有引用计数。如果一个进程在一个消息队列中添加了消息然后终止，系统不会删除这些消息，直到下个进程显示地使用或删除他们。
PIPE会在最后一个使用的进程终止后自动销毁。FIFO虽然在最后一个使用的进程结束后会保留名字，但是其中的数据会删除。
2. IPC在文件系统中没有名字。Linux是一切皆文件的，没有文件描述符有几个麻烦：a)无法ls，rm，chmod，无法像操作文件一样操作IPC对象，只能用其特定的函数。b)没办法使用select，poll这样的多路复用技术，这将导致进程无法同时监听两个消息队列。

## 消息队列

`int msgget(key_t key, int msgflg)`创建一个msg对象。
1. `key`可以是`IPC_PRIVATE`或者一个存在的IPC的key。
2. `msgflg`提供了创建消息队列的选项。a)为0时返回`key`的消息队列的标识符，不存在会报错 b) `PC_CREAT`：当msgflg&IPC_CREAT为真时，则新建一个消息队列；如果存在这样的消息队列，返回此消息队列的标识符 c) `IPC_CREAT|IPC_EXCL` 不存在则创建一个key的消息队列，存在则返回错误。
3. 成功返回消息队列的标识符，失败返回-1，并写errno。

`int msgctl(int msqid, int cmd, struct msqid_ds *buf)` 读写msg对象的属性
1. `msqid`是一个消息队列的标识符。
2. `cmd` 提供了读写的选项。a) `IPC_STAT` 读取属性到buf中。 b) `IPC_SET` 写入属性到buf中 c) `IPC_RMID` 删除消息队列和队列中的所有消息。删除前会用`msg_perm`校验归属。
3. `buf` 是设置的详情，见下表。

```c++
struct msqid_ds {
	struct ipc_perm msg_perm;     // Ownership and permissions 权限，初始化时填0 
	time_t          msg_stime;    // Time of last msgsnd(2) 初始化时填0 
	time_t          msg_rtime;    // Time of last msgrcv(2) 初始化时填0 
	time_t          msg_ctime;    // Time of last change 初始化时设置为当前时间 
	unsigned long   __msg_cbytes; // Current number of bytes in queue (non-standard)  
	msgqnum_t       msg_qnum;     // Current number of messages in queue 初始化时填0 
	msglen_t        msg_qbytes;   // Maximum number of bytes allowed in queue 初始化时填系统值MSGMNB 
	pid_t           msg_lspid;    // PID of last msgsnd(2) 初始化时填0  
	pid_t           msg_lrpid;    // PID of last msgrcv(2) 初始化时填0  
};
```

`int msgsnd(int msqid, const void *msgp, size_t msgsz, int msgflg)` 发送消息。如果消息队列已满，会阻塞等待。
1. 参数`msqid` 是发送消息的消息队列
2. 参数`msgp` 发送给队列的消息。msgp可以是任何类型的结构体，但第一个字段必须为long类型，即表明此发送消息的类型。msgp定义的参照格式如下：
```c++
struct s_msg{ /*msgp定义的参照格式*/
	long type; /* 必须大于0,消息类型 */
	char mtext[256]; /*消息正文，可以是其他任何类型*/
} msgp;
```
3. 参数`msgsz` 要发送消息的大小, 其中不含消息类型的4个字节。
4. 参数`msgflg` 设置发送的模式。`IPC_NOWAIT`类似一个非阻塞IO，写不进消息队列也会立即返回`IPC_NOERROR` 如果消息超过长度限制`msgsz`，会截断消息。
5. 成功返回0，失败返回-1，设置errno。EAGAIN 消息队列已满，EIDRM 消息队列已删除，EACCESS 无权限写入， EINVAL 参数错误。
6. msgsnd会一直阻塞等待，直到 a) 消息队列有空余 b) 消息队列被删除 c) msgsnd函数被信号中断。

`size_t msgrcv(int msqid, void *msgp, size_t msgsz, long msgtyp, int msgflg)` 会读取消息存入`msgp`指针，然后把消息从队列中删除。在此之前，此函数会一直阻塞。
1. 参数`msqid` 是接收消息的消息队列
2. 参数`msgp` 存放读出来的消息。结构体必须和上面的发送结构体相同。
3. 参数`msgsz` 读出来消息的大小, 其中不含消息类型的4个字节。
4. 参数`msgtyp`  a) 为0表示读第一个消息 b) 大于0表示读消息类型等于本参数的第一个消息 c) 小于0表示读消息类型小于等于本参数绝对值的第一个消息
5. 参数`msgflg` 设置读的模式。`IPC_NOWAIT`类似一个非阻塞IO，没有消息可读也会立即返回，此时错误为 ENOMSG。`IPC_NOERROR` 如果消息超过长度限制`msgsz`，会截断消息。
6. 成功返回消息长度，失败返回-1，设置errno。E2BIG 消息数据长度大于msgsz而msgflag没有设置IPC_NOERROR 。

下面给出了一个两个进程间通过消息队列通信的样例。由于消息队列创建后不会自动删除，需要运行`ipcrm -q msqid`来手动删除队列。
```c++
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#include  <time.h>
#define TEXT_SIZE  512

struct msgbuf {
    long mtype;
    int  status;
    char time[20];
    char mtext[TEXT_SIZE];
}
;
char  *getxtsj() {
    time_t  tv;
    struct  tm   *tmp;
    static  char  buf[20];
    tv = time( 0 );
    tmp = localtime( &tv );
    sprintf( buf, "%02d:%02d:%02d", tmp->tm_hour, tmp->tm_min, tmp->tm_sec );
    return   buf;
}
int main( int argc, char **argv ) {
    int msqid;
    struct msqid_ds info;
    struct msgbuf buf;
    struct msgbuf buf1;
    int flag;
    int sendlength, recvlength;
    int key;
    key = ftok( "msg.tmp", 0x01 );
    if ( key < 0 ) {
        perror( "ftok key error" );
        return(-1);
    }
    msqid = msgget( key, 0600 | IPC_CREAT );
    if ( msqid < 0 ) {
        perror( "create message queue error" );
        return(-1);
    }
    buf.mtype = 1;
    buf.status = 9;
    strcpy( buf.time, getxtsj() );
    strcpy( buf.mtext, "happy new year!" );
    sendlength = sizeof(struct msgbuf) - sizeof(long);
    flag = msgsnd( msqid, &buf, sendlength, 0 );
    if ( flag < 0 ) {
        perror( "send message error" );
        return(-1);
    }
    buf.mtype = 3;
    buf.status = 9;
    strcpy( buf.time, getxtsj() );
    strcpy( buf.mtext, "good bye!" );
    sendlength = sizeof(struct msgbuf) - sizeof(long);
    flag = msgsnd( msqid, &buf, sendlength, 0 );
    if ( flag < 0 ) {
        perror( "send message error" );
        return - 1;
    }
    system( "ipcs -q" );
    return(0);
}
```

接受消息：
```c++
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#define TEXT_SIZE  512
struct msgbuf {
    long mtype ;
    int  status ;
    char time[20] ;
    char mtext[TEXT_SIZE] ;
}
;
int main(int argc, char **argv) {
    int msqid ;
    struct msqid_ds info ;
    struct msgbuf buf1 ;
    int flag ;
    int  recvlength ;
    int key ;
    int mtype ;
    key = ftok("msg.tmp", 0x01 ) ;
    if ( key < 0 ) {
        perror("ftok key error") ;
        return -1 ;
    }
    msqid = msgget( key, 0 ) ;
    if ( msqid < 0 ) {
        perror("get ipc_id error") ;
        return -1 ;
    }
    recvlength = sizeof(struct msgbuf) - sizeof(long) ;
    memset(&buf1, 0x00, sizeof(struct msgbuf)) ;
    mtype = 1 ;
    flag = msgrcv( msqid, &buf1, recvlength ,mtype,0 ) ;
    if ( flag < 0 ) {
        perror("recv message error\n") ;
        return -1 ;
    }
    printf("type=%d,time=%s, message=%s\n", buf1.mtype, buf1.time,  buf1.mtext) ;
    system("ipcs -q") ;
    return 0 ;
}
```

## 信号量

信号量是一个计数器，用于控制多个进程对资源的访问。当一个进程访问信号量控制的资源时，以以下步骤执行：
1. 取信号量的值。如果值是正，则进程可以继续执行。进程访问资源，并把信号量的值减一，表示他占用了一个资源。
2. 如果值是0，进程会休眠，直到信号量的值大于0，进程被唤醒，再执行1。
3. 当进程释放资源时，信号量值加一，并唤醒正在等待的进程。

实际上，XSI中的信号量要复杂一些，他有几个缺点：
1. 信号量并非是一个数值，而是一个多个值的集合。创建时要指定值的数量。
2. 信号量的创建和初始化是分开的，并非一个原子操作。这样就没法原子地创建一个信号量。
3. 即使已经没有进程再使用信号量，他们依然不会销毁。

关于信号量不再展开描述，参见 <a href="https://blog.csdn.net/ljianhui/article/details/10243617">Linux进程间通信——使用信号量</a>


## 共享内存

进程间通信最方便的方法，就是一起读写内存。由于进程不需要把这块内存复制到自己的进程空间内，所以共享内存的方法非常快。需要注意的是，在一个进程写内存的时候，其他进程不能操作这块内存。这里可以用记录锁、信号量或者互斥量来同步。

通过`mmap`把文件映射到内存中也是一种共享内存的实现。于这种方式不同的是，XSI中的共享内存没有文件映射，是一个内存的匿名段。

`int shmget(key_t key, size_t size, int shmflg)` 用于创建一个共享内存。
1. `key`可以是`IPC_PRIVATE`或者一个存在的共享内存的key（可能是ftok生成）。
2. `size` 表示要创建的共享内存的大小，必须为内存页大小的整数倍。如果是读取线程获取已经存在的共享内存，填0。
3. `shmflg`提供了创建消息队列的选项。a)为0时返回`key`的共享内存的标识符，不存在会报错 b) `IPC_CREAT`：当`shmflg&IPC_CREAT`为真时，则新建一个共享内存；如果存在这样的共享内存，返回此共享内存的标识符 c) `IPC_CREAT|IPC_EXCL` 不存在则创建一个key的共享内存，存在则返回错误。
4. 成功返回0，失败返回-1。`EINVAL` 参数size小于SHMMIN或大于SHMMAX。`EEXIST` 预建立key所指的共享内存，但已经存在。 `EIDRM`参数key所指的共享内存已经删除。 `ENOSPC`超过了系统允许建立的共享内存的最大值(SHMALL)。 `ENOENT`参数key所指的共享内存不存在，而参数shmflg未设IPC_CREAT位。`EACCES`没有权限 `ENOMEM` 核心内存不足。

`int shmctl(int shmid, int cmd, struct shmid_ds *buf)` 设置共享内存。
1. 参数 `shmid`是共享内存的id 。
2. 参数 `cmd` 指定了本次操作的行为。`IPC_STAT` 得到共享内存的状态，把共享内存的`shmid_ds`结构复制到buf中。`IPC_SET`改变共享内存的状态，把buf所指的`shmid_ds`结构中的uid、gid、mode复制到共享内存的`shmid_ds`结构内`IPC_RMID`删除这片共享内存。
3. 参数 `shmid_ds`是一些共享内存的设置。创建新字段时，应按照下面的初始化设置进行初始化。
```c++
struct shmid_ds {
	struct ipc_perm shm_perm;    // Ownership and permissions 权限初始化
	size_t          shm_segsz;   // Size of segment (bytes) 初始化设置为请求的size
	time_t          shm_atime;   // Last attach time 初始化设置为0
	time_t          shm_dtime;   // Last detach time 初始化设置为0
	time_t          shm_ctime;   // Last change time 初始化设置为当前时间
	pid_t           shm_cpid;    // PID of creator 
	pid_t           shm_lpid;    // PID of last shmat(2)/shmdt(2) 初始化设置为0
	shmatt_t        shm_nattch;  // No. of current attaches 初始化设置为0
	...
};
```

`void *shmat(int shmid, const void *shmaddr, int shmflg)` 连接指定id的共享内存。连接后，这片共享内存就可以在进程空间内访问。
1. 参数`shmid`是共享内存的id。
2. 参数`shmaddr`指定本进程内内存的地址，之后这片地址会映射到共享内存。如果设为NULL，由系统决定地址（没有特殊需要就设为NULL）。
3. 参数`shmflg` 提供了一些选项。`SHM_RDONLY` 为只读模式，其他为读写模式。
4. 成功返回连接的本进程内存地址，失败返回-1。
5. 函数fork后，子进程会继承已连接的这片地址。exec后，子进程会和这片共享内存结束连接。

`int shmdt(const void *shmaddr)` 结束这片共享内存的映射。
1. 参数`shmaddr`指定本进程内内存的地址，是上面的`shmat`返回的。
2. 成功返回0，失败返回-1。
3. `shmdt`执行后，`shm_nattch`会减一。

