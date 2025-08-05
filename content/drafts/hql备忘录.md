---
title: "[hive]hql备忘录"
date:  2023-06-15T15:24:23+08:00
lastmod:  2023-06-15T15:24:23+08:00
draft: true
description: "本文介绍hsql的一些基础语法。"
tags: ["数据库", "hive", "mysql"]
categories: ["数据库"]
---


## 开发样例

```sql
--- 假设我们要一张商品的表
--- 把需要的表先查出来，放入内存中

-- 商品参加促销记录
with spu_promotion_record as (
    select  spu_id,
            collect_set(case when activity_id = xxx then status end) as status_list, --- 状态
            max(if(reason like '%管理员拒绝%', 1, 0)) as is_admin_reject -- 管理员驳回
    from    db.xxx_a_table
    where   date = '${date}'
    and     activity_id in(xxx)
    group by
            item_id
)
-- 商品百亿补贴记录
spu_subsidy_record as (
    select  spu_id,
            max(get_json_object(detail, '$.amount')) as spu_amount,
            max(cast(get_json_object(sku_info, '$.sku_price') as bigint)) as max_sku_price
    from    (
                select  *
                from    db.xxx_b_table
                lateral view
                        explode (
                            default.json_split(get_json_object(detail, '$.spu_info.sku_info'))
                        ) as sku_info
                where   date = '${date}'
            )
    group by
            item_id
)

--- 查询
--- left join提高查询效率
--- 驱动表是最小的表
--- 连接使用同一个字段
select  spu_promotion_record.item_id,
        if(array_contains(spu_promotion_record.status_list, 6), 1, 0) as is_success,
        spu_promotion_record.is_admin_reject,
        spu_subsidy_record.spu_amount,
        spu_subsidy_record.max_sku_price,
        spu_info.spu_name
from    spu_promotion_record
left join
        spu_subsidy_record
on      spu_promotion_record.spu_id = spu_subsidy_record.spu_id
left join
        spu_info onspu_promotion_record.spu_id = spu_info.spu_id
```


## 摊平

```sql
--- sign_info的内容
{
    "spu_info":{
        "sku_info":[
            {
                "sku_id":1,
                "sku_name":"蓝色/256GB"
            },
            {
                "sku_id":2,
                "sku_name":"蓝色/128GB"
            }
        ]
    }
}
---

select  *
from    db.table_1
lateral view
        explode (
            default.json_split(
                get_json_object(sign_info, '$.spu_info.sku_info')
            )
        ) as sku_info
where   date = '${date}'

---结果
| spu_id | sign_info | sku_info |
| spu1   | {...}     | {"sku_id":1, ...} |  
| spu1   | {...}     | {"sku_id":2, ...} |  
```


## 时间


日期➡️时间戳
```sql
select unix_timestamp('20160816','yyyyMMdd') --1471276800
```
时间戳➡️日期
```sql
select from_unixtime(1471276800,'yyyyMMdd') --20160816
```
日期➡️日期
```sql
--yyyyMMdd➡️yyyy-MM-dd
select from_unixtime(unix_timestamp('20211022','yyyyMMdd'),"yyyy-MM-dd"); 2021-10-22
```

字符串➡️日期
```sql
-- 强转
select to_date('2016-08-16 10:03:01') --2016-08-16 类似sql 中的date
-- 截断
select date_format('2021-10-22 17:34:56','yyyy-MM-dd') 2021-10-22
```
日期计算
```sql
select date_add('2016-08-16',10)
select date_sub(current_date(),1)
select datediff('2016-08-16','2016-08-11')
```