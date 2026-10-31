#!/usr/bin/env bash
# ============================================================================
# test_modules.sh - lib/ 模块单元测试。跑法: bash tests/test_modules.sh
# ============================================================================

# 注意: 不使用 set -e，以便所有测试都能运行

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试辅助函数
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

assert_empty() {
    local value="$1"
    local message="$2"

    if [[ -z "${value}" ]]; then
        echo -e "${GREEN}✓${NC} ${message}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} ${message} (expected empty, got: ${value})"
        ((TESTS_FAILED++))
    fi
}

assert_true() {
    local condition="$1"
    local message="$2"

    if eval "${condition}"; then
        echo -e "${GREEN}✓${NC} ${message}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} ${message}"
        ((TESTS_FAILED++))
    fi
}

# 切换到项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

echo "=============================================="
echo "Proxy-agent 模块单元测试"
echo "=============================================="
echo ""

# ============================================================================
# 测试模块加载
# ============================================================================

echo -e "${YELLOW}=== 测试模块加载 ===${NC}"

# 测试 constants.sh 加载
source lib/constants.sh
assert_not_empty "${_CONSTANTS_LOADED}" "constants.sh 模块加载成功"

# 测试 utils.sh 加载
source lib/utils.sh
assert_not_empty "${_UTILS_LOADED}" "utils.sh 模块加载成功"

# 测试 json-utils.sh 加载
source lib/json-utils.sh
assert_not_empty "${_JSON_UTILS_LOADED}" "json-utils.sh 模块加载成功"

# 测试 protocol-registry.sh 加载
source lib/protocol-registry.sh
assert_not_empty "${_PROTOCOL_REGISTRY_LOADED}" "protocol-registry.sh 模块加载成功"

# 测试 system-detect.sh 加载
source lib/system-detect.sh
assert_not_empty "${_SYSTEM_DETECT_LOADED}" "system-detect.sh 模块加载成功"

echo ""

# ============================================================================
# 测试 utils.sh 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 utils.sh 函数 ===${NC}"

# 测试 randomNum
num=$(randomNum 100 200)
assert_true "[[ ${num} -ge 100 && ${num} -le 200 ]]" "randomNum(100, 200) 生成有效数字: ${num}"

# 测试 randomPort
port=$(randomPort)
assert_true "[[ ${port} -ge 10000 && ${port} -le 30000 ]]" "randomPort() 生成有效端口: ${port}"

# 测试 trim
trimmed=$(trim "  hello  ")
assert_equals "hello" "${trimmed}" "trim() 去除空格"

# 测试 versionGreaterThan
assert_true "versionGreaterThan '1.2.3' '1.2.0'" "versionGreaterThan('1.2.3', '1.2.0')"
assert_true "! versionGreaterThan '1.2.0' '1.2.3'" "!versionGreaterThan('1.2.0', '1.2.3')"

# 测试 isYesInput - 接受 y/Y/yes/Yes 任意大小写组合
assert_true "isYesInput 'y'" "isYesInput('y') 返回 true"
assert_true "isYesInput 'Y'" "isYesInput('Y') 返回 true"
assert_true "isYesInput 'yes'" "isYesInput('yes') 返回 true"
assert_true "isYesInput 'YES'" "isYesInput('YES') 返回 true"
assert_true "isYesInput 'Yes'" "isYesInput('Yes') 返回 true"
# 拒绝模糊输入：yy 多为按键弹起延迟，不应解读为肯定
assert_true "! isYesInput 'yy'" "isYesInput('yy') 返回 false"
assert_true "! isYesInput 'yep'" "isYesInput('yep') 返回 false"
assert_true "! isYesInput 'n'" "isYesInput('n') 返回 false"
assert_true "! isYesInput ''" "isYesInput('') 返回 false"

# 测试 isDryRun / planAction（DRY_RUN 关闭时）
unset DRY_RUN
assert_true "! isDryRun" "isDryRun() 在 DRY_RUN 未设置时返回 false"
assert_true "! planAction 'should not print'" "planAction() 在非 dry-run 模式返回 1（调用方不短路）"

# 测试 DRY_RUN=1 时
DRY_RUN=1
assert_true "isDryRun" "isDryRun() 在 DRY_RUN=1 时返回 true"
assert_true "planAction 'test plan' >/dev/null" "planAction() 在 dry-run 模式返回 0（调用方应短路）"
# planAction 应输出 [plan] 前缀（黄色 ANSI 包裹），strip 后包含原文
plan_output=$(stripAnsi "$(planAction 'install reality')")
assert_equals "[plan] install reality" "${plan_output}" "planAction() 输出包含 [plan] 前缀和原 message"
unset DRY_RUN

# 测试 echoContent：红色是错误通道，返回 1，让「打了错误」等于「失败」；其余颜色返回 0
assert_equals 1 "$(echoContent red 'boom' >/dev/null; echo $?)" "echoContent red 返回 1"
assert_equals "boom" "$(stripAnsi "$(echoContent red 'boom')")" "echoContent red 仍把文本打到 stdout"
for _color in green yellow blue purple skyBlue white plain; do
    assert_equals 0 "$(echoContent "${_color}" 'ok' >/dev/null; echo $?)" "echoContent ${_color} 返回 0"
done

echo ""

# ============================================================================
# 测试 protocol-registry.sh 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 protocol-registry.sh 函数 ===${NC}"

# 测试 getProtocolConfigFileName
filename=$(getProtocolConfigFileName 0)
assert_equals "02_VLESS_TCP_inbounds.json" "${filename}" "getProtocolConfigFileName(0) = VLESS_TCP"

filename=$(getProtocolConfigFileName 6)
assert_equals "06_hysteria2_inbounds.json" "${filename}" "getProtocolConfigFileName(6) = hysteria2"

filename=$(getProtocolConfigFileName 7)
assert_equals "07_VLESS_vision_reality_inbounds.json" "${filename}" "getProtocolConfigFileName(7) = Reality"

# 测试 getProtocolDisplayName
name=$(getProtocolDisplayName 0)
assert_equals "VLESS+TCP[TLS_Vision]" "${name}" "getProtocolDisplayName(0)"

name=$(getProtocolDisplayName 6)
assert_equals "Hysteria2" "${name}" "getProtocolDisplayName(6)"

name=$(getProtocolDisplayName 7)
assert_equals "VLESS+Reality+Vision" "${name}" "getProtocolDisplayName(7)"

# 测试 protocolRequiresTLS
assert_true "protocolRequiresTLS 0" "VLESS_TCP_VISION requires TLS"
assert_true "protocolRequiresTLS 1" "VLESS_WS requires TLS"
assert_true "! protocolRequiresTLS 7" "VLESS_REALITY_VISION does not require TLS (uses Reality)"
assert_true "protocolRequiresTLS 6" "Hysteria2 requires TLS (ACME cert under tls/)"
assert_true "protocolRequiresTLS 9" "TUIC requires TLS (ACME cert under tls/)"
assert_true "! protocolRequiresTLS 14" "SS2022 does not require TLS"

# 测试 anyProtocolRequiresTLS（三处装机白名单的派生源）
assert_true 'anyProtocolRequiresTLS ",0,7,"' "anyProtocolRequiresTLS: VLESS_TCP + Reality needs a cert"
assert_true 'anyProtocolRequiresTLS ",7,6,"' "anyProtocolRequiresTLS: Reality + Hysteria2 needs a cert"
assert_true '! anyProtocolRequiresTLS ",7,12,14,"' "anyProtocolRequiresTLS: Reality/XHTTP/SS2022 only needs none"
assert_true '! anyProtocolRequiresTLS ""' "anyProtocolRequiresTLS: empty selection needs none"

# 测试 parseProtocolIdFromFileName
id=$(parseProtocolIdFromFileName "02_VLESS_TCP_inbounds.json")
assert_equals "0" "${id}" "parseProtocolIdFromFileName(02_VLESS_TCP) = 0"

id=$(parseProtocolIdFromFileName "07_VLESS_vision_reality_inbounds.json")
assert_equals "7" "${id}" "parseProtocolIdFromFileName(07_Reality) = 7"

# 测试 scanInstalledProtocols（回归 finding C：链式入口须探测全部已注册 Xray 代理协议，
# 不能只认 02/07/04，否则 XHTTP/WS-only 安装会导致链式转发静默失效、真实 IP 泄露）
_scanTmp1=$(mktemp -d)
: >"${_scanTmp1}/12_VLESS_XHTTP_inbounds.json"
scanRes1=$(scanInstalledProtocols "${_scanTmp1}")
assert_true '[[ "${scanRes1}" == *",12,"* ]]' "scanInstalledProtocols detects XHTTP-only dir (id 12)"
assert_not_empty "${scanRes1//,/}" "scanInstalledProtocols non-empty for XHTTP-only dir"

# dokodemo 端口跳跃文件名以 _<port>.json 结尾，不匹配 *_inbounds.json，不应误判为代理协议
_scanTmp2=$(mktemp -d)
: >"${_scanTmp2}/02_dokodemodoor_inbounds_443.json"
scanRes2=$(scanInstalledProtocols "${_scanTmp2}")
assert_empty "${scanRes2//,/}" "scanInstalledProtocols excludes dokodemo port-hopping file"
rm -rf "${_scanTmp1}" "${_scanTmp2}"

# 测试 SS2022 uPSK 长度契约（回归 finding B：uPSK 解码长度必须等于方法密钥长度，
# 镜像 install.sh initSingBoxClients id-14 的派生 head -c {16|32} | base64）
_ss2022Uuid="9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
_ss2022Len16=$(echo -n "${_ss2022Uuid}" | head -c 16 | base64 | base64 -d | wc -c | tr -d ' ')
_ss2022Len32=$(echo -n "${_ss2022Uuid}" | head -c 32 | base64 | base64 -d | wc -c | tr -d ' ')
assert_equals "16" "${_ss2022Len16}" "SS2022 aes-128-gcm uPSK decodes to 16 bytes"
assert_equals "32" "${_ss2022Len32}" "SS2022 aes-256-gcm/chacha20 uPSK decodes to 32 bytes"

# uPSK 直通判定契约（回归 N-4：来自 ss2022 inbound 的 password 已是派生 uPSK，
# 二次派生会静默改写存量密码；镜像 install.sh initSingBoxClients id-14 的直通正则）
_upskDetect() {
    [[ "$1" =~ ^[A-Za-z0-9+/]{22}==$ || "$1" =~ ^[A-Za-z0-9+/]{43}=$ ]] && echo pass || echo derive
}
_upsk16=$(echo -n "${_ss2022Uuid}" | head -c 16 | base64)
_upsk32=$(echo -n "${_ss2022Uuid}" | head -c 32 | base64)
assert_equals "pass" "$(_upskDetect "${_upsk16}")" "uPSK passthrough matches 16-byte derived key"
assert_equals "pass" "$(_upskDetect "${_upsk32}")" "uPSK passthrough matches 32-byte derived key"
assert_equals "derive" "$(_upskDetect "${_ss2022Uuid}")" "uPSK passthrough rejects raw 36-char UUID"
assert_equals "derive" "$(_upskDetect "short")" "uPSK passthrough rejects short strings"

# domain_strategy → domain_resolver 迁移过滤器语义（回归 N-3：sing-box 1.14 移除该字段，
# 镜像 install.sh singBoxMergeConfig 的迁移 jq）
_dsFilter='.outbounds |= map(if has("domain_strategy") then .domain_resolver = {server: "local", strategy: .domain_strategy} | del(.domain_strategy) else . end)'
_dsIn='{"outbounds":[{"type":"direct","tag":"IPv6_out","domain_strategy":"ipv6_only"},{"type":"direct","tag":"direct"}]}'
_dsOut=$(echo "${_dsIn}" | jq -c "${_dsFilter}")
assert_equals '{"outbounds":[{"type":"direct","tag":"IPv6_out","domain_resolver":{"server":"local","strategy":"ipv6_only"}},{"type":"direct","tag":"direct"}]}' "${_dsOut}" "domain_strategy migration rewrites field and keeps clean outbounds"
_dsDetect=$(echo "${_dsOut}" | jq -e '[.outbounds[]? | has("domain_strategy")] | any' >/dev/null 2>&1 && echo hit || echo clean)
assert_equals "clean" "${_dsDetect}" "migrated fragment no longer triggers detection filter"

