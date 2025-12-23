#!/usr/bin/env bash
# ============================================================================
# constants.sh - Proxy-agent 常量定义
# ============================================================================
# 本文件定义所有硬编码常量，包括协议ID、文件路径、默认配置等
# 使用 readonly 声明确保常量不被意外修改
# ============================================================================

# 防止重复加载
[[ -n "${_CONSTANTS_LOADED}" ]] && return 0
readonly _CONSTANTS_LOADED=1

# ============================================================================
# 协议ID定义
# 这些ID用于 currentInstallProtocolType 变量中的协议标识
# 格式: ",ID," 表示该协议已安装 (例如 ",0,1,3," 表示安装了协议0,1,3)
# ============================================================================

readonly PROTOCOL_VLESS_TCP_VISION=0      # VLESS+TCP+TLS+Vision
readonly PROTOCOL_VLESS_WS=1              # VLESS+WebSocket+TLS
readonly PROTOCOL_TROJAN_GRPC=2           # Trojan+gRPC+TLS (已废弃，推荐XHTTP)
readonly PROTOCOL_VMESS_WS=3              # VMess+WebSocket+TLS
readonly PROTOCOL_TROJAN_TCP=4            # Trojan+TCP+TLS
readonly PROTOCOL_VLESS_GRPC=5            # VLESS+gRPC+TLS (已废弃，推荐XHTTP)
readonly PROTOCOL_HYSTERIA2=6             # Hysteria2
readonly PROTOCOL_VLESS_REALITY_VISION=7  # VLESS+Reality+Vision
readonly PROTOCOL_VLESS_REALITY_GRPC=8    # VLESS+Reality+gRPC (已废弃，推荐XHTTP)
readonly PROTOCOL_TUIC=9                  # TUIC
readonly PROTOCOL_NAIVE=10                # NaiveProxy
readonly PROTOCOL_VMESS_HTTPUPGRADE=11    # VMess+HTTPUpgrade+TLS
readonly PROTOCOL_XHTTP=12                # VLESS+Reality+XHTTP
readonly PROTOCOL_ANYTLS=13               # AnyTLS
readonly PROTOCOL_SS2022=14               # Shadowsocks 2022
readonly PROTOCOL_SOCKS5=20               # SOCKS5 (内部使用)

# ============================================================================
# 配置目录路径
# ============================================================================

readonly PROXY_AGENT_DIR="/etc/Proxy-agent"
readonly V2RAY_AGENT_DIR="${PROXY_AGENT_DIR}"  # 向后兼容别名
readonly XRAY_CONFIG_DIR="${V2RAY_AGENT_DIR}/xray/conf"
readonly SINGBOX_CONFIG_DIR="${V2RAY_AGENT_DIR}/sing-box/conf/config"
readonly TLS_CERT_DIR="${V2RAY_AGENT_DIR}/tls"
readonly SUBSCRIBE_DIR="${V2RAY_AGENT_DIR}/subscribe"
readonly SUBSCRIBE_LOCAL_DIR="${V2RAY_AGENT_DIR}/subscribe_local"

# ============================================================================
# 配置文件名映射
# 文件名格式: XX_协议名_inbounds.json
# ============================================================================

declare -A PROTOCOL_CONFIG_FILES
PROTOCOL_CONFIG_FILES=(
    [${PROTOCOL_VLESS_TCP_VISION}]="02_VLESS_TCP_inbounds"
    [${PROTOCOL_VLESS_WS}]="03_VLESS_WS_inbounds"
    [${PROTOCOL_TROJAN_GRPC}]="02_trojan_gRPC_inbounds"
    [${PROTOCOL_VMESS_WS}]="05_VMess_WS_inbounds"
    [${PROTOCOL_TROJAN_TCP}]="04_trojan_TCP_inbounds"
    [${PROTOCOL_VLESS_GRPC}]="06_VLESS_gRPC_inbounds"
    [${PROTOCOL_HYSTERIA2}]="06_hysteria2_inbounds"
    [${PROTOCOL_VLESS_REALITY_VISION}]="07_VLESS_vision_reality_inbounds"
    [${PROTOCOL_VLESS_REALITY_GRPC}]="08_VLESS_vision_gRPC_inbounds"
    [${PROTOCOL_TUIC}]="09_tuic_inbounds"
    [${PROTOCOL_NAIVE}]="10_naive_inbounds"
    [${PROTOCOL_VMESS_HTTPUPGRADE}]="11_VMess_HTTPUpgrade_inbounds"
    [${PROTOCOL_XHTTP}]="12_VLESS_XHTTP_inbounds"
    [${PROTOCOL_ANYTLS}]="13_anytls_inbounds"
    [${PROTOCOL_SS2022}]="14_ss2022_inbounds"
    [${PROTOCOL_SOCKS5}]="20_socks5_inbounds"
)

# ============================================================================
# 协议显示名称
# ============================================================================

