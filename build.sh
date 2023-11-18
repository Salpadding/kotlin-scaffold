# 项目结构
# 源代码
# src/com/example/Main.java
# 编译输出
# target/com/example/Main.class
# 依赖库
# libs/jedis-5.0.2.jar

# maven_jar_name group artifact version
maven_jar_name() {
	local group=$(echo "${1}" | tr '.' '/')
	local art=${2}
	local ver=${3}
	echo "https://repo1.maven.org/maven2/${group}/${art}/${ver}/${art}-${ver}.jar"
}

# 声明依赖
# group artifact version 三元组 不要用逗号隔开
libs=(
	"org.apache.commons commons-pool2 2.12.0"
	"redis.clients jedis 5.0.2"
	"org.slf4j slf4j-api 2.0.9"
	"org.springframework.boot spring-boot-loader 2.7.17"
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
CLASSES=target

# 资源文件目录 可以被 ClassLoader 找到
RESOURCES=resources

JAVA_SRC=src/java
KOTLIN_SRC=src/kotlin

## 从 target 目录搜索 ${1}.class 文件
## 例如 Example -> com.example.ExampleKt
find_class() {
	find "${CLASSES}" -type f -name '*.class' | grep "${1}" |  # 过滤出 ${1}.class 
        head -n1 | sed "s|^${CLASSES}/||" |  # 去掉文件前缀 剩下包名/类名.class
        sed 's/.class$//' | sed 's|/|.|g' # / -> .  去掉后缀
}

## 生成 -cp x.jar:y.jar:z.jar 命令
get_cp() {
    local jars=($(find libs -type f -name '*.jar'))

	if [[ ${#jars} -eq 0 ]]; then
		echo " -cp ${CLASSES}:${RESOURCES}"
		return
	fi
    
    echo "${jars[@]}" | tr ' ' ':' |
            sed "s|\$|:${CLASSES}:${RESOURCES}|" | xargs echo -cp
}


# 带 -cp 参数的 javac
javac_cp() {
	get_cp | sed "s|\$| ${*}|" | xargs javac -d "${CLASSES}"
}


build() {
	mkdir -p "${CLASSES}"

	## 编译java
	find "${JAVA_SRC}" -type f -name '*.java' | while read file; do
		## java 是一个文件生成一个 class 可以检查文件是否变动
		dst=$(echo "${file}" | sed "s|^${JAVA_SRC}|${CLASSES}|" | sed 's/.java$/.class/')

		if ! [[ -f "${dst}" ]]; then
			javac_cp "${file}"
			continue
		fi

		if [[ $(date -r "${file}" '+%s') -gt $(date -r "${dst}" '+%s') ]]; then
			javac_cp "${file}"
		fi
	done

	## 编译 kotlin 生成 .class
	## kotlin 一个文件可能对应多个.class 无法检查文件变动
	if ! [[ -d "${KOTLIN_SRC}" ]]; then
		return
	fi
	KT_FILES=($(find "${KOTLIN_SRC}" -type f -name '*.kt'))
	if [[ "${#KT_FILES}" -eq 0 ]]; then
		return
	fi
	get_cp | sed "s|\$| ${KT_FILES[*]}|" | xargs kotlinc -d "${CLASSES}"

}


## 运行某个 class 的 main 函数
## 开启断言
run_class() {
	build
	get_cp | sed "s|\$| ${*}|" | xargs java -eq
}


build_jar() {
	JCLASS=$(find_class ${MAIN_CLASS})
	mkdir -p ${CLASSES}/META-INF
	echo 'Manifest-Version: 1.0' > ${CLASSES}/META-INF/MANIFEST.MF
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
"libs")
	## 下载依赖的 jar
	mkdir -p libs
	for jar in "${libs[@]}"; do
		args=($(echo "${jar}"))
		url=$(maven_jar_name "${args[@]}")
		if find ${cur}/libs -type f | grep $(basename ${url}) >/dev/null; then
			continue
		fi
		wget "${url}" -P "${cur}/libs"
	done
	;;
"jar")
	build
	build_jar
	;;
	## 运行
"run")
	build
	JCLASS=$(find_class ${MAIN_CLASS})
	get_cp | sed 's/^/java /' | sed "s|$| ${JCLASS}|" | "${SHELL}"
	;;
	## 测试 zsh build.sh test test2
"test")
	JCLASS=$(find_class ${TEST_CLASS})
	args=$(echo "$JCLASS ${*}" | tr ' ' '\n' | sed '/^$/d' | sed '2d' | tr '\n' ' ')
	run_class "${args}"
	;;
"bootJar")
	JCLASS=$(find_class ${MAIN_CLASS})
	tmp=$(mktemp -d)
	mkdir -p "${tmp}/BOOT-INF/lib"
	mkdir -p "${tmp}/BOOT-INF/classes"
	unzip libs/spring-boot-loader*.jar -d "${tmp}" >/dev/null
	echo "Main-Class: org.springframework.boot.loader.JarLauncher" >"${tmp}/META-INF/MANIFEST.MF"
	echo "Start-Class: ${JCLASS}" >>"${tmp}/META-INF/MANIFEST.MF"

	build

	cp -a ${CLASSES}/ "${tmp}/BOOT-INF/classes/"
	cp -a ${RESOURCES}/ "${tmp}/BOOT-INF/classes/"
	ls libs/*.jar | grep -v 'spring-boot-loader' | while read file; do
		cp ${file} "${tmp}/BOOT-INF/lib/"
	done

	rm -f ${JAR_FILE}
	jar cfm0 ${JAR_FILE} ${tmp}/META-INF/MANIFEST.MF -C "${tmp}" .
	rm -r "${tmp}"
	;;
esac
