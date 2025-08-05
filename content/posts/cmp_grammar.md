---
title: "[编译原理]Python实现的语法分析器"
date: 2016-12-27T01:20:24+08:00
lastmod: 2016-12-27T01:20:28+08:00
categories: ["编译原理"]
tags: ["编译原理"]
---



语法分析器是这套编译系统的第二部分,可以直接用上一篇中的词法分析器的结果继续做语法分析.
<!-- more -->
## 文法表
= =一直没时间更, 直到考试周格外闲...
借鉴了一个网络上的文法表, 覆盖了一些基础的C文法, 测试后发现该文法是LL(1)文法.
文法如下:
```
<函数定义>-><修饰词闭包><类型><变量>[(]<参数声明>[)][{]<函数块>[}]
<修饰词闭包>-><修饰词><修饰词闭包>
<修饰词闭包>->[@]
<修饰词>->[public]
<修饰词>->[private]
<修饰词>->[protected]
<类型>->[int]<取地址>
<类型>->[char]<取地址>
<类型>->[boolean]<取地址>
<类型>->[void]<取地址>
<取地址>-><星号><取地址>
<取地址>->[@]
<星号>->[*]
<变量>-><标志符><数组下标>
<标志符>->[id]
<数组下标>->[[]<因式>[]]
<数组下标>->[@]
<因式>->[(]<表达式>[)]
<因式>-><变量>
<因式>-><数字>
<数字>->[digit]
<表达式>-><因子><项>
<因子>-><因式><因式递归>
<因式递归>->[*]<因式><因式递归>
<因式递归>->[/]<因式><因式递归>
<因式递归>->[@]
<项>->[+]<因子><项>
<项>->[-]<因子><项>
<项>->[@]
<参数声明>-><声明><声明闭包>
<参数声明>->[@]
<声明>-><修饰词闭包><类型><变量><赋初值>
<赋初值>->[=]<右值>
<赋初值>->[@]
<右值>-><表达式>
<右值>->[{]<多个数据>[}]
<多个数据>-><数字><数字闭包>
<数字闭包>->[,]<数字><数字闭包>
<数字闭包>->[@]
<声明闭包>->[,]<声明><声明闭包>
<声明闭包>->[@]
<函数块>-><声明语句闭包><函数块闭包>
<声明语句闭包>-><声明语句><声明语句闭包>
<声明语句闭包>->[@]
<声明语句>-><声明>[;]
<函数块闭包>-><赋值函数><函数块闭包>
<函数块闭包>-><for循环><函数块闭包>
<函数块闭包>-><条件语句><函数块闭包>
<函数块闭包>-><函数返回><函数块闭包>
<函数块闭包>->[@]
<赋值函数>-><变量><赋值或函数调用>
<赋值或函数调用>->[=]<右值>[;]
<赋值或函数调用>->[(]<参数列表>[)][;]
<参数列表>-><参数><参数闭包>
<参数闭包>->[,]<参数><参数闭包>
<参数闭包>->[@]
<参数>-><标志符>
<参数>-><数字>
<参数>-><字符串>
<字符串>->[string]
<for循环>->[for][(]<赋值函数><逻辑表达式>[;]<后缀表达式>[)][{]<函数块>[}]
<逻辑表达式>-><表达式><逻辑运算符><表达式>
<逻辑运算符>->[<]
<逻辑运算符>->[>]
<逻辑运算符>->[==]
<逻辑运算符>->[!=]
<后缀表达式>-><变量><后缀运算符>
<后缀运算符>->[++]
<后缀运算符>->[--]
<条件语句>->[if][(]<逻辑表达式>[)][{]<函数块>[}]<否则语句>
<否则语句>->[else][{]<函数块>[}]
<否则语句>->[@]
<函数返回>->[return]<因式>[;]
```

## Grammar.py

典型的LL(1)的分析过程, 构造NULLABLE集, FIRST集, FOLLOW集, 计算SELECT集,最后画出预测分析表, 生成AST.
其中`simplify_tree`是用来递归简化树上的节点的.
代码很好读,都是华老师课件上的步骤.

