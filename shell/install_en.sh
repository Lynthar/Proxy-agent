#!/usr/bin/env bash
# Detect区
# -------------------------------------------------------------
# Check System
export LANG=en_US.UTF-8

# ============================================================================
# Module Loading
# If lib directory exists, load modular components
# This allows gradual refactoring while maintaining backward compatibility
# ============================================================================

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="${_SCRIPT_DIR}/lib"

# Load modules (if they exist)
if [[ -d "${_LIB_DIR}" ]]; then
    # Loading order is important:
    # Phase 1: constants -> utils -> system-detect -> service-control
    # Phase 2: json-utils -> protocol-registry -> config-reader
    for _module in constants utils json-utils system-detect service-control protocol-registry config-reader; do
        if [[ -f "${_LIB_DIR}/${_module}.sh" ]]; then
            # shellcheck source=/dev/null
            source "${_LIB_DIR}/${_module}.sh"
        fi
    done
fi

# Clean up temporary variables
unset _SCRIPT_DIR _LIB_DIR _module

# ============================================================================

echoContent() {
    case $1 in
    # Red
    "red")
        # shellcheck disable=SC2154
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # Sky Blue
    "skyBlue")
        ${echoType} "\033[1;36m${printN}$2 \033[0m"
        ;;
        # Green
    "green")
        ${echoType} "\033[32m${printN}$2 \033[0m"
        ;;
        # White
    "white")
        ${echoType} "\033[37m${printN}$2 \033[0m"
        ;;
    "magenta")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # Yellow
    "yellow")
        ${echoType} "\033[33m${printN}$2 \033[0m"
        ;;
    esac
}
# 检checkSELinuxstatus
checkCentosSELinux() {
    if [[ -f "/etc/selinux/config" ]] && ! grep -q "SELINUX=disabled" <"/etc/selinux/config"; then
        echoContent yellow "# focus意事项"
        echoContent yellow "DetecttoSELinux已enable，invite手movedisable（例如at /etc/selinux/config Set SELINUX=disabled 并Restart）。"
        exit 0
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
        echoContent red "\nThis script does not support this system. Please provide the logs below to the developer\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

# 检checkCPUlift供商
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
                echo "  not supported此CPU架构--->"
                exit 1
                ;;
            esac
        fi
    else
        echoContent red "  cannot识别此CPU架构，defaultamd64、x86_64--->"
        xrayCoreCPUVendor="Xray-linux-64"
        #        v2rayCoreCPUVendor="v2ray-linux-64"
    fi
}

# Initialize Global Variables
initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
    #    sudoCMD=""

    # Core supported CPU versions
    xrayCoreCPUVendor=""
    warpRegCoreCPUVendor=""
    cpuVendor=""

    # Domain
    domain=
    # Install总Progress
    totalProgress=1

    # 1.xray-coreInstall
    # 2.v2ray-core Install
    # 3.v2ray-core[xtls] Install
    coreInstallType=

    # coreInstallpath
    # coreInstallPath=

    # v2ctl Path
    ctlPath=
    # 1.allInstall
    # 2.personalizationInstall
    # v2rayAgentInstallType=

    # current的personalizationInstallsquarestyle 01234
    currentInstallProtocolType=

    # currentalpn的顺序
    currentAlpn=

    # Frontend type
    frontingType=

    # Select的personalizationInstallsquarestyle
    selectCustomInstallType=

    # Path to v2ray-core and xray-core config files
    configPath=

    # xray-core reality status
    realityStatus=

    # sing-box config file path
    singBoxConfigPath=

    # sing-box ports

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

    # nginx subscription port
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
    # Port hopping
    portHoppingStart=
    portHoppingEnd=
    portHopping=

    hysteria2PortHoppingStart=
    hysteria2PortHoppingEnd=
    hysteria2PortHopping=

    #    tuicPortHoppingStart=
    #    tuicPortHoppingEnd=
    #    tuicPortHopping=

    # tuic config file path
    #    tuicConfigPath=
    tuicAlgorithm=
    tuicPort=

    # Configurefile的path
    currentPath=

    # Configurefile的host
    currentHost=

    # Install时Select的coretypemodel
    selectCoreType=

    # defaultcoreversion
    #    v2rayCoreVersion=

    # randompath
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

    # scheduled tasks执line任务名称 RenewTLS-Updatecertificate UpdateGeo-Updategeofile
    cronName=$1

    # tlsInstallation failedbacktry的timecount
    installTLSCount=

    # BTPanelstatus
    #	BTPanelStatus=
    # 宝塔domain
    btDomain=
    # nginxConfigurefilepath
    nginxConfigPath=/etc/nginx/conf.d/
    nginxStaticPath=/usr/share/nginx/html/

    # yesnoas预viewversion
    prereleaseStatus=false

    # ssltypemodel
    sslType=
    # SSL CF API Token
    cfAPIToken=

    # ssl邮箱
    sslEmail=

    # 检check天count
    sslRenewalDays=90

    # dns sslstatus
    #    dnsSSLStatus=

    # dns tls domain
    dnsTLSDomain=
    ipType=

    # shoulddomainyesnopassdnsInstallthrough配符certificate
    #    installDNSACMEStatus=

    # customport
    customPort=

    # hysteriaport
    hysteriaPort=

    # hysteriaprotocol
    #    hysteriaProtocol=

    # hysteria延迟
    #    hysteriaLag=

    # hysteriadownline速degree
    hysteria2ClientDownloadSpeed=

    # hysteriaupline速degree
    hysteria2ClientUploadSpeed=

    # Reality
    realityPrivateKey=
    realityServerName=
    realityDestDomain=

    # portstatus
    #    isPortOpen=
    # through配符domainstatus
    #    wildcardDomainStatus=
    # passnginx检check的port
    #    nginxIPort=

    # wget show progress
    wgetShowProgressStatus=

    # warp
    reservedWarpReg=
    publicKeyWarpReg=
    addressWarpReg=
    secretKeyWarpReg=

    socks5RoutingOutboundAuthType=
    socks5RoutingOutboundUnifiedKey=

    socks5InboundAuthType=
    socks5InboundUserName=
    socks5InboundPassword=
    socks5InboundUnifiedKey=

    # uptimeInstallConfigurestatus
    lastInstallationConfig=

}

stripAnsi() {
    echo -e "$1" | sed $'s/\x1b\[[0-9;]*[a-zA-Z]//g'
}

validateJsonFile() {

    local jsonPath=$1
    if ! jq -e . "${jsonPath}" >/dev/null 2>&1; then
        echoContent red " ---> ${jsonPath} unlock析Failed，已移除，invite检checkabove录入并retry"
        rm -f "${jsonPath}"
        exit 0
    fi
}

readCredentialBySource() {

    local tips=$1
    local defaultValue=$2
    echoContent skyBlue "\n${tips}Credentials for handshake configuration. Can be entered manually, via file, or environment variable" >&2
    echoContent yellow "Please select${tips}录入squarestyle（自move化part署availablefileor环environment变measure）" >&2
    echoContent yellow "1.straightcatchInput${defaultValue:+[return车default] }" >&2
    echoContent yellow "2.fromfileRead" >&2
    echoContent yellow "3.from环environment变measureRead" >&2
    echo -n "Please select:" >&2
    read -r credentialSource
    local credentialValue=
    case ${credentialSource} in
    2)
        echo -n "Please enterfilepath:" >&2
        read -r credentialPath
        if [[ -z "${credentialPath}" || ! -f "${credentialPath}" ]]; then
            echoContent red " ---> filepathinvalid"
            exit 0
        fi
        credentialValue=$(tr -d '\n' <"${credentialPath}")
        ;;
    3)
        echo -n "Please enter环environment变measure名称:" >&2
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

    # go除may的ANSI控制符，防stopWriteConfigurefileback产生\x1bError
    credentialValue=$(stripAnsi "${credentialValue}")

    if [[ -z "${credentialValue}" ]]; then
        echoContent red " ---> ${tips}cannot be empty"
        exit 0
    fi

    echo "${credentialValue}"
}

# Readtlscertificate详feeling
readAcmeTLS() {
    local readAcmeDomain=
    if [[ -n "${currentHost}" ]]; then
        readAcmeDomain="${currentHost}"
    fi

    if [[ -n "${domain}" ]]; then
        readAcmeDomain="${domain}"
    fi

    dnsTLSDomain=$(echo "${readAcmeDomain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    if [[ -d "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc" && -f "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.key" && -f "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer" ]]; then
        installedDNSAPIStatus=true
    fi
}

# Readdefaultcustomport
readCustomPort() {
    if [[ -n "${configPath}" && -z "${realityStatus}" && "${coreInstallType}" == "1" ]]; then
        local port=
        port=$(jq -r .inbounds[0].port "${configPath}${frontingType}.json")
        if [[ "${port}" != "443" ]]; then
            customPort=${port}
        fi
    fi
}

# Readnginxsubscriptionport
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

# DetectInstallsquarestyle
readInstallType() {
    coreInstallType=
    configPath=
    singBoxConfigPath=

    # 1.DetectInstalldirectory
    if [[ -d "/etc/v2ray-agent" ]]; then
        if [[ -f "/etc/v2ray-agent/xray/xray" ]]; then
            # Detectxray-core
            if [[ -d "/etc/v2ray-agent/xray/conf" ]] && [[ -f "/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" || -f "/etc/v2ray-agent/xray/conf/02_trojan_TCP_inbounds.json" || -f "/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" ]]; then
                # xray-core
                configPath=/etc/v2ray-agent/xray/conf/
                ctlPath=/etc/v2ray-agent/xray/xray
                coreInstallType=1
                if [[ -f "${configPath}07_VLESS_vision_reality_inbounds.json" ]]; then
                    realityStatus=1
                fi
                if [[ -f "/etc/v2ray-agent/sing-box/sing-box" ]] && [[ -f "/etc/v2ray-agent/sing-box/conf/config/06_hysteria2_inbounds.json" || -f "/etc/v2ray-agent/sing-box/conf/config/09_tuic_inbounds.json" || -f "/etc/v2ray-agent/sing-box/conf/config/20_socks5_inbounds.json" ]]; then
                    singBoxConfigPath=/etc/v2ray-agent/sing-box/conf/config/
                fi
            fi
        elif [[ -f "/etc/v2ray-agent/sing-box/sing-box" && -f "/etc/v2ray-agent/sing-box/conf/config.json" ]]; then
            # Detectsing-box
            ctlPath=/etc/v2ray-agent/sing-box/sing-box
            coreInstallType=2
            configPath=/etc/v2ray-agent/sing-box/conf/config/
            singBoxConfigPath=/etc/v2ray-agent/sing-box/conf/config/
        fi
    fi
}

# Readprotocoltypemodel
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
    singBoxSocks5Port=

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
        if echo "${row}" | grep -q socks5_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}20,"
            singBoxSocks5Port=$(jq .inbounds[0].listen_port "${row}.json")
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

