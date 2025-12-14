#!/usr/bin/env bash
# ============================================================================
# config-reader.sh - 配置读取接口
#
# 提供统一的配置读取接口，封装对各类配置文件的读取操作
# 依赖: json-utils.sh, protocol-registry.sh
# ============================================================================

# 防止重复加载
[[ -n "${_CONFIG_READER_LOADED}" ]] && return 0
readonly _CONFIG_READER_LOADED=1

# ============================================================================
# 默认路径常量
# ============================================================================

# Xray配置路径
readonly XRAY_CONFIG_BASE="/etc/v2ray-agent/xray"
readonly XRAY_CONFIG_PATH="${XRAY_CONFIG_BASE}/conf/"
readonly XRAY_BINARY="${XRAY_CONFIG_BASE}/xray"

# sing-box配置路径
readonly SINGBOX_CONFIG_BASE="/etc/v2ray-agent/sing-box"
readonly SINGBOX_CONFIG_PATH="${SINGBOX_CONFIG_BASE}/conf/config/"
readonly SINGBOX_BINARY="${SINGBOX_CONFIG_BASE}/sing-box"

# TLS证书路径
readonly TLS_PATH="/etc/v2ray-agent/tls/"

# Nginx配置路径
readonly NGINX_CONFIG_PATH="/etc/nginx/conf.d/"

# 订阅路径
readonly SUBSCRIBE_LOCAL_PATH="/etc/v2ray-agent/subscribe_local/"

# ============================================================================
# 核心检测函数
# ============================================================================

# 检测安装的核心类型
# 输出: 1=xray, 2=sing-box, 空=未安装
detectCoreType() {
    if [[ -f "${XRAY_BINARY}" ]]; then
        # 检查是否有有效的配置文件
        if [[ -d "${XRAY_CONFIG_PATH}" ]] && \
           find "${XRAY_CONFIG_PATH}" -name "*_inbounds.json" -type f 2>/dev/null | grep -q .; then
            echo "1"
            return 0
        fi
    fi

    if [[ -f "${SINGBOX_BINARY}" ]]; then
        if [[ -d "${SINGBOX_CONFIG_PATH}" ]] && \
           find "${SINGBOX_CONFIG_PATH}" -name "*_inbounds.json" -type f 2>/dev/null | grep -q .; then
            echo "2"
            return 0
        fi
    fi

    return 1
}

# 获取配置目录路径
# 参数: $1 - 核心类型 (1=xray, 2=sing-box, 可选)
# 输出: 配置目录路径
getConfigPath() {
    local coreType="${1:-}"

    if [[ -z "${coreType}" ]]; then
        coreType=$(detectCoreType)
    fi

    case "${coreType}" in
        1) echo "${XRAY_CONFIG_PATH}" ;;
        2) echo "${SINGBOX_CONFIG_PATH}" ;;
        *) echo "" ;;
    esac
}

# 获取核心二进制路径
# 参数: $1 - 核心类型 (1=xray, 2=sing-box)
# 输出: 二进制文件路径
getCoreBinaryPath() {
    local coreType="${1:-}"

    if [[ -z "${coreType}" ]]; then
        coreType=$(detectCoreType)
    fi

    case "${coreType}" in
        1) echo "${XRAY_BINARY}" ;;
        2) echo "${SINGBOX_BINARY}" ;;
        *) echo "" ;;
    esac
}

# ============================================================================
# 协议配置读取
# ============================================================================

# 读取协议端口
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
#       $3 - 核心类型 (可选)
# 输出: 端口号
readProtocolPort() {
    local protocolId="$1"
    local cfgPath="${2:-}"
    local coreType="${3:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "${coreType}")
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    # Xray使用.port, sing-box使用.listen_port
    local port
    port=$(jq -r '.inbounds[0].port // .inbounds[0].listen_port // empty' "${configFile}" 2>/dev/null)

    [[ -n "${port}" && "${port}" != "null" ]] && echo "${port}" && return 0
    return 1
}

# 读取协议客户端列表
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
#       $3 - 核心类型 (可选)
# 输出: 客户端JSON数组
readProtocolClients() {
    local protocolId="$1"
    local cfgPath="${2:-}"
    local coreType="${3:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "${coreType}")
    [[ -z "${coreType}" ]] && coreType=$(detectCoreType)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    local clients
    if [[ "${coreType}" == "1" ]]; then
        # Xray格式
        clients=$(jq -c '.inbounds[0].settings.clients // []' "${configFile}" 2>/dev/null)
    else
        # sing-box格式
        clients=$(jq -c '.inbounds[0].users // []' "${configFile}" 2>/dev/null)
    fi

    echo "${clients:-[]}"
}

