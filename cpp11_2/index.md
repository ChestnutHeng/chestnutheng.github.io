# [C++]C++ 11/14 笔记（二）




本部分介绍了c++11的Lambda、函数容器和右值引用。
<!-- more -->

### Lambda
结构：
```
[捕获列表](参数列表) -> 返回类型{
    // 函数体
}
```
比如定义一个加法的lambda：
```cpp
auto add = [](auto x, auto y) {
    return x+y;
};
add(1.0, 2.3);
```
捕获列表用于传递外部的变量，分为以下几种：
1. [] 空捕获列表
2. [name1, name2, ...] 捕获一系列变量
3. [=] 值捕获, 捕获的变量为lambda表达式被创建时的值
4. [&] 引用捕获, 值会发生变化

### 函数容器
#### std::function
函数的类型安全的容器。比如下面的`std::function<int(int)> func2`定义了一个返回值`int`,参数为`(int)`的一个函数对象。其中捕获列表是传引用的，所以返回的是调用`func2`时的`1+value+important`的值。
```cpp
int important = 10;
std::function<int(int)> func2 = [&](int value) -> int {
    return 1+value+important;
};
```
#### std::bind/std::placeholder
有点像python的偏函数，它给函数一些预定的参数，以便于用更少的参数调用：
```cpp
int foo(int a, int b, int c) {
    return a + b + c;
}
int main() {
    // 将参数1,2绑定到函数 foo 上，但是使用 std::placeholders::_1 来对第一个参数进行占位
    auto bindFoo = std::bind(foo, std::placeholders::_1, 1,2);
    // 这时调用 bindFoo 时，只需要提供第一个参数即可
    bindFoo(1);
}
```

### 右值引用

#### 右值和左值
以赋值符号为界，左面的表示一个对象，右面的表示一个对象的值
#### 右值引用
右值引用引用一个**临时的值**而非对象。
注意：
1. 右值引用必须被初始化。不能`int &&i;`
2. 右值引用只能绑定临时值。不能`int &&i = b;`
```cpp
int &&i = 1;
int b = 2;
i = b;
b = 3;
std::cout << i << std::endl; // 2
```
相比较而言，左值引用只是对象的一个别名。
右值引用可以**延长值的生命周期**，并**完全接管**值的操作。比如：
```cpp
const std::string &i = "hello"; //声明后i不可修改
std::string &&i = "hello"; //i可变
i += " wow!"
std::cout << i << std::endl; // hello wow!
```
#### std::move
std::move可以将一个变量的值取出并成为右值。
```cpp
int b = 2;
int &&i = std::move(b);
```

#### 移动语义
传统c++没有移动的概念，一切视为拷贝。如果需要移动一个对象的值到另一个对象，就要把这个对象的值拷贝过去，然后销毁这个对象，造成了巨大的浪费。
而右值引用提供了不需要拷贝的方式：
```cpp
#include <iostream> // std::cout
#include <utility>  // std::move
#include <vector>   // std::vector
#include <string>   // std::string

int main() {

    std::string str = "Hello world.";
    std::vector<std::string> v;

    v.push_back(str); // 将使用 push_back(const T&), 即产生拷贝行为
    std::cout << "str: " << str << std::endl; // 将输出 "str: Hello world."

    v.push_back(std::move(str)); // 将使用 push_back(const T&&), 不会出现拷贝行为
    std::cout << "str: " << str << std::endl; // 这步操作后, str 中的值会变为空，将输出 "str: "

    return 0;
}
```

#### 完美转发
在传递参数时，并不区分左值右值，都当做左值传递。
使用`std:move`，可以把所有参数当右值传递。
使用`std::forward`，可以保留参数类型。
```cpp
#include <iostream>
#include <utility>
void reference(int& v) {
    std::cout << "左值引用" << std::endl;
}
void reference(int&& v) {
    std::cout << "右值引用" << std::endl;
}
template <typename T>
void pass(T&& v) {
    std::cout << "普通传参:";
    reference(v);
    std::cout << "std::move 传参:";
    reference(std::move(v));
    std::cout << "std::forward 传参:";
    reference(std::forward<T>(v));

}
int main() {
    pass(1);
    int v = 1;
    pass(v);
    return 0;
}
```