# 检checkyesnoInstall宝塔
checkBTPanel() {
    if [[ -n $(pgrep -f "BT-Panel") ]]; then
        # Readdomain
        if [[ -d '/www/server/panel/vhost/cert/' && -n $(find /www/server/panel/vhost/cert/*/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\nReading BT Panel configuration\n"

                find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}'

                read -r -p "Please enterweave号Select:" selectBTDomain
            else
                selectBTDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep -e "^${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> Wrong selection, please select again"
                    checkBTPanel
                else
                    domain=${btDomain}
                    if [[ ! -f "/etc/v2ray-agent/tls/${btDomain}.crt" && ! -f "/etc/v2ray-agent/tls/${btDomain}.key" ]]; then
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/fullchain.pem" "/etc/v2ray-agent/tls/${btDomain}.crt"
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/privkey.pem" "/etc/v2ray-agent/tls/${btDomain}.key"
                    fi

                    nginxStaticPath="/www/wwwroot/${btDomain}/html/"

                    mkdir -p "/www/wwwroot/${btDomain}/html/"

                    if [[ -f "/www/wwwroot/${btDomain}/.user.ini" ]]; then
                        chattr -i "/www/wwwroot/${btDomain}/.user.ini"
                    fi
                    nginxConfigPath="/www/server/panel/vhost/nginx/"
                fi
            else
                echoContent red " ---> Wrong selection, please select again"
                checkBTPanel
            fi
        fi
    fi
}
check1Panel() {
    if [[ -n $(pgrep -f "1panel") ]]; then
        # Readdomain
        if [[ -d '/opt/1panel/apps/openresty/openresty/www/sites/' && -n $(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\nReading 1Panel configuration\n"

                find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}'

                read -r -p "Please enterweave号Select:" selectBTDomain
            else
                selectBTDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> Wrong selection, please select again"
                    check1Panel
                else
                    domain=${btDomain}
                    if [[ ! -f "/etc/v2ray-agent/tls/${btDomain}.crt" && ! -f "/etc/v2ray-agent/tls/${btDomain}.key" ]]; then
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/fullchain.pem" "/etc/v2ray-agent/tls/${btDomain}.crt"
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/privkey.pem" "/etc/v2ray-agent/tls/${btDomain}.key"
                    fi

                    nginxStaticPath="/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/index/"
                fi
            else
                echoContent red " ---> Wrong selection, please select again"
                check1Panel
            fi
        fi
    fi
}
# Readcurrentalpn的顺序
readInstallAlpn() {
    if [[ -n "${currentInstallProtocolType}" && -z "${realityStatus}" ]]; then
        local alpn
        alpn=$(jq -r .inbounds[0].streamSettings.tlsSettings.alpn[0] ${configPath}${frontingType}.json)
        if [[ -n ${alpn} ]]; then
            currentAlpn=${alpn}
        fi
    fi
}

# 检checkfirewall
allowPort() {
    local type=$2
    local sourceRange=$3
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    # If firewall is active, add corresponding open port
    if dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+ufw"; then
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
            local nftComment="allow $1/${type}(mack-a)"
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
    elif dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+netfilter-persistent" && systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local updateFirewalldStatus=
        if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
            if ! iptables -C INPUT -p ${type} -s "${sourceRange}" --dport "$1" -m comment --comment "allow $1/${type}(mack-a)" -j ACCEPT 2>/dev/null; then
                updateFirewalldStatus=true
                iptables -I INPUT -p ${type} -s "${sourceRange}" --dport "$1" -m comment --comment "allow $1/${type}(mack-a)" -j ACCEPT
            fi
        elif ! iptables -L | grep -q "$1/${type}(mack-a)"; then
            updateFirewalldStatus=true
            iptables -I INPUT -p ${type} --dport "$1" -m comment --comment "allow $1/${type}(mack-a)" -j ACCEPT
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            netfilter-persistent save
        fi
    fi
}
# Get public IP
getPublicIP() {
    local type=4
    if [[ -n "$1" ]]; then
        type=$1
    fi
    if [[ -n "${currentHost}" && -z "$1" ]] && [[ "${singBoxVLESSRealityVisionServerName}" == "${currentHost}" || "${singBoxVLESSRealityGRPCServerName}" == "${currentHost}" || "${xrayVLESSRealityServerName}" == "${currentHost}" ]]; then
        echo "${currentHost}"
    else
        local currentIP=
        currentIP=$(curl -s "-${type}" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
        if [[ -z "${currentIP}" && -z "$1" ]]; then
            currentIP=$(curl -s "-6" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
        fi
        echo "${currentIP}"
    fi

}

# Output UFW port open status
checkUFWAllowPort() {
    if ufw status | grep -q "$1"; then
        echoContent green " ---> $1Port opened successfully"
    else
        echoContent red " ---> $1Port failed to open"
        exit 0
    fi
}

# Output firewall-cmd port open status
checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1" || firewall-cmd --list-rich-rules --permanent | grep -q "$1"; then
        echoContent green " ---> $1Port opened successfully"
    else
        echoContent red " ---> $1Port failed to open"
        exit 0
    fi
}

# Read Tuic Configuration
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

# Read last installation configuration
readLastInstallationConfig() {
    if [[ -n "${configPath}" ]]; then
        read -r -p "ReadtouptimeInstall的Configure，yesnomakeuse ？[y/n]:" lastInstallationConfigStatus
        if [[ "${lastInstallationConfigStatus}" == "y" ]]; then
            lastInstallationConfig=true
        fi
    fi
}
# Uninstall sing-box
unInstallSingBox() {
    local type=$1
    if [[ -n "${singBoxConfigPath}" ]]; then
        if grep -q 'tuic' </etc/v2ray-agent/sing-box/conf/config.json && [[ "${type}" == "tuic" ]]; then
            rm "${singBoxConfigPath}09_tuic_inbounds.json"
            echoContent green " ---> Deletesing-box tuicConfiguration successful"
        fi

        if grep -q 'hysteria2' </etc/v2ray-agent/sing-box/conf/config.json && [[ "${type}" == "hysteria2" ]]; then
            rm "${singBoxConfigPath}06_hysteria2_inbounds.json"
            echoContent green " ---> Deletesing-box hysteria2Configuration successful"
        fi
        rm "${singBoxConfigPath}config.json"
    fi

    readInstallType

    if [[ -n "${singBoxConfigPath}" ]]; then
        echoContent yellow " ---> Other configurations detected, keepingsing-boxcore"
        handleSingBox stop
        handleSingBox start
    else
        handleSingBox stop
        rm /etc/systemd/system/sing-box.service
        rm -rf /etc/v2ray-agent/sing-box/*
        echoContent green " ---> sing-box UninstallComplete"
    fi
}

# Check file directory and path
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

        # Install
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

    # Readpath
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

            # tryReadalpn h2 Path
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
    if [[ -f "/etc/v2ray-agent/cdn" ]] && [[ -n "$(head -1 /etc/v2ray-agent/cdn)" ]]; then
        currentCDNAddress=$(head -1 /etc/v2ray-agent/cdn)
    else
        currentCDNAddress="${currentHost}"
    fi
}

# Status display
showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
        if [[ "${coreInstallType}" == 1 ]]; then
            if [[ -n $(pgrep -f "xray/xray") ]]; then
                echoContent yellow "\nCore: Xray-core[Running]"
            else
                echoContent yellow "\nCore: Xray-core[Not running]"
            fi

        elif [[ "${coreInstallType}" == 2 ]]; then
            if [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
                echoContent yellow "\nCore: sing-box[Running]"
            else
                echoContent yellow "\nCore: sing-box[Not running]"
            fi
        fi
        # Readprotocoltypemodel
        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            echoContent yellow "Installedprotocol: \c"
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

# Clean old remnants
cleanUp() {
    if [[ "$1" == "xrayDel" ]]; then
        handleXray stop
        rm -rf /etc/v2ray-agent/xray/*
    elif [[ "$1" == "singBoxDel" ]]; then
        handleSingBox stop
        rm -rf /etc/v2ray-agent/sing-box/conf/config.json >/dev/null 2>&1
        rm -rf /etc/v2ray-agent/sing-box/conf/config/* >/dev/null 2>&1
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

# Initialize installation directory
mkdirTools() {
    mkdir -p /etc/v2ray-agent/tls
    mkdir -p /etc/v2ray-agent/subscribe_local/default
    mkdir -p /etc/v2ray-agent/subscribe_local/clashMeta

    mkdir -p /etc/v2ray-agent/subscribe_remote/default
    mkdir -p /etc/v2ray-agent/subscribe_remote/clashMeta

    mkdir -p /etc/v2ray-agent/subscribe/default
    mkdir -p /etc/v2ray-agent/subscribe/clashMetaProfiles
    mkdir -p /etc/v2ray-agent/subscribe/clashMeta

    mkdir -p /etc/v2ray-agent/subscribe/sing-box
    mkdir -p /etc/v2ray-agent/subscribe/sing-box_profiles
    mkdir -p /etc/v2ray-agent/subscribe_local/sing-box

    mkdir -p /etc/v2ray-agent/xray/conf
    mkdir -p /etc/v2ray-agent/xray/reality_scan
    mkdir -p /etc/v2ray-agent/xray/tmp
    mkdir -p /etc/systemd/system/
    mkdir -p /tmp/v2ray-agent-tls/

    mkdir -p /etc/v2ray-agent/warp

    mkdir -p /etc/v2ray-agent/sing-box/conf/config

    mkdir -p /usr/share/nginx/html/
}
# Detectroot
checkRoot() {
    if [ "$(id -u)" -ne 0 ]; then
        #        sudoCMD="sudo"
        echo "Non-root user detected, will use sudo to execute commands..."
    fi
}
# Install tools
installTools() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Installing tools"
    # Fix Ubuntu system issues
    if [[ "${release}" == "ubuntu" ]]; then
        dpkg --configure -a
    fi

    if [[ -n $(pgrep -f "apt") ]]; then
        pgrep -f apt | xargs kill -9
    fi

    echoContent green " ---> 检check、InstallUpdate【new机器know很slow，如long时间nonereverserespond，invite手moveStopbackheavynew执line】"

    ${upgrade} >/etc/v2ray-agent/install.log 2>&1
    if grep <"/etc/v2ray-agent/install.log" -q "changed"; then
        ${updateReleaseInfoChange} >/dev/null 2>&1
    fi

    if [[ "${release}" == "centos" ]]; then
        rm -rf /var/run/yum.pid
        ${installType} epel-release >/dev/null 2>&1
    fi

    if ! sudo --version >/dev/null 2>&1; then
        echoContent green " ---> Installsudo"
        ${installType} sudo >/dev/null 2>&1
    fi

    if ! wget --help >/dev/null 2>&1; then
        echoContent green " ---> Installwget"
        ${installType} wget >/dev/null 2>&1
    fi

    if ! command -v netfilter-persistent >/dev/null 2>&1; then
        if [[ "${release}" != "centos" ]]; then
            echoContent green " ---> Installiptables"
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
            ${installType} iptables-persistent >/dev/null 2>&1
        fi
    fi

    if ! curl --help >/dev/null 2>&1; then
        echoContent green " ---> Installcurl"
        ${installType} curl >/dev/null 2>&1
    fi

    if ! unzip >/dev/null 2>&1; then
        echoContent green " ---> Installunzip"
        ${installType} unzip >/dev/null 2>&1
    fi

    if ! socat -h >/dev/null 2>&1; then
        echoContent green " ---> Installsocat"
        ${installType} socat >/dev/null 2>&1
    fi

    if ! tar --help >/dev/null 2>&1; then
        echoContent green " ---> Installtar"
        ${installType} tar >/dev/null 2>&1
    fi

    if ! crontab -l >/dev/null 2>&1; then
        echoContent green " ---> Installcrontabs"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            ${installType} cron >/dev/null 2>&1
        else
            ${installType} crontabs >/dev/null 2>&1
        fi
    fi
    if ! jq --help >/dev/null 2>&1; then
        echoContent green " ---> Installjq"
        ${installType} jq >/dev/null 2>&1
    fi

    if ! command -v ld >/dev/null 2>&1; then
        echoContent green " ---> Installbinutils"
        ${installType} binutils >/dev/null 2>&1
    fi

    if ! openssl help >/dev/null 2>&1; then
        echoContent green " ---> Installopenssl"
        ${installType} openssl >/dev/null 2>&1
    fi

    if ! ping6 --help >/dev/null 2>&1; then
        echoContent green " ---> Installping6"
        ${installType} inetutils-ping >/dev/null 2>&1
    fi

    if ! qrencode --help >/dev/null 2>&1; then
        echoContent green " ---> Installqrencode"
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
        echoContent green " ---> Installlsof"
        ${installType} lsof >/dev/null 2>&1
    fi

    if ! dig -h >/dev/null 2>&1; then
        echoContent green " ---> Installdig"
        if echo "${installType}" | grep -qw "apt"; then
            ${installType} dnsutils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "yum"; then
            ${installType} bind-utils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "apk"; then
            ${installType} bind-tools >/dev/null 2>&1
        fi
    fi

    # Detecting Nginx version and providing uninstall option
    if echo "${selectCustomInstallType}" | grep -qwE ",7,|,8,|,7,8,"; then
        echoContent green " ---> Detecttono needdependencyNginx的service，SkipInstall"
    else
        if ! nginx >/dev/null 2>&1; then
            echoContent green " ---> Installnginx"
            installNginxTools
        else
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            if [[ ${nginxVersion} -lt 14 ]]; then
                read -r -p "Readtocurrent的Nginxversionnot supportedgRPC，knowguide致Installation failed，yesnoUninstallNginxbackheavynewInstall ？[y/n]:" unInstallNginxStatus
                if [[ "${unInstallNginxStatus}" == "y" ]]; then
                    ${removeType} nginx >/dev/null 2>&1
                    echoContent yellow " ---> nginxUninstallComplete"
                    echoContent green " ---> Installnginx"
                    installNginxTools >/dev/null 2>&1
                else
                    exit 0
                fi
            fi
        fi
    fi

    if ! command -v semanage >/dev/null 2>&1; then
        echoContent green " ---> Installsemanage"
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
        echoContent green " ---> Detecttono needdependencycertificate的service，SkipInstall"
    else
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            echoContent green " ---> Installing acme.sh"
            curl -s https://get.acme.sh | sh >/etc/v2ray-agent/tls/acme.log 2>&1

            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent red "  acmeInstallation failed--->"
                tail -n 100 /etc/v2ray-agent/tls/acme.log
                echoContent yellow "Error troubleshooting:"
                echoContent red "  1.Failed to get GitHub file. Please wait for GitHub to restore and try again. Status at [https://www.githubstatus.com/]"
                echoContent red "  2.acme.sh script has a bug. Check[https://github.com/acmesh-official/acme.sh] issues"
                echoContent red "  3.For pure IPv6 machines, please set NAT64. Execute the command below. If still not working, try other NAT64 servers"
                echoContent skyBlue "  sed -i \"1i\\\nameserver 2a00:1098:2b::1\\\nnameserver 2a00:1098:2c::1\\\nnameserver 2a01:4f8:c2c:123f::1\\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                exit 0
            fi
        fi
    fi

}
# Boot startup
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload
        systemctl enable "${serviceName}"
    fi
}
# Install Nginx
installNginxTools() {

    if [[ "${release}" == "debian" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb http://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
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
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
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

# Install warp
installWarp() {
    if [[ "${cpuVendor}" == "arm" ]]; then
        echoContent red " ---> Official WARP client does not support ARM architecture"
        exit 0
    fi

    ${installType} gnupg2 -y >/dev/null 2>&1
    if [[ "${release}" == "debian" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | sudo apt-key add - >/dev/null 2>&1
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        curl -s https://pkg.cloudflareclient.com/pubkey.gpg | sudo apt-key add - >/dev/null 2>&1
        echo "deb http://pkg.cloudflareclient.com/ focal main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
        sudo apt update >/dev/null 2>&1

    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        sudo rpm -ivh "http://pkg.cloudflareclient.com/cloudflare-release-el${centosVersion}.rpm" >/dev/null 2>&1
    fi

    echoContent green " ---> Installing WARP"
    ${installType} cloudflare-warp >/dev/null 2>&1
    if [[ -z $(which warp-cli) ]]; then
        echoContent red " ---> Installing WARPFailed"
        exit 0
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
        echoContent green " ---> WARPStarted successfully"
    fi
}

# passdns检checkdomain的IP
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
        echoContent red " ---> cannotpassDNSGetdomain IPv4 address"
        echoContent green " ---> try检checkdomain IPv6 address"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if echo "${dnsIP}" | grep -q "network unreachable" || [[ -z "${dnsIP}" ]]; then
            echoContent red " ---> Cannot get domain IPv6 address via DNS, exiting installation"
            exit 0
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        echoContent red " ---> Domain DNS IP does not match current server IP\n"
        echoContent yellow " ---> invite检checkdomainunlock析yesno生效with及correct"
        echoContent green " ---> currentVPS IP：${publicIP}"
        echoContent green " ---> DNS resolved IP：${dnsIP}"
        exit 0
    else
        echoContent green " ---> Domain IP verification passed"
    fi
}
# 检checkport实际openputstatus
checkPortOpen() {
    handleSingBox stop >/dev/null 2>&1
    handleXray stop >/dev/null 2>&1

    local port=$1
    local domain=$2
    local checkPortOpenResult=
    allowPort "${port}"

    if [[ -z "${btDomain}" ]]; then

        handleNginx stop
        # 初始化nginxConfigure
        touch ${nginxConfigPath}checkPortOpen.conf
        local listenIPv6PortConfig=

        if [[ -n $(curl -s -6 -m 4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2) ]]; then
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
        # 检checkdomain+port的openput
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        rm "${nginxConfigPath}checkPortOpen.conf"
        handleNginx stop
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            echoContent green " ---> Detectto${port}port已openput"
        else
            echoContent green " ---> 未Detectto${port}portopenput，ExitInstall"
            if echo "${checkPortOpenResult}" | grep -q "cloudflare"; then
                echoContent yellow " ---> invitedisable云朵back等待三divide钟heavynewtry"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    echoContent red " ---> Please check for web firewalls, such as Oracle Cloud"
                    echoContent red " ---> 检checkyesno自己Installpastnginx并且haveConfigure冲突，maywithtryDD纯净systembackheavynewtry"
                else
                    echoContent red " ---> Errorlog：${checkPortOpenResult}，invitewill此Errorlogpassissueslift交reverse馈"
                fi
            fi
            exit 0
        fi
        checkIP "${localIP}"
    fi
}

# Initializing Nginx certificate application configuration
initTLSNginxConfig() {
    handleNginx stop
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Initializing Nginx certificate application configuration"
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "Previous installation record found. Use the domain from last installation? ？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" == "y" ]]; then
            domain=${currentHost}
            echoContent yellow "\n ---> domain: ${domain}"
        else
            echo
            echoContent yellow "Please enter the domain to configure 例: example.com --->"
            read -r -p "domain:" domain
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        echoContent yellow "Please enter the domain to configure 例: example.com --->"
        read -r -p "domain:" domain
    fi

    if [[ -z ${domain} ]]; then
        echoContent red "  domaincannot be empty--->"
        initTLSNginxConfig 3
    else
        dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
        if [[ "${selectCoreType}" == "1" ]]; then
            customPortFunction
        fi
        # ModifyConfigure
        handleNginx stop
    fi
}

# Deletenginxdefault的Configure
removeNginxDefaultConf() {
    if [[ -f ${nginxConfigPath}default.conf ]]; then
        if [[ "$(grep -c "server_name" <${nginxConfigPath}default.conf)" == "1" ]] && [[ "$(grep -c "server_name  localhost;" <${nginxConfigPath}default.conf)" == "1" ]]; then
            echoContent green " ---> DeleteNginxdefaultConfigure"
            rm -rf ${nginxConfigPath}default.conf >/dev/null 2>&1
        fi
    fi
}
# ModifynginxheavydecidetowardConfigure
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

	client_header_timeout 1071906480m;
    keepalive_timeout 1071906480m;

    location /${currentPath}grpc {
    	if (\$content_type !~ "application/grpc") {
    		return 404;
    	}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location /${currentPath}trojangrpc {
		if (\$content_type !~ "application/grpc") {
            		return 404;
		}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31304;
	}
	location / {
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

	location /${currentPath}grpc {
		client_max_body_size 0;
		keepalive_requests 4294967296;
		client_body_timeout 1071906480m;
 		send_timeout 1071906480m;
 		lingering_close always;
 		grpc_read_timeout 1071906480m;
 		grpc_send_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}
	location / {
    }
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

	location /${currentPath}trojangrpc {
		client_max_body_size 0;
		# keepalive_time 1071906480m;
		keepalive_requests 4294967296;
		client_body_timeout 1071906480m;
 		send_timeout 1071906480m;
 		lingering_close always;
 		grpc_read_timeout 1071906480m;
 		grpc_send_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}
	location / {
    }
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

	location / {
	}
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
	location / {
	}
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
    singBoxNginxSSL="ssl_certificate /etc/v2ray-agent/tls/${domain}.crt;ssl_certificate_key /etc/v2ray-agent/tls/${domain}.key;"

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

# 检checkip
checkIP() {
    echoContent skyBlue "\n ---> 检checkdomainipmiddle"
    local localIP=$1

    if [[ -z ${localIP} ]] || ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q '\.' && ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q ':'; then
        echoContent red "\n ---> 未Detecttocurrentdomain的ip"
        echoContent skyBlue " ---> invitedependtimeenterlinedownlist检check"
        echoContent yellow " --->  1.检checkdomainyesno书writecorrect"
        echoContent yellow " --->  2.检checkdomaindnsunlock析yesnocorrect"
        echoContent yellow " --->  3.如unlock析correct，invite等待dns生效，预计三divide钟inside生效"
        echoContent yellow " --->  4.如报NginxStartask题，invite手moveStartnginxViewError，如自己cannot处arrangeinviteliftissues"
        echo
        echoContent skyBlue " ---> 如aboveSet都correct，inviteheavynewInstall纯净systemback再timetry"

        if [[ -n ${localIP} ]]; then
            echoContent yellow " ---> Detect返returnvalueabnormal，recommended手moveUninstallnginxbackheavynew执linescript"
            echoContent red " ---> abnormal结果：${localIP}"
        fi
        exit 0
    else
        if echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q "." || echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q ":"; then
            echoContent red "\n ---> Detecttomany个ip，Please confirmyesnodisablecloudflare的云朵"
            echoContent yellow " ---> disable云朵back等待三divide钟backretry"
            echoContent yellow " ---> Detectto的ip如down:[${localIP}]"
            exit 0
        fi
        echoContent green " ---> 检checkcurrentdomainIPcorrect"
    fi
}
# customemail
customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "yesnoheavynewInput邮箱address[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "Please enter邮箱address:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
                echoContent green " ---> Addfinished"
            else
                echoContent yellow "please re-entercorrect的邮箱格style[例: username@example.com]"
                customSSLEmail
            fi
        fi
    fi

}
# DNS APIApplying for certificate
switchDNSAPI() {
    read -r -p "yesnomakeuseDNS APIApplying for certificate[supportNAT]？[y/n]:" dnsAPIStatus
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.cloudflare[default]"
        echoContent yellow "2.aliyun"
        echoContent red "=============================================================="
        read -r -p "Please select[return车]makeusedefault:" selectDNSAPIType
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
# 初始化dnsConfigure
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        echoContent yellow "\n inviteat Cloudflare 控制台as DNS weave辑权limitCreate API Token 并fill入 CF_Token/CF_Account_ID。\n"
        read -r -p "Please enterAPI Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            echoContent red " ---> Inputasempty，please re-enter"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> not supported此domain申invitethrough配符certificate，recommendedmakeuse此格style[xx.xx.xx]"
                exit 0
            fi
            read -r -p "yesnomakeuse*.${dnsTLSDomain}enterlineAPI申invitethrough配符certificate？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        read -r -p "Please enterAli Key:" aliKey
        read -r -p "Please enterAli Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            echoContent red " ---> Inputasempty，please re-enter"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> not supported此domain申invitethrough配符certificate，recommendedmakeuse此格style[xx.xx.xx]"
                exit 0
            fi
            read -r -p "yesnomakeuse*.${dnsTLSDomain}enterlineAPI申invitethrough配符certificate？[y/n]:" dnsAPIStatus
        fi
    fi
}
# SelectsslInstalltypemodel
switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.letsencrypt[default]"
        echoContent yellow "2.zerossl"
        echoContent yellow "3.buypass[not supportedDNS申invite]"
        echoContent red "=============================================================="
        read -r -p "Please select[return车]makeusedefault:" selectSSLType
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
            echoContent red " ---> buypassnot supportedAPIApplying for certificate"
            exit 0
        fi
        echo "${sslType}" >/etc/v2ray-agent/tls/ssl_type
    fi
}

# SelectacmeInstallcertificatesquarestyle
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

# InstallSSLcertificate
acmeInstallSSL() {
    local dnsAPIDomain="${tlsDomain}"
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType}" == "cloudflare" ]]; then
        echoContent green " ---> DNS API Generatecertificatemiddle"
        sudo CF_Token="${cfAPIToken}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
    elif [[ "${dnsAPIType}" == "aliyun" ]]; then
        echoContent green " --->  DNS API Generatecertificatemiddle"
        sudo Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_ali -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
    else
        echoContent green " ---> Generatecertificatemiddle"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/v2ray-agent/tls/acme.log >/dev/null
    fi
}
# customport
customPortFunction() {
    local historyCustomPortStatus=
    if [[ -n "${customPort}" || -n "${currentPort}" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "ReadtouptimeInstall时的port，yesnomakeuseuptimeInstall时的port？[y/n]:" historyCustomPortStatus
            if [[ "${historyCustomPortStatus}" == "y" ]]; then
                port=${currentPort}
                echoContent yellow "\n ---> port: ${port}"
            fi
        elif [[ -n "${lastInstallationConfig}" ]]; then
            port=${currentPort}
        fi
    fi
    if [[ -z "${currentPort}" ]] || [[ "${historyCustomPortStatus}" == "n" ]]; then
        echo

        if [[ -n "${btDomain}" ]]; then
            echoContent yellow "Please enterport[不maywithBT Panel/1Panelportsame，return车random]"
            read -r -p "port:" port
            if [[ -z "${port}" ]]; then
                port=$((RANDOM % 20001 + 10000))
            fi
        else
            echo
            echoContent yellow "Please enterport[default: 443]，maycustomport[return车makeusedefault]"
            read -r -p "port:" port
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
                echoContent yellow "\n ---> port: ${port}"
                if [[ -z "${btDomain}" ]]; then
                    checkDNSIP "${domain}"
                    removeNginxDefaultConf
                    checkPortOpen "${port}" "${domain}"
                fi
            else
                echoContent red " ---> portInputError"
                exit 0
            fi
        else
            echoContent red " ---> portcannot be empty"
            exit 0
        fi
    fi
}

# Detectportyesno占use
checkPort() {
    if [[ -n "$1" ]] && lsof -i "tcp:$1" | grep -q LISTEN; then
        echoContent red "\n ---> $1portby占use，invite手movedisablebackInstall\n"
        lsof -i "tcp:$1" | grep LISTEN
        exit 0
    fi
}

# InstallTLS
installTLS() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Applying for TLS certificate\n"
    readAcmeTLS
    local tlsDomain=${domain}

    # Installtls
    if [[ -f "/etc/v2ray-agent/tls/${tlsDomain}.crt" && -f "/etc/v2ray-agent/tls/${tlsDomain}.key" && -n $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        echoContent green " ---> Detecttocertificate"
        renewalTLS

        if [[ -z $(find /etc/v2ray-agent/tls/ -name "${tlsDomain}.crt") ]] || [[ -z $(find /etc/v2ray-agent/tls/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus}" == "true" ]]; then
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            else
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    echoContent yellow " ---> 如未expiredor者customcertificatePlease select[n]\n"
                    read -r -p "yesnoheavynewInstall？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        rm -rf /etc/v2ray-agent/tls/*
                        installTLS "$1"
                    fi
                fi
            fi
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI
        if [[ -z "${dnsAPIType}" ]]; then
            echoContent yellow "\n ---> 不采useAPIApplying for certificate"
            echoContent green " ---> InstallTLScertificate，needdependency80port"
            allowPort 80
        fi

        switchSSLType
        customSSLEmail
        selectAcmeInstallSSL

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        else
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/v2ray-agent/tls/${tlsDomain}.crt" --keypath "/etc/v2ray-agent/tls/${tlsDomain}.key" --ecc >/dev/null
        fi

        if [[ ! -f "/etc/v2ray-agent/tls/${tlsDomain}.crt" || ! -f "/etc/v2ray-agent/tls/${tlsDomain}.key" ]] || [[ -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.key") || -z $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]]; then
            tail -n 10 /etc/v2ray-agent/tls/acme.log
            if [[ ${installTLSCount} == "1" ]]; then
                echoContent red " ---> TLSInstallation failed，invite检checkacmelog"
                exit 0
            fi

            installTLSCount=1
            echo

            if tail -n 10 /etc/v2ray-agent/tls/acme.log | grep -q "Could not validate email address as valid"; then
                echoContent red " ---> 邮箱cannotpassSSL厂商Verify，please re-enter"
                echo
                customSSLEmail "validate email"
                installTLS "$1"
            else
                installTLS "$1"
            fi
        fi

        echoContent green " ---> TLSGenerateSuccess"
    else
        echoContent yellow " ---> 未Installing acme.sh"
        exit 0
    fi
}

# 初始化randomcharacter符串
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..4}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    customPath=${initCustomPath}
}

# custom/randompath
randomPathFunction() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\nProgress  $1/${totalProgress} : Generaterandompath"
    else
        echoContent skyBlue "Generaterandompath"
    fi

    if [[ -n "${currentPath}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "ReadtouptimeInstallremember录，yesnomakeuseuptimeInstall时的pathpath ？[y/n]:" historyPathStatus
        echo
    elif [[ -n "${currentPath}" && -n "${lastInstallationConfig}" ]]; then
        historyPathStatus="y"
    fi

    if [[ "${historyPathStatus}" == "y" ]]; then
        customPath=${currentPath}
        echoContent green " ---> makeuseSuccess\n"
    else
        echoContent yellow "Please entercustompath[例: alone]，不needdiagonal杠，[return车]randompath"
        read -r -p 'path:' customPath
        if [[ -z "${customPath}" ]]; then
            initRandomPath
            currentPath=${customPath}
        else
            if [[ "${customPath: -2}" == "ws" ]]; then
                echo
                echoContent red " ---> custompathendunavailablewsend，no则cannot区divideroutingpath"
                randomPathFunction "$1"
            else
                currentPath=${customPath}
            fi
        fi
    fi
    echoContent yellow "\n path:${currentPath}"
    echoContent skyBlue "\n----------------------------"
}
# randomcount
randomNum() {
    if [[ "${release}" == "alpine" ]]; then
        local ranNum=
        ranNum="$(shuf -i "$1"-"$2" -n 1)"
        echo "${ranNum}"
    else
        echo $((RANDOM % $2 + $1))
    fi
}
# Nginxcamouflage博客
nginxBlog() {
    if [[ -n "$1" ]]; then
        echoContent skyBlue "\nProgress $1/${totalProgress} : Addcamouflagestandclick"
    else
        echoContent yellow "\nStartAddcamouflagestandclick"
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "DetecttoInstallcamouflagestandclick，yesnoneedheavynewInstall[y/n]:" nginxBlogInstallStatus
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
            echoContent green " ---> AddcamouflagestandclickSuccess"
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
        echoContent green " ---> AddcamouflagestandclickSuccess"
    fi

}

# Modifyhttp_port_tport
updateSELinuxHTTPPortT() {

    $(find /usr/bin /usr/sbin | grep -w journalctl) -xe >/etc/v2ray-agent/nginx_error.log 2>&1

    if find /usr/bin /usr/sbin | grep -q -w semanage && find /usr/bin /usr/sbin | grep -q -w getenforce && grep -E "31300|31302" </etc/v2ray-agent/nginx_error.log | grep -q "Permission denied"; then
        echoContent red " ---> 检checkSELinuxportyesnoopenput"
        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31300; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31300
            echoContent green " ---> http_port_t 31300 Port opened successfully"
        fi

        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31302; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31302
            echoContent green " ---> http_port_t 31302 Port opened successfully"
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
            rc-service nginx start 2>/etc/v2ray-agent/nginx_error.log
        else
            systemctl start nginx 2>/etc/v2ray-agent/nginx_error.log
        fi

        sleep 0.5

        if [[ -z $(pgrep -f "nginx") ]]; then
            echoContent red " ---> NginxStartFailed"
            echoContent red " ---> invitewillbelowlogreverse馈giveopensend者"
            nginx
            if grep -q "journalctl -xe" </etc/v2ray-agent/nginx_error.log; then
                updateSELinuxHTTPPortT
            fi
        else
            echoContent green " ---> NginxStarted successfully"
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
        echoContent green " ---> NginxdisableSuccess"
    fi
}

# scheduled tasksUpdatetlscertificate
installCronTLS() {
    if [[ -z "${btDomain}" ]]; then
        echoContent skyBlue "\nProgress $1/${totalProgress} : Adddecide时维guardcertificate"
        crontab -l >/etc/v2ray-agent/backup_crontab.cron
        local historyCrontab
        historyCrontab=$(sed '/v2ray-agent/d;/acme.sh/d' /etc/v2ray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/v2ray-agent/backup_crontab.cron
        echo "30 1 * * * /bin/bash /etc/v2ray-agent/install.sh RenewTLS >> /etc/v2ray-agent/crontab_tls.log 2>&1" >>/etc/v2ray-agent/backup_crontab.cron
        crontab /etc/v2ray-agent/backup_crontab.cron
        echoContent green "\n ---> Adddecide时维guardcertificateSuccess"
    fi
}
# scheduled tasksUpdategeofile
installCronUpdateGeo() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if crontab -l | grep -q "UpdateGeo"; then
            echoContent red "\n ---> 已Addauto updatescheduled tasks，invite不wantheavy复Add"
            exit 0
        fi
        echoContent skyBlue "\nProgress 1/1 : Adddecide时Updategeofile"
        crontab -l >/etc/v2ray-agent/backup_crontab.cron
        echo "35 1 * * * /bin/bash /etc/v2ray-agent/install.sh UpdateGeo >> /etc/v2ray-agent/crontab_tls.log 2>&1" >>/etc/v2ray-agent/backup_crontab.cron
        crontab /etc/v2ray-agent/backup_crontab.cron
        echoContent green "\n ---> Adddecide时UpdategeofileSuccess"
    fi
}

# Updatecertificate
renewalTLS() {

    if [[ -n $1 ]]; then
        echoContent skyBlue "\nProgress  $1/1 : Updatecertificate"
    fi
    readAcmeTLS
    local domain=${currentHost}
    if [[ -z "${currentHost}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi

    if [[ -f "/etc/v2ray-agent/tls/ssl_type" ]]; then
        if grep -q "buypass" <"/etc/v2ray-agent/tls/ssl_type"; then
            sslRenewalDays=180
        fi
    fi
    if [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        modifyTime=

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            modifyTime=$(stat --format=%z "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer")
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
            tlsStatus="已expired"
        fi

        echoContent skyBlue " ---> certificate检check日period:$(date "+%F %H:%M:%S")"
        echoContent skyBlue " ---> certificateGenerate日period:$(date -d @"${modifyTime}" +"%F %H:%M:%S")"
        echoContent skyBlue " ---> certificateGenerate天count:${days}"
        echoContent skyBlue " ---> certificateremaining天count:"${tlsStatus}
        echoContent skyBlue " ---> certificateexpiredfrontlast一天auto update，如UpdateFailedinvite手moveUpdate"

        if [[ ${remainingDays} -le 1 ]]; then
            echoContent yellow " ---> heavynewGeneratecertificate"
            handleNginx stop

            if [[ "${coreInstallType}" == "1" ]]; then
                handleXray stop
            elif [[ "${coreInstallType}" == "2" ]]; then
                handleSingBox stop
            fi

            sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${domain}" --fullchainpath /etc/v2ray-agent/tls/"${domain}.crt" --keypath /etc/v2ray-agent/tls/"${domain}.key" --ecc
            reloadCore
            handleNginx start
        else
            echoContent green " ---> certificatevalid"
        fi
    elif [[ -f "/etc/v2ray-agent/tls/${tlsDomain}.crt" && -f "/etc/v2ray-agent/tls/${tlsDomain}.key" && -n $(cat "/etc/v2ray-agent/tls/${tlsDomain}.crt") ]]; then
        echoContent yellow " ---> Detecttomakeusecustomcertificate，cannot执linerenew操作。"
    else
        echoContent red " ---> Not installed"
    fi
}

# Install sing-box
installSingBox() {
    readInstallType
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Installing sing-box"

    if [[ ! -f "/etc/v2ray-agent/sing-box/sing-box" ]]; then

        version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        echoContent green " ---> latestversion:${version}"

        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P /etc/v2ray-agent/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"
        else
            wget -c -q "${wgetShowProgressStatus}" -P /etc/v2ray-agent/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"
        fi

        if [[ ! -f "/etc/v2ray-agent/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz" ]]; then
            read -r -p "coredownloadFailed，inviteheavynewtryInstall，yesnoheavynewtry？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installSingBox "$1"
            fi
        else

            tar zxvf "/etc/v2ray-agent/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz" -C "/etc/v2ray-agent/sing-box/" >/dev/null 2>&1

            mv "/etc/v2ray-agent/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}/sing-box" /etc/v2ray-agent/sing-box/sing-box
            rm -rf /etc/v2ray-agent/sing-box/sing-box-*
            chmod 655 /etc/v2ray-agent/sing-box/sing-box
        fi
    else
        echoContent green " ---> currentversion:v$(/etc/v2ray-agent/sing-box/sing-box version | grep "sing-box version" | awk '{print $3}')"

        version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        echoContent green " ---> latestversion:${version}"

        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "yesnoUpdate、Upgrade？[y/n]:" reInstallSingBoxStatus
            if [[ "${reInstallSingBoxStatus}" == "y" ]]; then
                rm -f /etc/v2ray-agent/sing-box/sing-box
                installSingBox "$1"
            fi
        fi
    fi

}

# 检checkwget showProgress
checkWgetShowProgress() {
    if [[ "${release}" != "alpine" ]]; then
        if find /usr/bin /usr/sbin | grep -q "/wget" && wget --help | grep -q show-progress; then
            wgetShowProgressStatus="--show-progress"
        fi
    fi
}
# Installxray
installXray() {
    readInstallType
    local prereleaseStatus=false
    if [[ "$2" == "true" ]]; then
        prereleaseStatus=true
    fi

    echoContent skyBlue "\nProgress  $1/${totalProgress} : Installing Xray"

    if [[ ! -f "/etc/v2ray-agent/xray/xray" ]]; then

        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        echoContent green " ---> Xray-coreversion:${version}"
        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -q "${wgetShowProgressStatus}" -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        fi

        if [[ ! -f "/etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip" ]]; then
            read -r -p "coredownloadFailed，inviteheavynewtryInstall，yesnoheavynewtry？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installXray "$1"
            fi
        else
            unzip -o "/etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/v2ray-agent/xray >/dev/null
            rm -rf "/etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip"

            version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1 | jq -r '.[]|.tag_name')
            echoContent skyBlue "------------------------Version-------------------------------"
            echo "version:${version}"
            rm /etc/v2ray-agent/xray/geo* >/dev/null 2>&1

            if [[ "${release}" == "alpine" ]]; then
                wget -c -q -P /etc/v2ray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
                wget -c -q -P /etc/v2ray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
            else
                wget -c -q "${wgetShowProgressStatus}" -P /etc/v2ray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
                wget -c -q "${wgetShowProgressStatus}" -P /etc/v2ray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
            fi

            chmod 655 /etc/v2ray-agent/xray/xray
        fi
    else
        if [[ -z "${lastInstallationConfig}" ]]; then
            echoContent green " ---> Xray-coreversion:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"
            read -r -p "yesnoUpdate、Upgrade？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                rm -f /etc/v2ray-agent/xray/xray
                installXray "$1" "$2"
            fi
        fi
    fi
}

# xrayversionmanagearrange
xrayVersionManageMenu() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Xrayversionmanagearrange"
    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 没haveDetecttoInstalldirectory，invite执linescriptInstallinside容"
        exit 0
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.UpgradeXray-core"
    echoContent yellow "2.UpgradeXray-core 预viewversion"
    echoContent yellow "3.return退Xray-core"
    echoContent yellow "4.disableXray-core"
    echoContent yellow "5.openXray-core"
    echoContent yellow "6.RestartXray-core"
    echoContent yellow "7.Updategeosite、geoip"
    echoContent yellow "8.Setauto updategeofile[每天凌晨Update]"
    echoContent yellow "9.Viewlog"
    echoContent red "=============================================================="
    read -r -p "Please select:" selectXrayType
    if [[ "${selectXrayType}" == "1" ]]; then
        prereleaseStatus=false
        updateXray
    elif [[ "${selectXrayType}" == "2" ]]; then
        prereleaseStatus=true
        updateXray
    elif [[ "${selectXrayType}" == "3" ]]; then
        echoContent yellow "\n1.只maywithreturn退recent的五个version"
        echoContent yellow "2.不protect证return退back一decidemaywithnormalmakeuse"
        echoContent yellow "3.如果return退的versionnot supportedcurrent的config，则knowcannotconnection，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==false)|.tag_name" | awk '{print ""NR""":"$0}'
        echoContent skyBlue "--------------------------------------------------------------"
        read -r -p "Please enterwantreturn退的version:" selectXrayVersionType
        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==false)|.tag_name" | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
        if [[ -n "${version}" ]]; then
            updateXray "${version}"
        else
            echoContent red "\n ---> Inputhave误，please re-enter"
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

# Update geosite
updateGeoSite() {
    echoContent yellow "\ncome源 https://github.com/Loyalsoldier/v2ray-rules-dat"

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
    echoContent green " ---> Updatefinished"

}

# UpdateXray
updateXray() {
    readInstallType

    if [[ -z "${coreInstallType}" || "${coreInstallType}" != "1" ]]; then
        if [[ -n "$1" ]]; then
            version=$1
        else
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        fi

        echoContent green " ---> Xray-coreversion:${version}"

        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -q "${wgetShowProgressStatus}" -P /etc/v2ray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        fi

        unzip -o "/etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/v2ray-agent/xray >/dev/null
        rm -rf "/etc/v2ray-agent/xray/${xrayCoreCPUVendor}.zip"
        chmod 655 /etc/v2ray-agent/xray/xray
        handleXray stop
        handleXray start
    else
        echoContent green " ---> currentversion:v$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"
        remoteVersion=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=5" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        echoContent green " ---> latestversion:${remoteVersion}"

        if [[ -n "$1" ]]; then
            version=$1
        else
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=10" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        fi

        if [[ -n "$1" ]]; then
            read -r -p "return退versionas${version}，Continue?？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" == "y" ]]; then
                echoContent green " ---> currentXray-coreversion:$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)"

                handleXray stop
                rm -f /etc/v2ray-agent/xray/xray
                updateXray "${version}"
            else
                echoContent green " ---> abandonreturn退version"
            fi
        elif [[ "${version}" == "v$(/etc/v2ray-agent/xray/xray --version | awk '{print $2}' | head -1)" ]]; then
            read -r -p "currentversionwithlatestversionsame，yesnoheavynewInstall？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                handleXray stop
                rm -f /etc/v2ray-agent/xray/xray
                updateXray
            else
                echoContent green " ---> abandonheavynewInstall"
            fi
        else
            read -r -p "latestversionas:${version}，yesnoUpdate？[y/n]:" installXrayStatus
            if [[ "${installXrayStatus}" == "y" ]]; then
                rm /etc/v2ray-agent/xray/xray
                updateXray
            else
                echoContent green " ---> abandonUpdate"
            fi

        fi
    fi
}

# Verifyorganize个serviceyesnoavailable
checkGFWStatue() {
    readInstallType
    echoContent skyBlue "\nProgress $1/${totalProgress} : VerifyserviceStartstatus"
    if [[ "${coreInstallType}" == "1" ]] && [[ -n $(pgrep -f "xray/xray") ]]; then
        echoContent green " ---> serviceStarted successfully"
    elif [[ "${coreInstallType}" == "2" ]] && [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
        echoContent green " ---> serviceStarted successfully"
    else
        echoContent red " ---> serviceStartFailed，invite检check终端yesnohaveloghitprint"
        exit 0
    fi
}

# Installalpineboot startup
installAlpineStartup() {
    local serviceName=$1
    if [[ "${serviceName}" == "sing-box" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="sing-box service"
command="/etc/v2ray-agent/sing-box/sing-box"
command_args="run -c /etc/v2ray-agent/sing-box/conf/config.json"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF
    elif [[ "${serviceName}" == "xray" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="xray service"
command="/etc/v2ray-agent/xray/xray"
command_args="run -confdir /etc/v2ray-agent/xray/conf"
command_background=true
pidfile="/var/run/xray.pid"
EOF
    fi

    chmod +x "/etc/init.d/${serviceName}"
}

# sing-boxauto-start on boot
installSingBoxService() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Configuring sing-boxauto-start on boot"
    execStart='/etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json'

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

    echoContent green " ---> Configuring sing-boxboot startupfinished"
}

# Xrayauto-start on boot
installXrayService() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Configuring Xrayauto-start on boot"
    execStart='/etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf'
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
        echoContent green " ---> Configuring Xrayauto-start on bootSuccess"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "xray"
        bootStartup "xray"
    fi
}

# 操作Hysteria
handleHysteria() {
    # shellcheck disable=SC2010
    if find /bin /usr/bin | grep -q systemctl && ls /etc/systemd/system/ | grep -q hysteria.service; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "start" ]]; then
            systemctl start hysteria.service
        elif [[ -n $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop hysteria.service
        fi
    fi
    sleep 0.8

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "hysteria/hysteria") ]]; then
            echoContent green " ---> HysteriaStarted successfully"
        else
            echoContent red "HysteriaStartFailed"
            echoContent red "invite手move执line【/etc/v2ray-agent/hysteria/hysteria --log-level debug -c /etc/v2ray-agent/hysteria/conf/config.json server】，ViewErrorlog"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]]; then
            echoContent green " ---> HysteriadisableSuccess"
        else
            echoContent red "HysteriadisableFailed"
            echoContent red "invite手move执line【ps -ef|grep -v grep|grep hysteria|awk '{print \$2}'|xargs kill -9】"
            exit 0
        fi
    fi
}

# 操作sing-box
handleSingBox() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        if [[ -z $(pgrep -f "sing-box") ]] && [[ "$1" == "start" ]]; then
            singBoxMergeConfig
            systemctl start sing-box.service
        elif [[ -n $(pgrep -f "sing-box") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop sing-box.service
        fi
    elif [[ -f "/etc/init.d/sing-box" ]]; then
        if [[ -z $(pgrep -f "sing-box") ]] && [[ "$1" == "start" ]]; then
            singBoxMergeConfig
            rc-service sing-box start
        elif [[ -n $(pgrep -f "sing-box") ]] && [[ "$1" == "stop" ]]; then
            rc-service sing-box stop
        fi
    fi
    sleep 1

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "sing-box") ]]; then
            echoContent green " ---> sing-boxStarted successfully"
        else
            echoContent red "sing-boxStartFailed"
            echoContent yellow "invite手move执line【 /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ 】，ViewErrorlog"
            echo
            echoContent yellow "如upsurface命令没haveError，invite手move执line【 /etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json 】，ViewErrorlog"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "sing-box") ]]; then
            echoContent green " ---> sing-boxdisableSuccess"
        else
            echoContent red " ---> sing-boxdisableFailed"
            echoContent red "invite手move执line【ps -ef|grep -v grep|grep sing-box|awk '{print \$2}'|xargs kill -9】"
            exit 0
        fi
    fi
}

# 操作xray
handleXray() {
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            systemctl start xray.service
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -f "/etc/init.d/xray" ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            rc-service xray start
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            rc-service xray stop
        fi
    fi

    sleep 0.8

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "xray/xray") ]]; then
            echoContent green " ---> XrayStarted successfully"
        else
            echoContent red "XrayStartFailed"
            echoContent red "invite手move执linebelow的命令back【/etc/v2ray-agent/xray/xray -confdir /etc/v2ray-agent/xray/conf】willErrorlogenterlinereverse馈"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]]; then
            echoContent green " ---> XraydisableSuccess"
        else
            echoContent red "xraydisableFailed"
            echoContent red "invite手move执line【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
            exit 0
        fi
    fi
}

# ReadXrayusercount据并初始化
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
# Readsingboxusercount据并初始化
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
            # makeuseUUID的front16charactersaveenterlinebase64weave码作asuserkey
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

# 初始化hysteriaport
initHysteriaPort() {
    readSingBoxConfig
    if [[ -n "${hysteriaPort}" ]]; then
        read -r -p "ReadtouptimeInstall时的port，yesnomakeuseuptimeInstall时的port？[y/n]:" historyHysteriaPortStatus
        if [[ "${historyHysteriaPortStatus}" == "y" ]]; then
            echoContent yellow "\n ---> port: ${hysteriaPort}"
        else
            hysteriaPort=
        fi
    fi

    if [[ -z "${hysteriaPort}" ]]; then
        echoContent yellow "Please enterHysteriaport[return车random10000-30000]，不maywithotherserviceheavy复"
        read -r -p "port:" hysteriaPort
        if [[ -z "${hysteriaPort}" ]]; then
            hysteriaPort=$((RANDOM % 20001 + 10000))
        fi
    fi
    if [[ -z ${hysteriaPort} ]]; then
        echoContent red " ---> portcannot be empty"
        initHysteriaPort "$2"
    elif ((hysteriaPort < 1 || hysteriaPort > 65535)); then
        echoContent red " ---> port不valid"
        initHysteriaPort "$2"
    fi
    allowPort "${hysteriaPort}"
    allowPort "${hysteriaPort}" "udp"
}

# 初始化hysterianetwork信息
initHysteria2Network() {

    echoContent yellow "Please enterlocalbringwide峰value的downline速degree（default：100，单位：Mbps）"
    read -r -p "downline速degree:" hysteria2ClientDownloadSpeed
    if [[ -z "${hysteria2ClientDownloadSpeed}" ]]; then
        hysteria2ClientDownloadSpeed=100
        echoContent green "\n ---> downline速degree: ${hysteria2ClientDownloadSpeed}\n"
    fi

    echoContent yellow "Please enterlocalbringwide峰value的upline速degree（default：50，单位：Mbps）"
    read -r -p "upline速degree:" hysteria2ClientUploadSpeed
    if [[ -z "${hysteria2ClientUploadSpeed}" ]]; then
        hysteria2ClientUploadSpeed=50
        echoContent green "\n ---> upline速degree: ${hysteria2ClientUploadSpeed}\n"
    fi

    echoContent yellow "yesno启useobfuscation(obfs)? keepempty不启use，Inputpassword则启usesalamanderobfuscation"
    read -r -p "obfuscationpassword(keepempty不启use):" hysteria2ObfsPassword
    if [[ -n "${hysteria2ObfsPassword}" ]]; then
        echoContent green "\n ---> obfuscationEnabled\n"
    else
        echoContent green "\n ---> obfuscationNot enabled\n"
    fi
}

# 初始化 Shadowsocks 2022 Configure
initSS2022Config() {
    # Read现haveConfigure
    if [[ -f "${singBoxConfigPath}14_ss2022_inbounds.json" ]]; then
        ss2022Port=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}14_ss2022_inbounds.json")
        ss2022ServerKey=$(jq -r '.inbounds[0].password' "${singBoxConfigPath}14_ss2022_inbounds.json")
        ss2022Method=$(jq -r '.inbounds[0].method' "${singBoxConfigPath}14_ss2022_inbounds.json")
    fi

    if [[ -n "${ss2022Port}" ]]; then
        read -r -p "ReadtouptimeInstall时的port ${ss2022Port}，yesnomakeuse？[y/n]:" historySS2022PortStatus
        if [[ "${historySS2022PortStatus}" != "y" ]]; then
            ss2022Port=
            ss2022ServerKey=
        fi
    fi

    if [[ -z "${ss2022Port}" ]]; then
        echoContent yellow "Please enterShadowsocks 2022port[return车random10000-30000]"
        read -r -p "port:" ss2022Port
        if [[ -z "${ss2022Port}" ]]; then
            ss2022Port=$((RANDOM % 20001 + 10000))
        fi
        echoContent green "\n ---> port: ${ss2022Port}"
    fi

    # Selectencryptionsquarestyle
    if [[ -z "${ss2022Method}" ]]; then
        echoContent yellow "\nPlease selectencryptionsquarestyle:"
        echoContent yellow "1.2022-blake3-aes-128-gcm [recommended，key较short]"
        echoContent yellow "2.2022-blake3-aes-256-gcm"
        echoContent yellow "3.2022-blake3-chacha20-poly1305"
        read -r -p "Please select[default1]:" ss2022MethodChoice
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
        echoContent green "\n ---> encryptionsquarestyle: ${ss2022Method}"
    else
        if [[ "${ss2022Method}" == "2022-blake3-aes-128-gcm" ]]; then
            ss2022KeyLen=16
        else
            ss2022KeyLen=32
        fi
    fi

    # Generateservice器key
    if [[ -z "${ss2022ServerKey}" ]]; then
        ss2022ServerKey=$(openssl rand -base64 ${ss2022KeyLen})
        echoContent green " ---> service器key已自moveGenerate"
    fi
}

# firewalldSetport hopping
addFirewalldPortHopping() {

    local start=$1
    local end=$2
    local targetPort=$3
    for port in $(seq "$start" "$end"); do
        sudo firewall-cmd --permanent --add-forward-port=port="${port}":proto=udp:toport="${targetPort}"
    done
    sudo firewall-cmd --reload
}

# Port hopping
addPortHopping() {
    local type=$1
    local targetPort=$2
    if [[ -n "${portHoppingStart}" || -n "${portHoppingEnd}" ]]; then
        echoContent red " ---> 已Add不mayheavy复Add，mayDeletebackheavynewAdd"
        exit 0
    fi
    if [[ "${release}" == "centos" ]]; then
        if ! systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
            echoContent red " ---> 未Startfirewalldfirewall，cannotSetport hopping。"
            exit 0
        fi
    fi

    echoContent skyBlue "\nProgress 1/1 : port hopping"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项\n"
    echoContent yellow "仅supportHysteria2、Tuic"
    echoContent yellow "port hopping的up始位置as30000"
    echoContent yellow "port hopping的End位置as40000"
    echoContent yellow "maywithat30000-40000范围middleselect一section"
    echoContent yellow "recommended1000个leftright"
    echoContent yellow "focus意不wantandother的port hoppingSet范围一pattern，Setsameknow覆cover。"

    echoContent yellow "Please enterport hopping的范围，例如[30000-31000]"

    read -r -p "范围:" portHoppingRange
    if [[ -z "${portHoppingRange}" ]]; then
        echoContent red " ---> 范围cannot be empty"
        addPortHopping "${type}" "${targetPort}"
    elif echo "${portHoppingRange}" | grep -q "-"; then

        local portStart=
        local portEnd=
        portStart=$(echo "${portHoppingRange}" | awk -F '-' '{print $1}')
        portEnd=$(echo "${portHoppingRange}" | awk -F '-' '{print $2}')

        if [[ -z "${portStart}" || -z "${portEnd}" ]]; then
            echoContent red " ---> 范围不valid"
            addPortHopping "${type}" "${targetPort}"
        elif ((portStart < 30000 || portStart > 40000 || portEnd < 30000 || portEnd > 40000 || portEnd < portStart)); then
            echoContent red " ---> 范围不valid"
            addPortHopping "${type}" "${targetPort}"
        else
            echoContent green "\nport范围: ${portHoppingRange}\n"
            if [[ "${release}" == "centos" ]]; then
                sudo firewall-cmd --permanent --add-masquerade
                sudo firewall-cmd --reload
                addFirewalldPortHopping "${portStart}" "${portEnd}" "${targetPort}"
                if ! sudo firewall-cmd --list-forward-ports | grep -q "toport=${targetPort}"; then
                    echoContent red " ---> port hoppingAddFailed"
                    exit 0
                fi
            else
                iptables -t nat -A PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "mack-a_${type}_portHopping" -j DNAT --to-destination ":${targetPort}"
                sudo netfilter-persistent save
                if ! iptables-save | grep -q "mack-a_${type}_portHopping"; then
                    echoContent red " ---> port hoppingAddFailed"
                    exit 0
                fi
            fi
            allowPort "${portStart}:${portEnd}" udp
            echoContent green " ---> port hoppingAdded successfully"
        fi
    fi
}

# Readport hopping的Configure
readPortHopping() {
    local type=$1
    local targetPort=$2
    local portHoppingStart=
    local portHoppingEnd=

    if [[ "${release}" == "centos" ]]; then
        portHoppingStart=$(sudo firewall-cmd --list-forward-ports | grep "toport=${targetPort}" | head -1 | cut -d ":" -f 1 | cut -d "=" -f 2)
        portHoppingEnd=$(sudo firewall-cmd --list-forward-ports | grep "toport=${targetPort}" | tail -n 1 | cut -d ":" -f 1 | cut -d "=" -f 2)
    else
        if iptables-save | grep -q "mack-a_${type}_portHopping"; then
            local portHopping=
            portHopping=$(iptables-save | grep "mack-a_${type}_portHopping" | cut -d " " -f 8)

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
# Deleteport hoppingiptables规则
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
        iptables -t nat -L PREROUTING --line-numbers | grep "mack-a_${type}_portHopping" | awk '{print $1}' | while read -r line; do
            iptables -t nat -D PREROUTING 1
            sudo netfilter-persistent save
        done
    fi
}

# port hopping菜单
portHoppingMenu() {
    local type=$1
    # judgeseveriptablesyesnoexists
    if ! find /usr/bin /usr/sbin | grep -q -w iptables; then
        echoContent red " ---> cannot识别iptablestool，cannotmakeuseport hopping，ExitInstall"
        exit 0
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

    echoContent skyBlue "\nProgress 1/1 : port hopping"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Addport hopping"
    echoContent yellow "2.Deleteport hopping"
    echoContent yellow "3.Viewport hopping"
    read -r -p "Please select:" selectPortHoppingStatus
    if [[ "${selectPortHoppingStatus}" == "1" ]]; then
        addPortHopping "${type}" "${targetPort}"
    elif [[ "${selectPortHoppingStatus}" == "2" ]]; then
        deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${targetPort}"
        echoContent green " ---> Deleted successfully"
    elif [[ "${selectPortHoppingStatus}" == "3" ]]; then
        if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
            echoContent green " ---> currentport hopping范围as: ${portHoppingStart}-${portHoppingEnd}"
        else
            echoContent yellow " ---> 未Setport hopping"
        fi
    else
        portHoppingMenu
    fi
}

# 初始化tuicport
initTuicPort() {
    readSingBoxConfig
    if [[ -n "${tuicPort}" ]]; then
        read -r -p "ReadtouptimeInstall时的port，yesnomakeuseuptimeInstall时的port？[y/n]:" historyTuicPortStatus
        if [[ "${historyTuicPortStatus}" == "y" ]]; then
            echoContent yellow "\n ---> port: ${tuicPort}"
        else
            tuicPort=
        fi
    fi

    if [[ -z "${tuicPort}" ]]; then
        echoContent yellow "Please enterTuicport[return车random10000-30000]，不maywithotherserviceheavy复"
        read -r -p "port:" tuicPort
        if [[ -z "${tuicPort}" ]]; then
            tuicPort=$((RANDOM % 20001 + 10000))
        fi
    fi
    if [[ -z ${tuicPort} ]]; then
        echoContent red " ---> portcannot be empty"
        initTuicPort "$2"
    elif ((tuicPort < 1 || tuicPort > 65535)); then
        echoContent red " ---> port不valid"
        initTuicPort "$2"
    fi
    echoContent green "\n ---> port: ${tuicPort}"
    allowPort "${tuicPort}"
    allowPort "${tuicPort}" "udp"
}

# 初始化tuic的protocol
initTuicProtocol() {
    if [[ -n "${tuicAlgorithm}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "Readtouptimemakeuse的calculate法，yesnomakeuse ？[y/n]:" historyTuicAlgorithm
        if [[ "${historyTuicAlgorithm}" != "y" ]]; then
            tuicAlgorithm=
        else
            echoContent yellow "\n ---> calculate法: ${tuicAlgorithm}\n"
        fi
    elif [[ -n "${tuicAlgorithm}" && -n "${lastInstallationConfig}" ]]; then
        echoContent yellow "\n ---> calculate法: ${tuicAlgorithm}\n"
    fi

    if [[ -z "${tuicAlgorithm}" ]]; then

        echoContent skyBlue "\nPlease selectcalculate法typemodel"
        echoContent red "=============================================================="
        echoContent yellow "1.bbr(default)"
        echoContent yellow "2.cubic"
        echoContent yellow "3.new_reno"
        echoContent red "=============================================================="
        read -r -p "Please select:" selectTuicAlgorithm
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
        echoContent yellow "\n ---> calculate法: ${tuicAlgorithm}\n"
    fi
}

# 初始化singbox routeConfigure
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
# downloadsing-box geosite db
downloadSingBoxGeositeDB() {
    if [[ ! -f "${singBoxConfigPath}geosite.db" ]]; then
        if [[ "${release}" == "alpine" ]]; then
            wget -q -P "${singBoxConfigPath}" https://github.com/Johnshall/sing-geosite/releases/latest/download/geosite.db
        else
            wget -q "${wgetShowProgressStatus}" -P "${singBoxConfigPath}" https://github.com/Johnshall/sing-geosite/releases/latest/download/geosite.db
        fi

    fi
}

# Addsing-box路by规则
addSingBoxRouteRule() {
    local outboundTag=$1
    # domainlist表
    local domainList=$2
    # 路byfile名称
    local routingName=$3
    # ReaduptimeInstallinside容
    if [[ -f "${singBoxConfigPath}${routingName}.json" ]]; then
        read -r -p "Readtouptime的Configure，yesnoprotectkeep ？[y/n]:" historyRouteStatus
        if [[ "${historyRouteStatus}" == "y" ]]; then
            domainList="${domainList},$(jq -rc .route.rules[0].rule_set[] "${singBoxConfigPath}${routingName}.json" | awk -F "[_]" '{print $1}' | paste -sd ',')"
            domainList="${domainList},$(jq -rc .route.rules[0].domain_regex[] "${singBoxConfigPath}${routingName}.json" | awk -F "[*]" '{print $2}' | paste -sd ',' | sed 's/\\//g')"
        fi
    fi
    local rules=
    rules=$(initSingBoxRules "${domainList}" "${routingName}")
    # domain精确match规则
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    # ruleSet规则collect
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

# Addsing-boxoutbound
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

# AddXray-core outbound
addXrayOutbound() {
    local tag=$1
    local domainStrategy=

    if echo "${tag}" | grep -q "IPv4"; then
        domainStrategy="ForceIPv4"
    elif echo "${tag}" | grep -q "IPv6"; then
        domainStrategy="ForceIPv6"
    fi

    if [[ -n "${domainStrategy}" ]]; then
        cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
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
        cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
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
        cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
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
    # socks5 outbound（Xray use，lift供giverouting规则unify一pointtoward的upstream SOCKS outbound）
    if echo "${tag}" | grep -q "socks5"; then
        socks5RoutingOutboundIP=$(stripAnsi "${socks5RoutingOutboundIP}")
        socks5RoutingOutboundPort=$(stripAnsi "${socks5RoutingOutboundPort}")
        socks5RoutingOutboundUserName=$(stripAnsi "${socks5RoutingOutboundUserName}")
        socks5RoutingOutboundPassword=$(stripAnsi "${socks5RoutingOutboundPassword}")
        if [[ -z "${socks5RoutingOutboundAuthType}" ]]; then
            socks5RoutingOutboundAuthType="password"
        fi
        local socks5OutboundUserValue=${socks5RoutingOutboundUserName}
        local socks5OutboundPassValue=${socks5RoutingOutboundPassword}
        if [[ "${socks5RoutingOutboundAuthType}" == "unified" ]]; then
            socks5OutboundUserValue=${socks5RoutingOutboundUnifiedKey}
            socks5OutboundPassValue=${socks5RoutingOutboundUnifiedKey}
        fi
        socks5OutboundUserValue=$(stripAnsi "${socks5OutboundUserValue}")
        socks5OutboundPassValue=$(stripAnsi "${socks5OutboundPassValue}")
        socks5RoutingProxyTag=$(stripAnsi "${socks5RoutingProxyTag}")

        local socks5OutboundJson
        socks5OutboundJson=$(jq -n \
            --arg tag "${tag}" \
            --arg auth "${socks5RoutingOutboundAuthType}" \
            --arg address "${socks5RoutingOutboundIP}" \
            --arg port "${socks5RoutingOutboundPort}" \
            --arg user "${socks5OutboundUserValue}" \
            --arg pass "${socks5OutboundPassValue}" '
            {
              outbounds: [
                {
                  protocol: "socks",
                  tag: $tag,
                  settings: {
                    auth: $auth,
                    servers: [
                      {
                        address: $address,
                        port: ($port|tonumber),
                        users: [ {user: $user, pass: $pass} ]
                      }
                    ]
                  }
                }
              ]
            }
        ')

        if [[ -n "${socks5RoutingProxyTag}" ]]; then
            socks5OutboundJson=$(echo "${socks5OutboundJson}" | jq --arg proxyTag "${socks5RoutingProxyTag}" '.outbounds[0].proxySettings = {tag:$proxyTag,transportLayer:true}')
        fi

        if [[ -n "${socks5TransportType}" && "${socks5TransportType}" != "1" ]]; then
            local socks5XrayNetwork="tcp"
            if [[ "${socks5TransportType}" == "3" ]]; then
                socks5XrayNetwork="ws"
            elif [[ "${socks5TransportType}" == "4" ]]; then
                socks5XrayNetwork="http"
            fi

            socks5OutboundJson=$(echo "${socks5OutboundJson}" | jq \
                --arg network "${socks5XrayNetwork}" \
                --arg serverName "${socks5TransportServerName}" \
                --argjson alpn "${socks5TransportAlpnJson:-[]}" \
                --argjson insecure "${socks5TransportInsecure:-false}" '
                .outbounds[0].streamSettings = {
                  network: $network,
                  security: "tls",
                  tlsSettings: {
                    serverName: $serverName,
                    alpn: $alpn,
                    allowInsecure: $insecure
                  }
                }
            ')

            if [[ "${socks5TransportType}" == "3" ]]; then
                socks5OutboundJson=$(echo "${socks5OutboundJson}" | jq \
                    --arg path "${socks5TransportPath}" \
                    --arg host "${socks5TransportHost}" '.outbounds[0].streamSettings.wsSettings = {path:$path,headers:{Host:$host}}')
            elif [[ "${socks5TransportType}" == "4" ]]; then
                socks5OutboundJson=$(echo "${socks5OutboundJson}" | jq \
                    --arg path "${socks5TransportPath}" \
                    --argjson hostList "${socks5TransportHostList:-[]}" '.outbounds[0].streamSettings.httpSettings = {path:$path,host:$hostList}')
            fi
        fi

        local socks5XrayOutboundPath="/etc/v2ray-agent/xray/conf/${tag}.json"
        echo "${socks5OutboundJson}" | jq . >"${socks5XrayOutboundPath}"
        validateJsonFile "${socks5XrayOutboundPath}"
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv4"; then
        cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
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
        cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
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
        cat <<EOF >"/etc/v2ray-agent/xray/conf/${tag}.json"
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

# Delete Xray-coreoutbound
removeXrayOutbound() {
    local tag=$1
    if [[ -f "/etc/v2ray-agent/xray/conf/${tag}.json" ]]; then
        rm "/etc/v2ray-agent/xray/conf/${tag}.json" >/dev/null 2>&1
    fi
}
# 移除sing-boxConfigure
removeSingBoxConfig() {

    local tag=$1
    if [[ -f "${singBoxConfigPath}${tag}.json" ]]; then
        rm "${singBoxConfigPath}${tag}.json"
    fi
}

# 初始化wireguardoutbound信息
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

# 初始化 sing-box Hysteria2 Configure
initSingBoxHysteria2Config() {
    echoContent skyBlue "\nProgress $1/${totalProgress} : 初始化Hysteria2Configure"

    initHysteriaPort
    initHysteria2Network

    # 构buildobfsConfigure（如果启use）
    local hysteria2ObfsConfig=""
    if [[ -n "${hysteria2ObfsPassword}" ]]; then
        hysteria2ObfsConfig='"obfs": {"type": "salamander", "password": "'"${hysteria2ObfsPassword}"'"},'
    fi

    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/hysteria2.json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${hysteriaPort},
            "users": $(initXrayClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
            ${hysteria2ObfsConfig}
            "tls": {
                "enabled": true,
                "server_name":"${currentHost}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/v2ray-agent/tls/${currentHost}.crt",
                "key_path": "/etc/v2ray-agent/tls/${currentHost}.key"
            }
        }
    ]
}
EOF
}

# sing-box TuicInstall
singBoxTuicInstall() {
    if ! echo "${currentInstallProtocolType}" | grep -qE ",0,|,1,|,2,|,3,|,4,|,5,|,6,|,9,|,10,"; then
        echoContent red "\n ---> byinneeddependencycertificate，如InstallTuic，invite先InstallbringhaveTLS标识protocol"
        exit 0
    fi

    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",9,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    showAccounts 4
}

# sing-box hy2Install
singBoxHysteria2Install() {
    if ! echo "${currentInstallProtocolType}" | grep -qE ",0,|,1,|,2,|,3,|,4,|,5,|,6,|,9,|,10,"; then
        echoContent red "\n ---> byinneeddependencycertificate，如InstallHysteria2，invite先InstallbringhaveTLS标识protocol"
        exit 0
    fi

    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",6,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    showAccounts 4
}

# sing-box Shadowsocks 2022 Install
singBoxSS2022Install() {
    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",14,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    showAccounts 4
}

# combine并config
singBoxMergeConfig() {
    rm /etc/v2ray-agent/sing-box/conf/config.json >/dev/null 2>&1
    /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ >/dev/null 2>&1
}

# 初始化sing-boxport
initSingBoxPort() {
    local port=$1
    if [[ -n "${port}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "Readtouptimemakeuse的port，yesnomakeuse ？[y/n]:" historyPort
        if [[ "${historyPort}" != "y" ]]; then
            port=
        else
            echo "${port}"
        fi
    elif [[ -n "${port}" && -n "${lastInstallationConfig}" ]]; then
        echo "${port}"
    fi
    if [[ -z "${port}" ]]; then
        read -r -p 'Please entercustomport[needvalid]，port不mayheavy复，[return车]randomport:' port
        if [[ -z "${port}" ]]; then
            port=$((RANDOM % 50001 + 10000))
        fi
        if ((port >= 1 && port <= 65535)); then
            allowPort "${port}"
            allowPort "${port}" "udp"
            echo "${port}"
        else
            echoContent red " ---> portInputError"
            exit 0
        fi
    fi
}

# 初始化Xray Configurefile
initXrayConfig() {
    echoContent skyBlue "\nProgress $2/${totalProgress} : 初始化XrayConfigure"
    echo
    local uuid=
    local addClientsStatus=
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "ReadtouptimeuserConfigure，yesnomakeuseuptimeInstall的Configure ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> makeuseSuccess"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "Please entercustomUUID[needvalid]，[return车]randomUUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/v2ray-agent/xray/xray uuid)
        fi

        echoContent yellow "\nPlease entercustomuser名[needvalid]，[return车]randomuser名"
        read -r -p 'user名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuidReadError，randomGenerate"
        uuid=$(/etc/v2ray-agent/xray/xray uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"id":"'${uuid}'","add":"'${add}'","flow":"xtls-rprx-vision","email":"'${customEmail}'"}]'
        echoContent green "\n ${customEmail}:${uuid}"
        echo
    fi

    # log
    if [[ ! -f "/etc/v2ray-agent/xray/conf/00_log.json" ]]; then

        cat <<EOF >/etc/v2ray-agent/xray/conf/00_log.json
{
  "log": {
    "error": "/etc/v2ray-agent/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF
    fi

    if [[ ! -f "/etc/v2ray-agent/xray/conf/12_policy.json" ]]; then

        cat <<EOF >/etc/v2ray-agent/xray/conf/12_policy.json
{
  "policy": {
      "levels": {
          "0": {
              "handshake": $((1 + RANDOM % 4)),
              "connIdle": $((250 + RANDOM % 51))
          }
      }
  }
}
EOF
    fi

    addXrayOutbound "z_direct_outbound"
    # dns
    if [[ ! -f "/etc/v2ray-agent/xray/conf/11_dns.json" ]]; then
        cat <<EOF >/etc/v2ray-agent/xray/conf/11_dns.json
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
    cat <<EOF >/etc/v2ray-agent/xray/conf/09_routing.json
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
    # fallbacknginx
    local fallbacksList='{"dest":31300,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'

    # trojan
    if echo "${selectCustomInstallType}" | grep -q ",4," || [[ "$1" == "all" ]]; then
        fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'
        cat <<EOF >/etc/v2ray-agent/xray/conf/04_trojan_TCP_inbounds.json
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
        rm /etc/v2ray-agent/xray/conf/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_WS_TLS
    if echo "${selectCustomInstallType}" | grep -q ",1," || [[ "$1" == "all" ]]; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
        cat <<EOF >/etc/v2ray-agent/xray/conf/03_VLESS_WS_inbounds.json
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
        rm /etc/v2ray-agent/xray/conf/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_Reality_XHTTP_TLS
    if echo "${selectCustomInstallType}" | grep -q ",12," || [[ "$1" == "all" ]]; then
        initXrayXHTTPort
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        initRealityMldsa65
        cat <<EOF >/etc/v2ray-agent/xray/conf/12_VLESS_XHTTP_inbounds.json
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
            "mode": "auto"
        }
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/xray/conf/12_VLESS_XHTTP_inbounds.json >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",3," || [[ "$1" == "all" ]]; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'vws","dest":31299,"xver":1}'
        cat <<EOF >/etc/v2ray-agent/xray/conf/05_VMess_WS_inbounds.json
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
        rm /etc/v2ray-agent/xray/conf/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_gRPC
    if echo "${selectCustomInstallType}" | grep -q ",5," || [[ "$1" == "all" ]]; then
        cat <<EOF >/etc/v2ray-agent/xray/conf/06_VLESS_gRPC_inbounds.json
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
        rm /etc/v2ray-agent/xray/conf/06_VLESS_gRPC_inbounds.json >/dev/null 2>&1
    fi

    # VLESS Vision
    if echo "${selectCustomInstallType}" | grep -q ",0," || [[ "$1" == "all" ]]; then

        cat <<EOF >/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json
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
                  "certificateFile": "/etc/v2ray-agent/tls/${domain}.crt",
                  "keyFile": "/etc/v2ray-agent/tls/${domain}.key",
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
        rm /etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_TCP/reality
    if echo "${selectCustomInstallType}" | grep -q ",7," || [[ "$1" == "all" ]]; then
        echoContent skyBlue "\n===================== ConfigureVLESS+Reality =====================\n"

        initXrayRealityPort
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        initRealityMldsa65
        cat <<EOF >/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json
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
        cat <<EOF >/etc/v2ray-agent/xray/conf/08_VLESS_vision_gRPC_inbounds.json
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
        rm /etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
        rm /etc/v2ray-agent/xray/conf/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
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
    echoContent skyBlue "\nProgress $2/${totalProgress} : 初始化TCP_BrutalConfigure"
    read -r -p "yesnomakeuseTCP_Brutal？[y/n]:" tcpBrutalStatus
    if [[ "${tcpBrutalStatus}" == "y" ]]; then
        read -r -p "Please enterlocalbringwide峰value的downline速degree（default：100，单位：Mbps）:" tcpBrutalClientDownloadSpeed
        if [[ -z "${tcpBrutalClientDownloadSpeed}" ]]; then
            tcpBrutalClientDownloadSpeed=100
        fi

        read -r -p "Please enterlocalbringwide峰value的upline速degree（default：50，单位：Mbps）:" tcpBrutalClientUploadSpeed
        if [[ -z "${tcpBrutalClientUploadSpeed}" ]]; then
            tcpBrutalClientUploadSpeed=50
        fi
    fi
}
# 初始化sing-boxConfigurefile
initSingBoxConfig() {
    echoContent skyBlue "\nProgress $2/${totalProgress} : 初始化sing-boxConfigure"

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
        read -r -p "ReadtouptimeuserConfigure，yesnomakeuseuptimeInstall的Configure ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> makeuseSuccess"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "Please entercustomUUID[needvalid]，[return车]randomUUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/v2ray-agent/sing-box/sing-box generate uuid)
        fi

        echoContent yellow "\nPlease entercustomuser名[needvalid]，[return车]randomuser名"
        read -r -p 'user名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuidReadError，randomGenerate"
        uuid=$(/etc/v2ray-agent/sing-box/sing-box generate uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"uuid":"'${uuid}'","flow":"xtls-rprx-vision","name":"'${customEmail}'"}]'
        echoContent yellow "\n ${customEmail}:${uuid}"
    fi

    # VLESS Vision
    if echo "${selectCustomInstallType}" | grep -q ",0," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== ConfigureVLESS+Vision =====================\n"
        echoContent skyBlue "\nStartConfigureVLESS+Visionprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSVisionPort}")
        echoContent green "\n ---> VLESS_Visionport：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop

        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/02_VLESS_TCP_inbounds.json
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
            "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
            "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",1," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== ConfigureVLESS+WS =====================\n"
        echoContent skyBlue "\nStartConfigureVLESS+WSprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSWSPort}")
        echoContent green "\n ---> VLESS_WSport：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/03_VLESS_WS_inbounds.json
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
            "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
            "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
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
        rm /etc/v2ray-agent/sing-box/conf/config/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",3," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== ConfigureVMess+ws =====================\n"
        echoContent skyBlue "\nStartConfigureVMess+wsprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessWSPort}")
        echoContent green "\n ---> VMess_wsport：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/05_VMess_WS_inbounds.json
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
            "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
            "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
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
        rm /etc/v2ray-agent/sing-box/conf/config/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_Reality_Vision
    if echo "${selectCustomInstallType}" | grep -q ",7," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================= ConfigureVLESS+Reality+Vision =================\n"
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        echoContent skyBlue "\nStartConfigureVLESS+Reality+Visionprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityVisionPort}")
        echoContent green "\n ---> VLESS_Reality_Visionport：${result[-1]}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json
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
        rm /etc/v2ray-agent/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",8," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== ConfigureVLESS+Reality+gRPC ==================\n"
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        echoContent skyBlue "\nStartConfigureVLESS+Reality+gRPCprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityGRPCPort}")
        echoContent green "\n ---> VLESS_Reality_gPRCport：${result[-1]}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json
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
        rm /etc/v2ray-agent/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",6," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== Configure Hysteria2 ==================\n"
        echoContent skyBlue "\nStartConfigureHysteria2protocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxHysteria2Port}")
        echoContent green "\n ---> Hysteria2port：${result[-1]}"
        initHysteria2Network

        # 构buildobfsConfigure（如果启use）
        local hysteria2ObfsConfig=""
        if [[ -n "${hysteria2ObfsPassword}" ]]; then
            hysteria2ObfsConfig='"obfs": {"type": "salamander", "password": "'"${hysteria2ObfsPassword}"'"},'
        fi

        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/06_hysteria2_inbounds.json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
            ${hysteria2ObfsConfig}
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/06_hysteria2_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",4," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== Configure Trojan ==================\n"
        echoContent skyBlue "\nStartConfigureTrojanprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTrojanPort}")
        echoContent green "\n ---> Trojanport：${result[-1]}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/04_trojan_TCP_inbounds.json
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
                "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",9," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n==================== Configure Tuic =====================\n"
        echoContent skyBlue "\nStartConfigureTuicprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTuicPort}")
        echoContent green "\n ---> Tuicport：${result[-1]}"
        initTuicProtocol
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/09_tuic_inbounds.json
{
     "inbounds": [
        {
            "type": "tuic",
            "listen": "::",
            "tag": "singbox-tuic-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 9),
            "congestion_control": "${tuicAlgorithm}",
            "zero_rtt_handshake": true,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/09_tuic_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",10," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n==================== Configure Naive =====================\n"
        echoContent skyBlue "\nStartConfigureNaiveprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxNaivePort}")
        echoContent green "\n ---> Naiveport：${result[-1]}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/10_naive_inbounds.json
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
                "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/10_naive_inbounds.json >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",11," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== ConfigureVMess+HTTPUpgrade =====================\n"
        echoContent skyBlue "\nStartConfigureVMess+HTTPUpgradeprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessHTTPUpgradePort}")
        echoContent green "\n ---> VMess_HTTPUpgradeport：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
        checkPortOpen "${result[-1]}" "${domain}"
        singBoxNginxConfig "$1" "${result[-1]}"
        bootStartup nginx
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json
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
        rm /etc/v2ray-agent/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",13," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== Configure AnyTLS ==================\n"
        echoContent skyBlue "\nStartConfigureAnyTLSprotocolport"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxAnyTLSPort}")
        echoContent green "\n ---> AnyTLSport：${result[-1]}"
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/13_anytls_inbounds.json
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
                "certificate_path": "/etc/v2ray-agent/tls/${sslDomain}.crt",
                "key_path": "/etc/v2ray-agent/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/13_anytls_inbounds.json >/dev/null 2>&1
    fi

    # Shadowsocks 2022
    if echo "${selectCustomInstallType}" | grep -q ",14," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== Configure Shadowsocks 2022 ==================\n"
        echoContent skyBlue "\nStartConfigureShadowsocks 2022protocol"
        echo
        initSS2022Config
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/14_ss2022_inbounds.json
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
        echoContent green " ---> Shadowsocks 2022ConfigureComplete"
    elif [[ -z "$3" ]]; then
        rm /etc/v2ray-agent/sing-box/conf/config/14_ss2022_inbounds.json >/dev/null 2>&1
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
# 初始化 sing-boxsubscriptionConfigure
initSubscribeLocalConfig() {
    rm -rf /etc/v2ray-agent/subscribe_local/sing-box/*
}
# universal
defaultBase64Code() {
    local type=$1
    local port=$2
    local email=$3
    local id=$4
    local add=$5
    local path=$6
    local user=
    user=$(echo "${email}" | awk -F "[-]" '{print $1}')
    if [[ ! -f "/etc/v2ray-agent/subscribe_local/sing-box/${user}" ]]; then
        echo [] >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"
    fi
    local singBoxSubscribeLocalConfig=
    if [[ "${type}" == "vlesstcp" ]]; then

        echoContent yellow " ---> universal格style(VLESS+TCP+TLS_Vision)"
        echoContent green "    vless://${id}@${currentHost}:${port}?encryption=none&security=tls&fp=chrome&type=tcp&host=${currentHost}&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格style化明text(VLESS+TCP+TLS_Vision)"
        echoContent green "protocoltypemodel:VLESS，address:${currentHost}，port:${port}，userID:${id}，安complete:tls，client-fingerprint: chrome，transportsquarestyle:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vless://${id}@${currentHost}:${port}?encryption=none&security=tls&type=tcp&host=${currentHost}&fp=chrome&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${currentHost}\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"xudp\"}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code VLESS(VLESS+TCP+TLS_Vision)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${currentHost}%3A${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26type%3Dtcp%26${currentHost}%3D${currentHost}%26headerType%3Dnone%26sni%3D${currentHost}%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vmessws" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> universaljson(VMess+WS+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> universalvmess(VMess+WS+TLS)link"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> QR code vmess(VMess+WS+TLS)"

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vmess://${qrCodeBase64Default}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"max_early_data\":2048,\"early_data_header_name\":\"Sec-WebSocket-Protocol\"}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")

        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" == "vlessws" ]]; then

        echoContent yellow " ---> universal格style(VLESS+WS+TLS)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}\n"

        echoContent yellow " ---> 格style化明text(VLESS+WS+TLS)"
        echoContent green "    protocoltypemodel:VLESS，address:${add}，camouflagedomain/SNI:${currentHost}，port:${port}，client-fingerprint: chrome,userID:${id}，安complete:tls，transportsquarestyle:ws，path:${path}，账户名:${email}\n"

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"headers\":{\"Host\":\"${currentHost}\"}}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code VLESS(VLESS+WS+TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dws%26host%3D${currentHost}%26fp%3Dchrome%26sni%3D${currentHost}%26path%3D${path}%23${email}"

    elif [[ "${type}" == "vlessXHTTP" ]]; then

        echoContent yellow " ---> universal格style(VLESS+reality+XHTTP)"
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&type=xhttp&sni=${xrayVLESSRealityXHTTPServerName}&host=${xrayVLESSRealityXHTTPServerName}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=6ba85179e30d4fc2#${email}\n"

        echoContent yellow " ---> 格style化明text(VLESS+reality+XHTTP)"
        echoContent green "protocoltypemodel:VLESS reality，address:$(getPublicIP)，publicKey:${currentRealityXHTTPPublicKey}，shortId: 6ba85179e30d4fc2,serverNames：${xrayVLESSRealityXHTTPServerName}，port:${port}，path：${path}，SNI:${xrayVLESSRealityXHTTPServerName}，camouflagedomain:${xrayVLESSRealityXHTTPServerName}，userID:${id}，transportsquarestyle:xhttp，账户名:${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&type=xhttp&sni=${xrayVLESSRealityXHTTPServerName}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=6ba85179e30d4fc2#${email}
EOF
        echoContent yellow " ---> QR code VLESS(VLESS+reality+XHTTP)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40$(getPublicIP)%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dxhttp%26sni%3D${xrayVLESSRealityXHTTPServerName}%26fp%3Dchrome%26path%3D${path}%26host%3D${xrayVLESSRealityXHTTPServerName}%26pbk%3D${currentRealityXHTTPPublicKey}%26sid%3D6ba85179e30d4fc2%23${email}\n"

    elif
        [[ "${type}" == "vlessgrpc" ]]
    then

        echoContent yellow " ---> universal格style(VLESS+gRPC+TLS)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&fp=chrome&serviceName=${currentPath}grpc&alpn=h2&sni=${currentHost}#${email}\n"

        echoContent yellow " ---> 格style化明text(VLESS+gRPC+TLS)"
        echoContent green "    protocoltypemodel:VLESS，address:${add}，camouflagedomain/SNI:${currentHost}，port:${port}，userID:${id}，安complete:tls，transportsquarestyle:gRPC，alpn:h2，client-fingerprint: chrome,serviceName:${currentPath}grpc，账户名:${email}\n"

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&serviceName=${currentPath}grpc&fp=chrome&alpn=h2&sni=${currentHost}#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\": \"vless\",\"server\": \"${add}\",\"server_port\": ${port},\"uuid\": \"${id}\",\"tls\": {  \"enabled\": true,  \"server_name\": \"${currentHost}\",  \"utls\": {    \"enabled\": true,    \"fingerprint\": \"chrome\"  }},\"packet_encoding\": \"xudp\",\"transport\": {  \"type\": \"grpc\",  \"service_name\": \"${currentPath}grpc\"}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code VLESS(VLESS+gRPC+TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dgrpc%26host%3D${currentHost}%26serviceName%3D${currentPath}grpc%26fp%3Dchrome%26path%3D${currentPath}grpc%26sni%3D${currentHost}%26alpn%3Dh2%23${email}"

    elif [[ "${type}" == "trojan" ]]; then
        # URLEncode
        echoContent yellow " ---> Trojan(TLS)"
        echoContent green "    trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${currentHost}_Trojan\n"

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${email}_Trojan
EOF

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: trojan
    server: ${currentHost}
    port: ${port}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${currentHost}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"alpn\":[\"http/1.1\"],\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code Trojan(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${currentHost}%3a${port}%3fpeer%3d${currentHost}%26fp%3Dchrome%26sni%3d${currentHost}%26alpn%3Dhttp/1.1%23${email}\n"

    elif [[ "${type}" == "trojangrpc" ]]; then
        # URLEncode

        echoContent yellow " ---> Trojan gRPC(TLS)"
        echoContent green "    trojan://${id}@${add}:${port}?encryption=none&peer=${currentHost}&fp=chrome&security=tls&type=grpc&sni=${currentHost}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
trojan://${id}@${add}:${port}?encryption=none&peer=${currentHost}&security=tls&type=grpc&fp=chrome&sni=${currentHost}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${add}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"insecure\":true,\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"transport\":{\"type\":\"grpc\",\"service_name\":\"${currentPath}trojangrpc\",\"idle_timeout\":\"15s\",\"ping_timeout\":\"15s\",\"permit_without_stream\":false},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code Trojan gRPC(TLS)"
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

        # 构buildobfs参count
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
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
hysteria2://${id}@${currentHost}:${singBoxHysteria2Port}?${multiPort}${obfsUrlParam}peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}
EOF
        echoContent yellow " ---> v2rayN(hysteria+TLS)"
        echo "{\"server\": \"${currentHost}:${port}\",\"socks5\": { \"listen\": \"127.0.0.1:7798\", \"timeout\": 300},\"auth\":\"${id}\",\"tls\":{\"sni\":\"${currentHost}\"}}" | jq

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"hysteria2\",\"server\":\"${currentHost}\",\"server_port\":${singBoxHysteria2Port},\"up_mbps\":${hysteria2ClientUploadSpeed},\"down_mbps\":${hysteria2ClientDownloadSpeed},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"alpn\":[\"h3\"]}${singBoxObfs}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code Hysteria2(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=hysteria2%3A%2F%2F${id}%40${currentHost}%3A${singBoxHysteria2Port}%3F${multiPortEncode}${obfsUrlParamEncode}peer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%26alpn%3Dh3%23${email}\n"

    elif [[ "${type}" == "vlessReality" ]]; then
        local realityServerName=${xrayVLESSRealityServerName}
        local publicKey=${currentRealityPublicKey}
        local realityMldsa65Verify=${currentRealityMldsa65Verify}

        if [[ "${coreInstallType}" == "2" ]]; then
            realityServerName=${singBoxVLESSRealityVisionServerName}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi
        echoContent yellow " ---> universal格style(VLESS+reality+uTLS+Vision)"
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&pqv=${realityMldsa65Verify}&type=tcp&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格style化明text(VLESS+reality+uTLS+Vision)"
        echoContent green "protocoltypemodel:VLESS reality，address:$(getPublicIP)，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，pqv=${realityMldsa65Verify}，serverNames：${realityServerName}，port:${port}，userID:${id}，transportsquarestyle:tcp，账户名:${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&pqv=${realityMldsa65Verify}&type=tcp&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"$(getPublicIP)\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${realityServerName}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"6ba85179e30d4fc2\"}},\"packet_encoding\":\"xudp\"}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code VLESS(VLESS+reality+uTLS+Vision)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40$(getPublicIP)%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dtcp%26sni%3D${realityServerName}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vlessRealityGRPC" ]]; then
        local realityServerName=${xrayVLESSRealityServerName}
        local publicKey=${currentRealityPublicKey}
        local realityMldsa65Verify=${currentRealityMldsa65Verify}

        if [[ "${coreInstallType}" == "2" ]]; then
            realityServerName=${singBoxVLESSRealityGRPCServerName}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi

        echoContent yellow " ---> universal格style(VLESS+reality+uTLS+gRPC)"
        # pqv=${realityMldsa65Verify}&
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&type=grpc&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#${email}\n"

        echoContent yellow " ---> 格style化明text(VLESS+reality+uTLS+gRPC)"
        # pqv=${realityMldsa65Verify}，
        echoContent green "protocoltypemodel:VLESS reality，serviceName:grpc，address:$(getPublicIP)，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，serverNames：${realityServerName}，port:${port}，userID:${id}，transportsquarestyle:gRPC，client-fingerprint：chrome，账户名:${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality&pqv=${realityMldsa65Verify}&type=grpc&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"$(getPublicIP)\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${realityServerName}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"6ba85179e30d4fc2\"}},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"grpc\",\"service_name\":\"grpc\"}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code VLESS(VLESS+reality+uTLS+gRPC)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40$(getPublicIP)%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dgrpc%26sni%3D${realityServerName}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26path%3Dgrpc%26serviceName%3Dgrpc%23${email}\n"
    elif [[ "${type}" == "tuic" ]]; then
        local tuicUUID=
        tuicUUID=$(echo "${id}" | awk -F "[_]" '{print $1}')

        local tuicPassword=
        tuicPassword=$(echo "${id}" | awk -F "[_]" '{print $2}')

        if [[ -z "${email}" ]]; then
            echoContent red " ---> ReadConfigureFailed，inviteheavynewInstall"
            exit 0
        fi

        echoContent yellow " ---> 格style化明text(Tuic+TLS)"
        echoContent green "    protocoltypemodel:Tuic，address:${currentHost}，port：${port}，uuid：${tuicUUID}，password：${tuicPassword}，congestion-controller:${tuicAlgorithm}，alpn: h3，账户名:${email}\n"

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
tuic://${tuicUUID}:${tuicPassword}@${currentHost}:${port}?congestion_control=${tuicAlgorithm}&alpn=h3&sni=${currentHost}&udp_relay_mode=quic&allow_insecure=0#${email}
EOF
        echoContent yellow " ---> v2rayN(Tuic+TLS)"
        echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\": \"tuic\",\"server\": \"${currentHost}\",\"server_port\": ${port},\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"congestion_control\": \"${tuicAlgorithm}\",\"tls\": {\"enabled\": true,\"server_name\": \"${currentHost}\",\"alpn\": [\"h3\"]}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow "\n ---> QR code Tuic"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=tuic%3A%2F%2F${tuicUUID}%3A${tuicPassword}%40${currentHost}%3A${tuicPort}%3Fcongestion_control%3D${tuicAlgorithm}%26alpn%3Dh3%26sni%3D${currentHost}%26udp_relay_mode%3Dquic%26allow_insecure%3D0%23${email}\n"
    elif [[ "${type}" == "naive" ]]; then
        echoContent yellow " ---> Naive(TLS)"

        echoContent green "    naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}
EOF
        echoContent yellow " ---> QR code Naive(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=naive%2Bhttps%3A%2F%2F${email}%3A${id}%40${currentHost}%3A${port}%3Fpadding%3Dtrue%23${email}\n"
    elif [[ "${type}" == "vmessHTTPUpgrade" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> universaljson(VMess+HTTPUpgrade+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> universalvmess(VMess+HTTPUpgrade+TLS)link"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> QR code vmess(VMess+HTTPUpgrade+TLS)"

        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
   vmess://${qrCodeBase64Default}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"security\":\"auto\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"httpupgrade\",\"path\":\"${path}\"}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")

        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" == "anytls" ]]; then
        echoContent yellow " ---> AnyTLS"

        echoContent yellow " ---> 格style化明text(AnyTLS)"
        echoContent green "protocoltypemodel:anytls，address:${currentHost}，port:${singBoxAnyTLSPort}，userID:${id}，transportsquarestyle:tcp，账户名:${email}\n"

        echoContent green "    anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
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

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"anytls\",\"server\":\"${currentHost}\",\"server_port\":${singBoxAnyTLSPort},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\"}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code AnyTLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=anytls%3A%2F%2F${id}%40${currentHost}%3A${singBoxAnyTLSPort}%3Fpeer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%23${email}\n"

    elif [[ "${type}" == "ss2022" ]]; then
        local ss2022ServerKey=$5
        local ss2022Method=$6
        # SS2022 password格style: serverKey:userKey
        local ss2022Password="${ss2022ServerKey}:${id}"
        local ss2022PasswordBase64
        ss2022PasswordBase64=$(echo -n "${ss2022Password}" | base64 | tr -d '\n')

        echoContent yellow " ---> Shadowsocks 2022"

        echoContent yellow " ---> 格style化明text(SS2022)"
        echoContent green "protocoltypemodel:ss2022，address:${publicIP}，port:${port}，encryptionsquarestyle:${ss2022Method}，password:${ss2022Password}，账户名:${email}\n"

        # SIP002 URL格style: ss://BASE64(method:password)@host:port#name
        local ss2022UrlPassword
        ss2022UrlPassword=$(echo -n "${ss2022Method}:${ss2022Password}" | base64 | tr -d '\n')
        echoContent green "    ss://${ss2022UrlPassword}@${publicIP}:${port}#${email}\n"
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/default/${user}"
ss://${ss2022UrlPassword}@${publicIP}:${port}#${email}
EOF
        cat <<EOF >>"/etc/v2ray-agent/subscribe_local/clashMeta/${user}"
  - name: "${email}"
    type: ss
    server: ${publicIP}
    port: ${port}
    cipher: ${ss2022Method}
    password: "${ss2022Password}"
    udp: true
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"shadowsocks\",\"server\":\"${publicIP}\",\"server_port\":${port},\"method\":\"${ss2022Method}\",\"password\":\"${ss2022Password}\",\"multiplex\":{\"enabled\":true}}]" "/etc/v2ray-agent/subscribe_local/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${user}"

        echoContent yellow " ---> QR code SS2022"
        local ss2022QRCode
        ss2022QRCode=$(echo -n "ss://${ss2022UrlPassword}@${publicIP}:${port}#${email}" | sed 's/:/%3A/g; s/\//%2F/g; s/@/%40/g; s/#/%23/g')
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${ss2022QRCode}\n"
    fi

}

# account
showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readSingBoxConfig

    echo
    echoContent skyBlue "\nProgress $1/${totalProgress} : account"

    initSubscribeLocalConfig
    # VLESS TCP
    if echo ${currentInstallProtocolType} | grep -q ",0,"; then

        echoContent skyBlue "============================= VLESS TCP TLS_Vision [recommended] ==============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}02_VLESS_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> account:${email}"
            echo
            defaultBase64Code vlesstcp "${currentDefaultPort}${singBoxVLESSVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi

    # VLESS WS
    if echo ${currentInstallProtocolType} | grep -q ",1,"; then
        echoContent skyBlue "\n================================ VLESS WS TLS [仅CDNrecommended] ================================\n"

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
                echoContent skyBlue "\n ---> account:${email}${count}"
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
        echoContent skyBlue "\n================================  Trojan gRPC TLS [仅CDNrecommended]  ================================\n"
        jq .inbounds[0].settings.clients ${configPath}04_trojan_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email)
            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> account:${email}${count}"
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
        echoContent skyBlue "\n================================ VMess WS TLS [仅CDNrecommended]  ================================\n"
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
                echoContent skyBlue "\n ---> account:${email}${count}"
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
        echoContent skyBlue "\n==================================  Trojan TLS [不recommended] ==================================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echoContent skyBlue "\n ---> account:${email}"

            defaultBase64Code trojan "${currentDefaultPort}${singBoxTrojanPort}" "${email}" "$(echo "${user}" | jq -r .password)"
        done
    fi
    # VLESS grpc
    if echo ${currentInstallProtocolType} | grep -q ",5,"; then
        echoContent skyBlue "\n=============================== VLESS gRPC TLS [仅CDNrecommended]  ===============================\n"
        jq .inbounds[0].settings.clients ${configPath}06_VLESS_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do

            local email=
            email=$(echo "${user}" | jq -r .email)

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> account:${email}${count}"
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
        echoContent skyBlue "\n================================  Hysteria2 TLS [recommended] ================================\n"
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
            echoContent skyBlue "\n ---> account:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code hysteria "${hysteria2DefaultPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # VLESS reality vision
    if echo ${currentInstallProtocolType} | grep -q ",7,"; then
        echoContent skyBlue "============================= VLESS reality_vision [recommended]  ==============================\n"
        jq .inbounds[1].settings.clients//.inbounds[0].users ${configPath}07_VLESS_vision_reality_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> account:${email}"
            echo
            defaultBase64Code vlessReality "${xrayVLESSRealityVisionPort}${singBoxVLESSRealityVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # VLESS reality gRPC
    if echo ${currentInstallProtocolType} | grep -q ",8,"; then
        echoContent skyBlue "============================== VLESS reality_gRPC [recommended] ===============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}08_VLESS_vision_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> account:${email}"
            echo
            defaultBase64Code vlessRealityGRPC "${xrayVLESSRealityVisionPort}${singBoxVLESSRealityGRPCPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # tuic
    if echo ${currentInstallProtocolType} | grep -q ",9," || [[ -n "${tuicPort}" ]]; then
        echoContent skyBlue "\n================================  Tuic TLS [recommended]  ================================\n"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[].users[]' "${path}09_tuic_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> account:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code tuic "${singBoxTuicPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .uuid)_$(echo "${user}" | jq -r .password)"
        done

    fi
    # naive
    if echo ${currentInstallProtocolType} | grep -q ",10," || [[ -n "${singBoxNaivePort}" ]]; then
        echoContent skyBlue "\n================================  naive TLS [recommended，not supportedClashMeta]  ================================\n"

        jq -r -c '.inbounds[]|.users[]' "${configPath}10_naive_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> account:$(echo "${user}" | jq -r .username)"
            echo
            defaultBase64Code naive "${singBoxNaivePort}" "$(echo "${user}" | jq -r .username)" "$(echo "${user}" | jq -r .password)"
        done

    fi
    # VMess HTTPUpgrade
    if echo ${currentInstallProtocolType} | grep -q ",11,"; then
        echoContent skyBlue "\n================================ VMess HTTPUpgrade TLS [仅CDNrecommended]  ================================\n"
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
                echoContent skyBlue "\n ---> account:${email}${count}"
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
        echoContent skyBlue "\n================================ VLESS Reality XHTTP TLS [仅CDNrecommended] ================================\n"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}12_VLESS_XHTTP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echo
            local path="${currentPath}xHTTP"

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> account:${email}${count}"
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
            echoContent skyBlue "\n ---> account:$(echo "${user}" | jq -r .name)"
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
                echoContent skyBlue "\n ---> account:$(echo "${user}" | jq -r .name)"
                echo
                defaultBase64Code ss2022 "${port}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)" "${serverKey}" "${method}"
            done
        fi
    fi
}
# 移除nginx302Configure
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

# 检check302yesnoSuccess
checkNginx302() {
    local domain302Status=
    domain302Status=$(curl -s "https://${currentHost}:${currentPort}")
    if echo "${domain302Status}" | grep -q "302"; then
        #        local domain302Result=
        #        domain302Result=$(curl -L -s "https://${currentHost}:${currentPort}")
        #        if [[ -n "${domain302Result}" ]]; then
        echoContent green " ---> 302heavydecidetowardSetfinished"
        exit 0
        #        fi
    fi
    echoContent red " ---> 302heavydecidetowardSetFailed，invite仔thin检checkyesnoand示例same"
    backupNginxConfig restoreBackup
}

# BackupRestorenginxfile
backupNginxConfig() {
    if [[ "$1" == "backup" ]]; then
        cp ${nginxConfigPath}alone.conf /etc/v2ray-agent/alone_backup.conf
        echoContent green " ---> nginxConfigurefileBackupSuccess"
    fi

    if [[ "$1" == "restoreBackup" ]] && [[ -f "/etc/v2ray-agent/alone_backup.conf" ]]; then
        cp /etc/v2ray-agent/alone_backup.conf ${nginxConfigPath}alone.conf
        echoContent green " ---> nginxConfigurefileRestoreBackupSuccess"
        rm /etc/v2ray-agent/alone_backup.conf
    fi

}
# Add302Configure
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
            echoContent red " ---> 302AddFailed"
            backupNginxConfig restoreBackup
        fi

    done
}

# Updatecamouflagestand
updateNginxBlog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功can仅supportXray-coreinsideverify"
        exit 0
    fi

    echoContent skyBlue "\nProgress $1/${totalProgress} : 更exchangecamouflagestandclick"

    if ! echo "${currentInstallProtocolType}" | grep -q ",0," || [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> byin环environmentdependency，invite先Installing Xray-core的VLESS_TCP_TLS_Vision"
        exit 0
    fi
    echoContent red "=============================================================="
    echoContent yellow "# 如needcustom，invite手moveCopy模versionfileto ${nginxStaticPath} \n"
    echoContent yellow "1.new手leadguide"
    echoContent yellow "2.swim戏网stand"
    echoContent yellow "3.个人博客01"
    echoContent yellow "4.企业stand"
    echoContent yellow "5.unlockencryption的soundhappyfile模version[https://github.com/ix64/unlock-music]"
    echoContent yellow "6.mikutap[https://github.com/HFIProgramming/mikutap]"
    echoContent yellow "7.企业stand02"
    echoContent yellow "8.个人博客02"
    echoContent yellow "9.404自movejumpturnbaidu"
    echoContent yellow "10.302heavydecidetoward网stand"
    echoContent red "=============================================================="
    read -r -p "Please select:" selectInstallNginxBlogType

    if [[ "${selectInstallNginxBlogType}" == "10" ]]; then
        if [[ "${coreInstallType}" == "2" ]]; then
            echoContent red "\n ---> 此功can仅supportXray-coreinsideverify，invite等待back续Update"
            exit 0
        fi
        echoContent red "\n=============================================================="
        echoContent yellow "heavydecidetoward的优先level更high，Configure302after如果更changecamouflagestandclick，根路bydowncamouflagestandclickwill不up作use"
        echoContent yellow "如thinkwantcamouflagestandclick实现作useneedDelete302heavydecidetowardConfigure\n"
        echoContent yellow "1.Add"
        echoContent yellow "2.Delete"
        echoContent red "=============================================================="
        read -r -p "Please select:" redirectStatus

        if [[ "${redirectStatus}" == "1" ]]; then
            backupNginxConfig backup
            read -r -p "Please enterwantheavydecidetoward的domain,例如 https://www.baidu.com:" redirectDomain
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
            echoContent green " ---> 移除302heavydecidetowardSuccess"
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
        echoContent green " ---> 更exchange伪standSuccess"
    else
        echoContent red " ---> Wrong selection, please select again"
        updateNginxBlog
    fi
}

# Addnewport
addCorePort() {

    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功can仅supportXray-coreinsideverify"
        exit 0
    fi

    echoContent skyBlue "\n功can 1/${totalProgress} : Addnewport"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项\n"
    echoContent yellow "supportapprovemeasureAdd"
    echoContent yellow "不shadow响defaultport的makeuse"
    echoContent yellow "Viewaccount时，只know展示defaultport的account"
    echoContent yellow "不allowhave特殊character符，focus意逗号的格style"
    echoContent yellow "如Installedhysteria，know同时Installhysterianewport"
    echoContent yellow "录入示例:2053,2083,2087\n"

    echoContent yellow "1.View已Addport"
    echoContent yellow "2.Addport"
    echoContent yellow "3.Deleteport"
    echoContent red "=============================================================="
    read -r -p "Please select:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        exit 0
    elif [[ "${selectNewPortType}" == "2" ]]; then
        read -r -p "Please enterport号:" newPort
        read -r -p "Please enterdefault的port号，同时know更changesubscriptionportwith及saveclickport，[return车]default443:" defaultPort

        if [[ -n "${defaultPort}" ]]; then
            rm -rf "$(find ${configPath}* | grep "default")"
        fi

        if [[ -n "${newPort}" ]]; then

            while read -r port; do
                rm -rf "$(find ${configPath}* | grep "${port}")"

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

                # openputport
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

            echoContent green " ---> Addfinished"
            reloadCore
            addCorePort
        fi
    elif [[ "${selectNewPortType}" == "3" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        read -r -p "Please enterwantDelete的portweave号:" portIndex
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
            echoContent yellow "\n ---> weave号InputError，please select again"
            addCorePort
        fi
    fi
}

# Uninstallscript
unInstall() {
    read -r -p "yesnoConfirmUninstallInstallinside容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        echoContent green " ---> abandonUninstall"
        menu
        exit 0
    fi
    checkBTPanel
    echoContent yellow " ---> script不knowDeleteacmerelatedConfigure，Deleteinvite手move执line [rm -rf /root/.acme.sh]"
    handleNginx stop
    if [[ -z $(pgrep -f "nginx") ]]; then
        echoContent green " ---> StopNginxSuccess"
    fi
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray stop
            rc-update del xray default
            rm -rf /etc/init.d/xray
            echoContent green " ---> DeleteXrayauto-start on bootComplete"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
            handleSingBox stop
            rc-update del sing-box default
            rm -rf /etc/init.d/sing-box
            echoContent green " ---> Deletesing-boxauto-start on bootComplete"
        fi
    else
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray stop
            rm -rf /etc/systemd/system/xray.service
            echoContent green " ---> DeleteXrayauto-start on bootComplete"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
            handleSingBox stop
            rm -rf /etc/systemd/system/sing-box.service
            echoContent green " ---> Deletesing-boxauto-start on bootComplete"
        fi
    fi

    rm -rf /etc/v2ray-agent
    rm -rf ${nginxConfigPath}alone.conf
    rm -rf ${nginxConfigPath}checkPortOpen.conf >/dev/null 2>&1
    rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
    rm -rf ${nginxConfigPath}checkPortOpen.conf >/dev/null 2>&1

    unInstallSubscribe

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        rm -rf "${nginxStaticPath}"
        echoContent green " ---> Deletecamouflage网standComplete"
    fi

    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
    rm -rf /usr/bin/pasly
    rm -rf /usr/sbin/pasly
    echoContent green " ---> UninstallshortcutsComplete"
    echoContent green " ---> Uninstallv2ray-agentscriptComplete"
}

# CDNsaveclickmanagearrange
manageCDN() {
    echoContent skyBlue "\nProgress $1/1 : CDNsaveclickmanagearrange"
    local setCDNDomain=

    if echo "${currentInstallProtocolType}" | grep -qE ",1,|,2,|,3,|,5,|,11,"; then
        echoContent red "=============================================================="
        echoContent yellow "# focus意事项"
        echoContent yellow "\n教程address:"
        echoContent skyBlue "如need优化 Cloudflare return源 IP，may根据localnetworkformconditionSelectavailable的 IP section。"
        echoContent red "\n如forCloudflare优化不doneunlock，invite不wantmakeuse"

        echoContent yellow "1.CNAME www.digitalocean.com"
        echoContent yellow "2.CNAME who.int"
        echoContent yellow "3.CNAME blog.hostmonit.com"
        echoContent yellow "4.CNAME www.visa.com.hk"
        echoContent yellow "5.手moveInput[mayInputmany个，compare如: 1.1.1.1,1.1.2.2,cloudflare.com 逗号divide隔]"
        echoContent yellow "6.移除CDNsaveclick"
        echoContent red "=============================================================="
        read -r -p "Please select:" selectCDNType
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
            read -r -p "Please enterthinkwantcustomCDN IPor者domain:" setCDNDomain
            ;;
        6)
            echo >/etc/v2ray-agent/cdn
            echoContent green " ---> 移除Success"
            exit 0
            ;;
        esac

        if [[ -n "${setCDNDomain}" ]]; then
            echo >/etc/v2ray-agent/cdn
            echo "${setCDNDomain}" >"/etc/v2ray-agent/cdn"
            echoContent green " ---> ModifyCDNSuccess"
            subscribe false false
        else
            echoContent red " ---> 不maywithasempty，please re-enter"
            manageCDN 1
        fi
    else
        echoContent yellow "\n教程address:"
        echoContent skyBlue "invite根据networkformconditionSelectcombine适的 Cloudflare return源 IP。\n"
        echoContent red " ---> 未Detecttomaywithmakeuse的protocol，仅supportws、grpc、HTTPUpgraderelated的protocol"
    fi
}
# customuuid
customUUID() {
    read -r -p "Please entervalid的UUID，[return车]randomUUID:" currentCustomUUID
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
            echoContent red " ---> UUID不mayheavy复"
            exit 0
        fi
    fi
}

# customemail
customUserEmail() {
    read -r -p "Please entervalid的email，[return车]randomemail:" currentCustomEmail
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
            echoContent red " ---> email不mayheavy复"
            exit 0
        fi
    fi
}

# Adding users
addUser() {
    read -r -p "Please enterwantAdd的usercountmeasure:" userNum
    echo
    if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
        echoContent red " ---> Inputhave误，please re-enter"
        exit 0
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
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 7 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 7 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}07_VLESS_vision_reality_inbounds.json)
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
    echoContent green " ---> AddComplete"
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    manageAccount 1
}
# 移除user
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
            jq -r -c .inbounds[0].settings.clients[].email ${configPath}${userConfigType}.json | awk '{print NR""":"$0}'
        elif [[ "${coreInstallType}" == "2" ]]; then
            jq -r -c .inbounds[0].users[].name//.inbounds[0].users[].username ${configPath}${userConfigType}.json | awk '{print NR""":"$0}'
        fi

        read -r -p "Please selectwantDelete的userweave号[仅support单个Delete]:" delUserIndex
        if [[ $(jq -r '.inbounds[0].settings.clients|length' ${configPath}${userConfigType}.json) -lt ${delUserIndex} && $(jq -r '.inbounds[0].users|length' ${configPath}${userConfigType}.json) -lt ${delUserIndex} ]]; then
            echoContent red " ---> Wrong selection"
        else
            delUserIndex=$((delUserIndex - 1))
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
            vlessRealityResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}']//.inbounds[0].users['${delUserIndex}'])' ${configPath}07_VLESS_vision_reality_inbounds.json)
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
# Updatescript
updateV2RayAgent() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : Updatev2ray-agentscript"
    rm -rf /etc/v2ray-agent/install.sh
    if [[ "${release}" == "alpine" ]]; then
        wget -c -q -P /etc/v2ray-agent/ -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh"
    else
        wget -c -q "${wgetShowProgressStatus}" -P /etc/v2ray-agent/ -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh"
    fi

    sudo chmod 700 /etc/v2ray-agent/install.sh
    local version
    version=$(grep 'currentversion：v' "/etc/v2ray-agent/install.sh" | awk -F "[v]" '{print $2}' | tail -n +2 | head -n 1 | awk -F "[\"]" '{print $1}')

    echoContent green "\n ---> Updatefinished"
    echoContent yellow " ---> invite手move执line[pasly]openscript"
    echoContent green " ---> currentversion：${version}\n"
    echoContent yellow "如Update不Success，invite手move执linedownsurface命令\n"
    echoContent skyBlue "wget -P /root -N https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh"
    echo
    exit 0
}

# firewall
handleFirewall() {
    if systemctl status ufw 2>/dev/null | grep -q "active (exited)" && [[ "$1" == "stop" ]]; then
        systemctl stop ufw >/dev/null 2>&1
        systemctl disable ufw >/dev/null 2>&1
        echoContent green " ---> ufwdisableSuccess"

    fi

    if systemctl status firewalld 2>/dev/null | grep -q "active (running)" && [[ "$1" == "stop" ]]; then
        systemctl stop firewalld >/dev/null 2>&1
        systemctl disable firewalld >/dev/null 2>&1
        echoContent green " ---> firewallddisableSuccess"
    fi
}

# InstallBBR
bbrInstall() {
    echoContent red "\n=============================================================="
    echoContent green "BBR、DDscriptuse的[ylx2016]的become熟作品，address[https://github.com/ylx2016/Linux-NetSpeed]，invite熟知"
    echoContent yellow "1.Installscript【recommended原versionBBR+FQ】"
    echoContent yellow "2.return退maindirectory"
    echoContent red "=============================================================="
    read -r -p "Please select:" installBBRStatus
    if [[ "${installBBRStatus}" == "1" ]]; then
        wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
    else
        menu
    fi
}

# View、检checklog
checkLog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功can仅supportXray-coreinsideverify"
        exit 0
    fi
    if [[ -z "${configPath}" && -z "${realityStatus}" ]]; then
        echoContent red " ---> 没haveDetecttoInstalldirectory，invite执linescriptInstallinside容"
        exit 0
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

    echoContent skyBlue "\n功can $1/${totalProgress} : Viewlog"
    echoContent red "\n=============================================================="
    echoContent yellow "# recommended仅adjusttry时openaccesslog\n"

    if [[ "${logStatus}" == "false" ]]; then
        echoContent yellow "1.openaccesslog"
    else
        echoContent yellow "1.disableaccesslog"
    fi

    echoContent yellow "2.监listenaccesslog"
    echoContent yellow "3.监listenerrorlog"
    echoContent yellow "4.Viewcertificatescheduled taskslog"
    echoContent yellow "5.ViewcertificateInstalllog"
    echoContent yellow "6.清emptylog"
    echoContent yellow "7.loglevel别(current:${currentLogLevel})"
    echoContent red "=============================================================="

    read -r -p "Please select:" selectAccessLogType
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
        if [[ ! -f "/etc/v2ray-agent/crontab_tls.log" ]]; then
            touch /etc/v2ray-agent/crontab_tls.log
        fi
        tail -n 100 /etc/v2ray-agent/crontab_tls.log
        ;;
    5)
        tail -n 100 /etc/v2ray-agent/tls/acme.log
        ;;
    6)
        echo >${defaultAccessPath}
        echo >${defaultErrorPath}
        ;;
    7)
        echoContent yellow "\nloglevel别Switch(current:${currentLogLevel})"
        echoContent yellow "1.warning(default)"
        echoContent yellow "2.info"
        echoContent yellow "3.debug"
        echoContent yellow "4.最smalllog(Write/tmp，适combinenonegame/adjusttryfinishedbackmakeuse)"
        read -r -p "Please select:" selectLogLevel
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
            local tmpLogDir="/tmp/v2ray-agent"
            mkdir -p "${tmpLogDir}"
            currentLogLevel="warning"
            writeLogConfig "${tmpLogDir}/access.log" "${tmpLogDir}/error.log" "${currentLogLevel}"
            updateRealityLogShow "false"
            reloadCore
            echoContent green "\n ---> 已Switchas最smalllog模style"
            echoContent yellow " ---> access/error willWrite ${tmpLogDir}/，systemtemporarydirectoryknowatRestartor周periodClean时自move清empty，如need立即Cleanmay执line [rm -f ${tmpLogDir}/*.log]"
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

# scriptshortcuts
aliasInstall() {

    if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/v2ray-agent" ]] && grep -Eq "作者[:：]Lynthar|Proxy-agent" "$HOME/install.sh"; then
        mv "$HOME/install.sh" /etc/v2ray-agent/install.sh
        local paslyType=
        if [[ -d "/usr/bin/" ]]; then
            rm -f "/usr/bin/vasma"
            if [[ ! -f "/usr/bin/pasly" ]]; then
                ln -s /etc/v2ray-agent/install.sh /usr/bin/pasly
                chmod 700 /usr/bin/pasly
                paslyType=true
            fi

            rm -rf "$HOME/install.sh"
        elif [[ -d "/usr/sbin" ]]; then
            rm -f "/usr/sbin/vasma"
            if [[ ! -f "/usr/sbin/pasly" ]]; then
                ln -s /etc/v2ray-agent/install.sh /usr/sbin/pasly
                chmod 700 /usr/sbin/pasly
                paslyType=true
            fi
            rm -rf "$HOME/install.sh"
        fi
        if [[ "${paslyType}" == "true" ]]; then
            echoContent green "shortcutsCreateSuccess，may执line[pasly]heavynewopenscript"
        fi
    fi
}

# 检checkipv6、ipv4
checkIPv6() {
    currentIPv6IP=$(curl -s -6 -m 4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)

    if [[ -z "${currentIPv6IP}" ]]; then
        echoContent red " ---> not supportedipv6"
        exit 0
    fi
}

# ipv6 routing
ipv6Routing() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> Not installed，invitemakeusescriptInstall"
        menu
        exit 0
    fi

    checkIPv6
    echoContent skyBlue "\n功can 1/${totalProgress} : IPv6routing"
    echoContent red "\n=============================================================="
    echoContent yellow "1.View已routingdomain"
    echoContent yellow "2.Adddomain"
    echoContent yellow "3.SetIPv6global"
    echoContent yellow "4.UninstallIPv6routing"
    echoContent red "=============================================================="
    read -r -p "Please select:" ipv6Status
    if [[ "${ipv6Status}" == "1" ]]; then
        showIPv6Routing
        exit 0
    elif [[ "${ipv6Status}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# focus意事项\n"
        echoContent yellow "# focus意事项"
        echoContent yellow "# makeuseNotice：invite参考 documents directorymiddle的routingwith策略say明 \n"

        read -r -p "invitepressphotoupsurface示例录入domain:" domainList
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

        echoContent green " ---> Addfinished"

    elif [[ "${ipv6Status}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# focus意事项\n"
        echoContent yellow "1.knowDeleteallSet的routing规则"
        echoContent yellow "2.knowDeleteIPv6outside的alloutbound规则\n"
        read -r -p "yesnoConfirmSet？[y/n]:" IPv6OutStatus

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

            echoContent green " ---> IPv6globaloutboundSetfinished"
        else

            echoContent green " ---> abandonSet"
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

        echoContent green " ---> IPv6routingUninstall successful"
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi

    reloadCore
}

# ipv6routing规则展示
showIPv6Routing() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core："
            jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6_out")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}IPv6_out.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已SetIPv6globalrouting"
        else
            echoContent yellow " ---> Not installedIPv6routing"
        fi

    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}IPv6_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]|select (.outbound=="IPv6_out")' "${singBoxConfigPath}IPv6_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}IPv6_route.json" && -f "${singBoxConfigPath}IPv6_out.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已SetIPv6globalrouting"
        else
            echoContent yellow " ---> Not installedIPv6routing"
        fi
    fi
}
# btdownloadmanagearrange
btTools() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功can仅supportXray-coreinsideverify，invite等待back续Update"
        exit 0
    fi
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> Not installed，invitemakeusescriptInstall"
        menu
        exit 0
    fi

    echoContent skyBlue "\n功can 1/${totalProgress} : btdownloadmanagearrange"
    echoContent red "\n=============================================================="

    if [[ -f ${configPath}09_routing.json ]] && grep -q bittorrent <${configPath}09_routing.json; then
        echoContent yellow "currentstatus:已denydownloadBT"
    else
        echoContent yellow "currentstatus:allowdownloadBT"
    fi

    echoContent yellow "1.denydownloadBT"
    echoContent yellow "2.allowdownloadBT"
    echoContent red "=============================================================="
    read -r -p "Please select:" btStatus
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

        echoContent green " ---> denyBTdownload"

    elif [[ "${btStatus}" == "2" ]]; then

        unInstallSniffing

        unInstallRouting blackhole_out outboundTag bittorrent

        echoContent green " ---> allowBTdownload"
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi

    reloadCore
}

# domain黑名单
blacklist() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> Not installed，invitemakeusescriptInstall"
        menu
        exit 0
    fi

    echoContent skyBlue "\nProgress  $1/${totalProgress} : domain黑名单"
    echoContent red "\n=============================================================="
    echoContent yellow "1.View已屏蔽domain"
    echoContent yellow "2.Adddomain"
    echoContent yellow "3.屏蔽large陆domain"
    echoContent yellow "4.Uninstall黑名单"
    echoContent red "=============================================================="

    read -r -p "Please select:" blacklistStatus
    if [[ "${blacklistStatus}" == "1" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="blackhole_out")|.domain' ${configPath}09_routing.json | jq -r
        exit 0
    elif [[ "${blacklistStatus}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# focus意事项\n"
        echoContent yellow "1.规则support预decide义domainlist表[https://github.com/v2fly/domain-list-community]"
        echoContent yellow "2.规则supportcustomdomain"
        echoContent yellow "3.录入示例:speedtest,facebook,cn,example.com"
        echoContent yellow "4.如果domainat预decide义domainlist表middleexists则makeuse geosite:xx，如果does not exist则defaultmakeuseInput的domain"
        echoContent yellow "5.Add规则as增measureConfigure，不knowDeletebeforeSet的inside容\n"
        read -r -p "invitepressphotoupsurface示例录入domain:" domainList
        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayRouting blackhole_out outboundTag "${domainList}"
            addXrayOutbound blackhole_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "block_domain_outbound" "${domainList}" "block_domain_route"
            addSingBoxOutbound "block_domain_outbound"
            addSingBoxOutbound "01_direct_outbound"
        fi
        echoContent green " ---> Addfinished"

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

        echoContent green " ---> 屏蔽large陆domainfinished"

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
        echoContent green " ---> domain黑名单Deletefinished"
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi
    reloadCore
}
# AddroutingConfigure
addXrayRouting() {

    local tag=$1    # warp-socks
    local type=$2   # outboundTag/inboundTag
    local domain=$3 # domain

    if [[ -z "${tag}" || -z "${type}" || -z "${domain}" ]]; then
        echoContent red " ---> 参countError"
        exit 0
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
        if echo "${routingRule}" | grep -q "${line}"; then
            echoContent yellow " ---> ${line}already exists，Skip"
        else
            local geositeStatus
            geositeStatus=$(curl -s "https://api.github.com/repos/v2fly/domain-list-community/contents/data/${line}" | jq .message)

            if [[ "${geositeStatus}" == "null" ]]; then
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
# 根据tagUninstallRouting
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

# Uninstall嗅explore
unInstallSniffing() {

    find ${configPath} -name "*inbounds.json*" | awk -F "[c][o][n][f][/]" '{print $2}' | while read -r inbound; do
        if grep -q "destOverride" <"${configPath}${inbound}"; then
            sniffing=$(jq -r 'del(.inbounds[0].sniffing)' "${configPath}${inbound}")
            echo "${sniffing}" | jq . >"${configPath}${inbound}"
        fi
    done

}

# Install嗅explore
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

# Read第三squarewarpConfigure
readConfigWarpReg() {
    if [[ ! -f "/etc/v2ray-agent/warp/config" ]]; then
        /etc/v2ray-agent/warp/warp-reg >/etc/v2ray-agent/warp/config
    fi

    secretKeyWarpReg=$(grep <"/etc/v2ray-agent/warp/config" private_key | awk '{print $2}')

    addressWarpReg=$(grep <"/etc/v2ray-agent/warp/config" v6 | awk '{print $2}')

    publicKeyWarpReg=$(grep <"/etc/v2ray-agent/warp/config" public_key | awk '{print $2}')

    reservedWarpReg=$(grep <"/etc/v2ray-agent/warp/config" reserved | awk -F "[:]" '{print $2}')

}
# Installwarp-regtool
installWarpReg() {
    if [[ ! -f "/etc/v2ray-agent/warp/warp-reg" ]]; then
        echo
        echoContent yellow "# focus意事项"
        echoContent yellow "# dependency第三square程序，invite熟知其middle风险"
        echoContent yellow "# 项目address：https://github.com/badafans/warp-reg \n"

        read -r -p "warp-regNot installed，yesnoInstall ？[y/n]:" installWarpRegStatus

        if [[ "${installWarpRegStatus}" == "y" ]]; then

            curl -sLo /etc/v2ray-agent/warp/warp-reg "https://github.com/badafans/warp-reg/releases/download/v1.0/${warpRegCoreCPUVendor}"
            chmod 655 /etc/v2ray-agent/warp/warp-reg

        else
            echoContent yellow " ---> abandonInstall"
            exit 0
        fi
    fi
}

# 展示warproutingdomain
showWireGuardDomain() {
    local type=$1
    # xray
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core"
            jq -r -c '.routing.rules[]|select (.outboundTag=="wireguard_out_'"${type}"'")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}wireguard_out_${type}.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已Setwarp ${type}globalrouting"
        else
            echoContent yellow " ---> Not installedwarp ${type}routing"
        fi
    fi

    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]' "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" && -f "${singBoxConfigPath}wireguard_endpoints_${type}.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已Setwarp ${type}globalrouting"
        else
            echoContent yellow " ---> Not installedwarp ${type}routing"
        fi
    fi

}

# AddWireGuardrouting
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

# UninstallwireGuard
unInstallWireGuard() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        if [[ "${type}" == "IPv4" ]]; then
            if [[ ! -f "${configPath}wireguard_out_IPv6.json" ]]; then
                rm -rf /etc/v2ray-agent/warp/config >/dev/null 2>&1
            fi
        elif [[ "${type}" == "IPv6" ]]; then
            if [[ ! -f "${configPath}wireguard_out_IPv4.json" ]]; then
                rm -rf /etc/v2ray-agent/warp/config >/dev/null 2>&1
            fi
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ ! -f "${singBoxConfigPath}wireguard_endpoints_IPv6_route.json" && ! -f "${singBoxConfigPath}wireguard_endpoints_IPv4_route.json" ]]; then
            rm "${singBoxConfigPath}wireguard_outbound.json" >/dev/null 2>&1
            rm -rf /etc/v2ray-agent/warp/config >/dev/null 2>&1
        fi
    fi
}
# 移除WireGuardrouting
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
# warprouting-第三squareIPv4
warpRoutingReg() {
    local type=$2
    echoContent skyBlue "\nProgress  $1/${totalProgress} : WARProuting[第三square]"
    echoContent red "=============================================================="

    echoContent yellow "1.View已routingdomain"
    echoContent yellow "2.Adddomain"
    echoContent yellow "3.SetWARPglobal"
    echoContent yellow "4.UninstallWARProuting"
    echoContent red "=============================================================="
    read -r -p "Please select:" warpStatus
    installWarpReg
    readConfigWarpReg
    local address=
    if [[ ${type} == "IPv4" ]]; then
        address="172.16.0.2/32"
    elif [[ ${type} == "IPv6" ]]; then
        address="${addressWarpReg}/128"
    else
        echoContent red " ---> IPGetFailed，ExitInstall"
    fi

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        exit 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent yellow "# focus意事项"
        echoContent yellow "# supportsing-box、Xray-core"
        echoContent yellow "# makeuseNotice：invite参考 documents directorymiddle的routingwith策略say明 \n"

        read -r -p "invitepressphotoupsurface示例录入domain:" domainList
        addWireGuardRoute "${type}" outboundTag "${domainList}"
        echoContent green " ---> Addfinished"

    elif [[ "${warpStatus}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# focus意事项\n"
        echoContent yellow "1.knowDeleteallSet的routing规则"
        echoContent yellow "2.knowDelete除WARP[第三square]outside的alloutbound规则\n"
        read -r -p "yesnoConfirmSet？[y/n]:" warpOutStatus

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

                # Deleteallrouting规则
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

            echoContent green " ---> WARPglobaloutboundSetfinished"
        else
            echoContent green " ---> abandonSet"
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

        echoContent green " ---> UninstallWARP ${type}routingfinished"
    else

        echoContent red " ---> Wrong selection"
        exit 0
    fi
    reloadCore
}

# ======================= chain proxy功can =======================

# chain proxyMain Menu
chainProxyMenu() {
    echoContent skyBlue "\n功can: chain proxymanagearrange"
    echoContent red "\n=============================================================="
    echoContent yellow "# chain proxysay明"
    echoContent yellow "# useinatmany台environmentoutsideVPSbetweenbuild立encryptionforward链路"
    echoContent yellow "# supportmanylayerrelay: 入mouthful → relay1 → relay2 → ... → exitmouthful → 互联网"
    echoContent yellow "# makeuse Shadowsocks 2022 protocol，encryption安complete、性can优秀\n"

    echoContent yellow "1.fast速Configuretowardguide [recommended]"
    echoContent yellow "2.View链路status"
    echoContent yellow "3.Test链路connectthrough性"
    echoContent yellow "4.highlevelSet"
    echoContent yellow "5.Uninstallchain proxy"

    read -r -p "Please select:" selectType

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

# chain proxyConfiguretowardguide
chainProxyWizard() {
    echoContent skyBlue "\nchain proxyConfiguretowardguide"
    echoContent red "\n=============================================================="
    echoContent yellow "Please selectcopy机corner色:\n"
    echoContent yellow "1.exit node (Exit) - 链路终click，straightcatch访ask互联网"
    echoContent yellow "  └─ GenerateConfigure码，供relayorentry nodeImport"
    echoContent yellow ""
    echoContent yellow "2.relaysaveclick (Relay) - 链路middlesaveclick，forwardflowmeasure"
    echoContent yellow "  └─ ImportdownstreamConfigure码，GeneratenewConfigure码供upstreammakeuse"
    echoContent yellow "  └─ supportmanylayerrelay: 入mouthful→relay1→relay2→...→exitmouthful"
    echoContent yellow ""
    echoContent yellow "3.entry node (Entry) - 链路upclick，catchcollectclientconnection"
    echoContent yellow "  └─ Importexitmouthfulorrelaysaveclick的Configure码"
    echoContent yellow ""
    echoContent yellow "4.手moveConfigureentry node"
    echoContent yellow "  └─ 手moveInputexit node信息 (仅support单jump)"

    read -r -p "Please select:" selectType

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

# ensure sing-box Installed
ensureSingBoxInstalled() {
    if [[ ! -f "/etc/v2ray-agent/sing-box/sing-box" ]]; then
        echoContent yellow "\nDetectto sing-box Not installed，positiveatInstall..."
        installSingBox
        if [[ ! -f "/etc/v2ray-agent/sing-box/sing-box" ]]; then
            echoContent red " ---> sing-box Installation failed"
            return 1
        fi
    fi

    # ensureConfiguredirectoryexists
    mkdir -p /etc/v2ray-agent/sing-box/conf/config/

    # ensure基础Configureexists
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/config/00_log.json" ]]; then
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/00_log.json
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    }
}
EOF
    fi

    # ensure DNS Configureexists
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/config/01_dns.json" ]]; then
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/01_dns.json
{
    "dns": {
        "servers": [
            {
                "tag": "google",
                "address": "8.8.8.8"
            }
        ]
    }
}
EOF
    fi

    # ensuredirectoutboundexists
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/config/01_direct_outbound.json" ]]; then
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/01_direct_outbound.json
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

    # ensure systemd serviceInstalled（repair复：chain proxyneedservice才canStart）
    if [[ ! -f "/etc/systemd/system/sing-box.service" ]] && [[ ! -f "/etc/init.d/sing-box" ]]; then
        echoContent yellow "\nDetectto sing-box service未Configure，positiveatConfigure..."
        local execStart='/etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json'

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
            echoContent green " ---> sing-box serviceConfigureComplete"
        elif [[ "${release}" == "alpine" ]]; then
            cat <<EOF >/etc/init.d/sing-box
#!/sbin/openrc-run

name="sing-box"
description="Sing-Box Service"
command="/etc/v2ray-agent/sing-box/sing-box"
command_args="run -c /etc/v2ray-agent/sing-box/conf/config.json"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
    after firewall
}
EOF
            chmod +x /etc/init.d/sing-box
            rc-update add sing-box default >/dev/null 2>&1
            echoContent green " ---> sing-box serviceConfigureComplete (Alpine)"
        fi
    fi

    return 0
}

# Generatechain proxykey (Shadowsocks 2022 need Base64 weave码)
generateChainKey() {
    # AES-128-GCM need 16 charactersavekey
    openssl rand -base64 16
}

# Getcopy机公网 IP
getChainPublicIP() {
    local ip=""
    # trymany个serviceGetpublic IP
    ip=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
    if [[ -z "${ip}" ]]; then
        ip=$(curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null)
    fi
    if [[ -z "${ip}" ]]; then
        ip=$(curl -s4 --connect-timeout 5 https://ip.sb 2>/dev/null)
    fi
    echo "${ip}"
}

# Configureexit node (Exit)
setupChainExit() {
    echoContent skyBlue "\nConfigureexit node (Exit)"
    echoContent red "\n=============================================================="

    # ensure sing-box Installed
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检checkyesnoalready existschain proxyinbound
    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_inbound.json" ]]; then
        echoContent yellow "\nDetecttoalready existschain proxyConfigure"
        read -r -p "yesno覆cover现haveConfigure？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            # 显示现haveConfigure码
            showExistingChainCode
            return 0
        fi
    fi

    # Generaterandomport (10000-60000)
    local chainPort
    chainPort=$((RANDOM % 50000 + 10000))
    echoContent yellow "\nPlease enterchain proxyport [return车makeuserandomport: ${chainPort}]"
    read -r -p "port:" inputPort
    if [[ -n "${inputPort}" ]]; then
        if [[ ! "${inputPort}" =~ ^[0-9]+$ ]] || [[ "${inputPort}" -lt 1 ]] || [[ "${inputPort}" -gt 65535 ]]; then
            echoContent red " ---> port格styleError"
            return 1
        fi
        chainPort=${inputPort}
    fi

    # Generatekey
    local chainKey
    chainKey=$(generateChainKey)
    echoContent green "\n ---> 已Generaterandomkey"

    # encryptionsquare法
    local chainMethod="2022-blake3-aes-128-gcm"

    # Get public IP
    local publicIP
    publicIP=$(getChainPublicIP)
    if [[ -z "${publicIP}" ]]; then
        echoContent yellow "\ncannot自moveGetpublic IP，invite手moveInput"
        read -r -p "public IP:" publicIP
        if [[ -z "${publicIP}" ]]; then
            echoContent red " ---> IP不canasempty"
            return 1
        fi
    fi
    echoContent green " ---> copy机public IP: ${publicIP}"

    # inquireaskyesnolimit制入mouthfulIP
    echoContent yellow "\nyesnolimit制只allow特decideIPconnection？(lifthigh安complete性)"
    echoContent yellow "1.不limit制 [return车default]"
    echoContent yellow "2.limit制特decideIP"
    read -r -p "Please select:" limitIPChoice

    local allowedIP=""
    if [[ "${limitIPChoice}" == "2" ]]; then
        read -r -p "Please enterallowconnection的entry nodeIP:" allowedIP
        if [[ -z "${allowedIP}" ]]; then
            echoContent red " ---> IP不canasempty"
            return 1
        fi
    fi

    # CreateinboundConfigure
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_inbound.json
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

    # Create路byConfigure (let链styleinboundflowmeasurewalkdirect)
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_route.json
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

    # SaveConfigure信息useinGenerateConfigure码
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/chain_exit_info.json
{
    "role": "exit",
    "ip": "${publicIP}",
    "port": ${chainPort},
    "method": "${chainMethod}",
    "password": "${chainKey}",
    "allowed_ip": "${allowedIP}"
}
EOF

    # openputfirewallport
    if [[ -n "${allowedIP}" ]]; then
        allowPort "${chainPort}" "tcp" "${allowedIP}/32"
        echoContent green " ---> 已openputport ${chainPort} (仅allow ${allowedIP})"
    else
        allowPort "${chainPort}" "tcp"
        echoContent green " ---> 已openputport ${chainPort}"
    fi

    # combine并Configure并Restart
    mergeSingBoxConfig
    reloadCore

    # Generate并显示Configure码
    echoContent green "\n=============================================================="
    echoContent green "exit nodeConfigureComplete！"
    echoContent green "=============================================================="
    echoContent yellow "\nchain proxyConfigure码 (inviteCopytoentry node):\n"

    local chainCode
    chainCode="chain://ss2022@${publicIP}:${chainPort}?key=$(echo -n "${chainKey}" | base64 | tr -d '\n')&method=${chainMethod}"
    echoContent skyBlue "${chainCode}"

    echoContent yellow "\nor手moveConfigure:"
    echoContent green "  IPaddress: ${publicIP}"
    echoContent green "  port: ${chainPort}"
    echoContent green "  key: ${chainKey}"
    echoContent green "  encryptionsquarestyle: ${chainMethod}"

    echoContent red "\ninvite妥善protectmanageConfigure码，cut勿泄露！"
}

# 显示现haveConfigure码
showExistingChainCode() {
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/chain_exit_info.json" ]]; then
        echoContent red " ---> 未findtoexit nodeConfigure信息"
        return 1
    fi

    local publicIP port method password
    publicIP=$(jq -r '.ip' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
    port=$(jq -r '.port' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
    method=$(jq -r '.method' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
    password=$(jq -r '.password' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)

    echoContent green "\n=============================================================="
    echoContent green "现haveexit nodeConfigure"
    echoContent green "=============================================================="

    local chainCode
    chainCode="chain://ss2022@${publicIP}:${port}?key=$(echo -n "${password}" | base64 | tr -d '\n')&method=${method}"
    echoContent yellow "\nConfigure码:\n"
    echoContent skyBlue "${chainCode}"

    echoContent yellow "\n手moveConfigure信息:"
    echoContent green "  IPaddress: ${publicIP}"
    echoContent green "  port: ${port}"
    echoContent green "  key: ${password}"
    echoContent green "  encryptionsquarestyle: ${method}"
}

# unlock析Configure码 (support V1 单jumpand V2 manyjump格style)
# V1 格style: chain://ss2022@IP:PORT?key=xxx&method=xxx
# V2 格style: chain://v2@BASE64_JSON_ARRAY
# Output: chainHops countgroup (JSON), chainHopCount jumpcount
parseChainCode() {
    local code=$1

    # Initialize Global Variables
    chainHops=""
    chainHopCount=0
    chainExitIP=""
    chainExitPort=""
    chainExitKey=""
    chainExitMethod=""

    # V2 manyjump格style
    if [[ "${code}" =~ ^chain://v2@ ]]; then
        local base64Data
        base64Data=$(echo "${code}" | sed 's/chain:\/\/v2@//')

        # unlock码 Base64
        chainHops=$(echo "${base64Data}" | base64 -d 2>/dev/null)
        if [[ -z "${chainHops}" ]] || ! echo "${chainHops}" | jq empty 2>/dev/null; then
            echoContent red " ---> V2 Configure码unlock析Failed，JSON格styleError"
            return 1
        fi

        chainHopCount=$(echo "${chainHops}" | jq 'length')
        if [[ "${chainHopCount}" -lt 1 ]]; then
            echoContent red " ---> Configure码不include任何jumpturnsaveclick"
            return 1
        fi

        echoContent green " ---> V2 manyjumpConfigure码unlock析Success"
        echoContent green "  总jumpcount: ${chainHopCount}"

        # 显示链路
        local i=1
        while [[ $i -le ${chainHopCount} ]]; do
            local hopIP hopPort
            hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
            hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
            if [[ $i -eq ${chainHopCount} ]]; then
                echoContent green "  第${i}jump (exitmouthful): ${hopIP}:${hopPort}"
            else
                echoContent green "  第${i}jump (relay): ${hopIP}:${hopPort}"
            fi
            ((i++))
        done

        # compatible性：Setlast一jumpasexitmouthful
        chainExitIP=$(echo "${chainHops}" | jq -r '.[-1].ip')
        chainExitPort=$(echo "${chainHops}" | jq -r '.[-1].port')
        chainExitKey=$(echo "${chainHops}" | jq -r '.[-1].key')
        chainExitMethod=$(echo "${chainHops}" | jq -r '.[-1].method')

        return 0
    fi

    # V1 单jump格style
    if [[ "${code}" =~ ^chain://ss2022@ ]]; then
        # liftget IP:PORT
        local ipPort
        ipPort=$(echo "${code}" | sed 's/chain:\/\/ss2022@//' | cut -d'?' -f1)
        chainExitIP=$(echo "${ipPort}" | cut -d':' -f1)
        chainExitPort=$(echo "${ipPort}" | cut -d':' -f2)

        # liftget参count
        local params
        params=$(echo "${code}" | cut -d'?' -f2)

        # liftget key (Base64 weave码的keyneedunlock码)
        local keyBase64
        keyBase64=$(echo "${params}" | grep -oP 'key=\K[^&]+')
        chainExitKey=$(echo "${keyBase64}" | base64 -d 2>/dev/null)
        if [[ -z "${chainExitKey}" ]]; then
            chainExitKey="${keyBase64}"
        fi

        # liftget method
        chainExitMethod=$(echo "${params}" | grep -oP 'method=\K[^&]+')
        if [[ -z "${chainExitMethod}" ]]; then
            chainExitMethod="2022-blake3-aes-128-gcm"
        fi

        # Verifyliftget结果
        if [[ -z "${chainExitIP}" ]] || [[ -z "${chainExitPort}" ]] || [[ -z "${chainExitKey}" ]]; then
            echoContent red " ---> Configure码unlock析Failed"
            return 1
        fi

        # turnexchangeas V2 格style的单jumpcountgroup
        chainHops=$(jq -n --arg ip "${chainExitIP}" --argjson port "${chainExitPort}" \
            --arg key "${chainExitKey}" --arg method "${chainExitMethod}" \
            '[{ip: $ip, port: $port, key: $key, method: $method}]')
        chainHopCount=1

        echoContent green " ---> V1 Configure码unlock析Success"
        echoContent green "  exitmouthfulIP: ${chainExitIP}"
        echoContent green "  exitmouthfulport: ${chainExitPort}"
        echoContent green "  encryptionsquarestyle: ${chainExitMethod}"

        return 0
    fi

    echoContent red " ---> Configure码格styleError，not supported的格style"
    return 1
}

# passConfigure码Configureentry node
setupChainEntryByCode() {
    echoContent skyBlue "\nConfigureentry node (Entry) - Configure码模style"
    echoContent red "\n=============================================================="

    echoContent yellow "inviteadherepasteexitmouthfulorrelaysaveclick的Configure码:"
    read -r -p "Configure码:" chainCode

    if [[ -z "${chainCode}" ]]; then
        echoContent red " ---> Configure码不canasempty"
        return 1
    fi

    # unlock析Configure码 (support V1 单jumpand V2 manyjump)
    if ! parseChainCode "${chainCode}"; then
        return 1
    fi

    # 根据jumpcountadjustusedifferent的Configure函count
    if [[ ${chainHopCount} -gt 1 ]]; then
        # multi-hop mode - makeuseglobal chainHops 变measure
        setupChainEntryMultiHop
    else
        # 单jump模style - towardbackcompatible
        setupChainEntry "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}"
    fi
}

# 手moveConfigureentry node
setupChainEntryManual() {
    echoContent skyBlue "\nConfigureentry node (Entry) - 手move模style"
    echoContent red "\n=============================================================="

    read -r -p "exit nodeIP:" chainExitIP
    if [[ -z "${chainExitIP}" ]]; then
        echoContent red " ---> IP不canasempty"
        return 1
    fi

    read -r -p "exit nodeport:" chainExitPort
    if [[ -z "${chainExitPort}" ]]; then
        echoContent red " ---> port不canasempty"
        return 1
    fi

    read -r -p "key:" chainExitKey
    if [[ -z "${chainExitKey}" ]]; then
        echoContent red " ---> key不canasempty"
        return 1
    fi

    echoContent yellow "\nencryptionsquarestyle [return车default: 2022-blake3-aes-128-gcm]"
    read -r -p "encryptionsquarestyle:" chainExitMethod
    if [[ -z "${chainExitMethod}" ]]; then
        chainExitMethod="2022-blake3-aes-128-gcm"
    fi

    setupChainEntry "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}"
}

# Configurerelaysaveclick (Relay)
# relaysaveclick同时作asupstream的"exitmouthful"（catchcollectflowmeasure）anddownstream的"入mouthful"（forwardflowmeasure）
setupChainRelay() {
    echoContent skyBlue "\nConfigurerelaysaveclick (Relay)"
    echoContent red "\n=============================================================="
    echoContent yellow "relaysaveclick工作原arrange:"
    echoContent yellow "  upstreamsaveclick → [copy机] → downstreamsaveclick → ... → exitmouthful → 互联网"
    echoContent yellow "  copy机willcatchcollectupstreamflowmeasure并forwardtodownstream链路\n"

    # ensure sing-box Installed
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检checkyesnoalready existschain proxyConfigure
    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_inbound.json" ]] || \
       [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\nDetecttoalready existschain proxyConfigure"
        read -r -p "yesno覆cover现haveConfigure？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            return 0
        fi
    fi

    # step骤1: ImportdownstreamConfigure码
    echoContent yellow "step骤 1/3: ImportdownstreamsaveclickConfigure码"
    echoContent yellow "inviteadherepastedownstreamsaveclick（exitmouthfulorotherrelay）的Configure码:"
    read -r -p "Configure码:" downstreamCode

    if [[ -z "${downstreamCode}" ]]; then
        echoContent red " ---> Configure码不canasempty"
        return 1
    fi

    # unlock析downstreamConfigure码
    if ! parseChainCode "${downstreamCode}"; then
        return 1
    fi

    # chainHops 现atincludedownstreamallsaveclick

    # step骤2: Configurecopy机监listen
    echoContent yellow "\nstep骤 2/3: Configurecopy机监listenport"

    # Generaterandomport (10000-60000)
    local chainPort
    chainPort=$((RANDOM % 50000 + 10000))
    echoContent yellow "Please entercopy机chain proxyport [return车makeuserandomport: ${chainPort}]"
    read -r -p "port:" inputPort
    if [[ -n "${inputPort}" ]]; then
        if [[ ! "${inputPort}" =~ ^[0-9]+$ ]] || [[ "${inputPort}" -lt 1 ]] || [[ "${inputPort}" -gt 65535 ]]; then
            echoContent red " ---> port格styleError"
            return 1
        fi
        chainPort=${inputPort}
    fi

    # Generatekey
    local chainKey
    chainKey=$(generateChainKey)
    local chainMethod="2022-blake3-aes-128-gcm"

    # Get public IP
    local publicIP
    publicIP=$(getChainPublicIP)
    if [[ -z "${publicIP}" ]]; then
        echoContent yellow "\ncannot自moveGetpublic IP，invite手moveInput"
        read -r -p "public IP:" publicIP
        if [[ -z "${publicIP}" ]]; then
            echoContent red " ---> IP不canasempty"
            return 1
        fi
    fi
    echoContent green " ---> copy机public IP: ${publicIP}"

    # step骤3: GenerateConfigure
    echoContent yellow "\nstep骤 3/3: GenerateConfigure..."

    # CreateinboundConfigure (catchcollectupstreamflowmeasure)
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_inbound.json
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

    # CreateoutboundConfigure (detour chain todownstream)
    # 根据 chainHops Generate detour 链
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

        # firstjumpdirect，back续jumppassfront一jump
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

    # lastAdd chain_outbound 作as最终outbound
    local finalHopTag="chain_hop_${hopCount}"
    outboundsJson+=",
        {
            \"type\": \"direct\",
            \"tag\": \"chain_outbound\",
            \"detour\": \"${finalHopTag}\"
        }
    ]"

    echo "{\"outbounds\": ${outboundsJson}}" | jq . > /etc/v2ray-agent/sing-box/conf/config/chain_outbound.json

    # Create路byConfigure
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_route.json
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

    # 构buildnew的 hops countgroup (copy机 + downstreamallsaveclick)
    local newHops
    newHops=$(jq -n --arg ip "${publicIP}" --argjson port "${chainPort}" \
        --arg key "${chainKey}" --arg method "${chainMethod}" \
        --argjson downstream "${chainHops}" \
        '[{ip: $ip, port: $port, key: $key, method: $method}] + $downstream')

    # SaveConfigure信息
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/chain_relay_info.json
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

    # openputfirewallport
    allowPort "${chainPort}" "tcp"
    echoContent green " ---> 已openputport ${chainPort}"

    # combine并Configure并Restart
    mergeSingBoxConfig
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # VerifyStarted successfully
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box StartFailed"
        echoContent yellow "invite手move执line: /etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json"
        return 1
    fi

    # Generate V2 Configure码
    local newChainCode
    newChainCode="chain://v2@$(echo -n "${newHops}" | base64 | tr -d '\n')"

    echoContent green "\n=============================================================="
    echoContent green "relaysaveclickConfigureComplete！"
    echoContent green "=============================================================="
    echoContent yellow "\ncurrent链路 (${chainHopCount} + 1 = $((chainHopCount + 1)) jump):"
    echoContent green "  upstream → copy机(${publicIP}:${chainPort})"

    i=1
    while [[ $i -le ${chainHopCount} ]]; do
        local hopIP hopPort
        hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
        if [[ $i -eq ${chainHopCount} ]]; then
            echoContent green "        → exitmouthful(${hopIP}:${hopPort}) → 互联网"
        else
            echoContent green "        → relay${i}(${hopIP}:${hopPort})"
        fi
        ((i++))
    done

    echoContent yellow "\nConfigure码 (供upstream入mouthfulorrelaysaveclickmakeuse):\n"
    echoContent skyBlue "${newChainCode}"

    echoContent red "\ninvite妥善protectmanageConfigure码，cut勿泄露！"
}

# Configureentry node - multi-hop mode
# makeuseglobal变measure chainHops (by parseChainCode Set)
setupChainEntryMultiHop() {
    local chainBridgePort=31111  # sing-box SOCKS5 桥catchport

    # ensure sing-box Installed
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检checkyesnoalready existschain proxyConfigure
    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\nDetecttoalready existschain proxyConfigure"
        read -r -p "yesno覆cover现haveConfigure？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            return 0
        fi
    fi

    echoContent yellow "\npositiveatConfigureentry node (multi-hop mode, ${chainHopCount}jump)..."

    # Detectyesnohave Xray proxyprotocolattransportline
    local hasXrayProtocols=false
    if [[ -f "/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]] || \
       [[ -f "/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" ]] || \
       [[ -f "/etc/v2ray-agent/xray/conf/04_trojan_TCP_inbounds.json" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> Detectto Xray proxyprotocol，will同时Configure Xray chain forwarding"
    fi

    # ============= sing-box Configure =============

    # CreatemanyjumpoutboundConfigure (detour chain)
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

        # firstjumpdirect，back续jumppassfront一jump (detour)
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

    # lastAdd chain_outbound 作as最终outbound
    local finalHopTag="chain_hop_${hopCount}"
    outboundsJson+=",
        {
            \"type\": \"direct\",
            \"tag\": \"chain_outbound\",
            \"detour\": \"${finalHopTag}\"
        }
    ]"

    echo "{\"outbounds\": ${outboundsJson}}" | jq . > /etc/v2ray-agent/sing-box/conf/config/chain_outbound.json

    # 如果have Xray proxyprotocol，Create SOCKS5 桥catchinbound
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_bridge_inbound.json
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
        # 路by：桥catchinboundflowmeasurewalk链styleoutbound
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_route.json
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
        # 没have Xray，straightcatchSet final
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "final": "chain_outbound"
    }
}
EOF
    fi

    # SaveConfigure信息
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/chain_entry_info.json
{
    "role": "entry",
    "mode": "multi_hop",
    "hop_count": ${chainHopCount},
    "hops": ${chainHops},
    "bridge_port": ${chainBridgePort},
    "has_xray": ${hasXrayProtocols}
}
EOF

    # combine并 sing-box Configure
    echoContent yellow "positiveatcombine并 sing-box Configure..."
    if ! /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ 2>/dev/null; then
        echoContent red " ---> sing-box Configurecombine并Failed"
        echoContent yellow "adjusttry命令: /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/"
        return 1
    fi

    # VerifyConfigurefile已Generate
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/config.json" ]]; then
        echoContent red " ---> sing-box ConfigurefileGenerateFailed"
        return 1
    fi

    # Start sing-box
    echoContent yellow "positiveatStart sing-box..."
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # Verify sing-box Started successfully
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box StartFailed"
        echoContent yellow "invite手move执line: /etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json"
        return 1
    fi
    echoContent green " ---> sing-box Started successfully"

    # ============= Xray Configure (如果exists) =============
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "positiveatConfigure Xray chain forwarding..."

        # Create Xray SOCKS5 outbound (pointtoward sing-box 桥catch)
        cat <<EOF >/etc/v2ray-agent/xray/conf/chain_outbound.json
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

        # Backup原路byConfigure
        if [[ -f "/etc/v2ray-agent/xray/conf/09_routing.json" ]]; then
            cp /etc/v2ray-agent/xray/conf/09_routing.json /etc/v2ray-agent/xray/conf/09_routing.json.bak.chain
        fi

        # Createnew的路byConfigure
        cat <<EOF >/etc/v2ray-agent/xray/conf/09_routing.json
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

        # Restart Xray
        echoContent yellow "positiveatRestart Xray..."
        handleXray stop >/dev/null 2>&1
        handleXray start

        sleep 1
        if pgrep -f "xray/xray" >/dev/null 2>&1; then
            echoContent green " ---> Xray Restarted successfully，chain forwardingEnabled"
        else
            echoContent red " ---> Xray RestartFailed"
            echoContent yellow "invite检checkConfigure: /etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf"
            return 1
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green "entry nodeConfigureComplete！(multi-hop mode)"
    echoContent green "=============================================================="

    # 显示链路
    echoContent yellow "\ncurrent链路 (${chainHopCount} jump):"
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent green "  client → Xray → sing-box"
    else
        echoContent green "  client → sing-box"
    fi

    i=1
    while [[ $i -le ${chainHopCount} ]]; do
        local hopIP hopPort
        hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
        if [[ $i -eq ${chainHopCount} ]]; then
            echoContent green "           → exitmouthful(${hopIP}:${hopPort}) → 互联网"
        else
            echoContent green "           → relay${i}(${hopIP}:${hopPort})"
        fi
        ((i++))
    done

    # 自moveTestconnectthrough性
    echoContent yellow "\npositiveatTest链路connectthrough性..."
    sleep 2
    testChainConnection
}

# Configureentry node (单jump模style，towardbackcompatible)
setupChainEntry() {
    local exitIP=$1
    local exitPort=$2
    local exitKey=$3
    local exitMethod=$4
    local chainBridgePort=31111  # sing-box SOCKS5 桥catchport

    # ensure sing-box Installed
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检checkyesnoalready existschain proxyoutbound
    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\nDetecttoalready existschain proxyConfigure"
        read -r -p "yesno覆cover现haveConfigure？[y/n]:" confirmOverwrite
        if [[ "${confirmOverwrite}" != "y" ]]; then
            return 0
        fi
    fi

    echoContent yellow "\npositiveatConfigureentry node..."

    # Detectyesnohave Xray proxyprotocolattransportline
    local hasXrayProtocols=false
    if [[ -f "/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]] || \
       [[ -f "/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" ]] || \
       [[ -f "/etc/v2ray-agent/xray/conf/04_trojan_TCP_inbounds.json" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> Detectto Xray proxyprotocol，will同时Configure Xray chain forwarding"
    fi

    # ============= sing-box Configure =============

    # Create Shadowsocks outbound (toexit node)
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_outbound.json
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

    # 如果have Xray proxyprotocol，Create SOCKS5 桥catchinbound
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_bridge_inbound.json
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
        # 路by：桥catchinboundflowmeasurewalk链styleoutbound
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_route.json
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
        # 没have Xray，straightcatchSet final
        cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/chain_route.json
{
    "route": {
        "final": "chain_outbound"
    }
}
EOF
    fi

    # SaveConfigure信息
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/chain_entry_info.json
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

    # combine并 sing-box Configure
    echoContent yellow "positiveatcombine并 sing-box Configure..."
    if ! /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ 2>/dev/null; then
        echoContent red " ---> sing-box Configurecombine并Failed"
        echoContent yellow "adjusttry命令: /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/"
        return 1
    fi

    # VerifyConfigurefile已Generate
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/config.json" ]]; then
        echoContent red " ---> sing-box ConfigurefileGenerateFailed"
        return 1
    fi

    # Start sing-box
    echoContent yellow "positiveatStart sing-box..."
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # Verify sing-box Started successfully
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box StartFailed"
        echoContent yellow "invite手move执line: /etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json"
        return 1
    fi
    echoContent green " ---> sing-box Started successfully"

    # ============= Xray Configure (如果exists) =============
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "positiveatConfigure Xray chain forwarding..."

        # Create Xray SOCKS5 outbound (pointtoward sing-box 桥catch)
        cat <<EOF >/etc/v2ray-agent/xray/conf/chain_outbound.json
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

        # Modify Xray 路by，letflowmeasurewalkchain proxy
        # Backup原路byConfigure
        if [[ -f "/etc/v2ray-agent/xray/conf/09_routing.json" ]]; then
            cp /etc/v2ray-agent/xray/conf/09_routing.json /etc/v2ray-agent/xray/conf/09_routing.json.bak.chain
        fi

        # Createnew的路byConfigure，defaultoutboundchangeas chain_proxy
        cat <<EOF >/etc/v2ray-agent/xray/conf/09_routing.json
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

        # Restart Xray
        echoContent yellow "positiveatRestart Xray..."
        handleXray stop >/dev/null 2>&1
        handleXray start

        sleep 1
        if pgrep -f "xray/xray" >/dev/null 2>&1; then
            echoContent green " ---> Xray Restarted successfully，chain forwardingEnabled"
        else
            echoContent red " ---> Xray RestartFailed"
            echoContent yellow "invite检checkConfigure: /etc/v2ray-agent/xray/xray run -confdir /etc/v2ray-agent/xray/conf"
            return 1
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green "entry nodeConfigureComplete！"
    echoContent green "=============================================================="
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "flowmeasurepath: client → Xray → sing-box → exit node"
    else
        echoContent yellow "flowmeasurepath: client → sing-box → exit node"
    fi

    # 自moveTestconnectthrough性
    echoContent yellow "\npositiveatTest链路connectthrough性..."
    sleep 2
    testChainConnection
}

# View链路status
showChainStatus() {
    echoContent skyBlue "\nchain proxystatus"
    echoContent red "\n=============================================================="

    local role="未Configure"
    local exitIP=""
    local exitPort=""
    local status="❌ 未Configure"

    # 检checkyesnoasexit node
    if [[ -f "/etc/v2ray-agent/sing-box/conf/chain_exit_info.json" ]]; then
        role="exit node (Exit)"
        local ip port
        ip=$(jq -r '.ip' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
        port=$(jq -r '.port' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
        local allowedIP
        allowedIP=$(jq -r '.allowed_ip' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)

        # 检check sing-box yesnotransportline
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ Running"
        else
            status="❌ Not running"
        fi

        echoContent green "╔══════════════════════════════════════════════════════════════╗"
        echoContent green "║                      chain proxystatus                              ║"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  currentcorner色: ${role}"
        echoContent yellow "  监listenport: ${port}"
        echoContent yellow "  copy机IP: ${ip}"
        echoContent yellow "  allowconnection: ${allowedIP:-allIP}"
        echoContent yellow "  transportlinestatus: ${status}"
        echoContent green "╚══════════════════════════════════════════════════════════════╝"

        # 显示Configure码
        showExistingChainCode

    # 检checkyesnoasrelaysaveclick
    elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_relay_info.json" ]]; then
        role="relaysaveclick (Relay)"
        local ip port totalHops
        ip=$(jq -r '.ip' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
        port=$(jq -r '.port' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
        totalHops=$(jq -r '.total_hops' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
        local downstreamHops
        downstreamHops=$(jq -r '.downstream_hops' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)

        # 检check sing-box yesnotransportline
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ Running"
        else
            status="❌ Not running"
        fi

        echoContent green "╔══════════════════════════════════════════════════════════════╗"
        echoContent green "║                      chain proxystatus                              ║"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  currentcorner色: ${role}"
        echoContent yellow "  监listenport: ${port}"
        echoContent yellow "  copy机IP: ${ip}"
        echoContent yellow "  链路总jumpcount: ${totalHops}"
        echoContent yellow "  transportlinestatus: ${status}"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  downstream链路:"

        local i=0
        local hopCount
        hopCount=$(echo "${downstreamHops}" | jq 'length')
        while [[ $i -lt ${hopCount} ]]; do
            local hopIP hopPort
            hopIP=$(echo "${downstreamHops}" | jq -r ".[$i].ip")
            hopPort=$(echo "${downstreamHops}" | jq -r ".[$i].port")
            if [[ $i -eq $((hopCount - 1)) ]]; then
                echoContent yellow "    → exitmouthful(${hopIP}:${hopPort}) → 互联网"
            else
                echoContent yellow "    → relay$((i+1))(${hopIP}:${hopPort})"
            fi
            ((i++))
        done
        echoContent green "╚══════════════════════════════════════════════════════════════╝"

        # 显示Configure码
        showRelayChainCode

    # 检checkyesnoasentry node
    elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_entry_info.json" ]]; then
        local mode
        mode=$(jq -r '.mode // "single_hop"' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)

        # 检check sing-box yesnotransportline
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ Running"
        else
            status="❌ Not running"
        fi

        if [[ "${mode}" == "multi_hop" ]]; then
            role="entry node (Entry) - multi-hop mode"
            local hopCount hops
            hopCount=$(jq -r '.hop_count' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)
            hops=$(jq -r '.hops' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)

            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      chain proxystatus                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  currentcorner色: ${role}"
            echoContent yellow "  链路jumpcount: ${hopCount}"
            echoContent yellow "  transportlinestatus: ${status}"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  链路详feeling:"

            local i=0
            while [[ $i -lt ${hopCount} ]]; do
                local hopIP hopPort
                hopIP=$(echo "${hops}" | jq -r ".[$i].ip")
                hopPort=$(echo "${hops}" | jq -r ".[$i].port")
                if [[ $i -eq $((hopCount - 1)) ]]; then
                    echoContent yellow "    → exitmouthful(${hopIP}:${hopPort}) → 互联网"
                else
                    echoContent yellow "    → relay$((i+1))(${hopIP}:${hopPort})"
                fi
                ((i++))
            done
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        else
            role="entry node (Entry)"
            exitIP=$(jq -r '.exit_ip' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)
            exitPort=$(jq -r '.exit_port' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)

            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      chain proxystatus                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  currentcorner色: ${role}"
            echoContent yellow "  exitmouthfuladdress: ${exitIP}:${exitPort}"
            echoContent yellow "  transportlinestatus: ${status}"
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        fi

    else
        echoContent yellow "未Configurechain proxy"
        echoContent yellow "invitemakeuse 'fast速Configuretowardguide' enterlineConfigure"
    fi
}

# 显示relaysaveclickConfigure码
showRelayChainCode() {
    if [[ ! -f "/etc/v2ray-agent/sing-box/conf/chain_relay_info.json" ]]; then
        echoContent red " ---> 未findtorelaysaveclickConfigure信息"
        return 1
    fi

    local publicIP port method password downstreamHops
    publicIP=$(jq -r '.ip' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
    port=$(jq -r '.port' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
    method=$(jq -r '.method' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
    password=$(jq -r '.password' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
    downstreamHops=$(jq -r '.downstream_hops' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)

    # 构buildnew的 hops countgroup (copy机 + downstreamallsaveclick)
    local newHops
    newHops=$(jq -n --arg ip "${publicIP}" --argjson port "${port}" \
        --arg key "${password}" --arg method "${method}" \
        --argjson downstream "${downstreamHops}" \
        '[{ip: $ip, port: $port, key: $key, method: $method}] + $downstream')

    local chainCode
    chainCode="chain://v2@$(echo -n "${newHops}" | base64 | tr -d '\n')"

    echoContent yellow "\nConfigure码 (供upstream入mouthfulorrelaysaveclickmakeuse):\n"
    echoContent skyBlue "${chainCode}"
}

# Test链路connectthrough性
testChainConnection() {
    echoContent skyBlue "\nTest链路connectthrough性"
    echoContent red "\n=============================================================="

    # 确decidesaveclickcorner色并Getfirstjump信息
    local firstHopIP=""
    local firstHopPort=""
    local role=""

    if [[ -f "/etc/v2ray-agent/sing-box/conf/chain_entry_info.json" ]]; then
        role="entry"
        local mode
        mode=$(jq -r '.mode // "single_hop"' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)

        if [[ "${mode}" == "multi_hop" ]]; then
            # multi-hop mode，Getfirstjump
            firstHopIP=$(jq -r '.hops[0].ip' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)
            firstHopPort=$(jq -r '.hops[0].port' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)
        else
            # 单jump模style
            firstHopIP=$(jq -r '.exit_ip' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)
            firstHopPort=$(jq -r '.exit_port' /etc/v2ray-agent/sing-box/conf/chain_entry_info.json)
        fi

    elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_relay_info.json" ]]; then
        role="relay"
        # relaysaveclickGetdownstreamfirstjump
        firstHopIP=$(jq -r '.downstream_hops[0].ip' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)
        firstHopPort=$(jq -r '.downstream_hops[0].port' /etc/v2ray-agent/sing-box/conf/chain_relay_info.json)

    elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_exit_info.json" ]]; then
        role="exit"
        echoContent yellow "currentasexit node，no needTest链路"
        echoContent yellow "inviteatentry nodeTestconnectthrough性"

        # Testexit node自身network
        echoContent yellow "\nTestexit nodenetwork..."
        local testIP
        testIP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null)
        if [[ -n "${testIP}" ]]; then
            echoContent green "✅ exit nodenetworknormal"
            echoContent green "   exitmouthfulIP: ${testIP}"
        else
            echoContent red "❌ exit nodenetworkabnormal"
        fi
        return 0
    else
        echoContent red " ---> 未Configurechain proxy"
        return 1
    fi

    echoContent yellow "firstjumpsaveclick: ${firstHopIP}:${firstHopPort}\n"

    # Test1: TCPportconnectthrough性 (tofirstjump)
    echoContent yellow "Test1: TCPportconnectthrough性..."
    if nc -zv -w 5 "${firstHopIP}" "${firstHopPort}" >/dev/null 2>&1; then
        echoContent green "  ✅ TCPportconnectthrough (${firstHopIP}:${firstHopPort})"
    else
        echoContent red "  ❌ TCPport不through"
        echoContent red "  invite检check:"
        echoContent red "  1. 目标saveclickfirewallyesnoopenputport ${firstHopPort}"
        echoContent red "  2. 目标saveclick sing-box yesnotransportline"
        echoContent red "  3. IPaddressyesnocorrect"
        return 1
    fi

    # Test2: pass链路访askoutside网
    echoContent yellow "Test2: 链路forwardTest..."

    # 检check sing-box yesnotransportline
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red "  ❌ sing-box Not running"
        return 1
    fi

    # pass链路GetexitmouthfulIP
    sleep 1
    local outIP
    outIP=$(curl -s --connect-timeout 10 https://api.ipify.org 2>/dev/null)

    if [[ -n "${outIP}" ]]; then
        echoContent green "  ✅ 链路forwardnormal"
        echoContent green "  exitmouthfulIP: ${outIP}"

        # Test延迟
        local startTime endTime latency
        startTime=$(date +%s%N)
        curl -s --connect-timeout 5 https://www.google.com >/dev/null 2>&1
        endTime=$(date +%s%N)
        latency=$(( (endTime - startTime) / 1000000 ))
        echoContent green "  延迟: ${latency}ms"
    else
        echoContent red "  ❌ 链路forwardFailed"
        echoContent red "  invite检check各saveclickConfigureandnetwork"
        return 1
    fi

    echoContent green "\n=============================================================="
    echoContent green "链路Testpass！"
    echoContent green "=============================================================="
}

# highlevelSet
chainProxyAdvanced() {
    echoContent skyBlue "\nchain proxyhighlevelSet"
    echoContent red "\n=============================================================="

    echoContent yellow "1.显示Configure码 (exitmouthful/relaysaveclick)"
    echoContent yellow "2.Updatekey"
    echoContent yellow "3.Modifyport"
    echoContent yellow "4.View详thinConfigure"

    read -r -p "Please select:" selectType

    case ${selectType} in
    1)
        if [[ -f "/etc/v2ray-agent/sing-box/conf/chain_exit_info.json" ]]; then
            showExistingChainCode
        elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_relay_info.json" ]]; then
            showRelayChainCode
        else
            echoContent red " ---> current不yesexitmouthfulorrelaysaveclick"
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

# Updatekey
updateChainKey() {
    echoContent yellow "\nUpdatechain proxykey"

    if [[ -f "/etc/v2ray-agent/sing-box/conf/chain_exit_info.json" ]]; then
        # exit node
        local port method
        port=$(jq -r '.port' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
        method=$(jq -r '.method' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)
        local publicIP
        publicIP=$(jq -r '.ip' /etc/v2ray-agent/sing-box/conf/chain_exit_info.json)

        # Generatenewkey
        local newKey
        newKey=$(generateChainKey)

        # UpdateinboundConfigure
        jq --arg key "${newKey}" '.inbounds[0].password = $key' \
            /etc/v2ray-agent/sing-box/conf/config/chain_inbound.json > /tmp/chain_inbound.json
        mv /tmp/chain_inbound.json /etc/v2ray-agent/sing-box/conf/config/chain_inbound.json

        # Update信息file
        jq --arg key "${newKey}" '.password = $key' \
            /etc/v2ray-agent/sing-box/conf/chain_exit_info.json > /tmp/chain_exit_info.json
        mv /tmp/chain_exit_info.json /etc/v2ray-agent/sing-box/conf/chain_exit_info.json

        mergeSingBoxConfig
        reloadCore

        echoContent green " ---> key已Update"
        echoContent yellow "\nnewConfigure码:\n"
        local chainCode
        chainCode="chain://ss2022@${publicIP}:${port}?key=$(echo -n "${newKey}" | base64 | tr -d '\n')&method=${method}"
        echoContent skyBlue "${chainCode}"
        echoContent red "\ninviteUpdateentry nodeConfigure！"

    elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_entry_info.json" ]]; then
        echoContent red " ---> entry nodeinvitefromexit nodeGetnewConfigure码backheavynewConfigure"
    else
        echoContent red " ---> 未Configurechain proxy"
    fi
}

# Updateport
updateChainPort() {
    echoContent yellow "\nUpdatechain proxyport"

    local infoFile=""
    if [[ -f "/etc/v2ray-agent/sing-box/conf/chain_exit_info.json" ]]; then
        infoFile="/etc/v2ray-agent/sing-box/conf/chain_exit_info.json"
    elif [[ -f "/etc/v2ray-agent/sing-box/conf/chain_relay_info.json" ]]; then
        infoFile="/etc/v2ray-agent/sing-box/conf/chain_relay_info.json"
    else
        echoContent red " ---> 仅exitmouthfulorrelaysaveclickmayModifyport"
        return 1
    fi

    local oldPort
    oldPort=$(jq -r '.port' "${infoFile}")

    read -r -p "newport [current: ${oldPort}]:" newPort
    if [[ -z "${newPort}" ]]; then
        return 0
    fi

    if [[ ! "${newPort}" =~ ^[0-9]+$ ]] || [[ "${newPort}" -lt 1 ]] || [[ "${newPort}" -gt 65535 ]]; then
        echoContent red " ---> port格styleError"
        return 1
    fi

    # UpdateinboundConfigure
    jq --argjson port "${newPort}" '.inbounds[0].listen_port = $port' \
        /etc/v2ray-agent/sing-box/conf/config/chain_inbound.json > /tmp/chain_inbound.json
    mv /tmp/chain_inbound.json /etc/v2ray-agent/sing-box/conf/config/chain_inbound.json

    # Update信息file
    jq --argjson port "${newPort}" '.port = $port' \
        "${infoFile}" > /tmp/chain_info_temp.json
    mv /tmp/chain_info_temp.json "${infoFile}"

    # Updatefirewall
    allowPort "${newPort}" "tcp"

    mergeSingBoxConfig
    reloadCore

    echoContent green " ---> port已Updateas ${newPort}"

    # 显示相respond的Configure码
    if [[ "${infoFile}" == *"exit"* ]]; then
        showExistingChainCode
    else
        showRelayChainCode
    fi
    echoContent red "\ninviteUpdateupstreamsaveclickConfigure！"
}

# 显示详thinConfigure
showChainDetailConfig() {
    echoContent skyBlue "\nchain proxy详thinConfigure"
    echoContent red "\n=============================================================="

    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_inbound.json" ]]; then
        echoContent yellow "\ninboundConfigure (chain_inbound.json):"
        jq . /etc/v2ray-agent/sing-box/conf/config/chain_inbound.json
    fi

    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_outbound.json" ]]; then
        echoContent yellow "\noutboundConfigure (chain_outbound.json):"
        jq . /etc/v2ray-agent/sing-box/conf/config/chain_outbound.json
    fi

    if [[ -f "/etc/v2ray-agent/sing-box/conf/config/chain_route.json" ]]; then
        echoContent yellow "\n路byConfigure (chain_route.json):"
        jq . /etc/v2ray-agent/sing-box/conf/config/chain_route.json
    fi
}

# Uninstallchain proxy
removeChainProxy() {
    echoContent skyBlue "\nUninstallchain proxy"
    echoContent red "\n=============================================================="

    read -r -p "ConfirmUninstallchain proxy？[y/n]:" confirmRemove
    if [[ "${confirmRemove}" != "y" ]]; then
        return 0
    fi

    # Delete sing-box Configurefile
    rm -f /etc/v2ray-agent/sing-box/conf/config/chain_inbound.json
    rm -f /etc/v2ray-agent/sing-box/conf/config/chain_outbound.json
    rm -f /etc/v2ray-agent/sing-box/conf/config/chain_route.json
    rm -f /etc/v2ray-agent/sing-box/conf/config/chain_bridge_inbound.json
    rm -f /etc/v2ray-agent/sing-box/conf/chain_exit_info.json
    rm -f /etc/v2ray-agent/sing-box/conf/chain_entry_info.json
    rm -f /etc/v2ray-agent/sing-box/conf/chain_relay_info.json

    # Delete Xray chain proxyConfigure
    if [[ -f "/etc/v2ray-agent/xray/conf/chain_outbound.json" ]]; then
        rm -f /etc/v2ray-agent/xray/conf/chain_outbound.json
        echoContent yellow " ---> 已Delete Xray 链styleoutboundConfigure"

        # Restore原路byConfigure
        if [[ -f "/etc/v2ray-agent/xray/conf/09_routing.json.bak.chain" ]]; then
            mv /etc/v2ray-agent/xray/conf/09_routing.json.bak.chain /etc/v2ray-agent/xray/conf/09_routing.json
            echoContent yellow " ---> 已Restore Xray 原路byConfigure"
        else
            # 如果没haveBackup，Createdefault路byConfigure
            cat <<EOF >/etc/v2ray-agent/xray/conf/09_routing.json
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
            echoContent yellow " ---> 已Reset Xray 路byConfigureasdefault"
        fi

        # Restart Xray
        handleXray stop >/dev/null 2>&1
        handleXray start
    fi

    # heavynewcombine并 sing-box Configure
    mergeSingBoxConfig
    reloadCore

    echoContent green " ---> chain proxy已Uninstall"
}

# combine并 sing-box Configure (如果函countdoes not exist则decide义)
# focus意：此函countwith singBoxMergeConfig protect持一致，useinchain proxy独立transportlinescenescene
if ! type mergeSingBoxConfig >/dev/null 2>&1; then
    mergeSingBoxConfig() {
        if [[ -d "/etc/v2ray-agent/sing-box/conf/config/" ]]; then
            # 先DeleteoldConfigure，再combine并GeneratenewConfigure
            rm -f /etc/v2ray-agent/sing-box/conf/config.json >/dev/null 2>&1
            # makeuse sing-box combine并Configure（with singBoxMergeConfig protect持一致）
            if [[ -f "/etc/v2ray-agent/sing-box/sing-box" ]]; then
                /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ >/dev/null 2>&1
            fi
        fi
    }
fi

# ======================= chain proxy功canEnd =======================

# routingtool
routingToolsMenu() {
    echoContent skyBlue "\n功can 1/${totalProgress} : routingtool"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项"
    echoContent yellow "# useinserver的flowmeasurerouting，availableinunlockChatGPT、streaming等relatedinside容\n"

    echoContent yellow "1.WARProuting【第三square IPv4】"
    echoContent yellow "2.WARProuting【第三square IPv6】"
    echoContent yellow "3.IPv6routing"
    echoContent yellow "4.Socks5routing【替exchange任意categoryrouting】"
    echoContent yellow "5.DNSrouting"
    #    echoContent yellow "6.VMess+WS+TLSrouting"
    echoContent yellow "7.SNIreversetowardproxyrouting"

    read -r -p "Please select:" selectType

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
        socks5Routing
        ;;
    5)
        dnsRouting 1
        ;;
        #    6)
        #        if [[ -n "${singBoxConfigPath}" ]]; then
        #            echoContent red "\n ---> 此功cannot supportedHysteria2、Tuic"
        #        fi
        #        vmessWSRouting 1
        #        ;;
    7)
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent red "\n ---> 此功cannot supportedHysteria2、Tuic"
        fi
        sniRouting 1
        ;;
    esac

}

# VMess+WS+TLS routing
vmessWSRouting() {
    echoContent skyBlue "\n功can 1/${totalProgress} : VMess+WS+TLS routing"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项"
    echoContent yellow "# makeuseNotice：详见 documents directorymiddle的routingwith策略say明 \n"

    echoContent yellow "1.Addoutbound"
    echoContent yellow "2.Uninstall"
    read -r -p "Please select:" selectType

    case ${selectType} in
    1)
        setVMessWSRoutingOutbounds
        ;;
    2)
        removeVMessWSRouting
        ;;
    esac
}
# Socks5Configure检check
checkSocksConfig() {
    readInstallType

    if [[ -z "${singBoxConfigPath}" && -d "/etc/v2ray-agent/sing-box/conf/config/" ]]; then
        singBoxConfigPath="/etc/v2ray-agent/sing-box/conf/config/"
    fi

    echoContent skyBlue "\n功can 1/1 : Socks5Configure检check"

    if [[ -z "${singBoxConfigPath}" && "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 未DetecttoSocks5Configure，invite先Installcorresponding功can"
        exit 0
    fi

    local socksInboundFile="${singBoxConfigPath}20_socks5_inbounds.json"
    local socksOutboundFile="${singBoxConfigPath}socks5_outbound.json"
    local socksOutboundRouteFile="${singBoxConfigPath}socks5_01_outbound_route.json"
    local socksInboundRouteFile="${singBoxConfigPath}socks5_02_inbound_route.json"
    local singBoxSocksStatus=false
    local xraySocksStatus=false

    if [[ -f "${socksInboundFile}" || -f "${socksOutboundFile}" ]]; then
        singBoxSocksStatus=true
    fi

    if [[ -n "${configPath}" && -f "${configPath}socks5_outbound.json" ]]; then
        xraySocksStatus=true
    fi

    if [[ "${singBoxSocksStatus}" != "true" && "${xraySocksStatus}" != "true" ]]; then
        echoContent red " ---> 未findtoSocks5inboundoroutboundConfigurefile"
        exit 0
    fi

    # port占use检check
    if [[ -f "${socksInboundFile}" ]]; then
        local socksListenPort
        socksListenPort=$(jq -r '.inbounds[0].listen_port // empty' "${socksInboundFile}")
        if [[ -n "${socksListenPort}" ]]; then
            local portConflicts
            portConflicts=$(lsof -i "tcp:${socksListenPort}" | awk 'NR>1 && $1!="sing-box" {print}')
            if [[ -n "${portConflicts}" ]]; then
                echoContent red " ---> Socks5inboundport ${socksListenPort} 已byotherenter程占use"
                echoContent yellow " ---> repair复pointlead：Stop占useshouldport的enter程orModify ${socksInboundFile} middle的 listen_port backRestart"
            else
                echoContent green " ---> Socks5inboundport ${socksListenPort} normal"
            fi
        fi
    fi

    # 凭据及certificatepath检check
    if [[ -f "${socksInboundFile}" ]]; then
        local socksInboundUser
        local socksInboundPassword
        socksInboundUser=$(jq -r '.inbounds[0].users[0].username // empty' "${socksInboundFile}")
        socksInboundPassword=$(jq -r '.inbounds[0].users[0].password // empty' "${socksInboundFile}")

        if [[ -z "${socksInboundUser}" || -z "${socksInboundPassword}" ]]; then
            echoContent red " ---> Socks5inbound凭据missing"
            echoContent yellow " ---> repair复pointlead：at ${socksInboundFile} fillwrite username/password，orheavynew执line Socks5 inboundInstall"
        else
            echoContent green " ---> Socks5inbound凭据normal"
        fi
    fi

    if [[ -f "${socksOutboundFile}" ]]; then
        local socksOutboundUser
        local socksOutboundPassword
        socksOutboundUser=$(jq -r '.outbounds[0].username // empty' "${socksOutboundFile}")
        socksOutboundPassword=$(jq -r '.outbounds[0].password // empty' "${socksOutboundFile}")
        local socksOutboundCertPath
        local socksOutboundKeyPath
        socksOutboundCertPath=$(jq -r '.outbounds[0].tls.certificate_path // empty' "${socksOutboundFile}")
        socksOutboundKeyPath=$(jq -r '.outbounds[0].tls.key_path // empty' "${socksOutboundFile}")

        if [[ -z "${socksOutboundUser}" || -z "${socksOutboundPassword}" ]]; then
            echoContent red " ---> Socks5outbound凭据missing"
            echoContent yellow " ---> repair复pointlead：at ${socksOutboundFile} fillwrite username/password，orheavynew执line Socks5 outboundInstall"
        else
            echoContent green " ---> Socks5outbound凭据normal"
        fi

        if [[ -n "${socksOutboundCertPath}" && ! -f "${socksOutboundCertPath}" ]]; then
            echoContent red " ---> Socks5outboundcertificatepathinvalid: ${socksOutboundCertPath}"
            echoContent yellow " ---> repair复pointlead：Updatecertificatepathorup传certificatefilebackRestartservice"
        fi

        if [[ -n "${socksOutboundKeyPath}" && ! -f "${socksOutboundKeyPath}" ]]; then
            echoContent red " ---> Socks5outboundprivate keypathinvalid: ${socksOutboundKeyPath}"
            echoContent yellow " ---> repair复pointlead：Updateprivate keypathorup传private keyfilebackRestartservice"
        fi
    fi

    local outboundTags=()
    if [[ -n "${singBoxConfigPath}" ]]; then
        while read -r outboundFile; do
            while read -r outboundTag; do
                if [[ -n "${outboundTag}" && "${outboundTag}" != "null" ]]; then
                    outboundTags+=("${outboundTag}")
                fi
            done < <(jq -r '.outbounds[]?.tag // empty' "${outboundFile}" 2>/dev/null)
        done < <(find "${singBoxConfigPath}" -maxdepth 1 -type f -name "*.json")
    fi

    checkRouteTarget() {
        local routeFile=$1
        local routeName=$2
        if [[ -f "${routeFile}" ]]; then
            while read -r targetTag; do
                if [[ -z "${targetTag}" ]]; then
                    continue
                fi

                if [[ ! " ${outboundTags[*]} " =~ " ${targetTag} " ]]; then
                    echoContent red " ---> 路by ${routeName} middle的目标标签 ${targetTag} does not exist"
                    echoContent yellow " ---> repair复pointlead：heavynewInstall Socks5 routingorat ${singBoxConfigPath} insidepatch充shouldoutboundConfigure"
                fi
            done < <(jq -r '.route.rules[]?.outbound // empty' "${routeFile}" 2>/dev/null)
        fi
    }

    checkRouteTarget "${socksOutboundRouteFile}" "socks5_01_outbound_route"
    checkRouteTarget "${socksInboundRouteFile}" "socks5_02_inbound_route"

    if [[ "${coreInstallType}" == "1" ]]; then
        local xrayOutbounds=()
        if [[ -n "${configPath}" ]]; then
            while read -r outboundFile; do
                while read -r outboundTag; do
                    if [[ -n "${outboundTag}" && "${outboundTag}" != "null" ]]; then
                        xrayOutbounds+=("${outboundTag}")
                    fi
                done < <(jq -r '.outbounds[]?.tag // empty' "${outboundFile}" 2>/dev/null)
            done < <(find "${configPath}" -maxdepth 1 -type f -name "*.json")
        fi

        if [[ -f "${configPath}09_routing.json" ]]; then
            while read -r xrayTarget; do
                if [[ -z "${xrayTarget}" ]]; then
                    continue
                fi

                if [[ ! " ${xrayOutbounds[*]} " =~ " ${xrayTarget} " ]]; then
                    echoContent red " ---> Xray routing规则middle的outbound标签 ${xrayTarget} does not exist"
                    echoContent yellow " ---> repair复pointlead：检check ${configPath}${xrayTarget}.json yesnomissing，orheavynew执line Socks5 outboundConfigure"
                fi
            done < <(jq -r '.routing.rules[]?.outboundTag // empty' "${configPath}09_routing.json" 2>/dev/null)
        fi
    fi
}
# Socks5routing
socks5Routing() {
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> Not installed任意protocol，invitemakeuse 1.Install or者 2.任意groupcombineInstall enterlineInstallbackmakeuse"
        exit 0
    fi
    echoContent skyBlue "\n功can 1/${totalProgress} : Socks5routing"
    echoContent red "\n=============================================================="
    echoContent red "# focus意事项"
    echoContent yellow "# flowmeasure明text访ask"

    echoContent yellow "# 仅limitnormalnetwork环environmentdownset备间flowmeasureforward，denyuseinproxy访ask。"
    echoContent yellow "# outbound=willcopy机flowmeasure交giveupstream/landing machine；inbound=letcopy机lift供Socks供othersaveclick拨号。"
    echoContent yellow "# makeuseNotice：更many示例见 documents directory\n"

    echoContent yellow "1.Socks5outbound"
    echoContent yellow "2.Socks5inbound"
    echoContent yellow "3.Uninstall"
    echoContent yellow "4.检checkConfigure"
    read -r -p "Please select:" selectType

    case ${selectType} in
    1)
        socks5OutboundRoutingMenu
        ;;
    2)
        socks5InboundRoutingMenu
        ;;
    3)
        removeSocks5Routing
        ;;
    4)
        checkSocksConfig
        ;;
    esac
}
# Socks5inbound菜单
socks5InboundRoutingMenu() {
    readInstallType
    echoContent skyBlue "\n功can 1/1 : Socks5inbound"
    echoContent red "\n=============================================================="

    echoContent yellow "1.InstallSocks5inbound"
    echoContent yellow "2.Viewrouting规则"
    echoContent yellow "3.Addrouting规则"
    echoContent yellow "4.ViewinboundConfigure"
    read -r -p "Please select:" selectType
    case ${selectType} in
    1)
        totalProgress=1
        installSingBox 1
        installSingBoxService 1
        setSocks5Inbound
        setSocks5InboundRouting
        reloadCore
        socks5InboundRoutingMenu
        ;;
    2)
        showSingBoxRoutingRules socks5_02_inbound_route
        socks5InboundRoutingMenu
        ;;
    3)
        setSocks5InboundRouting addRules
        reloadCore
        socks5InboundRoutingMenu
        ;;
    4)
        if [[ -f "${singBoxConfigPath}20_socks5_inbounds.json" ]]; then
            echoContent yellow "\n ---> downlistinside容needConfiguretoother机器的outbound，invite不wantenterlineproxylineas\n"
            echoContent green " port：$(jq .inbounds[0].listen_port ${singBoxConfigPath}20_socks5_inbounds.json)"
            echoContent green " user名称：$(jq -r .inbounds[0].users[0].username ${singBoxConfigPath}20_socks5_inbounds.json)"
            echoContent green " userpassword：$(jq -r .inbounds[0].users[0].password ${singBoxConfigPath}20_socks5_inbounds.json)"
        else
            echoContent red " ---> Not installed相respond功can"
            socks5InboundRoutingMenu
        fi
        ;;
    esac

}

# Socks5outbound菜单
socks5OutboundRoutingMenu() {
    echoContent skyBlue "\n功can 1/1 : Socks5outbound"
    echoContent red "\n=============================================================="

    echoContent yellow "1.InstallSocks5outbound"
    echoContent yellow "2.SetSocks5globalforward"
    echoContent yellow "3.Viewrouting规则"
    echoContent yellow "4.Addrouting规则"
    read -r -p "Please select:" selectType
    case ${selectType} in
    1)
        setSocks5Outbound
        setSocks5OutboundRouting
        reloadCore
        socks5OutboundRoutingMenu
        ;;
    2)
        setSocks5Outbound
        setSocks5OutboundRoutingAll
        reloadCore
        socks5OutboundRoutingMenu
        ;;
    3)
        showSingBoxRoutingRules socks5_01_outbound_route
        showXrayRoutingRules socks5_outbound
        socks5OutboundRoutingMenu
        ;;
    4)
        setSocks5OutboundRouting addRules
        reloadCore
        socks5OutboundRoutingMenu
        ;;
    esac

}

# socks5global
setSocks5OutboundRoutingAll() {

    echoContent red "=============================================================="
    echoContent yellow "# focus意事项\n"
    echoContent yellow "1.knowDeleteall已经Set的routing规则，wrap括otherrouting（warp、IPv6等）"
    echoContent yellow "2.knowDeleteSocks5outside的alloutbound规则"
    echoContent yellow "3.allinboundflowmeasurewillpassSocks5outboundforward\n"
    read -r -p "yesnoConfirmSet？[y/n]:" socksOutStatus

    if [[ "${socksOutStatus}" == "y" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            removeXrayOutbound IPv4_out
            removeXrayOutbound IPv6_out
            removeXrayOutbound z_direct_outbound
            removeXrayOutbound blackhole_out
            removeXrayOutbound wireguard_out_IPv4
            removeXrayOutbound wireguard_out_IPv6

            rm ${configPath}09_routing.json >/dev/null 2>&1
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then

            removeSingBoxConfig IPv4_out
            removeSingBoxConfig IPv6_out

            removeSingBoxConfig wireguard_endpoints_IPv4_route
            removeSingBoxConfig wireguard_endpoints_IPv6_route
            removeSingBoxConfig wireguard_endpoints_IPv4
            removeSingBoxConfig wireguard_endpoints_IPv6

            removeSingBoxConfig socks5_01_outbound_route
            removeSingBoxConfig 01_direct_outbound

            # Createglobal路byConfigure，letallflowmeasurewalk socks5_outbound
            cat <<EOF >"${singBoxConfigPath}socks5_01_outbound_route.json"
{
  "route": {
    "final": "socks5_outbound"
  }
}
EOF
        fi

        echoContent green " ---> Socks5globaloutboundSetfinished"
    fi
}
# socks5 routing规则
showSingBoxRoutingRules() {
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}$1.json" ]]; then
            jq .route.rules "${singBoxConfigPath}$1.json"
        elif [[ "$1" == "socks5_01_outbound_route" && -f "${singBoxConfigPath}socks5_outbound.json" ]]; then
            jq .outbounds[0] "${singBoxConfigPath}socks5_outbound.json"
        elif [[ "$1" == "socks5_02_inbound_route" && -f "${singBoxConfigPath}20_socks5_inbounds.json" ]]; then
            jq .inbounds[0] "${singBoxConfigPath}20_socks5_inbounds.json"
        fi
    fi
}

# xrayinsideverifyrouting规则
showXrayRoutingRules() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            jq ".routing.rules[]|select(.outboundTag==\"$1\")" "${configPath}09_routing.json"
        elif [[ "$1" == "socks5_outbound" && -f "${configPath}socks5_outbound.json" ]]; then
            jq .outbounds[0].settings.servers[0] "${configPath}socks5_outbound.json"
        fi
    fi
}

# UninstallSocks5routing
removeSocks5Routing() {
    echoContent skyBlue "\n功can 1/1 : UninstallSocks5routing"
    echoContent red "\n=============================================================="

    echoContent yellow "1.UninstallSocks5outbound"
    echoContent yellow "2.UninstallSocks5inbound"
    echoContent yellow "3.Uninstallall"
    read -r -p "Please select:" unInstallSocks5RoutingStatus
    if [[ "${unInstallSocks5RoutingStatus}" == "1" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            removeXrayOutbound socks5_outbound
            unInstallRouting socks5_outbound outboundTag
            addXrayOutbound z_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig socks5_outbound
            removeSingBoxConfig socks5_01_outbound_route
            addSingBoxOutbound 01_direct_outbound
        fi

    elif [[ "${unInstallSocks5RoutingStatus}" == "2" ]]; then

        removeSingBoxConfig 20_socks5_inbounds
        removeSingBoxConfig socks5_02_inbound_route

        handleSingBox stop
    elif [[ "${unInstallSocks5RoutingStatus}" == "3" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            removeXrayOutbound socks5_outbound
            unInstallRouting socks5_outbound outboundTag
            addXrayOutbound z_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig socks5_outbound
            removeSingBoxConfig socks5_01_outbound_route
            removeSingBoxConfig 20_socks5_inbounds
            removeSingBoxConfig socks5_02_inbound_route
            addSingBoxOutbound 01_direct_outbound
        fi

        handleSingBox stop
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi
    echoContent green " ---> Uninstallfinished"
    reloadCore
}
# Socks5inbound
setSocks5Inbound() {

    echoContent yellow "\n==================== Configure Socks5 inbound(unlock机、landing machine) =====================\n"
    echoContent yellow "useinletcopy机lift供 Socks5 service，through常give另一台机器orinside网set备作asoutboundupstream。"
    echoContent skyBlue "\nStartConfigureSocks5protocolinboundport"
    echoContent skyBlue "shouldinboundlift供giveotherVPSorcopy机作asupstream，invite根据connectthrough性Select监listen范围"
    echoContent yellow "若仅监listeninside网or127.0.0.1，只can同机or同inside网机器访ask，跨VPS互联needSelectmaybyfor端访ask的address"
    echo
    mapfile -t result < <(initSingBoxPort "${singBoxSocks5Port}")
    local socks5InboundPort=${result[-1]}
    socks5InboundPort=$(stripAnsi "${socks5InboundPort}")
    if [[ -z "${socks5InboundPort}" || ! "${socks5InboundPort}" =~ ^[0-9]+$ ]]; then
        echoContent red " ---> portReadabnormal，please re-enter"
        exit 0
    fi
    echoContent green "\n ---> inboundSocks5port：${socks5InboundPort}"
    echoContent green "\n ---> 此portneedConfiguretoother机器outbound，invite不wantenterlineproxylineas"

    # 监listen范围Select（combine并done安completeNotice）
    echoContent yellow "\nPlease select监listen范围（will监listenchangeas 0.0.0.0/:: 时know暴露to公网，existsbysweep描and滥use风险）"
    echoContent yellow "1.仅copy机 127.0.0.1[return车default]"
    echoContent yellow "2.custominside网网section"
    echoContent yellow "3.allIPv4 0.0.0.0/0"
    read -r -p "监listen范围:" socks5InboundListenStatus
    local socks5InboundListen="127.0.0.1"
    local socks5InboundAllowRange="127.0.0.0/8"

    if [[ "${socks5InboundListenStatus}" == "2" ]]; then
        read -r -p "Please enterallow访ask的inside网网section(示例:192.168.0.0/16):" socks5InboundAllowRange
        if [[ -z "${socks5InboundAllowRange}" ]]; then
            echoContent red " ---> 网sectioncannot be empty"
            exit 0
        fi
        socks5InboundAllowRange=$(stripAnsi "${socks5InboundAllowRange}")
        socks5InboundListen="0.0.0.0"
    elif [[ "${socks5InboundListenStatus}" == "3" ]]; then
        socks5InboundListen="0.0.0.0"
        socks5InboundAllowRange="0.0.0.0/0"
    fi

    socks5InboundListen=$(stripAnsi "${socks5InboundListen}")

    # admit证squarestyleSelect
    # focus意: sing-box SOCKS 仅supportuser名/passwordadmit证，below两kind模style最终都makeuseuser名+password
    # - password: usermaydivide别Setuser名andpassword
    # - unified: user名andpasswordmakeusesame的UUID，便inremember忆andmanagearrange
    echoContent yellow "\nPlease selectadmit证squarestyle（landing machinewithupstreamneedprotect持一致）"
    echoContent yellow "1.user名/password[return车default，maycustom]"
    echoContent yellow "2.unify一key[user名andpasswordmakeusesameUUID，便inmanagearrange]"
    read -r -p "Please select:" socks5InboundAuthType

    if [[ -z "${socks5InboundAuthType}" || "${socks5InboundAuthType}" == "1" ]]; then
        socks5InboundAuthType="password"
    elif [[ "${socks5InboundAuthType}" == "2" ]]; then
        socks5InboundAuthType="unified"
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi

    echo

    echoContent yellow "\nPlease entercustomUUID[needvalid]，[return车]randomUUID"
    read -r -p 'UUID:' socks5RoutingUUID
    if [[ -z "${socks5RoutingUUID}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            socks5RoutingUUID=$(/etc/v2ray-agent/xray/xray uuid)
        elif [[ -n "${singBoxConfigPath}" ]]; then
            socks5RoutingUUID=$(/etc/v2ray-agent/sing-box/sing-box generate uuid)
        fi
    fi
    socks5RoutingUUID=$(stripAnsi "${socks5RoutingUUID}")
    echo

    if [[ "${socks5InboundAuthType}" == "unified" ]]; then
        echoContent skyBlue "unify一keyneedwithupstream一致，maystraightcatchreturn车沿useaboveUUIDorSelectother录入squarestyle"
        echoContent yellow "below\"Please select\"corresponding：1 straightcatchInput(return车defaultUUID) / 2 Readfile / 3 Read环environment变measure"
        socks5InboundUnifiedKey=$(readCredentialBySource "unify一key" "${socks5RoutingUUID}" | stripAnsi | tail -n 1)
        socks5InboundUserName="${socks5InboundUnifiedKey}"
        socks5InboundPassword="${socks5InboundUnifiedKey}"
    else
        socks5InboundUserName=$(readCredentialBySource "user名称" "${socks5RoutingUUID}" | stripAnsi | tail -n 1)
        socks5InboundPassword=$(readCredentialBySource "userpassword" "${socks5RoutingUUID}" | stripAnsi | tail -n 1)
    fi

    echoContent yellow "\nPlease selectroutingdomainDNSunlock析typemodel"
    echoContent yellow "# focus意事项：needprotect证vpssupport相respond的DNSunlock析"
    echoContent yellow "1.IPv4[return车default]"
    echoContent yellow "2.IPv6"

    read -r -p 'IPtypemodel:' socks5InboundDomainStrategyStatus
    local domainStrategy=
    if [[ -z "${socks5InboundDomainStrategyStatus}" || "${socks5InboundDomainStrategyStatus}" == "1" ]]; then
        domainStrategy="ipv4_only"
    elif [[ "${socks5InboundDomainStrategyStatus}" == "2" ]]; then
        domainStrategy="ipv6_only"
    else
        echoContent red " ---> SelecttypemodelError"
        exit 0
    fi
    socks5InboundAllowRange=$(stripAnsi "${socks5InboundAllowRange}")
    socks5InboundUserName=$(stripAnsi "${socks5InboundUserName}")
    socks5InboundPassword=$(stripAnsi "${socks5InboundPassword}")

    local socks5InboundJsonFile
    socks5InboundJsonFile=$(mktemp)
    # sing-box SOCKS inboundsupport的charactersection: listen, listen_port, tag, users, domain_strategy
    # not supported: aead (sing-box SOCKS 仅supportuser名/passwordadmit证)
    if ! jq -n \
        --arg listen "${socks5InboundListen}" \
        --argjson listenPort "${socks5InboundPort}" \
        --arg tag "socks5_inbound" \
        --arg user "${socks5InboundUserName}" \
        --arg pass "${socks5InboundPassword}" \
        --arg domainStrategy "${domainStrategy}" '
        {
          inbounds: [
            {
              type: "socks",
              listen: $listen,
              listen_port: $listenPort,
              tag: $tag,
              users: [
                {
                  username: $user,
                  password: $pass
                }
              ],
              domain_strategy: $domainStrategy
            }
          ]
        }
    ' >"${socks5InboundJsonFile}"; then
        rm -f "${socks5InboundJsonFile}"
        echoContent red " ---> Generate Socks5 inboundConfigureFailed，invite检checkInput"
        exit 0
    fi

    mv "${socks5InboundJsonFile}" /etc/v2ray-agent/sing-box/conf/config/20_socks5_inbounds.json

    validateJsonFile "/etc/v2ray-agent/sing-box/conf/config/20_socks5_inbounds.json"

    if [[ "${socks5InboundListen}" != "127.0.0.1" ]]; then
        allowPort "${socks5InboundPort}" tcp "${socks5InboundAllowRange}"
    fi

}

# 初始化sing-box ruleConfigure
initSingBoxRules() {
    local domainRules=[]
    local ruleSet=[]
    while read -r line; do
        local geositeStatus
        geositeStatus=$(curl -s "https://api.github.com/repos/SagerNet/sing-geosite/contents/geosite-${line}.srs?ref=rule-set" | jq .message)

        if [[ "${geositeStatus}" == "null" ]]; then
            ruleSet=$(echo "${ruleSet}" | jq -r ". += [{\"tag\":\"${line}_$2\",\"type\":\"remote\",\"format\":\"binary\",\"url\":\"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${line}.srs\",\"download_detour\":\"01_direct_outbound\"}]")
        else
            domainRules=$(echo "${domainRules}" | jq -r ". += [\"^([a-zA-Z0-9_-]+\\\.)*${line//./\\\\.}\"]")
        fi
    done < <(echo "$1" | tr ',' '\n' | grep -v '^$' | sort -n | uniq | paste -sd ',' | tr ',' '\n')
    echo "{ \"domainRules\":${domainRules},\"ruleSet\":${ruleSet}}"
}

# socks5 inbound routing规则
setSocks5InboundRouting() {

    singBoxConfigPath=/etc/v2ray-agent/sing-box/conf/config/

    if [[ "$1" == "addRules" && ! -f "${singBoxConfigPath}socks5_02_inbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        echoContent red " ---> inviteInstallinboundroutingback再Addrouting规则"
        echoContent red " ---> 如已Selectallowall网stand，inviteheavynewInstallroutingbackSet规则"
        exit 0
    fi
    local socks5InboundRoutingIPs=
    if [[ "$1" == "addRules" ]]; then
        socks5InboundRoutingIPs=$(jq .route.rules[0].source_ip_cidr "${singBoxConfigPath}socks5_02_inbound_route.json")
    else
        echoContent red "=============================================================="
        echoContent skyBlue "Please enterallow访ask的IPaddress，many个IP英text逗号隔open。例如:1.1.1.1,2.2.2.2\n"
        echoContent yellow "仅allow这些come源访askcopy机 Socks5 inbound，未listexitcome源willbyreject。"
        read -r -p "IP:" socks5InboundRoutingIPs

        if [[ -z "${socks5InboundRoutingIPs}" ]]; then
            echoContent red " ---> IPcannot be empty"
            exit 0
        fi
        socks5InboundRoutingIPs=$(echo "\"${socks5InboundRoutingIPs}"\" | jq -c '.|split(",")')
    fi

    echoContent red "=============================================================="
    echoContent skyBlue "Please enterwantrouting的domain\n"
    echoContent yellow "supportXray-core geositematch，supportsing-box1.8+ rule_setmatch\n"
    echoContent yellow "not增measureAdd，know替exchange原have规则\n"
    echoContent yellow "shouldInput的规则matchtogeositeor者rule_setbackknowmakeuse相respond的规则\n"
    echoContent yellow "如cannotmatch则，则makeusedomain精确match\n"

    read -r -p "yesnoallowall网stand？Please select[y/n]:" socks5InboundRoutingDomainStatus
    if [[ "${socks5InboundRoutingDomainStatus}" == "y" ]]; then
        addSingBoxRouteRule "01_direct_outbound" "" "socks5_02_inbound_route"
        local route=
        route=$(jq ".route.rules[0].inbound = [\"socks5_inbound\"]" "${singBoxConfigPath}socks5_02_inbound_route.json")
        route=$(echo "${route}" | jq ".route.rules[0].source_ip_cidr=${socks5InboundRoutingIPs}")
        echo "${route}" | jq . >"${singBoxConfigPath}socks5_02_inbound_route.json"

        addSingBoxOutbound block
        addSingBoxOutbound "01_direct_outbound"
    else
        echoContent yellow "录入示例:netflix,openai,example.com\n"
        read -r -p "domain:" socks5InboundRoutingDomain
        if [[ -z "${socks5InboundRoutingDomain}" ]]; then
            echoContent red " ---> domaincannot be empty"
            exit 0
        fi
        socks5InboundRoutingDomain=$(stripAnsi "${socks5InboundRoutingDomain}")
        addSingBoxRouteRule "01_direct_outbound" "${socks5InboundRoutingDomain}" "socks5_02_inbound_route"
        local route=
        route=$(jq ".route.rules[0].inbound = [\"socks5_inbound\"]" "${singBoxConfigPath}socks5_02_inbound_route.json")
        route=$(echo "${route}" | jq ".route.rules[0].source_ip_cidr=${socks5InboundRoutingIPs}")
        echo "${route}" | jq . >"${singBoxConfigPath}socks5_02_inbound_route.json"

        addSingBoxOutbound block
        addSingBoxOutbound "01_direct_outbound"
    fi

}

# socks5 outbound
setSocks5Outbound() {

    echoContent yellow "\n==================== Configure Socks5 outbound（forward机、proxy机） =====================\n"
    echoContent skyBlue "copystep骤Configurecopy机connectionlanding machine的upstream SOCKS service，参countneedwithlanding machine一致"
    echo
    echoContent yellow "upstreamaddress：fillSocksupstream/landing machineIPordomain，keepemptycannotcontinue。"
    read -r -p "Please enterlanding machineIPaddress:" socks5RoutingOutboundIP
    if [[ -z "${socks5RoutingOutboundIP}" ]]; then
        echoContent red " ---> IPcannot be empty"
        exit 0
    fi
    socks5RoutingOutboundIP=$(stripAnsi "${socks5RoutingOutboundIP}")
    echo
    echoContent yellow "upstreamport：fillSocks监listenport(示例:1080/443)，withupstream实际port一致。"
    read -r -p "Please enterlanding machineport:" socks5RoutingOutboundPort
    if [[ -z "${socks5RoutingOutboundPort}" ]]; then
        echoContent red " ---> portcannot be empty"
        exit 0
    fi
    socks5RoutingOutboundPort=$(stripAnsi "${socks5RoutingOutboundPort}")
    if [[ ! "${socks5RoutingOutboundPort}" =~ ^[0-9]+$ ]]; then
        echoContent red " ---> port格styleError，仅supportcountcharacter"
        exit 0
    fi
    echo
    # focus意: sing-box SOCKS 仅supportuser名/passwordadmit证
    # unified 模styleyes便捷功can，user名andpasswordmakeusesame的UUID
    echoContent yellow "Please selectupstreamadmit证squarestyle（mustwithlanding machineConfigure一致）"
    echoContent yellow "1.user名/password[return车default，maycustom]"
    echoContent yellow "2.unify一key[user名andpasswordmakeusesameUUID，便inmanagearrange]"
    read -r -p "Please select:" socks5RoutingOutboundAuthType
    if [[ -z "${socks5RoutingOutboundAuthType}" || "${socks5RoutingOutboundAuthType}" == "1" ]]; then
        socks5RoutingOutboundAuthType="password"
    elif [[ "${socks5RoutingOutboundAuthType}" == "2" ]]; then
        socks5RoutingOutboundAuthType="unified"
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi
    echo
    if [[ "${socks5RoutingOutboundAuthType}" == "unified" ]]; then
        echoContent skyBlue "unify一key模style：user名andpasswordmakeusesame的UUID，needwithlanding machineConfigure一致"
        echoContent yellow "below\"Please select\"corresponding：1 straightcatchInput(return车defaultrandomvalue) / 2 Readfile / 3 Read环environment变measure"
        local defaultSocks5OutboundUnifiedKey
        defaultSocks5OutboundUnifiedKey=$(cat /proc/sys/kernel/random/uuid)
        socks5RoutingOutboundUnifiedKey=$(readCredentialBySource "unify一key" "${defaultSocks5OutboundUnifiedKey}" | stripAnsi | tail -n 1)
        socks5RoutingOutboundUserName=${socks5RoutingOutboundUnifiedKey}
        socks5RoutingOutboundPassword=${socks5RoutingOutboundUnifiedKey}
    else
        socks5RoutingOutboundUserName=$(readCredentialBySource "Please enteruser名" "" | stripAnsi | tail -n 1)
        socks5RoutingOutboundPassword=$(readCredentialBySource "Please enteruserpassword" "" | stripAnsi | tail -n 1)
    fi
    echo

    # focus意: sing-box SOCKS outboundnot supported TLS，如needencryption链路invitemakeusechain proxy功can
    echoContent yellow "optional：pass已haveoutboundenterline链style拨号（如先walkWARP/direct/otheroutbound标签），keepempty则straightcatchconnectupstream。"
    read -r -p "链styleoutbound标签(many个英text逗号divide隔，press顺序生效):" socks5RoutingProxyTag
    socks5RoutingProxyTag=$(stripAnsi "${socks5RoutingProxyTag}")
    socks5RoutingProxyTagList=()
    if [[ -n "${socks5RoutingProxyTag}" ]]; then
        while IFS=',' read -r tag; do
            if [[ -n "${tag}" ]]; then
                socks5RoutingProxyTagList+=("$(stripAnsi "${tag}")")
            fi
        done < <(echo "${socks5RoutingProxyTag}" | tr -s ',' '\n')
    fi
    if [[ ${#socks5RoutingProxyTagList[@]} -gt 0 ]]; then
        echoContent green " ---> currentSocks5outboundwillpress顺序pass：${socks5RoutingProxyTagList[*]}"
        socks5RoutingFallbackDefault=${socks5RoutingProxyTagList[1]:-01_direct_outbound}
    else
        socks5RoutingFallbackDefault=01_direct_outbound
    fi
    echo

    # healthcheck Configure（仅usein Xray decide时Detectscript，sing-box SOCKS outboundnot supported healthcheck）
    echoContent yellow "optional：Configureexplore测URL/port/间隔，usein Xray decide时Detectscript（keepemptySkip）"
    read -r -p "explore测URL(defaulthttps://www.gstatic.com/generate_204):" socks5HealthCheckURL
    read -r -p "explore测port(defaultmakeuselanding machineport):" socks5HealthCheckPort
    read -r -p "explore测间隔(default30s):" socks5HealthCheckInterval
    socks5HealthCheckURL=$(stripAnsi "${socks5HealthCheckURL}")
    socks5HealthCheckPort=$(stripAnsi "${socks5HealthCheckPort}")
    socks5HealthCheckInterval=$(stripAnsi "${socks5HealthCheckInterval}")
    echo

    # 仅shouldpointdecideConfigurefiledirectory时才Generate sing-box outbound JSON
    if [[ -n "${singBoxConfigPath}" ]]; then
        local socks5ConfigFile="${singBoxConfigPath}socks5_outbound.json"
        socks5HealthCheckURL=${socks5HealthCheckURL:-https://www.gstatic.com/generate_204}
        socks5HealthCheckInterval=${socks5HealthCheckInterval:-30s}

        if [[ -z "${socks5RoutingOutboundIP}" ]]; then
            echoContent red " ---> upstreamaddresscannot be empty"
            exit 0
        fi

        if [[ -z "${socks5RoutingOutboundPort}" || ! "${socks5RoutingOutboundPort}" =~ ^[0-9]+$ ]]; then
            echoContent red " ---> upstreamport格styleError"
            exit 0
        fi

        if [[ "${socks5RoutingOutboundAuthType}" == "password" ]]; then
            if [[ -z "${socks5RoutingOutboundUserName}" ]]; then
                socks5RoutingOutboundUserName="admin"
            fi
            if [[ -z "${socks5RoutingOutboundPassword}" ]]; then
                socks5RoutingOutboundPassword="${uuidNew}"
            fi
        elif [[ "${socks5RoutingOutboundAuthType}" == "unified" ]]; then
            if [[ -z "${socks5RoutingOutboundUnifiedKey}" ]]; then
                echoContent red " ---> unify一keycannot be empty"
                exit 0
            fi
            socks5RoutingOutboundUserName="${socks5RoutingOutboundUnifiedKey}"
            socks5RoutingOutboundPassword="${socks5RoutingOutboundUnifiedKey}"
        fi

        local socks5ConfigTemp
        socks5ConfigTemp=$(mktemp)

        # sing-box SOCKS outboundsupport的charactersection: server, server_port, version, username, password, detour
        # not supported: tls, transport, healthcheck
        if ! jq -n \
            --arg server "${socks5RoutingOutboundIP}" \
            --argjson port "${socks5RoutingOutboundPort}" \
            --arg user "${socks5RoutingOutboundUserName}" \
            --arg pass "${socks5RoutingOutboundPassword}" \
            --arg detour "${socks5RoutingProxyTagList[0]}" ' {
  outbounds: [
    {
      type: "socks",
      tag: "socks5_outbound",
      server: $server,
      server_port: $port,
      version: "5"
    }
  ]
}
            | .outbounds[0].username = $user
            | .outbounds[0].password = $pass
            | (if ($detour|length)>0 then (.outbounds[0].detour=$detour) else . end)
' >"${socks5ConfigTemp}"; then
            rm -f "${socks5ConfigTemp}"
            echoContent red " ---> Generate Socks5 outboundConfigureFailed，invite检checkInput"
            exit 0
        fi

        mv "${socks5ConfigTemp}" "${socks5ConfigFile}"
        validateJsonFile "${socks5ConfigFile}"
    fi
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayOutbound socks5_outbound
        echoContent yellow "optional：Create Xray decide时Detectscript，explore测FailedbackSwitch路by标签orRestart"
        read -r -p "yesnoCreate并focusvolumecron任务？[y/n]:" socks5XrayCronStatus
        if [[ "${socks5XrayCronStatus}" == "y" ]]; then
            local socks5XrayFailoverTag=
            local socks5XrayCronInterval=
            read -r -p "DetectFailedbackSwitchto的路by标签（keepempty则RestartXray）:" socks5XrayFailoverTag
            read -r -p "Detect频lead(divide钟,default5):" socks5XrayCronInterval
            if [[ -z "${socks5XrayCronInterval}" || ! ${socks5XrayCronInterval} =~ ^[0-9]+$ || "${socks5XrayCronInterval}" == "0" ]]; then
                socks5XrayCronInterval=5
            fi
            cat <<EOF >/etc/v2ray-agent/socks5_outbound_healthcheck.sh
#!/usr/bin/env bash
check_url="${socks5HealthCheckURL:-https://www.gstatic.com/generate_204}"
proxy_auth="${socks5RoutingOutboundUserName}:${socks5RoutingOutboundPassword}@${socks5RoutingOutboundIP}:${socks5RoutingOutboundPort}"
failover_tag="${socks5XrayFailoverTag}"
routing_file="/etc/v2ray-agent/xray/conf/09_routing.json"

if ! curl -x "socks5://${proxy_auth}" --max-time 10 -ks "${check_url}" >/dev/null 2>&1; then
    if [[ -n "${failover_tag}" && -f "${routing_file}" ]] && command -v jq >/dev/null 2>&1; then
        updated_route=$(jq "if .routing and .routing.rules then .routing.rules |= map(if .outboundTag==\"socks5_outbound\" then (.outboundTag=\"${failover_tag}\") else . end) else . end" "${routing_file}")
        if [[ -n "${updated_route}" ]]; then
            echo "${updated_route}" | jq . >"${routing_file}"
            systemctl restart xray >/dev/null 2>&1
        fi
    else
        systemctl restart xray >/dev/null 2>&1
    fi
fi
EOF
            chmod 700 /etc/v2ray-agent/socks5_outbound_healthcheck.sh
            if crontab -l >/dev/null 2>&1; then
                crontab -l | sed '/socks5_outbound_healthcheck/d' >/etc/v2ray-agent/backup_crontab.cron
            else
                echo "" >/etc/v2ray-agent/backup_crontab.cron
            fi
            echo "*/${socks5XrayCronInterval} * * * * /bin/bash /etc/v2ray-agent/socks5_outbound_healthcheck.sh >/etc/v2ray-agent/socks5_outbound_healthcheck.log 2>&1" >>/etc/v2ray-agent/backup_crontab.cron
            crontab /etc/v2ray-agent/backup_crontab.cron
        fi
    fi
}

# socks5 outbound routing规则：matchdomain/IP/portbackforwardto socks5 outbound
setSocks5OutboundRouting() {

    if [[ "$1" == "addRules" && ! -f "${singBoxConfigPath}socks5_01_outbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        echoContent red " ---> inviteInstalloutboundroutingback再Addrouting规则"
        exit 0
    fi

    echoContent red "=============================================================="
    echoContent skyBlue "Please enterwantbinddecideto socks 标签的domain/IP/port（至fewfillwrite一项）\n"
    echoContent yellow "domainsupport geosite/rule_set，示例: netflix,openai,example.com\n"
    echoContent yellow "IP 示例: 1.1.1.1,8.8.8.8  |  port示例: 80,443\n"
    read -r -p "domain(maykeepempty，use逗号divide隔):" socks5RoutingOutboundDomain
    read -r -p "IP(maykeepempty，use逗号divide隔):" socks5RoutingOutboundIP
    read -r -p "port(maykeepempty，use逗号divide隔):" socks5RoutingOutboundPort
    socks5RoutingOutboundDomain=$(stripAnsi "${socks5RoutingOutboundDomain}")
    socks5RoutingOutboundIP=$(stripAnsi "${socks5RoutingOutboundIP}")
    socks5RoutingOutboundPort=$(stripAnsi "${socks5RoutingOutboundPort}")

    if [[ -z "${socks5RoutingOutboundDomain}" && -z "${socks5RoutingOutboundIP}" && -z "${socks5RoutingOutboundPort}" ]]; then
        echoContent red " ---> 至fewneedfillwritedomain、IP orportmiddle的一项"
        exit 0
    fi

    local rules=
    rules=$(initSingBoxRules "${socks5RoutingOutboundDomain}" "socks5_01_outbound_route")
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    local ruleSet=
    ruleSet=$(echo "${rules}" | jq .ruleSet)
    local ruleSetTag=[]
    if [[ "$(echo "${ruleSet}" | jq '.|length')" != "0" ]]; then
        ruleSetTag=$(echo "${ruleSet}" | jq '.|map(.tag)')
    fi

    local ipRules="[]"
    if [[ -n "${socks5RoutingOutboundIP}" ]]; then
        ipRules=$(echo "\"${socks5RoutingOutboundIP}\"" | jq -c '[split(",")[]|select(length>0)]')
    fi

    local portRules="[]"
    if [[ -n "${socks5RoutingOutboundPort}" ]]; then
        portRules=$(echo "\"${socks5RoutingOutboundPort}\"" | jq -c '[split(",")[]|select(length>0)|(tonumber? // .)]')
    fi

    local socks5RoutingFallbackOutbound=${socks5RoutingFallbackDefault:-01_direct_outbound}
    read -r -p "未命middle规则的fallbackoutbound标签[default${socks5RoutingFallbackOutbound}]:" socks5RoutingFallbackOutboundInput
    if [[ -n "${socks5RoutingFallbackOutboundInput}" ]]; then
        socks5RoutingFallbackOutbound=$(stripAnsi "${socks5RoutingFallbackOutboundInput}")
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        cat <<EOF >"${singBoxConfigPath}socks5_01_outbound_route.json"
{
  "route": {
    "rules": [
      {
        "rule_set":${ruleSetTag},
        "domain_regex":${domainRules},
        "ip_cidr":${ipRules},
        "port":${portRules},
        "outbound": "socks5_outbound"
      },
      {
        "outbound": "${socks5RoutingFallbackOutbound}"
      }
    ],
    "rule_set":${ruleSet}
  }
}
EOF

        jq '(.route.rules[]|select(.rule_set==[])|del(.rule_set))|(.route.rules[]|select(.domain_regex==[])|del(.domain_regex))|(.route.rules[]|select(.ip_cidr==[])|del(.ip_cidr))|(.route.rules[]|select(.port==[])|del(.port))|if .route.rule_set == [] then del(.route.rule_set) else . end' "${singBoxConfigPath}socks5_01_outbound_route.json" >"${singBoxConfigPath}socks5_01_outbound_route_tmp.json" && mv "${singBoxConfigPath}socks5_01_outbound_route_tmp.json" "${singBoxConfigPath}socks5_01_outbound_route.json"
    fi

    addSingBoxOutbound "01_direct_outbound"

    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -z "${socks5RoutingOutboundDomain}" ]]; then
            echoContent yellow " ---> Detectto未录入domain，Xray-core routing规则SkipGenerate"
        else
            unInstallRouting "socks5_outbound" "outboundTag"
            local domainRules=[]
            while read -r line; do
                if echo "${routingRule}" | grep -q "${line}"; then
                    echoContent yellow " ---> ${line}already exists，Skip"
                else
                    local geositeStatus
                    geositeStatus=$(curl -s "https://api.github.com/repos/v2fly/domain-list-community/contents/data/${line}" | jq .message)

                    if [[ "${geositeStatus}" == "null" ]]; then
                        domainRules=$(echo "${domainRules}" | jq -r ". += [\"geosite:${line}\"]")
                    else
                        domainRules=$(echo "${domainRules}" | jq -r ". += [\"domain:${line}\"]")
                    fi
                fi
            done < <(echo "${socks5RoutingOutboundDomain}" | tr ',' '\n')
            if [[ ! -f "${configPath}09_routing.json" ]]; then
                cat <<EOF >${configPath}09_routing.json
{
    "routing":{
        "rules": []
  }
}
EOF
            fi
            routing=$(jq -r ".routing.rules += [{\"type\": \"field\",\"domain\": ${domainRules},\"outboundTag\": \"socks5_outbound\"}]" ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green " ---> socks5routing规则Addfinished"
    echoContent green "==============================================================\n"
}

# SetVMess+WS+TLS【仅outbound】
setVMessWSRoutingOutbounds() {
    read -r -p "Please enterVMess+WS+TLS的address:" setVMessWSTLSAddress
    echoContent red "=============================================================="
    echoContent yellow "录入示例:netflix,openai\n"
    read -r -p "invitepressphotoupsurface示例录入domain:" domainList

    if [[ -z ${domainList} ]]; then
        echoContent red " ---> domaincannot be empty"
        setVMessWSRoutingOutbounds
    fi

    if [[ -n "${setVMessWSTLSAddress}" ]]; then
        removeXrayOutbound VMess-out

        echo
        read -r -p "Please enterVMess+WS+TLS的port:" setVMessWSTLSPort
        echo
        if [[ -z "${setVMessWSTLSPort}" ]]; then
            echoContent red " ---> portcannot be empty"
        fi

        read -r -p "Please enterVMess+WS+TLS的UUID:" setVMessWSTLSUUID
        echo
        if [[ -z "${setVMessWSTLSUUID}" ]]; then
            echoContent red " ---> UUIDcannot be empty"
        fi

        read -r -p "Please enterVMess+WS+TLS的Pathpath:" setVMessWSTLSPath
        echo
        if [[ -z "${setVMessWSTLSPath}" ]]; then
            echoContent red " ---> pathcannot be empty"
        elif ! echo "${setVMessWSTLSPath}" | grep -q "/"; then
            setVMessWSTLSPath="/${setVMessWSTLSPath}"
        fi
        addXrayOutbound "VMess-out"
        addXrayRouting VMess-out outboundTag "${domainList}"
        reloadCore
        echoContent green " ---> AddroutingSuccess"
        exit 0
    fi
    echoContent red " ---> addresscannot be empty"
    setVMessWSRoutingOutbounds
}

# 移除VMess+WS+TLSrouting
removeVMessWSRouting() {

    removeXrayOutbound VMess-out
    unInstallRouting VMess-out outboundTag

    reloadCore
    echoContent green " ---> Uninstall successful"
}

# Restartcore
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

# dnsrouting
dnsRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> Not installed，invitemakeusescriptInstall"
        menu
        exit 0
    fi
    echoContent skyBlue "\n功can 1/${totalProgress} : DNSrouting"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项"
    echoContent yellow "# makeuseNotice：invite参考 documents directorymiddle的routingwith策略say明 \n"

    echoContent yellow "1.Add"
    echoContent yellow "2.Uninstall"
    read -r -p "Please select:" selectType

    case ${selectType} in
    1)
        setUnlockDNS
        ;;
    2)
        removeUnlockDNS
        ;;
    esac
}

# SNIreversetowardproxyrouting
sniRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> Not installed，invitemakeusescriptInstall"
        menu
        exit 0
    fi
    echoContent skyBlue "\n功can 1/${totalProgress} : SNIreversetowardproxyrouting"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项"
    echoContent yellow "# makeuseNotice：invite参考 documents directorymiddle的routingwith策略say明 \n"
    echoContent yellow "# sing-boxnot supported规则collect，仅supportpointdecidedomain。\n"

    echoContent yellow "1.Add"
    echoContent yellow "2.Uninstall"
    read -r -p "Please select:" selectType

    case ${selectType} in
    1)
        setUnlockSNI
        ;;
    2)
        removeUnlockSNI
        ;;
    esac
}
# SetSNIrouting
setUnlockSNI() {
    read -r -p "Please enterrouting的SNI IP:" setSNIP
    if [[ -n ${setSNIP} ]]; then
        echoContent red "=============================================================="

        if [[ "${coreInstallType}" == 1 ]]; then
            echoContent yellow "录入示例:netflix,disney,hulu"
            read -r -p "invitepressphotoupsurface示例录入domain:" xrayDomainList
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
            read -r -p "invitepressphotoupsurface示例录入domain:" singboxDomainList
            addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined"
        fi
        echoContent yellow " ---> SNIreversetowardproxyroutingSuccess"
        reloadCore
    else
        echoContent red " ---> SNI IPcannot be empty"
    fi
    exit 0
}

