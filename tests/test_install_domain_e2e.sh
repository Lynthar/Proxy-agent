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
# doctorClean LABEL → pasly doctor 退出码 0、零 FAIL，打印去色后的输出
doctorClean() {
    local out rc
    out=$(V2RAY_LANG=en bash /usr/bin/pasly doctor 2>&1)
    rc=$?
    out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"${out}")
    [[ ${rc} -ne 0 || "${out}" == *"[FAIL]"* ]] && grep -F '[FAIL]' <<<"${out}" >&2
    assert_equals "0" "${rc}" "$1：doctor 退出码 0" >&2
    printf '%s\n' "${out}"
}
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
# 不是 204 就把 curl 与客户端的报错打出来，不重试：重试会盖住真问题
probeOutbound() {
    local conf="${WORK}/client.json" pid code
    jq --arg t "$2" '{log: {level: "warn"}, dns: {servers: [{type: "local", tag: "local"}]},
        inbounds: [{type: "socks", listen: "127.0.0.1", listen_port: 10808}],
        outbounds: [.outbounds[] | select(.tag == $t or .tag == ("st-" + $t))],
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

# probeXhttpLink LINK → 按 XHTTP 分享链接（Reality 或 TLS）起 Xray 客户端（sing-box 没有 XHTTP），经它访问外网，打印 HTTP 状态码；
# 不是 204 时同 probeOutbound 打出报错
probeXhttpLink() {
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
        --arg host "${p[host]:-}" --arg security "${p[security]:-}" --arg alpn "${p[alpn]:-}" '{log: {loglevel: "warning"},
        inbounds: [{listen: "127.0.0.1", port: 10809, protocol: "socks"}],
        outbounds: [{protocol: "vless",
            settings: {vnext: [{address: $addr, port: ($port | tonumber), users: [{id: $id, encryption: "none"}]}]},
            streamSettings: ({network: "xhttp", security: $security, xhttpSettings: {path: $path, host: $host}}
                + if $security == "reality"
                  then {realitySettings: {serverName: $sni, fingerprint: $fp, publicKey: $pbk, shortId: $sid}}
                  else {tlsSettings: {serverName: $sni, fingerprint: $fp, alpn: [$alpn]}} end)}]}' >"${WORK}/xhttp.json"
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
for f in 02_VLESS_TCP_inbounds 03_VLESS_WS_inbounds 04_trojan_TCP_inbounds 05_VMess_WS_inbounds 07_VLESS_vision_reality_inbounds 12_VLESS_XHTTP_inbounds 15_VLESS_XHTTP_TLS_inbounds; do
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
xhttpLink=$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'security=reality.*type=xhttp')
assert_not_empty "${xhttpLink}" "通用订阅里有 Reality XHTTP 的链接"
assert_equals "204" "$(probeXhttpLink "${xhttpLink}")" "按 XHTTP 链接配的 Xray 客户端经服务端访问外网"
xhttpTlsLink=$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'security=tls&type=xhttp')
assert_not_empty "${xhttpTlsLink}" "通用订阅里有 XHTTP+TLS 的链接"
assert_equals "204" "$(probeXhttpLink "${xhttpTlsLink}")" "XHTTP+TLS：经 443 回落、nginx 转发，Xray 客户端访问外网"
assert_equals "127.0.0.1" "$(jq -r '.inbounds[0].listen' "${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json")" "XHTTP+TLS 的入站只在回环上听"
xhttpTlsPath=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json")
assert_equals "404" "$(curl -s -o /dev/null -w '%{http_code}' --http1.1 --max-time 10 "https://${DOMAIN_A}${xhttpTlsPath}/")" "XHTTP+TLS：路径对、但走 http/1.1 只看到伪装站"
assert_equals "404" "$(curl -s -o /dev/null -w '%{http_code}' --http2 --max-time 10 "https://${DOMAIN_A}/not${xhttpTlsPath#/}/")" "XHTTP+TLS：路径不对的 h2 请求只看到伪装站"

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
# 菜单 5：换 Reality 目标，7 与 12 一起换、端口密钥 path 沿用；再用菜单 5 换回本机域名（换回前删掉 reality_dest.conf，当它没用过自偷）
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 5：Reality 目标换成 dl.google.com，7 与 12 一起换 ===${NC}"
realityFiles=("${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json" "${XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json")
# realityTargets → 7 与 12 各一个「serverName@target」，空格分隔
realityTargets() {
    jq -r '[.inbounds[] | .streamSettings.realitySettings // empty | "\(.serverNames[0])@\(.target)"][0]' "${realityFiles[@]}" 2>/dev/null | paste -sd' ' -
}
realityPortsKeys() {
    jq -r '.inbounds[0].port, ([.inbounds[] | .streamSettings | .realitySettings.privateKey, .xhttpSettings.path | values] | join(" "))' "${realityFiles[@]}" 2>/dev/null | paste -sd' ' -
}
realityBefore=$(realityTargets)
realityPortsKeysBefore=$(realityPortsKeys)
# 账号沿用 · 12 端口沿用 · 不用本机域名 · 输目标 · 12 密钥沿用 · 7 端口沿用 · 7 沿用刚定的目标 · 7 密钥沿用
r1Out=$(runMenu "5\ny\ny\nn\ndl.google.com:443\ny\ny\ny\ny\n")
r1Rc=$?
[[ ${r1Rc} -ne 0 ]] && tail -n 20 <<<"${r1Out}"
assert_equals "0" "${r1Rc}" "菜单 5 换目标退出码 0"
noNoise "菜单 5 换目标" "${r1Out}"
assert_equals "dl.google.com@dl.google.com:443 dl.google.com@dl.google.com:443" "$(realityTargets)" "菜单 5：7 与 12 的目标都换成 dl.google.com"
assert_equals "${realityPortsKeysBefore}" "$(realityPortsKeys)" "菜单 5：7 与 12 的端口、密钥与 12 的 path 都沿用，手里的链接不用换"
assert_equals "active active active" "$(activeState)" "菜单 5 之后 Xray、sing-box、nginx 都在跑"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "菜单 5 之后取 sing-box 订阅 200"
probeSub "换了 Reality 目标" "${WORK}/sub-sb.json"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'v2rayN/7.0' "${WORK}/sub-default.txt")" "菜单 5 之后取通用订阅 200"
xhttpLink=$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'security=reality.*type=xhttp')
assert_contains "${xhttpLink}" "sni=dl.google.com" "菜单 5：通用订阅里 XHTTP 的链接带上新目标"
assert_equals "204" "$(probeXhttpLink "${xhttpLink}")" "菜单 5：按新目标的 XHTTP 链接经服务端访问外网"
rm -f /etc/nginx/conf.d/reality_dest.conf && nginx -s reload
# 账号沿用 · 12 端口沿用 · 不沿用 dl.google.com · 用本机域名 · 12 密钥沿用 · 7 端口沿用 · 用本机域名 · 7 密钥沿用
r2Out=$(runMenu "5\ny\ny\nn\ny\ny\ny\ny\ny\n")
r2Rc=$?
[[ ${r2Rc} -ne 0 ]] && tail -n 20 <<<"${r2Out}"
assert_equals "0" "${r2Rc}" "菜单 5 换回本机域名退出码 0"
assert_equals "${realityBefore}" "$(realityTargets)" "菜单 5：7 与 12 都换回本机域名（目标在回环上）"
assert_equals "${realityPortsKeysBefore}" "$(realityPortsKeys)" "菜单 5 换回之后端口、密钥与 path 仍是原来的"
assert_contains "$(cat /etc/nginx/conf.d/reality_dest.conf 2>/dev/null)" "server_name ${DOMAIN_A};" "菜单 5：选了本机域名时重写 reality_dest.conf"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "换回之后取 sing-box 订阅 200"
probeSub "换回本机域名" "${WORK}/sub-sb.json"
assert_equals "200" "$(fetchSub "${DOMAIN_A}" 'v2rayN/7.0' "${WORK}/sub-default.txt")" "换回之后取通用订阅 200"
assert_equals "204" "$(probeXhttpLink "$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'security=reality.*type=xhttp')")" \
    "换回本机域名后 XHTTP 照样能用（nginx 重读了新写的 reality_dest.conf）"

