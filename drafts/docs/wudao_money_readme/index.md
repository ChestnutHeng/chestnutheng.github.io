# 

# 功能 - 你会获得什么？

* 记账自动分类，将你的

# 使用

1. 解压后，寻找自己的操作系统对应的版本。注意不要把配置json删除
```bash
-rwxr-xr-x  1 chestnutheng  staff   6.0M  6 28 19:59 GoldenKey_Linux_amd64
-rwxr-xr-x  1 chestnutheng  staff   5.9M  6 28 19:59 GoldenKey_Mac_amd64
-rwxr-xr-x  1 chestnutheng  staff   5.8M  6 28 19:59 GoldenKey_Windows_386.exe
-rwxr-xr-x  1 chestnutheng  staff   6.1M  6 28 19:59 GoldenKey_Windows_amd64.exe
-rw-r--r--  1 chestnutheng  staff   3.7K  6 28 19:59 golden_conf.json
```

2. 使用解压好的文件。直接双击或者命令行运行
```sh
Ξ money/ ▶ ./GoldenKey_Mac_amd64
2023/06/28 20:41:26 导入记录为0。请将导入的支付宝或者微信账单文件放在同目录！
```

3. 如果需要解析账单，需要把账单文件放入文件夹。
	1. 微信下载账单：
	2. 支付宝下载账单：https://consumeprod.alipay.com/record/standard.htm
		1. 个人版 - 选择开始日期到1月1日 - 下载明细
	3. 解压下载好的zip文件，和GoldenKey放入同级文件夹，如下图
```sh
Ξ tiny_projects/money ▶ tree .       
.
├── GoldenKey_Mac_amd64
├── golden_conf.json
├── alipay_record_20230621_1123_1.csv
├── alipay_record_20230628_1735_1.csv
├── 微信支付账单(20230401-20230531).csv
```

4. 运行GoldenKey，你会发现目录下生成了几个文件
```
.
├── GoldenKey_Mac_amd64
├── golden_conf.json
├── alipay_record_20230621_1123_1.csv
├── alipay_record_20230628_1735_1.csv
├── 微信支付账单(20230401-20230531).csv
├── bill_fix.csv
├── bills.csv
├── 账单管理结果_20210101_20230531.xlsx
```

账单管理结果 就是你要的文件！
