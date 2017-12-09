---
layout: default
title: "tensorflow helloworld"
description: "tensorflow"
category: "ml"
tags: [tensorflow, ml]
---

## mac cpu 安装

直接用pip裸装很可能遇到因为要卸载某个mac系统依赖的python包而导致Operation not permitted，比如我就遇到

```
Installing collected packages: six, html5lib, bleach, protobuf, futures, numpy, tensorflow-tensorboard, pbr, funcsigs, mock, backports.weakref, enum34, tensorflow
  Found existing installation: six 1.4.1
    DEPRECATION: Uninstalling a distutils installed project (six) has been deprecated and will be removed in a future version. This is due to the fact that uninstalling a distutils project will only partially uninstall the project.
    Uninstalling six-1.4.1:
Exception:
Traceback (most recent call last):
  File "/Library/Python/2.7/site-packages/pip-9.0.1-py2.7.egg/pip/basecommand.py", line 215, in main
    status = self.run(options, args)
  File "/Library/Python/2.7/site-packages/pip-9.0.1-py2.7.egg/pip/commands/install.py", line 342, in run
    prefix=options.prefix_path,
  File "/Library/Python/2.7/site-packages/pip-9.0.1-py2.7.egg/pip/req/req_set.py", line 778, in install
    requirement.uninstall(auto_confirm=True)
  File "/Library/Python/2.7/site-packages/pip-9.0.1-py2.7.egg/pip/req/req_install.py", line 754, in uninstall
    paths_to_remove.remove(auto_confirm)
  File "/Library/Python/2.7/site-packages/pip-9.0.1-py2.7.egg/pip/req/req_uninstall.py", line 115, in remove
    renames(path, new_path)
  File "/Library/Python/2.7/site-packages/pip-9.0.1-py2.7.egg/pip/utils/__init__.py", line 267, in renames
    shutil.move(old, new)
  File "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/shutil.py", line 302, in move
    copy2(src, real_dst)
  File "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/shutil.py", line 131, in copy2
    copystat(src, dst)
  File "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/shutil.py", line 103, in copystat
    os.chflags(dst, st.st_flags)
OSError: [Errno 1] Operation not permitted: '/var/folders/6c/gzgsfbkn1t1_m47l18q_95d40000gn/T/pip-gF9xBt-uninstall/System/Library/Frameworks/Python.framework/Versions/2.7/Extras/lib/python/six-1.4.1-py2.7.egg-info'
```

这里推荐使用官网介绍的virtualenv方式安装

```
# 设置新python虚拟环境的目录
$ targetDirectory=~/tensorflow
$ sudo easy_install pip
$ pip install --upgrade virtualenv
$ virtualenv --system-site-packages $targetDirectory # for Python 2.7

# 进入新的python虚拟环境
$ source ~/tensorflow/bin/activate
(tensorflow)$ 

# 安装TensorFlow
(tensorflow)$ easy_install -U pip
(tensorflow)$ pip install --upgrade tensorflow      # for Python 2.7

# 确认安装成功
(tensorflow)$ python -c "import tensorflow"

# 退出虚拟环境
(tensorflow)$ deactivate
# 卸载虚拟环境
$ rm -r ~/tensorflow
```

## 张量(tensor)与计算图

坐标超过两维的数组。一个数组中的元素分布在若干维坐标的规则网格中，我们称之为张量。

一个TensorFlow core程序包含两个部分：

1. 创建计算图
2. 运行计算图

创建一个简单的计算图

<img src="/images/tensorflow-1.png"/>

```
from __future__ import print_function
import tensorflow as tf
node1 = tf.constant(3.0, dtype=tf.float32)
node2 = tf.constant(4.0) # also tf.float32 implicitly
node3 = tf.add(node1, node2)
sess = tf.Session()
print("node3:", node3)
print("sess.run(node3):", sess.run(node3))
print(sess.run([node1, node2]))
# node3: Tensor("Add:0", shape=(), dtype=float32)
# sess.run(node3): 7.0
# [3.0, 4.0]
```

## placeholders

在计算图中，可以创建placeholders，表示将在以后赋值

