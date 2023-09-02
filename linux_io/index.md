# [Linux]文件和零拷贝




## 文件

### 文件描述符
1. 文件描述符：在Linux中，所有的文件都是通过文件描述符引用。fd是一个非负整数。按照惯例，标准输入的fd是0，标准输出的fd是1，标准错误的fd是2。分别作为`STDIN_FILENO`、`STDOUT_FILENO`、`STDERR_FILENO`定义在unistd中。
2. 文件描述符的上限：fd的范围是 `0 ~ OEPN_MAX-1` 。OPEN_MAX一般是20或者64。这代表一个进程最多打开19或63个文件。

### 文件内核API
1. 文件的打开：`int open(const char *pathname, int flags)`参数填上要打开的文件的名字（甚至可以不存在），会返回打开的fd。下面是一些常用的选项：
```
O_APPEND 文件将以追加模式打开，每次写操作之前，文件偏移量都会置于文件末尾。
O_CREAT 创建文件。如果文件已经存在，则会直接打开。
O_EXCL 和上面的O_CREAT联用时，表示如果文件已经存在，就会失败。可以保证多进程同时创建文件的原子操作。
O_SYNC 打开文件用于同步I/O。在数据写到磁盘之前写操作不会完成；一般的读操作已是同步的，所以这个标志对读操作没有影响。
O_NONBLOCK 如果可以，文件将在非阻塞模式下打开。任何其它操作都不会使该进程在I/O中阻塞。这种情况可能只用于FIFO。
O_DIRECT 打开文件用于直接I/O。将会绕过缓冲区操作。
```
2. 文件的关闭：`int close(int fd)` 关闭一个文件会释放上面所有的记录锁。一个进程终止后，内核会自动关闭它打开的所有文件。
5. 文件定位： `off_t lseek(int fd, off_t offset, int whence)` 参数whence指定了偏移地址（开始点`SEEK_SET` 当前点`SEEK_CUR` 结束点`SEET_END`），另一个参数offset是从参考点开始的偏移量（可正可负）。返回新的偏移地址。
6. 空洞文件：如果写入一部分之后lseek到后面去写入，中间就会产生一个空洞，实际不占用磁盘大小。
7. 文件读取：`ssize_t read(int fd, void *buf, size_t nbytes)` 返回读取到的字节数。下面的情况可能使得读取到的字节数少于需要的字节数： 1)再读这么多就到了文件尾 2)读网络缓冲区读完 3)读FIFO管道包含的字节少于需要的长度 4)读终端设备，一次一行
8. 文件写入：`ssize_t write(int fd, const void* buf, size_t nbytes)` 返回写入的字节数。一般和nbytes相同。
9. 文件属性编辑：`int fcntl(int fd, int cmd, ... /* arg */ )` 提供了编辑fd属性标志的方法。


### read buf该设置多大
在Linux ext4系统上，磁盘块长度`st_blksize`为4096字节。测试表明，在4096的整数倍上，读磁盘有更快的速率，可以根据需要选择4096或8192等字节的buf。
系统为了优化频繁写磁盘的情况，会使用预读取（read ahead）技术，在检测到顺序读时，会比本次读取需要的读出更多的数据，读入缓冲区。

### 文件结构

要设计一个多线程读取文件的程序，必须先知道文件和线程的关系。内核用3张表表示打开的文件，他们分别是：
1. 进程中的文件表，记录着进程打开的所有文件。每个文件用了一个**fd标志**和一个**文件指针**（指向2）表示。
2. 内核为每个进程打开的每个文件创建了一个文件表，包含了**文件状态标志**、**文件偏移量**和**i-node指针**。需要注意不同进程打开了不同文件的时候，会有两个文件表。所以并发读取是安全的。
3. 每个文件都对应一个`i-node`。这个node里包含了文件的磁盘块位置、**文件的长度**、拥有者、权限等。这些信息会被读入内存。

