---
layout: default
title: "swarmkit loadbalancer"
description: "swarmkit loadbalancer"
category: 
tags: [docker, network]
---

docker 1.12版本推出的swarm mode提供了service的负载均衡功能，我们窥一窥实现。

首先看看功能怎么使用。创建overlay网络，创建service加入网络，创建另一个体验负载均衡的service加入网络，查询`<service name>`返回VIP，查询`tasks.<service name>`返回所有task的IP。

    $ docker network create --driver overlay my-network
    $ docker service create --replicas 3 --network my-network --name my-web nginx
    $ docker service create --name my-busybox --network my-network busybox sleep 3000

    $ docker service ps my-busybox
    ID                         NAME              IMAGE    NODE      DESIRED STATE  CURRENT STATE            ERROR
    0urwetl5jfs9cphq7ggynja2y  my-busybox.1      busybox  manager1  Running        Running 12 minutes ago

    $ eval $(docker-machine env manager1)
    $ docker exec -it my-busybox.1.0urwetl5jfs9cphq7ggynja2y sh
    / # nslookup my-web
    Server:    127.0.0.11
    Address 1: 127.0.0.11

    Name:      my-web
    Address 1: 10.0.0.2
    / # nslookup tasks.my-web
    Server:    127.0.0.11
    Address 1: 127.0.0.11

    Name:      tasks.my-web
    Address 1: 10.0.0.4 my-web.2.14hggmn6m8rucruo2omt8wygt.my-network
    Address 2: 10.0.0.5 my-web.3.ehfb5ue134nyasq2g539uaa6g.my-network
    Address 3: 10.0.0.3 my-web.1.5yzoighbalqvio4djic464a9j.my-network
    / # wget -O- my-web
    Connecting to my-web (10.0.0.2:80)
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    ...
    
<img src="/images/service-vip.png" width="650px">

## 原理分析

task基本信息

service | container | ip vip | mac | node
--------|-----------|----|-----|-----
my-web | 5cca2a34de2b | 10.0.0.5 10.0.0.2 | 02:42:0a:00:00:05 | worker1
my-web | c00fffd5faba | 10.0.0.3 10.0.0.2 | 02:42:0a:00:00:03 | worker2
my-web | e6001f9a802e | 10.0.0.4 10.0.0.2 | 02:42:0a:00:00:04 | worker2
my-busybox | 8b876998b1c2 | 10.0.0.7 10.0.0.6 | 02:42:0a:00:00:07 | worker2

分别在host/overlay/container network namespace用ip/bridge/iptables/ipvsadm命令走一圈

	ip link/address/route/neigh
	ip netns exec overlay_namespace/container_namespace
	bridge fdb
	iptables filter/nat/mangle
	## 没有ipvsadm也可以用cat /proc/net/ip_vs
	ipvsadm

四个容器的network namespace都增加了ipvs配置，并且四个容器ipvs配置都相同

    root@worker1:/home/docker# ip netns exec 5cca2a34de2b ipvsadm
    IP Virtual Server version 1.2.1 (size=4096)
    Prot LocalAddress:Port Scheduler Flags
      -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
    FWM  257 rr
      -> 10.0.0.3:0                   Masq    1      0          0         
      -> 10.0.0.4:0                   Masq    1      0          0         
      -> 10.0.0.5:0                   Masq    1      0          0         
    FWM  260 rr
      -> 10.0.0.7:0                   Masq    1      0          0 
  