# 账户字段映射三列契约（注册表 cell 错一格 = 账户操作静默写错文件/字段，B01/B02/X1/N-4 全是这一族）
# 每行 core:id:期望值；来源是真实模板与读取端（xray-07 用户在 inbounds[1]，[0] 是 dokodemo）
while IFS=: read -r _c _id _want; do
    assert_equals "${_want}" "$(getProtocolUsersPath "${_c}" "${_id}")" "usersPath(core=${_c},id=${_id})"
done <<'CELLS'
1:0:.inbounds[0].settings.clients
1:1:.inbounds[0].settings.clients
1:3:.inbounds[0].settings.clients
1:4:.inbounds[0].settings.clients
1:7:.inbounds[1].settings.clients
1:11:.inbounds[0].settings.clients
1:12:.inbounds[0].settings.clients
1:6:.inbounds[0].users
1:9:.inbounds[0].users
2:0:.inbounds[0].users
2:7:.inbounds[0].users
2:10:.inbounds[0].users
2:14:.inbounds[0].users
CELLS
while IFS=: read -r _c _id _want; do
    assert_equals "${_want}" "$(getProtocolIdField "${_c}" "${_id}")" "idField(core=${_c},id=${_id})"
done <<'CELLS'
1:0:id
1:4:password
1:6:password
1:9:uuid
1:12:id
2:0:uuid
2:4:password
2:9:uuid
2:10:password
2:14:password
CELLS
while IFS=: read -r _c _id _want; do
    assert_equals "${_want}" "$(getProtocolNameField "${_c}" "${_id}")" "nameField(core=${_c},id=${_id})"
done <<'CELLS'
1:0:email
1:6:name
1:12:email
2:0:name
2:10:username
2:14:name
CELLS
assert_true "! getProtocolUsersPath 1 10" "usersPath rejects naive on Xray core"
assert_true "! getProtocolUsersPath 2 12" "usersPath rejects XHTTP on sing-box core"
assert_true "! getProtocolNameField 2 20" "nameField rejects socks internal inbound (no name)"
assert_true "! getProtocolIdField 3 0" "idField rejects unknown core"

# jsonTx 事务契约：Rollback 恢复快照并删除事务内新建的文件；Commit 保留写入
_txDir=$(mktemp -d)
echo '{"a":1}' >"${_txDir}/x.json"
jsonTxBegin "${_txDir}"
jsonTxTrack "${_txDir}/x.json"
echo '{"a":2}' >"${_txDir}/x.json"
jsonTxTrack "${_txDir}/new.json"
echo '{"b":1}' >"${_txDir}/new.json"
jsonTxRollback
assert_equals '{"a":1}' "$(cat "${_txDir}/x.json")" "jsonTxRollback restores tracked file to snapshot"
assert_true "[[ ! -f ${_txDir}/new.json ]]" "jsonTxRollback deletes files created inside the tx"
assert_true "[[ -z \$(find "${_txDir}" -maxdepth 1 -name '.txn.*' -print -quit) ]]" "jsonTxRollback removes snapshot dir"
jsonTxBegin "${_txDir}"
jsonTxTrack "${_txDir}/x.json"
echo '{"a":3}' >"${_txDir}/x.json"
jsonTxCommit
assert_equals '{"a":3}' "$(cat "${_txDir}/x.json")" "jsonTxCommit keeps modifications"
assert_true "[[ -z \$(find "${_txDir}" -maxdepth 1 -name '.txn.*' -print -quit) ]]" "jsonTxCommit removes snapshot dir"
assert_true "! jsonTxTrack ${_txDir}/x.json" "jsonTxTrack outside a tx returns error"
rm -rf "${_txDir}"

echo ""

# ============================================================================
# 测试 detectRelease（checkSystem 的发行版判定，只看 os-release 的 ID / ID_LIKE）
# ============================================================================
echo -e "${YELLOW}[system-detect.sh] detectRelease 测试${NC}"
_osrDir=$(mktemp -d)
_osr() { printf '%s\n' "$2" >"${_osrDir}/$1"; printf '%s' "${_osrDir}/$1"; }
assert_equals "ubuntu" "$(detectRelease "$(_osr ubuntu $'NAME="Ubuntu"\nVERSION_ID="22.04"\nID=ubuntu\nID_LIKE=debian')")" "detectRelease: Ubuntu 是 ubuntu，不因 ID_LIKE=debian 归成 debian"
assert_equals "debian" "$(detectRelease "$(_osr debian $'PRETTY_NAME="Debian GNU/Linux 12"\nID=debian\nVERSION_ID="12"')")" "detectRelease: Debian 是 debian"
assert_equals "debian" "$(detectRelease "$(_osr kali $'ID=kali\nID_LIKE=debian')")" "detectRelease: Debian 衍生版按 ID_LIKE 归 debian"
assert_equals "ubuntu" "$(detectRelease "$(_osr mint $'ID=linuxmint\nID_LIKE="ubuntu debian"')")" "detectRelease: Ubuntu 衍生版按 ID_LIKE 归 ubuntu"
assert_equals "alpine" "$(detectRelease "$(_osr alpine $'ID=alpine\nVERSION_ID=3.20.10')")" "detectRelease: Alpine 是 alpine"
assert_equals "centos" "$(detectRelease "$(_osr centos $'ID="centos"\nID_LIKE="rhel fedora"\nVERSION_ID="7"')")" "detectRelease: CentOS 是 centos"
assert_equals "centos" "$(detectRelease "$(_osr rocky $'ID="rocky"\nID_LIKE="rhel centos fedora"')")" "detectRelease: Rocky 按 ID_LIKE 归 centos"
assert_equals "centos" "$(detectRelease "$(_osr fedora $'ID=fedora')")" "detectRelease: Fedora 归 centos"
assert_true "! detectRelease $(_osr arch $'ID=arch')" "detectRelease: 认不出的发行版返回 1"
assert_equals "" "$(detectRelease "${_osrDir}/arch")" "detectRelease: 认不出时不输出"
assert_true "! detectRelease ${_osrDir}/missing" "detectRelease: 文件不存在返回 1"
rm -rf "${_osrDir}"

echo ""

# ============================================================================
# 测试 checkCPUVendor 的 sing-box 包名后缀（uname 用函数顶替，Linux 以外也能跑）
# ============================================================================
echo -e "${YELLOW}[system-detect.sh] checkCPUVendor 测试${NC}"
_cpuVendorFor() {
    (
        _ARCH="$1"
        uname() { if [[ "${1:-}" == "-m" ]]; then echo "${_ARCH}"; else echo Linux; fi; }
        release="$2"
        checkCPUVendor
        echo "${singBoxCoreCPUVendor} ${xrayCoreCPUVendor}"
    )
}
assert_equals "-linux-arm64-musl Xray-linux-arm64-v8a" "$(_cpuVendorFor aarch64 alpine)" "checkCPUVendor: Alpine arm64 取 sing-box 的 -musl 包，Xray 包名不变"
assert_equals "-linux-amd64-musl Xray-linux-64" "$(_cpuVendorFor x86_64 alpine)" "checkCPUVendor: Alpine amd64 取 sing-box 的 -musl 包"
assert_equals "-linux-arm64 Xray-linux-arm64-v8a" "$(_cpuVendorFor aarch64 debian)" "checkCPUVendor: glibc 系 arm64 仍取无后缀包"
assert_equals "-linux-amd64 Xray-linux-64" "$(_cpuVendorFor x86_64 centos)" "checkCPUVendor: glibc 系 amd64 仍取无后缀包"

echo ""

# ============================================================================
# 测试 isPlausiblePublicIP（getPublicIP 的输出闸门）
# ============================================================================
echo -e "${YELLOW}[system-detect.sh] isPlausiblePublicIP 测试${NC}"
assert_true "isPlausiblePublicIP 203.0.113.7" "isPlausiblePublicIP 接受普通 IPv4"
assert_true "isPlausiblePublicIP 2001:db8::1" "isPlausiblePublicIP 接受普通 IPv6"
assert_true "isPlausiblePublicIP ::ffff:203.0.113.7" "isPlausiblePublicIP 接受 IPv4-mapped IPv6"
assert_true "! isPlausiblePublicIP ''" "isPlausiblePublicIP 拒绝空串"
assert_true "! isPlausiblePublicIP 'not-an-ip-or-html'" "isPlausiblePublicIP 拒绝提示文本"
assert_true "! isPlausiblePublicIP '<html><body>error</body></html>'" "isPlausiblePublicIP 拒绝 HTML 错误页"
assert_true "! isPlausiblePublicIP 'deadbeef'" "isPlausiblePublicIP 拒绝无冒号纯十六进制串"
assert_true "! isPlausiblePublicIP '203.0.113.7 x'" "isPlausiblePublicIP 拒绝带空白的响应"

echo ""

# ============================================================================
# 测试 checkCentosSELinux 的 doctor 放行（stub getenforce 模拟 Enforcing）
# ============================================================================
echo -e "${YELLOW}[system-detect.sh] checkCentosSELinux doctor 放行测试${NC}"
selinuxStubDir=$(mktemp -d)
printf '#!/bin/sh\necho Enforcing\n' >"${selinuxStubDir}/getenforce"
chmod +x "${selinuxStubDir}/getenforce"
(PATH="${selinuxStubDir}:${PATH}" checkCentosSELinux) >/dev/null 2>&1
assert_equals "1" "$?" "Enforcing 且无放行变量时 exit 1"
(PATH="${selinuxStubDir}:${PATH}" PROXY_AGENT_SELINUX_NONFATAL=1 checkCentosSELinux) >/dev/null 2>&1
assert_equals "0" "$?" "PROXY_AGENT_SELINUX_NONFATAL=1（doctor 入口）时放行"
rm -rf "${selinuxStubDir}"

echo ""

# ============================================================================
# 清理测试文件
# ============================================================================


# ============================================================================
# 测试结果汇总
# Reality 分享链接的 pqv 参数：verify 为空时不得产出 "pqv=&" 这种空参数
assert_equals "" "$(realityPqvParam "")" "realityPqvParam: empty verify yields nothing"
assert_equals "" "$(realityPqvParam "" qr)" "realityPqvParam: empty verify yields nothing in qr form"
assert_equals "&pqv=abc_-123" "$(realityPqvParam "abc_-123")" "realityPqvParam: url form"
assert_equals "%26pqv%3Dabc_-123" "$(realityPqvParam "abc_-123" qr)" "realityPqvParam: qr form is percent-encoded"

# acme.sh -d 参数：非通配符只签用户填的域名，不追加根域（公共后缀下根域不归用户）
assert_equals "-d 'a.b.example.com'" "$(acmeIssueDomainArgs "a.b.example.com" "b.example.com" "n")" "acmeIssueDomainArgs: non-wildcard signs only the requested host"
assert_equals "-d 'a.b.example.com'" "$(acmeIssueDomainArgs "a.b.example.com" "b.example.com" "")" "acmeIssueDomainArgs: empty answer means non-wildcard"
assert_equals "-d '*.b.example.com' -d 'b.example.com'" "$(acmeIssueDomainArgs "a.b.example.com" "b.example.com" "y")" "acmeIssueDomainArgs: wildcard signs *.parent plus parent"

# rule_set 下载通道字段按内核归一化（镜像 install.sh normalizeSingBoxRuleSetHttpClient 的两条 jq）
_rsFwd='.route.rule_set |= map(if has("download_detour") then .http_client = "rule_set_http" | del(.download_detour) else . end)'
_rsBack='.route.rule_set |= map(del(.http_client))'
_rsIn='{"route":{"rule_set":[{"tag":"a","type":"remote","url":"u","download_detour":"01_direct_outbound"},{"tag":"b","type":"local","path":"p"}]}}'
_rsOut=$(echo "${_rsIn}" | jq -c "${_rsFwd}")
assert_equals '{"route":{"rule_set":[{"tag":"a","type":"remote","url":"u","http_client":"rule_set_http"},{"tag":"b","type":"local","path":"p"}]}}' "${_rsOut}" "rule_set forward migration swaps download_detour for http_client"
assert_equals '{"route":{"rule_set":[{"tag":"a","type":"remote","url":"u"},{"tag":"b","type":"local","path":"p"}]}}' "$(echo "${_rsOut}" | jq -c "${_rsBack}")" "rule_set backward migration strips http_client for pre-1.14 cores"
_rsDetour=$(printf '%s\n%s' '{"outbounds":[{"type":"selector","tag":"sel"}]}' '{"outbounds":[{"type":"direct","tag":"01_direct_outbound"},{"type":"direct","tag":"direct"}]}' | jq -r '.outbounds[]? | select(.type == "direct") | .tag' | head -1)
assert_equals "01_direct_outbound" "${_rsDetour}" "http client detour picks the first direct outbound across fragments"

