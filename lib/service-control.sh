#!/usr/bin/env bash
# ============================================================================
# service-control.sh - 服务控制模块
# ============================================================================
# 本模块提供服务启动、停止、重启等功能
# 依赖全局变量: release (系统类型)
# ============================================================================

# 防止重复加载
[[ -n "${_SERVICE_CONTROL_LOADED}" ]] && return 0
readonly _SERVICE_CONTROL_LOADED=1

# ============================================================================
# 通用服务控制函数
# 用法: serviceControl "serviceName" "start|stop|restart|status"
# ============================================================================

serviceControl() {
    local serviceName="$1"
    local action="$2"

    if [[ -z "${serviceName}" || -z "${action}" ]]; then
        echoContent red "serviceControl: 缺少参数"
        return 1
    fi

    # 检测服务管理器类型
    if [[ "${release}" == "alpine" ]]; then
        # Alpine 使用 OpenRC
        if [[ -f "/etc/init.d/${serviceName}" ]]; then
            case "${action}" in
                start)
                    rc-service "${serviceName}" start
                    ;;
                stop)
                    rc-service "${serviceName}" stop
                    ;;
                restart)
                    rc-service "${serviceName}" restart
                    ;;
                status)
                    rc-service "${serviceName}" status
                    ;;
            esac
        fi
    else
        # 其他系统使用 systemd
        if [[ -f "/etc/systemd/system/${serviceName}.service" ]] || \
           systemctl list-unit-files 2>/dev/null | grep -q "${serviceName}.service"; then
            case "${action}" in
                start)
                    systemctl start "${serviceName}.service"
                    ;;
                stop)
                    systemctl stop "${serviceName}.service"
                    ;;
                restart)
                    systemctl restart "${serviceName}.service"
                    ;;
                status)
                    systemctl status "${serviceName}.service"
                    ;;
                enable)
                    systemctl enable "${serviceName}.service"
                    ;;
                disable)
                    systemctl disable "${serviceName}.service"
                    ;;
            esac
        fi
    fi
}

# ============================================================================
# 检查进程是否运行
# 用法: if isProcessRunning "xray"; then ...
# ============================================================================

isProcessRunning() {
    local processPattern="$1"
    pgrep -f "${processPattern}" &>/dev/null
}

# ============================================================================
# 获取进程PID
# 用法: pid=$(getProcessPID "xray")
# ============================================================================

getProcessPID() {
    local processPattern="$1"
    pgrep -f "${processPattern}" 2>/dev/null | head -1
}

# ============================================================================
# 强制杀死进程
# 用法: killProcess "xray"
# ============================================================================

killProcess() {
    local processPattern="$1"
    local pids
    pids=$(pgrep -f "${processPattern}" 2>/dev/null)

    if [[ -n "${pids}" ]]; then
        echo "${pids}" | xargs kill -9 2>/dev/null
        return 0
    fi
    return 1
}

# ============================================================================
# Xray 服务控制
# 用法: handleXray start|stop
# ============================================================================

handleXrayService() {
    local action="$1"

    case "${action}" in
        start)
            if ! isProcessRunning "xray/xray"; then
                serviceControl "xray" "start"
                sleep 0.8

                if isProcessRunning "xray/xray"; then
                    echoContent green " ---> Xray启动成功"
                else
                    echoContent red "Xray启动失败"
                    echoContent red "请手动执行: /etc/Proxy-agent/xray/xray -confdir /etc/Proxy-agent/xray/conf"
                    return 1
                fi
            fi
            ;;
        stop)
            if isProcessRunning "xray/xray"; then
                serviceControl "xray" "stop"
                sleep 0.8

                if ! isProcessRunning "xray/xray"; then
                    echoContent green " ---> Xray关闭成功"
                else
                    echoContent red " ---> Xray关闭失败，尝试强制终止"
                    killProcess "xray/xray"
                fi
            fi
            ;;
        restart)
            handleXrayService "stop"
            handleXrayService "start"
            ;;
        status)
            if isProcessRunning "xray/xray"; then
                echoContent green " ---> Xray 运行中 (PID: $(getProcessPID 'xray/xray'))"
            else
                echoContent yellow " ---> Xray 未运行"
            fi
            ;;
    esac
}

# ============================================================================
# sing-box 服务控制
# 用法: handleSingBoxService start|stop
# 注意: 启动前需要调用 singBoxMergeConfig 合并配置
# ============================================================================

