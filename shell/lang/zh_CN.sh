#!/usr/bin/env bash
# =============================================================================
# Chinese (Simplified) Language File / 简体中文语言文件
# v2ray-agent i18n System
# =============================================================================

# =============================================================================
# 系统消息 - System Messages
# =============================================================================
MSG_SYS_NOT_SUPPORTED="本脚本不支持此系统，请将下方日志反馈给开发者"
MSG_SYS_CPU_NOT_SUPPORTED="不支持此 CPU 架构"
MSG_SYS_CPU_DEFAULT_AMD64="无法识别 CPU 架构，默认使用 amd64/x86_64"
MSG_SYS_NON_ROOT="检测到非 root 用户，将使用 sudo 执行命令..."
MSG_SYS_SELINUX_NOTICE="检测到 SELinux 已启用，请手动禁用（在 /etc/selinux/config 设置 SELINUX=disabled 并重启）"

# =============================================================================
# 菜单 - Menu
# =============================================================================
MSG_MENU_TITLE="八合一共存脚本"
MSG_MENU_AUTHOR="作者"
MSG_MENU_VERSION="当前版本"
MSG_MENU_GITHUB="Github"
MSG_MENU_DESC="描述"
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
MSG_MENU_EXIT="退出"
MSG_MENU_RETURN="返回主菜单"

# =============================================================================
# 进度提示 - Progress Messages
# =============================================================================
MSG_PROGRESS="进度"
MSG_PROGRESS_STEP="进度 %s/%s"
MSG_PROG_INSTALL_TOOLS="安装工具"
MSG_PROG_INSTALL_NGINX="安装 Nginx"
MSG_PROG_INIT_NGINX="初始化 Nginx 申请证书配置"
MSG_PROG_APPLY_CERT="申请 TLS 证书"
MSG_PROG_GEN_PATH="生成随机路径"
MSG_PROG_ADD_DISGUISE="添加伪装站点"
MSG_PROG_ADD_CRON="添加定时维护证书"
MSG_PROG_UPDATE_CERT="更新证书"
MSG_PROG_INSTALL_XRAY="安装 Xray"
MSG_PROG_INSTALL_SINGBOX="安装 sing-box"
MSG_PROG_CONFIG_XRAY="配置 Xray"
MSG_PROG_CONFIG_SINGBOX="配置 sing-box"
MSG_PROG_VERIFY_SERVICE="验证服务启动状态"
MSG_PROG_CONFIG_BOOT="配置开机自启"
MSG_PROG_INIT_HYSTERIA2="初始化 Hysteria2 配置"
MSG_PROG_PORT_HOPPING="端口跳跃"
MSG_PROG_XRAY_VERSION="Xray 版本管理"
MSG_PROG_SINGBOX_VERSION="sing-box 版本管理"
MSG_PROG_SCAN_REALITY="扫描 Reality 域名"

# =============================================================================
# 状态消息 - Status Messages
# =============================================================================
MSG_STATUS_SUCCESS="成功"
MSG_STATUS_FAILED="失败"
MSG_STATUS_COMPLETE="完成"
MSG_STATUS_ERROR="错误"
MSG_STATUS_WARNING="警告"
MSG_STATUS_NOTICE="提示"
MSG_STATUS_RUNNING="运行中"
MSG_STATUS_NOT_RUNNING="未运行"
MSG_STATUS_INSTALLED="已安装"
MSG_STATUS_NOT_INSTALLED="未安装"
MSG_STATUS_ENABLED="已启用"
MSG_STATUS_NOT_ENABLED="未启用"
MSG_STATUS_VALID="有效"
MSG_STATUS_INVALID="无效"
MSG_STATUS_EXPIRED="已过期"

# =============================================================================
# 输入提示 - Input Prompts
# =============================================================================
MSG_PROMPT_SELECT="请选择"
MSG_PROMPT_ENTER="请输入"
MSG_PROMPT_CONFIRM="请确认 [y/n]"
MSG_PROMPT_CONTINUE="是否继续？[y/n]"
MSG_PROMPT_DOMAIN="请输入域名"
MSG_PROMPT_DOMAIN_EXAMPLE="请输入要配置的域名，例: example.com"
MSG_PROMPT_PORT="请输入端口"
MSG_PROMPT_PORT_RANDOM="请输入端口 [回车随机 10000-30000]"
MSG_PROMPT_PORT_DEFAULT="请输入端口 [默认: %s]，可自定义端口 [回车使用默认]"
MSG_PROMPT_PATH="请输入路径"
MSG_PROMPT_PATH_CUSTOM="请输入自定义路径 [例: alone]，不需要斜杠，[回车] 随机路径"
MSG_PROMPT_UUID="请输入自定义 UUID [需合法]，[回车] 随机 UUID"
MSG_PROMPT_EMAIL="请输入自定义用户名 [需合法]，[回车] 随机用户名"
MSG_PROMPT_USE_LAST="检测到上次安装配置，是否使用？[y/n]"
MSG_PROMPT_USE_LAST_DOMAIN="检测到上次安装记录，是否使用上次安装时的域名？[y/n]"
MSG_PROMPT_USE_LAST_PORT="检测到上次安装时的端口，是否使用？[y/n]"
MSG_PROMPT_USE_LAST_PATH="检测到上次安装记录，是否使用上次安装时的 path 路径？[y/n]"
MSG_PROMPT_USE_LAST_UUID="检测到上次用户配置，是否使用上次安装的配置？[y/n]"
MSG_PROMPT_USE_LAST_KEY="检测到上次安装记录，是否使用上次安装时的 PublicKey/PrivateKey？[y/n]"
MSG_PROMPT_INPUT_NUM="请输入编号选择"
MSG_PROMPT_SELECT_ERROR="选择错误，请重新选择"
MSG_PROMPT_REINSTALL="是否重新安装？[y/n]"
MSG_PROMPT_UPDATE="是否更新、升级？[y/n]"
MSG_PROMPT_OVERWRITE="是否覆盖现有配置？[y/n]"

# =============================================================================
# 安装消息 - Installation Messages
# =============================================================================
MSG_INSTALL_START="开始安装"
MSG_INSTALL_COMPLETE="安装完成"
MSG_INSTALL_FAILED="安装失败"
MSG_INSTALL_SUCCESS="安装成功"
MSG_INSTALL_SKIP="跳过安装"
MSG_INSTALL_CHECKING="检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"
MSG_INSTALL_TOOL="安装 %s"
MSG_INSTALL_DETECT_NO_NGINX="检测到无需依赖 Nginx 的服务，跳过安装"
MSG_INSTALL_DETECT_NO_CERT="检测到无需依赖证书的服务，跳过安装"

MSG_UNINSTALL_COMPLETE="卸载完成"
MSG_UNINSTALL_CONFIRM="是否确认卸载安装内容？[y/n]"
MSG_UNINSTALL_SINGBOX="sing-box 卸载完成"

