# [算法]最大值栈和最大值队列




# 最大值栈和最大值队列(Tsinghua OJ,PA2) 

## 最大值栈

### 要求
以O(1)的时间查询栈中的最大值.
### 思路
维护一个最大值栈，在原栈中数据发生改变时最大值栈也跟着改变。
每次输入一个数据，若最大值栈为空，则比较最大值栈栈顶和当前元素，如果当前元素较大或相等，就把当前元素推入栈中，反之出栈时，如果出栈元素和当前元素相等，则把最大值栈中元素也推出栈。
### 实现

```c++
	template <typename T>
	class MaxStack
	{
	private:
		Stack <T> max_stack;
		Stack <T> _data;
	public:
		T max(){
			return max_stack.top();
		}
		void push(T ele){
			_data.push(ele);
			if(max_stack.empty() || ele >= max_stack.top()){
				max_stack.push(ele);
			}
		}
		T pop(){
			T tmp = _data.top();
			if(_data.pop() == max_stack.top()){
				max_stack.pop();
			}
			return tmp;
		}
	};
```

## 最大值队列

### 要求
用o(n)时间查询队列的最大值
### 思路
用两个最大值栈模拟队列。入队时把元素压入栈A，出队时弹出B的栈顶。（若B为空，则把A中元素全部弹出压入B再弹出）。取最大值时去A，B中的最大值的最大值。
### 输入
第一行仅含一个整数，即高度查询和车辆出入操作的总次数n
以下n行，依次这n次操作。各行的格式为以下几种之一:

1. E x		//有一辆高度为x的车进入隧道（x为整数）
2. D		//有一辆车离开隧道
3. M		//查询此时隧道中车辆的最大高度

### 输出

若D和M操作共计m次，则输出m行
对于每次D操作，输出离开隧道车辆的高度
对于每次M操作，输出所查询到的最大高度

### 实现

```c++
	#include "Stack.h"
	#include <iostream>
	#include <cstdio>

	using namespace std;


	template <typename T>
	class MaxStack
	{
	private:
		Stack <T> max_stack;
		Stack <T> _data;
	public:
		bool empty(){
			return _data.empty();
		}
		T max(){
			return max_stack.top();
		}
		void push(T ele){
			_data.push(ele);
			if(max_stack.empty() || ele >= max_stack.top()){
				max_stack.push(ele);
			}
		}
		T pop(){
			T tmp = _data.top();
			if(_data.pop() == max_stack.top()){
				max_stack.pop();
			}
			return tmp;
		}
		T top(){
			return _data.top();
		}
	};

	template <typename T>
	class MaxQueue{
	private:
		MaxStack <T> s1,s2;

	public:
		bool empty(){
			return s1.empty() && s2.empty();
		}
		void enqueue(T ele){
			s1.push(ele);
		}
		T dequeue(){
			if(s2.empty()){
				while(!s1.empty()){
					s2.push(s1.top());
					s1.pop();
				}
			}
			return s2.pop();
		}
		T front(){
			if(s2.empty()){
				while(!s1.empty()){
					s2.push(s1.top());
					s1.pop();
				}
			}
			return s2.top();
		}
		T max(){
			if((!s1.empty()) && (!s2.empty()))
				return (s1.max() > s2.max() ? s1.max() : s2.max());
			else if ((!s1.empty()) && (s2.empty()))
				return s1.max();
			else return s2.max();
		}
	};

	int main(int argc, char const *argv[])
	{
		MaxQueue <int>queue;

		int n;
		cin >> n;
	
		for (int i = 0; i < n; ++i) {
			char op[2];
			scanf("%s", op);
			if (*op == 'E') {
				int num;
	 			cin >> num;
				queue.enqueue(num);
			} else if (*op == 'D') {
				printf("%d\n", queue.front());
				queue.dequeue();
			} else {
				printf("%d\n", queue.max());;
			}
		}
	
		return 0;
	}
```