# geosite 分类清单匹配：名字可带引号也可不带，大小写不敏感，规则里的域名不算分类
_gsList=$(mktemp)
cat > "${_gsList}" <<'EOF'
lists:
  - name: "google"
    length: 1
    rules:
      - "domain:google.com"
  - name: geolocation-!cn
    length: 1
    rules:
      - "domain:example.org"
EOF
assert_equals 0 "$(geositeListHasCategory "${_gsList}" "google"; echo $?)" "geositeListHasCategory: quoted name matches"
assert_equals 0 "$(geositeListHasCategory "${_gsList}" "Google"; echo $?)" "geositeListHasCategory: match is case-insensitive"
assert_equals 0 "$(geositeListHasCategory "${_gsList}" "geolocation-!cn"; echo $?)" "geositeListHasCategory: unquoted name with ! matches"
assert_equals 1 "$(geositeListHasCategory "${_gsList}" "google.com"; echo $?)" "geositeListHasCategory: rule domains are not categories"
assert_equals 1 "$(geositeListHasCategory "${_gsList}" "goo"; echo $?)" "geositeListHasCategory: prefix does not match"
assert_equals 1 "$(geositeListHasCategory "${_gsList}" ""; echo $?)" "geositeListHasCategory: empty name never matches"
assert_equals 1 "$(geositeListHasCategory "/nonexistent/dlc.yml" "google"; echo $?)" "geositeListHasCategory: missing list means no category"
rm -f "${_gsList}"

# ============================================================================
# 测试 protocol-registry.sh 的 email 后缀列
# ============================================================================

echo -e "${YELLOW}=== 测试 getProtocolEmailSuffix ===${NC}"

assert_equals "VLESS_TCP/TLS_Vision" "$(getProtocolEmailSuffix 1 0)" "getProtocolEmailSuffix(1,0)"
assert_equals "VLESS_WS" "$(getProtocolEmailSuffix 1 1)" "getProtocolEmailSuffix(1,1)"
assert_equals "VMess_WS" "$(getProtocolEmailSuffix 1 3)" "getProtocolEmailSuffix(1,3)"
assert_equals "trojan_tcp" "$(getProtocolEmailSuffix 1 4)" "getProtocolEmailSuffix(1,4)"
assert_equals "vless_reality_vision" "$(getProtocolEmailSuffix 1 7)" "getProtocolEmailSuffix(1,7)"
assert_equals "VLESS_Reality_XHTTP" "$(getProtocolEmailSuffix 1 12)" "getProtocolEmailSuffix(1,12)"
assert_equals "Trojan_TCP" "$(getProtocolEmailSuffix 2 4)" "getProtocolEmailSuffix(2,4): sing-box 的大小写不同"
assert_equals "VLESS_Reality_Vision" "$(getProtocolEmailSuffix 2 7)" "getProtocolEmailSuffix(2,7)"
assert_equals "singbox_naive" "$(getProtocolEmailSuffix 2 10)" "getProtocolEmailSuffix(2,10)"
assert_true '! getProtocolEmailSuffix 2 20 >/dev/null' "getProtocolEmailSuffix(2,20): socks 无显示名，返回 1"
assert_true '! getProtocolEmailSuffix 1 10 >/dev/null' "getProtocolEmailSuffix(1,10): naive 不在 Xray 下"
_sfxWithDash=$(for _c in 1 2; do for _p in $(seq 0 20); do getProtocolEmailSuffix "${_c}" "${_p}" 2>/dev/null; done; done | grep -- '-')
assert_equals "" "${_sfxWithDash}" "getProtocolEmailSuffix: 后缀都不含连字符（\${name%-*} 才能无歧义剥回账户名）"

echo ""

# ============================================================================
# 测试 carpool.sh 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 carpool.sh 函数 ===${NC}"

export V2RAY_LANG=zh_CN   # 文案断言按中文写，不随运行环境的语言漂
source lib/i18n.sh
source lib/carpool.sh
assert_not_empty "${_CARPOOL_LOADED}" "carpool.sh 模块加载成功"
assert_equals "zh_CN" "${CURRENT_LANG}" "测试以中文文案运行"

cp_assert_contains() {
    if [[ "$1" == *"$2"* ]]; then
        echo -e "${GREEN}✓${NC} $3"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $3"
        echo -e "  String '$2' not found in: $1"
        ((TESTS_FAILED++))
    fi
}
cp_assert_not_contains() {
    if [[ "$1" != *"$2"* ]]; then
        echo -e "${GREEN}✓${NC} $3"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $3"
        echo -e "  String '$2' must not appear"
        ((TESTS_FAILED++))
    fi
}

_cpDir=$(mktemp -d)

# --- 两个键 ---
assert_equals "3fa85f64-5717-4562-b3fc-2c963f66afa6" "$(carpoolMemberKey "3fa85f64-5717-4562-b3fc-2c963f66afa6-VLESS_WS")" "carpoolMemberKey: 默认 UUID 名只剥协议后缀"
assert_equals "john-doe" "$(carpoolMemberKey "john-doe-VLESS_TCP/TLS_Vision")" "carpoolMemberKey: 带连字符的名字保留"
assert_equals "noone" "$(carpoolMemberKey "noone")" "carpoolMemberKey: 无后缀的名字原样"
assert_equals "john" "$(carpoolSubscribeKey "john-doe")" "carpoolSubscribeKey: 取第一段"
assert_true 'carpoolIsValidMemberName "a.b_c@d+e-f"' "carpoolIsValidMemberName: 允许 . _ @ + -"
assert_true '! carpoolIsValidMemberName "-abc"' "carpoolIsValidMemberName: 不能以 - 开头"
assert_true '! carpoolIsValidMemberName "a b"' "carpoolIsValidMemberName: 不允许空格"
assert_true '! carpoolIsValidMemberName ""' "carpoolIsValidMemberName: 空串拒绝"
assert_true 'carpoolIsValidUUID "550e8400-e29b-41d4-a716-446655440000"' "carpoolIsValidUUID: 合法"
assert_true '! carpoolIsValidUUID "550e8400-e29b-41d4-a716"' "carpoolIsValidUUID: 短了拒绝"
assert_equals "[0,1,7,12]" "$(carpoolInstalledProtocolsJson ",0,1,6,7,9,12,")" "carpoolInstalledProtocolsJson: 6/9 不入拼车，升序"
assert_equals "[]" "$(carpoolInstalledProtocolsJson ",6,9,")" "carpoolInstalledProtocolsJson: 只装 6/9 时为空"

# --- 日期 ---
assert_true 'carpoolIsValidDate 2024-02-29' "carpoolIsValidDate: 闰年 2 月 29"
assert_true '! carpoolIsValidDate 2026-02-29' "carpoolIsValidDate: 平年 2 月 29 拒绝"
assert_true '! carpoolIsValidDate 2100-02-29' "carpoolIsValidDate: 2100 不是闰年"
assert_true 'carpoolIsValidDate 2000-02-29' "carpoolIsValidDate: 2000 是闰年"
assert_true '! carpoolIsValidDate 2026-04-31' "carpoolIsValidDate: 4 月 31 拒绝"
assert_true '! carpoolIsValidDate 2026-13-01' "carpoolIsValidDate: 13 月拒绝"
assert_true '! carpoolIsValidDate 31/12/2026' "carpoolIsValidDate: 非 YYYY-MM-DD 拒绝"
assert_true '! carpoolIsValidDate 2026-1-5' "carpoolIsValidDate: 不补零拒绝"
assert_equals "0" "$(carpoolDaysBetween 1970-01-01 1970-01-01)" "carpoolDaysBetween: 同一天为 0"
assert_equals "1" "$(carpoolDaysBetween 1970-01-01 1970-01-02)" "carpoolDaysBetween: 纪元次日为 1"
assert_equals "2" "$(carpoolDaysBetween 2000-02-28 2000-03-01)" "carpoolDaysBetween: 跨闰日"
assert_equals "61" "$(carpoolDaysBetween 2026-10-31 2026-12-31)" "carpoolDaysBetween: 10-31 到 12-31"
assert_equals "-1" "$(carpoolDaysBetween 2027-01-01 2026-12-31)" "carpoolDaysBetween: 反向为负"
assert_equals "2026-10-01" "$(carpoolPeriodStart 2026-10-31 1)" "carpoolPeriodStart: resetDay 1 取本月 1 日"
assert_equals "2026-09-15" "$(carpoolPeriodStart 2026-10-10 15)" "carpoolPeriodStart: 日期早于 resetDay 取上月"
assert_equals "2026-10-15" "$(carpoolPeriodStart 2026-10-15 15)" "carpoolPeriodStart: 当天就是 resetDay"
assert_equals "2025-12-28" "$(carpoolPeriodStart 2026-01-05 28)" "carpoolPeriodStart: 跨年取上一年 12 月"
assert_equals "2026-02-28" "$(carpoolPeriodStart 2026-03-01 28)" "carpoolPeriodStart: 2 月的 28 日"
assert_equals "2026-11-01" "$(carpoolNextPeriodStart 2026-10-31 1)" "carpoolNextPeriodStart: 下月 1 日"
assert_equals "2027-01-01" "$(carpoolNextPeriodStart 2026-12-31 1)" "carpoolNextPeriodStart: 跨年"
assert_equals "2026-10-15" "$(carpoolNextPeriodStart 2026-10-10 15)" "carpoolNextPeriodStart: 本月还没到 resetDay"
assert_equals "2026-11-15" "$(carpoolNextPeriodStart 2026-10-15 15)" "carpoolNextPeriodStart: 当天是 resetDay 则下月"

# --- members.json 校验 ---
_cpMembers="${_cpDir}/members.json"
cat > "${_cpMembers}" <<'EOF'
{"resetDay": 15, "notify": {"label": "小车", "warnPercent": 90, "digestHour": null, "expireNoticeDays": 5},
 "members": {
   "alice": {"quotaGiB": 100, "expire": "2026-12-31", "protocols": "all"},
   "bob-x": {"quotaGiB": 0, "expire": "", "protocols": [0, 7], "uuid": "550e8400-e29b-41d4-a716-446655440000"},
   "carol": {}
 }}
EOF
assert_equals "0" "$(carpoolValidateMembers "${_cpMembers}" ",0,7,12,"; echo $?)" "carpoolValidateMembers: 合法文件通过"
assert_equals "" "$(carpoolValidateMembers "${_cpMembers}" ",0,7,12,")" "carpoolValidateMembers: 合法文件不打印原因"
assert_equals "0" "$(carpoolValidateMembers "${_cpMembers}" ",0,7,12," '{"dave":"11111111-1111-1111-1111-111111111111"}'; echo $?)" "carpoolValidateMembers: 别人的 uuid 不同就不算撞车"

