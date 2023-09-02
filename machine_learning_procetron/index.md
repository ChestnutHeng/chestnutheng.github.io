# [机器学习]感知机






# 机器学习基石笔记 感知机



## 损失函数
给定一个数据集  $T =\{(x_1,y_1),(x_2,y_2),\cdots,(x_N,y_N)\}$  ,  其中    $x = R^n \, , y=\{+1,-1\}$ 

若存在超平面S   $w\cdot x + b = 0$  能将所有的正负实例点分到两侧，则称数据集是线性可分的，否则称线性不可分。
任意一点$x_0$到超平面的距离为
$$\frac{1}{||w||}|w\cdot x_0 + b|$$
对于误分类数据$(x_i,y_i)$来说，
$-y_i(w\cdot x_i + b) > 0$

有误分类点到超平面距离
$$-\frac{1}{||w||}y_i|w\cdot x_0 + b|$$

则所有误分类点到超平面距离为
$$-\frac{1}{||w||}\sum_{x_i \in m }y_i|w\cdot x_0 + b|$$

所以感知机$sign(w\cdot x + b)$学习损失函数为
$$L(w,b) = -\sum_{x_i \in m }y_i|w\cdot x_0 + b|$$

## 学习算法
1. 选取初值$w_0,b_0$
2. 在训练集中选取数据$(x_i,y_i)$
3. 如果$y_i(w\cdot xi+ b) \leq 0$（分类错误）
$$w \leftarrow w + x_iy_i$$

4. 转至2，直至没有误分类点。

## 收敛性
令$R=\max || x_i ||  $ ，
令$\rho = \min \frac{W_f}{||W_f||}x_iy_i$
则有修正次数
$$k \leq \frac{R^2}{\rho ^2}$$

下面给出证明。
由
$$W\_k \cdot W\_f = W\_{k-1} W\_f + x\_i y\_i \geq W\_{k-1} + \rho \geq \cdots \geq k \rho$$

得
$$||w\_k||^2=||w\_{k-1} + x\_i y\_i||^2=||w\_{k-1}||^2 + 2w\_{k-1}x\_iy\_i+||x\_iy\_i||^2 \leq ||w\_{k-1}||^2 +||x\_iy\_i||^2 \leq ||w\_{k-1}||^2 + R^2$$

故
$$||w\_k||^2\leq ||w_{k-1}||^2 + R^2 \leq \cdots \leq kR^2$$

故  
$$k \rho \leq w_k\cdot w_f \leq ||w_k|| \cdot ||w_f|| \leq ||w_k|| \leq \sqrt k  R$$

故  $k \rho \leq \sqrt k R$,易得$k \leq \frac{R^2}{\rho ^2}$，得证。

## 其他性质
1. 一般用加上速度后的修正式：$ w \leftarrow w + \eta \cdot x_iy_i$ 来修正直线。
2. 读入数据的次序是影响修正次数的。

## 示范代码
```python
	import numpy as np

	def sign(x):
		if x < 0:
			return -1
		else:
			return 1

	w = np.array([0.,0.,0.,0.,0.])
	halts = 0
	speed = 1
	f = open('pla.dat')

	while True:
		data = f.readline()
		if data == '':
			break
		datas = data.split('\t')
		xi = np.array([float(i) for i in ('1 ' + datas[0]).split()])
		yi = float((datas[1].split())[0])
		if not abs(yi) == 1 :
			exit(1)
		if not sign(np.inner(w,xi)) == yi:
			w = w + speed * yi * xi
			print("W: " + str(w))
			halts += 1
		
	print('Halts :' + str(halts))
```


