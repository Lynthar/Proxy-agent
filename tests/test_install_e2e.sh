#!/usr/bin/env bash
# test_install_e2e.sh - 真装机端到端：以 root 在一次性容器里跑「一键 Reality」（菜单 19 → E2E_CORE 选的内核），
# 用内核自检、真实 Reality 握手（客户端由 E2E_CLIENT 选，默认同内核）、pasly 重入与 doctor 验收；Xray 内核再开拼车、
# 走一遍真实计量、增删成员、回滚、到期停用与关闭恢复（chain 腿另在中间接上、拆掉链式），最后卸载。跑法见 tests/e2e/run.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/e2e/assert.sh"

# ============================================================================
# 前置：只在容器里以 root 跑——安装会写 /etc、起服务、改 crontab，最后 rm -rf 安装根
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
INSTALL_ROOT="${PROXY_AGENT_DIR:-/etc/Proxy-agent}"
XRAY_BIN="${INSTALL_ROOT}/xray/xray"
XRAY_CONF_DIR="${INSTALL_ROOT}/xray/conf"
SINGBOX_BIN="${INSTALL_ROOT}/sing-box/sing-box"
SINGBOX_FRAGMENT_DIR="${INSTALL_ROOT}/sing-box/conf/config"
E2E_LOG="/tmp/proxy-agent-e2e-install.log"
E2E_CORE="${E2E_CORE:-xray}"
E2E_CLIENT="${E2E_CLIENT:-${E2E_CORE}}"

case "${E2E_CORE}" in
xray)
    CORE_BIN="${XRAY_BIN}" CORE_SERVICE=xray CORE_LABEL="Xray-core" MENU_CORE_CHOICE=1
    ;;
singbox)
    CORE_BIN="${SINGBOX_BIN}" CORE_SERVICE=sing-box CORE_LABEL="sing-box" MENU_CORE_CHOICE=2
    ;;
*)
    echo -e "${RED}E2E_CORE 只能是 xray 或 singbox，收到 ${E2E_CORE}${NC}"
    exit 2
    ;;
esac
# 交叉腿只有一种：sing-box 客户端对 Xray 服务端（脚本发的 sing-box 订阅必须连得上 Reality）
if [[ "${E2E_CLIENT}" != "${E2E_CORE}" && ! ("${E2E_CLIENT}" == "singbox" && "${E2E_CORE}" == "xray") ]]; then
    echo -e "${RED}E2E_CLIENT 只能与 E2E_CORE 相同，或 singbox 对 xray；收到 ${E2E_CLIENT} 对 ${E2E_CORE}${NC}"
    exit 2
fi
# E2E_CHAIN_CODE 由 run.sh chain 传入（出口机的配置码）：拼车开着时把本机接成链式入口，跑完再拆掉
if [[ -n "${E2E_CHAIN_CODE:-}" && "${E2E_CORE}" != "xray" ]]; then
    echo -e "${RED}E2E_CHAIN_CODE 只用于 Xray 内核（拼车只在 Xray 上开）${NC}"
    exit 2
fi

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
    echo -e "${RED}容器里既没有 systemd 也没有 OpenRC，脚本没法把内核拉成服务${NC}"
    exit 2
fi

E2E_UUID="11111111-2222-3333-4444-555555555555"
E2E_USER="e2euser"
E2E_PORT="443"
E2E_SNI="dl.google.com"

echo "=============================================="
echo -e "${YELLOW}Proxy-agent 真装机端到端测试${NC}"
echo -e "${YELLOW}$(. /etc/os-release && echo "${PRETTY_NAME}") · $(uname -m) · ${SERVICE_MANAGER} · ${CORE_LABEL} · 客户端 ${E2E_CLIENT}${NC}"
echo "=============================================="
echo ""

# ============================================================================
# 用户的做法：把 install.sh 放到 /root 再执行；lib/ 与 shell/lang/ 随行，装机时被拷进安装根
# ============================================================================

cp "${PROJECT_ROOT}/install.sh" "${PROJECT_ROOT}/VERSION" "${HOME}/"
cp -r "${PROJECT_ROOT}/lib" "${HOME}/lib"
mkdir -p "${HOME}/shell"
cp -r "${PROJECT_ROOT}/shell/lang" "${HOME}/shell/lang"

# 答案按提示顺序喂 stdin。Xray：UUID、用户名、端口（回车取默认，空机器上应是 443）、目标域名、私钥（回车生成）；
# sing-box 先问目标域名再问端口，密钥由 sing-box 自己生成、不问
echo -e "${YELLOW}=== 菜单 19 → ${MENU_CORE_CHOICE}：一键 Reality（${CORE_LABEL}）===${NC}"
if [[ "${E2E_CORE}" == "xray" ]]; then
    printf '19\n1\n%s\n%s\n\n%s:443\n\n' "${E2E_UUID}" "${E2E_USER}" "${E2E_SNI}"
else
    printf '19\n2\n%s\n%s\n%s:443\n\n' "${E2E_UUID}" "${E2E_USER}" "${E2E_SNI}"
fi | V2RAY_LANG=en bash "${HOME}/install.sh" >"${E2E_LOG}" 2>&1
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

assert_equals "yes" "$([[ -x "${CORE_BIN}" ]] && echo yes || echo no)" "${CORE_LABEL} 二进制就位且可执行"
assert_equals "0" "$("${CORE_BIN}" version >/dev/null 2>&1; echo $?)" "${CORE_LABEL} 二进制能在本机运行（架构与 libc 都对）"
if [[ "${E2E_CORE}" == "xray" ]]; then
    assert_equals "yes" "$([[ -s "${INSTALL_ROOT}/xray/geosite.dat" && -s "${INSTALL_ROOT}/xray/geoip.dat" ]] && echo yes || echo no)" "geosite.dat / geoip.dat 已下载"
    # 默认装的是钉住的版本，不是 GitHub 最新：更新的 Xray-core 会让下面的 sing-box 交叉握手失败
    pinnedXray=$(sed -n 's/^readonly XRAY_PINNED_VERSION="\(.*\)"$/\1/p' "${PROJECT_ROOT}/lib/constants.sh")
    assert_not_empty "${pinnedXray}" "lib/constants.sh 里有 XRAY_PINNED_VERSION"
    assert_equals "${pinnedXray#v}" "$("${XRAY_BIN}" version 2>/dev/null | head -1 | awk '{print $2}')" "装的是钉住的 Xray-core ${pinnedXray}"
else
    assert_equals "no" "$([[ -e "${XRAY_BIN}" ]] && echo yes || echo no)" "sing-box 一键 Reality 不装 Xray"
