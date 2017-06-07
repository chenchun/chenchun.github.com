---
layout: post
title: "transaction"
description: ""
category: 事务
tags: [java, 并发]
---

## 事务的四大特性

原子性，一致性，隔离性，持久性

## 原子性

一个原子事务要么完整执行，要么干脆不执行。 这意味着，工作单元中的每项任务都必须正确执行。如果有任一任务
执行失败，则整个工作单元或事务就会被终止。即此前对数据所作的任何修改都将被撤销。如果所有任务都被成功执
行，事务就会被提交，即对数据所作的修改将会是永久性的。

### Java AtomicInteger的原子性——比较并交换CAS

## mysql行锁

### 共享锁

共享锁官方解释非常绕，其实意思就是：

A: select;

B: select lock in share mode;

C: begin; select lock in share mode; update;

(事务为autocommit)

* 任务时候A都可以。

* 当有C操作或者其他行锁(譬如：begin; select for update)时，另一个连接的B操作不允许。当C操作commit之后，B操作可以进行

* 当无行锁时，多个连接的B操作是允许的。
