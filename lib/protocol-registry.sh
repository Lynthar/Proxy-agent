#!/usr/bin/env bash
# ============================================================================
# protocol-registry.sh - 协议注册表管理
#
# 集中管理协议ID、配置文件映射、协议检测等功能
# 减少重复代码，提供统一的协议操作接口
# ============================================================================

# 防止重复加载
[[ -n "${_PROTOCOL_REGISTRY_LOADED}" ]] && return 0
readonly _PROTOCOL_REGISTRY_LOADED=1

# ============================================================================
# 注意: 协议ID常量定义在 constants.sh 中，本模块依赖其先加载
# ============================================================================

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
        2)  echo "04_trojan_gRPC_inbounds.json" ;;
        3)  echo "05_VMess_WS_inbounds.json" ;;
        4)  echo "04_trojan_TCP_inbounds.json" ;;
        5)  echo "06_VLESS_gRPC_inbounds.json" ;;
        6)  echo "06_hysteria2_inbounds.json" ;;
        7)  echo "07_VLESS_vision_reality_inbounds.json" ;;
        8)  echo "08_VLESS_vision_gRPC_inbounds.json" ;;
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

# 获取协议短名称（用于订阅链接）
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

# ============================================================================
# 协议属性查询
# ============================================================================

# 检查协议是否需要TLS证书
# 参数: $1 - 协议ID
# 返回: 0=需要, 1=不需要
protocolRequiresTLS() {
    local protocolId="$1"

    case "${protocolId}" in
        0|1|2|3|4|5|10|11|13)
            return 0  # 需要TLS
            ;;
        6|7|8|9|12|14|20)
            return 1  # 不需要TLS（Reality/UDP/自签名）
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查协议是否使用Reality
# 参数: $1 - 协议ID
# 返回: 0=是, 1=否
protocolUsesReality() {
    local protocolId="$1"

    case "${protocolId}" in
        7|8|12)
            return 0  # Reality协议
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查协议是否使用UDP
# 参数: $1 - 协议ID
# 返回: 0=是, 1=否
protocolUsesUDP() {
    local protocolId="$1"

    case "${protocolId}" in
        6|9)
            return 0  # Hysteria2, TUIC使用UDP
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查协议是否支持CDN
# 参数: $1 - 协议ID
# 返回: 0=支持, 1=不支持
protocolSupportsCDN() {
    local protocolId="$1"

    case "${protocolId}" in
        1|3|5|11|12)
            return 0  # WS/gRPC/HTTPUpgrade/XHTTP支持CDN
            ;;
        *)
            return 1
            ;;
    esac
}

# 获取协议传输类型
# 参数: $1 - 协议ID
# 输出: tcp/ws/grpc/http/quic
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
# 协议检测函数
# ============================================================================

# 检查协议是否已安装
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选，默认使用全局configPath)
# 返回: 0=已安装, 1=未安装
isProtocolInstalled() {
    local protocolId="$1"
    local cfgPath="${2:-${configPath}}"

    # 方法1: 检查全局变量（如果已设置）
    if [[ -n "${currentInstallProtocolType}" ]]; then
        echo "${currentInstallProtocolType}" | grep -q ",${protocolId}," && return 0
    fi

    # 方法2: 检查配置文件是否存在
    local configFile
    configFile=$(getProtocolConfigFileName "${protocolId}")
    [[ -n "${configFile}" && -f "${cfgPath}${configFile}" ]] && return 0

    return 1
}

# 检查多个协议是否已安装（任意一个）
# 参数: 协议ID列表
# 返回: 0=至少一个已安装, 1=全部未安装
isAnyProtocolInstalled() {
    local id
    for id in "$@"; do
        isProtocolInstalled "${id}" && return 0
    done
    return 1
}

# 检查多个协议是否全部已安装
# 参数: 协议ID列表
# 返回: 0=全部已安装, 1=有未安装的
areAllProtocolsInstalled() {
    local id
    for id in "$@"; do
        isProtocolInstalled "${id}" || return 1
    done
    return 0
}

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

# 获取已安装协议列表（数组形式）
# 参数: $1 - 配置目录路径 (可选)
# 输出: 每行一个协议ID
getInstalledProtocolList() {
    local cfgPath="${1:-${configPath}}"
    local protocols

    protocols=$(scanInstalledProtocols "${cfgPath}")
    echo "${protocols}" | tr ',' '\n' | grep -v '^$' | sort -n
}

# 统计已安装协议数量
# 参数: $1 - 配置目录路径 (可选)
# 输出: 协议数量
countInstalledProtocols() {
    local cfgPath="${1:-${configPath}}"
    getInstalledProtocolList "${cfgPath}" | wc -l | tr -d ' '
}

# ============================================================================
# 协议配置路径获取
# ============================================================================

