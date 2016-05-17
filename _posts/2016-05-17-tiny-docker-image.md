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
# ldd /bin/bash /bin/ls/bin/bash:	linux-vdso.so.1 =>  (0x00007fff2d0c3000)	/$LIB/libonion.so => /lib64/libonion.so (0x00007f764bb5c000)	libtinfo.so.5 => /lib64/libtinfo.so.5 (0x00007f764b822000)	libdl.so.2 => /lib64/libdl.so.2 (0x00007f764b61e000)	libc.so.6 => /lib64/libc.so.6 (0x00007f764b25d000)	libpthread.so.0 => /lib64/libpthread.so.0 (0x00007f764b041000)	/lib64/ld-linux-x86-64.so.2 (0x00007f764ba4c000)/bin/ls:	linux-vdso.so.1 =>  (0x00007ffc5ef75000)	/$LIB/libonion.so => /lib64/libonion.so (0x00007f488af55000)	libselinux.so.1 => /lib64/libselinux.so.1 (0x00007f488ac20000)	libcap.so.2 => /lib64/libcap.so.2 (0x00007f488aa1b000)	libacl.so.1 => /lib64/libacl.so.1 (0x00007f488a812000)	libc.so.6 => /lib64/libc.so.6 (0x00007f488a451000)	libdl.so.2 => /lib64/libdl.so.2 (0x00007f488a24d000)	libpthread.so.0 => /lib64/libpthread.so.0 (0x00007f488a031000)	libpcre.so.1 => /lib64/libpcre.so.1 (0x00007f4889dd0000)	liblzma.so.5 => /lib64/liblzma.so.5 (0x00007f4889bab000)	/lib64/ld-linux-x86-64.so.2 (0x00007f488ae45000)	libattr.so.1 => /lib64/libattr.so.1 (0x00007f48899a6000)
```
### 准备文件系统

创建一个文件系统目录rootfs目录，build是制作image的脚本，将所有依赖的动态链接库拷贝到rootfs/lib64目录，将bash/ls文件拷贝到bin目录下。

```
# tree .|-- build`-- rootfs    |-- bin    |   |-- bash    |   `-- ls    `-- lib64        |-- ld-2.17.so        |-- ld-linux-x86-64.so.2 -> ld-2.17.so        |-- libacl.so.1 -> libacl.so.1.1.0        |-- libacl.so.1.1.0        |-- libattr.so.1 -> libattr.so.1.1.0        |-- libattr.so.1.1.0        |-- libc-2.17.so        |-- libc.so.6 -> libc-2.17.so        |-- libcap.so.2 -> libcap.so.2.22        |-- libcap.so.2.22        |-- libdl-2.17.so        |-- libdl.so.2 -> libdl-2.17.so        |-- liblzma.so.5 -> liblzma.so.5.0.99        |-- liblzma.so.5.0.99        |-- libonion.so -> libonion_security.so.1.0.13        |-- libonion_security.so.1.0.13        |-- libpcre.so -> libpcre.so.1.2.0        |-- libpcre.so.1        |-- libpcre.so.1.2.0        |-- libpthread-2.17.so        |-- libpthread.so.0 -> libpthread-2.17.so        |-- libselinux.so -> libselinux.so.1        |-- libselinux.so.1        |-- libtinfo.so -> libtinfo.so.5        |-- libtinfo.so.5 -> libtinfo.so.5.9        `-- libtinfo.so.5.93 directories, 29 files
# cat build cd rootfstar cv * | docker import - lscd ..
```
### 制作镜像

```# ./build bin/bin/bashbin/lslib64/lib64/libpcre.solib64/libattr.so.1lib64/libselinux.so.1lib64/libtinfo.so.5.9lib64/libtinfo.solib64/libonion.solib64/libcap.so.2.22lib64/libcap.so.2lib64/libonion_security.so.1.0.13lib64/libc.so.6lib64/libpthread.so.0lib64/libtinfo.so.5lib64/liblzma.so.5lib64/libselinux.solib64/ld-linux-x86-64.so.2lib64/libdl-2.17.solib64/libdl.so.2lib64/libpcre.so.1.2.0lib64/libc-2.17.solib64/libpcre.so.1lib64/liblzma.so.5.0.99lib64/libacl.so.1lib64/libattr.so.1.1.0lib64/libacl.so.1.1.0lib64/ld-2.17.solib64/libpthread-2.17.so3bb85eb1065a1d9aafc578866a8011472c13915338b56b55315d343b914f59f2
# docker images | grep lsls                            latest              3bb85eb1065a        51 seconds ago      4.907 MB# docker run -it ls bash   bash-4.2# ls -al /bin/                                                                                                                                                                      total 1080drwxr-xr-x  2 0 0   4096 May 17 01:40 .drwxr-xr-x 12 0 0   4096 May 17 03:09 ..-rwxr-xr-x  1 0 0 968840 May 17 01:40 bash-rwxr-xr-x  1 0 0 117616 May 16 10:03 lsbash-4.2# envbash: env: command not foundbash-4.2# exitexit
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
# go build hello.go # ldd ./hello	linux-vdso.so.1 =>  (0x00007fff729f4000)	/$LIB/libonion.so => /lib64/libonion.so (0x00007f2b5820a000)	libpthread.so.0 => /lib64/libpthread.so.0 (0x00007f2b57ede000)	libc.so.6 => /lib64/libc.so.6 (0x00007f2b57b1d000)	libdl.so.2 => /lib64/libdl.so.2 (0x00007f2b57919000)	/lib64/ld-linux-x86-64.so.2 (0x00007f2b580fa000)
```

编译时设置 `CGO_ENABLED=0` 关闭`cgo`方式，`-a`强制重新编译，`-ldflags '-s'`通过删除一些debug信息，使得二进制文件更小

```
# CGO_ENABLED=0 go build -a -ldflags '-s' hello.go # ldd ./hello	not a dynamic executable
```

### 制作镜像

```
# tar -cv hello | docker import - hellohello54b07c3ecd349750418b65998b350e5878e97dc77d7cbfe542d078817e840210
# docker run -d -p 8090:8080 --name hello hello /hello78c66a5f7332274ac080dfc8e410314085c5b48b6a60b611ea3d88ddcd242051# docker logs helloStarted, serving at 8080# curl http://127.0.0.1:8090/Hello World from Go in minimal Docker container```


# 参考

* [学习 Linux，101: 管理共享库](http://www.ibm.com/developerworks/cn/linux/l-lpic1-v3-102-3/)
* [Create The Smallest Possible Docker Container](http://blog.xebia.com/create-the-smallest-possible-docker-container/)

