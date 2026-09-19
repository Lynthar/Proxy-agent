#!/usr/bin/env bash
# test_install_e2e.sh - 真装机端到端：以 root 在一次性 Linux 容器里跑 install.sh 的「一键 Reality」安装
# （菜单 19 → Xray），装完用 xray run -test、真实 Reality 握手、pasly 重入与 doctor 验收，再卸载。
# 跑法: bash tests/e2e/run.sh alpine|debian（本机与 CI 同一条命令）

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "${expected}" == "${actual}" ]]; then
        echo -e "${GREEN}✓${NC} ${message}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} ${message}"
        echo -e "  Expected: ${expected}"
        echo -e "  Actual: ${actual}"
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo -e "${GREEN}✓${NC} ${message}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} ${message}"
        echo -e "  String '${needle}' not found in output"
        ((TESTS_FAILED++))
    fi
}

assert_not_empty() {
    local value="$1"
    local message="$2"

    if [[ -n "${value}" ]]; then
        echo -e "${GREEN}✓${NC} ${message}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} ${message} (value is empty)"
        ((TESTS_FAILED++))
    fi
}

# ============================================================================
# 前置：只在容器里以 root 跑——安装会写 /etc、起服务、改 crontab，最后 rm -rf 安装根
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
INSTALL_ROOT="${PROXY_AGENT_DIR:-/etc/Proxy-agent}"
XRAY_BIN="${INSTALL_ROOT}/xray/xray"
XRAY_CONF_DIR="${INSTALL_ROOT}/xray/conf"
E2E_LOG="/tmp/proxy-agent-e2e-install.log"

if [[ "$(id -u)" != "0" || "$(uname -s)" != "Linux" ]]; then
    echo -e "${RED}必须在 Linux 上以 root 运行${NC}"
    exit 2
fi
if [[ ! -f /.dockerenv && -z "${PROXY_AGENT_E2E_HOST:-}" ]]; then
    echo -e "${RED}这是真装机测试，会改写整机状态；只在容器里跑，或显式 PROXY_AGENT_E2E_HOST=1${NC}"
    exit 2
fi
if [[ -e "${INSTALL_ROOT}" || -e /usr/bin/pasly ]]; then
    echo -e "${RED}本机已有 Proxy-agent 安装痕迹（${INSTALL_ROOT} 或 /usr/bin/pasly），拒绝在其上覆盖${NC}"
    exit 2
fi

# 容器里没有 init 启动过 OpenRC，rc-service 会把每个服务都当成「正在启动」；补齐它的状态目录
if command -v rc-service >/dev/null 2>&1 && [[ ! -f /run/openrc/softlevel ]]; then
    mkdir -p /run/openrc/started /run/openrc/starting /run/openrc/stopping /run/openrc/inactive \
        /run/openrc/wasinactive /run/openrc/daemons /run/openrc/exclusive /run/openrc/scheduled /run/openrc/options
    touch /run/openrc/softlevel
fi

if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    SERVICE_MANAGER=systemd
elif command -v rc-service >/dev/null 2>&1; then
    SERVICE_MANAGER=openrc
else
    echo -e "${RED}容器里既没有 systemd 也没有 OpenRC，脚本没法把 Xray 拉成服务${NC}"
    exit 2
fi

E2E_UUID="11111111-2222-3333-4444-555555555555"
E2E_USER="e2euser"
E2E_PORT="443"
E2E_SNI="dl.google.com"

echo "=============================================="
echo -e "${YELLOW}Proxy-agent 真装机端到端测试${NC}"
echo -e "${YELLOW}$(. /etc/os-release && echo "${PRETTY_NAME}") · $(uname -m) · ${SERVICE_MANAGER}${NC}"
echo "=============================================="
echo ""

# ============================================================================
# 用户的做法：把 install.sh 放到 /root 再执行；lib/ 与 shell/lang/ 随行，装机时被拷进安装根
# ============================================================================

cp "${PROJECT_ROOT}/install.sh" "${PROJECT_ROOT}/VERSION" "${HOME}/"
cp -r "${PROJECT_ROOT}/lib" "${HOME}/lib"
mkdir -p "${HOME}/shell"
cp -r "${PROJECT_ROOT}/shell/lang" "${HOME}/shell/lang"

echo -e "${YELLOW}=== 菜单 19 → 1：一键 Reality（Xray-core），答案按提示顺序喂 stdin ===${NC}"
printf '19\n1\n%s\n%s\n%s\n%s:443\n\n' "${E2E_UUID}" "${E2E_USER}" "${E2E_PORT}" "${E2E_SNI}" \
    | V2RAY_LANG=en bash "${HOME}/install.sh" >"${E2E_LOG}" 2>&1
