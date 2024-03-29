# [C++]C++ 11/14 笔记（三）



本部分介绍了c++11的容器、智能指针和正则。
<!-- more -->

### std::array
代替原来的c数组，提供了size()，empty()，大小比较以及迭代器。
注意：
1. 声明的第二个模板参数必须是编译期常量
2. 不能隐式转换为指针，调用data()返回c数组地址
```c++
std::array<int,4> arr = {1,2,3,4};

// C 风格接口传参
// foo(arr, arr.size());           // 非法, 无法隐式转换
foo(&arr[0], arr.size());
foo(arr.data(), arr.size());

// 使用 `std::sort`
std::sort(arr.begin(), arr.end());
```

### std::forward_list
单向实现的列表，提供了O(1)的插入，并且比双向更省空间。

### 无序容器
传统 C++ 中的有序容器 `std::map/std::set`，这些元素内部通过红黑树进行实现，插入和搜索的平均复杂度均为 O(log(size))。在插入元素时候，会根据 < 操作符比较元素大小并判断元素是否相同，并选择合适的位置插入到容器中。当对这个容器中的元素进行遍历时，输出结果会按照 < 操作符的顺序来逐个遍历。

而无序容器中的元素是不进行排序的，内部通过 Hash 表实现，插入和搜索元素的平均复杂度为 O(constant)，在不关心容器内部元素顺序时，能够获得显著的性能提升。

C++11 引入了两组无序容器：`std::unordered_map`, `std::unordered_multimap` 和`std::unordered_set`, `std::unordered_multiset`。

它们的用法和原有的`std::map/std::multimap/std::set/set::multiset`基本类似。

### std::tuple
提供了N元组的数据结构。
该数据结构在cpp14中还不够完善。

### 智能指针
在传统 C++ 里我们使用 new 和 delete 去『记得』对资源进行释放。而 C++11引入了智能指针的概念，使用了引用计数的想法，让程序员不再需要关心手动释放内存。这些智能指针包括 `std::shared_ptr/std::unique_ptr/std::weak_ptr`，使用它们需要包含头文件 `<memory>`。

#### std::shared_ptr
`std::shared_ptr`是一种智能指针，它能够记录多少个`shared_ptr`共同指向一个对象，从而消除显示的调用 `delete`，当引用计数变为零的时候就会将对象自动删除。
`std::make_shared`会分配创建传入参数中的对象，并返回这个对象类型的`std::shared_ptr`指针。
```cpp
std::shared_ptr<int> pointer = std::make_shared<int>(10);
(*pointer)++;
std::cout << *pointer << std::endl; // 11

// 离开作用域前，shared_ptr 会被析构，从而释放内存
```
`std::shared_ptr`可以通过`get()` 方法来获取原始指针，通过`reset()`来减少一个引用计数，并通过`get_count()`来查看一个对象的引用计数。

#### std::unique_ptr
`std::unique_ptr`是一种独占的智能指针，它禁止其他智能指针与其共享同一个对象，从而保证了代码的安全：
```cpp
std::unique_ptr<int> pointer = std::make_unique<int>(10);   // make_unique 从 C++14 引入
std::unique_ptr<int> pointer2 = pointer;    // 非法
```
在c++11中需要手动实现
```cpp
template<typename T, typename ...Args>
std::unique_ptr<T> make_unique( Args&& ...args ) {
    return std::unique_ptr<T>( new T( std::forward<Args>(args)... ) );
}
```
既然是独占，换句话说就是不可复制。但是，我们可以利用`std::move`将其转移给其他的`unique_ptr`。

#### std::weak_ptr
当对象相互引用导致内存泄露时，让其中一个使用`std::weak_ptr`就可以解决了。（弱引用）

### 正则
`std::regex`创建模式对象。（注意所有转义需要二次转义）
`std::regex_match(字符串, 模式对象)`会返回是否匹配（true & false）
```cpp
std::string fnames[] = {"foo.txt", "bar.txt", "test", "a0.txt", "AAA.txt"};
std::regex txt_regex("[a-z]+\\.txt");
for (const auto &fname: fnames)
    std::cout << fname << ": " << std::regex_match(fname, txt_regex) << std::endl;
```
更复杂的用法：
```cpp
std::regex base_regex("([a-z]+)\\.txt");
std::smatch base_match;
for(const auto &fname: fnames) {
    if (std::regex_match(fname, base_match, base_regex)) {
        // sub_match 的第一个元素匹配整个字符串
        // sub_match 的第二个元素匹配了第一个括号表达式
        if (base_match.size() == 2) {
            std::string base = base_match[1].str();
            std::cout << "sub-match[0]: " << base_match[0].str() << std::endl;
            std::cout << fname << " sub-match[1]: " << base << std::endl;
        }
    }
}
```