# ============================================================================
# 装到一半退出：端口自检已经停了三个服务，却连不回本机（云防火墙没放行时就是这样），起步时在跑的都要拉回来
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 1 → 1 重装：端口自检不过退出 ===${NC}"
# raw 表：allowPort 插在 INPUT 最前的放行盖不过它
iptables -t raw -I PREROUTING 1 -p tcp --dport 443 -j DROP
# 不沿用上次配置、沿用域名、不沿用端口（回车 443，于是做端口自检）
s4Out=$(runMenu "1\n1\nn\ny\nn\n\n")
s4Rc=$?
iptables -t raw -D PREROUTING -p tcp --dport 443 -j DROP
assert_equals "yes" "$([[ ${s4Rc} -ne 0 ]] && echo yes || echo no)" "端口自检不过时安装以非零退出（${s4Rc}）"
assert_contains "${s4Out}" "未检测到443端口开放" "退出的原因确实是端口自检（三个服务在那里都停过）"
sleep 2
assert_equals "active active active" "$(activeState)" "退出后 Xray、sing-box、nginx 都按旧配置拉回来了"
assert_equals "204" "$(probeOutbound "${WORK}/sub-sb.json" "$(jq -r '.outbounds[] | select(.type == "hysteria2") | .tag' "${WORK}/sub-sb.json")")" \
    "退出后旁挂的 Hysteria2 照常可用"

