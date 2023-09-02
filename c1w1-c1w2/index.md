# [深度学习]C1W1~C1W2




## C1W1: 什么是deep learning

### 单一神经元
deeplearning是模拟大脑的一种机器学习算法。以房价预测为例：

<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/c1w1-1.png" style="width: 500px"/>

上图把房子面积作为输入X，房价作为输出Y，通过拟合得到了一个一次函数
$$
Y=aX+b
$$
这个函数的负值均视为0，即使用了ReLU函数作为神经元的激活函数做了处理。
$$
f(x) = \max(aX+b, 0)
$$


Note: ReLU函数：f(x)=\max(0, x)，近年来使用ReLU函数代替sigmoid函数为计算速度做了巨大的提升。

看看更多特征的情况：
<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/c1w1-1.5.png" style="height: 250px" />

### 飞速发展
<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/dlc1w1-3.png" style="height: 300px" />

上图中可以看到传统算法和神经网络的效果的一个对比，在数据多的情况下神经网络有明显的优势。近年来以下的一些原因导致deep learning飞速发展成为主流
1. 计算速度飞速提升，使得训练较大的神经网络成为可能
2. 数据变多（labeled data 变多）

### 生命周期 
一个典型的深度学习的流程，即是一个Idea-Code-Train 的循环

<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/c1w1-2.png" style="height: 280px" />

## C1W2: 基本的神经网络

### 问题描述

<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/C1W2-1.png" style="height: 280px" />

这里从一个简单的问题开始说起：识别一个64x64的图像是否为猫：

每个像素有RGB三个值组成，64*64个像素就是12228个值。所以X可以表示为一个12228维的向量。Y则是0或1（是或不是猫咪）。

这里需要很多(X, Y)组成的labeled data数据用来学习。每个样本用如下的数学方式表示：
$$
X\in R^{n_x}, Y\in\{0,1\}   \qquad 其中n_x为每个图片的维度(12288)
$$
训练集可以用很多样本表示：
$$
\textrm{m training examples:   } \\\{(X^{(1)}, Y^{(1)}), (X^{(2)}, Y^{(2)}), ... ,(X^{(3)}, Y^{(3)})\\\}
$$
其中每个X都有n_x列，所以整个样本集可以表示为
$$
X\in R^{n_x\times m},Y \in R^{1 \times m}
$$

### 逻辑回归

#### Sigmoid函数

在开始正题之前，先看一个函数：
$$
\sigma(z) = \frac{1}{1+e^{-z}}
$$
如果Z为正无穷，这个函数将会是 1/(1+0) = 1

如果Z为负无穷，这个函数将会是1/bignum = 0

这个S型函数非常适用于取值0~1之间的x的映射。

同时，这个函数的导数也十分有趣：
$$
\begin{aligned}
f'(z) &= (\frac{1}{1+e^{-z}})'= \frac{e^{-z}}{(1+e^{-z})^{2}} = \frac{1+e^{-z}-1}{(1+e^{-z})^{2}}  
\\
&= \frac{1}{(1+e^{-z})}(1-\frac{1}{(1+e^{-z})}) 
\\
&= f(z)(1-f(z))
\\
\end{aligned}
$$


#### 逻辑回归

判断单一图片是否为猫的图片，可以表示为给定图片X，预估y为1的概率：
$$
\textrm{Given } x , \textrm{ want } \hat{y}=P(y=1|x) \qquad let \ x \in R^{n_x}, 0\leq\hat{y}\leq1
$$
设参数
$$
w \in R^{n_x},b \in R
$$
输出参数和X的乘积，然后用sigmoid做区间化：
$$
\hat{y} = \sigma(w^Tx+b)
$$
现在的问题就是从样本中估计出参数w和b的值。

#### Cost Function

我们对样本做训练的目标，就是使得w和b对每一个样本的估计都损失最小。用数学的语言就是：
$$
\hat{y} = \sigma(w^Tx+b),\textrm{ where }\sigma(z) = \frac{1}{1+e^{-z}}
$$

$$
\textrm{ Given } \\\{(X^{(1)}, Y^{(1)}),  ... ,(X^{(3)}, Y^{(3)})\\\}, \textrm{ want } \hat{y} \approx y
$$

$\hat{y}$和$y$之间的差距，就是我们的损失。我们当然可以用平方损失函数
$$
L(\hat{y}, y) = \frac{1}{2}(\hat{y}-y)^2
$$
不过这里却有更好的函数：
$$
L(\hat{y}, y) = -(y\log{\hat{y}} + (1-y)\log{(1-\hat{y})})
$$
当 y = 1时，$L(\hat{y}, y) = -\log{\hat{y}}$。如果要L小，就要$\hat{y}$尽可能大

当 y = 0 时，$L(\hat{y}, y)= -\log{(1-\hat{y})}$。如果要L小，就要$\hat{y}$尽可能小

这两条性质证明了这是个很好的损失函数。总的损失函数可以写成：

$$
J(w,b) = \frac{1}{m} \sum^{m}\_{i=1} L(\hat{y^{(i)}}, y^{(i)}) = -\frac{1}{m} \sum^{m}\_{i=1}(y^{(i)}\log{\hat{y^{(i)}}} + (1-y^{(i)})\log{(1-\hat{y^{(i)}})})
$$


#### 梯度下降

我们要找到上述函数J(w,b)的最小值。J(w,b)可能是下面的简化曲线：

<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/C1W2-2.png" style="height: 150px" />