MSG_UPDATE_COMPLETE="更新完成"
MSG_UPDATE_ABANDON="放弃更新"
MSG_UPDATE_REINSTALL_ABANDON="放弃重新安装"
MSG_UPDATE_ROLLBACK_ABANDON="放弃回退版本"

# =============================================================================
# 核心/协议 - Core/Protocol Messages
# =============================================================================
MSG_CORE_XRAY="Xray-core"
MSG_CORE_SINGBOX="sing-box"
MSG_CORE_CURRENT="核心: %s"
MSG_CORE_CURRENT_RUNNING="核心: %s [运行中]"
MSG_CORE_CURRENT_STOPPED="核心: %s [未运行]"
MSG_CORE_VERSION="核心版本"
MSG_CORE_VERSION_CURRENT="当前版本: %s"
MSG_CORE_VERSION_LATEST="最新版本: %s"
MSG_CORE_VERSION_SAME="当前版本与最新版相同，是否重新安装？[y/n]"
MSG_CORE_DOWNLOAD_FAILED="核心下载失败，请重新尝试安装，是否重新尝试？[y/n]"
MSG_CORE_NOT_DETECTED="没有检测到安装目录，请执行脚本安装内容"

MSG_PROTOCOLS_INSTALLED="已安装协议"
MSG_PROTOCOL_DEPENDS="依赖 %s"

# Xray 版本管理菜单
MSG_XRAY_UPGRADE="升级 Xray-core"
MSG_XRAY_UPGRADE_PRE="升级 Xray-core 预览版"
MSG_XRAY_ROLLBACK="回退 Xray-core"
MSG_XRAY_STOP="关闭 Xray-core"
MSG_XRAY_START="打开 Xray-core"
MSG_XRAY_RESTART="重启 Xray-core"
MSG_XRAY_UPDATE_GEO="更新 geosite、geoip"
MSG_XRAY_AUTO_GEO="设置自动更新 geo 文件 [每天凌晨更新]"
MSG_XRAY_VIEW_LOG="查看日志"
MSG_XRAY_ROLLBACK_NOTICE_1="只可以回退最近的五个版本"
MSG_XRAY_ROLLBACK_NOTICE_2="不保证回退后一定可以正常使用"
MSG_XRAY_ROLLBACK_NOTICE_3="如果回退的版本不支持当前的 config，则会无法连接，谨慎操作"
MSG_XRAY_ROLLBACK_CONFIRM="回退版本为 %s，是否继续？[y/n]"
MSG_XRAY_ROLLBACK_INPUT="请输入要回退的版本"
MSG_XRAY_UPDATE_CONFIRM="最新版本为: %s，是否更新？[y/n]"
MSG_XRAY_GEO_SOURCE="来源 https://github.com/Loyalsoldier/v2ray-rules-dat"

# sing-box 版本管理菜单
MSG_SINGBOX_UPGRADE="升级 sing-box"
MSG_SINGBOX_STOP="关闭 sing-box"
MSG_SINGBOX_START="打开 sing-box"
MSG_SINGBOX_RESTART="重启 sing-box"
MSG_SINGBOX_LOG_ENABLE="启用日志"
MSG_SINGBOX_LOG_DISABLE="关闭日志"
MSG_SINGBOX_VIEW_LOG="查看日志"

# =============================================================================
# 端口消息 - Port Messages
# =============================================================================
MSG_PORT="端口"
MSG_PORT_CURRENT="端口: %s"
MSG_PORT_OPEN_SUCCESS="%s 端口开放成功"
MSG_PORT_OPEN_FAILED="%s 端口开放失败"
MSG_PORT_CONFLICT="端口冲突"
MSG_PORT_OCCUPIED="端口 %s 被占用，请手动关闭后安装"
MSG_PORT_EMPTY="端口不可为空"
MSG_PORT_INVALID="端口不合法"
MSG_PORT_INPUT_ERROR="端口输入错误"
MSG_PORT_DETECTED_OPEN="检测到 %s 端口已开放"
MSG_PORT_NOT_DETECTED="未检测到 %s 端口开放，退出安装"
MSG_PORT_BT_CONFLICT="请输入端口 [不可与 BT Panel/1Panel 端口相同，回车随机]"
MSG_PORT_RANGE="端口范围: %s"

# 端口跳跃
MSG_PORT_HOP_TITLE="端口跳跃"
MSG_PORT_HOP_ADD="添加端口跳跃"
MSG_PORT_HOP_DEL="删除端口跳跃"
MSG_PORT_HOP_VIEW="查看端口跳跃"
MSG_PORT_HOP_NOTICE_1="仅支持 Hysteria2、Tuic"
MSG_PORT_HOP_NOTICE_2="端口跳跃的起始位置为 30000"
MSG_PORT_HOP_NOTICE_3="端口跳跃的结束位置为 40000"
MSG_PORT_HOP_NOTICE_4="可以在 30000-40000 范围中选一段"
MSG_PORT_HOP_NOTICE_5="建议 1000 个左右"
MSG_PORT_HOP_NOTICE_6="注意不要和其他的端口跳跃设置范围一样，设置相同会覆盖"
MSG_PORT_HOP_INPUT="请输入端口跳跃的范围，例如 [30000-31000]"
MSG_PORT_HOP_EMPTY="范围不可为空"
MSG_PORT_HOP_INVALID="范围不合法"
MSG_PORT_HOP_SUCCESS="端口跳跃添加成功"
MSG_PORT_HOP_FAILED="端口跳跃添加失败"
MSG_PORT_HOP_DEL_SUCCESS="删除成功"
MSG_PORT_HOP_CURRENT="当前端口跳跃范围为: %s-%s"
MSG_PORT_HOP_NOT_SET="未设置端口跳跃"
MSG_PORT_HOP_NO_FIREWALL="未启动 firewalld 防火墙，无法设置端口跳跃"
MSG_PORT_HOP_NO_IPTABLES="无法识别 iptables 工具，无法使用端口跳跃，退出安装"
MSG_PORT_HOP_ALREADY_SET="已添加不可重复添加，可删除后重新添加"

