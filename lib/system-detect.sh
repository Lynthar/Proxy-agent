#!/usr/bin/env bash
# ============================================================================
# system-detect.sh - OS / CPU / 网络探测。这些函数不返回值，只写全局变量。
# ============================================================================

# 防止重复加载
[[ -n "${_SYSTEM_DETECT_LOADED:-}" ]] && return 0
readonly _SYSTEM_DETECT_LOADED=1

# ============================================================================
# checkCentosSELinux —— enforcing 时 exit 1（socket binding 会被 SELinux 阻断）
# ============================================================================

checkCentosSELinux() {
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
        # PROXY_AGENT_SELINUX_NONFATAL=1（doctor 入口设置）时只放行不退出，
        # 否则 doctor 永远到不了自己的 SELinux 诊断行
        if [[ -n "${PROXY_AGENT_SELINUX_NONFATAL:-}" ]]; then
            return 0
        fi
        echoContent yellow "# $(t NOTICE)"
        echoContent yellow "$(t SYS_SELINUX_NOTICE)"
        echoContent yellow "https://github.com/Lynthar/Proxy-agent/blob/master/docs/selinux.md"
        exit 1
    fi
}

# ============================================================================
# checkSystem → release / installType / removeType / upgrade / centosVersion / nginxConfigPath
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
# checkCPUVendor → cpuVendor 与 xray/singBox/warpReg 三个 CoreCPUVendor 后缀
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
# checkWgetShowProgress → wgetShowProgressStatus（"--show-progress" 或空）
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

# getPublicIP [4|6] → 公网 IP。无参=IPv4 失败回退 IPv6。
# Reality 短路（currentHost == serverName 且未指定 type）直接回显 currentHost，是性能项别删。

# isPlausiblePublicIP VALUE → 0=形似合法 IPv4/IPv6
# 宽松形态校验：拦 HTML 错误页/代理提示文本混进订阅与配置；严格语义版是 install.sh 的 isValidIP
isPlausiblePublicIP() {
    local v="$1"
    [[ "${v}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && return 0
    # IPv6（含 IPv4-mapped 尾段）：必须含冒号且仅由十六进制/冒号/点组成
    [[ "${v}" == *:* && "${v}" =~ ^[0-9a-fA-F:.]+$ ]] && return 0
    return 1
}

getPublicIP() {
    local type="${1:-4}"

    if [[ -z "${1:-}" && -n "${currentHost:-}" ]] && [[ \
        "${singBoxVLESSRealityVisionServerName:-}" == "${currentHost}" || \
        "${singBoxVLESSRealityGRPCServerName:-}" == "${currentHost}" || \
        "${xrayVLESSRealityServerName:-}" == "${currentHost}" ]]; then
        echo "${currentHost}"
        return 0
    fi

    # 单次运行内公网 IP 不变——按请求形态缓存，避免账号/订阅生成对每个协议都打一轮外网
    local cacheVar="_publicIPCache${1:-Auto}"
    if [[ -n "${!cacheVar:-}" ]]; then
        echo "${!cacheVar}"
        return 0
    fi

    # cf 自家 trace 优先（更稳定 + 单次响应里可同时拿到 ip 字段）；
    # 失败再走 ip.sb / ifconfig.me / ipinfo.io。全部 HTTPS，connect 5s + 总时限 10s。
    # 每个源的响应过 isPlausiblePublicIP，垃圾内容按失败处理落到下一个源
    local ip=
    ip="$(curl -s "-${type}" --connect-timeout 5 --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
          | sed -n 's/^ip=//p')"
    isPlausiblePublicIP "${ip}" || ip=
    if [[ -z "${ip}" ]]; then
        ip="$(curl -s "-${type}" --connect-timeout 5 --max-time 10 https://ip.sb 2>/dev/null)"
        isPlausiblePublicIP "${ip}" || ip=
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(curl -s "-${type}" --connect-timeout 5 --max-time 10 https://ifconfig.me 2>/dev/null)"
        isPlausiblePublicIP "${ip}" || ip=
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(curl -s "-${type}" --connect-timeout 5 --max-time 10 https://ipinfo.io/ip 2>/dev/null)"
        isPlausiblePublicIP "${ip}" || ip=
    fi

    # IPv4 全部失败 + 没显式指定 type 时，再尝试 IPv6（与 inline 历史行为一致）
    if [[ -z "${ip}" && -z "${1:-}" ]]; then
        ip="$(curl -s -6 --connect-timeout 5 --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
              | sed -n 's/^ip=//p')"
        isPlausiblePublicIP "${ip}" || ip=
    fi

    if [[ -n "${ip}" ]]; then
        printf -v "${cacheVar}" '%s' "${ip}"
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

# commandExists CMD → 0=存在。用法: if commandExists "curl"; then ...

commandExists() {
    command -v "$1" &>/dev/null
}

# 获取操作系统详细信息 → "OS Version (Kernel)"

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