handleSingBoxService() {
    local action="$1"

    case "${action}" in
        start)
            if ! isProcessRunning "sing-box"; then
                # 检查并合并配置 (如果函数存在)
                if type singBoxMergeConfig &>/dev/null; then
                    singBoxMergeConfig
                fi

                serviceControl "sing-box" "start"
                sleep 1

                if isProcessRunning "sing-box"; then
                    echoContent green " ---> sing-box启动成功"
                else
                    echoContent red "sing-box启动失败"
                    echoContent yellow "请手动执行检查:"
                    echoContent yellow "  /etc/Proxy-agent/sing-box/sing-box merge config.json -C /etc/Proxy-agent/sing-box/conf/config/ -D /etc/Proxy-agent/sing-box/conf/"
                    return 1
                fi
            fi
            ;;
        stop)
            if isProcessRunning "sing-box"; then
                serviceControl "sing-box" "stop"
                sleep 1

                if ! isProcessRunning "sing-box"; then
                    echoContent green " ---> sing-box关闭成功"
                else
                    echoContent red " ---> sing-box关闭失败，尝试强制终止"
                    killProcess "sing-box"
                fi
            fi
            ;;
        restart)
            handleSingBoxService "stop"
            handleSingBoxService "start"
            ;;
        status)
            if isProcessRunning "sing-box"; then
                echoContent green " ---> sing-box 运行中 (PID: $(getProcessPID 'sing-box'))"
            else
                echoContent yellow " ---> sing-box 未运行"
            fi
            ;;
    esac
}

# ============================================================================
# Nginx 服务控制
# 用法: handleNginxService start|stop
# ============================================================================

handleNginxService() {
    local action="$1"

    case "${action}" in
        start)
            if ! isProcessRunning "nginx"; then
                serviceControl "nginx" "start"
                sleep 0.5

                if isProcessRunning "nginx"; then
                    echoContent green " ---> Nginx启动成功"
                else
                    echoContent red " ---> Nginx启动失败"
                    echoContent red " ---> 查看错误: nginx -t"
                    return 1
                fi
            fi
            ;;
        stop)
            if isProcessRunning "nginx"; then
                serviceControl "nginx" "stop"
                sleep 0.5

                # 如果还在运行，强制杀死 (但不要杀死BT面板的nginx)
                if isProcessRunning "nginx" && [[ -z "${btDomain}" ]]; then
                    killProcess "nginx"
                fi
                echoContent green " ---> Nginx关闭成功"
            fi
            ;;
        restart)
            handleNginxService "stop"
            handleNginxService "start"
            ;;
        reload)
            if isProcessRunning "nginx"; then
                nginx -s reload
                echoContent green " ---> Nginx配置已重载"
            fi
            ;;
        test)
            nginx -t
            ;;
        status)
            if isProcessRunning "nginx"; then
                echoContent green " ---> Nginx 运行中 (PID: $(getProcessPID 'nginx'))"
            else
                echoContent yellow " ---> Nginx 未运行"
            fi
            ;;
    esac
}

# ============================================================================
# 防火墙控制
# 用法: handleFirewall "port" "add|remove" "tcp|udp"
# ============================================================================

handleFirewallPort() {
    local port="$1"
    local action="$2"
    local protocol="${3:-tcp}"

    if [[ -z "${port}" || -z "${action}" ]]; then
        return 1
    fi

    # UFW (Ubuntu/Debian)
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        case "${action}" in
            add)
                ufw allow "${port}/${protocol}" >/dev/null 2>&1
                ;;
            remove)
                ufw delete allow "${port}/${protocol}" >/dev/null 2>&1
                ;;
        esac
    # Firewalld (CentOS/RHEL)
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        case "${action}" in
            add)
                firewall-cmd --permanent --add-port="${port}/${protocol}" >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
                ;;
            remove)
                firewall-cmd --permanent --remove-port="${port}/${protocol}" >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
                ;;
        esac
    # iptables
    elif command -v iptables &>/dev/null; then
        case "${action}" in
            add)
                iptables -I INPUT -p "${protocol}" --dport "${port}" -j ACCEPT 2>/dev/null
                ;;
            remove)
                iptables -D INPUT -p "${protocol}" --dport "${port}" -j ACCEPT 2>/dev/null
                ;;
        esac
    fi
}

# ============================================================================
# 重载所有核心服务
# ============================================================================

reloadAllCores() {
    local xrayRunning=false
    local singBoxRunning=false

    # 检查哪些服务在运行
    isProcessRunning "xray/xray" && xrayRunning=true
    isProcessRunning "sing-box" && singBoxRunning=true

    # 重启运行中的服务
    if [[ "${xrayRunning}" == "true" ]]; then
        handleXrayService "restart"
    fi

    if [[ "${singBoxRunning}" == "true" ]]; then
        handleSingBoxService "restart"
    fi
}

# ============================================================================
# 获取服务状态摘要
# ============================================================================

getServicesStatus() {
    local status=""

    if isProcessRunning "xray/xray"; then
        status+="Xray: 运行中\n"
    else
        status+="Xray: 未运行\n"
    fi

    if isProcessRunning "sing-box"; then
        status+="sing-box: 运行中\n"
    else
        status+="sing-box: 未运行\n"
    fi

    if isProcessRunning "nginx"; then
        status+="Nginx: 运行中\n"
    else
        status+="Nginx: 未运行\n"
    fi

    echo -e "${status}"
}

# ============================================================================
# 等待服务启动
# 用法: waitForService "xray/xray" 10  # 等待最多10秒
# ============================================================================

waitForService() {
    local processPattern="$1"
    local maxWait="${2:-10}"
    local waited=0

    while [[ ${waited} -lt ${maxWait} ]]; do
        if isProcessRunning "${processPattern}"; then
            return 0
        fi
        sleep 1
        ((waited++))
    done

    return 1
}
