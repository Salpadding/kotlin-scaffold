# kotlin 脚手架

此脚手架的意义在于和 build.kt build.gradle pom.xml 等一系列反人类的配置文件 构建工具说再见

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
"redis.clients jedis 5.0.2"
)
```

你还需要 slf4j 那就再加

```shell
libs=(
"redis.clients jedis 5.0.2"
"org.apache.commons commons-pool2 2.12.0"
)
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


## 运行

```shell
./build.sh build
./build.sh run
```

## 打包

```shell
./build.sh jar
```

## 打包单个可执行的 jar 包

添加 spring-boot-loader 依赖

```shell
libs=(
"org.jetbrains.kotlin kotlin-stdlib 1.9.20"
"org.springframework.boot spring-boot-loader 2.7.17"
)
 ```

打包

```shell
./build.sh bootJar
```

