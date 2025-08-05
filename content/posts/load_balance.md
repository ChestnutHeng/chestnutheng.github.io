---
title: "[后台]负载均衡 （一）算法篇"
date: 2020-05-06T20:24:30+08:00
lastmod: 2020-05-21T17:13:47+08:00
tags: ["负载均衡", "算法", "后台"]
categories: ["后台"]
description: "负载均衡是集群中一个重要的组成部分。这个模块一般集成了名字服务、负载均衡、过载保护、限流等功能。第一部分是针对均衡本身算法的介绍。"
---


当单机的访问压力很大时，就需要引入集群。集群一个很重要的事情就是把请求均匀地分配在各个机器上，这就是负载均衡的雏形。
有基于MAC地址的二层负载均衡和基于IP地址的三层负载均衡。 二层负载均衡会通过一个虚拟MAC地址接收请求，然后再分配到真实的MAC地址；三层负载均衡会通过一个虚拟IP地址接收请求，然后再分配到真实的IP地址；
四层通过虚拟IP+端口接收请求，然后再分配到真实的服务器（比如LVS，F5）；七层通过虚拟的URL或主机名接收请求，然后再分配到真实的服务器（Haproxy和Nginx）。
四层和七层是最常见的负载均衡模型。
![七层和四层模型](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/load_ban1.jpg)
**四层：**以常见的TCP为例，负载均衡设备在接收到第一个来自客户端的SYN请求时，通过负载均衡算法选择服务器，并对报文中目标IP地址进行修改（改为后端服务器IP），直接转发给该服务器。TCP的连接建立，即三次握手是客户端和服务器直接建立的，负载均衡设备只是起到一个类似路由器的转发动作。在某些部署情况下，为保证服务器回包可以正确返回给负载均衡设备，在转发报文的同时可能还会对报文原来的源地址进行修改。
**七层：**以常见的TCP为例，负载均衡设备如果要根据真正的应用层内容再选择服务器，只能先代理最终的服务器和客户端建立连接(三次握手)后，才可能接受到客户端发送的真正应用层内容的报文，然后再根据该报文中的特定字段，再加上设置的负载均衡算法，选择内部某台服务器。负载均衡设备在这种情况下，更类似于一个代理服务器。负载均衡和前端的客户端以及后端的服务器会分别建立TCP连接。所以从这个技术原理上来看，七层负载均衡明显的对负载均衡设备的要求更高，处理七层的能力也必然会低于四层模式的部署方式。
[参考资料：四层和七层负载均衡的区别](https://kb.cnblogs.com/page/188170/)

# nginx用的负载均衡算法
Nginx可以作为HTTP反向代理，把访问本机的HTTP请求，均分到后端集群的若干台服务器上。负载均衡的核心就是负载均衡所使用的平衡算法，适用于各种场景。
[Nginx的负载均衡算法](https://www.kancloud.cn/digest/sknginx/130029)
Nginx目前提供的负载均衡模块：
ngx_http_upstream_round_robin，加权轮询，可均分请求，是默认的HTTP负载均衡算法，集成在框架中。
ngx_http_upstream_ip_hash_module，IP哈希，可保持会话。
ngx_http_upstream_least_conn_module，最少连接数，可均分连接。适用于链接数体现资源的服务，比如FTP。
ngx_http_upstream_hash_module，一致性哈希，可减少缓存数据的失效。

## 随机访问
在介绍nginx的模式前，先介绍下普通的负载均衡方法。假设有7个请求，我们给A、B、C三个节点分别4、2、1的权重。最朴素的负载均衡方式有下面几种：
1. 完全轮询：访问完A去访问B，访问完B去访问C，再去访问A。缺点是没有权重，不能根据负载调节。
2. 列表轮询：构造一个数组[A, A, A, A, B, B, C]，每次pop出去一个访问。缺点是pop出去的元素太随机，可能一次集中访问A ，而且占用内存太大，对于几万的权重范围不合适。
3. 随机数：我们按照A、B、C的权重划分好区间，A（0、1、2、3），B（4、5），C（6），然后取一个随机数，模余7，看看最后的结果在哪个区间内，就取哪个节点。缺点是完全随机，无法避免集中访问。

## 加权轮询

假设有7个请求，我们给A、B、C三个节点分别4、2、1的权重。如果随机按照概率来选，那么很可能出现连续四个请求都在A上面的情况，这样只能保证结果看起来均衡，但是时间段内不均衡。Nginx采用了一种平滑的加权平均算法来选取节点（Weighted Round Robin）。
先引入三个概念，都用来描述服务器节点的权重：
1. $W$ : weight 我们指定的权重，就是上面例子中的4、2、1。
2. $W_{ew}$: effective_weight 有效权重，初始值为$W$。用来对故障节点降权。
如果通信中有错误产生，就减小effective_weight。（故障降权）
此后有新的请求过来时，再逐步增加effective_weight，最终又恢复到weight。（自动恢复）
3. $W_{cw}$ : current_weight 当前真实权重，每次都会选到最大的真实权重的节点去请求

真实权重$W_{cw}$计算方式：
1. 初始化：$W_{cw}$ 起始值为0
2. 获得实时权重：请求到来后，给每个节点的真实权重加上有效权重，即$每个节点 W_{cw} = W_{cw} + W_{ew}$ 
3. 选出最大权重：选择真实权重最大的节点最为本次请求的目标
4. 回避刚选的节点：最选择的节点的实时权重减去所有节点（包括自己）的有效权重和。即$选中节点 W_{cw} = W_{cw} - (W_{ew1} + W_{ew2} + ... + W_{ewn})$ 

来看一个具体的例子：
假设A、B、C三个节点的权重分别为4、2、1。

|请求序号|请求后的current_weight|选择的节点|选择后的current_weight|
| :------: | :-------: | :------: | :------: |
|未请求|{0,0,0}|/|/|
|1|{4,2,1}|A|{-3,2,1}|
|2|{1,4,2}|B|{1,-3,2}|
|3|{5,-1,3}|A|{-2,-1,3}|
|4|{2,1,4}|C|{2,1,-3}|
|5|{6,3,-2}|A|{-1,3,-2}|
|6|{3,5,-1}|B|{3,-2,-1}|
|7|{7,0,0}|A|{0,0,0}|
三个结论：每个节点被选中的次数是符合权重的；A没有被连续选取；七次之后权重会归零，是一个循环。

```c
static ngx_http_upstream_rr_peer_t *ngx_http_upstream_get_peer(ngx_http_upstream_rr_peer_data_t *rrp)
{
    time_t                        now;
    uintptr_t                     m;
    ngx_int_t                     total;
    ngx_uint_t                    i, n, p;
    ngx_http_upstream_rr_peer_t  *peer, *best;

    now = ngx_time();
    best = NULL;
    total = 0;
    ...

    /* 遍历集群中的所有后端 */
    for (peer = rrp->peers->peer, i = 0;
         peer;
         peer = peer->next, i++)
    {

        n = i / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));

        /* 检查该后端服务器在位图中对应的位，为1时表示不可用 */
        if (rrp->tried[n] & m)
            continue;
       
        /* 永久不可用的标志 */
        if (peer->down) 
            continue;
        
       /* 在一段时间内，如果此后端服务器的失败次数，超过了允许的最大值，那么不允许使用此后端了 */
       if (peer->max_fails
            && peer->fails >= peer->max_fails
            && now - peer->checked <= peer->fail_timeout)
            continue;
        
        peer->current_weight += peer->effective_weight; /* 对每个后端，增加其当前权重 */
        total += peer->effective_weight; /* 累加所有后端的有效权重 */

        /* 如果之前此后端发生了失败，会减小其effective_weight来降低它的权重。          
         * 此后在选取后端的过程中，又通过增加其effective_weight来恢复它的权重。          
         */        
        if (peer->effective_weight < peer->weight) 
            peer->effective_weight++;
        
        /* 选取当前权重最大者，作为本次选定的后端 */
        if (best == NULL || peer->current_weight > best->current_weight) {
            best = peer;
            p = i;
        }
    }

    if (best == NULL) /* 没有可用的后端 */
        return NULL;
    
    rrp->current = best; /* 保存本次选定的后端 */

    n = p / (8 * sizeof(uintptr_t));
    m = (uintptr_t) 1 << p % (8 * sizeof(uintptr_t));

    /* 对于本次请求，如果之后需要再次选取后端，不能再选取这个后端了 */    
    rrp->tried[n] |= m;

    best->current_weight -= total; /* 选定后端后，需要降低其当前权重 */  
    /* 更新checked时间 */
    if (now - best->checked > best->fail_timeout)
        best->checked = now;
    
    return best;
}
```

## ip_hash

ip_hash是基于客户端IP的哈希值来选择服务器。同一个客户端的请求，都会发往同一台后端，除非该后端不可用了。ip_hash能够达到保持会话的效果。
和随机加权哈希一样，ip哈希借鉴了权重分段的思想，先算出哈希值, 然后模余total_weight，得到初始权重W [0, total_weight)，开始遍历节点。如果哈希值小于当前节点的权重，就选择当前节点；如果哈希值大于等于当前节点的权重，就减去当前节点的权重，再去尝试下个节点。我们还是讨论A，B，C三个节点的情况，假设权重分别为2、4、1 。
权重的和是7，那么哈希值应该是0~6 （因为模了哈希值）
6的情况：6 >= 2 , 所以不选A，减去2。 6-2 >= 4，所以不选B，减去4。2-4 < 1，所以选C 
5的情况：5 >= 2 , 所以不选A，减去2。 5-2 < 4，所以选B
4的情况：4 >= 2 , 所以不选A，减去2。 4-2 < 4，所以选B 。哈希值为3、2的情况也一样。
1、0的情况：1 < 2，所以选A
可以看到最后四个选B，两个选A，一个选C，还是均衡的。


```c
for ( ; ; ) {
    /* 1.根据客户端IP、本次选取的初始hash值，计算得到本次最终的hash值 */
    /* hash1 = (hash0 * 113 + addr[0]) % 6271; hash2 = (hash1 * 113 + addr[1]) % 6271;...; */
    for (i = 0; i < (ngx_uint_t) iphp->addrlen; i++)
        hash = (hash * 113 + iphp->addr[i]) % 6271;

    /* 2. 先给w赋值为所有节点的权重和。total_weight和weight都是固定值 */
    w = hash % iphp->rrp.peers->total_weight;
    peer = iphp->rrp.peers->peer; /* 第一台后端 */
    p = 0;
	
	/* 3.遍历后端链表时，依次减去每个后端的权重，直到w小于某个后端的权重 */
    while (w >= peer->weight) {
        w -= peer->weight;
        peer = peer->next;
        p++;
    }
    break;
}
choose(p);
```

## least_conn

有的场景下，把请求转发给连接数较少的后端，能够达到更好的负载均衡效果。
least_conn算法很简单，首选遍历后端集群，比较每个后端的conns/weight，选取该值最小的后端。如果有多个后端的conns/weight值同为最小的，那么对它们采用加权轮询算法。

```c
for (peer = peers->peer, i = 0; peer; peer = peer->next, i++)
{
    /* 检查此后端在状态位图中对应的位，为1时表示不可用 */ 
    n = i / (8 * sizeof(uintptr_t));
    m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));

    if (rrp->tried[n] & m)
       continue;

    /* server指令中携带了down属性，表示后端永久不可用 */
    if (peer->down)
        continue;

    /* 在一段时间内，如果此后端服务器的失败次数，超过了允许的最大值，那么不允许使用此后端了 */
     if (peer->max_fails && peer->fails >= peer->max_fails
         && now - peer->checked <= peer->fail_timeout)
        continue;
        
    /* 比较各个后端的conns/weight，选取最小者；
     * 如果有多个最小者，记录第一个的序号p，且设置many标志。
     */
    if (best == NULL || peer->conns * best->weight < best->conns * peer->weight)
    {
        best = peer;
        many = 0;
        p = i;
    } else if (peer->conns * best->weight == best->conns * peer->weight)
        many = 1;
}
/* 如果有多个后端的conns/weight同为最小者，则对它们使用轮询算法 */
if (many) {
    for (peer = best, i = p; peer; peer->peer->next, i++)
    {
       /* conns/weight必须为最小的 */
        if (peer->conns * best->weight != best->conns * peer->weight)
            continue;

        peer->current_weight += peer->effective_weight; /* 对每个后端，增加其当前权重 */
        total += peer->effective_weight; /* 累加所有后端的有效权重 */

       /* 如果之前此后端发生了失败，会减小其effective_weight来降低它的权重。          
          * 此后在选取后端的过程中，又通过增加其effective_weight来恢复它的权重。          
          */        
        if (peer->effective_weight < peer->weight) 
            peer->effective_weight++;
    
        /* 选取当前权重最大者，作为本次选定的后端 */
        if (best == NULL || peer->current_weight > best->current_weight) {
            best = peer;
            p = i;
        }
    }
}
```

## 一致哈希
当后端是缓存服务器时，经常使用一致性哈希算法来进行负载均衡。使用一致性哈希的好处在于，增减集群的缓存服务器时，只有少量的缓存会失效，回源量较小。常见的CDN架构都是使用一致性哈希。
我们知道的[一致性哈希](https://www.codeproject.com/Articles/56138/Consistent-hashing)是一个环，每个哈希值对应的请求属于哈希值在环上遇到的下一个节点。为了使得请求分布更加均衡，我们建立了很多虚拟节点，请求会对应到虚拟节点的真实节点上。
1. 创造虚拟节点
在nginx中，为了保证节点的权重，一般一个真实节点对应weight * 160个虚拟节点。
每个虚拟节点的hash值hash = crc32(base_hash PREV_HASH)，其中，PREV_HASH表示上个虚拟节点的哈希值，这样就可以不断产出虚拟节点。base_hash 表示对应真实节点的哈希值（crc32(HOST 0 PORT)）。
创造完所有数量后，我们对虚拟节点按照哈希值排序。
2. 请求分配
先对请求做哈希，得出hash值，然后使用二分查找，寻找第一个hash值大于等于请求的哈希值的虚拟节点，即顺时针方向最近的一个虚拟节点。
3. 找到真实节点
遍历真实节点数组，寻找可用的、该虚拟节点归属的真实节点(server成员相同)，如果有多个真实节点同时符合条件，那么使用轮询来从中选取一个真实节点。

```c
for ( ; ; ) {
    /* 在peer.init中，已根据请求的哈希值，找到顺时针方向最近的一个虚拟节点，
     * hash为该虚拟节点在数组中的索引。
     * 一开始hash值肯定小于number，之后每尝试一个虚拟节点后，hash++。取模是为了防止越界访问。
     */
    server = point[hp->hash % points->number].server;
    best = NULL;
    best_i = 0;
    total = 0;

    /* 遍历真实节点数组，寻找可用的、该虚拟节点归属的真实节点(server成员相同)，
      * 如果有多个真实节点同时符合条件，那么使用轮询来从中选取一个真实节点。
      */
    for (peer = hp->rrp.peers->peer, i = 0; peer; peer = peer->next, i++) {
        /* 检查此真实节点在状态位图中对应的位，为1时表示不可用 */
        n = i / (8 * sizeof(uintptr_t));
        m = (uintptr_t) 1 << i % (8 * sizeof(uintptr_t));
        if (hp->rrp.tried[n] & m)
            continue;            

        /* server指令中携带了down属性，表示后端永久不可用 */
        if (peer->down)
            continue;

        /* 如果真实节点的server成员和虚拟节点的不同，表示虚拟节点不属于此真实节点 */
        if (peer->server.len != server->len || 
            ngx_strncmp(peer->server.data, server->data, server->len) != 0)
            continue;

       /* 在一段时间内，如果此真实节点的失败次数，超过了允许的最大值，那么不允许使用了 */
       if (peer->max_fails
            && peer->fails >= peer->max_fails
            && now - peer->checked <= peer->fail_timeout)
            continue;
    
        peer->current_weight += peer->effective_weight; /* 对每个真实节点，增加其当前权重 */
        total += peer->effective_weight; /* 累加所有真实节点的有效权重 */

        /* 如果之前此真实节点发生了失败，会减小其effective_weight来降低它的权重。          
         * 此后又通过增加其effective_weight来恢复它的权重。          
         */        
        if (peer->effective_weight < peer->weight) 
            peer->effective_weight++;
    
        /* 选取当前权重最大者，作为本次选定的真实节点 */
        if (best == NULL || peer->current_weight > best->current_weight) {
            best = peer;
            best_i = i;
        }
	}
	/* 如果选定了一个真实节点 */
	if (best) {
	    best->current_weight -= total; /* 如果使用了轮询，需要降低选定节点的当前权重 */
	    goto found;
	}
	
	hp->hash++; /* 增加虚拟节点的索引，即“沿着顺时针方向” */
	hp->tries++; /* 已经尝试的虚拟节点数 */
}
```

## 恐慌阈值 Envoy
负载均衡一般是根据集群中主机的健康情况灵活变动的。当某台主机跪了，LB算法将会把它从候选列表中踢出去，这也是很合理的。

但是我们假设这么一种情况，某一时间，所有服务主机的负载情况是最大负载的80%，（负载800；最大处理能力1000）
因为某种原因，导致20.0%的机器彻底崩溃。（负载800；最大处理能力800）
LB策略忽略20%的机器，导致剩下的80%的机器都在最大处理负载上运行；
又来了一个网络波动，造成所有的服务器一个接一个崩溃，整个集群雪崩。
每拉起一台新的机器，LB策略立刻把所有的流量打到这么一台机器上，导致它再次崩溃。

如果有一个恐慌阈值，譬如50%，那么LB会在50%机器崩溃的时候，禁用淘汰策略，把所有机器都当做健康的，在整体集群上执行普通的Round-Robin策略。
多数机器恢复，整个集群的处理能力恢复80%的正确率。这使得整个集群能够在遇到极特殊情况的时候能够从困境中恢复

# LB用的负载均衡算法

## EDF调度算法
[EDF调度算法](http://zablog.me/2019/08/02/2019-08-02/)
最早截止时间优先调度法 Earliest Deadline First (EDF) scheduler，是加权轮转调度算法（WRR，Weighted Round-Robin）的一种实现方式。
其核心思想是为每个条目截止时间赋值为当前时间加权重的倒数，然后采用最早截止时间优先的方式进行调度。
调度算法最主要的应用是操作系统调度进程，重要的调度理论基本上都是在此时涌现的。而后续反向代理对下游条目进行负载均衡，也可以参考一样的调度理论，只是进程的运行和切换转变为请求的接受与投递。

假设有三个条目可供调度，分别是A、B、C，他们的权重分别是3：2：1。
![调度队列](https://chestnutheng-blog-1254282572.cos.ap-chengdu.myqcloud.com/lb2.png)
图上有一个数轴，从0到3，分别表示三个周期。
A条目的权重是3，我们以1/3为分隔不断重绘A，使得数轴的1/3，2/3，1，4/3等位置印上A；
B条目的权重是2，我们以1/2为分隔不断重绘B，使得数轴的1/2，1，3/2，2等位置印上B；
C条目的权重是1，我们以1为分隔不断重绘C，使得数轴的1，2，3等位置印上C；
最后，我们使用一个游标从左向右扫，扫描到的顺序就是调度的顺序，因此我们调度的顺序为A-B-A-C-B-A-A-B-A…
显而易见，调用的顺序含有一个循环节A-B-A-C-B-A，所以当调度足够多次数后，A、B、C的调度比值将会趋近于3：2：1

### 实现1
最简单的实现，是使用上述办法模拟一个周期，然后把周期存到数组中，用游标扫描即可。
以上述情形为例，首先我们定制一个数组 A-B-A-C-B-A，然后不断回环扫描这个数组，就可以完成加权轮转调度。
这种方法的每次调度的时间复杂度为O(1)，空间复杂度为O(M*N)，其中M是条目的平均权重，N是条目的数量。
优势：
实现简单，容易理解
单次调度的很快
多线程共享游标index即可，协作方便
劣势：
空间复杂度高
对条目修改很不友好（修改其中一个条目的权重，那么整个表需要重新构建，耗CPU）

### 实现2
我们可以维护一个大小为节点数量的堆，按照最快到期时间来排序，每次取最快到期的节点（就是线段上最靠前的节点），返回后更新它的节点到期时间。
1. 初始时 entry.deadline = 1.0/entry.Weight
2. 调度的时候，从中选择 deadline 最小的使用，并把 deadline 设置为 ttl（当前时间）+ 1.0/entry.Weight，然后重新把这个条目放入优先队列中。重新排布优先队列，如此往复。

举个例子：
三个节点A、B、C权重分别为5、2、1

|请求序号|选择的节点|选择节点后的堆|选择时的TTL|
| :------: |:------: | :------: | :------: |
|未请求|/|[A(1/5), B(1/2), C(1)]|0|
|1|A|[A(2/5), B(1/2), C(1)]|1/5|
|2|A|[B(1/2), A(3/5), C(1)]|2/5|
|3|B|[A(3/5), B(1), C(1)]|1/2|
|4|A|[A(4/5), B(1), C(1)]|3/5|
|5|A|[A(1), B(1), C(1)]|4/5|
|6|A|[B(1), C(1), A(6/5)]|1|
|7|B|[C(1), A(6/5), B(3/2)]|3/2|
|8|C|[A(6/5), B(3/2), C(2)]|1|

复杂度分析：
空间复杂度降低为 O(N) ，每次Pick的时间复杂度为 O(logN)
初始化的时间复杂度为 O(N)，也就是堆排序的复杂度
```go
// 节点
type Entry struct {
	deadline float64
	index    int64
	Value    string
	Weight   float64
}

// EDF implements the Earliest Deadline First scheduling algorithm
type EDF struct {
	pq       *priorityQueue    //这个优先级队列用deadline排序
	curIndex int64
	curDDL   float64
}

// Add a new entry for load balance
func (e *EDF) Add(entry *Entry) {
	entry.deadline = e.curDDL + 1/entry.Weight
	e.curIndex++
	entry.index = e.curIndex
	heap.Push(e.pq, entry)
}

// AddRaw add a new entry for load balance without sort
func (e *EDF) AddRaw(entry *Entry) {
	entry.deadline = e.curDDL + 1/entry.Weight
	e.curIndex++
	entry.index = e.curIndex
	*e.pq = append(*e.pq, entry)
}

// Delete an entry
func (e *EDF) Delete(entry *Entry) {
	entry.Weight = -1
}

// Pick an available entry
func (e *EDF) Pick() *Entry {
	// if no available entry, return nil
	if len(*e.pq) <= 0 {
		return nil
	}
	entry := heap.Pop(e.pq).(*Entry)
	if entry.Weight <= 0 {
		// if Weight isn't positive, try another entry
		return e.Pick()
	}
	// curDDL should be entry's deadline so that new added entry would have a fair
	// competition environment with the old ones
	e.curDDL = entry.deadline
	entry.deadline = entry.deadline + 1/entry.Weight
	e.curIndex++
	entry.index = e.curIndex
	heap.Push(e.pq, entry)
	return entry
}

// NewEDF create a new edf scheduler
func NewEDF(entries []*Entry) *EDF {
	// make a new edf
	priorityQueue := make(priorityQueue, 0)
	edf := &EDF{
		pq:       &priorityQueue,
		curIndex: 0,
	}
	// put entries into priority queue
	// TODO(maziang): use O(N) heap.Init instead of O(NlogN) Add.
	for _, entry := range entries {
		edf.AddRaw(entry)
	}
	heap.Init(edf.pq)

	// avoid instance flood pressure for the first entry
	// start from a random one via pick random times
	rand.Seed(time.Now().UnixNano())
	randomPick := rand.Intn(len(entries))
	for i := 0; i < randomPick; i++ {
		edf.Pick()
	}
	return edf
}
```
Note1 同样权重的情况: index是节点进入堆的次序。当deadline一样时，会选取index小的那一个。这是为了避免当所有节点权重一样时，变成完全随机调度。如果有了index，那么每次选取之后该节点的index会加一（相当于排到后面去），这样就能保证下一个节点能被调度到。
Note2 存储空间优化：
Note3 起始随机化：如果有个节点权重很大，那么在调度器全部重启的时候可能都会调度到这个节点，导致这个节点压力过大。所以NewEDF的初始化阶段会有随机化操作。