# =============================================================================
# 证书消息 - Certificate Messages
# =============================================================================
MSG_CERT_VALID="证书有效"
MSG_CERT_EXPIRED="证书过期"
MSG_CERT_ABOUT_EXPIRE="证书即将过期"
MSG_CERT_DAYS_LEFT="剩余 %s 天"
MSG_CERT_DETECTED="检测到证书"
MSG_CERT_APPLY="申请证书"
MSG_CERT_RENEW="续签证书"
MSG_CERT_RENEW_AUTO="证书过期前最后一天自动更新，如更新失败请手动更新"
MSG_CERT_CHECK_DATE="证书检查日期: %s"
MSG_CERT_GEN_DATE="证书生成日期: %s"
MSG_CERT_GEN_DAYS="证书生成天数: %s"
MSG_CERT_REMAINING="证书剩余天数: %s"
MSG_CERT_REGENERATE="重新生成证书"
MSG_CERT_CUSTOM_NOTICE="检测到使用自定义证书，无法执行 renew 操作"
MSG_CERT_NOT_EXPIRED="如未过期或者自定义证书请选择 [n]"
MSG_CERT_TLS_SUCCESS="TLS 生成成功"
MSG_CERT_TLS_FAILED="TLS 安装失败，请检查 acme 日志"
MSG_CERT_TLS_DEPEND="安装 TLS 证书，需要依赖 80 端口"
MSG_CERT_NO_API="不采用 API 申请证书"
MSG_CERT_API_DNS="是否使用 DNS API 申请证书 [支持 NAT]？[y/n]"
MSG_CERT_API_WILDCARD="是否使用 *.%s 进行 API 申请通配符证书？[y/n]"
MSG_CERT_API_NOT_SUPPORT="不支持此域名申请通配符证书，建议使用此格式 [xx.xx.xx]"
MSG_CERT_CRON_SUCCESS="添加定时维护证书成功"
MSG_CERT_CRON_EXISTS="已添加自动更新定时任务，请不要重复添加"
MSG_CERT_GEO_CRON_SUCCESS="添加定时更新 geo 文件成功"

# ACME
MSG_ACME_NOT_INSTALLED="未安装 acme.sh"
MSG_ACME_INSTALL_FAILED="acme 安装失败"
MSG_ACME_ERROR_TROUBLESHOOT="错误排查"
MSG_ACME_ERROR_GITHUB="获取 Github 文件失败，请等待 Github 恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
MSG_ACME_ERROR_BUG="acme.sh 脚本出现 bug，可查看 [https://github.com/acmesh-official/acme.sh] issues"
MSG_ACME_ERROR_IPV6="如纯 IPv6 机器，请设置 NAT64，可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他 NAT64"
MSG_ACME_EMAIL_INVALID="邮箱无法通过 SSL 厂商验证，请重新输入"
MSG_ACME_EMAIL_INPUT="请输入邮箱地址"
MSG_ACME_EMAIL_RETRY="是否重新输入邮箱地址 [y/n]"
MSG_ACME_EMAIL_FORMAT="请重新输入正确的邮箱格式 [例: username@example.com]"
MSG_ACME_EMAIL_ADDED="添加完毕"

# DNS API
MSG_DNS_API_SELECT="请选择 DNS 提供商"
MSG_DNS_CLOUDFLARE="Cloudflare [默认]"
MSG_DNS_ALIYUN="Aliyun"
MSG_DNS_CF_TOKEN_HINT="请在 Cloudflare 控制台为 DNS 编辑权限创建 API Token 并填入 CF_Token/CF_Account_ID"
MSG_DNS_INPUT_TOKEN="请输入 API Token"
MSG_DNS_INPUT_EMPTY="输入为空，请重新输入"
MSG_DNS_INPUT_ALI_KEY="请输入 Ali Key"
MSG_DNS_INPUT_ALI_SECRET="请输入 Ali Secret"
MSG_DNS_GEN_CERT="DNS API 生成证书中"

# SSL Provider
MSG_SSL_SELECT="请选择 SSL 证书提供商"
MSG_SSL_LETSENCRYPT="Let's Encrypt [默认]"
MSG_SSL_ZEROSSL="ZeroSSL"
MSG_SSL_BUYPASS="Buypass [不支持 DNS 申请]"
MSG_SSL_BUYPASS_NOT_SUPPORT="Buypass 不支持 API 申请证书"
MSG_SSL_GEN_CERT="生成证书中"

# =============================================================================
# 域名消息 - Domain Messages
# =============================================================================
MSG_DOMAIN="域名"
MSG_DOMAIN_CURRENT="域名: %s"
MSG_DOMAIN_VERIFY="验证域名"
MSG_DOMAIN_VERIFYING="检查域名 IP 中"
MSG_DOMAIN_MISMATCH="域名解析 IP 与当前服务器 IP 不一致"
MSG_DOMAIN_CHECK_HINT="请检查域名解析是否生效以及正确"
MSG_DOMAIN_SERVER_IP="当前 VPS IP: %s"
MSG_DOMAIN_DNS_IP="DNS 解析 IP: %s"
MSG_DOMAIN_VERIFY_PASS="域名 IP 校验通过"
MSG_DOMAIN_CHECK_CORRECT="检查当前域名 IP 正确"
MSG_DOMAIN_NOT_DETECTED="未检测到当前域名的 IP"
MSG_DOMAIN_CHECK_LIST="请依次进行下列检查"
MSG_DOMAIN_CHECK_1="检查域名是否书写正确"
MSG_DOMAIN_CHECK_2="检查域名 DNS 解析是否正确"
MSG_DOMAIN_CHECK_3="如解析正确，请等待 DNS 生效，预计三分钟内生效"
MSG_DOMAIN_CHECK_4="如报 Nginx 启动问题，请手动启动 nginx 查看错误，如自己无法处理请提 issues"
MSG_DOMAIN_REINSTALL_HINT="如以上设置都正确，请重新安装纯净系统后再次尝试"
MSG_DOMAIN_ABNORMAL="检测返回值异常，建议手动卸载 nginx 后重新执行脚本"
MSG_DOMAIN_ABNORMAL_RESULT="异常结果: %s"
MSG_DOMAIN_MULTI_IP="检测到多个 IP，请确认是否关闭 Cloudflare 的云朵"
MSG_DOMAIN_CF_WAIT="关闭云朵后等待三分钟后重试"
MSG_DOMAIN_DETECTED_IP="检测到的 IP 如下: [%s]"
MSG_DOMAIN_EMPTY="域名不可为空"
MSG_DOMAIN_INPUT="域名"

# =============================================================================
# 服务控制 - Service Control Messages
# =============================================================================
MSG_SVC_START="启动 %s"
MSG_SVC_STOP="停止 %s"
MSG_SVC_RESTART="重启 %s"
MSG_SVC_START_SUCCESS="%s 启动成功"
MSG_SVC_START_FAILED="%s 启动失败"
MSG_SVC_STOP_SUCCESS="%s 关闭成功"
MSG_SVC_STOP_FAILED="%s 关闭失败"
MSG_SVC_BOOT_CONFIG="配置 %s 开机自启"
MSG_SVC_BOOT_SUCCESS="配置 %s 开机启动完毕"
MSG_SVC_VERIFY_SUCCESS="服务启动成功"
MSG_SVC_VERIFY_FAILED="服务启动失败，请检查终端是否有日志打印"

