---
layout: post
title: "tiny docker image"
description: ""
category: 
tags: [docker]
---
{% include JB/setup %}

# 静态与动态链接

Linux 系统当中有两类可执行程序：

* **静态链接** 可执行程序包含了其所需的全部库函数；所有库函数都连接到程序中。 这类程序是完整的，其运行不需要外部库的支持。 静态链接程序的优点之一是其安装之前不需要做环境准备工作

* **动态链接** 可执行程序要小得多；这类程序运行时需要外部共享 函数库的支持，因此好像并不完整。除了程序体小之外，动态链接允许程序包指定必须的库，而不必将库装入程序包内。动态链接技术还允许多个运行中的程序共享一个库，这样就不会出现同一代码的多份拷贝共占内存的情况了。由于这些原因，当前多数程序采用动态链接技术。

## 如何确定程序是否为静态链接？

使用ldd命令

```
[ian@echidna ~]$ ldd /sbin/sln /sbin/ldconfig /bin/ln
/sbin/sln:
        not a dynamic executable
/sbin/ldconfig:
        not a dynamic executable
/bin/ln:
        linux-vdso.so.1 =>  (0x00007fff644af000)
        libc.so.6 => /lib64/libc.so.6 (0x00000037eb800000)
        /lib64/ld-linux-x86-64.so.2 (0x00000037eb400000)

[ian@pinguino ~]$ # Fedora 8 32-bit
[ian@pinguino ~]$ ldd /bin/ln
        linux-gate.so.1 =>  (0x00110000)
        libc.so.6 => /lib/libc.so.6 (0x00a57000)
        /lib/ld-linux.so.2 (0x00a38000)
```

* linux-vdso.so.1，Linux Virtual Dynamic Shared Object，它只存在于程序的地址空间当中。 在旧版本系统中该库为 linux-gate.so.1。 该虚拟库为用户程序以处理器可支持的最快的方式 （对于特定处理器，采用中断方式；对于大多数最新的处理器，采用快速系统调用方式） 访问系统函数提供了必要的逻辑 。
* libc.so.6，具有指向 /lib64/libc.so.6. 的指针。
* 指向其他库的绝对路径。

## libc

Linux标准C库，其实是对系统调用的一个封装，提供给C语言更好用的接口

# docker container

docker container只是一个容器，并不是一个操作系统，它的文件系统只是一些内核外的软件包。所以docker container的文件系统其实可以不包含任何东西

## 制作一个0B最小的image

```
$ tar cv --files-from /dev/null | docker import - scratch
sha256:920d25467f2617c9317cdb116c65aaa59b4dd1d1231ceeb9481c504efaec676d
$ docker images | grep scratch
scratch    latest       920d25467f26      24 seconds ago      0 B
```

## 制作一个只有bash/ls命令的软件包

### 找到依赖包

通过ldd命令发现bash/ls是一个动态链接的软件，我们可以通过拷贝所以依赖的动态链接库文件，制作一个只有bash/ls命令的软件包。

```
# ldd /bin/bash /bin/ls
```
### 准备文件系统

创建一个文件系统目录rootfs目录，build是制作image的脚本，将所有依赖的动态链接库拷贝到rootfs/lib64目录，将bash/ls文件拷贝到bin目录下。

```
# tree 




```

```

## 制作一个静态链接的go image

制作一个helloworld的web server image

```
# cat hello.go
package main

import (
	"fmt"
	"net/http"
)

func helloHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "Hello World from Go in minimal Docker container")
}

func main() {
	http.HandleFunc("/", helloHandler)

	fmt.Println("Started, serving at 8080")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		panic("ListenAndServe: " + err.Error())
	}
}
```

### 静态编译

直接`go build`会使用`cgo`，编译为动态链接的方式

```
# go build hello.go 
```

编译时设置 `CGO_ENABLED=0` 关闭`cgo`方式，`-a`强制重新编译，`-ldflags '-s'`通过删除一些debug信息，使得二进制文件更小

```
# CGO_ENABLED=0 go build -a -ldflags '-s' hello.go 
```

### 制作镜像

```
# tar -cv hello | docker import - hello



# 参考

* [学习 Linux，101: 管理共享库](http://www.ibm.com/developerworks/cn/linux/l-lpic1-v3-102-3/)
* [Create The Smallest Possible Docker Container](http://blog.xebia.com/create-the-smallest-possible-docker-container/)