# cp_expect_error JSON 期待子串 说明 [INSTALLED] [FOREIGN]
cp_expect_error() {
    printf '%s\n' "$1" > "${_cpMembers}"
    local out rc
    out=$(carpoolValidateMembers "${_cpMembers}" "${4:-,0,7,12,}" "${5:-{\}}")
    rc=$?
    assert_equals "1" "${rc}" "$3: 返回 1"
    cp_assert_contains "${out}" "$2" "$3: 原因里有「$2」"
}
cp_expect_error '{"members": {' "不是合法的 JSON" "校验: JSON 坏了"
cp_expect_error '[1,2]' "顶层必须是一个对象" "校验: 顶层不是对象"
cp_expect_error '{"resetDay": 1}' "缺少 members" "校验: 没有 members"
cp_expect_error '{"member": {}, "members": {}}' "不认识的字段 member" "校验: 顶层字段拼错"
cp_expect_error '{"resetDay": 0, "members": {}}' "resetDay 必须是 1–28 的整数，现在是 0" "校验: resetDay 0"
cp_expect_error '{"resetDay": 29, "members": {}}' "现在是 29" "校验: resetDay 29"
cp_expect_error '{"resetDay": 1.5, "members": {}}' "现在是 1.5" "校验: resetDay 小数"
cp_expect_error '{"resetDay": "1", "members": {}}' 'resetDay 必须是' "校验: resetDay 字符串"
cp_expect_error '{"notify": 1, "members": {}}' "notify.notify 的值不合法" "校验: notify 不是对象"
cp_expect_error '{"notify": {"label": ""}, "members": {}}' "notify.label 的值不合法" "校验: label 空"
cp_expect_error '{"notify": {"warnPercent": 101}, "members": {}}' "notify.warnPercent 的值不合法" "校验: warnPercent 超 100"
cp_expect_error '{"notify": {"digestHour": 24}, "members": {}}' "notify.digestHour 的值不合法" "校验: digestHour 24"
cp_expect_error '{"notify": {"expireNoticeDays": -1}, "members": {}}' "notify.expireNoticeDays 的值不合法" "校验: expireNoticeDays 负数"
cp_expect_error '{"notify": {"telegram": "x"}, "members": {}}' "不认识的字段 notify.telegram" "校验: notify 字段拼错"
cp_expect_error '{"members": {"-x": {}}}' "成员名 -x 不合法" "校验: 名字以 - 开头"
cp_expect_error '{"members": {"a b": {}}}' "成员名 a b 不合法" "校验: 名字带空格"
cp_expect_error '{"members": {"alice": {}, "Alice": {}}}' "只差大小写：alice,Alice" "校验: 只差大小写"
cp_expect_error '{"members": {"john-a": {}, "john-b": {}}}' "成员 john-a,john-b 名字的第一段相同" "校验: 订阅键冲突"
cp_expect_error '{"members": {"alice": 1}}' "成员 alice 的值必须是对象" "校验: 成员不是对象"
cp_expect_error '{"members": {"alice": {"quotaGib": 1}}}' "不认识的字段 alice.quotaGib" "校验: 成员字段拼错"
cp_expect_error '{"members": {"alice": {"quotaGiB": -1}}}' "成员 alice 的 quotaGiB 必须是非负整数" "校验: 配额负数"
cp_expect_error '{"members": {"alice": {"quotaGiB": 1.5}}}' "quotaGiB 必须是非负整数" "校验: 配额小数"
cp_expect_error '{"members": {"alice": {"quotaGiB": "100"}}}' "quotaGiB 必须是非负整数" "校验: 配额字符串"
cp_expect_error '{"members": {"alice": {"expire": "2026-02-30"}}}' "成员 alice 的 expire 必须为空或真实存在的" "校验: 2 月 30 日"
cp_expect_error '{"members": {"alice": {"expire": "2026/12/31"}}}' "expire 必须为空或真实存在的" "校验: 日期分隔符错"
cp_expect_error '{"members": {"alice": {"expire": 20261231}}}' "expire 必须为空或真实存在的" "校验: 日期是数字"
cp_expect_error '{"members": {"alice": {"protocols": "x"}}}' 'protocols 必须是 "all" 或非空的协议 ID 数组' "校验: protocols 乱填"
cp_expect_error '{"members": {"alice": {"protocols": []}}}' 'protocols 必须是 "all"' "校验: protocols 空数组"
cp_expect_error '{"members": {"alice": {"protocols": [0, "7"]}}}' 'protocols 必须是 "all"' "校验: protocols 混字符串"
cp_expect_error '{"members": {"alice": {"protocols": [0, 7, 6]}}}' "成员 alice 的协议 6 不能纳入拼车" "校验: 6 不能入拼车"
cp_expect_error '{"members": {"alice": {"protocols": [0, 7, 99]}}}' "协议 99 不能纳入拼车" "校验: 不存在的 ID"
cp_expect_error '{"members": {"alice": {"protocols": [0, 7, 1]}}}' "成员 alice 的协议 1 本机未安装" "校验: 协议未安装" ",0,7,"
cp_expect_error '{"members": {"alice": {"protocols": [7, 12]}}}' "protocols 必须包含已安装的协议 0" "校验: 0 必含"
cp_expect_error '{"members": {"alice": {"protocols": [0, 12]}}}' "protocols 必须包含已安装的协议 7" "校验: 7 必含"
assert_equals "0" "$(printf '%s\n' '{"members": {"alice": {"protocols": [1, 12]}}}' > "${_cpMembers}"; carpoolValidateMembers "${_cpMembers}" ",1,12,"; echo $?)" "校验: 没装 0/7 时就不要求它们"
cp_expect_error '{"members": {"alice": {"uuid": "nope"}}}' "成员 alice 的 uuid 格式不合法" "校验: uuid 格式"
cp_expect_error '{"members": {"alice": {"uuid": "550e8400-e29b-41d4-a716-446655440000"}, "bob": {"uuid": "550e8400-e29b-41d4-a716-446655440000"}}}' "成员 alice,bob 使用了同一个 uuid" "校验: 两人同 uuid"
cp_expect_error '{"members": {"alice": {"uuid": "550e8400-e29b-41d4-a716-446655440000"}}}' "成员 alice 的 uuid 已被不归拼车管的账号使用" "校验: uuid 撞上外部账号" ",0,7,12," '{"dave":"550e8400-e29b-41d4-a716-446655440000"}'
assert_equals "1" "$(carpoolValidateMembers "${_cpDir}/nope.json" ",0,7," >/dev/null; echo $?)" "校验: 文件不存在返回 1"
printf '%s\n' '{"members": {"alice": {"uuid": "550e8400-e29b-41d4-a716-446655440000"}}}' > "${_cpMembers}"
_cpOut=$(carpoolValidateMembers "${_cpMembers}" ",0,7," '"not-an-object"')
assert_equals "1" "$?" "校验: FOREIGN 参数不是对象（调用方错误）也返回 1，不会当成合法"
cp_assert_contains "${_cpOut}" "INTERNAL" "校验: 调用方错误报成 INTERNAL 并带 jq 原话，不冒充「JSON 不合法」"

# --- 归一化与播种 ---
cat > "${_cpMembers}" <<'EOF'
{"members": {"alice": {}, "bob": {"quotaGiB": 2, "expire": "2026-12-31", "protocols": [7, 0, 7]}}}
EOF
_cpNorm=$(carpoolNormalizeMembers "${_cpMembers}" ",0,7,12,")
assert_equals "1" "$(jq -r '.resetDay' <<<"${_cpNorm}")" "carpoolNormalizeMembers: resetDay 默认 1"
assert_equals "拼车|80|8|3" "$(jq -r '.notify | "\(.label)|\(.warnPercent)|\(.digestHour)|\(.expireNoticeDays)"' <<<"${_cpNorm}")" "carpoolNormalizeMembers: notify 默认值"
assert_equals "[0,7,12]" "$(jq -c '.members.alice.protocols' <<<"${_cpNorm}")" "carpoolNormalizeMembers: 省略 protocols 等于 all，展开成已装集合"
assert_equals '0||' "$(jq -r '.members.alice | "\(.quotaBytes)|\(.expire)|\(.uuid)"' <<<"${_cpNorm}")" "carpoolNormalizeMembers: 省略字段的默认值"
assert_equals "2147483648" "$(jq -r '.members.bob.quotaBytes' <<<"${_cpNorm}")" "carpoolNormalizeMembers: quotaGiB 2 = 2×2^30 字节"
assert_equals "[0,7]" "$(jq -c '.members.bob.protocols' <<<"${_cpNorm}")" "carpoolNormalizeMembers: 显式 protocols 去重排序"
printf '%s\n' '{"notify": {"digestHour": null, "label": "L"}, "members": {}}' > "${_cpMembers}"
assert_equals "null|L" "$(carpoolNormalizeMembers "${_cpMembers}" ",0,7," | jq -r '.notify | "\(.digestHour)|\(.label)"')" "carpoolNormalizeMembers: digestHour null（关闭）保留为 null"

_cpAccounts=$(carpoolAccountsFromClients '[{"id":"u1","email":"alice-VLESS_TCP/TLS_Vision"},{"password":"u2","email":"bob-x-trojan_tcp"},{"id":"u3","email":"3fa85f64-5717-4562-b3fc-2c963f66afa6"}]')
assert_equals '[{"name":"alice","uuid":"u1"},{"name":"bob-x","uuid":"u2"},{"name":"3fa85f64-5717-4562-b3fc","uuid":"u3"}]' "${_cpAccounts}" "carpoolAccountsFromClients: 名字剥后缀，凭据取 id 或 password"
_cpSeed=$(carpoolSeedMembers "${_cpAccounts}")
assert_equals '["alice","bob-x","3fa85f64-5717-4562-b3fc"]' "$(jq -c '.members | keys_unsorted' <<<"${_cpSeed}")" "carpoolSeedMembers: 全部账号入册、顺序不变"
assert_equals '{"quotaGiB":0,"expire":"","protocols":"all"}' "$(jq -c '.members.alice' <<<"${_cpSeed}")" "carpoolSeedMembers: 不限额不限期全协议、不写 uuid"
printf '%s\n' "${_cpSeed}" > "${_cpMembers}"
assert_equals "0" "$(carpoolValidateMembers "${_cpMembers}" ",0,4,"; echo $?)" "carpoolSeedMembers: 播种出来的文件本身通过校验"

# --- statsquery 汇总 ---
_cpStats='{"stat":[
  {"name":"user>>>alice-VLESS_WS>>>traffic>>>uplink","value":10},
  {"name":"user>>>alice-vless_reality_vision>>>traffic>>>uplink","value":"5"},
  {"name":"user>>>alice-VLESS_WS>>>traffic>>>downlink"},
  {"name":"user>>>bob-x-VLESS_WS>>>traffic>>>downlink","value":7},
  {"name":"inbound>>>VLESSTCP>>>traffic>>>uplink","value":99},
  {"name":"user>>>3fa85f64-5717-4562-b3fc-2c963f66afa6-VLESS_WS>>>traffic>>>uplink","value":1}]}'
_cpSums=$(carpoolSumStats "${_cpStats}")
assert_equals "15" "$(jq -r '.alice.up' <<<"${_cpSums}")" "carpoolSumStats: 数字与字符串形态跨协议相加"
assert_equals "0" "$(jq -r '.alice.down' <<<"${_cpSums}")" "carpoolSumStats: value 键省略当 0"
assert_equals "0|7" "$(jq -r '.["bob-x"] | "\(.up)|\(.down)"' <<<"${_cpSums}")" "carpoolSumStats: 带连字符的名字按成员键汇总"
assert_equals "1" "$(jq -r '.["3fa85f64-5717-4562-b3fc-2c963f66afa6"].up' <<<"${_cpSums}")" "carpoolSumStats: UUID 默认名只剥协议后缀"
# 开启前的裸 UUID 账号与它被拼车改写成「成员键-后缀」之后，计数器名不同，但两种剥法都落到同一个成员键
_cpSums=$(carpoolSumStats '{"stat":[{"name":"user>>>3fa85f64-5717-4562-b3fc-2c963f66afa6>>>traffic>>>uplink","value":3},{"name":"user>>>3fa85f64-5717-4562-b3fc-vless_reality_vision>>>traffic>>>uplink","value":4}]}')
assert_equals '{"3fa85f64-5717-4562-b3fc":{"up":7,"down":0}}' "${_cpSums}" "carpoolSumStats: 裸 UUID 名与改写后的「成员键-后缀」名汇总到同一个键"
assert_equals "3fa85f64-5717-4562-b3fc" "$(carpoolMemberKey "3fa85f64-5717-4562-b3fc-2c963f66afa6")" "carpoolMemberKey: 裸 UUID 名的成员键是去掉末段的 UUID（与 initXrayClients 的剥法一致）"
assert_equals "null" "$(jq -r '.inbound' <<<"${_cpSums}")" "carpoolSumStats: inbound 计数器忽略"
assert_equals "{}" "$(carpoolSumStats '{}')" "carpoolSumStats: 空响应得空对象"
assert_true '! carpoolSumStats "not json" >/dev/null 2>&1' "carpoolSumStats: 非 JSON 返回非零"

