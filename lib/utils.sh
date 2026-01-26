#!/usr/bin/env bash
# ============================================================================
# utils.sh - Proxy-agent 工具函数
# ============================================================================
# 本文件包含纯工具函数，这些函数没有副作用，不修改全局变量
# ============================================================================

# 防止重复加载
[[ -n "${_UTILS_LOADED}" ]] && return 0
readonly _UTILS_LOADED=1

# ============================================================================
# 颜色输出函数
# ============================================================================

# 彩色输出
# 用法: echoContent red "错误信息"
#       echoContent green "成功信息"
echoContent() {
    local color="$1"
    local content="$2"

    case "${color}" in
        red)
            echo -e "\033[31m${content}\033[0m"
            ;;
        green)
            echo -e "\033[32m${content}\033[0m"
            ;;
        yellow)
            echo -e "\033[33m${content}\033[0m"
            ;;
        blue)
            echo -e "\033[34m${content}\033[0m"
            ;;
        purple)
            echo -e "\033[35m${content}\033[0m"
            ;;
        skyBlue)
            echo -e "\033[36m${content}\033[0m"
            ;;
        white)
            echo -e "\033[37m${content}\033[0m"
            ;;
        *)
            echo -e "${content}"
            ;;
    esac
}

# ============================================================================
# 字符串处理函数
# ============================================================================

# 移除 ANSI 控制字符
# 用法: cleanText=$(stripAnsi "$coloredText")
stripAnsi() {
    echo -e "$@" | sed 's/\x1B\[[0-9;]*[JKmsu]//g'
}

# 去除字符串首尾空格
# 用法: trimmed=$(trim "  hello  ")
trim() {
    local str="$1"
    # 去除开头空格
    str="${str#"${str%%[![:space:]]*}"}"
    # 去除结尾空格
    str="${str%"${str##*[![:space:]]}"}"
    echo "${str}"
}

# URL 编码
# 用法: encoded=$(urlEncode "hello world")
urlEncode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for ((pos = 0; pos < strlen; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9])
                o="${c}"
                ;;
            *)
                printf -v o '%%%02X' "'$c"
                ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Base64 编码 (跨平台兼容)
# 用法: encoded=$(base64Encode "hello")
base64Encode() {
    echo -n "$1" | base64 | tr -d '\n'
}

# Base64 解码 (跨平台兼容)
# 用法: decoded=$(base64Decode "aGVsbG8=")
base64Decode() {
    echo -n "$1" | base64 -d 2>/dev/null || echo -n "$1" | base64 -D 2>/dev/null
}

# ============================================================================
# 数值处理函数
# ============================================================================

# 生成随机数 - 使用更安全的随机源
# 用法: num=$(randomNum 1000 9999)
# 注意: 对于非敏感场景，使用 /dev/urandom 提供足够的随机性
randomNum() {
    local min="${1:-0}"
    local max="${2:-65535}"
    local range=$((max - min + 1))

    # 优先使用 /dev/urandom（更安全）
    if [[ -r /dev/urandom ]]; then
        local random_bytes
        random_bytes=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
        echo $((random_bytes % range + min))
    # 回退到 shuf（如果可用）
    elif command -v shuf &>/dev/null; then
        shuf -i "${min}-${max}" -n 1
    # 最后回退到 $RANDOM（不够安全，但保证兼容性）
    else
        echo $((RANDOM % range + min))
    fi
}

# 生成随机端口 (10000-30000)
# 用法: port=$(randomPort)
randomPort() {
    randomNum 10000 30000
}

# 检查是否为有效端口号
# 用法: if isValidPort 443; then ...
isValidPort() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

# ============================================================================
# 文件和路径函数
# ============================================================================

# 检查文件是否存在且非空
# 用法: if fileExistsAndNotEmpty "/path/to/file"; then ...
fileExistsAndNotEmpty() {
    local file="$1"
    [[ -f "${file}" && -s "${file}" ]]
}

# 检查目录是否存在
# 用法: if dirExists "/path/to/dir"; then ...
dirExists() {
    [[ -d "$1" ]]
}

# 安全创建目录
# 用法: ensureDir "/path/to/dir"
ensureDir() {
    local dir="$1"
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
}

