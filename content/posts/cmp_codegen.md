---
title: "[编译原理]Python实现的语义分析器"
date: 2016-12-27T20:18:40+08:00
lastmod: 2016-12-27T20:18:44+08:00
categories: ["编译原理"]
tags: ["编译原理"]
---


语义分析是编译系统的第三部分,负责赋值检查,表达式检查以及代码生成.
<!-- more -->

## 基本思想
代码沿用了上一部分的文法表, 利用递归下降算法对每一个非终结符写一个函数. 但是文法多达70多条, 工作量太大, 就只实现了赋值语句, 表达式, 条件语句这几个代表性的文法规则. 其他实现起来也类似, 多写几个函数即可.

## 函数介绍
需要注意的几个细节:
1. compare_var_type用于比较类型, 比较失败则raise一个CompileError
2. 在生成代码过程中, 有的传入了其他的变量, 是为了回填
3. 把if回填做成了label的方式, 可以在后阶段再处理
4. 未初始化的变量调用也留给了后阶段处理.

函数表:

|成员函数|对应非终结符|备注|
|--|--|--|
|__init__()||初始化
|get_register()||分配寄存器
|get_label_no()||分配记号
|compare_var_type(var_type_1,var_type_2)||比较类型,raise错误
|build_table(x)||建立符号表
|check_factor(factor)|<因式>|用于检查
|check_factors(factor)|<因式递归>|用于检查
|check_factor_c(fc)|<因子>|用于检查
|check_term(term)|<项>|用于检查
|check_exp(x)|<表达式>|用于检查
|check_stm(x)|<赋值函数>|用于检查
|generate_factor(factor)|<因式>|用于生成
|generate_factors(factors,factor)|<因式递归>|用于生成
|generate_factor_c(fc)|<因子>|用于生成
|generate_term(term,factor)|<项>|用于生成
|generate_exp(x)|<表达式>|用于生成
|generate_stm(x)|<赋值函数>|用于生成
|generate_func_blocks(x)|<函数块闭包>|用于生成
|generate_func_block(x)|<函数块>|用于生成
|generate_else_block(x)|<否则语句>|用于生成
|generate_logical(x)|<逻辑表达式>|用于生成
|generate_if(x)|<条件语句>|用于生成
|generate_code(tree)|<函数定义>|用于生成
|dfs(tree,func)||搜索函数
|run(code)||获取生成结果

## 文法表
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

## 代码实现
知道了思路还是很好读的, 无非是看每个非终结符对应了哪条规则, 再利用分支调用对应的分支.

