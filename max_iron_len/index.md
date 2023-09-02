# [算法]DP解决钢条切割问题




# DP解决钢条切割问题

（原题见算法导论·动态规划）

对长度为n的钢条进行切割，对应的切割长度和价格对应如下：

int cost[] = {0, 1, 5, 8, 9, 10, 17, 17, 20, 24, 30};

比如1对应价值1,10对应价值30。即相应的下标和值的对应。现求切割所得最大效益mx。


## 递归算法

```c
    int cut_rod(int *cost,int n)
    {
        if(n == 0) return 0;
        int limit = MIN(n,10);       //分割第一条的上限
        int mx =  -1;
        for(int i = 1;i <= limit; ++i)
            mx = maxnum(mx,cost[i]+cut_rod(cost,n-i));    //取当前值于递归值的最大值
        return mx;
    }
```

由于对相同子问题的重复求解，T(n) = 2^n


## 递归标记数组算法（自顶而下）（DFS）


```c
    int mem_cut_rod(int *cost,int n,int *mem)   //mem数组长度为n,所有元素须在其他函数中初始化为-1
    {
        int mx;
        if (mem[n] >= 0) return mem[n];     //对于求过的问题，直接返回存储的值
        if (n == 0) mx = 0;
        else mx = -1;
        int limit = MIN(n,10);
        for(int i = 1;i <= limit; ++i)
            mx = maxnum(mx,cost[i]+mem_cut_rod(cost,n-i,mem));   //后面的内容和递归型是一样的
        mem[n] = mx;    //储存计算出的新值
        return mx;  
    }
```


## 逆拓扑序DP（自底向上）

```c

    int bottom_cut_rod(int *cost,int n)
    {
        int mem[MEM_LEN+1];                              //MEM_LEN = n，设置标记数组
        mem[0] = 0;                                       //i,j将从1开始，这里收益是0
        for(int i = 1; i <= n; ++i)                              //从第一个问题开始求解
        {
            int mx = -1;
            int limit = MIN(i,10);
            for(int j = 1;j <= limit; ++j)
                mx = maxnum(mx,cost[j] + mem[i-j]);     //求解最小的问题
            mem[i] = mx;
        }
        return mem[n];
    }
```


我们可以看到，2,3 的解法复杂度均为O(n^2)。


## 带解决方案的DFS


```c++
    typedef struct {
        string path;        //方案路径
        bool memoried;
        int value;
    } MEMORY;

    MEMORY *mem_pool;
    string num_to_str(int num) {
        char buf[120];
        sprintf(buf, "%d", num);
        return string(buf);
    }

    MEMORY DFS(int remain) {
        int select, limit = MIN(remain, COST_LEN), mx = -1, cur_cost;
        string cur_path, mx_path;
        if (mem_pool[remain - 1].memoried) {
            return mem_pool[remain - 1];
        }
        for (select = 1; select <= limit; ++select) {
            if (select == remain) {
                cur_cost = cost[remain];
                cur_path = num_to_str(remain);
            } else {
                MEMORY upper = DFS(remain - select);
                cur_cost = cost[select] + upper.value;
                cur_path = num_to_str(select) + ", " + upper.path;
            }
            if (cur_cost > mx) {
                mx = cur_cost;
                mx_path = cur_path;
            }
        }
        mem_pool[remain - 1].memoried = true;
        mem_pool[remain - 1].value = mx;
        mem_pool[remain - 1].path = mx_path;
        return mem_pool[remain - 1];
    }

    int main() {
        int n, i;
        cin >> n;
        mem_pool = new MEMORY[n];
        if (!mem_pool) {
            return 1;
        }
        for (i = 0; i < n; ++i) {
            mem_pool[i].memoried = false;
        }
        MEMORY result = DFS(n);
        cout << result.value << endl;
        cout << result.path << endl;
        delete[] mem_pool;
        return 0;
    }
```



## 其他代码

最后我们附上一份c实现的代码：


```c
    //2015.6.2
    //copyright XJSoft

    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <stdbool.h>

    typedef struct {
        bool memoried;
        int value;
    } MEMORY;

    int cost[] = {0, 1, 5, 8, 9, 10, 17, 17, 20, 24, 30};
    MEMORY *mem_pool;

    #define COST_LEN 10
    #define MIN(a,b) ((a)<(b)?(a):(b))
    int maxnum(const int v1,const int v2)
    {
        if (v1 > v2) return v1;
        else return v2;
    }

    int DFS(int remain) {
        int select, limit = MIN(remain, COST_LEN), mx = -1, cur_cost;
        if (mem_pool[remain - 1].memoried) {
            return mem_pool[remain - 1].value;
        }
        for (select = 1; select <= limit; ++select) {
            if (select == remain) {
                cur_cost = cost[remain];
            } else {
                cur_cost = cost[select] + DFS(remain - select);
            }
            if (cur_cost > mx) {
                mx = cur_cost;
            }
        }
        mem_pool[remain - 1].memoried = true;
        mem_pool[remain - 1].value = mx;
        return mx;
    }

    int DP(int n) {
        int remain, select, limit, mx, cur_cost;
        for (remain = 1; remain <= n; ++remain) {
            mx = -1;
            limit = MIN(remain, COST_LEN);
            for (select = 1; select <= limit; ++select) {
                if (select == remain) {
                    cur_cost = cost[select];
                } else {
                    cur_cost = cost[select] + mem_pool[remain - select - 1].value;
                }
                if (cur_cost > mx) {
                    mx = cur_cost;
                }
            }
            mem_pool[remain - 1].value = mx;
        }
        return mem_pool[n - 1].value;
    }

    int main() {
        int n, i;
        scanf("%d", &n);
        mem_pool = (MEMORY*)malloc(n * sizeof(MEMORY));
        if (!mem_pool) {
            printf("Mem error!\n");
            return 1;
        }
        for (i = 0; i < n; ++i) {
            mem_pool[i].memoried = false;
        }
        printf("%d\n", DP(n));
        free(mem_pool);
        return 0;
    }

```