# Addxray dns Configure
addXrayDNSConfig() {
    local ip=$1
    local domainList=$2
    local domains=[]
    while read -r line; do
        local geositeStatus
        geositeStatus=$(curl -s "https://api.github.com/repos/v2fly/domain-list-community/contents/data/${line}" | jq .message)

        if [[ "${geositeStatus}" == "null" ]]; then
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

# Addsing-box dnsConfigure
addSingBoxDNSConfig() {
    local ip=$1
    local domainList=$2
    local actionType=$3

    local rules=
    rules=$(initSingBoxRules "${domainList}" "dns")
    # domain精确match规则
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    # ruleSet规则collect
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
# Setdns
setUnlockDNS() {
    read -r -p "Please enterrouting的DNS:" setDNS
    if [[ -n ${setDNS} ]]; then
        echoContent red "=============================================================="
        echoContent yellow "录入示例:netflix,disney,hulu"
        read -r -p "invitepressphotoupsurface示例录入domain:" domainList

        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayDNSConfig "${setDNS}" "${domainList}"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxOutbound 01_direct_outbound
            addSingBoxDNSConfig "${setDNS}" "${domainList}"
        fi

        reloadCore

        echoContent yellow "\n ---> 如returncannotobservelookmaywithtrybelow两kindsquare案"
        echoContent yellow " 1.Restartvps"
        echoContent yellow " 2.Uninstalldnsunlockback，Modifylocal的[/etc/resolv.conf]DNSSet并Restartvps\n"
    else
        echoContent red " ---> dnscannot be empty"
    fi
    exit 0
}

# 移除 DNSrouting
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

    echoContent green " ---> Uninstall successful"

    exit 0
}

# 移除SNIrouting
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
    echoContent green " ---> Uninstall successful"

    exit 0
}

