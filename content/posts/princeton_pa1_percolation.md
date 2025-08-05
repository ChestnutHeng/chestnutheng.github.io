---
title: "[普林斯顿算法公开课]并查集解决渗透问题"
date: 2016-11-08T13:39:00+08:00
lastmod: 2016-11-08T13:40:00+08:00
tags: ["普林斯顿算法公开课", "算法", "并查集"]
categories: ["算法"]
description: "普林斯顿算法公开课作业一, 并查集的应用"
---



## Percolation.java

题目见  <a href='http://coursera.cs.princeton.edu/algs4/assignments/percolation.html'>渗透问题</a>

运用题目给出的API来解决问题.
第一个文件是Percolation.java, 用来编写解决单个渗透问题相关代码.
API:
```java
public class Percolation {
   public Percolation(int n)                // create n-by-n grid, with all sites blocked
   public void open(int row, int col)       // open site (row, col) if it is not open already
   public boolean isOpen(int row, int col)  // is site (row, col) open?
   public boolean isFull(int row, int col)  // is site (row, col) full?
   public boolean percolates()              // does the system percolate?

   public static void main(String[] args)   // test client (optional)
}
```
大体思想是, 建立一个查是否渗透的并查集, 只要最上面一排和最下面一排属于一个集合就认为是渗透的. 但是判断每两个节点是否联通需要额外的$n^2$的时间, 显然不合适.
我们引入两个假节点分别为top节点和down节点, 再把top节点与最上一排的节点连接, down节点与最下一排的节点连接, 这样渗透问题就等价转换为上下两个节点是否联通.
之后,每次打开一个节点时,只需搜索它的上下左右是否打开,如果打开就把该节点加入打开的节点的集合即可.
需要注意的两点:
1. 当n=1,2时的边界情况. 此时第一排和最后一排节点是同一个节点, 需要单独做处理.
2. 倒灌的情况. 由于最后一排节点是相互联通的, 所以会发生倒灌情况. 解决方法是, 单独建立一个并查集, top节点连接方法不变, down节点不做连接. 这样, 查某节点有没有水只需要查是否和top节点连接即可.

```java
/**
 * Created by chestnutheng on 16-11-7.
 */
import edu.princeton.cs.algs4.WeightedQuickUnionUF;

import java.lang.reflect.Array;
import java.util.Arrays;
import java.util.Scanner;

public class Percolation {
    private WeightedQuickUnionUF uf;
    private WeightedQuickUnionUF uf_bk;
    private int size;
    private boolean [] isopen;
    public Percolation(int n){
        if(n < 1){
            throw new IllegalArgumentException();
        }
        //init
        this.size = n;
        this.uf = new WeightedQuickUnionUF(n*n + 2);
        this.uf_bk = new WeightedQuickUnionUF(n*n + 2);
        this.isopen = new boolean[n*n+2];
        for(int i = 1; i < n*n +1; ++i){
            isopen[i] = false;
        }
        if(n == 1){
            return;
        }
        //connect top-down
        for(int i = 1; i < n + 1; ++i){
            uf.union(0, i);
            uf_bk.union(0, i);
        }
        isopen[0] = true;
        for(int i = n*(n - 1) + 1; i < n*n + 1; ++i){
            uf.union(n*n + 1, i);
        }
        isopen[n*n + 1] = true;
    }               // create n-by-n grid, with all sites blocked
    // open site (row, col) if it is not open already
    public void open(int row, int col){
        if(row > size || col > size || row < 1 || col < 1){
            throw new IndexOutOfBoundsException();
        }
        if(size == 1){
            uf.union(0,2);
            uf_bk.union(0,1);
            isopen[1] = true;
            return;
        }
        // search around and union
        int [] map_search;
        if (col == 1)
            map_search = new int[]{(row - 2)*size + col, row*size + col, (row - 1)*size + col + 1};
        else if(col == size)
            map_search = new int[]{(row - 2)*size + col, row*size + col, (row - 1)*size + col - 1};
        else
            map_search = new int[]{(row - 2)*size + col, row*size + col, (row - 1)*size + col - 1, (row - 1)*size + col + 1};
        //System.out.println(Arrays.toString(map_search));
        for (int v:map_search){
            if(v > 0 && v < size*size + 1 && isopen[v]) {
                uf.union(v, (row - 1) * size + col);
                uf_bk.union(v, (row - 1) * size + col);
            }
        }

        isopen[(row - 1)*size + col] = true;
    }
    // is site (row, col) open?
    public boolean isOpen(int row, int col){
        if(row > size || col > size || row < 1 || col < 1){
            throw new IndexOutOfBoundsException();
        }
        return isopen[(row - 1)*size + col];
    }
    // is site (row, col) full?
    public boolean isFull(int row, int col){
        if(row > size || col > size || row < 1 || col < 1){
            throw new IndexOutOfBoundsException();
        }
        return isopen[(row - 1)*size + col] && uf_bk.connected(0,(row - 1)*size + col);
    }
    // does the system percolate?
    public boolean percolates(){
        return uf.connected(0, size*size + 1);
    }
    // test client (optional)
    public static void main(String[] args){
        Scanner sc = new Scanner(System.in);
        int size = sc.nextInt();
        int length = sc.nextInt();
        Percolation pe=new Percolation(size);
        for(int i = 0; i < length; ++i){
            int m = sc.nextInt();
            int n = sc.nextInt();
            System.out.println(m + "," + n);
            pe.open(m, n);
        }
        System.out.println(pe.percolates());
        //System.out.println(Arrays.toString(pe.uf.parent));
    }
}
```

