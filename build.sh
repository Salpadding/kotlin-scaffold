#!/bin/bash

# 项目结构
# 源代码
# src/com/example/Main.java
# 编译输出
# target/com/example/Main.class
# 依赖库
# lib/jedis-5.0.2.jar

MAVEN_REPO=${MAVEN_REPO:-https://repo1.maven.org/maven2}
SPRING_VER=${SPRING_VER:-'5.3.0'}

maven_jar_path() {
	local group=$(echo "${1}" | tr '.' '/')
	local art=${2}
	local ver=${3}
	echo "${group}/${art}/${ver}/${art}-${ver}.jar"
}

# 声明依赖
# group artifact version 三元组 不要用逗号隔开
lib=(
	"org.apache.commons commons-pool2 2.12.0"
	"redis.clients jedis 5.0.2"
	"org.slf4j slf4j-api 2.0.9"
	"org.springframework.boot spring-boot-loader 2.7.17"
	"org.springframework spring-jcl ${SPRING_VER}"
	"org.springframework spring-web ${SPRING_VER}"
	"org.springframework spring-webmvc ${SPRING_VER}"
	"org.springframework spring-core ${SPRING_VER}"
	"org.springframework spring-beans ${SPRING_VER}"
	"org.springframework spring-context ${SPRING_VER}"
	"org.springframework spring-aop ${SPRING_VER}"
	"org.springframework spring-expression ${SPRING_VER}"
	"com.fasterxml.jackson.core jackson-databind 2.16.0"
	"com.fasterxml.jackson.core jackson-core 2.16.0"
	"com.fasterxml.jackson.core jackson-annotations 2.16.0"
	"javax.servlet javax.servlet-api 3.1.0"
)

# dirname $0 获取项目根目录
cur=$(dirname ${0})
cur=$(cd ${cur} && pwd)

# 分别用于找运行/测试的入口函数
MAIN_CLASS=${MAIN_CLASS:-Example}
TEST_CLASS=${TEST_CLASS:-Test}

# 输出 .jar 文件
JAR_FILE=out/example.jar

# .class 文件输出目录
CLASSES=target/classes

# 资源文件目录 可以被 ClassLoader 找到
RESOURCES=src/main/resources

JAVA_SRC=src/main/java
KOTLIN_SRC=src/kotlin

## 从 target 目录搜索 ${1}.class 文件
## 例如 Example -> com.example.ExampleKt
find_class() {
	find "${CLASSES}" -type f -name '*.class' | grep "${1}" | # 过滤出 ${1}.class
		head -n1 | sed "s|^${CLASSES}/||" |                      # 去掉文件前缀 剩下包名/类名.class
		sed 's/.class$//' | sed 's|/|.|g'                        # / -> .  去掉后缀
}

## 生成 classpath 例如 x.jar:y.jar:z.jar
get_cp() {
	local jars=($(find lib -type f -name '*.jar'))

	if [[ ${#jars} -eq 0 ]]; then
		echo "${RESOURCES}"
		return
	fi

	echo "${jars[@]}" | tr ' ' ':' |
		sed "s|\$|:${RESOURCES}|"
}

# 带 -cp 参数的 javac
javac_cp() {
	local cp=$(get_cp)
	javac -cp "${cp}" -sourcepath "${JAVA_SRC}" -d "${CLASSES}" "${@}"
}

build() {
	local cp=$(get_cp)

	local SRC="${1}"
	SRC=$([[ -n ${SRC} ]] && echo "${SRC}" || echo "${JAVA_SRC}")
	[[ -d "${SRC}" ]] || return

	mkdir -p "${CLASSES}"

	## 编译java
	find "${SRC}" -type f -name '*.java' | while read file; do
		## java 是一个文件生成一个 class 可以检查文件是否变动
		dst=$(echo "${file}" | sed "s|^${SRC}|${CLASSES}|" | sed 's/.java$/.class/')

		if ! [[ -f "${dst}" ]]; then
			javac_cp "${file}"
			continue
		fi

		if [[ $(date -r "${file}" '+%s') -gt $(date -r "${dst}" '+%s') ]]; then
			javac_cp "${file}"
		fi
	done

	KT_FILES=($(find "${SRC}" -type f -name '*.kt'))
	if [[ "${#KT_FILES}" -eq 0 ]]; then
		return
	fi
	kotlinc -cp "${cp}:${CLASSES}" -d "${CLASSES}" "${KT_FILES[@]}"
}

build_main() {
	build src/main/java
}

build_test() {
	build src/test/java
}

## 运行某个 class 的 main 函数
## 透传 命令行参数
run_class() {
	local cp=$(get_cp)
	java -ea -cp "${cp}:${CLASSES}" "${@}"
}

build_jar() {
	JCLASS=$(find_class ${MAIN_CLASS})
	mkdir -p ${CLASSES}/META-INF
	echo 'Manifest-Version: 1.0' >${CLASSES}/META-INF/MANIFEST.MF
	echo 'Class-Path: .' >>${CLASSES}/META-INF/MANIFEST.MF
	echo "Main-Class: ${JCLASS}" >>${CLASSES}/META-INF/MANIFEST.MF

	jar cfm ${JAR_FILE} ${CLASSES}/META-INF/MANIFEST.MF -C ${CLASSES} .
}

case "${1}" in
# mvn clean
"clean")
	rm -rf ${CLASSES}
	;;
# mvn compile
"build")
	build
	;;
# 下载依赖包
"lib")
	## 下载依赖的 jar
	mkdir -p lib
	for jar in "${lib[@]}"; do
		args=($(echo "${jar}"))
		jar_path=$(maven_jar_path "${args[@]}")
		jar_name=$(basename ${jar_path})
		if find ${cur}/lib -type f | grep ${jar_name} >/dev/null; then
			continue
		fi

		if [[ -f "${HOME}/.m2/repository/${jar_path}" ]]; then
			cp "${HOME}/.m2/repository/${jar_path}" "${cur}/lib"
			continue
		fi

		wget "${MAVEN_REPO}/${jar_path}" -P "${cur}/lib"

		[[ -f "${cur}/lib/${jar_name}" ]] && [[ -d "${HOME}/.m2" ]] &&
			mkdir -p "${HOME}/.m2/repository/$(dirname ${jar_path})" &&
			cp "${cur}/lib/${jar_name}" "${HOME}/.m2/repository/${jar_path}"
	done
	;;
"jar")
	build_main
	build_jar
	;;
	## 运行
