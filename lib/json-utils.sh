#!/usr/bin/env bash
# ============================================================================
# json-utils.sh - JSON操作工具函数
#
# 提供安全的JSON读取、修改、验证功能
# 封装jq操作，添加错误处理和原子写入
# ============================================================================

# 防止重复加载
[[ -n "${_JSON_UTILS_LOADED}" ]] && return 0
readonly _JSON_UTILS_LOADED=1

# ============================================================================
# 常量定义
# ============================================================================

# JSON临时文件前缀
readonly JSON_TMP_PREFIX="/tmp/v2ray-agent-json"

# ============================================================================
# 验证函数
# ============================================================================

# 检查jq是否可用
# 返回: 0=可用, 1=不可用
jsonJqAvailable() {
    command -v jq >/dev/null 2>&1
}

# 验证JSON文件语法
# 参数: $1 - JSON文件路径
# 返回: 0=有效, 1=无效
jsonValidateFile() {
    local file="$1"

    [[ -z "${file}" ]] && return 1
    [[ ! -f "${file}" ]] && return 1

    jq -e . "${file}" >/dev/null 2>&1
}

# 验证JSON字符串语法
# 参数: $1 - JSON字符串
# 返回: 0=有效, 1=无效
jsonValidateString() {
    local jsonStr="$1"

    [[ -z "${jsonStr}" ]] && return 1

    echo "${jsonStr}" | jq -e . >/dev/null 2>&1
}

# ============================================================================
# 读取函数
# ============================================================================

# 从JSON文件读取值
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式 (如 .inbounds[0].port)
#       $3 - 默认值 (可选)
# 输出: 读取到的值或默认值
jsonGetValue() {
    local file="$1"
    local path="$2"
    local default="${3:-}"

    if [[ ! -f "${file}" ]]; then
        echo "${default}"
        return 1
    fi

    local value
    value=$(jq -r "${path} // empty" "${file}" 2>/dev/null)

    if [[ -z "${value}" || "${value}" == "null" ]]; then
        echo "${default}"
        return 1
    fi

    echo "${value}"
}

# 从JSON文件读取值（带备选路径）
# 参数: $1 - JSON文件路径
#       $2 - 主路径
#       $3 - 备选路径
#       $4 - 默认值 (可选)
jsonGetValueWithFallback() {
    local file="$1"
    local primaryPath="$2"
    local fallbackPath="$3"
    local default="${4:-}"

    if [[ ! -f "${file}" ]]; then
        echo "${default}"
        return 1
    fi

    local value
    value=$(jq -r "${primaryPath} // ${fallbackPath} // empty" "${file}" 2>/dev/null)

    if [[ -z "${value}" || "${value}" == "null" ]]; then
        echo "${default}"
        return 1
    fi

    echo "${value}"
}

# 从JSON文件读取数组
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式
# 输出: 紧凑格式的JSON数组
jsonGetArray() {
    local file="$1"
    local path="$2"

    if [[ ! -f "${file}" ]]; then
        echo "[]"
        return 1
    fi

    local arr
    arr=$(jq -c "${path} // []" "${file}" 2>/dev/null)

    if [[ -z "${arr}" || "${arr}" == "null" ]]; then
        echo "[]"
        return 1
    fi

    echo "${arr}"
}

# 获取数组长度
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式
# 输出: 数组长度
jsonGetArrayLength() {
    local file="$1"
    local path="$2"

    if [[ ! -f "${file}" ]]; then
        echo "0"
        return 1
    fi

    jq -r "${path} | length // 0" "${file}" 2>/dev/null || echo "0"
}

# 遍历JSON数组（每行输出一个元素）
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式
# 输出: 每行一个JSON对象（紧凑格式）
jsonIterateArray() {
    local file="$1"
    local path="$2"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq -c "${path}[]" "${file}" 2>/dev/null
}

# 从JSON字符串读取值
# 参数: $1 - JSON字符串
#       $2 - jq路径表达式
#       $3 - 默认值 (可选)
jsonGetFromString() {
    local jsonStr="$1"
    local path="$2"
    local default="${3:-}"

    if [[ -z "${jsonStr}" ]]; then
        echo "${default}"
        return 1
    fi

    local value
    value=$(echo "${jsonStr}" | jq -r "${path} // empty" 2>/dev/null)

    if [[ -z "${value}" || "${value}" == "null" ]]; then
        echo "${default}"
        return 1
    fi

    echo "${value}"
}