echo ""
echo -e "${YELLOW}=== 菜单 1 → 1 重装：新域名的证书与私钥对不上，退出 ===${NC}"
DOMAIN_BAD="bad.${publicIP//./-}.sslip.io"
issueCert "${DOMAIN_BAD}"
placeCert "${DOMAIN_BAD}"
cat "${caDir}/${DOMAIN_A}.key" >"${TLS_DIR}/${DOMAIN_BAD}.key"
# 不沿用上次配置、不沿用域名、输新域名、不沿用端口（回车 443）
s4bOut=$(runMenu "1\n1\nn\nn\n${DOMAIN_BAD}\nn\n\n")
s4bRc=$?
assert_equals "yes" "$([[ ${s4bRc} -ne 0 ]] && echo yes || echo no)" "证书对不上时安装以非零退出（${s4bRc}）"
assert_contains "${s4bOut}" "证书验证失败" "退出的原因确实是证书与私钥不匹配"
sleep 2
assert_equals "active active active" "$(activeState)" "退出后 Xray、sing-box、nginx 都按旧配置拉回来了"

# ============================================================================
# 换域名重装：A → B，旁挂的 sing-box 要跟着起来，订阅、伪装站、Reality 目标、旁挂的证书都换成 B
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 1 → 1 重装：换成域名 ${DOMAIN_B} ===${NC}"
placeCert "${DOMAIN_B}"
# 不沿用配置、不沿用域名、输 B、不沿用端口（回车 443）、不沿用 path 且输个过短的（重问）、这回沿用 path、不重下 Xray、沿用账号；
# 12：沿用端口 y、本机域名当目标 y、沿用密钥 y；7：同上；伪装站不重装
s5Out=$(runMenu "1\n1\nn\nn\n${DOMAIN_B}\nn\n\nn\nab\ny\nn\ny\ny\ny\ny\ny\ny\ny\nn\n")
s5Rc=$?
[[ ${s5Rc} -ne 0 ]] && tail -n 30 <<<"${s5Out}"
assert_equals "0" "${s5Rc}" "换域名重装退出码 0"
noNoise "换域名重装" "${s5Out}"
assert_contains "${s5Out}" "路径格式非法" "path 输错：报错后重问，安装接着往下走"
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
# tls/ 里还留着旧域名的证书和上面那张配不上私钥的坏证书，doctor 查的是在用的 B
doctorOut=$(doctorClean "换域名后")
assert_contains "${doctorOut}" "[PASS] Certificate covers domain" "doctor：证书覆盖新域名"
assert_contains "${doctorOut}" "${DOMAIN_B}.crt" "doctor：查的是在用的 ${DOMAIN_B} 这张"
assert_equals "" "$(grep -E "\[[A-Z]+\] Certificate.*${DOMAIN_BAD}" <<<"${doctorOut}" || true)" "doctor：tls/ 里那张坏证书不在查的范围内"
assert_contains "${doctorOut}" "[WARN] Certificate chain" "doctor：测试 CA 签的单张证书提示证书链，不算 FAIL"
assert_contains "${doctorOut}" "[PASS] Account UUIDs" "doctor：全协议的账号 UUID 没有弱值（Xray + 旁挂 Hysteria2）"