declare -A PROTOCOL_DISPLAY_NAMES
PROTOCOL_DISPLAY_NAMES=(
    [${PROTOCOL_VLESS_TCP_VISION}]="VLESS+TCP/TLS_Vision"
    [${PROTOCOL_VLESS_WS}]="VLESS+WS+TLS"
    [${PROTOCOL_TROJAN_GRPC}]="Trojan+gRPC+TLS"
    [${PROTOCOL_VMESS_WS}]="VMess+WS+TLS"
    [${PROTOCOL_TROJAN_TCP}]="Trojan+TCP+TLS"
    [${PROTOCOL_VLESS_GRPC}]="VLESS+gRPC+TLS"
    [${PROTOCOL_HYSTERIA2}]="Hysteria2"
    [${PROTOCOL_VLESS_REALITY_VISION}]="VLESS+Reality+Vision"
    [${PROTOCOL_VLESS_REALITY_GRPC}]="VLESS+Reality+gRPC"
    [${PROTOCOL_TUIC}]="TUIC"
    [${PROTOCOL_NAIVE}]="Naive"
    [${PROTOCOL_VMESS_HTTPUPGRADE}]="VMess+HTTPUpgrade+TLS"
    [${PROTOCOL_XHTTP}]="VLESS+Reality+XHTTP"
    [${PROTOCOL_ANYTLS}]="AnyTLS"
    [${PROTOCOL_SS2022}]="Shadowsocks 2022"
)

# ============================================================================
# 是否需要TLS证书
# ============================================================================

declare -A PROTOCOL_REQUIRES_TLS
PROTOCOL_REQUIRES_TLS=(
    [${PROTOCOL_VLESS_TCP_VISION}]=true
    [${PROTOCOL_VLESS_WS}]=true
    [${PROTOCOL_TROJAN_GRPC}]=true
    [${PROTOCOL_VMESS_WS}]=true
    [${PROTOCOL_TROJAN_TCP}]=true
    [${PROTOCOL_VLESS_GRPC}]=true
    [${PROTOCOL_HYSTERIA2}]=true
    [${PROTOCOL_VLESS_REALITY_VISION}]=false    # Reality 不需要传统TLS
    [${PROTOCOL_VLESS_REALITY_GRPC}]=false
    [${PROTOCOL_TUIC}]=true
    [${PROTOCOL_NAIVE}]=true
    [${PROTOCOL_VMESS_HTTPUPGRADE}]=true
    [${PROTOCOL_XHTTP}]=false                    # Reality 不需要传统TLS
    [${PROTOCOL_ANYTLS}]=true
    [${PROTOCOL_SS2022}]=false                   # SS2022 使用自己的加密
)

# ============================================================================
# 默认端口
# ============================================================================

readonly DEFAULT_HTTPS_PORT=443
readonly DEFAULT_HTTP_PORT=80
readonly DEFAULT_RANDOM_PORT_MIN=10000
readonly DEFAULT_RANDOM_PORT_MAX=30000

# ============================================================================
# Hysteria2 默认配置
# ============================================================================

readonly DEFAULT_HYSTERIA2_DOWNLOAD_SPEED=100   # Mbps
readonly DEFAULT_HYSTERIA2_UPLOAD_SPEED=50      # Mbps

# ============================================================================
# TUIC 默认配置
# ============================================================================

readonly DEFAULT_TUIC_ALGORITHM="bbr"

# ============================================================================
# TLS 默认配置
# ============================================================================

readonly DEFAULT_TLS_RENEWAL_DAYS=90
readonly DEFAULT_ALPN_H2="h2"
readonly DEFAULT_ALPN_HTTP11="http/1.1"
readonly DEFAULT_ALPN_H3="h3"

# ============================================================================
# Nginx 配置路径 (根据系统不同)
# ============================================================================

readonly NGINX_CONFIG_PATH_DEFAULT="/etc/nginx/conf.d/"
readonly NGINX_CONFIG_PATH_ALPINE="/etc/nginx/http.d/"
readonly NGINX_STATIC_PATH="/usr/share/nginx/html/"

# ============================================================================
# 服务文件路径
# ============================================================================

readonly XRAY_SERVICE_FILE="/etc/systemd/system/xray.service"
readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"
readonly XRAY_ALPINE_INIT="/etc/init.d/xray"
readonly SINGBOX_ALPINE_INIT="/etc/init.d/sing-box"

# ============================================================================
# 二进制文件路径
# ============================================================================

readonly XRAY_BINARY="${V2RAY_AGENT_DIR}/xray/xray"
readonly SINGBOX_BINARY="${V2RAY_AGENT_DIR}/sing-box/sing-box"

# ============================================================================
# 日志文件路径
# ============================================================================

readonly XRAY_ACCESS_LOG="${V2RAY_AGENT_DIR}/xray/access.log"
readonly XRAY_ERROR_LOG="${V2RAY_AGENT_DIR}/xray/error.log"

# ============================================================================
# 脚本版本
# SCRIPT_VERSION 由 install.sh 从 VERSION 文件动态加载
# 这里只提供默认值和其他常量
# ============================================================================

: "${SCRIPT_VERSION:=(initial)}"  # 默认版本标识，如果未从VERSION文件加载
readonly SCRIPT_AUTHOR="Lynthar"
readonly SCRIPT_REPO="https://github.com/Lynthar/Proxy-agent"

# ============================================================================
# 注意: 协议辅助函数已移至 protocol-registry.sh
# 包括: isProtocolInstalled, getProtocolConfigPath, getProtocolDisplayName,
#       protocolRequiresTLS 等
# ============================================================================