Note1：磁盘划分为数据区和`i-node`区，一般每4个块（一个块为4K，8个扇区）就会有一个`i-node`，占地256字节。每创建一个文件，系统就分配一个`i-node`给文件，并把文件名和`i-node`编号关联起来。查找的时候，根据文件名找到编号，再找到文件的磁盘位置。
Note2：每次write完毕，内核文件表2中的文件偏移量都会增加写入的字节数。如果此时文件的偏移量大于`i-node`记录的文件长度，`i-node`记录会被更新为这个偏移量（文件变长）。
Note3：O_APPEND会被写内核文件表2中的文件状态标志中。这样，每次write发现这个标志，都会先把文件偏移量设置为i-node的文件长度，这样就可以写到尾端。
Note4：lseek只改变内核文件表2的文件偏移量，不进行任何I/O操作。
Note5：如果子进程是父进程fork出来的，那么他们会共享2中的内核文件表。

这三个表的关系如下图所示。下面有两个进程打开了同一文件：

![文件表](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/aupe/file_1.png)

### 原子操作

假设有两个进程要不断往一个日志文件的结尾添加日志。你可能写出下面的代码：
```cpp
if (lseek(fd, OL, 2) < 0)error("lseek error");
if (write(fd, buf, 100) < 0)error("write error");
```
即使linux保证了他的系统调用是原子的，但是还是肯能发生如下的操作序列：
1. A进程seek到文件尾，文件长度1500，偏移量1500。
2. B进程seek到文件尾，文件长度1500，偏移量1500。
3. B进程write 100字节，从1500开始写，文件长度1500->1600。
4. A进程write 100字节，从1500开始写，覆盖了B的写入。
Linux提供了下面的原子函数，结合了lseek和读写，保证了这种操作的原子性。
```
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
```
另一种方式是采用`O_APPEND`。这种模式保证了每次写的时候偏移量都在文件尾，所以不同竞争进程间不会为了偏移量相互影响。一些开源软件的日志就是这么实现的。

除了这个例子外，`O_EXCL`也用于打开文件时保证原子性。如果没有这个标志，一个进程创建文件可能会分为**检查文件是否存在**、**创建文件**两步，有可能发生重复创建导致数据丢失的情况。


## 内核的I/O Cache

read和write操作如果相当频繁，一方面会带来频繁的系统调用，另一方面，读写磁盘的效率远远跟不上。所以unix系统在I/O方面做了内核的优化，一方面用缓冲区削峰，把write调用再内存中整合后再写入磁盘（一般是list结构），另一方面把热点数据也缓存在内存中，使得read调用大部分都命中内存而不是磁盘（一般是hashmap）。

### 缓冲区缓存 Buffer Cache
unix系统中最朴素的I/O加速技术就是缓冲区。在调用write时，内核将数据拷贝到缓冲区中，然后排入队列，晚些时候一起写入磁盘。这种方法称为延迟写（delayed write）。延迟写可能有一些问题需要担心：
1. 此时read会不一致吗？如果一个read调用在写入磁盘前读取还未刷盘的这部分数据，内核将从缓冲区中读取，而不是读取磁盘上陈旧的数据。
2. 会改变写顺序吗？内核将会把缓冲区队列的数据重新安排，所以写顺序会被改变。但是，写的位置并不会改变，很少有对写顺序有要求的程序。
3. 刷盘时错误怎么办？刷盘错误程序不会感知，所以比如掉电等故障中没刷盘成功的数据会丢失。内核一般会用10ms的间隔来刷盘保证丢失的数据不会太多。

以下两个条件会触发刷盘：
1. 当空闲内存小于设定的阈值时，脏的缓冲区就会回写到磁盘上，被清理的缓冲区可能会被移除，来释放内存空间。
2. 当一个脏的缓冲区寿命超过设定的阀值时（一般为10ms），缓冲区被回写至磁盘。以此来避免数据的不确定性。