# 获取文件的绝对路径
# 用法: absPath=$(getAbsolutePath "./relative/path")
getAbsolutePath() {
    local path="$1"
    if [[ -d "${path}" ]]; then
        (cd "${path}" && pwd)
    elif [[ -f "${path}" ]]; then
        local dir
        dir=$(dirname "${path}")
        echo "$(cd "${dir}" && pwd)/$(basename "${path}")"
    else
        echo "${path}"
    fi
}

# ============================================================================
# JSON 处理函数
# ============================================================================

# 验证 JSON 文件格式
# 用法: if validateJsonFile "/path/to/file.json"; then ...
validateJsonFile() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        return 1
    fi
    jq empty "${file}" 2>/dev/null
}

# 从 JSON 文件读取值
# 用法: value=$(jsonRead "/path/to/file.json" ".inbounds[0].port")
jsonRead() {
    local file="$1"
    local path="$2"
    if [[ -f "${file}" ]]; then
        jq -r "${path} // empty" "${file}" 2>/dev/null
    fi
}

# 检查 jq 是否可用
# 用法: if jqAvailable; then ...
jqAvailable() {
    command -v jq &>/dev/null
}

# ============================================================================
# 网络相关函数
# ============================================================================

# 检查端口是否被占用
# 用法: if isPortInUse 443; then ...
isPortInUse() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":${port} "
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} "
    else
        return 1
    fi
}

# 检查域名是否解析到本机IP
# 用法: if domainResolvesToLocal "example.com"; then ...
domainResolvesToLocal() {
    local domain="$1"
    local localIPs
    local domainIP

    # 获取本机所有IP
    localIPs=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | tr '\n' ' ')

    # 解析域名
    domainIP=$(dig +short "${domain}" 2>/dev/null | head -1)

    [[ -n "${domainIP}" && "${localIPs}" == *"${domainIP}"* ]]
}

# 简单的HTTP GET请求 (仅获取状态码)
# 用法: statusCode=$(httpStatus "https://example.com")
httpStatus() {
    local url="$1"
    local timeout="${2:-10}"
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout "${timeout}" "${url}" 2>/dev/null
}

# ============================================================================
# UUID 相关函数
# ============================================================================

# 生成 UUID v4
# 用法: uuid=$(generateUUID)
generateUUID() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # 备用方法
        od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}'
    fi
}

# 验证 UUID 格式
# 用法: if isValidUUID "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"; then ...
isValidUUID() {
    local uuid="$1"
    [[ "${uuid}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

# ============================================================================
# 版本比较函数
# ============================================================================

# 比较版本号
# 用法: if versionGreaterThan "1.2.3" "1.2.0"; then ...
# 返回: 0 如果 v1 > v2
versionGreaterThan() {
    local v1="$1"
    local v2="$2"
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" != "$v1" ]]
}

# 比较版本号 (大于等于)
# 用法: if versionGreaterOrEqual "1.2.3" "1.2.0"; then ...
versionGreaterOrEqual() {
    local v1="$1"
    local v2="$2"
    [[ "$v1" == "$v2" ]] || versionGreaterThan "$v1" "$v2"
}

# ============================================================================
# 时间相关函数
# ============================================================================

# 获取当前时间戳
# 用法: ts=$(timestamp)
timestamp() {
    date +%s
}

# 获取格式化日期时间
# 用法: dt=$(datetime)
datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

# ============================================================================
# 日志函数
# ============================================================================

# 日志输出 (带时间戳)
# 用法: logInfo "This is info message"
logInfo() {
    echo "[$(datetime)] [INFO] $*"
}

logWarn() {
    echo "[$(datetime)] [WARN] $*" >&2
}

logError() {
    echo "[$(datetime)] [ERROR] $*" >&2
}

logDebug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[$(datetime)] [DEBUG] $*" >&2
    fi
}

# ============================================================================
# 数组操作函数
# ============================================================================

# 检查数组是否包含元素
# 用法: if arrayContains "element" "${array[@]}"; then ...
arrayContains() {
    local element="$1"
    shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${element}" ]] && return 0
    done
    return 1
}

# 数组去重
# 用法: uniqueArray=($(arrayUnique "${array[@]}"))
arrayUnique() {
    printf '%s\n' "$@" | sort -u
}
