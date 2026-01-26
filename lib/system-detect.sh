#!/usr/bin/env bash
# ============================================================================
# system-detect.sh - 系统检测模块
# ============================================================================
# 本模块负责检测操作系统类型、CPU架构等系统信息
# 注意：这些函数会写入全局变量，供主脚本使用
# ============================================================================

# 防止重复加载
[[ -n "${_SYSTEM_DETECT_LOADED}" ]] && return 0
readonly _SYSTEM_DETECT_LOADED=1

# ============================================================================
# 检查 SELinux 状态 (CentOS)
# 如果 SELinux 处于 enforcing 模式，需要调整策略
# ============================================================================

checkCentosSELinux() {
    if [[ -f "/etc/selinux/config" ]]; then
        local selinuxStatus
        selinuxStatus=$(sestatus 2>/dev/null | grep "Current mode" | awk '{print $3}')
        if [[ "${selinuxStatus}" == "enforcing" ]]; then
            echoContent yellow " ---> 检测到 SELinux 为 enforcing 模式"
            echoContent yellow " ---> 建议设置为 permissive 模式以避免潜在问题"
        fi
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
        echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
        echoContent yellow "$(cat /etc/issue 2>/dev/null)"
        echoContent yellow "$(cat /proc/version 2>/dev/null)"
        exit 0
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
                echoContent red "  不支持此CPU架构: $(uname -m)"
                exit 1
                ;;
            esac
        fi
    else
        echoContent yellow "  无法识别CPU架构，默认使用 amd64/x86_64"
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
        echoContent yellow "检测到非 Root 用户，部分操作可能需要 sudo 权限"
        return 1
    fi
    return 0
}

# ============================================================================
# 检查 wget 是否支持进度显示
# 设置全局变量:
#   - wgetShowProgressStatus: "--show-progress" 或空
# ============================================================================

checkWgetShowProgress() {
    if wget --help 2>&1 | grep -q "show-progress"; then
        wgetShowProgressStatus="--show-progress"
    else
        wgetShowProgressStatus=""
    fi
}

# ============================================================================
# 获取公网IP地址
# 设置全局变量:
#   - publicIP: 公网IP地址
# ============================================================================

getPublicIP() {
    local ipv4
    local ipv6

    # 尝试多个服务获取IPv4
    ipv4=$(curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || \
           curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
           curl -4 -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null)

    # 尝试获取IPv6
    ipv6=$(curl -6 -s --connect-timeout 5 ip.sb 2>/dev/null)

    if [[ -n "${ipv4}" ]]; then
        publicIP="${ipv4}"
    elif [[ -n "${ipv6}" ]]; then
        publicIP="${ipv6}"
    else
        echoContent red " ---> 无法获取公网IP地址"
        return 1
    fi
}

# ============================================================================
# 检测是否在容器中运行
# 返回: 0 如果在容器中, 1 如果不在
# ============================================================================

isRunningInContainer() {
    if [[ -f "/.dockerenv" ]]; then
        return 0
    fi
    if grep -q "docker\|lxc\|kubepods" /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    return 1
}

# ============================================================================
# 检测是否为虚拟化环境
# 返回虚拟化类型或 "none"
# ============================================================================

detectVirtualization() {
    if command -v systemd-detect-virt &>/dev/null; then
        systemd-detect-virt
    elif [[ -f "/sys/hypervisor/type" ]]; then
        cat /sys/hypervisor/type
    else
        echo "unknown"
    fi
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