```python
import json

from Parse import Parser


# compile error class
class CompileError(Exception):
    pass


class Check:
    # init
    def __init__(self):
        self.TABLE = {}
        self.error_message = ''
        self.register_no = 0
        self.label_no = 0
        self.ADD_TABLE = {'+': 'ADD ', '-': 'SUB ', '*': 'MUL ', '/': 'DEV '}
        self.ADD_CODE = []

    # allocate register
    def get_register(self):
        self.register_no += 1
        return 'r' + str(self.register_no)

    # allocate label
    def get_label_no(self):
        self.label_no += 1
        return 'LABEL ' + str(self.label_no)

    # compare two types and raise error
    def compare_var_type(self, var_type_1, var_type_2):
        if var_type_1 == var_type_2:
            return var_type_1
        else:
            self.error_message = 'Expression err: can\'t operate ' + var_type_1 + ' with ' + var_type_2
            raise CompileError

    # build var table
    def build_table(self, x):
        if type(x) != list or type(x[0]) != str:
            return
        var_name = None
        var_type = None
        if x[0].startswith("<函数定义>"):
            for v in x:
                if type(v) != list:
                    continue
                if type(v[0]) == str and v[0].startswith("<类型>"):
                    var_type = v[1]["raw_data"]
                elif type(v[0]) == str and v[0].startswith("<变量>"):
                    var_name = v[1][1]["raw_data"]
        elif x[0].startswith("<声明>"):
            for v in x:
                if type(v) != list:
                    continue
                if type(v[0]) == str and v[0].startswith("<类型>"):
                    var_type = v[1]["raw_data"]
                elif type(v[0]) == str and v[0].startswith("<变量>"):
                    var_name = v[1][1]["raw_data"]
        if var_name and var_type:
            r = self.get_register()
            self.ADD_CODE.append('SET ' + var_name + ', ' + r)
            self.TABLE[var_name] = {'type': var_type, 'register': r}

    def check_factor(self, factor):
        if factor[0].endswith('17'):
            return self.check_exp(factor[2])
        else:
            if factor[1][0].startswith('<变量>'):
                if factor[1][1][1]["raw_data"] in self.TABLE:
                    return self.TABLE[factor[1][1][1]["raw_data"]]['type']
                else:
                    self.error_message = 'No define ' + factor[1][1][1]["raw_data"] + '.'
                    raise CompileError
            else:
                return 'int'

    def check_factors(self, factor):
        if type(factor[3]) != list:
            return self.check_factor(factor[2])
        else:
            return self.compare_var_type(self.check_factor(factor[2]), self.check_factors(factor[3]))

    def check_factor_c(self, fc):
        if type(fc[2]) != list:
            return self.check_factor(fc[1])
        else:
            return self.compare_var_type(self.check_factor(fc[1]), self.check_factors(fc[2]))

    def check_term(self, term):
        if type(term[3]) != list:
            return self.check_factor_c(term[2])
        else:
            return self.compare_var_type(self.check_factor_c(term[2]), self.check_term(term[3]))

    def check_exp(self, x):
        if type(x) != list or type(x[0]) != str:
            return
        if x[0].startswith("<表达式>"):
            if type(x[2]) != list:      # 项
                return self.check_factor_c(x[1])  # check 因子
            else:
                return self.compare_var_type(self.check_factor_c(x[1]), self.check_term(x[2]))

    def check_stm(self, x):
        if x[0].startswith("<赋值函数>"):
            var_name = x[1][1][1]["raw_data"]
            if var_name in self.TABLE:
                var_type = self.TABLE[x[1][1][1]["raw_data"]]['type']
                exp_type = self.check_exp(x[2][2][1])
                if var_type != exp_type:
                    self.error_message = 'Var ' + var_name + ' should be '+ var_type + ', but got ' + str(self.check_exp(x[2][2][1]))
                    raise CompileError
            else:
                self.error_message = 'No define ' + x[1][1][1]["raw_data"]
                raise CompileError

    def generate_factor(self, factor):
        if factor[0].endswith('17'):
            return self.generate_exp(factor[2])
        else:
            if factor[1][0].startswith('<变量>'):
                if factor[1][1][1]["raw_data"] in self.TABLE:
                    return self.TABLE[factor[1][1][1]["raw_data"]]['register']
                else:
                    self.error_message = 'No define' + factor[1][1][1]["raw_data"]
            else:     # is number
                return factor[1][1]["raw_data"]

    def generate_factors(self, factors, factor):
        r = self.get_register()
        if type(factors[3]) != list:
            self.ADD_CODE.append(self.ADD_TABLE[factors[1]['raw_data']] + factor + ', ' +
                                 self.generate_factor(factors[2]) + ', ' + r)
        else:
            self.ADD_CODE.append(self.ADD_TABLE[factors[1]['raw_data']] + self.generate_factor(factors[2])
                                 + ', ' + self.generate_factors(factors[3], factor) + ', ' + r)
        return r

    def generate_factor_c(self, fc):
        if type(fc[2]) != list:
            return self.generate_factor(fc[1])
        else:
            r = self.generate_factor(fc[1])
            return self.generate_factors(fc[2], r)

    def generate_term(self, term, factor):
        r = self.get_register()
        if type(term[3]) != list:
            self.ADD_CODE.append(self.ADD_TABLE[term[1]['raw_data']] + factor + ', ' +
                                 self.generate_factor_c(term[2]) + ', ' + r)
        else:
            self.ADD_CODE.append(self.ADD_TABLE[term[1]['raw_data']] + self.generate_term(term[3], factor)
                                 + ', ' + self.generate_factor_c(term[2]) + ', ' + r)
        return r

    def generate_exp(self, x):
        if x[0].startswith("<表达式>"):
            if type(x[2]) == list:      # 项
                r = self.generate_factor_c(x[1])
                return self.generate_term(x[2], r)
            else:
                return self.generate_factor_c(x[1])

    def generate_stm(self, x):
        if x[0].startswith("<赋值函数>"):
            var_name = x[1][1][1]["raw_data"]
            if var_name in self.TABLE:
                self.ADD_CODE.append('MOV ' + self.generate_exp(x[2][2][1]) + ', ' +
                                     self.TABLE[var_name]['register'])
            else:
                self.error_message = 'No define ' + x[1][1][1]["raw_data"]

    def generate_func_blocks(self, x):
        if x[1][0].startswith("<赋值函数>"):
            self.generate_stm(x[1])
        elif x[1][0].startswith("<条件语句>"):
            self.generate_if(x[1])
        if x[2] == list:
            self.generate_func_blocks(x[2])

    def generate_func_block(self, x):
        if type(x[2]) == list:
            self.generate_func_blocks(x[2])

    def generate_else_block(self, x):
        self.generate_func_block(x[3])

    def generate_logical(self, x):
        r = self.get_register()
        self.ADD_CODE.append(x[2][1]['raw_data'] + ', ' + self.generate_exp(x[1])
                             + ', ' + self.generate_exp(x[3]) + ', ' + r)
        return r

    def generate_if(self, x):
        if x[0].startswith("<条件语句>"):
            lb_yes = self.get_label_no()
            lb_break = self.get_label_no()
            if type(x[8]) != list:
                self.ADD_CODE.append('if ' + self.generate_logical(x[3]) + ', ' + lb_yes + ', ' + lb_break)
                self.ADD_CODE.append(lb_yes + ':')
                self.generate_func_block(x[6])
                self.ADD_CODE.append(lb_break + ':')
            else:
                lb_no = self.get_label_no()
                self.ADD_CODE.append('if ' + self.generate_logical(x[3]) + ', ' + lb_yes + ', ' + lb_no)
                self.ADD_CODE.append(lb_yes + ':')
                self.generate_func_block(x[6])
                self.ADD_CODE.append('JMP ' + lb_break)
                self.ADD_CODE.append(lb_no + ':')
                self.generate_else_block(x[8])
                self.ADD_CODE.append(lb_break + ':')

    def generate_code(self, tree):
        self.generate_func_block(tree[8])

    # dfs the ast tree
    def dfs(self, tree, func):
        func(tree)
        for i in range(1, len(tree)):
            v = tree[i]
            if type(v) == list:
                self.dfs(v, func)

    # run the code
    def run(self, code):
        p = Parser()
        ast = p.run(code)
        self.ADD_CODE.clear()
        #print(json.dumps(ast, indent=8, ensure_ascii=False))
        try:
            self.dfs(ast, self.build_table)
            self.dfs(ast, self.check_stm)
            self.generate_code(ast)
        except CompileError:
            return

if __name__ == '__main__':
    text = "void main(){int s=2;int b=1;if(s>b){b=2;}else{b=1*(2+(3+s));}}"
    checker = Check()
    checker.run(text)
    if checker.error_message:
        print(checker.error_message)
    else:
        for v in checker.ADD_CODE:
            print(v)
```