installRc=$?
if [[ ${installRc} -ne 0 ]]; then
    echo -e "${RED}安装退出码 ${installRc}，输出末尾：${NC}"
    tail -n 40 "${E2E_LOG}"
fi
assert_equals "0" "${installRc}" "安装流程退出码 0"

# 安装成功的路径上不该有找不到的命令或文件
noisyLines=$(grep -E 'command not found|No such file or directory' "${E2E_LOG}" || true)
if [[ -n "${noisyLines}" ]]; then
    echo "${noisyLines}"
fi
assert_equals "" "${noisyLines}" "安装输出里没有 command not found / No such file"

# ============================================================================
# 落盘的东西是不是真的：二进制、配置、软链、随行文件、以及 Reality-only 不该装的证书工具
# ============================================================================

echo ""
echo -e "${YELLOW}=== 安装产物 ===${NC}"

assert_equals "yes" "$([[ -x "${XRAY_BIN}" ]] && echo yes || echo no)" "Xray 二进制就位且可执行"
assert_equals "yes" "$([[ -s "${INSTALL_ROOT}/xray/geosite.dat" && -s "${INSTALL_ROOT}/xray/geoip.dat" ]] && echo yes || echo no)" "geosite.dat / geoip.dat 已下载"
assert_equals "${INSTALL_ROOT}/install.sh" "$(readlink -f /usr/bin/pasly 2>/dev/null)" "/usr/bin/pasly 软链指向安装根里的 install.sh"
assert_equals "yes" "$([[ ! -e "${HOME}/install.sh" ]] && echo yes || echo no)" "/root/install.sh 已搬进安装根"
assert_equals "$(cat "${PROJECT_ROOT}/VERSION")" "$(cat "${INSTALL_ROOT}/VERSION" 2>/dev/null)" "VERSION 随行拷入"
missingCopies=$(cd "${PROJECT_ROOT}" && for f in lib/*.sh shell/lang/*.sh; do [[ -f "${INSTALL_ROOT}/${f}" ]] || echo "${f}"; done)
assert_equals "" "${missingCopies}" "lib/ 与 shell/lang/ 的每个文件都随行拷入"
assert_equals "no" "$([[ -d "${HOME}/.acme.sh" ]] && echo yes || echo no)" "Reality-only 没有装 acme.sh"
assert_equals "" "$(crontab -l 2>/dev/null | grep -F 'acme.sh' || true)" "crontab 里没有 acme.sh 续期行"

# ============================================================================
# 生成的配置：内核自己认、字段是喂进去的值、密钥对自洽
# ============================================================================

echo ""
echo -e "${YELLOW}=== Xray 配置 ===${NC}"

realityConf="${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json"
assert_equals "yes" "$([[ -f "${realityConf}" ]] && echo yes || echo no)" "07_VLESS_vision_reality_inbounds.json 已生成"

runTestOut=$("${XRAY_BIN}" run -test -confdir "${XRAY_CONF_DIR}" 2>&1)
runTestRc=$?
if [[ ${runTestRc} -ne 0 ]]; then
    echo "${runTestOut}" | tail -n 10
fi
assert_equals "0" "${runTestRc}" "xray run -test -confdir 通过"
assert_contains "${runTestOut}" "Configuration OK" "xray run -test 报 Configuration OK"

if [[ -f "${realityConf}" ]]; then
    assert_equals "${E2E_PORT}" "$(jq -r '.inbounds[0].port' "${realityConf}")" "对外端口是喂进去的 ${E2E_PORT}"
    assert_equals "${E2E_UUID}" "$(jq -r '.inbounds[1].settings.clients[0].id' "${realityConf}")" "客户端 UUID 是喂进去的值"
    assert_equals "${E2E_USER}-vless_reality_vision" "$(jq -r '.inbounds[1].settings.clients[0].email' "${realityConf}")" "客户端 email 带协议后缀"
    assert_equals "xtls-rprx-vision" "$(jq -r '.inbounds[1].settings.clients[0].flow' "${realityConf}")" "flow 是 xtls-rprx-vision"
    assert_equals "${E2E_SNI}" "$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0]' "${realityConf}")" "serverNames 是喂进去的目标域名"
    assert_equals "${E2E_SNI}:443" "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${realityConf}")" "target 是域名:443"
    assert_equals "1.8.0" "$(jq -r '.inbounds[1].streamSettings.realitySettings.minClientVer' "${realityConf}")" "minClientVer 钉在 1.8.0"
    assert_equals "2" "$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' "${realityConf}")" "两个 shortId"
    assert_equals "" "$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds[] | select(test("^[0-9a-f]{16}$") | not)' "${realityConf}")" "shortId 都是 16 位十六进制"

    privateKey=$(jq -r '.inbounds[1].streamSettings.realitySettings.privateKey' "${realityConf}")
    publicKey=$(jq -r '.inbounds[1].streamSettings.realitySettings.publicKey' "${realityConf}")
    derivedPublic=$("${XRAY_BIN}" x25519 -i "${privateKey}" 2>/dev/null | grep -E 'Public|Password' | awk '{print $NF}')
    assert_not_empty "${privateKey}" "privateKey 非空"
    assert_equals "${publicKey}" "${derivedPublic}" "publicKey 与 privateKey 派生值一致"
fi

# ============================================================================
# 服务：真的起来了、开机自启登记了、端口在听
# ============================================================================

echo ""
echo -e "${YELLOW}=== 服务 ===${NC}"

assert_not_empty "$(pgrep -f "xray/xray" || true)" "xray 进程在跑"
if [[ "${SERVICE_MANAGER}" == "systemd" ]]; then
    assert_equals "active" "$(systemctl is-active xray 2>/dev/null)" "systemd: xray.service active"
    assert_equals "enabled" "$(systemctl is-enabled xray 2>/dev/null)" "systemd: xray.service enabled"
else
    assert_contains "$(rc-service xray status 2>&1)" "started" "OpenRC: xray started"
    assert_contains "$(rc-update show default 2>/dev/null)" "xray" "OpenRC: xray 在 default 运行级"
fi
assert_equals "yes" "$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${E2E_PORT}" 2>/dev/null && echo yes || echo no)" "127.0.0.1:${E2E_PORT} 接受 TCP 连接"

# ============================================================================
# 订阅链接可用：拿脚本发给用户的 vless:// 链接起一个 Xray 客户端，穿过服务端访问外网
# ============================================================================

echo ""
echo -e "${YELLOW}=== 订阅链接与真实 Reality 握手 ===${NC}"

subscribeFile="${INSTALL_ROOT}/subscribe_local/default/${E2E_USER}"
shareLink=$(grep -o 'vless://[^[:space:]]*' "${subscribeFile}" 2>/dev/null | head -1)
assert_not_empty "${shareLink}" "subscribe_local/default/${E2E_USER} 里有 vless:// 链接"
assert_contains "$(sed 's/\x1b\[[0-9;]*m//g' "${E2E_LOG}")" "${shareLink}" "同一条链接也打给了用户"

linkUUID=${shareLink#vless://}
linkUUID=${linkUUID%%@*}
linkQuery=${shareLink#*\?}
linkQuery=${linkQuery%%#*}
linkParam() {
    local key="$1" pair
    for pair in ${linkQuery//&/ }; do
        if [[ "${pair}" == "${key}="* ]]; then
            printf '%s\n' "${pair#*=}"
            return 0
        fi
    done
}
linkHostPort=${shareLink#vless://*@}
linkHostPort=${linkHostPort%%\?*}
linkPort=${linkHostPort##*:}
assert_equals "${E2E_UUID}" "${linkUUID}" "链接里的 UUID 与配置一致"
assert_equals "${E2E_PORT}" "${linkPort}" "链接里的端口是安装时选的端口"
assert_equals "tcp" "$(linkParam type)" "链接 type=tcp"
assert_equals "reality" "$(linkParam security)" "链接 security=reality"
assert_equals "${E2E_SNI}" "$(linkParam sni)" "链接 sni 是目标域名"
assert_equals "${publicKey}" "$(linkParam pbk)" "链接 pbk 是配置里的 publicKey"
assert_equals "$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds[0]' "${realityConf}")" "$(linkParam sid)" "链接 sid 是配置里的第一个 shortId"
assert_equals "xtls-rprx-vision" "$(linkParam flow)" "链接 flow=xtls-rprx-vision"

clientConf=/tmp/proxy-agent-e2e-client.json
# 客户端的每个字段都取自链接，端口与传输也不例外：链接写错什么，握手就在什么上失败
jq -n --arg id "${linkUUID}" --arg port "${linkPort}" --arg net "$(linkParam type)" --arg sni "$(linkParam sni)" \
    --arg pbk "$(linkParam pbk)" --arg sid "$(linkParam sid)" --arg fp "$(linkParam fp)" --arg pqv "$(linkParam pqv)" '{
    log: {loglevel: "warning"},
    inbounds: [{listen: "127.0.0.1", port: 10808, protocol: "socks", settings: {udp: false}}],
    outbounds: [{
        protocol: "vless",
        settings: {vnext: [{address: "127.0.0.1", port: ($port | tonumber),
            users: [{id: $id, encryption: "none", flow: "xtls-rprx-vision"}]}]},
        streamSettings: {network: $net, security: "reality",
            realitySettings: ({serverName: $sni, fingerprint: $fp, publicKey: $pbk, shortId: $sid}
                + (if $pqv == "" then {} else {mldsa65Verify: $pqv} end))}
    }]
}' >"${clientConf}"
"${XRAY_BIN}" run -c "${clientConf}" >/tmp/proxy-agent-e2e-client.log 2>&1 &
clientPid=$!
sleep 2
httpCode=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 --proxy socks5h://127.0.0.1:10808 \
    https://www.google.com/generate_204 2>/tmp/proxy-agent-e2e-curl.log)
kill "${clientPid}" 2>/dev/null
wait "${clientPid}" 2>/dev/null
if [[ "${httpCode}" != "204" ]]; then
    cat /tmp/proxy-agent-e2e-curl.log /tmp/proxy-agent-e2e-client.log
fi
assert_equals "204" "${httpCode}" "按链接配置的客户端经服务端访问外网返回 204"

# ============================================================================
# 重入：pasly 认得出已装状态，doctor 全绿
# ============================================================================

echo ""
echo -e "${YELLOW}=== pasly 重入与 doctor ===${NC}"

menuOut=$(V2RAY_LANG=en pasly </dev/null 2>&1)
menuRc=$?
menuOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${menuOut}")
assert_equals "0" "${menuRc}" "pasly 打开菜单后无输入退出码 0"
assert_contains "${menuOut}" "Core: Xray-core [Running]" "菜单头显示 Xray-core 运行中"
assert_contains "${menuOut}" "Installed protocols: VLESS+Reality+Vision" "菜单头列出 VLESS+Reality+Vision"
assert_contains "${menuOut}" "1.Reinstall" "菜单第 1 项变成 Reinstall"

doctorOut=$(V2RAY_LANG=en pasly doctor 2>&1)
doctorRc=$?
doctorOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${doctorOut}")
if [[ ${doctorRc} -ne 0 ]] || [[ "${doctorOut}" == *"[FAIL]"* ]]; then
    echo "${doctorOut}"
fi
assert_equals "0" "${doctorRc}" "pasly doctor 退出码 0"
assert_equals "" "$(grep -F '[FAIL]' <<<"${doctorOut}" || true)" "doctor 零 FAIL"
assert_contains "${doctorOut}" "[PASS] Core process" "doctor 看到核心进程"
assert_contains "${doctorOut}" "[PASS] Config file validation" "doctor 配置校验通过"

# ============================================================================
# 卸载：菜单 20，确认 y；整机回到装前
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 20：卸载 ===${NC}"

uninstallOut=$(printf '20\ny\n' | V2RAY_LANG=en pasly 2>&1)
uninstallRc=$?
uninstallOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${uninstallOut}")
if [[ ${uninstallRc} -ne 0 ]]; then
    echo "${uninstallOut}" | tail -n 20
fi
assert_equals "0" "${uninstallRc}" "卸载退出码 0"
assert_equals "no" "$([[ -e "${INSTALL_ROOT}" ]] && echo yes || echo no)" "安装根已删除"
assert_equals "no" "$([[ -e /usr/bin/pasly ]] && echo yes || echo no)" "/usr/bin/pasly 已删除"
if [[ "${SERVICE_MANAGER}" == "systemd" ]]; then
    assert_equals "no" "$([[ -e /etc/systemd/system/xray.service ]] && echo yes || echo no)" "xray.service 单元文件已删除"
else
    assert_equals "no" "$([[ -e /etc/init.d/xray ]] && echo yes || echo no)" "/etc/init.d/xray 已删除"
    assert_equals "" "$(rc-update show default 2>/dev/null | grep xray || true)" "xray 已从 default 运行级移除"
fi
assert_equals "" "$(pgrep -f "xray/xray" || true)" "xray 进程已退出"
assert_equals "no" "$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${E2E_PORT}" 2>/dev/null && echo yes || echo no)" "127.0.0.1:${E2E_PORT} 不再监听"

# ============================================================================
# 测试结果汇总
# ============================================================================

echo ""
echo "=============================================="
echo -e "${YELLOW}测试结果汇总${NC}"
echo "=============================================="
echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}真装机端到端测试全部通过！${NC}"
    exit 0
else
    echo -e "${RED}有 ${TESTS_FAILED} 个测试失败！完整安装输出在 ${E2E_LOG}${NC}"
    exit 1
fi