fi
assert_equals "${INSTALL_ROOT}/install.sh" "$(readlink -f /usr/bin/pasly 2>/dev/null)" "/usr/bin/pasly 软链指向安装根里的 install.sh"
assert_equals "yes" "$([[ ! -e "${HOME}/install.sh" ]] && echo yes || echo no)" "/root/install.sh 已搬进安装根"
assert_equals "$(cat "${PROJECT_ROOT}/VERSION")" "$(cat "${INSTALL_ROOT}/VERSION" 2>/dev/null)" "VERSION 随行拷入"
missingCopies=$(cd "${PROJECT_ROOT}" && for f in lib/*.sh shell/lang/*.sh; do [[ -f "${INSTALL_ROOT}/${f}" ]] || echo "${f}"; done)
assert_equals "" "${missingCopies}" "lib/ 与 shell/lang/ 的每个文件都随行拷入"
assert_equals "no" "$([[ -d "${HOME}/.acme.sh" ]] && echo yes || echo no)" "Reality-only 没有装 acme.sh"
assert_equals "" "$(crontab -l 2>/dev/null | grep -F 'acme.sh' || true)" "crontab 里没有 acme.sh 续期行"
assert_not_empty "$(printf 'vless://e2e' | qrencode -m 1 -t UTF8 2>/dev/null)" "qrencode 已装、画得出二维码（账号页靠它，没装只是静默少一块）"

# ============================================================================
# 生成的配置：内核自己认、字段是喂进去的值、密钥对自洽
# ============================================================================

echo ""
echo -e "${YELLOW}=== ${CORE_LABEL} 配置 ===${NC}"

if [[ "${E2E_CORE}" == "xray" ]]; then
    realityConf="${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json"
    coreTestOut=$("${XRAY_BIN}" run -test -confdir "${XRAY_CONF_DIR}" 2>&1)
    coreTestRc=$?
else
    realityConf="${SINGBOX_FRAGMENT_DIR}/07_VLESS_vision_reality_inbounds.json"
    coreTestOut=$("${SINGBOX_BIN}" check -c "${INSTALL_ROOT}/sing-box/conf/config.json" 2>&1)
    coreTestRc=$?
fi
assert_equals "yes" "$([[ -f "${realityConf}" ]] && echo yes || echo no)" "07_VLESS_vision_reality_inbounds.json 已生成"
if [[ ${coreTestRc} -ne 0 ]]; then
    echo "${coreTestOut}" | tail -n 10
fi
assert_equals "0" "${coreTestRc}" "${CORE_LABEL} 自检合并后的配置通过"

# Hysteria2 片段要过真 sing-box 的 check：字段名、gecko、masquerade 对不对，桩测不出来。
# 证书现签 ECDSA：1.14 起客户端默认模仿 Chrome 握手，不认 Ed25519
if [[ "${E2E_CORE}" == "singbox" ]]; then
    HY2_FN=$(sed -n '/^hysteria2InboundJson() {/,/^}/p' "${PROJECT_ROOT}/install.sh")
    hy2Dir=$(mktemp -d)
    mkdir -p "${hy2Dir}/site"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=e2e.example \
        -keyout "${hy2Dir}/e2e.example.key" -out "${hy2Dir}/e2e.example.crt" >/dev/null 2>&1
    singBoxVersion=$("${SINGBOX_BIN}" version 2>/dev/null | awk '/^sing-box version/ {print $3; exit}')
    hy2Obfs=salamander
    if [[ "$(printf '%s\n' "${singBoxVersion}" 1.14.0 | sort -V | head -n 1)" == "1.14.0" ]]; then
        hy2Obfs=gecko
    fi
    # hy2Check UP DOWN OBFS SITE → 生成片段并 check，返回 check 的退出码；失败时打出 check 的输出
    hy2Check() {
        (TLS_DIR="${hy2Dir}"; eval "${HY2_FN}"
            hysteria2InboundJson 8443 '[{"name":"e2e","password":"pw"}]' e2e.example "$1" "$2" "$3" pw0 "$4") >"${hy2Dir}/hy2.json" &&
            "${SINGBOX_BIN}" check -c "${hy2Dir}/hy2.json" >"${hy2Dir}/check.log" 2>&1 || {
            tail -n 5 "${hy2Dir}/check.log"
            return 1
        }
    }
    hy2Check '' '' "${hy2Obfs}" "${hy2Dir}/site"
    assert_equals "0" "$?" "Hysteria2 片段过 sing-box ${singBoxVersion} 的 check：BBR + ${hy2Obfs} + masquerade"
    hy2Check 100 50 salamander ''
    assert_equals "0" "$?" "Hysteria2 片段过 sing-box ${singBoxVersion} 的 check：Brutal + salamander"
    rm -rf "${hy2Dir}"
fi

if [[ -f "${realityConf}" && "${E2E_CORE}" == "xray" ]]; then
    assert_contains "${coreTestOut}" "Configuration OK" "xray run -test 报 Configuration OK"
    assert_equals "${E2E_PORT}" "$(jq -r '.inbounds[0].port' "${realityConf}")" "对外端口是回车默认的 ${E2E_PORT}"
    assert_equals "${E2E_UUID}" "$(jq -r '.inbounds[1].settings.clients[0].id' "${realityConf}")" "客户端 UUID 是喂进去的值"
    assert_equals "${E2E_USER}-vless_reality_vision" "$(jq -r '.inbounds[1].settings.clients[0].email' "${realityConf}")" "客户端 email 带协议后缀"
    assert_equals "xtls-rprx-vision" "$(jq -r '.inbounds[1].settings.clients[0].flow' "${realityConf}")" "flow 是 xtls-rprx-vision"
    assert_equals "${E2E_SNI}" "$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0]' "${realityConf}")" "serverNames 是喂进去的目标域名"
    assert_equals "${E2E_SNI}:443" "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${realityConf}")" "target 是域名:443"
    assert_equals "1.8.0" "$(jq -r '.inbounds[1].streamSettings.realitySettings.minClientVer' "${realityConf}")" "minClientVer 钉在 1.8.0"
    # 容器按 Docker 默认没有 IPv6 路由。留着 UseIP 的话，这个文件里每次经代理连双栈站点约 3% 断开
    expectDirect=UseIP
    [[ -z "$(ip -6 route show default 2>/dev/null)" ]] && expectDirect=UseIPv4v6
    assert_equals "${expectDirect}" "$(jq -r '.outbounds[0].settings.domainStrategy' "${XRAY_CONF_DIR}/z_direct_outbound.json")" "直连出站的地址策略按本机路由选（${expectDirect}）"
    shortIds=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds[]' "${realityConf}")

    privateKey=$(jq -r '.inbounds[1].streamSettings.realitySettings.privateKey' "${realityConf}")
    publicKey=$(jq -r '.inbounds[1].streamSettings.realitySettings.publicKey' "${realityConf}")
    derivedPublic=$("${XRAY_BIN}" x25519 -i "${privateKey}" 2>/dev/null | grep -E 'Public|Password' | awk '{print $NF}')
    assert_not_empty "${privateKey}" "privateKey 非空"
    assert_equals "${publicKey}" "${derivedPublic}" "publicKey 与 privateKey 派生值一致"
elif [[ -f "${realityConf}" ]]; then
    assert_equals "${E2E_PORT}" "$(jq -r '.inbounds[0].listen_port' "${realityConf}")" "对外端口是回车默认的 ${E2E_PORT}"
    assert_equals "${E2E_UUID}" "$(jq -r '.inbounds[0].users[0].uuid' "${realityConf}")" "客户端 UUID 是喂进去的值"
    assert_equals "${E2E_USER}-VLESS_Reality_Vision" "$(jq -r '.inbounds[0].users[0].name' "${realityConf}")" "客户端名带协议后缀"
    assert_equals "xtls-rprx-vision" "$(jq -r '.inbounds[0].users[0].flow' "${realityConf}")" "flow 是 xtls-rprx-vision"
    assert_equals "${E2E_SNI}" "$(jq -r '.inbounds[0].tls.server_name' "${realityConf}")" "server_name 是喂进去的目标域名"
    assert_equals "${E2E_SNI}:443" "$(jq -r '.inbounds[0].tls.reality.handshake | "\(.server):\(.server_port)"' "${realityConf}")" "handshake 是域名:443"
    shortIds=$(jq -r '.inbounds[0].tls.reality.short_id[]' "${realityConf}")
    assert_not_empty "$(jq -r '.inbounds[0].tls.reality.private_key // empty' "${realityConf}")" "private_key 非空"
    # sing-box 不能由私钥反推公钥；公钥配不上私钥时下面的真实握手会失败
    publicKey=$(sed -n 's/^publicKey://p' "${SINGBOX_FRAGMENT_DIR}/reality_key" 2>/dev/null)
    assert_not_empty "${publicKey}" "reality_key 里记了公钥"
fi
assert_equals "2" "$(grep -c . <<<"${shortIds:-}")" "两个 shortId"
assert_equals "" "$(grep -vE '^[0-9a-f]{16}$' <<<"${shortIds:-}")" "shortId 都是 16 位十六进制"

# ============================================================================
# 服务：真的起来了、开机自启登记了、端口在听
# ============================================================================

echo ""
echo -e "${YELLOW}=== 服务 ===${NC}"

assert_not_empty "$(pgrep -f "${CORE_BIN}" || true)" "${CORE_SERVICE} 进程在跑"
if [[ "${SERVICE_MANAGER}" == "systemd" ]]; then
    assert_equals "active" "$(systemctl is-active "${CORE_SERVICE}" 2>/dev/null)" "systemd: ${CORE_SERVICE}.service active"
    assert_equals "enabled" "$(systemctl is-enabled "${CORE_SERVICE}" 2>/dev/null)" "systemd: ${CORE_SERVICE}.service enabled"
else
    assert_contains "$(rc-service "${CORE_SERVICE}" status 2>&1)" "started" "OpenRC: ${CORE_SERVICE} started"
    assert_contains "$(rc-update show default 2>/dev/null)" "${CORE_SERVICE}" "OpenRC: ${CORE_SERVICE} 在 default 运行级"
fi
assert_equals "yes" "$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${E2E_PORT}" 2>/dev/null && echo yes || echo no)" "127.0.0.1:${E2E_PORT} 接受 TCP 连接"
# 端口查重靠 /proc/net：BusyBox 与 Debian 上都得认出内核刚占上的端口，否则「已被占用」形同虚设
LISTEN_FN=$(sed -n '/^listeningPorts() {/,/^}/p' "${PROJECT_ROOT}/install.sh")
assert_equals "yes" "$(eval "${LISTEN_FN}"; listeningPorts tcp | grep -qx "${E2E_PORT}" && echo yes || echo no)" \
    "listeningPorts 认出 ${E2E_PORT}/tcp 正被监听"
# 安装顺手把 cron 守护进程拉起来：Alpine 的 BusyBox 带 crontab 却从不自启 crond，定时任务会静默不跑
assert_not_empty "$(pgrep cron || true)" "cron 守护进程在跑（证书续期与 geo 更新的定时任务有人执行）"

# ============================================================================
# 订阅链接可用：拿脚本发给用户的 vless:// 链接，用 E2E_CLIENT 选的内核起客户端，穿过服务端访问外网
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
assert_equals "$(head -n 1 <<<"${shortIds:-}")" "$(linkParam sid)" "链接 sid 是配置里的第一个 shortId"
assert_equals "xtls-rprx-vision" "$(linkParam flow)" "链接 flow=xtls-rprx-vision"

# 客户端二进制：默认就是刚装好的内核；交叉腿另下一份官方 sing-box 最新稳定版（releases/latest 不含预览版）
CLIENT_BIN="${CORE_BIN}"
if [[ "${E2E_CLIENT}" != "${E2E_CORE}" ]]; then
    clientDir=/tmp/proxy-agent-e2e-client-core
    clientTag=$(curl -sIL -o /dev/null -w '%{url_effective}' --max-time 20 https://github.com/SagerNet/sing-box/releases/latest)
    clientTag=${clientTag##*/}
    case "$(uname -m)" in
    x86_64) clientArch=amd64 ;;
    aarch64) clientArch=arm64 ;;
    *) clientArch= ;;
    esac
    clientLibc=""
    [[ -f /etc/alpine-release ]] && clientLibc="-musl"
    mkdir -p "${clientDir}"
    curl -sSL --max-time 120 "https://github.com/SagerNet/sing-box/releases/download/${clientTag}/sing-box-${clientTag#v}-linux-${clientArch}${clientLibc}.tar.gz" |
        tar -xz -C "${clientDir}" --strip-components=1
    CLIENT_BIN="${clientDir}/sing-box"
    assert_equals "yes" "$([[ -x "${CLIENT_BIN}" ]] && echo yes || echo no)" "交叉腿：sing-box ${clientTag} 客户端二进制已就位"