# 获取协议配置文件完整路径
# 参数: $1 - 协议ID
#       $2 - 配置目录路径 (可选)
# 输出: 完整文件路径
getProtocolConfigPath() {
    local protocolId="$1"
    local cfgPath="${2:-${configPath}}"
    local fileName

    fileName=$(getProtocolConfigFileName "${protocolId}")
    [[ -z "${fileName}" ]] && return 1

    echo "${cfgPath}${fileName}"
}

# 获取协议客户端配置路径（jq路径）
# 参数: $1 - 协议ID
#       $2 - 核心类型 (1=xray, 2=sing-box)
# 输出: jq路径表达式
getProtocolClientsPath() {
    local protocolId="$1"
    local coreType="${2:-1}"

    if [[ "${coreType}" == "1" ]]; then
        # Xray格式
        echo ".inbounds[0].settings.clients"
    else
        # sing-box格式
        echo ".inbounds[0].users"
    fi
}

# ============================================================================
# 协议分组
# ============================================================================

# 获取所有TLS协议
getAllTLSProtocols() {
    echo "0 1 2 3 4 5 10 11 13"
}

# 获取所有Reality协议
getAllRealityProtocols() {
    echo "7 8 12"
}

# 获取所有UDP协议
getAllUDPProtocols() {
    echo "6 9"
}

# 获取所有CDN支持协议
getAllCDNProtocols() {
    echo "1 3 5 11 12"
}

# 获取Xray支持的协议
getXrayProtocols() {
    echo "0 1 2 3 4 5 7 8 12"
}

# 获取sing-box支持的协议
getSingBoxProtocols() {
    echo "0 1 3 6 7 9 10 11 13 14"
}

# ============================================================================
# 协议选择辅助
# ============================================================================

# 解析用户选择的协议字符串
# 参数: $1 - 用户输入 (如 "0,1,3" 或 "7")
# 输出: 标准化的协议字符串 (如 ",0,1,3,")
parseProtocolSelection() {
    local input="$1"
    local result

    # 移除空格
    input=$(echo "${input}" | tr -d ' ')

    # 确保有前后逗号
    if [[ "${input:0:1}" != "," ]]; then
        input=",${input}"
    fi
    if [[ "${input: -1}" != "," ]]; then
        input="${input},"
    fi

    echo "${input}"
}

# 检查协议选择是否包含指定协议
# 参数: $1 - 协议选择字符串 (如 ",0,1,3,")
#       $2 - 要检查的协议ID
# 返回: 0=包含, 1=不包含
isProtocolSelected() {
    local selection="$1"
    local protocolId="$2"

    echo "${selection}" | grep -q ",${protocolId},"
}

# 向协议选择添加协议
# 参数: $1 - 当前选择字符串
#       $2 - 要添加的协议ID
# 输出: 更新后的选择字符串
addProtocolToSelection() {
    local selection="$1"
    local protocolId="$2"

    if ! isProtocolSelected "${selection}" "${protocolId}"; then
        selection="${selection}${protocolId},"
    fi

    echo "${selection}"
}

# 从协议选择移除协议
# 参数: $1 - 当前选择字符串
#       $2 - 要移除的协议ID
# 输出: 更新后的选择字符串
removeProtocolFromSelection() {
    local selection="$1"
    local protocolId="$2"

    echo "${selection}" | sed "s/,${protocolId},/,/g"
}

# ============================================================================
# 显示辅助函数
# ============================================================================

# 显示已安装协议状态
# 参数: $1 - 配置目录路径 (可选)
displayInstalledProtocols() {
    local cfgPath="${1:-${configPath}}"
    local protocols
    local count=0
    local id displayName

    protocols=$(getInstalledProtocolList "${cfgPath}")

    if [[ -z "${protocols}" ]]; then
        echo "未安装任何协议"
        return 1
    fi

    echo -n "已安装协议: "
    while IFS= read -r id; do
        [[ -z "${id}" ]] && continue
        displayName=$(getProtocolDisplayName "${id}")
        echo -n "${displayName} "
        ((count++))
    done <<< "${protocols}"
    echo ""
    echo "共 ${count} 个协议"
}

# 获取协议安装菜单项
# 参数: $1 - 协议ID
# 输出: 菜单显示文本
getProtocolMenuItem() {
    local protocolId="$1"
    local displayName
    local recommend=""

    displayName=$(getProtocolDisplayName "${protocolId}")

    # 添加推荐标记
    case "${protocolId}" in
        0|7)
            recommend="[推荐]"
            ;;
        1|3|5)
            recommend="[仅CDN推荐]"
            ;;
        4)
            recommend="[不推荐]"
            ;;
        12)
            recommend="[CDN可用]"
            ;;
    esac

    echo "${protocolId}.${displayName}${recommend}"
}