# --- state ---
cp_member() { # UUID QUOTA EXPIRE PROTOCOLS UP DOWN STATUS REASON
    jq -cn --arg u "$1" --argjson q "$2" --arg e "$3" --argjson p "$4" --argjson up "$5" --argjson dn "$6" --arg s "$7" --arg r "$8" \
        '{uuid: $u, quotaBytes: $q, expire: $e, protocols: $p, upBytes: $up, downBytes: $dn, status: $s, reason: $r}'
}
cp_state() { # PERIOD MEMBERS_JSON [NOTIFIED_JSON]
    jq -cn --arg p "$1" --argjson m "$2" --argjson n "${3:-{\}}" \
        '{enabled: true, apiPort: 1, period: $p, lastTick: "", pageEnabled: false, pageToken: "", collectFailures: 0, notified: $n, events: [], members: $m}'
}
_cpU1="11111111-1111-1111-1111-111111111111"
_cpU2="22222222-2222-2222-2222-222222222222"
_cpU3="33333333-3333-3333-3333-333333333333"
_cpNotify='{"label":"x","warnPercent":80,"digestHour":8,"expireNoticeDays":3}'
GiB=1073741824

_cpInit=$(carpoolInitialState 23456 2026-10-01)
assert_equals "true|23456|2026-10-01|0" "$(jq -r '"\(.enabled)|\(.apiPort)|\(.period)|\(.members | length)"' <<<"${_cpInit}")" "carpoolInitialState: 开启态、端口、周期、无成员"
assert_equals "1|拼车|80|8|3" "$(jq -r '"\(.resetDay)|\(.notify.label)|\(.notify.warnPercent)|\(.notify.digestHour)|\(.notify.expireNoticeDays)"' <<<"${_cpInit}")" "carpoolInitialState: resetDay 与 notify 的已应用副本带默认值"
assert_equals "0" "$(carpoolWriteState "${_cpInit}" "${_cpDir}/state.json"; echo $?)" "carpoolWriteState: 写入成功"
assert_equals "${_cpInit}" "$(carpoolReadState "${_cpDir}/state.json")" "carpoolReadState: 读回一致"
assert_equals "1" "$(carpoolReadState "${_cpDir}/absent.json" >/dev/null; echo $?)" "carpoolReadState: 缺文件返回 1"
assert_equals "" "$(ls "${_cpDir}"/state.json.bak.* 2>/dev/null)" "carpoolWriteState: 不留 .bak"

_cpOld=$(cp_state 2026-10-01 "{\"alice\": $(cp_member "${_cpU1}" 0 "" '[0,7]' 5 6 disabled quota), \"gone\": $(cp_member "${_cpU3}" 0 "" '[0]' 1 1 active "")}")
printf '%s\n' '{"members": {"bob": {"uuid": "22222222-2222-2222-2222-222222222222"}, "alice": {"quotaGiB": 1, "expire": "2026-12-31", "protocols": [0]}, "carol": {}, "dave": {}}}' > "${_cpMembers}"
_cpNorm=$(carpoolNormalizeMembers "${_cpMembers}" ",0,7,")
_cpMerged=$(carpoolMergeState "${_cpOld}" "${_cpNorm}" "{\"carol\": \"${_cpU3}\", \"zed\": \"zz\"}")
assert_equals '["bob","alice","carol","dave"]' "$(jq -c '.members | keys_unsorted' <<<"${_cpMerged}")" "carpoolMergeState: 成员顺序随文件，文件里没有的 gone 删掉"
assert_equals "${_cpU2}" "$(jq -r '.members.bob.uuid' <<<"${_cpMerged}")" "carpoolMergeState: uuid 文件给的优先"
assert_equals "${_cpU1}" "$(jq -r '.members.alice.uuid' <<<"${_cpMerged}")" "carpoolMergeState: 文件没给则沿用旧 state"
assert_equals "${_cpU3}" "$(jq -r '.members.carol.uuid' <<<"${_cpMerged}")" "carpoolMergeState: 都没有则采用 inbound 同名账号"
assert_equals "" "$(jq -r '.members.dave.uuid' <<<"${_cpMerged}")" "carpoolMergeState: 到处都没有留空，由调用方生成"
assert_equals "5|6|disabled|quota" "$(jq -r '.members.alice | "\(.upBytes)|\(.downBytes)|\(.status)|\(.reason)"' <<<"${_cpMerged}")" "carpoolMergeState: 旧成员的计数与状态沿用"
assert_equals "${GiB}|2026-12-31|[0]" "$(jq -r '.members.alice | "\(.quotaBytes)|\(.expire)|\(.protocols | tojson)"' <<<"${_cpMerged}")" "carpoolMergeState: 限额三项同步成文件的"
assert_equals "0|0|active|" "$(jq -r '.members.bob | "\(.upBytes)|\(.downBytes)|\(.status)|\(.reason)"' <<<"${_cpMerged}")" "carpoolMergeState: 新成员从零开始、active"
assert_equals "2026-10-01|23456" "$(jq -r '"\(.period)|\(.apiPort)"' <<<"$(carpoolMergeState "${_cpInit}" "${_cpNorm}" '{}')")" "carpoolMergeState: 顶层字段不动"
printf '%s\n' '{"resetDay": 20, "notify": {"label": "L", "warnPercent": 50}, "members": {"alice": {}}}' > "${_cpMembers}"
assert_equals "20|L|50|8" "$(carpoolMergeState "${_cpInit}" "$(carpoolNormalizeMembers "${_cpMembers}" ",0,7,")" '{}' | jq -r '"\(.resetDay)|\(.notify.label)|\(.notify.warnPercent)|\(.notify.digestHour)"')" "carpoolMergeState: resetDay 与 notify 跟文件走"

# 即时类同步：resetDay / notify / 在册成员的 quotaBytes 与 expire；protocols、uuid、文件里没有的成员不动
printf '%s\n' '{"resetDay": 10, "notify": {"warnPercent": 70}, "members": {"alice": {"quotaGiB": 3, "expire": "2027-01-31", "protocols": [0], "uuid": "22222222-2222-2222-2222-222222222222"}, "newbie": {}}}' > "${_cpMembers}"
_cpSynced=$(carpoolSyncLimits "${_cpMerged}" "$(carpoolNormalizeMembers "${_cpMembers}" ",0,7,")")
assert_equals "10|70" "$(jq -r '"\(.resetDay)|\(.notify.warnPercent)"' <<<"${_cpSynced}")" "carpoolSyncLimits: resetDay 与 notify 同步"
assert_equals "$((3 * GiB))|2027-01-31|[0]|${_cpU1}" "$(jq -r '.members.alice | "\(.quotaBytes)|\(.expire)|\(.protocols | tojson)|\(.uuid)"' <<<"${_cpSynced}")" "carpoolSyncLimits: 配额与到期同步，protocols 与 uuid 不动"
assert_equals '["bob","alice","carol","dave"]' "$(jq -c '.members | keys_unsorted' <<<"${_cpSynced}")" "carpoolSyncLimits: 不增不删成员"
assert_equals "0|" "$(jq -r '.members.bob | "\(.quotaBytes)|\(.expire)"' <<<"${_cpSynced}")" "carpoolSyncLimits: 文件里没有的成员原样"

_cpMap='{"0":[{"id":"zz","email":"zed-VLESS_TCP/TLS_Vision"},{"id":"'"${_cpU1}"'","email":"alice-VLESS_TCP/TLS_Vision"}],"4":[{"password":"pp","email":"pat-trojan_tcp"}]}'
assert_equals '{"zed":"zz","pat":"pp"}' "$(carpoolForeignAccounts "${_cpMerged}" "${_cpMap}")" "carpoolForeignAccounts: 不在册的账号 → {名: 凭据}，id 或 password 都认"
assert_equals '{}' "$(carpoolForeignAccounts "${_cpMerged}" '{}')" "carpoolForeignAccounts: 空映射得空对象"

_cpDiff=$(carpoolDiffMembers "${_cpOld}" "${_cpNorm}" "{\"carol\": \"${_cpU3}\", \"zed\": \"zz\"}")
assert_equals '["bob","carol","dave"]' "$(jq -c '.added' <<<"${_cpDiff}")" "carpoolDiffMembers: 新增"
assert_equals '["gone"]' "$(jq -c '.removed' <<<"${_cpDiff}")" "carpoolDiffMembers: 删除"
assert_equals '[{"name":"alice","from":[0,7],"to":[0]}]' "$(jq -c '.protocols' <<<"${_cpDiff}")" "carpoolDiffMembers: 协议变更"
assert_equals "[{\"name\":\"alice\",\"from\":0,\"to\":${GiB}}]" "$(jq -c '.quota' <<<"${_cpDiff}")" "carpoolDiffMembers: 配额变更"
assert_equals '[{"name":"alice","from":"","to":"2026-12-31"}]' "$(jq -c '.expire' <<<"${_cpDiff}")" "carpoolDiffMembers: 到期变更"
assert_equals '[]' "$(jq -c '.uuid' <<<"${_cpDiff}")" "carpoolDiffMembers: 文件没给 uuid 不算换凭据"
assert_equals '["zed"]' "$(jq -c '.unmanaged' <<<"${_cpDiff}")" "carpoolDiffMembers: 不在文件里的 inbound 账号只列出"
printf '%s\n' "{\"members\": {\"alice\": {\"uuid\": \"${_cpU2}\"}}}" > "${_cpMembers}"
assert_equals '["alice"]' "$(carpoolDiffMembers "${_cpOld}" "$(carpoolNormalizeMembers "${_cpMembers}" ",0,7,")" '{}' | jq -c '.uuid')" "carpoolDiffMembers: 文件给了不同的 uuid 算换凭据"

_cpUsed=$(carpoolAddUsage "${_cpMerged}" '{"alice":{"up":100,"down":200},"zed":{"up":1,"down":1}}')
assert_equals "105|206" "$(jq -r '.members.alice | "\(.upBytes)|\(.downBytes)"' <<<"${_cpUsed}")" "carpoolAddUsage: 增量累加"
assert_equals "0|0" "$(jq -r '.members.bob | "\(.upBytes)|\(.downBytes)"' <<<"${_cpUsed}")" "carpoolAddUsage: 没有增量的成员不变"
assert_equals "4" "$(jq -r '.members | length' <<<"${_cpUsed}")" "carpoolAddUsage: 不是成员的键丢弃"

