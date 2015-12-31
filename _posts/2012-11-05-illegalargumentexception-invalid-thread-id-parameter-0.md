---
layout: post
title: "IllegalArgumentException Invalid thread ID parameter: 0"
description: ""
category: bug
tags: [jdk, java]
---
{% include JB/setup %}

## Bug

今天配`solrcloud`，1 `shard`，3 `replicator`。运行起来后，其中1个实例的`Thread Dump`报错，提示`Invalid thread ID parameter: 0`。

hack了一下`solr`源代码，在`ThreadDumpHandler`里面添加了一些log。

	ThreadMXBean tmbean = ManagementFactory.getThreadMXBean();
	long[] tids = tmbean.getAllThreadIds();
	log.info("all threads tids:" + (tids == null? "null" :tids.length));
	if (tids != null) {
	  for (long l :tids) {
	    log.info(String.valueOf(l));
	  }
	  log.info("all thread infos:");
	  NamedList<SimpleOrderedMap<Object>> lst = new NamedList<SimpleOrderedMap<Object>>();
	  for (long l :tids) {
	    if (l > 0) {
	      ThreadInfo ti = tmbean.getThreadInfo(l, Integer.MAX_VALUE);
	      if (ti != null) {
	        log.info(ti.toString());
	        lst.add( "thread", getThreadInfo( ti, tmbean ) );
	      }
	    } else {
	      log.info("invalid thread id:" + l);
	    }

	  }
	  system.add( "threadDump", lst );
	}


发现id为0的线程是`Thread[QuorumPeer:/0.0.0.0:9983,5,main]`，`zookeeper`的一个线程。

## ThreadInfo

`ThreadInfo`不仅包含`Thread`的一些信息，还包含一些额外的信息，比如线程状态、线程阻塞原因、线程调用堆栈等。

如果只是想知道`Thread`的id，name，classloader，通过下面这种方式就可以得到

	List<Field> fields = new ArrayList<Field>();
	try {
	    Field f = Thread.class.getDeclaredField("contextClassLoader");
	    fields.add(f);
	    f.setAccessible(true);
	} catch (NoSuchFieldException e) {
	    e.printStackTrace();
	}
	try {
	    Field f = Thread.class.getDeclaredField("tid");
	    fields.add(f);
	    f.setAccessible(true);
	} catch (NoSuchFieldException e) {
	    e.printStackTrace();
	}
	for (Thread thread : Thread.getAllStackTraces().keySet()) {
	    for (Field f : fields) {
	        try {
	            System.out.println(f.getType().getName() + ":" + f.getName() + "=" 
	                    + f.get(thread));
	        } catch (IllegalAccessException e) {
	        }   
	    }   
	    System.out.println();
	}

然而分别用这两种方式，得到的结果却不一样，这个线程`Thread[QuorumPeer:/0.0.0.0:9983,5,main]`通过第一种方式得到的线程id是0，而第二种方式却是27，是不是很诡异。线程id为0时，通过 `sun.management.ThreadImpl.getThreadInfo(0) ` 会抛出一个`IllegalArgumentException "Invalid thread ID parameter: xxx"`

看`jdk`的代码，发现这两种方式得到所有`Thread`实例的方法`sun.management.ThreadImpl.getThreads()` 和 `java.lang.Thread.getThreads()` 都是`native`的。于是搞出jdk c的源码看了一下，这两个方法在c中底层实际是调用的一个方法，所以是没有区别的。都是调用的`jvm.h`中声明的下面这个方法。
`ThreadImpl.getThreadInfo`也是一个`native`方法调用，依赖于`ThreadImpl.getThreads()`，所以问题就是为什么C底层实现是一样的，得到的`Thread Id`不一样呢。。//<span style='color:blue'>TODO 仔细check jdk c源代码</span>

	JNIEXPORT jobjectArray JNICALL
	JVM_GetAllThreads(JNIEnv *env, jclass dummy);


## 解决

最后还是在`stackoverflow`上面得到了一个满意的[答案](http://stackoverflow.com/questions/13081425/invalid-thread-id-parameter-0-java-how-could-this-happen)，感谢国际友人，他发现这是`jdk`的一个bug [6404306](http://bugs.sun.com/bugdatabase/view_bug.do?bug_id=6404306)，其实这个bug参考[6412693](http://bugs.sun.com/bugdatabase/view_bug.do?bug_id=6412693)，6412693还是一个open状态。。大意是说可以看到部分初始化的`JNI attached threads`