# ============================================================================
# 菜单 3 → 6：脚本自己发的 vless / vmess 链接当外部节点。走真菜单，由旁挂的 sing-box 真握手，所以要在卸 Hysteria2 之前：入站删光后 sing-box 连二进制一起删
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 3 → 6：vless / vmess 链接当外部节点 ===${NC}"
fetchSub "${DOMAIN_B}" 'v2rayN/7.0' "${WORK}/sub-default.txt" >/dev/null
extLinks=$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -E '^(vless|vmess)://' | grep -v 'type=xhttp')
assert_equals "4" "$(grep -c . <<<"${extLinks}")" "通用订阅里有 VLESS TLS / WS / Reality、VMess 四条能当外部节点的链接"
while IFS= read -r extLink; do
    extOut=$(runMenu "3\n6\n1\n${extLink}\ny\n4\n1\n3\n1\ny\n0\n")
    assert_contains "${extOut}" "Node added" "外部节点：${extLink%%\?*} 添加成功"
    assert_contains "${extOut}" "through this node" "外部节点：${extLink%%\?*} 经本机 sing-box 真握手、访问外网"
    [[ "${extOut}" == *"through this node"* ]] || tail -n 15 <<<"${extOut}"
    assert_equals "0" "$(jq '.nodes | length' "${INSTALL_ROOT}/sing-box/conf/external_node_info.json" 2>/dev/null)" "外部节点：测完删掉，没留下"
done <<<"${extLinks}"
extOut=$(runMenu "3\n6\n1\n$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'security=reality.*type=xhttp')\n0\n")
assert_contains "${extOut}" "type = xhttp" "外部节点：XHTTP 链接当场拒绝并说明原因（sing-box 没有 XHTTP）"
assert_equals "0" "$(jq '.nodes | length' "${INSTALL_ROOT}/sing-box/conf/external_node_info.json" 2>/dev/null)" "外部节点：被拒的链接没有写进节点文件"
# 留一条走到最后：卸 Hysteria2、重装 sing-box 都要带着它，完整卸载才清掉。443 上的 VLESS TLS 换内核后端口账号不变，所以还能真握手
keptLink=$(grep -E 'security=tls' <<<"${extLinks}" | grep -E '^vless://[^?]+:443\?' | grep -v 'type=ws' | head -n 1)
runMenu "3\n6\n1\n${keptLink}\ny\n0\n" >/dev/null
assert_equals "1" "$(jq '.nodes | length' "${INSTALL_ROOT}/sing-box/conf/external_node_info.json" 2>/dev/null)" "外部节点：留一条，看卸 sing-box 时带不带走"

echo ""
echo -e "${YELLOW}=== 菜单 4 → 3：端口跳跃，再 4 → 2 卸掉 Hysteria2（拼车不计量 sing-box 里的协议，开拼车前要拿掉）===${NC}"
runMenu "4\n3\n1\n30000-30010\n" >/dev/null
assert_equals "1" "$(iptables -t nat -S PREROUTING | grep -c 'Proxy-agent_hysteria2_portHopping')" "加了端口跳跃：IPv4 有一条 NAT 规则"
assert_equals "" "$(iptables -S INPUT | grep -F '30000:30010' || true)" "加端口跳跃不放行区间（INPUT 看到的是 NAT 之后的目标端口）"
s6Out=$(runMenu "4\n2\n")
assert_equals "0" "$?" "卸 Hysteria2 退出码 0"
assert_equals "0" "$(iptables -t nat -S PREROUTING | grep -c 'Proxy-agent_hysteria2_portHopping')" "卸 Hysteria2 带走它的跳跃规则"
sleep 1
assert_equals "active inactive active" "$(activeState)" "没有入站了，旁挂的 sing-box 停掉"
assert_equals "no no" "$([[ -e "${SINGBOX_BIN}" ]] && echo yes || echo no) $([[ -e "${SINGBOX_FRAGMENT_DIR}" ]] && echo yes || echo no)" "sing-box 的二进制和片段都删了"
assert_contains "${s6Out}" "Kept 1 external node" "卸的时候说明留下了外部节点（含凭据）"
assert_equals "1 600" "$(jq '.nodes | length' "${INSTALL_ROOT}/sing-box/conf/external_node_info.json" 2>/dev/null) $(stat -c %a "${INSTALL_ROOT}/sing-box/conf/external_node_info.json" 2>/dev/null)" \
    "外部节点清单留着，权限还是 600"