# sing-box personalizationInstall
customSingBoxInstall() {
    echoContent skyBlue "\n========================personalizationInstall============================"
    echoContent yellow "0.VLESS+Vision+TCP"
    echoContent yellow "1.VLESS+TLS+WS[仅CDNrecommended]"
    echoContent yellow "3.VMess+TLS+WS[仅CDNrecommended]"
    echoContent yellow "4.Trojan+TLS[不recommended]"
    echoContent yellow "6.Hysteria2"
    echoContent yellow "7.VLESS+Reality+Vision"
    echoContent yellow "8.VLESS+Reality+gRPC"
    echoContent yellow "9.Tuic"
    echoContent yellow "10.Naive"
    echoContent yellow "11.VMess+TLS+HTTPUpgrade"
    echoContent yellow "13.anytls"
    echoContent yellow "14.Shadowsocks 2022[no needTLScertificate]"

    read -r -p "Please select[manyselect]，[例如:1,2,3]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> invitemakeuse英text逗号divide隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType}" != "10" ]] && [[ "${selectCustomInstallType}" != "11" ]] && [[ "${selectCustomInstallType}" != "13" ]] && [[ "${selectCustomInstallType}" != "14" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> manyselectinvitemakeuse英text逗号divide隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType: -1}" != "," ]]; then
        selectCustomInstallType="${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi

    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]]; then
        # WebSocket protocol迁移Notice
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,"; then
            echoContent yellow "\n ---> Notice: WebSockettransport已逐渐byXHTTP(SplitHTTP)getgeneration"
            echoContent yellow " ---> XHTTP具have更good的抗Detectcan力andCDNcompatible性，recommendedatXraymiddlemakeuseVLESS+Reality+XHTTP"
            echoContent yellow " ---> 参考: https://xtls.github.io/en/config/transports/splithttp.html\n"
        fi

        readLastInstallationConfig
        unInstallSubscribe
        totalProgress=9
        installTools 1
        # 申invitetls
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
        # Generateaccount
        checkGFWStatue 8
        showAccounts 9
    else
        echoContent red " ---> Input不valid"
        customSingBoxInstall
    fi
}