### 页缓存 Page Cache
相比起CPU而言，现在的磁盘速度远远落后。所以主存中会存有一份磁盘中常用数据的拷贝，以便于以后操作只操作主存，减少磁盘访问。那放哪些数据进去呢？这是一些思考：
1. 时间局部性：该方法的思考是，刚被访问的资源很可能会在不久后再次被访问。页缓存是内核寻找文件系统数据的第一目的地。只有缓存中找不到时内核，才会调用存储子系统从磁盘中读取数据。当数据第一次读取后，就会从磁盘读
入页缓存中，并从缓存中返回给应用。如果那项数据被再次读取，就直接从缓
2. 空间局部性：是关于数据的连续使用的性质。基于这个原理，内核实现了页缓存预读技术。预读是在每次读请求时从磁盘数据中读取更多的数据到页缓存中的动作一—多读一点点会很有效。当内核从磁盘读取一块数据时，也会读取接下来一两块数据。一次读取较大的连续数据块时磁盘不需要经常寻道，所以会比较有效。

### Cache的同步
#### 主动刷盘 fsync
同步I/O函数提供了针对单文件的主动刷盘：
```
// 把缓冲区刷盘
void sync(viod);
// 把某个fd的文件属性和文件刷盘
int fsync(int fd);
// 把某个fd的文件刷盘
int fdatasync(int fd);
```

#### 主动刷盘 O_SYNC
`O_SYNC`看起来就像是在每个write操作后都隐式地执行fsync。尽管这在语法上是毫无问题的，但Linux内核实现的O_SYNC效率会更高。
`O_SYNC` 根据写入文件的大小，可能会使大量的时间消耗在进程的I/O等待时间上，此时的O_SYNC会使总耗时增加一到两个数量级。这种时间开销增长是非常可观的，所以同步I/O一般是在无计可施情况下的最后选择。一般情况下在关键操作之后使用fsync会更加合理。


#### 直接IO
内核的I/O Cache给我们带来了很多便利，但是我们无法预知I/O系统的复杂行为。尤其在一些数据库的应用中，他们倾向于自己做缓存。使用`O_DIRECT`标志会使内核最小化I/O管理的影响，直接写到磁盘。使用这个标志时，注意下面几点：
1. I/O操作将忽略页缓存机制，直接对用户空间缓冲区和设备进行初始化。
2. 所有的I/O将是同步的，操作在完成之前不会返回。
3. 当使用直接I/O时，请求长度，缓冲区对齐，和文件偏移必须是设备扇区大小（通常是512字节）的整数倍。

