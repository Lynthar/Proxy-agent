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
# 上一次由脚本起这个内核的脚本版本。和当前版本不同，说明在跑的内核没用上本版的启动前修正：自更新不重启内核
readonly XRAY_STARTED_VERSION_FILE="${XRAY_DIR}/started_version"
readonly SINGBOX_STARTED_VERSION_FILE="${SINGBOX_DIR}/started_version"
# 链式代理与外部节点的状态文件住在 sing-box/conf 根，不是 conf/config/ 片段目录，merge 不读它们
readonly CHAIN_EXIT_INFO="${SINGBOX_CONF_DIR}/chain_exit_info.json"
readonly CHAIN_RELAY_INFO="${SINGBOX_CONF_DIR}/chain_relay_info.json"
readonly CHAIN_ENTRY_INFO="${SINGBOX_CONF_DIR}/chain_entry_info.json"
readonly CHAIN_MULTI_INFO="${SINGBOX_CONF_DIR}/chain_multi_info.json"
# 链式入口里 Xray 进 sing-box 的本机 socks 桥。按账号选出口在多链路里另开的桥占 +1 到 LAST，整段对代理用户封掉；
# 低于 Linux 临时端口段，也不与 randomPort 的 10000-30000 重叠
readonly CHAIN_BRIDGE_PORT=31111
readonly CHAIN_BRIDGE_PORT_LAST=31210
# 路由总览页面的端口：桥端口段最后一个，这段两边内核都按端口封，成员写成解析到 127.0.0.1 的域名也连不到。分桥端口时要跳过它
readonly TOPO_PAGE_PORT="${CHAIN_BRIDGE_PORT_LAST}"
# 拼车统计 API 从紧挨桥端口段的这段里挑：本机封锁按端口封、对所有目标生效，被封的端口因此都在 31111-31299 之内
readonly CARPOOL_API_PORT_FIRST=31211
readonly CARPOOL_API_PORT_LAST=31299
readonly EXTERNAL_NODE_FILE="${SINGBOX_CONF_DIR}/external_node_info.json"
readonly TLS_DIR="${PROXY_AGENT_DIR}/tls"
readonly SUBSCRIBE_DIR="${PROXY_AGENT_DIR}/subscribe"
readonly SUBSCRIBE_LOCAL_DIR="${PROXY_AGENT_DIR}/subscribe_local"
readonly SUBSCRIBE_REMOTE_DIR="${PROXY_AGENT_DIR}/subscribe_remote"
# 15 的 VLESS Encryption：服务端 600 秒票据，客户端 0rtt，认证用 X25519（末段分别是私钥与 xray x25519 -i 推出的 Password）
readonly XHTTP_TLS_DECRYPTION_PREFIX="mlkem768x25519plus.native.600s."
readonly XHTTP_TLS_ENCRYPTION_PREFIX="mlkem768x25519plus.native.0rtt."
# 订阅文件上次完整重建时的脚本版本：与 SCRIPT_VERSION 不同，菜单入口就沿用 salt 静默重建一次，新版的节点写法不用等机主查看订阅
readonly SUBSCRIBE_BUILT_VERSION_FILE="${SUBSCRIBE_LOCAL_DIR}/built_version"
# subscribe.conf 第一行记的模板修订号：renderSubscribeConf 的输出一改就加一，旧号的机器进菜单时按原端口与域名重写
readonly SUBSCRIBE_CONF_REVISION=3
# 订阅响应的 subscription-userinfo 从这个 nginx map 来；文件名要与 renderSubscribeConf 里 include 的通配对得上
readonly SUBSCRIBE_USERINFO_MAP="${PROXY_AGENT_DIR}/subscribe_userinfo.map"
readonly WARP_DIR="${PROXY_AGENT_DIR}/warp"
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

# Reality 入站显式写的最低客户端版本。Xray-core 26.7.11、26.7.28 两个预发布未写时默认 26.3.27，会拒掉脚本自己
# 发的 sing-box/clash 订阅（sing-box 1.14.4 及更早报 1.8.1、mihomo 与 1.14.5 起的 sing-box 报 1.8.2）；26.9.9 起没有默认值。
# 只用 Xray 客户端、想收紧的用户可手动改成 26.3.27
readonly REALITY_MIN_CLIENT_VER="1.8.0"
# Reality 目标选本机域名时转交连接的落点：nginx 只在回环上听、用这个域名的证书。不指订阅端口（订阅一改一删 Reality 就断），
# 也不经公网 IP 回连自己（云上的 1:1 NAT 常常不回环）。避开端口池、链式桥与拼车 API 段、nginx 的 31300 / 31302 回落
readonly REALITY_LOCAL_DEST_PORT=31305
# 15（VLESS+XHTTP+TLS）的入站只在回环上听，nginx 的 h2 块按路径 grpc_pass 到这里。与上面同样避开那些段，也避开 sing-box 11 的 31306
readonly XHTTP_TLS_LOCAL_PORT=31307

# Xray-core 的默认版本。26.9.9 起 REALITY 服务端要求 ClientHello 带 X25519MLKEM768 份额，官方 sing-box 1.14.5 才不再剥掉它
# （SagerNet/sing-box#4520）：更早的 sing-box 系客户端连 7 / 12 报 reality verification failed。升级菜单装这个版本
readonly XRAY_PINNED_VERSION="v26.11.9"
# Xray 直连出站的 finalRules：26.10.31 起 freedom 把 NAT64 前缀算进私有段，经 vless / vmess / trojan 进来的连接拨到它就进黑洞，
# 纯 IPv6、靠 DNS64 出 IPv4 的机器上几乎全断。用户规则排在默认规则前面；更早的 Xray 不认这个字段，照常加载
readonly XRAY_DIRECT_FINAL_RULES='[{"action":"allow","ip":["64:ff9b::/96","64:ff9b:1::/48"]}]'

# nginx.org 官网（linux_packages.html）公布的软件包签名钥指纹：Debian / Ubuntu 配 nginx.org 源前，下到的钥文件里必须有这一把
readonly NGINX_SIGNING_KEY_FPR="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"

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
