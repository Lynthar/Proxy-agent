#!/usr/bin/env bash
# ============================================================================
# system-detect.sh - 系统检测模块
# ============================================================================
# 本模块负责检测操作系统类型、CPU架构等系统信息
# 注意：这些函数会写入全局变量，供主脚本使用
# ============================================================================

# 防止重复加载
[[ -n "${_SYSTEM_DETECT_LOADED:-}" ]] && return 0
readonly _SYSTEM_DETECT_LOADED=1

# ============================================================================
# 检查 SELinux 状态 (CentOS)
# enforcing 时直接 exit 1（与历史 install.sh 行为一致：脚本不允许在
# enforcing 模式下继续——nginx / xray socket binding 会被 SELinux 阻断）
# ============================================================================

checkCentosSELinux() {
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
        echoContent yellow "# $(t NOTICE)"
        echoContent yellow "$(t SYS_SELINUX_NOTICE)"
        echoContent yellow "https://github.com/Lynthar/Proxy-agent/blob/master/docs/selinux.md"
        exit 1
    fi
}

# ============================================================================
# 检测操作系统类型
# 设置全局变量:
#   - release: 系统类型 (centos/debian/ubuntu/alpine)
#   - installType: 包安装命令
#   - removeType: 包卸载命令
#   - upgrade: 系统更新命令
#   - centosVersion: CentOS版本 (仅CentOS)
#   - nginxConfigPath: Nginx配置路径 (Alpine不同)
# ============================================================================

checkSystem() {
    # CentOS / RHEL
    if [[ -n $(find /etc -name "redhat-release" 2>/dev/null) ]] || \
       grep </proc/version -q -i "centos" 2>/dev/null; then
        mkdir -p /etc/yum.repos.d

        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release 2>/dev/null | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8" 2>/dev/null; then
                centosVersion=8
            fi
        fi

        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum update -y --skip-broken"
        checkCentosSELinux

    # Alpine Linux
    elif { [[ -f "/etc/issue" ]] && grep -qi "Alpine" /etc/issue; } || \
         { [[ -f "/proc/version" ]] && grep -qi "Alpine" /proc/version; }; then
        release="alpine"
        installType='apk add'
        upgrade="apk update"
        removeType='apk del'
        nginxConfigPath=/etc/nginx/http.d/

    # Debian
    elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || \
         { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; } || \
         { [[ -f "/etc/os-release" ]] && grep -qi "ID=debian" /etc/os-release; }; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'

    # Ubuntu
    elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || \
         { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'

        # Ubuntu 16.x 不支持
        if grep </etc/issue -q -i "16." 2>/dev/null; then
            release=
        fi
    fi

    # 检查是否支持
    if [[ -z "${release}" ]]; then
        echoContent red "\n$(t SYS_NOT_SUPPORTED)\n"
        echoContent yellow "$(cat /etc/issue 2>/dev/null)"
        echoContent yellow "$(cat /proc/version 2>/dev/null)"
        exit 1
    fi
}

# ============================================================================
# 检测 CPU 架构
# 设置全局变量:
#   - cpuVendor: CPU厂商/架构类型
#   - xrayCoreCPUVendor: Xray二进制名称后缀
#   - singBoxCoreCPUVendor: sing-box二进制名称后缀
#   - warpRegCoreCPUVendor: WARP二进制名称后缀
# ============================================================================

checkCPUVendor() {
    if command -v uname &>/dev/null; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
            'amd64' | 'x86_64')
                cpuVendor="amd64"
                xrayCoreCPUVendor="Xray-linux-64"
                warpRegCoreCPUVendor="main-linux-amd64"
                singBoxCoreCPUVendor="-linux-amd64"
                ;;
            'armv8' | 'aarch64')
                cpuVendor="arm64"
                xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                warpRegCoreCPUVendor="main-linux-arm64"
                singBoxCoreCPUVendor="-linux-arm64"
                ;;
            'armv7l')
                cpuVendor="armv7"
                xrayCoreCPUVendor="Xray-linux-arm32-v7a"
                warpRegCoreCPUVendor="main-linux-arm"
                singBoxCoreCPUVendor="-linux-armv7"
                ;;
            *)
                echoContent red "  $(t SYS_CPU_NOT_SUPPORTED): $(uname -m)"
                exit 1
                ;;
            esac
        fi
    else
        echoContent yellow "  $(t SYS_CPU_DEFAULT_AMD64)"
        cpuVendor="amd64"
        xrayCoreCPUVendor="Xray-linux-64"
        singBoxCoreCPUVendor="-linux-amd64"
    fi
}

