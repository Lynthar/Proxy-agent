#!/usr/bin/env bash
# ============================================================================
# protocol-registry.sh - 协议注册表
#
# 集中管理协议 ID、配置文件映射、协议属性查询
# 依赖 constants.sh 先加载
# ============================================================================

# 防止重复加载
[[ -n "${_PROTOCOL_REGISTRY_LOADED:-}" ]] && return 0
readonly _PROTOCOL_REGISTRY_LOADED=1

# ============================================================================
# 协议配置文件名映射
# ============================================================================

# 获取协议对应的配置文件名（不含路径）
# 参数: $1 - 协议ID
# 输出: 配置文件名
getProtocolConfigFileName() {
    local protocolId="$1"

    case "${protocolId}" in
        0)  echo "02_VLESS_TCP_inbounds.json" ;;
        1)  echo "03_VLESS_WS_inbounds.json" ;;
        2)  echo "04_trojan_gRPC_inbounds.json" ;;  # 已废弃
        3)  echo "05_VMess_WS_inbounds.json" ;;
        4)  echo "04_trojan_TCP_inbounds.json" ;;
        5)  echo "06_VLESS_gRPC_inbounds.json" ;;  # 已废弃
        6)  echo "06_hysteria2_inbounds.json" ;;
        7)  echo "07_VLESS_vision_reality_inbounds.json" ;;
        8)  echo "08_VLESS_vision_gRPC_inbounds.json" ;;  # 已废弃
        9)  echo "09_tuic_inbounds.json" ;;
        10) echo "10_naive_inbounds.json" ;;
        11) echo "11_VMess_HTTPUpgrade_inbounds.json" ;;
        12) echo "12_VLESS_XHTTP_inbounds.json" ;;
        13) echo "13_anytls_inbounds.json" ;;
        14) echo "14_ss2022_inbounds.json" ;;
        20) echo "20_socks5_inbounds.json" ;;
        *)  return 1 ;;
    esac
}

# 从文件名解析协议ID
# 参数: $1 - 配置文件名（可含路径）
# 输出: 协议ID
parseProtocolIdFromFileName() {
    local filename
    filename=$(basename "$1")

    case "${filename}" in
        *VLESS_TCP_inbounds.json)           echo "0" ;;
        *VLESS_WS_inbounds.json)            echo "1" ;;
        *trojan_gRPC_inbounds.json)         echo "2" ;;
        *VMess_WS_inbounds.json)            echo "3" ;;
        *trojan_TCP_inbounds.json)          echo "4" ;;
        *VLESS_gRPC_inbounds.json)          echo "5" ;;
        *hysteria2_inbounds.json)           echo "6" ;;
        *VLESS_vision_reality_inbounds.json) echo "7" ;;
        *VLESS_vision_gRPC_inbounds.json)   echo "8" ;;
        *tuic_inbounds.json)                echo "9" ;;
        *naive_inbounds.json)               echo "10" ;;
        *VMess_HTTPUpgrade_inbounds.json)   echo "11" ;;
        *VLESS_XHTTP_inbounds.json)         echo "12" ;;
        *anytls_inbounds.json)              echo "13" ;;
        *ss2022_inbounds.json)              echo "14" ;;
        *socks5_inbounds.json)              echo "20" ;;
        *)  return 1 ;;
    esac
}

# ============================================================================
# 协议显示名称
# ============================================================================

# 获取协议显示名称
# 参数: $1 - 协议ID
# 输出: 显示名称
getProtocolDisplayName() {
    local protocolId="$1"

    case "${protocolId}" in
        0)  echo "VLESS+TCP/TLS_Vision" ;;
        1)  echo "VLESS+WS+TLS" ;;
        2)  echo "Trojan+gRPC+TLS" ;;
        3)  echo "VMess+WS+TLS" ;;
        4)  echo "Trojan+TCP+TLS" ;;
        5)  echo "VLESS+gRPC+TLS" ;;
        6)  echo "Hysteria2" ;;
        7)  echo "VLESS+Reality+Vision" ;;
        8)  echo "VLESS+Reality+gRPC" ;;
        9)  echo "TUIC" ;;
        10) echo "Naive" ;;
        11) echo "VMess+HTTPUpgrade+TLS" ;;
        12) echo "VLESS+Reality+XHTTP" ;;
        13) echo "AnyTLS" ;;
        14) echo "Shadowsocks 2022" ;;
        20) echo "SOCKS5" ;;
        *)  echo "Unknown" ;;
    esac
}

