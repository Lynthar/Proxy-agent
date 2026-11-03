#!/usr/bin/env bash
# test_install_domain_e2e.sh - 带域名的真装机端到端：以 root 在一次性 Debian 容器里走菜单 1 的 Xray 全部安装，
# 装订阅、旁挂 Hysteria2、装到一半退出、换域名重装、拼车的页面与补装协议、只留 Reality、换成 sing-box 全部安装，最后卸载并核对残留。
# 每个节点都拿订阅里发出去的配置真握手。证书由测试 CA 签、预先放进 tls/（脚本的自定义证书路径），ACME 签发不在这条腿里。跑法见 tests/e2e/run.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/e2e/assert.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
INSTALL_ROOT="${PROXY_AGENT_DIR:-/etc/Proxy-agent}"
TLS_DIR="${INSTALL_ROOT}/tls"
XRAY_BIN="${INSTALL_ROOT}/xray/xray"
XRAY_CONF_DIR="${INSTALL_ROOT}/xray/conf"
SINGBOX_BIN="${INSTALL_ROOT}/sing-box/sing-box"
SINGBOX_FRAGMENT_DIR="${INSTALL_ROOT}/sing-box/conf/config"
E2E_LOG="/tmp/proxy-agent-e2e-domain.log"
WORK=/tmp/proxy-agent-e2e-domain
E2E_UUID="11111111-2222-3333-4444-555555555555"
E2E_USER="e2euser"

if [[ "$(id -u)" != "0" || "$(uname -s)" != "Linux" ]]; then
    echo -e "${RED}必须在 Linux 上以 root 运行${NC}"
    exit 2
fi
if [[ ! -f /.dockerenv && -z "${PROXY_AGENT_E2E_HOST:-}" ]]; then
    echo -e "${RED}这是真装机测试，会改写整机状态、往 lo 上加地址；只在容器里跑，或显式 PROXY_AGENT_E2E_HOST=1${NC}"
    exit 2
fi
# 证书要先放进 tls/，所以安装根本身可以已存在；有脚本或 pasly 才算装过
if [[ -e "${INSTALL_ROOT}/install.sh" || -e /usr/bin/pasly ]]; then
    echo -e "${RED}本机已有 Proxy-agent 安装（${INSTALL_ROOT}/install.sh 或 /usr/bin/pasly），拒绝在其上覆盖${NC}"
    exit 2
fi
if [[ ! -d /run/systemd/system ]]; then
    echo -e "${RED}这条腿只跑 systemd 的 Debian：nginx、两个内核与 cron 都按 systemd 判活${NC}"
    exit 2
fi
mkdir -p "${WORK}"
: >"${E2E_LOG}"

echo "=============================================="
echo -e "${YELLOW}Proxy-agent 带域名的真装机端到端测试${NC}"
echo -e "${YELLOW}$(. /etc/os-release && echo "${PRETTY_NAME}") · $(uname -m)${NC}"
echo "=============================================="

# ============================================================================
# 本机当一台公网 IP 在网卡上的 VPS：出口 IP 挂到 lo，sslip.io 的名字解析到它，测试 CA 进系统信任
# ============================================================================

# 出口 IP 与 install.sh 的 getPublicIP 同一个来源；容器里还没有 curl，用 openssl 直接发请求
publicIP=$(printf 'GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n' |
    openssl s_client -quiet -connect www.cloudflare.com:443 -servername www.cloudflare.com 2>/dev/null | tr -d '\r' | sed -n 's/^ip=//p')
