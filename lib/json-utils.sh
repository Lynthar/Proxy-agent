#!/usr/bin/env bash
# ============================================================================
# json-utils.sh - JSON 操作工具函数
#
# 提供安全的 JSON 读取、验证、原子写入功能
# 封装 jq 操作，添加错误处理
# ============================================================================

# 防止重复加载
[[ -n "${_JSON_UTILS_LOADED:-}" ]] && return 0
readonly _JSON_UTILS_LOADED=1

# ============================================================================
# 常量定义
# ============================================================================

# JSON 临时文件前缀（mktemp 会在此基础上加 6 字节随机后缀）
readonly JSON_TMP_PREFIX="/tmp/Proxy-agent-json"

# ============================================================================
# 验证函数
# ============================================================================

# 验证 JSON 文件语法
# 参数: $1 - JSON 文件路径
# 返回: 0=有效, 1=无效
jsonValidateFile() {
    local file="$1"

    [[ -z "${file}" ]] && return 1
    [[ ! -f "${file}" ]] && return 1

    jq -e . "${file}" >/dev/null 2>&1
}

# ============================================================================
# 读取函数
# ============================================================================

# 从 JSON 文件读取单个值
# 参数: $1 - JSON 文件路径
#       $2 - jq 路径表达式 (如 .inbounds[0].port)
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

# 从 JSON 文件读取数组
# 参数: $1 - JSON 文件路径
#       $2 - jq 路径表达式
# 输出: 紧凑格式的 JSON 数组；缺失/无效时输出 "[]"
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
# 参数: $1 - JSON 文件路径
#       $2 - jq 路径表达式
# 输出: 数组长度（缺失或无效返回 0）
jsonGetArrayLength() {
    local file="$1"
    local path="$2"

    if [[ ! -f "${file}" ]]; then
        echo "0"
        return 1
    fi

    jq -r "${path} | length // 0" "${file}" 2>/dev/null || echo "0"
}

# ============================================================================
# 数组追加函数
# ============================================================================

# 向数组追加元素
# 参数: $1 - JSON 文件路径
#       $2 - 数组路径
#       $3 - 要追加的元素（JSON 格式）
# 输出: 修改后的完整 JSON（仅输出，不写回）
# 注: 需要原子写回时，调用方应该把结果通过 jsonWriteFile 写回
jsonArrayAppend() {
    local file="$1"
    local arrayPath="$2"
    local element="$3"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    jq "${arrayPath} += [${element}]" "${file}" 2>/dev/null
}

# ============================================================================
# 原子文件写入函数
# ============================================================================