# Nginx
MSG_NGINX_START_SUCCESS="Nginx 启动成功"
MSG_NGINX_START_FAILED="Nginx 启动失败"
MSG_NGINX_STOP_SUCCESS="Nginx 关闭成功"
MSG_NGINX_UNINSTALL="nginx 卸载完成"
MSG_NGINX_UNINSTALL_CONFIRM="检测到当前的 Nginx 版本不支持 gRPC，会导致安装失败，是否卸载 Nginx 后重新安装？[y/n]"
MSG_NGINX_DEL_DEFAULT="删除 Nginx 默认配置"
MSG_NGINX_DEV_LOG="请将下方日志反馈给开发者"
MSG_NGINX_SELINUX_CHECK="检查 SELinux 端口是否开放"
MSG_NGINX_SELINUX_PORT_OK="http_port_t %s 端口开放成功"

# 手动命令提示
MSG_MANUAL_CMD_XRAY="请手动执行以下的命令后【/etc/v2ray-agent/xray/xray -confdir /etc/v2ray-agent/xray/conf】将错误日志进行反馈"
MSG_MANUAL_CMD_SINGBOX_MERGE="请手动执行【 /etc/v2ray-agent/sing-box/sing-box merge config.json -C /etc/v2ray-agent/sing-box/conf/config/ -D /etc/v2ray-agent/sing-box/conf/ 】，查看错误日志"
MSG_MANUAL_CMD_SINGBOX_RUN="如上面命令没有错误，请手动执行【 /etc/v2ray-agent/sing-box/sing-box run -c /etc/v2ray-agent/sing-box/conf/config.json 】，查看错误日志"
MSG_MANUAL_CMD_KILL="请手动执行【ps -ef|grep -v grep|grep %s|awk '{print \$2}'|xargs kill -9】"

# =============================================================================
# 配置消息 - Configuration Messages
# =============================================================================
MSG_CONFIG_SAVED="配置已保存"
MSG_CONFIG_LOADED="配置已加载"
MSG_CONFIG_BACKUP="配置已备份"
MSG_CONFIG_RESTORE="配置已恢复"
MSG_CONFIG_OTHER_DETECTED="检测到有其他配置，保留 %s 核心"
MSG_CONFIG_DEL_SUCCESS="删除 %s 配置成功"
MSG_CONFIG_USE_SUCCESS="使用成功"
MSG_CONFIG_REALITY="配置 VLESS+Reality"
MSG_CONFIG_PROTOCOL="配置 %s"
MSG_CONFIG_PROTOCOL_PORT="开始配置 %s 协议端口"
MSG_CONFIG_PORT_RESULT="%s 端口: %s"

# Path
MSG_PATH="路径"
MSG_PATH_CURRENT="path: %s"
MSG_PATH_WS_SUFFIX="自定义 path 结尾不可用 ws 结尾，否则无法区分分流路径"

# =============================================================================
# 错误消息 - Error Messages
# =============================================================================
MSG_ERR_GITHUB_FETCH="获取 Github 文件失败，请等待 Github 恢复后尝试"
MSG_ERR_ACME_BUG="acme.sh 脚本出现 bug"
MSG_ERR_IPV6_NAT64="如纯 IPv6 机器，请设置 NAT64"
MSG_ERR_TROUBLESHOOT="错误排查"
MSG_ERR_WARP_ARM="官方 WARP 客户端不支持 ARM 架构"
MSG_ERR_DNS_IPV4="无法通过 DNS 获取域名 IPv4 地址"
MSG_ERR_DNS_IPV6="无法通过 DNS 获取域名 IPv6 地址，退出安装"
MSG_ERR_DNS_TRY_IPV6="尝试检查域名 IPv6 地址"
MSG_ERR_PORT_CHECK="端口未检测到开放，退出安装"
MSG_ERR_CLOUDFLARE_HINT="请关闭云朵后等待三分钟重新尝试"
MSG_ERR_FIREWALL_HINT="请检查是否有网页防火墙，比如 Oracle 等云服务商"
MSG_ERR_NGINX_CONFLICT="检查是否自己安装过 nginx 并且有配置冲突，可以尝试 DD 纯净系统后重新尝试"
MSG_ERR_LOG="错误日志: %s，请将此错误日志通过 issues 提交反馈"
MSG_ERR_FILE_PATH_INVALID="文件路径无效"
MSG_ERR_NOT_EMPTY="%s 不可为空"
MSG_ERR_INPUT_INVALID="输入有误，请重新输入"
MSG_ERR_JSON_PARSE="%s 解析失败，已移除，请检查上方录入并重试"
MSG_ERR_UUID_READ="uuid 读取错误，随机生成"
MSG_ERR_PRIVATE_KEY_INVALID="输入的 Private Key 不合法"
MSG_ERR_IP_READ="无法读取正确 IP"
MSG_ERR_IP_GET="无法获取 IP"
MSG_ERR_CERT_DEPEND="由于需要依赖证书，如安装 %s，请先安装带有 TLS 标识协议"

# =============================================================================
# WARP 消息 - WARP Messages
# =============================================================================
MSG_WARP_INSTALL="安装 WARP"
MSG_WARP_INSTALL_FAILED="安装 WARP 失败"
MSG_WARP_START_SUCCESS="WARP 启动成功"
MSG_WARP_NOT_INSTALLED="warp-reg 未安装，是否安装？[y/n]"

# =============================================================================
# 面板消息 - Panel Messages
# =============================================================================
MSG_PANEL_BT_READ="读取宝塔配置"
MSG_PANEL_1PANEL_READ="读取 1Panel 配置"

# =============================================================================
# 防火墙消息 - Firewall Messages
# =============================================================================
MSG_FIREWALL_ACTIVE="防火墙已启用，添加开放端口"

# =============================================================================
# 订阅消息 - Subscription Messages
# =============================================================================
MSG_SUB_URL="订阅地址"
MSG_SUB_GENERATE="生成订阅"

# =============================================================================
# 用户管理 - User Management Messages
# =============================================================================
MSG_USER_ADD="添加用户"
MSG_USER_ADD_COUNT="请输入要添加的用户数量"
MSG_USER_DEL="删除用户"
MSG_USER_DEL_SELECT="请选择要删除的用户编号 [仅支持单个删除]"
MSG_USER_INFO="%s: %s"

# =============================================================================
# 伪装站点 - Disguise Site Messages
# =============================================================================
MSG_DISGUISE_START="开始添加伪装站点"
MSG_DISGUISE_SUCCESS="添加伪装站点成功"
MSG_DISGUISE_REINSTALL="检测到安装伪装站点，是否需要重新安装 [y/n]"

# =============================================================================
# CDN 消息 - CDN Messages
# =============================================================================
MSG_CDN_INPUT="请输入想要自定义 CDN IP 或者域名"