if [[ ! "${publicIP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}拿不到 IPv4 出口地址（${publicIP:-空}），这条腿要 IPv4 出网${NC}"
    exit 2
fi
ip addr add "${publicIP}/32" dev lo
DOMAIN_A="a.${publicIP//./-}.sslip.io"
DOMAIN_B="b.${publicIP//./-}.sslip.io"
if [[ "$(getent ahostsv4 "${DOMAIN_A}" | awk 'NR == 1 {print $1}')" != "${publicIP}" ]]; then
    echo -e "${RED}${DOMAIN_A} 没解析到 ${publicIP}：这条腿依赖 sslip.io 的公共 DNS${NC}"
    exit 2
fi

# 签 EC P-256：sing-box 1.14 起客户端默认模仿 Chrome 握手，不认 Ed25519
caDir="${WORK}/ca"
mkdir -p "${caDir}"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3 -subj /CN=proxy-agent-e2e-ca \
    -keyout "${caDir}/ca.key" -out "${caDir}/ca.crt" >/dev/null 2>&1
# issueCert DOMAIN → 用测试 CA 给 DOMAIN 签一张证书，放在 ${caDir}/DOMAIN.{crt,key}
issueCert() {
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj "/CN=$1" \
        -keyout "${caDir}/$1.key" -out "${caDir}/$1.csr" >/dev/null 2>&1
    printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$1" >"${caDir}/$1.ext"
    openssl x509 -req -in "${caDir}/$1.csr" -CA "${caDir}/ca.crt" -CAkey "${caDir}/ca.key" -CAcreateserial \
        -days 2 -extfile "${caDir}/$1.ext" -out "${caDir}/$1.crt" >/dev/null 2>&1
}
issueCert "${DOMAIN_A}"
issueCert "${DOMAIN_B}"
cp "${caDir}/ca.crt" /usr/local/share/ca-certificates/proxy-agent-e2e-ca.crt
update-ca-certificates >/dev/null 2>&1

# 残留核对的基线：安装前的文件树、软件包与 crontab
# snapFiles → 本机文件清单（排除运行时、缓存、日志与包管理器自己的状态）
snapFiles() {
    find / -xdev \( -path /proc -o -path /sys -o -path /run -o -path /tmp -o -path /var/tmp -o -path /var/cache \
        -o -path /var/log -o -path /var/lib/apt -o -path /var/lib/dpkg -o -path /var/lib/systemd -o -path /var/lib/ucf \
        -o -path /root/.cache -o -path /dev \) -prune -o -print 2>/dev/null | sort
}
snapFiles >"${WORK}/files-before"
dpkg-query -W -f '${Package}\n' | sort >"${WORK}/pkgs-before"

placeCert() {
    mkdir -p "${TLS_DIR}"
    cp "${caDir}/$1.crt" "${TLS_DIR}/$1.crt"
    cp "${caDir}/$1.key" "${TLS_DIR}/$1.key"
}
placeCert "${DOMAIN_A}"

cp "${PROJECT_ROOT}/install.sh" "${PROJECT_ROOT}/VERSION" "${HOME}/"
cp -r "${PROJECT_ROOT}/lib" "${HOME}/lib"
mkdir -p "${HOME}/shell"
cp -r "${PROJECT_ROOT}/shell/lang" "${HOME}/shell/lang"

# ============================================================================
# 助手：菜单驱动、订阅、真握手
# ============================================================================

# runMenu KEYS [SCRIPT] → 按 KEYS（%b 转义）把答案喂给 pasly（或 SCRIPT），去色输出追加进 E2E_LOG 并打印，退出码随它
runMenu() {
    local out rc
    out=$(printf '%b' "$1" | V2RAY_LANG=en bash "${2:-/usr/bin/pasly}" 2>&1)
    rc=$?
    out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${out}")
    printf '\n===== %s =====\n%s\n' "$1" "${out}" >>"${E2E_LOG}"
    printf '%s\n' "${out}"
    return "${rc}"
}

# noNoise LABEL OUTPUT → 这一步的输出里没有找不到的命令或文件
noNoise() {
    local noisy
    noisy=$(grep -E 'command not found|No such file or directory' <<<"$2" || true)
    [[ -n "${noisy}" ]] && echo "${noisy}"
    assert_equals "" "${noisy}" "$1：输出里没有 command not found / No such file"
}

# activeState → xray sing-box nginx 三个服务此刻的状态，空格分隔
activeState() {
    local s out=
    for s in xray sing-box nginx; do
        out+="$(systemctl is-active "${s}" 2>/dev/null) "
    done
    printf '%s\n' "${out% }"
}

# subPort / subKey → 订阅的端口与本账号订阅地址里的 md5
subPort() {
    grep -oE 'listen [0-9]+ ssl so_keepalive' /etc/nginx/conf.d/subscribe.conf 2>/dev/null | awk '{print $2}' | head -n 1
}
subKey() {
    ls "${INSTALL_ROOT}/subscribe/default/" 2>/dev/null | head -n 1
}
# fetchSub DOMAIN UA OUT → 以 UA 取通用订阅地址存进 OUT，打印 HTTP 状态码
fetchSub() {
    curl -sS -o "$3" -w '%{http_code}' --max-time 15 -A "$2" "https://$1:$(subPort)/s/$(subKey)" 2>/dev/null
}

# 客户端：官方 sing-box 最新稳定版，系统信任库里有测试 CA，订阅里的 server_name 照常校验
SB_CLIENT="${WORK}/sing-box-client/sing-box"
fetchSingBoxClient() {
    local tag arch
    tag=$(curl -sIL -o /dev/null -w '%{url_effective}' --max-time 20 https://github.com/SagerNet/sing-box/releases/latest)
    tag=${tag##*/}
    case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    esac
    mkdir -p "${SB_CLIENT%/*}"
    curl -sSL --max-time 120 "https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${tag#v}-linux-${arch}.tar.gz" |
        tar -xz -C "${SB_CLIENT%/*}" --strip-components=1
}

# probeOutbound SUBFILE TAG → 只用订阅里这一个出站起 sing-box 客户端，经它访问外网，打印 HTTP 状态码（连不上是 000）。
# 不是 204 就把 curl 与客户端的报错打出来再试一次：经代理连 google 偶发 curl (35)，一条腿二十多次握手几乎每轮撞一次
probeOutbound() {
    local code
    code=$(probeOutboundOnce "$@")
    if [[ "${code}" != "204" ]]; then
        echo -e "${YELLOW}  第一次握手得 ${code}，重试一次${NC}" >&2
        code=$(probeOutboundOnce "$@")
    fi
    printf '%s\n' "${code}"
}

# probeOutboundOnce SUBFILE TAG → probeOutbound 的一次尝试
probeOutboundOnce() {
    local conf="${WORK}/client.json" pid code
    jq --arg t "$2" '{log: {level: "warn"}, dns: {servers: [{type: "local", tag: "local"}]},
        inbounds: [{type: "socks", listen: "127.0.0.1", listen_port: 10808}],
        outbounds: [.outbounds[] | select(.tag == $t)],
        route: {final: $t, default_domain_resolver: "local"}}' "$1" >"${conf}"
    "${SB_CLIENT}" run -c "${conf}" >"${WORK}/client.log" 2>&1 &
    pid=$!
    sleep 2
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --proxy socks5h://127.0.0.1:10808 https://www.google.com/generate_204 2>"${WORK}/curl.err")
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    [[ "${code}" != "204" ]] && cat "${WORK}/curl.err" >&2 && tail -n 3 "${WORK}/client.log" >&2
    printf '%s\n' "${code}"
}

# probeSub LABEL SUBFILE → 订阅里每个代理出站都真握手一次，每个都要 204；出站类型排好序、空格分隔放进 probedTypes 供调用方核对
probeSub() {
    local tag type code
    probedTypes=
    while IFS=$'\t' read -r tag type; do
        code=$(probeOutbound "$2" "${tag}")
        assert_equals "204" "${code}" "$1：订阅里的 ${type} 节点（${tag}）真握手、经它访问外网"
        probedTypes+="${type} "
    done < <(jq -r '.outbounds[] | select(.type | test("^(vless|vmess|trojan|hysteria2|tuic|naive|anytls|shadowsocks)$")) | "\(.tag)\t\(.type)"' "$2")
    probedTypes=$(tr ' ' '\n' <<<"${probedTypes}" | grep . | sort | tr '\n' ' ' | sed 's/ $//')
}

# probeXhttpLink LINK → 按 Reality XHTTP 分享链接起 Xray 客户端（sing-box 没有 XHTTP），经它访问外网，打印 HTTP 状态码；
# 不是 204 时同 probeOutbound 再试一次
probeXhttpLink() {
    local code
    code=$(probeXhttpLinkOnce "$@")
    if [[ "${code}" != "204" ]]; then
        echo -e "${YELLOW}  第一次握手得 ${code}，重试一次${NC}" >&2
        code=$(probeXhttpLinkOnce "$@")
    fi
    printf '%s\n' "${code}"
}

# probeXhttpLinkOnce LINK → probeXhttpLink 的一次尝试
probeXhttpLinkOnce() {
    local link=$1 query pid code pair key value
    local -A p=()
    query=${link#*\?}
    query=${query%%#*}
    for pair in ${query//&/ }; do
        key=${pair%%=*}
        value=${pair#*=}
        p[${key}]=${value}
    done
    local hostPort=${link#*@}
    hostPort=${hostPort%%\?*}
    jq -n --arg id "$(sed 's#^vless://##; s#@.*##' <<<"${link}")" --arg addr "${hostPort%:*}" --arg port "${hostPort##*:}" \
        --arg sni "${p[sni]:-}" --arg fp "${p[fp]:-}" --arg pbk "${p[pbk]:-}" --arg sid "${p[sid]:-}" --arg path "${p[path]:-}" \
        --arg host "${p[host]:-}" '{log: {loglevel: "warning"},
        inbounds: [{listen: "127.0.0.1", port: 10809, protocol: "socks"}],
        outbounds: [{protocol: "vless",
            settings: {vnext: [{address: $addr, port: ($port | tonumber), users: [{id: $id, encryption: "none"}]}]},
            streamSettings: {network: "xhttp", security: "reality",
                realitySettings: {serverName: $sni, fingerprint: $fp, publicKey: $pbk, shortId: $sid},
                xhttpSettings: {path: $path, host: $host}}}]}' >"${WORK}/xhttp.json"
    "${XRAY_BIN}" run -c "${WORK}/xhttp.json" >"${WORK}/xhttp.log" 2>&1 &
    pid=$!
    sleep 2
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --proxy socks5h://127.0.0.1:10809 https://www.google.com/generate_204 2>"${WORK}/curl.err")
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    [[ "${code}" != "204" ]] && cat "${WORK}/curl.err" >&2 && tail -n 3 "${WORK}/xhttp.log" >&2
    printf '%s\n' "${code}"
}

# ============================================================================
# 菜单 1 → 1：Xray 全部安装，域名 A；两个 Reality 都以本机域名为目标（本机伪装站在 127.0.0.1 上兜底）
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 1 → 1：Xray 全部安装（${DOMAIN_A}）===${NC}"
# 域名、0 的端口（回车 443）、path（回车随机）、UUID、用户名；12：端口回车、本机域名当目标 y、私钥回车生成；7：端口回车、本机域名 y
s1Out=$(runMenu "1\n1\n${DOMAIN_A}\n\n\n${E2E_UUID}\n${E2E_USER}\n\ny\n\n\ny\n" "${HOME}/install.sh")
s1Rc=$?
[[ ${s1Rc} -ne 0 ]] && tail -n 30 <<<"${s1Out}"
assert_equals "0" "${s1Rc}" "Xray 带域名全部安装退出码 0"
noNoise "Xray 全部安装" "${s1Out}"
assert_equals "active - active" "$(activeState | sed 's/inactive/-/; s/unknown/-/')" "Xray 与 nginx 在跑，sing-box 没装"
assert_equals "enabled enabled" "$(systemctl is-enabled xray nginx 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "Xray 与 nginx 开机自启"
assert_contains "$("${XRAY_BIN}" run -test -confdir "${XRAY_CONF_DIR}" 2>&1)" "Configuration OK" "xray run -test 通过"
for f in 02_VLESS_TCP_inbounds 03_VLESS_WS_inbounds 04_trojan_TCP_inbounds 05_VMess_WS_inbounds 07_VLESS_vision_reality_inbounds 12_VLESS_XHTTP_inbounds; do
    assert_equals "yes" "$([[ -f "${XRAY_CONF_DIR}/${f}.json" ]] && echo yes || echo no)" "${f}.json 已生成"
done
assert_equals "127.0.0.1:31305" "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json" 2>/dev/null)" \
    "Reality 以本机域名为目标时拨 127.0.0.1:31305，不拨订阅口"
assert_contains "$(cat /etc/nginx/conf.d/reality_dest.conf 2>/dev/null)" "server_name ${DOMAIN_A};" "reality_dest.conf 是 ${DOMAIN_A} 的本机伪装站"
assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${DOMAIN_A}/")" \
    "https://${DOMAIN_A}/ 由 443 回落到伪装站，证书按测试 CA 校验通过"
assert_equals "301 https://${DOMAIN_A}/" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 "http://${DOMAIN_A}/")" \
    "80 端口把本域名 301 到 https"
assert_contains "$(crontab -l 2>/dev/null)" "install.sh RenewTLS" "crontab 里有证书维护任务"

echo ""
echo -e "${YELLOW}=== 菜单 7 → 2：订阅（端口回车随机、伪装站不重装、salt 回车随机）===${NC}"
s2Out=$(runMenu "7\n2\n\n\n\n")
s2Rc=$?
assert_equals "0" "${s2Rc}" "装订阅退出码 0"
noNoise "装订阅" "${s2Out}"
assert_contains "$(cat /etc/nginx/conf.d/subscribe.conf 2>/dev/null)" "server_name ${DOMAIN_A};" "subscribe.conf 用 ${DOMAIN_A}"
subKeyA=$(subKey)
assert_not_empty "${subKeyA}" "订阅目录里有本账号的订阅文件"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "sing-box 的 UA 取订阅 200"
assert_equals "0" "$(jq -e '.outbounds | length > 0' "${WORK}/sub-sb.json" >/dev/null 2>&1; echo $?)" "sing-box 的 UA 拿到的是 sing-box 配置"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'clash-verge/v2.4.0' "${WORK}/sub-clash.yaml")" "Clash 系 UA 取订阅 200"
assert_contains "$(cat "${WORK}/sub-clash.yaml")" "proxies:" "Clash 系 UA 拿到带 proxies 的完整配置"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'v2rayN/7.0' "${WORK}/sub-default.txt")" "其他 UA 取订阅 200"
assert_contains "$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null)" "vless://${E2E_UUID}@" "其他 UA 拿到 base64 的分享链接"

echo ""
echo -e "${YELLOW}=== 订阅里的每个节点真握手 ===${NC}"
fetchSingBoxClient
assert_equals "yes" "$([[ -x "${SB_CLIENT}" ]] && echo yes || echo no)" "官方 sing-box 客户端已就位（$("${SB_CLIENT}" version 2>/dev/null | awk 'NR == 1 {print $3}')）"
probeSub "Xray 全装" "${WORK}/sub-sb.json"
assert_equals "trojan vless vless vless vmess" "${probedTypes}" "sing-box 订阅里是 VLESS TLS / WS / Reality、VMess、Trojan 五个节点"
xhttpLink=$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'type=xhttp')
assert_not_empty "${xhttpLink}" "通用订阅里有 Reality XHTTP 的链接"
assert_equals "204" "$(probeXhttpLink "${xhttpLink}")" "按 XHTTP 链接配的 Xray 客户端经服务端访问外网"

# ============================================================================
# 菜单 4 → 1：Xray 机上旁挂 Hysteria2，同一个账号
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 4 → 1：旁挂 Hysteria2（沿用账号、端口回车、默认带宽与不混淆）===${NC}"
s3Out=$(runMenu "4\n1\ny\n\n\n\n")
s3Rc=$?
[[ ${s3Rc} -ne 0 ]] && tail -n 20 <<<"${s3Out}"
assert_equals "0" "${s3Rc}" "装 Hysteria2 退出码 0"
noNoise "装 Hysteria2" "${s3Out}"
assert_equals "active active active" "$(activeState)" "Xray、sing-box、nginx 都在跑"
assert_equals "${E2E_USER}-singbox_hysteria2" "$(jq -r '.inbounds[0].users[0].name' "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" 2>/dev/null)" \
    "Hysteria2 用的是同一个账号"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "装完再取 sing-box 订阅 200"
probeSub "加了 Hysteria2" "${WORK}/sub-sb.json"
assert_equals "hysteria2 trojan vless vless vless vmess" "${probedTypes}" "订阅里多了 Hysteria2 节点（装协议后订阅跟着重建）"

# ============================================================================
# 装到一半退出：端口自检停了三个服务之后在 path 处输错退出，起步时在跑的都要拉回来
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 1 → 1 重装：端口自检之后输错 path 退出 ===${NC}"
# 不沿用上次配置、沿用域名、不沿用端口（回车 443，于是做端口自检、停掉三个服务）、不沿用 path、输一个过短的 path
s4Out=$(runMenu "1\n1\nn\ny\nn\n\nn\nab\n")
s4Rc=$?
assert_equals "yes" "$([[ ${s4Rc} -ne 0 ]] && echo yes || echo no)" "输错 path 时安装以非零退出（${s4Rc}）"
assert_contains "${s4Out}" "检测到443端口已开放" "退出前确实做过端口自检（三个服务在那里都停过）"
sleep 2
assert_equals "active active active" "$(activeState)" "退出后 Xray、sing-box、nginx 都按旧配置拉回来了"
assert_equals "204" "$(probeOutbound "${WORK}/sub-sb.json" "$(jq -r '.outbounds[] | select(.type == "hysteria2") | .tag' "${WORK}/sub-sb.json")")" \
    "退出后旁挂的 Hysteria2 照常可用"

# ============================================================================
# 换域名重装：A → B，旁挂的 sing-box 要跟着起来，订阅、伪装站、Reality 目标、旁挂的证书都换成 B
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 1 → 1 重装：换成域名 ${DOMAIN_B} ===${NC}"
placeCert "${DOMAIN_B}"
# 不沿用配置、不沿用域名、输 B、不沿用端口（回车 443）、沿用 path、不重下 Xray、沿用账号；
# 12：沿用端口 y、本机域名当目标 y、沿用密钥 y；7：同上；伪装站不重装
s5Out=$(runMenu "1\n1\nn\nn\n${DOMAIN_B}\nn\n\ny\nn\ny\ny\ny\ny\ny\ny\ny\nn\n")
s5Rc=$?
[[ ${s5Rc} -ne 0 ]] && tail -n 30 <<<"${s5Out}"
assert_equals "0" "${s5Rc}" "换域名重装退出码 0"
noNoise "换域名重装" "${s5Out}"
sleep 2
assert_equals "active active active" "$(activeState)" "重装后旁挂的 sing-box 也起来了（端口自检停过它）"
assert_equals "${subKeyA}" "$(subKey)" "订阅地址的 md5 没变（沿用 salt），成员手里的订阅地址照常可用"
assert_contains "$(cat /etc/nginx/conf.d/subscribe.conf 2>/dev/null)" "server_name ${DOMAIN_B};" "subscribe.conf 换成 ${DOMAIN_B}"
assert_contains "$(cat /etc/nginx/conf.d/reality_dest.conf 2>/dev/null)" "server_name ${DOMAIN_B};" "reality_dest.conf 换成 ${DOMAIN_B}"
assert_equals "${DOMAIN_B}" "$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0]' "${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json" 2>/dev/null)" \
    "Reality 的 serverNames 换成 ${DOMAIN_B}"
assert_equals "200" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${DOMAIN_B}/")" "https://${DOMAIN_B}/ 伪装站可用"
assert_equals "${TLS_DIR}/${DOMAIN_B}.crt" "$(jq -r '.inbounds[0].tls.certificate_path' "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" 2>/dev/null)" \
    "旁挂的 Hysteria2 也换成 ${DOMAIN_B} 的证书"
assert_equals "200" "$(fetchSub "${DOMAIN_B}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "用 ${DOMAIN_B} 取 sing-box 订阅 200"
assert_equals "" "$(jq -r --arg a "${DOMAIN_A}" '.outbounds[] | select((.server // "") == $a or (.tls.server_name // "") == $a) | .tag' "${WORK}/sub-sb.json")" \
    "订阅里没有节点还指着旧域名 ${DOMAIN_A}"
probeSub "换域名后" "${WORK}/sub-sb.json"
assert_equals "hysteria2 trojan vless vless vless vmess" "${probedTypes}" "换域名后订阅里的节点都能用"

echo ""
echo -e "${YELLOW}=== 菜单 4 → 2：卸掉 Hysteria2（拼车不计量 sing-box 里的协议，开拼车前要拿掉）===${NC}"
s6Out=$(runMenu "4\n2\n")
assert_equals "0" "$?" "卸 Hysteria2 退出码 0"
sleep 1
assert_equals "active inactive active" "$(activeState)" "没有入站了，旁挂的 sing-box 停掉"

# ============================================================================
# 拼车：页面经订阅口发出去，成员页按自己的键；拼车开着时补装协议，成员自动进新入站；订阅三种格式都重建
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 7 → 6：开拼车、开页面 ===${NC}"
c1Out=$(runMenu "7\n6\n4\n")
assert_equals "0" "$?" "开启拼车退出码 0"
c2Out=$(runMenu "7\n6\n5\n1\n")
assert_equals "0" "$?" "开启页面退出码 0"
linksOut=$(runMenu "7\n6\n5\n2\n")
pageUrls=$(grep -oE 'https://[^ ]+/carpool/[0-9a-f]{32,64}' <<<"${linksOut}" | sort -u)
assert_equals "2" "$(grep -c . <<<"${pageUrls}")" "页面链接两条：车主页与 ${E2E_USER} 的成员页"
while read -r url; do
    [[ -z "${url}" ]] && continue
    assert_equals "200" "$(curl -s -o "${WORK}/page.html" -w '%{http_code}' --max-time 10 "${url}")" "页面 ${url##*/} 可访问"
    assert_contains "$(cat "${WORK}/page.html")" "${E2E_USER}" "页面上有 ${E2E_USER} 的用量"
done <<<"${pageUrls}"
pageBase=$(head -n 1 <<<"${pageUrls}")
pageBase=${pageBase%/*}
assert_equals "404" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${pageBase}/0123456789abcdef0123456789abcdef")" "随便编一个键 404"
assert_equals "404" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${pageBase}/${subKeyA}")" \
    "拿订阅地址的 md5 当页面键 404（成员页不等于订阅）"

echo ""
echo -e "${YELLOW}=== 菜单 2 → 1：拼车开着时先去掉 Trojan、再装回来 ===${NC}"
c3Out=$(runMenu "2\n1\n0,1,3,7,12\ny\n")
assert_equals "0" "$?" "个性化安装去掉 4 退出码 0"
assert_equals "no" "$([[ -f "${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json" ]] && echo yes || echo no)" "Trojan 入站已去掉"
c4Out=$(runMenu "2\n1\n0,1,3,4,7,12\ny\n")
c4Rc=$?
[[ ${c4Rc} -ne 0 ]] && tail -n 20 <<<"${c4Out}"
assert_equals "0" "${c4Rc}" "个性化安装装回 4 退出码 0"
assert_equals "${E2E_USER}-trojan_tcp" "$(jq -r '.inbounds[0].settings.clients[].email' "${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json" 2>/dev/null | head -n 1)" \
    "协议设为 all 的成员自动进了新装的 Trojan 入站"
for ua in 'sing-box 1.14.4' 'clash-verge/v2.4.0' 'v2rayN/7.0'; do
    assert_equals "200" "$(fetchSub "${DOMAIN_B}" "${ua}" "${WORK}/sub-check")" "拼车下重建过的订阅，UA「${ua}」照样 200"
done
assert_contains "$(cat "${WORK}/sub-check" | base64 -d 2>/dev/null)" "trojan://" "重建后的通用订阅里有装回来的 Trojan"
c5Out=$(runMenu "7\n6\n4\ny\ny\n")
assert_equals "0" "$?" "关闭拼车退出码 0"
assert_equals "false" "$(jq -r '.enabled' "${INSTALL_ROOT}/carpool/state.json" 2>/dev/null)" "拼车已关闭"
noNoise "拼车各步" "${c1Out}${c2Out}${linksOut}${c3Out}${c4Out}${c5Out}"

# ============================================================================
# 只留 Reality：nginx 还得在（订阅要它，Reality 的本机伪装站也在它上面）
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 2 → 1：只选 7 ===${NC}"
s8Out=$(runMenu "2\n1\n7\ny\n")
assert_equals "0" "$?" "只装 Reality 退出码 0"
noNoise "只装 Reality" "${s8Out}"
assert_equals "active" "$(systemctl is-active nginx 2>/dev/null)" "nginx 还在跑"
assert_equals "200" "$(fetchSub "${DOMAIN_B}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "订阅照样 200"
probeSub "只留 Reality" "${WORK}/sub-sb.json"
assert_equals "vless" "${probedTypes}" "订阅里只剩 Reality，且能用（本机伪装站在 nginx 上）"
xrayRealityPub=$(jq -r '.inbounds[1].streamSettings.realitySettings.publicKey' "${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json" 2>/dev/null)

# ============================================================================
# 菜单 1 → 2：换成 sing-box 全部安装，沿用 Xray 的 Reality 密钥
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 1 → 2：sing-box 全部安装（沿用账号与 Reality 密钥）===${NC}"
# 只剩 Reality 时没有带证书的协议，读不出上次的域名，要再输一次；卸 Hysteria2 时 sing-box 已整个删掉，不问要不要升级；
# 之后沿用账号，逐个协议回车取默认端口，沿用 path、本机域名当 Reality 目标、沿用密钥
s9Out=$(runMenu "1\n2\nn\n${DOMAIN_B}\ny\n\n\n\n\ny\ny\ny\n\n\n\n\n\n\n\n\n\ny\n\n\n\n")
s9Rc=$?
[[ ${s9Rc} -ne 0 ]] && tail -n 30 <<<"${s9Out}"
assert_equals "0" "${s9Rc}" "sing-box 全部安装退出码 0"
noNoise "sing-box 全部安装" "${s9Out}"
sleep 2
assert_equals "sing-box nginx" "$(for s in xray sing-box nginx; do [[ "$(systemctl is-active "${s}" 2>/dev/null)" == "active" ]] && printf '%s ' "${s}"; done | sed 's/ $//')" \
    "只剩 sing-box 与 nginx 在跑"
assert_equals "publicKey:${xrayRealityPub}" "$(cat "${SINGBOX_FRAGMENT_DIR}/reality_key" 2>/dev/null)" "reality_key 记的是沿用的 Xray 公钥"
assert_equals "200" "$(fetchSub "${DOMAIN_B}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "sing-box 内核下取订阅 200"
assert_equals "${xrayRealityPub}" "$(jq -r '.outbounds[] | select(.tls.reality.enabled == true) | .tls.reality.public_key' "${WORK}/sub-sb.json" | head -n 1)" \
    "订阅里 Reality 节点的 public_key 就是这把公钥"
probeSub "sing-box 全装" "${WORK}/sub-sb.json"
echo "sing-box 订阅里的节点类型：${probedTypes}"
assert_contains "${probedTypes}" "hysteria2" "sing-box 订阅里有 Hysteria2"
assert_contains "${probedTypes}" "tuic" "sing-box 订阅里有 TUIC"

# ============================================================================
# 菜单 20：卸载，再和装前比：文件、软件包、crontab、服务单元
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 20：卸载与残留核对 ===${NC}"
u1Out=$(runMenu "20\ny\n")
assert_equals "0" "$?" "卸载退出码 0"
assert_equals "no no" "$([[ -e "${INSTALL_ROOT}" ]] && echo yes || echo no) $([[ -e /usr/bin/pasly ]] && echo yes || echo no)" "安装根与 pasly 已删"
assert_equals "" "$(pgrep -x xray; pgrep -x sing-box)" "两个内核都已退出"
assert_equals "" "$(crontab -l 2>/dev/null | grep -F "${INSTALL_ROOT}" || true)" "crontab 里不再有指向安装根的任务"
assert_equals "" "$(find /etc/systemd/system -xtype l 2>/dev/null)" "/etc/systemd/system 下没有悬空的软链（单元删了，开机自启的链接也得撤）"
snapFiles >"${WORK}/files-after"
newFiles=$(comm -13 "${WORK}/files-before" "${WORK}/files-after")
assert_equals "" "$(grep -iE 'xray|sing-box|proxy-agent|pasly|subscribe' <<<"${newFiles}" || true)" "卸载后没有带脚本或内核名字的文件留下"
assert_equals "" "$(ls -A /usr/share/nginx/html 2>/dev/null | grep -v '^index.html$\|^50x.html$' || true)" "伪装站已删"
# 下面只列出来供人工核对，不判对错：装包时维护脚本生成的文件（rc.d、alternatives、包自己的自启链接）没法从包清单里认出来
echo "卸载后新多出来的文件（不含包维护脚本生成的 rc.d / alternatives / 自启链接，与 /usr 下的包文件）："
grep -vE '^/(etc/(rc[0-6S]\.d|alternatives|systemd/(system|user)/[^/]+\.wants)|usr/(bin|sbin|lib|share|libexec))(/|$)' <<<"${newFiles}" |
    grep -vE '^/root/\.acme\.sh/' | sed 's/^/    /'
echo "防火墙里留下的本脚本规则："
{ iptables-save 2>/dev/null; cat /etc/iptables/rules.v4 2>/dev/null; } | grep -F 'Proxy-agent' | sort -u | sed 's/^/    /'
echo "装机时新装的软件包：$(comm -13 "${WORK}/pkgs-before" <(dpkg-query -W -f '${Package}\n' | sort) | tr '\n' ' ')"

e2eSummary "带域名的真装机端到端测试" "${E2E_LOG}"