extOut=$(runMenu "3\n6\n4\n1\n0\n")
assert_contains "${extOut}" "sing-box is not installed" "sing-box 没了，菜单照常列出留下的节点、只测端口并说明原因"

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

# 用量头：真 nginx 从 map 里取，两种地址都带；客户端拿 upload + download 比 total
subHeaders() {
    curl -s -D- -o /dev/null --max-time 10 -A "$2" "https://${DOMAIN_B}:$(subPort)$1" | tr -d '\r' | sed -n 's/^[Ss]ubscription-[Uu]serinfo: //p'
}
assert_contains "$(subHeaders "/s/$(subKey)" 'curl/8')" "upload=0; download=" "通用地址带 subscription-userinfo"
assert_contains "$(subHeaders "/s/$(subKey)" 'sing-box 1.14.4')" "total=" "按 UA 分发到 sing-box 也带"
assert_contains "$(subHeaders "/s/default/$(subKey)" 'curl/8')" "expire=" "定格式的地址也带"
assert_equals "" "$(subHeaders "/s/0123456789abcdef0123456789abcdef" 'curl/8')" "编造的键不带"
assert_equals "600" "$(stat -c %a "${INSTALL_ROOT}/subscribe_userinfo.map" 2>/dev/null)" "map 只给 root 读（里面有订阅地址的 md5）"

