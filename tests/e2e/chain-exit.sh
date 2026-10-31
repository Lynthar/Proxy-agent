#!/usr/bin/env bash
# chain-exit.sh - run.sh chain 的出口机一侧，在容器里以 root 跑：E2E_EXIT_CORE（xray / singbox）一键 Reality，
# 再经菜单 3 → 1 → 1 配成链式出口。stdout 只打一行配置码（给入口导入），过程都进 stderr；任一步不对就非零退出
set -uo pipefail

INSTALL_ROOT=/etc/Proxy-agent
CHAIN_PORT=24680
LOG=/tmp/proxy-agent-e2e-exit.log
E2E_EXIT_CORE="${E2E_EXIT_CORE:-xray}"

fail() {
    echo "✗ 出口机：$1" >&2
    tail -n 40 "${LOG}" >&2
    exit 1
}

if [[ "${E2E_EXIT_CORE}" != "xray" && "${E2E_EXIT_CORE}" != "singbox" ]]; then
    echo "E2E_EXIT_CORE 只能是 xray 或 singbox，收到 ${E2E_EXIT_CORE}" >&2
    exit 2
fi

cp /src/install.sh /src/VERSION /root/
cp -r /src/lib /root/lib
mkdir -p /root/shell
cp -r /src/shell/lang /root/shell/lang

# 答案与 test_install_e2e.sh 同序：Xray 问 UUID、用户名、端口、目标、私钥；sing-box 先问目标再问端口
echo "=== 出口机：菜单 19：${E2E_EXIT_CORE} 一键 Reality ===" >&2
case "${E2E_EXIT_CORE}" in
xray) printf '19\n1\n%s\n%s\n\n%s:443\n\n' 22222222-3333-4444-5555-666666666666 exituser dl.google.com ;;
*) printf '19\n2\n%s\n%s\n%s:443\n\n' 22222222-3333-4444-5555-666666666666 exituser dl.google.com ;;
esac | V2RAY_LANG=en bash /root/install.sh >"${LOG}" 2>&1 || fail "一键 Reality 安装失败"

# 端口、是否限制来源 IP（回车不限）、出站网络策略（回车优先 IPv4）
echo "=== 出口机：菜单 3 → 1 → 1：配成链式出口，端口 ${CHAIN_PORT} ===" >&2
printf '3\n1\n1\n%s\n\n\n' "${CHAIN_PORT}" | V2RAY_LANG=en pasly >"${LOG}" 2>&1 || fail "配置链式出口失败"
chainCode=$(sed 's/\x1b\[[0-9;]*m//g' "${LOG}" | grep -o 'chain://[^[:space:]]*' | head -n 1)
[[ -n "${chainCode}" ]] || fail "输出里没有配置码"
jq -e --argjson p "${CHAIN_PORT}" 'any(.inbounds[]; .tag == "chain_inbound" and .listen_port == $p)' \
    "${INSTALL_ROOT}/sing-box/conf/config.json" >/dev/null || fail "合并后的 sing-box 配置里没有 chain_inbound:${CHAIN_PORT}"
pgrep -x sing-box >/dev/null || fail "sing-box 没在跑"
timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${CHAIN_PORT}" 2>/dev/null || fail "${CHAIN_PORT} 没有在监听"
echo "✓ 出口机就绪：sing-box 在 ${CHAIN_PORT} 上收链式流量" >&2
printf '%s\n' "${chainCode}"