假设我们先随机初始化w和b，在曲线上左上方的某一点。要让J的值变小，可以增加w的值。如果点在曲线的右上方，我们就需要减少w的值。事实上增加或减少w的值是有J对w的导数决定的。我们可以每次运行：
$$
w := w - \alpha \frac{dJ(w,b)}{dw} \qquad \alpha为学习速率，后面的是偏导数
$$
还有参数b：
$$
b := b - \alpha \frac{dJ(w,b)}{db} \qquad \alpha为学习速率，后面的是偏导数
$$
学习速率是用来决定每次参数迈的步子的大小。事实上J不会是一个凸函数，所以他拥有多个最小值，学习速率可以帮助参数不收敛到局部最小值。

#### 计算图

计算图可以让我们清晰地通过反向传播计算每个参数的导数。如下是一个代价函数求导的例子：

<img src="http://chestnutheng-blog-1254282572.file.myqcloud.com/C1W2-3.png" style="height: 250px" />

反向传播是一个从后向前的计算导数的过程，可以避免重复的计算。

先求根据上面的损失函数求出da：
$$
\frac{dL(a,y)}{da}=\frac{dL}{da} = -\frac{y}{a}+\frac{1-y}{1-a}
$$
然后求出dz：
$$
\frac{dL}{dz}=\frac{dL}{da} \cdot \frac{da}{dz} = (-\frac{y}{a}+\frac{1-y}{1-a})a(1-a)=(a-1)y+(1-y)a=a-y
$$
参数的导数更加容易：
$$
\frac{dL}{dw_1}=\frac{dL}{da} \cdot \frac{da}{dz} \cdot \frac{dz}{dw_1}=\frac{dL}{dz} \cdot \frac{dz}{dw_1}=\frac{dL}{dz} \cdot x_1
$$
链式求导可以很方便地运用在程序中，只要先记下前几步求导的值。同理，
$$
dw_2=dz \cdot x_2 , \quad db=dz
$$

#### Vectorization

现在已经做完了所有求得参数的准备工作。一个标准的过程可以被表示为：

```matlab
J = 0; dw1 = 0; dw2 = 0; db = 0
# 遍历样本
for i = 1 to m:
  z(i) = w * x(i) + b
  a(i) = theta(z(i))
  J += -(y(i)log(a(i)) + (1-y(i))log(1-a(i)))
  dz(i) = a(i) - y(i)
  dw1 += x1(i)*dz(i)
  dw2 += x2(i)*dz(i)
  ...
  db += dz(i)
J /= m
dw1 /= m; dw2 /= m; db /= m
```

在实际的计算中，分步去算参数的值非常不利于GPU进行加速。矩阵化运算可以提速400倍以上。下面是本次PA，也就是整个模型的全过程：

```python
train_set_x_orig, train_set_y, test_set_x_orig, test_set_y, classes = load_dataset()
train_set_x_flatten = train_set_x_orig.reshape(train_set_x_orig.shape[0], -1).T
test_set_x_flatten = test_set_x_orig.reshape(test_set_x_orig.shape[0], -1).T
def sigmoid(z):
    s = 1/(1+np.exp(-z))
    return s
def init(dim):
    w = np.zeros(dim).reshape(dim,1)
    b = 0
    return w,b
def propagate(w, b, X, Y):
    m = X.shape[1]
    A = sigmoid(np.dot(w.T, X)+b)                   # compute activation
    cost = -1/m*np.sum(Y*np.log(A) + (1-Y)*np.log(1-A))         # compute cost
    dw = 1/m*np.dot(X, (A-Y).T)
    db = 1/m*np.sum(A-Y)
    cost = np.squeeze(cost)
    grads = {"dw": dw, "db": db}
    return grads, cost
def optimize(w, b, X, Y, num_iterations, learning_rate, print_cost = False):
    costs = []
    for i in range(num_iterations):
        grads, cost = propagate(w, b, X, Y)
        dw = grads["dw"]
        db = grads["db"]
        w = w - learning_rate*dw
        b = b - learning_rate*db
        if i % 100 == 0:
            costs.append(cost)
        if print_cost and i % 100 == 0:
            print ("Cost after iteration %i: %f" %(i, cost))
    params = {"w": w, "b": b}
    grads = {"dw": dw, "db": db}
    return params, grads, costs
def predict(w, b, X):
    m = X.shape[1]
    Y_prediction = np.zeros((1,m))
    w = w.reshape(X.shape[0], 1)
    A = sigmoid(np.dot(w.T, X) + b)
    for i in range(A.shape[1]):
        Y_prediction[0][i] = 1 if A[0][i] > 0.5 else 0
    return Y_prediction

def model(X_train, Y_train, X_test, Y_test, num_iterations = 2000, learning_rate = 0.5, print_cost = False):
    # initialize parameters with zeros (≈ 1 line of code)
    w, b = init(X_train.shape[0])
    # Gradient descent (≈ 1 line of code)
    parameters, grads, costs = optimize(w, b, X_train, Y_train, num_iterations, learning_rate, print_cost)
    # Retrieve parameters w and b from dictionary "parameters"
    w = parameters["w"]
    b = parameters["b"]
    # Predict test/train set examples (≈ 2 lines of code)
    Y_prediction_test = predict(w, b, X_test)
    Y_prediction_train = predict(w, b, X_train)
    # Print train/test Errors
    print("train accuracy: {} %".format(100 - np.mean(np.abs(Y_prediction_train - Y_train)) * 100))
    print("test accuracy: {} %".format(100 - np.mean(np.abs(Y_prediction_test - Y_test)) * 100))
    d = {"costs": costs,
         "Y_prediction_test": Y_prediction_test, 
         "Y_prediction_train" : Y_prediction_train, 
         "w" : w, 
         "b" : b,
         "learning_rate" : learning_rate,
         "num_iterations": num_iterations}
    
    return d

d = model(train_set_x, train_set_y, test_set_x, test_set_y, num_iterations = 2000, learning_rate = 0.005, print_cost = True)
```




