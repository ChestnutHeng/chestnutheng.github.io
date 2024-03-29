# [C++]C++ 11/14 笔记（一）




本部分介绍了c++11的崭新的类型推导、循环、模板和构造方法。
<!-- more -->

## 弃用的特性

1.　不允许以下赋值出现，应使用`const char *`后者`auto`。
```cpp
char *str = "hello world!";
```

2.　C语言风格的类型转换被弃用，应该使用 `static_cast`、`reinterpret_cast`、`const_cast` 来进行类型转换
3.　`register`， `auto_ptr`关键字被弃用。

## 语言增强
### 新的关键字
1. 使用`nullptr`而不是`NULL`。新的`nullptr`为`nullptr_t`类型，可以隐式转换为任何类型，同时避免了`NULL == 0`这种类型冲突。

2. `constexpr`函数：告诉编译器返回的值为常量表达式

### 类型推导
#### auto类型
1. auto型可以作为变量的声明类型，函数的返回类型
2. auto型作为函数参数在c++17中才可使用，但要注意重载的问题
3. auto不能用于数组的类型推导
迭代器的样例：
```cpp
for(auto itr = vec.cbegin(); itr != vec.cend(); ++itr);
```
#### decltype函数
返回值为一个类型。比如我们可以把z声明为推测的类型
```cpp
decltype(x+y) z = x + y;
```

### for(item:array)循环
像Python一样地迭代：
```cpp
std::vector<int> arr(5, 100);
// & 启用了引用, 如果没有则对 arr 中的元素只能读取不能修改
for(auto &i : arr) {
    std::cout << i << std::endl;
}
```
### 初始化列表
除了
1. 拷贝构造
2. () 构造函数初始化
加入了使用列表来初始化的特性：
```cpp
class Magic {
public:
    Magic(std::initializer_list<int> list) {}
};

Magic magic = {1,2,3,4,5};
std::vector<int> v = {1, 2, 3, 4};
```

### 模板的强化

#### 关键字
1. 外部模板`extern template`推迟模板的实例化
2. `>>`不再只是右移运算符，可以视作括号嵌套：
```cpp
std::vector<std::vector<int>> wow;
```

#### using提供的类型别名
using提供了以下的别名：
1. 函数指针作为新类型
2. 模板类型作为新类型
```cpp
typedef int (*func)(int *);  // 定义了一个返回类型为 int，参数为 int* 的函数指针类型，名字叫做 func
using func = int (*)(int *); // 同上, 更加直观

template <typename T>
using IntVec = std::vector<int>;    // 合法
IntVec v;
```

#### 默认模板类型
比如直接使用以下模板函数就可以不指定模板参数直接使用add：
```cpp
template<typename T = int, typename U = int>
auto add(T x, U y) -> decltype(x+y) {
    return x+y;
}
```

#### 变长参数模板
```cpp
template<typename... Ts> class Magic; //任意数量参数
template<typename Require, typename... Args> class Magic; //一个以上参数
```

### OO的增强
#### 委托构造
委托本类的其他构造函数构造
```cpp
class Base {
public:
    int value1;
    int value2;
    Base() {
        value1 = 1;
    }
    Base(int value) : Base() {  // 委托 Base() 构造函数
        value2 = 2;
    }
};

int main() {
    Base b(2);
    std::cout << b.value1 << std::endl;
    std::cout << b.value2 << std::endl;
}
```

#### 继承构造
在子类中使用父类的构造函数
```cpp
class Base {
public:
    int value1;
    int value2;
    Base() {
        value1 = 1;
    }
    Base(int value) : Base() {                          // 委托 Base() 构造函数
        value2 = 2;
    }
};
class Subclass : public Base {
public:
    int value3;
    Subclass(int value3, int value2) : Base(value2) {   // 继承父类构造
        this->value3 = value3;
    }
};
int main() {
    Subclass s(3,2);
    std::cout << s.value1 << std::endl;
    std::cout << s.value2 << std::endl;
    std::cout << s.value3 << std::endl;
}
```
#### 显式虚函数重载
1. 当重载虚函数时，引入`override`关键字将显式的告知编译器进行重载，编译器将检查基函数是否存在这样的虚函数，否则将无法通过编译
2. `final`则是为了防止类被继续继承以及终止虚函数继续重载引入的。

### 强类型枚举
类型安全的枚举类：
```cpp
enum class new_enum : unsigned int {
    value1,
    value2,
    value3 = 100,
    value4 = 100
};
// 内部可以比较
if (new_enum::value3 == new_enum::value4) {
    std::cout << "new_enum::value3 EQ new_enum::value4" << std::endl;
}
//重载 >>
template<typename T>
std::ostream& operator<<(typename std::enable_if<std::is_enum<T>::value, std::ostream>::type& stream, const T& e)
{
    return stream << static_cast<typename std::underlying_type<T>::type>(e);
}
//就可以直接输出
std::cout << new_enum::value3 << std::endl
```