echo ""
echo -e "${YELLOW}=== 菜单 2 → 1：拼车开着时先去掉 Trojan、再装回来 ===${NC}"
c3Out=$(runMenu "2\n1\n0,1,3,7,12\ny\n")
assert_equals "0" "$?" "个性化安装去掉 4 退出码 0"
assert_equals "no" "$([[ -f "${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json" ]] && echo yes || echo no)" "Trojan 入站已去掉"
c4Out=$(runMenu "2\n1\n0,1,3,4,7,12,15\ny\n")
c4Rc=$?
[[ ${c4Rc} -ne 0 ]] && tail -n 20 <<<"${c4Out}"
assert_equals "0" "${c4Rc}" "个性化安装装回 4 退出码 0"
assert_equals "${E2E_USER}-trojan_tcp" "$(jq -r '.inbounds[0].settings.clients[].email' "${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json" 2>/dev/null | head -n 1)" \
    "协议设为 all 的成员自动进了新装的 Trojan 入站"
for ua in 'sing-box 1.14.4' 'clash-verge/v2.4.0' 'v2rayN/7.0'; do
    assert_equals "200" "$(fetchSub "${DOMAIN_B}" "${ua}" "${WORK}/sub-check")" "拼车下重建过的订阅，UA「${ua}」照样 200"
done
assert_contains "$(cat "${WORK}/sub-check" | base64 -d 2>/dev/null)" "trojan://" "重建后的通用订阅里有装回来的 Trojan"
assert_equals "${E2E_USER}-VLESS_XHTTP_TLS" "$(jq -r '.inbounds[0].settings.clients[].email' "${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json" 2>/dev/null | head -n 1)" \
    "协议设为 all 的成员也进了 XHTTP+TLS 的入站"
# carpoolUsed → 成员累计用量；只有下面这次探测的流量，涨了才说明 15 真在计量
carpoolUsed() {
    bash "${INSTALL_ROOT}/install.sh" CarpoolCollect >/dev/null 2>&1
    jq -r --arg u "${E2E_USER}" '.members[$u] | .upBytes + .downBytes' "${INSTALL_ROOT}/carpool/state.json" 2>/dev/null
}
usedBefore=$(carpoolUsed)
assert_equals "204" "$(probeXhttpLink "$(base64 -d "${WORK}/sub-check" 2>/dev/null | grep -m1 'security=tls&type=xhttp')")" "拼车开着时 XHTTP+TLS 照样能用"
usedAfter=$(carpoolUsed)
assert_equals "yes" "$([[ "${usedAfter:-0}" -gt "${usedBefore:-0}" ]] && echo yes || echo no)" "XHTTP+TLS 的流量记到成员头上（${usedBefore} → ${usedAfter}）"
c5Out=$(runMenu "7\n6\n4\ny\ny\n")
assert_equals "0" "$?" "关闭拼车退出码 0"
assert_equals "false" "$(jq -r '.enabled' "${INSTALL_ROOT}/carpool/state.json" 2>/dev/null)" "拼车已关闭"
assert_equals "" "$(subHeaders "/s/$(subKey)" 'curl/8')" "关了拼车，订阅响应不再带用量头"
noNoise "拼车各步" "${c1Out}${c2Out}${linksOut}${c3Out}${c4Out}${c5Out}"

# ============================================================================
# 只留 Reality：nginx 还得在（订阅要它，Reality 的本机伪装站也在它上面）
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 2 → 1：单选 15，自动带上 0，路径从它自己的入站读回来 ===${NC}"
x1Out=$(runMenu "2\n1\n15\ny\n")
x1Rc=$?
[[ ${x1Rc} -ne 0 ]] && tail -n 20 <<<"${x1Out}"
assert_equals "0" "${x1Rc}" "单选 15 退出码 0"
noNoise "单选 15" "${x1Out}"
assert_equals "yes no" "$([[ -f "${XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json" ]] && echo yes || echo no) $([[ -f "${XRAY_CONF_DIR}/03_VLESS_WS_inbounds.json" ]] && echo yes || echo no)" "带上了 0，没有 1"
assert_equals "200" "$(fetchSub "${DOMAIN_B}" 'v2rayN/7.0' "${WORK}/sub-default.txt")" "订阅照样 200"
xhttpTlsLink=$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -m1 'security=tls&type=xhttp')
assert_contains "${xhttpTlsLink}" "path=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json")#" "分享链接的路径就是入站的路径"
assert_equals "204" "$(probeXhttpLink "${xhttpTlsLink}")" "只有 0 + 15 时 XHTTP+TLS 照样能用"
# 单选 15 把 Reality 删了，装回 7 要再答：端口回车、本机域名当目标 y、私钥回车生成
x2Out=$(runMenu "2\n1\n0,7\ny\n\ny\n\n")
assert_equals "0" "$?" "去掉 15 退出码 0"
noNoise "去掉 15" "${x2Out}"
assert_equals "no" "$([[ -f "${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json" ]] && echo yes || echo no)" "15 的入站已去掉"
assert_equals "0" "$(grep -c grpc_pass /etc/nginx/conf.d/alone.conf 2>/dev/null)" "15 的 location 也去掉了"
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
# 只剩 Reality 时没有带证书的协议，读不出上次的域名，要再输一次；卸 Hysteria2 时 sing-box 只留了外部节点清单，不问要不要升级；
# 之后沿用账号，逐个协议回车取默认端口，沿用 path、本机域名当 Reality 目标、沿用密钥
s9Out=$(runMenu "1\n2\nn\n${DOMAIN_B}\ny\n\n\n\n\ny\ny\ny\n\n\n\n\n\n\n\n\n\ny\n\n\n\n\n\n")
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
doctorOut=$(doctorClean "sing-box 全部安装")
assert_contains "${doctorOut}" "[PASS] Certificate covers domain" "doctor：sing-box 内核下也读得到在用证书"
assert_contains "${doctorOut}" "[PASS] Account UUIDs" "doctor：sing-box 全协议的账号 UUID 没有弱值"
extOut=$(runMenu "3\n6\n4\n1\n0\n")
assert_contains "${extOut}" "through this node" "重装 sing-box 后，留下的外部节点经它真握手、访问外网"
[[ "${extOut}" == *"through this node"* ]] || tail -n 15 <<<"${extOut}"
stFile="${SINGBOX_FRAGMENT_DIR}/16_shadowtls_inbounds.json"
stTag=$(jq -r '.inbounds[0].users[0].name' "${stFile}" 2>/dev/null)
assert_equals "204" "$(probeOutbound "${WORK}/sub-sb.json" "${stTag}")" "ShadowTLS：订阅里的节点经 detour 真握手、访问外网"
assert_equals "" "$(jq -r '.outbounds[] | select(has("outbounds")) | .outbounds[] | select(startswith("st-"))' "${WORK}/sub-sb.json")" "ShadowTLS：只给 detour 用的外层出站不进选择器"
# Clash 配置经 proxy-providers 引节点，节点本身在 clashMeta 这个地址
assert_contains "$(curl -sS --max-time 15 "https://${DOMAIN_B}:$(subPort)/s/clashMeta/$(subKey)" 2>/dev/null)" "plugin: shadow-tls" "ShadowTLS：Clash 的节点文件里有它"
assert_equals "200" "$(fetchSub "${DOMAIN_B}" 'v2rayN/7.0' "${WORK}/sub-default.txt")" "其他 UA 取订阅 200"
assert_equals "0" "$(base64 -d "${WORK}/sub-default.txt" 2>/dev/null | grep -c 'shadow-tls')" "ShadowTLS：通用订阅里没有它（解析器不认就退化成裸 SS2022）"
stTarget=$(jq -r '.inbounds[0].handshake.server' "${stFile}" 2>/dev/null)
stPort=$(jq -r '.inbounds[0].listen_port' "${stFile}" 2>/dev/null)
assert_equals "0" "$(curl -s -o /dev/null -w '%{ssl_verify_result}' --max-time 15 --resolve "${stTarget}:${stPort}:127.0.0.1" "https://${stTarget}:${stPort}/")" \
    "ShadowTLS：没有密码直接探这个端口，看到的是 ${stTarget} 的真证书"
echo ""
echo -e "${YELLOW}=== 菜单 2 → 2：单选 16，不要证书 ===${NC}"
s10Out=$(runMenu "2\n2\n16\ny\n")
s10Rc=$?
[[ ${s10Rc} -ne 0 ]] && tail -n 20 <<<"${s10Out}"
assert_equals "0" "${s10Rc}" "单选 16 退出码 0"
noNoise "单选 16" "${s10Out}"
assert_equals "${E2E_UUID}" "$(jq -r '.inbounds[0].users[0].password' "${stFile}" 2>/dev/null)" "单选 16：沿用账号，外层密码就是 UUID"
assert_equals "${stPort} ${stTarget}" "$(jq -r '"\(.inbounds[0].listen_port) \(.inbounds[0].handshake.server)"' "${stFile}" 2>/dev/null)" "单选 16：端口与握手目标沿用，已发的节点不失效"
assert_equals "no" "$([[ -f "${SINGBOX_FRAGMENT_DIR}/14_ss2022_inbounds.json" ]] && echo yes || echo no)" "单选 16：其余协议已去掉"
sleep 2
assert_equals "200" "$(fetchSub "${DOMAIN_B}" 'sing-box 1.14.4' "${WORK}/sub-sb.json")" "只剩 16 时取订阅 200"
assert_equals "204" "$(probeOutbound "${WORK}/sub-sb.json" "${stTag}")" "只剩 16 时节点照样能用"
assert_equals "" "$(cd "${SINGBOX_FRAGMENT_DIR}" 2>/dev/null && ls | grep '\.bak' || true)" "几轮重装和合并之后，sing-box 片段目录里没有堆 .bak 文件"

# ============================================================================
# 菜单 20：卸载，再和装前比：文件、软件包、crontab、服务单元
# ============================================================================

echo ""
echo -e "${YELLOW}=== 菜单 20：卸载与残留核对 ===${NC}"
u1Out=$(runMenu "20\ny\n")
assert_equals "0" "$?" "卸载退出码 0"
assert_equals "no no" "$([[ -e "${INSTALL_ROOT}" ]] && echo yes || echo no) $([[ -e /usr/bin/pasly ]] && echo yes || echo no)" "安装根与 pasly 已删（留下的外部节点也在里面）"
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
assert_equals "" "$({ iptables-save 2>/dev/null; cat /etc/iptables/rules.v4 2>/dev/null; } | grep -F 'Proxy-agent' || true)" "带本脚本标记的防火墙规则都收回了，存盘的那份也是"
newPkgs=$(comm -13 "${WORK}/pkgs-before" <(dpkg-query -W -f '${Package}\n' | sort) | tr '\n' ' ')
echo "装机时新装的软件包：${newPkgs}"
assert_equals "" "$(tr ' ' '\n' <<<"${newPkgs}" | grep -E '^(exim4|bsd-mailx|inetutils-ping)' || true)" "装机没带进 exim4、bsd-mailx（cron 的推荐包）与 inetutils-ping"
assert_contains "${u1Out}" "The nginx package" "卸载结尾说明 nginx 软件包还留着"

e2eSummary "带域名的真装机端到端测试" "${E2E_LOG}"
