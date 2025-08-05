---
title: "[mysql]事务和隔离"
date: 2023-05-29T20:38:29+08:00
lastmod: 2023-05-29T20:38:29+08:00
draft: true
description: "本文介绍事务的使用和隔离级别。"
tags: ["数据库", "mysql"]
categories: ["数据库"]
---

Read uncommitted
A事务可以读取B事务未提交的数据

异常情况
* 脏读：B回滚，A读的数据错误

Read committed

Repeatable read

Serializable


# 死锁

获取不到锁
```mysql
mysql>  CREATE TABLE test( 
`id` bigint NOT NULL DEFAULT '0',
UNIQUE KEY `uk_entity_id` (`id`)
);
Query OK, 0 rows affected (0.11 sec)

mysql> begin;
mysql>  insert into test value(5);
--- 于此同时，在其他链接里
	mysql> begin;
	mysql> insert into test value(5);
	ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
	mysql> rollback;
--- 其他链接结束
mysql>  rollback;
```


事务的更改对其他事务不可见
```mysql
mysql> begin;
Query OK, 0 rows affected (0.04 sec)

mysql> insert into test value(5);
Query OK, 1 row affected (0.04 sec)

mysql> select * from test;
+----+
| id |
+----+
|  5 |
+----+
1 row in set (0.22 sec)

--- 于此同时，在其他链接里
	mysql> begin;
	Query OK, 0 rows affected (0.22 sec)
	
	mysql> select * from test;
	Empty set (0.39 sec
--- 其他链接结束
```