```python
import json
import re
import copy

from Driver import Driver


# build tree
def simplify_tree(x: list):
    r = []
    for i in x:
        if isinstance(i, list):
            v = simplify_tree(i)
            if v is not None:
                r.append(v)
        else:
            r.append(i)
    if len(r) == 0:
        return None
    elif len(r) == 1:
        return r[0]
    else:
        return r


class Parser:
    # init sets
    def __init__(self):
        self.TERMINAL = []
        self.NONTERMINAL = []
        self.NULLABLE = set()
        self. FIRST = {}
        self.FOLLOW = {}
        self.FIRST_S = {}
        self.CFG = []
        self.TABLE = {}
        self.error_message = ''
        # build terminal, nonterminal and CFG
        with open('wenfa.json', 'r') as f:
            raw_cfg = json.load(f)
            for v in raw_cfg:
                v = v.split('->')
                self.NONTERMINAL.append(v[0])
                beta = v[1].split('|')
                for s in beta:
                    item = s.split(' ')
                    for l in item:
                        if l not in self.TERMINAL and re.match('<.*>', l) is None:
                            self.TERMINAL.append(l)
                    self.CFG.append([v[0], item])
        # init sets
        self.init_nullable()
        self.init_first()
        self.init_follow()
        self.init_first_s()

    # is x noterminal?
    def is_nonterminal_array(self, x):
        for v in x:
            if v not in self.NONTERMINAL:
                return False
        return True

    # can x be null?
    def is_nullable_array(self, x):
        for v in x:
            if v not in self.NULLABLE:
                return False
        return True

    # init nullable set
    def init_nullable(self):
        while True:
            tmp = copy.deepcopy(self.NULLABLE)
            for v in self.CFG:
                if v[1] == ['@']:
                    self.NULLABLE |= {v[0]}
                if self.is_nonterminal_array(v[1]) and self.is_nullable_array(v[1]):
                    self.NULLABLE |= {v[0]}
            if tmp == self.NULLABLE:
                break

    # init first set
    def init_first(self):
        for v in self.NONTERMINAL:
            self.FIRST[v] = set()
        change_flag = True
        while change_flag:
            raw_set = copy.deepcopy(self.FIRST)
            for v in self.CFG:
                for s in v[1]:
                    if s in self.NONTERMINAL:
                        self.FIRST[v[0]] |= self.FIRST[s]
                        if s not in self.NULLABLE:
                            break
                    else:
                        self.FIRST[v[0]] |= {s}
                        break
            change_flag = False
            for v in raw_set:
                if raw_set[v] != self.FIRST[v]:
                    change_flag = True

    # init follow set
    def init_follow(self):
        for v in self.NONTERMINAL:
            self.FOLLOW[v] = set()
        change_flag = True
        while change_flag:
            raw_set = copy.deepcopy(self.FOLLOW)
            for v in self.CFG:
                tmp = self.FOLLOW[v[0]]
                beta = copy.deepcopy(v[1])
                beta.reverse()
                for s in beta:
                    if s in self.NONTERMINAL:
                        self.FOLLOW[s] |= tmp
                        if s not in self.NULLABLE:
                            tmp = self.FIRST[s]
                        else:
                            tmp |= self.FIRST[s]
                    else:
                        tmp = {s}
            change_flag = False
            for v in raw_set:
                if raw_set[v] != self.FOLLOW[v]:
                    change_flag = True

    # init select set
    def init_first_s(self):
        for i in range(0, len(self.CFG)):
            self.FIRST_S[i] = set()
        for i in range(0, len(self.CFG)):
            self.calc_first_s(i, self.CFG[i])
        # build table
        self.TABLE = {}
        for v in self.FIRST_S:
            if self.CFG[v][0] not in self.TABLE:
                self.TABLE[self.CFG[v][0]] = {}
            for s in self.FIRST_S[v]:
                if s not in self.TABLE[self.CFG[v][0]]:
                    self.TABLE[self.CFG[v][0]][s] = v
                else:
                    # occurs
                    if self.CFG[self.TABLE[self.CFG[v][0]][s]][1] != ['@']:
                        if self.CFG[v][1] == ['@']:
                            pass
                        else:
                            print('Occur: ', v, 'and', self.TABLE[self.CFG[v][0]][s])
                    else:
                        self.TABLE[self.CFG[v][0]][s] = v
        # this code could print predict table
        # print table
        # for v in self.TERMINAL:
        #     print(v, end=' ')
        # print('')
        # for v in self.TABLE:
        #     print(v, end=' ')
        #     for s in self.TERMINAL:
        #         try:
        #             print(self.TABLE[v][s], end=' ')
        #         except:
        #             print('* ', end='')
        #     print('')

    # calc first_s for every rule
    def calc_first_s(self, i, v):
        for s in v[1]:
            if s in self.NONTERMINAL:
                self.FIRST_S[i] |= self.FIRST[s]
                if s not in self.NULLABLE:
                    return
            else:
                self.FIRST_S[i] |= {s}
                if s != '@':
                    return
        self.FIRST_S[i] |= self.FOLLOW[v[0]]

    # drive code
    def parse(self, tokens):
        dom = []
        stack = [('<函数定义>', dom)]
        i = 0
        while stack:
            # EOF
            if i == len(tokens):
                self.error_message = 'Line ' + line_no + ' EOF_ERROR: unexpected end of file'
                return
            # get data
            if tokens[i]['raw_data'] in self.TERMINAL:
                ch = tokens[i]['raw_data']
            else:
                ch = tokens[i]['symbol']
            line_no = str(tokens[i]['line_no'])
            # operate stack
            if stack[-1][0] in self.NONTERMINAL:
                top = stack.pop(-1)
                T = top[0]
                try:
                    rule = self.TABLE[T][ch]
                except KeyError:
                    ch = '@'
                    if ch not in self.TABLE[T]:
                        self.error_message = 'Line ' + line_no + ' TB_ERROR: unexpected ' + tokens[i]['raw_data']
                        return
                    rule = self.TABLE[T][ch]
                expression = copy.deepcopy(self.CFG[rule][1])
                expression.reverse()
                sub = top[1]
                sub.append(T + ':' + str(rule))
                for j in range(0, len(expression)):
                    sub.append([])
                for j in range(0, len(expression)):
                    stack.append((expression[j], sub[len(expression) - j]))
                # print('Pop : ', stack[-1][0], '  Rule : ', rule, '  Stack : ', stack)
            else:
                if stack[-1][0] == '@':
                    stack.pop(-1)
                elif stack[-1][0] == ch:
                    stack[-1][1].append(tokens[i])
                    stack.pop(-1)
                    i += 1
                else:
                    self.error_message = 'Line ' + line_no + ' TK_ERROR: expect   ' + stack[-1][0] \
                                         + '   ,but got   ' + tokens[i]['raw_data']
                    return
        if i < len(tokens) - 1:
            self.error_message = 'Line ' + line_no + ' LE_ERROR: unexpected   ' + tokens[i]['raw_data']
        else:
            print('Established.')
        return dom

    def run(self, text):
        # print('NULL',self.NULLABLE)
        # print('FIRST', self.FIRST)
        # print('FOLLOW', self.FOLLOW)
        # print('LEN_S', self.FIRST_S)
        d = Driver('state_machine.json')
        d.run(text)
        tokens = d.token_list
        dom = self.parse(tokens)
        if dom is None:
            return self.error_message
        r = simplify_tree(dom)
        return r

# AST: every first elem is (parent:cfg_rules_no), and remained are children.
if __name__ == '__main__':
    p = Parser()
    text = """int main()\n{\n\tint i = 7;\n\tint j = 9;\n\tint c[20] = {2,10,10,19,3,4,5,5,34,6,54,52,34,55   \
    ,68,10,90,78,56,20};\n\tfor (i=0;i<20;i++){\n\t\tfor(j=i+1;j<20;j--){\n\t\t\tif(j == 19){\n\t\t\t\tc[i] \
     = j;\n\t\t\t}\n\t\t}\n\t}\n\treturn 0;\n}"""
    text = "void main(){}"
    st = p.run(text)
    print(json.dumps(st, indent=8, ensure_ascii=False))

```
