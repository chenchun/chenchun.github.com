---
layout: default
title: "4 ways to receive packets in network driver"
description: "4 ways to receive packets in network driver"
category: "network"
tags: [network, kernel]
---

内核的虚拟网卡如何收包？硬件网卡驱动如igb、ixgbe、e1000收包后，为什么会将包交给虚拟网卡处理？下面主要介绍虚拟网卡收包的4种方式。

# rx_handler

Bridge/OVS/Macvlan/Ipvlan等工作在L2的虚拟函数都采用这种方式从协议栈中收包，先来看使用方式

函数原型，返回RX_HANDLER_PASS表示skb沿着__netif_receive_skb_core的路径继续处理skb，返回RX_HANDLER_CONSUMED表示skb被这个函数处理完成了，__netif_receive_skb_core不需要继续处理。返回值枚举类型rx_handler_result在netdevice.h中有注释介绍。

```
static rx_handler_result_t my_handle_frame(struct sk_buff **pskb)
{
	struct sk_buff *skb = *pskb;
	if (not_interested(skb)) {
		return RX_HANDLER_PASS;
	}
	my_rx(skb);
	return RX_HANDLER_CONSUMED;
}
```

注册和卸载的代码

```
err = netdev_rx_handler_register(lowerdev, my_handle_frame, NULL);
if (err < 0) {
	pr_warn("register rx handler for dev %s err: %d\n", lowerdev->name, err);
	return err;
}

netdev_rx_handler_unregister(lowerdev)
```

lowerdev一般依赖在创建网卡时由用户态输入，比如`ip link add link eth0 name my0 type mydriver`

lowerdev与虚拟网卡的关系，一般在创建虚拟网卡时绑定这两者

```
struct my_dev {
	struct net_device	*dev;
	struct net_device	*lowerdev;
};

static int my_newlink(struct net *net, struct net_device *dev,
					   struct nlattr *tb[], struct nlattr *data[])
{
	int err;
	struct my_dev *mydev = netdev_priv(dev);
	struct net_device *lowerdev;

	if (!tb[IFLA_LINK]) {
		pr_warn("parent device not set\n");
		return -EINVAL;
	}

	lowerdev = __dev_get_by_index(net, nla_get_u32(tb[IFLA_LINK]));
	if (lowerdev == NULL) {
		pr_warn("device %d not exist\n", nla_get_u32(tb[IFLA_LINK]));
		return -ENODEV;
	}
	pr_info("my_newlink %s, slave dev %s\n", dev->name, lowerdev->name);

	if (!tb[IFLA_MTU])
		dev->mtu = lowerdev->mtu;
	else if (dev->mtu > lowerdev->mtu)
		return -EINVAL;

	if (lowerdev->type != ARPHRD_ETHER || lowerdev->flags & IFF_LOOPBACK)
		return -EINVAL;

	mydev->lowerdev = lowerdev;

	err = netdev_rx_handler_register(lowerdev, my_handle_frame, NULL);
	if (err < 0) {
		pr_warn("register rx handler for dev %s err: %d\n", lowerdev->name, err);
		return err;
	}

	err = register_netdevice(dev);
	if (err) {
		pr_warn("register dev %s err: %d\n", dev->name, err);
		goto rx_handler_unregister;
	}

	err = netdev_upper_dev_link(lowerdev, dev);
	if (err) {
		pr_warn("link dev %s with dev %s err: %d\n", lowerdev->name, dev->name, err);
		goto unregister_netdev;
	}

	return 0;

unregister_netdev:
	unregister_netdevice(dev);

rx_handler_unregister:
	netdev_rx_handler_unregister(lowerdev);
	return err;
}
```

卸载时注销

```
void my_dellink(struct net_device *dev, struct list_head *head)
{
	struct my_dev *mydev = netdev_priv(dev);
	netdev_upper_dev_unlink(mydev->lowerdev, dev);
	netdev_rx_handler_unregister(mydev->lowerdev);
	unregister_netdevice_queue(dev, head);
}
```

我们来看看调用rx_handler的代码，位于`__netif_receive_skb_core`