# ============================================================================
# 检查 Root 权限
# ============================================================================

checkRoot() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echoContent red "$(t SYS_ROOT_REQUIRED)"
        exit 1
    fi
}

# ============================================================================
# 检查 wget 是否支持进度显示
# 设置全局变量:
#   - wgetShowProgressStatus: "--show-progress" 或空
# ============================================================================

checkWgetShowProgress() {
    # Alpine 的 BusyBox wget 不支持 --show-progress，跳过探测
    if [[ "${release:-}" == "alpine" ]]; then
        wgetShowProgressStatus=""
        return
    fi
    if wget --help 2>&1 | grep -q "show-progress"; then
        wgetShowProgressStatus="--show-progress"
    else
        wgetShowProgressStatus=""
    fi
}

# ============================================================================
# 获取公网IP地址
# 调用约定（与 install.sh 历史调用方式兼容）：
#   getPublicIP        → echo IPv4，失败回退 IPv6
#   getPublicIP 4      → 强制 IPv4
#   getPublicIP 6      → 强制 IPv6
# Reality 短路：当 currentHost 与 Reality 的 serverName 相同（且未显式指定
# type）时，直接 echo currentHost，省去一次外网探测。install.sh 在 Reality
# 场景下大量调用 $(getPublicIP)，这条短路保留性能。
# ============================================================================

getPublicIP() {
    local type="${1:-4}"

    if [[ -z "${1:-}" && -n "${currentHost:-}" ]] && [[ \
        "${singBoxVLESSRealityVisionServerName:-}" == "${currentHost}" || \
        "${singBoxVLESSRealityGRPCServerName:-}" == "${currentHost}" || \
        "${xrayVLESSRealityServerName:-}" == "${currentHost}" ]]; then
        echo "${currentHost}"
        return 0
    fi

    # cf 自家 trace 优先（更稳定 + 单次响应里可同时拿到 ip 字段）；
    # 失败再走 ip.sb / ifconfig.me / ipinfo.io。每个源 5s 超时，
    # 总最坏耗时 ≈ 4 * 5s = 20s。
    local ip=
    ip="$(curl -s "-${type}" --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
          | sed -n 's/^ip=//p')"
    if [[ -z "${ip}" ]]; then
        ip="$(curl -s "-${type}" --connect-timeout 5 ip.sb 2>/dev/null)"
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(curl -s "-${type}" --connect-timeout 5 ifconfig.me 2>/dev/null)"
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(curl -s "-${type}" --connect-timeout 5 ipinfo.io/ip 2>/dev/null)"
    fi

    # IPv4 全部失败 + 没显式指定 type 时，再尝试 IPv6（与 inline 历史行为一致）
    if [[ -z "${ip}" && -z "${1:-}" ]]; then
        ip="$(curl -s -6 --connect-timeout 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
              | sed -n 's/^ip=//p')"
    fi

    echo "${ip}"
    [[ -n "${ip}" ]]
}

# ============================================================================
# 获取系统内存大小 (MB)
# ============================================================================

getSystemMemoryMB() {
    local memKB
    memKB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -n "${memKB}" ]]; then
        echo $((memKB / 1024))
    else
        echo "0"
    fi
}

# ============================================================================
# 获取系统CPU核心数
# ============================================================================

getCPUCores() {
    nproc 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo "1"
}

# ============================================================================
# 检查命令是否存在
# 用法: if commandExists "curl"; then ...
# ============================================================================

commandExists() {
    command -v "$1" &>/dev/null
}

# ============================================================================
# 获取操作系统详细信息
# 返回格式: "OS Version (Kernel)"
# ============================================================================

getOSInfo() {
    local osName=""
    local osVersion=""
    local kernelVersion

    if [[ -f "/etc/os-release" ]]; then
        osName=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
        osVersion=$(grep "^VERSION=" /etc/os-release | cut -d'"' -f2)
    elif [[ -f "/etc/redhat-release" ]]; then
        osName=$(cat /etc/redhat-release)
    elif [[ -f "/etc/issue" ]]; then
        osName=$(head -1 /etc/issue | sed 's/\\[a-z]//g')
    fi

    kernelVersion=$(uname -r)

    echo "${osName:-Unknown} ${osVersion} (Kernel: ${kernelVersion})"
}