# ============================================================================
# 选择和过滤函数
# ============================================================================

# 从数组中选择符合条件的元素
# 参数: $1 - JSON文件路径
#       $2 - 数组路径
#       $3 - select条件 (如 .port == 443)
# 输出: 匹配的元素（紧凑JSON）
jsonSelect() {
    local file="$1"
    local arrayPath="$2"
    local condition="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq -c "${arrayPath}[] | select(${condition})" "${file}" 2>/dev/null
}

# 检查数组中是否存在符合条件的元素
# 参数: $1 - JSON文件路径
#       $2 - 数组路径
#       $3 - select条件
# 返回: 0=存在, 1=不存在
jsonExists() {
    local file="$1"
    local arrayPath="$2"
    local condition="$3"

    local result
    result=$(jsonSelect "${file}" "${arrayPath}" "${condition}")

    [[ -n "${result}" ]]
}

# ============================================================================
# 修改函数（返回修改后的JSON字符串，不直接写文件）
# ============================================================================

# 设置JSON值
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式
#       $3 - 新值（JSON格式）
# 输出: 修改后的完整JSON
jsonSetValue() {
    local file="$1"
    local path="$2"
    local value="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq "${path} = ${value}" "${file}" 2>/dev/null
}

# 设置JSON字符串值（自动加引号）
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式
#       $3 - 新字符串值
# 输出: 修改后的完整JSON
jsonSetString() {
    local file="$1"
    local path="$2"
    local value="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq --arg val "${value}" "${path} = \$val" "${file}" 2>/dev/null
}

# 设置JSON数字值
# 参数: $1 - JSON文件路径
#       $2 - jq路径表达式
#       $3 - 新数字值
# 输出: 修改后的完整JSON
jsonSetNumber() {
    local file="$1"
    local path="$2"
    local value="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq --argjson val "${value}" "${path} = \$val" "${file}" 2>/dev/null
}

# 向数组添加元素
# 参数: $1 - JSON文件路径
#       $2 - 数组路径
#       $3 - 要添加的元素（JSON格式）
# 输出: 修改后的完整JSON
jsonArrayAppend() {
    local file="$1"
    local arrayPath="$2"
    local element="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq "${arrayPath} += [${element}]" "${file}" 2>/dev/null
}

# 从数组删除指定索引的元素
# 参数: $1 - JSON文件路径
#       $2 - 数组路径
#       $3 - 索引
# 输出: 修改后的完整JSON
jsonArrayDeleteByIndex() {
    local file="$1"
    local arrayPath="$2"
    local index="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq "del(${arrayPath}[${index}])" "${file}" 2>/dev/null
}

# 从数组删除符合条件的元素
# 参数: $1 - JSON文件路径
#       $2 - 数组路径
#       $3 - select条件
# 输出: 修改后的完整JSON
jsonArrayDeleteByCondition() {
    local file="$1"
    local arrayPath="$2"
    local condition="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq "del(${arrayPath}[] | select(${condition}))" "${file}" 2>/dev/null
}

# 删除字段
# 参数: $1 - JSON文件路径
#       $2 - 字段路径
# 输出: 修改后的完整JSON
jsonDeleteField() {
    local file="$1"
    local fieldPath="$2"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq "del(${fieldPath})" "${file}" 2>/dev/null
}

# ============================================================================
# 安全文件写入函数
# ============================================================================