```
static int __netif_receive_skb_core(struct sk_buff *skb, bool pfmemalloc)
{
	...
	rx_handler = rcu_dereference(skb->dev->rx_handler);
	if (rx_handler) {
		if (pt_prev) {
			ret = deliver_skb(skb, pt_prev, orig_dev);
			pt_prev = NULL;
		}
		switch (rx_handler(&skb)) {
		case RX_HANDLER_CONSUMED:
			ret = NET_RX_SUCCESS;
			goto unlock;
		case RX_HANDLER_ANOTHER:
			goto another_round;
		case RX_HANDLER_EXACT:
			deliver_exact = true;
		case RX_HANDLER_PASS:
			break;
		default:
			BUG();
		}
	}
	...
}
```

# vlan

vlan的方式比较特殊，代码在__netif_receive_skb_core中处理

```
static int __netif_receive_skb_core(struct sk_buff *skb, bool pfmemalloc)
{
	...
	if (skb->protocol == cpu_to_be16(ETH_P_8021Q) ||
		skb->protocol == cpu_to_be16(ETH_P_8021AD)) {
		skb = vlan_untag(skb);
		if (unlikely(!skb))
			goto unlock;
	}
	...
	if (vlan_tx_tag_present(skb)) {
		if (pt_prev) {
			ret = deliver_skb(skb, pt_prev, orig_dev);
			pt_prev = NULL;
		}
		if (vlan_do_receive(&skb))
			goto another_round;
		else if (unlikely(!skb))
			goto unlock;
	}
	...
}
```

# L4协议号

ICMP/TCP/UDP/IGMP/UDP-Lite/IPIP/GRE等L4层协议全都采用`inet_add_protocol`这种方式注册协议处理的钩子函数，不同的是，前面几个都是L4层协议栈，后两者是虚拟网卡。

先看钩子函数原型

```
static int my_rx(struct sk_buff *skb)
{
	return 0;
}

static void my_err(struct sk_buff *skb, u32 info)
{
	
}

static const struct net_protocol net_my_protocol = {
	.handler     = my_rx,
	.err_handler = my_err,
	.netns_ok    = 1,
	.no_policy = 1,
};
```

注册/注销钩子函数，一般虚拟网卡在模块加载和卸载函数中调用

```
const int IPPROTO_MYPROTO = 143;

if (inet_add_protocol(&net_my_protocol, IPPROTO_MYPROTO) < 0) {
	pr_err("can't add protocol\n");
	return -EAGAIN;
}

inet_del_protocol(&net_my_protocol, IPPROTO_MYPROTO);
```

`inet_add_protocol`具体实现在`net/ipv4/protocol.c`，将各种L4 protocol对应的函数钩子保存在inet_protos数组中。`cmpxchg`是一个compare and swap的函数。

```
int inet_add_protocol(const struct net_protocol *prot, unsigned char protocol)
{
	if (!prot->netns_ok) {
		pr_err("Protocol %u is not namespace aware, cannot register.\n",
			protocol);
		return -EINVAL;
	}

	return !cmpxchg((const struct net_protocol **)&inet_protos[protocol],
			NULL, prot) ? 0 : -1;
}
```

`inet_protos`最终在`ip_local_deliver_finish`中使用，根据protocol字段调用相应的钩子函数处理。

```
	int protocol = ip_hdr(skb)->protocol;
	const struct net_protocol *ipprot;
	int raw;

resubmit:
	raw = raw_local_deliver(skb, protocol);

	ipprot = rcu_dereference(inet_protos[protocol]);
	if (ipprot != NULL) {
		int ret;

		if (!ipprot->no_policy) {
			if (!xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb)) {
				kfree_skb(skb);
				goto out;
			}
			nf_reset(skb);
		}
		ret = ipprot->handler(skb);
		if (ret < 0) {
			protocol = -ret;
			goto resubmit;
		}
		IP_INC_STATS_BH(net, IPSTATS_MIB_INDELIVERS);
	}
```

调用路径

```
 => my_rx
 => ip_local_deliver
 => ip_rcv_finish
 => ip_rcv
 => __netif_receive_skb_core
 => __netif_receive_skb
```


# UDP encap_rcv

这种方式的代表是虚拟网卡vxlan，vxlan是一种将完整二层包封装一个UDP头部的Overlay协议，它在收包时通过创建的内核态UDP socket收包。用户态创建vxlan网卡时可以指定vxlan协议使用的udp端口`ip link add vxlan0 type vxlan id 2 dev eth1 dstport 8472`。

