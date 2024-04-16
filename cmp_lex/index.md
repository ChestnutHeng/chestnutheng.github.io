# [编译原理]Python实现的词法分析器




最近在上华保健老师的课, 在学习的过程中做了一套编译系统, 外加顺便应付学校的作业. 这个词法分析器是这套编译系统的第一部分.
<!-- more -->
其中RE到DFA, DFA到NFA的部分都是手工完成, 自己规定token格式(C语言格式), 得到一个NFA.
课程内容详见:
<a href="http://mooc.study.163.com/learn/USTC-1000002001?tid=1000003000#/learn/announce">编译原理MOOC</a>

算法都是课程中的算法, 不再详述.伪代码可以在华老师的课件中找到.

## state_machine.json

第一部分是手写的DFA, 用类似树状数组的方式存储.
![图片加载中-状态机](http://chestnutheng-blog-1254282572.file.myqcloud.com/blog_state_machine.png)
几个Key的含义如下:
```
SS: 起始状态
FS: 接受状态
I: 接受字符
T: 转换表   //如"8": {"3": 10, "5": 9}表示状态8输入I[3]可以转换到状态10, 状态8输入I[3]可以转换到状态9
S: 状态表    //下标对应的状态的含义
```

json文件:

<a href="http://chestnutheng-blog-1254282572.file.myqcloud.com/state_machine.json">state_machine.json</a>

## Driver.py

驱动文件,分析结果为三元组**(标识符, 内容, 行数)**的序列.

```python
#!/usr/bin/env python3

import json


class Driver:
    STATE_MACHINE = None
    content_symbols = ['id', 'digit']
    line_no = 0
    NOW_POINT = -1
    PREV_POINT = -1
    STRING = ''
    uncommit = ''
    token_list = []

    def __init__(self, file_name):
        with open(file_name, 'r') as f:
            self.STATE_MACHINE = json.load(f)

    # reset
    def reset(self):
        self.STRING = ''
        self.uncommit = ''
        self.token_list.clear()
        self.NOW_POINT = -1    #当前分析的字符下标
        self.PREV_POINT = -1   #用于获得标识符对应的内容
        self.line_no = 0

    # next char of string
    def next_ch(self):
        self.NOW_POINT += 1
        if self.NOW_POINT < len(self.STRING):
            return self.STRING[self.NOW_POINT]
        else:
            return None

    # rollback
    def rollback(self):
        self.NOW_POINT -= 1

    # drive code
    def next_token(self):
        state = "0"
        stack = []
        # get a token
        while True:
            c = self.next_ch()
            if c is None:
                return False
            # accept state
            if int(state) in self.STATE_MACHINE["FS"]:
                stack.clear()
            stack.append(state)
            # state change or state error
            num = None
            for i in range(0, len(self.STATE_MACHINE["I"])):
                if c in self.STATE_MACHINE["I"][i]:
                    num = i
            if num is None:
                return False
            # not accepted
            try:
                state = str(self.STATE_MACHINE["T"][state][str(num)])
            except KeyError:
                break
        state = stack.pop(-1)
        self.rollback()
        # get idn and token
        idn = self.STATE_MACHINE['S'][int(state)]
        name = self.STRING[self.PREV_POINT + 1:self.NOW_POINT + 1]
        if idn != 'SPACE':
            self.token_list.append({'symbol': idn, 'raw_data': name, 'line_no': self.line_no})

        self.PREV_POINT = self.NOW_POINT
        return True

    # print token to uncommit
    def print_token(self):
        for v in self.token_list:
            self.uncommit += v['raw_data'] + '\t< ' + v['symbol']
            if v['symbol'] in self.content_symbols:
                self.uncommit += ' , ' + v['raw_data'] + '>' + '\n'
            else:
                self.uncommit += ' , - >' + '\n'

    # run a string
    def run(self, string):
        self.reset()
        STRING_ARRAY = string.replace('\t', '').split('\n')
        for v in STRING_ARRAY:
            self.NOW_POINT = -1
            self.PREV_POINT = -1
            self.line_no += 1
            self.STRING = v + ';'
            while True:
                if not self.next_token():
                    break
        self.print_token()


if __name__ == '__main__':
    d = Driver('state_machine.json')
    d.run('while(num!=100)\n{\nnum++;\n}\n')    #简短的示例
    print(d.uncommit)
    print(d.token_list)
    d.run('n++')
    print(d.uncommit)
    print(d.token_list)

```



