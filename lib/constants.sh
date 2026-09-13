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
readonly EXTERNAL_NODE_FILE="${SINGBOX_CONF_DIR}/external_node_info.json"
readonly TLS_DIR="${PROXY_AGENT_DIR}/tls"
readonly SUBSCRIBE_DIR="${PROXY_AGENT_DIR}/subscribe"
readonly SUBSCRIBE_LOCAL_DIR="${PROXY_AGENT_DIR}/subscribe_local"
readonly SUBSCRIBE_REMOTE_DIR="${PROXY_AGENT_DIR}/subscribe_remote"
readonly WARP_DIR="${PROXY_AGENT_DIR}/warp"
readonly GEOSITE_LIST_FILE="${PROXY_AGENT_DIR}/geosite/dlc.dat_plain.yml"

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

# ============================================================================
# 脚本版本（SCRIPT_VERSION 由 install.sh 从 VERSION 文件加载，此处仅默认值）
# ============================================================================

: "${SCRIPT_VERSION:=(initial)}"  # 默认版本标识，如果未从VERSION文件加载

# ============================================================================
# 协议 ID 与协议元数据的唯一真源是 protocol-registry.sh，不在本文件。
# 协议 ID 写在用户机器的状态文件里（",0,1,7," 形式），永远不能改号。
# ============================================================================