### I/O Cache的一些思考
[Buffer和Cache的区别是什么？](https://www.zhihu.com/question/26190832/answer/32387918)
1、`Buffer`（缓冲区）是系统两端处理速度平衡（从长时间尺度上看）时使用的。它的引入是为了减小短期内突发I/O的影响，起到流量整形的作用。比如生产者——消费者问题，他们产生和消耗资源的速度大体接近，加一个buffer可以抵消掉资源刚产生/消耗时的突然变化。
2、`Cache`（缓存）则是系统两端处理速度不匹配时的一种折衷策略。因为CPU和memory之间的速度差异越来越大，所以人们充分利用数据的局部性（locality）特征，通过使用存储系统分级（memory hierarchy）的策略来减小这种差异带来的影响。

Buffer和Cache需要同步吗？
buffer和cache在Linux 2.4之前是两种缓存，也就是说同一份数据有两份内容在内核中。这两份数据的同步和维护其实带来了一些麻烦。在Linux 2.4之后，人们想到了统一这两种缓存，就把buffer指向了cache，使得数据只剩下一份实体。对于为什么是cache作为了主要的语义，参见[这里](https://www.quora.com/What-is-the-major-difference-between-the-buffer-cache-and-the-page-cache-Why-were-they-separate-entities-in-older-kernels-Why-were-they-merged-later-on)。


### IO栈
我们上面只说明了内核中的文件系统做的操作，在写入磁盘之前还有几个步骤。[Linux下的IO栈](https://www.0xffffff.org/2017/05/01/41-linux-io/)致大致有三个层次：
1. 文件系统层，以`write(2)`为例，内核拷贝了`write(2)`参数指定的用户态数据到Page Cache中，并适时向下层同步
2. 块层，管理块设备的IO队列，对IO请求进行合并、排序（IO调度算法和blk-mq都在这一层）
3. 设备层，通过DMA（一种磁盘、网卡等直接写内存的快速通道，不需要CPU参与）与内存直接交互，完成数据和具体设备之间的交互

![IO分层](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/linux/linux-io.png)

传统的Buffered IO使用`read(2)`读取文件的过程什么样的？假设要去读一个冷文件（Cache中不存在）
1. `open(2)`打开文件内核后建立了一系列的数据结构
2. 接下来调用`read(2)`，到达文件系统这一层，发现Page Cache中不存在该位置的磁盘映射，然后创建相应的Page Cache并和相关的扇区关联。
3. 然后请求继续到达块设备层，在IO队列里排队，接受一系列的调度后到达设备驱动层，此时一般使用DMA方式读取相应的磁盘扇区拷贝到Page Cache中
4. 然后`read(2)`拷贝数据到用户提供的用户态buffer中去（`read(2)`的参数指出的）。
可以看到，一次read总共进行了三次拷贝。相对地，我们以socket收发一次数据为例，看看需要什么成本：
![IO拷贝](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/linux/linux_copy.png)
图中总共进行了4次拷贝（其中两次是DMA拷贝，CPU没参与），4次上下文切换。大量数据的拷贝，用户态和内核态的频繁切换，会消耗大量的 CPU 资源，严重影响数据传输的性能，有数据表明，在Linux内核协议栈中，这个拷贝的耗时甚至占到了数据包整个处理流程的57.1%。这就是I/O加速带给我们的代价。

## stdio
上面可以看到，对系统进行和磁盘快大小整数倍的读写时，I/O的效率最高。仅仅是内核的I/O优化还不够，需要对普通文件执行许多轻量级I/O请求的程序通常使用用户缓冲I/O。用户缓冲I/O是在用户空间而不是在内核中完成的，它可以在程序中设定，也可以调用标准库透明地执行。一般程序可选的I/O优化有几种：
1. 直接使用内核提供的`write`和`read`系统调用。
2. 使用stdio提供的`fgetc fgets fread fputc fputs fwrite`等带用户态缓冲区的标准库函数。
3. 自己实现用户态缓冲区，用自己的用户态缓冲区+`write`和`read`系统调用。
4. 自己实现用户态缓冲区和内核缓冲区，使用`Direct I/O`读写磁盘。
用户态缓冲区的基本思想是，如果是写请求，先在缓冲区存一份数据，然后在一个缓冲区满的时候再调用write写进去。最合适的缓冲区大小是和磁盘块对齐的，一般4096或者8192的大小速度就会达到最快。如果是读请求，缓冲区就会成块读取数据，当一个块被读完后再预先读一块。无论读取的时候有没有对齐，缓冲区总会对齐了读。

### 设置缓冲区
```
int setvbuf (FILE *stream, char *buf, int mode, size_t size)
// 1. 该函数设置流的缓冲类型模式，模式必须是以下的一种：
IONBF //无缓冲 每输入一个字符，就刷入内核缓冲区
IOLBF //行缓冲 遇到换行符，就刷入内核缓冲区
IOFBF //块缓冲 默认的文件缓冲。每写满一个磁盘块就刷入一次
// 2. buf可以设置为自定义的缓冲区。如果不需要就设置为空，系统会自动分配。
// 3. 要特别注意buf的生命周期。buf必须在流刚打开时就设置。另外，buf必须在流关闭时依然没被回收。
```
### 清洗缓冲区
`int fflush(FILE *stream)` 会把stream指向的流中的所有未写入的数据会被清洗到内核中。如果stream是NULL，所有进程打开的流会被清洗掉。
1. `fflush`只是把用户缓冲的数据直接调用`write`写入到内核缓冲区。这并不保证数据能够写入物理介质，如果需要的话，请使用`fsync`这一类函数。
2. 一般可以在调用`fflush`后，立即调用`fsync`，这样可以直接刷到磁盘上。主要注意用户态的`fwrite`一类的函数一定不要和write一类的系统调用同时使用。

## 零拷贝
之前的章节可以看到，内核中的I/O缓存虽然给我们带来了磁盘读写速度的便利，但是确牺牲了很多的CPU时间。其实有很多拷贝不是必须的，我们也有一些手段去避免无用的反复拷贝和上下文切换。
### mmap
我们可以用mmap把数据直接映射到内核的Page Cache，这样就可以少一次用户态到内核的拷贝：
```
tmp_buf = mmap(file, len);
write(socket, tmp_buf, len);
```
[mmap copy](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/linux/copy1.png)
图中可以看到，DMA引擎将文件内容复制到内核缓冲区中，然后与用户进程共享缓冲区。这不会在内核和用户存储器空间之间执行任何复制。
mmap是有代价的。例如，当你的程序map了一个文件，但是当这个文件被另一个进程截断(truncate)时, write系统调用会因为访问非法地址而被SIGBUS信号终止。SIGBUS信号默认会杀死你的进程并产生一个coredump,如果你的服务器这样被中止了，那会产生一笔损失。
通常我们使用以下解决方案避免这种问题：
1. 处理SIGBUS信号 当遇到SIGBUS信号时，信号处理程序简单地返回，write系统调用在被中断之前会返回已经写入的字节数，并且errno会被设置成success。但是这是一种糟糕的处理办法，因为你并没有解决问题的实质核心。
2. 使用文件租借锁 我们为文件向内核申请一个租借锁，当其它进程想要截断这个文件时，内核会向我们发送一个实时的`RT_SIGNAL_LEASE`信号，告诉我们内核正在破坏你加持在文件上的读写锁。这样在程序访问非法内存并且被SIGBUS杀死之前，你的write系统调用会被中断。write会返回已经写入的字节数，并且置errno为success。

### sendfile
如果是给套接字发数据，sendfile提供了一种从一个fd中读取内容写入到另一个fd的方式。
`ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count)` 
1. 描述符`out_fd`必须指向一个套接字，而`in_fd`指向的文件必须是可以mmap的(sendfile只能将数据从文件传递到套接字上) 。
2. `offset`标识了从`in_fd`中读取的位置，`count`则表明读取的长度。
如果是管道，可以用下面的splice（两个fd至少有一个是管道）：
`ssize_t splice(int fd_in, loff_t *off_in, int fd_out, loff_t *off_out, size_t len, unsigned int flags)`

![sendfile copy](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/linux/copy1.png)
图中可以看到，`sendfile`可以直接把文件从内核缓冲区拷贝到socket缓冲区。虽然也是三次复制，但是少了一次陷入用户态的上下文切换。在我们调用`sendfile`时，如果有其它进程截断了文件会发生什么呢？假设我们没有设置任何信号处理程序，`sendfile`调用仅仅返回它在被中断之前已经传输的字节数，errno会被置为success。如果我们在调用`sendfile`之前给文件加了锁，`sendfile`的行为仍然和之前相同，我们还会收到`RT_SIGNAL_LEASE`的信号

### sendfile with DMA
常规 `sendfile` 还有一次内核态的拷贝操作，能不能也把这次拷贝给去掉呢？
答案就是这种 `DMA` 辅助的 `sendfile`。
这种方法借助硬件的帮助，在数据从内核缓冲区到 socket 缓冲区这一步操作上，并不是拷贝数据，而是拷贝缓冲区描述符，待完成后，`DMA` 引擎直接将数据从内核缓冲区拷贝到协议引擎中去，避免了最后一次拷贝。
![enter image description here](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/linux/copy3.png)

### 写时复制（COW），fbuf，netmap
一些其他的零拷贝技术，参见
[知乎上的零拷贝](https://zhuanlan.zhihu.com/p/76640160)
[Zero Copy I: User-Mode Perspective](https://www.linuxjournal.com/article/6345)
![零拷贝](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/linux/zerocopy.png)