在加载vxlan内核模块时，也可以自定义默认的udp端口（在创建vxlan网卡时不指定端口时使用此端口）

```
# default linux vxlan module port
$ cat /sys/module/vxlan/parameters/udp_port 
8472

# 新建vxlan.conf
# cat /etc/modprobe.d/vxlan.conf

#### Set the VXLAN UDP port ####
options vxlan udp_port=4789

# 重新加载vxlan模块
# rmmod vxlan
# modprobe -v vxlan
```

`vxlan_init_net`中注册vxlan收包函数的注册流程，先创建udp socket，再将socket的`encap_rcv`赋值为vxlan收包函数`vxlan_udp_encap_recv`

```
static __net_init int vxlan_init_net(struct net *net)
{
	struct vxlan_net *vn = net_generic(net, vxlan_net_id);
	struct sock *sk;
	struct sockaddr_in vxlan_addr = {
		.sin_family = AF_INET,
		.sin_addr.s_addr = htonl(INADDR_ANY),
	};
	int rc;
	unsigned h;

	/* Create UDP socket for encapsulation receive. */
	rc = sock_create_kern(AF_INET, SOCK_DGRAM, IPPROTO_UDP, &vn->sock);
	if (rc < 0) {
		pr_debug("UDP socket create failed\n");
		return rc;
	}
	/* Put in proper namespace */
	sk = vn->sock->sk;
	sk_change_net(sk, net);

	vxlan_addr.sin_port = htons(vxlan_port);

	rc = kernel_bind(vn->sock, (struct sockaddr *) &vxlan_addr,
			 sizeof(vxlan_addr));
	if (rc < 0) {
		pr_debug("bind for UDP socket %pI4:%u (%d)\n",
			 &vxlan_addr.sin_addr, ntohs(vxlan_addr.sin_port), rc);
		sk_release_kernel(sk);
		vn->sock = NULL;
		return rc;
	}

	/* Disable multicast loopback */
	inet_sk(sk)->mc_loop = 0;

	/* Mark socket as an encapsulation socket. */
	udp_sk(sk)->encap_type = 1;
	udp_sk(sk)->encap_rcv = vxlan_udp_encap_recv;
	udp_encap_enable();

	for (h = 0; h < VNI_HASH_SIZE; ++h)
		INIT_HLIST_HEAD(&vn->vni_list[h]);

	return 0;
}
```

UDP协议中调用encap_rcv的处理路径

```
int udp_queue_rcv_skb(struct sock *sk, struct sk_buff *skb)
{
	struct udp_sock *up = udp_sk(sk);
	...

	if (static_key_false(&udp_encap_needed) && up->encap_type) {
		int (*encap_rcv)(struct sock *sk, struct sk_buff *skb);

		/*
		 * This is an encapsulation socket so pass the skb to
		 * the socket's udp_encap_rcv() hook. Otherwise, just
		 * fall through and pass this up the UDP socket.
		 * up->encap_rcv() returns the following value:
		 * =0 if skb was successfully passed to the encap
		 *    handler or was discarded by it.
		 * >0 if skb should be passed on to UDP.
		 * <0 if skb should be resubmitted as proto -N
		 */

		/* if we're overly short, let UDP handle it */
		encap_rcv = ACCESS_ONCE(up->encap_rcv);
		if (skb->len > sizeof(struct udphdr) && encap_rcv != NULL) {
			int ret;

			ret = encap_rcv(sk, skb);
			if (ret <= 0) {
				UDP_INC_STATS_BH(sock_net(sk),
						 UDP_MIB_INDATAGRAMS,
						 is_udplite);
				return -ret;
			}
		}

		/* FALLTHROUGH -- it's a UDP Packet */
	}
	...
}
```

# 总结

从上面的4种方式看，其实虚拟网卡驱动在L2、L4收包路径上都可以注册自己的钩子函数。如果自研一个虚拟网卡驱动，除了vlan的方式，其他方式都是可以在自研代码中通过注册钩子函数实现的，不需要入侵内核。

笔者觉得也可以在L3层实现，通过在自研的内核模块中注册netfilter钩子函数就可以做到，不过目前内核的虚拟网卡驱动应该还没有这么用的。