# =============================================================================
# Reality 消息 - Reality Messages
# =============================================================================
MSG_REALITY_CONFIG_SN="配置客户端可用的 serverNames"
MSG_REALITY_NOTICE="请确保所选 Reality 目标域名支持 TLS，且为可直连的常见站点"
MSG_REALITY_INPUT_EXAMPLE="录入示例: addons.mozilla.org:443"
MSG_REALITY_INPUT_DOMAIN="请输入目标域名，[回车] 随机域名，默认端口 443"
MSG_REALITY_USE_DOMAIN="是否使用 %s 此域名作为 Reality 目标域名？[y/n]"
MSG_REALITY_USE_LAST="检测到上次安装设置的 Reality 域名，是否使用？[y/n]"
MSG_REALITY_CLIENT_DOMAIN="客户端可用域名: %s:%s"
MSG_REALITY_NOT_INSTALLED="请先安装 Reality 协议，并确认已配置可用的 serverName/公钥"
MSG_REALITY_CF_WARNING="检测到使用的域名，托管在 Cloudflare 并开启了代理，使用此类型域名可能导致 VPS 流量被其他人使用 [不建议使用]"
MSG_REALITY_IGNORE_RISK="忽略风险，继续使用"
MSG_REALITY_GEN_MLDSA65="生成 Reality mldsa65"
MSG_REALITY_X25519_SUPPORT="目标域名支持 X25519MLKEM768，但是证书的长度不足，忽略 ML-DSA-65"
MSG_REALITY_X25519_NOT_SUPPORT="目标域名不支持 X25519MLKEM768，忽略 ML-DSA-65"
MSG_REALITY_USE_LAST_SEED="检测到上次安装记录，是否使用上次安装时的 Seed/Verify？[y/n]"
MSG_REALITY_INPUT_PRIVATE_KEY="请输入 Private Key [回车自动生成]"

# Reality Scanner
MSG_REALITY_SCAN_IPV4="扫描 IPv4"
MSG_REALITY_SCAN_IPV6="扫描 IPv6"
MSG_REALITY_SCAN_NOTICE_1="扫描完成后，请自行检查扫描网站结果内容是否合规，需个人承担风险"
MSG_REALITY_SCAN_NOTICE_2="某些 IDC 不允许扫描操作，比如搬瓦工，其中风险请自行承担"
MSG_REALITY_SCAN_CONFIRM="某些 IDC 不允许扫描操作，比如搬瓦工，其中风险请自行承担，是否继续？[y/n]"
MSG_REALITY_SCAN_RESULT="结果存储在 /etc/v2ray-agent/xray/reality_scan/result.log 文件中"
MSG_REALITY_IP_CONFIRM="IP 是否正确？[y/n]"

# =============================================================================
# Hysteria2 消息 - Hysteria2 Messages
# =============================================================================
MSG_HYSTERIA2_PORT="请输入 Hysteria 端口 [回车随机 10000-30000]，不可与其他服务重复"
MSG_HYSTERIA2_DOWN_SPEED="请输入本地带宽峰值的下行速度（默认: 100，单位: Mbps）"
MSG_HYSTERIA2_UP_SPEED="请输入本地带宽峰值的上行速度（默认: 50，单位: Mbps）"
MSG_HYSTERIA2_DOWN_RESULT="下行速度: %s"
MSG_HYSTERIA2_UP_RESULT="上行速度: %s"
MSG_HYSTERIA2_OBFS_HINT="是否启用混淆 (obfs)? 留空不启用，输入密码则启用 salamander 混淆"
MSG_HYSTERIA2_OBFS_INPUT="混淆密码 (留空不启用)"
MSG_HYSTERIA2_OBFS_ENABLED="混淆已启用"
MSG_HYSTERIA2_OBFS_DISABLED="混淆未启用"
MSG_HYSTERIA2_MANAGE="Hysteria2 管理"
MSG_HYSTERIA2_DEBUG="请手动执行【/etc/v2ray-agent/hysteria/hysteria --log-level debug -c /etc/v2ray-agent/hysteria/conf/config.json server】，查看错误日志"

# =============================================================================
# Tuic 消息 - Tuic Messages
# =============================================================================
MSG_TUIC_PORT="请输入 Tuic 端口 [回车随机 10000-30000]，不可与其他服务重复"
MSG_TUIC_PORT_RESULT="端口: %s"
MSG_TUIC_ALGO="算法: %s"
MSG_TUIC_ALGO_SELECT="请选择算法类型"
MSG_TUIC_ALGO_BBR="bbr (默认)"
MSG_TUIC_ALGO_CUBIC="cubic"
MSG_TUIC_ALGO_NEWRENO="new_reno"
MSG_TUIC_USE_LAST_ALGO="检测到上次使用的算法，是否使用？[y/n]"
MSG_TUIC_MANAGE="Tuic 管理"

# =============================================================================
# SS2022 消息 - Shadowsocks 2022 Messages
# =============================================================================
MSG_SS2022_PORT="请输入 Shadowsocks 2022 端口 [回车随机 10000-30000]"
MSG_SS2022_PORT_RESULT="端口: %s"
MSG_SS2022_METHOD_SELECT="请选择加密方式"
MSG_SS2022_METHOD_1="2022-blake3-aes-128-gcm [推荐，密钥较短]"
MSG_SS2022_METHOD_2="2022-blake3-aes-256-gcm"
MSG_SS2022_METHOD_3="2022-blake3-chacha20-poly1305"
MSG_SS2022_METHOD_RESULT="加密方式: %s"
MSG_SS2022_KEY_GEN="服务器密钥已自动生成"
MSG_SS2022_CONFIG_DONE="Shadowsocks 2022 配置完成"
MSG_SS2022_USE_LAST_PORT="检测到上次安装时的端口 %s，是否使用？[y/n]"

# =============================================================================
# TCP_Brutal 消息 - TCP_Brutal Messages
# =============================================================================
MSG_TCP_BRUTAL_USE="是否使用 TCP_Brutal？[y/n]"
MSG_TCP_BRUTAL_DOWN="请输入本地带宽峰值的下行速度（默认: 100，单位: Mbps）"
MSG_TCP_BRUTAL_UP="请输入本地带宽峰值的上行速度（默认: 50，单位: Mbps）"
MSG_TCP_BRUTAL_INIT="初始化 TCP_Brutal 配置"

# =============================================================================
# 链式代理 - Chain Proxy Messages
# =============================================================================
MSG_CHAIN_CODE="配置码"
MSG_CHAIN_EXIT_IP="出口节点 IP"
MSG_CHAIN_EXIT_PORT="出口节点端口"
MSG_CHAIN_EXIT_KEY="密钥"
MSG_CHAIN_EXIT_METHOD="加密方式"
MSG_CHAIN_DOWNSTREAM="配置码"
MSG_CHAIN_PUBLIC_IP="公网 IP"
MSG_CHAIN_LIMIT_IP="请选择"
MSG_CHAIN_LIMIT_ALLOW="请输入允许连接的入口节点 IP"