```
a = tf.placeholder(tf.float32)
b = tf.placeholder(tf.float32)
adder_node = a + b  # + provides a shortcut for tf.add(a, b)
print(sess.run(adder_node, {a: 3, b: 4.5}))
print(sess.run(adder_node, {a: [1, 3], b: [2, 4]}))
# 7.5
# [ 3.  7.]
```

## Variables

Variables代表计算图中的可以被训练的参数，使用初始值和类型创建一个Variable。
Constants的值不会变化，在调用tf.constant的时候就被初始化好了。但是Variables不会在tf.Variable的时候初始化，需要调用tf.global_variables_initializer显示初始化

```
W = tf.Variable([.3], dtype=tf.float32)
b = tf.Variable([-.3], dtype=tf.float32)
x = tf.placeholder(tf.float32)
linear_model = W*x + b
init = tf.global_variables_initializer()
sess.run(init)
print(sess.run(linear_model, {x: [1, 2, 3, 4]}))
# [ 0.          0.30000001  0.60000002  0.90000004]
```

上面的代码就创建好了一个模型，为了检验这个模型的好坏，我们需要创建一个placeholder y表示期望值，并且创建一个loss函数来计算模型的运算值与期望值的差距。
`tf.square(linear_model - y)`创建了一个向量，每个元素表示一个样例数据的模型运算值与期望值的差距。`tf.reduce_sum`将所有误差值统一成一个标量（一个标量就是一个单独的数）

```
y = tf.placeholder(tf.float32)
squared_deltas = tf.square(linear_model - y)
loss = tf.reduce_sum(squared_deltas)
print(sess.run(loss, {x: [1, 2, 3, 4], y: [0, -1, -2, -3]}))
# 23.66
```

## tf.train API

TensorFlow提供了optimizers来缓慢的改变每个variable来最小化loss函数，最简单的optimizer就是梯度下降(gradient descent)。梯度下降算法modifies each variable according to the magnitude of the derivative of loss with respect to that variable.

```
optimizer = tf.train.GradientDescentOptimizer(0.01)
train = optimizer.minimize(loss)
sess.run(init) # reset values to incorrect defaults.
for i in range(1000):
  sess.run(train, {x: [1, 2, 3, 4], y: [0, -1, -2, -3]})

print(sess.run([W, b]))
# [array([-0.9999969], dtype=float32), array([ 0.99999082], dtype=float32)]
```

这样我们就完成了一个机器学习的过程，完整的代码如下：

```
import tensorflow as tf

# Model parameters
W = tf.Variable([.3], dtype=tf.float32)
b = tf.Variable([-.3], dtype=tf.float32)
# Model input and output
x = tf.placeholder(tf.float32)
linear_model = W*x + b
y = tf.placeholder(tf.float32)

# loss
loss = tf.reduce_sum(tf.square(linear_model - y)) # sum of the squares
# optimizer
optimizer = tf.train.GradientDescentOptimizer(0.01)
train = optimizer.minimize(loss)

# training data
x_train = [1, 2, 3, 4]
y_train = [0, -1, -2, -3]
# training loop
init = tf.global_variables_initializer()
sess = tf.Session()
sess.run(init) # reset values to wrong
for i in range(1000):
  sess.run(train, {x: x_train, y: y_train})

# evaluate training accuracy
curr_W, curr_b, curr_loss = sess.run([W, b, loss], {x: x_train, y: y_train})
print("W: %s b: %s loss: %s"%(curr_W, curr_b, curr_loss))
# W: [-0.9999969] b: [ 0.99999082] loss: 5.69997e-11
```

## tf.estimator

tf.estimator是TensorFlow提供的一个高层次的API，简化了机器学习的若干过程：运行train循环；运行评估循环；管理数据
tf.estimator定义了很多常见的模型

