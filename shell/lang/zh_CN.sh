#!/usr/bin/env bash
# Chinese (Simplified) Language File
# 中文语言文件

# System messages
MSG_SCRIPT_NOT_SUPPORTED="本脚本不支持此系统，请将下方日志反馈给开发者"
MSG_CPU_NOT_SUPPORTED="此CPU架构不支持"
MSG_DEFAULT_AMD64="无法识别CPU架构，默认使用amd64/x86_64"
MSG_NON_ROOT_USER="检测到非 Root 用户，将使用 sudo 执行命令..."
MSG_SELINUX_NOTICE="检测到SELinux已启用。请手动禁用（例如在/etc/selinux/config中设置SELINUX=disabled并重启）。"

# Progress messages
MSG_PROGRESS="进度"
MSG_INSTALL_TOOLS="安装工具"
MSG_INSTALL_ACME="安装acme.sh"
MSG_INSTALL_NGINX="安装Nginx"
MSG_APPLY_CERT="申请TLS证书"
MSG_INSTALL_XRAY="安装Xray"
MSG_INSTALL_SINGBOX="安装sing-box"
MSG_CONFIG_XRAY="配置Xray"
MSG_CONFIG_SINGBOX="配置sing-box"
MSG_ADD_USERS="添加用户"

# Status messages
MSG_SUCCESS="成功"
MSG_FAILED="失败"
MSG_COMPLETE="完成"
MSG_ERROR="错误"
MSG_WARNING="警告"
MSG_NOTICE="提示"
MSG_RUNNING="运行中"
MSG_NOT_RUNNING="未运行"
MSG_INSTALLED="已安装"
MSG_NOT_INSTALLED="未安装"
MSG_ENABLED="已启用"
MSG_NOT_ENABLED="未启用"

# Core messages
MSG_CORE_XRAY="核心: Xray-core"
MSG_CORE_SINGBOX="核心: sing-box"
MSG_CURRENT_CORE="当前核心"
MSG_CORE_VERSION="核心版本"

# Menu items
MSG_MENU_MAIN="主菜单"
MSG_MENU_ACCOUNT="账号管理"
MSG_MENU_INSTALL="安装"
MSG_MENU_UNINSTALL="卸载"
MSG_MENU_UPDATE="更新"
MSG_MENU_CONFIG="配置"
MSG_MENU_CERT="证书管理"
MSG_MENU_ROUTING="分流管理"
MSG_MENU_SUBSCRIPTION="订阅管理"
MSG_MENU_LOGS="查看日志"
MSG_MENU_EXIT="退出"
MSG_MENU_RETURN="返回主菜单"

# Input prompts
MSG_PROMPT_SELECT="请选择"
MSG_PROMPT_ENTER="请输入"
MSG_PROMPT_CONFIRM="请确认"
MSG_PROMPT_DOMAIN="请输入域名"
MSG_PROMPT_PORT="请输入端口"
MSG_PROMPT_PATH="请输入路径"
MSG_PROMPT_USE_LAST_CONFIG="检测到上次安装的配置，是否使用？[y/n]"
MSG_PROMPT_CONTINUE="是否继续？[y/n]"

# Port messages
MSG_PORT_OPEN_SUCCESS="端口开放成功"
MSG_PORT_OPEN_FAILED="端口开放失败"
MSG_PORT_CONFLICT="端口冲突"
MSG_PORT_OCCUPIED="端口被占用"

# Certificate messages
MSG_CERT_VALID="证书有效"
MSG_CERT_EXPIRED="证书过期"
MSG_CERT_ABOUT_EXPIRE="证书即将过期"
MSG_CERT_APPLY="申请证书"
MSG_CERT_RENEW="续签证书"
MSG_CERT_DAYS_REMAINING="剩余天数"

# Domain messages
MSG_DOMAIN_VERIFY="验证域名"
MSG_DOMAIN_MISMATCH="域名解析IP与当前服务器IP不一致"
MSG_DOMAIN_CHECK_HINT="请检查域名解析是否生效和正确"
MSG_DNS_RESOLVED="DNS解析 IP"
MSG_DOMAIN_VERIFY_PASS="域名IP校验通过"

# Installation messages
MSG_INSTALL_START="开始安装"
MSG_INSTALL_COMPLETE="安装完成"
MSG_INSTALL_FAILED="安装失败"
MSG_UNINSTALL_COMPLETE="卸载完成"
MSG_UPDATE_COMPLETE="更新完成"

# Configuration messages
MSG_CONFIG_SAVED="配置已保存"
MSG_CONFIG_LOADED="配置已加载"
MSG_CONFIG_BACKUP="配置已备份"
MSG_CONFIG_RESTORE="配置已恢复"
MSG_OTHER_CONFIG_DETECTED="检测到有其他配置，保留核心"

# Error messages
MSG_ERR_GITHUB_FETCH="获取Github文件失败，请等待Github恢复后尝试"
MSG_ERR_ACME_BUG="acme.sh脚本出现bug"
MSG_ERR_IPV6_NAT64="如纯IPv6机器，请设置NAT64"
MSG_ERR_TROUBLESHOOT="错误排查"
MSG_ERR_WARP_ARM="官方WARP客户端不支持ARM架构"
MSG_ERR_DNS_IPV6="无法通过DNS获取域名IPv6地址，退出安装"
MSG_ERR_PORT_CHECK="端口未检测到开放，退出安装"
MSG_ERR_CLOUDFLARE_HINT="请关闭云朵后等待三分钟重试"
MSG_ERR_FIREWALL_HINT="请检查是否有网页防火墙，比如Oracle等云服务商"
MSG_ERR_NGINX_CONFLICT="检查是否自己安装过nginx并且有配置冲突"

# Panel messages
MSG_READING_BT_PANEL="读取宝塔配置"
MSG_READING_1PANEL="读取1Panel配置"

# Firewall messages
MSG_FIREWALL_ACTIVE="防火墙已启用，添加开放端口"

# Service messages
MSG_SERVICE_START="启动服务"
MSG_SERVICE_STOP="停止服务"
MSG_SERVICE_RESTART="重启服务"
MSG_BOOT_STARTUP="开机启动"

# Clean messages
MSG_CLEAN_OLD="清理旧残留"

# Subscription messages
MSG_SUBSCRIPTION_URL="订阅地址"
MSG_SUBSCRIPTION_GENERATE="生成订阅"

# WARP messages
MSG_INSTALL_WARP="安装WARP"
MSG_WARP_FAILED="安装WARP失败"

# Protocol display
MSG_INSTALLED_PROTOCOLS="已安装协议"