# 多链路分流 - Multi-Chain Split Routing Messages
MSG_MULTI_CHAIN_TITLE="配置入口节点 (多链路分流模式)"
MSG_MULTI_CHAIN_DESC="此模式允许将不同流量分流到不同的出口节点"
MSG_MULTI_CHAIN_EXAMPLE="例如: Netflix → 美国出口, OpenAI → 香港出口"
MSG_MULTI_CHAIN_SINGLE_EXISTS="检测到已存在单链路配置"
MSG_MULTI_CHAIN_UNINSTALL_HINT="如需使用多链路分流模式，请先卸载现有链式代理配置"
MSG_MULTI_CHAIN_MENU_PATH="菜单路径: 链式代理管理 → 卸载链式代理"
MSG_MULTI_CHAIN_EXISTS="检测到已存在多链路配置"
MSG_MULTI_CHAIN_ADD_MORE="继续添加新链路"
MSG_MULTI_CHAIN_RECONFIGURE="重新配置 (将清除现有配置)"
MSG_MULTI_CHAIN_CANCEL="取消"
MSG_MULTI_CHAIN_CONFIRM_CLEAR="确认清除现有多链路配置？[y/n]"
MSG_MULTI_CHAIN_SELECT_MODE="请选择配置方式:"
MSG_MULTI_CHAIN_MODE_INTERACTIVE="逐个添加链路 (推荐)"
MSG_MULTI_CHAIN_MODE_BATCH="批量导入配置码"
MSG_MULTI_CHAIN_ADD_CHAIN="添加链路"
MSG_MULTI_CHAIN_ADD_FAILED="链路添加失败或已取消"
MSG_MULTI_CHAIN_CONTINUE_ADD="是否继续添加链路？[y/n]"
MSG_MULTI_CHAIN_NO_CHAIN="未添加任何链路，配置已取消"
MSG_MULTI_CHAIN_BATCH_TITLE="批量导入配置码"
MSG_MULTI_CHAIN_BATCH_HINT="请逐行粘贴配置码，每行一个"
MSG_MULTI_CHAIN_BATCH_END="输入完成后输入空行结束"
MSG_MULTI_CHAIN_PARSE_FAILED="配置码解析失败，已跳过"
MSG_MULTI_CHAIN_ADD_SUCCESS="链路 [%s] 添加成功 (%s:%s)"
MSG_MULTI_CHAIN_IMPORT_NONE="未导入任何链路，配置已取消"
MSG_MULTI_CHAIN_IMPORT_SUCCESS="成功导入 %s 条链路"
MSG_MULTI_CHAIN_CONFIGURE_RULES="是否现在配置分流规则？[y/n]"
MSG_MULTI_CHAIN_STEP_IMPORT="步骤 1/3: 导入配置"
MSG_MULTI_CHAIN_PASTE_CODE="请粘贴出口/中继节点的配置码:"
MSG_MULTI_CHAIN_STEP_NAME="步骤 2/3: 命名链路"
MSG_MULTI_CHAIN_CHAIN_INFO="链路信息:"
MSG_MULTI_CHAIN_TARGET="目标"
MSG_MULTI_CHAIN_PROTOCOL="协议"
MSG_MULTI_CHAIN_INPUT_NAME="请输入链路名称 (仅字母数字下划线，回车使用默认: %s):"
MSG_MULTI_CHAIN_NAME_EXISTS="链路名称已存在，请使用其他名称"
MSG_MULTI_CHAIN_NAME_INVALID="链路名称无效，仅允许字母数字下划线"
MSG_MULTI_CHAIN_STEP_RULES="步骤 3/3: 配置分流规则"
MSG_MULTI_CHAIN_RULE_HINT="选择此链路处理的流量类型 (可多选，逗号分隔):"
MSG_MULTI_CHAIN_RULE_STREAMING="流媒体 (Netflix/Disney+/YouTube/...)"
MSG_MULTI_CHAIN_RULE_AI="AI服务 (OpenAI/Bing/...)"
MSG_MULTI_CHAIN_RULE_SOCIAL="社交媒体 (Telegram/Twitter/...)"
MSG_MULTI_CHAIN_RULE_DEV="开发者 (GitHub/GitLab/...)"
MSG_MULTI_CHAIN_RULE_GAMING="游戏 (Steam/Epic/...)"
MSG_MULTI_CHAIN_RULE_GOOGLE="谷歌服务"
MSG_MULTI_CHAIN_RULE_CUSTOM="自定义域名规则"
MSG_MULTI_CHAIN_RULE_NONE="暂不配置 (稍后设置)"
MSG_MULTI_CHAIN_CUSTOM_DOMAIN="请输入自定义域名 (支持通配符，逗号分隔):"
MSG_MULTI_CHAIN_CUSTOM_EXAMPLE="例如: *.example.com, api.test.org"
MSG_MULTI_CHAIN_CONFIG_SUCCESS="链路配置完成"
MSG_MULTI_CHAIN_CONFIG_SAVED="配置已保存"
MSG_MULTI_CHAIN_STATUS_TITLE="多链路分流状态"
MSG_MULTI_CHAIN_TOTAL_CHAINS="链路总数: %s"
MSG_MULTI_CHAIN_DEFAULT_CHAIN="默认链路: %s"
MSG_MULTI_CHAIN_NO_DEFAULT="未设置默认链路 (未匹配流量直连)"
MSG_MULTI_CHAIN_LIST="链路列表:"
MSG_MULTI_CHAIN_RULES="分流规则:"
MSG_MULTI_CHAIN_RULE_ALL="所有未匹配流量"
MSG_MULTI_CHAIN_RULE_PENDING="待配置"
MSG_MULTI_CHAIN_RULE_CUSTOM_DOMAIN="自定义域名"
MSG_MULTI_CHAIN_TEST_TITLE="多链路连通性测试"
MSG_MULTI_CHAIN_TESTING="正在并行测试所有链路..."
MSG_MULTI_CHAIN_TEST_SUCCESS="✅ %s (%s) - 延迟: %sms"
MSG_MULTI_CHAIN_TEST_FAILED="❌ %s (%s) - 连接失败"
MSG_MULTI_CHAIN_TEST_RESULT="测试结果: %s/%s 链路正常"
MSG_MULTI_CHAIN_ADV_MENU="多链路高级设置"
MSG_MULTI_CHAIN_ADV_ADD="添加新链路"
MSG_MULTI_CHAIN_ADV_REMOVE="删除链路"
MSG_MULTI_CHAIN_ADV_DEFAULT="设置默认链路"
MSG_MULTI_CHAIN_ADV_RULES="管理分流规则"
MSG_MULTI_CHAIN_ADV_VIEW="查看详细配置"
MSG_MULTI_CHAIN_SELECT_REMOVE="请选择要删除的链路:"
MSG_MULTI_CHAIN_CONFIRM_REMOVE="确认删除链路 [%s]？[y/n]"
MSG_MULTI_CHAIN_REMOVED="链路已删除"
MSG_MULTI_CHAIN_SELECT_DEFAULT="请选择默认链路 (未匹配流量将使用此链路):"
MSG_MULTI_CHAIN_DIRECT="直连 (未匹配流量直连访问)"
MSG_MULTI_CHAIN_DEFAULT_SET="默认链路已设置为: %s"
MSG_MULTI_CHAIN_DEFAULT_DIRECT="默认链路已设置为直连"
MSG_MULTI_CHAIN_DETECTED="检测到多链路分流模式，共 %s 条链路"
MSG_MULTI_CHAIN_SINGLE_DETECTED="检测到单链路模式"
MSG_MULTI_CHAIN_NOT_FOUND="未检测到链式代理配置"
MSG_MULTI_CHAIN_DELETED="已删除多链路分流配置"