# 读取协议客户端数量
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
# 输出: 客户端数量
readProtocolClientCount() {
    local protocolId="$1"
    local cfgPath="${2:-}"

    local clients
    clients=$(readProtocolClients "${protocolId}" "${cfgPath}")

    echo "${clients}" | jq 'length' 2>/dev/null || echo "0"
}

# 读取指定索引的客户端
# 参数: $1 - 协议ID
#       $2 - 客户端索引
#       $3 - 配置目录路径 (可选)
# 输出: 客户端JSON对象
readProtocolClientByIndex() {
    local protocolId="$1"
    local index="$2"
    local cfgPath="${3:-}"

    local clients
    clients=$(readProtocolClients "${protocolId}" "${cfgPath}")

    echo "${clients}" | jq -c ".[${index}] // empty" 2>/dev/null
}

# 通过UUID/ID查找客户端
# 参数: $1 - 协议ID
#       $2 - UUID或密码
#       $3 - 配置目录路径 (可选)
# 输出: 客户端JSON对象
readProtocolClientByUUID() {
    local protocolId="$1"
    local uuid="$2"
    local cfgPath="${3:-}"

    local clients
    clients=$(readProtocolClients "${protocolId}" "${cfgPath}")

    # 尝试多种字段名
    echo "${clients}" | jq -c ".[] | select(.id == \"${uuid}\" or .uuid == \"${uuid}\" or .password == \"${uuid}\")" 2>/dev/null | head -1
}

# ============================================================================
# 域名和TLS配置读取
# ============================================================================

# 读取当前域名
# 参数: $1 - 配置目录路径 (可选)
#       $2 - 前置协议文件名 (可选)
# 输出: 域名
readCurrentHost() {
    local cfgPath="${1:-}"
    local frontingType="${2:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath)
    [[ -z "${cfgPath}" ]] && return 1

    # 尝试从TLS配置读取
    local configFile

    # 方法1: 从前置协议配置读取
    if [[ -n "${frontingType}" && -f "${cfgPath}${frontingType}" ]]; then
        configFile="${cfgPath}${frontingType}"
        local host
        host=$(jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile // empty' "${configFile}" 2>/dev/null)
        if [[ -n "${host}" ]]; then
            # 从证书路径提取域名
            host=$(basename "${host}" | sed 's/\.crt$//')
            [[ -n "${host}" ]] && echo "${host}" && return 0
        fi
    fi

    # 方法2: 从TLS目录读取
    if [[ -d "${TLS_PATH}" ]]; then
        local certFile
        certFile=$(find "${TLS_PATH}" -name "*.crt" -type f 2>/dev/null | head -1)
        if [[ -n "${certFile}" ]]; then
            local domain
            domain=$(basename "${certFile}" .crt)
            [[ -n "${domain}" ]] && echo "${domain}" && return 0
        fi
    fi

    return 1
}

# 读取TLS证书路径
# 参数: $1 - 域名
# 输出: 证书文件路径
readTLSCertPath() {
    local domain="$1"
    local certPath="${TLS_PATH}${domain}.crt"

    [[ -f "${certPath}" ]] && echo "${certPath}" && return 0
    return 1
}

# 读取TLS私钥路径
# 参数: $1 - 域名
# 输出: 私钥文件路径
readTLSKeyPath() {
    local domain="$1"
    local keyPath="${TLS_PATH}${domain}.key"

    [[ -f "${keyPath}" ]] && echo "${keyPath}" && return 0
    return 1
}

# ============================================================================
# Reality配置读取
# ============================================================================

# 读取Reality公钥
# 参数: $1 - 协议ID (7, 8, 或 12)
#       $2 - 配置目录路径 (可选)
#       $3 - 核心类型 (可选)
# 输出: 公钥
readRealityPublicKey() {
    local protocolId="$1"
    local cfgPath="${2:-}"
    local coreType="${3:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "${coreType}")
    [[ -z "${coreType}" ]] && coreType=$(detectCoreType)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    local pubKey
    if [[ "${coreType}" == "1" ]]; then
        # Xray格式
        pubKey=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // empty' "${configFile}" 2>/dev/null)
    else
        # sing-box格式
        pubKey=$(jq -r '.inbounds[0].tls.reality.public_key // empty' "${configFile}" 2>/dev/null)
    fi

    [[ -n "${pubKey}" && "${pubKey}" != "null" ]] && echo "${pubKey}" && return 0
    return 1
}

# 读取Reality私钥
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
#       $3 - 核心类型 (可选)
# 输出: 私钥
readRealityPrivateKey() {
    local protocolId="$1"
    local cfgPath="${2:-}"
    local coreType="${3:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "${coreType}")
    [[ -z "${coreType}" ]] && coreType=$(detectCoreType)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    local privKey
    if [[ "${coreType}" == "1" ]]; then
        # Xray格式
        privKey=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "${configFile}" 2>/dev/null)
    else
        # sing-box格式
        privKey=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "${configFile}" 2>/dev/null)
    fi

    [[ -n "${privKey}" && "${privKey}" != "null" ]] && echo "${privKey}" && return 0
    return 1
}