## PercolationStats.java
第二个文件是PercolationStats.java, 用来模拟若干次随机渗透, 得到一些统计数据.
过程非常简单,只需每次open一个没有打开的点, 记录渗透的时候的开点数量即可.
需要注意的是, 置信区间的公式为
$$[\overline{x} - \frac{1.96s}{\sqrt{T}}, \overline{x} + \frac{1.96s}{\sqrt{T}}]$$
s 为标准差, T 为测试次数.
刚开始由于把T写成了size,所以test6没过!! =_=
```java
/**
 * Created by chestnutheng on 16-11-7.
 */
import edu.princeton.cs.algs4.StdRandom;
import edu.princeton.cs.algs4.StdStats;

import java.lang.reflect.Array;
import java.util.Arrays;
import java.util.Scanner;


public class PercolationStats {
    private double []test_times_res;
    private double mean;
    private double dev;
    private int size;
    private int trials;
    // perform trials independent experiments on an n-by-n grid
    public PercolationStats(int n, int t){
        if(n < 1 || t <= 0){
            throw new IllegalArgumentException();
        }
        size = n;
        trials = t;
        int test_times = 0;
        test_times_res = new double[trials];
        while(test_times < trials){
            Percolation p = new Percolation(n);
            int count = 0;
            while(!p.percolates()){
                int x,y;
                do{
                    x = StdRandom.uniform(size) + 1;
                    y = StdRandom.uniform(size) + 1;
                }while (p.isOpen(x, y));
                p.open(x, y);
                count++;
            }
            test_times_res[test_times] = (double)count/((double)n*(double)n);
            test_times++;
        }
        mean = StdStats.mean(test_times_res);
        dev = StdStats.stddev(test_times_res);
    }
    // sample mean of percolation threshold
    public double mean(){
        return this.mean;
    }
    // sample standard deviation of percolation threshold
    public double stddev(){
        return this.dev;
    }
    // low  endpoint of 95% confidence interval
    public double confidenceLo(){
        return this.mean-1.96*this.dev/Math.sqrt(trials);
    }
    // high endpoint of 95% confidence interval
    public double confidenceHi(){
        return this.mean+1.96*this.dev/Math.sqrt(trials);
    }
    // test client
    public static void main(String[] args){
        Scanner sc = new Scanner(System.in);
        int N = sc.nextInt();
        int T = sc.nextInt();
        PercolationStats p = new PercolationStats(N, T);
        System.out.println("mean = " + p.mean());
        System.out.println("stddev = " + p.stddev());
        System.out.println("95% confidence interval " + p.confidenceLo() + ", " + p.confidenceHi());
    }
}
```