# =============================================================================
# 凭据输入 - Credential Input Messages
# =============================================================================
MSG_CRED_HINT="%s 用于配置双方握手的凭据，可手动/文件/环境变量方式录入"
MSG_CRED_SELECT="请选择 %s 录入方式（自动化部署可用文件或环境变量）"
MSG_CRED_DIRECT="直接输入"
MSG_CRED_DIRECT_DEFAULT="直接输入 [回车默认]"
MSG_CRED_FROM_FILE="从文件读取"
MSG_CRED_FROM_ENV="从环境变量读取"
MSG_CRED_FILE_PATH="请输入文件路径"
MSG_CRED_ENV_NAME="请输入环境变量名称"

# =============================================================================
# BBR 消息 - BBR Messages
# =============================================================================
MSG_BBR_INSTALL="安装 BBR"

# =============================================================================
# 分流工具 - Routing Tools Messages
# =============================================================================
MSG_ROUTING_IPV6="IPv6 分流"
MSG_ROUTING_DOMAIN="域名分流"
MSG_ROUTING_INPUT_DOMAIN="请按照上面示例录入域名"
MSG_ROUTING_CONFIRM="是否确认设置？[y/n]"

# =============================================================================
# 黑名单 - Blacklist Messages
# =============================================================================
MSG_BLACKLIST_DOMAIN="域名黑名单"
MSG_BLACKLIST_INPUT="请按照上面示例录入域名"

# =============================================================================
# 日志 - Log Messages
# =============================================================================
MSG_LOG_ACCESS="访问日志"
MSG_LOG_LEVEL="日志级别"
MSG_LOG_SELECT="请选择"

# =============================================================================
# 通用 - Common Messages
# =============================================================================
MSG_NOTICE="注意事项"
MSG_VERSION="版本"
MSG_DEFAULT="默认"
MSG_CUSTOM="自定义"
MSG_RANDOM="随机"
MSG_YES="是"
MSG_NO="否"
MSG_ENABLED="已启用"
MSG_DISABLED="已禁用"
MSG_CANCEL="取消"
MSG_CONFIRM="确认"
MSG_BACK="返回"
MSG_NEXT="下一步"
MSG_PREV="上一步"
MSG_FINISH="完成"
MSG_LOADING="加载中..."
MSG_PROCESSING="处理中..."
MSG_PLEASE_WAIT="请稍候..."

# =============================================================================
# 客户端输出格式 - Client Output Format Messages
# =============================================================================
MSG_CLIENT_GENERAL="通用格式"
MSG_CLIENT_FORMATTED="格式化明文"
MSG_CLIENT_QRCODE="二维码"
MSG_CLIENT_JSON="通用 JSON"
MSG_CLIENT_LINK="链接"
MSG_CLIENT_PROTOCOL="协议类型"
MSG_CLIENT_ADDRESS="地址"
MSG_CLIENT_PORT="端口"
MSG_CLIENT_USER_ID="用户 ID"
MSG_CLIENT_SECURITY="安全"
MSG_CLIENT_TRANSPORT="传输方式"
MSG_CLIENT_PATH="路径"
MSG_CLIENT_ACCOUNT="账户名"
MSG_CLIENT_SNI="SNI"
MSG_CLIENT_FINGERPRINT="client-fingerprint"
MSG_CLIENT_FLOW="flow"
MSG_CLIENT_PUBLIC_KEY="publicKey"
MSG_CLIENT_SHORT_ID="shortId"
MSG_CLIENT_SERVER_NAME="serverNames"

# =============================================================================
# 脚本版本管理 - Script Version Management Messages
# =============================================================================
MSG_MENU_SCRIPT_VERSION="脚本版本管理"
MSG_SCRIPT_VERSION_TITLE="脚本版本管理"
MSG_SCRIPT_VERSION_CURRENT="当前版本"
MSG_SCRIPT_VERSION_UPDATE="更新脚本"
MSG_SCRIPT_VERSION_ROLLBACK="回退版本"
MSG_SCRIPT_VERSION_BACKUP="手动备份"
MSG_SCRIPT_VERSION_LIST="查看备份"
MSG_SCRIPT_VERSION_BACK="返回主菜单"
MSG_SCRIPT_BACKUP_SUCCESS="备份成功"
MSG_SCRIPT_BACKUP_FAILED="备份失败"
MSG_SCRIPT_BACKUP_SKIP="跳过备份 (首次安装或无可用版本)"
MSG_SCRIPT_ROLLBACK_SELECT="选择要回退的版本"
MSG_SCRIPT_ROLLBACK_LOCAL="本地备份"
MSG_SCRIPT_ROLLBACK_GITHUB="GitHub Release"
MSG_SCRIPT_ROLLBACK_NO_VERSIONS="没有可用的版本"
MSG_SCRIPT_ROLLBACK_CONFIRM="确认回退到此版本?"
MSG_SCRIPT_ROLLBACK_SUCCESS="回退成功"
MSG_SCRIPT_ROLLBACK_FAILED="回退失败"
MSG_SCRIPT_ROLLBACK_RESTART="请运行 pasly 启动新版本"
MSG_SCRIPT_BACKUP_BEFORE_UPDATE="更新前备份当前版本..."
MSG_SCRIPT_BACKUP_COMPLETE="备份完成"
MSG_SCRIPT_NO_BACKUPS="暂无本地备份"
MSG_SCRIPT_BACKUP_TIME="备份时间"
MSG_SCRIPT_BACKUP_REASON="备份原因"
MSG_SCRIPT_REASON_UPDATE="更新前自动备份"
MSG_SCRIPT_REASON_ROLLBACK="回退前自动备份"
MSG_SCRIPT_REASON_MANUAL="手动备份"
MSG_SCRIPT_ROLLBACK_NOTE1="回退后可能与当前配置不兼容"
MSG_SCRIPT_ROLLBACK_NOTE2="建议回退前先备份重要配置"
MSG_SCRIPT_ROLLBACK_NOTE3="回退不会影响已安装的代理服务配置"
MSG_SCRIPT_GITHUB_UNAVAILABLE="无法获取 GitHub 版本列表"
MSG_CURRENT="当前"
MSG_NOTE="注意事项"

# =============================================================================
# 链式代理菜单 - Chain Proxy Menu Messages
# =============================================================================
MSG_CHAIN_MENU_WIZARD="快速配置向导"
MSG_CHAIN_MENU_STATUS="查看链路状态"
MSG_CHAIN_MENU_TEST="测试链路连通性"
MSG_CHAIN_MENU_ADVANCED="高级设置"
MSG_CHAIN_MENU_UNINSTALL="卸载链式代理"
MSG_RECOMMENDED="推荐"

