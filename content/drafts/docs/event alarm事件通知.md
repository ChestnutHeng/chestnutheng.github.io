
客户端
iphone遍历事件列表
* 如果当天有事件，则定12点的闹钟
* 12点后如果事件没有被处理，定20点的闹钟


timer: 承载一个计时器
例子：每年的12月1号、每年农历的12月20、每月4号、每周二三
* 循环类型 cycle_type：年、月、周
* 循环的值 cycle_value：（1201、4、[2,3]）
* 是否循环 is_cycle: 

cond：承载一个条件
* 条件名
* 条件列表，list<sub_cond>，里面是与的关系
	* key指标名
	* op操作符：lt，gt，lte，gte，eq，in，neq，nin
	* value：具体的值

indicator：指标，承载一个条件里key的获取方式

event: 承载一个事件，具有以下属性
* 事件名
* 事件描述
* 事件触发条件

event_instance: 单次的事件
* 所属事件id
* 事件触发的值


```
{
	"event_name" : "Tim的生日提醒", 
	"event_desc" : "每年这个时候的生日提醒",
	"event_id" : "1", 
	"event_cond" : null,
	"event_instance_id" : "1",
	"event_cond_value" : {},
}

{  
    "event_name":"股票价格提醒",  
    "event_desc":"股价提醒",  
    "event_id":"2",  
    "event_cond":[  
        {  
            "key":"stock_price",  
            "op":"lt",  
            "value":"51"  
        }  
    ],  
    "event_instance_id":"1",  
    "event_cond_value":{  
        "stock_price":"60"  
    }  
}





```