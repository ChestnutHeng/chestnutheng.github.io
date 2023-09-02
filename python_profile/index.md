# [Python]Python性能分析工具




## 时间分析

### time 命令
用*nix自带的系统命令
```
$ time python3 reg.py 

real	0m1.617s
user	0m1.504s
sys	0m0.112s
```
`sys` 系统调用时间
`user` 用户空间花费时间
`real` 实际时间
如果`user + sys < real` 说明时间被花费在IO上。

### profile和cProfile

python自带了两个函数时间分析工具，cProfile和profile。cProfile是纯C写的，所以用起来快了很多。
查看帮助:

```
$ python3 -m cProfile -h
Usage: cProfile.py [-o output_file_path] [-s sort] scriptfile [arg] ...

Options:
  -h, --help            show this help message and exit
  -o OUTFILE, --outfile=OUTFILE
                        Save stats to <outfile>
  -s SORT, --sort=SORT  Sort order when printing to stdout, based on
                        pstats.Stats class
```
-o 输出的文件只能给pstats.Stats类使用。
-s 是对结果按照关键字排序，关键字有 
`calls, cumulative, file, line, module, name, nfl, pcalls, stdname, time`

尝试分析一个测正则匹配次数的小程序：
```
$ python3 -m cProfile -s time exp.py
         4899025 function calls in 3.879 seconds

   Ordered by: internal time

   ncalls  tottime  percall  cumtime  percall filename:lineno(function)
        1    1.583    1.583    3.879    3.879 exp.py:1(<module>)
        1    0.777    0.777    0.859    0.859 {method 'readlines' of '_io._IOBase' objects}
  2415450    0.720    0.000    0.720    0.000 {method 'search' of '_sre.SRE_Pattern' objects}
  2415450    0.717    0.000    0.717    0.000 {method 'strip' of 'str' objects}
    33967    0.048    0.000    0.048    0.000 {built-in method _codecs.utf_8_decode}
    33967    0.033    0.000    0.082    0.000 codecs.py:318(decode)
        1    0.000    0.000    0.000    0.000 {built-in method builtins.print}
        1    0.000    0.000    0.000    0.000 {built-in method io.open}
        1    0.000    0.000    0.000    0.000 sre_parse.py:491(_parse)
        1    0.000    0.000    0.000    0.000 sre_compile.py:412(_compile_info)
        1    0.000    0.000    0.000    0.000 sre_compile.py:531(compile)
        1    0.000    0.000    0.000    0.000 re.py:278(_compile)
        1    0.000    0.000    0.000    0.000 sre_parse.py:167(getwidth)
        1    0.000    0.000    0.000    0.000 sre_compile.py:64(_compile)
       15    0.000    0.000    0.000    0.000 sre_parse.py:226(__next)
       65    0.000    0.000    0.000    0.000 {method 'append' of 'list' objects}
        1    0.000    0.000    0.000    0.000 sre_compile.py:391(_generate_overlap_table)
       14    0.000    0.000    0.000    0.000 sre_parse.py:247(get)
        1    0.000    0.000    0.000    0.000 sre_parse.py:819(parse)
       14    0.000    0.000    0.000    0.000 sre_parse.py:165(append)
        1    0.000    0.000    0.000    0.000 sre_parse.py:217(__init__)
        1    0.000    0.000    0.000    0.000 sre_parse.py:429(_parse_sub)
       26    0.000    0.000    0.000    0.000 {built-in method builtins.len}
...
```

对结果做了运行时间的排序。输出的表格中
`ncalls`为函数运行次数
`tottime`为函数自身运行时间(不包括内部其他函数)
`percall`为 `tottime/ncalls`
`cumtime`为函数总运行时间（包括其他函数、递归）
`percall`为 `cumtime/ncalls`

### line_profiler: 按行查看

安装:
`pip3 install line_profiler`

安装后便可以使用kernprof分析性能, 先在要分析的函数上加修饰器`@profile`，然后运行:
```
$ python3 -m kernprof -l -v exp.py 
10
Wrote profile results to exp.py.lprof
Timer unit: 1e-06 s

Total time: 6.26415 s
File: exp.py
Function: main at line 1

Line #      Hits         Time  Per Hit   % Time  Line Contents
==============================================================
     1                                           @profile
     2                                           def main():
     3         1            6      6.0      0.0      import re
     4         1          673    673.0      0.0      reg = re.compile(r'DO_PATH_REPLAN')
     5         1            1      1.0      0.0      count = 0
     6         1           45     45.0      0.0      with open('log.46.log') as f:
     7   2415451      2370592      1.0     37.8          for line in f.readlines():
     8   2415450      1674712      0.7     26.7              line = line.strip()
     9   2415450      2218037      0.9     35.4              if reg.search(line) is not None:
    10        10            6      0.6      0.0                  count += 1
    11         1           79     79.0      0.0          print(count)
```

## 内存分析

### memory_profiler

安装:
```
pip3 install memory_profiler
pip3 install psutil
```
同样，先在要分析的函数上加修饰器`@profile`，然后运行:
```
$ python3 -m memory_profiler exp.py
10
Filename: exp.py

Line #    Mem usage    Increment   Line Contents
================================================
     1   14.891 MiB    0.000 MiB   @profile
     2                             def main():
     3   14.891 MiB    0.000 MiB       import re
     4   14.891 MiB    0.000 MiB       reg = re.compile(r'DO_PATH_REPLAN')
     5   14.891 MiB    0.000 MiB       count = 0
     6   14.891 MiB    0.000 MiB       with open('log.46.log') as f:
     7  428.734 MiB  413.844 MiB           for line in f.readlines():
     8  428.734 MiB    0.000 MiB               line = line.strip()
     9  428.734 MiB    0.000 MiB               if reg.search(line) is not None:
    10  428.734 MiB    0.000 MiB                   count += 1
    11   15.250 MiB -413.484 MiB           print(count)

```


