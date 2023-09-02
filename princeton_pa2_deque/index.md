# [普林斯顿算法公开课]双向队列和随机队列




## 思路
这次的内容是写一个双向队列和随机队列, 双向队列自不必说, 用链表即可, 注意一下表头表尾的操作以及只有一个元素时的删除操作.
随机队列实现随机的时候需要查询具体下标的元素, 是一个O(1)操作, 所以使用自增长内存池实现.

刷到满分的过程中逐步解决的一些问题:
1.&nbsp;对题目要求的每一个Exception都要抛出.否则会有以下问题:
>* case test 失败
* 测试中断:
`Warning: the grading output was truncated due to excessive length.`

2.&nbsp;删除的节点和数组需要置null释放, 比如Deque出队的节点, RandomizedQueue出队的元素, 否则会报
>* `- loitering observed during 71 of 100 deletions`

3.&nbsp;注意RandomizedQueue的capacity大小调节的时机, 在size到达capacity一半时扩大, 在size到达capacity四分之一时减小.否则会有以下问题:
>* 不缩小capacity: 会导致内存测试失败
* 调节时机不对: 会导致一半的时间测试失败, 或者测试中断:
`Warning: the grading output was truncated due to excessive length.`
* size 不为正数的边界情况: 数组越界

= =这个capacity大小要求过于严格了, 导致我用自己习惯的增长方式没有AC...


## Deque.java

```java
/**
 * Created by chestnutheng on 16-11-14.
 */

import java.util.Iterator;

public class Deque<Item> implements Iterable<Item>{
    private Node first = null;
    private Node last = null;
    private int size = 0;
    private class Node
    {
        Item item;
        Node prev;
        Node next;
    }
    // construct an empty deque
    public Deque() {}
    // is the deque empty?
    public boolean isEmpty() {
        return size == 0;
    }
    // return the number of items on the deque
    public int size()   {
        return size;
    }
    // add the item to the front
    public void addFirst(Item item){
        if(item == null) {
            throw new java.lang.NullPointerException();
        }
        Node tv = new Node();
        tv.item = item;
        tv.next = first;
        if(first != null){
            first.prev = tv;
        }
        first = tv;
        size++;
        if(last == null){
            last = tv;
        }
    }
    // add the item to the end
    public void addLast(Item item) {
        if(item == null) {
            throw new java.lang.NullPointerException();
        }
        Node tv = new Node();
        tv.item = item;
        tv.next = null;
        tv.prev = last;
        if(last != null){
            last.next = tv;
        }
        last = tv;
        size++;
        if(first == null){
            first = tv;
        }
    }
    // remove and return the item from the front
    public Item removeFirst()   {
        if(isEmpty()){
            throw new java.util.NoSuchElementException();
        }
        Item item = first.item;
        first = first.next;
        if(first != null) {
            first.prev = null;
        }
        size--;
        if(size == 0){
            first = last = null;
        }
        return item;
    }
    // remove and return the item from the end
    public Item removeLast()   {
        if(isEmpty()){
            throw new java.util.NoSuchElementException();
        }
        Item item = last.item;
        last = last.prev;
        if(last != null) {
            last.next = null;
        }
        size--;
        if(size == 0){
            first = last = null;
        }
        return item;
    }
    // return an iterator over items in order from front to end
    public Iterator<Item> iterator(){
         class DequeIterator implements Iterator<Item>{
            private Node tv = first;
            public boolean hasNext() {
                return tv != null;
            }
            public void remove(){throw new java.lang.UnsupportedOperationException();}
            public Item next()
            {
                if(!hasNext()){
                    throw new java.util.NoSuchElementException();
                }
                Item item = tv.item;
                tv = tv.next;
                return item;
            }

        }
        return new DequeIterator();
    }
    // unit testing
    public static void main(String[] args) {
        Deque<String>deque = new Deque<>();
        deque.addLast("0");
        deque.removeLast();
        deque.size();
        deque.size();
        deque.isEmpty();
        deque.addFirst("5");
        deque.removeFirst();
        System.out.println(deque.size());
        deque.addLast("7");
        System.out.println(deque.removeFirst());
    }
}
```

## RandomizedQueue.java
```java
/**
 * Created by chestnutheng on 16-11-14.
 */
import java.util.Iterator;
import edu.princeton.cs.algs4.StdRandom;

public class RandomizedQueue<Item> implements Iterable<Item>{
    private int size = 0;
    private Item[] pool;
    // construct an empty randomized queue
    public RandomizedQueue(){
        pool = (Item[])new Object[5];
    }
    // check capacity size and resize
    private void check_capacity(){
        if(size == pool.length - 1){
            Item[] np = (Item[])new Object[size*2];
            for (int i = 0; i < size; ++i){
                np[i] = pool[i];
            }
            pool = np;
        }else if(size == pool.length/4 + 1 && size > 0){
            Item[] np = (Item[])new Object[size*2];
            for (int i = 0; i < size; ++i){
                np[i] = pool[i];
            }
            pool = np;
        }
    }
    // is the queue empty?
    public boolean isEmpty(){
        return size == 0;
    }
    // return the number of items on the queue
    public int size(){
        return size;
    }
    // add the item
    public void enqueue(Item item){
        if(item == null) {
            throw new java.lang.NullPointerException();
        }
        check_capacity();
        pool[size] = item;
        size++;
    }
    // remove and return a random item
    public Item dequeue(){
        if(isEmpty()){
            throw new java.util.NoSuchElementException();
        }
        int target = (int) (Math.random()*size);
        Item item = pool[target];
        pool[target] = pool[size - 1];
        pool[size - 1] = null;
        size--;
        check_capacity();
        return item;
    }
    // return (but do not remove) a random item
    public Item sample(){
        if(isEmpty()){
            throw new java.util.NoSuchElementException();
        }
        int target = (int) (Math.random()*size);
        return pool[target];
    }
    // return an independent iterator over items in random order
    public Iterator<Item> iterator(){
        class VectorIterator implements Iterator<Item>{
            private int helicopter = 0;
            private Item[] random_array;
            public VectorIterator(){
                random_array = (Item[])new Object[size];
                for (int i = 0; i < size; ++i){
                    random_array[i] = pool[i];
                }
                StdRandom.shuffle(random_array);
            }
            public boolean hasNext() {
                return helicopter < size;
            }
            public void remove(){throw new java.lang.UnsupportedOperationException();}
            public Item next() {
                if(!hasNext()){
                    throw new java.util.NoSuchElementException();
                }
                return random_array[helicopter++];
            }
        }
        return new VectorIterator();
    }
    //test client
    public static void main(String[] args){
        RandomizedQueue<Integer> r = new RandomizedQueue<>();
        r.enqueue(1);
        r.enqueue(2);
        r.dequeue();
        r.dequeue();
        for (int s:r
             ) {
            System.out.println(s);
        }
    }
}
```