# =============================================================================
# 外部节点功能 - External Node Messages
# =============================================================================
MSG_EXT_MENU_TITLE="外部节点管理"
MSG_EXT_MENU_OPTIONS="操作选项"
MSG_EXT_NODE_LIST="已配置的外部节点"
MSG_EXT_NO_NODES="暂无外部节点"
MSG_EXT_ADD_BY_LINK="通过链接添加节点"
MSG_EXT_ADD_MANUAL="手动添加节点"
MSG_EXT_DELETE_NODE="删除节点"
MSG_EXT_TEST_NODE="测试节点连通性"
MSG_EXT_SET_AS_EXIT="设为链式代理出口"
MSG_EXT_ADD_SS="添加 Shadowsocks 节点"
MSG_EXT_ADD_SOCKS="添加 SOCKS5 节点"
MSG_EXT_ADD_TROJAN="添加 Trojan 节点"
MSG_EXT_INPUT_SERVER="请输入服务器地址"
MSG_EXT_INPUT_PORT="请输入端口"
MSG_EXT_INPUT_PASSWORD="请输入密码"
MSG_EXT_INPUT_USERNAME="请输入用户名"
MSG_EXT_INPUT_NAME="请输入节点名称"
MSG_EXT_INPUT_SNI="请输入 SNI"
MSG_EXT_SELECT_METHOD="请选择加密方式"
MSG_EXT_SELECT_PROTOCOL="选择协议类型"
MSG_EXT_SERVER_REQUIRED="服务器地址不能为空"
MSG_EXT_PORT_INVALID="端口无效"
MSG_EXT_PASSWORD_REQUIRED="密码不能为空"
MSG_EXT_NODE_ADDED="节点已添加"
MSG_EXT_NODE_DELETED="节点已删除"
MSG_EXT_SKIP_CERT_VERIFY="是否跳过证书验证"
MSG_EXT_SUPPORTED_LINKS="支持的链接格式"
MSG_EXT_PASTE_LINK="请粘贴节点链接"
MSG_EXT_LINK_EMPTY="链接不能为空"
MSG_EXT_LINK_UNSUPPORTED="不支持的链接格式"
MSG_EXT_LINK_PARSE_FAILED="链接解析失败"
MSG_EXT_PARSE_RESULT="解析结果"
MSG_EXT_PROTOCOL="协议"
MSG_EXT_SERVER="服务器"
MSG_EXT_PORT="端口"
MSG_EXT_NAME="名称"
MSG_EXT_CONFIRM_ADD="确认添加"
MSG_EXT_SELECT_DELETE="请选择要删除的节点编号"
MSG_EXT_CONFIRM_DELETE="确认删除"
MSG_EXT_INVALID_SELECTION="选择无效"
MSG_EXT_SELECT_AS_EXIT="请选择作为出口的节点编号"
MSG_EXT_ADD_NODE_FIRST="请先添加外部节点"
MSG_EXT_CONFIGURING="正在配置"
MSG_EXT_CONFIG_FAILED="配置生成失败"
MSG_EXT_CONFIG_SUCCESS="配置完成"
MSG_EXT_TRAFFIC_ROUTE="流量路径"
MSG_EXT_SELECT_TEST="请选择要测试的节点编号"
MSG_EXT_TESTING="正在测试"
MSG_EXT_TCP_SUCCESS="TCP 连接成功"
MSG_EXT_TCP_FAILED="TCP 连接失败"
MSG_USER="用户"
MSG_ENTRY_NODE="入口节点"
MSG_INTERNET="互联网"
MSG_OPTIONAL="可选"
MSG_DISABLED="已禁用"
MSG_YES="是"
MSG_NO="否"

# =============================================================================
# 多链路分流集成 - Multi-Chain Integration Messages
# =============================================================================
MSG_CHAIN_ADD_NUMBER="添加链路"
MSG_CHAIN_ADD_TYPE_SELECT="选择添加方式"
MSG_CHAIN_ADD_BY_CODE="通过配置码添加 (自建节点)"
MSG_CHAIN_ADD_BY_EXTERNAL="通过外部节点添加 (拼车节点)"
MSG_CHAIN_ADD_FAILED="链路添加失败或已取消"
MSG_CHAIN_CONTINUE_ADD="是否继续添加链路"
MSG_CONTINUE="继续"
MSG_INVALID_SELECTION="选择无效"
MSG_EXT_SELECT_FOR_CHAIN="选择要添加为链路的外部节点"
MSG_EXT_ADD_NODE_HINT="请先在外部节点管理中添加节点"
MSG_EXT_SELECTED="已选择"
MSG_EXT_NODE_NOT_FOUND="节点未找到"
MSG_CHAIN_STEP_NAME="步骤: 命名此链路"
MSG_CHAIN_NAME_HINT="请为此链路设置标识名称 (仅限英文字母、数字、下划线)"
MSG_CHAIN_NAME_PROMPT="链路名称"
MSG_CHAIN_NAME_INVALID="名称格式无效，仅允许英文字母、数字、下划线"
MSG_CHAIN_NAME_EXISTS="链路名称已存在"
MSG_CHAIN_STEP_RULES="步骤: 设置分流规则"
MSG_CHAIN_RULES_HINT="选择此链路的分流规则"
MSG_CHAIN_RULE_LATER="稍后统一配置"
MSG_CHAIN_RULE_PRESET="使用预设规则"
MSG_CHAIN_RULE_CUSTOM="自定义域名"
MSG_CHAIN_RULE_DEFAULT="设为默认链路 (接收所有未匹配规则的流量)"
MSG_CHAIN_PRESET_STREAMING="流媒体 (Netflix/Disney+/YouTube/...)"
MSG_CHAIN_PRESET_AI="AI服务 (OpenAI/Bing/...)"
MSG_CHAIN_PRESET_SOCIAL="社交媒体 (Telegram/Twitter/...)"
MSG_CHAIN_PRESET_DEV="开发者 (GitHub/GitLab/...)"
MSG_CHAIN_PRESET_GAMING="游戏 (Steam/Epic/...)"
MSG_CHAIN_PRESET_GOOGLE="谷歌服务"
MSG_CHAIN_PRESET_MICROSOFT="微软服务"
MSG_CHAIN_PRESET_APPLE="苹果服务"
MSG_CHAIN_CUSTOM_DOMAIN_HINT="请输入域名 (逗号分隔，如: example.com,test.org)"
MSG_DOMAIN="域名"
MSG_CHAIN_ADDED="链路添加成功"
MSG_RULES="规则"
MSG_CUSTOM_DOMAIN="自定义域名"
MSG_DEFAULT_CHAIN="默认链路"
MSG_ALL_UNMATCHED="所有未匹配流量"
MSG_PENDING_CONFIG="待配置"