# Xray-corepersonalizationInstall
customXrayInstall() {
    echoContent skyBlue "\n========================personalizationInstall============================"
    echoContent yellow "VLESSfront置，defaultInstall0，nonedomainInstallReality只Select7即may"
    echoContent yellow "0.VLESS+TLS_Vision+TCP[recommended]"
    echoContent yellow "1.VLESS+TLS+WS[仅CDNrecommended]"
    #    echoContent yellow "2.Trojan+TLS+gRPC[仅CDNrecommended]"
    echoContent yellow "3.VMess+TLS+WS[仅CDNrecommended]"
    echoContent yellow "4.Trojan+TLS[不recommended]"
    echoContent yellow "5.VLESS+TLS+gRPC[仅CDNrecommended]"
    echoContent yellow "7.VLESS+Reality+uTLS+Vision[recommended]"
    # echoContent yellow "8.VLESS+Reality+gRPC"
    echoContent yellow "12.VLESS+Reality+XHTTP+TLS[CDNavailable]"
    read -r -p "Please select[manyselect]，[例如:1,2,3]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> invitemakeuse英text逗号divide隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType}" != "12" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> manyselectinvitemakeuse英text逗号divide隔"
        exit 0
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
        # WebSocket protocol迁移Notice
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,"; then
            echoContent yellow "\n ---> Notice: WebSockettransport已逐渐byXHTTP(SplitHTTP)getgeneration"
            echoContent yellow " ---> XHTTP具have更good的抗Detectcan力andCDNcompatible性，recommendedSelect12.VLESS+Reality+XHTTP+TLS"
            echoContent yellow " ---> 参考: https://xtls.github.io/en/config/transports/splithttp.html\n"
        fi

        readLastInstallationConfig
        unInstallSubscribe
        checkBTPanel
        check1Panel
        totalProgress=12
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\nProgress  3/${totalProgress} : Detectto宝塔surface板/1Panel，Skip申inviteTLSstep骤"
            handleXray stop
            if [[ "${selectCustomInstallType}" != ",7," ]]; then
                customPortFunction
            fi
        else
            # 申invitetls
            if [[ "${selectCustomInstallType}" != ",7," ]]; then
                initTLSNginxConfig 2
                handleXray stop
                installTLS 3
            else
                echoContent skyBlue "\nProgress  2/${totalProgress} : Detectto仅InstallReality，SkipTLScertificatestep骤"
            fi
        fi

        handleNginx stop
        # randompath
        if echo "${selectCustomInstallType}" | grep -qE ",1,|,2,|,3,|,5,|,12,"; then
            randomPathFunction 4
        fi
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\nProgress  6/${totalProgress} : Detectto宝塔surface板/1Panel，Skipcamouflage网stand"
        else
            nginxBlog 6
        fi
        if [[ "${selectCustomInstallType}" != ",7," ]]; then
            updateRedirectNginxConf
            handleNginx start
        fi

        # Installing Xray
        installXray 7 false
        installXrayService 8
        initXrayConfig custom 9
        cleanUp singBoxDel
        if [[ "${selectCustomInstallType}" != ",7," ]]; then
            installCronTLS 10
        fi

        handleXray stop
        handleXray start
        # Generateaccount
        checkGFWStatue 11
        showAccounts 12
    else
        echoContent red " ---> Input不valid"
        customXrayInstall
    fi
}

