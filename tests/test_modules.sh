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