```
# NumPy is often used to load, manipulate and preprocess data.
import numpy as np
import tensorflow as tf

# Declare list of features. We only have one numeric feature. There are many
# other types of columns that are more complicated and useful.
feature_columns = [tf.feature_column.numeric_column("x", shape=[1])]

# An estimator is the front end to invoke training (fitting) and evaluation
# (inference). There are many predefined types like linear regression,
# linear classification, and many neural network classifiers and regressors.
# The following code provides an estimator that does linear regression.
estimator = tf.estimator.LinearRegressor(feature_columns=feature_columns)

# TensorFlow provides many helper methods to read and set up data sets.
# Here we use two data sets: one for training and one for evaluation
# We have to tell the function how many batches
# of data (num_epochs) we want and how big each batch should be.
x_train = np.array([1., 2., 3., 4.])
y_train = np.array([0., -1., -2., -3.])
x_eval = np.array([2., 5., 8., 1.])
y_eval = np.array([-1.01, -4.1, -7, 0.])
input_fn = tf.estimator.inputs.numpy_input_fn(
    {"x": x_train}, y_train, batch_size=4, num_epochs=None, shuffle=True)
train_input_fn = tf.estimator.inputs.numpy_input_fn(
    {"x": x_train}, y_train, batch_size=4, num_epochs=1000, shuffle=False)
eval_input_fn = tf.estimator.inputs.numpy_input_fn(
    {"x": x_eval}, y_eval, batch_size=4, num_epochs=1000, shuffle=False)

# We can invoke 1000 training steps by invoking the  method and passing the
# training data set.
estimator.train(input_fn=input_fn, steps=1000)

# Here we evaluate how well our model did.
train_metrics = estimator.evaluate(input_fn=train_input_fn)
eval_metrics = estimator.evaluate(input_fn=eval_input_fn)
print("train metrics: %r"% train_metrics)
print("eval metrics: %r"% eval_metrics)
```

运行结果如下

```
train metrics: {'average_loss': 5.8584249e-11, 'global_step': 1000, 'loss': 2.3433699e-10}
eval metrics: {'average_loss': 0.0025258244, 'global_step': 1000, 'loss': 0.010103297}
```

## 自定义模型

```
import numpy as np
import tensorflow as tf

# Declare list of features, we only have one real-valued feature
def model_fn(features, labels, mode):
  # Build a linear model and predict values
  W = tf.get_variable("W", [1], dtype=tf.float64)
  b = tf.get_variable("b", [1], dtype=tf.float64)
  y = W*features['x'] + b
  # Loss sub-graph
  loss = tf.reduce_sum(tf.square(y - labels))
  # Training sub-graph
  global_step = tf.train.get_global_step()
  optimizer = tf.train.GradientDescentOptimizer(0.01)
  train = tf.group(optimizer.minimize(loss),
                   tf.assign_add(global_step, 1))
  # EstimatorSpec connects subgraphs we built to the
  # appropriate functionality.
  return tf.estimator.EstimatorSpec(
      mode=mode,
      predictions=y,
      loss=loss,
      train_op=train)

estimator = tf.estimator.Estimator(model_fn=model_fn)
# define our data sets
x_train = np.array([1., 2., 3., 4.])
y_train = np.array([0., -1., -2., -3.])
x_eval = np.array([2., 5., 8., 1.])
y_eval = np.array([-1.01, -4.1, -7., 0.])
input_fn = tf.estimator.inputs.numpy_input_fn(
    {"x": x_train}, y_train, batch_size=4, num_epochs=None, shuffle=True)
train_input_fn = tf.estimator.inputs.numpy_input_fn(
    {"x": x_train}, y_train, batch_size=4, num_epochs=1000, shuffle=False)
eval_input_fn = tf.estimator.inputs.numpy_input_fn(
    {"x": x_eval}, y_eval, batch_size=4, num_epochs=1000, shuffle=False)

# train
estimator.train(input_fn=input_fn, steps=1000)
# Here we evaluate how well our model did.
train_metrics = estimator.evaluate(input_fn=train_input_fn)
eval_metrics = estimator.evaluate(input_fn=eval_input_fn)
print("train metrics: %r"% train_metrics)
print("eval metrics: %r"% eval_metrics)
```

运行结果：

```
train metrics: {'loss': 1.3885429e-10, 'global_step': 1000}
eval metrics: {'loss': 0.010101625, 'global_step': 1000}
```