# SelectcoreInstalling sing-box、xray-core
selectCoreInstall() {
    echoContent skyBlue "\n功can 1/${totalProgress} : SelectcoreInstall"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.sing-box"
    echoContent red "=============================================================="
    read -r -p "Please select:" selectCoreType
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
        echoContent red ' ---> Wrong selection，heavynewSelect'
        selectCoreInstall
        ;;
    esac
}

# xray-core Install
xrayCoreInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    checkBTPanel
    check1Panel
    selectCustomInstallType=
    totalProgress=12
    installTools 2
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\nProgress  3/${totalProgress} : Detectto宝塔surface板/1Panel，Skip申inviteTLSstep骤"
        handleXray stop
        customPortFunction
    else
        # 申invitetls
        initTLSNginxConfig 3
        handleXray stop
        installTLS 4
    fi

    handleNginx stop
    randomPathFunction 5

    # Installing Xray
    installXray 6 false
    installXrayService 7
    initXrayConfig all 8
    cleanUp singBoxDel
    installCronTLS 9
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\nProgress  11/${totalProgress} : Detectto宝塔surface板/1Panel，Skipcamouflage网stand"
    else
        nginxBlog 10
    fi
    updateRedirectNginxConf
    handleXray stop
    sleep 2
    handleXray start

    handleNginx start
    # Generateaccount
    checkGFWStatue 11
    showAccounts 12
}