# 安全写入 JSON 到文件（原子操作）
# 参数: $1 - 目标文件路径
#       $2 - JSON 内容
#       $3 - 是否创建备份 (true/false, 默认 true)
# 返回: 0=成功, 1=失败（写入路径上任何错误都保留原文件不变）
# 流程: 验证 JSON 语法 → 可选备份旧文件 → 写 mktemp 临时文件 → 原子 rename
jsonWriteFile() {
    local file="$1"
    local content="$2"
    local backup="${3:-true}"

    # 验证 JSON 语法
    if ! echo "${content}" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    # 可选备份
    if [[ "${backup}" == "true" && -f "${file}" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # 写入临时文件（mktemp 保证并发安全）
    local tmpFile
    tmpFile=$(mktemp "${JSON_TMP_PREFIX}_XXXXXXXX") || return 1
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

# 安全修改 JSON 文件（原子操作，jq 过滤器驱动）
# 参数: $1 - JSON 文件路径
#       $2 - jq 过滤器表达式
#       $3 - 是否创建备份 (true/false, 默认 true)
# 返回: 0=成功, 1=失败
# 流程: 验证源文件 → 可选备份 → jq 到 mktemp 临时文件 → 验证结果 → 原子 rename
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

    # 可选备份
    if [[ "${backup}" == "true" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # jq 输出到临时文件
    local tmpFile
    tmpFile=$(mktemp "${JSON_TMP_PREFIX}_XXXXXXXX") || return 1
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
# Xray 配置专用读取函数
# ============================================================================

# 读取 Xray 入站端口
# 用法: port=$(xrayGetInboundPort "/path/to/config.json" 0)
xrayGetInboundPort() {
    local file="$1"
    local index="${2:-0}"

    jsonGetValue "${file}" ".inbounds[${index}].port"
}

# 读取 Xray 入站协议
# 用法: protocol=$(xrayGetInboundProtocol "/path/to/config.json" 0)
xrayGetInboundProtocol() {
    local file="$1"
    local index="${2:-0}"

    jsonGetValue "${file}" ".inbounds[${index}].protocol"
}

# 读取 Xray 客户端 UUID
# 用法: uuid=$(xrayGetClientUUID "/path/to/config.json" 0 0)
xrayGetClientUUID() {
    local file="$1"
    local inboundIndex="${2:-0}"
    local clientIndex="${3:-0}"

    jsonGetValue "${file}" ".inbounds[${inboundIndex}].settings.clients[${clientIndex}].id"
}

# 读取 Xray 所有客户端配置 (JSON 数组)
# 用法: clients=$(xrayGetClients "/path/to/config.json" 0)
xrayGetClients() {
    local file="$1"
    local index="${2:-0}"

    jsonGetArray "${file}" ".inbounds[${index}].settings.clients"
}

# 读取 Xray TLS 证书路径中的域名
# 用法: domain=$(xrayGetTLSDomain "/path/to/config.json")
xrayGetTLSDomain() {
    local file="$1"
    local certPath

    certPath=$(jsonGetValue "${file}" ".inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile")
    if [[ -n "${certPath}" ]]; then
        # 从路径 /etc/Proxy-agent/tls/domain.crt 提取域名
        echo "${certPath}" | awk -F '[/]' '{print $(NF)}' | sed 's/\.crt$//'
    fi
}

# 读取 Xray Reality 配置
# 直接写入全局变量，避免 eval 注入面。输出名前缀 reality*
# 用法:
#   xrayGetRealityConfig "/path/to/config.json" 1
#   echo "${realityServerName} ${realityPublicKey}"
xrayGetRealityConfig() {
    local file="$1"
    local index="${2:-1}"

    realityServerName=$(jsonGetValue "${file}" ".inbounds[${index}].streamSettings.realitySettings.serverNames[0]")
    realityPublicKey=$(jsonGetValue "${file}" ".inbounds[${index}].streamSettings.realitySettings.publicKey")
    realityPrivateKey=$(jsonGetValue "${file}" ".inbounds[${index}].streamSettings.realitySettings.privateKey")
    realityTarget=$(jsonGetValue "${file}" ".inbounds[${index}].streamSettings.realitySettings.target")
    realityMldsa65Seed=$(jsonGetValue "${file}" ".inbounds[${index}].streamSettings.realitySettings.mldsa65Seed")
    realityMldsa65Verify=$(jsonGetValue "${file}" ".inbounds[${index}].streamSettings.realitySettings.mldsa65Verify")
}

# 读取 Xray 流设置中的路径
# 用法: path=$(xrayGetStreamPath "/path/to/config.json" "ws")
xrayGetStreamPath() {
    local file="$1"
    local network="${2:-ws}"

    case "${network}" in
        ws)
            jsonGetValue "${file}" ".inbounds[0].streamSettings.wsSettings.path"
            ;;
        grpc)
            jsonGetValue "${file}" ".inbounds[0].streamSettings.grpcSettings.serviceName"
            ;;
        xhttp)
            jsonGetValue "${file}" ".inbounds[0].streamSettings.xhttpSettings.path"
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================================
# sing-box 配置专用读取函数
# ============================================================================

# 读取 sing-box 入站端口
# 用法: port=$(singboxGetInboundPort "/path/to/config.json" 0)
singboxGetInboundPort() {
    local file="$1"
    local index="${2:-0}"

    jsonGetValue "${file}" ".inbounds[${index}].listen_port"
}

# 读取 sing-box 用户 UUID
# 用法: uuid=$(singboxGetUserUUID "/path/to/config.json" 0 0)
singboxGetUserUUID() {
    local file="$1"
    local inboundIndex="${2:-0}"
    local userIndex="${3:-0}"

    jsonGetValue "${file}" ".inbounds[${inboundIndex}].users[${userIndex}].uuid"
}

# 读取 sing-box TLS 服务器名称
# 用法: serverName=$(singboxGetTLSServerName "/path/to/config.json")
singboxGetTLSServerName() {
    local file="$1"
    local index="${2:-0}"

    jsonGetValue "${file}" ".inbounds[${index}].tls.server_name"
}

# 读取 sing-box Reality 配置
# 直接写入全局变量，避免 eval 注入面。输出名前缀 singboxReality*
# 用法:
#   singboxGetRealityConfig "/path/to/config.json" 0
#   echo "${singboxRealityServerName}"
singboxGetRealityConfig() {
    local file="$1"
    local index="${2:-0}"

    singboxRealityServerName=$(jsonGetValue "${file}" ".inbounds[${index}].tls.server_name")
    singboxRealityPrivateKey=$(jsonGetValue "${file}" ".inbounds[${index}].tls.reality.private_key")
    singboxRealityHandshakeServer=$(jsonGetValue "${file}" ".inbounds[${index}].tls.reality.handshake.server")
    singboxRealityHandshakePort=$(jsonGetValue "${file}" ".inbounds[${index}].tls.reality.handshake.server_port")
}

# 读取 Hysteria2 配置
# 直接写入全局变量；输出名前缀 hysteria2*
# 用法:
#   singboxGetHysteria2Config "/path/to/config.json"
#   echo "${hysteria2Port} ${hysteria2UpMbps}"
singboxGetHysteria2Config() {
    local file="$1"

    hysteria2Port=$(jsonGetValue "${file}" ".inbounds[0].listen_port")
    hysteria2UpMbps=$(jsonGetValue "${file}" ".inbounds[0].up_mbps")
    hysteria2DownMbps=$(jsonGetValue "${file}" ".inbounds[0].down_mbps")
    hysteria2ObfsPassword=$(jsonGetValue "${file}" ".inbounds[0].obfs.password")
}

# 读取 TUIC 配置
# 直接写入全局变量；输出名前缀 tuic*
# 用法:
#   singboxGetTuicConfig "/path/to/config.json"
#   echo "${tuicPort} ${tuicAlgorithm}"
singboxGetTuicConfig() {
    local file="$1"

    tuicPort=$(jsonGetValue "${file}" ".inbounds[0].listen_port")
    tuicAlgorithm=$(jsonGetValue "${file}" ".inbounds[0].congestion_control")
}
