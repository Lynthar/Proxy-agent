#!/usr/bin/env bash
# ============================================================================
# constants.sh - Proxy-agent 常量定义（readonly，防误改）
# ============================================================================

# 防止重复加载
[[ -n "${_CONSTANTS_LOADED:-}" ]] && return 0
readonly _CONSTANTS_LOADED=1

# ============================================================================
# 安装根与布局：根可由环境变量覆盖（install.sh 开头已校验），其余全部派生，主脚本不再写字面量
# ============================================================================

readonly PROXY_AGENT_DIR="${PROXY_AGENT_DIR:-/etc/Proxy-agent}"
readonly XRAY_DIR="${PROXY_AGENT_DIR}/xray"
readonly XRAY_BIN="${XRAY_DIR}/xray"
readonly XRAY_CONF_DIR="${XRAY_DIR}/conf"
readonly SINGBOX_DIR="${PROXY_AGENT_DIR}/sing-box"
readonly SINGBOX_BIN="${SINGBOX_DIR}/sing-box"
readonly SINGBOX_CONF_DIR="${SINGBOX_DIR}/conf"
readonly SINGBOX_FRAGMENT_DIR="${SINGBOX_CONF_DIR}/config"
readonly SINGBOX_MERGED_CONFIG="${SINGBOX_CONF_DIR}/config.json"
# 链式代理与外部节点的状态文件住在 sing-box/conf 根，不是 conf/config/ 片段目录，merge 不读它们
readonly CHAIN_EXIT_INFO="${SINGBOX_CONF_DIR}/chain_exit_info.json"
readonly CHAIN_RELAY_INFO="${SINGBOX_CONF_DIR}/chain_relay_info.json"
readonly CHAIN_ENTRY_INFO="${SINGBOX_CONF_DIR}/chain_entry_info.json"
readonly CHAIN_MULTI_INFO="${SINGBOX_CONF_DIR}/chain_multi_info.json"
# 链式入口里 Xray 进 sing-box 的本机 socks 桥。按账号选出口在多链路里另开的桥占 +1 到 LAST，整段对代理用户封掉；
# 低于 Linux 临时端口段，也不与 randomPort 的 10000-30000 重叠
readonly CHAIN_BRIDGE_PORT=31111
readonly CHAIN_BRIDGE_PORT_LAST=31210
# 拼车统计 API 从紧挨桥端口段的这段里挑：本机封锁按端口封、对所有目标生效，被封的端口因此都在 31111-31299 之内
readonly CARPOOL_API_PORT_FIRST=31211
readonly CARPOOL_API_PORT_LAST=31299
readonly EXTERNAL_NODE_FILE="${SINGBOX_CONF_DIR}/external_node_info.json"
readonly TLS_DIR="${PROXY_AGENT_DIR}/tls"
readonly SUBSCRIBE_DIR="${PROXY_AGENT_DIR}/subscribe"
readonly SUBSCRIBE_LOCAL_DIR="${PROXY_AGENT_DIR}/subscribe_local"
readonly SUBSCRIBE_REMOTE_DIR="${PROXY_AGENT_DIR}/subscribe_remote"
# subscribe.conf 第一行记的模板修订号：renderSubscribeConf 的输出一改就加一，旧号的机器进菜单时按原端口与域名重写
readonly SUBSCRIBE_CONF_REVISION=3
# 订阅响应的 subscription-userinfo 从这个 nginx map 来；文件名要与 renderSubscribeConf 里 include 的通配对得上
readonly SUBSCRIBE_USERINFO_MAP="${PROXY_AGENT_DIR}/subscribe_userinfo.map"
readonly WARP_DIR="${PROXY_AGENT_DIR}/warp"
readonly GEOSITE_LIST_FILE="${PROXY_AGENT_DIR}/geosite/dlc.dat_plain.yml"
# 拼车状态住安装根下的 carpool/，不能进 xray/conf：-confdir 会把目录里所有 .json 当配置读
readonly CARPOOL_DIR="${PROXY_AGENT_DIR}/carpool"
readonly CARPOOL_MEMBERS_FILE="${CARPOOL_DIR}/members.json"
readonly CARPOOL_STATE_FILE="${CARPOOL_DIR}/state.json"
readonly CARPOOL_TELEGRAM_FILE="${CARPOOL_DIR}/telegram.conf"
readonly CARPOOL_LOCK_FILE="${CARPOOL_DIR}/.lock"
readonly CARPOOL_LOG_FILE="${PROXY_AGENT_DIR}/crontab_carpool.log"
readonly CARPOOL_PAGE_DIR="${SUBSCRIBE_DIR}/carpool"

# ============================================================================
# 版本下限
# ============================================================================

# 最低支持的 sing-box 版本
# 路由级 sniff/resolve action 需 1.11+；生成的配置还用了 1.12 引入的
# domain_resolver 与新格式 DNS server（{type,tag}），故必须 1.12+
readonly SINGBOX_MIN_VERSION="1.12.0"

# Reality 入站显式写的最低客户端版本。Xray-core 26.7 起未写时默认 26.3.27，会拒掉脚本自己
# 发的 sing-box/clash 订阅（sing-box 系客户端报 1.8.1、mihomo 报 1.8.2）；只用 Xray 客户端、
# 想跟随 Xray 收紧策略的用户可手动改成 26.3.27
readonly REALITY_MIN_CLIENT_VER="1.8.0"
# Reality 目标选本机域名时转交连接的落点：nginx 只在回环上听、用这个域名的证书。不指订阅端口（订阅一改一删 Reality 就断），
# 也不经公网 IP 回连自己（云上的 1:1 NAT 常常不回环）。避开端口池、链式桥与拼车 API 段、nginx 的 31300 / 31302 回落
readonly REALITY_LOCAL_DEST_PORT=31305

# Xray-core 默认钉在官方 sing-box 客户端还能完成 REALITY 握手的最后一个稳定版：26.9.9 起（首个稳定版 26.10.21）服务端要求
# ClientHello 带 X25519MLKEM768 份额，sing-box 会剥掉它（SagerNet/sing-box#4520），脚本发的 sing-box 订阅在 7/12 上报
# reality verification failed。升级菜单可显式装最新版；sing-box 修好前别动
readonly XRAY_PINNED_VERSION="v26.3.27"

# 拼车要的 api.listen 自 Xray 1.8.12 起才有；只拦手动回钉旧核的机器
readonly CARPOOL_XRAY_MIN_VERSION="1.8.12"

# ============================================================================
# 端口
# ============================================================================

# 看起来像 HTTPS / HTTP3 的协议回车时按此顺序取第一个没被占的端口：443，再是 Cloudflare 也转发的
# HTTPS 端口。都被占才回落随机端口
readonly TLS_PORT_POOL="443 8443 2053 2083 2087 2096"

# ============================================================================
# 脚本版本（SCRIPT_VERSION 由 install.sh 从 VERSION 文件加载，此处仅默认值）
# ============================================================================

: "${SCRIPT_VERSION:=(initial)}"  # 默认版本标识，如果未从VERSION文件加载

# ============================================================================
# 协议 ID 与元数据的真源是 protocol-registry.sh；ID 写在用户机器的状态文件里（",0,1,7,"），永不改号
# ============================================================================