fi

clientConf=/tmp/proxy-agent-e2e-client.json
# 客户端的每个字段都取自链接，端口与传输也不例外：链接写错什么，握手就在什么上失败
if [[ "${E2E_CLIENT}" == "xray" ]]; then
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
    clientCmd=("${CLIENT_BIN}" run -c "${clientConf}")
else
    jq -n --arg id "${linkUUID}" --arg port "${linkPort}" --arg flow "$(linkParam flow)" --arg sni "$(linkParam sni)" \
        --arg pbk "$(linkParam pbk)" --arg sid "$(linkParam sid)" --arg fp "$(linkParam fp)" '{
        log: {level: "warn"},
        inbounds: [{type: "socks", listen: "127.0.0.1", listen_port: 10808}],
        outbounds: [{
            type: "vless", server: "127.0.0.1", server_port: ($port | tonumber), uuid: $id, flow: $flow,
            tls: {enabled: true, server_name: $sni, utls: {enabled: true, fingerprint: $fp},
                reality: {enabled: true, public_key: $pbk, short_id: $sid}}
        }]
    }' >"${clientConf}"
    clientCmd=("${CLIENT_BIN}" run -c "${clientConf}")
fi
# realityProbe [CLIENT_CONF] → 起一次客户端（默认用按链接配的那份）、经服务端访问外网、关掉客户端，打印 HTTP 状态码（连不上是 000）
realityProbe() {
    local pid code
    "${CLIENT_BIN}" run -c "${1:-${clientConf}}" >/tmp/proxy-agent-e2e-client.log 2>&1 &
    pid=$!
    sleep 2
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 --proxy socks5h://127.0.0.1:10808 \
        https://www.google.com/generate_204 2>/tmp/proxy-agent-e2e-curl.log)
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    if [[ "${code}" != "204" ]]; then
        cat /tmp/proxy-agent-e2e-curl.log /tmp/proxy-agent-e2e-client.log >&2
        # 断连要看服务端怎么说，只有客户端日志的话下次还是查不了
        tail -n 8 "${INSTALL_ROOT}/xray/error.log" >&2 2>/dev/null
    fi
    printf '%s\n' "${code}"
}
assert_equals "204" "$(realityProbe)" "按链接配置的客户端经服务端访问外网返回 204"
# viaProxyCode CURL_ARGS... → 起一次客户端、经它跑一次 curl（-k，10 秒），打印 HTTP 状态码（连不上是 000），关掉客户端
viaProxyCode() {
    local pid code
    "${clientCmd[@]}" >/tmp/proxy-agent-e2e-client.log 2>&1 &
    pid=$!
    sleep 2
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --proxy socks5h://127.0.0.1:10808 "$@" 2>/dev/null)
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    printf '%s\n' "${code}"
}
# 代理用户连不到服务端本机：--connect-to 把对伪装站的 HTTPS 请求导到服务端自己的 Reality 端口，没拦就会被转给伪装站、拿到它的响应码
localControl=$(viaProxyCode "https://${E2E_SNI}/")
assert_equals "yes" "$([[ "${localControl}" =~ ^[1-5][0-9][0-9]$ ]] && echo yes || echo no)" "对照：经代理请求伪装站拿到响应码 ${localControl}（下面的 000 才说明是被拦下）"
for localTarget in 127.0.0.1 '[::ffff:127.0.0.1]' 0.0.0.0; do
    assert_equals "000" "$(viaProxyCode --connect-to "${E2E_SNI}:443:${localTarget}:${linkPort}" "https://${E2E_SNI}/")" \
        "经代理连服务端本机 ${localTarget}:${linkPort} 被拦下"