"run")
	build_main
	JCLASS=$(find_class ${MAIN_CLASS})
	run_class "${JCLASS}" "${@:2}"
	;;
	## 测试 zsh build.sh test test2
"test")
	build_main
	build_test
	JCLASS=$(find_class ${TEST_CLASS})
	run_class "${JCLASS}" "${@:2}"
	;;
"native-image")
	## apt install libz-dev
	build
	JCLASS=$(find_class ${MAIN_CLASS})
	get_cp | sed "s|\$|:${CLASSES} ${JCLASS}|" | xargs native-image
	;;
"bootJar")
	JCLASS=$(find_class ${MAIN_CLASS})
	tmp=$(mktemp -d)
	mkdir -p "${tmp}/BOOT-INF/lib"
	mkdir -p "${tmp}/BOOT-INF/classes"
	unzip lib/spring-boot-loader*.jar -d "${tmp}" >/dev/null
	echo "Main-Class: org.springframework.boot.loader.JarLauncher" >"${tmp}/META-INF/MANIFEST.MF"
	echo "Start-Class: ${JCLASS}" >>"${tmp}/META-INF/MANIFEST.MF"

	build

	cp -a ${CLASSES}/ "${tmp}/BOOT-INF/classes/"
	cp -a ${RESOURCES}/ "${tmp}/BOOT-INF/classes/"
	ls lib/*.jar | grep -v 'spring-boot-loader' | while read file; do
		cp ${file} "${tmp}/BOOT-INF/lib/"
	done

	rm -f ${JAR_FILE}
	jar cfm0 ${JAR_FILE} ${tmp}/META-INF/MANIFEST.MF -C "${tmp}" .
	rm -r "${tmp}"
	;;
esac
