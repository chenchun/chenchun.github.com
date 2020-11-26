---
layout: default 
title: Chen Chun 
---

Currently working at [Tencent](https://en.wikipedia.org/wiki/Tencent).
I have been an engineer of the underlying infrastructure technology platform such as container platform based on [Kubernetes](https://kubernetes.io) and [Docker](https://www.docker.com/), data platform based on [Hadoop](http://hadoop.apache.org/).

# My project

- [ipo](https://github.com/chenchun/ipo) (private repo currently) is a kernel virtual network driver module which can be used to implement a high speed overlay network for containers.
- [ipset](https://github.com/chenchun/ipset) is a go bindings of [ipset](http://ipset.netfilter.org/) utility.
- [cgroupfs](https://github.com/chenchun/cgroupfs) provides an emulated /proc/meminfo, /proc/cpuinfo... for containers.
- [lctn](https://github.com/chenchun/lctn) is a simple command line program to run a process in a linux container.

# Open source contributions

I'm an active open source project contributors. The following are my contributions.

## Docker and Kubernetes ecosystem

I was a docker [libnetwork project maintainer](https://github.com/docker/libnetwork/pull/963)

- [Kubernetes](https://github.com/kubernetes/kubernetes/pulls?q=author%3Achenchun+)
- [Docker](https://github.com/moby/moby/pulls?q=is%3Apr+chenchun)
- [Libnetwork](https://github.com/docker/libnetwork/pulls?q=is%3Apr+chenchun)
- [Runc](https://github.com/opencontainers/runc/pulls?q=is%3Apr+ramichen)
- [Flannel](https://github.com/coreos/flannel/pulls?q=is%3Apr+chenchun)
- [Cadvisor](https://github.com/google/cadvisor/pulls?q=is%3Apr+author%3Achenchun+is%3Aclosed)
- [Netlink](https://github.com/vishvananda/netlink/pulls?q=is%3Apr+author%3Achenchun+)

## Hadoop and big data ecosystem

- [Hadoop/Hive/Ambari](https://issues.apache.org/jira/issues/?jql=assignee%20in%20(chenchun))
- [presto](https://github.com/prestodb/presto/pulls?q=is%3Apr+author%3Achenchun+is%3Aclosed)

## Linux Kernel

[Linux kernel](https://github.com/torvalds/linux/commit/c56050c700d18f18fbec934f56069150bcec3709)

# Talks

- In January 2016, as a guest speaker of "@Container Container Technology Conference 2016", [shared the "Docker Application Practice of Tencent Gaia Platform"](http://dockone.io/article/1555)
- In October 2018, as a guest of the China SACC2018, [shared the Tencent GaiaStack container product private cloud scenario practice](http://blog.itpub.net/31545813/viewspace-2217150/)

# Posts

<ul class="posts">
  {% for post in site.posts %}
  {% assign ym = post.date | date: "%Y%m" | plus:'0' %}
  {% if ym >= 201309 %}
    <li><span>{{ post.date | date: "%Y" }}</span> &raquo; <a href="{{ BASE_PATH }}{{ post.url }}">{{ post.title }}</a></li>
  {% endif %}
  {% endfor %}
</ul>

# Other posts

- I am one of the authors of the book ["Step by Step Docker"](https://www.zhihu.com/topic/20130661/hot) published in November 2016.
- [Hive SQL的编译过程](https://tech.meituan.com/2014/02/12/hive-sql-to-mapreduce.html)
- [Presto实现原理和美团的使用实践](https://tech.meituan.com/2014/06/16/presto.html)，发表在《程序员》2014.6月刊