done
# 本机网卡上的公网地址：经代理连它走 lo、绕过 INPUT 防火墙。挂地址要 NET_ADMIN，只有 Debian 腿有。
# 规则在核心启动时才读网卡，所以先有一条经代理连得到的对照，重启之后才是被拦下，两种结果分得开
selfAddr=198.51.100.7
if ip addr add "${selfAddr}/32" dev lo 2>/dev/null; then
    printf 'HTTP/1.0 200 OK\r\n\r\n' >/tmp/proxy-agent-e2e-self.http
    socat "TCP-LISTEN:18081,bind=${selfAddr},fork,reuseaddr" EXEC:"cat /tmp/proxy-agent-e2e-self.http" &
    selfListener=$!
    sleep 0.5
    selfControl=$(viaProxyCode "http://${selfAddr}:18081/")
    [[ "${selfControl}" == "200" ]] || cat /tmp/proxy-agent-e2e-client.log
    assert_equals "200" "${selfControl}" "对照：核心启动时 ${selfAddr} 还不在网卡上，经代理连得到"
    if [[ "${E2E_CORE}" == "xray" ]]; then
        printf '16\n1\n6\n' | V2RAY_LANG=en pasly >/dev/null 2>&1
        selfBlocked=$(jq --arg a "${selfAddr}" '.routing.rules[] | select(.ruleTag == "local-block-ip") | .ip | index($a) != null' "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)
    else
        printf '16\n2\n4\n' | V2RAY_LANG=en pasly >/dev/null 2>&1
        selfBlocked=$(jq --arg a "${selfAddr}" '[.route.rules[] | .ip_cidr // [] | index($a)] | any' "${INSTALL_ROOT}/sing-box/conf/config.json" 2>/dev/null)
    fi
    sleep 6
    assert_equals "true" "${selfBlocked}" "重启后 ${selfAddr} 进了本机封锁的规则"
    assert_equals "000" "$(viaProxyCode "http://${selfAddr}:18081/")" "经代理连本机网卡上的公网地址被拦下，靠防火墙挡外网的服务摸不到"
    kill "${selfListener}" 2>/dev/null
    wait "${selfListener}" 2>/dev/null
    ip addr del "${selfAddr}/32" dev lo
fi

# ============================================================================
# 重入：pasly 认得出已装状态，doctor 全绿
# ============================================================================

echo ""
echo -e "${YELLOW}=== pasly 重入与 doctor ===${NC}"

menuOut=$(V2RAY_LANG=en pasly </dev/null 2>&1)
menuRc=$?
menuOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${menuOut}")
assert_equals "0" "${menuRc}" "pasly 打开菜单后无输入退出码 0"
assert_contains "${menuOut}" "Core: ${CORE_LABEL} [Running]" "菜单头显示 ${CORE_LABEL} 运行中"
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
assert_contains "${doctorOut}" "System clock" "doctor 查了系统时钟"
assert_contains "${doctorOut}" "[PASS] Account UUIDs" "doctor 配置安全这一节跑了：账号 UUID 没有弱值"
assert_contains "${doctorOut}" "[PASS] Log level" "doctor 配置安全这一节跑了：日志级别正常"

# 菜单 16 → 1 → 8 加 geo 自动更新：cron 行要带安装根前缀，卸载时要被清掉
if [[ "${E2E_CORE}" == "xray" ]]; then
    echo ""
    echo -e "${YELLOW}=== 菜单 16 → 1 → 8：添加 geo 定时更新 ===${NC}"
    geoCronOut=$(printf '16\n1\n8\n' | V2RAY_LANG=en pasly 2>&1)
    geoCronRc=$?
    if [[ ${geoCronRc} -ne 0 ]]; then
        sed 's/\x1b\[[0-9;]*m//g' <<<"${geoCronOut}" | tail -n 10
    fi
    assert_equals "0" "${geoCronRc}" "添加 geo 定时更新退出码 0"
    assert_equals "35 1 * * * PROXY_AGENT_DIR=${INSTALL_ROOT} /bin/bash ${INSTALL_ROOT}/install.sh UpdateGeo >> ${INSTALL_ROOT}/crontab_tls.log 2>&1" \
        "$(crontab -l 2>/dev/null | grep -F 'install.sh UpdateGeo')" "crontab 里的 UpdateGeo 行带安装根前缀"
fi

# listenAddrs PORT → 该 TCP 端口上 LISTEN 的本地地址（/proc/net/tcp{,6} 的十六进制形式），每行一个
listenAddrs() {
    awk -v p=":$(printf '%04X' "$1")" '$4 == "0A" && substr($2, length($2) - 4) == p { split($2, a, ":"); print a[1] }' \
        /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

# ============================================================================
# 路由总览：写文件与只听回环的页面两条路。页面只读，密钥、UUID、分享链接都不能进去
# ============================================================================

echo ""
echo -e "${YELLOW}=== pasly topo：路由总览 ===${NC}"
topoFile=/tmp/proxy-agent-e2e-topo.html
topoOut=$(V2RAY_LANG=en pasly topo --out "${topoFile}" 2>&1)
topoRc=$?
[[ ${topoRc} -ne 0 ]] && echo "${topoOut}"
assert_equals "0" "${topoRc}" "pasly topo --out 退出码 0"
assert_equals "600" "$(stat -c %a "${topoFile}" 2>/dev/null)" "页面文件只有 root 可读"
topoHtml=$(cat "${topoFile}" 2>/dev/null)
assert_contains "${topoHtml}" "VLESS+Reality+Vision" "页面写入站全称"
assert_contains "${topoHtml}" ">${E2E_USER}<" "页面列出账号"
assert_contains "${topoHtml}" ".x.x.x" "出口地址默认打码"
assert_equals "no" "$([[ "${topoHtml}" == *'class="issues"'* ]] && echo yes || echo no)" "刚装好：和状态、磁盘都对得上，不报不一致"
assert_equals "0" "$(grep -c "${E2E_UUID}\|vless://\|<script" "${topoFile}")" "页面里没有 UUID、分享链接、脚本"
V2RAY_LANG=en pasly topo --full --out "${topoFile}" >/dev/null 2>&1
topoFull=$(cat "${topoFile}" 2>/dev/null)
assert_equals "no|yes" "$([[ "${topoFull}" == *".x.x.x"* ]] && echo yes || echo no)|$([[ "${topoFull}" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] && echo yes || echo no)" "--full 才显示完整地址"
assert_equals "0" "$(grep -c "${E2E_UUID}" "${topoFile}")" "--full 的页面里也没有 UUID"
assert_contains "$(V2RAY_LANG=en pasly topo --out "${INSTALL_ROOT}/subscribe/topo.html" 2>&1; echo "rc=$?")" "rc=1" "拒绝写进 nginx 对外的订阅目录"

# 页面：前台跑，只听回环。关掉 fifo 的写端相当于按回车，看退出后端口是否撤掉
topoFifo=/tmp/proxy-agent-e2e-topo.fifo
mkfifo "${topoFifo}"
V2RAY_LANG=en pasly topo <"${topoFifo}" >/tmp/proxy-agent-e2e-topo.log 2>&1 &
topoPid=$!
exec 9>"${topoFifo}"
# 等提示打印出来才算开好：端口一开脚本还要确认 socat 活着，这时读日志会读到空
for _ in $(seq 1 40); do
    grep -q 'ssh -N -L' /tmp/proxy-agent-e2e-topo.log 2>/dev/null && break
    sleep 0.5
done
assert_equals "0100007F" "$(listenAddrs 31210)" "页面只听 127.0.0.1，公网连不到"
assert_contains "$(sed 's/\x1b\[[0-9;]*m//g' /tmp/proxy-agent-e2e-topo.log)" "ssh -N -L 31210:127.0.0.1:31210" "终端打印开隧道的命令"
assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:31210/)" "经回环打得开"
assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:31210/)" "localhost 也打得开"
assert_equals "403" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Host: evil.example' http://127.0.0.1:31210/)" "别的 Host 一律拒绝（防 DNS 重绑定）"
assert_equals "404" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:31210/x)" "只有这一个页面"
topoHeaders=$(curl -s -D - -o /dev/null --max-time 5 http://127.0.0.1:31210/)
assert_contains "${topoHeaders}" "Cache-Control: no-store" "页面不缓存"
assert_contains "${topoHeaders}" "default-src 'none'" "页面的 CSP 不许加载任何外部资源"
assert_contains "$(curl -s --max-time 5 http://127.0.0.1:31210/)" "<svg" "取到的是页面本身"
for topoTarget in 127.0.0.1 localtest.me; do
    assert_equals "000" "$(viaProxyCode "http://${topoTarget}:31210/")" "代理用户连不到页面（${topoTarget}:31210，桥端口段按端口封）"
done
exec 9>&-
wait "${topoPid}"
assert_equals "0" "$?" "关闭页面退出码 0"
assert_equals "" "$(listenAddrs 31210)" "关掉之后端口撤掉"
assert_equals "" "$(pgrep -f 'TCP-LISTEN:31210' || true)" "关掉之后 socat 不留"

# ============================================================================
# 拼车（只有 Xray 内核能开）：菜单 7 → 6 → 4 开启，真实流量要被 cron 那条 tick 记进成员名下；增删成员、回滚不倒回用量，再到期停用、关闭时恢复
# ============================================================================

# runCarpoolTick CRON_LINE [AT] → 把 crontab 那一行原样执行一次，打印它这次追加进日志的内容，返回它的退出码。
# 环境照 Debian cron 交给任务的给（实测 PATH=/usr/bin:/bin）；Alpine 的 crond 继承 OpenRC，比这宽。
# 给了 AT（YYYY-MM-DD HH:MM:SS）就经 faketime 让这次 tick 从那一刻起走表；Xray 是静态 Go 程序，统计 API 不受影响
runCarpoolTick() {
    local log="${INSTALL_ROOT}/crontab_carpool.log" before=0 rc fake=()
    [[ -f "${log}" ]] && before=$(wc -l <"${log}")
    [[ -n "${2:-}" ]] && fake=(faketime -f "@$2")
    env -i HOME=/root PATH=/usr/bin:/bin SHELL=/bin/sh "${fake[@]}" /bin/sh -c "$(cut -d' ' -f6- <<<"$1")"
    rc=$?
    tail -n +"$((before + 1))" "${log}" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
    return "${rc}"
}

# statsValue JSON NAME → statsquery 输出里该计数器的值（Xray 对 0 省掉 value 字段）；没有这个计数器打印 missing
statsValue() {
    jq -r --arg n "$2" '[.stat[]? | select(.name == $n) | (.value // 0 | tonumber)] | first // "missing"' <<<"$1" 2>/dev/null
}

# xrayEnviron → 正在跑的 Xray 进程的环境变量，每行一个
xrayEnviron() {
    local pid
    pid=$(pgrep -f "${XRAY_BIN}" | head -n 1)
    [[ -n "${pid}" ]] && tr '\0' '\n' <"/proc/${pid}/environ"
}

# carpoolIntact WHEN → 拼车在 Xray 一侧的五样都还在：统计 API 片段与它只听回环、policy 两个开关、服务环境、cron 行
carpoolIntact() {
    assert_equals "127.0.0.1:${apiPort}" "$(jq -r '.api.listen' "${XRAY_CONF_DIR}/12_stats_api.json" 2>/dev/null)" "$1：12_stats_api.json 还在"
    assert_equals "0100007F" "$(listenAddrs "${apiPort}")" "$1：统计 API 仍只在 127.0.0.1 上监听"
    assert_equals "true true" "$(jq -r '.policy.levels."0" | "\(.statsUserUplink) \(.statsUserDownlink)"' "${XRAY_CONF_DIR}/12_policy.json" 2>/dev/null)" \
        "$1：12_policy.json 的统计开关还在"
    assert_contains "$(xrayEnviron)" "XRAY_BUF_SPLICE=disable" "$1：Xray 进程仍带 XRAY_BUF_SPLICE=disable"
    assert_equals "${carpoolCron}" "$(crontab -l 2>/dev/null | grep -F 'install.sh CarpoolTick')" "$1：CarpoolTick 的 cron 行还在"
}

# applyMembers [tty] → 菜单 7 → 6 → 2 应用 members.json，打印去色后的输出，退出码随 pasly。
# 带 tty 时经 util-linux 的 script 给它一个终端、对删除确认答 y；pty 的换行是 \r\n，去掉，外面套 timeout 防挂住
applyMembers() {
    if [[ "${1:-}" == "tty" ]]; then
        printf '7\n6\n2\ny\n' | timeout 120 script -qec 'V2RAY_LANG=en pasly' /dev/null 2>&1 | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g'
    else
        printf '7\n6\n2\n' | V2RAY_LANG=en pasly 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    fi
    return "${PIPESTATUS[1]}"
}

# memberUsed NAME [STATE_FILE] → state 里该成员的原始上下行合计（默认读现场的 state.json）
memberUsed() {
    jq -r --arg u "$1" '.members[$u] | .upBytes + .downBytes' "${2:-${carpoolDir}/state.json}" 2>/dev/null
}

# accountExit KEYS → 经菜单 3 → 8 按账号选出口（KEYS 是 printf 格式的后续输入），打印去色后的输出，退出码随 pasly
accountExit() {
    printf '3\n8\n%b' "$1" | V2RAY_LANG=en pasly 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    return "${PIPESTATUS[1]}"
}

# midTransferDown STAT → 起客户端，限速 500 KB/s 下 4 MB，下载期间每 0.5 秒读一次该计数器，打印其中最大的值；下完再关客户端。
# 只认取样之后 curl 还在跑的值：splice 要到连接关闭才计数，curl 退出后取到的满额证明不了什么；不卡固定时刻，建连慢也不误报
midTransferDown() {
    local pid curlPid value=0 sample
    "${clientCmd[@]}" >/tmp/proxy-agent-e2e-client.log 2>&1 &
    pid=$!
    sleep 2
    curl -sS -o /dev/null --max-time 30 --limit-rate 500K --proxy socks5h://127.0.0.1:10808 \
        'https://speed.cloudflare.com/__down?bytes=4000000' 2>/tmp/proxy-agent-e2e-curl.log &
    curlPid=$!
    while sleep 0.5; do
        sample=$(statsValue "$("${XRAY_BIN}" api statsquery -s "127.0.0.1:${apiPort}" -t 3 -pattern 'user>>>' 2>&1)" "$1")
        kill -0 "${curlPid}" 2>/dev/null || break
        [[ "${sample}" =~ ^[0-9]+$ ]] && ((sample > value)) && value=${sample}
    done
    wait "${curlPid}" || cat /tmp/proxy-agent-e2e-curl.log >&2
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    printf '%s\n' "${value}"
}

if [[ "${E2E_CORE}" == "xray" ]]; then
    echo ""
    echo -e "${YELLOW}=== 菜单 7 → 6 → 4：开启拼车 ===${NC}"
    carpoolDir="${INSTALL_ROOT}/carpool"
    carpoolOut=$(printf '7\n6\n4\n' | V2RAY_LANG=en pasly 2>&1)
    carpoolRc=$?
    carpoolOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${carpoolOut}")
    carpoolState=$(cat "${carpoolDir}/state.json" 2>/dev/null)
    if [[ ${carpoolRc} -ne 0 || "$(jq -r '.enabled' <<<"${carpoolState}" 2>/dev/null)" != "true" ]]; then
        tail -n 30 <<<"${carpoolOut}"
    fi
    assert_equals "0" "${carpoolRc}" "开启拼车退出码 0"
    apiPort=$(jq -r '.apiPort' <<<"${carpoolState}" 2>/dev/null)
    assert_equals "true" "$(jq -r '.enabled' <<<"${carpoolState}" 2>/dev/null)" "state.json 记为已开启"
    assert_equals "${E2E_UUID}" "$(jq -r --arg u "${E2E_USER}" '.members[$u].uuid' <<<"${carpoolState}" 2>/dev/null)" \
        "现有账号播种成成员，UUID 沿用 inbound 里的值"
    assert_equals "700" "$(stat -c %a "${carpoolDir}" 2>/dev/null)" "carpool/ 目录权限 700"
    assert_equals "127.0.0.1:${apiPort}" "$(jq -r '.api.listen' "${XRAY_CONF_DIR}/12_stats_api.json" 2>/dev/null)" \
        "12_stats_api.json 的统计 API 只配在 127.0.0.1"
    assert_equals "true true" "$(jq -r '.policy.levels."0" | "\(.statsUserUplink) \(.statsUserDownlink)"' "${XRAY_CONF_DIR}/12_policy.json" 2>/dev/null)" \
        "12_policy.json 打开了按用户的上下行统计"
    # 统计 API 不鉴权，内核实际绑定的地址只能是回环
    assert_equals "0100007F" "$(listenAddrs "${apiPort}")" "统计 API 端口实际只在 127.0.0.1 上监听"
    carpoolCron=$(crontab -l 2>/dev/null | grep -F 'install.sh CarpoolTick')
    assert_equals "*/5 * * * * PROXY_AGENT_DIR=${INSTALL_ROOT} /bin/bash ${INSTALL_ROOT}/install.sh CarpoolTick >> ${INSTALL_ROOT}/crontab_carpool.log 2>&1" \
        "${carpoolCron}" "crontab 里的 CarpoolTick 行带安装根前缀"
    assert_not_empty "$(command -v flock || true)" "flock 可用（state 的读改写靠它加锁）"
    assert_contains "$("${XRAY_BIN}" run -test -confdir "${XRAY_CONF_DIR}" 2>&1)" "Configuration OK" \
        "Xray 在跑、统计 API 端口被它占着时 run -test 照样通过（每次重载前都要过这一关）"
    assert_contains "$(xrayEnviron)" "XRAY_BUF_SPLICE=disable" "开着拼车时 Xray 进程带 XRAY_BUF_SPLICE=disable（${SERVICE_MANAGER}）"

    echo ""
    echo -e "${YELLOW}=== 拼车：真实流量 → 按 cron 的环境跑一次 tick ===${NC}"
    assert_equals "204" "$(realityProbe)" "开启拼车（内核重载过）后客户端照样经服务端访问外网"
    statName="user>>>${E2E_USER}-vless_reality_vision>>>traffic>>>downlink"
    statsRaw=$("${XRAY_BIN}" api statsquery -s "127.0.0.1:${apiPort}" -t 3 -pattern 'user>>>' 2>&1)
    statsDown=$(statsValue "${statsRaw}" "${statName}")
    assert_equals "yes" "$([[ "${statsDown}" =~ ^[0-9]+$ && "${statsDown}" -gt 0 ]] && echo yes || echo no)" \
        "statsquery 有 ${statName}，计数 ${statsDown} > 0"
    tickOut=$(runCarpoolTick "${carpoolCron}")
    tickRc=$?
    if [[ ${tickRc} -ne 0 ]]; then
        echo "${tickOut}"
    fi
    assert_equals "0" "${tickRc}" "CarpoolTick 在 cron 的环境下退出码 0"
    carpoolState=$(cat "${carpoolDir}/state.json" 2>/dev/null)
    usedBytes=$(memberUsed "${E2E_USER}")
    assert_equals "yes" "$([[ "${usedBytes}" =~ ^[0-9]+$ && "${usedBytes}" -gt 0 ]] && echo yes || echo no)" \
        "这次流量记进了 ${E2E_USER} 名下（${usedBytes} 字节）"
    assert_equals "0" "$(jq -r '.collectFailures' <<<"${carpoolState}" 2>/dev/null)" "采集没有失败计数"
    # 整机读真 /proc：开启时那次 tick 记下基线，这次 tick 的增量里含刚才经代理的流量（网卡还多出协议开销）
    assert_equals '["eth0"]' "$(jq -c '.machine.ifaces' <<<"${carpoolState}" 2>/dev/null)" "整机按默认路由找到网卡 eth0"
    machineBytes=$(jq -r '.machine.rx + .machine.tx' <<<"${carpoolState}" 2>/dev/null)
    assert_equals "yes" "$([[ "${machineBytes}" =~ ^[0-9]+$ && "${usedBytes}" =~ ^[0-9]+$ && "${machineBytes}" -ge "${usedBytes}" ]] && echo yes || echo no)" \
        "整机本周期收发 ${machineBytes} 字节，不少于成员统计的 ${usedBytes} 字节"
    # 采集带 -reset：取过的计数器要归零，否则每个 tick 都把累计值重加一遍
    assert_equals "0" "$(statsValue "$("${XRAY_BIN}" api statsquery -s "127.0.0.1:${apiPort}" -t 3 -pattern 'user>>>' 2>&1)" "${statName}")" \
        "tick 采集之后该计数器归零"
    # 关机、重启不经脚本：服务管理器直接停 Xray 时，服务单元的停止钩子也得先把内存里的计数收进 state
    assert_equals "204" "$(realityProbe)" "直接停服务之前再走一次流量"
    usedBefore=$(memberUsed "${E2E_USER}")
    if [[ "${SERVICE_MANAGER}" == "systemd" ]]; then
        systemctl stop xray.service
    else
        rc-service xray stop >/dev/null 2>&1
    fi
    usedAfter=$(memberUsed "${E2E_USER}")
    assert_equals "yes" "$([[ "${usedAfter}" =~ ^[0-9]+$ && "${usedAfter}" -gt "${usedBefore}" ]] && echo yes || echo no)" \
        "不经脚本直接停 Xray（${SERVICE_MANAGER}）：停止钩子把这次流量记进 state（${usedBefore} → ${usedAfter} 字节）"
    if [[ "${SERVICE_MANAGER}" == "systemd" ]]; then
        systemctl start xray.service
    else
        rc-service xray start >/dev/null 2>&1
    fi
    sleep 1.5
    # 经代理够不着统计 API：目标写成 IP、localhost、解析到 127.0.0.1 的域名、IPv4 映射还是 0.0.0.0，都按端口拦下。
    # 只看响应码：没拦时这个 QueryStats(reset) 返回 200 并清零计数；计数本身不能当判据，cron 里的 tick 也会清零
    printf '\x00\x00\x00\x00\x0b\x0a\x07user>>>\x10\x01' >/tmp/proxy-agent-e2e-reset.bin
    for localTarget in 127.0.0.1 localhost localtest.me '[::ffff:127.0.0.1]' 0.0.0.0; do
        assert_equals "000" "$(viaProxyCode --http2-prior-knowledge -H 'content-type: application/grpc' -H 'te: trailers' \
            --data-binary @/tmp/proxy-agent-e2e-reset.bin "http://${localTarget}:${apiPort}/xray.app.stats.command.StatsService/QueryStats")" \
            "经代理连统计 API（${localTarget}:${apiPort}）被拦下，清零请求发不过去"
    done

    echo ""
    echo -e "${YELLOW}=== 菜单 7 → 6 → 2：文件里加一个成员并应用，新成员用自己的 UUID 连得上 ===${NC}"
    E2E_GUEST="e2eguest"
    membersBefore=$(cat "${carpoolDir}/members.json")
    # 不写 uuid：应用时由 Xray 现生成，state 里记下
    membersWithGuest=$(jq --arg g "${E2E_GUEST}" '.members[$g] = {quotaGiB: 0, expire: "", protocols: "all"}' <<<"${membersBefore}")
    printf '%s\n' "${membersWithGuest}" >"${carpoolDir}/members.json"
    addOut=$(applyMembers)
    addRc=$?
    [[ ${addRc} -ne 0 ]] && tail -n 20 <<<"${addOut}"
    assert_equals "0" "${addRc}" "只有新增、不用确认：不在 tty 上也应用成功"
    guestUUID=$(jq -r --arg g "${E2E_GUEST}" '.members[$g].uuid // empty' "${carpoolDir}/state.json" 2>/dev/null)
    assert_equals "yes" "$([[ "${guestUUID}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && echo yes || echo no)" \
        "文件里没写 UUID，state 给 ${E2E_GUEST} 生成了一个（${guestUUID}）"
    assert_equals "${E2E_GUEST}-vless_reality_vision" "$(jq -r --arg id "${guestUUID}" '.inbounds[1].settings.clients[]? | select(.id == $id) | .email' "${realityConf}" 2>/dev/null)" \
        "${E2E_GUEST} 以这个 UUID 进了 Reality 入站"
    guestConf=/tmp/proxy-agent-e2e-client-guest.json
    if [[ "${E2E_CLIENT}" == "xray" ]]; then
        jq --arg id "${guestUUID}" '.outbounds[0].settings.vnext[0].users[0].id = $id' "${clientConf}" >"${guestConf}"
    else
        jq --arg id "${guestUUID}" '.outbounds[0].uuid = $id' "${clientConf}" >"${guestConf}"
    fi
    assert_equals "204" "$(realityProbe "${guestConf}")" "${E2E_GUEST} 用自己的 UUID 经服务端访问外网"

    echo ""
    echo -e "${YELLOW}=== 拼车：从文件删掉这个成员 → 不在 tty 上应用被拒、什么都不改 → 在 tty 上确认删除 ===${NC}"
    printf '%s\n' "${membersBefore}" >"${carpoolDir}/members.json"
    refuseOut=$(applyMembers)
    refuseRc=$?
    assert_equals "yes" "$([[ ${refuseRc} -ne 0 ]] && echo yes || echo no)" "删除要逐项确认，不在 tty 上应用以非零退出（${refuseRc}）"
    assert_contains "${refuseOut}" "must be confirmed item by item in a terminal" "拒绝时告诉车主要在终端里确认"
    assert_equals "true" "$(jq --arg g "${E2E_GUEST}" '.members | has($g)' "${carpoolDir}/state.json" 2>/dev/null)" "被拒后 ${E2E_GUEST} 仍在 state 的成员表里"
    assert_equals "204" "$(realityProbe "${guestConf}")" "被拒后 ${E2E_GUEST} 照样连得上（没有半应用）"
    if command -v script >/dev/null 2>&1; then
        removeOut=$(applyMembers tty)
        removeRc=$?
        [[ ${removeRc} -ne 0 ]] && tail -n 20 <<<"${removeOut}"
        assert_equals "0" "${removeRc}" "在 tty 上确认删除，应用退出码 0"
        assert_contains "${removeOut}" "Remove member ${E2E_GUEST} (account and subscription files)?" "确认提示点名 ${E2E_GUEST}"
        assert_equals "0" "$(jq --arg id "${guestUUID}" '[.inbounds[1].settings.clients[]? | select(.id == $id)] | length' "${realityConf}" 2>/dev/null)" \
            "${E2E_GUEST} 已从 Reality 入站拿掉"
        assert_equals "no" "$([[ "$(realityProbe "${guestConf}" 2>/dev/null)" == "204" ]] && echo yes || echo no)" "被删的 ${E2E_GUEST} 用原 UUID 连不上"
        assert_equals "204" "$(realityProbe)" "${E2E_USER} 不受影响，照常上网"
        removeTickOut=$(runCarpoolTick "${carpoolCron}")
        removeTickRc=$?
        [[ ${removeTickRc} -ne 0 ]] && echo "${removeTickOut}"
        assert_equals "0|0|false" "${removeTickRc}|$(jq --arg id "${guestUUID}" '[.inbounds[1].settings.clients[]? | select(.id == $id)] | length' "${realityConf}" 2>/dev/null)|$(jq 'has("removing")' "${carpoolDir}/state.json" 2>/dev/null)" \
            "删人后的 tick：退出码 0，${E2E_GUEST} 没被加回来，待删记录已清"
        tickOut+=$'\n'"${removeTickOut}"
    else
        # Alpine 只有 BusyBox、没有 script；装 util-linux 会连 BusyBox 的 flock 一起换掉，这条腿就不再测它了
        echo -e "${YELLOW}跳过在 tty 上确认删人：容器里没有 script，这一步只在 Debian 腿上验${NC}"
        printf '%s\n' "${membersWithGuest}" >"${carpoolDir}/members.json"
    fi

    echo ""
    echo -e "${YELLOW}=== 菜单 22 → 3 备份、跑流量，再 22 → 2 回滚并恢复配置：用量不倒回快照那天 ===${NC}"
    backupOut=$(printf '22\n3\n' | V2RAY_LANG=en pasly 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    backupDir=$(ls -1td "${INSTALL_ROOT}"/backup/v* 2>/dev/null | head -n 1)
    assert_contains "${backupOut}" "Backup successful" "手动备份成功"
    snapshotUsed=$(memberUsed "${E2E_USER}" "${backupDir}/config/carpool/state.json")
    membersAtBackup=$(cat "${carpoolDir}/members.json")
    # 备份之后改一下文件（只改配额，tick 会同步、不用应用）：回滚后它回到快照里的样子，才说明快照真的恢复了
    jq --arg u "${E2E_USER}" '.members[$u].quotaGiB = 500' <<<"${membersAtBackup}" >"${carpoolDir}/members.json"
    assert_equals "yes" "$([[ "${snapshotUsed}" =~ ^[0-9]+$ ]] && echo yes || echo no)" "备份的配置快照里带着 carpool/state.json（${E2E_USER} 当时 ${snapshotUsed} 字节）"
    realityProbe >/dev/null
    runCarpoolTick "${carpoolCron}" >/dev/null
    usedBeforeRollback=$(memberUsed "${E2E_USER}")
    assert_equals "yes" "$([[ "${usedBeforeRollback}" =~ ^[0-9]+$ && "${snapshotUsed}" =~ ^[0-9]+$ && usedBeforeRollback -gt snapshotUsed ]] && echo yes || echo no)" \
        "备份之后的流量已记账：${usedBeforeRollback} > 快照里的 ${snapshotUsed}"
    # 这段流量不跑 tick：要么回滚停 Xray 时由停机钩子收进 state，要么被 cron 的 tick 先收走
    realityProbe >/dev/null
    rollbackOut=$(printf '22\n2\n1\ny\ny\n' | V2RAY_LANG=en pasly 2>&1)
    rollbackRc=$?
    rollbackOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${rollbackOut}")
    [[ ${rollbackRc} -ne 0 || "${rollbackOut}" != *"Config restored"* ]] && tail -n 30 <<<"${rollbackOut}"
    assert_equals "0" "${rollbackRc}" "回滚退出码 0"
    assert_contains "${rollbackOut}" "Config restored" "选了恢复配置，配置快照已恢复"
    usedAfterRollback=$(memberUsed "${E2E_USER}")
    assert_equals "yes" "$([[ "${usedAfterRollback}" =~ ^[0-9]+$ && "${usedBeforeRollback}" =~ ^[0-9]+$ && usedAfterRollback -gt usedBeforeRollback ]] && echo yes || echo no)" \
        "回滚后用量 ${usedAfterRollback} 字节：没倒回快照（${snapshotUsed}），回滚前那段流量也记上了（回滚前 ${usedBeforeRollback}）"
    assert_equals "${membersAtBackup}" "$(cat "${carpoolDir}/members.json" 2>/dev/null)" "备份后改过的 members.json 回到快照里的内容"
    carpoolIntact "回滚之后"
    assert_equals "204" "$(realityProbe)" "回滚后 ${E2E_USER} 照常上网"

    chainOut=
    unchainOut=
    if [[ -n "${E2E_CHAIN_CODE:-}" ]]; then
        echo ""
        echo -e "${YELLOW}=== 菜单 3 → 1 → 3：拼车开着时把本机接成链式入口 ===${NC}"
        routingBefore=$(cat "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)
        chainOut=$(printf '3\n1\n3\n%s\n' "${E2E_CHAIN_CODE}" | V2RAY_LANG=en pasly 2>&1)
        chainRc=$?
        chainOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${chainOut}")
        if [[ ${chainRc} -ne 0 || "${chainOut}" != *"链路测试通过"* ]]; then
            tail -n 40 <<<"${chainOut}"
        fi
        assert_equals "0" "${chainRc}" "配置链式入口退出码 0"
        assert_contains "${chainOut}" "链路测试通过" "入口自测：经 sing-box 桥、出口机访问外网"
        assert_equals "chain_proxy" "$(jq -r '.routing.rules[-1].outboundTag' "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)" \
            "Xray 路由的兜底规则改成 chain_proxy（没有直连回落，下面能通就是走了出口）"
        carpoolIntact "装上链式之后"
        assert_contains "$(V2RAY_LANG=en pasly </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')" "Core: Xray-core [Running]" \
            "多了 sing-box 桥之后内核仍认作 Xray（拼车只在 Xray 上计量）"
        assert_equals "204" "$(realityProbe)" "接上链式后客户端经入口 → 出口访问外网"
        # 路由总览：接上链式之后出口要画出来。配置码的密钥和出口地址并排放在状态文件里，打码和选字段都要真生效
        chainKeyPlain=$(sed -E 's/.*[?&]key=([^&]*).*/\1/' <<<"${E2E_CHAIN_CODE}" | base64 -d 2>/dev/null)
        chainHostPlain=${E2E_CHAIN_CODE#*@}
        chainHostPlain=${chainHostPlain%%:*}
        V2RAY_LANG=en pasly topo --out "${topoFile}" >/dev/null 2>&1
        assert_equals "no" "$(grep -qF "${chainHostPlain}" "${topoFile}" && echo yes || echo no)" "路由总览（链式）：默认看不到出口地址 ${chainHostPlain}"
        assert_not_empty "${chainKeyPlain}" "从配置码取到出口的密钥"
        assert_equals "no" "$(grep -qF "${chainKeyPlain}" "${topoFile}" && echo yes || echo no)" "路由总览（链式）：页面里没有出口的密钥"
        V2RAY_LANG=en pasly topo --full --out "${topoFile}" >/dev/null 2>&1
        assert_equals "yes" "$(grep -qF "${chainHostPlain}" "${topoFile}" && echo yes || echo no)" "路由总览（链式）：--full 显示出口地址"
        assert_equals "no" "$(grep -qF "${chainKeyPlain}" "${topoFile}" && echo yes || echo no)" "路由总览（链式）：--full 的页面里也没有密钥"
    fi

    # Vision 下行走 splice 时要到连接关闭才计数，传输中只看得到握手那几十 KB；关掉 splice 后边传边记
    midDown=$(midTransferDown "${statName}")
    assert_equals "yes" "$([[ "${midDown}" =~ ^[0-9]+$ && "${midDown}" -gt 300000 ]] && echo yes || echo no)" \
        "限速下载进行到一半时下行计数已过 300 KB（${midDown} 字节）"
    if [[ -n "${E2E_CHAIN_CODE:-}" ]]; then
        chainTickOut=$(runCarpoolTick "${carpoolCron}")
        chainTickRc=$?
        [[ ${chainTickRc} -ne 0 ]] && echo "${chainTickOut}"
        assert_equals "0" "${chainTickRc}" "链式开着时 CarpoolTick 退出码 0"
        usedAfter=$(memberUsed "${E2E_USER}")
        assert_equals "yes" "$([[ "${usedAfter}" =~ ^[0-9]+$ && $((usedAfter - usedBytes)) -ge 4000000 ]] && echo yes || echo no)" \
            "经链式的 4 MB 下载记进了 ${E2E_USER} 名下（增加 $((usedAfter - usedBytes)) 字节）"
        tickOut+=$'\n'"${chainTickOut}"

        echo ""
        echo -e "${YELLOW}=== 菜单 3 → 8：按账号选出口，出口机断了只断指向它的人 ===${NC}"
        # 把出口机路由成黑洞：走链路的连接立刻失败。先证明拦截生效，下面「直连照样通」才说明没经过出口
        chainExitIP=${E2E_CHAIN_CODE#*@}
        chainExitIP=${chainExitIP%%:*}
        ip route add blackhole "${chainExitIP}/32"
        assert_equals "no" "$([[ "$(realityProbe 2>/dev/null)" == "204" ]] && echo yes || echo no)" \
            "出口机断了：没指定出口、默认走链路的 ${E2E_USER} 连不上（拦截生效，也没回落到直连）"
        acctIdx=$(accountExit 'x\n' | sed -n "s/^ *\([0-9][0-9]*\)\. ${E2E_USER} → .*/\1/p")
        assert_not_empty "${acctIdx}" "菜单 3 → 8 列出 ${E2E_USER}"
        acctOut=$(accountExit "${acctIdx}\n2\n")
        acctRc=$?
        [[ ${acctRc} -ne 0 ]] && tail -n 20 <<<"${acctOut}"
        assert_equals "0|direct" "${acctRc}|$(jq -r --arg u "${E2E_USER}" '.accounts[$u]' "${INSTALL_ROOT}/sing-box/conf/chain_entry_info.json" 2>/dev/null)" \
            "${E2E_USER} 指定直连：菜单退出码 0，映射写进链式状态"
        assert_equals "204" "$(realityProbe)" "指定直连的 ${E2E_USER} 不经出口机照样上网"
        accountExit "${acctIdx}\n3\n" >/dev/null
        assert_equals "no" "$([[ "$(realityProbe 2>/dev/null)" == "204" ]] && echo yes || echo no)" \
            "指定走链路的 ${E2E_USER} 在出口断了时断开，不回落到直连"
        accountExit '0\n2\n' >/dev/null
        accountExit "${acctIdx}\n1\n" >/dev/null
        assert_equals "chain_direct" "$(jq -r '.routing.rules[-1].outboundTag' "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)" \
            "默认出口改成直连：Xray 兜底规则随之直连"
        assert_equals "204" "$(realityProbe)" "跟随默认、默认直连的 ${E2E_USER} 照样上网"
        accountExit '0\n1\n' >/dev/null
        ip route del blackhole "${chainExitIP}/32"
        assert_equals "chain_proxy" "$(jq -r '.routing.rules[-1].outboundTag' "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)" \
            "默认出口改回链路"
        assert_equals "204" "$(realityProbe)" "出口机恢复后，${E2E_USER} 经链路照常上网"
    fi

    rolloverOut=
    if command -v apt-get >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}=== 拼车：超额停用 → 到下一个重置日的 tick 清零、恢复 ===${NC}"
        apt-get install -y -qq faketime >/dev/null 2>&1
        assert_not_empty "$(command -v faketime || true)" "装上 faketime（只给这一次 tick 换日期）"
        assert_contains "$(V2RAY_LANG=en faketime -f '+300s' pasly doctor 2>&1 | sed 's/\x1b\[[0-9;]*m//g')" "[WARN] System clock" "时钟快 5 分钟：doctor 告警"
        # 这段把周期翻到假日期：cron 按真实时钟的 tick 插进来会把起点改回去、断言变红。
        # 摘 cron 行没用（重载时 ensureCarpoolCron 会补回来），只能停服务、等在跑的那次结束，段尾再起
        systemctl stop cron
        for _ in $(seq 1 60); do pgrep -f 'install.sh CarpoolTick' >/dev/null || break; sleep 1; done
        printf '%s\n' "$(jq --arg u "${E2E_USER}" '.members[$u].quotaGiB = 1' "${carpoolDir}/members.json")" >"${carpoolDir}/members.json"
        # 一个周期的用量测试里跑不出来：拿 state 的同一把锁，把已用量记成 1.5 GiB（cron 里的 tick 不会写到一半）
        flock "${carpoolDir}/.lock" bash -c 'jq --arg u "$1" ".members[\$u].downBytes += 1610612736" "$2" >"$2.e2e" && cat "$2.e2e" >"$2" && rm -f "$2.e2e"' \
            _ "${E2E_USER}" "${carpoolDir}/state.json"
        quotaOut=$(runCarpoolTick "${carpoolCron}")
        assert_equals "0|disabled quota" "$?|$(jq -r --arg u "${E2E_USER}" '.members[$u] | "\(.status) \(.reason)"' "${carpoolDir}/state.json" 2>/dev/null)" \
            "超过 1 GiB 配额：tick 退出码 0，${E2E_USER} 判为超额停用"
        assert_equals "no" "$([[ "$(realityProbe 2>/dev/null)" == "204" ]] && echo yes || echo no)" "超额停用后原链接连不上"
        nextReset=$(source "${INSTALL_ROOT}/lib/carpool.sh" >/dev/null 2>&1
            carpoolNextPeriodStart "$(date +%F)" "$(jq -r '.resetDay' "${carpoolDir}/state.json")")
        rolloverOut=$(runCarpoolTick "${carpoolCron}" "${nextReset} 00:10:00")
        rolloverRc=$?
        [[ ${rolloverRc} -ne 0 ]] && echo "${rolloverOut}"
        carpoolState=$(cat "${carpoolDir}/state.json" 2>/dev/null)
        assert_equals "0|${nextReset}" "${rolloverRc}|$(jq -r '.period' <<<"${carpoolState}" 2>/dev/null)" \
            "到了下一个重置日 ${nextReset}：tick 退出码 0，周期起点换到这一天"
        assert_equals "active|0" "$(jq -r --arg u "${E2E_USER}" '.members[$u] | "\(.status)|\(.upBytes + .downBytes)"' <<<"${carpoolState}" 2>/dev/null)" \
            "新周期里 ${E2E_USER} 用量清零、超额停用自动恢复"
        assert_equals "1" "$(jq --arg id "${E2E_UUID}" '[.inbounds[1].settings.clients[]? | select(.id == $id)] | length' "${realityConf}" 2>/dev/null)" \
            "${E2E_USER} 放回了 Reality 入站"
        assert_equals "204" "$(realityProbe)" "恢复后原链接重新连得上"
        # 回到真实日期：起点按真实日期算回来（起点前移只改起点、不清零），刚才那段流量照记，成员不受影响
        usedBeforeReal=$(memberUsed "${E2E_USER}")
        realStart=$(source "${INSTALL_ROOT}/lib/carpool.sh" >/dev/null 2>&1
            carpoolPeriodStart "$(date +%F)" "$(jq -r '.resetDay' "${carpoolDir}/state.json")")
        afterOut=$(runCarpoolTick "${carpoolCron}")
        assert_equals "0|${realStart}|active|yes" "$?|$(jq -r --arg u "${E2E_USER}" '"\(.period)|\(.members[$u].status)"' "${carpoolDir}/state.json" 2>/dev/null)|$(
            [[ "$(memberUsed "${E2E_USER}")" -ge "${usedBeforeReal:-0}" ]] && echo yes || echo no)" \
            "回到真实日期的 tick：周期起点算回 ${realStart}，不再清零，${E2E_USER} 仍可用"
        printf '%s\n' "$(jq --arg u "${E2E_USER}" '.members[$u].quotaGiB = 0' "${carpoolDir}/members.json")" >"${carpoolDir}/members.json"
        rolloverOut+=$'\n'"${quotaOut}"$'\n'"${afterOut}"
        systemctl start cron
    fi

    echo ""
    echo -e "${YELLOW}=== 拼车：到期日改到过去 → tick 停用 → 原链接连不上 ===${NC}"
    expiredMembers=$(jq --arg u "${E2E_USER}" '.members[$u].expire = "2020-01-01"' "${carpoolDir}/members.json")
    printf '%s\n' "${expiredMembers}" >"${carpoolDir}/members.json"
    expireOut=$(runCarpoolTick "${carpoolCron}")
    expireRc=$?
    if [[ ${expireRc} -ne 0 ]]; then
        echo "${expireOut}"
    fi
    assert_equals "0" "${expireRc}" "这次 tick 要重载内核，在 cron 的环境下退出码仍是 0"
    carpoolState=$(cat "${carpoolDir}/state.json" 2>/dev/null)
    assert_equals "disabled expired" "$(jq -r --arg u "${E2E_USER}" '.members[$u] | "\(.status) \(.reason)"' <<<"${carpoolState}" 2>/dev/null)" \
        "tick 读入新的到期日，${E2E_USER} 判为到期停用"
    assert_equals "0" "$(jq --arg id "${E2E_UUID}" '[.inbounds[1].settings.clients[]? | select(.id == $id)] | length' "${realityConf}" 2>/dev/null)" \
        "${E2E_USER} 已从 Reality 入站拿掉"
    assert_not_empty "$(pgrep -f "${XRAY_BIN}" || true)" "入站里一个用户都不剩时 Xray 照样在跑"
    assert_equals "no" "$([[ "$(realityProbe 2>/dev/null)" == "204" ]] && echo yes || echo no)" "停用后用原链接连不上"

    if [[ -n "${E2E_CHAIN_CODE:-}" ]]; then
        echo ""
        echo -e "${YELLOW}=== 菜单 3 → 5：拼车开着时拆掉链式 ===${NC}"
        unchainOut=$(printf '3\n5\ny\n' | V2RAY_LANG=en pasly 2>&1)
        unchainRc=$?
        unchainOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${unchainOut}")
        [[ ${unchainRc} -ne 0 ]] && tail -n 30 <<<"${unchainOut}"
        assert_equals "0" "${unchainRc}" "卸载链式退出码 0"
        assert_equals "${routingBefore}" "$(cat "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)" "09_routing.json 还原成接链式之前的内容"
        assert_equals "no" "$([[ -e "${XRAY_CONF_DIR}/chain_outbound.json" ]] && echo yes || echo no)" "Xray 的 chain_outbound.json 已删"
        # 旁挂的 sing-box 没东西可服务了就得停：留着的话，本机任何进程都能经回环上的桥从出口出网
        assert_equals "" "$(pgrep -x sing-box || true)" "拆掉链式后旁挂的 sing-box 已停"
        assert_equals "" "$(listenAddrs 31111)" "拆掉链式后桥的 31111 不再监听"
        carpoolIntact "拆掉链式之后"
        assert_equals "0" "$(jq --arg id "${E2E_UUID}" '[.inbounds[1].settings.clients[]? | select(.id == $id)] | length' "${realityConf}" 2>/dev/null)" \
            "拆链式重启 Xray 之后，到期的 ${E2E_USER} 仍不在 Reality 入站里"
    fi

    echo ""
    echo -e "${YELLOW}=== 菜单 7 → 6 → 4：关闭拼车，到期的也一并恢复 ===${NC}"
    disableOut=$(printf '7\n6\n4\ny\ny\n' | V2RAY_LANG=en pasly 2>&1)
    disableRc=$?
    disableOut=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${disableOut}")
    carpoolState=$(cat "${carpoolDir}/state.json" 2>/dev/null)
    if [[ ${disableRc} -ne 0 || "$(jq -r '.enabled' <<<"${carpoolState}" 2>/dev/null)" != "false" ]]; then
        tail -n 30 <<<"${disableOut}"
    fi
    assert_equals "0" "${disableRc}" "关闭拼车退出码 0"
    assert_equals "false" "$(jq -r '.enabled' <<<"${carpoolState}" 2>/dev/null)" "state.json 记为已关闭"
    assert_equals "active" "$(jq -r --arg u "${E2E_USER}" '.members[$u].status' <<<"${carpoolState}" 2>/dev/null)" \
        "第二问答了 y，到期停用的 ${E2E_USER} 也恢复了"
    assert_equals "1" "$(jq --arg id "${E2E_UUID}" '[.inbounds[1].settings.clients[]? | select(.id == $id)] | length' "${realityConf}" 2>/dev/null)" \
        "${E2E_USER} 用原 UUID 放回了 Reality 入站"
    assert_equals "no" "$([[ -e "${XRAY_CONF_DIR}/12_stats_api.json" ]] && echo yes || echo no)" "12_stats_api.json 已撤掉"
    assert_equals "" "$(xrayEnviron | grep XRAY_BUF_SPLICE || true)" "关掉拼车后 Xray 进程不再带 XRAY_BUF_SPLICE"
    assert_equals "no" "$([[ -e /etc/systemd/system/xray.service.d/carpool.conf || -e /etc/conf.d/xray ]] && echo yes || echo no)" \
        "systemd drop-in / OpenRC conf.d 撤干净"
    assert_equals "false false" "$(jq -r '.policy.levels."0" | "\(has("statsUserUplink")) \(has("statsUserDownlink"))"' "${XRAY_CONF_DIR}/12_policy.json" 2>/dev/null)" \
        "12_policy.json 的两个统计字段已撤掉"
    assert_equals "" "$(crontab -l 2>/dev/null | grep -F 'install.sh CarpoolTick' || true)" "CarpoolTick 的 cron 行已删"
    assert_equals "" "$(listenAddrs "${apiPort}")" "统计 API 端口不再监听"
    assert_equals "yes" "$([[ -s "${carpoolDir}/members.json" ]] && echo yes || echo no)" "members.json 保留"
    assert_equals "204" "$(realityProbe)" "恢复后原链接重新连得上（客户端配置没动过）"

    noisyLines=$(grep -E 'command not found|No such file or directory' <<<"${carpoolOut}"$'\n'"${tickOut}"$'\n'"${addOut}"$'\n'"${refuseOut}"$'\n'"${removeOut}"$'\n'"${backupOut}"$'\n'"${rollbackOut}"$'\n'"${expireOut}"$'\n'"${rolloverOut}"$'\n'"${chainOut}"$'\n'"${unchainOut}"$'\n'"${disableOut}" || true)
    if [[ -n "${noisyLines}" ]]; then
        echo "${noisyLines}"
    fi
    assert_equals "" "${noisyLines}" "拼车各步的输出里没有 command not found / No such file"
fi

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
    assert_equals "no" "$([[ -e "/etc/systemd/system/${CORE_SERVICE}.service" ]] && echo yes || echo no)" "${CORE_SERVICE}.service 单元文件已删除"
else
    assert_equals "no" "$([[ -e "/etc/init.d/${CORE_SERVICE}" ]] && echo yes || echo no)" "/etc/init.d/${CORE_SERVICE} 已删除"
    assert_equals "" "$(rc-update show default 2>/dev/null | grep -F "${CORE_SERVICE}" || true)" "${CORE_SERVICE} 已从 default 运行级移除"
fi
assert_equals "" "$(pgrep -f "${CORE_BIN}" || true)" "${CORE_SERVICE} 进程已退出"
assert_equals "no" "$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${E2E_PORT}" 2>/dev/null && echo yes || echo no)" "127.0.0.1:${E2E_PORT} 不再监听"
assert_equals "" "$(crontab -l 2>/dev/null | grep -F "${INSTALL_ROOT}/install.sh" || true)" "crontab 里不再有指向已删 install.sh 的定时任务"

e2eSummary "真装机端到端测试" "${E2E_LOG}"
