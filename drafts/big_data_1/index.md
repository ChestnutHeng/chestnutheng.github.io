# [BigData]大数据算法



# 水库抽样
## 问题描述
Input：一组数据
Output：这组数据的K个均匀抽样
* 要求：
 * 扫描一次
 * 空间复杂度o(k)
 * 扫描到前n个数字时，保存当前数据的均匀抽样
* 实现
    收到第i个元素t时，以k/i的概率随机替换抽样数组ans[]中的元素
* 证明
    均匀：
    $$\frac{k}{i}\times(1-\frac{1}{i+1})\times(1-\frac{1}{i+2})\times\dots\times(1-\frac{1}{n})=\frac{k}{n}$$
    
## 实现代码

```c++
	#include <iostream>
	#include <cstdlib>
	#include <ctime>

	using namespace std;
	int random(int min ,int max)
	{

		return (min+(rand()%(max-min+1)));
	}

	int main()
	{
	
		srand(unsigned(time(0)));
		int k;
		int i;
		cout << "Input k:" ;
		cin >> k;
		double *ans = new double[k+1];
		double input;
		cout << "Input k numbers:" << endl;
		for(i = 1;i <= k; ++i)
		{
			cin >> ans[i];
		}
		cout << "Input stream numbers:(q to quit)" << endl;
		while(true)
		{

			int j = random(1,i);
			if(!(cin >> input)) break;
			if(j <= k)
				ans[j] = input;
			//output
			cout << "Ans :" ;
			for(int p = 1;p < k; ++p)
				cout << ans[p] << ",";
			cout << ans[k] << endl;
			i++;
		}
	
		delete [] ans;
		return 0;
	}
```
# 平面图直径
## 问题描述

> Input：m个点的平面图，任意两点的距离储存在矩阵D中。
 * 输入大小n = m^2
 * 最大的$D_{ij}$为图的直径
 * 点之间距离满足三角不等式
> Output：该图的直径和距离最大的$D_{ij}$

* 要求：
 * 运行时间o(n)
* 实现
    1. 任意选择$k\leq m$
    2. 选择使得$D_{kl}$最大的l
    3. 输出$D_{kl}$和(k,l)
* 证明
 * 近似比
   $$D_{ij}\leq D_{ik} + D_{kj}\leq D_{kl} + D_{kl}\leq 2D_{kl}$$
 * 运行时间 $O(m)=O(\sqrt{n})=o(n)$

## 代码实现

```c++
	#include <iostream>
	#include <cstdlib>
	#include <ctime>

	using namespace std;
	int random(int min ,int max)
	{

		return (min+(rand()%(max-min+1)));
	}

	int main()
	{
	
		srand(unsigned(time(0)));
		int m;
		cout << "Input m:";
		cin >> m;
		int **ans = new int * [m];
		for(int i = 0; i < m; ++i)
		{
			ans[i] = new int[m];
		}
		cout << "Input martrix:" << endl;
		for(int i = 0; i < m; ++i)
		{
			for(int j = 0;j < m; ++j)
			{
				cin >> ans[i][j];
			}
		}

		int line = random(0,m-1);
		int maxd = 0,maxi;
		for(int i = 0;i < m; ++i)
		{
			if(ans[line][i] > maxd)
			{
				maxd = ans[line][i];
				maxi = i;
			}
		}
		cout << "MAX_D:" << maxd << ", D_(i,j):(" << line << "," << maxi+1 <<")" <<endl;
		for(int i = 0; i < m; ++i)
		{
			delete [] ans[m];
		}
		delete [] ans;
		return 0;
	}
```


