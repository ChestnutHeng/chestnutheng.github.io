---
title: "[C++]sizeof那些事儿"
date: 2017-08-16T23:33:20+08:00
lastmod: 2017-08-16T23:33:24+08:00
tags: ["c++", "sizeof"]
categories: ["c++"]
description: "sizeof是什么？怎么用？返回了什么？怎么实现？本文详细回答了这些问题。"
---



## sizeof 是什么
首先明确一点，sizeof是**运算符**，不是函数。运算符是一个对于编译器来说的概念，是由编译器处理的，在程序编译好之后所有的sizeof都已经被替换为实际的值。类似的还有decltype。所以像
```c++
sizeof(++i);
```

这类的语句是不会改变i的值的。在C99之后，sizeof增加了一些运行时特性，可以算出可变数组的大小，像这样：

```c++
int num;
scanf("%d", &num);	 //input 4
int arr[num];
sizeof(arr);		//output 16
```



## sizeof 怎么用

[sizeof](http://zh.cppreference.com/w/c/language/sizeof) 支持下面的语法：

```c++
sizeof(type) 	    (1) 以字节数返回type类型对象表示的大小 
sizeof expression 	(2) 以字节数返回expression的类型对象表示的大小 
```

其中，`sizeof(char)`、 `sizeof(signed char)`以及`sizeof(unsigned char)`始终返回1。

`sizeof`不能用于函数类型、不完整类型（含void）或[位域](http://zh.cppreference.com/w/c/language/bit_field)左值。在一些编译器里，`sizeof(void)`会返回0，但这是没有定义的。

## 普通的sizeof

几个上面用法的例子：

```c
int main(void)
{
    // type argument:
    printf("sizeof(float)         = %u\n", sizeof(float));   //4
    printf("sizeof(void(*)(void)) = %u\n", sizeof(void(*)(void)));   //4
    printf("sizeof(char[10])      = %u\n", sizeof(char[10]));    //10

    // expression argument:
    printf("sizeof 'a'   = %u\n", sizeof 'a'); // 'a'的类型是int, 4
//  printf("sizeof main = %zu\n", sizeof main); // 错误：函数类型
    printf("sizeof &main = %u\n", sizeof main()); //类型为返回值int, 4
    printf("sizeof \"hello\" = %u\n", sizeof "hello"); // 类型为char[6], 6
    printf("sizeof(\"12345\" + 1)     = %u\n", sizeof("12345" + 1)); // 类型为指针, 4
}
```

需要注意的是，在函数传参等数组退化为指针的时候`sizeof`返回的当然是指针大小，切忌用它来计算数组大小。

## sizeof 和字节对齐

在sizeof用于非基本类型时，编译器会有字节对齐这样一个行为。它可以有效地用空间换时间，快速找到数据的地址。

字节对齐指的是每个变量的首地址和自身对齐值对齐，所以和变量顺序也有一定的关系。

字节对齐满足三个准则：

1) 结构体变量的首地址：能够被其最宽基本类型成员的大小所整除；

2) 结构体每个成员相对于结构体首地址的偏移量：都是该成员大小的整数倍，如有需要编译器会在成员之间加上填充字节。

3) 结构体末尾填充：结构体的总大小为结构体最宽**基本类型**成员大小的整数倍，如有需要编译器会在最末一个成员之后加上填充字节。

基本类型的宽度：char=1，short=2，int=4，double=8，指针=4

例如下面一个例子：

```c
typedef struct{
 int id;              //0-7  由于下个元素要和4对齐，补齐了2字节
 double weight;       //8-15
 float height;        //16-23 由于结构体大小和8对齐，补齐了4字节
}Body_Info;

typedef struct{
 char name[2];        //0-3   由于下个元素要和4对齐，补齐了2字节
 int  id;             //4-7   很齐
 double score;        //8-15  很齐　　
 short grade;         //16-23 由于下个元素要和8（BB中最长类型）对齐，补齐了6字节　　　
 Body_Info b;         //24-47 很齐
}Student_Info;
// 删除掉Student_Info的id或者name，大小都是不变的
// 删除掉Student_Info的grade或者把grade移动到name后，大小会成为40字节

```



## sizeof的实现

因为是个编译器行为，就没有函数代码了，也不在标准库里。在`clang`的编译器代码中可以看到一些对`sizeof`的处理，可以把玩一下：

```c++
TypeInfo ASTContext::getTypeInfoImpl(const Type *T) const {
  uint64_t Width = 0;
  unsigned Align = 8;
  bool AlignIsRequired = false;
switch (T->getTypeClass()){
case Type::Vector: {
    const VectorType *VT = cast<VectorType>(T);
    TypeInfo EltInfo = getTypeInfo(VT->getElementType());
    Width = EltInfo.Width * VT->getNumElements();
....
case BuiltinType::UInt:
case BuiltinType::Int:
    Width = Target->getIntWidth();
    Align = Target->getIntAlign();
    break;
case BuiltinType::ULong:
case BuiltinType::Long:
    Width = Target->getLongWidth();
    Align = Target->getLongAlign();
    break;
...
case Type::Pointer:
    unsigned AS = getTargetAddressSpace(cast<PointerType>(T)->getPointeeType());
    Width = Target->getPointerWidth(AS);
    Align = Target->getPointerAlign(AS);
    break;
...
}
```

编译结束后，`sizeof`就会根据`Width`和`Align`被替换为常量。
