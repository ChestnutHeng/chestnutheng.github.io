

增加
```
local key = KEYS[1]
local val = tonumber(ARGV[1])
local upper = tonumber(ARGV[2])
local expireAt = tonumber(ARGV[3])
local cur = redis.call('get',key)
if(cur == false)
then
	cur = 0
else
	cur = tonumber(cur)
end
if(cur >= upper)
then
	return 0
end
local new = cur + val
if(new > upper)
then
	new = upper
end
redis.call('set',key,new)
redis.call('expireat',key,expireAt)
	return new - cur
```


减少
```
local key = KEYS[1]
local val = tonumber(ARGV[1])
local lower = tonumber(ARGV[2])
local expireAt = tonumber(ARGV[3])
local cur = redis.call('get',key)
if(cur == false)
then
	cur = 0
else
	cur = tonumber(cur)
end
if(cur <= lower)
then
	return 0
end
local new = cur - val
if(new < lower)
then
	new = lower
end
redis.call('set',key,new)
redis.call('expireat',key,expireAt)
	return new - cur
```

