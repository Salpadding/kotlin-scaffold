# kotlin 脚手架

此脚手架的意义在于 say good bye to build.kt build.gradle pom.xml 等一系列反人类的配置文件
仅使用 zsh wget javac kotlinc 作为构建工具

KISS 原则 keep it simple stupid

把所有开发相关简化为如下几个流程

## 依赖管理

### 声明依赖

简单粗暴
在 build.sh 开头中添加依赖

例如你需要jedis 就这样
```shell
libs=(
"jedis=https://repo1.maven.org/maven2/redis/clients/jedis/5.0.2/jedis-5.0.2.jar"
)
```

你还需要 slf4j 那就再加

```shell
libs=(
"jedis=https://repo1.maven.org/maven2/redis/clients/jedis/5.0.2/jedis-5.0.2.jar",
"commons-pool2=https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.12.0/commons-pool2-2.12.0.jar"
)
```

```shell
./build.sh libs
```

### 下载依赖

```shell
./build.sh libs
```

### 清空依赖

```shell
rm -rf libs && mkdir libs
```

## 构建

先编译java后编译的kotlin

```shell
./build.sh clean
./build.sh build
```


## 测试