# --- 判定 ---
cp_judge() { carpoolJudge "$1" "${2:-${_cpNotify}}" "$3" "$4"; }
cp_one() { # NAME MEMBER_JSON [PERIOD] → state
    cp_state "${3:-2026-10-01}" "{\"$1\": $2}"
}
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" $((10 * GiB)) "" '[0]' $((6 * GiB)) $((4 * GiB)) active "")")" "" 2026-10-20 2026-10-01)
assert_equals "disabled|quota" "$(jq -r '.state.members.alice | "\(.status)|\(.reason)"' <<<"${_cpJ}")" "判定: 用量正好等于配额即停用"
assert_equals '[{"type":"disabled","name":"alice","reason":"quota"}]' "$(jq -c '.events' <<<"${_cpJ}")" "判定: 超额发停用事件"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" $((10 * GiB)) "" '[0]' $((6 * GiB)) $((4 * GiB - 1)) active "")")" '{"label":"x","warnPercent":0,"digestHour":8,"expireNoticeDays":3}' 2026-10-20 2026-10-01)
assert_equals "active|[]" "$(jq -r '"\(.state.members.alice.status)|\(.events | tojson)"' <<<"${_cpJ}")" "判定: 差 1 字节不停用、无事件"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" 0 "" '[0]' $((900 * GiB)) 0 active "")")" "" 2026-10-20 2026-10-01)
assert_equals "active" "$(jq -r '.state.members.alice.status' <<<"${_cpJ}")" "判定: 配额 0 不限"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" 0 2026-10-19 '[0]' 0 0 active "")")" "" 2026-10-20 2026-10-01)
assert_equals "disabled|expired" "$(jq -r '.state.members.alice | "\(.status)|\(.reason)"' <<<"${_cpJ}")" "判定: 到期日已过即停用"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" 0 2026-10-20 '[0]' 0 0 active "")")" "" 2026-10-20 2026-10-01)
assert_equals "active" "$(jq -r '.state.members.alice.status' <<<"${_cpJ}")" "判定: 到期当天仍可用（24:00 失效）"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" ${GiB} 2026-10-19 '[0]' ${GiB} ${GiB} active "")")" "" 2026-10-20 2026-10-01)
assert_equals "expired" "$(jq -r '.state.members.alice.reason' <<<"${_cpJ}")" "判定: 超额又到期记 expired"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" $((10 * GiB)) "" '[0]' $((6 * GiB)) $((4 * GiB)) disabled quota)")" "" 2026-10-20 2026-10-01)
assert_equals "disabled|[]" "$(jq -r '"\(.state.members.alice.status)|\(.events | tojson)"' <<<"${_cpJ}")" "判定: 已停用且仍超额，不重复发事件"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" $((20 * GiB)) "" '[0]' $((6 * GiB)) $((4 * GiB)) disabled quota)")" "" 2026-10-20 2026-10-01)
assert_equals "active|" "$(jq -r '.state.members.alice | "\(.status)|\(.reason)"' <<<"${_cpJ}")" "判定: 配额调高到用量之上立即恢复"
assert_equals '[{"type":"restored","name":"alice"}]' "$(jq -c '.events' <<<"${_cpJ}")" "判定: 恢复发事件"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" 0 "" '[0]' $((6 * GiB)) $((4 * GiB)) disabled quota)")" "" 2026-10-20 2026-10-01)
assert_equals "active" "$(jq -r '.state.members.alice.status' <<<"${_cpJ}")" "判定: 配额改成 0（不限）立即恢复"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" 0 2026-11-30 '[0]' 0 0 disabled expired)")" "" 2026-10-20 2026-10-01)
assert_equals "active" "$(jq -r '.state.members.alice.status' <<<"${_cpJ}")" "判定: 到期日延后立即恢复"
_cpJ=$(cp_judge "$(cp_one alice "$(cp_member "${_cpU1}" 0 "" '[0]' 0 0 disabled manual)")" "" 2026-10-20 2026-10-01)
assert_equals "disabled|manual|[]" "$(jq -r '"\(.state.members.alice.status)|\(.state.members.alice.reason)|\(.events | tojson)"' <<<"${_cpJ}")" "判定: manual 永不自动恢复"

# 新周期：清零、quota 停用者恢复、到期者不恢复、notified 清空、周期事件带上期用量
_cpS=$(cp_state 2026-09-01 "{
  \"alice\": $(cp_member "${_cpU1}" ${GiB} "" '[0]' ${GiB} 5 disabled quota),
  \"bob\": $(cp_member "${_cpU2}" ${GiB} 2026-09-30 '[0]' ${GiB} 0 disabled quota),
  \"carol\": $(cp_member "${_cpU3}" 0 2026-09-15 '[0]' 3 4 disabled expired),
  \"dave\": $(cp_member "44444444-4444-4444-4444-444444444444" 0 "" '[0]' 9 9 active '')}" '{"warn:alice":true}')
_cpJ=$(cp_judge "${_cpS}" "" 2026-10-02 2026-10-01)
assert_equals "2026-10-01" "$(jq -r '.state.period' <<<"${_cpJ}")" "新周期: period 更新"
assert_equals "0" "$(jq -r '[.state.members[] | .upBytes + .downBytes] | add' <<<"${_cpJ}")" "新周期: 全员清零"
assert_equals "{}" "$(jq -c '.state.notified' <<<"${_cpJ}")" "新周期: notified 清空"
assert_equals "active|" "$(jq -r '.state.members.alice | "\(.status)|\(.reason)"' <<<"${_cpJ}")" "新周期: 超额停用者恢复"
assert_equals "disabled|expired" "$(jq -r '.state.members.bob | "\(.status)|\(.reason)"' <<<"${_cpJ}")" "新周期: 超额且已到期的翻成 expired、不恢复"
assert_equals "disabled|expired" "$(jq -r '.state.members.carol | "\(.status)|\(.reason)"' <<<"${_cpJ}")" "新周期: 到期停用者保持"
assert_equals "active" "$(jq -r '.state.members.dave.status' <<<"${_cpJ}")" "新周期: 正常成员不动"
assert_equals "period|2026-09-01|$((GiB + 5))|18" "$(jq -r '.events[0] | "\(.type)|\(.previous)|\(.usage.alice.up + .usage.alice.down)|\(.usage.dave.up + .usage.dave.down)"' <<<"${_cpJ}")" "新周期: 周期事件带上期各人用量"
assert_equals '["period","restored"]' "$(jq -c '[.events[].type]' <<<"${_cpJ}")" "新周期: 只有 alice 的恢复事件，bob 不发恢复"

# 预警与到期提醒：各发一次，去重键进 notified
_cpS=$(cp_state 2026-10-01 "{\"alice\": $(cp_member "${_cpU1}" $((10 * GiB)) 2026-10-22 '[0]' $((8 * GiB)) 0 active '')}")
_cpJ=$(cp_judge "${_cpS}" "" 2026-10-20 2026-10-01)
assert_equals '["warn","expiring"]' "$(jq -c '[.events[].type]' <<<"${_cpJ}")" "提醒: 用量 80% 与 2 天后到期各发一次"
assert_equals "80|$((8 * GiB))|$((10 * GiB))" "$(jq -r '.events[0] | "\(.percent)|\(.used)|\(.quota)"' <<<"${_cpJ}")" "提醒: 预警事件带百分比与用量"
assert_equals "2026-10-22|2" "$(jq -r '.events[1] | "\(.date)|\(.days)"' <<<"${_cpJ}")" "提醒: 到期事件带日期与剩余天数"
assert_equals '{"warn:alice":true,"expire:alice:2026-10-22":true}' "$(jq -c '.state.notified' <<<"${_cpJ}")" "提醒: 去重键记进 notified"
_cpJ2=$(cp_judge "$(jq -c '.state' <<<"${_cpJ}")" "" 2026-10-21 2026-10-01)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpJ2}")" "提醒: 第二次 tick 不再重复"
_cpJ2=$(cp_judge "$(jq -c '.state | .members.alice.expire = "2026-10-23"' <<<"${_cpJ}")" "" 2026-10-21 2026-10-01)
assert_equals '["expiring"]' "$(jq -c '[.events[].type]' <<<"${_cpJ2}")" "提醒: 改了到期日就再提醒一次"
_cpJ=$(cp_judge "${_cpS}" '{"label":"x","warnPercent":0,"digestHour":8,"expireNoticeDays":0}' 2026-10-20 2026-10-01)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpJ}")" "提醒: 阈值为 0 时关闭"
_cpJ=$(cp_judge "${_cpS}" "" 2026-10-18 2026-10-01)
assert_equals "[]" "$(jq -c '[.events[] | select(.type == "expiring")]' <<<"${_cpJ}")" "提醒: 还有 4 天不提醒（阈值 3）"
_cpJ=$(cp_judge "${_cpS}" "" 2026-10-19 2026-10-01)
assert_equals "3" "$(jq -r '.events[] | select(.type == "expiring") | .days' <<<"${_cpJ}")" "提醒: 正好 3 天提醒"
_cpS=$(cp_state 2026-10-01 "{\"alice\": $(cp_member "${_cpU1}" 0 "" '[0]' 1 1 active '')}")
assert_equals "$(jq -Sc . <<<"${_cpS}")" "$(cp_judge "${_cpS}" "" 2026-10-20 2026-10-01 | jq -Sc '.state')" "判定: 没有变化时 state 原样"

_cpEv=$(carpoolAppendEvents "${_cpS}" '[{"type":"period","previous":"x","usage":{"a":{"up":1,"down":2}}},{"type":"disabled","name":"alice","reason":"quota"}]' "2026-10-20 12:00")
assert_equals '[{"time":"2026-10-20 12:00","type":"period"},{"time":"2026-10-20 12:00","type":"disabled","name":"alice","reason":"quota"}]' "$(jq -c '.events' <<<"${_cpEv}")" "carpoolAppendEvents: 只留 type/name/reason 加时间"
_cpMany=$(jq -cn '[range(60) | {type: "restored", name: "m\(.)"}]')
assert_equals "50|m59" "$(carpoolAppendEvents "${_cpS}" "${_cpMany}" now | jq -r '"\(.events | length)|\(.events[-1].name)"')" "carpoolAppendEvents: 最多留 50 条、保最新"

# --- 期望 clients ---
_cpS=$(cp_state 2026-10-01 "{
  \"alice\": $(cp_member "${_cpU1}" 0 "" '[0,7,12]' 0 0 active ''),
  \"bob-x\": $(cp_member "${_cpU2}" 0 "" '[0,7]' 0 0 disabled quota),
  \"carol\": $(cp_member "${_cpU3}" 0 "" '[0,7]' 0 0 active ''),
  \"dave\": $(cp_member "" 0 "" '[0,7,12]' 0 0 active '')}")
_cpCur='[{"id":"zz","email":"zed-vless_reality_vision","flow":"xtls-rprx-vision"},{"id":"old","email":"alice"},{"id":"bb","email":"bob-x-vless_reality_vision"},{"id":"yy","email":"yan-vless_reality_vision"}]'
_cpExp=$(carpoolExpectedClients 7 "${_cpS}" "${_cpCur}")
assert_equals '["zed-vless_reality_vision","yan-vless_reality_vision","alice-vless_reality_vision","carol-vless_reality_vision"]' "$(jq -c '[.[].email]' <<<"${_cpExp}")" "期望 clients: 外部账号原序在前，成员按文件顺序在后，停用者与无 uuid 者不在"
assert_equals "${_cpU1}" "$(jq -r '.[2].id' <<<"${_cpExp}")" "期望 clients: 成员凭据来自 state，不是 inbound 里的旧值"
assert_equals '{"id":"'"${_cpU1}"'","email":"alice-vless_reality_vision","flow":"xtls-rprx-vision"}' "$(jq -c '.[2]' <<<"${_cpExp}")" "期望 clients: 7 的形状 {id,email,flow}"
assert_equals '{"id":"'"${_cpU1}"'","flow":"xtls-rprx-vision","email":"alice-VLESS_TCP/TLS_Vision"}' "$(carpoolExpectedClients 0 "${_cpS}" '[]' | jq -c '.[0]')" "期望 clients: 0 的形状 {id,flow,email}"
assert_equals '{"id":"'"${_cpU1}"'","email":"alice-VLESS_WS"}' "$(carpoolExpectedClients 1 "$(jq -c '.members.alice.protocols = [0,1,7]' <<<"${_cpS}")" '[]' | jq -c '.[0]')" "期望 clients: 1 的形状 {id,email}"
assert_equals '{"id":"'"${_cpU1}"'","email":"alice-VLESS_Reality_XHTTP"}' "$(carpoolExpectedClients 12 "${_cpS}" '[]' | jq -c '.[0]')" "期望 clients: 12 的形状 {id,email}"
assert_equals '{"id":"'"${_cpU1}"'","email":"alice-VMess_WS","alterId":0}' "$(carpoolExpectedClients 3 "$(jq -c '.members.alice.protocols = [0,3,7]' <<<"${_cpS}")" '[]' | jq -c '.[0]')" "期望 clients: 3 的形状 {id,email,alterId}"
assert_equals '{"password":"'"${_cpU1}"'","email":"alice-trojan_tcp"}' "$(carpoolExpectedClients 4 "$(jq -c '.members.alice.protocols = [0,4,7]' <<<"${_cpS}")" '[]' | jq -c '.[0]')" "期望 clients: 4 的形状 {password,email}"
assert_equals '["alice-VLESS_Reality_XHTTP"]' "$(carpoolExpectedClients 12 "${_cpS}" '[]' | jq -c '[.[].email]')" "期望 clients: 协议子集——carol 没有 12 就不进 12 的文件"
assert_equals "[]" "$(carpoolExpectedClients 4 "${_cpS}" '[]')" "期望 clients: 没人有该协议时为空数组"
assert_equals "1" "$(carpoolExpectedClients 6 "${_cpS}" '[]' >/dev/null 2>&1; echo $?)" "期望 clients: 6 不是拼车协议，返回 1"
assert_true 'carpoolClientsEqual "[{\"id\":\"a\",\"email\":\"x\"}]" "[{\"email\":\"x\",\"id\":\"a\"}]"' "carpoolClientsEqual: 键序无关"
assert_true '! carpoolClientsEqual "[{\"id\":\"a\"},{\"id\":\"b\"}]" "[{\"id\":\"b\"},{\"id\":\"a\"}]"' "carpoolClientsEqual: 元素顺序有关"
assert_true '! carpoolClientsEqual "[{\"id\":\"a\"}]" "[{\"id\":\"a\",\"flow\":\"x\"}]"' "carpoolClientsEqual: 字段多一个就不等"

