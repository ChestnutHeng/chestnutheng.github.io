# [Python]Scrapy Scan


scrapy是个很简单强大的python爬虫框架，不需要处理网络相关逻辑就可以轻松爬取。本文介绍了一些基本的内容。需要注意的是，本文档中所有的●表示非必须内容。
本教程基于官方文档：[官方文档](https://scrapy-chs.readthedocs.io/zh_CN/0.24/topics/settings.html)

# 安装scrapy

## CentOS

```sh
yum install python34-devel.x86_64
pip3 install scrapy
```

# 创建项目

```
//创建项目hello
scrapy startproject hello
//创建一个爬虫（在项目根目录运行，不要加http://），名字为baidu，域名为www.baidu.com
scrapy genspider baidu "www.baidu.com"
```
● 需要注意的是，如果要无视robots.txt文件，请在下面的`settings.py`中设置`ROBOTSTXT_OBEY = False`
● 刚才建好的项目目录文件树如下：
```
tree hello 
hello
|-- hello
|   |-- __init__.py
|   |-- items.py            // 输出结构体定义
|   |-- middlewares.py
|   |-- pipelines.py
|   |-- __pycache__
|   |-- settings.py         // 设置，记得把 ROBOTSTXT_OBEY = False
|   |-- spiders
|       |-- __init__.py
|       |-- baidu.py        // 刚创建的爬虫
|       |-- __pycache__
|-- scrapy.cfg

```


# Shell：测试代码

使用shell可以帮助实现爬虫的代码，查看网页的相关信息。结合浏览器中的审查元素查看会让你构造出需要选择的数据部分。
```py
# 1. 在命令行中执行 scrapy shell 就可以进入shell。
# ● 下面改造了http头的USER_AGENT，一般可以防止请求因为USER_AGENT被拒绝
scrapy shell -s USER_AGENT，="Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/67.0.3396.99 Safari/537.36-480"

# 2. 进入shell后可用的对象：request、response、sel（选择器）、settings、spider、crawler
# 可用的函数 帮助shelp() 请求fetch(url) fetch(req) 浏览器打开view(rsp)

# 3. 接下来可以拉取网页，下面是一些操作的实例:
fetch('https://www.baidu.com')
# 浏览器中打开爬取的网页
view(response)
# 查看req和rsp
request.body
response.headers
# 选择网页中的元素
response.xpath('//div')
sel.xpath('//title/text()').extract()
# ● get 改为post
request = request.replace(method="POST")
```

## ● 调试您的spider

下面代码会在运行spider时，在这里进入shell调试。

```py
from scrapy.shell import inspect_response
inspect_response(response, self)
```

# 选择器：找到爬取的内容

Scrapy选择器构建于 lxml 库之上，这意味着它们在速度和解析准确性上非常相似。选择器从如下的库中获取：
```py
from scrapy.selector import Selector
from scrapy.http import HtmlResponse
# 可以从rsp中构造，也可以 text="<h></h>" 从字符串中构造
response = HtmlResponse(url='http://example.com', body='')
Selector(response=response).xpath('//span/text()').extract() # [u'good']
# 幸运的是rsp提供了方法直接构造选择器：
response.selector.xpath('//span/text()').extract()
# 以及更短的快捷方式：
response.xpath('//title/text()').extract() 
response.css('title::text').extract()  
```
● xpath和css是两种用来选择数据的工具，他们遵循不同的语法。但是他们都都返回一个selector对象。selector有几个成员函数很有用，他们是
1. extract() 返回里面文字的值
2. re() 用正则过滤文字值，返回文字值
3. xpath() css() 返回的selector依然可以用这些工具，这意味着可以嵌套

```py
# 下面是一个从的img标签的text中获取括号内文字的方法
response.xpath('//a[contains(@href, "image")]/text()').re(r'Name:\s*(.*)')
# 下面是用xpath的相对路径和选择器嵌套：
divs = response.xpath('//div')
for p in divs.xpath('.//p'):    # 父路径下的所有后代p
    ...
for p in divs.xpath('p'):    # 父路径下的所有直接
    ...
```

## ● Xpath 语法参考

[w3s : Xpath语法参考](http://www.w3school.com.cn/xpath/xpath_syntax.asp)
Xpath是一种用于操作xml的选择器，可以快速操作想要的html标签。

|语法|实例|解释|
|:---|:---|:---|
|a|bookstore|	选取 bookstore 元素的所有子节点。
|/a|/bookstore	|选取根元素 bookstore。
|a/b|bookstore/book	|选取属于 bookstore 的子元素的所有 book 元素。
|//a|//book	|选取所有 book 子元素，而不管它们在文档中的位置。
|a//b|bookstore//book|	选择属于 bookstore 元素的后代的所有 book 元素，而不管它们位于 bookstore 之下的什么位置。
|@a|//@lang	|选取名为 lang 的所有属性。
|\*|/bookstore/\*|	选取 bookstore 元素的所有子元素。
||//\*|	选取文档中的所有元素。
||//title[@*]	|选取所有带有属性的 title 元素。

## ● CSS 语法参考

[w3s : CSS语法参考](http://www.w3school.com.cn/cssref/css_selectors.asp)
如果要操作一个类或者id而不是标签，CSS是最快的方法。

|例子|例子描述|
|:---|:---|
|\.intro|选择 class="intro" 的所有元素|
|#firstname	|选择 id="firstname" 的所有元素
|*	|选择所有元素
|p	|选择所有 p 元素
|div,p|选择所有 div元素和所有 p 元素
|div p|选择 div 元素内部的所有 p 元素
|div>p|选择父元素为 <div> 元素的所有 <p> 元素|
|div+p|选择紧接在 <div> 元素之后的所有 <p> 元素
|[target]|选择带有 target 属性所有元素
|[target=\_blank]|选择 target="]\_blank" 的所有元素。
|[title~=flower]|选择 title 属性包含单词 "flower" 的所有元素
|[lang&#124;=en]	|选择 lang 属性值以 "en" 开头的所有元素

# Item：存储你爬取结果的桶

好了，现在开始写爬虫。不过在这之前需要先定义好你想要爬下来的数据格式是怎么样的，待会把他们装进去。你需要修改`hello/items.py`，编写一个简单的类。
```py
class HelloItem(scrapy.Item):
    # 用 scrapy.Field() 作为类型就可以了
    id = scrapy.Field()
    name = scrapy.Field()
    description = scrapy.Field()
```
● item和字典的API非常相似。可以使用get()、下标等读写item，甚至可以相互用对方初始化。

# Spider：爬虫逻辑

spider是爬取流程的主体。打开`hello/spiders/baidu.py`，编辑成员函数和成员变量：
1. `name` 爬虫的名字
2. `allowed_domains` 只允许爬取`allowed_domains`的内容
3. `start_urls` 运行时没指定url，就从这里开始爬
4. `start_requests()` 可以重写这个来处理第一个`request`。否则，将会用`make_requests_from_url`爬url列表里的内容。
5. `make_requests_from_url(url)` 可以重写这个来处理请求的发起。默认调用parse来处理rsp。
6. `parse(rsp)` 处理rsp。需要返回item或者req的迭代对象作为输出和下一批爬取的内容，或者都返回。
```py
import scrapy
from hello.items import HelloItem
import scrapy

class BaiduSpider(scrapy.Spider):
    # 创建爬虫时指定的名字
    name = 'baidu'
    # ● 设置中OffsiteMiddleware=True的时候，只允许爬取allowed_domains的内容
    allowed_domains = ['baidu.com']
    # 爬取的目标链接
    start_urls = ['http://www.baidu.com/']
    
    # 用这个函数处理url的rsp
    def parse(self, response):
        sel = scrapy.Selector(response)
        # 选择所有的h3标题返回存储
        for h3 in response.xpath('//h3').extract():
            yield HelloItem(title=h3)
        # 返回链接继续爬取
        for url in response.xpath('//a/@href').extract():
            yield scrapy.Request(url, callback=self.parse)
    
    # ● 一个重写start_requests的样例，构造了req，并用logged_in函数处理rsp
    def start_requests(self):
        return [scrapy.FormRequest("http://www.example.com/login",
                               formdata={'user': 'john', 'pass': 'secret'},
                               callback=self.logged_in)]
    def logged_in(rsp):...
```
写完后，在项目目录下运行scrapy crawl来运行spider：
```
// 基础的运行
scrapy crawl hello
// 传递参数给myspider，并在构造函数中使用
scrapy crawl myspider -a category=electronics
class MySpider(Spider):
    def __init__(self, category=None, *args, **kwargs):
        super(MySpider, self).__init__(*args, **kwargs)
        self.start_urls = ['http://www.example.com/categories/%s' % category]
// 把爬到的item输出文件
scrapy crawl dmoz -o items.json
```

# PipeLine：处理item并输出

Pipeline提供了处理返回的item的几个函数。编辑`hello/pipeline.py`修改Pipeline的成员函数：
1. process_item(item, spider) 每个item获取后都会用这个处理。这个函数会返回一个处理好的item。
2. open_spider(spider) 开启spider时被调用
3. close_spider(spider) 关闭spider时被调用

```py
# 下面是一个用id去重item的样例：
class DuplicatesPipeline(object):
    def __init__(self):
        self.ids_seen = set()
    def process_item(self, item, spider):
        if item['id'] in self.ids_seen:
            raise DropItem("Duplicate item found: %s" % item)
        else:
            self.ids_seen.add(item['id'])
            return item
from scrapy.exporters import CsvItemExporter
# 一个用导出器导出的样例：
from scrapy.exporters import CsvItemExporter
class ExportPipeline(object):
    def open_spider(self, spider):
        self.file = open("test.csv", "wb")
        self.exporter = CsvItemExporter(self.file,       
        fields_to_export=["id", "name", "desc"])
        self.exporter.start_exporting()
    def process_item(self, item, spider):
        self.exporter.export_item(item)
        return item
    def close_spider(self, spider):
        self.exporter.finish_exporting()
        self.file.close()
```
最后，修改`settings.py`中的`ITEM_PIPELINES`保证你的Pipeline生效。key表示路径，值表示执行的顺序。
```py
ITEM_PIPELINES = {
    'mybot.pipelines.validate.DuplicatesPipeline': 300,
    'mybot.pipelines.validate.ExportPipeline': 800,
}
```

## ● Feeds Export

序列化你的item结果有很多种方式：
```py
FEED_EXPORTERS_BASE = {
    'json': 'scrapy.contrib.exporter.JsonItemExporter',
    'jsonlines': 'scrapy.contrib.exporter.JsonLinesItemExporter',
    'csv': 'scrapy.contrib.exporter.CsvItemExporter',
    'xml': 'scrapy.contrib.exporter.XmlItemExporter',
    'marshal': 'scrapy.contrib.exporter.MarshalItemExporter',
}
```

# 高级特性

## 下载器中间件：修改req和rsp的钩子
[官方文档：下载器中间件](https://scrapy-chs.readthedocs.io/zh_CN/0.24/topics/downloader-middleware.html#topics-downloader-middleware-ref)


# 最佳实践

下面是些处理这些站点的建议(tips):
1. 使用user agent池，轮流选择之一来作为user agent。池中包含常见的浏览器的user agent(google一下一大堆)
2. 禁止cookies(参考 [COOKIES_ENABLED](https://scrapy-chs.readthedocs.io/zh_CN/0.24/topics/downloader-middleware.html#std:setting-COOKIES_ENABLED))，有些站点会使用cookies来发现爬虫的轨迹。
3. 设置下载延迟(2或更高)。参考 [DOWNLOAD_DELAY](https://scrapy-chs.readthedocs.io/zh_CN/0.24/topics/settings.html#std:setting-DOWNLOAD_DELAY) 设置。
4. 如果可行，使用 Google cache 来爬取数据，而不是直接访问站点。
5. 使用IP池。例如免费的 Tor项目 或付费服务(ProxyMesh)。
6. 使用高度分布式的下载器(downloader)来绕过禁止(ban)，您就只需要专注分析处理页面。这样的例子有: Crawlera