```log
Type: InnoDB
Name: 
Status: 
=====================================
2023-07-14 11:16:47 140325158688512 INNODB MONITOR OUTPUT
=====================================
Per second averages calculated from the last 2 seconds
-----------------
BACKGROUND THREAD
-----------------
srv_master_thread loops: 23985694 srv_active, 0 srv_shutdown, 13380 srv_idle
srv_master_thread log flush and writes: 0
----------
SEMAPHORES
----------
OS WAIT ARRAY INFO: reservation count 1420322109
OS WAIT ARRAY INFO: signal count 1439839584
RW-shared spins 0, rounds 0, OS waits 0
RW-excl spins 0, rounds 0, OS waits 0
RW-sx spins 0, rounds 0, OS waits 0
Spin rounds per wait: 0.00 RW-shared, 0.00 RW-excl, 0.00 RW-sx
------------------------
LATEST DETECTED DEADLOCK
------------------------
2023-07-14 10:46:34 140328265680640
*** (1) TRANSACTION:
TRANSACTION 4822490389, ACTIVE 3 sec inserting
mysql tables in use 1, locked 1
LOCK WAIT 4 lock struct(s), heap size 1128, 2 row lock(s), undo log entries 1
MySQL thread id 3654528, OS thread handle 140325251184384, query id 40042973372 dc03-pff-200-feb0-5019-442d-b624.byted.org fdbd:dc03:ff:200:feb0:5019:442d:b624 eco6444116921_w update
/* psm=ecom.mmc.budget_platform, ip=fdbd:dc03:10:620::195, ip=- */ INSERT /* psm=ecom.mmc.budget_platform, logid=202307141046220102102261064417AD9, ip=fdbd:dc03:10:620::195, pid=230 */  INTO `t_pro_budget_account` (`account_id`,`biz_entity_id`,`sub_entity_id`,`biz_entity_type`,`biz_entity_code`,`budget_flow_type`,`total_amount`,`used_amount`,`cost_amount`,`frozen_amount`,`refund_amount`,`refund_status`,`gmv`,`biz_field1`,`biz_field2`,`biz_field3`,`biz_field4`,`biz_field5`,`version`,`extra`,`deleted_time`,`create_time`,`update_time`,`not_count_cost`,`last_cost_time`,`accrual_cost_amount`,`is_repay_spend`) VALUES ('7255500243079299368','109305399','2023','EffectObjShop','',2,3754716,0,0,0,0,0,0,'2023','','7188161946133250365','','',0,'{\"distribute_amount\":3754716}',0,'2023-07-14 10:46:31.724949385','2023-07-14 10:46:31.724949466

*** (1) HOLDS THE LOCK(S):
RECORD LOCKS space id 109 page no 62116 n bits 312 index uniq_account of table `ecom_budget_platform`.`t_pro_budget_account` trx id 4822490389 lock mode S locks gap before rec
Record lock, heap no 224 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 9; hex 313039333035343332; asc 109305432;;
 1: len 13; hex 4566666563744f626a53686f70; asc EffectObjShop;;
 2: len 0; hex ; asc ;;
 3: len 4; hex 32303233; asc 2023;;
 4: len 1; hex 82; asc  ;;
 5: len 8; hex 8000000000000000; asc         ;;
 6: len 8; hex 000000000108e2c7; asc         ;;


*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 109 page no 62116 n bits 312 index uniq_account of table `ecom_budget_platform`.`t_pro_budget_account` trx id 4822490389 lock_mode X locks gap before rec insert intention waiting
Record lock, heap no 224 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 9; hex 313039333035343332; asc 109305432;;
 1: len 13; hex 4566666563744f626a53686f70; asc EffectObjShop;;
 2: len 0; hex ; asc ;;
 3: len 4; hex 32303233; asc 2023;;
 4: len 1; hex 82; asc  ;;
 5: len 8; hex 8000000000000000; asc         ;;
 6: len 8; hex 000000000108e2c7; asc         ;;


*** (2) TRANSACTION:
TRANSACTION 4822471224, ACTIVE 15 sec inserting
mysql tables in use 1, locked 1
LOCK WAIT 4 lock struct(s), heap size 1128, 2 row lock(s), undo log entries 1
MySQL thread id 3727311, OS thread handle 140325156574976, query id 40042778686 dc03-pff-200-4f8d-8fa4-d5e4-db22.byted.org fdbd:dc03:ff:200:4f8d:8fa4:d5e4:db22 eco6444116921_w update
/* psm=ecom.mmc.budget_platform, ip=fdbd:dc03:14:c16::154, ip=- */ INSERT /* psm=ecom.mmc.budget_platform, logid=20230714104619000000000000425317D, ip=fdbd:dc03:14:c16::154, pid=270 */  INTO `t_pro_budget_account` (`account_id`,`biz_entity_id`,`sub_entity_id`,`biz_entity_type`,`biz_entity_code`,`budget_flow_type`,`total_amount`,`used_amount`,`cost_amount`,`frozen_amount`,`refund_amount`,`refund_status`,`gmv`,`biz_field1`,`biz_field2`,`biz_field3`,`biz_field4`,`biz_field5`,`version`,`extra`,`deleted_time`,`create_time`,`update_time`,`not_count_cost`,`last_cost_time`,`accrual_cost_amount`,`is_repay_spend`) VALUES ('7255500191149949236','109305399','2023','EffectObjShop','',2,0,0,0,0,0,0,0,'2023','','7188161946133250365','','',0,'',0,'2023-07-14 10:46:19.65021172','2023-07-14 10:46:19.650211822',0,0,0,0)

*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 109 page no 62116 n bits 312 index uniq_account of table `ecom_budget_platform`.`t_pro_budget_account` trx id 4822471224 lock mode S locks gap before rec
Record lock, heap no 224 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 9; hex 313039333035343332; asc 109305432;;
 1: len 13; hex 4566666563744f626a53686f70; asc EffectObjShop;;
 2: len 0; hex ; asc ;;
 3: len 4; hex 32303233; asc 2023;;
 4: len 1; hex 82; asc  ;;
 5: len 8; hex 8000000000000000; asc         ;;
 6: len 8; hex 000000000108e2c7; asc         ;;


*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 109 page no 62116 n bits 312 index uniq_account of table `ecom_budget_platform`.`t_pro_budget_account` trx id 4822471224 lock_mode X locks gap before rec insert intention waiting
Record lock, heap no 224 PHYSICAL RECORD: n_fields 7; compact format; info bits 0
 0: len 9; hex 313039333035343332; asc 109305432;;
 1: len 13; hex 4566666563744f626a53686f70; asc EffectObjShop;;
 2: len 0; hex ; asc ;;
 3: len 4; hex 32303233; asc 2023;;
 4: len 1; hex 82; asc  ;;
 5: len 8; hex 8000000000000000; asc         ;;
 6: len 8; hex 000000000108e2c7; asc         ;;

*** WE ROLL BACK TRANSACTION (2)
------------
TRANSACTIONS
------------
Trx id counter 4825125995
Purge done for trx's n:o < 4770684970 undo n:o < 252 state: running
History list length 19075455
```


|时间|事务1|事务2|
|---|---|---|
|0s|开始||
|14s|--|开始|
|15s|报错回滚||
|15s|--|成功|
