---
layout: default
title: "Cache route in kernel module"
description: "Cache route in your kernel module"
category: "kernel"
tags: [kernel]
---

# 为什么要在自己的内核模块中缓存路由 

当前内核存储路由有两种算法：HASH算法和LC-trie算法。在编译内核的时候通过IP: advanced router选择。不论是哪种算法，在缓存路由时都根据了dest subnet进行索引，毕竟路由表的核心目的就是根据包的目的IP地址查询下一跳地址。但是笔者在写一个虚拟网卡驱动模块时，**需要根据gateway地址查询路由项**。笔者查遍内核的route(include/net/route.h)和fib相关函数，均没有方法可以通过gateway查询路由项。

# 解决方法

内核其实有提供route的watch接口，比如通过ip monitor route就可以实时监控路由表的所有变化。笔者不想对内核有任何侵入，猜想是否也可以在内核模块中也通过netlink socket watch路由表的变化？笔者验证后这种方法可行，下面分享下实现的代码。

# netlink socket

创建netlink socket monitor内核route变化，创建socket参数和sockaddr参考[go netlink](https://github.com/vishvananda/netlink/blob/a1c9a648f744c90cd1b03af9aa8bb1e92daa116f/route_linux.go#L1017)

```
size_t recvbuf_size = 2000;
unsigned char *recvbuf;
struct sock *sk;	/* ROUTE raw socket */
struct socket *sock;
struct sockaddr_nl nl_route_addr = {
	.nl_family = AF_NETLINK,
};
int rc;

nl_route_addr.nl_groups |= (1 << (RTNLGRP_IPV4_ROUTE - 1));

recvbuf = kmalloc(recvbuf_size, GFP_KERNEL);
if (!recvbuf) {
	pr_err("%s: Failed to alloc recvbuf.\n", __func__);
	rc = -1;
	goto fail;
}

rc = sock_create_kern(PF_NETLINK, SOCK_RAW, NETLINK_ROUTE, &sock);
if (rc < 0) {
	pr_err("NETLINK_ROUTE sock create failed, rc %d\n", rc);
	goto fail;
}
sk = sock->sk;

rc = kernel_bind(sock, (struct sockaddr *) &nl_route_addr,
				 sizeof(nl_route_addr));
if (rc < 0) {
	pr_err("bind for NETLINK_ROUTE sock %d\n", rc);
	goto fail;
}
```

销毁netlink socket

```
sk_release_kernel(sk);
sk = NULL;
if (recvbuf) {
	kfree(recvbuf);
}
```

# 内核线程

启动内核线程

```
struct task_struct *route_task;

route_task = kthread_create(route_thread, NULL, "my_route");
if(IS_ERR(route_task)){
	pr_err("Unable to start route kernel thread.\n");
	rc = PTR_ERR(route_task);
	route_task = NULL;
	goto fail;
}

wake_up_process(route_task);
```

销毁内核线程

```
if (route_task) {
	kthread_stop(route_task);
	route_task = NULL;
}
```

route_thread内核线程通过read socket接受netlink消息。

```
int route_thread(void *data) {
	int err;
	struct msghdr msg;
	struct kvec iov;
	int recvlen = 0;
	struct nlmsghdr *nh;
	struct fib_config cfg;
	pr_info("route thread started\n");
	while (!kthread_should_stop()) {
		iov.iov_base = recvbuf;
		iov.iov_len = recvbuf_size;
		msg.msg_name = NULL;
		msg.msg_namelen = 0;
		msg.msg_control = NULL;
		msg.msg_controllen = 0;
		msg.msg_flags = MSG_DONTWAIT;
		recvlen = kernel_recvmsg(sk->sk_socket, &msg, &iov, 1, recvbuf_size, msg.msg_flags);
		if (recvlen > 0) {
			for (nh = (struct nlmsghdr *) recvbuf; NLMSG_OK (nh, recvlen);
				 nh = NLMSG_NEXT (nh, recvlen)) {
				if (nh->nlmsg_type == NLMSG_DONE)
					break;
				if (nh->nlmsg_type == NLMSG_ERROR) {
					pr_warn("receive error nlmsg");
					break;
				}
				rtm_to_fib_config(nh, &cfg);
				if (cfg.fc_gw == 0)
					continue;
				// continue if dst device of the route is not us
				if (cfg.fc_oif != my_ifindex)
					continue;
				if (nh->nlmsg_type == RTM_NEWROUTE) {
					spin_lock_bh(&hash_lock);
					if ((err = my_route_add(cfg.fc_gw, cfg.fc_dst)) != 0) {
						pr_err("failed to add route, gateway %pI4, dst %pI4, err %d\n", &cfg.fc_gw, &cfg.fc_dst, err);
					}
					spin_unlock_bh(&hash_lock);
				} else if (nh->nlmsg_type == RTM_DELROUTE) {
					if ((err = my_route_delete(cfg.fc_gw)) != 0) {
						pr_err("failed to del route, gateway %pI4, dst %pI4, err %d\n", &cfg.fc_gw, &cfg.fc_dst, err);
					}
				}
			}
		} else {
			schedule_timeout_interruptible(msecs_to_jiffies(1000));
		}
	}
	return 0;
}
```

`rtm_to_fib_config`拷贝自fib_frontend.c并去掉了一些不需要的部分。

需要注意的是kernel_recvmsg调用，笔者通过给msg flag加上MSG_DONTWAIT而采用了非阻塞的方式，去掉flag后在停止route_thread时很容易hang住内核。阻塞方式读笔者尝试了很多方法，都会hang住内核。

# 创建Route Hash表

根据gateway地址缓存route项，通过rcu提供锁保护，参考vxlan模块缓存fdb实现

```
#define ROUTE_HASH_BITS	12
#define ROUTE_HASH_SIZE	(1<<ROUTE_HASH_BITS)

struct hlist_head	route_head[ROUTE_HASH_SIZE];
spinlock_t	  hash_lock;

struct my_route {
	struct hlist_node hlist;	/* linked list of entries */
	struct rcu_head	  rcu;
	__be32 gateway;
	__be32 dst;
};

static void init()
{
	spin_lock_init(&hash_lock);
	for (h = 0; h < ROUTE_HASH_SIZE; ++h)
		INIT_HLIST_HEAD(&route_head[h]);
}

/* Hash chain to use given gateway address */
static inline struct hlist_head *my_route_head(__be32 gateway)
{
	return &route_head[hash_32(gateway, ROUTE_HASH_BITS)];
}

static struct my_route *my_find_route(const __be32 gateway)
{
	struct hlist_head *head = my_route_head(gateway);
	struct my_route *f;

	hlist_for_each_entry_rcu(f, head, hlist) {
		if (gateway == f->gateway)
			return f;
	}
	return NULL;
}

/* Add new entry to route table -- assumes lock held */
static int my_route_add(const __be32 gateway, __be32 dst)
{
	struct my_route *f;
	f = my_find_route(gateway);
	if (f) {
		pr_warn("route gateway %pI4, dst %pI4 exist, new dst %pI4\n", &f->gateway, &f->dst, &dst);
		return -EEXIST;
	}
	f = kmalloc(sizeof(*f), GFP_ATOMIC);
	if (!f)
		return -ENOMEM;
	f->dst = dst;
	f->gateway = gateway;
	hlist_add_head_rcu(&f->hlist, my_route_head(gateway));
	pr_info("add route gateway: %pI4, dst %pI4\n", &gateway, &dst);
	return 0;
}

static void my_route_free(struct rcu_head *head)
{
	struct my_route *f = container_of(head, struct my_route, rcu);
	kfree(f);
}

static void my_route_destroy(struct my_route *f)
{
	pr_info("delete route %pI4\n", &f->gateway);
	hlist_del_rcu(&f->hlist);
	call_rcu(&f->rcu, my_route_free);
}

static int my_route_delete(__be32 gateway)
{
	struct my_route *f;
	int err = -ENOENT;
	spin_lock_bh(&hash_lock);
	f = my_find_route(gateway);
	if (f) {
		my_route_destroy(f);
		err = 0;
	}
	spin_unlock_bh(&hash_lock);
	return err;
}
```

# 

# 参考

- [fib系统分析](https://blog.csdn.net/viewsky11/article/details/53437092)
- [IPv4 route lookup on Linux](https://vincent.bernat.ch/en/blog/2017-ipv4-route-lookup-linux)