# 读取Reality目标域名
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
#       $3 - 核心类型 (可选)
# 输出: 目标域名
readRealityServerName() {
    local protocolId="$1"
    local cfgPath="${2:-}"
    local coreType="${3:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "${coreType}")
    [[ -z "${coreType}" ]] && coreType=$(detectCoreType)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    local serverName
    if [[ "${coreType}" == "1" ]]; then
        serverName=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "${configFile}" 2>/dev/null)
    else
        serverName=$(jq -r '.inbounds[0].tls.server_name // empty' "${configFile}" 2>/dev/null)
    fi

    [[ -n "${serverName}" && "${serverName}" != "null" ]] && echo "${serverName}" && return 0
    return 1
}

# 读取Reality ShortIds
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
# 输出: shortIds JSON数组
readRealityShortIds() {
    local protocolId="$1"
    local cfgPath="${2:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    jq -c '.inbounds[0].streamSettings.realitySettings.shortIds // []' "${configFile}" 2>/dev/null
}

# ============================================================================
# Hysteria2/TUIC特定配置读取
# ============================================================================

# 读取Hysteria2配置
# 参数: $1 - 配置目录路径 (可选)
# 输出: JSON对象 {port, uploadSpeed, downloadSpeed, obfsPassword}
readHysteria2Config() {
    local cfgPath="${1:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "2")
    [[ -z "${cfgPath}" ]] && return 1

    local configFile="${cfgPath}06_hysteria2_inbounds.json"
    [[ ! -f "${configFile}" ]] && return 1

    jq -c '{
        port: (.inbounds[0].listen_port // null),
        uploadSpeed: (.inbounds[0].up_mbps // null),
        downloadSpeed: (.inbounds[0].down_mbps // null),
        obfsPassword: (.inbounds[0].obfs.password // null)
    }' "${configFile}" 2>/dev/null
}

# 读取TUIC配置
# 参数: $1 - 配置目录路径 (可选)
# 输出: JSON对象 {port, algorithm}
readTuicConfig() {
    local cfgPath="${1:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "2")
    [[ -z "${cfgPath}" ]] && return 1

    local configFile="${cfgPath}09_tuic_inbounds.json"
    [[ ! -f "${configFile}" ]] && return 1

    jq -c '{
        port: (.inbounds[0].listen_port // null),
        algorithm: (.inbounds[0].congestion_control // "bbr")
    }' "${configFile}" 2>/dev/null
}

# ============================================================================
# Nginx配置读取
# ============================================================================

# 读取Nginx订阅配置
# 输出: JSON对象 {port, domain, type}
readNginxSubscribeConfig() {
    local configFile="${NGINX_CONFIG_PATH}subscribe.conf"
    [[ ! -f "${configFile}" ]] && return 1

    local port domain

    port=$(grep -E "listen\s+[0-9]+" "${configFile}" 2>/dev/null | head -1 | grep -oE "[0-9]+" | head -1)
    domain=$(grep -E "server_name\s+" "${configFile}" 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';')

    if [[ -n "${port}" ]]; then
        local subType="https"
        [[ "${port}" != "443" ]] && subType="custom"

        echo "{\"port\":${port},\"domain\":\"${domain}\",\"type\":\"${subType}\"}"
        return 0
    fi

    return 1
}

# ============================================================================
# WARP配置读取
# ============================================================================

# 读取WARP配置
# 输出: JSON对象 {privateKey, address, publicKey, reserved}
readWarpConfig() {
    local configFile="/etc/v2ray-agent/warp/config"
    [[ ! -f "${configFile}" ]] && return 1

    local privateKey address publicKey reserved

    privateKey=$(grep "private_key" "${configFile}" 2>/dev/null | awk -F "=" '{print $2}' | tr -d ' ')
    address=$(grep "v6" "${configFile}" 2>/dev/null | awk -F "=" '{print $2}' | tr -d ' ')
    publicKey=$(grep "public_key" "${configFile}" 2>/dev/null | awk -F "=" '{print $2}' | tr -d ' ')
    reserved=$(grep "reserved" "${configFile}" 2>/dev/null | awk -F "=" '{print $2}' | tr -d ' ')

    echo "{\"privateKey\":\"${privateKey}\",\"address\":\"${address}\",\"publicKey\":\"${publicKey}\",\"reserved\":\"${reserved}\"}"
}

# ============================================================================
# 路径读取
# ============================================================================

# 读取WebSocket路径
# 参数: $1 - 协议ID (1或3)
#       $2 - 配置目录路径 (可选)
#       $3 - 核心类型 (可选)
# 输出: 路径字符串
readWebSocketPath() {
    local protocolId="$1"
    local cfgPath="${2:-}"
    local coreType="${3:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath "${coreType}")
    [[ -z "${coreType}" ]] && coreType=$(detectCoreType)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    local path
    if [[ "${coreType}" == "1" ]]; then
        path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' "${configFile}" 2>/dev/null)
    else
        path=$(jq -r '.inbounds[0].transport.path // empty' "${configFile}" 2>/dev/null)
    fi

    [[ -n "${path}" && "${path}" != "null" ]] && echo "${path}" && return 0
    return 1
}

# 读取gRPC服务名
# 参数: $1 - 协议ID (2, 5, 或8)
#       $2 - 配置目录路径 (可选)
# 输出: 服务名字符串
readGrpcServiceName() {
    local protocolId="$1"
    local cfgPath="${2:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    configFile="${cfgPath}$(getProtocolConfigFileName "${protocolId}" 2>/dev/null)"
    [[ ! -f "${configFile}" ]] && return 1

    jq -r '.inbounds[0].streamSettings.grpcSettings.serviceName // .inbounds[0].transport.service_name // empty' "${configFile}" 2>/dev/null
}

# ============================================================================
# ALPN配置读取
# ============================================================================

# 读取ALPN配置
# 参数: $1 - 配置目录路径 (可选)
#       $2 - 前置协议文件名 (可选)
# 输出: ALPN协议字符串
readCurrentAlpn() {
    local cfgPath="${1:-}"
    local frontingType="${2:-}"

    [[ -z "${cfgPath}" ]] && cfgPath=$(getConfigPath)
    [[ -z "${cfgPath}" ]] && return 1

    local configFile
    if [[ -n "${frontingType}" && -f "${cfgPath}${frontingType}" ]]; then
        configFile="${cfgPath}${frontingType}"
    else
        # 查找第一个TLS配置文件
        configFile=$(find "${cfgPath}" -name "*_inbounds.json" -type f 2>/dev/null | head -1)
    fi

    [[ ! -f "${configFile}" ]] && return 1

    jq -r '.inbounds[0].streamSettings.tlsSettings.alpn[0] // empty' "${configFile}" 2>/dev/null
}

# ============================================================================
# 综合配置读取
# ============================================================================

# 读取完整安装状态
# 输出: JSON对象包含所有关键配置信息
readInstallationStatus() {
    local coreType protocols host

    coreType=$(detectCoreType)
    [[ -z "${coreType}" ]] && echo '{"installed":false}' && return 1

    local cfgPath
    cfgPath=$(getConfigPath "${coreType}")

    protocols=$(scanInstalledProtocols "${cfgPath}" 2>/dev/null)
    host=$(readCurrentHost "${cfgPath}" 2>/dev/null)

    jq -n \
        --arg coreType "${coreType}" \
        --arg protocols "${protocols}" \
        --arg host "${host:-}" \
        --arg configPath "${cfgPath}" \
        '{
            installed: true,
            coreType: ($coreType | tonumber),
            coreName: (if $coreType == "1" then "xray" else "sing-box" end),
            protocols: $protocols,
            host: $host,
            configPath: $configPath
        }'
}

# ============================================================================
# 兼容性辅助函数
# ============================================================================

# 设置全局变量（兼容现有代码）
# 用于在模块加载后初始化全局变量
initConfigReaderGlobals() {
    local status
    status=$(readInstallationStatus)

    if echo "${status}" | jq -e '.installed' >/dev/null 2>&1; then
        # 设置全局变量（如果它们未定义）
        : "${coreInstallType:=$(echo "${status}" | jq -r '.coreType')}"
        : "${configPath:=$(echo "${status}" | jq -r '.configPath')}"
        : "${currentInstallProtocolType:=$(echo "${status}" | jq -r '.protocols')}"
        : "${currentHost:=$(echo "${status}" | jq -r '.host // empty')}"

        return 0
    fi

    return 1
}