# 安全写入JSON到文件（原子操作）
# 参数: $1 - 目标文件路径
#       $2 - JSON内容
#       $3 - 是否创建备份 (true/false, 默认true)
# 返回: 0=成功, 1=失败
jsonWriteFile() {
    local file="$1"
    local content="$2"
    local backup="${3:-true}"

    # 验证JSON语法
    if ! echo "${content}" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    # 创建备份
    if [[ "${backup}" == "true" && -f "${file}" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # 写入临时文件
    local tmpFile="${JSON_TMP_PREFIX}_$$_$(date +%s)"
    if ! echo "${content}" | jq . > "${tmpFile}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    # 原子移动
    if ! mv "${tmpFile}" "${file}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    return 0
}

# 安全修改JSON文件
# 参数: $1 - JSON文件路径
#       $2 - jq过滤器表达式
#       $3 - 是否创建备份 (true/false, 默认true)
# 返回: 0=成功, 1=失败
jsonModifyFile() {
    local file="$1"
    local filter="$2"
    local backup="${3:-true}"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # 验证源文件
    if ! jq -e . "${file}" >/dev/null 2>&1; then
        return 1
    fi

    # 创建备份
    if [[ "${backup}" == "true" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # 写入临时文件
    local tmpFile="${JSON_TMP_PREFIX}_$$_$(date +%s)"
    if ! jq "${filter}" "${file}" > "${tmpFile}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    # 验证结果
    if ! jq -e . "${tmpFile}" >/dev/null 2>&1; then
        rm -f "${tmpFile}"
        return 1
    fi

    # 原子移动
    if ! mv "${tmpFile}" "${file}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    return 0
}

# ============================================================================
# JSON创建函数
# ============================================================================

# 创建空JSON对象
jsonCreateObject() {
    echo "{}"
}

# 创建空JSON数组
jsonCreateArray() {
    echo "[]"
}

# 使用参数创建JSON对象
# 参数: key=value 对，交替传入
# 示例: jsonBuildObject "name" "test" "port" 443
# 输出: {"name":"test","port":443}
jsonBuildObject() {
    local result="{}"
    local key value

    while [[ $# -ge 2 ]]; do
        key="$1"
        value="$2"
        shift 2

        # 检测值类型并适当处理
        if [[ "${value}" =~ ^[0-9]+$ ]]; then
            # 纯数字，作为数字处理
            result=$(echo "${result}" | jq --arg k "${key}" --argjson v "${value}" '.[$k] = $v')
        elif [[ "${value}" == "true" || "${value}" == "false" ]]; then
            # 布尔值
            result=$(echo "${result}" | jq --arg k "${key}" --argjson v "${value}" '.[$k] = $v')
        elif [[ "${value}" == "null" ]]; then
            # null值
            result=$(echo "${result}" | jq --arg k "${key}" '.[$k] = null')
        elif echo "${value}" | jq -e . >/dev/null 2>&1; then
            # 有效JSON，直接嵌入
            result=$(echo "${result}" | jq --arg k "${key}" --argjson v "${value}" '.[$k] = $v')
        else
            # 字符串
            result=$(echo "${result}" | jq --arg k "${key}" --arg v "${value}" '.[$k] = $v')
        fi
    done

    echo "${result}"
}

# ============================================================================
# 合并函数
# ============================================================================

# 合并两个JSON对象
# 参数: $1 - 基础JSON（字符串或文件路径）
#       $2 - 要合并的JSON（字符串或文件路径）
# 输出: 合并后的JSON
jsonMergeObjects() {
    local base="$1"
    local overlay="$2"

    # 检测是文件还是字符串
    local baseJson overlayJson

    if [[ -f "${base}" ]]; then
        baseJson=$(cat "${base}")
    else
        baseJson="${base}"
    fi

    if [[ -f "${overlay}" ]]; then
        overlayJson=$(cat "${overlay}")
    else
        overlayJson="${overlay}"
    fi

    echo "${baseJson}" | jq --argjson overlay "${overlayJson}" '. * $overlay'
}

# 合并JSON数组
# 参数: $1 - 第一个数组（JSON字符串）
#       $2 - 第二个数组（JSON字符串）
# 输出: 合并后的数组
jsonMergeArrays() {
    local arr1="$1"
    local arr2="$2"

    echo "${arr1}" | jq --argjson arr2 "${arr2}" '. + $arr2'
}

# ============================================================================
# 清理函数
# ============================================================================

# 清理旧的备份文件
# 参数: $1 - 目录路径
#       $2 - 保留天数 (默认7)
jsonCleanupBackups() {
    local dir="$1"
    local days="${2:-7}"

    find "${dir}" -name "*.bak.*" -mtime +"${days}" -delete 2>/dev/null
}

# 清理临时文件
jsonCleanupTmp() {
    rm -f "${JSON_TMP_PREFIX}"_* 2>/dev/null
}
