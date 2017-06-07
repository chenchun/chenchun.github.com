---
layout: default
title: "hibernate cancel query"
description: ""
category: hibernate
tags: [hibernate, java]
---

今天想做一个导出excel的功能，杀掉长时间没有反应的查询，最开始的思路是通过`concurrent`包使用子线程执行，在主线程通过`future`在超时后取消掉查询。

## 其他线程kill实现方式

	ExecutorService executor = Executors.newSingleThreadExecutor();
	Future<List<List<String>>> future = executor
        .submit(new Callable<List<List<String>>>() {
            @Override
            public List<List<String>> call() throws Exception {
                return excelService.getBySql(safeSql);
            }   
        }); 
	log.info("after " + String.valueOf(second) + "second");
	try {
    	List<List<String>> datas = future.get(second, TimeUnit.SECONDS);
	    map = createAjaxSuccessMap();
    	map.put("datas", datas);
    	map.put("sql", safeSql);
	} catch (TimeoutException te) {
    	excelService.cancelQuery();
	    future.cancel(true);
	    map = createAjaxFailureMap("查询超时"); 
	}

	public void cancelQuery() {
    	hibernateTemplate.execute(new HibernateCallback<Object>() {
        	@Override
	        public Object doInHibernate(Session session) throws HibernateException, SQLException {
	            session.cancelQuery();
    	        return null;
        	}   
	    }); 
	}

后来通过`mysql`客户端`show processlist`查看当前的连接，发现cancelQuery不好使，查询依然继续执行。

`hibernate` `cancelQuery`方法上的注释说
***This is the sole method on session which may be safely called from another thread.***（这是session提供的唯一一个可以通过另外一个线程调用的方法）

也找到了作者写这个方法的需求的源头`http://www.java2s.com/Questions_And_Answers/JPA/Query/cancel.htm`

但是查询仍然没有取消，最后还是找到`mysql jdbc`驱动[官方文档说明](http://dev.mysql.com/doc/refman/5.5/en/connector-j-reference-implementation-notes.html)发现了问题的根源，取消查询有两种方式：

- ***不建议使用`statement.cancel()`方法***。因为这个方法是不确定的，它底层是使用的mysql的<a href="http://dev.mysql.com/doc/refman/5.5/en/kill.html">kill query</a>去杀掉当前连接connection正在执行的查询，如果当前没有正在执行的查询，它会杀掉下一个查询。

- ***建议使用`statement.setQueryTimeout()`方法***。这种方式实际是在当前线程中设置的查询超时时间，不需要其他线程的帮助，所以数据库连接connection没有改变。

## Timeout实现


	protected List<Object[]> findBySql(final String sql, final int timeout) {
	    return (List<Object[]>) hibernateTemplate.executeFind(new HibernateCallback() {
	        @Override
	        public Object doInHibernate(Session session) throws HibernateException, SQLException {
    	        SQLQuery sqlQuery = session.createSQLQuery(sql);
    	        sqlQuery.setTimeout(timeout);
            	return sqlQuery.list();
        	}   
    	}); 
	}
	
## TODO
对于上面的代码而言，其实关键在于子线程中`session`和主线程中的`session`是否是使用的一个`connection`，这就要看`hibernate`的实现了（<span style='color:blue'>TODO:详细了解一下hibernate中session的分配</span>）。