# 对账载荷：只含有差异的协议；全部一致输出空
_cpMap=$(jq -cn --arg u "${_cpU1}" --arg u3 "${_cpU3}" '{
  "0": [{id: "zz", flow: "xtls-rprx-vision", email: "zed-VLESS_TCP/TLS_Vision"}, {id: $u, flow: "xtls-rprx-vision", email: "alice-VLESS_TCP/TLS_Vision"}, {id: $u3, flow: "xtls-rprx-vision", email: "carol-VLESS_TCP/TLS_Vision"}],
  "7": [{id: "zz", email: "zed-vless_reality_vision", flow: "xtls-rprx-vision"}, {id: "bb", email: "bob-x-vless_reality_vision", flow: "xtls-rprx-vision"}, {id: $u, email: "alice-vless_reality_vision", flow: "xtls-rprx-vision"}, {id: $u3, email: "carol-vless_reality_vision", flow: "xtls-rprx-vision"}],
  "12": [{id: $u, email: "alice-VLESS_Reality_XHTTP"}]}')
_cpPayload=$(carpoolReconcilePayload "${_cpS}" "${_cpMap}")
assert_equals '["7"]' "$(jq -c 'keys' <<<"${_cpPayload}")" "carpoolReconcilePayload: 只有 07 有差异（停用的 bob-x 还在里面）"
assert_equals '["zed-vless_reality_vision","alice-vless_reality_vision","carol-vless_reality_vision"]' "$(jq -c '.["7"] | [.[].email]' <<<"${_cpPayload}")" "carpoolReconcilePayload: 07 的期望值去掉 bob-x、保留外部账号 zed"
assert_equals "" "$(carpoolReconcilePayload "${_cpS}" "$(jq -c 'del(.["7"])' <<<"${_cpMap}")")" "carpoolReconcilePayload: 全部一致时输出空"
assert_equals "0" "$(carpoolReconcilePayload "${_cpS}" "$(jq -c 'del(.["7"])' <<<"${_cpMap}")" >/dev/null; echo $?)" "carpoolReconcilePayload: 全部一致时返回 0"
assert_equals "1" "$(carpoolReconcilePayload "${_cpS}" '{"6": []}' >/dev/null 2>&1; echo $?)" "carpoolReconcilePayload: 映射里出现非拼车协议返回 1"

# --- 占位订阅 ---
assert_equals "a%20b%2Fc%3F%23" "$(carpoolUrlEncode 'a b/c?#')" "carpoolUrlEncode: 保留字百分号编码"
assert_equals "A-z.~_09" "$(carpoolUrlEncode 'A-z.~_09')" "carpoolUrlEncode: unreserved 不动"
assert_equals "%E4%B8%AD" "$(carpoolUrlEncode '中')" "carpoolUrlEncode: 多字节按 UTF-8 字节编码"
_cpLink=$(carpoolPlaceholderDefault "$(carpoolReasonText quota)" | base64 -d)
assert_equals "vless://00000000-0000-0000-0000-000000000000@127.0.0.1:1?encryption=none&security=none&type=tcp#%E6%B5%81%E9%87%8F%E5%B7%B2%E7%94%A8%E5%B0%BD" "${_cpLink}" "占位 default: base64 里一条指向 127.0.0.1:1 的 vless，节点名是编码后的「流量已用尽」"
assert_equals "1" "$(carpoolPlaceholderDefault x | wc -l | tr -d ' ')" "占位 default: 单行 base64"
_cpClash=$(carpoolPlaceholderClash "$(carpoolReasonText expired)")
cp_assert_contains "${_cpClash}" $'proxies:\n  - name: "已到期"\n    type: socks5\n    server: 127.0.0.1\n    port: 1' "占位 clashMeta: socks5 指向 127.0.0.1:1，节点名是原因"
assert_equals '[{"tag":"已被车主停用","type":"socks","server":"127.0.0.1","server_port":1}]' "$(carpoolPlaceholderSingBoxProfile "$(carpoolReasonText manual)")" "占位 sing-box_profiles: 一个 socks 出站"
assert_equals "2|socks|direct" "$(carpoolPlaceholderSingBoxConfig x | jq -r '"\(.outbounds | length)|\(.outbounds[0].type)|\(.outbounds[1].type)"')" "占位 sing-box: 最小配置含该出站与 direct"
assert_equals "x" "$(carpoolReasonText x)" "carpoolReasonText: 未知原因原样返回"

# --- 文案与页面 ---
assert_equals "0 B|1 KiB|1 MiB|1.5 GiB|100 GiB" "$(printf '%s|%s|%s|%s|%s' "$(carpoolFormatBytes 0)" "$(carpoolFormatBytes 1024)" "$(carpoolFormatBytes 1048576)" "$(carpoolFormatBytes 1610612736)" "$(carpoolFormatBytes 107374182400)")" "carpoolFormatBytes: 四档"
assert_equals "alice 已停用（流量已用尽）" "$(carpoolEventText '{"type":"disabled","name":"alice","reason":"quota"}')" "carpoolEventText: 停用"
assert_equals "alice 已恢复" "$(carpoolEventText '{"type":"restored","name":"alice"}')" "carpoolEventText: 恢复"
assert_equals "alice 已用 85%（4.65 GiB / 5.58 GiB）" "$(carpoolEventText '{"type":"warn","name":"alice","percent":85,"used":5000000000,"quota":6000000000}')" "carpoolEventText: 预警"
assert_equals "alice 将于 2026-10-22 到期，还有 2 天" "$(carpoolEventText '{"type":"expiring","name":"alice","date":"2026-10-22","days":2}')" "carpoolEventText: 到期提醒"
assert_equals $'新周期开始，流量已清零；上期用量：\n  alice: 1 KiB\n  bob: 0 B' "$(carpoolEventText '{"type":"period","previous":"2026-09-01","usage":{"alice":{"up":1000,"down":24},"bob":{"up":0,"down":0}}}')" "carpoolEventText: 周期清零附上期用量"

_cpS=$(cp_state 2026-10-15 "{
  \"alice\": $(cp_member "${_cpU1}" $((100 * GiB)) 2026-12-31 '[0,7]' $((100 * GiB)) 1 disabled quota),
  \"bob-x\": $(cp_member "${_cpU2}" 0 "" '[0,7]' 5 6 active '')}")
_cpS=$(carpoolAppendEvents "${_cpS}" '[{"type":"disabled","name":"alice","reason":"quota"}]' "2026-10-31 11:55")
assert_equals $'alice\t100 GiB\t100 GiB\t2026-12-31\t流量已用尽\nbob-x\t11 B\t不限\t-\t正常' "$(carpoolUsageTable "${_cpS}")" "carpoolUsageTable: 名字 已用 配额 到期 状态"

printf '%s\n' '{"resetDay": 15, "notify": {"label": "<b>小车</b>&\"x\""}, "members": {"alice": {"quotaGiB": 100, "expire": "2026-12-31"}, "bob-x": {}}}' > "${_cpMembers}"
_cpNorm=$(carpoolNormalizeMembers "${_cpMembers}" ",0,7,")
_cpPage=$(carpoolRenderOwnerPage "${_cpS}" "${_cpNorm}" 2026-10-31 "2026-10-31 12:00" '["zed<x>"]' "")
cp_assert_contains "${_cpPage}" '<title>&lt;b&gt;小车&lt;/b&gt;&amp;&quot;x&quot;</title>' "车主页: 标题 HTML 转义"
cp_assert_contains "${_cpPage}" 'zed&lt;x&gt;' "车主页: 未纳入拼车的账号名也转义"
cp_assert_contains "${_cpPage}" '<html lang="zh-CN">' "车主页: 语言跟随服务端"
cp_assert_contains "${_cpPage}" '本周期自 2026-10-15 · 下次清零 2026-11-15' "车主页: 周期与下次清零日"
cp_assert_contains "${_cpPage}" '<tr class="disabled"><td>alice</td><td>100 GiB<div class="bar"><i class="hot" style="width:100%"></i></div></td><td>100 GiB</td><td>100%</td><td>2026-12-31</td><td>已停用 · 流量已用尽</td></tr>' "车主页: 停用成员一行"
cp_assert_contains "${_cpPage}" '<tr class="active"><td>bob-x</td><td>11 B</td><td>不限</td><td>-</td><td>-</td><td>正常</td></tr>' "车主页: 不限额成员一行"
cp_assert_contains "${_cpPage}" '<li>2026-10-31 11:55 · alice 已停用（流量已用尽）</li>' "车主页: 最近事件"
cp_assert_not_contains "${_cpPage}" "${_cpU1}" "车主页: 不含任何 UUID"
cp_assert_not_contains "${_cpPage}" '<script' "车主页: 无脚本"
cp_assert_not_contains "${_cpPage}" 'http' "车主页: 无外链"
cp_assert_not_contains "${_cpPage}" 'Proxy-agent' "车主页: 无脚本名"
_cpPage=$(carpoolRenderOwnerPage "${_cpS}" "${_cpNorm}" 2026-10-31 now '[]' '配置文件有改动未应用')
cp_assert_contains "${_cpPage}" '<p class="warn">配置文件有改动未应用</p>' "车主页: 待应用提示"
cp_assert_not_contains "${_cpPage}" '未纳入拼车的账号' "车主页: 没有外部账号就不显示那段"
assert_equals "1" "$(grep -c '<p>还没有成员</p>' <<<"$(carpoolRenderOwnerPage "$(cp_state 2026-10-01 '{}')" "${_cpNorm}" 2026-10-31 now)")" "车主页: 没有成员时的提示"
_cpPage=$(carpoolRenderMemberPage "${_cpS}" "${_cpNorm}" bob-x 2026-10-31 "2026-10-31 12:00")
cp_assert_contains "${_cpPage}" '<h1>&lt;b&gt;小车&lt;/b&gt;&amp;&quot;x&quot; · bob-x</h1>' "成员页: 标题是标签加本人名"
cp_assert_contains "${_cpPage}" '<tr><th>已用</th><td>11 B</td></tr><tr><th>配额</th><td>不限</td></tr><tr><th>到期</th><td>-</td></tr><tr><th>状态</th><td>正常</td></tr>' "成员页: 四行"
cp_assert_not_contains "${_cpPage}" 'alice' "成员页: 看不到别人"
cp_assert_not_contains "${_cpPage}" "${_cpU2}" "成员页: 不含本人 UUID"
_cpPage=$(carpoolRenderMemberPage "${_cpS}" "${_cpNorm}" alice 2026-10-31 now)
cp_assert_contains "${_cpPage}" '<td>100 GiB (100%)<div class="bar"><i class="hot" style="width:100%"></i></div></td>' "成员页: 有配额时带百分比"
assert_equals "1" "$(carpoolRenderMemberPage "${_cpS}" "${_cpNorm}" nobody 2026-10-31 now >/dev/null; echo $?)" "成员页: 不是成员返回 1"

# --- 关闭分组、清零、差异文案 ---
_cpS=$(cp_state 2026-10-01 "{
  \"a\": $(cp_member "${_cpU1}" ${GiB} "" '[0]' ${GiB} 0 disabled quota),
  \"b\": $(cp_member "${_cpU2}" ${GiB} 2026-10-19 '[0]' ${GiB} 0 disabled quota),
  \"c\": $(cp_member "${_cpU3}" 0 2026-09-01 '[0]' 1 1 disabled expired),
  \"d\": $(cp_member "44444444-4444-4444-4444-444444444444" 0 "" '[0]' 2 2 disabled manual),
  \"e\": $(cp_member "55555555-5555-5555-5555-555555555555" 0 "" '[0]' 3 3 active '')}" '{"warn:a":true,"warn:e":true,"expire:b:2026-10-19":true}')
