# 项目结构
# 源代码
# src/com/example/Main.java
# 编译输出
# target/com/example/Main.class
# 依赖库
# libs/jedis-5.0.2.jar

# maven_jar group artifact version
maven_jar() {
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
JAR_FILE=out/example.jar

## 从 target 目录搜索 ${1}.class 文件
## 例如 Example -> com.example.ExampleKt
find_class() {
	find target -type f | grep "${1}" | head -n1 | sed 's|^target/||' | sed 's/.class$//' | sed 's|/|.|g'
}

## 生成 -cp x.jar:y.jar:z.jar 命令
libs_cp() {
	local n=$(ls "libs" | grep '.jar$' | wc -l)

	if [[ ${n} -eq 0 ]]; then
		echo " -cp target:resources"
		return
	fi

	find "libs" -type f | grep '.jar$' | tr '\n' ':' | sed 's/:$/:target:resources/' | xargs echo ' -cp '
}

# 带 -cp 参数的 javac
javac_cp() {
	libs_cp | sed "s|\$|:src/java ${1}|" | xargs echo "javac -d target" | ${SHELL}
}

build() {
	mkdir -p target

	## 编译java
	find "src/java" -type f | grep '.java$' | while read file; do
		## java 是一个文件生成一个 class 可以检查文件是否变动
		dst=$(echo "${file}" | sed "s|^src/java|target|" | sed 's/.java$/.class/')

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
	if ! [[ -d src/kotlin ]]; then
		return
	fi
	KT_FILES=($(find "src/kotlin" -type f | grep '.kt$' | tr '\n' ' '))
	if [[ "${#KT_FILES}" -eq 0 ]]; then
		return
	fi
	libs_cp | sed 's/^/kotlinc /' | sed "s|\$|:src/kotlin:src/java  -d target ${KT_FILES[*]}|" | "${SHELL}"

}

## 运行某个 class 的 main 函数
run_class() {
	build
	libs_cp | xargs echo 'java ' | sed "s|\$| ${*}|" | "${SHELL}"
}

build_jar() {
	JCLASS=$(find_class ${MAIN_CLASS})
	mkdir -p target/META-INF
	echo 'Manifest-Version: 1.0' >target/META-INF/MANIFEST.MF
	echo 'Class-Path: .' >>target/META-INF/MANIFEST.MF
	echo "Main-Class: ${JCLASS}" >>target/META-INF/MANIFEST.MF

	jar cvfm ${JAR_FILE} target/META-INF/MANIFEST.MF -C target .
}

case "${1}" in
# mvn clean
"clean")
	rm -rf target
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
		url=$(maven_jar "${args[@]}")
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
	libs_cp | sed 's/^/java /' | sed "s|$| ${JCLASS}|" | "${SHELL}"
	;;
	## 测试 zsh build.sh test test2
"test")
	JCLASS=$(find_class ${TEST_CLASS})
	args=$(echo "$JCLASS ${*}" | tr ' ' '\n' | sed '/^$/d' | sed '2d' | tr '\n' ' ')
	run_class "${args}"
	;;
"bootJar")
	JCLASS=$(find_class ${MAIN_CLASS})
	echo "${JCLASS}"
	tmp=$(mktemp -d)
	mkdir -p "${tmp}/BOOT-INF/lib"
	mkdir -p "${tmp}/BOOT-INF/classes"
	unzip libs/spring-boot-loader*.jar -d "${tmp}"
	echo "Main-Class: org.springframework.boot.loader.JarLauncher" >"${tmp}/META-INF/MANIFEST.MF"
	echo "Start-Class: ${JCLASS}" >>"${tmp}/META-INF/MANIFEST.MF"

	build

	cp -a target/ "${tmp}/BOOT-INF/classes"
	ls libs/*.jar | grep -v 'spring-boot-loader' | while read file; do
		cp ${file} "${tmp}/BOOT-INF/lib/"
		echo
	done
	rm -f ${JAR_FILE}
	cat "${tmp}/META-INF/MANIFEST.MF"
	jar cvfm0 ${JAR_FILE} ${tmp}/META-INF/MANIFEST.MF -C "${tmp}" .
	rm -r "${tmp}"
	;;
esac