nat表的POSTROUTING chain增加了一条ipvs规则 `-A POSTROUTING -d 10.0.0.0/24 -m ipvs --ipvs -j SNAT --to-source 10.0.0.5`（127.0.0.11的规则是docker dns服务增加的规则），每个容器这条规则的`--to-source`都是容器自己的IP

    root@worker1:/home/docker# ip netns exec 5cca2a34de2b iptables -S -t nat
    -P PREROUTING ACCEPT
    -P INPUT ACCEPT
    -P OUTPUT ACCEPT
    -P POSTROUTING ACCEPT
    -N DOCKER_OUTPUT
    -N DOCKER_POSTROUTING
    -A OUTPUT -d 127.0.0.11/32 -j DOCKER_OUTPUT
    -A POSTROUTING -d 127.0.0.11/32 -j DOCKER_POSTROUTING
    -A POSTROUTING -d 10.0.0.0/24 -m ipvs --ipvs -j SNAT --to-source 10.0.0.5
    -A DOCKER_OUTPUT -d 127.0.0.11/32 -p tcp -m tcp --dport 53 -j DNAT --to-destination 127.0.0.11:38534
    -A DOCKER_OUTPUT -d 127.0.0.11/32 -p udp -m udp --dport 53 -j DNAT --to-destination 127.0.0.11:39353
    -A DOCKER_POSTROUTING -s 127.0.0.11/32 -p tcp -m tcp --sport 38534 -j SNAT --to-source :53
    -A DOCKER_POSTROUTING -s 127.0.0.11/32 -p udp -m udp --sport 39353 -j SNAT --to-source :53

mangle表OUTPUT chain增加了mark规则，四个容器规则相同

    root@worker1:/home/docker# ip netns exec 5cca2a34de2b iptables -S -t mangle
    -P PREROUTING ACCEPT
    -P INPUT ACCEPT
    -P FORWARD ACCEPT
    -P OUTPUT ACCEPT
    -P POSTROUTING ACCEPT
    -A OUTPUT -d 10.0.0.2/32 -j MARK --set-xmark 0x101/0xffffffff
    -A OUTPUT -d 10.0.0.6/32 -j MARK --set-xmark 0x106/0xffffffff

容器Overlay veth网卡多了一个secondary IP，IP地址是各个service的VIP

    root@worker1:/home/docker# ip netns exec 5cca2a34de2b ip ad
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        inet 127.0.0.1/8 scope host lo
           valid_lft forever preferred_lft forever
        inet6 ::1/128 scope host 
           valid_lft forever preferred_lft forever
    25: eth0@if26: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default 
        link/ether 02:42:0a:00:00:05 brd ff:ff:ff:ff:ff:ff
        inet 10.0.0.5/24 scope global eth0
           valid_lft forever preferred_lft forever
        inet 10.0.0.2/32 scope global eth0
           valid_lft forever preferred_lft forever
        inet6 fe80::42:aff:fe00:5/64 scope link 
           valid_lft forever preferred_lft forever
    27: eth1@if28: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
        link/ether 02:42:ac:12:00:03 brd ff:ff:ff:ff:ff:ff
        inet 172.18.0.3/16 scope global eth1
           valid_lft forever preferred_lft forever
        inet6 fe80::42:acff:fe12:3/64 scope link 
           valid_lft forever preferred_lft forever
       
学习下ipvs，不难看出这里使用的ipvs NAT模式实现了负载均衡，访问VIP时报文IP的替换发生在主动访问的容器中，简单的配置过程如下

三个容器或者三台机器，假设被访问的两个容器IP分别为10.250.1.2，10.250.1.3，给他们分配10.250.1.4的VIP，使用lvs做NAT负载均衡

    iptables -t mangle -A OUTPUT -d 10.250.1.4/32 -j MARK --set-mark 1
    ipvsadm -A -f 1 -s rr
    ipvsadm -a -f 1 -r 10.250.1.2:0 -m -w 1
    ipvsadm -a -f 1 -r 10.250.1.3:0 -m -w 1

`-set-mark 1`使报文通过OUTPUT chain时打上1的标记，`ipvsadm -A -f 1 -s rr`创建了FWMARK的virtual server，只要报文有1的标记，就会应用ipvs的规则，改变dest ip

    ip address add 10.0.0.2 dev eth1

新加的eth1的secondary ip主要是给容器通过vip访问到自己时使用

SNAT规则主要是用来给容器访问其他容器使用

    iptables -t nat -A POSTROUTING -d 10.0.0.0/24 -m ipvs --ipvs -j SNAT --to-source 10.0.0.5
    echo 1 > /proc/sys/net/ipv4/vs/conntrack

这样配置的load balance与其他PAAS思路不太相同，规则都配置在了容器的network namespace中，对容器中的应用有很大的干扰。并且容器的overlay网卡还多了一个secondary ip，看起来比较困惑，为什么要这么实现？能否在host/overlay network namespace配置ipvs规则达到相同的效果？


