---
layout: default
title: "Play with crosvm on ubuntu"
description: "Play with crosvm on ubuntu"
category: "vmm"
tags: [vmm, crosvm]
---

[crosvm](https://chromium.googlesource.com/chromiumos/platform/crosvm)
is the Chrome OS virtual machine monitor. AWS [Firecracker](https://github.com/firecracker-microvm/firecracker) starts from crosvm and now they both share common A set of VMM building blocks such as kvm-bindings, kvm-ioctls, linux-loader, vmm-sys-util, vm-memory in [rust-vmm](https://github.com/rust-vmm).

This post is based on a post [Quick hack: Experiments with crosvm](https://www.collabora.com/news-and-blog/blog/2017/11/09/quick-hack-experiments-with-crosvm/) and covered some solutions playing crosvm on ubuntu.

## Build kernel(optional)

You can also bypass this and use installed ubuntu kernel image on your ubuntu.

```
cd ~/src
git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux
git checkout v4.12
#make x86_64_defconfig
#make bzImage
cp /boot/config-$(uname -r) .config
make oldconfig # choosing all default options is fine
make -j8 deb-pkg
sudo dpkg -i ../linux-image-4.12.0_4.12.0-2_amd64.deb # install initrd.img and vmlinuz 
cd .. 
```

## Build minijail

```
cd ~/project/vm/
git clone https://android.googlesource.com/platform/external/minijail
cd minijail
make
cd .. 
```

## Prerequisite before building crosvm

```
sudo apt-get install libusb-1.0-0-dev libfdt-dev

# suppose you wish to clone everything about crosvm into ~/project/vm/chrome, clone adhd first
mkdir -p ~/project/vm/chrome/third_party/
cd ~/project/vm/chrome/third_party/
git clone https://chromium.googlesource.com/chromiumos/third_party/adhd
```

## Build crosvm

```
mkdir -p ~/project/vm/chrome/platform/
cd ~/project/vm/chrome/platform/
git clone https://chromium.googlesource.com/a/chromiumos/platform/crosvm
cd crosvm
LIBRARY_PATH=~/project/vm/minijail cargo build 
```

## Generate rootfs

```
cd ~/src/crosvm
dd if=/dev/zero of=rootfs.ext4 bs=1K count=1M
mkfs.ext4 rootfs.ext4
mkdir rootfs/
sudo mount rootfs.ext4 rootfs/
debootstrap testing rootfs/
sudo umount rootfs/
```

Change root password

```
chroot rootfs
unshare -m bash
mount --make-rslave /
passwd root

# might have to fsck when starting vm at next step
fsck /dev/vda
```

## Run crosvm

Please update `initrd.img-4.13.0-46-generic` and `vmlinuz-4.13.0-46-generic` with previous installed kernel or installed ubuntu kernel if necessary

```
sudo LD_LIBRARY_PATH=~/project/vm/minijail/ ./target/debug/crosvm run --disable-sandbox --rwroot rootfs.ext4 --seccomp-policy-dir=./seccomp/x86_64/ -i /boot/initrd.img-4.13.0-46-generic /boot/vmlinuz-4.13.0-46-generic
```

## Reference

- [Compile Linux with initrd and cmdline](https://gist.github.com/tklengyel/6082a4227ab824cfebd9101e9e8f8095)
- [Quick hack: Experiments with crosvm](https://www.collabora.com/news-and-blog/blog/2017/11/09/quick-hack-experiments-with-crosvm/)

