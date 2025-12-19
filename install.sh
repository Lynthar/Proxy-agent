#!/usr/bin/env bash
# 检测区
# -------------------------------------------------------------
# 检查系统
export LANG=en_US.UTF-8

# ============================================================================
# 全局错误处理
# 注意：不使用 set -e 因为脚本中有许多命令允许失败
# 但启用 pipefail 确保管道错误能被检测
# ============================================================================
set -o pipefail

# 错误处理函数
_error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    if [[ ${exit_code} -ne 0 ]]; then
        echo -e "\033[31m[错误] 脚本在第 ${line_number} 行发生错误\033[0m" >&2
        echo -e "\033[31m[错误] 命令: ${command}\033[0m" >&2
        echo -e "\033[31m[错误] 退出码: ${exit_code}\033[0m" >&2
    fi
}

# 捕获 ERR 信号（仅用于调试，不会终止脚本）
# trap '_error_handler ${LINENO} "${BASH_COMMAND}"' ERR

# 清理函数 - 脚本退出时清理临时文件
_cleanup() {
    # 清理可能遗留的临时文件
    rm -f /tmp/Proxy-agent-*.tmp 2>/dev/null
}
trap '_cleanup' EXIT

# ============================================================================
# 模块加载
# 如果 lib 目录存在，加载模块化组件
# 这允许逐步重构而保持向后兼容
# ============================================================================

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="${_SCRIPT_DIR}/lib"

# 加载模块（如果存在）
if [[ -d "${_LIB_DIR}" ]]; then
    # 加载顺序很重要：
    # Phase 1: i18n (国际化，最先加载)
    # Phase 2: constants -> utils -> system-detect -> service-control
    # Phase 3: json-utils -> protocol-registry -> config-reader
    for _module in i18n constants utils json-utils system-detect service-control protocol-registry config-reader; do
        if [[ -f "${_LIB_DIR}/${_module}.sh" ]]; then
            # shellcheck source=/dev/null
            source "${_LIB_DIR}/${_module}.sh"
        fi
    done
fi

# 清理临时变量
unset _LIB_DIR _module

# ============================================================================
# 版本号管理
# 版本号来源优先级: VERSION文件 > 硬编码默认值
# ============================================================================
_load_version() {
    local versionFile="${_SCRIPT_DIR}/VERSION"
    local installedVersionFile="/etc/Proxy-agent/VERSION"

    # 优先从脚本目录读取
    if [[ -f "${versionFile}" ]]; then
        SCRIPT_VERSION="v$(cat "${versionFile}" 2>/dev/null | tr -d '[:space:]')"
    # 其次从安装目录读取
    elif [[ -f "${installedVersionFile}" ]]; then
        SCRIPT_VERSION="v$(cat "${installedVersionFile}" 2>/dev/null | tr -d '[:space:]')"
    else
        # 默认版本
        SCRIPT_VERSION="v3.6.0"
    fi
    export SCRIPT_VERSION
}
_load_version

# ============================================================================
# GitHub Release 版本检测
# 从 GitHub API 获取最新 Release 版本号
# ============================================================================
GITHUB_REPO="Lynthar/Proxy-agent"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# 获取最新 Release 版本号
# 返回: 版本号 (如 v3.6.0) 或空字符串
getLatestReleaseVersion() {
    local response
    local version

    # 使用 curl 获取 GitHub API 响应
    response=$(curl -s --connect-timeout 5 -m 10 "${GITHUB_API_URL}" 2>/dev/null)

    if [[ -n "${response}" ]]; then
        # 提取 tag_name 字段
        version=$(echo "${response}" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' 2>/dev/null)

        # 如果 grep -P 不可用，尝试其他方法
        if [[ -z "${version}" ]]; then
            version=$(echo "${response}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        fi

        # 确保版本号以 v 开头
        if [[ -n "${version}" && "${version}" != v* ]]; then
            version="v${version}"
        fi

        echo "${version}"
    fi
}

# 比较版本号
# 参数: $1 = 当前版本, $2 = 远程版本
# 返回: 0 = 需要更新, 1 = 已是最新, 2 = 无法比较
compareVersions() {
    local current="$1"
    local remote="$2"

    # 去除 v 前缀
    current="${current#v}"
    remote="${remote#v}"

    if [[ -z "${current}" || -z "${remote}" ]]; then
        return 2
    fi

    if [[ "${current}" == "${remote}" ]]; then
        return 1
    fi

    # 使用 sort -V 比较版本号
    local higher
    higher=$(printf '%s\n%s' "${current}" "${remote}" | sort -V | tail -1)

    if [[ "${higher}" == "${remote}" ]]; then
        return 0  # 需要更新
    else
        return 1  # 已是最新
    fi
}

# 检查更新并显示提示
checkForUpdates() {
    local latestVersion
    latestVersion=$(getLatestReleaseVersion)

    if [[ -n "${latestVersion}" ]]; then
        if compareVersions "${SCRIPT_VERSION}" "${latestVersion}"; then
            export LATEST_VERSION="${latestVersion}"
            return 0  # 有新版本
        fi
    fi
    return 1  # 无新版本或检查失败
}

# ============================================================================
# i18n 后备机制 - 当模块未加载时提供基本翻译支持
# ============================================================================
if ! type t &>/dev/null; then
    # t() 函数未定义，加载内嵌的基本语言消息
    # 基本消息定义（中文）
    MSG_MENU_AUTHOR="作者"
    MSG_MENU_VERSION="当前版本"
    MSG_MENU_GITHUB="Github"
    MSG_MENU_DESC="描述"
    MSG_MENU_TITLE="八合一共存脚本"
    MSG_MENU_INSTALL="安装"
    MSG_MENU_REINSTALL="重新安装"
    MSG_MENU_COMBO_INSTALL="任意组合安装"
    MSG_MENU_CHAIN_PROXY="链式代理管理"
    MSG_MENU_HYSTERIA2="Hysteria2 管理"
    MSG_MENU_REALITY="REALITY 管理"
    MSG_MENU_TUIC="Tuic 管理"
    MSG_MENU_USER="用户管理"
    MSG_MENU_DISGUISE="伪装站管理"
    MSG_MENU_CERT="证书管理"
    MSG_MENU_CDN="CDN 节点管理"
    MSG_MENU_ROUTING="分流工具"
    MSG_MENU_ADD_PORT="添加新端口"
    MSG_MENU_BT="BT 下载管理"
    MSG_MENU_BLACKLIST="域名黑名单"
    MSG_MENU_CORE="Core 管理"
    MSG_MENU_UPDATE_SCRIPT="更新脚本"
    MSG_MENU_BBR="安装 BBR、DD 脚本"
    MSG_MENU_UNINSTALL="卸载脚本"
    MSG_MENU_TOOL_MGMT="工具管理"
    MSG_MENU_VERSION_MGMT="版本管理"
    MSG_MENU_SCRIPT_MGMT="脚本管理"
    MSG_PROMPT_SELECT="请选择"
    MSG_NOTICE="注意事项"
    MSG_SYS_SELINUX_NOTICE="检测到 SELinux 已启用，请手动禁用（在 /etc/selinux/config 设置 SELINUX=disabled 并重启）"
    MSG_SYS_NOT_SUPPORTED="本脚本不支持此系统，请将下方日志反馈给开发者"
    MSG_SYS_CPU_NOT_SUPPORTED="不支持此 CPU 架构"
    MSG_SYS_CPU_DEFAULT_AMD64="无法识别 CPU 架构，默认使用 amd64/x86_64"
    MSG_CORE_CURRENT_RUNNING="核心: %s [运行中]"
    MSG_CORE_CURRENT_STOPPED="核心: %s [未运行]"
    MSG_PROTOCOLS_INSTALLED="已安装协议"
    MSG_PROGRESS_STEP="进度 %s/%s"
    MSG_PROG_INSTALL_TOOLS="安装工具"
    MSG_INSTALL_CHECKING="检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"
    MSG_INSTALL_TOOL="安装 %s"

    # 后备 t() 函数
    t() {
        local key="MSG_$1"
        local text="${!key:-$1}"
        shift
        if [[ $# -gt 0 ]]; then
            # shellcheck disable=SC2059
            printf "${text}" "$@"
        else
            echo "${text}"
        fi
    }
fi

# ============================================================================

# 域名验证函数 - 防止命令注入
# 返回 0 表示有效，返回 1 表示无效
isValidDomain() {
    local domain="$1"
    # 空值无效
    [[ -z "${domain}" ]] && return 1
    # 检查是否包含危险字符（命令注入防护）
    if [[ "${domain}" =~ [\;\|\&\$\`\(\)\{\}\[\]\<\>\!\#\*\?\~\'\"] ]]; then
        return 1
    fi
    # 检查是否包含空格或换行
    if [[ "${domain}" =~ [[:space:]] ]]; then
        return 1
    fi
    # 基本域名格式验证（允许子域名、顶级域名等）
    # 格式: 允许字母、数字、连字符和点，但不能以点或连字符开头/结尾
    if [[ ! "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    # 不允许连续的点
    if [[ "${domain}" =~ \.\. ]]; then
        return 1
    fi
    return 0
}

# URL/重定向地址验证函数 - 防止命令注入
isValidRedirectUrl() {
    local url="$1"
    [[ -z "${url}" ]] && return 1
    # 检查是否包含危险字符
    if [[ "${url}" =~ [\;\|\&\$\`\(\)\{\}\[\]\<\>\!\#\*\~\'] ]]; then
        return 1
    fi
    # 必须以 http:// 或 https:// 开头
    if [[ ! "${url}" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

# SHA256校验和验证函数
# 用法: verifySHA256 <文件路径> <预期的SHA256值>
# 返回: 0=验证成功, 1=验证失败
verifySHA256() {
    local file="$1"
    local expectedHash="$2"

    if [[ ! -f "${file}" ]]; then
        echoContent red " ---> 校验失败: 文件不存在"
        return 1
    fi

    local actualHash
    if command -v sha256sum &>/dev/null; then
        actualHash=$(sha256sum "${file}" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actualHash=$(shasum -a 256 "${file}" | awk '{print $1}')
    else
        echoContent yellow " ---> 警告: 未找到sha256sum工具，跳过校验"
        return 0
    fi

    if [[ "${actualHash,,}" == "${expectedHash,,}" ]]; then
        return 0
    else
        echoContent red " ---> 校验失败: SHA256不匹配"
        echoContent red "     预期: ${expectedHash}"
        echoContent red "     实际: ${actualHash}"
        return 1
    fi
}

# 从Xray .dgst文件中提取SHA256值
# 用法: extractXrayHash <dgst文件路径>
extractXrayHash() {
    local dgstFile="$1"
    if [[ -f "${dgstFile}" ]]; then
        grep "SHA2-256" "${dgstFile}" | awk '{print $2}' | head -1
    fi
}

# 从sing-box校验文件中提取SHA256值
# 用法: extractSingBoxHash <校验文件路径> <目标文件名>
extractSingBoxHash() {
    local checksumFile="$1"
    local targetFile="$2"
    if [[ -f "${checksumFile}" ]]; then
        grep "${targetFile}" "${checksumFile}" | awk '{print $1}' | head -1
    fi
}

# TLS证书与私钥匹配验证函数
# 用法: verifyCertKeyMatch <证书文件路径> <私钥文件路径>
# 返回: 0=匹配成功, 1=匹配失败或文件不存在
verifyCertKeyMatch() {
    local certFile="$1"
    local keyFile="$2"

    # 检查文件是否存在
    if [[ ! -f "${certFile}" ]]; then
        echoContent red " ---> 证书验证失败: 证书文件不存在 ${certFile}"
        return 1
    fi
    if [[ ! -f "${keyFile}" ]]; then
        echoContent red " ---> 证书验证失败: 私钥文件不存在 ${keyFile}"
        return 1
    fi

    # 检查文件是否为空
    if [[ ! -s "${certFile}" ]]; then
        echoContent red " ---> 证书验证失败: 证书文件为空"
        return 1
    fi
    if [[ ! -s "${keyFile}" ]]; then
        echoContent red " ---> 证书验证失败: 私钥文件为空"
        return 1
    fi

    # 提取证书和私钥的公钥哈希进行比对
    local certHash keyHash

    # 检测密钥类型（ECC或RSA）
    if openssl x509 -in "${certFile}" -noout -text 2>/dev/null | grep -q "EC Public Key\|id-ecPublicKey"; then
        # ECC证书
        certHash=$(openssl x509 -in "${certFile}" -pubkey -noout 2>/dev/null | openssl ec -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
        keyHash=$(openssl ec -in "${keyFile}" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
    else
        # RSA证书
        certHash=$(openssl x509 -in "${certFile}" -noout -modulus 2>/dev/null | sha256sum | awk '{print $1}')
        keyHash=$(openssl rsa -in "${keyFile}" -noout -modulus 2>/dev/null | sha256sum | awk '{print $1}')
    fi

    if [[ -z "${certHash}" || -z "${keyHash}" ]]; then
        echoContent yellow " ---> 证书验证警告: 无法提取证书/私钥信息进行匹配验证"
        return 0
    fi

    if [[ "${certHash}" == "${keyHash}" ]]; then
        return 0
    else
        echoContent red " ---> 证书验证失败: 证书与私钥不匹配"
        echoContent red "     证书公钥哈希: ${certHash:0:16}..."
        echoContent red "     私钥公钥哈希: ${keyHash:0:16}..."
        return 1
    fi
}

# 验证证书有效期
# 用法: verifyCertExpiry <证书文件路径>
# 返回: 0=有效, 1=已过期或即将过期(7天内)
verifyCertExpiry() {
    local certFile="$1"

    if [[ ! -f "${certFile}" ]]; then
        return 1
    fi

    local expiryDate expiryTimestamp currentTimestamp daysLeft
    expiryDate=$(openssl x509 -in "${certFile}" -noout -enddate 2>/dev/null | cut -d= -f2)

    if [[ -z "${expiryDate}" ]]; then
        echoContent yellow " ---> 无法读取证书过期时间"
        return 0
    fi

    expiryTimestamp=$(date -d "${expiryDate}" +%s 2>/dev/null)
    currentTimestamp=$(date +%s)

    if [[ -z "${expiryTimestamp}" ]]; then
        return 0
    fi

    ((daysLeft = (expiryTimestamp - currentTimestamp) / 86400))

    if [[ ${daysLeft} -lt 0 ]]; then
        echoContent red " ---> 证书已过期 ${daysLeft#-} 天"
        return 1
    elif [[ ${daysLeft} -lt 7 ]]; then
        echoContent yellow " ---> 警告: 证书将在 ${daysLeft} 天后过期"
        return 0
    fi

    return 0
}

echoContent() {
    case $1 in
    # 红色
    "red")
        # shellcheck disable=SC2154
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 天蓝色
    "skyBlue")
        ${echoType} "\033[1;36m${printN}$2 \033[0m"
        ;;
        # 绿色
    "green")
        ${echoType} "\033[32m${printN}$2 \033[0m"
        ;;
        # 白色
    "white")
        ${echoType} "\033[37m${printN}$2 \033[0m"
        ;;
    "magenta")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 黄色
    "yellow")
        ${echoType} "\033[33m${printN}$2 \033[0m"
        ;;
    esac
}

# 验证IP地址格式
# 参数1: IP地址字符串
# 返回: 0=有效, 1=无效
isValidIP() {
    local ip=$1
    # IPv4 验证
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    # IPv6 验证 (简化版，支持完整格式和压缩格式)
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] || \
       [[ "$ip" =~ ^::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$ ]] || \
       [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){1,6}:$ ]]; then
        return 0
    fi
    return 1
}

# 检查SELinux状态（使用运行时检测）
checkCentosSELinux() {
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" == "Enforcing" ]]; then
        echoContent yellow "# $(t NOTICE)"
        echoContent yellow "$(t SYS_SELINUX_NOTICE)"
        echoContent yellow "https://github.com/Lynthar/Proxy-agent/blob/master/documents/selinux.md"
        exit 1
    fi
}
checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d

        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi

        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum update -y --skip-broken"
        checkCentosSELinux
    elif { [[ -f "/etc/issue" ]] && grep -qi "Alpine" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "Alpine" /proc/version; }; then
        release="alpine"
        installType='apk add'
        upgrade="apk update"
        removeType='apk del'
        nginxConfigPath=/etc/nginx/http.d/
    elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; } || { [[ -f "/etc/os-release" ]] && grep -qi "ID=debian" /etc/issue; }; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'

    elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    fi

    if [[ -z ${release} ]]; then
        echoContent red "\n$(t SYS_NOT_SUPPORTED)\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 1
    fi
}

# 检查CPU提供商
checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
            'amd64' | 'x86_64')
                xrayCoreCPUVendor="Xray-linux-64"
                #                v2rayCoreCPUVendor="v2ray-linux-64"
                warpRegCoreCPUVendor="main-linux-amd64"
                singBoxCoreCPUVendor="-linux-amd64"
                ;;
            'armv8' | 'aarch64')
                cpuVendor="arm"
                xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                #                v2rayCoreCPUVendor="v2ray-linux-arm64-v8a"
                warpRegCoreCPUVendor="main-linux-arm64"
                singBoxCoreCPUVendor="-linux-arm64"
                ;;
            *)
                echo "  $(t SYS_CPU_NOT_SUPPORTED)--->"
                exit 1
                ;;
            esac
        fi
    else
        echoContent red "  $(t SYS_CPU_DEFAULT_AMD64)--->"
        xrayCoreCPUVendor="Xray-linux-64"
        #        v2rayCoreCPUVendor="v2ray-linux-64"
    fi
}

# 初始化全局变量
initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
    #    sudoCMD=""

    # 核心支持的cpu版本
    xrayCoreCPUVendor=""
    warpRegCoreCPUVendor=""
    cpuVendor=""

    # 域名
    domain=
    # 安装总进度
    totalProgress=1

    # 1.xray-core安装
    # 2.v2ray-core 安装
    # 3.v2ray-core[xtls] 安装
    coreInstallType=

    # 核心安装path
    # coreInstallPath=

    # v2ctl Path
    ctlPath=
    # 1.全部安装
    # 2.个性化安装
    # v2rayAgentInstallType=

    # 当前的个性化安装方式 01234
    currentInstallProtocolType=

    # 当前alpn的顺序
    currentAlpn=

    # 前置类型
    frontingType=

    # 选择的个性化安装方式
    selectCustomInstallType=

    # v2ray-core、xray-core配置文件的路径
    configPath=

    # xray-core reality状态
    realityStatus=

    # sing-box配置文件路径
    singBoxConfigPath=

    # sing-box端口

    singBoxVLESSVisionPort=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityGRPCPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=
    singBoxTuicPort=
    singBoxNaivePort=
    singBoxVMessWSPort=
    singBoxVLESSWSPort=
    singBoxVMessHTTPUpgradePort=

    # nginx订阅端口
    subscribePort=

    subscribeType=

    # sing-box reality serverName publicKey
    singBoxVLESSRealityGRPCServerName=
    singBoxVLESSRealityVisionServerName=
    singBoxVLESSRealityPublicKey=

    # xray-core reality serverName publicKey
    xrayVLESSRealityServerName=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPServerName=
    xrayVLESSRealityXHTTPort=
    #    xrayVLESSRealityPublicKey=

    #    interfaceName=
    # 端口跳跃
    portHoppingStart=
    portHoppingEnd=
    portHopping=

    hysteria2PortHoppingStart=
    hysteria2PortHoppingEnd=
    hysteria2PortHopping=

    #    tuicPortHoppingStart=
    #    tuicPortHoppingEnd=
    #    tuicPortHopping=

    # tuic配置文件路径
    #    tuicConfigPath=
    tuicAlgorithm=
    tuicPort=

    # 配置文件的path
    currentPath=

    # 配置文件的host
    currentHost=

    # 安装时选择的core类型
    selectCoreType=

    # 默认core版本
    #    v2rayCoreVersion=

    # 随机路径
    customPath=

    # centos version
    centosVersion=

    # UUID
    currentUUID=

    # clients
    currentClients=

    # previousClients
    #    previousClients=

    localIP=

    # 定时任务执行任务名称 RenewTLS-更新证书 UpdateGeo-更新geo文件
    cronName=$1

    # tls安装失败后尝试的次数
    installTLSCount=

    # BTPanel状态
    #	BTPanelStatus=
    # 宝塔域名
    btDomain=
    # nginx配置文件路径
    nginxConfigPath=/etc/nginx/conf.d/
    nginxStaticPath=/usr/share/nginx/html/

    # 是否为预览版
    prereleaseStatus=false

    # ssl类型
    sslType=
    # SSL CF API Token
    cfAPIToken=

    # ssl邮箱
    sslEmail=

    # 检查天数
    sslRenewalDays=90

    # dns ssl状态
    #    dnsSSLStatus=

    # dns tls domain
    dnsTLSDomain=
    ipType=

    # 该域名是否通过dns安装通配符证书
    #    installDNSACMEStatus=

    # 自定义端口
    customPort=

    # hysteria端口
    hysteriaPort=

    # hysteria协议
    #    hysteriaProtocol=

    # hysteria延迟
    #    hysteriaLag=

    # hysteria下行速度
    hysteria2ClientDownloadSpeed=

    # hysteria上行速度
    hysteria2ClientUploadSpeed=

    # Reality
    realityPrivateKey=
    realityServerName=
    realityDestDomain=

    # 端口状态
    #    isPortOpen=
    # 通配符域名状态
    #    wildcardDomainStatus=
    # 通过nginx检查的端口
    #    nginxIPort=

    # wget show progress
    wgetShowProgressStatus=

    # warp
    reservedWarpReg=
    publicKeyWarpReg=
    addressWarpReg=
    secretKeyWarpReg=

    # 上次安装配置状态
    lastInstallationConfig=

}

stripAnsi() {
    echo -e "$1" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g'
}

validateJsonFile() {

    local jsonPath=$1
    if ! jq -e . "${jsonPath}" >/dev/null 2>&1; then
        echoContent red " ---> ${jsonPath} 解析失败，已移除，请检查上方录入并重试"
        rm -f "${jsonPath}"
        exit 1
    fi
}

readCredentialBySource() {

    local tips=$1
    local defaultValue=$2
    echoContent skyBlue "\n${tips}用于配置双方握手的凭据，可手动/文件/环境变量方式录入" >&2
    echoContent yellow "请选择${tips}录入方式（自动化部署可用文件或环境变量）" >&2
    echoContent yellow "1.直接输入${defaultValue:+[回车默认] }" >&2
    echoContent yellow "2.从文件读取" >&2
    echoContent yellow "3.从环境变量读取" >&2
    echo -n "请选择:" >&2
    read -r credentialSource
    local credentialValue=
    case ${credentialSource} in
    2)
        echo -n "请输入文件路径:" >&2
        read -r credentialPath
        if [[ -z "${credentialPath}" || ! -f "${credentialPath}" ]]; then
            echoContent red " ---> 文件路径无效"
            exit 1
        fi
        credentialValue=$(tr -d '\n' <"${credentialPath}")
        ;;
    3)
        echo -n "请输入环境变量名称:" >&2
        read -r credentialEnv
        credentialValue=${!credentialEnv}
        ;;
    *)
        echo -n "${tips}:" >&2
        read -r credentialValue
        if [[ -z "${credentialValue}" && -n "${defaultValue}" ]]; then
            credentialValue=${defaultValue}
        fi
        ;;
    esac

    # 去除可能的ANSI控制符，防止写入配置文件后产生\x1b错误
    credentialValue=$(stripAnsi "${credentialValue}")

    if [[ -z "${credentialValue}" ]]; then
        echoContent red " ---> ${tips}不可为空"
        exit 1
    fi

    echo "${credentialValue}"
}

# 读取tls证书详情
readAcmeTLS() {
    # 重置 DNS API 状态，避免上次调用的残留值
    installedDNSAPIStatus=""

    local readAcmeDomain=
    if [[ -n "${currentHost}" ]]; then
        readAcmeDomain="${currentHost}"
    fi

    if [[ -n "${domain}" ]]; then
        readAcmeDomain="${domain}"
    fi

    # 如果没有域名，直接返回
    if [[ -z "${readAcmeDomain}" ]]; then
        return
    fi

    dnsTLSDomain=$(echo "${readAcmeDomain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    # 检查通配符证书目录是否存在
    # 注意：通配符证书目录名以字面 "*." 开头，如 *.example.com_ecc
    # 使用 \* 匹配字面星号，避免匹配普通证书目录如 sub.example.com_ecc
    local acmeEccDir
    acmeEccDir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name '\*.'"${dnsTLSDomain}_ecc" 2>/dev/null | head -1)
    if [[ -n "${acmeEccDir}" ]]; then
        local keyFile certFile
        # 通配符证书文件名也以字面 "*." 开头
        keyFile=$(find "${acmeEccDir}" -maxdepth 1 -type f -name '\*.'"${dnsTLSDomain}.key" 2>/dev/null | head -1)
        certFile=$(find "${acmeEccDir}" -maxdepth 1 -type f -name '\*.'"${dnsTLSDomain}.cer" 2>/dev/null | head -1)
        if [[ -n "${keyFile}" && -n "${certFile}" ]]; then
            installedDNSAPIStatus=true
        fi
    fi
}

# 读取默认自定义端口
readCustomPort() {
    if [[ -n "${configPath}" && -z "${realityStatus}" && "${coreInstallType}" == "1" ]]; then
        local port=
        port=$(jq -r .inbounds[0].port "${configPath}${frontingType}.json")
        if [[ "${port}" != "443" ]]; then
            customPort=${port}
        fi
    fi
}

# 读取nginx订阅端口
readNginxSubscribe() {
    subscribeType="https"
    if [[ -f "${nginxConfigPath}subscribe.conf" ]]; then
        if grep -q "sing-box" "${nginxConfigPath}subscribe.conf"; then
            subscribePort=$(grep "listen" "${nginxConfigPath}subscribe.conf" | awk '{print $2}')
            subscribeDomain=$(grep "server_name" "${nginxConfigPath}subscribe.conf" | awk '{print $2}')
            subscribeDomain=${subscribeDomain//;/}
            if [[ -n "${currentHost}" && "${subscribeDomain}" != "${currentHost}" ]]; then
                subscribePort=
                subscribeType=
            else
                if ! grep "listen" "${nginxConfigPath}subscribe.conf" | grep -q "ssl"; then
                    subscribeType="http"
                fi
            fi

        fi
    fi
}

# 检测安装方式
readInstallType() {
    coreInstallType=
    configPath=
    singBoxConfigPath=

    # 1.检测安装目录
    if [[ -d "/etc/Proxy-agent" ]]; then
        if [[ -f "/etc/Proxy-agent/xray/xray" ]]; then
            # 检测xray-core
            if [[ -d "/etc/Proxy-agent/xray/conf" ]] && [[ -f "/etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json" || -f "/etc/Proxy-agent/xray/conf/02_trojan_TCP_inbounds.json" || -f "/etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" ]]; then
                # xray-core
                configPath=/etc/Proxy-agent/xray/conf/
                ctlPath=/etc/Proxy-agent/xray/xray
                coreInstallType=1
                if [[ -f "${configPath}07_VLESS_vision_reality_inbounds.json" ]]; then
                    realityStatus=1
                fi
                if [[ -f "/etc/Proxy-agent/sing-box/sing-box" ]] && [[ -f "/etc/Proxy-agent/sing-box/conf/config/06_hysteria2_inbounds.json" || -f "/etc/Proxy-agent/sing-box/conf/config/09_tuic_inbounds.json" ]]; then
                    singBoxConfigPath=/etc/Proxy-agent/sing-box/conf/config/
                fi
            fi
        elif [[ -f "/etc/Proxy-agent/sing-box/sing-box" && -f "/etc/Proxy-agent/sing-box/conf/config.json" ]]; then
            # 检测sing-box
            ctlPath=/etc/Proxy-agent/sing-box/sing-box
            coreInstallType=2
            configPath=/etc/Proxy-agent/sing-box/conf/config/
            singBoxConfigPath=/etc/Proxy-agent/sing-box/conf/config/
        fi
    fi
}

# 读取协议类型
readInstallProtocolType() {
    currentInstallProtocolType=
    frontingType=

    xrayVLESSRealityPort=
    xrayVLESSRealityServerName=

    xrayVLESSRealityXHTTPort=
    xrayVLESSRealityXHTTPServerName=

    #    currentRealityXHTTPPrivateKey=
    currentRealityXHTTPPublicKey=

    currentRealityPrivateKey=
    currentRealityPublicKey=

    currentRealityMldsa65Seed=
    currentRealityMldsa65Verify=

    singBoxVLESSVisionPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=

    frontingTypeReality=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityVisionServerName=
    singBoxVLESSRealityGRPCPort=
    singBoxVLESSRealityGRPCServerName=
    singBoxAnyTLSPort=
    singBoxTuicPort=
    singBoxNaivePort=
    singBoxVMessWSPort=

    while read -r row; do
        if echo "${row}" | grep -q VLESS_TCP_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}0,"
            frontingType=02_VLESS_TCP_inbounds
            if [[ "${coreInstallType}" == "2" ]]; then
                singBoxVLESSVisionPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q VLESS_WS_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}1,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=03_VLESS_WS_inbounds
                singBoxVLESSWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q VLESS_XHTTP_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}12,"
            xrayVLESSRealityXHTTPort=$(jq -r .inbounds[0].port "${row}.json")

            xrayVLESSRealityXHTTPServerName=$(jq -r .inbounds[0].streamSettings.realitySettings.serverNames[0] "${row}.json")

            currentRealityXHTTPPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey "${row}.json")
            #            currentRealityXHTTPPrivateKey=$(jq -r .inbounds[0].streamSettings.realitySettings.privateKey "${row}.json")

            #            if [[ "${coreInstallType}" == "2" ]]; then
            #                frontingType=03_VLESS_WS_inbounds
            #                singBoxVLESSWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            #            fi
        fi

        if echo "${row}" | grep -q trojan_gRPC_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}2,"
        fi
        if echo "${row}" | grep -q VMess_WS_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}3,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=05_VMess_WS_inbounds
                singBoxVMessWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q trojan_TCP_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}4,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=04_trojan_TCP_inbounds
                singBoxTrojanPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q VLESS_gRPC_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}5,"
        fi
        if echo "${row}" | grep -q hysteria2_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}6,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=06_hysteria2_inbounds
                singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q VLESS_vision_reality_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}7,"
            if [[ "${coreInstallType}" == "1" ]]; then
                xrayVLESSRealityServerName=$(jq -r .inbounds[1].streamSettings.realitySettings.serverNames[0] "${row}.json")
                realityServerName=${xrayVLESSRealityServerName}
                xrayVLESSRealityPort=$(jq -r .inbounds[0].port "${row}.json")

                realityDomainPort=$(jq -r .inbounds[1].streamSettings.realitySettings.target "${row}.json" | awk -F '[:]' '{print $2}')

                currentRealityPublicKey=$(jq -r .inbounds[1].streamSettings.realitySettings.publicKey "${row}.json")
                currentRealityPrivateKey=$(jq -r .inbounds[1].streamSettings.realitySettings.privateKey "${row}.json")

                currentRealityMldsa65Seed=$(jq -r .inbounds[1].streamSettings.realitySettings.mldsa65Seed "${row}.json")
                currentRealityMldsa65Verify=$(jq -r .inbounds[1].streamSettings.realitySettings.mldsa65Verify "${row}.json")

                frontingTypeReality=07_VLESS_vision_reality_inbounds

            elif [[ "${coreInstallType}" == "2" ]]; then
                frontingTypeReality=07_VLESS_vision_reality_inbounds
                singBoxVLESSRealityVisionPort=$(jq -r .inbounds[0].listen_port "${row}.json")
                singBoxVLESSRealityVisionServerName=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                realityDomainPort=$(jq -r .inbounds[0].tls.reality.handshake.server_port "${row}.json")

                realityServerName=${singBoxVLESSRealityVisionServerName}
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')

                    currentRealityPrivateKey=$(jq -r .inbounds[0].tls.reality.private_key "${row}.json")
                    currentRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
            fi
        fi
        if echo "${row}" | grep -q VLESS_vision_gRPC_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}8,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingTypeReality=08_VLESS_vision_gRPC_inbounds
                singBoxVLESSRealityGRPCPort=$(jq -r .inbounds[0].listen_port "${row}.json")
                singBoxVLESSRealityGRPCServerName=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
            fi
        fi
        if echo "${row}" | grep -q tuic_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}9,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=09_tuic_inbounds
                singBoxTuicPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q naive_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}10,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=10_naive_inbounds
                singBoxNaivePort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q anytls_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}13,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=13_anytls_inbounds
                singBoxAnyTLSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q ss2022_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}14,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=14_ss2022_inbounds
                ss2022Port=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row}" | grep -q VMess_HTTPUpgrade_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}11,"
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=11_VMess_HTTPUpgrade_inbounds
                singBoxVMessHTTPUpgradePort=$(grep 'listen' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
            fi
        fi

    done < <(find ${configPath} -name "*inbounds.json" | sort | awk -F "[.]" '{print $1}')

    if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            currentInstallProtocolType="${currentInstallProtocolType}6,"
            singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            currentInstallProtocolType="${currentInstallProtocolType}9,"
            singBoxTuicPort=$(jq .inbounds[0].listen_port "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
    fi
    if [[ "${currentInstallProtocolType:0:1}" != "," ]]; then
        currentInstallProtocolType=",${currentInstallProtocolType}"
    fi
}

# 检查是否安装宝塔
checkBTPanel() {
    if [[ -n $(pgrep -f "BT-Panel") ]]; then
        # 读取域名
        if [[ -d '/www/server/panel/vhost/cert/' && -n $(find /www/server/panel/vhost/cert/*/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\n读取宝塔配置\n"

                find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}'

                read -r -p "请输入编号选择:" selectBTDomain
            else
                selectBTDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep -e "^${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> 选择错误，请重新选择"
                    checkBTPanel
                else
                    domain=${btDomain}
                    if [[ ! -f "/etc/Proxy-agent/tls/${btDomain}.crt" && ! -f "/etc/Proxy-agent/tls/${btDomain}.key" ]]; then
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/fullchain.pem" "/etc/Proxy-agent/tls/${btDomain}.crt"
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/privkey.pem" "/etc/Proxy-agent/tls/${btDomain}.key"
                    fi

                    nginxStaticPath="/www/wwwroot/${btDomain}/html/"

                    mkdir -p "/www/wwwroot/${btDomain}/html/"

                    if [[ -f "/www/wwwroot/${btDomain}/.user.ini" ]]; then
                        chattr -i "/www/wwwroot/${btDomain}/.user.ini"
                    fi
                    nginxConfigPath="/www/server/panel/vhost/nginx/"
                fi
            else
                echoContent red " ---> 选择错误，请重新选择"
                checkBTPanel
            fi
        fi
    fi
}
check1Panel() {
    if [[ -n $(pgrep -f "1panel") ]]; then
        # 读取域名
        if [[ -d '/opt/1panel/apps/openresty/openresty/www/sites/' && -n $(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\n读取1Panel配置\n"

                find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}'

                read -r -p "请输入编号选择:" selectBTDomain
            else
                selectBTDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> 选择错误，请重新选择"
                    check1Panel
                else
                    domain=${btDomain}
                    if [[ ! -f "/etc/Proxy-agent/tls/${btDomain}.crt" && ! -f "/etc/Proxy-agent/tls/${btDomain}.key" ]]; then
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/fullchain.pem" "/etc/Proxy-agent/tls/${btDomain}.crt"
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/privkey.pem" "/etc/Proxy-agent/tls/${btDomain}.key"
                    fi

                    nginxStaticPath="/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/index/"
                fi
            else
                echoContent red " ---> 选择错误，请重新选择"
                check1Panel
            fi
        fi
    fi
}
# 读取当前alpn的顺序
readInstallAlpn() {
    if [[ -n "${currentInstallProtocolType}" && -z "${realityStatus}" ]]; then
        local alpn
        alpn=$(jq -r .inbounds[0].streamSettings.tlsSettings.alpn[0] ${configPath}${frontingType}.json)
        if [[ -n ${alpn} ]]; then
            currentAlpn=${alpn}
        fi
    fi
}

# 检查防火墙
allowPort() {
    local type=$2
    local sourceRange=$3
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+ufw"; then
        if ufw status | grep -q "Status: active"; then
            if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
                sudo ufw allow from "${sourceRange}" to any port "$1" proto "${type}"
                checkUFWAllowPort "$1"
            elif ! ufw status | grep -q "$1/${type}"; then
                sudo ufw allow "$1/${type}"
                checkUFWAllowPort "$1"
            fi
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local updateFirewalldStatus=
        if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
            local richRule="rule family=\"ipv4\" source address=\"${sourceRange}\" port protocol=\"${type}\" port=\"$1\" accept"
            if ! firewall-cmd --permanent --query-rich-rule="${richRule}" >/dev/null 2>&1; then
                updateFirewalldStatus=true
                firewall-cmd --permanent --zone=public --add-rich-rule="${richRule}"
                checkFirewalldAllowPort "$1"
            fi
        elif ! firewall-cmd --list-ports --permanent | grep -qw "$1/${type}"; then
            updateFirewalldStatus=true
            local firewallPort=$1
            if echo "${firewallPort}" | grep -q ":"; then
                firewallPort=$(echo "${firewallPort}" | awk -F ":" '{print $1"-"$2}')
            fi
            firewall-cmd --zone=public --add-port="${firewallPort}/${type}" --permanent
            checkFirewalldAllowPort "${firewallPort}"
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            firewall-cmd --reload
        fi
    elif rc-update show 2>/dev/null | grep -q ufw; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                sudo ufw allow "$1/${type}"
                checkUFWAllowPort "$1"
            fi
        fi
    elif command -v nft >/dev/null 2>&1 && systemctl status nftables 2>/dev/null | grep -q "active"; then
        if nft list chain inet filter input >/dev/null 2>&1; then
            local nftComment="allow $1/${type}(Proxy-agent)"
            local nftSourceRange="${sourceRange:-0.0.0.0/0}"
            local nftRules
            local updateNftablesStatus=
            nftRules=$(nft list chain inet filter input)
            if ! echo "${nftRules}" | grep -q "${nftComment}" || ! echo "${nftRules}" | grep -q "${nftSourceRange}"; then
                updateNftablesStatus=true
                nft add rule inet filter input ip saddr "${nftSourceRange}" ${type} dport "$1" counter accept comment "${nftComment}"
            fi

            if echo "${updateNftablesStatus}" | grep -q "true"; then
                nft list ruleset >/etc/nftables.conf
                systemctl reload nftables >/dev/null 2>&1 || nft -f /etc/nftables.conf
            fi
        fi
    elif command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+netfilter-persistent" && systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local updateFirewalldStatus=
        if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
            if ! iptables -C INPUT -p ${type} -s "${sourceRange}" --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT 2>/dev/null; then
                updateFirewalldStatus=true
                iptables -I INPUT -p ${type} -s "${sourceRange}" --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT
            fi
        elif ! iptables -L | grep -q "$1/${type}(Proxy-agent)"; then
            updateFirewalldStatus=true
            iptables -I INPUT -p ${type} --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            netfilter-persistent save
        fi
    fi
}
# 获取公网IP
getPublicIP() {
    local type=4
    if [[ -n "$1" ]]; then
        type=$1
    fi
    if [[ -n "${currentHost}" && -z "$1" ]] && [[ "${singBoxVLESSRealityVisionServerName}" == "${currentHost}" || "${singBoxVLESSRealityGRPCServerName}" == "${currentHost}" || "${xrayVLESSRealityServerName}" == "${currentHost}" ]]; then
        echo "${currentHost}"
    else
        local currentIP=
        currentIP=$(curl -s "-${type}" https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
        if [[ -z "${currentIP}" && -z "$1" ]]; then
            currentIP=$(curl -s "-6" https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
        fi
        echo "${currentIP}"
    fi

}

# 输出ufw端口开放状态
checkUFWAllowPort() {
    if ufw status | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 1
    fi
}

# 输出firewall-cmd端口开放状态
checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1" || firewall-cmd --list-rich-rules --permanent | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 1
    fi
}

# 读取Tuic配置
readSingBoxConfig() {
    tuicPort=
    hysteriaPort=
    if [[ -n "${singBoxConfigPath}" ]]; then

        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            tuicPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}09_tuic_inbounds.json")
            tuicAlgorithm=$(jq -r '.inbounds[0].congestion_control' "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            hysteriaPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ClientUploadSpeed=$(jq -r '.inbounds[0].up_mbps' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ClientDownloadSpeed=$(jq -r '.inbounds[0].down_mbps' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ObfsPassword=$(jq -r '.inbounds[0].obfs.password // empty' "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
    fi
}

# 读取上次安装的配置
readLastInstallationConfig() {
    if [[ -n "${configPath}" ]]; then
        read -r -p "读取到上次安装的配置，是否使用 ？[y/n]:" lastInstallationConfigStatus
        if [[ "${lastInstallationConfigStatus}" == "y" ]]; then
            lastInstallationConfig=true
        fi
    fi
}
# 卸载 sing-box
unInstallSingBox() {
    local type=$1
    if [[ -n "${singBoxConfigPath}" ]]; then
        if grep -q 'tuic' </etc/Proxy-agent/sing-box/conf/config.json && [[ "${type}" == "tuic" ]]; then
            rm "${singBoxConfigPath}09_tuic_inbounds.json"
            echoContent green " ---> 删除sing-box tuic配置成功"
        fi

        if grep -q 'hysteria2' </etc/Proxy-agent/sing-box/conf/config.json && [[ "${type}" == "hysteria2" ]]; then
            rm "${singBoxConfigPath}06_hysteria2_inbounds.json"
            echoContent green " ---> 删除sing-box hysteria2配置成功"
        fi
        rm "${singBoxConfigPath}config.json"
    fi

    readInstallType

    if [[ -n "${singBoxConfigPath}" ]]; then
        echoContent yellow " ---> 检测到有其他配置，保留sing-box核心"
        handleSingBox stop
        handleSingBox start
    else
        handleSingBox stop
        rm /etc/systemd/system/sing-box.service
        rm -rf /etc/Proxy-agent/sing-box/*
        echoContent green " ---> sing-box 卸载完成"
    fi
}

# 检查文件目录以及path路径
readConfigHostPathUUID() {
    currentPath=
    currentDefaultPort=
    currentUUID=
    currentClients=
    currentHost=
    currentPort=
    currentCDNAddress=
    singBoxVMessWSPath=
    singBoxVLESSWSPath=
    singBoxVMessHTTPUpgradePath=

    if [[ "${coreInstallType}" == "1" ]]; then

        # 安装
        if [[ -n "${frontingType}" ]]; then
            currentHost=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}${frontingType}.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '[.][c][r][t]' '{print $1}')

            currentPort=$(jq .inbounds[0].port ${configPath}${frontingType}.json)

            local defaultPortFile=
            defaultPortFile=$(find ${configPath}* | grep "default")

            if [[ -n "${defaultPortFile}" ]]; then
                currentDefaultPort=$(echo "${defaultPortFile}" | awk -F [_] '{print $4}')
            else
                currentDefaultPort=$(jq -r .inbounds[0].port ${configPath}${frontingType}.json)
            fi
            currentUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].settings.clients ${configPath}${frontingType}.json)
        fi

        # reality
        if echo ${currentInstallProtocolType} | grep -q ",7,"; then

            currentClients=$(jq -r .inbounds[1].settings.clients ${configPath}07_VLESS_vision_reality_inbounds.json)
            currentUUID=$(jq -r .inbounds[1].settings.clients[0].id ${configPath}07_VLESS_vision_reality_inbounds.json)
            xrayVLESSRealityVisionPort=$(jq -r .inbounds[0].port ${configPath}07_VLESS_vision_reality_inbounds.json)
            if [[ "${currentPort}" == "${xrayVLESSRealityVisionPort}" ]]; then
                xrayVLESSRealityVisionPort="${currentDefaultPort}"
            fi
        fi
    elif [[ "${coreInstallType}" == "2" ]]; then
        if [[ -n "${frontingType}" ]]; then
            currentHost=$(jq -r .inbounds[0].tls.server_name ${configPath}${frontingType}.json)
            if echo ${currentInstallProtocolType} | grep -q ",11," && [[ "${currentHost}" == "null" ]]; then
                currentHost=$(grep 'server_name' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
                currentHost=${currentHost//;/}
            fi
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingType}.json)
        else
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingTypeReality}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingTypeReality}.json)
        fi
    fi

    # 读取path
    if [[ -n "${configPath}" && -n "${frontingType}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            local fallback
            fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' ${configPath}${frontingType}.json | head -1)

            local path
            path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}')

            if [[ $(echo "${fallback}" | jq -r .dest) == 31297 ]]; then
                currentPath=$(echo "${path}" | awk -F "[w][s]" '{print $1}')
            elif [[ $(echo "${fallback}" | jq -r .dest) == 31299 ]]; then
                currentPath=$(echo "${path}" | awk -F "[v][w][s]" '{print $1}')
            fi

            # 尝试读取alpn h2 Path
            if [[ -z "${currentPath}" ]]; then
                dest=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.alpn)|.dest' ${configPath}${frontingType}.json | head -1)
                if [[ "${dest}" == "31302" || "${dest}" == "31304" ]]; then
                    checkBTPanel
                    check1Panel
                    if grep -q "trojangrpc {" <${nginxConfigPath}alone.conf; then
                        currentPath=$(grep "trojangrpc {" <${nginxConfigPath}alone.conf | awk -F "[/]" '{print $2}' | awk -F "[t][r][o][j][a][n]" '{print $1}')
                    elif grep -q "grpc {" <${nginxConfigPath}alone.conf; then
                        currentPath=$(grep "grpc {" <${nginxConfigPath}alone.conf | head -1 | awk -F "[/]" '{print $2}' | awk -F "[g][r][p][c]" '{print $1}')
                    fi
                fi
            fi
            if [[ -z "${currentPath}" && -f "${configPath}12_VLESS_XHTTP_inbounds.json" ]]; then
                currentPath=$(jq -r .inbounds[0].streamSettings.xhttpSettings.path "${configPath}12_VLESS_XHTTP_inbounds.json" | awk -F "[x][H][T][T][P]" '{print $1}' | awk -F "[/]" '{print $2}')
            fi
        elif [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}05_VMess_WS_inbounds.json" ]]; then
            singBoxVMessWSPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}05_VMess_WS_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}05_VMess_WS_inbounds.json" | awk -F "[/]" '{print $2}')
        fi
        if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}03_VLESS_WS_inbounds.json" ]]; then
            singBoxVLESSWSPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}03_VLESS_WS_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}03_VLESS_WS_inbounds.json" | awk -F "[/]" '{print $2}')
            currentPath=${currentPath::-2}
        fi
        if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
            singBoxVMessHTTPUpgradePath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" | awk -F "[/]" '{print $2}')
            # currentPath=${currentPath::-2}
        fi
    fi
    if [[ -f "/etc/Proxy-agent/cdn" ]] && [[ -n "$(head -1 /etc/Proxy-agent/cdn)" ]]; then
        currentCDNAddress=$(head -1 /etc/Proxy-agent/cdn)
    else
        currentCDNAddress="${currentHost}"
    fi
}

# 状态展示
showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
        if [[ "${coreInstallType}" == 1 ]]; then
            if [[ -n $(pgrep -f "xray/xray") ]]; then
                echoContent yellow "\n$(t CORE_CURRENT_RUNNING "Xray-core")"
            else
                echoContent yellow "\n$(t CORE_CURRENT_STOPPED "Xray-core")"
            fi

        elif [[ "${coreInstallType}" == 2 ]]; then
            if [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
                echoContent yellow "\n$(t CORE_CURRENT_RUNNING "sing-box")"
            else
                echoContent yellow "\n$(t CORE_CURRENT_STOPPED "sing-box")"
            fi
        fi
        # 读取协议类型
        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            echoContent yellow "$(t PROTOCOLS_INSTALLED): \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",0,"; then
            echoContent yellow "VLESS+TCP[TLS_Vision] \c"
        fi

        if echo ${currentInstallProtocolType} | grep -q ",1,"; then
            echoContent yellow "VLESS+WS[TLS] \c"
        fi

        if echo ${currentInstallProtocolType} | grep -q ",2,"; then
            echoContent yellow "Trojan+gRPC[TLS] \c"
        fi

        if echo ${currentInstallProtocolType} | grep -q ",3,"; then
            echoContent yellow "VMess+WS[TLS] \c"
        fi

        if echo ${currentInstallProtocolType} | grep -q ",4,"; then
            echoContent yellow "Trojan+TCP[TLS] \c"
        fi

        if echo ${currentInstallProtocolType} | grep -q ",5,"; then
            echoContent yellow "VLESS+gRPC[TLS] \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",6,"; then
            echoContent yellow "Hysteria2 \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",7,"; then
            echoContent yellow "VLESS+Reality+Vision \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",8,"; then
            echoContent yellow "VLESS+Reality+gRPC \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",9,"; then
            echoContent yellow "Tuic \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",10,"; then
            echoContent yellow "Naive \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",11,"; then
            echoContent yellow "VMess+TLS+HTTPUpgrade \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",12,"; then
            echoContent yellow "VLESS+Reality+XHTTP \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",13,"; then
            echoContent yellow "AnyTLS \c"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",14,"; then
            echoContent yellow "SS2022 \c"
        fi
    fi
}

# 清理旧残留
cleanUp() {
    if [[ "$1" == "xrayDel" ]]; then
        handleXray stop
        rm -rf /etc/Proxy-agent/xray/*
    elif [[ "$1" == "singBoxDel" ]]; then
        handleSingBox stop
        rm -rf /etc/Proxy-agent/sing-box/conf/config.json >/dev/null 2>&1
        rm -rf /etc/Proxy-agent/sing-box/conf/config/* >/dev/null 2>&1
    fi
}
initVar "$1"
checkSystem
checkCPUVendor

readInstallType
readInstallProtocolType
readConfigHostPathUUID
readCustomPort
readSingBoxConfig
# -------------------------------------------------------------

# 初始化安装目录
mkdirTools() {
    # TLS证书目录 - 设置严格权限保护私钥
    mkdir -p /etc/Proxy-agent/tls
    chmod 700 /etc/Proxy-agent/tls

    mkdir -p /etc/Proxy-agent/subscribe_local/default
    mkdir -p /etc/Proxy-agent/subscribe_local/clashMeta

    mkdir -p /etc/Proxy-agent/subscribe_remote/default
    mkdir -p /etc/Proxy-agent/subscribe_remote/clashMeta

    mkdir -p /etc/Proxy-agent/subscribe/default
    mkdir -p /etc/Proxy-agent/subscribe/clashMetaProfiles
    mkdir -p /etc/Proxy-agent/subscribe/clashMeta

    mkdir -p /etc/Proxy-agent/subscribe/sing-box
    mkdir -p /etc/Proxy-agent/subscribe/sing-box_profiles
    mkdir -p /etc/Proxy-agent/subscribe_local/sing-box

    # Xray配置目录 - 设置适当权限
    mkdir -p /etc/Proxy-agent/xray/conf
    chmod 700 /etc/Proxy-agent/xray/conf
    mkdir -p /etc/Proxy-agent/xray/reality_scan
    mkdir -p /etc/Proxy-agent/xray/tmp
    mkdir -p /etc/systemd/system/
    mkdir -p /tmp/Proxy-agent-tls/

    # WARP配置目录 - 包含私钥
    mkdir -p /etc/Proxy-agent/warp
    chmod 700 /etc/Proxy-agent/warp

    # sing-box配置目录 - 设置适当权限
    mkdir -p /etc/Proxy-agent/sing-box/conf/config
    chmod 700 /etc/Proxy-agent/sing-box/conf

    mkdir -p /usr/share/nginx/html/
}
# 检测root
checkRoot() {
    if [ "$(id -u)" -ne 0 ]; then
        #        sudoCMD="sudo"
        echo "检测到非 Root 用户，将使用 sudo 执行命令..."
    fi
}
# 安装工具包
installTools() {
    echoContent skyBlue "\n$(t PROGRESS_STEP "$1" "${totalProgress}") : $(t PROG_INSTALL_TOOLS)"
    # 修复ubuntu个别系统问题
    if [[ "${release}" == "ubuntu" ]]; then
        dpkg --configure -a
    fi

    if [[ -n $(pgrep -f "apt") ]]; then
        pgrep -f apt | xargs kill -9
    fi

    echoContent green " ---> $(t INSTALL_CHECKING)"

    ${upgrade} >/etc/Proxy-agent/install.log 2>&1
    if grep <"/etc/Proxy-agent/install.log" -q "changed"; then
        ${updateReleaseInfoChange} >/dev/null 2>&1
    fi

    if [[ "${release}" == "centos" ]]; then
        rm -rf /var/run/yum.pid
        ${installType} epel-release >/dev/null 2>&1
    fi

    if ! sudo --version >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "sudo")"
        ${installType} sudo >/dev/null 2>&1
    fi

    if ! wget --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "wget")"
        ${installType} wget >/dev/null 2>&1
    fi

    if ! command -v netfilter-persistent >/dev/null 2>&1; then
        if [[ "${release}" != "centos" ]]; then
            echoContent green " ---> $(t INSTALL_TOOL "iptables")"
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
            ${installType} iptables-persistent >/dev/null 2>&1
        fi
    fi

    if ! curl --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "curl")"
        ${installType} curl >/dev/null 2>&1
    fi

    if ! unzip >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "unzip")"
        ${installType} unzip >/dev/null 2>&1
    fi

    if ! socat -h >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "socat")"
        ${installType} socat >/dev/null 2>&1
    fi

    if ! tar --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "tar")"
        ${installType} tar >/dev/null 2>&1
    fi

    if ! crontab -l >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "crontabs")"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            ${installType} cron >/dev/null 2>&1
        else
            ${installType} crontabs >/dev/null 2>&1
        fi
    fi
    if ! jq --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "jq")"
        ${installType} jq >/dev/null 2>&1
    fi

    if ! command -v ld >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "binutils")"
        ${installType} binutils >/dev/null 2>&1
    fi

    if ! openssl help >/dev/null 2>&1; then
        echoContent green " ---> 安装openssl"
        ${installType} openssl >/dev/null 2>&1
    fi

    if ! ping6 --help >/dev/null 2>&1; then
        echoContent green " ---> 安装ping6"
        ${installType} inetutils-ping >/dev/null 2>&1
    fi

    if ! qrencode --help >/dev/null 2>&1; then
        echoContent green " ---> 安装qrencode"
        ${installType} qrencode >/dev/null 2>&1
    fi

    if ! command -v lsb_release >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            ${installType} lsb-release >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            ${installType} redhat-lsb-core >/dev/null 2>&1
        else
            ${installType} lsb-release >/dev/null 2>&1
        fi
    fi

    if ! lsof -h >/dev/null 2>&1; then
        echoContent green " ---> 安装lsof"
        ${installType} lsof >/dev/null 2>&1
    fi

    if ! dig -h >/dev/null 2>&1; then
        echoContent green " ---> 安装dig"
        if echo "${installType}" | grep -qw "apt"; then
            ${installType} dnsutils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "yum"; then
            ${installType} bind-utils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "apk"; then
            ${installType} bind-tools >/dev/null 2>&1
        fi
    fi

    # 检测nginx版本，并提供是否卸载的选项
    if echo "${selectCustomInstallType}" | grep -qwE ",7,|,8,|,7,8,"; then
        echoContent green " ---> 检测到无需依赖Nginx的服务，跳过安装"
    else
        if ! nginx >/dev/null 2>&1; then
            echoContent green " ---> 安装nginx"
            installNginxTools
        else
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            if [[ ${nginxVersion} -lt 14 ]]; then
                read -r -p "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装 ？[y/n]:" unInstallNginxStatus
                if [[ "${unInstallNginxStatus}" == "y" ]]; then
                    ${removeType} nginx >/dev/null 2>&1
                    echoContent yellow " ---> nginx卸载完成"
                    echoContent green " ---> 安装nginx"
                    installNginxTools >/dev/null 2>&1
                else
                    exit 0
                fi
            fi
        fi
    fi

    if ! command -v semanage >/dev/null 2>&1; then
        echoContent green " ---> 安装semanage"
        ${installType} bash-completion >/dev/null 2>&1

        if [[ "${centosVersion}" == "7" ]]; then
            policyCoreUtils="policycoreutils-python"
        elif [[ "${centosVersion}" == "8" || "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            policyCoreUtils="policycoreutils-python-utils"
        fi

        if [[ -n "${policyCoreUtils}" ]]; then
            ${installType} ${policyCoreUtils} >/dev/null 2>&1
        fi
        if [[ -n $(which semanage) ]]; then
            if command -v getenforce >/dev/null 2>&1; then
                selinux_status=$(getenforce)
                if [ "$selinux_status" != "Disabled" ]; then
                    semanage port -a -t http_port_t -p tcp 31300
                fi
            fi
        fi
    fi

    if [[ "${selectCustomInstallType}" == "7" ]]; then
        echoContent green " ---> 检测到无需依赖证书的服务，跳过安装"
    else
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            echoContent green " ---> 安装acme.sh"
            curl -s https://get.acme.sh | sh >/etc/Proxy-agent/tls/acme.log 2>&1

            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent red "  acme安装失败--->"
                tail -n 100 /etc/Proxy-agent/tls/acme.log
                echoContent yellow "错误排查:"
                echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
                echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
                echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他NAT64"
                echoContent skyBlue "  sed -i \"1i\\\nameserver 2a00:1098:2b::1\\\nnameserver 2a00:1098:2c::1\\\nnameserver 2a01:4f8:c2c:123f::1\\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                exit 1
            fi
        fi
    fi

}
# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload
        systemctl enable "${serviceName}"
    fi
}
# 安装Nginx
installNginxTools() {

    if [[ "${release}" == "debian" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb https://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb https://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        cat <<EOF >/etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    elif [[ "${release}" == "alpine" ]]; then
        rm "${nginxConfigPath}default.conf"
    fi
    ${installType} nginx >/dev/null 2>&1
    bootStartup nginx
}

# 安装warp
installWarp() {
    if [[ "${cpuVendor}" == "arm" ]]; then
        echoContent red " ---> 官方WARP客户端不支持ARM架构"
        exit 1
    fi

    ${installType} gnupg2 -y >/dev/null 2>&1
    if [[ "${release}" == "debian" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | sudo apt-key add - >/dev/null 2>&1
        echo "deb https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | sudo apt-key add - >/dev/null 2>&1
        echo "deb https://pkg.cloudflareclient.com/ focal main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        sudo rpm -ivh "https://pkg.cloudflareclient.com/cloudflare-release-el${centosVersion}.rpm" >/dev/null 2>&1
    fi

    echoContent green " ---> 安装WARP"
    ${installType} cloudflare-warp >/dev/null 2>&1
    if [[ -z $(which warp-cli) ]]; then
        echoContent red " ---> 安装WARP失败"
        exit 1
    fi
    systemctl enable warp-svc
    warp-cli --accept-tos register
    warp-cli --accept-tos set-mode proxy
    warp-cli --accept-tos set-proxy-port 31303
    warp-cli --accept-tos connect
    warp-cli --accept-tos enable-always-on

    local warpStatus=
    warpStatus=$(curl -s --socks5 127.0.0.1:31303 https://www.cloudflare.com/cdn-cgi/trace | grep "warp" | cut -d "=" -f 2)

    if [[ "${warpStatus}" == "on" ]]; then
        echoContent green " ---> WARP启动成功"
    fi
}

# 通过dns检查域名的IP
checkDNSIP() {
    local domain=$1
    local dnsIP=
    ipType=4
    dnsIP=$(dig @1.1.1.1 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    if [[ -z "${dnsIP}" ]]; then
        dnsIP=$(dig @8.8.8.8 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    fi
    if echo "${dnsIP}" | grep -q "timed out" || [[ -z "${dnsIP}" ]]; then
        echo
        echoContent red " ---> 无法通过DNS获取域名 IPv4 地址"
        echoContent green " ---> 尝试检查域名 IPv6 地址"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if echo "${dnsIP}" | grep -q "network unreachable" || [[ -z "${dnsIP}" ]]; then
            echoContent red " ---> 无法通过DNS获取域名IPv6地址，退出安装"
            exit 1
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        echoContent red " ---> 域名解析IP与当前服务器IP不一致\n"
        echoContent yellow " ---> 请检查域名解析是否生效以及正确"
        echoContent green " ---> 当前VPS IP：${publicIP}"
        echoContent green " ---> DNS解析 IP：${dnsIP}"
        exit 0
    else
        echoContent green " ---> 域名IP校验通过"
    fi
}
# 检查端口实际开放状态
checkPortOpen() {
    handleSingBox stop >/dev/null 2>&1
    handleXray stop >/dev/null 2>&1

    local port=$1
    local domain=$2
    local checkPortOpenResult=
    allowPort "${port}"

    if [[ -z "${btDomain}" ]]; then

        handleNginx stop
        # 初始化nginx配置
        touch ${nginxConfigPath}checkPortOpen.conf
        local listenIPv6PortConfig=

        if [[ -n $(curl -s -6 -m 4 https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2) ]]; then
            listenIPv6PortConfig="listen [::]:${port};"
        fi
        cat <<EOF >${nginxConfigPath}checkPortOpen.conf
server {
    listen ${port};
    ${listenIPv6PortConfig}
    server_name ${domain};
    location /checkPort {
        return 200 'fjkvymb6len';
    }
    location /ip {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header REMOTE-HOST \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        default_type text/plain;
        return 200 \$proxy_add_x_forwarded_for;
    }
}
EOF
        handleNginx start
        # 检查域名+端口的开放
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        rm "${nginxConfigPath}checkPortOpen.conf"
        handleNginx stop
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            echoContent green " ---> 检测到${port}端口已开放"
        else
            echoContent green " ---> 未检测到${port}端口开放，退出安装"
            if echo "${checkPortOpenResult}" | grep -q "cloudflare"; then
                echoContent yellow " ---> 请关闭云朵后等待三分钟重新尝试"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    echoContent red " ---> 请检查是否有网页防火墙，比如Oracle等云服务商"
                    echoContent red " ---> 检查是否自己安装过nginx并且有配置冲突，可以尝试DD纯净系统后重新尝试"
                else
                    echoContent red " ---> 错误日志：${checkPortOpenResult}，请将此错误日志通过issues提交反馈"
                fi
            fi
            exit 1
        fi
        checkIP "${localIP}"
    fi
}

# 初始化Nginx申请证书配置
initTLSNginxConfig() {
    handleNginx stop
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" == "y" ]]; then
            domain=${currentHost}
            echoContent yellow "\n ---> 域名: ${domain}"
        else
            echo
            echoContent yellow "请输入要配置的域名 例: example.com --->"
            read -r -p "域名:" domain
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        echoContent yellow "请输入要配置的域名 例: example.com --->"
        read -r -p "域名:" domain
    fi

    if [[ -z ${domain} ]]; then
        echoContent red "  域名不可为空--->"
        initTLSNginxConfig 3
    elif ! isValidDomain "${domain}"; then
        echoContent red "  域名格式无效或包含不安全字符--->"
        echoContent yellow "  域名只能包含字母、数字、连字符和点"
        initTLSNginxConfig 3
    else
        dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
        if [[ "${selectCoreType}" == "1" ]]; then
            customPortFunction
        fi
        # 修改配置
        handleNginx stop
    fi
}

# 删除nginx默认的配置
removeNginxDefaultConf() {
    if [[ -f "${nginxConfigPath}default.conf" ]]; then
        if [[ "$(grep -c "server_name" <"${nginxConfigPath}default.conf")" == "1" ]] && [[ "$(grep -c "server_name  localhost;" <"${nginxConfigPath}default.conf")" == "1" ]]; then
            echoContent green " ---> 删除Nginx默认配置"
            rm -rf "${nginxConfigPath}default.conf" >/dev/null 2>&1
        fi
    fi
}
# 修改nginx重定向配置
updateRedirectNginxConf() {
    local redirectDomain=
    redirectDomain=${domain}:${port}

    local nginxH2Conf=
    nginxH2Conf="listen 127.0.0.1:31302 http2 so_keepalive=on proxy_protocol;"
    nginxVersion=$(nginx -v 2>&1)

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen 127.0.0.1:31302 so_keepalive=on proxy_protocol;http2 on;"
    fi

    cat <<EOF >${nginxConfigPath}alone.conf
    server {
    		listen 127.0.0.1:31300;
    		server_name _;
    		return 403;
    }
EOF

    if echo "${selectCustomInstallType}" | grep -qE ",2,|,5," || [[ -z "${selectCustomInstallType}" ]]; then

        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}
	server_name ${domain};
	root ${nginxStaticPath};

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	# 基础超时配置
	client_header_timeout 60s;
	keepalive_timeout 65;

	# 安全头部
	server_tokens off;
	add_header X-Content-Type-Options "nosniff" always;
	add_header X-Frame-Options "SAMEORIGIN" always;
	add_header X-XSS-Protection "1; mode=block" always;

	location /${currentPath}grpc {
		if (\$content_type !~ "application/grpc") {
			return 404;
		}
		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 86400s;
		grpc_read_timeout 86400s;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location /${currentPath}trojangrpc {
		if (\$content_type !~ "application/grpc") {
			return 404;
		}
		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 86400s;
		grpc_read_timeout 86400s;
		grpc_pass grpc://127.0.0.1:31304;
	}

	# 伪装站静态文件
	location / {
		try_files \$uri \$uri/ =404;
	}

	# 常见静态资源缓存
	location ~* \.(ico|css|js|gif|jpeg|jpg|png|woff|woff2|ttf|svg|eot)$ {
		expires 30d;
		add_header Cache-Control "public, immutable";
	}

	# favicon 处理
	location = /favicon.ico {
		log_not_found off;
		access_log off;
	}

	# robots.txt 处理
	location = /robots.txt {
		log_not_found off;
		access_log off;
	}
}
EOF
    elif echo "${selectCustomInstallType}" | grep -q ",5," || [[ -z "${selectCustomInstallType}" ]]; then
        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	# 安全头部
	server_tokens off;
	add_header X-Content-Type-Options "nosniff" always;
	add_header X-Frame-Options "SAMEORIGIN" always;

	location /${currentPath}grpc {
		client_max_body_size 0;
		keepalive_requests 10000;
		client_body_timeout 86400s;
		send_timeout 86400s;
		lingering_close always;
		grpc_read_timeout 86400s;
		grpc_send_timeout 86400s;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location / {
		try_files \$uri \$uri/ =404;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt { log_not_found off; access_log off; }
}
EOF

    elif echo "${selectCustomInstallType}" | grep -q ",2," || [[ -z "${selectCustomInstallType}" ]]; then
        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	# 安全头部
	server_tokens off;
	add_header X-Content-Type-Options "nosniff" always;
	add_header X-Frame-Options "SAMEORIGIN" always;

	location /${currentPath}trojangrpc {
		client_max_body_size 0;
		keepalive_requests 10000;
		client_body_timeout 86400s;
		send_timeout 86400s;
		lingering_close always;
		grpc_read_timeout 86400s;
		grpc_send_timeout 86400s;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location / {
		try_files \$uri \$uri/ =404;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt { log_not_found off; access_log off; }
}
EOF
    else

        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	# 安全头部
	server_tokens off;
	add_header X-Content-Type-Options "nosniff" always;
	add_header X-Frame-Options "SAMEORIGIN" always;

	location / {
		try_files \$uri \$uri/ =404;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt { log_not_found off; access_log off; }
}
EOF
    fi

    cat <<EOF >>${nginxConfigPath}alone.conf
server {
	listen 127.0.0.1:31300 proxy_protocol;
	server_name ${domain};

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	root ${nginxStaticPath};

	# 安全头部
	server_tokens off;

	location / {
		try_files \$uri \$uri/ =404;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt { log_not_found off; access_log off; }
}
EOF
    handleNginx stop
}
# singbox Nginx config
singBoxNginxConfig() {
    local type=$1
    local port=$2

    local nginxH2Conf=
    nginxH2Conf="listen ${port} http2 so_keepalive=on ssl;"
    nginxVersion=$(nginx -v 2>&1)

    local singBoxNginxSSL=
    singBoxNginxSSL="ssl_certificate /etc/Proxy-agent/tls/${domain}.crt;ssl_certificate_key /etc/Proxy-agent/tls/${domain}.key;"

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen ${port} so_keepalive=on ssl;http2 on;"
    fi

    if echo "${selectCustomInstallType}" | grep -q ",11," || [[ "$1" == "all" ]]; then
        cat <<EOF >>${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf
server {
	${nginxH2Conf}

	server_name ${domain};
	root ${nginxStaticPath};
    ${singBoxNginxSSL}

    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;

    location /${currentPath} {
    	if (\$http_upgrade != "websocket") {
            return 444;
        }

        proxy_pass                          http://127.0.0.1:31306;
        proxy_http_version                  1.1;
        proxy_set_header Upgrade            \$http_upgrade;
        proxy_set_header Connection         "upgrade";
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header Host               \$host;
        proxy_redirect                      off;
	}
}
EOF
    fi
}

# 检查ip
checkIP() {
    echoContent skyBlue "\n ---> 检查域名ip中"
    local localIP=$1

    if [[ -z ${localIP} ]] || ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q '\.' && ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q ':'; then
        echoContent red "\n ---> 未检测到当前域名的ip"
        echoContent skyBlue " ---> 请依次进行下列检查"
        echoContent yellow " --->  1.检查域名是否书写正确"
        echoContent yellow " --->  2.检查域名dns解析是否正确"
        echoContent yellow " --->  3.如解析正确，请等待dns生效，预计三分钟内生效"
        echoContent yellow " --->  4.如报Nginx启动问题，请手动启动nginx查看错误，如自己无法处理请提issues"
        echo
        echoContent skyBlue " ---> 如以上设置都正确，请重新安装纯净系统后再次尝试"

        if [[ -n ${localIP} ]]; then
            echoContent yellow " ---> 检测返回值异常，建议手动卸载nginx后重新执行脚本"
            echoContent red " ---> 异常结果：${localIP}"
        fi
        exit 1
    else
        if echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q "." || echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q ":"; then
            echoContent red "\n ---> 检测到多个ip，请确认是否关闭cloudflare的云朵"
            echoContent yellow " ---> 关闭云朵后等待三分钟后重试"
            echoContent yellow " ---> 检测到的ip如下:[${localIP}]"
            exit 1
        fi
        echoContent green " ---> 检查当前域名IP正确"
    fi
}
# 自定义email
customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
                echoContent green " ---> 添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                customSSLEmail
            fi
        fi
    fi

}
# DNS API申请证书
switchDNSAPI() {
    read -r -p "是否使用DNS API申请证书[支持NAT]？[y/n]:" dnsAPIStatus
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.cloudflare[默认]"
        echoContent yellow "2.aliyun"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectDNSAPIType
        case ${selectDNSAPIType} in
        1)
            dnsAPIType="cloudflare"
            ;;
        2)
            dnsAPIType="aliyun"
            ;;
        *)
            dnsAPIType="cloudflare"
            ;;
        esac
        initDNSAPIConfig "${dnsAPIType}"
    fi
}
# 初始化dns配置
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        echoContent yellow "\n 请在 Cloudflare 控制台为 DNS 编辑权限创建 API Token 并填入 CF_Token/CF_Account_ID。\n"
        read -r -p "请输入API Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        read -r -p "请输入Ali Key:" aliKey
        read -r -p "请输入Ali Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    fi
}
# 选择ssl安装类型
switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.letsencrypt[默认]"
        echoContent yellow "2.zerossl"
        echoContent yellow "3.buypass[不支持DNS申请]"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectSSLType
        case ${selectSSLType} in
        1)
            sslType="letsencrypt"
            ;;
        2)
            sslType="zerossl"
            ;;
        3)
            sslType="buypass"
            ;;
        *)
            sslType="letsencrypt"
            ;;
        esac
        if [[ -n "${dnsAPIType}" && "${sslType}" == "buypass" ]]; then
            echoContent red " ---> buypass不支持API申请证书"
            exit 1
        fi
        echo "${sslType}" >/etc/Proxy-agent/tls/ssl_type
    fi
}

# 选择acme安装证书方式
selectAcmeInstallSSL() {
    #    local sslIPv6=
    #    local currentIPType=
    if [[ "${ipType}" == "6" ]]; then
        sslIPv6="--listen-v6"
    fi
    #    currentIPType=$(curl -s "-${ipType}" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)

    #    if [[ -z "${currentIPType}" ]]; then
    #                currentIPType=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)
    #        if [[ -n "${currentIPType}" ]]; then
    #            sslIPv6="--listen-v6"
    #        fi
    #    fi

    acmeInstallSSL

    readAcmeTLS
}

# 安装SSL证书
acmeInstallSSL() {
    local dnsAPIDomain="${tlsDomain}"
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType}" == "cloudflare" ]]; then
        echoContent green " ---> DNS API 生成证书中"
        # 使用临时环境文件避免在进程列表中暴露API Token
        local acmeEnvFile
        acmeEnvFile=$(mktemp)
        chmod 600 "${acmeEnvFile}"
        cat > "${acmeEnvFile}" << ACME_ENV_EOF
export CF_Token="${cfAPIToken}"
ACME_ENV_EOF
        # shellcheck source=/dev/null
        sudo bash -c "source '${acmeEnvFile}' && '$HOME/.acme.sh/acme.sh' --issue -d '${dnsAPIDomain}' -d '${dnsTLSDomain}' --dns dns_cf -k ec-256 --server '${sslType}' ${sslIPv6}" 2>&1 | tee -a /etc/Proxy-agent/tls/acme.log >/dev/null
        rm -f "${acmeEnvFile}"
    elif [[ "${dnsAPIType}" == "aliyun" ]]; then
        echoContent green " --->  DNS API 生成证书中"
        # 使用临时环境文件避免在进程列表中暴露API Key/Secret
        local acmeEnvFile
        acmeEnvFile=$(mktemp)
        chmod 600 "${acmeEnvFile}"
        cat > "${acmeEnvFile}" << ACME_ENV_EOF
export Ali_Key="${aliKey}"
export Ali_Secret="${aliSecret}"
ACME_ENV_EOF
        # shellcheck source=/dev/null
        sudo bash -c "source '${acmeEnvFile}' && '$HOME/.acme.sh/acme.sh' --issue -d '${dnsAPIDomain}' -d '${dnsTLSDomain}' --dns dns_ali -k ec-256 --server '${sslType}' ${sslIPv6}" 2>&1 | tee -a /etc/Proxy-agent/tls/acme.log >/dev/null
        rm -f "${acmeEnvFile}"
    else
        echoContent green " ---> 生成证书中"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/Proxy-agent/tls/acme.log >/dev/null
    fi
}
# 自定义端口
customPortFunction() {
    local historyCustomPortStatus=
    if [[ -n "${customPort}" || -n "${currentPort}" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口？[y/n]:" historyCustomPortStatus
            if [[ "${historyCustomPortStatus}" == "y" ]]; then
                port=${currentPort}
                echoContent yellow "\n ---> 端口: ${port}"
            fi
        elif [[ -n "${lastInstallationConfig}" ]]; then
            port=${currentPort}
        fi
    fi
    if [[ -z "${currentPort}" ]] || [[ "${historyCustomPortStatus}" == "n" ]]; then
        echo

        if [[ -n "${btDomain}" ]]; then
            echoContent yellow "请输入端口[不可与BT Panel/1Panel端口相同，回车随机]"
            read -r -p "端口:" port
            if [[ -z "${port}" ]]; then
                port=$(randomNum 10000 30000)
            fi
        else
            echo
            echoContent yellow "请输入端口[默认: 443]，可自定义端口[回车使用默认]"
            read -r -p "端口:" port
            if [[ -z "${port}" ]]; then
                port=443
            fi
            if [[ "${port}" == "${xrayVLESSRealityPort}" ]]; then
                handleXray stop
            fi
        fi

        if [[ -n "${port}" ]]; then
            if ((port >= 1 && port <= 65535)); then
                allowPort "${port}"
                echoContent yellow "\n ---> 端口: ${port}"
                if [[ -z "${btDomain}" ]]; then
                    checkDNSIP "${domain}"
                    removeNginxDefaultConf
                    checkPortOpen "${port}" "${domain}"
                fi
            else
                echoContent red " ---> 端口输入错误"
                exit 1
            fi
        else
            echoContent red " ---> 端口不可为空"
            exit 1
        fi
    fi
}

# 检测端口是否占用
checkPort() {
    if [[ -n "$1" ]] && lsof -i "tcp:$1" | grep -q LISTEN; then
        echoContent red "\n ---> $1端口被占用，请手动关闭后安装\n"
        lsof -i "tcp:$1" | grep LISTEN
        exit 1
    fi
}

# 安装TLS
installTLS() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
    readAcmeTLS
    local tlsDomain=${domain}

    # 安装tls
    if [[ -f "/etc/Proxy-agent/tls/${tlsDomain}.crt" && -f "/etc/Proxy-agent/tls/${tlsDomain}.key" && -n $(cat "/etc/Proxy-agent/tls/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        echoContent green " ---> 检测到证书"
        renewalTLS

        if [[ -z $(find /etc/Proxy-agent/tls/ -name "${tlsDomain}.crt") ]] || [[ -z $(find /etc/Proxy-agent/tls/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "/etc/Proxy-agent/tls/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus}" == "true" ]]; then
                # 验证通配符证书确实存在于 acme.sh 中（目录名以字面 *. 开头）
                local wildcardCertDir wildcardCertFile
                wildcardCertDir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name '\*.'"${dnsTLSDomain}_ecc" 2>/dev/null | head -1)
                if [[ -n "${wildcardCertDir}" ]]; then
                    wildcardCertFile=$(find "${wildcardCertDir}" -maxdepth 1 -type f -name '\*.'"${dnsTLSDomain}.cer" 2>/dev/null | head -1)
                fi
                if [[ -n "${wildcardCertFile}" ]]; then
                    local wildcardDomain
                    wildcardDomain=$(basename "${wildcardCertDir}" | sed 's/_ecc$//')
                    sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${wildcardDomain}" --fullchainpath "/etc/Proxy-agent/tls/${tlsDomain}.crt" --keypath "/etc/Proxy-agent/tls/${tlsDomain}.key" --ecc >/dev/null
                else
                    echoContent red " ---> 未找到有效的通配符证书，将尝试申请新证书"
                    installedDNSAPIStatus=""
                    rm -rf /etc/Proxy-agent/tls/*
                    installTLS "$1"
                    return
                fi
            else
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/Proxy-agent/tls/${tlsDomain}.crt" --keypath "/etc/Proxy-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
                    read -r -p "是否重新安装？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        rm -rf /etc/Proxy-agent/tls/*
                        installTLS "$1"
                    fi
                fi
            fi
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI
        if [[ -z "${dnsAPIType}" ]]; then
            echoContent yellow "\n ---> 不采用API申请证书"
            echoContent green " ---> 安装TLS证书，需要依赖80端口"
            allowPort 80
        fi

        switchSSLType
        customSSLEmail
        selectAcmeInstallSSL

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            # 从实际目录名获取正确的证书域名
            local wildcardCertDir
            wildcardCertDir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name '\*.'"${dnsTLSDomain}_ecc" 2>/dev/null | head -1)
            if [[ -n "${wildcardCertDir}" ]]; then
                local wildcardDomain
                wildcardDomain=$(basename "${wildcardCertDir}" | sed 's/_ecc$//')
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${wildcardDomain}" --fullchainpath "/etc/Proxy-agent/tls/${tlsDomain}.crt" --keypath "/etc/Proxy-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            else
                echoContent red " ---> 通配符证书目录不存在"
            fi
        else
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/Proxy-agent/tls/${tlsDomain}.crt" --keypath "/etc/Proxy-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        fi

        if [[ ! -f "/etc/Proxy-agent/tls/${tlsDomain}.crt" || ! -f "/etc/Proxy-agent/tls/${tlsDomain}.key" ]] || [[ -z $(cat "/etc/Proxy-agent/tls/${tlsDomain}.key") || -z $(cat "/etc/Proxy-agent/tls/${tlsDomain}.crt") ]]; then
            tail -n 10 /etc/Proxy-agent/tls/acme.log
            if [[ ${installTLSCount} == "1" ]]; then
                echoContent red " ---> TLS安装失败，请检查acme日志"
                echoContent yellow "     日志文件: /etc/Proxy-agent/tls/acme.log"
                exit 1
            fi

            installTLSCount=1
            echo

            if tail -n 10 /etc/Proxy-agent/tls/acme.log | grep -q "Could not validate email address as valid"; then
                echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
                echo
                customSSLEmail "validate email"
                installTLS "$1"
            else
                installTLS "$1"
            fi
        fi

        # 验证证书与私钥匹配
        echoContent green " ---> 验证证书与私钥..."
        if ! verifyCertKeyMatch "/etc/Proxy-agent/tls/${tlsDomain}.crt" "/etc/Proxy-agent/tls/${tlsDomain}.key"; then
            echoContent red " ---> 证书验证失败，请检查证书文件"
            exit 1
        fi

        # 验证证书有效期
        verifyCertExpiry "/etc/Proxy-agent/tls/${tlsDomain}.crt"

        echoContent green " ---> TLS生成成功"
    else
        echoContent yellow " ---> 未安装acme.sh"
        exit 1
    fi
}

# 初始化随机字符串 - 使用更安全的随机源
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    local charLen=${#chars}
    for i in {1..4}; do
        local idx
        idx=$(randomNum 0 $((charLen - 1)))
        initCustomPath+="${chars:idx:1}"
    done
    customPath=${initCustomPath}
}

# 自定义/随机路径
randomPathFunction() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"
    else
        echoContent skyBlue "生成随机路径"
    fi

    if [[ -n "${currentPath}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
        echo
    elif [[ -n "${currentPath}" && -n "${lastInstallationConfig}" ]]; then
        historyPathStatus="y"
    fi

    if [[ "${historyPathStatus}" == "y" ]]; then
        customPath=${currentPath}
        echoContent green " ---> 使用成功\n"
    else
        echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
        read -r -p '路径:' customPath
        if [[ -z "${customPath}" ]]; then
            initRandomPath
            currentPath=${customPath}
        else
            if [[ "${customPath: -2}" == "ws" ]]; then
                echo
                echoContent red " ---> 自定义path结尾不可用ws结尾，否则无法区分分流路径"
                randomPathFunction "$1"
            else
                currentPath=${customPath}
            fi
        fi
    fi
    echoContent yellow "\n path:${currentPath}"
    echoContent skyBlue "\n----------------------------"
}
# 随机数 - 使用更安全的随机源
# 用法: randomNum min max
randomNum() {
    local min="${1:-0}"
    local max="${2:-65535}"
    local range=$((max - min + 1))

    # 优先使用 /dev/urandom（更安全）
    if [[ -r /dev/urandom ]]; then
        local random_bytes
        random_bytes=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
        echo $((random_bytes % range + min))
    # 回退到 shuf（如果可用，常见于 Alpine）
    elif command -v shuf &>/dev/null; then
        shuf -i "${min}-${max}" -n 1
    # 最后回退到 $RANDOM
    else
        echo $((RANDOM % range + min))
    fi
}
# Nginx伪装博客
nginxBlog() {
    if [[ -n "$1" ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加伪装站点"
    else
        echoContent yellow "\n开始添加伪装站点"
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "检测到安装伪装站点，是否需要重新安装[y/n]:" nginxBlogInstallStatus
        else
            nginxBlogInstallStatus="n"
        fi

        if [[ "${nginxBlogInstallStatus}" == "y" ]]; then
            rm -rf "${nginxStaticPath}*"
            #  randomNum=$((RANDOM % 6 + 1))
            randomNum=$(randomNum 1 9)
            if [[ "${release}" == "alpine" ]]; then
                wget -q -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${randomNum}.zip"
            else
                wget -q "${wgetShowProgressStatus}" -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${randomNum}.zip"
            fi

            unzip -o "${nginxStaticPath}html${randomNum}.zip" -d "${nginxStaticPath}" >/dev/null
            rm -f "${nginxStaticPath}html${randomNum}.zip*"
            echoContent green " ---> 添加伪装站点成功"
        fi
    else
        randomNum=$(randomNum 1 9)
        #        randomNum=$((RANDOM % 6 + 1))
        rm -rf "${nginxStaticPath}*"

        if [[ "${release}" == "alpine" ]]; then
            wget -q -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${randomNum}.zip"
        else
            wget -q "${wgetShowProgressStatus}" -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${randomNum}.zip"
        fi

        unzip -o "${nginxStaticPath}html${randomNum}.zip" -d "${nginxStaticPath}" >/dev/null
        rm -f "${nginxStaticPath}html${randomNum}.zip*"
        echoContent green " ---> 添加伪装站点成功"
    fi

}

# 修改http_port_t端口
updateSELinuxHTTPPortT() {

    $(find /usr/bin /usr/sbin | grep -w journalctl) -xe >/etc/Proxy-agent/nginx_error.log 2>&1

    if find /usr/bin /usr/sbin | grep -q -w semanage && find /usr/bin /usr/sbin | grep -q -w getenforce && grep -E "31300|31302" </etc/Proxy-agent/nginx_error.log | grep -q "Permission denied"; then
        echoContent red " ---> 检查SELinux端口是否开放"
        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31300; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31300
            echoContent green " ---> http_port_t 31300 端口开放成功"
        fi

        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31302; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31302
            echoContent green " ---> http_port_t 31302 端口开放成功"
        fi
        handleNginx start

    else
        exit 0
    fi
}

# 操作Nginx
handleNginx() {

    if ! echo "${selectCustomInstallType}" | grep -qwE ",7,|,8,|,7,8," && [[ -z $(pgrep -f "nginx") ]] && [[ "$1" == "start" ]]; then
        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx start 2>/etc/Proxy-agent/nginx_error.log
        else
            systemctl start nginx 2>/etc/Proxy-agent/nginx_error.log
        fi

        sleep 0.5

        if [[ -z $(pgrep -f "nginx") ]]; then
            echoContent red " ---> Nginx启动失败"
            echoContent red " ---> 请将下方日志反馈给开发者"
            nginx
            if grep -q "journalctl -xe" </etc/Proxy-agent/nginx_error.log; then
                updateSELinuxHTTPPortT
            fi
        else
            echoContent green " ---> Nginx启动成功"
        fi

    elif [[ -n $(pgrep -f "nginx") ]] && [[ "$1" == "stop" ]]; then

        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx stop
        else
            systemctl stop nginx
        fi
        sleep 0.5

        if [[ -z ${btDomain} && -n $(pgrep -f "nginx") ]]; then
            pgrep -f "nginx" | xargs kill -9
        fi
        echoContent green " ---> Nginx关闭成功"
    fi
}

# 定时任务更新tls证书
installCronTLS() {
    if [[ -z "${btDomain}" ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加定时维护证书"
        crontab -l >/etc/Proxy-agent/backup_crontab.cron
        local historyCrontab
        historyCrontab=$(sed '/v2ray-agent/d;/Proxy-agent/d;/acme.sh/d' /etc/Proxy-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/Proxy-agent/backup_crontab.cron
        echo "30 1 * * * /bin/bash /etc/Proxy-agent/install.sh RenewTLS >> /etc/Proxy-agent/crontab_tls.log 2>&1" >>/etc/Proxy-agent/backup_crontab.cron
        crontab /etc/Proxy-agent/backup_crontab.cron
        echoContent green "\n ---> 添加定时维护证书成功"
    fi
}
# 定时任务更新geo文件
installCronUpdateGeo() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if crontab -l | grep -q "UpdateGeo"; then
            echoContent red "\n ---> 已添加自动更新定时任务，请不要重复添加"
            exit 1
        fi
        echoContent skyBlue "\n进度 1/1 : 添加定时更新geo文件"
        crontab -l >/etc/Proxy-agent/backup_crontab.cron
        echo "35 1 * * * /bin/bash /etc/Proxy-agent/install.sh UpdateGeo >> /etc/Proxy-agent/crontab_tls.log 2>&1" >>/etc/Proxy-agent/backup_crontab.cron
        crontab /etc/Proxy-agent/backup_crontab.cron
        echoContent green "\n ---> 添加定时更新geo文件成功"
    fi
}

# 更新证书
renewalTLS() {

    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/1 : 更新证书"
    fi
    readAcmeTLS
    local domain=${currentHost}
    if [[ -z "${currentHost}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi

    if [[ -f "/etc/Proxy-agent/tls/ssl_type" ]]; then
        if grep -q "buypass" <"/etc/Proxy-agent/tls/ssl_type"; then
            sslRenewalDays=180
        fi
    fi
    if [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        modifyTime=

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            # 使用 find 获取通配符证书文件路径，避免 glob 在引号中不展开的问题
            local wildcardCertFile
            wildcardCertFile=$(find "$HOME/.acme.sh" -path '*/\*.'"${dnsTLSDomain}_ecc"'/\*.'"${dnsTLSDomain}.cer" -type f 2>/dev/null | head -1)
            if [[ -n "${wildcardCertFile}" ]]; then
                modifyTime=$(stat --format=%z "${wildcardCertFile}")
            else
                echoContent red " ---> 未找到通配符证书文件"
                return 1
            fi
        else
            modifyTime=$(stat --format=%z "$HOME/.acme.sh/${domain}_ecc/${domain}.cer")
        fi

        modifyTime=$(date +%s -d "${modifyTime}")
        currentTime=$(date +%s)
        ((stampDiff = currentTime - modifyTime))
        ((days = stampDiff / 86400))
        ((remainingDays = sslRenewalDays - days))

        tlsStatus=${remainingDays}
        if [[ ${remainingDays} -le 0 ]]; then
            tlsStatus="已过期"
        fi

        echoContent skyBlue " ---> 证书检查日期:$(date "+%F %H:%M:%S")"
        echoContent skyBlue " ---> 证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")"
        echoContent skyBlue " ---> 证书生成天数:${days}"
        echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}
        echoContent skyBlue " ---> 证书过期前最后一天自动更新，如更新失败请手动更新"

        if [[ ${remainingDays} -le 1 ]]; then
            echoContent yellow " ---> 重新生成证书"
            handleNginx stop

            if [[ "${coreInstallType}" == "1" ]]; then
                handleXray stop
            elif [[ "${coreInstallType}" == "2" ]]; then
                handleSingBox stop
            fi

            sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${domain}" --fullchainpath /etc/Proxy-agent/tls/"${domain}.crt" --keypath /etc/Proxy-agent/tls/"${domain}.key" --ecc
            reloadCore
            handleNginx start
        else
            echoContent green " ---> 证书有效"
        fi
    elif [[ -f "/etc/Proxy-agent/tls/${tlsDomain}.crt" && -f "/etc/Proxy-agent/tls/${tlsDomain}.key" && -n $(cat "/etc/Proxy-agent/tls/${tlsDomain}.crt") ]]; then
        echoContent yellow " ---> 检测到使用自定义证书，无法执行renew操作。"
    else
        echoContent red " ---> 未安装"
    fi
}

# 安装 sing-box
installSingBox() {
    readInstallType
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装sing-box"

    if [[ ! -f "/etc/Proxy-agent/sing-box/sing-box" ]]; then

        version=$(curl -s --connect-timeout 10 "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        # 检查版本获取是否成功
        if [[ -z "${version}" ]]; then
            echoContent red " ---> 获取 sing-box 版本失败，请检查网络连接或 GitHub API 访问"
            echoContent yellow "     可能原因: 网络超时、GitHub API 限流、DNS 解析失败"
            read -r -p "是否重新尝试？[y/n]" retryStatus
            if [[ "${retryStatus}" == "y" ]]; then
                installSingBox "$1"
            fi
            return 1
        fi

        echoContent green " ---> 最新版本:${version}"

        local singBoxTarFile="/etc/Proxy-agent/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"
        local singBoxChecksumFile="/etc/Proxy-agent/sing-box/sing-box_${version/v/}_checksums.txt"
        local singBoxTarFileName="sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"

        # 下载sing-box核心文件和校验和文件
        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P /etc/Proxy-agent/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/${singBoxTarFileName}"
            wget -c -q -P /etc/Proxy-agent/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box_${version/v/}_checksums.txt"
        else
            wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/${singBoxTarFileName}"
            wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box_${version/v/}_checksums.txt"
        fi

        if [[ ! -f "${singBoxTarFile}" ]]; then
            read -r -p "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installSingBox "$1"
            fi
        else
            # 校验SHA256
            local expectedHash
            expectedHash=$(extractSingBoxHash "${singBoxChecksumFile}" "${singBoxTarFileName}")
            if [[ -n "${expectedHash}" ]]; then
                echoContent green " ---> 验证文件完整性..."
                if ! verifySHA256 "${singBoxTarFile}" "${expectedHash}"; then
                    echoContent red " ---> 文件校验失败，可能已被篡改，请重新下载"
                    rm -f "${singBoxTarFile}" "${singBoxChecksumFile}"
                    read -r -p "是否重新尝试？[y/n]" retryStatus
                    if [[ "${retryStatus}" == "y" ]]; then
                        installSingBox "$1"
                    fi
                    return 1
                fi
                echoContent green " ---> 文件校验通过"
            else
                echoContent yellow " ---> 警告: 未能获取校验信息，跳过完整性验证"
            fi

            tar zxvf "${singBoxTarFile}" -C "/etc/Proxy-agent/sing-box/" >/dev/null 2>&1

            mv "/etc/Proxy-agent/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}/sing-box" /etc/Proxy-agent/sing-box/sing-box
            rm -rf /etc/Proxy-agent/sing-box/sing-box-*
            chmod 655 /etc/Proxy-agent/sing-box/sing-box
        fi
    else
        echoContent green " ---> 当前版本:v$(/etc/Proxy-agent/sing-box/sing-box version | grep "sing-box version" | awk '{print $3}')"

        version=$(curl -s --connect-timeout 10 "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        if [[ -n "${version}" ]]; then
            echoContent green " ---> 最新版本:${version}"
        else
            echoContent yellow " ---> 无法获取最新版本信息"
        fi

        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "是否更新、升级？[y/n]:" reInstallSingBoxStatus
            if [[ "${reInstallSingBoxStatus}" == "y" ]]; then
                rm -f /etc/Proxy-agent/sing-box/sing-box
                installSingBox "$1"
            fi
        fi
    fi

}

# 检查wget showProgress
checkWgetShowProgress() {
    if [[ "${release}" != "alpine" ]]; then
        if find /usr/bin /usr/sbin | grep -q "/wget" && wget --help | grep -q show-progress; then
            wgetShowProgressStatus="--show-progress"
        fi
    fi
}
# 安装xray
installXray() {
    readInstallType
    local prereleaseStatus=false
    if [[ "$2" == "true" ]]; then
        prereleaseStatus=true
    fi

    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"

    if [[ ! -f "/etc/Proxy-agent/xray/xray" ]]; then

        version=$(curl -s --connect-timeout 10 "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        # 检查版本获取是否成功
        if [[ -z "${version}" ]]; then
            echoContent red " ---> 获取 Xray-core 版本失败，请检查网络连接或 GitHub API 访问"
            echoContent yellow "     可能原因: 网络超时、GitHub API 限流、DNS 解析失败"
            read -r -p "是否重新尝试？[y/n]" retryStatus
            if [[ "${retryStatus}" == "y" ]]; then
                installXray "$1" "$2"
            fi
            return 1
        fi

        echoContent green " ---> Xray-core版本:${version}"

        local xrayZipFile="/etc/Proxy-agent/xray/${xrayCoreCPUVendor}.zip"
        local xrayDgstFile="/etc/Proxy-agent/xray/${xrayCoreCPUVendor}.zip.dgst"

        # 下载Xray核心文件
        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P /etc/Proxy-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
            wget -c -q -P /etc/Proxy-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip.dgst"
        else
            wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
            wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip.dgst"
        fi

        if [[ ! -f "${xrayZipFile}" ]]; then
            read -r -p "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installXray "$1"
            fi
        else
            # 校验SHA256
            local expectedHash
            expectedHash=$(extractXrayHash "${xrayDgstFile}")
            if [[ -n "${expectedHash}" ]]; then
                echoContent green " ---> 验证文件完整性..."
                if ! verifySHA256 "${xrayZipFile}" "${expectedHash}"; then
                    echoContent red " ---> 文件校验失败，可能已被篡改，请重新下载"
                    rm -f "${xrayZipFile}" "${xrayDgstFile}"
                    read -r -p "是否重新尝试？[y/n]" retryStatus
                    if [[ "${retryStatus}" == "y" ]]; then
                        installXray "$1" "$2"
                    fi
                    return 1
                fi
                echoContent green " ---> 文件校验通过"
            else
                echoContent yellow " ---> 警告: 未能获取校验信息，跳过完整性验证"
            fi

            unzip -o "${xrayZipFile}" -d /etc/Proxy-agent/xray >/dev/null
            rm -f "${xrayZipFile}" "${xrayDgstFile}"

            version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1 | jq -r '.[]|.tag_name')
            echoContent skyBlue "------------------------Version-------------------------------"
            echo "version:${version}"
            rm /etc/Proxy-agent/xray/geo* >/dev/null 2>&1

            if [[ "${release}" == "alpine" ]]; then
                wget -c -q -P /etc/Proxy-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
                wget -c -q -P /etc/Proxy-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
            else
                wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
                wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
            fi

            chmod 655 /etc/Proxy-agent/xray/xray
        fi
    else
        if [[ -z "${lastInstallationConfig}" ]]; then
            echoContent green " ---> Xray-core版本:$(/etc/Proxy-agent/xray/xray --version | awk '{print $2}' | head -1)"
            read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                rm -f /etc/Proxy-agent/xray/xray
                installXray "$1" "$2"
            fi
        fi
    fi
}

# xray版本管理
xrayVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 1
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.更新geosite、geoip"
    echoContent yellow "8.设置自动更新geo文件[每天凌晨更新]"
    echoContent yellow "9.查看日志"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectXrayType
    if [[ "${selectXrayType}" == "1" ]]; then
        prereleaseStatus=false
        updateXray
    elif [[ "${selectXrayType}" == "2" ]]; then
        prereleaseStatus=true
        updateXray
    elif [[ "${selectXrayType}" == "3" ]]; then
        echoContent yellow "\n1.只可以回退最近的五个版本"
        echoContent yellow "2.不保证回退后一定可以正常使用"
        echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==false)|.tag_name" | awk '{print ""NR""":"$0}'
        echoContent skyBlue "--------------------------------------------------------------"
        read -r -p "请输入要回退的版本:" selectXrayVersionType
        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==false)|.tag_name" | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
        if [[ -n "${version}" ]]; then
            updateXray "${version}"
        else
            echoContent red "\n ---> 输入有误，请重新输入"
            xrayVersionManageMenu 1
        fi
    elif [[ "${selectXrayType}" == "4" ]]; then
        handleXray stop
    elif [[ "${selectXrayType}" == "5" ]]; then
        handleXray start
    elif [[ "${selectXrayType}" == "6" ]]; then
        reloadCore
    elif [[ "${selectXrayType}" == "7" ]]; then
        updateGeoSite
    elif [[ "${selectXrayType}" == "8" ]]; then
        installCronUpdateGeo
    elif [[ "${selectXrayType}" == "9" ]]; then
        checkLog 1
    fi
}

# 更新 geosite
updateGeoSite() {
    echoContent yellow "\n来源 https://github.com/Loyalsoldier/v2ray-rules-dat"

    version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1 | jq -r '.[]|.tag_name')
    echoContent skyBlue "------------------------Version-------------------------------"
    echo "version:${version}"
    rm ${configPath}../geo* >/dev/null

    if [[ "${release}" == "alpine" ]]; then
        wget -c -q -P ${configPath}../ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
        wget -c -q -P ${configPath}../ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
    else
        wget -c -q "${wgetShowProgressStatus}" -P ${configPath}../ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
        wget -c -q "${wgetShowProgressStatus}" -P ${configPath}../ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
    fi

    reloadCore
    echoContent green " ---> 更新完毕"

}

# 更新Xray
updateXray() {
    readInstallType

    if [[ -z "${coreInstallType}" || "${coreInstallType}" != "1" ]]; then
        if [[ -n "$1" ]]; then
            version=$1
        else
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        fi

        echoContent green " ---> Xray-core版本:${version}"

        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P /etc/Proxy-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -q "${wgetShowProgressStatus}" -P /etc/Proxy-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        fi

        unzip -o "/etc/Proxy-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/Proxy-agent/xray >/dev/null
        rm -rf "/etc/Proxy-agent/xray/${xrayCoreCPUVendor}.zip"
        chmod 655 /etc/Proxy-agent/xray/xray
        handleXray stop
        handleXray start
    else
        echoContent green " ---> 当前版本:v$(/etc/Proxy-agent/xray/xray --version | awk '{print $2}' | head -1)"
        remoteVersion=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        echoContent green " ---> 最新版本:${remoteVersion}"

        if [[ -n "$1" ]]; then
            version=$1
        else
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=10" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        fi

        if [[ -n "$1" ]]; then
            read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" == "y" ]]; then
                echoContent green " ---> 当前Xray-core版本:$(/etc/Proxy-agent/xray/xray --version | awk '{print $2}' | head -1)"

                handleXray stop
                rm -f /etc/Proxy-agent/xray/xray
                updateXray "${version}"
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" == "v$(/etc/Proxy-agent/xray/xray --version | awk '{print $2}' | head -1)" ]]; then
            read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                handleXray stop
                rm -f /etc/Proxy-agent/xray/xray
                updateXray
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
            if [[ "${installXrayStatus}" == "y" ]]; then
                rm /etc/Proxy-agent/xray/xray
                updateXray
            else
                echoContent green " ---> 放弃更新"
            fi

        fi
    fi
}

# 验证整个服务是否可用
checkGFWStatue() {
    readInstallType
    echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ "${coreInstallType}" == "1" ]] && [[ -n $(pgrep -f "xray/xray") ]]; then
        echoContent green " ---> 服务启动成功"
    elif [[ "${coreInstallType}" == "2" ]] && [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
        echoContent green " ---> 服务启动成功"
    else
        echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
        exit 1
    fi
}

# 安装alpine开机启动
installAlpineStartup() {
    local serviceName=$1
    if [[ "${serviceName}" == "sing-box" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="sing-box service"
command="/etc/Proxy-agent/sing-box/sing-box"
command_args="run -c /etc/Proxy-agent/sing-box/conf/config.json"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF
    elif [[ "${serviceName}" == "xray" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="xray service"
command="/etc/Proxy-agent/xray/xray"
command_args="run -confdir /etc/Proxy-agent/xray/conf"
command_background=true
pidfile="/var/run/xray.pid"
EOF
    fi

    chmod +x "/etc/init.d/${serviceName}"
}

# sing-box开机自启
installSingBoxService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置sing-box开机自启"
    execStart='/etc/Proxy-agent/sing-box/sing-box run -c /etc/Proxy-agent/sing-box/conf/config.json'

    if [[ -n $(find /bin /usr/bin -name "systemctl") && "${release}" != "alpine" ]]; then
        rm -rf /etc/systemd/system/sing-box.service
        touch /etc/systemd/system/sing-box.service
        cat <<EOF >/etc/systemd/system/sing-box.service
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${execStart}
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        bootStartup "sing-box.service"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "sing-box"
        bootStartup "sing-box"
    fi

    echoContent green " ---> 配置sing-box开机启动完毕"
}

# Xray开机自启
installXrayService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    execStart='/etc/Proxy-agent/xray/xray run -confdir /etc/Proxy-agent/xray/conf'
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        touch /etc/systemd/system/xray.service
        cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=infinity
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        bootStartup "xray.service"
        echoContent green " ---> 配置Xray开机自启成功"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "xray"
        bootStartup "xray"
    fi
}

# 操作Hysteria
handleHysteria() {
    local startResult=0

    # shellcheck disable=SC2010
    if find /bin /usr/bin | grep -q systemctl && ls /etc/systemd/system/ | grep -q hysteria.service; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "start" ]]; then
            systemctl start hysteria.service || startResult=$?
        elif [[ -n $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop hysteria.service
        fi
    fi
    sleep 1.5

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "hysteria/hysteria") ]]; then
            echoContent green " ---> Hysteria启动成功"
        else
            echoContent red "Hysteria启动失败 (systemctl 返回码: ${startResult})"
            if [[ -f "/etc/systemd/system/hysteria.service" ]]; then
                echoContent yellow "\n ---> systemd 服务状态:"
                systemctl status hysteria.service --no-pager -l 2>&1 | head -20
            fi
            echoContent yellow "\n请手动执行【/etc/Proxy-agent/hysteria/hysteria --log-level debug -c /etc/Proxy-agent/hysteria/conf/config.json server】查看详细错误日志"
            exit 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]]; then
            echoContent green " ---> Hysteria关闭成功"
        else
            echoContent red "Hysteria关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep hysteria|awk '{print \$2}'|xargs kill -9】"
            exit 1
        fi
    fi
}

# 操作sing-box
handleSingBox() {
    local startResult=0
    local mergeResult=0

    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        if [[ -z $(pgrep -f "sing-box") ]] && [[ "$1" == "start" ]]; then
            singBoxMergeConfig || mergeResult=$?
            if [[ ${mergeResult} -ne 0 ]]; then
                echoContent red " ---> sing-box 配置合并失败，无法启动服务"
                exit 1
            fi
            systemctl start sing-box.service || startResult=$?
        elif [[ -n $(pgrep -f "sing-box") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop sing-box.service
        fi
    elif [[ -f "/etc/init.d/sing-box" ]]; then
        if [[ -z $(pgrep -f "sing-box") ]] && [[ "$1" == "start" ]]; then
            singBoxMergeConfig || mergeResult=$?
            if [[ ${mergeResult} -ne 0 ]]; then
                echoContent red " ---> sing-box 配置合并失败，无法启动服务"
                exit 1
            fi
            rc-service sing-box start || startResult=$?
        elif [[ -n $(pgrep -f "sing-box") ]] && [[ "$1" == "stop" ]]; then
            rc-service sing-box stop
        fi
    fi
    sleep 1.5

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "sing-box") ]]; then
            echoContent green " ---> sing-box启动成功"
        else
            echoContent red "sing-box启动失败 (systemctl 返回码: ${startResult})"
            # 显示 systemd 服务状态以帮助诊断
            if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
                echoContent yellow "\n ---> systemd 服务状态:"
                systemctl status sing-box.service --no-pager -l 2>&1 | head -20
                echoContent yellow "\n ---> 最近日志:"
                journalctl -u sing-box.service --no-pager -n 15 2>/dev/null || true
            fi
            echoContent yellow "\n请手动执行【 /etc/Proxy-agent/sing-box/sing-box run -c /etc/Proxy-agent/sing-box/conf/config.json 】，查看详细错误日志"
            exit 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "sing-box") ]]; then
            echoContent green " ---> sing-box关闭成功"
        else
            echoContent red " ---> sing-box关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep sing-box|awk '{print \$2}'|xargs kill -9】"
            exit 1
        fi
    fi
}

# 操作xray
handleXray() {
    local startResult=0

    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            systemctl start xray.service || startResult=$?
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -f "/etc/init.d/xray" ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            rc-service xray start || startResult=$?
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            rc-service xray stop
        fi
    fi

    sleep 1.5

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "xray/xray") ]]; then
            echoContent green " ---> Xray启动成功"
        else
            echoContent red "Xray启动失败 (systemctl 返回码: ${startResult})"
            # 显示 systemd 服务状态以帮助诊断
            if [[ -f "/etc/systemd/system/xray.service" ]]; then
                echoContent yellow "\n ---> systemd 服务状态:"
                systemctl status xray.service --no-pager -l 2>&1 | head -20
                echoContent yellow "\n ---> 最近日志:"
                journalctl -u xray.service --no-pager -n 15 2>/dev/null || true
            fi
            echoContent yellow "\n请手动执行【/etc/Proxy-agent/xray/xray -confdir /etc/Proxy-agent/xray/conf】查看详细错误日志"
            exit 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]]; then
            echoContent green " ---> Xray关闭成功"
        else
            echoContent red "Xray关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
            exit 1
        fi
    fi
}

# 读取Xray用户数据并初始化
initXrayClients() {
    local type=",$1,"
    local newUUID=$2
    local newEmail=$3
    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${newEmail}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .id//.uuid)
        email=$(echo "${user}" | jq -r .email//.name | awk -F "[-]" '{print $1}')
        currentUser=
        if echo "${type}" | grep -q "0"; then
            currentUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${email}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS WS
        if echo "${type}" | grep -q ",1,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS XHTTP
        if echo "${type}" | grep -q ",12,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_Reality_XHTTP\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # trojan grpc
        if echo "${type}" | grep -q ",2,"; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-Trojan_gRPC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess WS
        if echo "${type}" | grep -q ",3,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VMess_WS\",\"alterId\": 0}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # trojan tcp
        if echo "${type}" | grep -q ",4,"; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-trojan_tcp\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless grpc
        if echo "${type}" | grep -q ",5,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_grpc\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # hysteria
        if echo "${type}" | grep -q ",6,"; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${email}-singbox_hysteria2\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless reality vision
        if echo "${type}" | grep -q ",7,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_vision\",\"flow\":\"xtls-rprx-vision\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless reality grpc
        if echo "${type}" | grep -q ",8,"; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_grpc\",\"flow\":\"\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # tuic
        if echo "${type}" | grep -q ",9,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"password\":\"${uuid}\",\"name\":\"${email}-singbox_tuic\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}
# 读取singbox用户数据并初始化
initSingBoxClients() {
    local type=",$1,"
    local newUUID=$2
    local newName=$3

    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"uuid\":\"${newUUID}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${newName}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .uuid//.id//.password)
        name=$(echo "${user}" | jq -r .name//.email//.username | awk -F "[-]" '{print $1}')
        currentUser=
        # VLESS Vision
        if echo "${type}" | grep -q ",0,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${name}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS WS
        if echo "${type}" | grep -q ",1,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess ws
        if echo "${type}" | grep -q ",3,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VMess_WS\",\"alterId\": 0}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # trojan
        if echo "${type}" | grep -q ",4,"; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-Trojan_TCP\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS Reality Vision
        if echo "${type}" | grep -q ",7,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${name}-VLESS_Reality_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS Reality gRPC
        if echo "${type}" | grep -q ",8,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VLESS_Reality_gPRC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # hysteria2
        if echo "${type}" | grep -q ",6,"; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-singbox_hysteria2\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # tuic
        if echo "${type}" | grep -q ",9,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"password\":\"${uuid}\",\"name\":\"${name}-singbox_tuic\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # naive
        if echo "${type}" | grep -q ",10,"; then
            currentUser="{\"password\":\"${uuid}\",\"username\":\"${name}-singbox_naive\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess HTTPUpgrade
        if echo "${type}" | grep -q ",11,"; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VMess_HTTPUpgrade\",\"alterId\": 0}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # anytls
        if echo "${type}" | grep -q ",13,"; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-anytls\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # Shadowsocks 2022
        if echo "${type}" | grep -q ",14,"; then
            # 使用UUID的前16字节进行base64编码作为用户密钥
            local ss2022UserKey
            ss2022UserKey=$(echo -n "${uuid}" | head -c 16 | base64)
            currentUser="{\"password\":\"${ss2022UserKey}\",\"name\":\"${name}-SS2022\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        if echo "${type}" | grep -q ",20,"; then
            currentUser="{\"username\":\"${uuid}\",\"password\":\"${uuid}\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}

# 初始化hysteria端口
initHysteriaPort() {
    readSingBoxConfig
    if [[ -n "${hysteriaPort}" ]]; then
        read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口？[y/n]:" historyHysteriaPortStatus
        if [[ "${historyHysteriaPortStatus}" == "y" ]]; then
            echoContent yellow "\n ---> 端口: ${hysteriaPort}"
        else
            hysteriaPort=
        fi
    fi

    if [[ -z "${hysteriaPort}" ]]; then
        echoContent yellow "请输入Hysteria端口[回车随机10000-30000]，不可与其他服务重复"
        read -r -p "端口:" hysteriaPort
        if [[ -z "${hysteriaPort}" ]]; then
            hysteriaPort=$(randomNum 10000 30000)
        fi
    fi
    if [[ -z ${hysteriaPort} ]]; then
        echoContent red " ---> 端口不可为空"
        initHysteriaPort "$2"
    elif ((hysteriaPort < 1 || hysteriaPort > 65535)); then
        echoContent red " ---> 端口不合法"
        initHysteriaPort "$2"
    fi
    allowPort "${hysteriaPort}"
    allowPort "${hysteriaPort}" "udp"
}

# 初始化hysteria网络信息
initHysteria2Network() {

    echoContent yellow "请输入本地带宽峰值的下行速度（默认：100，单位：Mbps）"
    read -r -p "下行速度:" hysteria2ClientDownloadSpeed
    if [[ -z "${hysteria2ClientDownloadSpeed}" ]]; then
        hysteria2ClientDownloadSpeed=100
        echoContent green "\n ---> 下行速度: ${hysteria2ClientDownloadSpeed}\n"
    fi

    echoContent yellow "请输入本地带宽峰值的上行速度（默认：50，单位：Mbps）"
    read -r -p "上行速度:" hysteria2ClientUploadSpeed
    if [[ -z "${hysteria2ClientUploadSpeed}" ]]; then
        hysteria2ClientUploadSpeed=50
        echoContent green "\n ---> 上行速度: ${hysteria2ClientUploadSpeed}\n"
    fi

    echoContent yellow "是否启用混淆(obfs)? 留空不启用，输入密码则启用salamander混淆"
    read -r -p "混淆密码(留空不启用):" hysteria2ObfsPassword
    if [[ -n "${hysteria2ObfsPassword}" ]]; then
        echoContent green "\n ---> 混淆已启用\n"
    else
        echoContent green "\n ---> 混淆未启用\n"
    fi
}

# 初始化 Shadowsocks 2022 配置
initSS2022Config() {
    # 读取现有配置
    if [[ -f "${singBoxConfigPath}14_ss2022_inbounds.json" ]]; then
        ss2022Port=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}14_ss2022_inbounds.json")
        ss2022ServerKey=$(jq -r '.inbounds[0].password' "${singBoxConfigPath}14_ss2022_inbounds.json")
        ss2022Method=$(jq -r '.inbounds[0].method' "${singBoxConfigPath}14_ss2022_inbounds.json")
    fi

    if [[ -n "${ss2022Port}" ]]; then
        read -r -p "读取到上次安装时的端口 ${ss2022Port}，是否使用？[y/n]:" historySS2022PortStatus
        if [[ "${historySS2022PortStatus}" != "y" ]]; then
            ss2022Port=
            ss2022ServerKey=
        fi
    fi

    if [[ -z "${ss2022Port}" ]]; then
        echoContent yellow "请输入Shadowsocks 2022端口[回车随机10000-30000]"
        read -r -p "端口:" ss2022Port
        if [[ -z "${ss2022Port}" ]]; then
            ss2022Port=$(randomNum 10000 30000)
        fi
        echoContent green "\n ---> 端口: ${ss2022Port}"
    fi

    # 选择加密方式
    if [[ -z "${ss2022Method}" ]]; then
        echoContent yellow "\n请选择加密方式:"
        echoContent yellow "1.2022-blake3-aes-128-gcm [推荐，密钥较短]"
        echoContent yellow "2.2022-blake3-aes-256-gcm"
        echoContent yellow "3.2022-blake3-chacha20-poly1305"
        read -r -p "请选择[默认1]:" ss2022MethodChoice
        case ${ss2022MethodChoice} in
        2)
            ss2022Method="2022-blake3-aes-256-gcm"
            ss2022KeyLen=32
            ;;
        3)
            ss2022Method="2022-blake3-chacha20-poly1305"
            ss2022KeyLen=32
            ;;
        *)
            ss2022Method="2022-blake3-aes-128-gcm"
            ss2022KeyLen=16
            ;;
        esac
        echoContent green "\n ---> 加密方式: ${ss2022Method}"
    else
        if [[ "${ss2022Method}" == "2022-blake3-aes-128-gcm" ]]; then
            ss2022KeyLen=16
        else
            ss2022KeyLen=32
        fi
    fi

    # 生成服务器密钥
    if [[ -z "${ss2022ServerKey}" ]]; then
        ss2022ServerKey=$(openssl rand -base64 ${ss2022KeyLen})
        echoContent green " ---> 服务器密钥已自动生成"
    fi
}

# firewalld设置端口跳跃
addFirewalldPortHopping() {

    local start=$1
    local end=$2
    local targetPort=$3
    for port in $(seq "$start" "$end"); do
        sudo firewall-cmd --permanent --add-forward-port=port="${port}":proto=udp:toport="${targetPort}"
    done
    sudo firewall-cmd --reload
}

# 端口跳跃
addPortHopping() {
    local type=$1
    local targetPort=$2
    if [[ -n "${portHoppingStart}" || -n "${portHoppingEnd}" ]]; then
        echoContent red " ---> 已添加不可重复添加，可删除后重新添加"
        exit 1
    fi
    if [[ "${release}" == "centos" ]]; then
        if ! systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
            echoContent red " ---> 未启动firewalld防火墙，无法设置端口跳跃。"
            exit 1
        fi
    fi

    echoContent skyBlue "\n进度 1/1 : 端口跳跃"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项\n"
    echoContent yellow "仅支持Hysteria2、Tuic"
    echoContent yellow "端口跳跃的起始位置为30000"
    echoContent yellow "端口跳跃的结束位置为40000"
    echoContent yellow "可以在30000-40000范围中选一段"
    echoContent yellow "建议1000个左右"
    echoContent yellow "注意不要和其他的端口跳跃设置范围一样，设置相同会覆盖。"

    echoContent yellow "请输入端口跳跃的范围，例如[30000-31000]"

    read -r -p "范围:" portHoppingRange
    if [[ -z "${portHoppingRange}" ]]; then
        echoContent red " ---> 范围不可为空"
        addPortHopping "${type}" "${targetPort}"
    elif echo "${portHoppingRange}" | grep -q "-"; then

        local portStart=
        local portEnd=
        portStart=$(echo "${portHoppingRange}" | awk -F '-' '{print $1}')
        portEnd=$(echo "${portHoppingRange}" | awk -F '-' '{print $2}')

        if [[ -z "${portStart}" || -z "${portEnd}" ]]; then
            echoContent red " ---> 范围不合法"
            addPortHopping "${type}" "${targetPort}"
        elif ((portStart < 30000 || portStart > 40000 || portEnd < 30000 || portEnd > 40000 || portEnd < portStart)); then
            echoContent red " ---> 范围不合法"
            addPortHopping "${type}" "${targetPort}"
        else
            echoContent green "\n端口范围: ${portHoppingRange}\n"
            if [[ "${release}" == "centos" ]]; then
                sudo firewall-cmd --permanent --add-masquerade
                sudo firewall-cmd --reload
                addFirewalldPortHopping "${portStart}" "${portEnd}" "${targetPort}"
                if ! sudo firewall-cmd --list-forward-ports | grep -q "toport=${targetPort}"; then
                    echoContent red " ---> 端口跳跃添加失败"
                    exit 1
                fi
            else
                iptables -t nat -A PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "Proxy-agent_${type}_portHopping" -j DNAT --to-destination ":${targetPort}"
                sudo netfilter-persistent save
                if ! iptables-save | grep -q "Proxy-agent_${type}_portHopping"; then
                    echoContent red " ---> 端口跳跃添加失败"
                    exit 1
                fi
            fi
            allowPort "${portStart}:${portEnd}" udp
            echoContent green " ---> 端口跳跃添加成功"
        fi
    fi
}

# 读取端口跳跃的配置
readPortHopping() {
    local type=$1
    local targetPort=$2
    local portHoppingStart=
    local portHoppingEnd=

    if [[ "${release}" == "centos" ]]; then
        portHoppingStart=$(sudo firewall-cmd --list-forward-ports | grep "toport=${targetPort}" | head -1 | cut -d ":" -f 1 | cut -d "=" -f 2)
        portHoppingEnd=$(sudo firewall-cmd --list-forward-ports | grep "toport=${targetPort}" | tail -n 1 | cut -d ":" -f 1 | cut -d "=" -f 2)
    else
        if iptables-save | grep -q "Proxy-agent_${type}_portHopping"; then
            local portHopping=
            portHopping=$(iptables-save | grep "Proxy-agent_${type}_portHopping" | cut -d " " -f 8)

            portHoppingStart=$(echo "${portHopping}" | cut -d ":" -f 1)
            portHoppingEnd=$(echo "${portHopping}" | cut -d ":" -f 2)
        fi
    fi
    if [[ "${type}" == "hysteria2" ]]; then
        hysteria2PortHoppingStart="${portHoppingStart}"
        hysteria2PortHoppingEnd=${portHoppingEnd}
        hysteria2PortHopping="${portHoppingStart}-${portHoppingEnd}"
    elif [[ "${type}" == "tuic" ]]; then
        tuicPortHoppingStart="${portHoppingStart}"
        tuicPortHoppingEnd="${portHoppingEnd}"
        #        tuicPortHopping="${portHoppingStart}-${portHoppingEnd}"
    fi
}
# 删除端口跳跃iptables规则
deletePortHoppingRules() {
    local type=$1
    local start=$2
    local end=$3
    local targetPort=$4

    if [[ "${release}" == "centos" ]]; then
        for port in $(seq "${start}" "${end}"); do
            sudo firewall-cmd --permanent --remove-forward-port=port="${port}":proto=udp:toport="${targetPort}"
        done
        sudo firewall-cmd --reload
    else
        iptables -t nat -L PREROUTING --line-numbers | grep "Proxy-agent_${type}_portHopping" | awk '{print $1}' | while read -r line; do
            iptables -t nat -D PREROUTING 1
            sudo netfilter-persistent save
        done
    fi
}

# 端口跳跃菜单
portHoppingMenu() {
    local type=$1
    # 判断iptables是否存在
    if ! find /usr/bin /usr/sbin | grep -q -w iptables; then
        echoContent red " ---> 无法识别iptables工具，无法使用端口跳跃，退出安装"
        exit 1
    fi

    local targetPort=
    local portHoppingStart=
    local portHoppingEnd=

    if [[ "${type}" == "hysteria2" ]]; then
        readPortHopping "${type}" "${singBoxHysteria2Port}"
        targetPort=${singBoxHysteria2Port}
        portHoppingStart=${hysteria2PortHoppingStart}
        portHoppingEnd=${hysteria2PortHoppingEnd}
    elif [[ "${type}" == "tuic" ]]; then
        readPortHopping "${type}" "${singBoxTuicPort}"
        targetPort=${singBoxTuicPort}
        portHoppingStart=${tuicPortHoppingStart}
        portHoppingEnd=${tuicPortHoppingEnd}
    fi

    echoContent skyBlue "\n进度 1/1 : 端口跳跃"
    echoContent red "\n=============================================================="
    echoContent yellow "1.添加端口跳跃"
    echoContent yellow "2.删除端口跳跃"
    echoContent yellow "3.查看端口跳跃"
    read -r -p "请选择:" selectPortHoppingStatus
    if [[ "${selectPortHoppingStatus}" == "1" ]]; then
        addPortHopping "${type}" "${targetPort}"
    elif [[ "${selectPortHoppingStatus}" == "2" ]]; then
        deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${targetPort}"
        echoContent green " ---> 删除成功"
    elif [[ "${selectPortHoppingStatus}" == "3" ]]; then
        if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
            echoContent green " ---> 当前端口跳跃范围为: ${portHoppingStart}-${portHoppingEnd}"
        else
            echoContent yellow " ---> 未设置端口跳跃"
        fi
    else
        portHoppingMenu
    fi
}

# 初始化tuic端口
initTuicPort() {
    readSingBoxConfig
    if [[ -n "${tuicPort}" ]]; then
        read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口？[y/n]:" historyTuicPortStatus
        if [[ "${historyTuicPortStatus}" == "y" ]]; then
            echoContent yellow "\n ---> 端口: ${tuicPort}"
        else
            tuicPort=
        fi
    fi

    if [[ -z "${tuicPort}" ]]; then
        echoContent yellow "请输入Tuic端口[回车随机10000-30000]，不可与其他服务重复"
        read -r -p "端口:" tuicPort
        if [[ -z "${tuicPort}" ]]; then
            tuicPort=$(randomNum 10000 30000)
        fi
    fi
    if [[ -z ${tuicPort} ]]; then
        echoContent red " ---> 端口不可为空"
        initTuicPort "$2"
    elif ((tuicPort < 1 || tuicPort > 65535)); then
        echoContent red " ---> 端口不合法"
        initTuicPort "$2"
    fi
    echoContent green "\n ---> 端口: ${tuicPort}"
    allowPort "${tuicPort}"
    allowPort "${tuicPort}" "udp"
}

# 初始化tuic的协议
initTuicProtocol() {
    if [[ -n "${tuicAlgorithm}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次使用的算法，是否使用 ？[y/n]:" historyTuicAlgorithm
        if [[ "${historyTuicAlgorithm}" != "y" ]]; then
            tuicAlgorithm=
        else
            echoContent yellow "\n ---> 算法: ${tuicAlgorithm}\n"
        fi
    elif [[ -n "${tuicAlgorithm}" && -n "${lastInstallationConfig}" ]]; then
        echoContent yellow "\n ---> 算法: ${tuicAlgorithm}\n"
    fi

    if [[ -z "${tuicAlgorithm}" ]]; then

        echoContent skyBlue "\n请选择算法类型"
        echoContent red "=============================================================="
        echoContent yellow "1.bbr(默认)"
        echoContent yellow "2.cubic"
        echoContent yellow "3.new_reno"
        echoContent red "=============================================================="
        read -r -p "请选择:" selectTuicAlgorithm
        case ${selectTuicAlgorithm} in
        1)
            tuicAlgorithm="bbr"
            ;;
        2)
            tuicAlgorithm="cubic"
            ;;
        3)
            tuicAlgorithm="new_reno"
            ;;
        *)
            tuicAlgorithm="bbr"
            ;;
        esac
        echoContent yellow "\n ---> 算法: ${tuicAlgorithm}\n"
    fi
}

# 初始化singbox route配置
initSingBoxRouteConfig() {
    downloadSingBoxGeositeDB
    local outboundTag=$1
    if [[ ! -f "${singBoxConfigPath}${outboundTag}_route.json" ]]; then
        cat <<EOF >"${singBoxConfigPath}${outboundTag}_route.json"
{
    "route": {
        "geosite": {
            "path": "${singBoxConfigPath}geosite.db"
        },
        "rules": [
            {
                "domain": [
                ],
                "geosite": [
                ],
                "outbound": "${outboundTag}"
            }
        ]
    }
}
EOF
    fi
}
# 下载sing-box geosite db
downloadSingBoxGeositeDB() {
    if [[ ! -f "${singBoxConfigPath}geosite.db" ]]; then
        if [[ "${release}" == "alpine" ]]; then
            wget -q -P "${singBoxConfigPath}" https://github.com/Johnshall/sing-geosite/releases/latest/download/geosite.db
        else
            wget -q "${wgetShowProgressStatus}" -P "${singBoxConfigPath}" https://github.com/Johnshall/sing-geosite/releases/latest/download/geosite.db
        fi

    fi
}

# 初始化sing-box规则配置（检查geosite可用性）
# 参数1: 域名列表(逗号分隔)
# 参数2: 路由名称后缀
# 返回: JSON格式 {"domainRules":[], "ruleSet":[]}
initSingBoxRules() {
    local domainRules=[]
    local ruleSet=[]
    while read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        local geositeStatus
        # 添加超时和错误处理
        geositeStatus=$(curl -s --connect-timeout 5 --max-time 10 \
            "https://api.github.com/repos/SagerNet/sing-geosite/contents/geosite-${line}.srs?ref=rule-set" 2>/dev/null | jq -r '.message // empty')

        # 如果API返回null或空(即文件存在)，使用rule_set
        # 如果API失败或返回错误消息，回退到domain_regex
        if [[ -z "${geositeStatus}" ]]; then
            ruleSet=$(echo "${ruleSet}" | jq -r ". += [{\"tag\":\"${line}_$2\",\"type\":\"remote\",\"format\":\"binary\",\"url\":\"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${line}.srs\",\"download_detour\":\"01_direct_outbound\"}]")
        else
            # 转义域名中的点号用于正则表达式
            local escapedLine="${line//./\\.}"
            domainRules=$(echo "${domainRules}" | jq -r ". += [\"^([a-zA-Z0-9_-]+\\\\.)*${escapedLine}\"]")
        fi
    done < <(echo "$1" | tr ',' '\n' | grep -v '^$' | sort -u)
    echo "{ \"domainRules\":${domainRules},\"ruleSet\":${ruleSet}}"
}

# 添加sing-box路由规则
addSingBoxRouteRule() {
    local outboundTag=$1
    # 域名列表
    local domainList=$2
    # 路由文件名称
    local routingName=$3
    # 读取上次安装内容
    if [[ -f "${singBoxConfigPath}${routingName}.json" ]]; then
        read -r -p "读取到上次的配置，是否保留 ？[y/n]:" historyRouteStatus
        if [[ "${historyRouteStatus}" == "y" ]]; then
            domainList="${domainList},$(jq -rc .route.rules[0].rule_set[] "${singBoxConfigPath}${routingName}.json" | awk -F "[_]" '{print $1}' | paste -sd ',')"
            domainList="${domainList},$(jq -rc .route.rules[0].domain_regex[] "${singBoxConfigPath}${routingName}.json" | awk -F "[*]" '{print $2}' | paste -sd ',' | sed 's/\\//g')"
        fi
    fi
    local rules=
    rules=$(initSingBoxRules "${domainList}" "${routingName}")
    # domain精确匹配规则
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    # ruleSet规则集
    local ruleSet=
    ruleSet=$(echo "${rules}" | jq .ruleSet)

    # ruleSet规则tag
    local ruleSetTag=[]
    if [[ "$(echo "${ruleSet}" | jq '.|length')" != "0" ]]; then
        ruleSetTag=$(echo "${ruleSet}" | jq '.|map(.tag)')
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then

        cat <<EOF >"${singBoxConfigPath}${routingName}.json"
{
  "route": {
    "rules": [
      {
        "rule_set":${ruleSetTag},
        "domain_regex":${domainRules},
        "outbound": "${outboundTag}"
      }
    ],
    "rule_set":${ruleSet}
  }
}
EOF
        jq 'if .route.rule_set == [] then del(.route.rule_set) else . end' "${singBoxConfigPath}${routingName}.json" >"${singBoxConfigPath}${routingName}_tmp.json" && mv "${singBoxConfigPath}${routingName}_tmp.json" "${singBoxConfigPath}${routingName}.json"
    fi

}

# 移除sing-box route rule
removeSingBoxRouteRule() {
    local outboundTag=$1
    local delRules
    if [[ -f "${singBoxConfigPath}${outboundTag}_route.json" ]]; then
        delRules=$(jq -r 'del(.route.rules[]|select(.outbound=="'"${outboundTag}"'"))' "${singBoxConfigPath}${outboundTag}_route.json")
        echo "${delRules}" >"${singBoxConfigPath}${outboundTag}_route.json"
    fi
}

# 添加sing-box出站
addSingBoxOutbound() {
    local tag=$1
    local type="ipv4"
    local detour=$2
    if echo "${tag}" | grep -q "IPv6"; then
        type=ipv6
    fi
    if [[ -n "${detour}" ]]; then
        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}",
             "detour": "${detour}",
             "domain_strategy": "${type}_only"
        }
    ]
}
EOF
    elif echo "${tag}" | grep -q "direct"; then

        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}"
        }
    ]
}
EOF
    elif echo "${tag}" | grep -q "block"; then

        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "block",
             "tag": "${tag}"
        }
    ]
}
EOF
    else
        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}",
             "domain_strategy": "${type}_only"
        }
    ]
}
EOF
    fi
}

# 添加Xray-core 出站
addXrayOutbound() {
    local tag=$1
    local domainStrategy=

    if echo "${tag}" | grep -q "IPv4"; then
        domainStrategy="ForceIPv4"
    elif echo "${tag}" | grep -q "IPv6"; then
        domainStrategy="ForceIPv6"
    fi

    if [[ -n "${domainStrategy}" ]]; then
        cat <<EOF >"/etc/Proxy-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings":{
                "domainStrategy":"${domainStrategy}"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # direct
    if echo "${tag}" | grep -q "direct"; then
        cat <<EOF >"/etc/Proxy-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings": {
                "domainStrategy":"UseIP"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # blackhole
    if echo "${tag}" | grep -q "blackhole"; then
        cat <<EOF >"/etc/Proxy-agent/xray/conf/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"blackhole",
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv4"; then
        cat <<EOF >"/etc/Proxy-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv6"; then
        cat <<EOF >"/etc/Proxy-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "vmess-out"; then
        cat <<EOF >"/etc/Proxy-agent/xray/conf/${tag}.json"
{
  "outbounds": [
    {
      "tag": "${tag}",
      "protocol": "vmess",
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false
        },
        "wsSettings": {
          "path": "${setVMessWSTLSPath}"
        }
      },
      "mux": {
        "enabled": true,
        "concurrency": 8
      },
      "settings": {
        "vnext": [
          {
            "address": "${setVMessWSTLSAddress}",
            "port": "${setVMessWSTLSPort}",
            "users": [
              {
                "id": "${setVMessWSTLSUUID}",
                "security": "auto",
                "alterId": 0
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
    fi
}

# 删除 Xray-core出站
removeXrayOutbound() {
    local tag=$1
    if [[ -f "/etc/Proxy-agent/xray/conf/${tag}.json" ]]; then
        rm "/etc/Proxy-agent/xray/conf/${tag}.json" >/dev/null 2>&1
    fi
}
# 移除sing-box配置
removeSingBoxConfig() {

    local tag=$1
    if [[ -f "${singBoxConfigPath}${tag}.json" ]]; then
        rm "${singBoxConfigPath}${tag}.json"
    fi
}

# 初始化wireguard出站信息
addSingBoxWireGuardEndpoints() {
    local type=$1

    readConfigWarpReg

    cat <<EOF >"${singBoxConfigPath}wireguard_endpoints_${type}.json"
{
     "endpoints": [
        {
            "type": "wireguard",
            "tag": "wireguard_endpoints_${type}",
            "address": [
                "${address}"
            ],
            "private_key": "${secretKeyWarpReg}",
            "peers": [
                {
                  "address": "162.159.192.1",
                  "port": 2408,
                  "public_key": "${publicKeyWarpReg}",
                  "reserved":${reservedWarpReg},
                  "allowed_ips": ["0.0.0.0/0","::/0"]
                }
            ]
        }
    ]
}
EOF
}

# 初始化 sing-box Hysteria2 配置
initSingBoxHysteria2Config() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Hysteria2配置"

    initHysteriaPort
    initHysteria2Network

    # 构建obfs配置（如果启用）
    local hysteria2ObfsConfig=""
    if [[ -n "${hysteria2ObfsPassword}" ]]; then
        hysteria2ObfsConfig='"obfs": {"type": "salamander", "password": "'"${hysteria2ObfsPassword}"'"},'
    fi

    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/hysteria2.json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${hysteriaPort},
            "users": $(initXrayClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
            "ignore_client_bandwidth": false,
            ${hysteria2ObfsConfig}
            "tls": {
                "enabled": true,
                "server_name":"${currentHost}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/Proxy-agent/tls/${currentHost}.crt",
                "key_path": "/etc/Proxy-agent/tls/${currentHost}.key"
            }
        }
    ]
}
EOF
}

# sing-box Tuic安装
singBoxTuicInstall() {
    if ! echo "${currentInstallProtocolType}" | grep -qE ",0,|,1,|,2,|,3,|,4,|,5,|,6,|,9,|,10,"; then
        echoContent red "\n ---> 由于需要依赖证书，如安装Tuic，请先安装带有TLS标识协议"
        exit 1
    fi

    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",9,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    showAccounts 4
}

# sing-box hy2安装
singBoxHysteria2Install() {
    if ! echo "${currentInstallProtocolType}" | grep -qE ",0,|,1,|,2,|,3,|,4,|,5,|,6,|,9,|,10,"; then
        echoContent red "\n ---> 由于需要依赖证书，如安装Hysteria2，请先安装带有TLS标识协议"
        exit 1
    fi

    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",6,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    showAccounts 4
}

# sing-box Shadowsocks 2022 安装
singBoxSS2022Install() {
    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",14,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    showAccounts 4
}

# 合并config
singBoxMergeConfig() {
    rm /etc/Proxy-agent/sing-box/conf/config.json >/dev/null 2>&1

    local mergeOutput mergeResult
    mergeOutput=$(/etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/ 2>&1)
    mergeResult=$?

    if [[ ${mergeResult} -ne 0 ]]; then
        echoContent red " ---> sing-box 配置合并失败"
        echoContent red " ---> 错误信息:"
        echo "${mergeOutput}" | head -20
        return 1
    fi

    # 验证合并后的配置文件存在且有效
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/config.json" ]]; then
        echoContent red " ---> sing-box 配置文件生成失败"
        return 1
    fi

    return 0
}

# 初始化sing-box端口
initSingBoxPort() {
    local port=$1
    if [[ -n "${port}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次使用的端口，是否使用 ？[y/n]:" historyPort
        if [[ "${historyPort}" != "y" ]]; then
            port=
        else
            echo "${port}"
        fi
    elif [[ -n "${port}" && -n "${lastInstallationConfig}" ]]; then
        echo "${port}"
    fi
    if [[ -z "${port}" ]]; then
        read -r -p '请输入自定义端口[需合法]，端口不可重复，[回车]随机端口:' port
        if [[ -z "${port}" ]]; then
            port=$(randomNum 10000 60000)
        fi
        if ((port >= 1 && port <= 65535)); then
            allowPort "${port}"
            allowPort "${port}" "udp"
            echo "${port}"
        else
            echoContent red " ---> 端口输入错误"
            exit 1
        fi
    fi
}

# 初始化Xray 配置文件
initXrayConfig() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化Xray配置"
    echo
    local uuid=
    local addClientsStatus=
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，是否使用上次安装的配置 ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/Proxy-agent/xray/xray uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        read -r -p '用户名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(/etc/Proxy-agent/xray/xray uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"id":"'${uuid}'","add":"'${add}'","flow":"xtls-rprx-vision","email":"'${customEmail}'"}]'
        echoContent green "\n ${customEmail}:${uuid}"
        echo
    fi

    # log
    if [[ ! -f "/etc/Proxy-agent/xray/conf/00_log.json" ]]; then

        cat <<EOF >/etc/Proxy-agent/xray/conf/00_log.json
{
  "log": {
    "error": "/etc/Proxy-agent/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF
    fi

    if [[ ! -f "/etc/Proxy-agent/xray/conf/12_policy.json" ]]; then
        local handshakeVal connIdleVal
        handshakeVal=$(randomNum 1 4)
        connIdleVal=$(randomNum 250 300)
        cat <<EOF >/etc/Proxy-agent/xray/conf/12_policy.json
{
  "policy": {
      "levels": {
          "0": {
              "handshake": ${handshakeVal},
              "connIdle": ${connIdleVal}
          }
      }
  }
}
EOF
    fi

    addXrayOutbound "z_direct_outbound"
    # dns
    if [[ ! -f "/etc/Proxy-agent/xray/conf/11_dns.json" ]]; then
        cat <<EOF >/etc/Proxy-agent/xray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF
    fi
    # routing
    cat <<EOF >/etc/Proxy-agent/xray/conf/09_routing.json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:gstatic.com",
          "domain:googleapis.com",
	  "domain:googleapis.cn"
        ],
        "outboundTag": "z_direct_outbound"
      }
    ]
  }
}
EOF
    # VLESS_TCP_TLS_Vision
    # 回落nginx
    local fallbacksList='{"dest":31300,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'

    # trojan
    if echo "${selectCustomInstallType}" | grep -q ",4," || [[ "$1" == "all" ]]; then
        fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'
        cat <<EOF >/etc/Proxy-agent/xray/conf/04_trojan_TCP_inbounds.json
{
"inbounds":[
	{
	  "port": 31296,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag":"trojanTCP",
	  "settings": {
		"clients": $(initXrayClients 4),
		"fallbacks":[
			{
			    "dest":"31300",
			    "xver":1
			}
		]
	  },
	  "streamSettings": {
		"network": "tcp",
		"security": "none",
		"tcpSettings": {
			"acceptProxyProtocol": true
		}
	  }
	}
	]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_WS_TLS
    if echo "${selectCustomInstallType}" | grep -q ",1," || [[ "$1" == "all" ]]; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
        cat <<EOF >/etc/Proxy-agent/xray/conf/03_VLESS_WS_inbounds.json
{
"inbounds":[
    {
	  "port": 31297,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSWS",
	  "settings": {
		"clients": $(initXrayClients 1),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${customPath}ws"
		}
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_Reality_XHTTP_TLS
    if echo "${selectCustomInstallType}" | grep -q ",12," || [[ "$1" == "all" ]]; then
        initXrayXHTTPort
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        initRealityMldsa65
        cat <<EOF >/etc/Proxy-agent/xray/conf/12_VLESS_XHTTP_inbounds.json
{
"inbounds":[
    {
	  "port": ${xHTTPort},
	  "listen": "0.0.0.0",
	  "protocol": "vless",
	  "tag":"VLESSRealityXHTTP",
	  "settings": {
		"clients": $(initXrayClients 12),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "xhttp",
		"security": "reality",
		"realitySettings": {
            "show": false,
            "target": "${realityServerName}:${realityDomainPort}",
            "xver": 0,
            "serverNames": [
                "${realityServerName}"
            ],
            "privateKey": "${realityPrivateKey}",
            "publicKey": "${realityPublicKey}",
            "maxTimeDiff": 60000,
            "shortIds": [
                "${realityShortId1}",
                "${realityShortId2}"
            ]
        },
        "xhttpSettings": {
            "host": "${realityServerName}",
            "path": "/${customPath}xHTTP",
            "mode": "auto",
            "extra": {
                "xPaddingBytes": "100-1000"
            }
        }
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/12_VLESS_XHTTP_inbounds.json >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",3," || [[ "$1" == "all" ]]; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'vws","dest":31299,"xver":1}'
        cat <<EOF >/etc/Proxy-agent/xray/conf/05_VMess_WS_inbounds.json
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31299,
          "protocol": "vmess",
          "tag":"VMessWS",
          "settings": {
            "clients": $(initXrayClients 3)
          },
          "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
              "acceptProxyProtocol": true,
              "path": "/${customPath}vws"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_gRPC
    if echo "${selectCustomInstallType}" | grep -q ",5," || [[ "$1" == "all" ]]; then
        cat <<EOF >/etc/Proxy-agent/xray/conf/06_VLESS_gRPC_inbounds.json
{
    "inbounds":[
        {
            "port": 31301,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "tag":"VLESSGRPC",
            "settings": {
                "clients": $(initXrayClients 5),
                "decryption": "none"
            },
            "streamSettings": {
                "network": "grpc",
                "grpcSettings": {
                    "serviceName": "${customPath}grpc"
                }
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/06_VLESS_gRPC_inbounds.json >/dev/null 2>&1
    fi

    # VLESS Vision
    if echo "${selectCustomInstallType}" | grep -q ",0," || [[ "$1" == "all" ]]; then

        cat <<EOF >/etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json
{
    "inbounds":[
        {
          "port": ${port},
          "protocol": "vless",
          "tag":"VLESSTCP",
          "settings": {
            "clients":$(initXrayClients 0),
            "decryption": "none",
            "fallbacks": [
                ${fallbacksList}
            ]
          },
          "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
              "alpn": ["h2", "http/1.1"],
              "rejectUnknownSni": true,
              "minVersion": "1.2",
              "certificates": [
                {
                  "certificateFile": "/etc/Proxy-agent/tls/${domain}.crt",
                  "keyFile": "/etc/Proxy-agent/tls/${domain}.key",
                  "ocspStapling": 3600
                }
              ]
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_TCP/reality
    if echo "${selectCustomInstallType}" | grep -q ",7," || [[ "$1" == "all" ]]; then
        echoContent skyBlue "\n===================== 配置VLESS+Reality =====================\n"

        initXrayRealityPort
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        initRealityMldsa65
        cat <<EOF >/etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json
{
  "inbounds": [
    {
      "tag": "dokodemo-in-VLESSReality",
      "port": ${realityPort},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 45987,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 45987,
      "protocol": "vless",
      "settings": {
        "clients": $(initXrayClients 7),
        "decryption": "none",
        "fallbacks":[
          {
            "dest": "31305",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${realityServerName}:${realityDomainPort}",
          "xver": 0,
          "serverNames": [
            "${realityServerName}"
          ],
          "privateKey": "${realityPrivateKey}",
          "publicKey": "${realityPublicKey}",
          "mldsa65Seed": "${realityMldsa65Seed}",
          "mldsa65Verify": "${realityMldsa65Verify}",
          "maxTimeDiff": 60000,
          "shortIds": [
            "${realityShortId1}",
            "${realityShortId2}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "${realityServerName}"
        ],
        "outboundTag": "z_direct_outbound"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "blackhole_out"
      }
    ]
  }
}
EOF
        cat <<EOF >/etc/Proxy-agent/xray/conf/08_VLESS_vision_gRPC_inbounds.json
{
  "inbounds": [
    {
      "port": 31305,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "tag": "VLESSRealityGRPC",
      "settings": {
        "clients": $(initXrayClients 8),
        "decryption": "none"
      },
      "streamSettings": {
            "network": "grpc",
            "grpcSettings": {
                "serviceName": "grpc",
                "multiMode": true
            },
            "sockopt": {
                "acceptProxyProtocol": true
            }
      }
    }
  ]
}
EOF

    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
        rm /etc/Proxy-agent/xray/conf/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi
    installSniffing
    if [[ -z "$3" ]]; then
        removeXrayOutbound wireguard_out_IPv4_route
        removeXrayOutbound wireguard_out_IPv6_route
        removeXrayOutbound wireguard_outbound
        removeXrayOutbound IPv4_out
        removeXrayOutbound IPv6_out
        removeXrayOutbound socks5_outbound
        removeXrayOutbound blackhole_out
        removeXrayOutbound wireguard_out_IPv6
        removeXrayOutbound wireguard_out_IPv4
        addXrayOutbound z_direct_outbound
        addXrayOutbound blackhole_out
    fi
}

# 初始化TCP Brutal
initTCPBrutal() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化TCP_Brutal配置"
    read -r -p "是否使用TCP_Brutal？[y/n]:" tcpBrutalStatus
    if [[ "${tcpBrutalStatus}" == "y" ]]; then
        read -r -p "请输入本地带宽峰值的下行速度（默认：100，单位：Mbps）:" tcpBrutalClientDownloadSpeed
        if [[ -z "${tcpBrutalClientDownloadSpeed}" ]]; then
            tcpBrutalClientDownloadSpeed=100
        fi

        read -r -p "请输入本地带宽峰值的上行速度（默认：50，单位：Mbps）:" tcpBrutalClientUploadSpeed
        if [[ -z "${tcpBrutalClientUploadSpeed}" ]]; then
            tcpBrutalClientUploadSpeed=50
        fi
    fi
}
# 初始化sing-box配置文件
initSingBoxConfig() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化sing-box配置"

    echo
    local uuid=
    local addClientsStatus=
    local sslDomain=
    if [[ -n "${domain}" ]]; then
        sslDomain="${domain}"
    elif [[ -n "${currentHost}" ]]; then
        sslDomain="${currentHost}"
    fi
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，是否使用上次安装的配置 ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/Proxy-agent/sing-box/sing-box generate uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        read -r -p '用户名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(/etc/Proxy-agent/sing-box/sing-box generate uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"uuid":"'${uuid}'","flow":"xtls-rprx-vision","name":"'${customEmail}'"}]'
        echoContent yellow "\n ${customEmail}:${uuid}"
    fi

    # VLESS Vision
    if echo "${selectCustomInstallType}" | grep -q ",0," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VLESS+Vision =====================\n"
        echoContent skyBlue "\n开始配置VLESS+Vision协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSVisionPort}")
        echoContent green "\n ---> VLESS_Vision端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop

        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/02_VLESS_TCP_inbounds.json
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSTCP",
          "users":$(initSingBoxClients 0),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
            "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",1," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VLESS+WS =====================\n"
        echoContent skyBlue "\n开始配置VLESS+WS协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSWSPort}")
        echoContent green "\n ---> VLESS_WS端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/03_VLESS_WS_inbounds.json
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSWS",
          "users":$(initSingBoxClients 1),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
            "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}ws",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",3," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VMess+ws =====================\n"
        echoContent skyBlue "\n开始配置VMess+ws协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessWSPort}")
        echoContent green "\n ---> VMess_ws端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/05_VMess_WS_inbounds.json
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VMessWS",
          "users":$(initSingBoxClients 3),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
            "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_Reality_Vision
    if echo "${selectCustomInstallType}" | grep -q ",7," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================= 配置VLESS+Reality+Vision =================\n"
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        echoContent skyBlue "\n开始配置VLESS+Reality+Vision协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityVisionPort}")
        echoContent green "\n ---> VLESS_Reality_Vision端口：${result[-1]}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "tag": "VLESSReality",
      "users":$(initSingBoxClients 7),
      "tls": {
        "enabled": true,
        "server_name": "${realityServerName}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server": "${realityServerName}",
                "server_port":${realityDomainPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "${realityShortId1}",
                "${realityShortId2}"
            ]
        }
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",8," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置VLESS+Reality+gRPC ==================\n"
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        echoContent skyBlue "\n开始配置VLESS+Reality+gRPC协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityGRPCPort}")
        echoContent green "\n ---> VLESS_Reality_gPRC端口：${result[-1]}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "users":$(initSingBoxClients 8),
      "tag": "VLESSRealityGRPC",
      "tls": {
        "enabled": true,
        "server_name": "${realityServerName}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server":"${realityServerName}",
                "server_port":${realityDomainPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "${realityShortId1}",
                "${realityShortId2}"
            ]
        }
      },
      "transport": {
          "type": "grpc",
          "service_name": "grpc"
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",6," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 Hysteria2 ==================\n"
        echoContent skyBlue "\n开始配置Hysteria2协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxHysteria2Port}")
        echoContent green "\n ---> Hysteria2端口：${result[-1]}"
        initHysteria2Network

        # 构建obfs配置（如果启用）
        local hysteria2ObfsConfig=""
        if [[ -n "${hysteria2ObfsPassword}" ]]; then
            hysteria2ObfsConfig='"obfs": {"type": "salamander", "password": "'"${hysteria2ObfsPassword}"'"},'
        fi

        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/06_hysteria2_inbounds.json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
            "ignore_client_bandwidth": false,
            ${hysteria2ObfsConfig}
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/06_hysteria2_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",4," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 Trojan ==================\n"
        echoContent skyBlue "\n开始配置Trojan协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTrojanPort}")
        echoContent green "\n ---> Trojan端口：${result[-1]}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/04_trojan_TCP_inbounds.json
{
    "inbounds": [
        {
            "type": "trojan",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 4),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",9," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n==================== 配置 Tuic =====================\n"
        echoContent skyBlue "\n开始配置Tuic协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTuicPort}")
        echoContent green "\n ---> Tuic端口：${result[-1]}"
        initTuicProtocol
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/09_tuic_inbounds.json
{
     "inbounds": [
        {
            "type": "tuic",
            "listen": "::",
            "tag": "singbox-tuic-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 9),
            "congestion_control": "${tuicAlgorithm}",
            "auth_timeout": "3s",
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/09_tuic_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",10," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n==================== 配置 Naive =====================\n"
        echoContent skyBlue "\n开始配置Naive协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxNaivePort}")
        echoContent green "\n ---> Naive端口：${result[-1]}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/10_naive_inbounds.json
{
     "inbounds": [
        {
            "type": "naive",
            "listen": "::",
            "tag": "singbox-naive-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 10),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/10_naive_inbounds.json >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",11," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VMess+HTTPUpgrade =====================\n"
        echoContent skyBlue "\n开始配置VMess+HTTPUpgrade协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessHTTPUpgradePort}")
        echoContent green "\n ---> VMess_HTTPUpgrade端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
        checkPortOpen "${result[-1]}" "${domain}"
        singBoxNginxConfig "$1" "${result[-1]}"
        bootStartup nginx
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"127.0.0.1",
          "listen_port":31306,
          "tag":"VMessHTTPUpgrade",
          "users":$(initSingBoxClients 11),
          "transport": {
            "type": "httpupgrade",
            "path": "/${currentPath}"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",13," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 AnyTLS ==================\n"
        echoContent skyBlue "\n开始配置AnyTLS协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxAnyTLSPort}")
        echoContent green "\n ---> AnyTLS端口：${result[-1]}"
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/13_anytls_inbounds.json
{
    "inbounds": [
        {
            "type": "anytls",
            "listen": "::",
            "tag":"anytls",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 13),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/Proxy-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/Proxy-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/13_anytls_inbounds.json >/dev/null 2>&1
    fi

    # Shadowsocks 2022
    if echo "${selectCustomInstallType}" | grep -q ",14," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 Shadowsocks 2022 ==================\n"
        echoContent skyBlue "\n开始配置Shadowsocks 2022协议"
        echo
        initSS2022Config
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/14_ss2022_inbounds.json
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "listen": "::",
            "tag": "ss2022-in",
            "listen_port": ${ss2022Port},
            "method": "${ss2022Method}",
            "password": "${ss2022ServerKey}",
            "users": $(initSingBoxClients 14),
            "multiplex": {
                "enabled": true
            }
        }
    ]
}
EOF
        echoContent green " ---> Shadowsocks 2022配置完成"
    elif [[ -z "$3" ]]; then
        rm /etc/Proxy-agent/sing-box/conf/config/14_ss2022_inbounds.json >/dev/null 2>&1
    fi

    if [[ -z "$3" ]]; then
        removeSingBoxConfig wireguard_endpoints_IPv4_route
        removeSingBoxConfig wireguard_endpoints_IPv6_route
        removeSingBoxConfig wireguard_endpoints_IPv4
        removeSingBoxConfig wireguard_endpoints_IPv6

        removeSingBoxConfig IPv4_out
        removeSingBoxConfig IPv6_out
        removeSingBoxConfig IPv6_route
        removeSingBoxConfig block
        removeSingBoxConfig cn_block_outbound
        removeSingBoxConfig cn_block_route
        removeSingBoxConfig 01_direct_outbound
        removeSingBoxConfig socks5_outbound.json
        removeSingBoxConfig block_domain_outbound
        removeSingBoxConfig dns
    fi
}
# 初始化 sing-box订阅配置
initSubscribeLocalConfig() {
    rm -rf /etc/Proxy-agent/subscribe_local/sing-box/*
}
# 通用
defaultBase64Code() {
    local type=$1
    local port=$2
    local email=$3
    local id=$4
    local add=$5
    local path=$6
    local user=
    user=$(echo "${email}" | awk -F "[-]" '{print $1}')
    if [[ ! -f "/etc/Proxy-agent/subscribe_local/sing-box/${user}" ]]; then
        echo [] >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"
    fi
    local singBoxSubscribeLocalConfig=
    if [[ "${type}" == "vlesstcp" ]]; then

        echoContent yellow " ---> 通用格式(VLESS+TCP+TLS_Vision)"
        echoContent green "    vless://${id}@${currentHost}:${port}?encryption=none&security=tls&fp=chrome&type=tcp&host=${currentHost}&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+TCP+TLS_Vision)"
        echoContent green "协议类型:VLESS，地址:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，client-fingerprint: chrome，传输方式:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vless://${id}@${currentHost}:${port}?encryption=none&security=tls&type=tcp&host=${currentHost}&fp=chrome&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${currentHost}
    port: ${port}
    uuid: ${id}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    client-fingerprint: chrome
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${currentHost}\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"xudp\"}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+TCP+TLS_Vision)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${currentHost}%3A${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26type%3Dtcp%26${currentHost}%3D${currentHost}%26headerType%3Dnone%26sni%3D${currentHost}%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vmessws" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+WS+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> 通用vmess(VMess+WS+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> 二维码 vmess(VMess+WS+TLS)"

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vmess://${qrCodeBase64Default}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vmess
    server: ${add}
    port: ${port}
    uuid: ${id}
    alterId: 0
    cipher: none
    udp: true
    tls: true
    client-fingerprint: chrome
    servername: ${currentHost}
    network: ws
    ws-opts:
      path: ${path}
      headers:
        Host: ${currentHost}
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"max_early_data\":2048,\"early_data_header_name\":\"Sec-WebSocket-Protocol\"}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")

        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" == "vlessws" ]]; then

        echoContent yellow " ---> 通用格式(VLESS+WS+TLS)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+WS+TLS)"
        echoContent green "    协议类型:VLESS，地址:${add}，伪装域名/SNI:${currentHost}，端口:${port}，client-fingerprint: chrome,用户ID:${id}，安全:tls，传输方式:ws，路径:${path}，账户名:${email}\n"

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: ws
    client-fingerprint: chrome
    servername: ${currentHost}
    ws-opts:
      path: ${path}
      headers:
        Host: ${currentHost}
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"headers\":{\"Host\":\"${currentHost}\"}}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+WS+TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dws%26host%3D${currentHost}%26fp%3Dchrome%26sni%3D${currentHost}%26path%3D${path}%23${email}"

    elif [[ "${type}" == "vlessXHTTP" ]]; then

        echoContent yellow " ---> 通用格式(VLESS+reality+XHTTP)"
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&type=xhttp&sni=${xrayVLESSRealityXHTTPServerName}&host=${xrayVLESSRealityXHTTPServerName}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=6ba85179e30d4fc2#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+XHTTP)"
        echoContent green "协议类型:VLESS reality，地址:$(getPublicIP)，publicKey:${currentRealityXHTTPPublicKey}，shortId: 6ba85179e30d4fc2,serverNames：${xrayVLESSRealityXHTTPServerName}，端口:${port}，路径：${path}，SNI:${xrayVLESSRealityXHTTPServerName}，伪装域名:${xrayVLESSRealityXHTTPServerName}，用户ID:${id}，传输方式:xhttp，账户名:${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&type=xhttp&sni=${xrayVLESSRealityXHTTPServerName}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=6ba85179e30d4fc2#${email}
EOF
        echoContent yellow " ---> 二维码 VLESS(VLESS+reality+XHTTP)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40$(getPublicIP)%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dxhttp%26sni%3D${xrayVLESSRealityXHTTPServerName}%26fp%3Dchrome%26path%3D${path}%26host%3D${xrayVLESSRealityXHTTPServerName}%26pbk%3D${currentRealityXHTTPPublicKey}%26sid%3D6ba85179e30d4fc2%23${email}\n"

    elif
        [[ "${type}" == "vlessgrpc" ]]
    then

        echoContent yellow " ---> 通用格式(VLESS+gRPC+TLS)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&fp=chrome&serviceName=${currentPath}grpc&alpn=h2&sni=${currentHost}#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+gRPC+TLS)"
        echoContent green "    协议类型:VLESS，地址:${add}，伪装域名/SNI:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，传输方式:gRPC，alpn:h2，client-fingerprint: chrome,serviceName:${currentPath}grpc，账户名:${email}\n"

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&serviceName=${currentPath}grpc&fp=chrome&alpn=h2&sni=${currentHost}#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: grpc
    client-fingerprint: chrome
    servername: ${currentHost}
    grpc-opts:
      grpc-service-name: ${currentPath}grpc
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\": \"vless\",\"server\": \"${add}\",\"server_port\": ${port},\"uuid\": \"${id}\",\"tls\": {  \"enabled\": true,  \"server_name\": \"${currentHost}\",  \"utls\": {    \"enabled\": true,    \"fingerprint\": \"chrome\"  }},\"packet_encoding\": \"xudp\",\"transport\": {  \"type\": \"grpc\",  \"service_name\": \"${currentPath}grpc\"}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+gRPC+TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dgrpc%26host%3D${currentHost}%26serviceName%3D${currentPath}grpc%26fp%3Dchrome%26path%3D${currentPath}grpc%26sni%3D${currentHost}%26alpn%3Dh2%23${email}"

    elif [[ "${type}" == "trojan" ]]; then
        # URLEncode
        echoContent yellow " ---> Trojan(TLS)"
        echoContent green "    trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${currentHost}_Trojan\n"

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${email}_Trojan
EOF

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: trojan
    server: ${currentHost}
    port: ${port}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${currentHost}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"alpn\":[\"http/1.1\"],\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 Trojan(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${currentHost}%3a${port}%3fpeer%3d${currentHost}%26fp%3Dchrome%26sni%3d${currentHost}%26alpn%3Dhttp/1.1%23${email}\n"

    elif [[ "${type}" == "trojangrpc" ]]; then
        # URLEncode

        echoContent yellow " ---> Trojan gRPC(TLS)"
        echoContent green "    trojan://${id}@${add}:${port}?encryption=none&peer=${currentHost}&fp=chrome&security=tls&type=grpc&sni=${currentHost}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
trojan://${id}@${add}:${port}?encryption=none&peer=${currentHost}&security=tls&type=grpc&fp=chrome&sni=${currentHost}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    server: ${add}
    port: ${port}
    type: trojan
    password: ${id}
    network: grpc
    sni: ${currentHost}
    udp: true
    grpc-opts:
      grpc-service-name: ${currentPath}trojangrpc
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${add}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"insecure\":true,\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"transport\":{\"type\":\"grpc\",\"service_name\":\"${currentPath}trojangrpc\",\"idle_timeout\":\"15s\",\"ping_timeout\":\"15s\",\"permit_without_stream\":false},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 Trojan gRPC(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${add}%3a${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26peer%3d${currentHost}%26type%3Dgrpc%26sni%3d${currentHost}%26path%3D${currentPath}trojangrpc%26alpn%3Dh2%26serviceName%3D${currentPath}trojangrpc%23${email}\n"

    elif [[ "${type}" == "hysteria" ]]; then
        echoContent yellow " ---> Hysteria(TLS)"
        local clashMetaPortContent="port: ${port}"
        local multiPort=
        local multiPortEncode
        if echo "${port}" | grep -q "-"; then
            clashMetaPortContent="ports: ${port}"
            multiPort="mport=${port}&"
            multiPortEncode="mport%3D${port}%26"
        fi

        # 构建obfs参数
        local obfsUrlParam=""
        local obfsUrlParamEncode=""
        local clashMetaObfs=""
        local singBoxObfs=""
        if [[ -n "${hysteria2ObfsPassword}" ]]; then
            obfsUrlParam="obfs=salamander&obfs-password=${hysteria2ObfsPassword}&"
            obfsUrlParamEncode="obfs%3Dsamalander%26obfs-password%3D${hysteria2ObfsPassword}%26"
            clashMetaObfs="    obfs: salamander
    obfs-password: ${hysteria2ObfsPassword}"
            singBoxObfs=",\"obfs\":{\"type\":\"salamander\",\"password\":\"${hysteria2ObfsPassword}\"}"
        fi

        echoContent green "    hysteria2://${id}@${currentHost}:${singBoxHysteria2Port}?${multiPort}${obfsUrlParam}peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
hysteria2://${id}@${currentHost}:${singBoxHysteria2Port}?${multiPort}${obfsUrlParam}peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}
EOF
        echoContent yellow " ---> v2rayN(hysteria+TLS)"
        echo "{\"server\": \"${currentHost}:${port}\",\"socks5\": { \"listen\": \"127.0.0.1:7798\", \"timeout\": 300},\"auth\":\"${id}\",\"tls\":{\"sni\":\"${currentHost}\"}}" | jq

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: hysteria2
    server: ${currentHost}
    ${clashMetaPortContent}
    password: ${id}
    alpn:
        - h3
    sni: ${currentHost}
    up: "${hysteria2ClientUploadSpeed} Mbps"
    down: "${hysteria2ClientDownloadSpeed} Mbps"
${clashMetaObfs}
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"hysteria2\",\"server\":\"${currentHost}\",\"server_port\":${singBoxHysteria2Port},\"up_mbps\":${hysteria2ClientUploadSpeed},\"down_mbps\":${hysteria2ClientDownloadSpeed},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"alpn\":[\"h3\"]}${singBoxObfs}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 Hysteria2(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=hysteria2%3A%2F%2F${id}%40${currentHost}%3A${singBoxHysteria2Port}%3F${multiPortEncode}${obfsUrlParamEncode}peer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%26alpn%3Dh3%23${email}\n"

    elif [[ "${type}" == "vlessReality" ]]; then
        local realityServerName=${xrayVLESSRealityServerName}
        local publicKey=${currentRealityPublicKey}
        local realityMldsa65Verify=${currentRealityMldsa65Verify}

        if [[ "${coreInstallType}" == "2" ]]; then
            realityServerName=${singBoxVLESSRealityVisionServerName}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi
        echoContent yellow " ---> 通用格式(VLESS+reality+uTLS+Vision)"
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&pqv=${realityMldsa65Verify}&type=tcp&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+uTLS+Vision)"
        echoContent green "协议类型:VLESS reality，地址:$(getPublicIP)，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，pqv=${realityMldsa65Verify}，serverNames：${realityServerName}，端口:${port}，用户ID:${id}，传输方式:tcp，账户名:${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&pqv=${realityMldsa65Verify}&type=tcp&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: $(getPublicIP)
    port: ${port}
    uuid: ${id}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${realityServerName}
    reality-opts:
      public-key: ${publicKey}
      short-id: 6ba85179e30d4fc2
    client-fingerprint: chrome
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"$(getPublicIP)\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${realityServerName}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"6ba85179e30d4fc2\"}},\"packet_encoding\":\"xudp\"}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+reality+uTLS+Vision)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40$(getPublicIP)%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dtcp%26sni%3D${realityServerName}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vlessRealityGRPC" ]]; then
        local realityServerName=${xrayVLESSRealityServerName}
        local publicKey=${currentRealityPublicKey}
        local realityMldsa65Verify=${currentRealityMldsa65Verify}

        if [[ "${coreInstallType}" == "2" ]]; then
            realityServerName=${singBoxVLESSRealityGRPCServerName}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi

        echoContent yellow " ---> 通用格式(VLESS+reality+uTLS+gRPC)"
        # pqv=${realityMldsa65Verify}&
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&type=grpc&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+uTLS+gRPC)"
        # pqv=${realityMldsa65Verify}，
        echoContent green "协议类型:VLESS reality，serviceName:grpc，地址:$(getPublicIP)，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，serverNames：${realityServerName}，端口:${port}，用户ID:${id}，传输方式:gRPC，client-fingerprint：chrome，账户名:${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&pqv=${realityMldsa65Verify}&type=grpc&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: $(getPublicIP)
    port: ${port}
    uuid: ${id}
    network: grpc
    tls: true
    udp: true
    servername: ${realityServerName}
    reality-opts:
      public-key: ${publicKey}
      short-id: 6ba85179e30d4fc2
    grpc-opts:
      grpc-service-name: "grpc"
    client-fingerprint: chrome
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"$(getPublicIP)\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${realityServerName}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"6ba85179e30d4fc2\"}},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"grpc\",\"service_name\":\"grpc\"}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+reality+uTLS+gRPC)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40$(getPublicIP)%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dgrpc%26sni%3D${realityServerName}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26path%3Dgrpc%26serviceName%3Dgrpc%23${email}\n"
    elif [[ "${type}" == "tuic" ]]; then
        local tuicUUID=
        tuicUUID=$(echo "${id}" | awk -F "[_]" '{print $1}')

        local tuicPassword=
        tuicPassword=$(echo "${id}" | awk -F "[_]" '{print $2}')

        if [[ -z "${email}" ]]; then
            echoContent red " ---> 读取配置失败，请重新安装"
            exit 1
        fi

        echoContent yellow " ---> 格式化明文(Tuic+TLS)"
        echoContent green "    协议类型:Tuic，地址:${currentHost}，端口：${port}，uuid：${tuicUUID}，password：${tuicPassword}，congestion-controller:${tuicAlgorithm}，alpn: h3，账户名:${email}\n"

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
tuic://${tuicUUID}:${tuicPassword}@${currentHost}:${port}?congestion_control=${tuicAlgorithm}&alpn=h3&sni=${currentHost}&udp_relay_mode=quic&allow_insecure=0#${email}
EOF
        echoContent yellow " ---> v2rayN(Tuic+TLS)"
        echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    server: ${currentHost}
    type: tuic
    port: ${port}
    uuid: ${tuicUUID}
    password: ${tuicPassword}
    alpn:
     - h3
    congestion-controller: ${tuicAlgorithm}
    disable-sni: true
    reduce-rtt: true
    sni: ${email}
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\": \"tuic\",\"server\": \"${currentHost}\",\"server_port\": ${port},\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"congestion_control\": \"${tuicAlgorithm}\",\"tls\": {\"enabled\": true,\"server_name\": \"${currentHost}\",\"alpn\": [\"h3\"]}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow "\n ---> 二维码 Tuic"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=tuic%3A%2F%2F${tuicUUID}%3A${tuicPassword}%40${currentHost}%3A${tuicPort}%3Fcongestion_control%3D${tuicAlgorithm}%26alpn%3Dh3%26sni%3D${currentHost}%26udp_relay_mode%3Dquic%26allow_insecure%3D0%23${email}\n"
    elif [[ "${type}" == "naive" ]]; then
        echoContent yellow " ---> Naive(TLS)"

        echoContent green "    naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}
EOF
        echoContent yellow " ---> 二维码 Naive(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=naive%2Bhttps%3A%2F%2F${email}%3A${id}%40${currentHost}%3A${port}%3Fpadding%3Dtrue%23${email}\n"
    elif [[ "${type}" == "vmessHTTPUpgrade" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+HTTPUpgrade+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> 通用vmess(VMess+HTTPUpgrade+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> 二维码 vmess(VMess+HTTPUpgrade+TLS)"

        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
   vmess://${qrCodeBase64Default}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: vmess
    server: ${add}
    port: ${port}
    uuid: ${id}
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    client-fingerprint: chrome
    servername: ${currentHost}
    network: ws
    ws-opts:
     path: ${path}
     headers:
       Host: ${currentHost}
     v2ray-http-upgrade: true
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"security\":\"auto\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"httpupgrade\",\"path\":\"${path}\"}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")

        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" == "anytls" ]]; then
        echoContent yellow " ---> AnyTLS"

        echoContent yellow " ---> 格式化明文(AnyTLS)"
        echoContent green "协议类型:anytls，地址:${currentHost}，端口:${singBoxAnyTLSPort}，用户ID:${id}，传输方式:tcp，账户名:${email}\n"

        echoContent green "    anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: anytls
    port: ${singBoxAnyTLSPort}
    server: ${currentHost}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
    alpn:
      - h2
      - http/1.1
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"anytls\",\"server\":\"${currentHost}\",\"server_port\":${singBoxAnyTLSPort},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\"}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 AnyTLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=anytls%3A%2F%2F${id}%40${currentHost}%3A${singBoxAnyTLSPort}%3Fpeer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%23${email}\n"

    elif [[ "${type}" == "ss2022" ]]; then
        local ss2022ServerKey=$5
        local ss2022Method=$6
        # SS2022 密码格式: serverKey:userKey
        local ss2022Password="${ss2022ServerKey}:${id}"
        local ss2022PasswordBase64
        ss2022PasswordBase64=$(echo -n "${ss2022Password}" | base64 | tr -d '\n')

        echoContent yellow " ---> Shadowsocks 2022"

        echoContent yellow " ---> 格式化明文(SS2022)"
        echoContent green "协议类型:ss2022，地址:${publicIP}，端口:${port}，加密方式:${ss2022Method}，密码:${ss2022Password}，账户名:${email}\n"

        # SIP002 URL格式: ss://BASE64(method:password)@host:port#name
        local ss2022UrlPassword
        ss2022UrlPassword=$(echo -n "${ss2022Method}:${ss2022Password}" | base64 | tr -d '\n')
        echoContent green "    ss://${ss2022UrlPassword}@${publicIP}:${port}#${email}\n"
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/default/${user}"
ss://${ss2022UrlPassword}@${publicIP}:${port}#${email}
EOF
        cat <<EOF >>"/etc/Proxy-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: ss
    server: ${publicIP}
    port: ${port}
    cipher: ${ss2022Method}
    password: "${ss2022Password}"
    udp: true
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"shadowsocks\",\"server\":\"${publicIP}\",\"server_port\":${port},\"method\":\"${ss2022Method}\",\"password\":\"${ss2022Password}\",\"multiplex\":{\"enabled\":true}}]" "/etc/Proxy-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> 二维码 SS2022"
        local ss2022QRCode
        ss2022QRCode=$(echo -n "ss://${ss2022UrlPassword}@${publicIP}:${port}#${email}" | sed 's/:/%3A/g; s/\//%2F/g; s/@/%40/g; s/#/%23/g')
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${ss2022QRCode}\n"
    fi

}

# 账号
showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readSingBoxConfig

    echo
    echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"

    initSubscribeLocalConfig
    # VLESS TCP
    if echo ${currentInstallProtocolType} | grep -q ",0,"; then

        echoContent skyBlue "============================= VLESS TCP TLS_Vision [推荐] ==============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}02_VLESS_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            defaultBase64Code vlesstcp "${currentDefaultPort}${singBoxVLESSVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi

    # VLESS WS
    if echo ${currentInstallProtocolType} | grep -q ",1,"; then
        echoContent skyBlue "\n================================ VLESS WS TLS [仅CDN推荐] ================================\n"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}03_VLESS_WS_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vlessWSPort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vlessWSPort="${singBoxVLESSWSPort}"
            fi
            echo
            local path="${currentPath}ws"

            if [[ ${coreInstallType} == "1" ]]; then
                path="/${currentPath}ws"
            elif [[ "${coreInstallType}" == "2" ]]; then
                path="${singBoxVLESSWSPath}"
            fi

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessws "${vlessWSPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # trojan grpc
    if echo ${currentInstallProtocolType} | grep -q ",2,"; then
        echoContent skyBlue "\n================================  Trojan gRPC TLS [仅CDN推荐]  ================================\n"
        jq .inbounds[0].settings.clients ${configPath}04_trojan_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email)
            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code trojangrpc "${currentDefaultPort}" "${email}${count}" "$(echo "${user}" | jq -r .password)" "${line}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')

        done
    fi
    # VMess WS
    if echo ${currentInstallProtocolType} | grep -q ",3,"; then
        echoContent skyBlue "\n================================ VMess WS TLS [仅CDN推荐]  ================================\n"
        local path="${currentPath}vws"
        if [[ ${coreInstallType} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreInstallType}" == "2" ]]; then
            path="${singBoxVMessWSPath}"
        fi
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}05_VMess_WS_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vmessPort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vmessPort="${singBoxVMessWSPort}"
            fi

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessws "${vmessPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi

    # trojan tcp
    if echo ${currentInstallProtocolType} | grep -q ",4,"; then
        echoContent skyBlue "\n==================================  Trojan TLS [不推荐] ==================================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echoContent skyBlue "\n ---> 账号:${email}"

            defaultBase64Code trojan "${currentDefaultPort}${singBoxTrojanPort}" "${email}" "$(echo "${user}" | jq -r .password)"
        done
    fi
    # VLESS grpc
    if echo ${currentInstallProtocolType} | grep -q ",5,"; then
        echoContent skyBlue "\n=============================== VLESS gRPC TLS [仅CDN推荐]  ===============================\n"
        jq .inbounds[0].settings.clients ${configPath}06_VLESS_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do

            local email=
            email=$(echo "${user}" | jq -r .email)

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessgrpc "${currentDefaultPort}" "${email}${count}" "$(echo "${user}" | jq -r .id)" "${line}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')

        done
    fi
    # hysteria2
    if echo ${currentInstallProtocolType} | grep -q ",6," || [[ -n "${hysteriaPort}" ]]; then
        readPortHopping "hysteria2" "${singBoxHysteria2Port}"
        echoContent skyBlue "\n================================  Hysteria2 TLS [推荐] ================================\n"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        local hysteria2DefaultPort=
        if [[ -n "${hysteria2PortHoppingStart}" && -n "${hysteria2PortHoppingEnd}" ]]; then
            hysteria2DefaultPort="${hysteria2PortHopping}"
        else
            hysteria2DefaultPort=${singBoxHysteria2Port}
        fi

        jq -r -c '.inbounds[]|.users[]' "${path}06_hysteria2_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code hysteria "${hysteria2DefaultPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # VLESS reality vision
    if echo ${currentInstallProtocolType} | grep -q ",7,"; then
        echoContent skyBlue "============================= VLESS reality_vision [推荐]  ==============================\n"
        jq .inbounds[1].settings.clients//.inbounds[0].users ${configPath}07_VLESS_vision_reality_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            defaultBase64Code vlessReality "${xrayVLESSRealityVisionPort}${singBoxVLESSRealityVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # VLESS reality gRPC
    if echo ${currentInstallProtocolType} | grep -q ",8,"; then
        echoContent skyBlue "============================== VLESS reality_gRPC [推荐] ===============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}08_VLESS_vision_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            defaultBase64Code vlessRealityGRPC "${xrayVLESSRealityVisionPort}${singBoxVLESSRealityGRPCPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # tuic
    if echo ${currentInstallProtocolType} | grep -q ",9," || [[ -n "${tuicPort}" ]]; then
        echoContent skyBlue "\n================================  Tuic TLS [推荐]  ================================\n"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[].users[]' "${path}09_tuic_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code tuic "${singBoxTuicPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .uuid)_$(echo "${user}" | jq -r .password)"
        done

    fi
    # naive
    if echo ${currentInstallProtocolType} | grep -q ",10," || [[ -n "${singBoxNaivePort}" ]]; then
        echoContent skyBlue "\n================================  naive TLS [推荐，不支持ClashMeta]  ================================\n"

        jq -r -c '.inbounds[]|.users[]' "${configPath}10_naive_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .username)"
            echo
            defaultBase64Code naive "${singBoxNaivePort}" "$(echo "${user}" | jq -r .username)" "$(echo "${user}" | jq -r .password)"
        done

    fi
    # VMess HTTPUpgrade
    if echo ${currentInstallProtocolType} | grep -q ",11,"; then
        echoContent skyBlue "\n================================ VMess HTTPUpgrade TLS [仅CDN推荐]  ================================\n"
        local path="${currentPath}vws"
        if [[ ${coreInstallType} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreInstallType}" == "2" ]]; then
            path="${singBoxVMessHTTPUpgradePath}"
        fi
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}11_VMess_HTTPUpgrade_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vmessHTTPUpgradePort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vmessHTTPUpgradePort="${singBoxVMessHTTPUpgradePort}"
            fi

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessHTTPUpgrade "${vmessHTTPUpgradePort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # VLESS Reality XHTTP
    if echo ${currentInstallProtocolType} | grep -q ",12,"; then
        echoContent skyBlue "\n================================ VLESS Reality XHTTP TLS [仅CDN推荐] ================================\n"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}12_VLESS_XHTTP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echo
            local path="${currentPath}xHTTP"

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessXHTTP "${xrayVLESSRealityXHTTPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # AnyTLS
    if echo ${currentInstallProtocolType} | grep -q ",13,"; then
        echoContent skyBlue "\n================================  AnyTLS ================================\n"

        jq -r -c '.inbounds[]|.users[]' "${configPath}13_anytls_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code anytls "${singBoxAnyTLSPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # Shadowsocks 2022
    if echo ${currentInstallProtocolType} | grep -q ",14," || [[ -n "${ss2022Port}" ]]; then
        echoContent skyBlue "\n================================  Shadowsocks 2022 ================================\n"
        local path="${singBoxConfigPath}"
        if [[ -f "${path}14_ss2022_inbounds.json" ]]; then
            local serverKey
            local method
            serverKey=$(jq -r '.inbounds[0].password' "${path}14_ss2022_inbounds.json")
            method=$(jq -r '.inbounds[0].method' "${path}14_ss2022_inbounds.json")
            local port
            port=$(jq -r '.inbounds[0].listen_port' "${path}14_ss2022_inbounds.json")

            jq -r -c '.inbounds[]|.users[]' "${path}14_ss2022_inbounds.json" | while read -r user; do
                echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
                echo
                defaultBase64Code ss2022 "${port}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)" "${serverKey}" "${method}"
            done
        fi
    fi
}
# 移除nginx302配置
removeNginx302() {
    local count=
    grep -n "return 302" <"${nginxConfigPath}alone.conf" | while read -r line; do

        if ! echo "${line}" | grep -q "request_uri"; then
            local removeIndex=
            removeIndex=$(echo "${line}" | awk -F "[:]" '{print $1}')
            removeIndex=$((removeIndex + count))
            sed -i "${removeIndex}d" ${nginxConfigPath}alone.conf
            count=$((count - 1))
        fi
    done
}

# 检查302是否成功
checkNginx302() {
    local domain302Status=
    domain302Status=$(curl -s "https://${currentHost}:${currentPort}")
    if echo "${domain302Status}" | grep -q "302"; then
        #        local domain302Result=
        #        domain302Result=$(curl -L -s "https://${currentHost}:${currentPort}")
        #        if [[ -n "${domain302Result}" ]]; then
        echoContent green " ---> 302重定向设置完毕"
        exit 0
        #        fi
    fi
    echoContent red " ---> 302重定向设置失败，请仔细检查是否和示例相同"
    backupNginxConfig restoreBackup
}

# 备份恢复nginx文件
backupNginxConfig() {
    if [[ "$1" == "backup" ]]; then
        cp ${nginxConfigPath}alone.conf /etc/Proxy-agent/alone_backup.conf
        echoContent green " ---> nginx配置文件备份成功"
    fi

    if [[ "$1" == "restoreBackup" ]] && [[ -f "/etc/Proxy-agent/alone_backup.conf" ]]; then
        cp /etc/Proxy-agent/alone_backup.conf ${nginxConfigPath}alone.conf
        echoContent green " ---> nginx配置文件恢复备份成功"
        rm /etc/Proxy-agent/alone_backup.conf
    fi

}
# 添加302配置
addNginx302() {

    local count=1
    grep -n "location / {" <"${nginxConfigPath}alone.conf" | while read -r line; do
        if [[ -n "${line}" ]]; then
            local insertIndex=
            insertIndex="$(echo "${line}" | awk -F "[:]" '{print $1}')"
            insertIndex=$((insertIndex + count))
            sed "${insertIndex}i return 302 '$1';" ${nginxConfigPath}alone.conf >${nginxConfigPath}tmpfile && mv ${nginxConfigPath}tmpfile ${nginxConfigPath}alone.conf
            count=$((count + 1))
        else
            echoContent red " ---> 302添加失败"
            backupNginxConfig restoreBackup
        fi

    done
}

# 更新伪装站
updateNginxBlog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 1
    fi

    echoContent skyBlue "\n进度 $1/${totalProgress} : 更换伪装站点"

    if ! echo "${currentInstallProtocolType}" | grep -q ",0," || [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 由于环境依赖，请先安装Xray-core的VLESS_TCP_TLS_Vision"
        exit 1
    fi
    echoContent red "=============================================================="
    echoContent yellow "# 如需自定义，请手动复制模版文件到 ${nginxStaticPath} \n"
    echoContent yellow "1.新手引导"
    echoContent yellow "2.游戏网站"
    echoContent yellow "3.个人博客01"
    echoContent yellow "4.企业站"
    echoContent yellow "5.解锁加密的音乐文件模版[https://github.com/ix64/unlock-music]"
    echoContent yellow "6.mikutap[https://github.com/HFIProgramming/mikutap]"
    echoContent yellow "7.企业站02"
    echoContent yellow "8.个人博客02"
    echoContent yellow "9.404自动跳转baidu"
    echoContent yellow "10.302重定向网站"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectInstallNginxBlogType

    if [[ "${selectInstallNginxBlogType}" == "10" ]]; then
        if [[ "${coreInstallType}" == "2" ]]; then
            echoContent red "\n ---> 此功能仅支持Xray-core内核，请等待后续更新"
            exit 1
        fi
        echoContent red "\n=============================================================="
        echoContent yellow "重定向的优先级更高，配置302之后如果更改伪装站点，根路由下伪装站点将不起作用"
        echoContent yellow "如想要伪装站点实现作用需删除302重定向配置\n"
        echoContent yellow "1.添加"
        echoContent yellow "2.删除"
        echoContent red "=============================================================="
        read -r -p "请选择:" redirectStatus

        if [[ "${redirectStatus}" == "1" ]]; then
            backupNginxConfig backup
            read -r -p "请输入要重定向的域名,例如 https://www.baidu.com:" redirectDomain
            if ! isValidRedirectUrl "${redirectDomain}"; then
                echoContent red " ---> URL格式无效，必须以 http:// 或 https:// 开头且不含特殊字符"
                exit 1
            fi
            removeNginx302
            addNginx302 "${redirectDomain}"
            handleNginx stop
            handleNginx start
            if [[ -z $(pgrep -f "nginx") ]]; then
                backupNginxConfig restoreBackup
                handleNginx start
                exit 0
            fi
            checkNginx302
            exit 0
        fi
        if [[ "${redirectStatus}" == "2" ]]; then
            removeNginx302
            echoContent green " ---> 移除302重定向成功"
            exit 0
        fi
    fi
    if [[ "${selectInstallNginxBlogType}" =~ ^[1-9]$ ]]; then
        rm -rf "${nginxStaticPath}*"

        if [[ "${release}" == "alpine" ]]; then
            wget -q -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${selectInstallNginxBlogType}.zip"
        else
            wget -q "${wgetShowProgressStatus}" -P "${nginxStaticPath}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/fodder/blog/unable/html${selectInstallNginxBlogType}.zip"
        fi

        unzip -o "${nginxStaticPath}html${selectInstallNginxBlogType}.zip" -d "${nginxStaticPath}" >/dev/null
        rm -f "${nginxStaticPath}html${selectInstallNginxBlogType}.zip*"
        echoContent green " ---> 更换伪站成功"
    else
        echoContent red " ---> 选择错误，请重新选择"
        updateNginxBlog
    fi
}

# 添加新端口
addCorePort() {

    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 1
    fi

    echoContent skyBlue "\n功能 1/${totalProgress} : 添加新端口"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项\n"
    echoContent yellow "支持批量添加"
    echoContent yellow "不影响默认端口的使用"
    echoContent yellow "查看账号时，只会展示默认端口的账号"
    echoContent yellow "不允许有特殊字符，注意逗号的格式"
    echoContent yellow "如已安装hysteria，会同时安装hysteria新端口"
    echoContent yellow "录入示例:2053,2083,2087\n"

    echoContent yellow "1.查看已添加端口"
    echoContent yellow "2.添加端口"
    echoContent yellow "3.删除端口"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        exit 0
    elif [[ "${selectNewPortType}" == "2" ]]; then
        read -r -p "请输入端口号:" newPort
        read -r -p "请输入默认的端口号，同时会更改订阅端口以及节点端口，[回车]默认443:" defaultPort

        if [[ -n "${defaultPort}" && -n "${configPath}" ]]; then
            find "${configPath}" -maxdepth 1 -type f -name "*default*" -exec rm -f {} \;
        fi

        if [[ -n "${newPort}" ]]; then

            while read -r port; do
                if [[ -n "${configPath}" && -n "${port}" ]]; then
                    find "${configPath}" -maxdepth 1 -type f -name "*${port}*" -exec rm -f {} \;
                fi

                local fileName=
                local hysteriaFileName=
                if [[ -n "${defaultPort}" && "${port}" == "${defaultPort}" ]]; then
                    fileName="${configPath}02_dokodemodoor_inbounds_${port}_default.json"
                else
                    fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"
                fi

                if [[ -n ${hysteriaPort} ]]; then
                    hysteriaFileName="${configPath}02_dokodemodoor_inbounds_hysteria_${port}.json"
                fi

                # 开放端口
                allowPort "${port}"
                allowPort "${port}" "udp"

                local settingsPort=443
                if [[ -n "${customPort}" ]]; then
                    settingsPort=${customPort}
                fi

                if [[ -n ${hysteriaFileName} ]]; then
                    cat <<EOF >"${hysteriaFileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${hysteriaPort},
		"network": "udp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-hysteria-${port}"
	}
  ]
}
EOF
                fi
                cat <<EOF >"${fileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${settingsPort},
		"network": "tcp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-${port}"
	}
  ]
}
EOF
            done < <(echo "${newPort}" | tr ',' '\n')

            echoContent green " ---> 添加完毕"
            reloadCore
            addCorePort
        fi
    elif [[ "${selectNewPortType}" == "3" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        read -r -p "请输入要删除的端口编号:" portIndex
        local dokoConfig
        dokoConfig=$(find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}' | grep "${portIndex}:")
        if [[ -n "${dokoConfig}" ]]; then
            rm "${configPath}02_dokodemodoor_inbounds_$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}').json"
            local hysteriaDokodemodoorFilePath=

            hysteriaDokodemodoorFilePath="${configPath}02_dokodemodoor_inbounds_hysteria_$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}').json"
            if [[ -f "${hysteriaDokodemodoorFilePath}" ]]; then
                rm "${hysteriaDokodemodoorFilePath}"
            fi

            reloadCore
            addCorePort
        else
            echoContent yellow "\n ---> 编号输入错误，请重新选择"
            addCorePort
        fi
    fi
}

# 卸载脚本
unInstall() {
    read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        echoContent green " ---> 放弃卸载"
        menu
        exit 0
    fi
    checkBTPanel
    echoContent yellow " ---> 脚本不会删除acme相关配置，删除请手动执行 [rm -rf /root/.acme.sh]"
    handleNginx stop
    if [[ -z $(pgrep -f "nginx") ]]; then
        echoContent green " ---> 停止Nginx成功"
    fi
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray stop
            rc-update del xray default
            rm -rf /etc/init.d/xray
            echoContent green " ---> 删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
            handleSingBox stop
            rc-update del sing-box default
            rm -rf /etc/init.d/sing-box
            echoContent green " ---> 删除sing-box开机自启完成"
        fi
    else
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray stop
            rm -rf /etc/systemd/system/xray.service
            echoContent green " ---> 删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
            handleSingBox stop
            rm -rf /etc/systemd/system/sing-box.service
            echoContent green " ---> 删除sing-box开机自启完成"
        fi
    fi

    rm -rf /etc/Proxy-agent
    rm -rf "${nginxConfigPath}alone.conf"
    rm -rf "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1
    rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1

    unInstallSubscribe

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        rm -rf "${nginxStaticPath}"
        echoContent green " ---> 删除伪装网站完成"
    fi

    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
    rm -rf /usr/bin/pasly
    rm -rf /usr/sbin/pasly
    echoContent green " ---> 卸载快捷方式完成"
    echoContent green " ---> 卸载 Proxy-agent 脚本完成"
}

# CDN节点管理
manageCDN() {
    echoContent skyBlue "\n进度 $1/1 : CDN节点管理"
    local setCDNDomain=

    if echo "${currentInstallProtocolType}" | grep -qE ",1,|,2,|,3,|,5,|,11,"; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项"
        echoContent yellow "\n教程地址:"
        echoContent skyBlue "如需优化 Cloudflare 回源 IP，可根据本地网络状况选择可用的 IP 段。"
        echoContent red "\n如对Cloudflare优化不了解，请不要使用"

        echoContent yellow "1.CNAME www.digitalocean.com"
        echoContent yellow "2.CNAME who.int"
        echoContent yellow "3.CNAME blog.hostmonit.com"
        echoContent yellow "4.CNAME www.visa.com.hk"
        echoContent yellow "5.手动输入[可输入多个，比如: 1.1.1.1,1.1.2.2,cloudflare.com 逗号分隔]"
        echoContent yellow "6.移除CDN节点"
        echoContent red "=============================================================="
        read -r -p "请选择:" selectCDNType
        case ${selectCDNType} in
        1)
            setCDNDomain="www.digitalocean.com"
            ;;
        2)
            setCDNDomain="who.int"
            ;;
        3)
            setCDNDomain="blog.hostmonit.com"
            ;;
        4)
            setCDNDomain="www.visa.com.hk"
            ;;
        5)
            read -r -p "请输入想要自定义CDN IP或者域名:" setCDNDomain
            # 验证输入不包含危险字符
            if [[ "${setCDNDomain}" =~ [\;\|\&\$\`\(\)\{\}\[\]\<\>\!\#\*\?\~\'\"] ]] || [[ "${setCDNDomain}" =~ [[:space:]] ]]; then
                echoContent red " ---> 输入包含不安全字符"
                exit 1
            fi
            ;;
        6)
            echo >/etc/Proxy-agent/cdn
            echoContent green " ---> 移除成功"
            exit 0
            ;;
        esac

        if [[ -n "${setCDNDomain}" ]]; then
            echo >/etc/Proxy-agent/cdn
            echo "${setCDNDomain}" >"/etc/Proxy-agent/cdn"
            echoContent green " ---> 修改CDN成功"
            subscribe false false
        else
            echoContent red " ---> 不可以为空，请重新输入"
            manageCDN 1
        fi
    else
        echoContent yellow "\n教程地址:"
        echoContent skyBlue "请根据网络状况选择合适的 Cloudflare 回源 IP。\n"
        echoContent red " ---> 未检测到可以使用的协议，仅支持ws、grpc、HTTPUpgrade相关的协议"
    fi
}
# 自定义uuid
customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    echo
    if [[ -z "${currentCustomUUID}" ]]; then
        if [[ "${selectInstallType}" == "1" || "${coreInstallType}" == "1" ]]; then
            currentCustomUUID=$(${ctlPath} uuid)
        elif [[ "${selectInstallType}" == "2" || "${coreInstallType}" == "2" ]]; then
            currentCustomUUID=$(${ctlPath} generate uuid)
        fi

        echoContent yellow "uuid：${currentCustomUUID}\n"

    else
        local checkUUID=
        if [[ "${coreInstallType}" == "1" ]]; then
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" ".inbounds[0].settings.clients[] | select(.uuid | index(\$currentUUID) != null) | .name" ${configPath}${frontingType}.json)
        elif [[ "${coreInstallType}" == "2" ]]; then
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" ".inbounds[0].users[] | select(.uuid | index(\$currentUUID) != null) | .name//.username" ${configPath}${frontingType}.json)
        fi

        if [[ -n "${checkUUID}" ]]; then
            echoContent red " ---> UUID不可重复"
            exit 1
        fi
    fi
}

# 自定义email
customUserEmail() {
    read -r -p "请输入合法的email，[回车]随机email:" currentCustomEmail
    echo
    if [[ -z "${currentCustomEmail}" ]]; then
        currentCustomEmail="${currentCustomUUID}"
        echoContent yellow "email: ${currentCustomEmail}\n"
    else
        local checkEmail=
        if [[ "${coreInstallType}" == "1" ]]; then
            local frontingTypeConfig="${frontingType}"
            if [[ "${currentInstallProtocolType}" == ",7,8," ]]; then
                frontingTypeConfig="07_VLESS_vision_reality_inbounds"
            fi

            checkEmail=$(jq -r --arg currentEmail "$currentCustomEmail" ".inbounds[0].settings.clients[] | select(.name | index(\$currentEmail) != null) | .name" ${configPath}${frontingTypeConfig}.json)
        elif
            [[ "${coreInstallType}" == "2" ]]
        then
            checkEmail=$(jq -r --arg currentEmail "$currentCustomEmail" ".inbounds[0].users[] | select(.name | index(\$currentEmail) != null) | .name" ${configPath}${frontingType}.json)
        fi

        if [[ -n "${checkEmail}" ]]; then
            echoContent red " ---> email不可重复"
            exit 1
        fi
    fi
}

# 添加用户
addUser() {
    read -r -p "请输入要添加的用户数量:" userNum
    echo
    if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
        echoContent red " ---> 输入有误，请重新输入"
        exit 1
    fi
    local userConfig=
    if [[ "${coreInstallType}" == "1" ]]; then
        userConfig=".inbounds[0].settings.clients"
    elif [[ "${coreInstallType}" == "2" ]]; then
        userConfig=".inbounds[0].users"
    fi

    while [[ ${userNum} -gt 0 ]]; do
        readConfigHostPathUUID
        local users=
        ((userNum--)) || true

        customUUID
        customUserEmail

        uuid=${currentCustomUUID}
        email=${currentCustomEmail}

        # VLESS TCP
        if echo "${currentInstallProtocolType}" | grep -q ",0,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 0 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 0 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}02_VLESS_TCP_inbounds.json)
            echo "${clients}" | jq . >${configPath}02_VLESS_TCP_inbounds.json
        fi

        # VLESS WS
        if echo "${currentInstallProtocolType}" | grep -q ",1,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 1 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 1 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}03_VLESS_WS_inbounds.json)
            echo "${clients}" | jq . >${configPath}03_VLESS_WS_inbounds.json
        fi

        # trojan grpc
        if echo "${currentInstallProtocolType}" | grep -q ",2,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 2 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 2 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}04_trojan_gRPC_inbounds.json)
            echo "${clients}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
        fi
        # VMess WS
        if echo "${currentInstallProtocolType}" | grep -q ",3,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 3 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 3 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}05_VMess_WS_inbounds.json)
            echo "${clients}" | jq . >${configPath}05_VMess_WS_inbounds.json
        fi
        # trojan tcp
        if echo "${currentInstallProtocolType}" | grep -q ",4,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 4 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 4 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}04_trojan_TCP_inbounds.json)
            echo "${clients}" | jq . >${configPath}04_trojan_TCP_inbounds.json
        fi

        # vless grpc
        if echo "${currentInstallProtocolType}" | grep -q ",5,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 5 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 5 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}06_VLESS_gRPC_inbounds.json)
            echo "${clients}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
        fi

        # vless reality vision
        if echo "${currentInstallProtocolType}" | grep -q ",7,"; then
            local clients=
            local realityUserConfig=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 7 "${uuid}" "${email}")
                realityUserConfig=".inbounds[1].settings.clients"
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 7 "${uuid}" "${email}")
                realityUserConfig=".inbounds[0].users"
            fi
            clients=$(jq -r "${realityUserConfig} = ${clients}" ${configPath}07_VLESS_vision_reality_inbounds.json)
            echo "${clients}" | jq . >${configPath}07_VLESS_vision_reality_inbounds.json
        fi

        # vless reality grpc
        if echo "${currentInstallProtocolType}" | grep -q ",8,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 8 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 8 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}08_VLESS_vision_gRPC_inbounds.json)
            echo "${clients}" | jq . >${configPath}08_VLESS_vision_gRPC_inbounds.json
        fi

        # hysteria2
        if echo ${currentInstallProtocolType} | grep -q ",6,"; then
            local clients=

            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 6 "${uuid}" "${email}")
            elif [[ -n "${singBoxConfigPath}" ]]; then
                clients=$(initSingBoxClients 6 "${uuid}" "${email}")
            fi

            clients=$(jq -r ".inbounds[0].users = ${clients}" "${singBoxConfigPath}06_hysteria2_inbounds.json")
            echo "${clients}" | jq . >"${singBoxConfigPath}06_hysteria2_inbounds.json"
        fi

        # tuic
        if echo ${currentInstallProtocolType} | grep -q ",9,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 9 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 9 "${uuid}" "${email}")
            fi

            clients=$(jq -r ".inbounds[0].users = ${clients}" "${singBoxConfigPath}09_tuic_inbounds.json")

            echo "${clients}" | jq . >"${singBoxConfigPath}09_tuic_inbounds.json"
        fi
        # naive
        if echo ${currentInstallProtocolType} | grep -q ",10,"; then
            local clients=
            clients=$(initSingBoxClients 10 "${uuid}" "${email}")
            clients=$(jq -r ".inbounds[0].users = ${clients}" "${singBoxConfigPath}10_naive_inbounds.json")

            echo "${clients}" | jq . >"${singBoxConfigPath}10_naive_inbounds.json"
        fi
        # VMess WS
        if echo "${currentInstallProtocolType}" | grep -q ",11,"; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 11 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 11 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}11_VMess_HTTPUpgrade_inbounds.json)
            echo "${clients}" | jq . >${configPath}11_VMess_HTTPUpgrade_inbounds.json
        fi
        # anytls
        if echo "${currentInstallProtocolType}" | grep -q ",13,"; then
            local clients=
            clients=$(initSingBoxClients 13 "${uuid}" "${email}")

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}13_anytls_inbounds.json)
            echo "${clients}" | jq . >${configPath}13_anytls_inbounds.json
        fi
        # Shadowsocks 2022
        if echo "${currentInstallProtocolType}" | grep -q ",14,"; then
            local clients=
            clients=$(initSingBoxClients 14 "${uuid}" "${email}")

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}14_ss2022_inbounds.json)
            echo "${clients}" | jq . >${configPath}14_ss2022_inbounds.json
        fi
    done
    reloadCore
    echoContent green " ---> 添加完成"
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    manageAccount 1
}
# 移除用户
removeUser() {
    local userConfigType=
    if [[ -n "${frontingType}" ]]; then
        userConfigType="${frontingType}"
    elif [[ -n "${frontingTypeReality}" ]]; then
        userConfigType="${frontingTypeReality}"
    fi

    local uuid=
    if [[ -n "${userConfigType}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            jq -r -c '(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]?|.email' ${configPath}${userConfigType}.json | awk '{print NR""":"$0}'
            read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
            if [[ $(jq -r '(.inbounds[0].settings.clients // .inbounds[1].settings.clients)?|length' ${configPath}${userConfigType}.json) -lt ${delUserIndex} ]]; then
                echoContent red " ---> 选择错误"
            else
                delUserIndex=$((delUserIndex - 1))
            fi
        elif [[ "${coreInstallType}" == "2" ]]; then
            jq -r -c .inbounds[0].users[].name//.inbounds[0].users[].username ${configPath}${userConfigType}.json | awk '{print NR""":"$0}'
            read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
            if [[ $(jq -r '.inbounds[0].users|length' ${configPath}${userConfigType}.json) -lt ${delUserIndex} ]]; then
                echoContent red " ---> 选择错误"
            else
                delUserIndex=$((delUserIndex - 1))
            fi
        fi
    fi

    if [[ -n "${delUserIndex}" ]]; then

        if echo ${currentInstallProtocolType} | grep -q ",0,"; then
            local vlessVision
            vlessVision=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}02_VLESS_TCP_inbounds.json)
            echo "${vlessVision}" | jq . >${configPath}02_VLESS_TCP_inbounds.json
        fi
        if echo ${currentInstallProtocolType} | grep -q ",1,"; then
            local vlessWSResult
            vlessWSResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}03_VLESS_WS_inbounds.json)
            echo "${vlessWSResult}" | jq . >${configPath}03_VLESS_WS_inbounds.json
        fi

        if echo ${currentInstallProtocolType} | grep -q ",2,"; then
            local trojangRPCUsers
            trojangRPCUsers=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}04_trojan_gRPC_inbounds.json)
            echo "${trojangRPCUsers}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
        fi

        if echo ${currentInstallProtocolType} | grep -q ",3,"; then
            local vmessWSResult
            vmessWSResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}05_VMess_WS_inbounds.json)
            echo "${vmessWSResult}" | jq . >${configPath}05_VMess_WS_inbounds.json
        fi

        if echo ${currentInstallProtocolType} | grep -q ",5,"; then
            local vlessGRPCResult
            vlessGRPCResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}06_VLESS_gRPC_inbounds.json)
            echo "${vlessGRPCResult}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
        fi

        if echo ${currentInstallProtocolType} | grep -q ",4,"; then
            local trojanTCPResult
            trojanTCPResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}04_trojan_TCP_inbounds.json)
            echo "${trojanTCPResult}" | jq . >${configPath}04_trojan_TCP_inbounds.json
        fi

        if echo ${currentInstallProtocolType} | grep -q ",7,"; then
            local vlessRealityResult
            vlessRealityResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[1].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}07_VLESS_vision_reality_inbounds.json)
            echo "${vlessRealityResult}" | jq . >${configPath}07_VLESS_vision_reality_inbounds.json
        fi
        if echo ${currentInstallProtocolType} | grep -q ",8,"; then
            local vlessRealityGRPCResult
            vlessRealityGRPCResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}08_VLESS_vision_gRPC_inbounds.json)
            echo "${vlessRealityGRPCResult}" | jq . >${configPath}08_VLESS_vision_gRPC_inbounds.json
        fi

        if echo ${currentInstallProtocolType} | grep -q ",6,"; then
            local hysteriaResult
            hysteriaResult=$(jq -r 'del(.inbounds[0].users['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            echo "${hysteriaResult}" | jq . >"${singBoxConfigPath}06_hysteria2_inbounds.json"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",9,"; then
            local tuicResult
            tuicResult=$(jq -r 'del(.inbounds[0].users['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' "${singBoxConfigPath}09_tuic_inbounds.json")
            echo "${tuicResult}" | jq . >"${singBoxConfigPath}09_tuic_inbounds.json"
        fi
        if echo ${currentInstallProtocolType} | grep -q ",10,"; then
            local naiveResult
            naiveResult=$(jq -r 'del(.inbounds[0].users['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' "${singBoxConfigPath}10_naive_inbounds.json")
            echo "${naiveResult}" | jq . >"${singBoxConfigPath}10_naive_inbounds.json"
        fi
        # VMess HTTPUpgrade
        if echo ${currentInstallProtocolType} | grep -q ",11,"; then
            local vmessHTTPUpgradeResult
            vmessHTTPUpgradeResult=$(jq -r 'del(.inbounds[0].users['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json")
            echo "${vmessHTTPUpgradeResult}" | jq . >"${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json"
            echo "${vmessHTTPUpgradeResult}" | jq . >${configPath}11_VMess_HTTPUpgrade_inbounds.json
        fi
        # Shadowsocks 2022
        if echo ${currentInstallProtocolType} | grep -q ",14,"; then
            local ss2022Result
            ss2022Result=$(jq -r 'del(.inbounds[0].users['${delUserIndex}'])' "${singBoxConfigPath}14_ss2022_inbounds.json")
            echo "${ss2022Result}" | jq . >"${singBoxConfigPath}14_ss2022_inbounds.json"
        fi
        reloadCore
        readNginxSubscribe
        if [[ -n "${subscribePort}" ]]; then
            subscribe false
        fi
    fi
    manageAccount 1
}
# 更新脚本
updateV2RayAgent() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 更新 Proxy-agent 脚本"

    local installDir="/etc/Proxy-agent"
    local latestVersion=""
    local rawBase="https://raw.githubusercontent.com/Lynthar/Proxy-agent/master"

    # 检查 GitHub Release 最新版本
    echoContent yellow " ---> 检查最新版本..."

    # 确保函数存在才调用
    if type getLatestReleaseVersion &>/dev/null; then
        latestVersion=$(getLatestReleaseVersion 2>/dev/null)
    fi

    if [[ -n "${latestVersion}" && "${latestVersion}" != "null" ]]; then
        echoContent green " ---> 发现最新 Release: ${latestVersion}"

        # 比较版本（确保函数存在）
        if type compareVersions &>/dev/null; then
            if ! compareVersions "${SCRIPT_VERSION}" "${latestVersion}"; then
                echoContent green " ---> 当前已是最新版本 (${SCRIPT_VERSION})"
                echoContent yellow " ---> 如需强制更新，请使用手动命令"
                read -r -p "是否继续更新? [y/N]: " forceUpdate
                if [[ "${forceUpdate}" != "y" && "${forceUpdate}" != "Y" ]]; then
                    menu
                    return
                fi
            fi
        fi
    else
        echoContent yellow " ---> 使用 master 分支更新"
        latestVersion=""
    fi

    # 下载新版本脚本
    echoContent yellow " ---> 下载脚本文件..."
    rm -rf "${installDir}/install.sh"

    if [[ "${release}" == "alpine" ]]; then
        wget -c -q -P "${installDir}/" -N "${rawBase}/install.sh"
    else
        wget -c -q "${wgetShowProgressStatus}" -P "${installDir}/" -N "${rawBase}/install.sh"
    fi

    if [[ ! -f "${installDir}/install.sh" ]]; then
        echoContent red " ---> 下载脚本失败!"
        echoContent yellow "请手动执行: wget -P /root -N ${rawBase}/install.sh"
        exit 1
    fi
    chmod 700 "${installDir}/install.sh"

    # 下载 VERSION 文件
    echoContent yellow " ---> 下载版本文件..."
    if [[ -n "${latestVersion}" ]]; then
        # 从 Release tag 提取版本号保存
        echo "${latestVersion#v}" > "${installDir}/VERSION"
    else
        wget -c -q -O "${installDir}/VERSION" "${rawBase}/VERSION" 2>/dev/null || true
    fi

    # 下载/更新 lib 目录模块
    echoContent yellow " ---> 下载模块文件..."
    mkdir -p "${installDir}/lib"
    local moduleCount=0
    for module in i18n constants utils json-utils system-detect service-control protocol-registry config-reader; do
        if wget -c -q -O "${installDir}/lib/${module}.sh" "${rawBase}/lib/${module}.sh" 2>/dev/null; then
            ((moduleCount++))
        fi
    done
    echoContent green " ---> 已下载 ${moduleCount} 个模块"

    # 下载/更新语言文件
    echoContent yellow " ---> 下载语言文件..."
    mkdir -p "${installDir}/shell/lang"
    for langFile in zh_CN en_US loader; do
        wget -c -q -O "${installDir}/shell/lang/${langFile}.sh" "${rawBase}/shell/lang/${langFile}.sh" 2>/dev/null || true
    done

    # 读取新版本号
    local version=""
    if [[ -f "${installDir}/VERSION" && -s "${installDir}/VERSION" ]]; then
        version="v$(cat "${installDir}/VERSION" 2>/dev/null | tr -d '[:space:]')"
    elif [[ -n "${latestVersion}" ]]; then
        version="${latestVersion}"
    else
        version="latest"
    fi

    echoContent green "\n ---> 更新完毕"
    echoContent yellow " ---> 请手动执行[pasly]打开脚本"
    echoContent green " ---> 当前版本: ${version}"
    echoContent yellow "\n如更新不成功，请手动执行下面命令\n"
    echoContent skyBlue "wget -P /root -N ${rawBase}/install.sh && chmod 700 /root/install.sh && /root/install.sh"
    echo
    exit 0
}

# 防火墙
handleFirewall() {
    if systemctl status ufw 2>/dev/null | grep -q "active (exited)" && [[ "$1" == "stop" ]]; then
        systemctl stop ufw >/dev/null 2>&1
        systemctl disable ufw >/dev/null 2>&1
        echoContent green " ---> ufw关闭成功"

    fi

    if systemctl status firewalld 2>/dev/null | grep -q "active (running)" && [[ "$1" == "stop" ]]; then
        systemctl stop firewalld >/dev/null 2>&1
        systemctl disable firewalld >/dev/null 2>&1
        echoContent green " ---> firewalld关闭成功"
    fi
}

# 安装BBR
bbrInstall() {
    echoContent red "\n=============================================================="
    echoContent green "BBR、DD脚本用的[ylx2016]的成熟作品，地址[https://github.com/ylx2016/Linux-NetSpeed]，请熟知"
    echoContent yellow "1.安装脚本【推荐原版BBR+FQ】"
    echoContent yellow "2.回退主目录"
    echoContent red "=============================================================="
    read -r -p "请选择:" installBBRStatus
    if [[ "${installBBRStatus}" == "1" ]]; then
        wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
    else
        menu
    fi
}

# 查看、检查日志
checkLog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 1
    fi
    if [[ -z "${configPath}" && -z "${realityStatus}" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 1
    fi
    local realityLogShow=
    local logStatus=false
    local currentLogLevel="warning"
    local accessLogPath=
    local errorLogPath=
    if [[ -f "${configPath}00_log.json" ]]; then
        if grep -q "access" ${configPath}00_log.json; then
            logStatus=true
        fi
        currentLogLevel=$(jq -r '.log.loglevel // "warning"' ${configPath}00_log.json)
        accessLogPath=$(jq -r '.log.access // empty' ${configPath}00_log.json)
        errorLogPath=$(jq -r '.log.error // empty' ${configPath}00_log.json)
    fi

    writeLogConfig() {
        local accessPath=$1
        local errorPath=$2
        local level=$3
        {
            echo "{"
            echo "  \"log\": {"
            if [[ -n "${accessPath}" ]]; then
                echo "    \"access\": \"${accessPath}\"," 
            fi
            echo "    \"error\": \"${errorPath}\"," 
            echo "    \"loglevel\": \"${level}\"," 
            echo "    \"dnsLog\": false"
            echo "  }"
            echo "}"
        } >${configPath}00_log.json
    }

    updateRealityLogShow() {
        if [[ -n ${realityStatus} ]]; then
            local vlessVisionRealityInbounds
            vlessVisionRealityInbounds=$(jq -r ".inbounds[0].streamSettings.realitySettings.show=${1}" ${configPath}07_VLESS_vision_reality_inbounds.json)
            echo "${vlessVisionRealityInbounds}" | jq . >${configPath}07_VLESS_vision_reality_inbounds.json
        fi
    }

    echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
    echoContent red "\n=============================================================="
    echoContent yellow "# 建议仅调试时打开access日志\n"

    if [[ "${logStatus}" == "false" ]]; then
        echoContent yellow "1.打开access日志"
    else
        echoContent yellow "1.关闭access日志"
    fi

    echoContent yellow "2.监听access日志"
    echoContent yellow "3.监听error日志"
    echoContent yellow "4.查看证书定时任务日志"
    echoContent yellow "5.查看证书安装日志"
    echoContent yellow "6.清空日志"
    echoContent yellow "7.日志级别(当前:${currentLogLevel})"
    echoContent red "=============================================================="

    read -r -p "请选择:" selectAccessLogType
    local configPathLog=${configPath//conf\//}
    local defaultAccessPath=${accessLogPath:-${configPathLog}access.log}
    local defaultErrorPath=${errorLogPath:-${configPathLog}error.log}

    case ${selectAccessLogType} in
    1)
        if [[ "${logStatus}" == "false" ]]; then
            realityLogShow=true
            writeLogConfig "${defaultAccessPath}" "${defaultErrorPath}" "${currentLogLevel}"
        elif [[ "${logStatus}" == "true" ]]; then
            realityLogShow=false
            writeLogConfig "" "${defaultErrorPath}" "${currentLogLevel}"
        fi

        updateRealityLogShow "${realityLogShow}"
        reloadCore
        checkLog 1
        ;;
    2)
        tail -f ${defaultAccessPath}
        ;;
    3)
        tail -f ${defaultErrorPath}
        ;;
    4)
        if [[ ! -f "/etc/Proxy-agent/crontab_tls.log" ]]; then
            touch /etc/Proxy-agent/crontab_tls.log
        fi
        tail -n 100 /etc/Proxy-agent/crontab_tls.log
        ;;
    5)
        tail -n 100 /etc/Proxy-agent/tls/acme.log
        ;;
    6)
        echo >${defaultAccessPath}
        echo >${defaultErrorPath}
        ;;
    7)
        echoContent yellow "\n日志级别切换(当前:${currentLogLevel})"
        echoContent yellow "1.warning(默认)"
        echoContent yellow "2.info"
        echoContent yellow "3.debug"
        echoContent yellow "4.最小日志(写入/tmp，适合无盘/调试完毕后使用)"
        read -r -p "请选择:" selectLogLevel
        local targetAccessPath=""
        case ${selectLogLevel} in
        1)
            currentLogLevel="warning"
            ;;
        2)
            currentLogLevel="info"
            ;;
        3)
            currentLogLevel="debug"
            ;;
        4)
            local tmpLogDir="/tmp/Proxy-agent"
            mkdir -p "${tmpLogDir}"
            currentLogLevel="warning"
            writeLogConfig "${tmpLogDir}/access.log" "${tmpLogDir}/error.log" "${currentLogLevel}"
            updateRealityLogShow "false"
            reloadCore
            echoContent green "\n ---> 已切换为最小日志模式"
            echoContent yellow " ---> access/error 将写入 ${tmpLogDir}/，系统临时目录会在重启或周期清理时自动清空，如需立即清理可执行 [rm -f ${tmpLogDir}/*.log]"
            checkLog 1
            ;;
        esac
        if [[ "${selectLogLevel}" != "4" ]]; then
            if [[ "${logStatus}" == "true" ]]; then
                targetAccessPath=${defaultAccessPath}
                realityLogShow=true
            else
                realityLogShow=false
            fi
            writeLogConfig "${targetAccessPath}" "${defaultErrorPath}" "${currentLogLevel}"
            updateRealityLogShow "${realityLogShow}"
            reloadCore
            checkLog 1
        fi
        ;;
    esac
}

# 脚本快捷方式
aliasInstall() {

    if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/Proxy-agent" ]] && grep -Eq "作者[:：]Lynthar|Proxy-agent" "$HOME/install.sh"; then
        mv "$HOME/install.sh" /etc/Proxy-agent/install.sh

        # 复制 VERSION 文件（如果存在于脚本目录）
        if [[ -f "${_SCRIPT_DIR}/VERSION" ]]; then
            cp -f "${_SCRIPT_DIR}/VERSION" /etc/Proxy-agent/VERSION 2>/dev/null
        fi

        # 复制 lib 目录（如果存在）
        if [[ -d "${_SCRIPT_DIR}/lib" ]]; then
            mkdir -p /etc/Proxy-agent/lib
            cp -rf "${_SCRIPT_DIR}/lib/"*.sh /etc/Proxy-agent/lib/ 2>/dev/null
        fi

        # 复制 shell/lang 目录（如果存在）
        if [[ -d "${_SCRIPT_DIR}/shell/lang" ]]; then
            mkdir -p /etc/Proxy-agent/shell/lang
            cp -rf "${_SCRIPT_DIR}/shell/lang/"*.sh /etc/Proxy-agent/shell/lang/ 2>/dev/null
        fi

        local paslyType=
        if [[ -d "/usr/bin/" ]]; then
            rm -f "/usr/bin/vasma"
            if [[ ! -f "/usr/bin/pasly" ]]; then
                ln -s /etc/Proxy-agent/install.sh /usr/bin/pasly
                chmod 700 /usr/bin/pasly
                paslyType=true
            fi

            rm -rf "$HOME/install.sh"
        elif [[ -d "/usr/sbin" ]]; then
            rm -f "/usr/sbin/vasma"
            if [[ ! -f "/usr/sbin/pasly" ]]; then
                ln -s /etc/Proxy-agent/install.sh /usr/sbin/pasly
                chmod 700 /usr/sbin/pasly
                paslyType=true
            fi
            rm -rf "$HOME/install.sh"
        fi
        if [[ "${paslyType}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[pasly]重新打开脚本"
        fi
    fi
}

# 检查ipv6、ipv4
checkIPv6() {
    currentIPv6IP=$(curl -s -6 -m 4 https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)

    if [[ -z "${currentIPv6IP}" ]]; then
        echoContent red " ---> 不支持ipv6"
        exit 1
    fi
}

# ipv6 分流
ipv6Routing() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi

    checkIPv6
    echoContent skyBlue "\n功能 1/${totalProgress} : IPv6分流"
    echoContent red "\n=============================================================="
    echoContent yellow "1.查看已分流域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.设置IPv6全局"
    echoContent yellow "4.卸载IPv6分流"
    echoContent red "=============================================================="
    read -r -p "请选择:" ipv6Status
    if [[ "${ipv6Status}" == "1" ]]; then
        showIPv6Routing
        exit 0
    elif [[ "${ipv6Status}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "# 注意事项"
        echoContent yellow "# 使用提示：请参考 documents 目录中的分流与策略说明 \n"

        read -r -p "请按照上面示例录入域名:" domainList
        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayRouting IPv6_out outboundTag "${domainList}"
            addXrayOutbound IPv6_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "IPv6_out" "${domainList}" "IPv6_route"
            addSingBoxOutbound 01_direct_outbound
            addSingBoxOutbound IPv6_out
            addSingBoxOutbound IPv4_out
        fi

        echoContent green " ---> 添加完毕"

    elif [[ "${ipv6Status}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.会删除所有设置的分流规则"
        echoContent yellow "2.会删除IPv6之外的所有出站规则\n"
        read -r -p "是否确认设置？[y/n]:" IPv6OutStatus

        if [[ "${IPv6OutStatus}" == "y" ]]; then
            if [[ "${coreInstallType}" == "1" ]]; then
                addXrayOutbound IPv6_out
                removeXrayOutbound IPv4_out
                removeXrayOutbound z_direct_outbound
                removeXrayOutbound blackhole_out
                removeXrayOutbound wireguard_out_IPv4
                removeXrayOutbound wireguard_out_IPv6
                removeXrayOutbound socks5_outbound

                rm ${configPath}09_routing.json >/dev/null 2>&1
            fi
            if [[ -n "${singBoxConfigPath}" ]]; then

                removeSingBoxConfig IPv4_out

                removeSingBoxConfig wireguard_endpoints_IPv4_route
                removeSingBoxConfig wireguard_endpoints_IPv6_route
                removeSingBoxConfig wireguard_endpoints_IPv4
                removeSingBoxConfig wireguard_endpoints_IPv6

                removeSingBoxConfig socks5_02_inbound_route

                removeSingBoxConfig IPv6_route

                removeSingBoxConfig 01_direct_outbound

                addSingBoxOutbound IPv6_out

            fi

            echoContent green " ---> IPv6全局出站设置完毕"
        else

            echoContent green " ---> 放弃设置"
            exit 0
        fi

    elif [[ "${ipv6Status}" == "4" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting IPv6_out outboundTag

            removeXrayOutbound IPv6_out
            addXrayOutbound "z_direct_outbound"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig IPv6_out
            removeSingBoxConfig "IPv6_route"
            addSingBoxOutbound "01_direct_outbound"
        fi

        echoContent green " ---> IPv6分流卸载成功"
    else
        echoContent red " ---> 选择错误"
        exit 1
    fi

    reloadCore
}

# ipv6分流规则展示
showIPv6Routing() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core："
            jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6_out")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}IPv6_out.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已设置IPv6全局分流"
        else
            echoContent yellow " ---> 未安装IPv6分流"
        fi

    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}IPv6_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]|select (.outbound=="IPv6_out")' "${singBoxConfigPath}IPv6_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}IPv6_route.json" && -f "${singBoxConfigPath}IPv6_out.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已设置IPv6全局分流"
        else
            echoContent yellow " ---> 未安装IPv6分流"
        fi
    fi
}
# bt下载管理
btTools() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核，请等待后续更新"
        exit 1
    fi
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi

    echoContent skyBlue "\n功能 1/${totalProgress} : bt下载管理"
    echoContent red "\n=============================================================="

    if [[ -f "${configPath}09_routing.json" ]] && grep -q bittorrent <"${configPath}09_routing.json"; then
        echoContent yellow "当前状态:已禁止下载BT"
    else
        echoContent yellow "当前状态:允许下载BT"
    fi

    echoContent yellow "1.禁止下载BT"
    echoContent yellow "2.允许下载BT"
    echoContent red "=============================================================="
    read -r -p "请选择:" btStatus
    if [[ "${btStatus}" == "1" ]]; then

        if [[ -f "${configPath}09_routing.json" ]]; then

            unInstallRouting blackhole_out outboundTag bittorrent

            routing=$(jq -r '.routing.rules += [{"type":"field","outboundTag":"blackhole_out","protocol":["bittorrent"]}]' ${configPath}09_routing.json)

            echo "${routing}" | jq . >${configPath}09_routing.json

        else
            cat <<EOF >${configPath}09_routing.json
{
    "routing":{
        "domainStrategy": "IPOnDemand",
        "rules": [
          {
            "type": "field",
            "outboundTag": "blackhole_out",
            "protocol": [ "bittorrent" ]
          }
        ]
  }
}
EOF
        fi

        installSniffing
        removeXrayOutbound blackhole_out
        addXrayOutbound blackhole_out

        echoContent green " ---> 禁止BT下载"

    elif [[ "${btStatus}" == "2" ]]; then

        unInstallSniffing

        unInstallRouting blackhole_out outboundTag bittorrent

        echoContent green " ---> 允许BT下载"
    else
        echoContent red " ---> 选择错误"
        exit 1
    fi

    reloadCore
}

# 域名黑名单
blacklist() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi

    echoContent skyBlue "\n进度  $1/${totalProgress} : 域名黑名单"
    echoContent red "\n=============================================================="
    echoContent yellow "1.查看已屏蔽域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.屏蔽大陆域名"
    echoContent yellow "4.卸载黑名单"
    echoContent red "=============================================================="

    read -r -p "请选择:" blacklistStatus
    if [[ "${blacklistStatus}" == "1" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="blackhole_out")|.domain' ${configPath}09_routing.json | jq -r
        exit 0
    elif [[ "${blacklistStatus}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.规则支持预定义域名列表[https://github.com/v2fly/domain-list-community]"
        echoContent yellow "2.规则支持自定义域名"
        echoContent yellow "3.录入示例:speedtest,facebook,cn,example.com"
        echoContent yellow "4.如果域名在预定义域名列表中存在则使用 geosite:xx，如果不存在则默认使用输入的域名"
        echoContent yellow "5.添加规则为增量配置，不会删除之前设置的内容\n"
        read -r -p "请按照上面示例录入域名:" domainList
        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayRouting blackhole_out outboundTag "${domainList}"
            addXrayOutbound blackhole_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "block_domain_outbound" "${domainList}" "block_domain_route"
            addSingBoxOutbound "block_domain_outbound"
            addSingBoxOutbound "01_direct_outbound"
        fi
        echoContent green " ---> 添加完毕"

    elif [[ "${blacklistStatus}" == "3" ]]; then

        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting blackhole_out outboundTag

            addXrayRouting blackhole_out outboundTag "cn"

            addXrayOutbound blackhole_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then

            addSingBoxRouteRule "cn_block_outbound" "cn" "cn_block_route"

            addSingBoxRouteRule "01_direct_outbound" "googleapis.com,googleapis.cn,xn--ngstr-lra8j.com,gstatic.com" "cn_01_google_play_route"

            addSingBoxOutbound "cn_block_outbound"
            addSingBoxOutbound "01_direct_outbound"
        fi

        echoContent green " ---> 屏蔽大陆域名完毕"

    elif [[ "${blacklistStatus}" == "4" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting blackhole_out outboundTag
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig "cn_block_route"
            removeSingBoxConfig "cn_block_outbound"

            removeSingBoxConfig "cn_01_google_play_route"

            removeSingBoxConfig "block_domain_route"
            removeSingBoxConfig "block_domain_outbound"
        fi
        echoContent green " ---> 域名黑名单删除完毕"
    else
        echoContent red " ---> 选择错误"
        exit 1
    fi
    reloadCore
}
# 添加routing配置
addXrayRouting() {

    local tag=$1    # warp-socks
    local type=$2   # outboundTag/inboundTag
    local domain=$3 # 域名

    if [[ -z "${tag}" || -z "${type}" || -z "${domain}" ]]; then
        echoContent red " ---> 参数错误"
        exit 1
    fi

    local routingRule=
    if [[ ! -f "${configPath}09_routing.json" ]]; then
        cat <<EOF >${configPath}09_routing.json
{
    "routing":{
        "type": "field",
        "rules": [
            {
                "type": "field",
                "domain": [
                ],
            "outboundTag": "${tag}"
          }
        ]
  }
}
EOF
    fi
    local routingRule=
    routingRule=$(jq -r ".routing.rules[]|select(.outboundTag==\"${tag}\" and (.protocol == null))" ${configPath}09_routing.json)

    if [[ -z "${routingRule}" ]]; then
        routingRule="{\"type\": \"field\",\"domain\": [],\"outboundTag\": \"${tag}\"}"
    fi

    while read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        if echo "${routingRule}" | grep -q "${line}"; then
            echoContent yellow " ---> ${line}已存在，跳过"
        else
            local geositeStatus
            # 添加超时和错误处理
            geositeStatus=$(curl -s --connect-timeout 5 --max-time 10 \
                "https://api.github.com/repos/v2fly/domain-list-community/contents/data/${line}" 2>/dev/null | jq -r '.message // empty')

            # 如果API返回空(文件存在)，使用geosite格式
            # 如果API失败或返回错误消息，回退到domain格式
            if [[ -z "${geositeStatus}" ]]; then
                routingRule=$(echo "${routingRule}" | jq -r '.domain += ["geosite:'"${line}"'"]')
            else
                routingRule=$(echo "${routingRule}" | jq -r '.domain += ["domain:'"${line}"'"]')
            fi
        fi
    done < <(echo "${domain}" | tr ',' '\n')

    unInstallRouting "${tag}" "${type}"
    if ! grep -q "gstatic.com" ${configPath}09_routing.json && [[ "${tag}" == "blackhole_out" ]]; then
        local routing=
        routing=$(jq -r ".routing.rules += [{\"type\": \"field\",\"domain\": [\"gstatic.com\"],\"outboundTag\": \"direct\"}]" ${configPath}09_routing.json)
        echo "${routing}" | jq . >${configPath}09_routing.json
    fi

    routing=$(jq -r ".routing.rules += [${routingRule}]" ${configPath}09_routing.json)
    echo "${routing}" | jq . >${configPath}09_routing.json
}
# 根据tag卸载Routing
unInstallRouting() {
    local tag=$1
    local type=$2
    local protocol=$3

    if [[ -f "${configPath}09_routing.json" ]]; then
        local routing=
        if [[ -n "${protocol}" ]]; then
            routing=$(jq -r "del(.routing.rules[] | select(.${type} == \"${tag}\" and (.protocol | index(\"${protocol}\"))))" ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        else
            routing=$(jq -r "del(.routing.rules[] | select(.${type} == \"${tag}\" and (.protocol == null )))" ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        fi
    fi
}

# 卸载嗅探
unInstallSniffing() {

    find ${configPath} -name "*inbounds.json*" | awk -F "[c][o][n][f][/]" '{print $2}' | while read -r inbound; do
        if grep -q "destOverride" <"${configPath}${inbound}"; then
            sniffing=$(jq -r 'del(.inbounds[0].sniffing)' "${configPath}${inbound}")
            echo "${sniffing}" | jq . >"${configPath}${inbound}"
        fi
    done

}

# 安装嗅探
installSniffing() {
    readInstallType
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]]; then
            if ! grep -q "destOverride" <"${configPath}02_VLESS_TCP_inbounds.json"; then
                sniffing=$(jq -r '.inbounds[0].sniffing = {"enabled":true,"destOverride":["http","tls","quic"]}' "${configPath}02_VLESS_TCP_inbounds.json")
                echo "${sniffing}" | jq . >"${configPath}02_VLESS_TCP_inbounds.json"
            fi
        fi
    fi
}

# 读取第三方warp配置
readConfigWarpReg() {
    if [[ ! -f "/etc/Proxy-agent/warp/config" ]]; then
        /etc/Proxy-agent/warp/warp-reg >/etc/Proxy-agent/warp/config
    fi

    secretKeyWarpReg=$(grep <"/etc/Proxy-agent/warp/config" private_key | awk '{print $2}')

    addressWarpReg=$(grep <"/etc/Proxy-agent/warp/config" v6 | awk '{print $2}')

    publicKeyWarpReg=$(grep <"/etc/Proxy-agent/warp/config" public_key | awk '{print $2}')

    reservedWarpReg=$(grep <"/etc/Proxy-agent/warp/config" reserved | awk -F "[:]" '{print $2}')

}
# 安装warp-reg工具
installWarpReg() {
    if [[ ! -f "/etc/Proxy-agent/warp/warp-reg" ]]; then
        echo
        echoContent yellow "# 注意事项"
        echoContent yellow "# 依赖第三方程序，请熟知其中风险"
        echoContent yellow "# 项目地址：https://github.com/badafans/warp-reg \n"

        read -r -p "warp-reg未安装，是否安装 ？[y/n]:" installWarpRegStatus

        if [[ "${installWarpRegStatus}" == "y" ]]; then

            curl -sLo /etc/Proxy-agent/warp/warp-reg "https://github.com/badafans/warp-reg/releases/download/v1.0/${warpRegCoreCPUVendor}"
            chmod 655 /etc/Proxy-agent/warp/warp-reg

        else
            echoContent yellow " ---> 放弃安装"
            exit 0
        fi
    fi
}

# 展示warp分流域名
showWireGuardDomain() {
    local type=$1
    # xray
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core"
            jq -r -c '.routing.rules[]|select (.outboundTag=="wireguard_out_'"${type}"'")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}wireguard_out_${type}.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已设置warp ${type}全局分流"
        else
            echoContent yellow " ---> 未安装warp ${type}分流"
        fi
    fi

    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]' "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" && -f "${singBoxConfigPath}wireguard_endpoints_${type}.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已设置warp ${type}全局分流"
        else
            echoContent yellow " ---> 未安装warp ${type}分流"
        fi
    fi

}

# 添加WireGuard分流
addWireGuardRoute() {
    local type=$1
    local tag=$2
    local domainList=$3
    # xray
    if [[ "${coreInstallType}" == "1" ]]; then

        addXrayRouting "wireguard_out_${type}" "${tag}" "${domainList}"
        addXrayOutbound "wireguard_out_${type}"
    fi
    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then

        # rule
        addSingBoxRouteRule "wireguard_endpoints_${type}" "${domainList}" "wireguard_endpoints_${type}_route"
        # addSingBoxOutbound "wireguard_out_${type}" "wireguard_out"
        if [[ -n "${domainList}" ]]; then
            addSingBoxOutbound "01_direct_outbound"
        fi

        # outbound
        addSingBoxWireGuardEndpoints "${type}"
    fi
}

# 卸载wireGuard
unInstallWireGuard() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        if [[ "${type}" == "IPv4" ]]; then
            if [[ ! -f "${configPath}wireguard_out_IPv6.json" ]]; then
                rm -rf /etc/Proxy-agent/warp/config >/dev/null 2>&1
            fi
        elif [[ "${type}" == "IPv6" ]]; then
            if [[ ! -f "${configPath}wireguard_out_IPv4.json" ]]; then
                rm -rf /etc/Proxy-agent/warp/config >/dev/null 2>&1
            fi
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ ! -f "${singBoxConfigPath}wireguard_endpoints_IPv6_route.json" && ! -f "${singBoxConfigPath}wireguard_endpoints_IPv4_route.json" ]]; then
            rm "${singBoxConfigPath}wireguard_outbound.json" >/dev/null 2>&1
            rm -rf /etc/Proxy-agent/warp/config >/dev/null 2>&1
        fi
    fi
}
# 移除WireGuard分流
removeWireGuardRoute() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting wireguard_out_"${type}" outboundTag

        removeXrayOutbound "wireguard_out_${type}"
        if [[ ! -f "${configPath}IPv4_out.json" ]]; then
            addXrayOutbound IPv4_out
        fi
    fi

    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxRouteRule "wireguard_endpoints_${type}"
    fi

    unInstallWireGuard "${type}"
}
# warp分流-第三方IPv4
warpRoutingReg() {
    local type=$2
    echoContent skyBlue "\n进度  $1/${totalProgress} : WARP分流[第三方]"
    echoContent red "=============================================================="

    echoContent yellow "1.查看已分流域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.设置WARP全局"
    echoContent yellow "4.卸载WARP分流"
    echoContent red "=============================================================="
    read -r -p "请选择:" warpStatus
    installWarpReg
    readConfigWarpReg
    local address=
    if [[ ${type} == "IPv4" ]]; then
        address="172.16.0.2/32"
    elif [[ ${type} == "IPv6" ]]; then
        address="${addressWarpReg}/128"
    else
        echoContent red " ---> IP获取失败，退出安装"
    fi

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        exit 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent yellow "# 注意事项"
        echoContent yellow "# 支持sing-box、Xray-core"
        echoContent yellow "# 使用提示：请参考 documents 目录中的分流与策略说明 \n"

        read -r -p "请按照上面示例录入域名:" domainList
        addWireGuardRoute "${type}" outboundTag "${domainList}"
        echoContent green " ---> 添加完毕"

    elif [[ "${warpStatus}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.会删除所有设置的分流规则"
        echoContent yellow "2.会删除除WARP[第三方]之外的所有出站规则\n"
        read -r -p "是否确认设置？[y/n]:" warpOutStatus

        if [[ "${warpOutStatus}" == "y" ]]; then
            readConfigWarpReg
            if [[ "${coreInstallType}" == "1" ]]; then
                addXrayOutbound "wireguard_out_${type}"
                if [[ "${type}" == "IPv4" ]]; then
                    removeXrayOutbound "wireguard_out_IPv6"
                elif [[ "${type}" == "IPv6" ]]; then
                    removeXrayOutbound "wireguard_out_IPv4"
                fi

                removeXrayOutbound IPv4_out
                removeXrayOutbound IPv6_out
                removeXrayOutbound z_direct_outbound
                removeXrayOutbound blackhole_out
                removeXrayOutbound socks5_outbound

                rm ${configPath}09_routing.json >/dev/null 2>&1
            fi

            if [[ -n "${singBoxConfigPath}" ]]; then

                removeSingBoxConfig IPv4_out
                removeSingBoxConfig IPv6_out
                removeSingBoxConfig 01_direct_outbound

                # 删除所有分流规则
                removeSingBoxConfig wireguard_endpoints_IPv4_route
                removeSingBoxConfig wireguard_endpoints_IPv6_route

                removeSingBoxConfig IPv6_route
                removeSingBoxConfig socks5_02_inbound_route

                addSingBoxWireGuardEndpoints "${type}"
                addWireGuardRoute "${type}" outboundTag ""
                if [[ "${type}" == "IPv4" ]]; then
                    removeSingBoxConfig wireguard_endpoints_IPv6
                else
                    removeSingBoxConfig wireguard_endpoints_IPv4
                fi

                # outbound
                # addSingBoxOutbound "wireguard_out_${type}" "wireguard_out"

            fi

            echoContent green " ---> WARP全局出站设置完毕"
        else
            echoContent green " ---> 放弃设置"
            exit 0
        fi

    elif [[ "${warpStatus}" == "4" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting "wireguard_out_${type}" outboundTag

            removeXrayOutbound "wireguard_out_${type}"
            addXrayOutbound "z_direct_outbound"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig "wireguard_endpoints_${type}_route"

            removeSingBoxConfig "wireguard_endpoints_${type}"
            addSingBoxOutbound "01_direct_outbound"
        fi

        echoContent green " ---> 卸载WARP ${type}分流完毕"
    else

        echoContent red " ---> 选择错误"
        exit 1
    fi
    reloadCore
}

# ======================= 链式代理功能 =======================

# 链式代理主菜单
chainProxyMenu() {
    echoContent skyBlue "\n功能: 链式代理管理"
    echoContent red "\n=============================================================="
    echoContent yellow "# 链式代理说明"
    echoContent yellow "# 用于在多台境外VPS之间建立加密转发链路"
    echoContent yellow "# 支持多层中继: 入口 → 中继1 → 中继2 → ... → 出口 → 互联网"
    echoContent yellow "# 使用 Shadowsocks 2022 协议，加密安全、性能优秀\n"

    echoContent yellow "1.快速配置向导 [推荐]"
    echoContent yellow "2.查看链路状态"
    echoContent yellow "3.测试链路连通性"
    echoContent yellow "4.高级设置"
    echoContent yellow "5.卸载链式代理"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        chainProxyWizard
        ;;
    2)
        showChainStatus
        ;;
    3)
        testChainConnection
        ;;
    4)
        chainProxyAdvanced
        ;;
    5)
        removeChainProxy
        ;;
    esac
}

# 链式代理配置向导
chainProxyWizard() {
    echoContent skyBlue "\n链式代理配置向导"
    echoContent red "\n=============================================================="
    echoContent yellow "请选择本机角色:\n"
    echoContent yellow "1.出口节点 (Exit) - 链路终点，直接访问互联网"
    echoContent yellow "  └─ 生成配置码，供中继或入口节点导入"
    echoContent yellow ""
    echoContent yellow "2.中继节点 (Relay) - 链路中间节点，转发流量"
    echoContent yellow "  └─ 导入下游配置码，生成新配置码供上游使用"
    echoContent yellow "  └─ 支持多层中继: 入口→中继1→中继2→...→出口"
    echoContent yellow ""
    echoContent yellow "3.入口节点 (Entry) - 链路起点，接收客户端连接"
    echoContent yellow "  └─ 导入出口或中继节点的配置码"
    echoContent yellow ""
    echoContent yellow "4.手动配置入口节点"
    echoContent yellow "  └─ 手动输入出口节点信息 (仅支持单跳)"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setupChainExit
        ;;
    2)
        setupChainRelay
        ;;
    3)
        setupChainEntryByCode
        ;;
    4)
        setupChainEntryManual
        ;;
    esac
}

# 确保 sing-box 已安装
ensureSingBoxInstalled() {
    if [[ ! -f "/etc/Proxy-agent/sing-box/sing-box" ]]; then
        echoContent yellow "\n检测到 sing-box 未安装，正在安装..."
        installSingBox
        if [[ ! -f "/etc/Proxy-agent/sing-box/sing-box" ]]; then
            echoContent red " ---> sing-box 安装失败"
            return 1
        fi
    fi

    # 确保配置目录存在
    mkdir -p /etc/Proxy-agent/sing-box/conf/config/

    # 确保基础配置存在
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/config/00_log.json" ]]; then
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/00_log.json
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    }
}
EOF
    fi

    # 确保 DNS 配置存在 (使用 sing-box 1.12+ 新格式)
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/config/01_dns.json" ]]; then
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/01_dns.json
{
    "dns": {
        "servers": [
            {
                "tag": "google",
                "address": "https://dns.google/dns-query",
                "detour": "direct"
            },
            {
                "tag": "local",
                "address": "local",
                "detour": "direct"
            }
        ]
    }
}
EOF
    fi

    # 确保直连出站存在
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/config/01_direct_outbound.json" ]]; then
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/01_direct_outbound.json
{
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
    fi

    # 确保 systemd 服务已安装且路径正确（修复：链式代理需要服务才能启动）
    # 检查服务文件是否存在，以及是否指向正确的路径
    local needUpdateService=false
    if [[ ! -f "/etc/systemd/system/sing-box.service" ]] && [[ ! -f "/etc/init.d/sing-box" ]]; then
        needUpdateService=true
        echoContent yellow "\n检测到 sing-box 服务未配置，正在配置..."
    elif [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        # 检查服务文件是否指向正确路径（修复从 v2ray-agent 迁移的问题）
        if grep -q "v2ray-agent" /etc/systemd/system/sing-box.service; then
            needUpdateService=true
            echoContent yellow "\n检测到 sing-box 服务路径需要更新..."
        fi
    fi

    if [[ "${needUpdateService}" == "true" ]]; then
        local execStart='/etc/Proxy-agent/sing-box/sing-box run -c /etc/Proxy-agent/sing-box/conf/config.json'

        if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ "${release}" != "alpine" ]]; then
            cat <<EOF >/etc/systemd/system/sing-box.service
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${execStart}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable sing-box.service >/dev/null 2>&1
            echoContent green " ---> sing-box 服务配置完成"
        elif [[ "${release}" == "alpine" ]]; then
            cat <<EOF >/etc/init.d/sing-box
#!/sbin/openrc-run

name="sing-box"
description="Sing-Box Service"
command="/etc/Proxy-agent/sing-box/sing-box"
command_args="run -c /etc/Proxy-agent/sing-box/conf/config.json"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
    after firewall
}
EOF
            chmod +x /etc/init.d/sing-box
            rc-update add sing-box default >/dev/null 2>&1
            echoContent green " ---> sing-box 服务配置完成 (Alpine)"
        fi
    fi

    return 0
}

# 生成链式代理密钥 (Shadowsocks 2022 需要 Base64 编码)
generateChainKey() {
    # AES-128-GCM 需要 16 字节密钥
    openssl rand -base64 16
}

# 获取本机公网 IP
getChainPublicIP() {
    local ip=""
    # 尝试多个服务获取公网IP
    ip=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
    if [[ -z "${ip}" ]]; then
        ip=$(curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null)
    fi
    if [[ -z "${ip}" ]]; then
        ip=$(curl -s4 --connect-timeout 5 https://ip.sb 2>/dev/null)
    fi
    echo "${ip}"
}

# 配置出口节点 (Exit)
setupChainExit() {
    echoContent skyBlue "\n配置出口节点 (Exit)"
    echoContent red "\n=============================================================="

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理入站
    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_inbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            # 显示现有配置码
            showExistingChainCode
            return 0
        fi
    fi

    # 生成随机端口 (10000-60000)
    local chainPort
    chainPort=$(randomNum 10000 60000)
    echoContent yellow "\n请输入链式代理端口 [回车使用随机端口: ${chainPort}]"
    read -r -p "端口:" inputPort
    if [[ -n "${inputPort}" ]]; then
        if [[ ! "${inputPort}" =~ ^[0-9]+$ ]] || [[ "${inputPort}" -lt 1 ]] || [[ "${inputPort}" -gt 65535 ]]; then
            echoContent red " ---> 端口格式错误"
            return 1
        fi
        chainPort=${inputPort}
    fi

    # 生成密钥
    local chainKey
    chainKey=$(generateChainKey)
    echoContent green "\n ---> 已生成随机密钥"

    # 加密方法
    local chainMethod="2022-blake3-aes-128-gcm"

    # 获取公网IP
    local publicIP
    publicIP=$(getChainPublicIP)
    if [[ -z "${publicIP}" ]]; then
        echoContent yellow "\n无法自动获取公网IP，请手动输入"
        read -r -p "公网IP:" publicIP
        if [[ -z "${publicIP}" ]]; then
            echoContent red " ---> IP不能为空"
            return 1
        fi
        if ! isValidIP "${publicIP}"; then
            echoContent red " ---> IP地址格式无效"
            return 1
        fi
    fi
    echoContent green " ---> 本机公网IP: ${publicIP}"

    # 询问是否限制入口IP
    echoContent yellow "\n是否限制只允许特定IP连接？(提高安全性)"
    echoContent yellow "1.不限制 [回车默认]"
    echoContent yellow "2.限制特定IP"
    read -r -p "请选择:" limitIPChoice

    local allowedIP=""
    if [[ "${limitIPChoice}" == "2" ]]; then
        read -r -p "请输入允许连接的入口节点IP:" allowedIP
        if [[ -z "${allowedIP}" ]]; then
            echoContent red " ---> IP不能为空"
            return 1
        fi
        if ! isValidIP "${allowedIP}"; then
            echoContent red " ---> IP地址格式无效"
            return 1
        fi
    fi

    # 创建入站配置
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_inbound.json
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "tag": "chain_inbound",
            "listen": "::",
            "listen_port": ${chainPort},
            "method": "${chainMethod}",
            "password": "${chainKey}",
            "multiplex": {
                "enabled": true
            }
        }
    ]
}
EOF

    # 创建路由配置 (让链式入站流量走直连)
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "rules": [
            {
                "inbound": ["chain_inbound"],
                "outbound": "direct"
            }
        ],
        "final": "direct"
    }
}
EOF

    # 保存配置信息用于生成配置码
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/chain_exit_info.json
{
    "role": "exit",
    "ip": "${publicIP}",
    "port": ${chainPort},
    "method": "${chainMethod}",
    "password": "${chainKey}",
    "allowed_ip": "${allowedIP}"
}
EOF

    # 开放防火墙端口
    if [[ -n "${allowedIP}" ]]; then
        allowPort "${chainPort}" "tcp" "${allowedIP}/32"
        echoContent green " ---> 已开放端口 ${chainPort} (仅允许 ${allowedIP})"
    else
        allowPort "${chainPort}" "tcp"
        echoContent green " ---> 已开放端口 ${chainPort}"
    fi

    # 合并配置并重启
    mergeSingBoxConfig
    reloadCore

    # 生成并显示配置码
    echoContent green "\n=============================================================="
    echoContent green "出口节点配置完成！"
    echoContent green "=============================================================="
    echoContent yellow "\n链式代理配置码 (请复制到入口节点):\n"

    local chainCode
    chainCode="chain://ss2022@${publicIP}:${chainPort}?key=$(echo -n "${chainKey}" | base64 | tr -d '\n')&method=${chainMethod}"
    echoContent skyBlue "${chainCode}"

    echoContent yellow "\n或手动配置:"
    echoContent green "  IP地址: ${publicIP}"
    echoContent green "  端口: ${chainPort}"
    echoContent green "  密钥: ${chainKey}"
    echoContent green "  加密方式: ${chainMethod}"

    echoContent red "\n请妥善保管配置码，切勿泄露！"
}

# 显示现有配置码
showExistingChainCode() {
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/chain_exit_info.json" ]]; then
        echoContent red " ---> 未找到出口节点配置信息"
        return 1
    fi

    local publicIP port method password
    publicIP=$(jq -r '.ip' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
    port=$(jq -r '.port' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
    method=$(jq -r '.method' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
    password=$(jq -r '.password' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)

    echoContent green "\n=============================================================="
    echoContent green "现有出口节点配置"
    echoContent green "=============================================================="

    local chainCode
    chainCode="chain://ss2022@${publicIP}:${port}?key=$(echo -n "${password}" | base64 | tr -d '\n')&method=${method}"
    echoContent yellow "\n配置码:\n"
    echoContent skyBlue "${chainCode}"

    echoContent yellow "\n手动配置信息:"
    echoContent green "  IP地址: ${publicIP}"
    echoContent green "  端口: ${port}"
    echoContent green "  密钥: ${password}"
    echoContent green "  加密方式: ${method}"
}

# 解析配置码 (支持 V1 单跳和 V2 多跳格式)
# V1 格式: chain://ss2022@IP:PORT?key=xxx&method=xxx
# V2 格式: chain://v2@BASE64_JSON_ARRAY
# 输出: chainHops 数组 (JSON), chainHopCount 跳数
parseChainCode() {
    local code=$1

    # 初始化全局变量
    chainHops=""
    chainHopCount=0
    chainExitIP=""
    chainExitPort=""
    chainExitKey=""
    chainExitMethod=""

    # V2 多跳格式
    if [[ "${code}" =~ ^chain://v2@ ]]; then
        local base64Data
        base64Data=$(echo "${code}" | sed 's/chain:\/\/v2@//')

        # 解码 Base64
        chainHops=$(echo "${base64Data}" | base64 -d 2>/dev/null)
        if [[ -z "${chainHops}" ]] || ! echo "${chainHops}" | jq empty 2>/dev/null; then
            echoContent red " ---> V2 配置码解析失败，JSON格式错误"
            return 1
        fi

        chainHopCount=$(echo "${chainHops}" | jq 'length')
        if [[ "${chainHopCount}" -lt 1 ]]; then
            echoContent red " ---> 配置码不包含任何跳转节点"
            return 1
        fi

        echoContent green " ---> V2 多跳配置码解析成功"
        echoContent green "  总跳数: ${chainHopCount}"

        # 显示链路
        local i=1
        while [[ $i -le ${chainHopCount} ]]; do
            local hopIP hopPort
            hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
            hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
            if [[ $i -eq ${chainHopCount} ]]; then
                echoContent green "  第${i}跳 (出口): ${hopIP}:${hopPort}"
            else
                echoContent green "  第${i}跳 (中继): ${hopIP}:${hopPort}"
            fi
            ((i++))
        done

        # 兼容性：设置最后一跳为出口
        chainExitIP=$(echo "${chainHops}" | jq -r '.[-1].ip')
        chainExitPort=$(echo "${chainHops}" | jq -r '.[-1].port')
        chainExitKey=$(echo "${chainHops}" | jq -r '.[-1].key')
        chainExitMethod=$(echo "${chainHops}" | jq -r '.[-1].method')

        return 0
    fi

    # V1 单跳格式
    if [[ "${code}" =~ ^chain://ss2022@ ]]; then
        # 提取 IP:PORT
        local ipPort
        ipPort=$(echo "${code}" | sed 's/chain:\/\/ss2022@//' | cut -d'?' -f1)
        chainExitIP=$(echo "${ipPort}" | cut -d':' -f1)
        chainExitPort=$(echo "${ipPort}" | cut -d':' -f2)

        # 提取参数
        local params
        params=$(echo "${code}" | cut -d'?' -f2)

        # 提取 key (Base64 编码的密钥需要解码)
        local keyBase64
        keyBase64=$(echo "${params}" | grep -oP 'key=\K[^&]+')
        chainExitKey=$(echo "${keyBase64}" | base64 -d 2>/dev/null)
        if [[ -z "${chainExitKey}" ]]; then
            chainExitKey="${keyBase64}"
        fi

        # 提取 method
        chainExitMethod=$(echo "${params}" | grep -oP 'method=\K[^&]+')
        if [[ -z "${chainExitMethod}" ]]; then
            chainExitMethod="2022-blake3-aes-128-gcm"
        fi

        # 验证提取结果
        if [[ -z "${chainExitIP}" ]] || [[ -z "${chainExitPort}" ]] || [[ -z "${chainExitKey}" ]]; then
            echoContent red " ---> 配置码解析失败"
            return 1
        fi

        # 转换为 V2 格式的单跳数组
        chainHops=$(jq -n --arg ip "${chainExitIP}" --argjson port "${chainExitPort}" \
            --arg key "${chainExitKey}" --arg method "${chainExitMethod}" \
            '[{ip: $ip, port: $port, key: $key, method: $method}]')
        chainHopCount=1

        echoContent green " ---> V1 配置码解析成功"
        echoContent green "  出口IP: ${chainExitIP}"
        echoContent green "  出口端口: ${chainExitPort}"
        echoContent green "  加密方式: ${chainExitMethod}"

        return 0
    fi

    echoContent red " ---> 配置码格式错误，不支持的格式"
    return 1
}

# 通过配置码配置入口节点
setupChainEntryByCode() {
    echoContent skyBlue "\n配置入口节点 (Entry) - 配置码模式"
    echoContent red "\n=============================================================="

    echoContent yellow "请粘贴出口或中继节点的配置码:"
    read -r -p "配置码:" chainCode

    if [[ -z "${chainCode}" ]]; then
        echoContent red " ---> 配置码不能为空"
        return 1
    fi

    # 解析配置码 (支持 V1 单跳和 V2 多跳)
    if ! parseChainCode "${chainCode}"; then
        return 1
    fi

    # 根据跳数调用不同的配置函数
    if [[ ${chainHopCount} -gt 1 ]]; then
        # 多跳模式 - 使用全局 chainHops 变量
        setupChainEntryMultiHop
    else
        # 单跳模式 - 向后兼容
        setupChainEntry "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}"
    fi
}

# 手动配置入口节点
setupChainEntryManual() {
    echoContent skyBlue "\n配置入口节点 (Entry) - 手动模式"
    echoContent red "\n=============================================================="

    read -r -p "出口节点IP:" chainExitIP
    if [[ -z "${chainExitIP}" ]]; then
        echoContent red " ---> IP不能为空"
        return 1
    fi
    if ! isValidIP "${chainExitIP}"; then
        echoContent red " ---> IP地址格式无效"
        return 1
    fi

    read -r -p "出口节点端口:" chainExitPort
    if [[ -z "${chainExitPort}" ]]; then
        echoContent red " ---> 端口不能为空"
        return 1
    fi

    read -r -p "密钥:" chainExitKey
    if [[ -z "${chainExitKey}" ]]; then
        echoContent red " ---> 密钥不能为空"
        return 1
    fi

    echoContent yellow "\n加密方式 [回车默认: 2022-blake3-aes-128-gcm]"
    read -r -p "加密方式:" chainExitMethod
    if [[ -z "${chainExitMethod}" ]]; then
        chainExitMethod="2022-blake3-aes-128-gcm"
    fi

    setupChainEntry "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}"
}

# 配置中继节点 (Relay)
# 中继节点同时作为上游的"出口"（接收流量）和下游的"入口"（转发流量）
setupChainRelay() {
    echoContent skyBlue "\n配置中继节点 (Relay)"
    echoContent red "\n=============================================================="
    echoContent yellow "中继节点工作原理:"
    echoContent yellow "  上游节点 → [本机] → 下游节点 → ... → 出口 → 互联网"
    echoContent yellow "  本机将接收上游流量并转发到下游链路\n"

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理配置
    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_inbound.json" ]] || \
       [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            return 0
        fi
    fi

    # 步骤1: 导入下游配置码
    echoContent yellow "步骤 1/3: 导入下游节点配置码"
    echoContent yellow "请粘贴下游节点（出口或其他中继）的配置码:"
    read -r -p "配置码:" downstreamCode

    if [[ -z "${downstreamCode}" ]]; then
        echoContent red " ---> 配置码不能为空"
        return 1
    fi

    # 解析下游配置码
    if ! parseChainCode "${downstreamCode}"; then
        return 1
    fi

    # chainHops 现在包含下游所有节点

    # 步骤2: 配置本机监听
    echoContent yellow "\n步骤 2/3: 配置本机监听端口"

    # 生成随机端口 (10000-60000)
    local chainPort
    chainPort=$(randomNum 10000 60000)
    echoContent yellow "请输入本机链式代理端口 [回车使用随机端口: ${chainPort}]"
    read -r -p "端口:" inputPort
    if [[ -n "${inputPort}" ]]; then
        if [[ ! "${inputPort}" =~ ^[0-9]+$ ]] || [[ "${inputPort}" -lt 1 ]] || [[ "${inputPort}" -gt 65535 ]]; then
            echoContent red " ---> 端口格式错误"
            return 1
        fi
        chainPort=${inputPort}
    fi

    # 生成密钥
    local chainKey
    chainKey=$(generateChainKey)
    local chainMethod="2022-blake3-aes-128-gcm"

    # 获取公网IP
    local publicIP
    publicIP=$(getChainPublicIP)
    if [[ -z "${publicIP}" ]]; then
        echoContent yellow "\n无法自动获取公网IP，请手动输入"
        read -r -p "公网IP:" publicIP
        if [[ -z "${publicIP}" ]]; then
            echoContent red " ---> IP不能为空"
            return 1
        fi
        if ! isValidIP "${publicIP}"; then
            echoContent red " ---> IP地址格式无效"
            return 1
        fi
    fi
    echoContent green " ---> 本机公网IP: ${publicIP}"

    # 步骤3: 生成配置
    echoContent yellow "\n步骤 3/3: 生成配置..."

    # 创建入站配置 (接收上游流量)
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_inbound.json
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "tag": "chain_inbound",
            "listen": "::",
            "listen_port": ${chainPort},
            "method": "${chainMethod}",
            "password": "${chainKey}",
            "multiplex": {
                "enabled": true
            }
        }
    ]
}
EOF

    # 创建出站配置 (detour chain 到下游)
    # 根据 chainHops 生成 detour 链
    local outboundsJson="["
    local i=0
    local hopCount=${chainHopCount}

    while [[ $i -lt ${hopCount} ]]; do
        local hopIP hopPort hopKey hopMethod hopTag
        hopIP=$(echo "${chainHops}" | jq -r ".[$i].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$i].port")
        hopKey=$(echo "${chainHops}" | jq -r ".[$i].key")
        hopMethod=$(echo "${chainHops}" | jq -r ".[$i].method")
        hopTag="chain_hop_$((i+1))"

        if [[ $i -gt 0 ]]; then
            outboundsJson+=","
        fi

        # 第一跳直连，后续跳通过前一跳
        if [[ $i -eq 0 ]]; then
            outboundsJson+="
        {
            \"type\": \"shadowsocks\",
            \"tag\": \"${hopTag}\",
            \"server\": \"${hopIP}\",
            \"server_port\": ${hopPort},
            \"method\": \"${hopMethod}\",
            \"password\": \"${hopKey}\",
            \"multiplex\": {
                \"enabled\": true,
                \"protocol\": \"h2mux\",
                \"max_connections\": 4,
                \"min_streams\": 4
            }
        }"
        else
            local prevTag="chain_hop_${i}"
            outboundsJson+="
        {
            \"type\": \"shadowsocks\",
            \"tag\": \"${hopTag}\",
            \"server\": \"${hopIP}\",
            \"server_port\": ${hopPort},
            \"method\": \"${hopMethod}\",
            \"password\": \"${hopKey}\",
            \"multiplex\": {
                \"enabled\": true,
                \"protocol\": \"h2mux\",
                \"max_connections\": 4,
                \"min_streams\": 4
            },
            \"detour\": \"${prevTag}\"
        }"
        fi

        ((i++))
    done

    # 最后添加 chain_outbound 作为最终出站
    local finalHopTag="chain_hop_${hopCount}"
    outboundsJson+=",
        {
            \"type\": \"direct\",
            \"tag\": \"chain_outbound\",
            \"detour\": \"${finalHopTag}\"
        }
    ]"

    echo "{\"outbounds\": ${outboundsJson}}" | jq . > /etc/Proxy-agent/sing-box/conf/config/chain_outbound.json

    # 创建路由配置
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "rules": [
            {
                "inbound": ["chain_inbound"],
                "outbound": "chain_outbound"
            }
        ],
        "final": "direct"
    }
}
EOF

    # 构建新的 hops 数组 (本机 + 下游所有节点)
    local newHops
    newHops=$(jq -n --arg ip "${publicIP}" --argjson port "${chainPort}" \
        --arg key "${chainKey}" --arg method "${chainMethod}" \
        --argjson downstream "${chainHops}" \
        '[{ip: $ip, port: $port, key: $key, method: $method}] + $downstream')

    # 保存配置信息
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/chain_relay_info.json
{
    "role": "relay",
    "ip": "${publicIP}",
    "port": ${chainPort},
    "method": "${chainMethod}",
    "password": "${chainKey}",
    "downstream_hops": ${chainHops},
    "total_hops": $((chainHopCount + 1))
}
EOF

    # 开放防火墙端口
    allowPort "${chainPort}" "tcp"
    echoContent green " ---> 已开放端口 ${chainPort}"

    # 合并配置并重启
    mergeSingBoxConfig
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: /etc/Proxy-agent/sing-box/sing-box run -c /etc/Proxy-agent/sing-box/conf/config.json"
        return 1
    fi

    # 生成 V2 配置码
    local newChainCode
    newChainCode="chain://v2@$(echo -n "${newHops}" | base64 | tr -d '\n')"

    echoContent green "\n=============================================================="
    echoContent green "中继节点配置完成！"
    echoContent green "=============================================================="
    echoContent yellow "\n当前链路 (${chainHopCount} + 1 = $((chainHopCount + 1)) 跳):"
    echoContent green "  上游 → 本机(${publicIP}:${chainPort})"

    i=1
    while [[ $i -le ${chainHopCount} ]]; do
        local hopIP hopPort
        hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
        if [[ $i -eq ${chainHopCount} ]]; then
            echoContent green "        → 出口(${hopIP}:${hopPort}) → 互联网"
        else
            echoContent green "        → 中继${i}(${hopIP}:${hopPort})"
        fi
        ((i++))
    done

    echoContent yellow "\n配置码 (供上游入口或中继节点使用):\n"
    echoContent skyBlue "${newChainCode}"

    echoContent red "\n请妥善保管配置码，切勿泄露！"
}

# 配置入口节点 - 多跳模式
# 使用全局变量 chainHops (由 parseChainCode 设置)
setupChainEntryMultiHop() {
    local chainBridgePort=31111  # sing-box SOCKS5 桥接端口

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理配置
    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            return 0
        fi
    fi

    echoContent yellow "\n正在配置入口节点 (多跳模式, ${chainHopCount}跳)..."

    # 检测是否有 Xray 代理协议在运行
    local hasXrayProtocols=false
    if [[ -f "/etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]] || \
       [[ -f "/etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" ]] || \
       [[ -f "/etc/Proxy-agent/xray/conf/04_trojan_TCP_inbounds.json" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> 检测到 Xray 代理协议，将同时配置 Xray 链式转发"
    fi

    # ============= sing-box 配置 =============

    # 创建多跳出站配置 (detour chain)
    local outboundsJson="["
    local i=0
    local hopCount=${chainHopCount}

    while [[ $i -lt ${hopCount} ]]; do
        local hopIP hopPort hopKey hopMethod hopTag
        hopIP=$(echo "${chainHops}" | jq -r ".[$i].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$i].port")
        hopKey=$(echo "${chainHops}" | jq -r ".[$i].key")
        hopMethod=$(echo "${chainHops}" | jq -r ".[$i].method")
        hopTag="chain_hop_$((i+1))"

        if [[ $i -gt 0 ]]; then
            outboundsJson+=","
        fi

        # 第一跳直连，后续跳通过前一跳 (detour)
        if [[ $i -eq 0 ]]; then
            outboundsJson+="
        {
            \"type\": \"shadowsocks\",
            \"tag\": \"${hopTag}\",
            \"server\": \"${hopIP}\",
            \"server_port\": ${hopPort},
            \"method\": \"${hopMethod}\",
            \"password\": \"${hopKey}\",
            \"multiplex\": {
                \"enabled\": true,
                \"protocol\": \"h2mux\",
                \"max_connections\": 4,
                \"min_streams\": 4
            }
        }"
        else
            local prevTag="chain_hop_${i}"
            outboundsJson+="
        {
            \"type\": \"shadowsocks\",
            \"tag\": \"${hopTag}\",
            \"server\": \"${hopIP}\",
            \"server_port\": ${hopPort},
            \"method\": \"${hopMethod}\",
            \"password\": \"${hopKey}\",
            \"multiplex\": {
                \"enabled\": true,
                \"protocol\": \"h2mux\",
                \"max_connections\": 4,
                \"min_streams\": 4
            },
            \"detour\": \"${prevTag}\"
        }"
        fi

        ((i++))
    done

    # 最后添加 chain_outbound 作为最终出站
    local finalHopTag="chain_hop_${hopCount}"
    outboundsJson+=",
        {
            \"type\": \"direct\",
            \"tag\": \"chain_outbound\",
            \"detour\": \"${finalHopTag}\"
        }
    ]"

    echo "{\"outbounds\": ${outboundsJson}}" | jq . > /etc/Proxy-agent/sing-box/conf/config/chain_outbound.json

    # 如果有 Xray 代理协议，创建 SOCKS5 桥接入站
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_bridge_inbound.json
{
    "inbounds": [
        {
            "type": "socks",
            "tag": "chain_bridge_in",
            "listen": "127.0.0.1",
            "listen_port": ${chainBridgePort}
        }
    ]
}
EOF
        # 路由：桥接入站流量走链式出站
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "rules": [
            {
                "inbound": ["chain_bridge_in"],
                "outbound": "chain_outbound"
            }
        ],
        "final": "chain_outbound"
    }
}
EOF
    else
        # 没有 Xray，直接设置 final
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "final": "chain_outbound"
    }
}
EOF
    fi

    # 保存配置信息
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/chain_entry_info.json
{
    "role": "entry",
    "mode": "multi_hop",
    "hop_count": ${chainHopCount},
    "hops": ${chainHops},
    "bridge_port": ${chainBridgePort},
    "has_xray": ${hasXrayProtocols}
}
EOF

    # 合并 sing-box 配置
    echoContent yellow "正在合并 sing-box 配置..."
    if ! /etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/ 2>/dev/null; then
        echoContent red " ---> sing-box 配置合并失败"
        echoContent yellow "调试命令: /etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/"
        return 1
    fi

    # 验证配置文件已生成
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/config.json" ]]; then
        echoContent red " ---> sing-box 配置文件生成失败"
        return 1
    fi

    # 启动 sing-box
    echoContent yellow "正在启动 sing-box..."
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证 sing-box 启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: /etc/Proxy-agent/sing-box/sing-box run -c /etc/Proxy-agent/sing-box/conf/config.json"
        return 1
    fi
    echoContent green " ---> sing-box 启动成功"

    # ============= Xray 配置 (如果存在) =============
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "正在配置 Xray 链式转发..."

        # 创建 Xray SOCKS5 出站 (指向 sing-box 桥接)
        cat <<EOF >/etc/Proxy-agent/xray/conf/chain_outbound.json
{
    "outbounds": [
        {
            "tag": "chain_proxy",
            "protocol": "socks",
            "settings": {
                "servers": [
                    {
                        "address": "127.0.0.1",
                        "port": ${chainBridgePort}
                    }
                ]
            }
        }
    ]
}
EOF

        # 备份原路由配置
        if [[ -f "/etc/Proxy-agent/xray/conf/09_routing.json" ]]; then
            cp /etc/Proxy-agent/xray/conf/09_routing.json /etc/Proxy-agent/xray/conf/09_routing.json.bak.chain
        fi

        # 创建新的路由配置
        cat <<EOF >/etc/Proxy-agent/xray/conf/09_routing.json
{
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "domain": [
                    "domain:gstatic.com",
                    "domain:googleapis.com",
                    "domain:googleapis.cn"
                ],
                "outboundTag": "chain_proxy"
            },
            {
                "type": "field",
                "network": "tcp,udp",
                "outboundTag": "chain_proxy"
            }
        ]
    }
}
EOF

        # 重启 Xray
        echoContent yellow "正在重启 Xray..."
        handleXray stop >/dev/null 2>&1
        handleXray start

        sleep 1
        if pgrep -f "xray/xray" >/dev/null 2>&1; then
            echoContent green " ---> Xray 重启成功，链式转发已启用"
        else
            echoContent red " ---> Xray 重启失败"
            echoContent yellow "请检查配置: /etc/Proxy-agent/xray/xray run -confdir /etc/Proxy-agent/xray/conf"
            return 1
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green "入口节点配置完成！(多跳模式)"
    echoContent green "=============================================================="

    # 显示链路
    echoContent yellow "\n当前链路 (${chainHopCount} 跳):"
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent green "  客户端 → Xray → sing-box"
    else
        echoContent green "  客户端 → sing-box"
    fi

    i=1
    while [[ $i -le ${chainHopCount} ]]; do
        local hopIP hopPort
        hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
        if [[ $i -eq ${chainHopCount} ]]; then
            echoContent green "           → 出口(${hopIP}:${hopPort}) → 互联网"
        else
            echoContent green "           → 中继${i}(${hopIP}:${hopPort})"
        fi
        ((i++))
    done

    # 自动测试连通性
    echoContent yellow "\n正在测试链路连通性..."
    sleep 2
    testChainConnection
}

# 配置入口节点 (单跳模式，向后兼容)
setupChainEntry() {
    local exitIP=$1
    local exitPort=$2
    local exitKey=$3
    local exitMethod=$4
    local chainBridgePort=31111  # sing-box SOCKS5 桥接端口

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理出站
    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            return 0
        fi
    fi

    echoContent yellow "\n正在配置入口节点..."

    # 检测是否有 Xray 代理协议在运行
    local hasXrayProtocols=false
    if [[ -f "/etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]] || \
       [[ -f "/etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" ]] || \
       [[ -f "/etc/Proxy-agent/xray/conf/04_trojan_TCP_inbounds.json" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> 检测到 Xray 代理协议，将同时配置 Xray 链式转发"
    fi

    # ============= sing-box 配置 =============

    # 创建 Shadowsocks 出站 (到出口节点)
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_outbound.json
{
    "outbounds": [
        {
            "type": "shadowsocks",
            "tag": "chain_outbound",
            "server": "${exitIP}",
            "server_port": ${exitPort},
            "method": "${exitMethod}",
            "password": "${exitKey}",
            "multiplex": {
                "enabled": true,
                "protocol": "h2mux",
                "max_connections": 4,
                "min_streams": 4
            }
        }
    ]
}
EOF

    # 如果有 Xray 代理协议，创建 SOCKS5 桥接入站
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_bridge_inbound.json
{
    "inbounds": [
        {
            "type": "socks",
            "tag": "chain_bridge_in",
            "listen": "127.0.0.1",
            "listen_port": ${chainBridgePort}
        }
    ]
}
EOF
        # 路由：桥接入站流量走链式出站
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "rules": [
            {
                "inbound": ["chain_bridge_in"],
                "outbound": "chain_outbound"
            }
        ],
        "final": "chain_outbound"
    }
}
EOF
    else
        # 没有 Xray，直接设置 final
        cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "final": "chain_outbound"
    }
}
EOF
    fi

    # 保存配置信息
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/chain_entry_info.json
{
    "role": "entry",
    "exit_ip": "${exitIP}",
    "exit_port": ${exitPort},
    "method": "${exitMethod}",
    "password": "${exitKey}",
    "bridge_port": ${chainBridgePort},
    "has_xray": ${hasXrayProtocols}
}
EOF

    # 合并 sing-box 配置
    echoContent yellow "正在合并 sing-box 配置..."
    if ! /etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/ 2>/dev/null; then
        echoContent red " ---> sing-box 配置合并失败"
        echoContent yellow "调试命令: /etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/"
        return 1
    fi

    # 验证配置文件已生成
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/config.json" ]]; then
        echoContent red " ---> sing-box 配置文件生成失败"
        return 1
    fi

    # 启动 sing-box
    echoContent yellow "正在启动 sing-box..."
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证 sing-box 启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: /etc/Proxy-agent/sing-box/sing-box run -c /etc/Proxy-agent/sing-box/conf/config.json"
        return 1
    fi
    echoContent green " ---> sing-box 启动成功"

    # ============= Xray 配置 (如果存在) =============
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "正在配置 Xray 链式转发..."

        # 创建 Xray SOCKS5 出站 (指向 sing-box 桥接)
        cat <<EOF >/etc/Proxy-agent/xray/conf/chain_outbound.json
{
    "outbounds": [
        {
            "tag": "chain_proxy",
            "protocol": "socks",
            "settings": {
                "servers": [
                    {
                        "address": "127.0.0.1",
                        "port": ${chainBridgePort}
                    }
                ]
            }
        }
    ]
}
EOF

        # 修改 Xray 路由，让流量走链式代理
        # 备份原路由配置
        if [[ -f "/etc/Proxy-agent/xray/conf/09_routing.json" ]]; then
            cp /etc/Proxy-agent/xray/conf/09_routing.json /etc/Proxy-agent/xray/conf/09_routing.json.bak.chain
        fi

        # 创建新的路由配置，默认出站改为 chain_proxy
        cat <<EOF >/etc/Proxy-agent/xray/conf/09_routing.json
{
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "domain": [
                    "domain:gstatic.com",
                    "domain:googleapis.com",
                    "domain:googleapis.cn"
                ],
                "outboundTag": "chain_proxy"
            },
            {
                "type": "field",
                "network": "tcp,udp",
                "outboundTag": "chain_proxy"
            }
        ]
    }
}
EOF

        # 重启 Xray
        echoContent yellow "正在重启 Xray..."
        handleXray stop >/dev/null 2>&1
        handleXray start

        sleep 1
        if pgrep -f "xray/xray" >/dev/null 2>&1; then
            echoContent green " ---> Xray 重启成功，链式转发已启用"
        else
            echoContent red " ---> Xray 重启失败"
            echoContent yellow "请检查配置: /etc/Proxy-agent/xray/xray run -confdir /etc/Proxy-agent/xray/conf"
            return 1
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green "入口节点配置完成！"
    echoContent green "=============================================================="
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "流量路径: 客户端 → Xray → sing-box → 出口节点"
    else
        echoContent yellow "流量路径: 客户端 → sing-box → 出口节点"
    fi

    # 自动测试连通性
    echoContent yellow "\n正在测试链路连通性..."
    sleep 2
    testChainConnection
}

# 查看链路状态
showChainStatus() {
    echoContent skyBlue "\n链式代理状态"
    echoContent red "\n=============================================================="

    local role="未配置"
    local exitIP=""
    local exitPort=""
    local status="❌ 未配置"

    # 检查是否为出口节点
    if [[ -f "/etc/Proxy-agent/sing-box/conf/chain_exit_info.json" ]]; then
        role="出口节点 (Exit)"
        local ip port
        ip=$(jq -r '.ip' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
        port=$(jq -r '.port' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
        local allowedIP
        allowedIP=$(jq -r '.allowed_ip' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)

        # 检查 sing-box 是否运行
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ 运行中"
        else
            status="❌ 未运行"
        fi

        echoContent green "╔══════════════════════════════════════════════════════════════╗"
        echoContent green "║                      链式代理状态                              ║"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  当前角色: ${role}"
        echoContent yellow "  监听端口: ${port}"
        echoContent yellow "  本机IP: ${ip}"
        echoContent yellow "  允许连接: ${allowedIP:-所有IP}"
        echoContent yellow "  运行状态: ${status}"
        echoContent green "╚══════════════════════════════════════════════════════════════╝"

        # 显示配置码
        showExistingChainCode

    # 检查是否为中继节点
    elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_relay_info.json" ]]; then
        role="中继节点 (Relay)"
        local ip port totalHops
        ip=$(jq -r '.ip' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
        port=$(jq -r '.port' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
        totalHops=$(jq -r '.total_hops' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
        local downstreamHops
        downstreamHops=$(jq -r '.downstream_hops' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)

        # 检查 sing-box 是否运行
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ 运行中"
        else
            status="❌ 未运行"
        fi

        echoContent green "╔══════════════════════════════════════════════════════════════╗"
        echoContent green "║                      链式代理状态                              ║"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  当前角色: ${role}"
        echoContent yellow "  监听端口: ${port}"
        echoContent yellow "  本机IP: ${ip}"
        echoContent yellow "  链路总跳数: ${totalHops}"
        echoContent yellow "  运行状态: ${status}"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  下游链路:"

        local i=0
        local hopCount
        hopCount=$(echo "${downstreamHops}" | jq 'length')
        while [[ $i -lt ${hopCount} ]]; do
            local hopIP hopPort
            hopIP=$(echo "${downstreamHops}" | jq -r ".[$i].ip")
            hopPort=$(echo "${downstreamHops}" | jq -r ".[$i].port")
            if [[ $i -eq $((hopCount - 1)) ]]; then
                echoContent yellow "    → 出口(${hopIP}:${hopPort}) → 互联网"
            else
                echoContent yellow "    → 中继$((i+1))(${hopIP}:${hopPort})"
            fi
            ((i++))
        done
        echoContent green "╚══════════════════════════════════════════════════════════════╝"

        # 显示配置码
        showRelayChainCode

    # 检查是否为入口节点
    elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_entry_info.json" ]]; then
        local mode
        mode=$(jq -r '.mode // "single_hop"' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)

        # 检查 sing-box 是否运行
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ 运行中"
        else
            status="❌ 未运行"
        fi

        if [[ "${mode}" == "multi_hop" ]]; then
            role="入口节点 (Entry) - 多跳模式"
            local hopCount hops
            hopCount=$(jq -r '.hop_count' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)
            hops=$(jq -r '.hops' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)

            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      链式代理状态                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  当前角色: ${role}"
            echoContent yellow "  链路跳数: ${hopCount}"
            echoContent yellow "  运行状态: ${status}"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  链路详情:"

            local i=0
            while [[ $i -lt ${hopCount} ]]; do
                local hopIP hopPort
                hopIP=$(echo "${hops}" | jq -r ".[$i].ip")
                hopPort=$(echo "${hops}" | jq -r ".[$i].port")
                if [[ $i -eq $((hopCount - 1)) ]]; then
                    echoContent yellow "    → 出口(${hopIP}:${hopPort}) → 互联网"
                else
                    echoContent yellow "    → 中继$((i+1))(${hopIP}:${hopPort})"
                fi
                ((i++))
            done
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        else
            role="入口节点 (Entry)"
            exitIP=$(jq -r '.exit_ip' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)
            exitPort=$(jq -r '.exit_port' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)

            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      链式代理状态                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  当前角色: ${role}"
            echoContent yellow "  出口地址: ${exitIP}:${exitPort}"
            echoContent yellow "  运行状态: ${status}"
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        fi

    else
        echoContent yellow "未配置链式代理"
        echoContent yellow "请使用 '快速配置向导' 进行配置"
    fi
}

# 显示中继节点配置码
showRelayChainCode() {
    if [[ ! -f "/etc/Proxy-agent/sing-box/conf/chain_relay_info.json" ]]; then
        echoContent red " ---> 未找到中继节点配置信息"
        return 1
    fi

    local publicIP port method password downstreamHops
    publicIP=$(jq -r '.ip' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
    port=$(jq -r '.port' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
    method=$(jq -r '.method' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
    password=$(jq -r '.password' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
    downstreamHops=$(jq -r '.downstream_hops' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)

    # 构建新的 hops 数组 (本机 + 下游所有节点)
    local newHops
    newHops=$(jq -n --arg ip "${publicIP}" --argjson port "${port}" \
        --arg key "${password}" --arg method "${method}" \
        --argjson downstream "${downstreamHops}" \
        '[{ip: $ip, port: $port, key: $key, method: $method}] + $downstream')

    local chainCode
    chainCode="chain://v2@$(echo -n "${newHops}" | base64 | tr -d '\n')"

    echoContent yellow "\n配置码 (供上游入口或中继节点使用):\n"
    echoContent skyBlue "${chainCode}"
}

# 测试链路连通性
testChainConnection() {
    echoContent skyBlue "\n测试链路连通性"
    echoContent red "\n=============================================================="

    # 确定节点角色并获取首跳信息
    local firstHopIP=""
    local firstHopPort=""
    local role=""

    if [[ -f "/etc/Proxy-agent/sing-box/conf/chain_entry_info.json" ]]; then
        role="entry"
        local mode
        mode=$(jq -r '.mode // "single_hop"' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)

        if [[ "${mode}" == "multi_hop" ]]; then
            # 多跳模式，获取第一跳
            firstHopIP=$(jq -r '.hops[0].ip' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)
            firstHopPort=$(jq -r '.hops[0].port' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)
        else
            # 单跳模式
            firstHopIP=$(jq -r '.exit_ip' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)
            firstHopPort=$(jq -r '.exit_port' /etc/Proxy-agent/sing-box/conf/chain_entry_info.json)
        fi

    elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_relay_info.json" ]]; then
        role="relay"
        # 中继节点获取下游第一跳
        firstHopIP=$(jq -r '.downstream_hops[0].ip' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)
        firstHopPort=$(jq -r '.downstream_hops[0].port' /etc/Proxy-agent/sing-box/conf/chain_relay_info.json)

    elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_exit_info.json" ]]; then
        role="exit"
        echoContent yellow "当前为出口节点，无需测试链路"
        echoContent yellow "请在入口节点测试连通性"

        # 测试出口节点自身网络
        echoContent yellow "\n测试出口节点网络..."
        local testIP
        testIP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null)
        if [[ -n "${testIP}" ]]; then
            echoContent green "✅ 出口节点网络正常"
            echoContent green "   出口IP: ${testIP}"
        else
            echoContent red "❌ 出口节点网络异常"
        fi
        return 0
    else
        echoContent red " ---> 未配置链式代理"
        return 1
    fi

    echoContent yellow "首跳节点: ${firstHopIP}:${firstHopPort}\n"

    # 测试1: TCP端口连通性 (到第一跳)
    echoContent yellow "测试1: TCP端口连通性..."
    if nc -zv -w 5 "${firstHopIP}" "${firstHopPort}" >/dev/null 2>&1; then
        echoContent green "  ✅ TCP端口连通 (${firstHopIP}:${firstHopPort})"
    else
        echoContent red "  ❌ TCP端口不通"
        echoContent red "  请检查:"
        echoContent red "  1. 目标节点防火墙是否开放端口 ${firstHopPort}"
        echoContent red "  2. 目标节点 sing-box 是否运行"
        echoContent red "  3. IP地址是否正确"
        return 1
    fi

    # 测试2: 通过链路访问外网
    echoContent yellow "测试2: 链路转发测试..."

    # 检查 sing-box 是否运行
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red "  ❌ sing-box 未运行"
        return 1
    fi

    # 通过链路获取出口IP
    sleep 1
    local outIP
    outIP=$(curl -s --connect-timeout 10 https://api.ipify.org 2>/dev/null)

    if [[ -n "${outIP}" ]]; then
        echoContent green "  ✅ 链路转发正常"
        echoContent green "  出口IP: ${outIP}"

        # 测试延迟
        local startTime endTime latency
        startTime=$(date +%s%N)
        curl -s --connect-timeout 5 https://www.google.com >/dev/null 2>&1
        endTime=$(date +%s%N)
        latency=$(( (endTime - startTime) / 1000000 ))
        echoContent green "  延迟: ${latency}ms"
    else
        echoContent red "  ❌ 链路转发失败"
        echoContent red "  请检查各节点配置和网络"
        return 1
    fi

    echoContent green "\n=============================================================="
    echoContent green "链路测试通过！"
    echoContent green "=============================================================="
}

# 高级设置
chainProxyAdvanced() {
    echoContent skyBlue "\n链式代理高级设置"
    echoContent red "\n=============================================================="

    echoContent yellow "1.显示配置码 (出口/中继节点)"
    echoContent yellow "2.更新密钥"
    echoContent yellow "3.修改端口"
    echoContent yellow "4.查看详细配置"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        if [[ -f "/etc/Proxy-agent/sing-box/conf/chain_exit_info.json" ]]; then
            showExistingChainCode
        elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_relay_info.json" ]]; then
            showRelayChainCode
        else
            echoContent red " ---> 当前不是出口或中继节点"
        fi
        ;;
    2)
        updateChainKey
        ;;
    3)
        updateChainPort
        ;;
    4)
        showChainDetailConfig
        ;;
    esac
}

# 更新密钥
updateChainKey() {
    echoContent yellow "\n更新链式代理密钥"

    if [[ -f "/etc/Proxy-agent/sing-box/conf/chain_exit_info.json" ]]; then
        # 出口节点
        local port method
        port=$(jq -r '.port' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
        method=$(jq -r '.method' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)
        local publicIP
        publicIP=$(jq -r '.ip' /etc/Proxy-agent/sing-box/conf/chain_exit_info.json)

        # 生成新密钥
        local newKey
        newKey=$(generateChainKey)

        # 更新入站配置 - 使用安全的临时文件
        local tmpInboundFile
        tmpInboundFile=$(mktemp)
        chmod 600 "${tmpInboundFile}"
        jq --arg key "${newKey}" '.inbounds[0].password = $key' \
            /etc/Proxy-agent/sing-box/conf/config/chain_inbound.json > "${tmpInboundFile}"
        mv "${tmpInboundFile}" /etc/Proxy-agent/sing-box/conf/config/chain_inbound.json

        # 更新信息文件 - 使用安全的临时文件
        local tmpInfoFile
        tmpInfoFile=$(mktemp)
        chmod 600 "${tmpInfoFile}"
        jq --arg key "${newKey}" '.password = $key' \
            /etc/Proxy-agent/sing-box/conf/chain_exit_info.json > "${tmpInfoFile}"
        mv "${tmpInfoFile}" /etc/Proxy-agent/sing-box/conf/chain_exit_info.json

        mergeSingBoxConfig
        reloadCore

        echoContent green " ---> 密钥已更新"
        echoContent yellow "\n新配置码:\n"
        local chainCode
        chainCode="chain://ss2022@${publicIP}:${port}?key=$(echo -n "${newKey}" | base64 | tr -d '\n')&method=${method}"
        echoContent skyBlue "${chainCode}"
        echoContent red "\n请更新入口节点配置！"

    elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_entry_info.json" ]]; then
        echoContent red " ---> 入口节点请从出口节点获取新配置码后重新配置"
    else
        echoContent red " ---> 未配置链式代理"
    fi
}

# 更新端口
updateChainPort() {
    echoContent yellow "\n更新链式代理端口"

    local infoFile=""
    if [[ -f "/etc/Proxy-agent/sing-box/conf/chain_exit_info.json" ]]; then
        infoFile="/etc/Proxy-agent/sing-box/conf/chain_exit_info.json"
    elif [[ -f "/etc/Proxy-agent/sing-box/conf/chain_relay_info.json" ]]; then
        infoFile="/etc/Proxy-agent/sing-box/conf/chain_relay_info.json"
    else
        echoContent red " ---> 仅出口或中继节点可修改端口"
        return 1
    fi

    local oldPort
    oldPort=$(jq -r '.port' "${infoFile}")

    read -r -p "新端口 [当前: ${oldPort}]:" newPort
    if [[ -z "${newPort}" ]]; then
        return 0
    fi

    if [[ ! "${newPort}" =~ ^[0-9]+$ ]] || [[ "${newPort}" -lt 1 ]] || [[ "${newPort}" -gt 65535 ]]; then
        echoContent red " ---> 端口格式错误"
        return 1
    fi

    # 更新入站配置 - 使用安全的临时文件
    local tmpInboundFile
    tmpInboundFile=$(mktemp)
    chmod 600 "${tmpInboundFile}"
    jq --argjson port "${newPort}" '.inbounds[0].listen_port = $port' \
        /etc/Proxy-agent/sing-box/conf/config/chain_inbound.json > "${tmpInboundFile}"
    mv "${tmpInboundFile}" /etc/Proxy-agent/sing-box/conf/config/chain_inbound.json

    # 更新信息文件 - 使用安全的临时文件
    local tmpInfoFile
    tmpInfoFile=$(mktemp)
    chmod 600 "${tmpInfoFile}"
    jq --argjson port "${newPort}" '.port = $port' \
        "${infoFile}" > "${tmpInfoFile}"
    mv "${tmpInfoFile}" "${infoFile}"

    # 更新防火墙
    allowPort "${newPort}" "tcp"

    mergeSingBoxConfig
    reloadCore

    echoContent green " ---> 端口已更新为 ${newPort}"

    # 显示相应的配置码
    if [[ "${infoFile}" == *"exit"* ]]; then
        showExistingChainCode
    else
        showRelayChainCode
    fi
    echoContent red "\n请更新上游节点配置！"
}

# 显示详细配置
showChainDetailConfig() {
    echoContent skyBlue "\n链式代理详细配置"
    echoContent red "\n=============================================================="

    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_inbound.json" ]]; then
        echoContent yellow "\n入站配置 (chain_inbound.json):"
        jq . /etc/Proxy-agent/sing-box/conf/config/chain_inbound.json
    fi

    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\n出站配置 (chain_outbound.json):"
        jq . /etc/Proxy-agent/sing-box/conf/config/chain_outbound.json
    fi

    if [[ -f "/etc/Proxy-agent/sing-box/conf/config/chain_route.json" ]]; then
        echoContent yellow "\n路由配置 (chain_route.json):"
        jq . /etc/Proxy-agent/sing-box/conf/config/chain_route.json
    fi
}

# 卸载链式代理
removeChainProxy() {
    echoContent skyBlue "\n卸载链式代理"
    echoContent red "\n=============================================================="

    read -r -p "确认卸载链式代理？[y/n]:" confirmRemove
    if [[ "${confirmRemove}" != "y" ]]; then
        return 0
    fi

    # 删除 sing-box 配置文件
    rm -f /etc/Proxy-agent/sing-box/conf/config/chain_inbound.json
    rm -f /etc/Proxy-agent/sing-box/conf/config/chain_outbound.json
    rm -f /etc/Proxy-agent/sing-box/conf/config/chain_route.json
    rm -f /etc/Proxy-agent/sing-box/conf/config/chain_bridge_inbound.json
    rm -f /etc/Proxy-agent/sing-box/conf/chain_exit_info.json
    rm -f /etc/Proxy-agent/sing-box/conf/chain_entry_info.json
    rm -f /etc/Proxy-agent/sing-box/conf/chain_relay_info.json

    # 删除 Xray 链式代理配置
    if [[ -f "/etc/Proxy-agent/xray/conf/chain_outbound.json" ]]; then
        rm -f /etc/Proxy-agent/xray/conf/chain_outbound.json
        echoContent yellow " ---> 已删除 Xray 链式出站配置"

        # 恢复原路由配置
        if [[ -f "/etc/Proxy-agent/xray/conf/09_routing.json.bak.chain" ]]; then
            mv /etc/Proxy-agent/xray/conf/09_routing.json.bak.chain /etc/Proxy-agent/xray/conf/09_routing.json
            echoContent yellow " ---> 已恢复 Xray 原路由配置"
        else
            # 如果没有备份，创建默认路由配置
            cat <<EOF >/etc/Proxy-agent/xray/conf/09_routing.json
{
    "routing": {
        "rules": [
            {
                "type": "field",
                "domain": [
                    "domain:gstatic.com",
                    "domain:googleapis.com",
                    "domain:googleapis.cn"
                ],
                "outboundTag": "z_direct_outbound"
            }
        ]
    }
}
EOF
            echoContent yellow " ---> 已重置 Xray 路由配置为默认"
        fi

        # 重启 Xray
        handleXray stop >/dev/null 2>&1
        handleXray start
    fi

    # 重新合并 sing-box 配置
    mergeSingBoxConfig
    reloadCore

    echoContent green " ---> 链式代理已卸载"
}

# 合并 sing-box 配置 (如果函数不存在则定义)
# 注意：此函数与 singBoxMergeConfig 保持一致，用于链式代理独立运行场景
if ! type mergeSingBoxConfig >/dev/null 2>&1; then
    mergeSingBoxConfig() {
        if [[ -d "/etc/Proxy-agent/sing-box/conf/config/" ]]; then
            # 先删除旧配置，再合并生成新配置
            rm -f /etc/Proxy-agent/sing-box/conf/config.json >/dev/null 2>&1
            # 使用 sing-box 合并配置（与 singBoxMergeConfig 保持一致）
            if [[ -f "/etc/Proxy-agent/sing-box/sing-box" ]]; then
                /etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/ >/dev/null 2>&1
            fi
        fi
    }
fi

# ======================= 链式代理功能结束 =======================

# 分流工具
routingToolsMenu() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 分流工具"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 用于服务端的流量分流，可用于解锁ChatGPT、流媒体等相关内容\n"

    echoContent yellow "1.WARP分流【第三方 IPv4】"
    echoContent yellow "2.WARP分流【第三方 IPv6】"
    echoContent yellow "3.IPv6分流"
    echoContent yellow "4.DNS分流"
    echoContent yellow "5.SNI反向代理分流"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        warpRoutingReg 1 IPv4
        ;;
    2)
        warpRoutingReg 1 IPv6
        ;;
    3)
        ipv6Routing 1
        ;;
    4)
        dnsRouting 1
        ;;
    5)
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent red "\n ---> 此功能不支持Hysteria2、Tuic"
        fi
        sniRouting 1
        ;;
    esac

}

# VMess+WS+TLS 分流
vmessWSRouting() {
    echoContent skyBlue "\n功能 1/${totalProgress} : VMess+WS+TLS 分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 使用提示：详见 documents 目录中的分流与策略说明 \n"

    echoContent yellow "1.添加出站"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setVMessWSRoutingOutbounds
        ;;
    2)
        removeVMessWSRouting
        ;;
    esac
}

# 设置VMess+WS+TLS【仅出站】
setVMessWSRoutingOutbounds() {
    read -r -p "请输入VMess+WS+TLS的地址:" setVMessWSTLSAddress
    echoContent red "=============================================================="
    echoContent yellow "录入示例:netflix,openai\n"
    read -r -p "请按照上面示例录入域名:" domainList

    if [[ -z ${domainList} ]]; then
        echoContent red " ---> 域名不可为空"
        setVMessWSRoutingOutbounds
    fi

    if [[ -n "${setVMessWSTLSAddress}" ]]; then
        removeXrayOutbound VMess-out

        echo
        read -r -p "请输入VMess+WS+TLS的端口:" setVMessWSTLSPort
        echo
        if [[ -z "${setVMessWSTLSPort}" ]]; then
            echoContent red " ---> 端口不可为空"
        fi

        read -r -p "请输入VMess+WS+TLS的UUID:" setVMessWSTLSUUID
        echo
        if [[ -z "${setVMessWSTLSUUID}" ]]; then
            echoContent red " ---> UUID不可为空"
        fi

        read -r -p "请输入VMess+WS+TLS的Path路径:" setVMessWSTLSPath
        echo
        if [[ -z "${setVMessWSTLSPath}" ]]; then
            echoContent red " ---> 路径不可为空"
        elif ! echo "${setVMessWSTLSPath}" | grep -q "/"; then
            setVMessWSTLSPath="/${setVMessWSTLSPath}"
        fi
        addXrayOutbound "VMess-out"
        addXrayRouting VMess-out outboundTag "${domainList}"
        reloadCore
        echoContent green " ---> 添加分流成功"
        exit 0
    fi
    echoContent red " ---> 地址不可为空"
    setVMessWSRoutingOutbounds
}

# 移除VMess+WS+TLS分流
removeVMessWSRouting() {

    removeXrayOutbound VMess-out
    unInstallRouting VMess-out outboundTag

    reloadCore
    echoContent green " ---> 卸载成功"
}

# 重启核心
reloadCore() {
    readInstallType

    if [[ "${coreInstallType}" == "1" ]]; then
        handleXray stop
        handleXray start
    fi
    if echo "${currentInstallProtocolType}" | grep -q ",20," || [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
        handleSingBox stop
        handleSingBox start
    fi
}

# dns分流
dnsRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : DNS分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 使用提示：请参考 documents 目录中的分流与策略说明 \n"

    echoContent yellow "1.添加"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockDNS
        ;;
    2)
        removeUnlockDNS
        ;;
    esac
}

# SNI反向代理分流
sniRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : SNI反向代理分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 使用提示：请参考 documents 目录中的分流与策略说明 \n"
    echoContent yellow "# sing-box不支持规则集，仅支持指定域名。\n"

    echoContent yellow "1.添加"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockSNI
        ;;
    2)
        removeUnlockSNI
        ;;
    esac
}
# 设置SNI分流
setUnlockSNI() {
    read -r -p "请输入分流的SNI IP:" setSNIP
    if [[ -n ${setSNIP} ]]; then
        # 验证IP格式
        if ! isValidIP "${setSNIP}"; then
            echoContent red " ---> IP地址格式无效，请输入正确的IPv4或IPv6地址"
            exit 1
        fi
        echoContent red "=============================================================="

        if [[ "${coreInstallType}" == 1 ]]; then
            echoContent yellow "录入示例:netflix,disney,hulu"
            read -r -p "请按照上面示例录入域名:" xrayDomainList
            local hosts={}
            while read -r domain; do
                hosts=$(echo "${hosts}" | jq -r ".\"geosite:${domain}\"=\"${setSNIP}\"")
            done < <(echo "${xrayDomainList}" | tr ',' '\n')
            cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "hosts":${hosts},
        "servers": [
            "8.8.8.8",
            "1.1.1.1"
        ]
    }
}
EOF
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent yellow "录入示例:www.netflix.com,www.google.com"
            read -r -p "请按照上面示例录入域名:" singboxDomainList
            addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined"
        fi
        echoContent yellow " ---> SNI反向代理分流成功"
        reloadCore
    else
        echoContent red " ---> SNI IP不可为空"
    fi
    exit 1
}

# 添加xray dns 配置
addXrayDNSConfig() {
    local ip=$1
    local domainList=$2
    local domains=[]
    while read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        local geositeStatus
        # 添加超时和错误处理
        geositeStatus=$(curl -s --connect-timeout 5 --max-time 10 \
            "https://api.github.com/repos/v2fly/domain-list-community/contents/data/${line}" 2>/dev/null | jq -r '.message // empty')

        # 如果API返回空(文件存在)，使用geosite格式
        if [[ -z "${geositeStatus}" ]]; then
            domains=$(echo "${domains}" | jq -r '. += ["geosite:'"${line}"'"]')
        else
            domains=$(echo "${domains}" | jq -r '. += ["domain:'"${line}"'"]')
        fi
    done < <(echo "${domainList}" | tr ',' '\n')

    if [[ "${coreInstallType}" == "1" ]]; then

        cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
            {
                "address": "${ip}",
                "port": 53,
                "domains": ${domains}
            },
        "localhost"
        ]
    }
}
EOF
    fi
}

# 添加sing-box dns配置
addSingBoxDNSConfig() {
    local ip=$1
    local domainList=$2
    local actionType=$3

    local rules=
    rules=$(initSingBoxRules "${domainList}" "dns")
    # domain精确匹配规则
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    # ruleSet规则集
    local ruleSet=
    ruleSet=$(echo "${rules}" | jq .ruleSet)

    # ruleSet规则tag
    local ruleSetTag=[]
    if [[ "$(echo "${ruleSet}" | jq '.|length')" != "0" ]]; then
        ruleSetTag=$(echo "${ruleSet}" | jq '.|map(.tag)')
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ "${actionType}" == "predefined" ]]; then
            local predefined={}
            while read -r line; do
                predefined=$(echo "${predefined}" | jq ".\"${line}\"=\"${ip}\"")
            done < <(echo "${domainList}" | tr ',' '\n' | grep -v '^$' | sort -n | uniq | paste -sd ',' | tr ',' '\n')

            cat <<EOF >"${singBoxConfigPath}dns.json"
{
  "dns": {
    "servers": [
        {
            "tag": "local",
            "type": "local"
        },
        {
            "tag": "hosts",
            "type": "hosts",
            "predefined": ${predefined}
        }
    ],
    "rules": [
        {
            "domain_regex":${domainRules},
            "server":"hosts"
        }
    ]
  }
}
EOF
        else
            cat <<EOF >"${singBoxConfigPath}dns.json"
{
  "dns": {
    "servers": [
      {
        "tag": "local",
        "type": "local"
      },
      {
        "tag": "dnsRouting",
        "type": "udp",
        "server": "${ip}"
      }
    ],
    "rules": [
      {
        "rule_set": ${ruleSetTag},
        "domain_regex": ${domainRules},
        "server":"dnsRouting"
      }
    ]
  },
  "route":{
    "rule_set":${ruleSet}
  }
}
EOF
        fi
    fi
}
# 设置dns
setUnlockDNS() {
    read -r -p "请输入分流的DNS:" setDNS
    if [[ -n ${setDNS} ]]; then
        echoContent red "=============================================================="
        echoContent yellow "录入示例:netflix,disney,hulu"
        read -r -p "请按照上面示例录入域名:" domainList

        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayDNSConfig "${setDNS}" "${domainList}"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxOutbound 01_direct_outbound
            addSingBoxDNSConfig "${setDNS}" "${domainList}"
        fi

        reloadCore

        echoContent yellow "\n ---> 如还无法观看可以尝试以下两种方案"
        echoContent yellow " 1.重启vps"
        echoContent yellow " 2.卸载dns解锁后，修改本地的[/etc/resolv.conf]DNS设置并重启vps\n"
    else
        echoContent red " ---> dns不可为空"
    fi
    exit 1
}

# 移除 DNS分流
removeUnlockDNS() {
    if [[ "${coreInstallType}" == "1" && -f "${configPath}11_dns.json" ]]; then
        cat <<EOF >${configPath}11_dns.json
{
	"dns": {
		"servers": [
			"localhost"
		]
	}
}
EOF
    fi

    if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}dns.json" ]]; then
        cat <<EOF >${singBoxConfigPath}dns.json
{
    "dns": {
        "servers":[
            {
                "type":"local"
            }
        ]
    }
}
EOF
    fi

    reloadCore

    echoContent green " ---> 卸载成功"

    exit 0
}

# 移除SNI分流
removeUnlockSNI() {
    if [[ "${coreInstallType}" == 1 ]]; then
        cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
            "localhost"
        ]
    }
}
EOF
    fi

    if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}dns.json" ]]; then
        cat <<EOF >${singBoxConfigPath}dns.json
{
    "dns": {
        "servers":[
            {
                "type":"local"
            }
        ]
    }
}
EOF
    fi

    reloadCore
    echoContent green " ---> 卸载成功"

    exit 0
}

# sing-box 个性化安装
customSingBoxInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "0.VLESS+Vision+TCP"
    echoContent yellow "1.VLESS+TLS+WS[仅CDN推荐]"
    echoContent yellow "3.VMess+TLS+WS[仅CDN推荐]"
    echoContent yellow "4.Trojan+TLS[不推荐]"
    echoContent yellow "6.Hysteria2"
    echoContent yellow "7.VLESS+Reality+Vision"
    echoContent yellow "8.VLESS+Reality+gRPC"
    echoContent yellow "9.Tuic"
    echoContent yellow "10.Naive"
    echoContent yellow "11.VMess+TLS+HTTPUpgrade"
    echoContent yellow "13.anytls"
    echoContent yellow "14.Shadowsocks 2022[无需TLS证书]"

    read -r -p "请选择[多选]，[例如:1,2,3]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 1
    fi
    if [[ "${selectCustomInstallType}" != "10" ]] && [[ "${selectCustomInstallType}" != "11" ]] && [[ "${selectCustomInstallType}" != "13" ]] && [[ "${selectCustomInstallType}" != "14" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> 多选请使用英文逗号分隔"
        exit 1
    fi
    if [[ "${selectCustomInstallType: -1}" != "," ]]; then
        selectCustomInstallType="${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi

    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]]; then
        # WebSocket 协议迁移提示
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,"; then
            echoContent yellow "\n ---> 提示: WebSocket传输已逐渐被XHTTP(SplitHTTP)取代"
            echoContent yellow " ---> XHTTP具有更好的抗检测能力和CDN兼容性，建议在Xray中使用VLESS+Reality+XHTTP"
            echoContent yellow " ---> 参考: https://xtls.github.io/en/config/transports/splithttp.html\n"
        fi

        readLastInstallationConfig
        unInstallSubscribe
        totalProgress=9
        installTools 1
        # 申请tls
        if echo "${selectCustomInstallType}" | grep -q -E ",0,|,1,|,3,|,4,|,6,|,9,|,10,|,11,|,13,"; then
            initTLSNginxConfig 2
            installTLS 3
            handleNginx stop
        fi

        installSingBox 4
        installSingBoxService 5
        initSingBoxConfig custom 6
        cleanUp xrayDel
        installCronTLS 7
        handleSingBox stop
        handleSingBox start
        handleNginx stop
        handleNginx start
        # 生成账号
        checkGFWStatue 8
        showAccounts 9
    else
        echoContent red " ---> 输入不合法"
        customSingBoxInstall
    fi
}

# Xray-core个性化安装
customXrayInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "VLESS前置，默认安装0，无域名安装Reality只选择7即可"
    echoContent yellow "0.VLESS+TLS_Vision+TCP[推荐]"
    echoContent yellow "1.VLESS+TLS+WS[仅CDN推荐]"
    #    echoContent yellow "2.Trojan+TLS+gRPC[仅CDN推荐]"
    echoContent yellow "3.VMess+TLS+WS[仅CDN推荐]"
    echoContent yellow "4.Trojan+TLS[不推荐]"
    echoContent yellow "5.VLESS+TLS+gRPC[仅CDN推荐]"
    echoContent yellow "7.VLESS+Reality+uTLS+Vision[推荐]"
    # echoContent yellow "8.VLESS+Reality+gRPC"
    echoContent yellow "12.VLESS+Reality+XHTTP+TLS[CDN可用]"
    read -r -p "请选择[多选]，[例如:1,2,3]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 1
    fi
    if [[ "${selectCustomInstallType}" != "12" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> 多选请使用英文逗号分隔"
        exit 1
    fi

    if [[ "${selectCustomInstallType}" == "7" ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    else
        if ! echo "${selectCustomInstallType}" | grep -q "0,"; then
            selectCustomInstallType=",0,${selectCustomInstallType},"
        else
            selectCustomInstallType=",${selectCustomInstallType},"
        fi
    fi

    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType//,/}" =~ ^[0-7]+$ ]]; then
        # WebSocket 协议迁移提示
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,"; then
            echoContent yellow "\n ---> 提示: WebSocket传输已逐渐被XHTTP(SplitHTTP)取代"
            echoContent yellow " ---> XHTTP具有更好的抗检测能力和CDN兼容性，建议选择12.VLESS+Reality+XHTTP+TLS"
            echoContent yellow " ---> 参考: https://xtls.github.io/en/config/transports/splithttp.html\n"
        fi

        readLastInstallationConfig
        unInstallSubscribe
        checkBTPanel
        check1Panel
        totalProgress=12
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\n进度  3/${totalProgress} : 检测到宝塔面板/1Panel，跳过申请TLS步骤"
            handleXray stop
            if [[ "${selectCustomInstallType}" != ",7," ]]; then
                customPortFunction
            fi
        else
            # 申请tls
            if [[ "${selectCustomInstallType}" != ",7," ]]; then
                initTLSNginxConfig 2
                handleXray stop
                installTLS 3
            else
                echoContent skyBlue "\n进度  2/${totalProgress} : 检测到仅安装Reality，跳过TLS证书步骤"
            fi
        fi

        handleNginx stop
        # 随机path
        if echo "${selectCustomInstallType}" | grep -qE ",1,|,2,|,3,|,5,|,12,"; then
            randomPathFunction 4
        fi
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\n进度  6/${totalProgress} : 检测到宝塔面板/1Panel，跳过伪装网站"
        else
            nginxBlog 6
        fi
        if [[ "${selectCustomInstallType}" != ",7," ]]; then
            updateRedirectNginxConf
            handleNginx start
        fi

        # 安装Xray
        installXray 7 false
        installXrayService 8
        initXrayConfig custom 9
        cleanUp singBoxDel
        if [[ "${selectCustomInstallType}" != ",7," ]]; then
            installCronTLS 10
        fi

        handleXray stop
        handleXray start
        # 生成账号
        checkGFWStatue 11
        showAccounts 12
    else
        echoContent red " ---> 输入不合法"
        customXrayInstall
    fi
}

# 选择核心安装sing-box、xray-core
selectCoreInstall() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 选择核心安装"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.sing-box"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectCoreType
    case ${selectCoreType} in
    1)
        if [[ "${selectInstallType}" == "2" ]]; then
            customXrayInstall
        else
            xrayCoreInstall
        fi
        ;;
    2)
        if [[ "${selectInstallType}" == "2" ]]; then
            customSingBoxInstall
        else
            singBoxInstall
        fi
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        selectCoreInstall
        ;;
    esac
}

# xray-core 安装
xrayCoreInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    checkBTPanel
    check1Panel
    selectCustomInstallType=
    totalProgress=12
    installTools 2
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n进度  3/${totalProgress} : 检测到宝塔面板/1Panel，跳过申请TLS步骤"
        handleXray stop
        customPortFunction
    else
        # 申请tls
        initTLSNginxConfig 3
        handleXray stop
        installTLS 4
    fi

    handleNginx stop
    randomPathFunction 5

    # 安装Xray
    installXray 6 false
    installXrayService 7
    initXrayConfig all 8
    cleanUp singBoxDel
    installCronTLS 9
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n进度  11/${totalProgress} : 检测到宝塔面板/1Panel，跳过伪装网站"
    else
        nginxBlog 10
    fi
    updateRedirectNginxConf
    handleXray stop
    sleep 2
    handleXray start

    handleNginx start
    # 生成账号
    checkGFWStatue 11
    showAccounts 12
}

# sing-box 全部安装
singBoxInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    checkBTPanel
    check1Panel
    selectCustomInstallType=
    totalProgress=8
    installTools 2

    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n进度  3/${totalProgress} : 检测到宝塔面板/1Panel，跳过申请TLS步骤"
        handleXray stop
        customPortFunction
    else
        # 申请tls
        initTLSNginxConfig 3
        handleXray stop
        installTLS 4
    fi

    handleNginx stop

    installSingBox 5
    installSingBoxService 6
    initSingBoxConfig all 7

    cleanUp xrayDel
    installCronTLS 8

    handleSingBox stop
    handleSingBox start
    handleNginx stop
    handleNginx start
    # 生成账号
    showAccounts 9
}

# 核心管理
coreVersionManageMenu() {

    if [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 1
    fi
    echoContent skyBlue "\n功能 1/1 : 请选择核心"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.sing-box"
    echoContent red "=============================================================="
    read -r -p "请输入:" selectCore

    if [[ "${selectCore}" == "1" ]]; then
        xrayVersionManageMenu 1
    elif [[ "${selectCore}" == "2" ]]; then
        singBoxVersionManageMenu 1
    fi
}
# 定时任务检查
cronFunction() {
    if [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit 0
    elif [[ "${cronName}" == "UpdateGeo" ]]; then
        updateGeoSite >>/etc/Proxy-agent/crontab_updateGeoSite.log
        echoContent green " ---> geo更新日期:$(date "+%F %H:%M:%S")" >>/etc/Proxy-agent/crontab_updateGeoSite.log
        exit 0
    fi
}
# 账号管理
manageAccount() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 账号管理"
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装"
        exit 1
    fi

    echoContent red "\n=============================================================="
    echoContent yellow "# 添加单个用户时可自定义email和uuid"
    echoContent yellow "# 如安装了Hysteria或者Tuic，账号会同时添加到相应的类型下面\n"
    echoContent yellow "1.查看账号"
    echoContent yellow "2.查看订阅"
    echoContent yellow "3.管理其他订阅"
    echoContent yellow "4.添加用户"
    echoContent yellow "5.删除用户"
    echoContent red "=============================================================="
    read -r -p "请输入:" manageAccountStatus
    if [[ "${manageAccountStatus}" == "1" ]]; then
        showAccounts 1
    elif [[ "${manageAccountStatus}" == "2" ]]; then
        subscribe
    elif [[ "${manageAccountStatus}" == "3" ]]; then
        addSubscribeMenu 1
    elif [[ "${manageAccountStatus}" == "4" ]]; then
        addUser
    elif [[ "${manageAccountStatus}" == "5" ]]; then
        removeUser
    else
        echoContent red " ---> 选择错误"
    fi
}

# 安装订阅
installSubscribe() {
    readNginxSubscribe
    local nginxSubscribeListen=
    local nginxSubscribeSSL=
    local serverName=
    local SSLType=
    local listenIPv6=
    if [[ -z "${subscribePort}" ]]; then

        nginxVersion=$(nginx -v 2>&1)

        if echo "${nginxVersion}" | grep -q "not found" || [[ -z "${nginxVersion}" ]]; then
            echoContent yellow "未检测到nginx，无法使用订阅服务\n"
            read -r -p "是否安装[y/n]？" installNginxStatus
            if [[ "${installNginxStatus}" == "y" ]]; then
                installNginxTools
            else
                echoContent red " ---> 放弃安装nginx\n"
                exit 1
            fi
        fi
        echoContent yellow "开始配置订阅，请输入订阅的端口\n"

        mapfile -t result < <(initSingBoxPort "${subscribePort}")
        echo
        echoContent yellow " ---> 开始配置订阅的伪装站点\n"
        nginxBlog
        echo
        local httpSubscribeStatus=
        local subscribeServerName=

        # 确定订阅使用的域名
        if [[ -n "${currentHost}" ]]; then
            subscribeServerName="${currentHost}"
        elif [[ -n "${domain}" ]]; then
            subscribeServerName="${domain}"
        fi

        # 检查是否有可用的TLS证书（实际检查文件是否存在）
        local tlsCertExists=false
        if [[ -n "${subscribeServerName}" ]] && \
           [[ -f "/etc/Proxy-agent/tls/${subscribeServerName}.crt" ]] && \
           [[ -f "/etc/Proxy-agent/tls/${subscribeServerName}.key" ]]; then
            tlsCertExists=true
        fi

        # 如果没有TLS证书，使用HTTP订阅
        if [[ "${tlsCertExists}" != "true" ]]; then
            httpSubscribeStatus=true
        fi

        if [[ "${httpSubscribeStatus}" == "true" ]]; then

            echoContent yellow "未发现tls证书，使用无加密订阅，可能被运营商拦截，请注意风险。"
            echo
            read -r -p "是否使用http订阅[y/n]？" addNginxSubscribeStatus
            echo
            if [[ "${addNginxSubscribeStatus}" != "y" ]]; then
                echoContent yellow " ---> 退出安装"
                exit
            fi
        else
            SSLType="ssl"
            serverName="server_name ${subscribeServerName};"
            nginxSubscribeSSL="ssl_certificate /etc/Proxy-agent/tls/${subscribeServerName}.crt;ssl_certificate_key /etc/Proxy-agent/tls/${subscribeServerName}.key;"
        fi
        if [[ -n "$(curl --connect-timeout 2 -s -6 https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)" ]]; then
            listenIPv6="listen [::]:${result[-1]} ${SSLType};"
        fi
        if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;http2 on;${listenIPv6}"
        else
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;${listenIPv6}"
        fi

        cat <<EOF >${nginxConfigPath}subscribe.conf
server {
    ${nginxSubscribeListen}
    ${serverName}
    ${nginxSubscribeSSL}
    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;
    root ${nginxStaticPath};
    location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {
        default_type 'text/plain; charset=utf-8';
        alias /etc/Proxy-agent/subscribe/\$1/\$2;
    }
    location / {
    }
}
EOF
        bootStartup nginx
        handleNginx stop
        handleNginx start
    fi
    if [[ -z $(pgrep -f "nginx") ]]; then
        handleNginx start
    fi
}
# 卸载订阅
unInstallSubscribe() {
    rm -rf "${nginxConfigPath}subscribe.conf" >/dev/null 2>&1
}

# 添加订阅
addSubscribeMenu() {
    echoContent skyBlue "\n===================== 添加其他机器订阅 ======================="
    echoContent yellow "1.添加"
    echoContent yellow "2.移除"
    echoContent red "=============================================================="
    read -r -p "请选择:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        if [[ ! -f "/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl" ]]; then
            echoContent green " ---> 未安装其他订阅"
            exit 0
        fi
        grep -v '^$' "/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl" | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的订阅编号[仅支持单个删除]:" delSubscribeIndex
        if [[ -z "${delSubscribeIndex}" ]]; then
            echoContent green " ---> 不可以为空"
            exit 0
        fi

        sed -i "$((delSubscribeIndex))d" "/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl" >/dev/null 2>&1

        echoContent green " ---> 其他机器订阅删除成功"
        subscribe
    fi
}
# 添加其他机器clashMeta订阅
addOtherSubscribe() {
    echoContent yellow "#注意事项:"
    echoContent yellow "请输入目标站点信息，确保与 Reality 配置相匹配。"
    echoContent skyBlue "录入示例：www.example.com:443:vps1\n"
    read -r -p "请输入域名 端口 机器别名:" remoteSubscribeUrl
    if [[ -z "${remoteSubscribeUrl}" ]]; then
        echoContent red " ---> 不可为空"
        addOtherSubscribe
    elif ! echo "${remoteSubscribeUrl}" | grep -q ":"; then
        echoContent red " ---> 规则不合法"
    else

        if [[ -f "/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl" ]] && grep -q "${remoteSubscribeUrl}" /etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl; then
            echoContent red " ---> 此订阅已添加"
            exit 1
        fi
        echo
        read -r -p "是否是HTTP订阅？[y/n]" httpSubscribeStatus
        if [[ "${httpSubscribeStatus}" == "y" ]]; then
            remoteSubscribeUrl="${remoteSubscribeUrl}:http"
        fi
        echo "${remoteSubscribeUrl}" >>/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl
        subscribe
    fi
}
# clashMeta配置文件
clashMetaConfig() {
    local url=$1
    local id=$2
    cat <<EOF >"/etc/Proxy-agent/subscribe/clashMetaProfiles/${id}"
log-level: debug
mode: rule
ipv6: true
mixed-port: 7890
allow-lan: true
bind-address: "*"
lan-allowed-ips:
  - 0.0.0.0/0
  - ::/0
find-process-mode: strict
external-controller: 0.0.0.0:9090

geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
geo-auto-update: true
geo-update-interval: 24

external-controller-cors:
  allow-private-network: true

global-client-fingerprint: chrome

profile:
  store-selected: true
  store-fake-ip: true

sniffer:
  enable: true
  override-destination: false
  sniff:
    QUIC:
      ports: [ 443 ]
    TLS:
      ports: [ 443 ]
    HTTP:
      ports: [80]


dns:
  enable: true
  prefer-h3: false
  listen: 0.0.0.0:1053
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'dns.google'
    - "localhost.ptlogin2.qq.com"
  use-hosts: true
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - 1.1.1.1
    - 8.8.8.8
  proxy-server-nameserver:
    - https://223.5.5.5/dns-query
    - https://1.12.12.12/dns-query
  nameserver-policy:
    "geosite:cn,private":
      - https://doh.pub/dns-query
      - https://dns.alidns.com/dns-query

proxy-providers:
  ${subscribeSalt}_provider:
    type: http
    path: ./${subscribeSalt}_provider.yaml
    url: ${url}
    interval: 3600
    proxy: DIRECT
    health-check:
      enable: true
      url: https://cp.cloudflare.com/generate_204
      interval: 300

proxy-groups:
  - name: 手动切换
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies: null
  - name: 自动选择
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 36000
    tolerance: 50
    use:
      - ${subscribeSalt}_provider
    proxies: null

  - name: 全球代理
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: 流媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: DNS_Proxy
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 自动选择
      - 手动切换
      - DIRECT

  - name: Telegram
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Google
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: YouTube
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Netflix
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Spotify
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
      - DIRECT
  - name: HBO
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Bing
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择


  - name: OpenAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: ClaudeAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: Disney
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: GitHub
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT

  - name: 国内媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
  - name: 本地直连
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 自动选择
  - name: 漏网之鱼
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 手动切换
      - 自动选择
rule-providers:
  lan:
    type: http
    behavior: classical
    interval: 86400
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Lan/Lan.yaml
    path: ./Rules/lan.yaml
  reject:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt
    path: ./ruleset/reject.yaml
    interval: 86400
  proxy:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt
    path: ./ruleset/proxy.yaml
    interval: 86400
  direct:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt
    path: ./ruleset/direct.yaml
    interval: 86400
  private:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt
    path: ./ruleset/private.yaml
    interval: 86400
  gfw:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/gfw.txt
    path: ./ruleset/gfw.yaml
    interval: 86400
  greatfire:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/greatfire.txt
    path: ./ruleset/greatfire.yaml
    interval: 86400
  tld-not-cn:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400
  telegramcidr:
    type: http
    behavior: ipcidr
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/telegramcidr.txt
    path: ./ruleset/telegramcidr.yaml
    interval: 86400
  applications:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt
    path: ./ruleset/applications.yaml
    interval: 86400
  Disney:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Disney/Disney.yaml
    path: ./ruleset/disney.yaml
    interval: 86400
  Netflix:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Netflix/Netflix.yaml
    path: ./ruleset/netflix.yaml
    interval: 86400
  YouTube:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/YouTube/YouTube.yaml
    path: ./ruleset/youtube.yaml
    interval: 86400
  HBO:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/HBO/HBO.yaml
    path: ./ruleset/hbo.yaml
    interval: 86400
  OpenAI:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml
    path: ./ruleset/openai.yaml
    interval: 86400
  ClaudeAI:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.yaml
    path: ./ruleset/claudeai.yaml
    interval: 86400
  Bing:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Bing/Bing.yaml
    path: ./ruleset/bing.yaml
    interval: 86400
  Google:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Google/Google.yaml
    path: ./ruleset/google.yaml
    interval: 86400
  GitHub:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml
    path: ./ruleset/github.yaml
    interval: 86400
  Spotify:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Spotify/Spotify.yaml
    path: ./ruleset/spotify.yaml
    interval: 86400
  ChinaMaxDomain:
    type: http
    behavior: domain
    interval: 86400
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_Domain.yaml
    path: ./Rules/ChinaMaxDomain.yaml
  ChinaMaxIPNoIPv6:
    type: http
    behavior: ipcidr
    interval: 86400
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_IP_No_IPv6.yaml
    path: ./Rules/ChinaMaxIPNoIPv6.yaml
rules:
  - RULE-SET,YouTube,YouTube,no-resolve
  - RULE-SET,Google,Google,no-resolve
  - RULE-SET,GitHub,GitHub
  - RULE-SET,telegramcidr,Telegram,no-resolve
  - RULE-SET,Spotify,Spotify,no-resolve
  - RULE-SET,Netflix,Netflix
  - RULE-SET,HBO,HBO
  - RULE-SET,Bing,Bing
  - RULE-SET,OpenAI,OpenAI
  - RULE-SET,ClaudeAI,ClaudeAI
  - RULE-SET,Disney,Disney
  - RULE-SET,proxy,全球代理
  - RULE-SET,gfw,全球代理
  - RULE-SET,applications,本地直连
  - RULE-SET,ChinaMaxDomain,本地直连
  - RULE-SET,ChinaMaxIPNoIPv6,本地直连,no-resolve
  - RULE-SET,lan,本地直连,no-resolve
  - GEOIP,CN,本地直连
  - MATCH,漏网之鱼
EOF

}
# 随机salt - 使用更安全的随机源
initRandomSalt() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    local charLen=${#chars}
    for i in {1..10}; do
        local idx
        idx=$(randomNum 0 $((charLen - 1)))
        initCustomPath+="${chars:idx:1}"
    done
    echo "${initCustomPath}"
}
# 订阅
subscribe() {
    readInstallProtocolType
    installSubscribe

    readNginxSubscribe
    local renewSalt=$1
    local showStatus=$2
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "2" ]]; then

        echoContent skyBlue "-------------------------备注---------------------------------"
        echoContent yellow "# 查看订阅会重新生成本地账号的订阅"
        echoContent red "# 需要手动输入md5加密的salt值，如果不了解使用随机即可"
        echoContent yellow "# 不影响已添加的远程订阅的内容\n"

        if [[ -f "/etc/Proxy-agent/subscribe_local/subscribeSalt" && -n $(cat "/etc/Proxy-agent/subscribe_local/subscribeSalt") ]]; then
            if [[ -z "${renewSalt}" ]]; then
                read -r -p "读取到上次安装设置的Salt，是否使用上次生成的Salt ？[y/n]:" historySaltStatus
                if [[ "${historySaltStatus}" == "y" ]]; then
                    subscribeSalt=$(cat /etc/Proxy-agent/subscribe_local/subscribeSalt)
                else
                    read -r -p "请输入salt值, [回车]使用随机:" subscribeSalt
                fi
            else
                subscribeSalt=$(cat /etc/Proxy-agent/subscribe_local/subscribeSalt)
            fi
        else
            read -r -p "请输入salt值, [回车]使用随机:" subscribeSalt
            showStatus=
        fi

        if [[ -z "${subscribeSalt}" ]]; then
            subscribeSalt=$(initRandomSalt)
        fi
        echoContent yellow "\n ---> Salt: ${subscribeSalt}"

        echo "${subscribeSalt}" >/etc/Proxy-agent/subscribe_local/subscribeSalt

        rm -rf /etc/Proxy-agent/subscribe/default/*
        rm -rf /etc/Proxy-agent/subscribe/clashMeta/*
        rm -rf /etc/Proxy-agent/subscribe_local/default/*
        rm -rf /etc/Proxy-agent/subscribe_local/clashMeta/*
        rm -rf /etc/Proxy-agent/subscribe_local/sing-box/*
        showAccounts >/dev/null
        if [[ -n $(ls /etc/Proxy-agent/subscribe_local/default/) ]]; then
            if [[ -f "/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl" && -n $(cat "/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl") ]]; then
                if [[ -z "${renewSalt}" ]]; then
                    read -r -p "读取到其他订阅，是否更新？[y/n]" updateOtherSubscribeStatus
                else
                    updateOtherSubscribeStatus=y
                fi
            fi
            local subscribePortLocal="${subscribePort}"
            find /etc/Proxy-agent/subscribe_local/default/* | while read -r email; do
                email=$(echo "${email}" | awk -F "[d][e][f][a][u][l][t][/]" '{print $2}')

                local emailMd5=
                emailMd5=$(echo -n "${email}${subscribeSalt}"$'\n' | md5sum | awk '{print $1}')

                cat "/etc/Proxy-agent/subscribe_local/default/${email}" >>"/etc/Proxy-agent/subscribe/default/${emailMd5}"
                if [[ "${updateOtherSubscribeStatus}" == "y" ]]; then
                    updateRemoteSubscribe "${emailMd5}" "${email}"
                fi
                local base64Result
                base64Result=$(base64 -w 0 "/etc/Proxy-agent/subscribe/default/${emailMd5}")
                echo "${base64Result}" >"/etc/Proxy-agent/subscribe/default/${emailMd5}"
                echoContent yellow "--------------------------------------------------------------"
                local currentDomain=${currentHost}

                if [[ -n "${currentDefaultPort}" && "${currentDefaultPort}" != "443" ]]; then
                    currentDomain="${currentHost}:${currentDefaultPort}"
                fi
                if [[ -n "${subscribePortLocal}" ]]; then
                    if [[ "${subscribeType}" == "http" ]]; then
                        currentDomain="$(getPublicIP):${subscribePort}"
                    else
                        currentDomain="${currentHost}:${subscribePort}"
                    fi
                fi
                if [[ -z "${showStatus}" ]]; then
                    echoContent skyBlue "\n----------默认订阅----------\n"
                    echoContent green "email:${email}\n"
                    echoContent yellow "url:${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    echoContent yellow "在线二维码:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    if [[ "${release}" != "alpine" ]]; then
                        echo "${subscribeType}://${currentDomain}/s/default/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                    fi

                    # clashMeta
                    if [[ -f "/etc/Proxy-agent/subscribe_local/clashMeta/${email}" ]]; then

                        cat "/etc/Proxy-agent/subscribe_local/clashMeta/${email}" >>"/etc/Proxy-agent/subscribe/clashMeta/${emailMd5}"

                        sed -i '1i\proxies:' "/etc/Proxy-agent/subscribe/clashMeta/${emailMd5}"

                        local clashProxyUrl="${subscribeType}://${currentDomain}/s/clashMeta/${emailMd5}"
                        clashMetaConfig "${clashProxyUrl}" "${emailMd5}"
                        echoContent skyBlue "\n----------clashMeta订阅----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        echoContent yellow "在线二维码:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        if [[ "${release}" != "alpine" ]]; then
                            echo "${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                        fi

                    fi
                    # sing-box
                    if [[ -f "/etc/Proxy-agent/subscribe_local/sing-box/${email}" ]]; then
                        cp "/etc/Proxy-agent/subscribe_local/sing-box/${email}" "/etc/Proxy-agent/subscribe/sing-box_profiles/${emailMd5}"

                        echoContent skyBlue " ---> 下载 sing-box 通用配置文件"
                        if [[ "${release}" == "alpine" ]]; then
                            wget -O "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}" -q "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/documents/sing-box.json"
                        else
                            wget -O "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}" -q "${wgetShowProgressStatus}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/documents/sing-box.json"
                        fi

                        jq ".outbounds=$(jq ".outbounds|map(if has(\"outbounds\") then .outbounds += $(jq ".|map(.tag)" "/etc/Proxy-agent/subscribe_local/sing-box/${email}") else . end)" "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}")" "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}" >"/etc/Proxy-agent/subscribe/sing-box/${emailMd5}_tmp" && mv "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}_tmp" "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}"
                        jq ".outbounds += $(jq '.' "/etc/Proxy-agent/subscribe_local/sing-box/${email}")" "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}" >"/etc/Proxy-agent/subscribe/sing-box/${emailMd5}_tmp" && mv "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}_tmp" "/etc/Proxy-agent/subscribe/sing-box/${emailMd5}"

                        echoContent skyBlue "\n----------sing-box订阅----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        echoContent yellow "在线二维码:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        if [[ "${release}" != "alpine" ]]; then
                            echo "${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                        fi

                    fi

                    echoContent skyBlue "--------------------------------------------------------------"
                else
                    echoContent green " ---> email:${email}，订阅已更新，请使用客户端重新拉取"
                fi

            done
        fi
    else
        echoContent red " ---> 未安装伪装站点，无法使用订阅服务"
    fi
}

# 更新远程订阅
updateRemoteSubscribe() {

    local emailMD5=$1
    local email=$2
    while read -r line; do
        local subscribeType=
        subscribeType="https"

        local serverAlias=
        serverAlias=$(echo "${line}" | awk -F "[:]" '{print $3}')

        local remoteUrl=
        remoteUrl=$(echo "${line}" | awk -F "[:]" '{print $1":"$2}')

        local subscribeTypeRemote=
        subscribeTypeRemote=$(echo "${line}" | awk -F "[:]" '{print $4}')

        if [[ -n "${subscribeTypeRemote}" ]]; then
            subscribeType="${subscribeTypeRemote}"
        fi
        local clashMetaProxies=

        clashMetaProxies=$(curl -s "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" | sed '/proxies:/d' | sed "s/\"${email}/\"${email}_${serverAlias}/g")

        if ! echo "${clashMetaProxies}" | grep -q "nginx" && [[ -n "${clashMetaProxies}" ]]; then
            echo "${clashMetaProxies}" >>"/etc/Proxy-agent/subscribe/clashMeta/${emailMD5}"
            echoContent green " ---> clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> clashMeta订阅 ${remoteUrl}:${email}不存在"
        fi

        local default=
        default=$(curl -s "${subscribeType}://${remoteUrl}/s/default/${emailMD5}")

        if ! echo "${default}" | grep -q "nginx" && [[ -n "${default}" ]]; then
            default=$(echo "${default}" | base64 -d | sed "s/#${email}/#${email}_${serverAlias}/g")
            echo "${default}" >>"/etc/Proxy-agent/subscribe/default/${emailMD5}"

            echoContent green " ---> 通用订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 不存在"
        fi

        local singBoxSubscribe=
        singBoxSubscribe=$(curl -s "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}")

        if ! echo "${singBoxSubscribe}" | grep -q "nginx" && [[ -n "${singBoxSubscribe}" ]]; then
            singBoxSubscribe=${singBoxSubscribe//tag\": \"${email}/tag\": \"${email}_${serverAlias}}
            singBoxSubscribe=$(jq ". +=${singBoxSubscribe}" "/etc/Proxy-agent/subscribe_local/sing-box/${email}")
            echo "${singBoxSubscribe}" | jq . >"/etc/Proxy-agent/subscribe_local/sing-box/${email}"

            echoContent green " ---> 通用订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 不存在"
        fi

    done < <(grep -v '^$' <"/etc/Proxy-agent/subscribe_remote/remoteSubscribeUrl")
}

# 切换alpn
switchAlpn() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 切换alpn"
    if [[ -z ${currentAlpn} ]]; then
        echoContent red " ---> 无法读取alpn，请检查是否安装"
        exit 1
    fi

    echoContent red "\n=============================================================="
    echoContent green "当前alpn首位为:${currentAlpn}"
    echoContent yellow "  1.当http/1.1首位时，trojan可用，gRPC部分客户端可用【客户端支持手动选择alpn的可用】"
    echoContent yellow "  2.当h2首位时，gRPC可用，trojan部分客户端可用【客户端支持手动选择alpn的可用】"
    echoContent yellow "  3.如客户端不支持手动更换alpn，建议使用此功能更改服务端alpn顺序，来使用相应的协议"
    echoContent red "=============================================================="

    if [[ "${currentAlpn}" == "http/1.1" ]]; then
        echoContent yellow "1.切换alpn h2 首位"
    elif [[ "${currentAlpn}" == "h2" ]]; then
        echoContent yellow "1.切换alpn http/1.1 首位"
    else
        echoContent red '不符合'
    fi

    echoContent red "=============================================================="

    read -r -p "请选择:" selectSwitchAlpnType
    if [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "http/1.1" ]]; then

        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn = [\"h2\",\"http/1.1\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json

    elif [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "h2" ]]; then
        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn =[\"http/1.1\",\"h2\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json
    else
        echoContent red " ---> 选择错误"
        exit 1
    fi
    reloadCore
}

# 初始化realityKey
initRealityKey() {
    echoContent skyBlue "\n生成Reality key\n"
    if [[ -n "${currentRealityPublicKey}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的PublicKey/PrivateKey ？[y/n]:" historyKeyStatus
        if [[ "${historyKeyStatus}" == "y" ]]; then
            realityPrivateKey=${currentRealityPrivateKey}
            realityPublicKey=${currentRealityPublicKey}
        fi
    elif [[ -n "${currentRealityPublicKey}" && -n "${lastInstallationConfig}" ]]; then
        realityPrivateKey=${currentRealityPrivateKey}
        realityPublicKey=${currentRealityPublicKey}
    fi
    if [[ -z "${realityPrivateKey}" ]]; then
        if [[ "${selectCoreType}" == "2" || "${coreInstallType}" == "2" ]]; then
            realityX25519Key=$(/etc/Proxy-agent/sing-box/sing-box generate reality-keypair)
            realityPrivateKey=$(echo "${realityX25519Key}" | head -1 | awk '{print $2}')
            realityPublicKey=$(echo "${realityX25519Key}" | tail -n 1 | awk '{print $2}')
            echo "publicKey:${realityPublicKey}" >/etc/Proxy-agent/sing-box/conf/config/reality_key
        else
            read -r -p "请输入Private Key[回车自动生成]:" historyPrivateKey
            if [[ -n "${historyPrivateKey}" ]]; then
                realityX25519Key=$(/etc/Proxy-agent/xray/xray x25519 -i "${historyPrivateKey}")
            else
                realityX25519Key=$(/etc/Proxy-agent/xray/xray x25519)
            fi
            # 兼容新旧版本 Xray x25519 输出格式
            # 旧版: "Private key: xxx" / "Public key: xxx"
            # 新版: "PrivateKey: xxx" / "Password: xxx"
            realityPrivateKey=$(echo "${realityX25519Key}" | grep -E "Private|PrivateKey" | awk '{print $NF}')
            realityPublicKey=$(echo "${realityX25519Key}" | grep -E "Public|Password" | awk '{print $NF}')
            if [[ -z "${realityPrivateKey}" ]]; then
                echoContent red "输入的Private Key不合法"
                initRealityKey
            else
                echoContent green "\n privateKey:${realityPrivateKey}"
                echoContent green "\n publicKey:${realityPublicKey}"
            fi
        fi
    fi
}

# 生成随机 Reality shortIds
initRealityShortIds() {
    if [[ -z "${realityShortId1}" ]]; then
        realityShortId1=$(openssl rand -hex 8)
        realityShortId2=$(openssl rand -hex 8)
    fi
}

# 初始化 mldsa65Seed
initRealityMldsa65() {
    echoContent skyBlue "\n生成Reality mldsa65\n"
    if /etc/Proxy-agent/xray/xray tls ping "${realityServerName}:${realityDomainPort}" 2>/dev/null | grep -q "X25519MLKEM768"; then
        length=$(/etc/Proxy-agent/xray/xray tls ping "${realityServerName}:${realityDomainPort}" | grep "Certificate chain's total length:" | awk '{print $5}' | head -1)

        if [ "$length" -gt 3500 ]; then
            if [[ -n "${currentRealityMldsa65}" && -z "${lastInstallationConfig}" ]]; then
                read -r -p "读取到上次安装记录，是否使用上次安装时的Seed/Verify ？[y/n]:" historyMldsa65Status
                if [[ "${historyMldsa65Status}" == "y" ]]; then
                    realityMldsa65Seed=${currentRealityMldsa65Seed}
                    realityMldsa65Verify=${currentRealityMldsa65Verify}
                fi
            elif [[ -n "${currentRealityMldsa65Seed}" && -n "${lastInstallationConfig}" ]]; then
                realityMldsa65Seed=${currentRealityMldsa65Seed}
                realityMldsa65Verify=${currentRealityMldsa65Verify}
            fi
            if [[ -z "${realityMldsa65Seed}" ]]; then
                #        if [[ "${selectCoreType}" == "2" || "${coreInstallType}" == "2" ]]; then
                #            realityX25519Key=$(/etc/Proxy-agent/sing-box/sing-box generate reality-keypair)
                #            realityPrivateKey=$(echo "${realityX25519Key}" | head -1 | awk '{print $2}')
                #            realityPublicKey=$(echo "${realityX25519Key}" | tail -n 1 | awk '{print $2}')
                #            echo "publicKey:${realityPublicKey}" >/etc/Proxy-agent/sing-box/conf/config/reality_key
                #        else
                realityMldsa65=$(/etc/Proxy-agent/xray/xray mldsa65)
                realityMldsa65Seed=$(echo "${realityMldsa65}" | head -1 | awk '{print $2}')
                realityMldsa65Verify=$(echo "${realityMldsa65}" | tail -n 1 | awk '{print $2}')
                #        fi
            fi
            #    echoContent green "\n Seed:${realityMldsa65Seed}"
            #    echoContent green "\n Verify:${realityMldsa65Verify}"
        else
            echoContent green " 目标域名支持X25519MLKEM768，但是证书的长度不足，忽略ML-DSA-65。"
        fi
    else
        echoContent green " 目标域名不支持X25519MLKEM768，忽略ML-DSA-65。"
    fi
}
# 检查reality域名是否符合
checkRealityDest() {
    local traceResult=
    traceResult=$(curl -s "https://$(echo "${realityDestDomain}" | cut -d ':' -f 1)/cdn-cgi/trace" | grep "visit_scheme=https")
    if [[ -n "${traceResult}" ]]; then
        echoContent red "\n ---> 检测到使用的域名，托管在cloudflare并开启了代理，使用此类型域名可能导致VPS流量被其他人使用[不建议使用]\n"
        read -r -p "是否继续 ？[y/n]" setRealityDestStatus
        if [[ "${setRealityDestStatus}" != 'y' ]]; then
            exit 1
        fi
        echoContent yellow "\n ---> 忽略风险，继续使用"
    fi
}

# 初始化客户端可用的ServersName
initRealityClientServersName() {
    local realityDestDomainList="gateway.icloud.com,itunes.apple.com,swdist.apple.com,swcdn.apple.com,updates.cdn-apple.com,mensura.cdn-apple.com,osxapps.itunes.apple.com,aod.itunes.apple.com,download-installer.cdn.mozilla.net,addons.mozilla.org,s0.awsstatic.com,d1.awsstatic.com,cdn-dynmedia-1.microsoft.com,images-na.ssl-images-amazon.com,m.media-amazon.com,player.live-video.net,one-piece.com,lol.secure.dyn.riotcdn.net,www.lovelive-anime.jp,academy.nvidia.com,software.download.prss.microsoft.com,dl.google.com,www.google-analytics.com,www.caltech.edu,www.calstatela.edu,www.suny.edu,www.suffolk.edu,www.python.org,vuejs-jp.org,vuejs.org,zh-hk.vuejs.org,react.dev,www.java.com,www.oracle.com,www.mysql.com,www.mongodb.com,redis.io,cname.vercel-dns.com,vercel-dns.com,www.swift.com,academy.nvidia.com,www.swift.com,www.cisco.com,www.asus.com,www.samsung.com,www.amd.com,www.umcg.nl,www.fom-international.com,www.u-can.co.jp,github.io"
    if [[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]; then
        if echo ${realityDestDomainList} | grep -q "${realityServerName}"; then
            read -r -p "读取到上次安装设置的Reality域名，是否使用？[y/n]:" realityServerNameStatus
            if [[ "${realityServerNameStatus}" != "y" ]]; then
                realityServerName=
                realityDomainPort=
            fi
        else
            realityServerName=
            realityDomainPort=
        fi
    fi

    if [[ -z "${realityServerName}" ]]; then
        if [[ -n "${domain}" ]]; then
            echo
            read -r -p "是否使用 ${domain} 此域名作为Reality目标域名 ？[y/n]:" realityServerNameCurrentDomainStatus
            if [[ "${realityServerNameCurrentDomainStatus}" == "y" ]]; then
                realityServerName="${domain}"
                if [[ "${selectCoreType}" == "1" ]]; then
                    if [[ -z "${subscribePort}" ]]; then
                        echo
                        installSubscribe
                        readNginxSubscribe
                        realityDomainPort="${subscribePort}"
                    else
                        realityDomainPort="${subscribePort}"
                    fi
                fi
                if [[ "${selectCoreType}" == "2" ]]; then
                    if [[ -z "${subscribePort}" ]]; then
                        echo
                        installSubscribe
                        readNginxSubscribe
                        realityDomainPort="${subscribePort}"
                    else
                        realityDomainPort="${subscribePort}"
                    fi
                fi
            fi
        fi
        if [[ -z "${realityServerName}" ]]; then
            realityDomainPort=443
            echoContent skyBlue "\n================ 配置客户端可用的serverNames ===============\n"
            echoContent yellow "#注意事项"
            echoContent green "请确保所选 Reality 目标域名支持 TLS，且为可直连的常见站点。\n"
            echoContent yellow "录入示例:addons.mozilla.org:443\n"
            read -r -p "请输入目标域名，[回车]随机域名，默认端口443:" realityServerName
            if [[ -z "${realityServerName}" ]]; then
                randomNum=$(randomNum 1 27)
                realityServerName=$(echo "${realityDestDomainList}" | awk -F ',' -v randomNum="$randomNum" '{print $randomNum}')
            else
                # 验证用户输入的域名（可能包含端口，先提取域名部分验证）
                local realityDomainCheck="${realityServerName%%:*}"
                if ! isValidDomain "${realityDomainCheck}"; then
                    echoContent red " ---> 域名格式无效或包含不安全字符"
                    exit 1
                fi
            fi
            if echo "${realityServerName}" | grep -q ":"; then
                realityDomainPort=$(echo "${realityServerName}" | awk -F "[:]" '{print $2}')
                realityServerName=$(echo "${realityServerName}" | awk -F "[:]" '{print $1}')
            fi
        fi
    fi

    echoContent yellow "\n ---> 客户端可用域名: ${realityServerName}:${realityDomainPort}\n"
}
# 初始化reality端口
initXrayRealityPort() {
    if [[ -n "${xrayVLESSRealityPort}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的端口 ？[y/n]:" historyRealityPortStatus
        if [[ "${historyRealityPortStatus}" == "y" ]]; then
            realityPort=${xrayVLESSRealityPort}
        fi
    elif [[ -n "${xrayVLESSRealityPort}" && -n "${lastInstallationConfig}" ]]; then
        realityPort=${xrayVLESSRealityPort}
    fi

    if [[ -z "${realityPort}" ]]; then
        #        if [[ -n "${port}" ]]; then
        #            read -r -p "是否使用TLS+Vision端口 ？[y/n]:" realityPortTLSVisionStatus
        #            if [[ "${realityPortTLSVisionStatus}" == "y" ]]; then
        #                realityPort=${port}
        #            fi
        #        fi
        #        if [[ -z "${realityPort}" ]]; then
        echoContent yellow "请输入端口[回车随机10000-30000]"

        read -r -p "端口:" realityPort
        if [[ -z "${realityPort}" ]]; then
            realityPort=$(randomNum 10000 30000)
        fi
        #        fi
        if [[ -n "${realityPort}" && "${xrayVLESSRealityPort}" == "${realityPort}" ]]; then
            handleXray stop
        else
            checkPort "${realityPort}"
        fi
    fi
    if [[ -z "${realityPort}" ]]; then
        initXrayRealityPort
    else
        allowPort "${realityPort}"
        echoContent yellow "\n ---> 端口: ${realityPort}"
    fi

}
# 初始化XHTTP端口
initXrayXHTTPort() {
    if [[ -n "${xrayVLESSRealityXHTTPort}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的端口 ？[y/n]:" historyXHTTPortStatus
        if [[ "${historyXHTTPortStatus}" == "y" ]]; then
            xHTTPort=${xrayVLESSRealityXHTTPort}
        fi
    elif [[ -n "${xrayVLESSRealityXHTTPort}" && -n "${lastInstallationConfig}" ]]; then
        xHTTPort=${xrayVLESSRealityXHTTPort}
    fi

    if [[ -z "${xHTTPort}" ]]; then

        echoContent yellow "请输入端口[回车随机10000-30000]"
        read -r -p "端口:" xHTTPort
        if [[ -z "${xHTTPort}" ]]; then
            xHTTPort=$(randomNum 10000 30000)
        fi
        if [[ -n "${xHTTPort}" && "${xrayVLESSRealityXHTTPort}" == "${xHTTPort}" ]]; then
            handleXray stop
        else
            checkPort "${xHTTPort}"
        fi
    fi
    if [[ -z "${xHTTPort}" ]]; then
        initXrayXHTTPort
    else
        allowPort "${xHTTPort}"
        allowPort "${xHTTPort}" "udp"
        echoContent yellow "\n ---> 端口: ${xHTTPort}"
    fi
}

# reality管理
manageReality() {
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig

    if ! echo "${currentInstallProtocolType}" | grep -q -E "7,|8," || [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 请先安装Reality协议，并确认已配置可用的 serverName/公钥。"
        exit 1
    fi

    if [[ "${coreInstallType}" == "1" ]]; then
        selectCustomInstallType=",7,"
        initXrayConfig custom 1 true
    elif [[ "${coreInstallType}" == "2" ]]; then
        if echo "${currentInstallProtocolType}" | grep -q ",7,"; then
            selectCustomInstallType=",7,"
        fi
        if echo "${currentInstallProtocolType}" | grep -q ",8,"; then
            selectCustomInstallType="${selectCustomInstallType},8,"
        fi
        initSingBoxConfig custom 1 true
    fi

    reloadCore
    subscribe false
}

# 安装reality scanner
installRealityScanner() {
    if [[ ! -f "/etc/Proxy-agent/xray/reality_scan/RealiTLScanner-linux-64" ]]; then
        version=$(curl -s https://api.github.com/repos/XTLS/RealiTLScanner/releases?per_page=1 | jq -r '.[]|.tag_name')
        wget -c -q -P /etc/Proxy-agent/xray/reality_scan/ "https://github.com/XTLS/RealiTLScanner/releases/download/${version}/RealiTLScanner-linux-64"
        chmod 655 /etc/Proxy-agent/xray/reality_scan/RealiTLScanner-linux-64
    fi
}
# reality scanner
realityScanner() {
    echoContent skyBlue "\n进度 1/1 : 扫描Reality域名"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "扫描完成后，请自行检查扫描网站结果内容是否合规，需个人承担风险"
    echoContent red "某些IDC不允许扫描操作，比如搬瓦工，其中风险请自行承担\n"
    echoContent yellow "1.扫描IPv4"
    echoContent yellow "2.扫描IPv6"
    echoContent red "=============================================================="
    read -r -p "请选择:" realityScannerStatus
    local type=
    if [[ "${realityScannerStatus}" == "1" ]]; then
        type=4
    elif [[ "${realityScannerStatus}" == "2" ]]; then
        type=6
    fi

    read -r -p "某些IDC不允许扫描操作，比如搬瓦工，其中风险请自行承担，是否继续？[y/n]:" scanStatus

    if [[ "${scanStatus}" != "y" ]]; then
        exit 0
    fi

    publicIP=$(getPublicIP "${type}")
    echoContent yellow "IP:${publicIP}"
    if [[ -z "${publicIP}" ]]; then
        echoContent red " ---> 无法获取IP"
        exit 1
    fi

    read -r -p "IP是否正确？[y/n]:" ipStatus
    if [[ "${ipStatus}" == "y" ]]; then
        echoContent yellow "结果存储在 /etc/Proxy-agent/xray/reality_scan/result.log 文件中\n"
        /etc/Proxy-agent/xray/reality_scan/RealiTLScanner-linux-64 -addr "${publicIP}" | tee /etc/Proxy-agent/xray/reality_scan/result.log
    else
        echoContent red " ---> 无法读取正确IP"
    fi
}
# hysteria管理
manageHysteria() {
    echoContent skyBlue "\n进度  1/1 : Hysteria2 管理"
    echoContent red "\n=============================================================="
    local hysteria2Status=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/Proxy-agent/sing-box/conf/config/06_hysteria2_inbounds.json" ]]; then
        echoContent yellow "依赖第三方sing-box\n"
        echoContent yellow "1.重新安装"
        echoContent yellow "2.卸载"
        echoContent yellow "3.端口跳跃管理"
        hysteria2Status=true
    else
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.安装"
    fi

    echoContent red "=============================================================="
    read -r -p "请选择:" installHysteria2Status
    if [[ "${installHysteria2Status}" == "1" ]]; then
        singBoxHysteria2Install
    elif [[ "${installHysteria2Status}" == "2" && "${hysteria2Status}" == "true" ]]; then
        unInstallSingBox hysteria2
    elif [[ "${installHysteria2Status}" == "3" && "${hysteria2Status}" == "true" ]]; then
        portHoppingMenu hysteria2
    fi
}

# tuic管理
manageTuic() {
    echoContent skyBlue "\n进度  1/1 : Tuic管理"
    echoContent red "\n=============================================================="
    local tuicStatus=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/Proxy-agent/sing-box/conf/config/09_tuic_inbounds.json" ]]; then
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.重新安装"
        echoContent yellow "2.卸载"
        echoContent yellow "3.端口跳跃管理"
        tuicStatus=true
    else
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.安装"
    fi

    echoContent red "=============================================================="
    read -r -p "请选择:" installTuicStatus
    if [[ "${installTuicStatus}" == "1" ]]; then
        singBoxTuicInstall
    elif [[ "${installTuicStatus}" == "2" && "${tuicStatus}" == "true" ]]; then
        unInstallSingBox tuic
    elif [[ "${installTuicStatus}" == "3" && "${tuicStatus}" == "true" ]]; then
        portHoppingMenu tuic
    fi
}
# sing-box log日志
singBoxLog() {
    cat <<EOF >/etc/Proxy-agent/sing-box/conf/config/log.json
{
  "log": {
    "disabled": $1,
    "level": "warn",
    "output": "/etc/Proxy-agent/sing-box/conf/box.log",
    "timestamp": true
  }
}
EOF

    handleSingBox stop
    handleSingBox start
}

# sing-box 版本管理
singBoxVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : sing-box 版本管理"
    if [[ -z "${singBoxConfigPath}" ]]; then
        echoContent red " ---> 没有检测到安装程序，请执行脚本安装内容"
        menu
        exit 1
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级 sing-box"
    echoContent yellow "2.关闭 sing-box"
    echoContent yellow "3.打开 sing-box"
    echoContent yellow "4.重启 sing-box"
    echoContent yellow "=============================================================="
    local logStatus=
    if [[ -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}log.json" && "$(jq -r .log.disabled "${singBoxConfigPath}log.json")" == "false" ]]; then
        echoContent yellow "5.关闭日志"
        logStatus=true
    else
        echoContent yellow "5.启用日志"
        logStatus=false
    fi

    echoContent yellow "6.查看日志"
    echoContent red "=============================================================="

    read -r -p "请选择:" selectSingBoxType
    if [[ ! -f "${singBoxConfigPath}../box.log" ]]; then
        touch "${singBoxConfigPath}../box.log" >/dev/null 2>&1
    fi
    if [[ "${selectSingBoxType}" == "1" ]]; then
        installSingBox 1
        handleSingBox stop
        handleSingBox start
    elif [[ "${selectSingBoxType}" == "2" ]]; then
        handleSingBox stop
    elif [[ "${selectSingBoxType}" == "3" ]]; then
        handleSingBox start
    elif [[ "${selectSingBoxType}" == "4" ]]; then
        handleSingBox stop
        handleSingBox start
    elif [[ "${selectSingBoxType}" == "5" ]]; then
        singBoxLog ${logStatus}
        if [[ "${logStatus}" == "false" ]]; then
            tail -f "${singBoxConfigPath}../box.log"
        fi
    elif [[ "${selectSingBoxType}" == "6" ]]; then
        tail -f "${singBoxConfigPath}../box.log"
    fi
}

# ============================================================================
# 切换语言 / Switch Language
# ============================================================================
switchLanguage() {
    local langFile="/etc/Proxy-agent/lang_pref"
    local currentLang="${CURRENT_LANG:-zh_CN}"
    local scriptPath="/etc/Proxy-agent/install.sh"

    # 如果安装目录的脚本不存在，使用当前脚本路径
    if [[ ! -f "${scriptPath}" ]]; then
        scriptPath="${_SCRIPT_DIR}/install.sh"
    fi

    echoContent red "\n=============================================================="
    echoContent skyBlue "当前语言 / Current Language: ${currentLang}"
    echoContent red "=============================================================="
    echoContent yellow "1. 中文 (Chinese)"
    echoContent yellow "2. English"
    echoContent yellow "0. 返回 / Back"
    echoContent red "=============================================================="

    read -r -p "请选择 / Select: " langChoice

    case "${langChoice}" in
        1)
            echo "zh_CN" > "${langFile}"
            export V2RAY_LANG="zh_CN"
            echoContent green "语言已设置为中文，重新加载菜单..."
            sleep 1
            exec bash "${scriptPath}"
            ;;
        2)
            echo "en_US" > "${langFile}"
            export V2RAY_LANG="en_US"
            echoContent green "Language set to English, reloading menu..."
            sleep 1
            exec bash "${scriptPath}"
            ;;
        0|*)
            menu
            ;;
    esac
}

# 主菜单
menu() {
    cd "$HOME" || exit
    echoContent red "\n=============================================================="
    echoContent green "$(t MENU_AUTHOR): Lynthar"

    # 显示版本号，并在后台检查更新
    local versionDisplay="${SCRIPT_VERSION}"
    if [[ -n "${LATEST_VERSION}" ]] && compareVersions "${SCRIPT_VERSION}" "${LATEST_VERSION}"; then
        versionDisplay="${SCRIPT_VERSION} -> ${LATEST_VERSION} [有更新/Update Available]"
        echoContent yellow "$(t MENU_VERSION): ${versionDisplay}"
    else
        echoContent green "$(t MENU_VERSION): ${versionDisplay}"
    fi

    echoContent green "$(t MENU_GITHUB): https://github.com/Lynthar/Proxy-agent"
    echoContent green "$(t MENU_DESC): $(t MENU_TITLE)"
    showInstallStatus
    checkWgetShowProgress
    if [[ -n "${coreInstallType}" ]]; then
        echoContent yellow "1.$(t MENU_REINSTALL)"
    else
        echoContent yellow "1.$(t MENU_INSTALL)"
    fi

    echoContent yellow "2.$(t MENU_COMBO_INSTALL)"
    echoContent yellow "3.$(t MENU_CHAIN_PROXY)"
    echoContent yellow "4.$(t MENU_HYSTERIA2)"
    echoContent yellow "5.$(t MENU_REALITY)"
    echoContent yellow "6.$(t MENU_TUIC)"

    echoContent skyBlue "-------------------------$(t MENU_TOOL_MGMT)-----------------------------"
    echoContent yellow "7.$(t MENU_USER)"
    echoContent yellow "8.$(t MENU_DISGUISE)"
    echoContent yellow "9.$(t MENU_CERT)"
    echoContent yellow "10.$(t MENU_CDN)"
    echoContent yellow "11.$(t MENU_ROUTING)"
    echoContent yellow "12.$(t MENU_ADD_PORT)"
    echoContent yellow "13.$(t MENU_BT)"
    echoContent yellow "15.$(t MENU_BLACKLIST)"
    echoContent skyBlue "-------------------------$(t MENU_VERSION_MGMT)-----------------------------"
    echoContent yellow "16.$(t MENU_CORE)"
    echoContent yellow "17.$(t MENU_UPDATE_SCRIPT)"
    echoContent yellow "18.$(t MENU_BBR)"
    echoContent skyBlue "-------------------------$(t MENU_SCRIPT_MGMT)-----------------------------"
    echoContent yellow "20.$(t MENU_UNINSTALL)"
    echoContent yellow "21.切换语言 / Switch Language"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -r -p "$(t PROMPT_SELECT):" selectInstallType
    case ${selectInstallType} in
    1)
        selectCoreInstall
        ;;
    2)
        selectCoreInstall
        ;;
    3)
        chainProxyMenu
        ;;
    4)
        manageHysteria
        ;;
    5)
        manageReality 1
        ;;
    6)
        manageTuic
        ;;
    7)
        manageAccount 1
        ;;
    8)
        updateNginxBlog 1
        ;;
    9)
        renewalTLS 1
        ;;
    10)
        manageCDN 1
        ;;
    11)
        routingToolsMenu 1
        ;;
    12)
        addCorePort 1
        ;;
    13)
        btTools 1
        ;;
    14)
        switchAlpn 1
        ;;
    15)
        blacklist 1
        ;;
    16)
        coreVersionManageMenu 1
        ;;
    17)
        updateV2RayAgent 1
        ;;
    18)
        bbrInstall
        ;;
    20)
        unInstall 1
        ;;
    21)
        switchLanguage
        ;;
    esac
}

# 启动时检查更新（使用短超时，避免阻塞太久）
checkForUpdates 2>/dev/null

cronFunction
menu