# 获取协议短名称（用于订阅链接/URL）
# 参数: $1 - 协议ID
getProtocolShortName() {
    local protocolId="$1"

    case "${protocolId}" in
        0)  echo "vless_vision" ;;
        1)  echo "vless_ws" ;;
        2)  echo "trojan_grpc" ;;
        3)  echo "vmess_ws" ;;
        4)  echo "trojan_tcp" ;;
        5)  echo "vless_grpc" ;;
        6)  echo "hysteria2" ;;
        7)  echo "vless_reality_vision" ;;
        8)  echo "vless_reality_grpc" ;;
        9)  echo "tuic" ;;
        10) echo "naive" ;;
        11) echo "vmess_httpupgrade" ;;
        12) echo "vless_reality_xhttp" ;;
        13) echo "anytls" ;;
        14) echo "ss2022" ;;
        20) echo "socks5" ;;
        *)  echo "unknown" ;;
    esac
}

# 获取协议的 sing-box inbound tag
# 参数: $1 - 协议ID
# 输出: sing-box 入站标签名称
getProtocolInboundTag() {
    local protocolId="$1"

    case "${protocolId}" in
        0)  echo "VLESSTCP" ;;
        1)  echo "VLESSWS" ;;
        3)  echo "VMessWS" ;;
        4)  echo "trojanTCP" ;;
        6)  echo "hysteria2-in" ;;
        7)  echo "VLESSReality" ;;
        9)  echo "singbox-tuic-in" ;;
        10) echo "singbox-naive-in" ;;
        11) echo "VMessHTTPUpgrade" ;;
        12) echo "VLESSRealityXHTTP" ;;
        13) echo "anytls" ;;
        14) echo "ss2022-in" ;;
        *)  return 1 ;;
    esac
}

# ============================================================================
# 协议属性查询
# ============================================================================

# 检查协议是否需要 TLS 证书
# 返回: 0=需要, 1=不需要
protocolRequiresTLS() {
    local protocolId="$1"

    case "${protocolId}" in
        0|1|2|3|4|5|10|11|13)
            return 0
            ;;
        6|7|8|9|12|14|20)
            return 1  # Reality / UDP / 自签
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查协议是否使用 Reality
protocolUsesReality() {
    local protocolId="$1"

    case "${protocolId}" in
        7|8|12) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查协议是否使用 UDP
protocolUsesUDP() {
    local protocolId="$1"

    case "${protocolId}" in
        6|9) return 0 ;;  # Hysteria2, TUIC
        *) return 1 ;;
    esac
}

# 检查协议是否支持 CDN
protocolSupportsCDN() {
    local protocolId="$1"

    case "${protocolId}" in
        1|3|5|11|12) return 0 ;;  # WS / gRPC / HTTPUpgrade / XHTTP
        *) return 1 ;;
    esac
}

# 获取协议传输类型
# 输出: tcp / ws / grpc / httpupgrade / xhttp / quic / http2 / anytls / shadowsocks / socks5
getProtocolTransport() {
    local protocolId="$1"

    case "${protocolId}" in
        0|4|7)  echo "tcp" ;;
        1|3)    echo "ws" ;;
        2|5|8)  echo "grpc" ;;
        11)     echo "httpupgrade" ;;
        12)     echo "xhttp" ;;
        6|9)    echo "quic" ;;
        10)     echo "http2" ;;
        13)     echo "anytls" ;;
        14)     echo "shadowsocks" ;;
        20)     echo "socks5" ;;
        *)      echo "unknown" ;;
    esac
}

# ============================================================================
# 协议检测与路径
# ============================================================================

# 扫描已安装的协议
# 参数: $1 - 配置目录路径
# 输出: 逗号分隔的协议ID字符串 (如 ",0,1,7,")
scanInstalledProtocols() {
    local cfgPath="$1"
    local result=","
    local file protocolId

    [[ ! -d "${cfgPath}" ]] && echo "" && return 1

    while IFS= read -r file; do
        protocolId=$(parseProtocolIdFromFileName "${file}")
        if [[ -n "${protocolId}" ]]; then
            result="${result}${protocolId},"
        fi
    done < <(find "${cfgPath}" -name "*_inbounds.json" -type f 2>/dev/null | sort)

    echo "${result}"
}

# 获取协议配置文件完整路径
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选，默认 ${configPath})
# 输出: 完整文件路径
getProtocolConfigPath() {
    local protocolId="$1"
    local cfgPath="${2:-${configPath}}"
    local fileName

    fileName=$(getProtocolConfigFileName "${protocolId}")
    [[ -z "${fileName}" ]] && return 1

    echo "${cfgPath}${fileName}"
}
