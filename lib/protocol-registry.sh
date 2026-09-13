#!/usr/bin/env bash
# ============================================================================
# protocol-registry.sh - 协议 ID、配置文件映射与属性查询（需先加载 constants.sh）
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

# 协议显示名（主菜单「已安装协议」行、账户事务报错行、链式分流菜单共用同一套文案）
# 参数: $1 - 协议ID
getProtocolDisplayName() {
    local protocolId="$1"

    case "${protocolId}" in
        0)  echo "VLESS+TCP[TLS_Vision]" ;;
        1)  echo "VLESS+WS[TLS]" ;;
        2)  echo "Trojan+gRPC[TLS]" ;;
        3)  echo "VMess+WS[TLS]" ;;
        4)  echo "Trojan+TCP[TLS]" ;;
        5)  echo "VLESS+gRPC[TLS]" ;;
        6)  echo "Hysteria2" ;;
        7)  echo "VLESS+Reality+Vision" ;;
        8)  echo "VLESS+Reality+gRPC" ;;
        9)  echo "Tuic" ;;
        10) echo "Naive" ;;
        11) echo "VMess+TLS+HTTPUpgrade" ;;
        12) echo "VLESS+Reality+XHTTP" ;;
        13) echo "AnyTLS" ;;
        14) echo "SS2022" ;;
        20) echo "SOCKS5" ;;
        *)  echo "Unknown" ;;
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

# 检查协议是否需要 tls/ 下的 ACME 域名证书（Hysteria2/TUIC 的模板与装机流程都要它）
# 返回: 0=需要, 1=不需要（Reality / ss2022 / socks5）
protocolRequiresTLS() {
    local protocolId="$1"

    case "${protocolId}" in
        0|1|2|3|4|5|6|9|10|11|13) return 0 ;;
        *) return 1 ;;
    esac
}

# anyProtocolRequiresTLS ",0,6," → 0=清单里至少一个协议需要证书（装机前要不要先申请 TLS）
anyProtocolRequiresTLS() {
    local protocolId
    for protocolId in ${1//,/ }; do
        protocolRequiresTLS "${protocolId}" && return 0
    done
    return 1
}

# ============================================================================
# 账户字段映射（按内核区分——同名文件在两个内核下的用户数组结构不同）
# ============================================================================

# getProtocolUsersPath COREKIND ID → 用户数组的 jq 路径
# Xray 的 07 用户在 inbounds[1]（[0] 是 dokodemo 分发器）；Xray 内核下 6/9 是
# sing-box sidecar 文件，走 .users。改任何 cell 前先对照真实模板与读取端。
getProtocolUsersPath() {
    local core="$1" protocolId="$2"

    if [[ "${core}" == "1" ]]; then
        case "${protocolId}" in
            7)                       echo ".inbounds[1].settings.clients" ;;
            6 | 9)                   echo ".inbounds[0].users" ;;
            0 | 1 | 2 | 3 | 4 | 5 | 8 | 11 | 12) echo ".inbounds[0].settings.clients" ;;
            *) return 1 ;;
        esac
    elif [[ "${core}" == "2" ]]; then
        case "${protocolId}" in
            0 | 1 | 3 | 4 | 6 | 7 | 8 | 9 | 10 | 11 | 13 | 14 | 20) echo ".inbounds[0].users" ;;
            *) return 1 ;;
        esac
    else
        return 1
    fi
}

# getProtocolIdField COREKIND ID → 承载身份凭据的字段名（id/uuid/password/username）
# 注意 ss2022(14) 的 password 是派生 uPSK 不是原始 UUID，不能当身份源逆推。
getProtocolIdField() {
    local core="$1" protocolId="$2"

    if [[ "${core}" == "1" ]]; then
        case "${protocolId}" in
            0 | 1 | 3 | 5 | 7 | 8 | 12) echo "id" ;;
            2 | 4 | 6)                  echo "password" ;;
            9)                          echo "uuid" ;;
            *) return 1 ;;
        esac
    elif [[ "${core}" == "2" ]]; then
        case "${protocolId}" in
            0 | 1 | 3 | 7 | 8 | 9 | 11) echo "uuid" ;;
            4 | 6 | 10 | 13 | 14)       echo "password" ;;
            20)                         echo "username" ;;
            *) return 1 ;;
        esac
    else
        return 1
    fi
}

# getProtocolNameField COREKIND ID → 承载显示名的字段名（email/name/username）
# sing-box 的 naive(10) 用 username；socks(20) 无显示名字段，返回 1。
getProtocolNameField() {
    local core="$1" protocolId="$2"

    if [[ "${core}" == "1" ]]; then
        case "${protocolId}" in
            6 | 9)                                   echo "name" ;;
            0 | 1 | 2 | 3 | 4 | 5 | 7 | 8 | 11 | 12) echo "email" ;;
            *) return 1 ;;
        esac
    elif [[ "${core}" == "2" ]]; then
        case "${protocolId}" in
            10)                                          echo "username" ;;
            0 | 1 | 3 | 4 | 6 | 7 | 8 | 9 | 11 | 13 | 14) echo "name" ;;
            *) return 1 ;;
        esac
    else
        return 1
    fi
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

# getProtocolConfigPath ID [CONFIG_DIR=${configPath}] → 配置文件完整路径
getProtocolConfigPath() {
    local protocolId="$1"
    local cfgPath="${2:-${configPath}}"
    local fileName

    fileName=$(getProtocolConfigFileName "${protocolId}")
    [[ -z "${fileName}" ]] && return 1

    echo "${cfgPath}${fileName}"
}
