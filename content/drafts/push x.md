
设计理念
1. 构建一套事件监测、规则匹配、发送的系统


HK0700到达卖出点 -> 发送邮件消息
1. 触发器cron：分钟级扫描
2. 值组件：price1=GetStockPrice(code1)
3. 发射器：sendEmail()
4. 规则引擎：if price1 > conf1 : sendEmail()
5. 聚合引擎：当日不再发

flight到达低点or日报 -> 发送邮件消息
1. 触发器cron：早晚扫描
2. 值组件：priceList=GetFlight(A, B, day)
3. 发射器：sendEmail()
4. 规则引擎：if priceList0 < conf1 : sendEmail()



2. cron表达式： ` */10 * * * *`
3. 执行动作：`getFlight`
4. 参数列表：`杭州 北京 2023-08-08`
5. 规则：`price[0] < 1000`
6. 发射器： `sendEmail`

```json
{
	"rule_name" : "杭州-北京flights监控",
	"crontab" : "*/10 * * * *",
	"event" : "getFlight",
	"params" : ["杭州","北京","2023-08-08"],
	"rule" : {
		"key" : "min_price",
		"val" : "1000",
		"op"  : "<"
	},
	"action" : "sendEmail"
}


// getFlight回包
{
	"min_price" : 1000.0
}
```