# sing-box allInstall
singBoxInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    checkBTPanel
    check1Panel
    selectCustomInstallType=
    totalProgress=8
    installTools 2

    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\nProgress  3/${totalProgress} : Detectto宝塔surface板/1Panel，Skip申inviteTLSstep骤"
        handleXray stop
        customPortFunction
    else
        # 申invitetls
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
    # Generateaccount
    showAccounts 9
}

# Core Management
coreVersionManageMenu() {

    if [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 没haveDetecttoInstalldirectory，invite执linescriptInstallinside容"
        menu
        exit 0
    fi
    echoContent skyBlue "\n功can 1/1 : Please selectcore"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.sing-box"
    echoContent red "=============================================================="
    read -r -p "Please enter:" selectCore

    if [[ "${selectCore}" == "1" ]]; then
        xrayVersionManageMenu 1
    elif [[ "${selectCore}" == "2" ]]; then
        singBoxVersionManageMenu 1
    fi
}
# scheduled tasks检check
cronFunction() {
    if [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit 0
    elif [[ "${cronName}" == "UpdateGeo" ]]; then
        updateGeoSite >>/etc/v2ray-agent/crontab_updateGeoSite.log
        echoContent green " ---> geoUpdate日period:$(date "+%F %H:%M:%S")" >>/etc/v2ray-agent/crontab_updateGeoSite.log
        exit 0
    fi
}
# Account Management
manageAccount() {
    echoContent skyBlue "\n功can 1/${totalProgress} : Account Management"
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> Not installed"
        exit 0
    fi

    echoContent red "\n=============================================================="
    echoContent yellow "# Add单个user时maycustomemailanduuid"
    echoContent yellow "# 如InstalldoneHysteriaor者Tuic，accountknow同时Addto相respond的typemodeldownsurface\n"
    echoContent yellow "1.Viewaccount"
    echoContent yellow "2.Viewsubscription"
    echoContent yellow "3.managearrangeothersubscription"
    echoContent yellow "4.Adding users"
    echoContent yellow "5.Deleteuser"
    echoContent red "=============================================================="
    read -r -p "Please enter:" manageAccountStatus
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
        echoContent red " ---> Wrong selection"
    fi
}

# Installsubscription
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
            echoContent yellow "未Detecttonginx，cannotmakeusesubscriptionservice\n"
            read -r -p "yesnoInstall[y/n]？" installNginxStatus
            if [[ "${installNginxStatus}" == "y" ]]; then
                installNginxTools
            else
                echoContent red " ---> abandonInstallnginx\n"
                exit 0
            fi
        fi
        echoContent yellow "StartConfiguresubscription，Please entersubscription的port\n"

        mapfile -t result < <(initSingBoxPort "${subscribePort}")
        echo
        echoContent yellow " ---> StartConfiguresubscription的camouflagestandclick\n"
        nginxBlog
        echo
        local httpSubscribeStatus=

        if ! echo "${selectCustomInstallType}" | grep -qE ",0,|,1,|,2,|,3,|,4,|,5,|,6,|,9,|,10,|,11,|,13," && ! echo "${currentInstallProtocolType}" | grep -qE ",0,|,1,|,2,|,3,|,4,|,5,|,6,|,9,|,10,|,11,|,13," && [[ -z "${domain}" ]]; then
            httpSubscribeStatus=true
        fi

        if [[ "${httpSubscribeStatus}" == "true" ]]; then

            echoContent yellow "未send现tlscertificate，makeusenoneencryptionsubscription，maybytransport营商拦截，invitefocus意风险。"
            echo
            read -r -p "yesnomakeusehttpsubscription[y/n]？" addNginxSubscribeStatus
            echo
            if [[ "${addNginxSubscribeStatus}" != "y" ]]; then
                echoContent yellow " ---> ExitInstall"
                exit
            fi
        else
            local subscribeServerName=
            if [[ -n "${currentHost}" ]]; then
                subscribeServerName="${currentHost}"
            else
                subscribeServerName="${domain}"
            fi

            SSLType="ssl"
            serverName="server_name ${subscribeServerName};"
            nginxSubscribeSSL="ssl_certificate /etc/v2ray-agent/tls/${subscribeServerName}.crt;ssl_certificate_key /etc/v2ray-agent/tls/${subscribeServerName}.key;"
        fi
        if [[ -n "$(curl --connect-timeout 2 -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)" ]]; then
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
        alias /etc/v2ray-agent/subscribe/\$1/\$2;
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
# Uninstallsubscription
unInstallSubscribe() {
    rm -rf ${nginxConfigPath}subscribe.conf >/dev/null 2>&1
}

# Addsubscription
addSubscribeMenu() {
    echoContent skyBlue "\n===================== Addother机器subscription ======================="
    echoContent yellow "1.Add"
    echoContent yellow "2.移除"
    echoContent red "=============================================================="
    read -r -p "Please select:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        if [[ ! -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]]; then
            echoContent green " ---> Not installedothersubscription"
            exit 0
        fi
        grep -v '^$' "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" | awk '{print NR""":"$0}'
        read -r -p "Please selectwantDelete的subscriptionweave号[仅support单个Delete]:" delSubscribeIndex
        if [[ -z "${delSubscribeIndex}" ]]; then
            echoContent green " ---> 不maywithasempty"
            exit 0
        fi

        sed -i "$((delSubscribeIndex))d" "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" >/dev/null 2>&1

        echoContent green " ---> other机器subscriptionDeleted successfully"
        subscribe
    fi
}
# Addother机器clashMetasubscription
addOtherSubscribe() {
    echoContent yellow "#focus意事项:"
    echoContent yellow "Please enter目标standclick信息，ensurewith Reality Configure相match。"
    echoContent skyBlue "录入示例：www.example.com:443:vps1\n"
    read -r -p "Please enterdomain port 机器别名:" remoteSubscribeUrl
    if [[ -z "${remoteSubscribeUrl}" ]]; then
        echoContent red " ---> cannot be empty"
        addOtherSubscribe
    elif ! echo "${remoteSubscribeUrl}" | grep -q ":"; then
        echoContent red " ---> 规则不valid"
    else

        if [[ -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" ]] && grep -q "${remoteSubscribeUrl}" /etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl; then
            echoContent red " ---> 此subscription已Add"
            exit 0
        fi
        echo
        read -r -p "yesnoyesHTTPsubscription？[y/n]" httpSubscribeStatus
        if [[ "${httpSubscribeStatus}" == "y" ]]; then
            remoteSubscribeUrl="${remoteSubscribeUrl}:http"
        fi
        echo "${remoteSubscribeUrl}" >>/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl
        subscribe
    fi
}
# clashMetaConfigurefile
clashMetaConfig() {
    local url=$1
    local id=$2
    cat <<EOF >"/etc/v2ray-agent/subscribe/clashMetaProfiles/${id}"
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
  - name: 手moveSwitch
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies: null
  - name: 自moveSelect
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 36000
    tolerance: 50
    use:
      - ${subscribeSalt}_provider
    proxies: null

  - name: complete球proxy
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect

  - name: streaming
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect
      - DIRECT
  - name: DNS_Proxy
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 自moveSelect
      - 手moveSwitch
      - DIRECT

  - name: Telegram
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect
  - name: Google
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect
      - DIRECT
  - name: YouTube
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect
  - name: Netflix
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - streaming
      - 手moveSwitch
      - 自moveSelect
  - name: Spotify
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - streaming
      - 手moveSwitch
      - 自moveSelect
      - DIRECT
  - name: HBO
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - streaming
      - 手moveSwitch
      - 自moveSelect
  - name: Bing
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect


  - name: OpenAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect

  - name: ClaudeAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect

  - name: Disney
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - streaming
      - 手moveSwitch
      - 自moveSelect
  - name: GitHub
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手moveSwitch
      - 自moveSelect
      - DIRECT

  - name: 国inside媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
  - name: localdirect
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 自moveSelect
  - name: 漏网之鱼
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 手moveSwitch
      - 自moveSelect
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
  - RULE-SET,proxy,complete球proxy
  - RULE-SET,gfw,complete球proxy
  - RULE-SET,applications,localdirect
  - RULE-SET,ChinaMaxDomain,localdirect
  - RULE-SET,ChinaMaxIPNoIPv6,localdirect,no-resolve
  - RULE-SET,lan,localdirect,no-resolve
  - GEOIP,CN,localdirect
  - MATCH,漏网之鱼
EOF

}
# randomsalt
initRandomSalt() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..10}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    echo "${initCustomPath}"
}
# subscription
subscribe() {
    readInstallProtocolType
    installSubscribe

    readNginxSubscribe
    local renewSalt=$1
    local showStatus=$2
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "2" ]]; then

        echoContent skyBlue "-------------------------备focus---------------------------------"
        echoContent yellow "# ViewsubscriptionknowheavynewGeneratelocalaccount的subscription"
        echoContent red "# need手moveInputmd5encryption的saltvalue，如果不doneunlockmakeuserandom即may"
        echoContent yellow "# 不shadow响已Add的remotesubscription的inside容\n"

        if [[ -f "/etc/v2ray-agent/subscribe_local/subscribeSalt" && -n $(cat "/etc/v2ray-agent/subscribe_local/subscribeSalt") ]]; then
            if [[ -z "${renewSalt}" ]]; then
                read -r -p "ReadtouptimeInstallSet的Salt，yesnomakeuseuptimeGenerate的Salt ？[y/n]:" historySaltStatus
                if [[ "${historySaltStatus}" == "y" ]]; then
                    subscribeSalt=$(cat /etc/v2ray-agent/subscribe_local/subscribeSalt)
                else
                    read -r -p "Please entersaltvalue, [return车]makeuserandom:" subscribeSalt
                fi
            else
                subscribeSalt=$(cat /etc/v2ray-agent/subscribe_local/subscribeSalt)
            fi
        else
            read -r -p "Please entersaltvalue, [return车]makeuserandom:" subscribeSalt
            showStatus=
        fi

        if [[ -z "${subscribeSalt}" ]]; then
            subscribeSalt=$(initRandomSalt)
        fi
        echoContent yellow "\n ---> Salt: ${subscribeSalt}"

        echo "${subscribeSalt}" >/etc/v2ray-agent/subscribe_local/subscribeSalt

        rm -rf /etc/v2ray-agent/subscribe/default/*
        rm -rf /etc/v2ray-agent/subscribe/clashMeta/*
        rm -rf /etc/v2ray-agent/subscribe_local/default/*
        rm -rf /etc/v2ray-agent/subscribe_local/clashMeta/*
        rm -rf /etc/v2ray-agent/subscribe_local/sing-box/*
        showAccounts >/dev/null
        if [[ -n $(ls /etc/v2ray-agent/subscribe_local/default/) ]]; then
            if [[ -f "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl" && -n $(cat "/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl") ]]; then
                if [[ -z "${renewSalt}" ]]; then
                    read -r -p "Readtoothersubscription，yesnoUpdate？[y/n]" updateOtherSubscribeStatus
                else
                    updateOtherSubscribeStatus=y
                fi
            fi
            local subscribePortLocal="${subscribePort}"
            find /etc/v2ray-agent/subscribe_local/default/* | while read -r email; do
                email=$(echo "${email}" | awk -F "[d][e][f][a][u][l][t][/]" '{print $2}')

                local emailMd5=
                emailMd5=$(echo -n "${email}${subscribeSalt}"$'\n' | md5sum | awk '{print $1}')

                cat "/etc/v2ray-agent/subscribe_local/default/${email}" >>"/etc/v2ray-agent/subscribe/default/${emailMd5}"
                if [[ "${updateOtherSubscribeStatus}" == "y" ]]; then
                    updateRemoteSubscribe "${emailMd5}" "${email}"
                fi
                local base64Result
                base64Result=$(base64 -w 0 "/etc/v2ray-agent/subscribe/default/${emailMd5}")
                echo "${base64Result}" >"/etc/v2ray-agent/subscribe/default/${emailMd5}"
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
                    echoContent skyBlue "\n----------defaultsubscription----------\n"
                    echoContent green "email:${email}\n"
                    echoContent yellow "url:${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    echoContent yellow "onlineQR code:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    if [[ "${release}" != "alpine" ]]; then
                        echo "${subscribeType}://${currentDomain}/s/default/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                    fi

                    # clashMeta
                    if [[ -f "/etc/v2ray-agent/subscribe_local/clashMeta/${email}" ]]; then

                        cat "/etc/v2ray-agent/subscribe_local/clashMeta/${email}" >>"/etc/v2ray-agent/subscribe/clashMeta/${emailMd5}"

                        sed -i '1i\proxies:' "/etc/v2ray-agent/subscribe/clashMeta/${emailMd5}"

                        local clashProxyUrl="${subscribeType}://${currentDomain}/s/clashMeta/${emailMd5}"
                        clashMetaConfig "${clashProxyUrl}" "${emailMd5}"
                        echoContent skyBlue "\n----------clashMetasubscription----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        echoContent yellow "onlineQR code:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        if [[ "${release}" != "alpine" ]]; then
                            echo "${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                        fi

                    fi
                    # sing-box
                    if [[ -f "/etc/v2ray-agent/subscribe_local/sing-box/${email}" ]]; then
                        cp "/etc/v2ray-agent/subscribe_local/sing-box/${email}" "/etc/v2ray-agent/subscribe/sing-box_profiles/${emailMd5}"

                        echoContent skyBlue " ---> download sing-box universalConfigurefile"
                        if [[ "${release}" == "alpine" ]]; then
                            wget -O "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}" -q "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/documents/sing-box.json"
                        else
                            wget -O "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}" -q "${wgetShowProgressStatus}" "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/documents/sing-box.json"
                        fi

                        jq ".outbounds=$(jq ".outbounds|map(if has(\"outbounds\") then .outbounds += $(jq ".|map(.tag)" "/etc/v2ray-agent/subscribe_local/sing-box/${email}") else . end)" "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}")" "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}" >"/etc/v2ray-agent/subscribe/sing-box/${emailMd5}_tmp" && mv "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}_tmp" "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}"
                        jq ".outbounds += $(jq '.' "/etc/v2ray-agent/subscribe_local/sing-box/${email}")" "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}" >"/etc/v2ray-agent/subscribe/sing-box/${emailMd5}_tmp" && mv "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}_tmp" "/etc/v2ray-agent/subscribe/sing-box/${emailMd5}"

                        echoContent skyBlue "\n----------sing-boxsubscription----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        echoContent yellow "onlineQR code:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        if [[ "${release}" != "alpine" ]]; then
                            echo "${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                        fi

                    fi

                    echoContent skyBlue "--------------------------------------------------------------"
                else
                    echoContent green " ---> email:${email}，subscription已Update，invitemakeuseclientheavynewpullget"
                fi

            done
        fi
    else
        echoContent red " ---> Not installedcamouflagestandclick，cannotmakeusesubscriptionservice"
    fi
}

# Updateremotesubscription
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
            echo "${clashMetaProxies}" >>"/etc/v2ray-agent/subscribe/clashMeta/${emailMD5}"
            echoContent green " ---> clashMetasubscription ${remoteUrl}:${email} Update successful"
        else
            echoContent red " ---> clashMetasubscription ${remoteUrl}:${email}does not exist"
        fi

        local default=
        default=$(curl -s "${subscribeType}://${remoteUrl}/s/default/${emailMD5}")

        if ! echo "${default}" | grep -q "nginx" && [[ -n "${default}" ]]; then
            default=$(echo "${default}" | base64 -d | sed "s/#${email}/#${email}_${serverAlias}/g")
            echo "${default}" >>"/etc/v2ray-agent/subscribe/default/${emailMD5}"

            echoContent green " ---> universalsubscription ${remoteUrl}:${email} Update successful"
        else
            echoContent red " ---> universalsubscription ${remoteUrl}:${email} does not exist"
        fi

        local singBoxSubscribe=
        singBoxSubscribe=$(curl -s "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}")

        if ! echo "${singBoxSubscribe}" | grep -q "nginx" && [[ -n "${singBoxSubscribe}" ]]; then
            singBoxSubscribe=${singBoxSubscribe//tag\": \"${email}/tag\": \"${email}_${serverAlias}}
            singBoxSubscribe=$(jq ". +=${singBoxSubscribe}" "/etc/v2ray-agent/subscribe_local/sing-box/${email}")
            echo "${singBoxSubscribe}" | jq . >"/etc/v2ray-agent/subscribe_local/sing-box/${email}"

            echoContent green " ---> universalsubscription ${remoteUrl}:${email} Update successful"
        else
            echoContent red " ---> universalsubscription ${remoteUrl}:${email} does not exist"
        fi

    done < <(grep -v '^$' <"/etc/v2ray-agent/subscribe_remote/remoteSubscribeUrl")
}

# Switchalpn
switchAlpn() {
    echoContent skyBlue "\n功can 1/${totalProgress} : Switchalpn"
    if [[ -z ${currentAlpn} ]]; then
        echoContent red " ---> cannotReadalpn，invite检checkyesnoInstall"
        exit 0
    fi

    echoContent red "\n=============================================================="
    echoContent green "currentalpnfirst位as:${currentAlpn}"
    echoContent yellow "  1.shouldhttp/1.1first位时，trojanavailable，gRPCpartialclientavailable【clientsupport手moveSelectalpn的available】"
    echoContent yellow "  2.shouldh2first位时，gRPCavailable，trojanpartialclientavailable【clientsupport手moveSelectalpn的available】"
    echoContent yellow "  3.如clientnot supported手move更exchangealpn，recommendedmakeuse此功can更changeserveralpn顺序，comemakeuse相respond的protocol"
    echoContent red "=============================================================="

    if [[ "${currentAlpn}" == "http/1.1" ]]; then
        echoContent yellow "1.Switchalpn h2 first位"
    elif [[ "${currentAlpn}" == "h2" ]]; then
        echoContent yellow "1.Switchalpn http/1.1 first位"
    else
        echoContent red '不符combine'
    fi

    echoContent red "=============================================================="

    read -r -p "Please select:" selectSwitchAlpnType
    if [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "http/1.1" ]]; then

        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn = [\"h2\",\"http/1.1\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json

    elif [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "h2" ]]; then
        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn =[\"http/1.1\",\"h2\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json
    else
        echoContent red " ---> Wrong selection"
        exit 0
    fi
    reloadCore
}

# 初始化realityKey
initRealityKey() {
    echoContent skyBlue "\nGenerateReality key\n"
    if [[ -n "${currentRealityPublicKey}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "ReadtouptimeInstallremember录，yesnomakeuseuptimeInstall时的PublicKey/PrivateKey ？[y/n]:" historyKeyStatus
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
            realityX25519Key=$(/etc/v2ray-agent/sing-box/sing-box generate reality-keypair)
            realityPrivateKey=$(echo "${realityX25519Key}" | head -1 | awk '{print $2}')
            realityPublicKey=$(echo "${realityX25519Key}" | tail -n 1 | awk '{print $2}')
            echo "publicKey:${realityPublicKey}" >/etc/v2ray-agent/sing-box/conf/config/reality_key
        else
            read -r -p "Please enterPrivate Key[return车自moveGenerate]:" historyPrivateKey
            if [[ -n "${historyPrivateKey}" ]]; then
                realityX25519Key=$(/etc/v2ray-agent/xray/xray x25519 -i "${historyPrivateKey}")
            else
                realityX25519Key=$(/etc/v2ray-agent/xray/xray x25519)
            fi
            # compatiblenewoldversion Xray x25519 Output格style
            # oldversion: "Private key: xxx" / "Public key: xxx"
            # newversion: "PrivateKey: xxx" / "Password: xxx"
            realityPrivateKey=$(echo "${realityX25519Key}" | grep -E "Private|PrivateKey" | awk '{print $NF}')
            realityPublicKey=$(echo "${realityX25519Key}" | grep -E "Public|Password" | awk '{print $NF}')
            if [[ -z "${realityPrivateKey}" ]]; then
                echoContent red "Input的Private Key不valid"
                initRealityKey
            else
                echoContent green "\n privateKey:${realityPrivateKey}"
                echoContent green "\n publicKey:${realityPublicKey}"
            fi
        fi
    fi
}

# Generaterandom Reality shortIds
initRealityShortIds() {
    if [[ -z "${realityShortId1}" ]]; then
        realityShortId1=$(openssl rand -hex 8)
        realityShortId2=$(openssl rand -hex 8)
    fi
}

# 初始化 mldsa65Seed
initRealityMldsa65() {
    echoContent skyBlue "\nGenerateReality mldsa65\n"
    if /etc/v2ray-agent/xray/xray tls ping "${realityServerName}:${realityDomainPort}" 2>/dev/null | grep -q "X25519MLKEM768"; then
        length=$(/etc/v2ray-agent/xray/xray tls ping "${realityServerName}:${realityDomainPort}" | grep "Certificate chain's total length:" | awk '{print $5}' | head -1)

        if [ "$length" -gt 3500 ]; then
            if [[ -n "${currentRealityMldsa65}" && -z "${lastInstallationConfig}" ]]; then
                read -r -p "ReadtouptimeInstallremember录，yesnomakeuseuptimeInstall时的Seed/Verify ？[y/n]:" historyMldsa65Status
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
                #            realityX25519Key=$(/etc/v2ray-agent/sing-box/sing-box generate reality-keypair)
                #            realityPrivateKey=$(echo "${realityX25519Key}" | head -1 | awk '{print $2}')
                #            realityPublicKey=$(echo "${realityX25519Key}" | tail -n 1 | awk '{print $2}')
                #            echo "publicKey:${realityPublicKey}" >/etc/v2ray-agent/sing-box/conf/config/reality_key
                #        else
                realityMldsa65=$(/etc/v2ray-agent/xray/xray mldsa65)
                realityMldsa65Seed=$(echo "${realityMldsa65}" | head -1 | awk '{print $2}')
                realityMldsa65Verify=$(echo "${realityMldsa65}" | tail -n 1 | awk '{print $2}')
                #        fi
            fi
            #    echoContent green "\n Seed:${realityMldsa65Seed}"
            #    echoContent green "\n Verify:${realityMldsa65Verify}"
        else
            echoContent green " 目标domainsupportX25519MLKEM768，但yescertificate的longdegree不足，忽略ML-DSA-65。"
        fi
    else
        echoContent green " 目标domainnot supportedX25519MLKEM768，忽略ML-DSA-65。"
    fi
}
# 检checkrealitydomainyesno符combine
checkRealityDest() {
    local traceResult=
    traceResult=$(curl -s "https://$(echo "${realityDestDomain}" | cut -d ':' -f 1)/cdn-cgi/trace" | grep "visit_scheme=https")
    if [[ -n "${traceResult}" ]]; then
        echoContent red "\n ---> Detecttomakeuse的domain，托manageatcloudflare并enabledoneproxy，makeuse此typemodeldomainmayguide致VPSflowmeasurebyother人makeuse[不recommendedmakeuse]\n"
        read -r -p "Continue? ？[y/n]" setRealityDestStatus
        if [[ "${setRealityDestStatus}" != 'y' ]]; then
            exit 0
        fi
        echoContent yellow "\n ---> 忽略风险，continuemakeuse"
    fi
}

# 初始化clientavailable的ServersName
initRealityClientServersName() {
    local realityDestDomainList="gateway.icloud.com,itunes.apple.com,swdist.apple.com,swcdn.apple.com,updates.cdn-apple.com,mensura.cdn-apple.com,osxapps.itunes.apple.com,aod.itunes.apple.com,download-installer.cdn.mozilla.net,addons.mozilla.org,s0.awsstatic.com,d1.awsstatic.com,cdn-dynmedia-1.microsoft.com,images-na.ssl-images-amazon.com,m.media-amazon.com,player.live-video.net,one-piece.com,lol.secure.dyn.riotcdn.net,www.lovelive-anime.jp,academy.nvidia.com,software.download.prss.microsoft.com,dl.google.com,www.google-analytics.com,www.caltech.edu,www.calstatela.edu,www.suny.edu,www.suffolk.edu,www.python.org,vuejs-jp.org,vuejs.org,zh-hk.vuejs.org,react.dev,www.java.com,www.oracle.com,www.mysql.com,www.mongodb.com,redis.io,cname.vercel-dns.com,vercel-dns.com,www.swift.com,academy.nvidia.com,www.swift.com,www.cisco.com,www.asus.com,www.samsung.com,www.amd.com,www.umcg.nl,www.fom-international.com,www.u-can.co.jp,github.io"
    if [[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]; then
        if echo ${realityDestDomainList} | grep -q "${realityServerName}"; then
            read -r -p "ReadtouptimeInstallSet的Realitydomain，yesnomakeuse？[y/n]:" realityServerNameStatus
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
            read -r -p "yesnomakeuse ${domain} 此domain作asReality目标domain ？[y/n]:" realityServerNameCurrentDomainStatus
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
            echoContent skyBlue "\n================ Configureclientavailable的serverNames ===============\n"
            echoContent yellow "#focus意事项"
            echoContent green "inviteensure所select Reality 目标domainsupport TLS，且asmaydirect的常见standclick。\n"
            echoContent yellow "录入示例:addons.mozilla.org:443\n"
            read -r -p "Please enter目标domain，[return车]randomdomain，defaultport443:" realityServerName
            if [[ -z "${realityServerName}" ]]; then
                randomNum=$(randomNum 1 27)
                realityServerName=$(echo "${realityDestDomainList}" | awk -F ',' -v randomNum="$randomNum" '{print $randomNum}')
            fi
            if echo "${realityServerName}" | grep -q ":"; then
                realityDomainPort=$(echo "${realityServerName}" | awk -F "[:]" '{print $2}')
                realityServerName=$(echo "${realityServerName}" | awk -F "[:]" '{print $1}')
            fi
        fi
    fi

    echoContent yellow "\n ---> clientavailabledomain: ${realityServerName}:${realityDomainPort}\n"
}
# 初始化realityport
initXrayRealityPort() {
    if [[ -n "${xrayVLESSRealityPort}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "ReadtouptimeInstallremember录，yesnomakeuseuptimeInstall时的port ？[y/n]:" historyRealityPortStatus
        if [[ "${historyRealityPortStatus}" == "y" ]]; then
            realityPort=${xrayVLESSRealityPort}
        fi
    elif [[ -n "${xrayVLESSRealityPort}" && -n "${lastInstallationConfig}" ]]; then
        realityPort=${xrayVLESSRealityPort}
    fi

    if [[ -z "${realityPort}" ]]; then
        #        if [[ -n "${port}" ]]; then
        #            read -r -p "yesnomakeuseTLS+Visionport ？[y/n]:" realityPortTLSVisionStatus
        #            if [[ "${realityPortTLSVisionStatus}" == "y" ]]; then
        #                realityPort=${port}
        #            fi
        #        fi
        #        if [[ -z "${realityPort}" ]]; then
        echoContent yellow "Please enterport[return车random10000-30000]"

        read -r -p "port:" realityPort
        if [[ -z "${realityPort}" ]]; then
            realityPort=$((RANDOM % 20001 + 10000))
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
        echoContent yellow "\n ---> port: ${realityPort}"
    fi

}
# 初始化XHTTPport
initXrayXHTTPort() {
    if [[ -n "${xrayVLESSRealityXHTTPort}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "ReadtouptimeInstallremember录，yesnomakeuseuptimeInstall时的port ？[y/n]:" historyXHTTPortStatus
        if [[ "${historyXHTTPortStatus}" == "y" ]]; then
            xHTTPort=${xrayVLESSRealityXHTTPort}
        fi
    elif [[ -n "${xrayVLESSRealityXHTTPort}" && -n "${lastInstallationConfig}" ]]; then
        xHTTPort=${xrayVLESSRealityXHTTPort}
    fi

    if [[ -z "${xHTTPort}" ]]; then

        echoContent yellow "Please enterport[return车random10000-30000]"
        read -r -p "port:" xHTTPort
        if [[ -z "${xHTTPort}" ]]; then
            xHTTPort=$((RANDOM % 20001 + 10000))
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
        echoContent yellow "\n ---> port: ${xHTTPort}"
    fi
}

# realitymanagearrange
manageReality() {
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig

    if ! echo "${currentInstallProtocolType}" | grep -q -E "7,|8," || [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> invite先InstallRealityprotocol，并Confirm已Configureavailable的 serverName/public key。"
        exit 0
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

# Installreality scanner
installRealityScanner() {
    if [[ ! -f "/etc/v2ray-agent/xray/reality_scan/RealiTLScanner-linux-64" ]]; then
        version=$(curl -s https://api.github.com/repos/XTLS/RealiTLScanner/releases?per_page=1 | jq -r '.[]|.tag_name')
        wget -c -q -P /etc/v2ray-agent/xray/reality_scan/ "https://github.com/XTLS/RealiTLScanner/releases/download/${version}/RealiTLScanner-linux-64"
        chmod 655 /etc/v2ray-agent/xray/reality_scan/RealiTLScanner-linux-64
    fi
}
# reality scanner
realityScanner() {
    echoContent skyBlue "\nProgress 1/1 : sweep描Realitydomain"
    echoContent red "\n=============================================================="
    echoContent yellow "# focus意事项"
    echoContent yellow "sweep描Completeback，invite自line检checksweep描网stand结果inside容yesnocombine规，need个人acknowledge担风险"
    echoContent red "某些IDC不allowsweep描操作，compare如move瓦工，其middle风险invite自lineacknowledge担\n"
    echoContent yellow "1.sweep描IPv4"
    echoContent yellow "2.sweep描IPv6"
    echoContent red "=============================================================="
    read -r -p "Please select:" realityScannerStatus
    local type=
    if [[ "${realityScannerStatus}" == "1" ]]; then
        type=4
    elif [[ "${realityScannerStatus}" == "2" ]]; then
        type=6
    fi

    read -r -p "某些IDC不allowsweep描操作，compare如move瓦工，其middle风险invite自lineacknowledge担，Continue?？[y/n]:" scanStatus

    if [[ "${scanStatus}" != "y" ]]; then
        exit 0
    fi

    publicIP=$(getPublicIP "${type}")
    echoContent yellow "IP:${publicIP}"
    if [[ -z "${publicIP}" ]]; then
        echoContent red " ---> cannotGetIP"
        exit 0
    fi

    read -r -p "IPyesnocorrect？[y/n]:" ipStatus
    if [[ "${ipStatus}" == "y" ]]; then
        echoContent yellow "结果save储at /etc/v2ray-agent/xray/reality_scan/result.log filemiddle\n"
        /etc/v2ray-agent/xray/reality_scan/RealiTLScanner-linux-64 -addr "${publicIP}" | tee /etc/v2ray-agent/xray/reality_scan/result.log
    else
        echoContent red " ---> cannotReadcorrectIP"
    fi
}
# hysteriamanagearrange
manageHysteria() {
    echoContent skyBlue "\nProgress  1/1 : Hysteria2 managearrange"
    echoContent red "\n=============================================================="
    local hysteria2Status=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/v2ray-agent/sing-box/conf/config/06_hysteria2_inbounds.json" ]]; then
        echoContent yellow "dependency第三squaresing-box\n"
        echoContent yellow "1.heavynewInstall"
        echoContent yellow "2.Uninstall"
        echoContent yellow "3.port hoppingmanagearrange"
        hysteria2Status=true
    else
        echoContent yellow "dependencysing-boxinsideverify\n"
        echoContent yellow "1.Install"
    fi

    echoContent red "=============================================================="
    read -r -p "Please select:" installHysteria2Status
    if [[ "${installHysteria2Status}" == "1" ]]; then
        singBoxHysteria2Install
    elif [[ "${installHysteria2Status}" == "2" && "${hysteria2Status}" == "true" ]]; then
        unInstallSingBox hysteria2
    elif [[ "${installHysteria2Status}" == "3" && "${hysteria2Status}" == "true" ]]; then
        portHoppingMenu hysteria2
    fi
}

# tuicmanagearrange
manageTuic() {
    echoContent skyBlue "\nProgress  1/1 : Tuicmanagearrange"
    echoContent red "\n=============================================================="
    local tuicStatus=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/v2ray-agent/sing-box/conf/config/09_tuic_inbounds.json" ]]; then
        echoContent yellow "dependencysing-boxinsideverify\n"
        echoContent yellow "1.heavynewInstall"
        echoContent yellow "2.Uninstall"
        echoContent yellow "3.port hoppingmanagearrange"
        tuicStatus=true
    else
        echoContent yellow "dependencysing-boxinsideverify\n"
        echoContent yellow "1.Install"
    fi

    echoContent red "=============================================================="
    read -r -p "Please select:" installTuicStatus
    if [[ "${installTuicStatus}" == "1" ]]; then
        singBoxTuicInstall
    elif [[ "${installTuicStatus}" == "2" && "${tuicStatus}" == "true" ]]; then
        unInstallSingBox tuic
    elif [[ "${installTuicStatus}" == "3" && "${tuicStatus}" == "true" ]]; then
        portHoppingMenu tuic
    fi
}
# sing-box loglog
singBoxLog() {
    cat <<EOF >/etc/v2ray-agent/sing-box/conf/config/log.json
{
  "log": {
    "disabled": $1,
    "level": "warn",
    "output": "/etc/v2ray-agent/sing-box/conf/box.log",
    "timestamp": true
  }
}
EOF

    handleSingBox stop
    handleSingBox start
}

# sing-box versionmanagearrange
singBoxVersionManageMenu() {
    echoContent skyBlue "\nProgress  $1/${totalProgress} : sing-box versionmanagearrange"
    if [[ -z "${singBoxConfigPath}" ]]; then
        echoContent red " ---> 没haveDetecttoInstall程序，invite执linescriptInstallinside容"
        menu
        exit 0
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.Upgrade sing-box"
    echoContent yellow "2.disable sing-box"
    echoContent yellow "3.open sing-box"
    echoContent yellow "4.Restart sing-box"
    echoContent yellow "=============================================================="
    local logStatus=
    if [[ -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}log.json" && "$(jq -r .log.disabled "${singBoxConfigPath}log.json")" == "false" ]]; then
        echoContent yellow "5.disablelog"
        logStatus=true
    else
        echoContent yellow "5.启uselog"
        logStatus=false
    fi

    echoContent yellow "6.Viewlog"
    echoContent red "=============================================================="

    read -r -p "Please select:" selectSingBoxType
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

# Main Menu
menu() {
    cd "$HOME" || exit
    echoContent red "\n=============================================================="
    echoContent green "作者：Lynthar"
    echoContent green "currentversion：v3.5.1"
    echoContent green "Github：https://github.com/Lynthar/Proxy-agent"
    echoContent green "描述：八combine一共savescript"
    showInstallStatus
    checkWgetShowProgress
    if [[ -n "${coreInstallType}" ]]; then
        echoContent yellow "1.heavynewInstall"
    else
        echoContent yellow "1.Install"
    fi

    echoContent yellow "2.任意groupcombineInstall"
    echoContent yellow "3.chain proxymanagearrange"
    echoContent yellow "4.Hysteria2managearrange"
    echoContent yellow "5.REALITYmanagearrange"
    echoContent yellow "6.Tuicmanagearrange"

    echoContent skyBlue "-------------------------toolmanagearrange-----------------------------"
    echoContent yellow "7.User Management"
    echoContent yellow "8.Camouflage Site Management"
    echoContent yellow "9.Certificate Management"
    echoContent yellow "10.CDNsaveclickmanagearrange"
    echoContent yellow "11.routingtool"
    echoContent yellow "12.Addnewport"
    echoContent yellow "13.BTdownloadmanagearrange"
    echoContent yellow "15.domain黑名单"
    echoContent skyBlue "-------------------------versionmanagearrange-----------------------------"
    echoContent yellow "16.coremanagearrange"
    echoContent yellow "17.Updatescript"
    echoContent yellow "18.InstallBBR、DDscript"
    echoContent skyBlue "-------------------------scriptmanagearrange-----------------------------"
    echoContent yellow "20.Uninstallscript"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -r -p "Please select:" selectInstallType
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
    esac
}
cronFunction
menu
