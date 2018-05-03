---
layout: default
title: "Implementing kubernetes network policy"
description: "Implementing kubernetes network policy"
category: "network"
tags: [network, kubernetes]
---

# Kubernetes network policy

A policy example yaml from [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-network-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: db
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - ipBlock:
        cidr: 172.17.0.0/16
        except:
        - 172.17.1.0/24
    - namespaceSelector:
        matchLabels:
          project: myproject
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 6379
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/24
    ports:
    - protocol: TCP
      port: 5978
```

I made a picture to translate the below code.

<img src="/images/kubernetes-network-policy/policy-ingress.png"/>

As the picture says, only three ingress traffic can access role:db pods' 6379/TCP port in default namespace. The picture doesn't contain egress policy part which follows the same rule.

# Design

Kubernetes network policy is superset of multi-tenent network which is a namespace level policy, because it accounts to pod level. Based on this, it may be impossible to implement it by network protocols such as VXLAN.

`Iptables` is suitable for filtering packets based on protocols, ips and ports. But it has a fatal weakness that kernel travel accross chain rules one by one to determine if packets match them. Consider the selected pods' ips by `namespaceSelector` and `podSelector` in `ingress.from`, they may be a sparse set, if using iptables, we have to write many rules which is quite ineffient. This brings `ipset` which uses hash map or bloom filter to match ips or ports. So the basic design is using `iptables` along with `ipset`.

<img src="/images/kubernetes-network-policy/policy-ipset.png"/>

- `ipset` `hash:ip` is used to match `namespaceSelector` and `podSelector`
- `ipset` `hash:net` is used to match `ipBlock`, `ipset` supports nomatch option to except serveral cases
- For `ports` part, we can make same protol ports a single iptables rule by using multiport iptables extension to match them

The ingress rule may be as follows is there is no `bridge` in your cni network

<img src="/images/kubernetes-network-policy/policy-ingress.png"/>

and egress rule may be

<img src="/images/kubernetes-network-policy/policy-egress.png"/>

# Implementation tips

You must be careful on creating or deleting iptables rules and ipsets.

- delete iptables rules first than ipsets if they reference some later ones
- delete iptables rules which referencing chain B first before deleting chain B
- use iptables-save and iptables-restore to do batch inserting or deleting whenever possible