_cpG=$(carpoolCloseGroups "${_cpS}" 2026-10-20)
assert_equals '{"restore":["a"],"expiredNow":["b"],"keepExpired":["c"],"keepManual":["d"]}' "${_cpG}" "carpoolCloseGroups: 超额未到期恢复、超额已到期翻 expired、到期与手动保持，active 不入组"
_cpClosed=$(carpoolApplyClose "${_cpS}" "${_cpG}" false)
assert_equals "active||disabled|expired|disabled|expired|disabled|manual|active|" "$(jq -r '[.members[] | .status, .reason] | join("|")' <<<"${_cpClosed}")" "carpoolApplyClose: 默认只恢复 restore 组，expiredNow 改 reason"
_cpClosed=$(carpoolApplyClose "${_cpS}" "${_cpG}" true)
assert_equals "active|disabled|active|active|active" "$(jq -r '[.members[] | .status] | join("|")' <<<"${_cpClosed}")" "carpoolApplyClose: 一并恢复时到期与手动的也放回"
assert_equals "disabled|expired" "$(jq -r '.members.b | "\(.status)|\(.reason)"' <<<"$(carpoolApplyClose "${_cpS}" "${_cpG}" true)")" "carpoolApplyClose: 一并恢复也不恢复「超额且已到期」的 b"
_cpR=$(carpoolResetUsageState "${_cpS}" a)
assert_equals "0|$((GiB))|1" "$(jq -r '"\(.members.a.upBytes)|\(.members.b.upBytes)|\(.members.c.upBytes)"' <<<"${_cpR}")" "carpoolResetUsageState: 单人清零只动那个人"
assert_equals '{"warn:e":true,"expire:b:2026-10-19":true}' "$(jq -c '.notified' <<<"${_cpR}")" "carpoolResetUsageState: 只清那个人的预警去重键"
_cpR=$(carpoolResetUsageState "${_cpS}")
assert_equals "0" "$(jq -r '[.members[] | .upBytes + .downBytes] | add' <<<"${_cpR}")" "carpoolResetUsageState: 全员清零"
assert_equals '{"expire:b:2026-10-19":true}' "$(jq -c '.notified' <<<"${_cpR}")" "carpoolResetUsageState: 全员清零清掉所有预警键、保留到期提醒键"
assert_equals "active|" "$(carpoolJudge "${_cpR}" "${_cpNotify}" 2026-10-20 2026-10-01 | jq -r '.state.members.a | "\(.status)|\(.reason)"')" "清零后判定：超额停用者恢复"

_cpD='{"added":["new1"],"removed":["gone"],"protocols":[{"name":"alice","from":[0,7],"to":[0]}],"uuid":["bob"],"quota":[{"name":"alice","from":0,"to":1073741824}],"expire":[{"name":"alice","from":"","to":"2026-12-31"}],"unmanaged":["zed"]}'
assert_true '! carpoolDiffIsEmpty "${_cpD}"' "carpoolDiffIsEmpty: 有差异"
assert_true 'carpoolDiffIsEmpty "{\"added\":[],\"removed\":[],\"protocols\":[],\"uuid\":[],\"quota\":[],\"expire\":[],\"unmanaged\":[\"zed\"]}"' "carpoolDiffIsEmpty: 只有未纳入账号不算差异"
assert_true 'carpoolDiffNeedsConfirm "${_cpD}"' "carpoolDiffNeedsConfirm: 含删除要确认"
assert_true '! carpoolDiffNeedsConfirm "{\"added\":[\"x\"],\"removed\":[],\"protocols\":[],\"uuid\":[],\"quota\":[],\"expire\":[],\"unmanaged\":[]}"' "carpoolDiffNeedsConfirm: 只新增不用确认"
assert_equals $'新增成员 new1\n删除成员 gone\nalice 的协议 [0,7] → [0]\nbob 换 UUID\nalice 的配额 不限 → 1 GiB\nalice 的到期 - → 2026-12-31\n未纳入拼车的账号（不动）: zed' "$(carpoolDiffText "${_cpD}")" "carpoolDiffText: 七类差异各一行"

# --- Telegram：配置解析、tick 级通知去重、文案 ---
_cpTg="${_cpDir}/telegram.conf"
printf 'TG_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF\nTG_CHAT_ID=-1001234567890\n' >"${_cpTg}"
assert_equals $'123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF\n-1001234567890' "$(carpoolReadTelegramConf "${_cpTg}")" "carpoolReadTelegramConf: 两行输出 token 与 chat id"
printf 'TG_BOT_TOKEN="123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF"\nTG_CHAT_ID= 42 \n' >"${_cpTg}"
assert_equals "42" "$(carpoolReadTelegramConf "${_cpTg}" | sed -n 2p)" "carpoolReadTelegramConf: 引号与空白容忍"
printf 'TG_BOT_TOKEN=nope\nTG_CHAT_ID=42\n' >"${_cpTg}"
assert_true '! carpoolReadTelegramConf "${_cpTg}" >/dev/null' "carpoolReadTelegramConf: token 格式不对返回 1"
printf 'TG_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF\nTG_CHAT_ID=abc\n' >"${_cpTg}"
assert_true '! carpoolReadTelegramConf "${_cpTg}" >/dev/null' "carpoolReadTelegramConf: chat id 不是整数返回 1"
printf 'TG_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF\n' >"${_cpTg}"
assert_true '! carpoolReadTelegramConf "${_cpTg}" >/dev/null' "carpoolReadTelegramConf: 缺 chat id 返回 1"
assert_true '! carpoolReadTelegramConf "${_cpDir}/absent.conf" >/dev/null' "carpoolReadTelegramConf: 文件缺失返回 1"

_cpS=$(cp_state 2026-10-01 "{\"alice\": $(cp_member "${_cpU1}" 0 "" '[0]' 1 2 active '')}")
_cpS=$(jq -c '.notify = {label: "车", warnPercent: 80, digestHour: 8, expireNoticeDays: 3}' <<<"${_cpS}")
_cpN=$(carpoolTickNotices "${_cpS}" 2026-10-20 7 true f1)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpN}")" "tick 通知: 一切正常、未到摘要时间 → 无事件"
_cpN=$(carpoolTickNotices "${_cpS}" 2026-10-20 8 false f1)
assert_equals '["invalid","digest"]' "$(jq -c '[.events[].type]' <<<"${_cpN}")" "tick 通知: 文件无效 + 到点摘要"
assert_equals '{"invalid:f1":true,"digest:2026-10-20":true}' "$(jq -c '.state.notified' <<<"${_cpN}")" "tick 通知: 去重键记进 notified"
_cpN2=$(carpoolTickNotices "$(jq -c '.state' <<<"${_cpN}")" 2026-10-20 9 false f1)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpN2}")" "tick 通知: 同一文件内容、同一天不再重复"
_cpN2=$(carpoolTickNotices "$(jq -c '.state' <<<"${_cpN}")" 2026-10-21 8 false f2)
assert_equals '["invalid","digest"]' "$(jq -c '[.events[].type]' <<<"${_cpN2}")" "tick 通知: 文件内容变了再提醒一次、新的一天再发摘要"
_cpN=$(carpoolTickNotices "$(jq -c '.notify.digestHour = null' <<<"${_cpS}")" 2026-10-20 23 true f1)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpN}")" "tick 通知: digestHour 为 null 不发摘要"
_cpN=$(carpoolTickNotices "$(jq -c '.collectFailures = 2' <<<"${_cpS}")" 2026-10-20 0 true f1)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpN}")" "tick 通知: 采集失败 2 次还不报"
_cpN=$(carpoolTickNotices "$(jq -c '.collectFailures = 3' <<<"${_cpS}")" 2026-10-20 0 true f1)
assert_equals '[{"type":"collectFailed","count":3}]' "$(jq -c '.events' <<<"${_cpN}")" "tick 通知: 连续 3 次报一次"
_cpN2=$(carpoolTickNotices "$(jq -c '.state | .collectFailures = 7' <<<"${_cpN}")" 2026-10-20 0 true f1)
assert_equals "[]" "$(jq -c '.events' <<<"${_cpN2}")" "tick 通知: 继续失败不重复"
_cpN2=$(carpoolTickNotices "$(jq -c '.state | .collectFailures = 0' <<<"${_cpN}")" 2026-10-20 0 true f1)
assert_equals '[{"type":"collectRecovered"}]|{}' "$(jq -c '.events' <<<"${_cpN2}")|$(jq -c '.state.notified' <<<"${_cpN2}")" "tick 通知: 恢复报一次并清键"

assert_equals "配置已应用：新增成员 x" "$(carpoolEventText '{"type":"applied","summary":"新增成员 x"}')" "carpoolEventText: applied"
assert_equals "统计采集已连续失败 3 次" "$(carpoolEventText '{"type":"collectFailed","count":3}')" "carpoolEventText: collectFailed"
assert_equals "拼车已关闭。恢复：a, b；仍停用：c" "$(carpoolEventText '{"type":"closed","restored":"a, b","kept":"c"}')" "carpoolEventText: closed"
assert_equals $'[车]\nalice 已停用（流量已用尽）\nbob 已恢复' "$(carpoolNotifyText 车 '[{"type":"disabled","name":"alice","reason":"quota"},{"type":"restored","name":"bob"}]')" "carpoolNotifyText: 标签一行 + 每事件一行"
assert_equals "" "$(carpoolNotifyText 车 '[]')" "carpoolNotifyText: 没有事件输出空"
assert_equals $'每日摘要 2026-10-20\nalice: 3 B / 不限 · 正常' "$(carpoolDigestText "${_cpS}" 2026-10-20)" "carpoolDigestText: 标题 + 每人一行"
cp_assert_not_contains "$(carpoolNotifyText 车 '[{"type":"disabled","name":"alice","reason":"quota"}]')$(carpoolDigestText "${_cpS}" 2026-10-20)" "${_cpU1}" "通知文案: 不含 UUID"
_cpEv=$(carpoolAppendEvents "${_cpS}" '[{"type":"digest","date":"x"},{"type":"collectFailed","count":3}]' now)
assert_equals '[{"time":"now","type":"collectFailed","count":3}]' "$(jq -c '.events' <<<"${_cpEv}")" "carpoolAppendEvents: 摘要不进页面事件，collectFailed 带次数"
_cpPage=$(carpoolRenderOwnerPage "${_cpEv}" "${_cpNorm}" 2026-10-31 now '[]' '')
cp_assert_contains "${_cpPage}" "<li>now · 统计采集已连续失败 3 次</li>" "车主页: 采集失败事件有文案"

# --- nginx location 块 ---
_cpBlock=$(carpoolNginxLocationBlock /srv/sub/carpool)
cp_assert_contains "${_cpBlock}" 'location ~ "^/s/carpool/([0-9a-f]{32,64})$" {' "nginx 块: 路径正则只收 32–64 位十六进制，且带引号（裸 {32,64} 会被 nginx 当块括号）"
cp_assert_contains "${_cpBlock}" 'alias /srv/sub/carpool/$1;' "nginx 块: alias 指向页面目录下的捕获名"
cp_assert_contains "${_cpBlock}" "default-src 'none'; style-src 'unsafe-inline'" "nginx 块: CSP 只放行内联样式"
cp_assert_contains "${_cpBlock}" 'X-Robots-Tag noindex' "nginx 块: 不进搜索引擎"
cp_assert_contains "${_cpBlock}" "default_type 'text/html; charset=utf-8'" "nginx 块: HTML 类型"
assert_equals "1|1" "$(printf '%s|%s' "$(grep -c '# carpool-page-begin' <<<"${_cpBlock}")" "$(grep -c '# carpool-page-end' <<<"${_cpBlock}")")" "nginx 块: 起止标记各一个"
assert_equals "1" "$(grep -c '^    }$' <<<"${_cpBlock}")" "nginx 块: 只有一层花括号，撤掉时按标记删整段不会伤到别的 location"

rm -rf "${_cpDir}"
echo ""

# ============================================================================

echo "=============================================="
echo -e "${YELLOW}测试结果汇总${NC}"
echo "=============================================="
echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}所有测试通过！${NC}"
    exit 0
else
    echo -e "${RED}有 ${TESTS_FAILED} 个测试失败！${NC}"
    exit 1
fi
