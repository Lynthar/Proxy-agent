#!/usr/bin/env bash
# ============================================================================
# json-utils.sh - JSON 读取、校验、原子写入（封装 jq，统一错误处理）
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

# jsonGetValue FILE JQ_PATH [DEFAULT] → 值；文件缺失或路径不存在时输出 DEFAULT
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

# jsonGetArray FILE JQ_PATH → 紧凑 JSON 数组；缺失或无效时输出 []
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

# jsonGetArrayLength FILE JQ_PATH → 数组长度；缺失或无效时输出 0
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

# jsonArrayAppend FILE ARRAY_PATH ELEMENT_JSON → 修改后的完整 JSON（只输出，不写回）
# 要落盘必须把结果交给 jsonWriteFile，否则不是原子的。
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

# jsonWriteFile FILE CONTENT [BACKUP=true] → 0=成功 1=失败
# 验证语法 → 可选备份 → 写 mktemp → 原子 rename；任一步失败原文件不变。
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

# jsonModifyFile FILE JQ_FILTER [BACKUP=true] → 0=成功 1=失败
# 验证源文件 → 可选备份 → jq 到 mktemp → 验证结果 → 原子 rename。
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

# xrayGetRealityConfig FILE [INDEX=1] → 写全局 realityServerName / realityPublicKey / …
# 走全局变量而非回显 heredoc + eval，那条路径是注入面。
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

# singboxGetRealityConfig FILE [INDEX=0] → 写全局 singboxRealityServerName / …
singboxGetRealityConfig() {
    local file="$1"
    local index="${2:-0}"

    singboxRealityServerName=$(jsonGetValue "${file}" ".inbounds[${index}].tls.server_name")
    singboxRealityPrivateKey=$(jsonGetValue "${file}" ".inbounds[${index}].tls.reality.private_key")
    singboxRealityHandshakeServer=$(jsonGetValue "${file}" ".inbounds[${index}].tls.reality.handshake.server")
    singboxRealityHandshakePort=$(jsonGetValue "${file}" ".inbounds[${index}].tls.reality.handshake.server_port")
}

# singboxGetHysteria2Config FILE → 写全局 hysteria2Port / hysteria2UpMbps / …
singboxGetHysteria2Config() {
    local file="$1"

    hysteria2Port=$(jsonGetValue "${file}" ".inbounds[0].listen_port")
    hysteria2UpMbps=$(jsonGetValue "${file}" ".inbounds[0].up_mbps")
    hysteria2DownMbps=$(jsonGetValue "${file}" ".inbounds[0].down_mbps")
    hysteria2ObfsPassword=$(jsonGetValue "${file}" ".inbounds[0].obfs.password")
}

# singboxGetTuicConfig FILE → 写全局 tuicPort / tuicAlgorithm
singboxGetTuicConfig() {
    local file="$1"

    tuicPort=$(jsonGetValue "${file}" ".inbounds[0].listen_port")
    tuicAlgorithm=$(jsonGetValue "${file}" ".inbounds[0].congestion_control")
}
