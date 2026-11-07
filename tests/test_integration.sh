#!/usr/bin/env bash
# ============================================================================
# test_integration.sh - 集成测试：建模拟安装树测配置读取。跑法: bash tests/test_integration.sh
# ============================================================================

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0

# 模拟环境根目录
MOCK_ROOT="/tmp/proxy-agent-integration-test"

# 辅助函数
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

# 切换到项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

echo "=============================================="
echo -e "${BLUE}Proxy-agent 集成测试${NC}"
echo -e "${YELLOW}模拟 VPS 安装环境${NC}"
echo "=============================================="
echo ""

# ============================================================================
# 清理之前的测试环境
# ============================================================================

cleanup() {
    rm -rf "${MOCK_ROOT}"
}

# 注册清理函数
trap cleanup EXIT

cleanup

# ============================================================================
# 创建模拟安装环境
# ============================================================================

echo -e "${YELLOW}=== 创建模拟 VPS 环境 ===${NC}"

# 创建目录结构
mkdir -p "${MOCK_ROOT}/etc/Proxy-agent/xray/conf"
mkdir -p "${MOCK_ROOT}/etc/Proxy-agent/sing-box/conf/config"
mkdir -p "${MOCK_ROOT}/etc/Proxy-agent/tls"
mkdir -p "${MOCK_ROOT}/etc/Proxy-agent/subscribe"

# 创建模拟的 Xray 二进制文件
touch "${MOCK_ROOT}/etc/Proxy-agent/xray/xray"
chmod +x "${MOCK_ROOT}/etc/Proxy-agent/xray/xray"

# 创建模拟的 sing-box 二进制文件
touch "${MOCK_ROOT}/etc/Proxy-agent/sing-box/sing-box"
chmod +x "${MOCK_ROOT}/etc/Proxy-agent/sing-box/sing-box"

echo -e "${GREEN}✓${NC} 创建目录结构"

# ============================================================================
# 创建 Xray 配置文件
# ============================================================================

# VLESS TCP TLS Vision 配置
cat > "${MOCK_ROOT}/etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json" << 'EOF'
{
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "tag": "VLESSTCP",
            "settings": {
                "clients": [
                    {
                        "id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
                        "flow": "xtls-rprx-vision",
                        "email": "user1-VLESS_TCP"
                    },
                    {
                        "id": "b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22",
                        "flow": "xtls-rprx-vision",
                        "email": "user2-VLESS_TCP"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {"dest": 31300, "xver": 1},
                    {"alpn": "h2", "dest": 31302, "xver": 1}
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h2", "http/1.1"],
                    "certificates": [
                        {
                            "certificateFile": "/etc/Proxy-agent/tls/test.example.com.crt",
                            "keyFile": "/etc/Proxy-agent/tls/test.example.com.key"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

# VLESS WebSocket 配置
cat > "${MOCK_ROOT}/etc/Proxy-agent/xray/conf/03_VLESS_WS_inbounds.json" << 'EOF'
{
    "inbounds": [
        {
            "port": 31297,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "tag": "VLESSWS",
            "settings": {
                "clients": [
                    {
                        "id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
                        "email": "user1-VLESS_WS"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "acceptProxyProtocol": true,
                    "path": "/testpath123ws"
                }
            }
        }
    ]
}
EOF

# VLESS Reality Vision 配置
cat > "${MOCK_ROOT}/etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" << 'EOF'
{
    "inbounds": [
        {
            "port": 8443,
            "protocol": "dokodemo-door",
            "tag": "dokodemo-in-VLESSReality",
            "settings": {
                "address": "127.0.0.1",
                "port": 45987,
                "network": "tcp"
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 45987,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a33",
                        "flow": "xtls-rprx-vision",
                        "email": "user1-Reality"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "target": "www.microsoft.com:443",
                    "serverNames": ["www.microsoft.com"],
                    "privateKey": "WDrcaQ0SVSc0nh1SVrPmQsBkIjPQgXwZb8_z8L5kGGw",
                    "publicKey": "O3gPFZ1Tc0FBi0VYRzfhkEAhVPZs1_n5hH_Df3eDOT0",
                    "mldsa65Seed": "testSeed12345",
                    "mldsa65Verify": "testVerify67890",
                    "maxTimeDiff": 60000,
                    "shortIds": ["abc123", "def456"]
                }
            }
        }
    ]
}
EOF

echo -e "${GREEN}✓${NC} 创建 Xray 配置文件"

# ============================================================================
# 创建 sing-box 配置文件
# ============================================================================

# Hysteria2 配置
cat > "${MOCK_ROOT}/etc/Proxy-agent/sing-box/conf/config/06_hysteria2_inbounds.json" << 'EOF'
{
    "inbounds": [
        {
            "type": "hysteria2",
            "tag": "hysteria2-in",
            "listen_port": 8844,
            "up_mbps": 100,
            "down_mbps": 50,
            "users": [
                {
                    "password": "testpassword123"
                }
            ],
            "obfs": {
                "type": "salamander",
                "password": "obfspassword456"
            },
            "tls": {
                "enabled": true
            }
        }
    ]
}
EOF

# TUIC 配置
cat > "${MOCK_ROOT}/etc/Proxy-agent/sing-box/conf/config/09_tuic_inbounds.json" << 'EOF'
{
    "inbounds": [
        {
            "type": "tuic",
            "tag": "tuic-in",
            "listen_port": 8845,
            "congestion_control": "bbr",
            "users": [
                {
                    "uuid": "d3eebc99-9c0b-4ef8-bb6d-6bb9bd380a44",
                    "password": "tuicpass789"
                }
            ]
        }
    ]
}
EOF

# sing-box Reality Vision 配置
cat > "${MOCK_ROOT}/etc/Proxy-agent/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json" << 'EOF'
{
    "inbounds": [
        {
            "type": "vless",
            "tag": "vless-reality-in",
            "listen_port": 9443,
            "users": [
                {
                    "uuid": "e4eebc99-9c0b-4ef8-bb6d-6bb9bd380a55",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "www.google.com",
                "reality": {
                    "enabled": true,
                    "private_key": "SingboxPrivateKey123",
                    "handshake": {
                        "server": "www.google.com",
                        "server_port": 443
                    }
                }
            }
        }
    ]
}
EOF

echo -e "${GREEN}✓${NC} 创建 sing-box 配置文件"

# ============================================================================
# 创建 TLS 证书文件（空文件用于测试）
# ============================================================================

touch "${MOCK_ROOT}/etc/Proxy-agent/tls/test.example.com.crt"
touch "${MOCK_ROOT}/etc/Proxy-agent/tls/test.example.com.key"

# 创建 CDN 配置文件
echo "cdn.example.com" > "${MOCK_ROOT}/etc/Proxy-agent/cdn"

echo -e "${GREEN}✓${NC} 创建 TLS 证书和 CDN 配置"

echo ""

# ============================================================================
# 加载模块
# ============================================================================

echo -e "${YELLOW}=== 加载模块 ===${NC}"

source lib/constants.sh
source lib/utils.sh
source lib/json-utils.sh
source lib/protocol-registry.sh
source lib/system-detect.sh

# 定义测试路径变量
_TEST_V2RAY_AGENT_DIR="${MOCK_ROOT}/etc/Proxy-agent"
_TEST_XRAY_CONFIG_DIR="${_TEST_V2RAY_AGENT_DIR}/xray/conf"
_TEST_SINGBOX_CONFIG_DIR="${_TEST_V2RAY_AGENT_DIR}/sing-box/conf/config"
_TEST_TLS_CERT_DIR="${_TEST_V2RAY_AGENT_DIR}/tls"

echo -e "${GREEN}✓${NC} 模块加载完成"
echo ""

# ============================================================================
# 测试 protocol-registry 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 protocol-registry 函数 ===${NC}"

# 测试扫描已安装协议
protocols=$(scanInstalledProtocols "${_TEST_XRAY_CONFIG_DIR}")
assert_contains "${protocols}" ",0," "检测到 VLESS TCP (协议 0)"
assert_contains "${protocols}" ",1," "检测到 VLESS WS (协议 1)"
assert_contains "${protocols}" ",7," "检测到 VLESS Reality (协议 7)"

# 测试 sing-box 协议扫描
singboxProtocols=$(scanInstalledProtocols "${_TEST_SINGBOX_CONFIG_DIR}")
assert_contains "${singboxProtocols}" ",6," "检测到 Hysteria2 (协议 6)"
assert_contains "${singboxProtocols}" ",7," "检测到 sing-box Reality (协议 7)"
assert_contains "${singboxProtocols}" ",9," "检测到 TUIC (协议 9)"

# 测试获取协议配置路径
configPath=$(getProtocolConfigPath 0 "${_TEST_XRAY_CONFIG_DIR}/")
assert_equals "${_TEST_XRAY_CONFIG_DIR}/02_VLESS_TCP_inbounds.json" "${configPath}" "getProtocolConfigPath(0)"

echo ""

# ============================================================================
# 测试 TLS 证书检测
# ============================================================================

echo -e "${YELLOW}=== 测试 TLS 证书检测 ===${NC}"

# 创建测试函数
tlsCertExistsTest() {
    local domain="$1"
    [[ -f "${_TEST_TLS_CERT_DIR}/${domain}.crt" && -f "${_TEST_TLS_CERT_DIR}/${domain}.key" ]]
}

if tlsCertExistsTest "test.example.com"; then
    echo -e "${GREEN}✓${NC} TLS 证书检测: test.example.com 存在"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} TLS 证书检测: test.example.com 应该存在"
    ((TESTS_FAILED++))
fi

if ! tlsCertExistsTest "nonexistent.com"; then
    echo -e "${GREEN}✓${NC} TLS 证书检测: nonexistent.com 不存在"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} TLS 证书检测: nonexistent.com 不应该存在"
    ((TESTS_FAILED++))
fi

echo ""

# ============================================================================
# 测试 CDN 地址读取
# ============================================================================

echo -e "${YELLOW}=== 测试 CDN 配置读取 ===${NC}"

cdnAddress=$(cat "${_TEST_V2RAY_AGENT_DIR}/cdn" 2>/dev/null)
assert_equals "cdn.example.com" "${cdnAddress}" "读取 CDN 地址"

echo ""

# ============================================================================
# 测试原子写入功能
# ============================================================================

echo -e "${YELLOW}=== 测试 JSON 原子写入功能 ===${NC}"

# 创建测试文件
TEST_WRITE_FILE="${MOCK_ROOT}/test_write.json"
echo '{"test": "original"}' > "${TEST_WRITE_FILE}"

# 测试 jsonWriteFile
if jsonWriteFile "${TEST_WRITE_FILE}" '{"test": "modified", "new": "value"}'; then
    result=$(jq -r ".test" "${TEST_WRITE_FILE}")
    assert_equals "modified" "${result}" "jsonWriteFile() 写入成功"

    newValue=$(jq -r ".new" "${TEST_WRITE_FILE}")
    assert_equals "value" "${newValue}" "jsonWriteFile() 新字段存在"
else
    echo -e "${RED}✗${NC} jsonWriteFile() 失败"
    ((TESTS_FAILED++))
fi

# 测试 jsonModifyFile
if jsonModifyFile "${TEST_WRITE_FILE}" '.test = "final"' false; then
    result=$(jq -r ".test" "${TEST_WRITE_FILE}")
    assert_equals "final" "${result}" "jsonModifyFile() 修改成功"
else
    echo -e "${RED}✗${NC} jsonModifyFile() 失败"
    ((TESTS_FAILED++))
fi

# 上游 jq 出错时内容是空串：写入必须失败、原文件不动，不能落一个 0 字节的配置
assert_equals "1" "$(jsonWriteFile "${TEST_WRITE_FILE}" "" false; echo $?)" "jsonWriteFile() 拒绝空内容"
assert_equals "1" "$(jsonWriteFile "${TEST_WRITE_FILE}" '{"a": 1} {"b": 2}' false; echo $?)" "jsonWriteFile() 拒绝两个 JSON 值"
assert_equals "1" "$(jsonModifyFile "${TEST_WRITE_FILE}" 'empty' false; echo $?)" "jsonModifyFile() 拒绝空结果"
assert_equals "final" "$(jq -r '.test' "${TEST_WRITE_FILE}")" "被拒的写入没有动原文件"
: >"${MOCK_ROOT}/test_empty.json"
assert_equals "1" "$(jsonModifyFile "${MOCK_ROOT}/test_empty.json" '.a = 1' false; echo $?)" "jsonModifyFile() 拒绝 0 字节的源文件"

echo ""

# ============================================================================
# 测试 legacy allowInsecure 清理（镜像 install.sh 的 removeLegacyAllowInsecure 过滤器）
# ============================================================================

echo -e "${YELLOW}=== 测试 legacy allowInsecure 清理 ===${NC}"

STRIP_ALLOWINSECURE_FILTER='del(.outbounds[]?.streamSettings.tlsSettings.allowInsecure)'
LEGACY_SOCKS5_FILE="${MOCK_ROOT}/etc/Proxy-agent/xray/conf/socks5_outbound.json"

cat > "${LEGACY_SOCKS5_FILE}" << 'EOF'
{
    "outbounds": [
        {
            "tag": "socks5_outbound",
            "protocol": "socks",
            "settings": {
                "servers": [
                    {"address": "192.0.2.10", "port": 1080, "users": [{"user": "u1", "pass": "p1"}]}
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "upstream.example.com",
                    "alpn": ["h2", "http/1.1"],
                    "allowInsecure": true
                }
            }
        }
    ]
}
EOF

if jsonModifyFile "${LEGACY_SOCKS5_FILE}" "${STRIP_ALLOWINSECURE_FILTER}" false; then
    result=$(jq -r '.outbounds[0].streamSettings.tlsSettings | has("allowInsecure")' "${LEGACY_SOCKS5_FILE}")
    assert_equals "false" "${result}" "allowInsecure 字段已剥离"

    result=$(jq -r '.outbounds[0].streamSettings.tlsSettings.serverName' "${LEGACY_SOCKS5_FILE}")
    assert_equals "upstream.example.com" "${result}" "serverName 字段保留"

    result=$(jq -r '.outbounds[0].settings.servers[0].address' "${LEGACY_SOCKS5_FILE}")
    assert_equals "192.0.2.10" "${result}" "上游 socks5 服务器配置保留"

    result=$(jq -r '.outbounds[0].streamSettings.security' "${LEGACY_SOCKS5_FILE}")
    assert_equals "tls" "${result}" "TLS 传输配置保留"
else
    echo -e "${RED}✗${NC} legacy allowInsecure 清理失败"
    ((TESTS_FAILED++))
fi

# 无 allowInsecure 的旧文件（纯 socks 出站）应原样保留
cat > "${LEGACY_SOCKS5_FILE}" << 'EOF'
{"outbounds": [{"tag": "socks5_outbound", "protocol": "socks", "settings": {"servers": [{"address": "192.0.2.11", "port": 1080}]}}]}
EOF
beforeStrip=$(jq -c -S . "${LEGACY_SOCKS5_FILE}")
if jsonModifyFile "${LEGACY_SOCKS5_FILE}" "${STRIP_ALLOWINSECURE_FILTER}" false; then
    afterStrip=$(jq -c -S . "${LEGACY_SOCKS5_FILE}")
    assert_equals "${beforeStrip}" "${afterStrip}" "无 allowInsecure 的文件保持不变"
else
    echo -e "${RED}✗${NC} 纯 socks 出站文件处理失败"
    ((TESTS_FAILED++))
fi

rm -f "${LEGACY_SOCKS5_FILE}"

echo ""

# ============================================================================
# 测试 Reality minClientVer 补齐（镜像 install.sh ensureRealityMinClientVer 的 jq）
# 缺则补、有则留、非 Reality 入站不动
# ============================================================================

echo -e "${YELLOW}=== 测试 Reality minClientVer 补齐 ===${NC}"

MINVER_FILE="${MOCK_ROOT}/etc/Proxy-agent/xray/conf/07_minver_test.json"
cat > "${MINVER_FILE}" <<'EOF'
{"inbounds":[{"tag":"dokodemo","protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}},{"tag":"reality","protocol":"vless","streamSettings":{"security":"reality","realitySettings":{"maxTimeDiff":60000}}},{"tag":"kept","protocol":"vless","streamSettings":{"security":"reality","realitySettings":{"minClientVer":"26.3.27"}}}]}
EOF
MINVER_DETECT='[.inbounds[]? | (.streamSettings.realitySettings | type) == "object" and (.streamSettings.realitySettings | has("minClientVer") | not)] | any'
MINVER_FILTER='.inbounds |= map(if (.streamSettings.realitySettings | type) == "object" and (.streamSettings.realitySettings | has("minClientVer") | not) then .streamSettings.realitySettings.minClientVer = "1.8.0" else . end)'
assert_equals "true" "$(jq -r "${MINVER_DETECT}" "${MINVER_FILE}")" "minClientVer 检测：缺字段的 Reality 入站命中"
if jsonModifyFile "${MINVER_FILE}" "${MINVER_FILTER}" false; then
    assert_equals "1.8.0" "$(jq -r '.inbounds[1].streamSettings.realitySettings.minClientVer' "${MINVER_FILE}")" "minClientVer 补齐：缺字段的入站补成 1.8.0"
    assert_equals "26.3.27" "$(jq -r '.inbounds[2].streamSettings.realitySettings.minClientVer' "${MINVER_FILE}")" "minClientVer 补齐：已有值不改"
    assert_equals "false" "$(jq -r '.inbounds[0] | has("streamSettings")' "${MINVER_FILE}")" "minClientVer 补齐：非 Reality 入站不动"
    assert_equals "false" "$(jq -r "${MINVER_DETECT}" "${MINVER_FILE}")" "minClientVer 检测：补齐后不再命中"
else
    echo -e "${RED}✗${NC} minClientVer 补齐失败"
    ((TESTS_FAILED++))
fi
rm -f "${MINVER_FILE}"
# 原文执行两个启动前的补写：xray/conf 里不留 .json.bak.*（-confdir 不读它们，只是越堆越多）
MINVER_ROOT="${MOCK_ROOT}/minver.root"
rm -rf "${MINVER_ROOT}" && mkdir -p "${MINVER_ROOT}/xray/conf"
printf '%s\n' '{"inbounds":[{"streamSettings":{"security":"reality","realitySettings":{}}}]}' >"${MINVER_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{"outbounds":[{"streamSettings":{"tlsSettings":{"allowInsecure":true}}}]}' >"${MINVER_ROOT}/xray/conf/socks5_outbound.json"
env PROXY_AGENT_DIR="${MINVER_ROOT}" MINVER_FNS="$(sed -n '/^removeLegacyAllowInsecure() {/,/^}/p;/^ensureRealityMinClientVer() {/,/^}/p' install.sh)" bash -c '
    source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh
    eval "${MINVER_FNS}"
    removeLegacyAllowInsecure; ensureRealityMinClientVer' >/dev/null 2>&1
assert_equals "1.8.0|false" "$(jq -r '.inbounds[0].streamSettings.realitySettings.minClientVer' "${MINVER_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")|$(jq -r '.outbounds[0].streamSettings.tlsSettings | has("allowInsecure")' "${MINVER_ROOT}/xray/conf/socks5_outbound.json")" \
    "启动前补写（原文）：minClientVer 补上、allowInsecure 剥掉"
assert_equals "" "$(ls "${MINVER_ROOT}/xray/conf" | grep '\.bak')" "启动前补写：xray/conf 里不留 .bak 文件"
rm -rf "${MINVER_ROOT}"

# 直连出站的地址策略：缺一个地址族才改，只改恰好是 UseIP 的（原文执行，路由探测桩掉）
DS_ROOT="${MOCK_ROOT}/direct-strategy.root"
DS_FN=$(sed -n '/^ensureXrayDirectStrategy() {/,/^}/p' install.sh)
assert_not_empty "${DS_FN}" "抽到 ensureXrayDirectStrategy 原文"
# run_ds 有v4 有v6 初始策略 → 跑一次，打印结果策略|退出码|提示行数（初始策略为 none 时不建文件）
run_ds() {
    rm -rf "${DS_ROOT}" && mkdir -p "${DS_ROOT}/xray/conf"
    [[ "$3" == none ]] || jq -n --arg s "$3" '{outbounds: [{protocol: "freedom", settings: {domainStrategy: $s}, tag: "z_direct_outbound"}]}' >"${DS_ROOT}/xray/conf/z_direct_outbound.json"
    env PROXY_AGENT_DIR="${DS_ROOT}" DS_FN="${DS_FN}" DS_V4="$1" DS_V6="$2" V2RAY_LANG=en bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh
        echoContent() { printf "%s\n" "$2"; }
        hostHasRouteTo() { if [[ "$1" == *:* ]]; then [[ "${DS_V6}" == yes ]]; else [[ "${DS_V4}" == yes ]]; fi; }
        eval "${DS_FN}"
        out=$(ensureXrayDirectStrategy); rc=$?
        s=$(jq -r ".outbounds[0].settings.domainStrategy" "${XRAY_CONF_DIR}/z_direct_outbound.json" 2>/dev/null)
        printf "%s|%s|%s\n" "${s:-none}" "${rc}" "$(grep -c . <<<"${out}")"'
}
assert_equals "UseIPv4v6|0|1" "$(run_ds yes no UseIP)" "直连策略：没有 IPv6 路由改成先 IPv4，并提示一次"
assert_equals "UseIPv6v4|0|1" "$(run_ds no yes UseIP)" "直连策略：没有 IPv4 路由改成先 IPv6（纯 IPv6 + NAT64 不能选到 IPv4）"
assert_equals "UseIP|0|0" "$(run_ds yes yes UseIP)" "直连策略：双栈不动"
assert_equals "UseIP|0|0" "$(run_ds no no UseIP)" "直连策略：两边都探不到（断网或 bash 没有 /dev/udp）不动"
assert_equals "AsIs|0|0" "$(run_ds yes no AsIs)" "直连策略：手改过的值不动"
assert_equals "ForceIPv6|0|0" "$(run_ds yes no ForceIPv6)" "直连策略：没有 IPv6 也不动手改的 ForceIPv6"
assert_equals "UseIPv4v6|0|0" "$(run_ds no yes UseIPv4v6)" "直连策略：改过一次之后不再翻回去，也不再提示"
assert_equals "none|0|0" "$(run_ds yes no none)" "直连策略：WARP / IPv6 全局删掉了直连出站时不新建"
run_ds yes no UseIP >/dev/null
assert_equals "" "$(ls "${DS_ROOT}/xray/conf" | grep -v '^z_direct_outbound.json$')" "直连策略：改写后 xray/conf 里不留备份与临时文件"
assert_equals "freedom|z_direct_outbound" "$(jq -r '.outbounds[0] | "\(.protocol)|\(.tag)"' "${DS_ROOT}/xray/conf/z_direct_outbound.json")" "直连策略：出站的其余字段不动"
assert_contains "$(sed -n '/^handleXray() {/,/^}/p' install.sh)" "ensureXrayDirectStrategy" "handleXray start 前挂了直连策略修正（存量机器靠它补上）"
rm -rf "${DS_ROOT}"

echo ""

# ============================================================================
# 测试账户删除过滤器语义（镜像 applyAccountChangeAllProtocols 的 delName 过滤器）
# 回归背景：按下标删假定所有协议文件的用户顺序一致；按名字删对每个文件独立匹配，
# 名字是去掉最后一段协议后缀的账户名，三种文件形态（.users / .settings.clients / Reality 07）都要真的删掉
# ============================================================================

echo -e "${YELLOW}=== 测试按名字删除用户的过滤器语义 ===${NC}"

# 与 install.sh 同一条过滤器：$f 是 registry 给的名字字段，$key 是去掉协议后缀的账户名
delete_by_name() {
    jq --arg f "$2" --arg key "$3" "$1"' |= map(select(((.[$f] // "") | sub("-[^-]*$"; "")) != $key))' "${REMOVE_USER_TMP}"
}
REMOVE_USER_TMP="${MOCK_ROOT}/remove_user_semantics.json"

# sing-box 形态（.users，名字段 name）
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"type": "vless", "users": [{"uuid": "u-aaa", "name": "alice-VLESS_WS"}, {"uuid": "u-bbb", "name": "bob-VLESS_WS"}]}]}
EOF
assert_equals "u-bbb" "$(delete_by_name '.inbounds[0].users' name alice | jq -r '[.inbounds[0].users[].uuid] | join(",")')" "sing-box .users 形态：按名字删掉 alice，只剩 bob"
assert_equals "u-aaa,u-bbb" "$(delete_by_name '.inbounds[0].users' name alic | jq -r '[.inbounds[0].users[].uuid] | join(",")')" "按名字删：名字是整段比较，前缀 alic 删不掉 alice"

# Xray 形态（.settings.clients，名字段 email；后缀里带 / 也只剥最后一个 - 之后）
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"protocol": "vless", "settings": {"clients": [{"id": "u-ccc", "email": "carol-VLESS_TCP/TLS_Vision"}, {"id": "u-ddd", "email": "dave-VLESS_TCP/TLS_Vision"}]}}]}
EOF
assert_equals "u-ccc" "$(delete_by_name '.inbounds[0].settings.clients' email dave | jq -r '[.inbounds[0].settings.clients[].id] | join(",")')" "Xray .settings.clients 形态：按名字删掉 dave，保留 carol"

# Xray Reality 07 形态（clients 在 inbounds[1]），inbounds[0] 的 dokodemo 不动
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"port": 443, "protocol": "dokodemo-door", "settings": {}}, {"protocol": "vless", "settings": {"clients": [{"id": "u-eee", "email": "erin-vless_reality_vision"}, {"id": "u-fff", "email": "frank-vless_reality_vision"}]}}]}
EOF
assert_equals "u-fff" "$(delete_by_name '.inbounds[1].settings.clients' email erin | jq -r '[.inbounds[1].settings.clients[].id] | join(",")')" "Reality 07 形态：inbounds[1] 里按名字删掉 erin"
assert_equals "dokodemo-door" "$(delete_by_name '.inbounds[1].settings.clients' email erin | jq -r '.inbounds[0].protocol')" "Reality 07 形态：inbounds[0] 的 dokodemo 分发器不受影响"
assert_equals "false" "$(delete_by_name '.inbounds[1].settings.clients' email erin | jq -r '.inbounds[0].settings | has("clients")')" "Reality 07 形态：dokodemo 的 settings 不长出 clients"

# 默认名是 UUID：两侧都只剥最后一段，带后缀的名剥掉后缀得完整 UUID，裸 UUID 名剥掉自己的末段——
# 各自都能匹配自己（removeUser 从前置文件取名时用同一剥法），不带连字符的名字不受波及
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"protocol": "vless", "settings": {"clients": [{"id": "u-ggg", "email": "3fa85f64-5717-4562-b3fc-2c963f66afa6-VLESS_WS"}, {"id": "u-hhh", "email": "3fa85f64-5717-4562-b3fc-2c963f66afa6"}, {"id": "u-iii", "email": "noone"}]}}]}
EOF
assert_equals "u-hhh,u-iii" "$(delete_by_name '.inbounds[0].settings.clients' email 3fa85f64-5717-4562-b3fc-2c963f66afa6 | jq -r '[.inbounds[0].settings.clients[].id] | join(",")')" "按名字删：带后缀的 UUID 名，键是完整 UUID，只删它自己"
assert_equals "u-ggg,u-iii" "$(delete_by_name '.inbounds[0].settings.clients' email 3fa85f64-5717-4562-b3fc | jq -r '[.inbounds[0].settings.clients[].id] | join(",")')" "按名字删：裸 UUID 名，键是剥掉末段的 UUID，自己仍匹配自己"

# naive fronting 的名字段是 username
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"type": "naive", "users": [{"username": "ivy-singbox_naive", "password": "u-iii"}, {"username": "jon-singbox_naive", "password": "u-jjj"}]}]}
EOF
assert_equals "jon-singbox_naive" "$(delete_by_name '.inbounds[0].users' username ivy | jq -r '.inbounds[0].users[].username')" "注册表列表(2,10)：按 username 删掉 ivy"

# add 侧不变：整组替换落在 registry 给的路径
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"port": 443, "protocol": "dokodemo-door", "settings": {}}, {"protocol": "vless", "settings": {"clients": [{"id": "u-eee", "email": "erin-vless_reality_vision"}]}}]}
EOF
result=$(jq --argjson newClients '[{"id":"u-new","email":"new-vless_reality_vision"}]' '.inbounds[1].settings.clients = $newClients' "${REMOVE_USER_TMP}" | jq -r '.inbounds[1].settings.clients[0].id')
assert_equals "u-new" "${result}" "注册表 add(1,7)：整组替换落在 inbounds[1]"
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"type": "vless", "users": [{"uuid": "u-ggg", "name": "gina-VLESS_WS"}]}]}
EOF
result=$(jq --argjson newClients '[{"uuid":"u-1","name":"a"},{"uuid":"u-2","name":"b"},{"uuid":"u-3","name":"c"}]' '.inbounds[0].users = $newClients' "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].users | length')
assert_equals "3" "${result}" "注册表 add(2,*)：整组替换落在 .users"

rm -f "${REMOVE_USER_TMP}"

echo ""

# ============================================================================
# addCorePort 的删除匹配（抽 install.sh 原文执行，不抄副本）
# ============================================================================

echo -e "${BLUE}[addCorePort] 端口文件删除与编号选择${NC}"

# 「删同端口旧配置」收在 removeCorePortFiles 一处，加端口与删除菜单都调它
REMOVE_PORT_FILES_FN=$(sed -n '/^removeCorePortFiles() {/,/^}/p' install.sh)
assert_not_empty "${REMOVE_PORT_FILES_FN}" "addCorePort：抽到 removeCorePortFiles"
eval "${REMOVE_PORT_FILES_FN}"

# 端口 80 不得波及 8080，端口 2 不得波及 02_/12_ 核心 inbound 片段
run_add_port_delete() {
    local targetPort="$1" dir="$2"
    rm -rf "${dir}" && mkdir -p "${dir}"
    : >"${dir}/02_VLESS_TCP_inbounds.json"
    : >"${dir}/12_VLESS_XHTTP_inbounds.json"
    : >"${dir}/02_dokodemodoor_inbounds_80.json"
    : >"${dir}/02_dokodemodoor_inbounds_hysteria_80.json"
    : >"${dir}/02_dokodemodoor_inbounds_8080.json"
    local configPath="${dir}/"
    removeCorePortFiles "${targetPort}"
}

ADD_PORT_DIR="${MOCK_ROOT}/addcoreport/conf"

run_add_port_delete 80 "${ADD_PORT_DIR}"
assert_equals "absent" "$([[ -f "${ADD_PORT_DIR}/02_dokodemodoor_inbounds_80.json" ]] && echo present || echo absent)" \
    "addCorePort(80)：删掉本端口的 dokodemodoor 片段"
assert_equals "absent" "$([[ -f "${ADD_PORT_DIR}/02_dokodemodoor_inbounds_hysteria_80.json" ]] && echo present || echo absent)" \
    "addCorePort(80)：删掉本端口的 hysteria 片段"
assert_equals "present" "$([[ -f "${ADD_PORT_DIR}/02_dokodemodoor_inbounds_8080.json" ]] && echo present || echo absent)" \
    "addCorePort(80)：8080 的片段不被子串匹配删掉"

run_add_port_delete 2 "${ADD_PORT_DIR}"
assert_equals "present" "$([[ -f "${ADD_PORT_DIR}/02_VLESS_TCP_inbounds.json" ]] && echo present || echo absent)" \
    "addCorePort(2)：02_VLESS_TCP_inbounds.json 不被删"
assert_equals "present" "$([[ -f "${ADD_PORT_DIR}/12_VLESS_XHTTP_inbounds.json" ]] && echo present || echo absent)" \
    "addCorePort(2)：12_VLESS_XHTTP_inbounds.json 不被删"

# 附加端口跟着主端口：Xray 启动前改指当前的主端口（装了 0 是它，只有 Reality 是 Reality 对外那端），Hysteria2 那份指 Hysteria2
CPT_FNS=$(sed -n '/^corePortTarget() {/,/^}/p; /^ensureCorePortTargets() {/,/^}/p' install.sh)
CPT_ROOT="${MOCK_ROOT}/coreporttarget.root"
run_cpt() (
    env PROXY_AGENT_DIR="${CPT_ROOT}" CPT_FNS="${CPT_FNS}" bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh
        eval "${CPT_FNS}"
        eval "$1"' _ "$1"
)
cpt_doko() { jq -cn --argjson l "$2" --argjson t "$3" '{inbounds: [{listen: "0.0.0.0", port: $l, protocol: "dokodemo-door", settings: {address: "127.0.0.1", port: $t, network: "tcp"}}]}' >"${CPT_ROOT}/xray/conf/$1"; }
cpt_target() { jq -r '.inbounds[0].settings.port' "${CPT_ROOT}/xray/conf/$1"; }
rm -rf "${CPT_ROOT}" && mkdir -p "${CPT_ROOT}/xray/conf" "${CPT_ROOT}/sing-box/conf/config"
printf '%s\n' '{"inbounds":[{"tag":"dokodemo-in-VLESSReality","port":2053,"protocol":"dokodemo-door"},{"port":45987,"protocol":"vless"}]}' >"${CPT_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
cpt_doko 02_dokodemodoor_inbounds_2087.json 2087 443
cpt_doko 02_dokodemodoor_inbounds_hysteria_2087.json 2087 30000
run_cpt 'ensureCorePortTargets' >/dev/null 2>&1
assert_equals "2053" "$(cpt_target 02_dokodemodoor_inbounds_2087.json)" "附加端口（只有 Reality）：主端口从 443 换到 2053 后，2087 改指 2053，不再转进没人听的 443"
assert_equals "30000" "$(cpt_target 02_dokodemodoor_inbounds_hysteria_2087.json)" "附加端口：没装 Hysteria2 时 Hysteria2 那份不动"
printf '%s\n' '{"inbounds":[{"port":8443,"protocol":"vless"}]}' >"${CPT_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
printf '%s\n' '{"inbounds":[{"type":"hysteria2","listen_port":41000}]}' >"${CPT_ROOT}/sing-box/conf/config/06_hysteria2_inbounds.json"
cpt_doko 02_dokodemodoor_inbounds_2053_default.json 2053 443
run_cpt 'ensureCorePortTargets' >/dev/null 2>&1
assert_equals "8443|8443|41000" "$(cpt_target 02_dokodemodoor_inbounds_2087.json)|$(cpt_target 02_dokodemodoor_inbounds_2053_default.json)|$(cpt_target 02_dokodemodoor_inbounds_hysteria_2087.json)" \
    "附加端口（装了 0）：都改指 0 的前置端口 8443（1 / 3 / 4 从它回落），带 _default 的也一样；Hysteria2 那份指 Hysteria2 的 41000"
cpt_doko 02_dokodemodoor_inbounds_8443.json 8443 443
run_cpt 'ensureCorePortTargets' >/dev/null 2>&1
assert_equals "443" "$(cpt_target 02_dokodemodoor_inbounds_8443.json)" "附加端口：自己就是主端口的不改，免得转回自己"
assert_equals "8443" "$(run_cpt 'corePortTarget')" "corePortTarget：装了 0 取 0 的端口"
rm -f "${CPT_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" "${CPT_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
assert_equals "1" "$(run_cpt 'corePortTarget' >/dev/null 2>&1; echo $?)" "corePortTarget：0 与 7 都没有时返回 1（addCorePort 回落 443，启动前的钩子什么都不改）"
assert_contains "$(sed -n '/^handleXray() {/,/^}/p' install.sh)" "ensureCorePortTargets" "handleXray start 前挂了附加端口改指"
assert_contains "$(sed -n '/^addCorePort() {/,/^}/p' install.sh)" 'settingsPort=$(corePortTarget)' "addCorePort：新加的端口按同一个取法定目标（装了 Reality 时不再写死 443）"
rm -rf "${CPT_ROOT}"

# 一键无域名 Reality（菜单 19）：会删掉别的协议时先列出来要 y；什么都不删就不问
RQ_FNS=$(sed -n '/^realityQuickDropped() {/,/^}/p; /^realityQuickConfirm() {/,/^}/p' install.sh)
RQ_ROOT="${MOCK_ROOT}/realityquick.root"
run_rq() (
    env PROXY_AGENT_DIR="${RQ_ROOT}" RQ_FNS="${RQ_FNS}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/protocol-registry.sh
        eval "${RQ_FNS}"
        eval "$1"' _ "$1"
)
rq_files() { local d=$1; shift; for f in "$@"; do : >"${RQ_ROOT}/${d}/${f}_inbounds.json"; done; }
rm -rf "${RQ_ROOT}" && mkdir -p "${RQ_ROOT}/xray/conf" "${RQ_ROOT}/sing-box/conf/config"
rq_files xray/conf 02_VLESS_TCP 03_VLESS_WS 07_VLESS_vision_reality 12_VLESS_XHTTP
rq_files sing-box/conf/config 06_hysteria2
assert_equals "0 1 12" "$(run_rq 'coreKind=1; realityQuickDropped 1' | paste -sd' ' -)" "一键 Reality（Xray 上装 Xray）：删 7 以外的 Xray 协议，旁挂的 6 留着"
assert_equals "0 1 6 12" "$(run_rq 'coreKind=1; realityQuickDropped 2' | paste -sd' ' -)" "一键 Reality（Xray 上装 sing-box）：Xray 整份删，旁挂的 6 也被只装 7 的 sing-box 配置删掉"
_out=$(printf 'n\n' | run_rq 'coreKind=1; realityQuickConfirm 1; echo continued' 2>&1)
assert_contains "${_out}" "VLESS+TCP[TLS_Vision], VLESS+WS[TLS], VLESS+Reality+XHTTP" "一键 Reality：开工前列出会删掉的协议"
assert_equals "0" "$(grep -c continued <<<"${_out}")" "一键 Reality：答 n 就退出，什么都不动"
assert_contains "$(printf 'y\n' | run_rq 'coreKind=1; realityQuickConfirm 1; echo continued' 2>&1)" "continued" "一键 Reality：答 y 才往下装"
rm -f "${RQ_ROOT}"/xray/conf/0[23]_* "${RQ_ROOT}/xray/conf/12_VLESS_XHTTP_inbounds.json"
assert_equals "continued" "$(run_rq 'coreKind=1; realityQuickConfirm 1 </dev/null; echo continued' 2>&1)" "一键 Reality：只有 7（或全新机器）时不问"
rm -rf "${RQ_ROOT}"

# 换默认端口时清旧 _default 片段：只认 dokodemo-door 那份，别的带 default 的文件名不动
ADD_PORT_CLEAR_DEFAULT_LINE=$(grep -F -m1 'find "${configPath}" -maxdepth 1 -type f -name' install.sh)
assert_not_empty "${ADD_PORT_CLEAR_DEFAULT_LINE}" "addCorePort：抽到清旧默认端口片段的语句"
rm -rf "${ADD_PORT_DIR}" && mkdir -p "${ADD_PORT_DIR}"
: >"${ADD_PORT_DIR}/02_dokodemodoor_inbounds_443_default.json"
: >"${ADD_PORT_DIR}/02_dokodemodoor_inbounds_2053.json"
: >"${ADD_PORT_DIR}/default_settings.json"
( configPath="${ADD_PORT_DIR}/"; eval "${ADD_PORT_CLEAR_DEFAULT_LINE}" )
assert_equals "absent" "$([[ -f "${ADD_PORT_DIR}/02_dokodemodoor_inbounds_443_default.json" ]] && echo present || echo absent)" \
    "addCorePort：旧默认端口片段被清掉"
assert_equals "present" "$([[ -f "${ADD_PORT_DIR}/02_dokodemodoor_inbounds_2053.json" ]] && echo present || echo absent)" \
    "addCorePort：非默认端口片段不动"
assert_equals "present" "$([[ -f "${ADD_PORT_DIR}/default_settings.json" ]] && echo present || echo absent)" \
    "addCorePort：文件名含 default 的其他文件不被通配误删"

# 删除菜单的编号选择：整列比较，编号 1 不得同时命中 11
ADD_PORT_SELECT_LINE=$(grep -F 'dokoConfig=$(find' install.sh)
assert_not_empty "${ADD_PORT_SELECT_LINE}" "addCorePort：抽到删除菜单的编号选择语句"

rm -rf "${ADD_PORT_DIR}" && mkdir -p "${ADD_PORT_DIR}"
for _p in 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011; do
    : >"${ADD_PORT_DIR}/02_dokodemodoor_inbounds_${_p}.json"
done
select_add_port() {
    local configPath="${ADD_PORT_DIR}/" portIndex="$1" dokoConfig
    eval "${ADD_PORT_SELECT_LINE}"
    printf '%s\n' "${dokoConfig}"
}
assert_equals "1" "$(select_add_port 1 | grep -c .)" \
    "addCorePort：11 个端口下编号 1 只选中一行"
assert_equals "1" "$(select_add_port 1 | grep -c '^1:')" \
    "addCorePort：编号 1 选中的正是第 1 行"
assert_equals "1" "$(select_add_port 11 | grep -c '^11:')" \
    "addCorePort：编号 11 选中的正是第 11 行"
assert_equals "0" "$(select_add_port 99 | grep -c .)" \
    "addCorePort：越界编号选不中任何行"

# 删除菜单选中「默认端口」那条：真实文件带 _default 后缀，删完清单不得再含它
ADD_PORT_LIST_LINE=$(grep -F -m1 'find ${configPath} -name "*dokodemodoor*"' install.sh)
assert_not_empty "${ADD_PORT_LIST_LINE}" "addCorePort：抽到端口清单语句"
ADD_PORT_REMOVE_BLOCK=$(awk -v marker='-n "${dokoConfig}"' '
    /^addCorePort/ { inFn = 1 }
    inFn && index($0, marker) { grab = 1; next }
    grab && /reloadCore/ { exit }
    grab { print }
' install.sh)
assert_not_empty "${ADD_PORT_REMOVE_BLOCK}" "addCorePort：抽到删除菜单的删文件块"

rm -rf "${ADD_PORT_DIR}" && mkdir -p "${ADD_PORT_DIR}"
: >"${ADD_PORT_DIR}/02_dokodemodoor_inbounds_443_default.json"
: >"${ADD_PORT_DIR}/02_dokodemodoor_inbounds_2053.json"
list_add_ports() {
    local configPath="${ADD_PORT_DIR}/"
    eval "${ADD_PORT_LIST_LINE}"
}
delete_add_port() {
    local configPath="${ADD_PORT_DIR}/" portIndex="$1" dokoConfig
    eval "${ADD_PORT_SELECT_LINE}"
    eval "${ADD_PORT_REMOVE_BLOCK}"
}
delete_add_port "$(list_add_ports | awk -F ':' '$2 == 443 { print $1 }')"
assert_equals "0" "$(list_add_ports | grep -c ':443$')" \
    "addCorePort：删掉默认端口那条后清单不再含它"
assert_equals "1" "$(list_add_ports | grep -c ':2053$')" \
    "addCorePort：删默认端口不波及其他端口"

rm -rf "${MOCK_ROOT}/addcoreport"

echo ""

# ============================================================================
# sing-box inbound 模板 ↔ registry：tag 列与 certificate_path 列不能各说各话
# ============================================================================

echo -e "${BLUE}[initSingBoxConfig] 模板 tag / 证书引用与 registry 交叉钉${NC}"

# 抽 initSingBoxConfig 里写 NN_xxx_inbounds.json 的 heredoc，一块一行：文件名|tag|有无证书。
# 任何 heredoc（不论重定向写在 << 前后、定界符带不带引号）都跳过到定界符为止，函数只在 heredoc 外的顶格 } 结束
SINGBOX_TEMPLATE_ROWS=$(awk '
    /^initSingBoxConfig\(\)/ { inFn = 1; next }
    !inFn { next }
    delim != "" {
        line = $0; if (dash) sub(/^\t+/, "", line)
        if (line == delim) { if (name != "") print name "|" tag "|" cert; delim = ""; next }
        if (/"tag"/) { t = $0; sub(/.*"tag"[ ]*:[ ]*"/, "", t); sub(/".*/, "", t); tag = t }
        if (/certificate_path/) cert = "yes"
        next
    }
    /^}/ { exit }
    match($0, /<<-?[ ]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) && substr($0, RSTART + 2, 1) != "<" {
        delim = substr($0, RSTART + 2, RLENGTH - 2); dash = sub(/^-/, "", delim)
        sub(/^[ ]*/, "", delim); gsub(/["\047]/, "", delim)
        name = ""; tag = ""; cert = "no"
        if (match($0, /[0-9][0-9]_[A-Za-z0-9_]+_inbounds\.json/)) name = substr($0, RSTART, RLENGTH)
    }
' install.sh)
assert_not_empty "${SINGBOX_TEMPLATE_ROWS}" "initSingBoxConfig：抽到 inbound 模板块"

# 应有的模板全集独立写死（加协议时同步）：抽漏一块就对不上，不能靠「至少抽到一块」放行。
# 6 与 16 不是 heredoc，由 jq -n 生成，下面把它们的输出拼成同样一行参加交叉钉
SINGBOX_TEMPLATE_WANT=$(for _pid in 0 1 3 4 7 9 10 11 13 14; do getProtocolConfigFileName "${_pid}"; done | sort)
assert_equals "${SINGBOX_TEMPLATE_WANT}" "$(cut -d'|' -f1 <<< "${SINGBOX_TEMPLATE_ROWS}" | sort)" \
    "initSingBoxConfig：抽到的 heredoc 模板恰好是除 6、16 以外每个 sing-box 协议各一块"
HY2_FN=$(sed -n '/^hysteria2InboundJson() {/,/^}/p' install.sh)
assert_not_empty "${HY2_FN}" "hysteria2InboundJson：抽到函数原文"
_hy2Row=$(eval "${HY2_FN}"; hysteria2InboundJson 443 '[]' example.com '' '' '' '' '' |
    jq -r '.inbounds[0] | "\(.tag)|\(if .tls.certificate_path then "yes" else "no" end)"')
SINGBOX_TEMPLATE_ROWS+=$'\n'"$(getProtocolConfigFileName 6)|${_hy2Row}"
ST_TPL_FN=$(sed -n '/^shadowTlsInbound() {/,/^}/p' install.sh)
assert_not_empty "${ST_TPL_FN}" "shadowTlsInbound：抽到函数原文"
_stRow=$(eval "${ST_TPL_FN}"; shadowTlsInbound 443 example.com key '[]' |
    jq -r '.inbounds[0] | "\(.tag)|\(if .tls.certificate_path then "yes" else "no" end)"')
SINGBOX_TEMPLATE_ROWS+=$'\n'"$(getProtocolConfigFileName 16)|${_stRow}"

while IFS='|' read -r _tplName _tplTag _tplCert; do
    [[ -z "${_tplName}" ]] && continue
    _tplId=$(parseProtocolIdFromFileName "${_tplName}")
    assert_equals "$(getProtocolInboundTag "${_tplId}")" "${_tplTag}" \
        "模板 ${_tplName} 的 tag 等于 getProtocolInboundTag(${_tplId})"
    if [[ "${_tplCert}" == "yes" ]]; then
        assert_equals "0" "$(protocolRequiresTLS "${_tplId}"; echo $?)" \
            "模板 ${_tplName} 引用 tls/ 证书 ⇒ protocolRequiresTLS(${_tplId})"
    fi
done <<< "${SINGBOX_TEMPLATE_ROWS}"

echo ""

echo -e "${BLUE}[Hysteria2] 入站片段与读回${NC}"

hy2_json() ( eval "${HY2_FN}"; hysteria2InboundJson "$@" )
_hy2Bbr=$(hy2_json 443 '[{"name":"a","password":"p"}]' example.com '' '' '' '' /usr/share/nginx/html)
assert_equals "true" "$(jq '.inbounds[0].ignore_client_bandwidth' <<<"${_hy2Bbr}")" \
    "Hysteria2：不填带宽即 BBR，ignore_client_bandwidth 让客户端也走 BBR"
assert_equals "false" "$(jq '.inbounds[0] | has("up_mbps") or has("down_mbps")' <<<"${_hy2Bbr}")" \
    "Hysteria2：BBR 不写 up_mbps / down_mbps，写了就成了拒绝客户端用 BBR"
assert_equals '{"type":"file","directory":"/usr/share/nginx/html"}' "$(jq -c '.inbounds[0].masquerade' <<<"${_hy2Bbr}")" \
    "Hysteria2：masquerade 拿伪装站目录当文件服务器"
assert_equals "false" "$(jq '.inbounds[0] | has("obfs")' <<<"${_hy2Bbr}")" "Hysteria2：不混淆时不写 obfs"
assert_equals '[{"name":"a","password":"p"}] 443' "$(jq -r '.inbounds[0] | "\(.users | tojson) \(.listen_port)"' <<<"${_hy2Bbr}")" \
    "Hysteria2：用户数组原样进片段，端口是数字"
assert_equals "${TLS_DIR}/example.com.crt ${TLS_DIR}/example.com.key" \
    "$(jq -r '.inbounds[0].tls | "\(.certificate_path) \(.key_path)"' <<<"${_hy2Bbr}")" "Hysteria2：证书按域名取 tls/ 下那一对"
_hy2Brutal=$(hy2_json 8443 '[]' example.com 100 50 gecko 'a"b\c' '')
assert_equals "100 50 false" "$(jq -r '.inbounds[0] | "\(.up_mbps) \(.down_mbps) \(.ignore_client_bandwidth)"' <<<"${_hy2Brutal}")" \
    "Hysteria2：Brutal 写服务端 up / down，并允许客户端按带宽发"
assert_equals '{"type":"gecko","password":"a\"b\\c"}' "$(jq -c '.inbounds[0].obfs' <<<"${_hy2Brutal}")" \
    "Hysteria2：混淆类型与密码只当数据进 jq"
assert_equals "false" "$(jq '.inbounds[0] | has("masquerade")' <<<"${_hy2Brutal}")" "Hysteria2：没有伪装站目录就不写 masquerade"

READ_SB_FN=$(sed -n '/^readSingBoxConfig() {/,/^}/p' install.sh)
assert_not_empty "${READ_SB_FN}" "readSingBoxConfig：抽到函数原文"
HY2_READ_DIR="${MOCK_ROOT}/hy2read/"
mkdir -p "${HY2_READ_DIR}"
# 打印「客户端下行|客户端上行|混淆类型|混淆密码」
hy2_read() (
    singBoxConfigPath="${HY2_READ_DIR}"
    eval "${READ_SB_FN}"
    readSingBoxConfig
    printf '%s|%s|%s|%s\n' "${hysteria2ClientDownloadSpeed}" "${hysteria2ClientUploadSpeed}" "${hysteria2ObfsType}" "${hysteria2ObfsPassword}"
)
printf '%s\n' "${_hy2Bbr}" >"${HY2_READ_DIR}06_hysteria2_inbounds.json"
assert_equals "|||" "$(hy2_read)" "readSingBoxConfig：BBR 片段读回空带宽而不是 null，订阅就不给客户端带宽"
printf '%s\n' "${_hy2Brutal}" >"${HY2_READ_DIR}06_hysteria2_inbounds.json"
assert_equals '100|50|gecko|a"b\c' "$(hy2_read)" "readSingBoxConfig：up_mbps 读作客户端下行、down_mbps 读作上行，混淆类型一并读出"
printf '%s\n' '{"inbounds":[{"type":"hysteria2","listen_port":443,"up_mbps":200,"down_mbps":20,"ignore_client_bandwidth":false,"obfs":{"type":"salamander","password":"pw"}}]}' \
    >"${HY2_READ_DIR}06_hysteria2_inbounds.json"
assert_equals "200|20|salamander|pw" "$(hy2_read)" "readSingBoxConfig：旧版写死 Brutal 的片段照旧读出带宽与混淆"
rm -rf "${HY2_READ_DIR}"

echo ""

# ============================================================================
# sing-box 片段里不得出现「detour 指向 direct」：1.12+ 拒绝 direct 出站带 detour，1.14 上 detour 到空 direct 启动即 FATAL
# ============================================================================

echo -e "${BLUE}[sing-box detour] 多跳出站与 rule_set 下载通道${NC}"

HOPS_FN=$(sed -n '/^chainHopOutbounds() {/,/^}/p' install.sh)
assert_not_empty "${HOPS_FN}" "chainHopOutbounds：抽到函数原文"
hops_json() ( eval "${HOPS_FN}"; chainHopOutbounds "$@" )
_hops2=$(hops_json '[{"ip":"192.0.2.1","port":1001,"key":"k1","method":"m"},{"ip":"192.0.2.2","port":1002,"key":"k2","method":"m"}]')
assert_equals "chain_hop_1|192.0.2.1|- chain_outbound|192.0.2.2|chain_hop_1" \
    "$(jq -r '[.outbounds[] | "\(.tag)|\(.server)|\(.detour // "-")"] | join(" ")' <<<"${_hops2}")" \
    "chainHopOutbounds：两跳时末跳就叫 chain_outbound，经第一跳拨出"
assert_equals "0" "$(jq '[.outbounds[] | select(.type == "direct")] | length' <<<"${_hops2}")" \
    "chainHopOutbounds：不产出 direct 出站（direct 带 detour 被 1.12+ 拒绝）"
assert_equals "chain_outbound|-" "$(hops_json '[{"ip":"192.0.2.1","port":1001,"key":"k1","method":"m"}]' | jq -r '.outbounds[] | "\(.tag)|\(.detour // "-")"')" \
    "chainHopOutbounds：单跳直接就是 chain_outbound"
assert_equals "1" "$(hops_json '[]' >/dev/null 2>&1; [[ $? -ne 0 ]] && echo 1 || echo 0)" "chainHopOutbounds：没有跳时失败"

HTTP_CLIENT_FN=$(sed -n '/^ensureSingBoxHttpClient() {/,/^}/p' install.sh)
assert_not_empty "${HTTP_CLIENT_FN}" "ensureSingBoxHttpClient：抽到函数原文"
HTTP_CLIENT_DIR=$(mktemp -d)/
printf '%s\n' '{"outbounds":[{"type":"direct","tag":"01_direct_outbound"}]}' >"${HTTP_CLIENT_DIR}01_direct_outbound.json"
(eval "${HTTP_CLIENT_FN}"; ensureSingBoxHttpClient "${HTTP_CLIENT_DIR}")
assert_equals '[{"tag":"rule_set_http"}] rule_set_http' \
    "$(jq -c -j '.http_clients, " ", .route.default_http_client' "${HTTP_CLIENT_DIR}02_http_client.json")" \
    "ensureSingBoxHttpClient：http client 不带 detour（有 direct 出站也不指过去）"
rm -rf "${HTTP_CLIENT_DIR}"
# 每次合并都会走这些补写：片段目录里不留 .bak，不然越堆越多
SB_BAK_DIR=$(mktemp -d)/
printf '%s\n' '{"route":{"rule_set":[{"type":"remote","tag":"a","download_detour":"direct"}]}}' >"${SB_BAK_DIR}r.json"
env SB_BAK_DIR="${SB_BAK_DIR}" SB_BAK_FN="$(sed -n '/^ensureSingBoxLocalDns() {/,/^}/p;/^ensureSingBoxHttpClient() {/,/^}/p;/^normalizeSingBoxRuleSetHttpClient() {/,/^}/p' install.sh)" bash -c '
    source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh
    eval "${SB_BAK_FN}"
    singBoxConfigPath="${SB_BAK_DIR}"
    singBoxInstalledVersion() { echo "${SB_VER}"; }
    SB_VER=1.14.4
    ensureSingBoxLocalDns; ensureSingBoxLocalDns
    normalizeSingBoxRuleSetHttpClient "${SB_BAK_DIR}"; normalizeSingBoxRuleSetHttpClient "${SB_BAK_DIR}"
    SB_VER=1.13.0
    normalizeSingBoxRuleSetHttpClient "${SB_BAK_DIR}"' >/dev/null 2>&1
assert_equals "null|null" "$(jq -r '.route.rule_set[0] | "\(.download_detour)|\(.http_client)"' "${SB_BAK_DIR}r.json")" "sing-box 片段的 rule_set 迁移走了一个来回（1.14 迁入、更早的内核去掉）"
assert_equals "" "$(ls "${SB_BAK_DIR}" | grep '\.bak')" "sing-box 片段目录：补写与迁移都不留 .bak 文件"
rm -rf "${SB_BAK_DIR}"
assert_equals "0" "$(jq '[.http_clients[]? | select(has("detour"))] | length' docs/sing-box.json)" \
    "docs/sing-box.json：客户端模板的 http_clients 不带 detour（指向空 direct 时 1.14 客户端启动即 FATAL）"

echo ""

# ============================================================================
# 真机测试修出来的几处：中继对下一跳直连、出口按来源拒、多链路嵌套、换内核不抹旁挂、重定向白名单、SIP022 链接、订阅与 Reality 回落
# ============================================================================

echo -e "${BLUE}[真机修复] 链式、安装路径、订阅${NC}"

VPS_FN_NAMES="chainHopOutbounds chainRelayRouteJson chainExitSourceInject directOutboundInject globalEgressChainNotice routingToolsMenu isValidRedirectUrl _linkBase64Decode _linkPercentDecode _linkQueryGet _linkRefuse _linkCheckEndpoint _linkTlsJson _linkTransportJson parseVlessLink _vmessField parseVmessLink isValidDomain isValidIP parseSSLink cleanUp chainRefuseCoreSwitch singBoxFragmentsHaveInbounds configuredPorts portsTakenFor customUserEmail initRealityShortIds"
VPS_FNS=$(sed -n "$(for _f in ${VPS_FN_NAMES}; do printf '/^%s() {/,/^}/p\n' "${_f}"; done)" install.sh)
assert_equals "$(wc -w <<<"${VPS_FN_NAMES}" | tr -d ' ')" "$(grep -c '^[a-zA-Z0-9_]*() {$' <<<"${VPS_FNS}")" "真机修复：每个函数都抽到了"
# 订阅与 Reality 回落的渲染函数 heredoc 里有顶格的 }，按下一个函数的开头截取（同 installSubscribe 那段）
VPS_FNS+=$'\n'$(awk '/^installSubscribe\(\) \{/{f=1} /^unInstallSubscribe\(\) \{/{f=0} f' install.sh)
assert_contains "${VPS_FNS}" "renderRealityLocalDest() {" "真机修复：订阅与 Reality 回落的渲染函数也抽到了"
VPS_ROOT="${MOCK_ROOT}/vps.root"
VPS_CALLS="${MOCK_ROOT}/vps_calls"
VPS_F="${VPS_ROOT}/sing-box/conf/config"
VPS_NGINX="${MOCK_ROOT}/vps_nginx/"

# run_vps CMD → 以 VPS_ROOT 为安装根跑 CMD；服务启停、nginx、curl 桩掉，启停记进 VPS_CALLS
run_vps() (
    env PROXY_AGENT_DIR="${VPS_ROOT}" VPS_FNS="${VPS_FNS}" VPS_CALLS="${VPS_CALLS}" VPS_NGINX="${VPS_NGINX}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
        eval "${VPS_FNS}"
        handleSingBox() { echo "singbox $1" >>"${VPS_CALLS}"; }
        handleXray() { echo "xray $1" >>"${VPS_CALLS}"; }
        nginx() { echo "nginx version: nginx/1.26.3" >&2; }
        curl() { return 0; }
        listeningPorts() { :; }
        nginxConfigPath="${VPS_NGINX}"
        nginxStaticPath=/var/www/html
        eval "$1"' _ "$1"
)
vps_reset() {
    rm -rf "${VPS_ROOT}" "${VPS_NGINX}" && mkdir -p "${VPS_F}" "${VPS_ROOT}/sing-box" "${VPS_ROOT}/tls" "${VPS_NGINX}"
    : >"${VPS_ROOT}/sing-box/sing-box"
    : >"${VPS_CALLS}"
}

# --- 中继：发往下一跳的内层连接直连过去 ---
_vpsRoute=$(run_vps "chainRelayRouteJson '[{\"ip\":\"192.0.2.9\",\"port\":5009,\"key\":\"k\",\"method\":\"m\"},{\"ip\":\"192.0.2.10\",\"port\":5010,\"key\":\"k\",\"method\":\"m\"}]'")
assert_equals '{"inbound":["chain_inbound"],"ip_cidr":["192.0.2.9"],"port":[5009],"outbound":"direct"}' "$(jq -c '.route.rules[0]' <<<"${_vpsRoute}")" \
    "中继路由：第一条把目标正是下一跳的连接直连（入口嵌套拨号的内层），不再套进下游链"
assert_equals "chain_outbound" "$(jq -r '.route.rules[-1].outbound' <<<"${_vpsRoute}")" "中继路由：其余流量照旧进下游链"
assert_equals '["exit.example.org"]' "$(run_vps "chainRelayRouteJson '[{\"ip\":\"exit.example.org\",\"port\":5009,\"key\":\"k\",\"method\":\"m\"}]'" | jq -c '.route.rules[0].domain')" \
    "中继路由：下一跳写成域名时按 domain 匹配"
assert_equals '["2001:db8::1"]' "$(run_vps "chainRelayRouteJson '[{\"ip\":\"2001:db8::1\",\"port\":5009,\"key\":\"k\",\"method\":\"m\"}]'" | jq -c '.route.rules[0].ip_cidr')" \
    "中继路由：IPv6 下一跳按 ip_cidr 匹配"

# --- 多链路：中继给的多跳码经中继嵌套着拨，前面各跳的 tag 不会撞链路名 ---
_vpsMulti=$(run_vps "chainHopOutbounds '[{\"ip\":\"192.0.2.1\",\"port\":1,\"key\":\"k\",\"method\":\"m\"},{\"ip\":\"192.0.2.2\",\"port\":2,\"key\":\"k\",\"method\":\"m\"}]' us us-hop-")
assert_equals "us-hop-1|192.0.2.1|- us|192.0.2.2|us-hop-1" "$(jq -r '[.outbounds[] | "\(.tag)|\(.server)|\(.detour // "-")"] | join(" ")' <<<"${_vpsMulti}")" \
    "多链路：多跳码的出口叫链路名、经中继拨出，中继不再被绕过"

# --- 出口：只允许入口 IP 写进 sing-box 路由，不靠防火墙 ---
vps_reset
printf '%s\n' '{"inbounds":[{"type":"shadowsocks","tag":"chain_inbound"}],"route":{"rules":[{"inbound":["chain_inbound"],"outbound":"direct"}]}}' >"${VPS_ROOT}/merged.json"
printf '%s\n' '{"role":"exit","allowed_ip":"198.51.100.4"}' >"${VPS_ROOT}/sing-box/conf/chain_exit_info.json"
run_vps "chainExitSourceInject ${VPS_ROOT}/merged.json" >/dev/null 2>&1
assert_equals '{"type":"logical","mode":"and","rules":[{"inbound":["chain_inbound"]},{"source_ip_cidr":["198.51.100.4"],"invert":true}],"action":"reject"}' \
    "$(jq -c '.route.rules[0]' "${VPS_ROOT}/merged.json")" "出口限源：别的来源连进 chain_inbound 一律 reject（只管 chain_inbound，旁挂的 6 / 9 不受影响）"
assert_equals "2" "$(jq '.route.rules | length' "${VPS_ROOT}/merged.json")" "出口限源：原有规则留着"
printf '%s\n' '{"inbounds":[{"type":"shadowsocks","tag":"chain_inbound"}],"route":{"rules":[]}}' >"${VPS_ROOT}/merged.json"
: >"${VPS_ROOT}/sing-box/conf/chain_relay_info.json"
run_vps "chainExitSourceInject ${VPS_ROOT}/merged.json" >/dev/null 2>&1
assert_equals "0" "$(jq '.route.rules | length' "${VPS_ROOT}/merged.json")" "出口限源：中继状态在（出口状态是覆盖前留下的）就不注入，中继不会被错拦"
rm -f "${VPS_ROOT}/sing-box/conf/chain_relay_info.json"
printf '%s\n' '{"role":"exit","allowed_ip":""}' >"${VPS_ROOT}/sing-box/conf/chain_exit_info.json"
run_vps "chainExitSourceInject ${VPS_ROOT}/merged.json" >/dev/null 2>&1
assert_equals "0" "$(jq '.route.rules | length' "${VPS_ROOT}/merged.json")" "出口限源：没设只允许入口 IP 就不注入"
printf '%s\n' '{not json' >"${VPS_ROOT}/sing-box/conf/chain_exit_info.json"
assert_equals "1" "$(run_vps "chainExitSourceInject ${VPS_ROOT}/merged.json" >/dev/null 2>&1; echo $?)" \
    "出口限源：出口状态读不懂让合并失败（跳过等于对所有人放开）"

# --- 出口 / 中继开 IPv6 全局：direct 出站被删，final 与链式直连规则仍指向它 ---
printf '%s\n' '{"outbounds":[{"type":"direct","tag":"IPv6_out"}],"route":{"rules":[{"inbound":["chain_inbound"],"outbound":"direct"}],"final":"direct"}}' >"${VPS_ROOT}/merged.json"
run_vps "directOutboundInject ${VPS_ROOT}/merged.json" >/dev/null 2>&1
assert_equals '["IPv6_out","direct"]' "$(jq -c '[.outbounds[].tag]' "${VPS_ROOT}/merged.json")" \
    "出口（IPv6 全局）：补上 direct，排在后面不抢默认出口（没有入口状态也补，不然 sing-box 起不来）"
printf '%s\n' '{"outbounds":[],"route":{"rules":[{"inbound":["x"],"outbound":"wg"}]}}' >"${VPS_ROOT}/merged.json"
run_vps "directOutboundInject ${VPS_ROOT}/merged.json" >/dev/null 2>&1
assert_equals '[]' "$(jq -c '[.outbounds[].tag]' "${VPS_ROOT}/merged.json")" "合并：没人指向 direct 时不补（WARP 全局没有出站，补了就成了默认出口）"

# --- IPv6 / WARP 全局的确认前：链式出口 / 中继提示经链路的流量不走全局出口 ---
printf '%s\n' '{"role":"exit"}' >"${VPS_ROOT}/sing-box/conf/chain_exit_info.json"
assert_contains "$(run_vps 'globalEgressChainNotice' 2>&1)" "不走全局出口" "全局出口：链式出口上确认前提示经链路的流量仍直连"
rm -f "${VPS_ROOT}/sing-box/conf/chain_exit_info.json"
assert_equals "" "$(run_vps 'globalEgressChainNotice' 2>&1)" "全局出口：不是链式出口 / 中继就不提示"

# --- 分流工具：Xray 链式入口上拒绝（追加的规则排在链式兜底之后永不命中），别的机器照常进菜单 ---
mkdir -p "${VPS_ROOT}/xray/conf" && : >"${VPS_ROOT}/xray/conf/chain_outbound.json"
_out=$(run_vps 'coreKind=1; routingToolsMenu </dev/null; echo rc=$?' 2>&1)
assert_contains "${_out}" "多链路规则" "分流工具（Xray 链式入口）：拒绝并指向多链路规则"
assert_equals "0" "$(grep -c 'WARP分流' <<<"${_out}")" "分流工具（Xray 链式入口）：不进菜单"
assert_contains "$(run_vps 'coreKind=2; routingToolsMenu </dev/null; echo rc=$?' 2>&1)" "WARP分流" "分流工具（sing-box 内核）：分流片段排在链式路由前面会生效，照常进菜单"
rm -f "${VPS_ROOT}/xray/conf/chain_outbound.json"
assert_contains "$(run_vps 'coreKind=1; routingToolsMenu </dev/null; echo rc=$?' 2>&1)" "WARP分流" "分流工具（Xray、不是链式入口）：照常进菜单"

# --- 换内核：已是 Xray 时不碰 sing-box；从 sing-box 切过来只删协议入站，出口 / 中继留着 ---
vps_reset
for _f in 06_hysteria2_inbounds 07_VLESS_vision_reality_inbounds chain_inbound chain_route 01_direct_outbound; do printf '%s\n' '{"inbounds":[{"tag":"x"}]}' >"${VPS_F}/${_f}.json"; done
_vpsOut=$(run_vps 'cleanUp singBoxProtocolsDel 1' 2>&1)
assert_equals "5" "$(find "${VPS_F}" -name '*.json' | wc -l | tr -d ' ')" "换内核：已是 Xray 内核时 sing-box 片段一个不删（旁挂 6 / 9、链式出口都在）"
assert_contains "${_vpsOut}" "旁挂" "换内核：保留旁挂 6 / 9 时说明账号以它们自己的配置为准"
assert_equals "" "$(cat "${VPS_CALLS}")" "换内核：已是 Xray 内核时不停 sing-box"
run_vps 'cleanUp singBoxProtocolsDel 2' >/dev/null 2>&1
assert_equals "01_direct_outbound.json chain_inbound.json chain_route.json" "$(cd "${VPS_F}" && ls | tr '\n' ' ' | sed 's/ $//')" \
    "换内核：从 sing-box 切到 Xray 只删协议入站，链式出口 / 中继的片段留着"
assert_equals "singbox stop singbox start" "$(tr '\n' ' ' <"${VPS_CALLS}" | sed 's/ $//')" "换内核：删完还有入站（出口）就让 sing-box 接着跑"
vps_reset
printf '%s\n' '{"inbounds":[{"tag":"x"}]}' >"${VPS_F}/07_VLESS_vision_reality_inbounds.json"
run_vps 'cleanUp singBoxProtocolsDel 2' >/dev/null 2>&1
assert_equals "singbox stop" "$(tr '\n' ' ' <"${VPS_CALLS}" | sed 's/ $//')" "换内核：一个入站都不剩就停着"

vps_reset
: >"${VPS_ROOT}/sing-box/conf/chain_entry_info.json"
assert_equals "1" "$(run_vps 'coreKind=2; chainRefuseCoreSwitch 1; echo passed' >/dev/null 2>&1; echo $?)" "换内核：本机是链式入口时拒绝（入口在两种内核下结构不同）"
assert_equals "passed" "$(run_vps 'coreKind=1; chainRefuseCoreSwitch 1; echo passed' 2>/dev/null)" "换内核：不换内核的重装照常"
for _fn in xrayCoreInstall customXrayInstall; do
    assert_equals "reloadCore" "$(sed -n "/^${_fn}() {/,/^}/p" install.sh | sed -n '/initXrayConfig/,$p' | grep -oE 'reloadCore|handleXray start|handleSingBox start' | paste -sd' ' -)" \
        "${_fn}：写完配置经 reloadCore 重启——端口自检停过旁挂的 sing-box（链式、6 / 9），只起 Xray 它就一直停着"
done
rm -f "${VPS_ROOT}/sing-box/conf/chain_entry_info.json"
assert_equals "passed" "$(run_vps 'coreKind=2; chainRefuseCoreSwitch 1; echo passed' 2>/dev/null)" "换内核：只是出口 / 中继的机器可以换"

# --- 302 重定向：白名单，引号、分号、空白、$、花括号、反斜杠都改得了 nginx 那一行 ---
_vpsUrls=""
for _u in "https://x.com/a?b=1&c=2" "http://1.2.3.4:8080/p" "https://x.com;return 200 pwn" "https://x.com/'" "https://x.com/\$host" "https://x.com/a b" \
          "https://x.com/{a}" "https://x.com/a\\b" 'https://x.com/"' "https://x.com/\`id\`" "https://x.com/a|b" "https://x.com/<a>" "ftp://x.com" ""; do
    _vpsUrls+="$(run_vps "isValidRedirectUrl '${_u//\'/\'\\\'\'}' && echo A || echo r")"
done
assert_equals "AArrrrrrrrrrrr" "${_vpsUrls}" "302 重定向：只收 http(s) 地址里的安全字符，黑名单字符类提前闭合那种全放行不再出现"

# --- SIP022 的 ss:// 链接：userinfo 是百分号编码的明文 method:password ---
assert_equals "2022-blake3-aes-128-gcm|xPU/ab+c==" \
    "$(run_vps "parseSSLink 'ss://2022-blake3-aes-128-gcm:xPU%2Fab%2Bc%3D%3D@192.0.2.5:8388#n'" | jq -r '"\(.method)|\(.password)"')" \
    "SS 链接：SIP022 的 userinfo 按百分号解码，密码里不再留着 %2F"
assert_equals "aes-128-gcm|pass" \
    "$(run_vps "parseSSLink 'ss://$(printf 'aes-128-gcm:pass' | base64 | tr -d '=')@192.0.2.5:8388#n'" | jq -r '"\(.method)|\(.password)"')" \
    "SS 链接：SIP002 的 base64 userinfo 照旧解码"

# --- vless / vmess 链接：解析出 sing-box 出站的形状，sing-box 连不了的当场拒绝 ---
EXT_UUID=0f3c8a4e-1b2d-4c5e-8f90-123456789abc
ext_vless() { run_vps "parseVlessLink 'vless://$1'" 2>&1; }
ext_vmess() { run_vps "parseVmessLink 'vmess://$(printf '%s' "$1" | base64 | tr -d '\n')'" 2>&1; }
assert_equals '{"name":"a b","type":"vless","server":"203.0.113.9","server_port":443,"uuid":"'"${EXT_UUID}"'","flow":"xtls-rprx-vision","tls":{"enabled":true,"server_name":"www.python.org","utls":{"enabled":true,"fingerprint":"chrome"},"reality":{"enabled":true,"public_key":"PBK","short_id":"ab12"}}}' \
    "$(ext_vless "${EXT_UUID}@203.0.113.9:443?encryption=none&security=reality&type=tcp&sni=www.python.org&fp=chrome&pbk=PBK&sid=ab12&flow=xtls-rprx-vision#a%20b" | jq -c .)" \
    "VLESS 链接：脚本发的 Reality 链接解析成 sing-box 出站，名字解码"
assert_equals '{"name":"VLESS-a.example","type":"vless","server":"a.example","server_port":8443,"uuid":"'"${EXT_UUID}"'","tls":{"enabled":true,"server_name":"h.example","utls":{"enabled":true,"fingerprint":"chrome"}},"transport":{"type":"ws","path":"/p/ws","headers":{"Host":"h.example"}}}' \
    "$(ext_vless "${EXT_UUID}@a.example:8443?encryption=none&security=tls&type=ws&host=h.example&fp=chrome&path=%2Fp%2Fws" | jq -c .)" \
    "VLESS 链接：WS 路径解码，没写 sni 时用 host，没写名字时用地址"
assert_equals '["2001:db8::1",443,"grpc","svc",true,["h2","http/1.1"]]' \
    "$(ext_vless "${EXT_UUID}@[2001:db8::1]:443/?security=tls&type=grpc&serviceName=svc&allowInsecure=1&alpn=h2%2Chttp%2F1.1&sni=x.example" | jq -c '[.server, .server_port, .transport.type, .transport.service_name, .tls.insecure, .tls.alpn]')" \
    "VLESS 链接：IPv6 字面量去方括号，gRPC、跳过校验、多个 ALPN"
assert_equals 'null' "$(ext_vless "${EXT_UUID}@a.example:443?xsni=wrong&security=none" | jq -c '.tls')" "VLESS 链接：不加密时没有 tls；参数按整键匹配，xsni 不算 sni"
assert_equals 'x.example' "$(ext_vless "${EXT_UUID}@a.example:443?xsni=wrong&security=tls&sni=x.example" | jq -r '.tls.server_name')" "VLESS 链接：xsni 不会被当成 sni"
for _extCase in \
    "${EXT_UUID}@a.example:443?security=reality&type=xhttp&pbk=K|type = xhttp|sing-box 没有 XHTTP" \
    "${EXT_UUID}@a.example:443?security=tls&type=kcp|type = kcp|mKCP" \
    "${EXT_UUID}@a.example:443?encryption=mlkem768x25519plus.native.0rtt.x&security=tls|encryption = mlkem768x25519plus|VLESS Encryption" \
    "${EXT_UUID}@a.example:443?security=tls&flow=xtls-rprx-vision-udp443|flow = xtls-rprx-vision-udp443|别的 flow" \
    "${EXT_UUID}@a.example:443?security=tls&headerType=http|headerType = http|TCP 的 HTTP 伪装" \
    "${EXT_UUID}@a.example:443?security=tls&fp=bogus|fp = bogus|未知指纹（写进片段后整个 sing-box 起不来）" \
    "${EXT_UUID}@a.example:443?security=reality|pbk = |Reality 没有公钥" \
    "${EXT_UUID}@a.example:443?security=xtls|security = xtls|未知加密方式" \
    "not-a-uuid@a.example:443?security=tls|uuid = not-a-uuid|UUID 不合法" \
    "${EXT_UUID}@a.example:0443?security=tls|port = 0443|端口前导零（--argjson 会解析失败）" \
    "${EXT_UUID}@a.example:70000?security=tls|port = 70000|端口越界" \
    "${EXT_UUID}@a\"b.example:443?security=tls|server = a\"b.example|地址里有引号"; do
    IFS='|' read -r _extLink _extWant _extWhy <<<"${_extCase}"
    _extOut=$(ext_vless "${_extLink}")
    assert_contains "${_extOut}" "${_extWant}" "VLESS 链接：拒绝${_extWhy}，并说明是哪一项"
    assert_equals "" "$(grep -F '"type"' <<<"${_extOut}")" "VLESS 链接：拒绝${_extWhy}时不输出节点"
done
assert_equals '{"name":"vm","type":"vmess","server":"a.example","server_port":443,"uuid":"'"${EXT_UUID}"'","packet_encoding":"xudp","security":"auto","tls":{"enabled":true,"server_name":"h.example"},"transport":{"type":"ws","path":"/vws","headers":{"Host":"h.example"}}}' \
    "$(ext_vmess '{"port":443,"ps":"vm","tls":"tls","id":"'"${EXT_UUID}"'","aid":0,"v":2,"host":"h.example","type":"none","path":"/vws","net":"ws","add":"a.example","scy":"auto"}' | jq -c .)" \
    "VMess 链接：端口是数字也行，sni 缺省用 host，UDP 用 xudp"
assert_equals '["httpupgrade","/u",7,8443,null]' \
    "$(ext_vmess '{"port":"8443","id":"'"${EXT_UUID}"'","aid":"7","path":"/u","net":"httpupgrade","add":"a.example","tls":""}' | jq -c '[.transport.type, .transport.path, .alter_id, .server_port, .tls]')" \
    "VMess 链接：端口与 aid 是字符串也行，空 tls 不加密"
assert_equals 'svc' "$(ext_vmess '{"port":443,"id":"'"${EXT_UUID}"'","path":"svc","net":"grpc","add":"a.example","tls":"tls"}' | jq -r '.transport.service_name')" "VMess 链接：gRPC 的 service_name 在 path 字段"
assert_contains "$(ext_vmess '{"port":443,"id":"'"${EXT_UUID}"'","net":"xhttp","add":"a.example"}')" "type = xhttp" "VMess 链接：拒绝 sing-box 没有的传输"
assert_contains "$(ext_vmess '{"port":443,"id":"'"${EXT_UUID}"'","net":"tcp","type":"http","add":"a.example"}')" "type = http" "VMess 链接：拒绝 TCP 的 HTTP 伪装"
assert_contains "$(ext_vmess '{"port":443,"id":"'"${EXT_UUID}"'","net":"tcp","scy":"bogus","add":"a.example"}')" "scy = bogus" "VMess 链接：拒绝未知加密"
assert_contains "$(ext_vmess '{"port":443,"id":"'"${EXT_UUID}"'","net":"tcp","aid":"x","add":"a.example"}')" "aid = x" "VMess 链接：拒绝 aid 不是数字"
assert_equals "1" "$(run_vps "parseVmessLink 'vmess://not-base64-json'" >/dev/null 2>&1; echo $?)" "VMess 链接：不是 base64 的 JSON 返回 1"
assert_equals "a\\b" "$(run_vps "_linkPercentDecode 'a\\b'")" "解码：带反斜杠的原样返回，不被 %b 当转义"

# 节点存盘后生成出站：只挑 sing-box 认的字段，id、name、enabled 这些写进片段会让合并失败
EXT_GEN_FN=$(sed -n '/^generateExternalOutboundConfig() {/,/^}/p' install.sh)
assert_equals '{"type":"vless","tag":"chain1","server":"a.example","server_port":443,"uuid":"u","flow":"xtls-rprx-vision","tls":{"enabled":true},"transport":{"type":"ws"}}' \
    "$(env EXT_GEN_FN="${EXT_GEN_FN}" bash -c 'eval "${EXT_GEN_FN}"; getExternalNodeById() { echo "{\"id\":\"i\",\"name\":\"n\",\"enabled\":true,\"created_at\":\"t\",\"type\":\"vless\",\"server\":\"a.example\",\"server_port\":443,\"uuid\":\"u\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true},\"transport\":{\"type\":\"ws\"}}"; }; generateExternalOutboundConfig i chain1' | jq -c .)" \
    "外部节点：VLESS 节点生成的出站只有 sing-box 认的字段"
assert_equals '["vmess","chain1","xudp",4]' \
    "$(env EXT_GEN_FN="${EXT_GEN_FN}" bash -c 'eval "${EXT_GEN_FN}"; getExternalNodeById() { echo "{\"id\":\"i\",\"name\":\"n\",\"type\":\"vmess\",\"server\":\"a\",\"server_port\":1,\"uuid\":\"u\",\"packet_encoding\":\"xudp\",\"alter_id\":4}"; }; generateExternalOutboundConfig i chain1' | jq -c '[.type, .tag, .packet_encoding, .alter_id]')" \
    "外部节点：VMess 节点的 packet_encoding 与 alter_id 带到出站"

# --- 订阅：配置从端口渲染，安装流程选端口时它算已占 ---
vps_reset
run_vps 'renderSubscribeConf 50188 sub.example.org' >/dev/null 2>&1
assert_contains "$(cat "${VPS_NGINX}subscribe.conf")" "listen 50188  so_keepalive=on" "订阅渲染：没有该域名的证书就是 http"
: >"${VPS_ROOT}/tls/sub.example.org.crt"; : >"${VPS_ROOT}/tls/sub.example.org.key"
run_vps 'renderSubscribeConf 50188 sub.example.org' >/dev/null 2>&1
assert_contains "$(cat "${VPS_NGINX}subscribe.conf")" "server_name sub.example.org;" "订阅渲染：有证书就是 https，server_name 是给的域名"
assert_contains "$(grep -m1 listen "${VPS_NGINX}subscribe.conf")" "listen 50188 ssl" "订阅渲染：主 server 块排最前，第一行 listen 就是订阅端口"
assert_contains "$(cat "${VPS_NGINX}subscribe.conf")" "sing-box" "订阅渲染：readNginxSubscribe 认文件靠的 sing-box 这个词还在"
assert_equals "50188" "$(run_vps 'subscribeConfPort')" "订阅端口：从 subscribe.conf 第一行 listen 读出"
assert_contains "$(run_vps 'portsTakenFor 7 "'"${VPS_ROOT}"'/xray/conf" "" ""')" "50188" "选端口：订阅端口算已占（安装中 nginx 停着，/proc 看不到它）"
assert_equals "" "$(run_vps 'nginxConfigPath=; subscribeConfPort')" "订阅端口：没有 nginx 配置目录（一键 Reality）时为空"

# --- Reality 目标选本机域名：落到只听回环的独立伪装站，不再指订阅端口 ---
assert_equals "1" "$(run_vps 'renderRealityLocalDest nocert.example.org' >/dev/null 2>&1; echo $?)" "Reality 本机回落：没有该域名证书时不写、返回 1"
run_vps 'renderRealityLocalDest sub.example.org' >/dev/null 2>&1
assert_contains "$(cat "${VPS_NGINX}reality_dest.conf")" "listen 127.0.0.1:31305 ssl;" "Reality 本机回落：只听回环上的固定端口"
assert_contains "$(cat "${VPS_NGINX}reality_dest.conf")" "http2 on;" "Reality 本机回落：nginx ≥ 1.25.1 开 h2"

# --- 普通加人：名字第一段与已有账号相同就拒（订阅文件按第一段分，两人会共用一份订阅、互见凭据）---
mkdir -p "${VPS_ROOT}/xray/conf"
printf '%s\n' '{"inbounds":[{"settings":{"clients":[{"id":"u1","email":"t-alice-VLESS_TCP/TLS_Vision"}]}}]}' >"${VPS_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
_vpsEmail() { run_vps "coreKind=1; configPath=${VPS_ROOT}/xray/conf/; frontingType=02_VLESS_TCP_inbounds; customUserEmail <<<'$1'" >/dev/null 2>&1; echo $?; }
assert_equals "1" "$(_vpsEmail t-bob)" "加人：t-bob 与已有的 t-alice 第一段相同，拒绝"
assert_equals "1" "$(_vpsEmail t)" "加人：名字正好是已有账号的第一段也拒"
assert_equals "0" "$(_vpsEmail bob)" "加人：第一段不撞就照常"
_vpsEmailRetry() { run_vps "coreKind=1; configPath=${VPS_ROOT}/xray/conf/; frontingType=02_VLESS_TCP_inbounds; printf '$1' | { customUserEmail >/dev/null 2>&1; echo \"\${currentCustomEmail}|\$?\"; }" 2>/dev/null; }
assert_equals "bob|0" "$(_vpsEmailRetry 'a b\nbob\n')" "加人：email 格式非法时重问，不退回 shell"
assert_equals "carol|0" "$(_vpsEmailRetry 't-bob\ncarol\n')" "加人：订阅键撞车时重问"

# --- Reality：密钥沿用就连 shortId 一起沿用，旧链接的 sid 还对得上 ---
assert_equals "aaaa|bbbb" "$(run_vps 'realityShortId1=; currentRealityShortId=aaaa; currentRealityShortId2=bbbb; currentRealityPublicKey=PK; realityPublicKey=PK; initRealityShortIds; echo "${realityShortId1}|${realityShortId2}"')" \
    "Reality shortId：密钥沿用时 shortId 不再重新随机"
assert_equals "new" "$(run_vps 'realityShortId1=; currentRealityShortId=aaaa; currentRealityPublicKey=PK; realityPublicKey=NEW; initRealityShortIds; [[ "${realityShortId1}" != aaaa && ${#realityShortId1} -eq 16 ]] && echo new')" \
    "Reality shortId：换了密钥就随机新的一对"
rm -rf "${VPS_ROOT}" "${VPS_NGINX}" "${VPS_CALLS}"

echo ""

# ============================================================================
# showInstallStatus 的协议行（抽 install.sh 原文执行，不抄副本）
# ============================================================================

echo -e "${BLUE}[showInstallStatus] 协议显示行${NC}"

SHOW_STATUS_FN=$(sed -n '/^showInstallStatus() {/,/^}/p;/^xrayDaemonRunning() {/,/^}/p' install.sh)
assert_not_empty "${SHOW_STATUS_FN}" "showInstallStatus：抽到函数原文"

# 子 shell 里跑：桩掉进程探测与重扫盘，echoContent 只留文本并去掉行尾 \c，t 只留键名
render_install_status() (
    coreKind="$1"; currentInstallProtocolType="$2"
    pgrep() { :; }
    readInstallProtocolType() { :; }
    echoContent() { local s="$2"; printf '%s\n' "${s% \\c}"; }
    t() { printf '%s' "$1"; }
    eval "${SHOW_STATUS_FN}"
    showInstallStatus
)

assert_equals "$(printf '%s\n' '\nCORE_CURRENT_STOPPED' 'PROTOCOLS_INSTALLED:' \
    'VLESS+TCP[TLS_Vision]' 'VLESS+WS[TLS]' 'Trojan+gRPC[TLS]' 'VMess+WS[TLS]' 'Trojan+TCP[TLS]' \
    'VLESS+gRPC[TLS]' 'Hysteria2' 'VLESS+Reality+Vision' 'VLESS+Reality+gRPC' 'Tuic' 'Naive' \
    'VMess+TLS+HTTPUpgrade' 'VLESS+Reality+XHTTP' 'AnyTLS' 'SS2022' 'VLESS+XHTTP[TLS]' 'ShadowTLS+SS2022' '')" \
    "$(render_install_status 2 ",0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,")" \
    "showInstallStatus：全部 17 个协议按 ID 升序、用菜单文案显示"
assert_equals "$(printf '%s\n' '\nCORE_CURRENT_STOPPED' 'PROTOCOLS_INSTALLED:' 'VLESS+Reality+Vision' 'Tuic' 'Naive' '')" \
    "$(render_install_status 1 ",10,9,7,")" \
    "showInstallStatus：显示顺序按 ID 数值、与状态串顺序无关"
assert_equals "$(printf '%s\n' '\nCORE_CURRENT_STOPPED')" \
    "$(render_install_status 2 "")" \
    "showInstallStatus：没有协议时不打协议行"

echo ""

# ============================================================================
# registry 是协议文件名的唯一真源；安装根只能从 PROXY_AGENT_DIR 派生
# ============================================================================

echo -e "${BLUE}[registry / 布局] install.sh 的协议文件名与安装根${NC}"

UNREGISTERED_NAMES=$(comm -23 \
    <(grep -oE '[0-9]{2}_[A-Za-z0-9]+(_[A-Za-z0-9]+)*_inbounds\.json' install.sh | sort -u) \
    <(grep -oE '[0-9]{2}_[A-Za-z0-9]+(_[A-Za-z0-9]+)*_inbounds\.json' lib/protocol-registry.sh | sort -u))
assert_equals "" "${UNREGISTERED_NAMES}" "install.sh 里出现的每个 *_inbounds.json 文件名都在 registry 里"

HARDCODED_ROOT=$(grep -n '/etc/Proxy-agent' install.sh lib/*.sh | grep -v 'PROXY_AGENT_DIR:-/etc/Proxy-agent')
assert_equals "" "${HARDCODED_ROOT}" "install.sh 与 lib/ 不再写死 /etc/Proxy-agent（只剩默认值惯用法）"

# Debian 12 / Ubuntu 22.04 自带 jq 1.6：关键字当变量名（--arg label → $label）整段 filter 编译失败，1.7 才放开
JQ_KEYWORD_VARS=$(grep -nE -- '--arg(json)? (as|def|module|import|include|if|then|elif|else|end|reduce|foreach|and|or|not|try|catch|label) |as \$(as|def|module|import|include|if|then|elif|else|end|reduce|foreach|and|or|not|try|catch|label)\b' install.sh lib/*.sh)
assert_equals "" "${JQ_KEYWORD_VARS}" "jq 变量名不用关键字（jq 1.6 不认 \$label 这类写法）"

# t() 用 bash 内置 printf 渲染，它不认 %2$s 这种位置参数：整条消息只剩第一个参数之前的字
LANG_POSITIONAL=$(grep -nE '%[0-9]+\\?\$' shell/lang/*.sh)
assert_equals "" "${LANG_POSITIONAL}" "语言文件不用 printf 位置参数"

# nginx 在不在跑只能按进程名精确判：-f 会把 "vim nginx.conf" 当成 nginx。
# 先去掉引号与反斜杠再比，任何拼法的 pgrep … nginx 都必须正好是 pgrep -x nginx
NGINX_PGREP_CALLS=$(awk '
    /^[[:space:]]*#/ { next }
    {
        line = $0; gsub(/["\047\\]/, "", line)
        while (match(line, /pgrep[[:space:]][^|;&)`]*/)) {
            call = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
            if (call !~ /nginx/) continue
            gsub(/[[:space:]]+/, " ", call); sub(/ $/, "", call)
            print FILENAME ":" FNR ": " call
        }
    }
' install.sh lib/*.sh)
assert_not_empty "${NGINX_PGREP_CALLS}" "抽到判 nginx 进程的 pgrep 调用"
assert_equals "" "$(grep -v ': pgrep -x nginx$' <<< "${NGINX_PGREP_CALLS}")" \
    "install.sh 与 lib/ 判 nginx 进程一律 pgrep -x，没有 -f 子串匹配"

# Xray 在不在跑只认服务那条 run -confdir：拼车统计的 api statsquery、配置检查的 run -test 都不算
XRAY_PGREP_CALLS=$(grep -nE 'pgrep[^|;&]*xray' install.sh lib/*.sh | grep -v '^install.sh:[0-9]*: *\[\[ -n \$(pgrep -f "xray/xray run -confdir") \]\]$')
assert_equals "" "${XRAY_PGREP_CALLS}" "install.sh 与 lib/ 判 Xray 进程一律经 xrayDaemonRunning"
XRAY_ALIVE_FN=$(sed -n '/^xrayDaemonRunning() {/,/^}/p' install.sh)
XRAY_ALIVE_DIR=$(mktemp -d)
mkdir -p "${XRAY_ALIVE_DIR}/xray"
printf '#!/bin/sh\nwhile :; do sleep 1; done\n' >"${XRAY_ALIVE_DIR}/xray/xray"
chmod +x "${XRAY_ALIVE_DIR}/xray/xray"
xray_alive_with() { # ARGS... → 起一个带这串参数的假 xray，打印 xrayDaemonRunning 的判定
    local pid verdict=no
    "${XRAY_ALIVE_DIR}/xray/xray" "$@" &
    pid=$!
    sleep 0.3
    (eval "${XRAY_ALIVE_FN}"; xrayDaemonRunning) && verdict=yes
    kill "${pid}" 2>/dev/null; wait "${pid}" 2>/dev/null
    echo "${verdict}"
}
assert_equals "no" "$(xray_alive_with api statsquery -s 127.0.0.1:31211 -reset)" "xrayDaemonRunning：拼车统计的 statsquery 不算服务在跑"
assert_equals "no" "$(xray_alive_with run -test -confdir /x/conf)" "xrayDaemonRunning：配置检查的 run -test 不算服务在跑"
assert_equals "yes" "$(xray_alive_with run -confdir /x/conf)" "xrayDaemonRunning：服务那条 run -confdir 算在跑"
rm -rf "${XRAY_ALIVE_DIR}"

# nginxBlog：目录里有用户自己的东西时先问、默认保留；nginx 包自带的页面不算
NGINX_BLOG_FN=$(sed -n '/^nginxStaticHasForeignContent() {/,/^}/p;/^nginxBlog() {/,/^}/p' install.sh)
BLOG_DIR=$(mktemp -d)
run_blog() { # 在子 shell 里跑 nginxBlog，wget 桩成下载失败并记一笔；打印输出
    (
        export V2RAY_LANG=zh_CN; source lib/i18n.sh; source lib/utils.sh
        nginxStaticPath="${BLOG_DIR}/"; release=debian; lastInstallationConfig=
        echoContent() { printf '%s\n' "$2"; }
        wget() { echo "WGET"; return 1; }
        randomNum() { echo 0; }
        eval "${NGINX_BLOG_FN}"
        nginxBlog
    ) 2>&1
}
printf '<title>Welcome to nginx!</title>\n' >"${BLOG_DIR}/index.html"
echo x >"${BLOG_DIR}/50x.html"
_out=$(run_blog </dev/null)
assert_equals "no|yes" "$([[ "${_out}" == *"没有换成伪装站"* ]] && echo yes || echo no)|$([[ "${_out}" == *WGET* ]] && echo yes || echo no)" \
    "nginxBlog：只有 nginx 包自带的页面时不问，照常装伪装站"
echo mine >"${BLOG_DIR}/blog.html"
_out=$(printf 'n\n' | run_blog)
assert_equals "yes|no|mine" "$([[ "${_out}" == *"没有换成伪装站"* ]] && echo yes || echo no)|$([[ "${_out}" == *WGET* ]] && echo yes || echo no)|$(cat "${BLOG_DIR}/blog.html")" \
    "nginxBlog：有用户自己的文件时先问，回答 n 不下载、原样保留"
_out=$(run_blog </dev/null)
assert_equals "no|mine" "$([[ "${_out}" == *WGET* ]] && echo yes || echo no)|$(cat "${BLOG_DIR}/blog.html")" "nginxBlog：没有终端可答时默认保留"
_out=$(printf 'y\n' | run_blog)
assert_contains "${_out}" "WGET" "nginxBlog：回答 y 才去装伪装站"
rm -rf "${BLOG_DIR}"

# doctor 证书段：没有协议入站、核心却装着（只跑链式角色的 sing-box 机器）时不说「未检测到核心」
DOCTOR_CERT_FN=$(sed -n '/^_doctorCheckCert() {/,/^}/p' install.sh)
DOCTOR_TLS=$(mktemp -d)
doctor_cert_rows() { # coreKind → 证书两行的跳过理由（干净 bash：本 shell 的 TLS_DIR 已 readonly）
    env -u TLS_DIR -u SINGBOX_BIN -u SINGBOX_FRAGMENT_DIR V2RAY_LANG=zh_CN DOCTOR_TLS="${DOCTOR_TLS}" DOCTOR_CERT_FN="${DOCTOR_CERT_FN}" CORE="$1" bash -c '
        source lib/i18n.sh
        TLS_DIR="${DOCTOR_TLS}"; SINGBOX_BIN=/nonexistent; SINGBOX_FRAGMENT_DIR=/nonexistent
        currentInstallProtocolType=; coreKind="${CORE}"
        _doctorSection() { :; }; _doctorRow() { [[ "$2" == skip ]] && printf "%s\n" "$3"; }
        eval "${DOCTOR_CERT_FN}"
        _doctorCheckCert' 2>&1 | sort -u
}
assert_equals "没有需要证书的协议" "$(doctor_cert_rows 2)" "doctor 证书：核心装着、没有协议入站时说没有需要证书的协议"
assert_equals "未检测到已安装核心" "$(doctor_cert_rows "")" "doctor 证书：真没有核心时照旧"
rm -rf "${DOCTOR_TLS}"

OVERRIDE_LAYOUT=$(env PROXY_AGENT_DIR=/tmp/pa-override bash -c \
    'source lib/constants.sh; echo "${XRAY_BIN} ${SINGBOX_FRAGMENT_DIR} ${TLS_DIR} ${CHAIN_MULTI_INFO}"')
assert_equals "/tmp/pa-override/xray/xray /tmp/pa-override/sing-box/conf/config /tmp/pa-override/tls /tmp/pa-override/sing-box/conf/chain_multi_info.json" \
    "${OVERRIDE_LAYOUT}" "PROXY_AGENT_DIR 覆盖后整套布局跟着走"

# 安装根合法性：抽 install.sh 开头那行 [[ … =~ … ]] 原文，在干净的 bash 里执行（本 shell 的 PROXY_AGENT_DIR 已 readonly）
ROOT_CHECK_LINE=$(grep -F 'if [[ ! "${PROXY_AGENT_DIR}" =~' install.sh)
assert_not_empty "${ROOT_CHECK_LINE}" "抽到安装根合法性检查"
root_verdict() {
    env PROXY_AGENT_DIR="$1" bash -c "${ROOT_CHECK_LINE} echo reject; else echo accept; fi"
}
for _root in /etc/Proxy-agent /opt/pa /srv/.hidden/pa; do
    assert_equals "accept" "$(root_verdict "${_root}")" "安装根 ${_root} 合法"
done
for _root in / /opt /etc/.. "/a b/c" relative/x '/opt/pa*' /etc/Proxy-agent/..; do
    assert_equals "reject" "$(root_verdict "${_root}")" "安装根 ${_root} 被拒绝（unInstall 会 rm -rf 它）"
done

# readInstallProtocolType 自带一份「文件名 → ID」表，registry 是另一份：跑原文逐个对拍。
# 安装根名含点、也含协议 stem（根校验都收），扫描只能认文件名
SCAN_FN=$(sed -n '/^readInstallProtocolType() {/,/^}/p' install.sh)
assert_not_empty "${SCAN_FN}" "readInstallProtocolType：抽到函数原文"
SCAN_DIR="${MOCK_ROOT}/pa.tuic_inbounds/xray/conf"
scan_protocols() (
    coreKind=1; configPath="${SCAN_DIR}/"; singBoxConfigPath=
    eval "${SCAN_FN}"
    readInstallProtocolType 2>/dev/null
    printf '%s' "${currentInstallProtocolType}"
)
SCAN_MISMATCH=$(for _pid in $(seq 0 30); do
    _file=$(getProtocolConfigFileName "${_pid}") || continue
    _want=",${_pid},"
    [[ "${_pid}" == "20" ]] && _want=","   # 20（socks5）全仓没有生产者，扫描也不认
    rm -rf "${SCAN_DIR}" && mkdir -p "${SCAN_DIR}"
    printf '{"inbounds":[]}\n' >"${SCAN_DIR}/${_file}"
    _got=$(scan_protocols)
    [[ "${_got}" == "${_want}" ]] || echo "${_file}: 扫出 ${_got}，应为 ${_want}"
done)
assert_equals "" "${SCAN_MISMATCH}" "readInstallProtocolType：每个 registry 协议文件单独安装时，扫出且只扫出它自己的 ID"
rm -rf "${MOCK_ROOT}/pa.tuic_inbounds"
EMPTY_SCAN_ERR=$( (coreKind=; configPath=; singBoxConfigPath=; eval "${SCAN_FN}"; readInstallProtocolType) 2>&1 >/dev/null )
assert_equals "" "${EMPTY_SCAN_ERR}" "readInstallProtocolType：未安装（configPath 为空）时不报错"

# 分享链接与订阅里的 sid 取自 currentRealityShortId；读漏了，服务端的 shortId 白名单不认空串、连不上
REALITY_SCAN_DIR="${MOCK_ROOT}/reality-scan/"
mkdir -p "${REALITY_SCAN_DIR}"
read_reality_sid() (
    coreKind="$1"; configPath="${REALITY_SCAN_DIR}"; singBoxConfigPath=
    eval "${SCAN_FN}"
    readInstallProtocolType 2>/dev/null
    printf '%s' "${currentRealityShortId}"
)
printf '%s\n' '{"inbounds":[{"port":443},{"streamSettings":{"realitySettings":{"shortIds":["aaaa000011112222","bbbb"]}}}]}' \
    >"${REALITY_SCAN_DIR}07_VLESS_vision_reality_inbounds.json"
assert_equals "aaaa000011112222" "$(read_reality_sid 1)" "readInstallProtocolType：Xray Reality 读出第一个 shortId"
printf '%s\n' '{"inbounds":[{"listen_port":443,"tls":{"server_name":"a.example","reality":{"handshake":{"server_port":443},"short_id":["cccc333344445555","dddd"]}}}]}' \
    >"${REALITY_SCAN_DIR}07_VLESS_vision_reality_inbounds.json"
assert_equals "cccc333344445555" "$(read_reality_sid 2)" "readInstallProtocolType：sing-box Reality 读出第一个 short_id"
rm -rf "${REALITY_SCAN_DIR}"

# 含点的安装根走完整链路：探测内核 → 扫协议 → 账户事务，新用户要真的写进去
DOTTED_ROOT="${MOCK_ROOT}/dotted.root"
mkdir -p "${DOTTED_ROOT}/xray/conf" && : >"${DOTTED_ROOT}/xray/xray"
printf '%s\n' '{"inbounds":[{"port":443,"settings":{"clients":[{"id":"a1","email":"alice"}]}}]}' \
    >"${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
DOTTED_FNS=$(sed -n '/^readInstallType() {/,/^}/p;/^readInstallProtocolType() {/,/^}/p;/^initXrayClients() {/,/^}/p;/^applyAccountChangeAllProtocols() {/,/^}/p;/^xrayConfigTest() {/,/^}/p' install.sh)
env PROXY_AGENT_DIR="${DOTTED_ROOT}" DOTTED_FNS="${DOTTED_FNS}" bash -c '
    source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
    eval "${DOTTED_FNS}"
    readInstallType; readInstallProtocolType
    currentClients="[{\"uuid\":\"a1\",\"name\":\"alice\"}]"
    applyAccountChangeAllProtocols add b2 bob' >/dev/null 2>&1
assert_equals '["a1","b2"]' "$(jq -c '[.inbounds[0].settings.clients[].id]' "${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" \
    "安装根含点：添加用户真的写进已装协议"

# 按名字删：两个协议文件里同一批用户顺序相反，按下标删会删错人，按名字删两边都删对
printf '%s\n' '{"inbounds":[{"port":443,"settings":{"clients":[{"id":"a1","email":"alice-VLESS_TCP/TLS_Vision"},{"id":"b2","email":"bob-VLESS_TCP/TLS_Vision"},{"id":"c3","email":"carol-VLESS_TCP/TLS_Vision"}]}}]}' \
    >"${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
printf '%s\n' '{"inbounds":[{"port":31297,"settings":{"clients":[{"id":"c3","email":"carol-VLESS_WS"},{"id":"b2","email":"bob-VLESS_WS"},{"id":"a1","email":"alice-VLESS_WS"}]}}]}' \
    >"${DOTTED_ROOT}/xray/conf/03_VLESS_WS_inbounds.json"
env PROXY_AGENT_DIR="${DOTTED_ROOT}" DOTTED_FNS="${DOTTED_FNS}" bash -c '
    source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
    eval "${DOTTED_FNS}"
    readInstallType; readInstallProtocolType
    applyAccountChangeAllProtocols delName bob' >/dev/null 2>&1
assert_equals "0" "$?" "账户事务 delName：返回 0"
assert_equals '["a1","c3"]' "$(jq -c '[.inbounds[0].settings.clients[].id]' "${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" \
    "账户事务 delName：前置协议文件里 bob 没了、其余顺序不变"
assert_equals '["c3","a1"]' "$(jq -c '[.inbounds[0].settings.clients[].id]' "${DOTTED_ROOT}/xray/conf/03_VLESS_WS_inbounds.json")" \
    "账户事务 delName：顺序相反的第二个文件里删的也是 bob"
env PROXY_AGENT_DIR="${DOTTED_ROOT}" DOTTED_FNS="${DOTTED_FNS}" bash -c '
    source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
    eval "${DOTTED_FNS}"
    readInstallType; readInstallProtocolType
    applyAccountChangeAllProtocols del 1' >/dev/null 2>&1
assert_equals "1" "$?" "账户事务：旧的按下标 del 动作被拒绝"
assert_equals '["a1","c3"]' "$(jq -c '[.inbounds[0].settings.clients[].id]' "${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" \
    "账户事务：被拒绝的动作不碰文件"
rm -f "${DOTTED_ROOT}/xray/conf/03_VLESS_WS_inbounds.json"
printf '%s\n' '{"inbounds":[{"port":443,"settings":{"clients":[{"id":"a1","email":"alice"},{"id":"b2","email":"bob"}]}}]}' \
    >"${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"

# 15 走同一个事务：加人写进它的入站，后缀对得上才删得掉；文件名不能被 12 的探测吞掉
printf '%s\n' '{"inbounds":[{"port":31307,"settings":{"clients":[{"id":"a1","email":"alice-VLESS_XHTTP_TLS"}]}}]}' \
    >"${DOTTED_ROOT}/xray/conf/15_VLESS_XHTTP_TLS_inbounds.json"
run_dotted_15() {
    env PROXY_AGENT_DIR="${DOTTED_ROOT}" DOTTED_FNS="${DOTTED_FNS}" bash -c '
        source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
        eval "${DOTTED_FNS}"
        readInstallType; readInstallProtocolType
        echo "${currentInstallProtocolType}"
        currentClients="[{\"uuid\":\"a1\",\"name\":\"alice\"}]"
        [[ -z "$1" ]] || applyAccountChangeAllProtocols "$@" >/dev/null 2>&1' _ "$@" 2>/dev/null
}
assert_equals ",0,15," "$(run_dotted_15)" "readInstallProtocolType：认出 15，不当成 12"
run_dotted_15 add c3 carol >/dev/null
assert_equals '["alice-VLESS_XHTTP_TLS","carol-VLESS_XHTTP_TLS"]' "$(jq -c '[.inbounds[0].settings.clients[].email]' "${DOTTED_ROOT}/xray/conf/15_VLESS_XHTTP_TLS_inbounds.json")" \
    "账户事务：加人写进 15，后缀是 VLESS_XHTTP_TLS"
run_dotted_15 delName carol >/dev/null
assert_equals '["alice-VLESS_XHTTP_TLS"]' "$(jq -c '[.inbounds[0].settings.clients[].email]' "${DOTTED_ROOT}/xray/conf/15_VLESS_XHTTP_TLS_inbounds.json")" \
    "账户事务：按名删人，15 里也没了"
rm -f "${DOTTED_ROOT}/xray/conf/15_VLESS_XHTTP_TLS_inbounds.json"
printf '%s\n' '{"inbounds":[{"port":443,"settings":{"clients":[{"id":"a1","email":"alice"},{"id":"b2","email":"bob"}]}}]}' \
    >"${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"

# 16 有两层用户：事务只写外层，内层跟着重写，uPSK 由外层密码派生；只删一层的话被删的人还能走另一层的密钥
ST_ROOT="${MOCK_ROOT}/shadowtls.root"
rm -rf "${ST_ROOT}" && mkdir -p "${ST_ROOT}/sing-box/conf/config" && : >"${ST_ROOT}/sing-box/sing-box" && : >"${ST_ROOT}/sing-box/conf/config.json"
printf '%s\n' '{"inbounds":[{"type":"shadowtls","listen_port":443,"users":[{"name":"alice-ShadowTLS","password":"a1"}]},{"type":"shadowsocks","password":"k","users":[]}]}' \
    >"${ST_ROOT}/sing-box/conf/config/16_shadowtls_inbounds.json"
ST_FNS="${DOTTED_FNS}"$'\n'"$(sed -n '/^initSingBoxClients() {/,/^}/p;/^shadowTlsUserKey() {/,/^}/p;/^shadowTlsWithInnerUsers() {/,/^}/p' install.sh)"
run_st() {
    env PROXY_AGENT_DIR="${ST_ROOT}" ST_FNS="${ST_FNS}" bash -c '
        source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
        eval "${ST_FNS}"
        singBoxMergeConfig() { return 0; }
        readInstallType; readInstallProtocolType
        echo "${currentInstallProtocolType} ${frontingType}"
        currentClients="$(jq -c .inbounds[0].users "${singBoxConfigPath}16_shadowtls_inbounds.json")"
        [[ -z "$1" ]] || applyAccountChangeAllProtocols "$@" >/dev/null 2>&1' _ "$@" 2>/dev/null
}
ST_FILE="${ST_ROOT}/sing-box/conf/config/16_shadowtls_inbounds.json"
assert_equals ",16, 16_shadowtls_inbounds" "$(run_st)" "readInstallProtocolType：认出 16，身份源是外层（密码就是 UUID）"
run_st add c3 carol >/dev/null
assert_equals '["alice-ShadowTLS","carol-ShadowTLS"]' "$(jq -c '[.inbounds[0].users[].name]' "${ST_FILE}")" "账户事务：加人写进 16 的外层"
assert_equals '["alice-ShadowTLS","carol-ShadowTLS"]' "$(jq -c '[.inbounds[1].users[].name]' "${ST_FILE}")" "账户事务：内层名字跟外层一样（auth_user 只认内层）"
assert_equals "$(printf '%s' c3 | openssl dgst -sha256 -binary | head -c 16 | base64)" "$(jq -r '.inbounds[1].users[1].password' "${ST_FILE}")" "账户事务：内层 uPSK 是 16 字节，由外层密码哈希派生"
run_st delName carol >/dev/null
assert_equals '["alice-ShadowTLS"]|["alice-ShadowTLS"]' "$(jq -c '[.inbounds[0].users[].name]' "${ST_FILE}")|$(jq -c '[.inbounds[1].users[].name]' "${ST_FILE}")" "账户事务：删人两层都没了"
# 14 + 16 都在时身份源要是 16：14 的 password 是派生 uPSK，拿它当 UUID 会把所有人的密码换掉
printf '%s\n' '{"inbounds":[{"listen_port":1,"users":[{"name":"alice-SS2022","password":"derived"}]}]}' >"${ST_ROOT}/sing-box/conf/config/14_ss2022_inbounds.json"
assert_equals ",14,16, 16_shadowtls_inbounds" "$(run_st)" "readInstallProtocolType：14 与 16 同在时身份源是 16"
rm -rf "${ST_ROOT}"

# 生成器回归成空数组时，事务必须拒绝提交，而不是把该协议的用户清空再报成功
env PROXY_AGENT_DIR="${DOTTED_ROOT}" DOTTED_FNS="${DOTTED_FNS}" bash -c '
    source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
    eval "${DOTTED_FNS}"
    initXrayClients() { echo "[]"; }
    readInstallType; readInstallProtocolType
    applyAccountChangeAllProtocols add c3 carol' >/dev/null 2>&1
assert_equals "1" "$?" "账户事务：生成器给出空用户列表时返回 1"
assert_equals '["a1","b2"]' "$(jq -c '[.inbounds[0].settings.clients[].id]' "${DOTTED_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" \
    "账户事务：生成器给出空用户列表时原有用户原样保留"
rm -rf "${DOTTED_ROOT}"

# registry 自己的两张表（ID → 文件名、文件名 → ID）必须互为逆映射：错一格，账户操作就静默写错文件
REGISTRY_ROUNDTRIP=$(for _pid in $(sed -n '/^getProtocolConfigFileName() {/,/^}/p' lib/protocol-registry.sh |
    sed -n -E 's/^ *([0-9]+)\) *echo "[^"]+".*/\1/p'); do
    _back=$(parseProtocolIdFromFileName "$(getProtocolConfigFileName "${_pid}")") || _back="unknown"
    [[ "${_back}" == "${_pid}" ]] || echo "${_pid} -> $(getProtocolConfigFileName "${_pid}") -> ${_back}"
done)
assert_equals "" "${REGISTRY_ROUNDTRIP}" "registry：getProtocolConfigFileName 与 parseProtocolIdFromFileName 互为逆映射"

echo ""

# ============================================================================
# 写侧：initXrayClients / initSingBoxClients 产出的用户对象带 registry 声明的身份与显示名字段
# ============================================================================

echo -e "${BLUE}[clients] 写侧用户字段 ↔ registry 账户列${NC}"

CLIENTS_FNS=$(sed -n '/^initXrayClients() {/,/^}/p;/^initSingBoxClients() {/,/^}/p' install.sh)
assert_not_empty "${CLIENTS_FNS}" "抽到 initXrayClients / initSingBoxClients 原文"

render_clients() (
    currentClients='[{"uuid":"11111111-2222-3333-4444-555555555555","name":"alice-VLESS_TCP/TLS_Vision"}]'
    eval "${CLIENTS_FNS}"
    if [[ "$1" == "1" ]]; then initXrayClients "$2"; else initSingBoxClients "$2"; fi
)

# 每个内核上该产出用户的协议独立写死（加协议时同步）：删掉一个活分支，产出集合就对不上
CLIENTS_LIVE_1="0 1 3 4 6 7 9 12 15"
CLIENTS_LIVE_2="0 1 3 4 6 7 9 10 11 13 14 16 20"
REGISTRY_IDS=$(for _pid in $(seq 0 30); do getProtocolConfigFileName "${_pid}" >/dev/null && echo "${_pid}"; done)
for _core in 1 2; do
    _produced=""
    for _pid in ${REGISTRY_IDS}; do
        _keys=$(render_clients "${_core}" "${_pid}" 2>/dev/null | jq -r '.[0] // empty | keys[]' 2>/dev/null | tr '\n' ' ')
        [[ -z "${_keys}" ]] && continue
        _produced="${_produced} ${_pid}"
        _idField=$(getProtocolIdField "${_core}" "${_pid}") || _idField="(registry 无身份列)"
        _nameField=$(getProtocolNameField "${_core}" "${_pid}")
        assert_contains " ${_keys}" " ${_idField} " "core ${_core} id ${_pid}: 写侧带 registry 身份字段 ${_idField}"
        if [[ -n "${_nameField}" ]]; then
            assert_contains " ${_keys}" " ${_nameField} " "core ${_core} id ${_pid}: 写侧带 registry 显示名字段 ${_nameField}"
        fi
    done
    _live="CLIENTS_LIVE_${_core}"
    assert_equals "${!_live}" "${_produced# }" "core ${_core}：生成器产出用户的协议恰好是活组合"
done

# 写侧 email/name 的协议后缀 ↔ registry getProtocolEmailSuffix：拼车按 registry 拼账户名，两边漂移就永远对不上账
for _core in 1 2; do
    for _pid in ${REGISTRY_IDS}; do
        getProtocolNameField "${_core}" "${_pid}" >/dev/null 2>&1 || continue
        _name=$(render_clients "${_core}" "${_pid}" 2>/dev/null | jq -r '.[0] // empty | .email // .name // .username // empty' 2>/dev/null)
        [[ -z "${_name}" ]] && continue
        assert_equals "alice-$(getProtocolEmailSuffix "${_core}" "${_pid}")" "${_name}" "core ${_core} id ${_pid}: 写侧后缀 == registry getProtocolEmailSuffix"
    done
done

echo ""

# 拼车名单、Xray 可装协议、账户事务白名单是三份手写清单：Xray 能装却不在拼车名单里，那个入站里停用与删人都无效；
# 在拼车名单里却不在事务白名单里，对账的 set 会静默跳过它
echo -e "${BLUE}[carpool] 拼车协议名单 ↔ Xray 可装协议 ↔ 账户事务白名单${NC}"
CP_IDS=$(grep -oE '^readonly CARPOOL_PROTOCOLS=",[0-9,]+,"' lib/carpool.sh | grep -oE '[0-9]+' | sort -n | tr '\n' ' ')
XRAY_IDS=$(sed -n '/^customXrayInstall() {/,/^}/p' install.sh | grep -oE 'validateCustomInstallTokens "\$\{selectCustomInstallType\}"( [0-9]+)+' | grep -oE ' [0-9]+' | tr -d ' ' | sort -n | tr '\n' ' ')
TX_IDS=$(sed -n '/^applyAccountChangeAllProtocols() {/,/^}/p' install.sh | grep -E '^ +0 \|' | grep -oE '[0-9]+' | sort -n | tr '\n' ' ')
assert_not_empty "${XRAY_IDS}" "抽到 customXrayInstall 的可装协议清单"
assert_not_empty "${TX_IDS}" "抽到 applyAccountChangeAllProtocols 的协议白名单"
for _pid in ${XRAY_IDS}; do
    assert_contains " ${CP_IDS}" " ${_pid} " "Xray 可装的 ${_pid} 在拼车名单里"
done
for _pid in ${CP_IDS}; do
    assert_contains " ${TX_IDS}" " ${_pid} " "拼车名单里的 ${_pid} 在账户事务白名单里"
done

# 客户端对象写了两份（initXrayClients 与对账期望）：字段一漂移，对账次次判有变化，每个 tick 都重载、断所有人的连接
CP_SHAPE_STATE='{"members":{"alice":{"status":"active","protocols":"all","uuid":"11111111-2222-3333-4444-555555555555"}}}'
for _pid in ${CP_IDS}; do
    _written=$(render_clients 1 "${_pid}" 2>/dev/null)
    assert_equals "1" "$(jq 'length' <<<"${_written}" 2>/dev/null)" "id ${_pid}: initXrayClients 写出一个 client"
    _map=$(jq -nc --arg k "${_pid}" --argjson v "${_written:-null}" '{($k): $v}')
    assert_equals "rc=0" "$(source lib/carpool.sh; carpoolReconcilePayload "${CP_SHAPE_STATE}" "${_map}"; echo "rc=$?")" \
        "id ${_pid}: initXrayClients 写出的 client 对账判无变化"
done

echo ""

# ============================================================================
# lib 模块清单：install.sh 里每一处手打的清单都必须与 ls lib/ 一致（自举健康检查、损坏清理、raw 文件表、
# source 顺序、回滚下载、自更新下载、doctor 各有一份，少一处新模块就在那条路径上不落地）
# ============================================================================

echo -e "${BLUE}[lib] 模块清单 ↔ ls lib/${NC}"

LIB_ON_DISK=$(ls lib/*.sh | sed 's#^lib/##; s/\.sh$//' | sort | tr '\n' ' ')
LIB_LIST_LINES=$(grep -nE 'for [_a-z]+ in i18n constants [a-z -]+; do|libFiles=\(' install.sh)
assert_equals "8" "$(wc -l <<<"${LIB_LIST_LINES}" | tr -d ' ')" "install.sh 里有 8 处模块清单"
while IFS= read -r _line; do
    _mods=$(sed -E 's/.* in (i18n[a-z -]*); do.*/\1/; s/.*libFiles=\(([^)]*)\).*/\1/; s/\.sh//g' <<<"${_line}" | tr ' ' '\n' | sort | tr '\n' ' ')
    assert_equals "${LIB_ON_DISK}" "${_mods}" "模块清单与 lib/ 一致: install.sh:${_line%%:*}"
done <<<"${LIB_LIST_LINES}"
for _m in ${LIB_ON_DISK}; do
    assert_equals "yes" "$(grep -qF -- "${_m}.sh" install.sh && echo yes || echo no)" "install.sh 里写着 ${_m}.sh（从 GitHub 回滚靠它判断目标版本有没有这个模块）"
done
assert_contains "$(sed -n '/^_required_lib_fns=(/,/^)/p' install.sh)" "carpoolJudge" "_required_lib_fns 含拼车入口函数，lib/carpool.sh 没加载会在启动时报出"

echo ""

# ============================================================================
# 拼车：ensure 钩子、set 事务、tick、占位、cron 分支、快照（抽 install.sh 原文；服务、crontab、xray 二进制都桩掉）
# ============================================================================

echo -e "${YELLOW}=== 测试拼车钩子与 tick ===${NC}"

CP_FN_NAMES="applyAccountChangeAllProtocols carpoolSyncUserinfo xrayConfigTest readInstallType readInstallProtocolType carpoolLock carpoolUnlock carpoolEnabled xrayDaemonRunning carpoolCurrentClientsMap ensureCarpoolCron ensureCarpoolXray carpoolReconcile carpoolCollect carpoolMachineStep carpoolCollectBeforeStop carpoolSubscribeMd5 carpoolMemberPageKey carpoolWritePlaceholders carpoolRefreshSubscribe carpoolJudgeAndWrite carpoolSetNotified carpoolSettle carpoolTick carpoolRefuseIfEnabled carpoolGuardAccountMenu carpoolCheckPrerequisites carpoolPickApiPort carpoolApiReady carpoolAllAccounts carpoolFillUuids carpoolRemoveCron carpoolRemoveSubscriptionFiles carpoolConfirmReenable carpoolEnable carpoolDisable carpoolHasTty carpoolApply carpoolResetUsage carpoolShowUsage carpoolWritePage carpoolRemovePages carpoolReloadNginx carpoolInsertPageBlock carpoolEnsureNginxLocation carpoolPendingText carpoolRenderPages carpoolPageUrlBase carpoolShowPageLinks carpoolPageSetToken carpoolPageEnable carpoolPageDisable carpoolTelegramSend carpoolNotifyEvents carpoolTickExitTrap carpoolTelegramMask carpoolTelegramConfigure carpoolTelegramTest carpoolTelegramDisable carpoolPageMenu carpoolMembersClean carpoolMembersEditApply carpoolPickMember carpoolAsk carpoolShowProtocolChoices carpoolShowMemberLinks carpoolMemberAdd carpoolMemberEdit carpoolMemberMenu carpoolMenu addUser removeUser cronFunction backupConfigSnapshot restoreConfigSnapshot installCronTLS removeOwnCronEntries chainAccountStateFile chainAccountReadState chainAccountBridges writeXrayChainConfig chainAccountForget"
CP_FNS=$(sed -n "$(for _f in ${CP_FN_NAMES}; do printf '/^%s() {/,/^}/p\n' "${_f}"; done)" install.sh)
assert_not_empty "${CP_FNS}" "拼车：抽到 install.sh 原文"
assert_equals "$(wc -w <<<"${CP_FN_NAMES}" | tr -d ' ')" "$(grep -c '^[a-zA-Z0-9]*() {$' <<<"${CP_FNS}")" "拼车：每个函数都抽到了（抽不到说明函数体里出现了顶格的 }）"

CP_ROOT="${MOCK_ROOT}/carpool.root"
CP_TABLE="${MOCK_ROOT}/carpool_crontab"
CP_CALLS="${MOCK_ROOT}/carpool_calls"
CP_STATS="${MOCK_ROOT}/carpool_stats.json"
CP_NET="${MOCK_ROOT}/carpool_net.json"
CP_U1="11111111-1111-1111-1111-111111111111"
CP_U2="22222222-2222-2222-2222-222222222222"
GiB=1073741824
CP_PERIOD="$(date +%Y-%m)-01"
cp_md5() { if command -v md5sum >/dev/null 2>&1; then md5sum | awk '{print $1}'; else md5 -q; fi; }
CP_ALICE_MD5=$(printf 'alicetestsalt\n' | cp_md5)

# 模拟树：两个协议文件里 zed 是不归拼车管的账号，alice / bob 是成员；对象形状与 initXrayClients 一致，所以初始无漂移
cp_reset_tree() {
    rm -rf "${CP_ROOT}"
    mkdir -p "${CP_ROOT}/xray/conf" "${CP_ROOT}/carpool" "${CP_ROOT}/subscribe/default" "${CP_ROOT}/subscribe/clashMeta" \
        "${CP_ROOT}/subscribe/sing-box" "${CP_ROOT}/subscribe/sing-box_profiles" "${CP_ROOT}/subscribe_local"
    cat >"${CP_ROOT}/xray/xray" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "help run") echo "  -test" ;;
    "run -test") exit "${XRAY_TEST_RC:-0}" ;;
    "api statsquery") echo "statsquery $*" >>"${CP_CALLS}"; if [[ -s "${CP_STATS}" ]]; then cat "${CP_STATS}"; else exit 1; fi ;;
    "version ") echo "Xray ${CP_XRAY_VERSION:-26.3.27} (Xray, Penetrates Everything.) stub" ;;
    "uuid ") echo "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" ;;
esac
EOF
    chmod +x "${CP_ROOT}/xray/xray"
    jq -n --arg u1 "${CP_U1}" --arg u2 "${CP_U2}" '{inbounds: [{port: 443, protocol: "vless", settings: {clients: [
        {id: "zz", flow: "xtls-rprx-vision", email: "zed-VLESS_TCP/TLS_Vision"},
        {id: $u1, flow: "xtls-rprx-vision", email: "alice-VLESS_TCP/TLS_Vision"},
        {id: $u2, flow: "xtls-rprx-vision", email: "bob-VLESS_TCP/TLS_Vision"}], decryption: "none"}}]}' >"${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
    jq -n --arg u1 "${CP_U1}" --arg u2 "${CP_U2}" '{inbounds: [{port: 443, protocol: "dokodemo-door", settings: {}}, {protocol: "vless", settings: {clients: [
        {id: "zz", email: "zed-vless_reality_vision", flow: "xtls-rprx-vision"},
        {id: $u1, email: "alice-vless_reality_vision", flow: "xtls-rprx-vision"},
        {id: $u2, email: "bob-vless_reality_vision", flow: "xtls-rprx-vision"}], decryption: "none"}}]}' >"${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
    printf '%s\n' '{"policy":{"levels":{"0":{"handshake":2,"connIdle":280}}}}' >"${CP_ROOT}/xray/conf/12_policy.json"
    printf '%s\n' '{"notify": {"label": "车", "digestHour": null}, "members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
    jq -n --arg u1 "${CP_U1}" --arg u2 "${CP_U2}" --arg period "${CP_PERIOD}" --argjson q $((5 * GiB)) '{
        enabled: true, apiPort: 23456, period: $period, lastTick: "", resetDay: 1,
        notify: {label: "车", warnPercent: 80, digestHour: null, expireNoticeDays: 3},
        billing: "both", plan: {sizeGB: 0, warnPercent: 85, interface: ""}, machine: {},
        pageEnabled: false, pageToken: "", collectFailures: 0, notified: {}, events: [],
        members: {
          alice: {uuid: $u1, quotaBytes: $q, expire: "", protocols: "all", upBytes: 0, downBytes: 0, status: "active", reason: ""},
          bob: {uuid: $u2, quotaBytes: 0, expire: "", protocols: "all", upBytes: 0, downBytes: 0, status: "active", reason: ""}}}' >"${CP_ROOT}/carpool/state.json"
    echo testsalt >"${CP_ROOT}/subscribe_local/subscribeSalt"
    mkdir -p "${CP_ROOT}/nginx"
    cat >"${CP_ROOT}/nginx/subscribe.conf" <<'EOF'
server {
    listen 12345 ssl;
    server_name example.com;
    server_tokens off;
    root /usr/share/nginx/html;
    location ~ "^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([0-9a-f]{32})$" {
        default_type 'text/plain; charset=utf-8';
        alias /etc/Proxy-agent/subscribe/$1/$2;
    }
    location / {
    }
}
EOF
    : >"${CP_TABLE}"
    : >"${CP_CALLS}"
    rm -f "${CP_STATS}" "${CP_NET}"
}

# run_cp CMD → 在干净 bash 里以模拟树为安装根执行 CMD；可用环境变量：CP_CORE（内核）、CP_SUBPORT（订阅端口）、
# XRAY_TEST_RC（桩 xray 的 -test 退出码）、CP_RELOAD_INJECT（reloadCore 桩往 state 里塞一笔用量）。
# 整机读数取自 CP_NET 文件（carpoolMachineSample 的输出形状），文件不存在就当读不到网卡：不读宿主机的 /proc
run_cp() (
    env PROXY_AGENT_DIR="${CP_ROOT}" CP_FNS="${CP_FNS}" CP_TABLE="${CP_TABLE}" CP_CALLS="${CP_CALLS}" CP_STATS="${CP_STATS}" CP_NET="${CP_NET}" \
        V2RAY_LANG=zh_CN XRAY_TEST_RC="${XRAY_TEST_RC:-0}" CP_CORE="${CP_CORE:-1}" CP_SUBPORT="${CP_SUBPORT:-}" CP_RELOAD_INJECT="${CP_RELOAD_INJECT:-}" \
        CP_XRAY_VERSION="${CP_XRAY_VERSION:-26.3.27}" CP_CROND_RC="${CP_CROND_RC:-0}" CP_PROTOS="${CP_PROTOS:-}" \
        CP_SUBTYPE="${CP_SUBTYPE:-https}" CP_NGINX_T_RC="${CP_NGINX_T_RC:-0}" CP_CURL_FAIL="${CP_CURL_FAIL:-}" CP_ENV_RC="${CP_ENV_RC:-0}" bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh; source lib/carpool.sh
        eval "${CP_FNS}"
        export CP_CALLS CP_STATS XRAY_TEST_RC CP_XRAY_VERSION
        crontab() { case "$1" in -l) cat "${CP_TABLE}" 2>/dev/null ;; -) cat >"${CP_TABLE}" ;; *) cat "$1" >"${CP_TABLE}" ;; esac; }
        pgrep() { echo 4242; }
        command -v flock >/dev/null 2>&1 || flock() { :; }
        command -v md5sum >/dev/null 2>&1 || md5sum() { md5 -q "$@"; }
        listeningPorts() { jq -r ".api.listen // empty | sub(\".*:\"; \"\")" "${XRAY_CONF_DIR}/12_stats_api.json" 2>/dev/null; }
        curl() { printf "curl %s\n" "$*" >>"${CP_CALLS}"; if [[ -n "${CP_CURL_FAIL}" ]]; then return 7; fi; echo "{\"ok\":true}"; }
        ensureCronService() { return "${CP_CROND_RC}"; }
        manageAccount() { echo "MENU $*"; }
        reloadCore() {
            echo reloadCore >>"${CP_CALLS}"
            if [[ -n "${CP_RELOAD_INJECT}" ]]; then
                jq ".members.bob.upBytes += 100" "${CARPOOL_STATE_FILE}" >"${CARPOOL_STATE_FILE}.inj" && mv "${CARPOOL_STATE_FILE}.inj" "${CARPOOL_STATE_FILE}"
            fi
            ensureCarpoolXray >/dev/null 2>&1
        }
        readNginxSubscribe() { subscribePort="${CP_SUBPORT}"; subscribeType="${CP_SUBTYPE}"; }
        subscribe() { echo "subscribe $*" >>"${CP_CALLS}"; }
        singBoxMergeConfig() { :; }
        nginx() { echo "nginx $*" >>"${CP_CALLS}"; if [[ "$1" == "-t" ]]; then return "${CP_NGINX_T_RC}"; fi; }
        handleNginx() { echo "handleNginx $*" >>"${CP_CALLS}"; }
        carpoolXrayServiceEnv() { echo "serviceEnv $1" >>"${CP_CALLS}"; return "${CP_ENV_RC}"; }
        carpoolMachineSample() { echo "machineSample $1" >>"${CP_CALLS}"; [[ -s "${CP_NET}" ]] && cat "${CP_NET}"; }
        getPublicIP() { echo 203.0.113.9; }
        nginxConfigPath="${PROXY_AGENT_DIR}/nginx/"
        currentHost=example.com
        btDomain=; totalProgress=1
        readInstallType; readInstallProtocolType
        coreKind="${CP_CORE}"
        [[ -n "${CP_PROTOS}" ]] && currentInstallProtocolType="${CP_PROTOS}"
        eval "$1"' _ "$1"
)
cp_state() { jq -r "$1" "${CP_ROOT}/carpool/state.json"; }
cp_emails() { jq -c "$2 | [.[].email | sub(\"-[^-]*\$\"; \"\")]" "${CP_ROOT}/xray/conf/$1"; }
cp_inode() { ls -i "$1" | awk '{print $1}'; }

# --- ensureCarpoolXray：开着就补齐 ---
cp_reset_tree
_i02=$(cp_inode "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_equals "true|true|2|280" "$(jq -r '.policy.levels."0" | "\(.statsUserUplink)|\(.statsUserDownlink)|\(.handshake)|\(.connIdle)"' "${CP_ROOT}/xray/conf/12_policy.json")" \
    "ensure：policy 补上两个统计开关，原有 handshake / connIdle 不动"
assert_equals '{"api":{"listen":"127.0.0.1:23456","services":["StatsService"],"tag":"api"},"stats":{}}' "$(jq -Sc . "${CP_ROOT}/xray/conf/12_stats_api.json")" \
    "ensure：12_stats_api.json 只监听 127.0.0.1 的 apiPort、只开 StatsService"
assert_equals "*/5 * * * * PROXY_AGENT_DIR=${CP_ROOT} /bin/bash ${CP_ROOT}/install.sh CarpoolTick >> ${CP_ROOT}/crontab_carpool.log 2>&1" "$(cat "${CP_TABLE}")" \
    "ensure：cron 行带安装根前缀、每 5 分钟一次"
assert_equals "${_i02}" "$(cp_inode "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "ensure：无漂移时协议文件零写入（inode 不变）"
assert_contains "$(cat "${CP_CALLS}")" "serviceEnv on" "ensure：开着时给 Xray 服务带上关 splice 的环境"
_sig=$(cat "${CP_ROOT}/xray/conf/12_policy.json" "${CP_ROOT}/xray/conf/12_stats_api.json" "${CP_TABLE}" | cp_md5)
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_equals "${_sig}" "$(cat "${CP_ROOT}/xray/conf/12_policy.json" "${CP_ROOT}/xray/conf/12_stats_api.json" "${CP_TABLE}" | cp_md5)" "ensure：幂等，第二次不改任何东西"
sed -i.bak 's#^\*/5 #*/1 #' "${CP_TABLE}" && rm -f "${CP_TABLE}.bak"
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_equals "1" "$(grep -c 'install.sh CarpoolTick' "${CP_TABLE}")" "ensure：车主改过间隔的 CarpoolTick 行不会被再加一条"
assert_equals "1" "$(grep -c '^\*/1 ' "${CP_TABLE}")" "ensure：改过的间隔保留"
run_cp 'installCronTLS 1' >/dev/null 2>&1
assert_equals "1" "$(grep -c 'install.sh CarpoolTick' "${CP_TABLE}")" "installCronTLS 之后 CarpoolTick 行仍在"
assert_equals "1" "$(grep -c 'install.sh RenewTLS' "${CP_TABLE}")" "installCronTLS 自己的行照常加上"
run_cp 'removeOwnCronEntries' >/dev/null 2>&1
assert_equals "0" "$(grep -c 'install.sh' "${CP_TABLE}")" "removeOwnCronEntries 连 CarpoolTick 一起清掉"

# --- ensureCarpoolXray：关着就撤 ---
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
: >"${CP_CALLS}"
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_contains "$(cat "${CP_CALLS}")" "serviceEnv off" "ensure（关）：Xray 服务的关 splice 环境撤掉"
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "ensure（关）：12_stats_api.json 撤掉"
assert_equals '{"connIdle":280,"handshake":2}' "$(jq -Sc '.policy.levels."0"' "${CP_ROOT}/xray/conf/12_policy.json")" "ensure（关）：统计开关撤掉，其余字段原样"
rm -f "${CP_ROOT}/carpool/state.json"
printf '%s\n' '{"policy":{"levels":{"0":{"handshake":2,"statsUserUplink":true,"statsUserDownlink":true}}}}' >"${CP_ROOT}/xray/conf/12_policy.json"
: >"${CP_CALLS}"
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "ensure（没开过）：什么都不生成"
assert_equals "true|true" "$(jq -r '.policy.levels."0" | "\(.statsUserUplink)|\(.statsUserDownlink)"' "${CP_ROOT}/xray/conf/12_policy.json")" "ensure（没开过）：车主自己开的统计开关不动"
assert_equals "" "$(cat "${CP_CALLS}")" "ensure（没开过）：服务环境也不碰"
cp_reset_tree
rm -f "${CP_ROOT}/xray/conf/12_policy.json"
_out=$(run_cp 'ensureCarpoolXray; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "ensure：12_policy.json 缺失时返回 1、不自己造一份"
assert_contains "${_out}" "不存在，无法开启按用户统计" "ensure：缺 policy 时红字说清"
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_policy.json" ]] && echo yes || echo no)" "ensure：缺 policy 时不凭空创建"
cp_reset_tree
_out=$(CP_ENV_RC=1 run_cp 'ensureCarpoolXray; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "ensure：服务环境写不上时返回 1"
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "ensure：服务环境写不上时不开统计 API（计数不准就不计）"

# --- 账户事务 set ---
cp_reset_tree
_payload="${CP_ROOT}/payload.json"
jq -n --arg u1 "${CP_U1}" '{"7": [{id: $u1, email: "alice-vless_reality_vision", flow: "xtls-rprx-vision"}]}' >"${_payload}"
_before02=$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")
assert_equals "0" "$(run_cp "applyAccountChangeAllProtocols set ${_payload}" >/dev/null 2>&1; echo $?)" "set：返回 0"
assert_equals '["alice"]' "$(cp_emails 07_VLESS_vision_reality_inbounds.json '.inbounds[1].settings.clients')" "set：07 的 clients 整组换成载荷"
assert_equals "${_before02}" "$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "set：载荷里没有的 02 一个字节不动"
assert_equals "0" "$(ls "${CP_ROOT}/xray/conf/"*.bak.* 2>/dev/null | wc -l | tr -d ' ')" "set：不留 .bak"
printf '%s\n' '{"12": []}' >"${_payload}"
assert_equals "0" "$(run_cp "applyAccountChangeAllProtocols set ${_payload}" >/dev/null 2>&1; echo $?)" "set：载荷里是没装的协议时直接返回 0"
printf '%s\n' '[1,2]' >"${_payload}"
assert_equals "1" "$(run_cp "applyAccountChangeAllProtocols set ${_payload}" >/dev/null 2>&1; echo $?)" "set：载荷不是对象返回 1"
printf '%s\n' '{"0": []}' >"${_payload}"
assert_equals "0" "$(run_cp "applyAccountChangeAllProtocols set ${_payload}" >/dev/null 2>&1; echo $?)" "set：空数组合法（能不能起由 -test 兜底）"
assert_equals "0" "$(jq '.inbounds[0].settings.clients | length' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "set：02 的 clients 清空"
cp_reset_tree
printf '%s\n' '{"0": [{"id": "x", "email": "x-VLESS_TCP/TLS_Vision"}]}' >"${_payload}"
_before02=$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")
assert_equals "1" "$(XRAY_TEST_RC=1 run_cp "applyAccountChangeAllProtocols set ${_payload}" >/dev/null 2>&1; echo $?)" "set：内核校验不过返回 1"
assert_equals "${_before02}" "$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "set：内核校验不过整体回滚"

# --- tick：alice 超额 ---
cp_reset_tree
jq -n --argjson six $((6 * GiB)) '{stat: [
    {name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six},
    {name: "user>>>alice-vless_reality_vision>>>traffic>>>downlink", value: "1"},
    {name: "user>>>bob-VLESS_TCP/TLS_Vision>>>traffic>>>uplink"},
    {name: "user>>>zed-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: 5},
    {name: "inbound>>>VLESSTCP>>>traffic>>>uplink", value: 99}]}' >"${CP_STATS}"
_out=$(run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "tick：正常返回 0"
assert_contains "${_out}" "alice 已停用（流量已用尽）" "tick：日志里有停用事件"
assert_equals "disabled|quota|$((6 * GiB))|1" "$(cp_state '.members.alice | "\(.status)|\(.reason)|\(.upBytes)|\(.downBytes)"')" "tick：alice 用量累加并因超额停用"
assert_equals "active|0|0" "$(cp_state '.members.bob | "\(.status)|\(.upBytes)|\(.downBytes)"')" "tick：bob 不动"
assert_equals "0" "$(cp_state '.collectFailures')" "tick：采集成功，失败计数归零"
assert_not_empty "$(cp_state '.lastTick')" "tick：lastTick 写上"
assert_equals "disabled|alice|quota" "$(cp_state '.events[-1] | "\(.type)|\(.name)|\(.reason)"')" "tick：事件记进 state.events"
assert_equals '["zed","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "tick：02 里 alice 被摘掉，外部账号 zed 与 bob 保留且顺序不变"
assert_equals '["zed","bob"]' "$(cp_emails 07_VLESS_vision_reality_inbounds.json '.inbounds[1].settings.clients')" "tick：07 同样摘掉 alice"
assert_equals "1" "$(grep -c '^statsquery .*-s 127.0.0.1:23456 .*-pattern user>>> -reset' "${CP_CALLS}")" "tick：按 apiPort 查 user>>> 并 -reset"
assert_equals "1" "$(grep -c '^reloadCore$' "${CP_CALLS}")" "tick：有变更时重载一次"
assert_equals "0" "$(grep -c '^subscribe' "${CP_CALLS}")" "tick：只有停用、没有恢复，不重建订阅"
for _d in default clashMeta sing-box sing-box_profiles; do
    assert_equals "yes" "$([[ -s "${CP_ROOT}/subscribe/${_d}/${CP_ALICE_MD5}" ]] && echo yes || echo no)" "tick：占位 ${_d}/<md5(订阅键+salt)> 已写"
done
assert_contains "$(base64 -d <"${CP_ROOT}/subscribe/default/${CP_ALICE_MD5}")" "vless://00000000-0000-0000-0000-000000000000@127.0.0.1:1" "tick：default 占位是指向 127.0.0.1:1 的 vless"
assert_equals "0" "$(ls "${CP_ROOT}/carpool/".set.* 2>/dev/null | wc -l | tr -d ' ')" "tick：set 载荷的临时文件已清掉"

# 第二次 tick：没有增量、没有漂移 → 协议文件零写入、不重载
: >"${CP_CALLS}"; printf '%s\n' '{}' >"${CP_STATS}"
_i02=$(cp_inode "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"); _i07=$(cp_inode "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")
assert_equals "0" "$(run_cp 'carpoolTick' >/dev/null 2>&1; echo $?)" "tick（无变化）：返回 0"
assert_equals "${_i02}|${_i07}" "$(cp_inode "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")|$(cp_inode "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")" "tick（无变化）：协议文件 inode 不变，零写入"
assert_equals "0" "$(grep -c '^reloadCore$' "${CP_CALLS}")" "tick（无变化）：不重载"
assert_equals "disabled|quota" "$(cp_state '.members.alice | "\(.status)|\(.reason)"')" "tick（无变化）：alice 仍停用"

# reload 期间 stop 钩子又写了一笔 state：tick 之后那笔不能被旧副本盖掉
cp_reset_tree
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
CP_RELOAD_INJECT=1 run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "100" "$(cp_state '.members.bob.upBytes')" "tick：reload 之后不再用旧副本写 state（stop 钩子写入的用量保留）"

# Xray 没在跑：不算采集失败、不去查
cp_reset_tree
jq -n '{stat: [{name: "user>>>bob-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: 9}]}' >"${CP_STATS}"
assert_equals "0" "$(run_cp 'pgrep() { :; }; carpoolTick' >/dev/null 2>&1; echo $?)" "tick（Xray 停着）：返回 0"
assert_equals "0|0" "$(cp_state '"\(.collectFailures)|\(.members.bob.upBytes)"')" "tick（Xray 停着）：不算采集失败、也不记用量"
assert_equals "0" "$(grep -c statsquery "${CP_CALLS}")" "tick（Xray 停着）：不去查 StatsService"

# 采集失败只计数，照常判定；members.json 坏了只告警、沿用上次限额
cp_reset_tree
rm -f "${CP_STATS}"
_out=$(run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "tick（采集失败）：返回 0"
assert_equals "1" "$(cp_state '.collectFailures')" "tick（采集失败）：失败计数 +1"
assert_contains "${_out}" "统计采集失败（连续 1 次）" "tick（采集失败）：日志一行"
cp_reset_tree
printf '%s\n' '{"members": {"alice": {"quotaGiB": "oops"}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "tick（文件无效）：返回 0"
assert_contains "${_out}" "校验未通过，本次沿用上次已应用的限额" "tick（文件无效）：告警一行"
assert_contains "${_out}" "quotaGiB 必须是非负整数" "tick（文件无效）：附上原因"
assert_equals "$((5 * GiB))" "$(cp_state '.members.alice.quotaBytes')" "tick（文件无效）：限额沿用 state 里的"
cp_reset_tree
printf '%s\n' '{"resetDay": 20, "notify": {"warnPercent": 10}, "members": {"alice": {"quotaGiB": 50, "expire": "2099-01-01"}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "$((50 * GiB))|2099-01-01|1|10" "$(cp_state '"\(.members.alice.quotaBytes)|\(.members.alice.expire)|\(.resetDay)|\(.notify.warnPercent)"')" "tick：即时类字段（配额、到期、notify）从文件同步进 state；resetDay 要应用才生效，tick 不动它"

# 没开 / 不是 Xray：静默退出，不碰 state
cp_reset_tree
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_iState=$(cp_inode "${CP_ROOT}/carpool/state.json")
assert_equals "0|" "$(run_cp 'carpoolTick' 2>&1; echo "$?|")" "tick（关着）：静默返回 0"
assert_equals "${_iState}" "$(cp_inode "${CP_ROOT}/carpool/state.json")" "tick（关着）：state 不写"
# 开头看到还开着，等锁时被关掉：关闭时恢复的人（配额已超、到期已过）不能又被判停用
cp_reset_tree
jq -n '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: 1}]}' >"${CP_STATS}"
jq '.members.alice.expire = "2000-01-01" | .members.alice.upBytes = 53687091200' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
: >"${CP_CALLS}"
run_cp 'carpoolLock() { jq ".enabled = false" "${CARPOOL_DIR}/state.json" >"${CARPOOL_DIR}/s.tmp" && mv "${CARPOOL_DIR}/s.tmp" "${CARPOOL_DIR}/state.json"; }; carpoolTick' >/dev/null 2>&1
assert_equals "false|active" "$(cp_state '"\(.enabled)|\(.members.alice.status)"')" "tick（等锁时被关掉）：关闭时恢复的人不再被判停用"
assert_equals "" "$(cp_state '.lastTick')" "tick（等锁时被关掉）：不判定、不写 state"
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "tick（等锁时被关掉）：入站里还有他"
assert_equals "0" "$(grep -c 'statsquery\|^reloadCore$' "${CP_CALLS}")" "tick（等锁时被关掉）：不采集、不重载"
cp_reset_tree
_out=$(CP_CORE=2 run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "tick（内核不是 Xray）：返回 0"
assert_contains "${_out}" "拼车已失效" "tick（内核不是 Xray）：说明原因"

# 恢复路径：配额调高 → 放回协议文件、重建订阅（只在订阅已装时）
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{"billing": "out", "members": {"alice": {"quotaGiB": 10}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(CP_SUBPORT=12345 run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "alice 已恢复" "tick（恢复）：日志里有恢复事件"
assert_equals "active|" "$(cp_state '.members.alice | "\(.status)|\(.reason)"')" "tick（恢复）：配额调高后 alice 恢复"
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "tick（恢复）：alice 按 members 顺序放回 02"
assert_equals "${CP_U1}" "$(jq -r '.inbounds[1].settings.clients[1].id' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")" "tick（恢复）：07 里放回的是 state 里的 uuid"
assert_equals "1" "$(grep -c '^subscribe false true$' "${CP_CALLS}")" "tick（恢复）：订阅已装时以 subscribe false true 重建"
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
printf '%s\n' '{"billing": "out", "members": {"alice": {"quotaGiB": 10}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(grep -c '^subscribe' "${CP_CALLS}")" "tick（恢复）：没装订阅就不调 subscribe（它会在 cron 下交互）"

# stop 钩子：把内存里的计数收进 state
cp_reset_tree
jq -n '{stat: [{name: "user>>>bob-VLESS_TCP/TLS_Vision>>>traffic>>>downlink", value: 77}]}' >"${CP_STATS}"
run_cp 'carpoolCollectBeforeStop' >/dev/null 2>&1
assert_equals "77" "$(cp_state '.members.bob.downBytes')" "carpoolCollectBeforeStop：停 Xray 前采一次进 state"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
: >"${CP_CALLS}"
run_cp 'carpoolCollectBeforeStop' >/dev/null 2>&1
assert_equals "0" "$(grep -c statsquery "${CP_CALLS}")" "carpoolCollectBeforeStop：关着就不查"

# 计费口径：文件里的 billing 每个 tick 同步进 state，判定按它乘；state 里存的仍是原始字节
cp_reset_tree
jq -n --argjson three $((3 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $three}]}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "both|disabled|quota|$((3 * GiB))" "$(cp_state '"\(.billing)|\(.members.alice.status)|\(.members.alice.reason)|\(.members.alice.upBytes)"')" \
    "口径（不写即 both）：3 GiB 按 6 GiB 计，超过 5 GiB 配额即停用，state 存原始字节"
cp_reset_tree
printf '%s\n' '{"billing": "out", "notify": {"label": "车", "digestHour": null}, "members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
jq -n --argjson three $((3 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $three}]}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "out|active" "$(cp_state '"\(.billing)|\(.members.alice.status)"')" "口径 out：同样的 3 GiB 按原值计，不停用"

# 整机：第一次读数只记基线；之后按增量累加；到套餐的 warnPercent 预警一次；重启按 bootId 认出
cp_net() { jq -n --arg b "$1" --argjson rx "$2" --argjson tx "$3" '{bootId: $b, counters: {eth0: {rx: $rx, tx: $tx}}}' >"${CP_NET}"; }
cp_reset_tree
printf '%s\n' '{"plan": {"sizeGB": 1}, "notify": {"label": "车", "digestHour": null}, "members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
cp_net b1 5000000000 6000000000
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals '["eth0"]|0|0|6000000000' "$(cp_state '"\(.machine.ifaces | tojson)|\(.machine.rx)|\(.machine.tx)|\(.machine.last.eth0.tx)"')" "整机：第一次读数只记基线，不加"
assert_equals "1" "$(grep -c '^machineSample $' "${CP_CALLS}")" "整机：plan 没写 interface 时按默认路由取"
cp_net b1 5400000000 6500000000
_out=$(run_cp 'carpoolTick' 2>&1)
assert_equals "400000000|500000000" "$(cp_state '"\(.machine.rx)|\(.machine.tx)"')" "整机：同一次开机按增量累加"
assert_contains "${_out}" "整机本周期已用套餐的 90%（900 MB / 1 GB）" "整机：both 下收发合计 900 MB 是 1 GB 套餐的 90%，过 85% 预警"
assert_equals "true" "$(cp_state '.notified["plan:warn"]')" "整机：预警的去重键记下"
cp_net b1 5450000000 6550000000
_out=$(run_cp 'pgrep() { :; }; carpoolTick' 2>&1)
assert_equals "450000000|550000000" "$(cp_state '"\(.machine.rx)|\(.machine.tx)"')" "整机：Xray 没在跑也照样读网卡"
assert_equals "0" "$(grep -c '整机本周期已用套餐' <<<"${_out}")" "整机：同一周期不再重复预警"
cp_net b2 100000000 0
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "550000000|550000000|b2" "$(cp_state '"\(.machine.rx)|\(.machine.tx)|\(.machine.bootId)"')" "整机：重启后（bootId 变了）本次读数整段算增量"
cp_net b2 100000500 600
run_cp 'carpoolCollectBeforeStop' >/dev/null 2>&1
assert_equals "550000500|550000600" "$(cp_state '"\(.machine.rx)|\(.machine.tx)"')" "整机：停 Xray 前的钩子也记一次网卡（重启后从 0 起，上次 tick 之后的收发不丢）"
_out=$(run_cp 'carpoolShowUsage' 2>&1)
assert_contains "${_out}" "整机本周期 1.1 GB / 套餐 1 GB（110%）· 成员合计 0 B · 计费口径：双向（进 + 出） · 网卡 eth0" "查看用量：整机一行带套餐、成员合计、口径与网卡"
rm -f "${CP_NET}"
_out=$(run_cp 'carpoolTick' 2>&1)
assert_contains "${_out}" "找不到默认路由所在的网卡" "整机：读不到网卡时记一行"
assert_equals "550000500" "$(cp_state '.machine.rx')" "整机：读不到网卡时累计不动"
printf '%s\n' '{"plan": {"sizeGB": 1, "interface": "eth9"}, "notify": {"label": "车", "digestHour": null}, "members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
: >"${CP_CALLS}"
_out=$(run_cp 'carpoolTick' 2>&1)
assert_equals "1" "$(grep -c '^machineSample eth9$' "${CP_CALLS}")" "整机：plan.interface 当次 tick 就按它取读数"
assert_contains "${_out}" "读不到网卡 eth9 的计数" "整机：指定的网卡读不到时点名"

# 换周期：整机累计随成员一起清零，读数基线保留；周期事件带上期整机用量
cp_reset_tree
printf '%s\n' '{"plan": {"sizeGB": 1}, "notify": {"label": "车", "digestHour": null}, "members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
cp_net b1 1000 2000
run_cp 'carpoolTick' >/dev/null 2>&1
jq '.period = "2000-01-01" | .notified = {"plan:warn": true}' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
cp_net b1 300001000 200002000
_out=$(run_cp 'carpoolTick' 2>&1)
assert_contains "${_out}" "  整机: 500 MB" "换周期：周期事件附上期整机用量（both：收发合计）"
assert_equals "0|0|300001000|{}" "$(cp_state '"\(.machine.rx)|\(.machine.tx)|\(.machine.last.eth0.rx)|\(.notified | tojson)"')" "换周期：整机累计清零、读数基线保留、预警键清空"

# cron 分支与快照
assert_equals "3" "$(run_cp 'carpoolTick() { return 3; }; cronName=CarpoolTick; cronFunction' >/dev/null 2>&1; echo $?)" "cronFunction CarpoolTick：退出码原样带出"
cp_reset_tree
_snap="${MOCK_ROOT}/carpool.snap"
rm -rf "${_snap}"
printf 'TG_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF\nTG_CHAT_ID=42\n' >"${CP_ROOT}/carpool/telegram.conf" && chmod 600 "${CP_ROOT}/carpool/telegram.conf"
run_cp "backupConfigSnapshot ${_snap}" >/dev/null 2>&1
assert_equals "yes" "$([[ -f "${_snap}/carpool/members.json" && -f "${_snap}/carpool/state.json" ]] && echo yes || echo no)" "backupConfigSnapshot：快照含 carpool/"
assert_equals "-rw-------" "$(ls -l "${_snap}/carpool/telegram.conf" | awk '{print $1}' | cut -c1-10)" "backupConfigSnapshot：快照里的 telegram.conf 仍是 600"
printf '%s\n' '{"members": {}}' >"${CP_ROOT}/carpool/members.json"
jq '.members.alice.upBytes = 777' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
run_cp "restoreConfigSnapshot ${_snap}" >/dev/null 2>&1
assert_equals '{"notify":{"label":"车","digestHour":null},"members":{"alice":{"quotaGiB":5},"bob":{}}}' "$(jq -c . "${CP_ROOT}/carpool/members.json")" "restoreConfigSnapshot：快照里的 carpool/ 覆盖回来"
assert_equals "777" "$(cp_state '.members.alice.upBytes')" "restoreConfigSnapshot：现场的 state.json 留着，用量不倒回快照那天"
assert_equals "0" "$(find "${CP_ROOT}" -maxdepth 1 -name '.carpool-state.*' | wc -l | tr -d ' ')" "restoreConfigSnapshot：暂存的 state 副本不留在安装根"
rm -f "${CP_ROOT}/carpool/state.json"
run_cp "restoreConfigSnapshot ${_snap}" >/dev/null 2>&1
assert_equals "no" "$([[ -f "${CP_ROOT}/carpool/state.json" ]] && echo yes || echo no)" "restoreConfigSnapshot：现场没有 state 时也不从快照拿（不然拼车带着旧用量复活）"
rm -rf "${_snap}/carpool"
printf '%s\n' '{"members": {"keep": {}}}' >"${CP_ROOT}/carpool/members.json"
run_cp "restoreConfigSnapshot ${_snap}" >/dev/null 2>&1
assert_equals '{"members":{"keep":{}}}' "$(jq -c . "${CP_ROOT}/carpool/members.json")" "restoreConfigSnapshot：快照里没有 carpool/ 就不动车主的文件"

# --- 开启：播种、采用 uuid、写 state、reload（start 钩子补片段与 cron）、第一次 tick ---
cp_reset_tree
rm -f "${CP_ROOT}/carpool/members.json" "${CP_ROOT}/carpool/state.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "开启：返回 0"
assert_contains "${_out}" "已按现有账号生成" "开启：没有 members.json 时播种"
assert_contains "${_out}" "拼车已开启" "开启：成功提示"
assert_contains "${_out}" "成员名取自现有账号名，改名等于换订阅链接" "开启：提示成员名的来历"
assert_equals '{"zed":{"quotaGiB":0,"expire":"","protocols":"all"},"alice":{"quotaGiB":0,"expire":"","protocols":"all"},"bob":{"quotaGiB":0,"expire":"","protocols":"all"}}' "$(jq -c '.members' "${CP_ROOT}/carpool/members.json")" "开启：播种的成员 = 现有账号，全员不限额不限期全协议"
assert_equals "true|${CP_PERIOD}|1" "$(cp_state '"\(.enabled)|\(.period)|\(.resetDay)"')" "开启：state 开着、周期按 resetDay 算"
assert_equals "31211" "$(cp_state '.apiPort')" "开启：apiPort 取紧挨桥端口段那一段里第一个空闲的（本机封锁按端口封，被封的都落在 31111-31299）"
assert_equals "31213" "$(run_cp 'listeningPorts() { printf "31211\n31212\n"; }; carpoolPickApiPort' 2>/dev/null)" "carpoolPickApiPort：跳过本机已在监听的端口（按 /proc/net，不靠 lsof）"
assert_equals "zz|${CP_U1}|${CP_U2}" "$(cp_state '[.members[].uuid] | join("|")')" "开启：uuid 从 inbound 采用"
assert_equals "active|active|active" "$(cp_state '[.members[].status] | join("|")')" "开启：全员 active"
assert_equals "1" "$(grep -c '^reloadCore$' "${CP_CALLS}")" "开启：重载一次"
assert_equals "yes" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "开启：start 钩子写了 12_stats_api.json"
assert_equals "1" "$(grep -c 'install.sh CarpoolTick' "${CP_TABLE}")" "开启：cron 行加上"
assert_not_empty "$(cp_state '.lastTick')" "开启：第一次 tick 跑过"
assert_equals "drwx------" "$(ls -ld "${CP_ROOT}/carpool" | awk '{print $1}' | cut -c1-10)" "开启：carpool/ 目录 700"
_out=$(run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "拼车已经开着" "开启：已开着时提示"
# start 钩子没写出统计 API 片段：不报开启，state 翻回关着、cron 行撤掉
cp_reset_tree
rm -f "${CP_ROOT}/carpool/state.json" "${CP_TABLE}"
_out=$(CP_ENV_RC=1 run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "开启（统计 API 没起来）：返回 1"
assert_contains "${_out}" "统计 API 没有就绪" "开启（统计 API 没起来）：说明原因"
assert_equals "no" "$([[ "${_out}" == *"拼车已开启"* ]] && echo yes || echo no)" "开启（统计 API 没起来）：不报已开启"
assert_equals "false|0" "$(cp_state '.enabled')|$(cat "${CP_TABLE}" 2>/dev/null | grep -c 'install.sh CarpoolTick')" "开启（统计 API 没起来）：state 关着、没有 cron 行"

# 开启被拒的六种情形都不写 state
cp_reset_tree
rm -f "${CP_ROOT}/carpool/state.json"
_out=$(CP_CORE=2 run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "开启（内核不是 Xray）：返回 1"
assert_contains "${_out}" "拼车只支持 Xray 内核" "开启（内核不是 Xray）：说明原因"
assert_equals "no" "$([[ -f "${CP_ROOT}/carpool/state.json" ]] && echo yes || echo no)" "开启（被拒）：不写 state"
_out=$(CP_XRAY_VERSION=1.8.11 run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "Xray 1.8.11 太旧，拼车需要 1.8.12 以上" "开启（Xray 太旧）：说明版本与下限"
_out=$(CP_PROTOS=",0,6,7," run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "装了 Hysteria2 或 TUIC" "开启（装了 6/9）：拒绝"
_out=$(CP_CROND_RC=1 run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "cron 守护进程没在跑" "开启（crond 起不来）：拒绝"
_out=$(run_cp 'flock() { :; }; command() { if [[ "$2" == "flock" ]]; then return 1; fi; builtin command "$@"; }; carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "缺少 flock 命令" "开启（没有 flock）：拒绝"
jq -n '{inbounds: [{listen: "127.0.0.1", port: 31305, protocol: "vless", settings: {clients: [{id: "zz", email: "zed-VLESS_Reality_gRPC"}], decryption: "none"}}]}' \
    >"${CP_ROOT}/xray/conf/08_VLESS_vision_gRPC_inbounds.json"
_out=$(run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "开启（v1.0.x 留下的 gRPC 入站）：返回 1"
assert_contains "${_out}" "08_VLESS_vision_gRPC_inbounds.json" "开启（v1.0.x 留下的 gRPC 入站）：点名对账管不到的文件"
rm -f "${CP_ROOT}/xray/conf/08_VLESS_vision_gRPC_inbounds.json"
assert_equals "no" "$([[ -f "${CP_ROOT}/carpool/state.json" ]] && echo yes || echo no)" "开启（被拒 ×6）：仍没有 state"

# 再次开启：沿用上次的 members.json 与计数
cp_reset_tree
jq '.enabled = false | .members.alice.upBytes = 12345' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "重开：返回 0"
assert_equals "true|12345|23456" "$(cp_state '"\(.enabled)|\(.members.alice.upBytes)|\(.apiPort)"')" "重开：计数与 apiPort 沿用"
assert_equals "no" "$([[ "${_out}" == *"已按现有账号生成"* ]] && echo yes || echo no)" "重开：已有 members.json 不再播种"
# 关着时在菜单里删了 bob（只改协议文件，state 还记着他的 UUID）：重开要列出来、在终端里逐项确认，不确认就不开
cp_reset_tree
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[2])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[2])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(run_cp 'carpoolHasTty() { return 1; }; carpoolEnable; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=1" "重开（关着时删了 bob，非 tty）：返回 1"
assert_contains "${_out}" "bob 现在不在任何协议里" "重开（关着时删了 bob）：说出谁会被放回"
assert_contains "${_out}" "需要在终端里逐项确认" "重开（非 tty）：说明要交互"
assert_equals 'false|["zed","alice"]' "$(cp_state '.enabled')|$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "重开（非 tty）：不开启，bob 不回来"
_out=$(printf 'n\n' | run_cp 'carpoolHasTty() { return 0; }; carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "已取消" "重开（回答 n）：取消"
assert_equals 'false|["zed","alice"]' "$(cp_state '.enabled')|$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "重开（回答 n）：不开启，bob 不回来"
_out=$(printf 'y\n' | run_cp 'carpoolHasTty() { return 0; }; carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "重开（回答 y）：返回 0"
assert_equals "true|${CP_U2}" "$(cp_state '.enabled')|$(jq -r '.inbounds[0].settings.clients[] | select(.email | startswith("bob-")) | .id' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "重开（回答 y）：开启，bob 按原 UUID 放回"
# 关着时给 bob 换了新 UUID：重开会改回 state 里的，同样要先说出来
cp_reset_tree
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq '.inbounds[0].settings.clients[2].id = "99999999-9999-9999-9999-999999999999"' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq '.inbounds[1].settings.clients[2].id = "99999999-9999-9999-9999-999999999999"' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
_out=$(run_cp 'carpoolHasTty() { return 1; }; carpoolEnable; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "bob 现在的 UUID 是 99999999-9999-9999-9999-999999999999，开启会改回拼车记着的 ${CP_U2}" "重开（关着时换了 UUID）：说出新旧两个 UUID"
assert_equals "false" "$(cp_state '.enabled')" "重开（关着时换了 UUID，非 tty）：不开启"
# 关着时把 bob 从文件和协议里都删了：开启一次之后，第一段撞他的新成员照样要拒，否则他手里的旧订阅链接拉到新成员的凭据
cp_reset_tree
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.members.bob)' "${CP_ROOT}/carpool/members.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/carpool/members.json"
jq 'del(.inbounds[0].settings.clients[2])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[2])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(run_cp 'carpoolHasTty() { return 1; }; carpoolEnable; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=0" "重开（关着时从文件和协议都删了 bob）：返回 0"
assert_equals '["bob"]' "$(cp_state '.retiredNames | tojson')" "重开（关着时删了 bob）：bob 记进 retiredNames"
jq '.members["bob-2"] = {}' "${CP_ROOT}/carpool/members.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/carpool/members.json"
_out=$(run_cp 'carpoolHasTty() { return 1; }; carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "与已删除的成员 bob 名字的第一段相同" "重开之后再加 bob-2：拒绝，说明撞了已删成员"
assert_equals "null" "$(cp_state '.members["bob-2"] | tojson')" "重开之后再加 bob-2：没有写进 state"

# --- 关闭：只恢复超额停用者；事务失败不关闭 ---
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
_out=$(printf 'n\n' | run_cp 'carpoolDisable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "将恢复（因超额停用）: alice" "关闭：先列出将恢复的人"
assert_contains "${_out}" "已取消" "关闭：回答 n 取消"
assert_equals "true" "$(cp_state '.enabled')" "关闭（取消）：仍开着"
_out=$(printf 'y\n' | run_cp 'carpoolDisable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "关闭：返回 0"
assert_contains "${_out}" "拼车已关闭" "关闭：成功提示"
assert_equals "false|active|" "$(cp_state '"\(.enabled)|\(.members.alice.status)|\(.members.alice.reason)"')" "关闭：enabled=false，超额停用的 alice 恢复"
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "关闭：alice 放回 02"
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "关闭：reload 的 start 钩子撤掉 12_stats_api.json"
assert_equals "0" "$(grep -c 'install.sh CarpoolTick' "${CP_TABLE}")" "关闭：cron 行删掉"
# CarpoolTick 是 crontab 唯一一行时（一键 Reality 没有 RenewTLS），grep -v 空输出返回 1，在 install.sh 的 pipefail 下不能报成清理失败
printf '%s\n' "*/5 * * * * PROXY_AGENT_DIR=${CP_ROOT} /bin/bash ${CP_ROOT}/install.sh CarpoolTick >> /dev/null 2>&1" >"${CP_TABLE}"
_out=$(run_cp 'set -o pipefail; carpoolRemoveCron; echo "rc=$?"' 2>&1)
assert_equals "no|0" "$([[ "${_out}" == *"清理 crontab 失败"* ]] && echo yes || echo no)|$(grep -c 'CarpoolTick' "${CP_TABLE}")" "关闭（cron 里只有 CarpoolTick）：删掉且不报失败"
assert_equals "$((6 * GiB))" "$(cp_state '.members.alice.upBytes')" "关闭：计数不清零"
# 到期停用者默认保持，回答第二问 y 才一并恢复
cp_reset_tree
jq '.members.alice.status = "disabled" | .members.alice.reason = "expired" | .members.alice.expire = "2020-01-01"' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(printf 'y\nn\n' | run_cp 'carpoolDisable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "保持停用（已到期 / 车主停用）: alice" "关闭（到期者）：列在保持停用组"
assert_equals "false|disabled|expired" "$(cp_state '"\(.enabled)|\(.members.alice.status)|\(.members.alice.reason)"')" "关闭（到期者）：默认保持停用"
assert_equals '["zed","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "关闭（到期者）：不放回"
assert_equals "yes" "$([[ -s "${CP_ROOT}/subscribe/default/${CP_ALICE_MD5}" ]] && echo yes || echo no)" "关闭（到期者）：占位保留"
cp_reset_tree
jq '.members.alice.status = "disabled" | .members.alice.reason = "expired" | .members.alice.expire = "2020-01-01"' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
_out=$(printf 'y\ny\n' | run_cp 'carpoolDisable; echo "rc=$?"' 2>&1)
assert_equals "false|active" "$(cp_state '"\(.enabled)|\(.members.alice.status)"')" "关闭（一并恢复）：到期者也放回"
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "关闭（一并恢复）：alice 回到 02"
# 事务失败整体不关闭
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
_out=$(printf 'y\n' | XRAY_TEST_RC=1 run_cp 'carpoolDisable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "关闭（事务失败）：返回 1"
assert_contains "${_out}" "拼车保持开启" "关闭（事务失败）：说明仍在运行"
assert_equals "true" "$(cp_state '.enabled')" "关闭（事务失败）：仍开着"
assert_equals '["zed","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "关闭（事务失败）：协议文件回滚"
_out=$(run_cp 'carpoolDisable; echo "rc=$?"' 2>&1 </dev/null)
cp_reset_tree
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_out=$(run_cp 'carpoolDisable; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "拼车未开启" "关闭（没开）：提示"

# --- 应用配置文件 ---
cp_reset_tree
printf '%s\n' '{"members": {"alice": {"quotaGiB": 5}, "bob": {}, "carol": {"quotaGiB": 1, "protocols": [0, 7]}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(CP_SUBPORT=12345 run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=0" "应用（新增）：返回 0"
assert_contains "${_out}" "新增成员 carol" "应用（新增）：显示差异"
assert_contains "${_out}" "配置已应用" "应用（新增）：成功提示"
assert_equals "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa|active|${GiB}" "$(cp_state '.members.carol | "\(.uuid)|\(.status)|\(.quotaBytes)"')" "应用（新增）：新成员生成 uuid、active、限额按文件"
assert_equals '["zed","alice","bob","carol"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "应用（新增）：carol 进 02"
assert_equals "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" "$(jq -r '.inbounds[1].settings.clients[3].id' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")" "应用（新增）：07 里的 carol 用的是生成的 uuid"
assert_equals "1" "$(grep -c '^subscribe false true$' "${CP_CALLS}")" "应用（新增）：重建订阅"
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "配置文件没有改动" "应用（无改动）：提示"
_cpFile=$(cat "${CP_ROOT}/carpool/members.json")
jq '.notify.warnPercent = 60' <<<"${_cpFile}" >"${CP_ROOT}/carpool/members.json"
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "设置 notify.warnPercent：80 → 60" "应用（只改通知设置）：列进差异，不再说没有改动"
assert_equals "60" "$(cp_state '.notify.warnPercent')" "应用（只改通知设置）：当场写进 state，不等 tick"
printf '%s\n' "${_cpFile}" >"${CP_ROOT}/carpool/members.json"
run_cp 'carpoolApply' >/dev/null 2>&1 </dev/null
# 删除成员在非 tty 下拒绝，文件不动
printf '%s\n' '{"members": {"alice": {"quotaGiB": 5}, "carol": {"quotaGiB": 1, "protocols": [0, 7]}}}' >"${CP_ROOT}/carpool/members.json"
_before02=$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=1" "应用（非 tty 删人）：返回 1"
assert_contains "${_out}" "删除成员 bob" "应用（非 tty 删人）：先显示差异"
assert_contains "${_out}" "需要在终端里逐项确认" "应用（非 tty 删人）：说明要交互"
assert_equals "${_before02}" "$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "应用（非 tty 删人）：协议文件不动"
assert_equals "true" "$(cp_state '.members | has("bob")')" "应用（非 tty 删人）：state 不动"
# 在终端里确认删人：账号从每个协议文件删掉（不是变成「不归拼车管的账号」留下），state 忘掉他
: >"${CP_CALLS}"
_out=$(printf 'y\n' | CP_SUBPORT=12345 run_cp 'carpoolHasTty() { return 0; }; carpoolApply; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "应用（确认删人）：返回 0"
assert_equals '["zed","alice","carol"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "应用（确认删人）：bob 从 02 删掉，zed 不动"
assert_equals '["zed","alice","carol"]' "$(cp_emails 07_VLESS_vision_reality_inbounds.json '.inbounds[1].settings.clients')" "应用（确认删人）：bob 从 07 删掉"
assert_equals "false|[\"bob\"]" "$(cp_state '"\(.members | has("bob"))|\(.removing | tojson)"')" "应用（确认删人）：成员表里没有 bob，待删记到 removing"
assert_equals "1" "$(grep -c '^reloadCore$' "${CP_CALLS}")" "应用（确认删人）：重载一次"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "null" "$(cp_state '.removing')" "应用（确认删人）：inbound 里已经没有他，下个 tick 清掉 removing"
assert_equals '["bob"]' "$(cp_state '.retiredNames | tojson')" "应用（确认删人）：bob 记进 retiredNames，清掉 removing 后也留着"
# 之后另一次应用加 bob-2：订阅文件按第一段定位，bob 手里的旧链接会拉到 bob-2 的凭据，要拒绝
jq '.members["bob-2"] = {}' "${CP_ROOT}/carpool/members.json" >"${CP_ROOT}/m.tmp" && mv "${CP_ROOT}/m.tmp" "${CP_ROOT}/carpool/members.json"
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=1" "应用（复用已删成员的第一段）：返回 1"
assert_contains "${_out}" "成员 bob-2 与已删除的成员 bob 名字的第一段相同" "应用（复用已删成员的第一段）：说明撞上了谁"
assert_equals "false" "$(cp_state '.members | has("bob-2")')" "应用（复用已删成员的第一段）：state 不动"
# 删人时对账失败：removing 留着，下个 tick 重试删掉
cp_reset_tree
printf '%s\n' '{"members": {"alice": {"quotaGiB": 5}}}' >"${CP_ROOT}/carpool/members.json"
printf 'y\n' | XRAY_TEST_RC=1 run_cp 'carpoolHasTty() { return 0; }; carpoolApply' >/dev/null 2>&1
assert_equals '["zed","alice","bob"]|["bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')|$(cp_state '.removing | tojson')" "应用（删人时事务失败）：协议文件不动，removing 留着"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals '["zed","alice"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "应用（删人时事务失败）：下个 tick 补删"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "null" "$(cp_state '.removing')" "应用（删人时事务失败）：删干净后 removing 清掉"
printf '%s\n' '{"members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
_out=$(CP_SUBPORT=12345 run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "应用（删了再加回）：bob 作为新成员回来"
cp_reset_tree
printf '%s\n' '{"members": {"alice": {"quotaGiB": 5}, "bob": {}, "carol": {"quotaGiB": 1, "protocols": [0, 7]}}}' >"${CP_ROOT}/carpool/members.json"
run_cp 'carpoolApply' >/dev/null 2>&1 </dev/null
# 文件无效
printf '%s\n' '{"members": {"alice": {"quotaGiB": -1}}}' >"${CP_ROOT}/carpool/members.json"
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=1" "应用（文件无效）：返回 1"
assert_contains "${_out}" "quotaGiB 必须是非负整数" "应用（文件无效）：列出原因"
# 即时字段改动：无需确认
printf '%s\n' '{"resetDay": 20, "members": {"alice": {"quotaGiB": 50, "expire": "2099-12-31"}, "bob": {}, "carol": {"quotaGiB": 1, "protocols": [0, 7]}}}' >"${CP_ROOT}/carpool/members.json"
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=0" "应用（改配额）：返回 0"
assert_contains "${_out}" "alice 的配额 5 GiB → 50 GiB" "应用（改配额）：差异文案"
assert_equals "$((50 * GiB))|2099-12-31|20" "$(cp_state '"\(.members.alice.quotaBytes)|\(.members.alice.expire)|\(.resetDay)"')" "应用（改配额）：state 同步"
_out=$(run_cp 'jq ".enabled = false" "${CARPOOL_STATE_FILE}" > "${CARPOOL_STATE_FILE}.t" && mv "${CARPOOL_STATE_FILE}.t" "${CARPOOL_STATE_FILE}"; carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "拼车未开启" "应用（没开）：提示"
cp_reset_tree
for _d in default clashMeta clashMetaProfiles sing-box sing-box_profiles carpool; do mkdir -p "${CP_ROOT}/subscribe/${_d}"; echo x >"${CP_ROOT}/subscribe/${_d}/${CP_ALICE_MD5}"; done
run_cp 'carpoolRemoveSubscriptionFiles alice' >/dev/null 2>&1
assert_equals "${CP_ROOT}/subscribe/carpool/${CP_ALICE_MD5}" "$(ls "${CP_ROOT}"/subscribe/*/"${CP_ALICE_MD5}" 2>/dev/null)" "carpoolRemoveSubscriptionFiles：五个订阅目录都删，页面目录不归它管"

# --- 清零 ---
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six | .notified = {"warn:alice": true}' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(printf '2\nnobody\n' | run_cp 'carpoolResetUsage; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "nobody 不是拼车成员" "清零：不是成员时拒绝"
_out=$(printf '2\nalice\n' | run_cp 'carpoolResetUsage; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "清零（单人）：返回 0"
assert_equals "0|active||{}" "$(cp_state '"\(.members.alice.upBytes)|\(.members.alice.status)|\(.members.alice.reason)|\(.notified | tojson)"')" "清零（单人）：用量归零、恢复、预警键清掉"
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "清零（单人）：alice 放回协议文件"

# --- 守卫与拦截 ---
cp_reset_tree
_out=$(run_cp 'carpoolMemberAdd() { echo MEMBER-ADD; }; carpoolMemberEdit() { echo "MEMBER-EDIT $1"; }; read() { echo READ-CALLED; }; addUser; removeUser' 2>&1 </dev/null)
assert_equals "2" "$(grep -c '账号改由拼车的成员管理维护' <<<"${_out}")" "守卫：拼车开着时 addUser / removeUser 都说明改由成员管理维护"
assert_equals "1|1" "$(grep -c '^MEMBER-ADD$' <<<"${_out}")|$(grep -c '^MEMBER-EDIT remove$' <<<"${_out}")" "守卫：加人转到加成员、删人转到移除成员"
assert_equals "2" "$(grep -c '^MENU 1$' <<<"${_out}")" "守卫：做完回账号菜单"
assert_equals "0" "$(grep -c 'READ-CALLED' <<<"${_out}")" "守卫：没有走到手动增删的交互"
_out=$(run_cp 'carpoolMemberAdd() { :; }; carpoolMemberEdit() { :; }; manageAccount() { echo "MENU $*"; return 1; }; read() { echo READ-CALLED; }; addUser; removeUser' 2>&1 </dev/null)
assert_equals "0" "$(grep -c 'READ-CALLED' <<<"${_out}")" "守卫：回到的账号菜单以非零结束（比如输错选项）也不落进手动增删"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_out=$(run_cp 'read() { echo READ-CALLED; userNum=0; }; addUser' 2>&1 </dev/null)
assert_equals "1" "$(grep -c 'READ-CALLED' <<<"${_out}")" "守卫：关着时 addUser 照常进入交互"
# --- 成员管理菜单：每项只改 members.json 再走应用；没应用成就把文件改回 ---
cp_members() { jq -c "$1" "${CP_ROOT}/carpool/members.json"; }
cp_days_later() { jq -rn --arg d "$(date +%F)" --argjson n "$1" '($d + "T00:00:00Z" | fromdateiso8601) + $n * 86400 | strftime("%Y-%m-%d")'; }
cp_reset_tree
_out=$(printf 'carol\n10\n+30\n\n' | CP_SUBPORT=12345 run_cp 'carpoolMemberAdd; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "成员管理（加成员）：返回 0"
assert_equals "{\"quotaGiB\":10,\"expire\":\"$(cp_days_later 30)\",\"protocols\":\"all\"}" "$(cp_members '.members.carol')" \
    "成员管理（加成员）：写进 members.json，+30 从今天算，回车是全部协议"
assert_equals "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa|active|$((10 * GiB))" "$(cp_state '"\(.members.carol.uuid)|\(.members.carol.status)|\(.members.carol.quotaBytes)"')" \
    "成员管理（加成员）：应用后 state 里有他，UUID 当场生成"
assert_equals '["zed","alice","bob","carol"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "成员管理（加成员）：进了协议文件"
assert_equals "1" "$(grep -cE 'carol 的订阅地址：https://example\.com:12345/s/[0-9a-f]{32}' <<<"${_out}")" "成员管理（加成员）：打印他的通用订阅地址"
assert_equals "null" "$(cp_members '.members.carol.uuid')" "成员管理（加成员）：文件里不留 UUID"

cp_reset_tree
_cpBefore=$(cat "${CP_ROOT}/carpool/members.json")
_out=$(printf 'bad name\nalice\n\n' | run_cp 'carpoolMemberAdd; echo "rc=$?"' 2>&1)
assert_equals "1|1|1" "$(grep -c '名字要以字母或数字开头' <<<"${_out}")|$(grep -c '已经有成员 alice' <<<"${_out}")|$(grep -c '已取消' <<<"${_out}")" \
    "成员管理（加成员）：名字不合法、已存在都重问，回车取消"
assert_equals "${_cpBefore}" "$(cat "${CP_ROOT}/carpool/members.json")" "成员管理（加成员，取消）：文件不动"

jq '.retiredNames = ["dave"]' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_out=$(printf 'dave-x\n\n\n\n' | run_cp 'carpoolMemberAdd; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "成员管理（加成员，撞上已删成员的订阅键）：返回 1"
assert_contains "${_out}" "已改回原样" "成员管理（加成员，校验不过）：说明文件已改回"
assert_equals "${_cpBefore}" "$(cat "${CP_ROOT}/carpool/members.json")" "成员管理（加成员，校验不过）：members.json 逐字改回"

cp_reset_tree
printf '1\n+30\n' | run_cp 'carpoolMemberEdit renew' >/dev/null 2>&1
assert_equals "$(cp_days_later 30)|$(cp_days_later 30)" "$(cp_members '.members.alice.expire' | tr -d '"')|$(cp_state '.members.alice.expire')" "成员管理（续期）：不限期的从今天算，文件与 state 都改"
printf '1\n+5\n' | run_cp 'carpoolMemberEdit renew' >/dev/null 2>&1
assert_equals "$(cp_days_later 35)" "$(cp_state '.members.alice.expire')" "成员管理（续期）：没过期的从原到期日往后加"
printf '2\n20\n' | run_cp 'carpoolMemberEdit quota' >/dev/null 2>&1
assert_equals "20|$((20 * GiB))" "$(cp_members '.members.bob.quotaGiB')|$(cp_state '.members.bob.quotaBytes')" "成员管理（改额度）：文件与 state 都改"
printf '1\n0, 7\n' | run_cp 'carpoolMemberEdit protocols' >/dev/null 2>&1
assert_equals '[0,7]|[0,7]' "$(cp_members '.members.alice.protocols')|$(cp_state '.members.alice.protocols | tojson')" "成员管理（改协议）：逗号或空格分隔都认"
_cpBefore=$(cat "${CP_ROOT}/carpool/members.json")
_out=$(printf '1\n7\n' | run_cp 'carpoolMemberEdit protocols; echo "rc=$?"' 2>&1)
assert_equals "rc=1|${_cpBefore}" "$(grep -o 'rc=[0-9]' <<<"${_out}")|$(cat "${CP_ROOT}/carpool/members.json")" "成员管理（改协议）：漏了必选的 0 时应用被拒，文件改回"
_out=$(printf '1\n\n' | run_cp 'carpoolMemberEdit quota; echo "rc=$?"' 2>&1)
assert_equals "rc=0|${_cpBefore}" "$(grep -o 'rc=[0-9]' <<<"${_out}")|$(cat "${CP_ROOT}/carpool/members.json")" "成员管理（改额度）：回车取消，什么都不改"

_cpOldUuid=$(cp_state '.members.alice.uuid')
_out=$(printf '1\nn\n' | run_cp 'carpoolHasTty() { return 0; }; carpoolMemberEdit uuid; echo "rc=$?"' 2>&1)
assert_equals "${_cpOldUuid}|null" "$(cp_state '.members.alice.uuid')|$(cp_members '.members.alice.uuid')" "成员管理（换 UUID，答 n）：凭据不变，文件改回"
_out=$(printf '1\ny\n' | run_cp 'carpoolHasTty() { return 0; }; carpoolMemberEdit uuid; echo "rc=$?"' 2>&1)
assert_equals "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa|null" "$(cp_state '.members.alice.uuid')|$(cp_members '.members.alice.uuid')" \
    "成员管理（换 UUID）：确认后 state 换成新凭据，文件里不留"
assert_contains "${_out}" "订阅地址不变" "成员管理（换 UUID）：告诉车主订阅地址不变"
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "没有" "成员管理（换 UUID）：之后文件与 state 没有差异"

_out=$(printf '2\nn\n' | run_cp 'carpoolHasTty() { return 0; }; carpoolMemberEdit remove' 2>&1)
assert_equals "true|true" "$(cp_members '.members | has("bob")')|$(cp_state '.members | has("bob")')" "成员管理（移除，答 n）：人还在、文件改回"
printf '2\ny\n' | run_cp 'carpoolHasTty() { return 0; }; carpoolMemberEdit remove' >/dev/null 2>&1
assert_equals "false|false|[\"zed\",\"alice\"]" "$(cp_members '.members | has("bob")')|$(cp_state '.members | has("bob")')|$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" \
    "成员管理（移除）：确认后文件、state、协议文件里都没了"

cp_reset_tree
jq '.members.alice.quotaGiB = 7' "${CP_ROOT}/carpool/members.json" >"${CP_ROOT}/carpool/m.tmp" && mv "${CP_ROOT}/carpool/m.tmp" "${CP_ROOT}/carpool/members.json"
_cpBefore=$(cat "${CP_ROOT}/carpool/members.json")
_out=$(printf 'carol\n\n\n\n' | run_cp 'carpoolMemberAdd; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "还没应用的改动" "成员管理：文件里有没应用的改动时先让车主处理"
assert_equals "rc=1|${_cpBefore}" "$(grep -o 'rc=[0-9]' <<<"${_out}")|$(cat "${CP_ROOT}/carpool/members.json")" "成员管理：这时不动文件"

cp_reset_tree
assert_contains "$(printf '0\n' | run_cp 'carpoolMenu' 2>&1)" "6.成员管理" "拼车菜单：开着时有成员管理"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
assert_equals "0" "$(printf '0\n' | run_cp 'carpoolMenu' 2>&1 | grep -c '成员管理')" "拼车菜单：关着时没有成员管理"

cp_reset_tree
_out=$(run_cp 'carpoolRefuseIfEnabled; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "拼车开着时不能切换内核或安装 Hysteria2 / TUIC" "拦截：开着时拒绝"
assert_equals "no" "$([[ "${_out}" == *"rc="* ]] && echo yes || echo no)" "拦截：开着时 exit 1，不往下走"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
assert_equals "rc=0" "$(run_cp 'carpoolRefuseIfEnabled; echo "rc=$?"' 2>&1)" "拦截：关着时放行"
for _fn in singBoxHysteria2Install singBoxTuicInstall installSingBoxRealityOnly selectCoreInstall; do
    assert_equals "1" "$(sed -n "/^${_fn}() {/,/^}/p" install.sh | grep -c 'carpoolRefuseIfEnabled')" "拦截：${_fn} 入口调了 carpoolRefuseIfEnabled"
done
assert_equals "1" "$(sed -n '/^manageAccount() {/,/^}/p' install.sh | grep -c 'carpoolMenu')" "菜单：账号管理挂了拼车管理"

# --- 只读页面 ---
cp_reset_tree
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(CP_SUBPORT=12345 run_cp 'carpoolPageEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "页面开启：返回 0"
_token=$(cp_state '.pageToken')
assert_equals "true|yes" "$(cp_state '.pageEnabled')|$([[ "${_token}" =~ ^[0-9a-f]{32}$ ]] && echo yes || echo no)" "页面开启：state 记下 32 位十六进制令牌"
assert_equals "yes" "$([[ -f "${CP_ROOT}/subscribe/carpool/${_token}" ]] && echo yes || echo no)" "页面开启：车主页文件 = 令牌"
_alicePage=$(printf '%s:alice' "${_token}" | cp_md5)
assert_equals "yes" "$([[ -f "${CP_ROOT}/subscribe/carpool/${_alicePage}" ]] && echo yes || echo no)" "页面开启：成员页文件 = md5(车主页令牌:成员名)"
assert_equals "no" "$([[ -f "${CP_ROOT}/subscribe/carpool/${CP_ALICE_MD5}" ]] && echo yes || echo no)" "页面开启：成员页不用订阅 md5（转发成员页不等于转发订阅）"
assert_equals "3" "$(find "${CP_ROOT}/subscribe/carpool" -type f | wc -l | tr -d ' ')" "页面开启：车主页 + 两个成员页，没有别的文件"
assert_equals "-rw-r--r--" "$(ls -l "${CP_ROOT}/subscribe/carpool/${_token}" | awk '{print $1}' | cut -c1-10)" "页面开启：文件 644（nginx 要读）"
_page=$(cat "${CP_ROOT}/subscribe/carpool/${_token}")
assert_contains "${_page}" "<td>alice</td>" "车主页：有成员行"
assert_contains "${_page}" "未纳入拼车的账号: zed" "车主页：列出未纳入的账号"
assert_equals "no" "$([[ "${_page}" == *"${CP_U1}"* ]] && echo yes || echo no)" "车主页：不含 UUID"
_member=$(cat "${CP_ROOT}/subscribe/carpool/${_alicePage}")
assert_contains "${_member}" "· alice</h1>" "成员页：本人"
assert_equals "no" "$([[ "${_member}" == *"bob"* ]] && echo yes || echo no)" "成员页：看不到别人"
assert_equals "1" "$(grep -c 'location ~ "^/s/carpool/' "${CP_ROOT}/nginx/subscribe.conf")" "页面开启：subscribe.conf 多一个 location"
assert_equals "1" "$(grep -c '^    location ~ "^/s/(clashMeta' "${CP_ROOT}/nginx/subscribe.conf")" "页面开启：订阅原有 location 原样"
assert_equals "yes" "$(awk '/carpool-page-end/{e=NR} /^    location \/ \{/{l=NR} END{print (e && l && e < l) ? "yes" : "no"}' "${CP_ROOT}/nginx/subscribe.conf")" "页面开启：块插在 location / 之前"
assert_equals "1|1" "$(grep -c '^nginx -t$' "${CP_CALLS}")|$(grep -c '^nginx -s reload$' "${CP_CALLS}")" "页面开启：nginx -t 过了才 reload"
assert_contains "${_out}" "车主页: https://example.com:12345/s/carpool/${_token}" "页面开启：车主链接走订阅的域名与端口"
assert_contains "${_out}" "成员页 alice: https://example.com:12345/s/carpool/${_alicePage}" "页面开启：成员链接"
echo junk >"${CP_ROOT}/subscribe/carpool/0123456789abcdef0123456789abcdef"
: >"${CP_CALLS}"
run_cp 'carpoolRenderPages' >/dev/null 2>&1
assert_equals "1" "$(grep -c '# carpool-page-begin' "${CP_ROOT}/nginx/subscribe.conf")" "重渲染：location 块不重复"
assert_equals "0" "$(grep -c '^nginx' "${CP_CALLS}")" "重渲染：块已在就不碰 nginx"
assert_equals "no" "$([[ -f "${CP_ROOT}/subscribe/carpool/0123456789abcdef0123456789abcdef" ]] && echo yes || echo no)" "重渲染：期望集合之外的文件删掉"
assert_equals "3" "$(find "${CP_ROOT}/subscribe/carpool" -type f | wc -l | tr -d ' ')" "重渲染：仍是三个文件"
# tick 之后页面跟着更新
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_contains "$(cat "${CP_ROOT}/subscribe/carpool/${_token}")" "已停用 · 流量已用尽" "tick 后：车主页显示停用"
assert_contains "$(cat "${CP_ROOT}/subscribe/carpool/${_token}")" "<p>整机本周期 - · 成员合计 12.88 GB · 计费口径：双向（进 + 出）</p>" "tick 后：车主页有整机一行（还没有读数时整机写 -），成员合计按口径"
assert_contains "$(cat "${CP_ROOT}/subscribe/carpool/${_alicePage}")" "已停用 · 流量已用尽" "tick 后：成员页同步"
# 配置文件待应用 / 无效 的提示
printf '%s\n' '{"members": {"alice": {"quotaGiB": 50}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
run_cp 'carpoolRenderPages' >/dev/null 2>&1
assert_contains "$(cat "${CP_ROOT}/subscribe/carpool/${_token}")" "配置文件有改动未应用：alice 的配额 5 GiB → 50 GiB" "车主页：待应用的改动"
printf '%s\n' '{"members": {"alice": {"quotaGiB": "x"}}}' >"${CP_ROOT}/carpool/members.json"
run_cp 'carpoolRenderPages' >/dev/null 2>&1
assert_contains "$(cat "${CP_ROOT}/subscribe/carpool/${_token}")" "配置文件校验未通过" "车主页：文件无效的提示"
# 重生成令牌
_out=$(printf '3\n' | CP_SUBPORT=12345 run_cp 'carpoolPageMenu' 2>&1)
_token2=$(cp_state '.pageToken')
assert_contains "${_out}" "车主令牌已重生成" "重生成令牌：提示"
assert_equals "no|yes|no" "$([[ "${_token2}" == "${_token}" ]] && echo yes || echo no)|$([[ -f "${CP_ROOT}/subscribe/carpool/${_token2}" ]] && echo yes || echo no)|$([[ -f "${CP_ROOT}/subscribe/carpool/${_token}" ]] && echo yes || echo no)" "重生成令牌：新文件在、旧文件删"
# 关闭页面
_out=$(printf '1\n' | run_cp 'carpoolPageMenu' 2>&1)
assert_contains "${_out}" "页面已关闭，文件已删除" "页面关闭：提示"
assert_equals "false|" "$(cp_state '"\(.pageEnabled)|\(.pageToken)"')" "页面关闭：state 清掉"
assert_equals "0" "$(find "${CP_ROOT}/subscribe/carpool" -type f | wc -l | tr -d ' ')" "页面关闭：文件删光"
assert_equals "0" "$(grep -c 'carpool' "${CP_ROOT}/nginx/subscribe.conf")" "页面关闭：location 块撤掉"
assert_equals "1" "$(grep -c '^    location / {' "${CP_ROOT}/nginx/subscribe.conf")" "页面关闭：其余配置原样"
_out=$(printf '2\n' | run_cp 'carpoolPageMenu' 2>&1)
assert_contains "${_out}" "页面未开启" "页面链接：关着时提示"
# HTTP 订阅：提示一次，链接用公网 IP
_out=$(CP_SUBPORT=12345 CP_SUBTYPE=http run_cp 'carpoolPageEnable' 2>&1)
assert_contains "${_out}" "页面也会走 HTTP" "页面开启（HTTP 订阅）：提示"
assert_contains "${_out}" "车主页: http://203.0.113.9:12345/s/carpool/" "页面开启（HTTP 订阅）：链接用公网 IP"
# 没装订阅拒绝；nginx -t 不过就还原
cp_reset_tree
_out=$(run_cp 'carpoolPageEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "页面开启（没装订阅）：返回 1"
assert_contains "${_out}" "请先在账号管理里安装订阅" "页面开启（没装订阅）：说明"
assert_equals "false" "$(cp_state '.pageEnabled')" "页面开启（没装订阅）：state 不动"
_before=$(cat "${CP_ROOT}/nginx/subscribe.conf")
_out=$(CP_SUBPORT=12345 CP_NGINX_T_RC=1 run_cp 'carpoolPageEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "页面开启（nginx -t 不过）：返回 1"
assert_contains "${_out}" "已还原 subscribe.conf" "页面开启（nginx -t 不过）：说明"
assert_equals "${_before}" "$(cat "${CP_ROOT}/nginx/subscribe.conf")" "页面开启（nginx -t 不过）：配置逐字还原"
assert_equals "0" "$(grep -c 'nginx -s reload' "${CP_CALLS}")" "页面开启（nginx -t 不过）：不 reload"
# 关闭拼车连页面一起撤
cp_reset_tree
printf '%s\n' '{}' >"${CP_STATS}"
CP_SUBPORT=12345 run_cp 'carpoolPageEnable' >/dev/null 2>&1
assert_equals "true" "$(cp_state '.pageEnabled')" "关闭拼车前：页面开着"
printf 'y\n' | run_cp 'carpoolDisable' >/dev/null 2>&1
assert_equals "false|false|" "$(cp_state '"\(.enabled)|\(.pageEnabled)|\(.pageToken)"')" "关闭拼车：页面标志一起清"
assert_equals "0" "$(find "${CP_ROOT}/subscribe/carpool" -type f 2>/dev/null | wc -l | tr -d ' ')" "关闭拼车：页面文件删光"
assert_equals "0" "$(grep -c 'carpool' "${CP_ROOT}/nginx/subscribe.conf")" "关闭拼车：location 块撤掉"
_out=$(printf '5\n9\n' | run_cp 'carpoolMenu' 2>&1)
assert_contains "${_out}" "拼车页面与通知" "菜单 5：进入页面与通知子菜单"
assert_contains "${_out}" "页面未开启 · Telegram 通知未配置" "菜单 5：状态行"

# --- Telegram 通知 ---
CP_TG_TOKEN="123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxx-abc_DEF"
cp_tg_conf() { printf 'TG_BOT_TOKEN=%s\nTG_CHAT_ID=-1001234567890\n' "${CP_TG_TOKEN}" >"${CP_ROOT}/carpool/telegram.conf"; chmod 600 "${CP_ROOT}/carpool/telegram.conf"; }
cp_curl_count() { grep -c '^curl ' "${CP_CALLS}" 2>/dev/null || true; }
cp_reset_tree
_out=$(printf '%s\n-1001234567890\n' "${CP_TG_TOKEN}" | run_cp 'carpoolTelegramConfigure; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "Telegram 配置：返回 0"
assert_equals $'TG_BOT_TOKEN='"${CP_TG_TOKEN}"$'\nTG_CHAT_ID=-1001234567890' "$(cat "${CP_ROOT}/carpool/telegram.conf")" "Telegram 配置：两行写进 telegram.conf"
assert_equals "-rw-------" "$(ls -l "${CP_ROOT}/carpool/telegram.conf" | awk '{print $1}' | cut -c1-10)" "Telegram 配置：文件 600"
assert_contains "${_out}" "已写入" "Telegram 配置：提示"
assert_contains "${_out}" "已发送" "Telegram 配置：顺手发了测试消息"
assert_equals "no" "$([[ "${_out}" == *"AAHxxxx"* ]] && echo yes || echo no)" "Telegram 配置：终端输出不回显 token"
assert_equals "1" "$(cp_curl_count)" "Telegram 配置：一次 curl"
assert_contains "$(cat "${CP_CALLS}")" "--connect-timeout 5 -m 15" "Telegram 发送：curl 带超时"
assert_contains "$(cat "${CP_CALLS}")" "chat_id=-1001234567890" "Telegram 发送：chat id 走 --data-urlencode"
assert_contains "$(cat "${CP_CALLS}")" $'text=[车]\n测试消息：拼车通知已接通' "Telegram 发送：标签一行 + 正文"
_out=$(printf 'badtoken\n' | run_cp 'carpoolTelegramConfigure; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "token 格式不对" "Telegram 配置：token 不合法拒绝"
assert_equals "123456789" "$(sed -n 's/^TG_BOT_TOKEN=\([0-9]*\):.*/\1/p' "${CP_ROOT}/carpool/telegram.conf")" "Telegram 配置：拒绝时原文件不动"
_out=$(run_cp 'carpoolTelegramMask' 2>&1)
assert_equals "Telegram 通知已配置 (123456789:*** → -1001234567890)" "${_out}" "Telegram 状态行：只露数字段"
# tick 事件 → 一条消息；不含 UUID
cp_reset_tree; cp_tg_conf
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
assert_equals "0" "$(run_cp 'carpoolTick' >/dev/null 2>&1; echo $?)" "通知（停用）：tick 返回 0"
assert_equals "1" "$(cp_curl_count)" "通知（停用）：一条消息"
assert_contains "$(cat "${CP_CALLS}")" $'text=[车]\nalice 已停用（流量已用尽）' "通知（停用）：内容"
assert_equals "0" "$(grep -c "${CP_U1}" "${CP_CALLS}")" "通知：消息里没有 UUID"
: >"${CP_CALLS}"; printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "通知：没有事件就不发"
# 没有 telegram.conf → 不发
cp_reset_tree
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "通知：未配置 Telegram 时一条也不发"
# curl 失败只记日志
cp_reset_tree; cp_tg_conf
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
_out=$(CP_CURL_FAIL=1 run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "通知（curl 失败）：tick 仍返回 0"
assert_contains "${_out}" "发送失败（curl）" "通知（curl 失败）：日志一行"
assert_equals "disabled" "$(cp_state '.members.alice.status')" "通知（curl 失败）：判定照常落地"
# 每日摘要：到点一次，第二次不发
cp_reset_tree; cp_tg_conf
printf '%s\n' '{"notify": {"label": "车", "digestHour": 0}, "members": {"alice": {"quotaGiB": 5}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "摘要：到点发一条"
assert_contains "$(cat "${CP_CALLS}")" $'text=[车]\n每日摘要 '"$(date +%F)"$'\nalice: 0 B / 5 GiB · 正常\nbob: 0 B / 不限 · 正常' "摘要：内容是每人一行"
assert_equals "0" "$(cp_state '.events | length')" "摘要：不进页面事件"
: >"${CP_CALLS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "摘要：同一天不再发"
# 文件无效一次；采集失败三次一次、恢复一次
cp_reset_tree; cp_tg_conf
printf '%s\n' '{"members": {"alice": {"quotaGiB": -1}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "通知（文件无效）：发一条"
assert_contains "$(cat "${CP_CALLS}")" "配置文件校验未通过，沿用上次已应用的限额：成员 alice 的 quotaGiB 必须是非负整数" "通知（文件无效）：附原因"
: >"${CP_CALLS}"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "通知（文件无效）：内容没变不重复"
printf '%s\n' '{"members": {"alice": {"quotaGiB": "x"}}}' >"${CP_ROOT}/carpool/members.json"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "通知（文件无效）：内容变了再发一次"
cp_reset_tree; cp_tg_conf
rm -f "${CP_STATS}"
run_cp 'carpoolTick' >/dev/null 2>&1; run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "通知（采集失败）：两次还不报"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "通知（采集失败）：第三次报一次"
assert_contains "$(cat "${CP_CALLS}")" "统计采集已连续失败 3 次" "通知（采集失败）：内容"
: >"${CP_CALLS}"; run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "通知（采集失败）：第四次不重复"
printf '%s\n' '{}' >"${CP_STATS}"; run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "通知（采集恢复）：恢复报一次"
assert_contains "$(cat "${CP_CALLS}")" "统计采集已恢复" "通知（采集恢复）：内容"
# 应用 / 关闭 / 失效 / 事务失败
cp_reset_tree; cp_tg_conf
printf '%s\n' '{"notify": {"label": "车", "digestHour": null}, "members": {"alice": {"quotaGiB": 5}, "bob": {}, "carol": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'carpoolApply' >/dev/null 2>&1 </dev/null
assert_contains "$(cat "${CP_CALLS}")" $'text=[车]\n配置已应用：新增成员 carol' "通知（应用）：变更摘要"
assert_equals "applied" "$(cp_state '.events[-1].type')" "通知（应用）：进页面事件"
cp_reset_tree; cp_tg_conf
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{}' >"${CP_STATS}"
printf 'y\n' | run_cp 'carpoolDisable' >/dev/null 2>&1
assert_contains "$(cat "${CP_CALLS}")" $'text=[车]\n拼车已关闭。恢复：alice；仍停用：-' "通知（关闭）：恢复了谁、谁还停着"
cp_reset_tree; cp_tg_conf
CP_CORE=2 run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "通知（失效）：内核不是 Xray 发一条"
assert_contains "$(cat "${CP_CALLS}")" "拼车已失效" "通知（失效）：内容"
CP_CORE=2 run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(cp_curl_count)" "通知（失效）：只发一次"
cp_reset_tree; cp_tg_conf
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
XRAY_TEST_RC=1 run_cp 'carpoolTick' >/dev/null 2>&1
assert_contains "$(cat "${CP_CALLS}")" "账户事务失败，协议文件未改动" "通知（事务失败）：发一条"
XRAY_TEST_RC=1 run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "1" "$(grep -c '账户事务失败' "${CP_CALLS}")" "通知（事务失败）：每个 tick 都失败也只发一次"
run_cp 'carpoolTick' >/dev/null 2>&1
assert_equals "null" "$(cp_state '.notified["tx:failed"]')" "通知（事务失败）：对账成功一次后去重键清掉"
XRAY_TEST_RC=1 run_cp 'jq ".members.alice.status = \"active\"" "${CARPOOL_STATE_FILE}" > "${CARPOOL_STATE_FILE}.t" && mv "${CARPOOL_STATE_FILE}.t" "${CARPOOL_STATE_FILE}"; carpoolSettle "[]"' >/dev/null 2>&1
assert_equals "2" "$(grep -c '账户事务失败' "${CP_CALLS}")" "通知（事务失败）：恢复之后再失败，重新发一次"
# cron 入口的 EXIT 陷阱：reload 把进程带走时补一条；正常结束不发
cp_reset_tree; cp_tg_conf
jq -n --argjson six $((6 * GiB)) '{stat: [{name: "user>>>alice-VLESS_TCP/TLS_Vision>>>traffic>>>uplink", value: $six}]}' >"${CP_STATS}"
_rc=$(run_cp 'reloadCore() { exit 1; }; cronName=CarpoolTick; cronFunction' >/dev/null 2>&1; echo $?)
assert_equals "1" "${_rc}" "EXIT 陷阱：reload 失败时进程退出码 1"
assert_contains "$(cat "${CP_CALLS}")" "tick 异常退出（退出码 1）" "EXIT 陷阱：补发一条异常退出"
cp_reset_tree; cp_tg_conf
printf '%s\n' '{}' >"${CP_STATS}"
run_cp 'cronName=CarpoolTick; cronFunction' >/dev/null 2>&1
assert_equals "0" "$(cp_curl_count)" "EXIT 陷阱：正常结束不发"
# 测试消息与关闭通知
cp_reset_tree; cp_tg_conf
_out=$(printf '5\n' | run_cp 'carpoolPageMenu' 2>&1)
assert_contains "${_out}" "Telegram 通知已配置 (123456789:*** → -1001234567890)" "页面与通知菜单：状态行"
assert_contains "${_out}" "已发送" "菜单 5：测试消息发出"
_out=$(printf '6\n' | run_cp 'carpoolPageMenu' 2>&1)
assert_contains "${_out}" "不再发送通知" "菜单 6：关闭通知"
assert_equals "no" "$([[ -f "${CP_ROOT}/carpool/telegram.conf" ]] && echo yes || echo no)" "菜单 6：telegram.conf 删掉"
_out=$(printf '5\n' | run_cp 'carpoolPageMenu' 2>&1)
assert_contains "${_out}" "Telegram 通知未配置" "菜单 5：未配置时提示"

# --- 菜单与 cron 分支 ---
cp_reset_tree
_out=$(printf '1\n' | run_cp 'carpoolMenu' 2>&1)
assert_contains "${_out}" "4.关闭拼车" "菜单：开着时第 4 项是关闭"
assert_contains "${_out}" "alice" "菜单 1：用量表里有成员"
assert_contains "${_out}" "未纳入拼车的账号: zed" "菜单 1：列出未纳入的账号"
_out=$(printf '9\n' | run_cp 'carpoolMenu' 2>&1)
assert_contains "${_out}" "选择错误" "菜单：非法选项"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_out=$(printf '1\n' | run_cp 'carpoolMenu' 2>&1)
assert_contains "${_out}" "4.开启拼车" "菜单：关着时第 4 项是开启"
assert_equals "3" "$(run_cp 'carpoolApply() { return 3; }; cronName=CarpoolApply; cronFunction' >/dev/null 2>&1; echo $?)" "cronFunction CarpoolApply：退出码原样带出"

# 静态钉住挂钩位置
HANDLE_XRAY_FN=$(sed -n '/^handleXray() {/,/^}/p' install.sh)
assert_equals "1" "$(grep -c 'ensureCarpoolXray' <<<"${HANDLE_XRAY_FN}")" "handleXray start 里挂了 ensureCarpoolXray"
assert_equals "1" "$(grep -c 'carpoolCollectBeforeStop' <<<"${HANDLE_XRAY_FN}")" "handleXray stop 里挂了采集钩子"
assert_equals "CarpoolCollect) carpoolCollectBeforeStop checkForUpdates" \
    "$(sed -n '/^# 顶层入口分发/,$p' install.sh | grep -oE 'CarpoolCollect\)|carpoolCollectBeforeStop|checkForUpdates' | paste -sd' ' -)" \
    "入口：服务停止钩子 CarpoolCollect 在更新检查之前分发（关机途中网络可能已断）"
assert_equals "ensureCarpoolXray writeXrayChainConfig ensureXrayLocalBlock" "$(grep -oE 'ensureCarpoolXray|writeXrayChainConfig|ensureXrayLocalBlock' <<<"${HANDLE_XRAY_FN}" | paste -sd' ' -)" \
    "handleXray start：拼车之后、本机封锁之前写回链式路由（链式入口重装、开 IPv6 全局后不静默走直连）"
SUBSCRIBE_FN=$(sed -n '/^subscribe() {/,/^}/p' install.sh)
assert_equals "1" "$(grep -c 'carpoolWritePlaceholders' <<<"${SUBSCRIBE_FN}")" "subscribe 末尾给停用成员补占位"
assert_equals "2" "$(grep -c 'wget -O "${_singboxTpl}" -q --timeout=15' <<<"${SUBSCRIBE_FN}")" "subscribe：sing-box 模板的两处 wget 带超时（cron 下不能挂死）"

# subscribe false true（carpoolRefreshSubscribe 走的静默重建）：三种格式都重建；模板拉不到时已有的 sing-box 配置不动
CP_ZED_MD5=$(printf 'zedtestsalt\n' | cp_md5)
CP_SUB_STUBS='readInstallProtocolType() { :; }; installSubscribe() { :; }
    showAccounts() {
        local n
        mkdir -p "${SUBSCRIBE_LOCAL_DIR}/default" "${SUBSCRIBE_LOCAL_DIR}/clashMeta" "${SUBSCRIBE_LOCAL_DIR}/sing-box"
        for n in alice zed; do
            echo "vless://${n}" >"${SUBSCRIBE_LOCAL_DIR}/default/${n}"
            echo "  - {name: ${n}}" >"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${n}"
            echo "[{\"tag\": \"${n}-out\", \"type\": \"vless\"}]" >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${n}"
        done
    }
    clashMetaConfig() { echo "$1" >"${SUBSCRIBE_DIR}/clashMetaProfiles/$2"; }'
CP_WGET_OK='wget() { local out; while [[ $# -gt 0 ]]; do [[ "$1" == -O ]] && out=$2; shift; done; echo "{\"outbounds\": [{\"tag\": \"select\", \"outbounds\": []}]}" >"${out}"; }'
cp_reset_tree
mkdir -p "${CP_ROOT}/subscribe/clashMetaProfiles"
echo stale >"${CP_ROOT}/subscribe/clashMeta/${CP_ALICE_MD5}"
echo placeholder >"${CP_ROOT}/subscribe/sing-box/${CP_ALICE_MD5}"
run_cp "${SUBSCRIBE_FN}; ${CP_SUB_STUBS}; ${CP_WGET_OK}; subscribe false true" >/dev/null 2>&1
assert_equals "proxies:|  - {name: zed}" "$(paste -sd'|' "${CP_ROOT}/subscribe/clashMeta/${CP_ZED_MD5}")" "subscribe 静默：别人的 clashMeta 文件也重建，不是删光了事"
assert_contains "$(cat "${CP_ROOT}/subscribe/clashMetaProfiles/${CP_ALICE_MD5}" 2>/dev/null)" "/s/clashMeta/${CP_ALICE_MD5}" "subscribe 静默：clashMetaProfiles 照常生成、指向重建的 clashMeta"
assert_equals '["select","alice-out"]|["alice-out"]' "$(jq -c '[.outbounds[].tag]' "${CP_ROOT}/subscribe/sing-box/${CP_ALICE_MD5}" 2>/dev/null)|$(jq -c '.outbounds[0].outbounds' "${CP_ROOT}/subscribe/sing-box/${CP_ALICE_MD5}" 2>/dev/null)" \
    "subscribe 静默：恢复的人的 sing-box 配置从占位换回真配置"
assert_equals "yes" "$([[ -s "${CP_ROOT}/subscribe/sing-box_profiles/${CP_ZED_MD5}" ]] && echo yes || echo no)" "subscribe 静默：sing-box_profiles 照常生成"
echo placeholder >"${CP_ROOT}/subscribe/sing-box/${CP_ALICE_MD5}"
run_cp "${SUBSCRIBE_FN}; ${CP_SUB_STUBS}; wget() { return 4; }; subscribe false true" >/dev/null 2>&1
assert_equals "placeholder" "$(cat "${CP_ROOT}/subscribe/sing-box/${CP_ALICE_MD5}")" "subscribe：模板拉不到时不动已有的 sing-box 配置"
assert_equals "proxies:" "$(head -1 "${CP_ROOT}/subscribe/clashMeta/${CP_ALICE_MD5}")" "subscribe：模板拉不到不影响 clashMeta 重建"

# --- 用量头：成员的用量写进 subscribe.conf include 的 map；用量变化每小时至多重载一次，成员、配额、到期变了立刻生效 ---
cp_reset_tree
printf '%s\n' '# proxy-agent subscribe.conf r3' 'map $uri $paSubUserinfo {' '}' 'server {' '    listen 12345 ssl;' '}' >"${CP_ROOT}/nginx/subscribe.conf"
CP_UI_FILE="${CP_ROOT}/subscribe_userinfo.map"
CP_ALICE_LINE() { printf '~/%s$ "upload=0; download=%s; total=%s; expire=%s";' "${CP_ALICE_MD5}" "$1" "$2" "$3"; }
cp_alice_total=$(cp_state '.members.alice.quotaBytes')
: >"${CP_CALLS}"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_contains "$(cat "${CP_UI_FILE}")" "$(CP_ALICE_LINE 0 "${cp_alice_total}" 0)" "用量头：map 里有成员的 md5 与四个键"
assert_equals "2" "$(grep -c . "${CP_UI_FILE}")" "用量头：每个成员一行"
assert_equals "600" "$(stat -c %a "${CP_UI_FILE}" 2>/dev/null || stat -f %Lp "${CP_UI_FILE}")" "用量头：map 含订阅地址的 md5，只给 root 读"
assert_equals "nginx -t|nginx -s reload" "$(grep -E '^(nginx|handleNginx)' "${CP_CALLS}" | paste -sd'|' -)" "用量头：写完过 nginx -t 再 reload"
cp_ui_before=$(cat "${CP_UI_FILE}")
: >"${CP_CALLS}"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_equals "" "$(cat "${CP_CALLS}")" "用量头：没变化就不写不重载"
jq '.members.alice.downBytes += 500' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/state.json.t" && cat "${CP_ROOT}/carpool/state.json.t" >"${CP_ROOT}/carpool/state.json"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_equals "${cp_ui_before}" "$(cat "${CP_UI_FILE}")" "用量头：一小时内只有用量变了，不动文件"
assert_equals "" "$(cat "${CP_CALLS}")" "用量头：一小时内只有用量变了，不重载"
touch -t 202001010000 "${CP_UI_FILE}"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_contains "$(cat "${CP_UI_FILE}")" "$(CP_ALICE_LINE 1000 "${cp_alice_total}" 0)" "用量头：过了一小时写进新用量（billing=both 算 2 倍，全记在 download）"
assert_equals "nginx -t|nginx -s reload" "$(grep -E '^nginx' "${CP_CALLS}" | paste -sd'|' -)" "用量头：过了一小时才重载"
: >"${CP_CALLS}"
jq '.members.alice.quotaBytes = 2048 | .members.alice.expire = "2026-11-04"' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/state.json.t" && cat "${CP_ROOT}/carpool/state.json.t" >"${CP_ROOT}/carpool/state.json"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_contains "$(cat "${CP_UI_FILE}")" "$(CP_ALICE_LINE 1000 2048 1793836799)" "用量头：配额、到期变了不等一小时"
assert_equals "nginx -t|nginx -s reload" "$(grep -E '^nginx' "${CP_CALLS}" | paste -sd'|' -)" "用量头：配额、到期变了立刻重载"
: >"${CP_CALLS}"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/state.json.t" && cat "${CP_ROOT}/carpool/state.json.t" >"${CP_ROOT}/carpool/state.json"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_equals "" "$(cat "${CP_UI_FILE}")" "用量头：关了拼车 map 清空，头就不发了"
assert_equals "nginx -t|nginx -s reload" "$(grep -E '^nginx' "${CP_CALLS}" | paste -sd'|' -)" "用量头：关了拼车立刻重载"
# nginx 没在跑：只写文件，下次起来读新的；不能拉起它（tick 撞上安装流程停服的窗口会抢走 80 端口）
cp_reset_tree
printf '%s\n' 'map $uri $paSubUserinfo {' '}' 'server {' '    listen 12345 ssl;' '}' >"${CP_ROOT}/nginx/subscribe.conf"
: >"${CP_CALLS}"
run_cp 'pgrep() { return 1; }; carpoolSyncUserinfo' >/dev/null 2>&1
assert_contains "$(cat "${CP_UI_FILE}")" "${CP_ALICE_MD5}" "用量头：nginx 没在跑也写文件"
assert_equals "" "$(grep -E '^(nginx|handleNginx)' "${CP_CALLS}" || true)" "用量头：nginx 没在跑就不碰它"
# nginx -t 不过（用户自己的配置坏了）：不 reload
cp_reset_tree
printf '%s\n' 'map $uri $paSubUserinfo {' '}' 'server {' '    listen 12345 ssl;' '}' >"${CP_ROOT}/nginx/subscribe.conf"
: >"${CP_CALLS}"
CP_NGINX_T_RC=1 run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_equals "nginx -t" "$(grep -E '^nginx' "${CP_CALLS}" | paste -sd'|' -)" "用量头：nginx -t 不过就不 reload"
# 旧模板不读这个文件：不白写、不白重载
cp_reset_tree
: >"${CP_CALLS}"
run_cp 'carpoolSyncUserinfo' >/dev/null 2>&1
assert_equals "no|" "$([[ -e "${CP_UI_FILE}" ]] && echo yes || echo no)|$(grep -E '^nginx' "${CP_CALLS}" || true)" "用量头：旧模板的机器不写也不重载"
RSC_FN=$(sed -n '/^renderSubscribeConf() {/,/^EOF$/p' install.sh)
assert_contains "${RSC_FN}" 'include ${PROXY_AGENT_DIR}/subscribe_userinfo*.map;' "用量头：模板用通配 include，文件缺失时 nginx -t 照过"
assert_equals "2" "$(grep -c 'add_header Subscription-Userinfo \\$paSubUserinfo always;' <<<"${RSC_FN}")" "用量头：通用地址与定格式地址都带这个头"
assert_equals "${CP_ROOT}/subscribe_userinfo.map" "$(env PROXY_AGENT_DIR="${CP_ROOT}" bash -c 'source lib/constants.sh; printf %s "${SUBSCRIBE_USERINFO_MAP}"')" "用量头：常量里的路径与模板通配的文件名对得上"

# 「查看订阅」：回车沿用 salt，只有明确答 n 才换（换 salt 等于换掉所有人的订阅地址）
run_salt() {
    cp_reset_tree
    mkdir -p "${CP_ROOT}/subscribe/clashMetaProfiles"
    printf "$1" | run_cp "${SUBSCRIBE_FN}; ${CP_SUB_STUBS}; ${CP_WGET_OK}; readSubscribeSalt() { subscribeSalt=newsaltvalue; }; subscribe" >/dev/null 2>&1
    cat "${CP_ROOT}/subscribe_local/subscribeSalt"
}
assert_equals "testsalt" "$(run_salt '\n')" "查看订阅：回车沿用 salt"
assert_equals "testsalt" "$(run_salt 'y\n')" "查看订阅：答 y 沿用 salt"
assert_equals "newsaltvalue" "$(run_salt 'n\n')" "查看订阅：答 n 才换 salt"
assert_equals "newsaltvalue" "$(run_salt 'N\n')" "查看订阅：大写 N 也算"

rm -rf "${CP_ROOT}" "${_snap}" "${CP_TABLE}" "${CP_CALLS}" "${CP_STATS}"
echo ""

# ============================================================================
# resolveXrayVersion：默认钉版不联网；latest / prerelease 才查 GitHub
# ============================================================================

echo -e "${YELLOW}=== 测试 resolveXrayVersion ===${NC}"

RESOLVE_XRAY_FN=$(sed -n '/^resolveXrayVersion() {/,/^}/p' install.sh)
assert_not_empty "${RESOLVE_XRAY_FN}" "resolveXrayVersion：抽到函数原文"
assert_equals "yes" "$([[ "${XRAY_PINNED_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" \
    "XRAY_PINNED_VERSION 是一个完整的 release 标签（${XRAY_PINNED_VERSION}）"

# 桩 curl：第一个参数是 fail 时模拟断网并记录被调用，否则回一份含稳定版与预览版的 release 列表
run_resolve_xray() (
    eval "${RESOLVE_XRAY_FN}"
    XRAY_RELEASES_STUB='[{"tag_name":"v26.10.29","prerelease":false},{"tag_name":"v26.9.30","prerelease":true},{"tag_name":"v26.3.27","prerelease":false}]'
    curl() { if [[ "${XRAY_CURL_MODE}" == "fail" ]]; then echo "CURL_CALLED" >&2; return 1; fi; printf '%s' "${XRAY_RELEASES_STUB}"; }
    XRAY_CURL_MODE="$2"
    resolveXrayVersion "$1" 2>&1
)
assert_equals "${XRAY_PINNED_VERSION}" "$(run_resolve_xray pinned fail)" "pinned：回钉住的标签且不联网（断网桩未被调用）"
assert_equals "${XRAY_PINNED_VERSION}" "$(run_resolve_xray "" ok)" "无参默认即 pinned"
assert_equals "v26.10.29" "$(run_resolve_xray latest ok)" "latest：取列表里第一个非预览版"
assert_equals "v26.9.30" "$(run_resolve_xray prerelease ok)" "prerelease：取列表里第一个预览版"
assert_equals "CURL_CALLED" "$(run_resolve_xray latest fail)" "latest：断网时真的去查了且不回任何标签，由调用方报错"

# 两个装核入口都只经 resolveXrayVersion 取版本：直接拼 API 的旧写法回潮就会绕过钉版
INSTALL_XRAY_FN=$(sed -n '/^installXray() {/,/^}/p;/^updateXray() {/,/^}/p' install.sh)
assert_equals "0" "$(grep -c 'api.github.com/repos/XTLS' <<<"${INSTALL_XRAY_FN}")" "installXray / updateXray 不再直接查 GitHub release 列表"
assert_equals "3" "$(grep -c 'resolveXrayVersion' <<<"${INSTALL_XRAY_FN}")" "installXray 一处、updateXray 两处经 resolveXrayVersion 取版本"

echo ""

# ============================================================================
# reloadCore：Xray 内核上旁挂的 sing-box 片段里有入站就跟着重启，一个不剩就停掉
# ============================================================================

echo -e "${YELLOW}=== 测试 reloadCore 的分派 ===${NC}"

RELOAD_FN=$(sed -n '/^singBoxFragmentsHaveInbounds() {/,/^}/p;/^reloadCore() {/,/^}/p' install.sh)
assert_equals "2" "$(grep -c '^[a-zA-Z]*() {$' <<<"${RELOAD_FN}")" "reloadCore：抽到两个函数原文"
RELOAD_DIR="${MOCK_ROOT}/reload"

# run_reload CORE SIDECAR6_9 RUNNING → 在干净 bash 里以 RELOAD_DIR 为安装根跑 reloadCore，打印启停调用序列（空格分隔）
run_reload() {
    env PROXY_AGENT_DIR="${RELOAD_DIR}" RELOAD_FN="${RELOAD_FN}" R_CORE="$1" R_SIDECAR="$2" RUNNING="$3" bash -c '
        source lib/constants.sh
        eval "${RELOAD_FN}"
        readInstallType() { coreKind="${R_CORE}"; singBoxConfigPath="${R_SIDECAR}"; currentInstallProtocolType=",7,"; }
        handleXray() { calls+="xray-$1 "; }
        handleSingBox() { calls+="singbox-$1 "; }
        singBoxAutostart() { calls+="autostart-$1 "; }
        pgrep() { [[ -n "${RUNNING}" ]] && echo 4242; }
        calls=
        reloadCore
        printf "%s\n" "${calls% }"'
}
reload_tree() { # FRAGMENT_JSON... → 重建安装根下的 sing-box 二进制与片段目录
    local dir="${RELOAD_DIR}/sing-box/conf/config" i=0 f
    rm -rf "${RELOAD_DIR}" && mkdir -p "${dir}" && touch "${RELOAD_DIR}/sing-box/sing-box"
    for f in "$@"; do printf '%s\n' "${f}" >"${dir}/$((i++))_frag.json"; done
}
rm -rf "${RELOAD_DIR}"
assert_equals "xray-stop xray-start autostart-off" "$(run_reload 1 "" "")" "Xray 内核、没装 sing-box：只重启 Xray（关自启在没有服务文件时什么都不做）"
reload_tree '{"log":{"level":"info"}}' '{"inbounds":[{"type":"socks","tag":"chain_bridge_in"}]}' '{"outbounds":[{"type":"direct"}]}'
assert_equals "xray-stop xray-start singbox-stop singbox-start autostart-on" "$(run_reload 1 "" "")" "Xray 内核、片段里有链式的桥：连旁挂的 sing-box 一起重启，并确保开机自启"
reload_tree '{"log":{"level":"info"}}' '{"inbounds":[]}' '{"outbounds":[{"type":"direct"}]}'
assert_equals "xray-stop xray-start singbox-stop autostart-off" "$(run_reload 1 "" yes)" "Xray 内核、片段里一个入站都不剩、sing-box 还在跑：停掉它，并关掉开机自启（否则重启后起一个空 sing-box）"
assert_equals "xray-stop xray-start autostart-off" "$(run_reload 1 "" "")" "Xray 内核、没有入站、sing-box 也没在跑：不启停它，只确保自启关着"
reload_tree '{"inbounds":[' '{"outbounds":[]}'
assert_equals "xray-stop xray-start singbox-stop singbox-start autostart-on" "$(run_reload 1 "" yes)" "片段读不懂：照常重启，让合并去报错，不当成没东西停掉"
reload_tree '{"outbounds":[]}'
assert_equals "xray-stop xray-start singbox-stop singbox-start autostart-on" "$(run_reload 1 "${RELOAD_DIR}/sing-box/conf/config/" "")" "Xray 内核装了 6 / 9（singBoxConfigPath 非空）：照旧重启"
assert_equals "singbox-stop singbox-start autostart-on" "$(run_reload 2 "${RELOAD_DIR}/sing-box/conf/config/" "")" "sing-box 内核：只重启 sing-box"

echo ""

# ============================================================================
# 按账号选出口：映射 → Xray 路由与桥、合并期注入 sing-box、坏状态必须失败、换配置码带映射、删账号连映射一起删、菜单
# ============================================================================

echo -e "${YELLOW}=== 测试按账号选出口 ===${NC}"

CA_FN_NAMES="localBlockApiPort localGlobalAddrs ensureXrayLocalBlock localBlockInject directOutboundInject chainAccountStateFile chainAccountReadState chainAccountBridges chainAccountAssignPorts writeXrayChainConfig chainAccountInject chainAccountCarry chainAccountApply xrayConfigTest chainAccountSave chainAccountForget chainAccountAllNames chainAccountExitLabel chainAccountExitMenu writeChainInfoAtomic validateChainName removeMultiChainOutbound chainReadRule chainRuleLabel getPresetDisplayName validateIpCidrs updateChainKey showMultiChainSummary multiChainAddChain testMultiChainConnection testExternalNodeConnection selectSSMethod setupExternalAsSingleExit chainExternalSingleOnXray generateExternalOutboundConfig getExternalNodeById initExternalNodeFile"
CA_FNS=$(sed -n "$(for _f in ${CA_FN_NAMES}; do printf '/^%s() {/,/^}/p\n' "${_f}"; done)" install.sh)
assert_equals "$(wc -w <<<"${CA_FN_NAMES}" | tr -d ' ')" "$(grep -c '^[a-zA-Z0-9]*() {$' <<<"${CA_FNS}")" "按账号选出口：每个函数都抽到了"
CA_ROOT="${MOCK_ROOT}/chainacct.root"
CA_CALLS="${MOCK_ROOT}/chainacct_calls"
CA_X="${CA_ROOT}/xray/conf"
CA_F="${CA_ROOT}/sing-box/conf/config"
CA_ENTRY="${CA_ROOT}/sing-box/conf/chain_entry_info.json"
CA_MULTI="${CA_ROOT}/sing-box/conf/chain_multi_info.json"
CA_MERGED="${MOCK_ROOT}/chainacct_merged.json"

# run_ca CMD → 以 CA_ROOT 为安装根跑 CMD；合并与重载桩掉（调用记进 CA_CALLS，CA_MERGE_RC 让合并失败，
# XRAY_TEST_FAIL=once 让装了的 xray 桩第一次 -test 不过，CA_LISTEN 是本机正在听的 TCP 端口）
run_ca() (
    env PROXY_AGENT_DIR="${CA_ROOT}" CA_FNS="${CA_FNS}" CA_ADDRS="${CA_ADDRS:-}" CA_CALLS="${CA_CALLS}" CA_MERGE_RC="${CA_MERGE_RC:-0}" XRAY_TEST_FAIL="${XRAY_TEST_FAIL:-}" CA_LISTEN="${CA_LISTEN:-}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
        eval "${CA_FNS}"
        ip() { [[ -n "${CA_ADDRS}" ]] && printf "%s\n" "${CA_ADDRS}"; }
        singBoxMergeConfig() { echo merge >>"${CA_CALLS}"; return "${CA_MERGE_RC}"; }
        reloadCore() { echo reloadCore >>"${CA_CALLS}"; }
        listeningPorts() { [[ "$1" == tcp ]] && printf "%s\n" ${CA_LISTEN}; }
        setDefaultChain() { echo setDefaultChain >>"${CA_CALLS}"; }
        generateMultiChainRouteConfig() { echo routeConfig >>"${CA_CALLS}"; }
        ensureDirectOutbound() { echo "{\"outbounds\":[{\"type\":\"direct\",\"tag\":\"direct\"}]}" >"${singBoxConfigPath}01_direct_outbound.json"; }
        eval "$1"' _ "$1"
)
ca_reset() {
    rm -rf "${CA_ROOT}" && mkdir -p "${CA_X}" "${CA_F}"
    : >"${CA_CALLS}"
}
ca_single() { jq -cn --argjson extra "$1" '{schema_version: 1, role: "entry", exit_ip: "198.51.100.7", exit_port: 5000, bridge_port: 31111, has_xray: true} + $extra' >"${CA_ENTRY}"; }
# 三条链路：us、hk 已经分过桥端口（故意与名字顺序相反），jp 还没有
ca_multi() {
    jq -cn --argjson extra "$1" '{schema_version: 1, role: "entry", mode: "multi_chain", default_chain: "direct", bridge_port: 31111, has_xray: true, rules: [],
        chains: [{name: "us", ip: "198.51.100.1", port: 5001, bridge_port: 31112}, {name: "hk", ip: "198.51.100.2", port: 5002, bridge_port: 31115},
                 {name: "jp", ip: "198.51.100.3", port: 5003}]} + $extra' >"${CA_MULTI}"
}
ca_rules() { jq -c "$1" "${CA_X}/09_routing.json"; }
# ca_chain_rules 只看链式自己的规则：writeXrayChainConfig 写完就补上的 local-block 组单独断言
ca_chain_rules() { jq -c '.routing.rules |= map(select((.ruleTag // "") | startswith("local-block") | not))' "${CA_X}/09_routing.json" | jq -c "$1"; }
ca_outs() { jq -c '[.outbounds[] | "\(.tag):\(.settings.servers[0].port // .protocol)"]' "${CA_X}/chain_outbound.json"; }
ca_re_hits() { jq -r --arg s "$1" '[.routing.rules[] | select(.user) | .user[] | ltrimstr("regexp:") as $re | $s | test($re)] | any' "${CA_X}/09_routing.json"; }

# --- Xray 侧：单链路 ---
ca_reset
printf '%s\n' '{"routing":{"rules":[{"type":"field","domain":["example.org"],"outboundTag":"IPv6_out"}]}}' >"${CA_X}/09_routing.json"
_caOrig=$(cat "${CA_X}/09_routing.json")
ca_single '{"accounts": {"alice": "direct", "a.b+c": "chain_outbound"}}'
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals "0" "$?" "Xray 侧（单链路）：写入返回 0"
assert_equals '["chain_proxy:31111","chain_direct:freedom"]' "$(ca_outs)" "Xray 侧（单链路）：默认桥的 chain_proxy 打头（第一个出站是默认），链式自己的直连排在后面，不另开桥"
assert_equals '["chain_direct","chain_proxy","chain_proxy","chain_proxy"]' "$(ca_chain_rules '[.routing.rules[].outboundTag]')" \
    "Xray 侧（单链路）：按账号 → gstatic 与兜底走链路；直连指向 chain_direct，不靠 WARP / IPv6 全局会删掉的 z_direct_outbound"
assert_equals '["local-block-port","local-block-ip"]' "$(jq -c '[.routing.rules[0:2][].ruleTag]' "${CA_X}/09_routing.json")" \
    "Xray 侧：写完当场把封本机的规则补在最前，不等下一次启动"
assert_equals 'regexp:^a\.b\+c-[^-]*$' "$(ca_chain_rules '.routing.rules[] | select(.outboundTag == "chain_proxy" and .user) | .user[0]' | jq -r .)" "Xray 侧：账号名里的 . 与 + 转义"
assert_equals "true" "$(ca_re_hits 'a.b+c-VLESS_WS')" "Xray 侧：正则命中这个账号带协议后缀的 email"
assert_equals "false" "$(ca_re_hits 'axb+c-VLESS_WS')" "Xray 侧：. 不当通配（axb+c 不命中）"
assert_equals "false" "$(ca_re_hits 'alice-x-VLESS_WS')" "Xray 侧：alice-x 这个别的账号不命中 alice 的规则"
assert_equals "${_caOrig}" "$(cat "${CA_X}/09_routing.json.bak.chain")" "Xray 侧：第一次写时把原路由存成 .bak.chain"
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals "${_caOrig}" "$(cat "${CA_X}/09_routing.json.bak.chain")" "Xray 侧：再写一次不覆盖备份（否则拆链式时恢复出来的是链式路由）"
printf '%s\n' '{"routing":{"rules":[{"type":"field","domain":["domain:gstatic.com"],"outboundTag":"z_direct_outbound"}]}}' >"${CA_X}/09_routing.json"
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals '["chain_direct","chain_proxy","chain_proxy","chain_proxy"]' "$(ca_chain_rules '[.routing.rules[].outboundTag]')" \
    "Xray 侧：重装把 09_routing.json 换回模板后，下一次写入（每次启动前都有）把链式路由写回来"
assert_equals "${_caOrig}" "$(cat "${CA_X}/09_routing.json.bak.chain")" "Xray 侧：写回时备份仍是最早的原路由"
rm -f "${CA_X}/09_routing.json"
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals '["chain_direct","chain_proxy","chain_proxy","chain_proxy"]' "$(ca_chain_rules '[.routing.rules[].outboundTag]')" \
    "Xray 侧：WARP / IPv6 全局删掉 09_routing.json 后同样写回"
ca_single '{"default_chain": "direct"}'
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals '["chain_direct","chain_direct"]' "$(ca_chain_rules '[.routing.rules[].outboundTag]')" "Xray 侧（单链路默认直连）：gstatic 与兜底都直连"
printf '%s\n' '{broken' >"${CA_X}/zz_hand_written.json"
assert_contains "$(run_ca 'writeXrayChainConfig 31111; echo rc=$?' 2>&1)" "rc=1" "Xray 侧：有 jq 读不了的片段时补不上封锁，返回 1 报出来，不静默跳过"
rm -f "${CA_X}/zz_hand_written.json"

# --- Xray 侧：多链路 ---
ca_reset
ca_multi '{"accounts": {"alice": "hk", "bob": "us", "carol": "direct"}}'
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals '["chain_proxy:31111","chain_proxy_hk:31115","chain_proxy_us:31112","chain_direct:freedom"]' "$(ca_outs)" \
    "Xray 侧（多链路）：被引用的链路各开一条桥，端口是链路自己的 bridge_port；jp 没人用不开"
assert_equals '["chain_direct","chain_proxy_hk","chain_proxy_us","chain_proxy","chain_proxy"]' "$(ca_chain_rules '[.routing.rules[].outboundTag]')" \
    "Xray 侧（多链路）：指定的人各走各的桥，其余进默认桥由 sing-box 按域名分"
assert_equals 'regexp:^alice-[^-]*$' "$(ca_chain_rules '.routing.rules[] | select(.outboundTag == "chain_proxy_hk") | .user[0]' | jq -r .)" "Xray 侧（多链路）：alice 的规则指向 hk 的桥"
ca_multi '{"accounts": {"alice": "hk"}}'
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
assert_equals '["chain_proxy:31111","chain_proxy_hk:31115","chain_direct:freedom"]' "$(ca_outs)" \
    "Xray 侧（多链路）：bob 不再指定 us 之后 hk 的端口不变（按位置排的话会挪，重启间隙里新旧两个内核会把人送进别的出口）"

# --- 分配桥端口 ---
assert_equals '["us=31112","hk=31113","jp=null"]' \
    "$(run_ca "chainAccountAssignPorts '$(jq -cn '{mode: "multi_chain", accounts: {alice: "hk", bob: "us"}, chains: [{name: "us", bridge_port: 31112}, {name: "hk"}, {name: "jp"}]}')'" 2>/dev/null | jq -c '[.chains[] | "\(.name)=\(.bridge_port)"]')" \
    "分配：新被引用的 hk 拿最小的空端口，已有的 us 不动，没人用的 jp 不分"
assert_equals '["us=31112","hk=31115","jp=null"]' \
    "$(CA_LISTEN="22 31113 31114" run_ca "chainAccountAssignPorts '$(jq -cn '{mode: "multi_chain", accounts: {alice: "hk", bob: "us"}, chains: [{name: "us", bridge_port: 31112}, {name: "hk"}, {name: "jp"}]}')'" 2>/dev/null | jq -c '[.chains[] | "\(.name)=\(.bridge_port)"]')" \
    "分配：本机已有进程在听的 31113、31114 跳过（sing-box 绑不上会直接退出，回滚到不了）"
_caFull=$(jq -cn '{mode: "multi_chain", accounts: {alice: "new"}, chains: ([range(31112; 31211)] | to_entries | map({name: "c\(.key)", bridge_port: .value}) + [{name: "new"}])}')
assert_contains "$(run_ca "chainAccountAssignPorts '${_caFull}'; echo rc=\$?" 2>&1)" "rc=5" "分配：31112-31210 全占满时报错，不越界"
assert_equals '{"accounts":{"a":"chain_outbound"}}' "$(run_ca "chainAccountAssignPorts '{\"accounts\":{\"a\":\"chain_outbound\"}}'" 2>/dev/null)" "分配：单链路 / 多跳原样返回"

# --- sing-box 侧：合并期注入（多链路，Xray 机上有桥与旁挂 6） ---
ca_multi '{"accounts": {"alice": "hk", "bob": "us", "carol": "direct"}}'
run_ca 'writeXrayChainConfig 31111' >/dev/null 2>&1
jq -n '{inbounds: [
        {type: "socks", tag: "chain_bridge_in", listen: "127.0.0.1", listen_port: 31111},
        {type: "hysteria2", tag: "singbox-hysteria2-in", users: [{name: "alice-singbox_hysteria2", password: "p"}, {name: "dave-singbox_hysteria2", password: "p"}]},
        {type: "shadowsocks", tag: "relay-in", users: [{name: "alice", password: "p"}]}],
    route: {rules: [{inbound: "chain_bridge_in", action: "sniff", timeout: "1s"}, {rule_set: ["geosite-netflix"], outbound: "us"}], final: "direct"}}' >"${CA_MERGED}"
run_ca "chainAccountInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals "0" "$?" "注入（多链路）：返回 0"
assert_equals '["chain_acct_in_hk:31115","chain_acct_in_us:31112"]' "$(jq -c '[.inbounds[] | select(.tag | startswith("chain_acct_in_")) | "\(.tag):\(.listen_port)"]' "${CA_MERGED}")" \
    "注入（多链路）：被引用的链路各开一条桥，听它自己的 bridge_port"
assert_equals "$(jq -c '[.outbounds[] | select(.tag | startswith("chain_proxy_")) | {(.tag | ltrimstr("chain_proxy_")): .settings.servers[0].port}] | add' "${CA_X}/chain_outbound.json")" \
    "$(jq -c '[.inbounds[] | select(.tag | startswith("chain_acct_in_")) | {(.tag | ltrimstr("chain_acct_in_")): .listen_port}] | add' "${CA_MERGED}")" \
    "注入（多链路）：每条链路的 Xray 出站端口 = sing-box 入站端口"
assert_equals '[["chain_acct_in_hk","chain_acct_in_us"],"sniff"]' "$(jq -c '[.route.rules[0].inbound, .route.rules[0].action]' "${CA_MERGED}")" "注入：新桥先 sniff"
assert_equals "resolve" "$(jq -r '.route.rules[1].action' "${CA_MERGED}")" "注入：再 prefer_ipv4 重解析"
assert_equals '[{"inbound":["chain_acct_in_hk"],"outbound":"hk"},{"inbound":["chain_acct_in_us"],"outbound":"us"},{"auth_user":["alice-singbox_hysteria2"],"outbound":"hk"}]' \
    "$(jq -c '.route.rules[2:5]' "${CA_MERGED}")" "注入：桥各进各的链路；旁挂 6 的 alice 按全名进 hk；没后缀的 alice 与没指定的 dave 不在里面"
assert_equals '[{"inbound":"chain_bridge_in","action":"sniff","timeout":"1s"},{"rule_set":["geosite-netflix"],"outbound":"us"}]' "$(jq -c '.route.rules[5:]' "${CA_MERGED}")" \
    "注入：原有的域名分流排在账号规则之后（被指定的人以映射为终态）"
assert_equals "direct" "$(jq -r '.route.final' "${CA_MERGED}")" "注入（多链路）：final 不动"
jq '.outbounds = [{type: "direct", tag: "direct"}, {type: "socks", tag: "us"}]' "${CA_MERGED}" >"${CA_MERGED}.t" && mv "${CA_MERGED}.t" "${CA_MERGED}"
run_ca "chainAccountInject ${CA_MERGED} && directOutboundInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals '["direct","us"]' "$(jq -c '[.outbounds[].tag]' "${CA_MERGED}")" "合并：已有 direct 出站时不重复补"

# --- sing-box 侧：sing-box 内核单链路，默认直连 ---
ca_reset
ca_single '{"accounts": {"bob": "chain_outbound"}, "default_chain": "direct"}'
jq -n '{inbounds: [
        {type: "vless", tag: "VLESSReality", users: [{name: "bob-VLESS_Reality_Vision", uuid: "u"}, {name: "eve-VLESS_Reality_Vision", uuid: "u"}]},
        {type: "naive", tag: "naive-in", users: [{username: "bob-singbox_naive", password: "p"}]}],
    route: {final: "chain_outbound"}}' >"${CA_MERGED}"
cp "${CA_MERGED}" "${CA_MERGED}.orig"
run_ca "chainAccountInject ${CA_MERGED} && directOutboundInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals '[{"auth_user":["bob-VLESS_Reality_Vision","bob-singbox_naive"],"outbound":"chain_outbound"}]' "$(jq -c '.route.rules' "${CA_MERGED}")" \
    "注入（sing-box 内核）：bob 在两个协议里的全名都进规则（naive 用 username）"
assert_equals "direct" "$(jq -r '.route.final' "${CA_MERGED}")" "注入（单链路默认直连）：final 改成 direct"
assert_equals '["direct"]' "$(jq -c '[.outbounds[].tag]' "${CA_MERGED}")" "合并（IPv6 全局删掉了 direct 出站）：补一个，final 与直连账号才有处可去"
assert_equals "0" "$(jq '[.inbounds[] | select(.tag | startswith("chain_acct_in_"))] | length' "${CA_MERGED}")" "注入（sing-box 内核）：没有 Xray 的桥就不开新桥"
jq -cn '{accounts: {bob: "chain_outbound"}}' >"${CA_ENTRY}"
cp "${CA_MERGED}.orig" "${CA_MERGED}"
run_ca "chainAccountInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals '["bob-VLESS_Reality_Vision","bob-singbox_naive"]' "$(jq -c '.route.rules[0].auth_user' "${CA_MERGED}")" "注入（状态缺 role）：照常读映射，不当成「不是入口」跳过"
# sing-box 1.12.0–1.14.3 的 merge 把 naive 的用户写成 Go 字段名 Username / Password，1.14.4 起才是小写
jq '.inbounds[1].users = [{Username: "bob-singbox_naive", Password: "p"}]' "${CA_MERGED}.orig" >"${CA_MERGED}"
run_ca "chainAccountInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals '["bob-VLESS_Reality_Vision","bob-singbox_naive"]' "$(jq -c '.route.rules[0].auth_user' "${CA_MERGED}")" "注入（旧版 merge 的大写 Username）：naive 账号照样进规则，不落到默认出口"

# --- 没有映射、external_single、坏状态 ---
ca_reset
printf '%s\n' '{"route":{"final":"chain_outbound"}}' >"${CA_MERGED}"
_caBefore=$(cat "${CA_MERGED}")
run_ca "chainAccountInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals "0|${_caBefore}" "$?|$(cat "${CA_MERGED}")" "注入（没有链式）：返回 0、合并结果原样"
jq -cn '{role: "entry", mode: "external_single", accounts: {bob: "direct"}}' >"${CA_ENTRY}"
run_ca "chainAccountInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals "0|${_caBefore}" "$?|$(cat "${CA_MERGED}")" "注入（external_single）：不支持的入口不注入"
for _caBad in '{"role":' 'null' '{"role":"entry","accounts":{"bob":"nope"}}' '{"role":"entry","accounts":{"a*b":"direct"}}' \
        '{"role":"entry","accounts":{"alice\n":"direct"}}' '{"role":"entry","default_chain":"us"}'; do
    printf '%s\n' "${_caBad}" >"${CA_ENTRY}"
    _out=$(run_ca "chainAccountInject ${CA_MERGED}; echo rc=\$?" 2>&1)
    assert_contains "${_out}" "rc=1" "注入（坏状态 ${_caBad}）：返回 1，合并随之失败而不是跳过映射"
done
assert_contains "${_out}" "default_chain=us" "注入（坏状态）：说出哪一项不合法"
rm -f "${CA_ENTRY}"
ca_multi '{"accounts": {"alice": "zz"}}'
assert_contains "$(run_ca "chainAccountInject ${CA_MERGED}; echo rc=\$?" 2>&1)" "alice=zz" "注入（多链路指向不存在的链路）：返回 1 并列出"
ca_multi '{"accounts": {"alice": "jp"}}'
assert_contains "$(run_ca "chainAccountInject ${CA_MERGED}; echo rc=\$?" 2>&1)" "bridge_port(jp)=null" "注入（被引用的链路没有桥端口）：返回 1"
jq '.chains[1].bridge_port = 31112 | .accounts = {alice: "hk"}' "${CA_MULTI}" >"${CA_MULTI}.t" && mv "${CA_MULTI}.t" "${CA_MULTI}"
assert_contains "$(run_ca "chainAccountInject ${CA_MERGED}; echo rc=\$?" 2>&1)" "rc=1" "注入（两条链路同一个桥端口）：返回 1"

# --- 换出口配置码带上映射 ---
ca_reset
jq -cn '{role: "entry", mode: "multi_hop", accounts: {alice: "direct"}, default_chain: "direct"}' >"${CA_ENTRY}"
assert_equals '{"role":"entry","exit_ip":"203.0.113.5","accounts":{"alice":"direct"},"default_chain":"direct"}' \
    "$(run_ca "chainAccountCarry '{\"role\":\"entry\",\"exit_ip\":\"203.0.113.5\"}'" 2>/dev/null)" "换配置码：旧的 accounts 与 default_chain 带到新状态"
jq -cn '{role: "entry", mode: "external_single", accounts: {alice: "direct"}}' >"${CA_ENTRY}"
assert_equals '{"role":"entry"}' "$(run_ca "chainAccountCarry '{\"role\":\"entry\"}'" 2>/dev/null)" "换配置码：external_single 的旧状态不带"
printf '%s\n' '{"role":' >"${CA_ENTRY}"
assert_contains "$(run_ca "chainAccountCarry '{\"role\":\"entry\"}'; echo rc=\$?" 2>&1)" "rc=1" "换配置码：旧状态读不懂就失败，不带着空映射继续（否则标了直连的人全进链路）"

# --- 删账号连映射一起删 ---
ca_reset
ca_single '{"accounts": {"alice": "direct", "bob": "chain_outbound"}}'
printf '%s\n' '{"outbounds":[]}' >"${CA_X}/chain_outbound.json"
run_ca 'chainAccountForget alice' >/dev/null 2>&1
assert_equals '{"bob":"chain_outbound"}' "$(jq -c '.accounts' "${CA_ENTRY}")" "删账号：映射里的 alice 删掉（否则同名新账号会继承旧出口）"
assert_equals "false" "$(ca_re_hits 'alice-VLESS_WS')" "删账号：Xray 路由随之重写，alice 不再有规则"
_caBefore=$(cat "${CA_ENTRY}")
run_ca 'chainAccountForget zed' >/dev/null 2>&1
assert_equals "0|${_caBefore}" "$?|$(cat "${CA_ENTRY}")" "删账号：没映射的账号不碰状态"

# --- 链路名保留 direct、删链路前查映射 ---
assert_equals "1 0" "$(run_ca 'validateChainName direct; a=$?; validateChainName us_west; echo "${a} $?"')" "链路名：direct 保留（它是直连的 tag，也是映射里「直连」的写法）"
ca_reset
ca_multi '{"accounts": {"alice": "hk", "bob": "hk"}}'
touch "${CA_F}/chain_outbound_hk.json" "${CA_F}/chain_outbound_jp.json"
_out=$(printf '2\n' | run_ca 'removeMultiChainOutbound; echo rc=$?' 2>&1)
assert_contains "${_out}" "还是这些账号指定的出口：alice, bob" "删链路（有人指定）：拒绝并列出账号"
assert_equals "rc=1|yes" "$(grep -o 'rc=[0-9]' <<<"${_out}")|$([[ -f "${CA_F}/chain_outbound_hk.json" ]] && echo yes)" "删链路（有人指定）：返回 1，出站文件还在"
printf '3\ny\n' | run_ca 'removeMultiChainOutbound' >/dev/null 2>&1
assert_equals "no|us,hk" "$([[ -f "${CA_F}/chain_outbound_jp.json" ]] && echo yes || echo no)|$(jq -r '[.chains[].name] | join(",")' "${CA_MULTI}")" "删链路（没人指定）：照常删"

# --- 分流规则的选择：两个向导与规则菜单共用，输错重问，不静默落成没有规则 ---
_caRule() { printf "$2" | run_ca "chainReadRule $1; echo \"rc=\$?|\${chainRuleType}|\${chainRuleValue}|\$(chainRuleLabel \"\${chainRuleType}\" \"\${chainRuleValue}\")\"" 2>/dev/null | grep -o 'rc=.*'; }
assert_equals "rc=0|none||待配置" "$(_caRule later '1\n')" "选规则（向导）：1 是稍后统一配置"
assert_equals "rc=0|preset|ai|AI服务 (OpenAI/Bing/...)" "$(_caRule later '2\n2\n')" "选规则（向导）：2 进预设的二级菜单，再选 2 是 AI"
assert_equals "rc=0|preset|streaming|流媒体 (Netflix/Disney+/YouTube/...)" "$(_caRule later '2b\n2\n9\n2\n1\n')" \
    "选规则：旧写法 2b 与二级菜单里越界的 9 都重问，不落成没有规则"
assert_equals "rc=0|ip_cidr|10.0.0.0/8|IP CIDR" "$(_caRule later '4\n\n4\n10.0.0.0/33\n4\n10.0.0.0/8\n')" "选规则：IP CIDR 留空或不合法都重问"
assert_equals "rc=0|geoip|kr|geoip-kr" "$(_caRule later '5\n8\nKR\n')" "选规则：自定义 GeoIP 转小写"
assert_equals "rc=0|default||所有未匹配流量" "$(_caRule later '5\n8\nk r\n6\n')" "选规则：GeoIP 代码带空格之类的字符重问；6 是设为默认链路"
assert_equals "rc=0|custom|a.com,b.org|自定义域名" "$(_caRule '' '2\n\n2\na.com,b.org\n')" "选规则（规则菜单，没有稍后配置）：2 是自定义域名，留空重问"
assert_equals "rc=1||" "$(_caRule later '' | cut -d'|' -f1-3)" "选规则：读不到输入就返回 1，不空转"

# --- 多链路汇总：每种规则都有名字，IP CIDR 的链路不显示成待配置 ---
ca_reset
ca_multi '{"rules": [{"type": "ip_cidr", "value": "10.0.0.0/8", "chain": "us"}, {"type": "geoip", "value": "jp", "chain": "jp"}]}'
_out=$(run_ca 'showMultiChainSummary' 2>&1)
assert_contains "$(grep '^  us ' <<<"${_out}")" "IP CIDR" "多链路汇总：按 IP CIDR 分流的链路显示 IP CIDR，不是待配置"
assert_contains "$(grep '^  jp ' <<<"${_out}")" "geoip-jp" "多链路汇总：GeoIP 链路显示 geoip-jp"
assert_contains "$(grep '^  hk ' <<<"${_out}")" "待配置" "多链路汇总：没规则的链路才是待配置"

# --- 已有多链路时继续添加：也能选外部节点，加完重建路由并生效 ---
ca_reset
_caAdd='addSingleChainOutbound() { echo code >>"${CA_CALLS}"; }; addExternalNodeAsChain() { echo external >>"${CA_CALLS}"; }; multiChainAddChain'
printf '2\n' | run_ca "${_caAdd}" >/dev/null 2>&1
assert_equals "external routeConfig merge reloadCore" "$(paste -sd ' ' - <"${CA_CALLS}")" "继续添加（多链路）：选 2 通过外部节点添加，随后重建路由、合并、重载"
: >"${CA_CALLS}"
printf '0\n' | run_ca "${_caAdd}" >/dev/null 2>&1
assert_equals "" "$(cat "${CA_CALLS}")" "继续添加（多链路）：选 0 取消，什么都不动"

# --- 外部节点测试：TCP 通之后经节点真取一次出口 IP，认证不对要报失败 ---
ca_reset
jq -cn '{nodes: [{id: "n1", name: "good", type: "shadowsocks", server: "192.0.2.20", server_port: 8388, method: "aes-128-gcm", password: "right"},
                 {id: "n2", name: "bad", type: "shadowsocks", server: "192.0.2.21", server_port: 8388, method: "aes-128-gcm", password: "wrong"}]}' \
    >"${CA_ROOT}/sing-box/conf/external_node_info.json"
# 桩：TCP 一律通；假 sing-box 只在密码对时「取到」出口 IP，并记下收到的参数
mkdir -p "${CA_ROOT}/sing-box"
printf '%s\n' '#!/bin/bash' 'echo "$*" >>"$(dirname "$0")/argv"' \
    'jq -e ".outbounds[0].password == \"right\" and .route.default_domain_resolver == \"local\"" "$4" >/dev/null && echo 203.0.113.9' >"${CA_ROOT}/sing-box/sing-box"
chmod +x "${CA_ROOT}/sing-box/sing-box"
_caExt='listExternalNodes() { :; }; getExternalNodeCount() { echo 2; }; timeout() { [[ "$1" == 5 ]] && return 0; shift; "$@"; }; testExternalNodeConnection; echo rc=$?'
_out=$(printf '1\n' | run_ca "${_caExt}" 2>&1)
assert_contains "${_out}" "出口 IP：203.0.113.9" "外部节点测试（密码对）：经节点取到出口 IP 才报成功"
assert_contains "$(head -1 "${CA_ROOT}/sing-box/argv")" "tools fetch -c " "外部节点测试：用 sing-box tools fetch 经这个出站发请求，不起常驻进程"
mkdir -p "${CA_ROOT}/tmp"
_out=$(printf '2\n' | run_ca "export TMPDIR=${CA_ROOT}/tmp; ${_caExt}" 2>&1)
assert_contains "${_out}" "访问外网失败" "外部节点测试（密码错）：TCP 通也报失败，不再只看端口"
assert_equals "" "$(ls -A "${CA_ROOT}/tmp")" "外部节点测试：带凭据的临时配置用完即删"
rm -f "${CA_ROOT}/sing-box/sing-box"
assert_contains "$(printf '1\n' | run_ca "${_caExt}" 2>&1)" "只测了 TCP 端口" "外部节点测试（没装 sing-box）：如实说只测了端口"

# --- 外部节点：加密方式菜单不进节点；Xray 上拒绝设为唯一出口；合并失败还原；旧版写坏的节点拦下 ---
assert_equals "aes-256-gcm" "$(printf '2\n' | run_ca 'SS_METHODS=(aes-128-gcm aes-256-gcm); selectSSMethod' 2>/dev/null)" \
    "选加密方式：stdout 只有选中的方式，菜单文字不能被 \$() 一起存进节点"
ca_ext_nodes() {
    ca_reset
    jq -cn --arg bad "$(printf 'Select:\n  1. aes-128-gcm\naes-256-gcm')" '{nodes: [
        {id: "n1", name: "good", type: "shadowsocks", server: "192.0.2.20", server_port: 8388, method: "aes-128-gcm", password: "p"},
        {id: "n2", name: "old", type: "shadowsocks", server: "192.0.2.21", server_port: 8388, method: $bad, password: "p"}]}' \
        >"${CA_ROOT}/sing-box/conf/external_node_info.json"
}
ca_chain_files() { find "${CA_F}" -name 'chain_*' | wc -l | tr -d ' '; }
_caSingle='listExternalNodes() { :; }; getExternalNodeCount() { echo 2; }; ensureSingBoxInstalled() { :; }; setupExternalAsSingleExit; echo rc=$?'

ca_ext_nodes
_out=$(printf '1\n' | run_ca "coreKind=1; ${_caSingle}" 2>&1)
assert_equals "rc=1" "$(tail -n 1 <<<"${_out}")" "外部节点唯一出口（Xray）：拒绝，流量到不了 sing-box 片段，接了只会报成功"
assert_contains "${_out}" "多链路" "外部节点唯一出口（Xray）：指向能用的多链路"
assert_equals "0|no|" "$(ca_chain_files)|$([[ -f "${CA_ENTRY}" ]] && echo yes || echo no)|$(cat "${CA_CALLS}")" \
    "外部节点唯一出口（Xray）：不写片段与状态，也不重载"

ca_ext_nodes
_out=$(printf '1\n' | run_ca "coreKind=2; ${_caSingle}" 2>&1)
assert_equals "rc=0" "$(tail -n 1 <<<"${_out}")" "外部节点唯一出口（sing-box）：照常配置"
assert_equals "external_single|chain_external_outbound|merge reloadCore" \
    "$(jq -r .mode "${CA_ENTRY}")|$(jq -r .route.final "${CA_F}/chain_route.json")|$(paste -sd ' ' - <"${CA_CALLS}")" \
    "外部节点唯一出口（sing-box）：状态、路由写好，合并后重载"

ca_ext_nodes
printf '{"old":1}\n' >"${CA_F}/chain_route.json"
_out=$(printf '1\n' | CA_MERGE_RC=1 run_ca "coreKind=2; ${_caSingle}" 2>&1)
assert_equals "rc=1" "$(tail -n 1 <<<"${_out}")" "外部节点唯一出口（合并失败）：报失败"
assert_equals '{"old":1}|no|no|0' "$(cat "${CA_F}/chain_route.json")|$([[ -f "${CA_F}/chain_outbound.json" ]] && echo yes || echo no)|$([[ -f "${CA_ENTRY}" ]] && echo yes || echo no)|$(find "${CA_ROOT}" -maxdepth 1 -name '.txn.*' | wc -l | tr -d ' ')" \
    "外部节点唯一出口（合并失败）：片段与状态还原、不留事务目录，否则此后每次合并都失败"

ca_ext_nodes
_out=$(printf '2\n' | run_ca "coreKind=2; ${_caSingle}" 2>&1)
assert_equals "rc=1" "$(tail -n 1 <<<"${_out}")" "外部节点唯一出口（旧版写坏的节点）：拒绝"
assert_contains "${_out}" "删除后重新添加" "外部节点唯一出口（旧版写坏的节点）：说清楚怎么办"
assert_equals "0|" "$(ca_chain_files)|$(cat "${CA_CALLS}")" "外部节点唯一出口（旧版写坏的节点）：不写片段、不重载"

ca_ext_nodes
jq -cn '{role: "entry", mode: "external_single", external_node_name: "good"}' >"${CA_ENTRY}"
_caProbe='chainExternalSingleOnXray && echo yes || echo no'
assert_equals "yes|no" "$(run_ca "coreKind=1; ${_caProbe}")|$(run_ca "coreKind=2; ${_caProbe}")" "旧版留下的状态：只有 Xray 内核上才算没生效"
ca_single '{}'
assert_equals "no" "$(run_ca "coreKind=1; ${_caProbe}")" "旧版留下的状态：普通单链路入口不算"

# --- 多链路测试：按每条链路自己的出站真取出口 IP；密钥错、经中继的链路不再只看出口端口 ---
ca_reset
ca_multi '{}'
for _n in us hk; do
    jq -cn --arg n "${_n}" '{outbounds: [{type: "shadowsocks", tag: $n, server: "198.51.100.1", server_port: 5001,
        password: (if $n == "us" then "right" else "wrong" end), domain_resolver: "google"}]}' >"${CA_F}/chain_outbound_${_n}.json"
done
jq -cn '{outbounds: [{type: "shadowsocks", tag: "jp-hop-1", server: "198.51.100.9", server_port: 6000, password: "right"},
    {type: "shadowsocks", tag: "jp", server: "198.51.100.3", server_port: 5003, password: "right", detour: "jp-hop-1"}]}' >"${CA_F}/chain_outbound_jp.json"
# 假 sing-box（tools fetch -c CONF -o TAG URL）：选中的出站密码对、经中继时那一跳也在、没留下引用别处 DNS 的 domain_resolver，才「取到」出口 IP
mkdir -p "${CA_ROOT}/sing-box" "${CA_ROOT}/tmp"
printf '%s\n' '#!/bin/bash' \
    'jq -e --arg t "$6" "(.outbounds[] | select(.tag == \$t)) as \$o | \$o.password == \"right\" and \$o.domain_resolver == null
        and ((\$o.detour // null) == null or any(.outbounds[]; .tag == \$o.detour)) and .route.default_domain_resolver == \"local\"" "$4" >/dev/null \
        && echo "203.0.113.$(( ${#6} ))"' >"${CA_ROOT}/sing-box/sing-box"
chmod +x "${CA_ROOT}/sing-box/sing-box"
_out=$(run_ca "export TMPDIR=${CA_ROOT}/tmp; timeout() { shift; \"\$@\"; }; date() { echo 1000000000; }; testMultiChainConnection" 2>&1)
assert_contains "${_out}" "✅ us (198.51.100.1:5001) - 经链路取到出口 IP 203.0.113.2" "多链路测试：经链路取到出口 IP 才报 ✅，显示出口 IP"
assert_contains "${_out}" "❌ hk" "多链路测试：密钥不对的链路报 ❌（出口端口照样通，以前报 ✅）"
assert_contains "${_out}" "✅ jp" "多链路测试：经中继的链路带着中继那一跳一起拨"
assert_contains "${_out}" "2 通过, 1 失败" "多链路测试：汇总按真连结果算"
assert_equals "" "$(ls -A "${CA_ROOT}/tmp")" "多链路测试：带密钥的临时配置用完即删"
rm -f "${CA_ROOT}/sing-box/sing-box"

# --- 出口更新密钥：先确认，答 n 什么都不动 ---
ca_reset
jq -cn '{role: "exit", ip: "198.51.100.8", port: 5000, method: "2022-blake3-aes-128-gcm", password: "old"}' >"${CA_ROOT}/sing-box/conf/chain_exit_info.json"
jq -cn '{inbounds: [{type: "shadowsocks", tag: "chain_inbound", password: "old"}]}' >"${CA_F}/chain_inbound.json"
_out=$(printf 'n\n' | run_ca 'updateChainKey; echo rc=$?' 2>&1)
assert_contains "${_out}" "会全部断开" "更新密钥：先说明接在上面的入口会断"
assert_equals "rc=0|old|old|" "$(grep -o 'rc=[0-9]' <<<"${_out}")|$(jq -r '.inbounds[0].password' "${CA_F}/chain_inbound.json")|$(jq -r '.password' "${CA_ROOT}/sing-box/conf/chain_exit_info.json")|$(cat "${CA_CALLS}")" \
    "更新密钥（答 n）：入站与状态里的密钥都不动，不合并不重载"
printf 'y\n' | run_ca 'generateChainKey() { echo newkey; }; updateChainKey' >/dev/null 2>&1
assert_equals "newkey|newkey|merge reloadCore" "$(jq -r '.inbounds[0].password' "${CA_F}/chain_inbound.json")|$(jq -r '.password' "${CA_ROOT}/sing-box/conf/chain_exit_info.json")|$(paste -sd ' ' - <"${CA_CALLS}")" \
    "更新密钥（答 y）：换掉并生效"

# --- 卸载链式：出口 / 中继机按角色说明，不说成单链路模式 ---
_caRemove=$(sed -n '/^removeChainProxy() {/,/^}/p' install.sh)
ca_reset
printf '%s\n' '{"role":"exit"}' >"${CA_ROOT}/sing-box/conf/chain_exit_info.json"
_out=$(printf 'n\n' | run_ca "${_caRemove}"$'\n''removeChainProxy' 2>&1)
assert_contains "${_out}" "出口节点" "卸载链式（出口机）：说本机是出口"
assert_equals "0" "$(grep -c '单链路' <<<"${_out}")" "卸载链式（出口机）：不说成单链路模式"
printf '%s\n' '{"role":"relay"}' >"${CA_ROOT}/sing-box/conf/chain_relay_info.json"
assert_contains "$(printf 'n\n' | run_ca "${_caRemove}"$'\n''removeChainProxy' 2>&1)" "中继节点" "卸载链式（中继机，留着旧的出口状态）：按中继说"

# --- 多链路状态在时，单链路 / 多跳入口拒绝（否则留下两套入口状态） ---
# 两个函数里的 heredoc 有顶格的 }，按下一个函数的开头截取
_caEntrySetup=$(awk '/^(setupChainEntry|setupChainEntryMultiHop)\(\) \{/{f=1; print; next} f && /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/{f=0} f' install.sh)
ca_reset
ca_multi '{}'
_out=$(run_ca "${_caEntrySetup}"$'\n''ensureSingBoxInstalled() { echo ensure >>"${CA_CALLS}"; }; setupChainEntry 198.51.100.9 5000 k m; echo rc=$?; setupChainEntryMultiHop; echo rc=$?' 2>&1)
assert_equals "rc=1 rc=1" "$(grep -o 'rc=[0-9]' <<<"${_out}" | paste -sd ' ' -)" "单链路入口（已有多链路）：单跳与多跳都拒绝"
assert_contains "${_out}" "请先卸载现有的多链路配置" "单链路入口（已有多链路）：说明要先卸载多链路"
assert_equals "|no|no" "$(cat "${CA_CALLS}")|$([[ -f "${CA_F}/chain_outbound.json" ]] && echo yes || echo no)|$([[ -f "${CA_ENTRY}" ]] && echo yes || echo no)" \
    "单链路入口（已有多链路）：不装 sing-box、不写出站片段与单链路状态"

# --- 菜单 ---
ca_reset
_out=$(run_ca 'chainAccountExitMenu; echo rc=$?' 2>&1 </dev/null)
assert_contains "${_out}" "rc=1" "菜单（不是入口）：返回 1"
ca_single '{}'
jq -n '{inbounds: [{tag: "a"}, {settings: {clients: [{email: "bob-vless_reality_vision"}, {email: "alice-vless_reality_vision"}]}}]}' >"${CA_X}/07_VLESS_vision_reality_inbounds.json"
jq -n '{inbounds: [{users: [{name: "carol-singbox_hysteria2"}]}]}' >"${CA_F}/06_hysteria2_inbounds.json"
_out=$(printf '1\n2\n' | run_ca 'chainAccountExitMenu; echo rc=$?' 2>&1)
assert_contains "${_out}" "没接进链路" "菜单（装了 Xray 协议、Xray 侧没接进链路）：拒绝，说明映射对 Xray 账号不起作用"
assert_equals "rc=1|null" "$(grep -o 'rc=[0-9]' <<<"${_out}")|$(jq -r '.accounts.alice' "${CA_ENTRY}")" "菜单（Xray 侧没接上）：不写映射"
printf '%s\n' '{"outbounds":[]}' >"${CA_X}/chain_outbound.json"
assert_equals "alice bob carol" "$(run_ca 'chainAccountAllNames' 2>/dev/null | paste -sd ' ' -)" "菜单：账号列表合并 Xray 与 sing-box 两边、去掉协议后缀"
printf '1\n2\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "direct|merge reloadCore" "$(jq -r '.accounts.alice' "${CA_ENTRY}")|$(paste -sd ' ' - <"${CA_CALLS}")" "菜单：alice → 直连，写入后合并并重载"
assert_equals "chain_direct" "$(ca_chain_rules '[.routing.rules[] | select(.user)][0].outboundTag' | jq -r .)" "菜单：Xray 路由随之有了 alice 的直连规则"
assert_equals "yes" "$([[ -f "${CA_F}/01_direct_outbound.json" ]] && echo yes)" "菜单：sing-box 里补上 direct 出站（旁挂的 6 / 9 指定直连要用）"
printf '0\n2\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "direct|chain_direct" "$(jq -r '.default_chain' "${CA_ENTRY}")|$(ca_chain_rules '.routing.rules[-1].outboundTag' | jq -r .)" "菜单：默认出口改成直连，Xray 兜底随之直连"
printf '1\n1\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "false" "$(jq '(.accounts // {}) | has("alice")' "${CA_ENTRY}")" "菜单：alice 改回跟随默认"
_caBefore=$(cat "${CA_ENTRY}")
_out=$(printf '2\n2\n' | CA_MERGE_RC=1 run_ca 'chainAccountExitMenu; echo rc=$?' 2>&1)
assert_contains "${_out}" "改回原样" "菜单（合并失败）：提示没生效"
assert_equals "${_caBefore}" "$(cat "${CA_ENTRY}")" "菜单（合并失败）：状态写回原样"
cat >"${CA_ROOT}/xray/xray" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "help run") echo "  -test" ;;
    "run -test") echo xraytest >>"${CA_CALLS}"
        if [[ "${XRAY_TEST_FAIL}" == once && "$(grep -c xraytest "${CA_CALLS}")" == 1 ]]; then echo "unknown outbound tag"; exit 1; fi ;;
esac
EOF
chmod +x "${CA_ROOT}/xray/xray"
: >"${CA_CALLS}"
_caRules=$(ca_chain_rules '.')
_out=$(printf '2\n2\n' | XRAY_TEST_FAIL=once run_ca 'chainAccountExitMenu; echo rc=$?' 2>&1)
assert_contains "${_out}" "unknown outbound tag" "菜单（Xray -test 不过）：打出 -test 的原因"
assert_contains "${_out}" "改回原样" "菜单（Xray -test 不过）：提示没生效"
assert_equals "${_caBefore}|${_caRules}" "$(cat "${CA_ENTRY}")|$(ca_chain_rules '.')" "菜单（Xray -test 不过）：状态与 Xray 路由都写回原样"
assert_equals "xraytest xraytest merge reloadCore" "$(paste -sd ' ' - <"${CA_CALLS}")" \
    "菜单（Xray -test 不过）：坏配置不合并不重载，写回的旧配置过了 -test 才重载"
: >"${CA_CALLS}"
printf '2\n2\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "direct|xraytest merge reloadCore" "$(jq -r '.accounts.bob' "${CA_ENTRY}")|$(paste -sd ' ' - <"${CA_CALLS}")" \
    "菜单（装了 Xray）：先 -test 再合并、重载"
rm -f "${CA_ROOT}/xray/xray"
assert_contains "$(printf '9\n' | run_ca 'chainAccountExitMenu; echo rc=$?' 2>&1)" "rc=1" "菜单：越界的编号拒绝"
ca_single '{"protocol_routing": {"enabled": true}}'
assert_contains "$(printf '9\n' | run_ca 'chainAccountExitMenu' 2>&1)" "已开启按协议分流" "菜单（开着按协议分流）：说明没指定的账号只有选中的协议走链路"
rm -f "${CA_ENTRY}"
ca_multi '{}'
printf '1\n4\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "hk" "$(jq -r '.accounts.alice' "${CA_MULTI}")" "菜单（多链路）：出口列表是 跟随默认 / 直连 / 各条链路，第 4 项是 hk"
printf '2\n5\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "jp|31113|chain_proxy_jp:31113" "$(jq -r '.accounts.bob' "${CA_MULTI}")|$(jq -r '.chains[2].bridge_port' "${CA_MULTI}")|$(jq -r '.outbounds[] | select(.tag == "chain_proxy_jp") | "\(.tag):\(.settings.servers[0].port)"' "${CA_X}/chain_outbound.json")" \
    "菜单（多链路）：bob → jp，给 jp 分最小的空桥端口并写进 Xray 出站"
: >"${CA_CALLS}"
printf '0\n' | run_ca 'chainAccountExitMenu' >/dev/null 2>&1
assert_equals "setDefaultChain" "$(cat "${CA_CALLS}")" "菜单（多链路）：改默认出口交给 setDefaultChain"
_out=$(printf '9\n' | run_ca 'chainAccountExitMenu' 2>&1)
assert_contains "${_out}" "先按多链路的分流规则走" "菜单（多链路）：没指定出口的账号先按分流规则走，不说成直接走默认出口"
mkdir -p "${CA_ROOT}/carpool"
jq -cn '{enabled: true, members: {zoe: {status: "disabled", reason: "expired"}, alice: {status: "active"}}}' >"${CA_ROOT}/carpool/state.json"
assert_contains "$(printf '9\n' | run_ca 'source lib/carpool.sh; chainAccountExitMenu' 2>&1)" "zoe → " "菜单（拼车开着）：停用中的成员不在入站里也列出来，恢复前就能先指定出口"
jq '.enabled = false' "${CA_ROOT}/carpool/state.json" >"${CA_ROOT}/carpool/s.t" && mv "${CA_ROOT}/carpool/s.t" "${CA_ROOT}/carpool/state.json"
assert_equals "0" "$(printf '9\n' | run_ca 'source lib/carpool.sh; chainAccountExitMenu' 2>&1 | grep -c 'zoe')" "菜单（拼车关着）：不列拼车状态里的名字"

# --- 代理用户连不到本机与内网：Xray 启动前补规则、sing-box 合并时注入 ---
ca_reset
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals "0" "$?" "本机封锁（Xray，没有路由文件、没开拼车）：返回 0"
assert_equals '[["local-block-port","31111-31210"],["local-block-ip",true]]' "$(ca_rules '[.routing.rules[] | [.ruleTag, (.port // (.ip | index("127.0.0.0/8") != null))]]')" \
    "本机封锁（Xray）：没有 09_routing.json 时新建，桥端口段按端口封、回环在 IP 清单里"
assert_equals "local_block:blackhole local_pass:freedom" "$(jq -r '[.outbounds[] | "\(.tag):\(.protocol)"] | join(" ")' "${CA_X}/local_block_tail_outbound.json")" \
    "本机封锁（Xray）：黑洞与放行两个出站的文件名带 tail（不带就会被插到最前、z_direct 不在时成了默认出站）"
printf '%s\n' '{"routing":{"domainStrategy":"AsIs","rules":[{"type":"field","domain":["example.org"],"outboundTag":"IPv6_out"}]}}' >"${CA_X}/09_routing.json"
printf '%s\n' '{"stats":{},"api":{"tag":"api","listen":"127.0.0.1:23456","services":["StatsService"]}}' >"${CA_X}/12_stats_api.json"
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals '["local-block-port","local-block-ip",null]' "$(ca_rules '[.routing.rules[].ruleTag]')" "本机封锁（Xray）：两条封锁排在原有规则前面"
assert_equals "31111-31210,23456|IPv6_out|AsIs" "$(ca_rules '"\(.routing.rules[0].port)|\(.routing.rules[2].outboundTag)|\(.routing.domainStrategy)"' | jq -r .)" \
    "本机封锁（Xray）：开着拼车时统计 API 端口也按端口封；原有规则与 domainStrategy 不动"
_caBefore=$(cat "${CA_X}/09_routing.json")
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals "${_caBefore}" "$(cat "${CA_X}/09_routing.json")" "本机封锁（Xray）：再跑一次不重复插、文件不变"
printf '%s\n' '{"stats":{},"api":{"tag":"api","listen":"127.0.0.1:24000","services":["StatsService"]}}' >"${CA_X}/12_stats_api.json"
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals "31111-31210,24000|3" "$(ca_rules '"\(.routing.rules[0].port)|\(.routing.rules | length)"' | jq -r .)" "本机封锁（Xray）：API 换了端口，旧的封锁换成新的，不留两份"
jq -n '{inbounds: [{tag: "dokodemo-in-VLESSReality", port: 443, protocol: "dokodemo-door", settings: {address: "127.0.0.1", port: 45987}}, {port: 45987, listen: "127.0.0.1", protocol: "vless"}]}' \
    >"${CA_X}/07_VLESS_vision_reality_inbounds.json"
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals '["local_pass",["dokodemo-in-VLESSReality"]]|local_block|local_block|4' "$(ca_rules '"\([.routing.rules[0].outboundTag, .routing.rules[0].inboundTag] | tojson)|\(.routing.rules[1].outboundTag)|\(.routing.rules[2].outboundTag)|\(.routing.rules | length)"' | jq -r .)" \
    "本机封锁（Xray）：dokodemo-door 入站转给 127.0.0.1 写死端口的那一跳先放行（Reality 的 443 就是这样转给 45987 的）"
assert_equals "0" "$(ca_rules '[.routing.rules[].ruleTag | select(. != null)] | length - (unique | length)')" \
    "本机封锁（Xray）：三条规则的 ruleTag 互不相同（Xray 26.9.9 起启动时查重，重复就起不来）"
jq '.routing.rules = [{type: "field", ruleTag: "local-block", port: "1-2", outboundTag: "local_block"},
    {type: "field", ruleTag: "local-block", outboundTag: "local_block", ip: ["127.0.0.0/8"]}] + .routing.rules' \
    "${CA_X}/09_routing.json" >"${CA_X}/09_routing.json.tmp" && mv "${CA_X}/09_routing.json.tmp" "${CA_X}/09_routing.json"
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals '["local-block-pass","local-block-port","local-block-ip"]|4' "$(ca_rules '"\([.routing.rules[].ruleTag | select(. != null)] | tojson)|\(.routing.rules | length)"' | jq -r .)" \
    "本机封锁（Xray）：旧版留下的同名 local-block 规则整组换成新的，不残留"
printf '%s\n' '{"routing":' >"${CA_X}/09_routing.json"
_caOut=$(run_ca 'ensureXrayLocalBlock; echo rc=$?' 2>&1)
assert_contains "${_caOut}" "rc=1" "本机封锁（Xray）：路由文件读不懂时返回 1（handleXray 随之不启动）"
assert_contains "${_caOut}" "jq 读不了 ${CA_X}/09_routing.json" "本机封锁（Xray）：点名读不懂的文件"
printf '%s\n' '{"routing":{"rules":[]}}' >"${CA_X}/09_routing.json"
printf '%s\n' '// hand-written note' '{"log":{"loglevel":"warning"}}' >"${CA_X}/00_log.json"
_caOut=$(run_ca 'ensureXrayLocalBlock; echo rc=$?' 2>&1)
assert_contains "${_caOut}" "jq 读不了 ${CA_X}/00_log.json" "本机封锁（Xray）：别的片段带注释也点名它，不赖路由文件"
assert_equals "0" "$(grep -c "jq 读不了 ${CA_X}/09_routing.json" <<<"${_caOut}")" "本机封锁（Xray）：读得懂的文件不点名"

ca_reset
printf '%s\n' '{"stats":{},"api":{"tag":"api","listen":"127.0.0.1:23456","services":["StatsService"]}}' >"${CA_X}/12_stats_api.json"
printf '%s\n' '{"route":{"rules":[{"inbound":"x","outbound":"direct"}],"final":"direct"}}' >"${CA_MERGED}"
run_ca "localBlockInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals '[{"ip_is_private":true,"action":"reject"},{"ip_cidr":["0.0.0.0/8","::ffff:0:0/96"],"action":"reject"},{"port_range":["31111:31210"],"action":"reject"},{"port":[23456],"action":"reject"},{"inbound":"x","outbound":"direct"}]' \
    "$(jq -c '.route.rules' "${CA_MERGED}")" "本机封锁（sing-box）：私网、0.0.0.0/8 与 IPv4 映射、桥端口段、统计 API 端口排在最前"
rm -f "${CA_X}/12_stats_api.json"
printf '%s\n' '{"outbounds":[{"type":"direct","tag":"direct"}]}' >"${CA_MERGED}"
run_ca "localBlockInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals "3|null" "$(jq -r '"\(.route.rules | length)|\(.route.final)"' "${CA_MERGED}")" "本机封锁（sing-box）：没开拼车就没有 API 端口那条；原来没有 route 也只加规则、不设 final"

# --- 本机网卡上的全局地址也封：发往它们的连接经 lo 送达、绕过 INPUT 防火墙。行的形状照 ip -o addr 的原样 ---
ca_reset
CA_ADDRS=$'2: eth0    inet 203.0.113.5/24 brd 203.0.113.255 scope global eth0\\       valid_lft forever preferred_lft forever\n2: eth0    inet6 2001:db8::5/64 scope global \\       valid_lft forever preferred_lft forever'
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals '["2001:db8::5","203.0.113.5"]' "$(ca_rules '.routing.rules[] | select(.ruleTag == "local-block-ip") | .ip[-2:]')" "本机地址（Xray）：v4、v6 去掉前缀长度后并进 IP 清单"
assert_equals "true" "$(ca_rules '.routing.rules[] | select(.ruleTag == "local-block-ip") | .ip | index("127.0.0.0/8") != null')" "本机地址（Xray）：原来的回环与私网照封"
CA_ADDRS='2: eth0    inet 203.0.113.9/24 scope global eth0'
run_ca 'ensureXrayLocalBlock' >/dev/null 2>&1
assert_equals "true|false|1" "$(ca_rules '[.routing.rules[] | select(.ruleTag == "local-block-ip")] | "\(.[0].ip | index("203.0.113.9") != null)|\(.[0].ip | index("203.0.113.5") != null)|\(length)"' | jq -r .)" \
    "本机地址（Xray）：地址换了，下次启动整组换成新的，不留旧的"
CA_ADDRS='2: eth0    inet 203.0.113.5/24 scope global eth0'
printf '%s\n' '{"route":{"rules":[]}}' >"${CA_MERGED}"
run_ca "localBlockInject ${CA_MERGED}" >/dev/null 2>&1
assert_equals '["0.0.0.0/8","::ffff:0:0/96","203.0.113.5"]' "$(jq -c '.route.rules[1].ip_cidr' "${CA_MERGED}")" "本机地址（sing-box）：并进 ip_cidr"
CA_ADDRS=

# --- 卸载链式、又没有路由备份：默认路由只在直连出站还在时才指向它。规则指向不存在的出站，Xray 会直接断连接 ---
run_remove_nobak() {
    ca_reset
    printf '%s\n' '{"role":"entry"}' >"${CA_ROOT}/sing-box/conf/chain_entry_info.json"
    printf '%s\n' '{"outbounds":[]}' >"${CA_X}/chain_outbound.json"
    [[ "$1" == direct ]] && printf '%s\n' '{"outbounds":[]}' >"${CA_X}/z_direct_outbound.json"
    printf 'y\n' | run_ca "${_caRemove}"$'\n''handleXray() { :; }; removeChainProxy' >/dev/null 2>&1
    jq -c '[.routing.rules[].outboundTag]' "${CA_X}/09_routing.json" 2>&1
}
assert_equals '["z_direct_outbound"]' "$(run_remove_nobak direct)" "卸载链式（没有备份）：直连出站在时默认路由指向它"
assert_equals '[]' "$(run_remove_nobak)" "卸载链式（没有备份，WARP / IPv6 全局）：直连出站不在就不写指向它的规则"

echo ""

# ============================================================================
# cron 行的卫生：installCronTLS 只换自己的行、unInstall 清掉指向本根的行、crond 真的被拉起
# ============================================================================

echo -e "${YELLOW}=== 测试 cron 行与 cron 守护进程 ===${NC}"

CRON_FNS=$(sed -n '/^installCronTLS() {/,/^}/p;/^removeOwnCronEntries() {/,/^}/p;/^ensureCronService() {/,/^}/p;/^bootStartup() {/,/^}/p' install.sh)
assert_not_empty "${CRON_FNS}" "cron：抽到四个函数原文"
CRON_FAKE_ROOT="${MOCK_ROOT}/cron.root"
mkdir -p "${CRON_FAKE_ROOT}"
CRON_TABLE="${MOCK_ROOT}/fake_crontab"

# 桩 crontab：-l 读假表（表不存在时像没有 crontab 一样失败）、- 从 stdin 写、FILE 从文件写
run_cron_fn() (
    env PROXY_AGENT_DIR="${CRON_FAKE_ROOT}" CRON_FNS="${CRON_FNS}" CRON_TABLE="${CRON_TABLE}" bash -c '
        source lib/constants.sh
        eval "${CRON_FNS}"
        crontab() { case "$1" in -l) cat "${CRON_TABLE}" 2>/dev/null ;; -) cat >"${CRON_TABLE}" ;; *) cat "$1" >"${CRON_TABLE}" ;; esac; }
        echoContent() { :; }; t() { echo "$1"; }
        btDomain=; totalProgress=1
        "$1"' _ "$1" >/dev/null 2>&1
)

printf '%s\n' "0 0 * * * /usr/local/bin/backup.sh" \
    "35 1 * * * PROXY_AGENT_DIR=${CRON_FAKE_ROOT} /bin/bash ${CRON_FAKE_ROOT}/install.sh UpdateGeo >> ${CRON_FAKE_ROOT}/crontab_tls.log 2>&1" \
    "30 1 * * * /bin/bash ${CRON_FAKE_ROOT}/install.sh RenewTLS >> ${CRON_FAKE_ROOT}/crontab_tls.log 2>&1" \
    '0 2 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null' \
    "0 3 * * * /bin/bash /etc/v2ray-agent/install.sh RenewTLS" >"${CRON_TABLE}"
run_cron_fn installCronTLS
assert_equals "1" "$(grep -c 'backup.sh' "${CRON_TABLE}")" "installCronTLS：无关的用户行原样保留"
assert_equals "1" "$(grep -c 'install.sh UpdateGeo' "${CRON_TABLE}")" "installCronTLS：UpdateGeo 行不再被一起抹掉"
assert_equals "0" "$(grep -c -e 'acme.sh' -e 'v2ray-agent' "${CRON_TABLE}")" "installCronTLS：acme.sh 与 v2ray-agent 的遗留行删掉"
assert_equals "30 1 * * * PROXY_AGENT_DIR=${CRON_FAKE_ROOT} /bin/bash ${CRON_FAKE_ROOT}/install.sh RenewTLS >> ${CRON_FAKE_ROOT}/crontab_tls.log 2>&1" \
    "$(grep 'install.sh RenewTLS' "${CRON_TABLE}")" "installCronTLS：旧格式的 RenewTLS 行换成唯一一条带安装根前缀的新行"
run_cron_fn installCronTLS
assert_equals "1" "$(grep -c 'install.sh RenewTLS' "${CRON_TABLE}")" "installCronTLS：再跑一次仍只有一条 RenewTLS"
assert_equals "3" "$(grep -c . "${CRON_TABLE}")" "installCronTLS：两次之后表里恰好三行"

printf '%s\n' "0 0 * * * /usr/local/bin/backup.sh" \
    "35 1 * * * PROXY_AGENT_DIR=${CRON_FAKE_ROOT} /bin/bash ${CRON_FAKE_ROOT}/install.sh UpdateGeo" \
    "30 1 * * * /bin/bash ${CRON_FAKE_ROOT}/install.sh RenewTLS" \
    "30 1 * * * /bin/bash /opt/other-root/install.sh RenewTLS" >"${CRON_TABLE}"
run_cron_fn removeOwnCronEntries
assert_equals "$(printf '%s\n' '0 0 * * * /usr/local/bin/backup.sh' '30 1 * * * /bin/bash /opt/other-root/install.sh RenewTLS')" \
    "$(cat "${CRON_TABLE}")" "removeOwnCronEntries：只删指向本根 install.sh 的行，用户行与别的根保留"
rm -f "${CRON_TABLE}"
run_cron_fn removeOwnCronEntries
assert_equals "no" "$([[ -e "${CRON_TABLE}" ]] && echo yes || echo no)" "removeOwnCronEntries：本来没有 crontab 时不会凭空建一张"

# 桩服务管理器：记录每次调用；守护进程是否在跑由 $2 决定，其余子命令一律成功
run_cron_service() (
    env CRON_FNS="${CRON_FNS}" CRON_CALLS="${MOCK_ROOT}/cron.calls" bash -c '
        eval "${CRON_FNS}"
        echoContent() { :; }; t() { echo "$1"; }
        release="$1"; CRON_STATE="$2"
        : >"${CRON_CALLS}"
        systemctl() { echo "systemctl $*" >>"${CRON_CALLS}"; if [[ "$1" == "is-active" ]]; then [[ "${CRON_STATE}" == "running" ]]; fi; }
        rc-service() { echo "rc-service $*" >>"${CRON_CALLS}"; if [[ "$2" == "status" ]]; then [[ "${CRON_STATE}" == "running" ]]; fi; }
        rc-update() { echo "rc-update $*" >>"${CRON_CALLS}"; }
        ensureCronService
        echo "rc=$?"
        cat "${CRON_CALLS}"' _ "$1" "$2"
)
assert_equals "$(printf '%s\n' 'rc=0' 'systemctl is-active --quiet cron')" "$(run_cron_service debian running)" "ensureCronService：Debian 上 cron 已在跑时只探测不动"
assert_contains "$(run_cron_service debian stopped)" "systemctl enable cron" "ensureCronService：Debian 上 cron 没跑时 enable"
assert_contains "$(run_cron_service debian stopped)" "systemctl start cron" "ensureCronService：Debian 上 cron 没跑时 start"
assert_contains "$(run_cron_service centos stopped)" "systemctl start crond" "ensureCronService：RHEL 系的服务名是 crond"
assert_equals "$(printf '%s\n' 'rc=0' 'rc-service crond status' 'rc-update add crond default' 'rc-service crond start')" \
    "$(run_cron_service alpine stopped)" "ensureCronService：Alpine 上 crond 没跑时 rc-update add + rc-service start"
assert_equals "$(printf '%s\n' 'rc=0' 'rc-service crond status')" "$(run_cron_service alpine running)" "ensureCronService：Alpine 上 crond 在跑时不动"

# 装完 crontab 包就得确保守护进程在跑，而不是只在刚装包时
INSTALL_TOOLS_FN=$(sed -n '/^installTools() {/,/^}/p' install.sh)
INSTALL_BASE_TOOLS_FN=$(sed -n '/^installBaseTools() {/,/^}/p' install.sh)
assert_equals "1" "$(grep -c '^    installBaseTools$' <<<"${INSTALL_TOOLS_FN}")" "installTools：无条件先过 installBaseTools"
assert_equals "1" "$(grep -c '^    ensureCronService$' <<<"${INSTALL_BASE_TOOLS_FN}")" "installBaseTools：无条件调用 ensureCronService（Alpine 自带 crontab、不会走装包分支）"
UNINSTALL_FN=$(sed -n '/^unInstall() {/,/^}/p' install.sh)
assert_equals "yes" "$(grep -n -E 'removeOwnCronEntries|rm -rf \$\{PROXY_AGENT_DIR\}$' <<<"${UNINSTALL_FN}" | head -1 | grep -q removeOwnCronEntries && echo yes || echo no)" \
    "unInstall：先清 cron 行再 rm -rf 安装根"
assert_equals "removeProtocolPortHopping removeProtocolPortHopping removeOwnFirewallRules rm" "$(grep -oE 'removeProtocolPortHopping|removeOwnFirewallRules|rm -rf \$\{PROXY_AGENT_DIR\}$' <<<"${UNINSTALL_FN}" | cut -d' ' -f1 | paste -sd' ' -)" \
    "unInstall：跳跃规则与放行都在 rm -rf 安装根之前收（firewalld 要读片段里的目标端口）"
rm -rf "${CRON_FAKE_ROOT}" "${MOCK_ROOT}/cron.calls"

echo ""

# ============================================================================
# updateRemoteSubscribe 的三次远程拉取都要带超时：它被 cron 里的订阅重建调到，无超时的 curl 会把任务挂死
# ============================================================================

echo -e "${YELLOW}=== 测试 updateRemoteSubscribe 的 curl 超时 ===${NC}"

REMOTE_SUB_FN=$(sed -n '/^updateRemoteSubscribe() {/,/^}/p' install.sh)
assert_not_empty "${REMOTE_SUB_FN}" "updateRemoteSubscribe：抽到函数原文"
REMOTE_SUB_CURLS=$(grep -c 'curl ' <<<"${REMOTE_SUB_FN}")
assert_equals "3" "${REMOTE_SUB_CURLS}" "updateRemoteSubscribe：三种订阅格式各拉一次"
assert_equals "${REMOTE_SUB_CURLS}" "$(grep 'curl ' <<<"${REMOTE_SUB_FN}" | grep -c -e '--connect-timeout [0-9]' )" "updateRemoteSubscribe：每次 curl 都带 --connect-timeout"
assert_equals "${REMOTE_SUB_CURLS}" "$(grep 'curl ' <<<"${REMOTE_SUB_FN}" | grep -c -E -e '(-m|--max-time) [0-9]+')" "updateRemoteSubscribe：每次 curl 都带总超时 -m"

echo ""

# ============================================================================
# 测试：updateGeoSite 的失败语义——下载失败要返回 1，旧 geo 文件不能先被删掉
# ============================================================================

echo -e "${YELLOW}=== 测试 updateGeoSite 失败语义 ===${NC}"

GEO_FN=$(sed -n '/^fetchGeoFiles() {/,/^}/p;/^updateGeoSite() {/,/^}/p' install.sh)
assert_not_empty "${GEO_FN}" "updateGeoSite：抽到函数原文"
GEO_DIR="${MOCK_ROOT}/geo/xray/"
mkdir -p "${GEO_DIR}conf"

# 子 shell 里跑：桩掉 curl、wget 与内核重载。ok = 写 -O 目标，empty = 成功但文件是空的，别的 = 下载失败；记下 wget 取的地址与 curl 有没有被调
run_update_geo() (
    configPath="${GEO_DIR}conf/"
    release="debian"; wgetShowProgressStatus=""
    GEO_WGET_MODE="$1"
    [[ "${2:-}" == "mv-fail" ]] && mv() { return 1; }
    curl() { : >"${GEO_DIR}curl-called"; }
    wget() {
        local out=""
        printf '%s\n' "${*: -1}" >>"${GEO_DIR}wget-urls"
        while [[ $# -gt 0 ]]; do [[ "$1" == "-O" ]] && out="$2"; shift; done
        case "${GEO_WGET_MODE}" in
            ok) printf 'new' >"${out}" ;;
            empty) : >"${out}" ;;
            *) return 8 ;;
        esac
    }
    reloadCore() { : >"${GEO_DIR}reloaded"; }
    echoContent() { printf '%s\n' "$2"; }
    t() { printf '%s' "$1"; }
    eval "${GEO_FN}"
    updateGeoSite >/dev/null 2>&1
)
geo_files() { printf '%s %s' "$(cat "${GEO_DIR}geosite.dat" 2>/dev/null)" "$(cat "${GEO_DIR}geoip.dat" 2>/dev/null)"; }
geo_staging_left() { find "${GEO_DIR}" -maxdepth 1 -name 'geo-update.*' | wc -l | tr -d ' '; }

printf 'old' >"${GEO_DIR}geosite.dat"; printf 'old' >"${GEO_DIR}geoip.dat"
run_update_geo fail
assert_equals "1" "$?" "updateGeoSite：下载失败返回 1"
assert_equals "old old" "$(geo_files)" "updateGeoSite：下载失败时旧 geo 文件原样保留"
assert_equals "0" "$(geo_staging_left)" "updateGeoSite：下载失败不留暂存目录"

run_update_geo empty
assert_equals "1" "$?" "updateGeoSite：下到空文件算失败"
assert_equals "old old" "$(geo_files)" "updateGeoSite：下到空文件时旧 geo 文件原样保留"

# 发布失败：mv 整体失败（一个都没换），以及 geoip.dat 被同名目录占着（只换掉 geosite）
rm -f "${GEO_DIR}reloaded"
run_update_geo ok mv-fail
assert_equals "1" "$?" "updateGeoSite：新文件挪不进去时返回 1"
assert_equals "old old" "$(geo_files)" "updateGeoSite：挪不进去时旧 geo 文件原样保留"
assert_equals "0" "$(geo_staging_left)" "updateGeoSite：挪不进去也不留暂存目录"
rm -f "${GEO_DIR}geoip.dat" && mkdir "${GEO_DIR}geoip.dat"
run_update_geo ok
assert_equals "1" "$?" "updateGeoSite：只发布了一部分也返回 1"
assert_equals "no" "$([[ -e "${GEO_DIR}reloaded" ]] && echo yes || echo no)" "updateGeoSite：发布失败不重载内核"
rmdir "${GEO_DIR}geoip.dat"

rm -f "${GEO_DIR}wget-urls" "${GEO_DIR}curl-called"
run_update_geo ok
assert_equals "0" "$?" "updateGeoSite：两个文件都下到后返回 0"
assert_equals "yes" "$([[ -e "${GEO_DIR}reloaded" ]] && echo yes || echo no)" "updateGeoSite：发布成功后重载内核"
assert_equals "new new" "$(geo_files)" "updateGeoSite：两个文件都换成了新的"
assert_equals "no" "$([[ -e "${GEO_DIR}curl-called" ]] && echo yes || echo no)" "updateGeoSite：不查 GitHub API（未认证额度按出口 IP 算，用完就取不到版本号）"
assert_equals "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat|https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
    "$(paste -sd'|' - <"${GEO_DIR}wget-urls")" "updateGeoSite：走 releases/latest/download 的固定地址"

# installXray：默认配置不读 geo，下载失败不中止安装（服务这时已停），但要说出来
IX_FN=$(sed -n '/^fetchGeoFiles() {/,/^}/p;/^installXray() {/,/^}/p' install.sh)
IX_DIR="${MOCK_ROOT}/installxray/xray"
# run_ix GEO_MODE → 新装 Xray：桩掉版本解析、下载、解压；GEO_MODE 是 ok 或 fail，打印输出与退出码
run_ix() {
    mkdir -p "${IX_DIR}"
    find "${IX_DIR}" -type f -delete
    printf 'old' >"${IX_DIR}/geosite.dat"
    env IX_FN="${IX_FN}" IX_DIR="${IX_DIR}" GEO_MODE="$1" bash -c '
        eval "${IX_FN}"
        XRAY_DIR="${IX_DIR}" XRAY_BIN="${IX_DIR}/xray" release=debian xrayCoreCPUVendor=Xray-linux-64 wgetShowProgressStatus= totalProgress=1
        readInstallType() { :; }
        resolveXrayVersion() { echo v26.3.27; }
        extractXrayHash() { :; }
        echoContent() { echo "$2"; }
        t() { echo "$1"; }
        curl() { echo curl-called; }
        unzip() { : >"${XRAY_BIN}"; }
        wget() {
            local out= dir= url="${*: -1}"
            while [[ $# -gt 0 ]]; do
                [[ "$1" == "-O" ]] && out="$2"
                [[ "$1" == "-P" ]] && dir="$2"
                shift
            done
            case "${url}" in
                *.dat) [[ "${GEO_MODE}" == ok ]] || return 8; printf new >"${out}" ;;
                *) : >"${dir}/${url##*/}" ;;
            esac
        }
        installXray 1 false
        echo "rc=$?"' 2>&1
}
ixOut=$(run_ix ok)
assert_contains "${ixOut}" "rc=0" "installXray：geo 下到时安装成功"
assert_equals "new new" "$(cat "${IX_DIR}/geosite.dat" "${IX_DIR}/geoip.dat" | fold -w 3 | paste -sd' ' -)" "installXray：两个 geo 文件都就位"
assert_equals "no" "$(grep -q 'GEO_INSTALL_SKIPPED\|curl-called' <<<"${ixOut}" && echo yes || echo no)" "installXray：geo 下到时不告警，也不查 GitHub API"
ixOut=$(run_ix fail)
assert_contains "${ixOut}" "rc=0" "installXray：geo 下载失败不中止安装"
assert_contains "${ixOut}" "GEO_DOWNLOAD_FAILED" "installXray：geo 下载失败报出是哪个文件"
assert_contains "${ixOut}" "GEO_INSTALL_SKIPPED" "installXray：geo 下载失败说明后果与补救"
assert_equals "yes old" "$([[ -f "${IX_DIR}/xray" ]] && echo yes || echo no) $(cat "${IX_DIR}/geosite.dat")" "installXray：geo 下载失败时内核照常就位，已有的 geo 不动"
assert_equals "0" "$(find "${IX_DIR}" -maxdepth 1 -name 'geo-update.*' | wc -l | tr -d ' ')" "installXray：geo 下载失败不留暂存目录"
assert_equals "new new" "$(geo_files)" "updateGeoSite：成功后两个 geo 文件都换成新版"
assert_equals "0" "$(geo_staging_left)" "updateGeoSite：成功后不留暂存目录"

echo ""

# ============================================================================
# 测试：releaseAssetSHA256——sing-box 不发校验和文件，安装只靠 releases 响应里资产的 digest
# ============================================================================

echo -e "${YELLOW}=== 测试 readValidPort ===${NC}"

PORT_FN=$(sed -n '/^readValidPort() {/,/^}/p' install.sh)
assert_not_empty "${PORT_FN}" "readValidPort：抽到函数原文"
# 子 shell 里跑：$1 是喂给 read 的输入，其余原样传给 readValidPort；成功打印端口，失败打印 rc=1
run_read_port() (
    echoContent() { :; }
    t() { :; }
    randomNum() { echo "rand:$1-$2"; }
    eval "${PORT_FN}"
    local input="$1" got=
    shift
    if readValidPort "" got "$@" <<<"${input}"; then echo "${got}"; else echo "rc=1"; fi
)
assert_equals "443" "$(run_read_port 443 RANDOM 10000 60000)" "readValidPort：随机区间外的合法端口照收（sing-box Reality 要能选 443）"
assert_equals "rand:10000-60000" "$(run_read_port '' RANDOM 10000 60000)" "readValidPort：回车在给定区间里随机"
assert_equals "443" "$(run_read_port '' 443)" "readValidPort：回车取默认值"
assert_equals "65535" "$(run_read_port 65535 RANDOM 10000 30000)" "readValidPort：65535 合法"
assert_equals "rc=1" "$(run_read_port 65536 RANDOM 10000 30000)" "readValidPort：超过 65535 拒绝"
assert_equals "rc=1" "$(run_read_port 18446744073709551616 RANDOM 10000 30000)" "readValidPort：超长数字不靠算术溢出混过去"
assert_equals "rc=1" "$(run_read_port 0443 443)" "readValidPort：前导 0 拒绝"
assert_equals "rc=1" "$(run_read_port 44a 443)" "readValidPort：非数字拒绝"
assert_equals "rc=1" "$(run_read_port '')" "readValidPort：空输入且无默认值拒绝"

echo ""

echo -e "${YELLOW}=== 测试 customPortFunction ===${NC}"

CUSTOM_PORT_FN=$(sed -n '/^customPortFunction() {/,/^}/p;/^isYesInput() {/,/^}/p' install.sh lib/utils.sh)
assert_not_empty "${CUSTOM_PORT_FN}" "customPortFunction：抽到函数原文"
PICK_PORT_FNS=$(sed -n '/^configuredPorts() {/,/^}/p;/^portsTakenFor() {/,/^}/p;/^pickInboundPort() {/,/^}/p' install.sh)
assert_not_empty "${PICK_PORT_FNS}" "端口选择：抽到 configuredPorts / portsTakenFor / pickInboundPort 原文"
# 子 shell 里跑：$1 currentPort，$2 lastInstallationConfig，$3 喂给 read 的输入；打印最终的 port
run_custom_port() (
    echoContent() { :; }
    allowPort() { :; }
    checkDNSIP() { :; }
    removeNginxDefaultConf() { :; }
    checkPortOpen() { :; }
    handleXray() { :; }
    t() { printf '%s' "$1"; }
    eval "${PORT_FN}"
    eval "${PICK_PORT_FNS}"
    listeningPorts() { :; }
    subscribeConfPort() { :; }
    eval "${CUSTOM_PORT_FN}"
    currentPort="$1" lastInstallationConfig="$2" customPort= btDomain= port=
    customPortFunction <<<"$3" >/dev/null
    echo "${port}"
)
assert_equals "8443" "$(run_custom_port 8443 '' y)" "customPortFunction：答 y 沿用上次端口"
assert_equals "8443" "$(run_custom_port 8443 '' Y)" "customPortFunction：答 Y 也算沿用"
assert_equals "443" "$(run_custom_port 8443 '' $'\n')" "customPortFunction：直接回车不沿用，接着问端口（回车取 443），port 不会留空"
assert_equals "2053" "$(run_custom_port 8443 '' $'n\n2053')" "customPortFunction：答 n 后输入新端口"
assert_equals "8443" "$(run_custom_port 8443 true '')" "customPortFunction：沿用上次配置时不问、直接用上次端口"
assert_equals "443" "$(run_custom_port '' '' $'\n')" "customPortFunction：首装直接问端口"

echo ""

echo -e "${YELLOW}=== 测试 端口池与查重 ===${NC}"

PP_FNS="${PORT_FN}
${PICK_PORT_FNS}
${CUSTOM_PORT_FN}
$(awk 'f && /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/ {exit} /^writeHttpRedirectNginxConf\(\) \{/ {f=1} f' install.sh)"
PP_ROOT="${MOCK_ROOT}/portpool"
# pp_run CODE → 在安装根指向 PP_ROOT 的干净 bash 里跑抽出的原文；LIVE_TCP / LIVE_UDP 是桩掉的本机监听
pp_run() {
    env PROXY_AGENT_DIR="${PP_ROOT}" PP_FNS="${PP_FNS}" LIVE_TCP="${LIVE_TCP:-}" LIVE_UDP="${LIVE_UDP:-}" bash -c '
        source lib/constants.sh; source lib/utils.sh; source lib/protocol-registry.sh
        eval "${PP_FNS}"
        listeningPorts() { if [[ "$1" == "tcp" ]]; then printf "%s\n" ${LIVE_TCP}; else printf "%s\n" ${LIVE_UDP}; fi; }
        t() { printf "%s" "$1"; }
        echoContent() { :; }
        allowPort() { :; }
        checkDNSIP() { :; }; removeNginxDefaultConf() { :; }; checkPortOpen() { :; }; handleXray() { :; }
        nginxConfigPath="${PROXY_AGENT_DIR}/nginx/"
        '"$1" 2>/dev/null
}
pp_reset() {
    rm -rf "${PP_ROOT}"
    mkdir -p "${PP_ROOT}/xray/conf" "${PP_ROOT}/sing-box/conf/config" "${PP_ROOT}/nginx"
}
pp_xray() { printf '%s\n' "$2" >"${PP_ROOT}/xray/conf/$1"; }
pp_sb() { printf '%s\n' "$2" >"${PP_ROOT}/sing-box/conf/config/$1"; }
PP_XRAY_PICK='pickInboundPort "${ID}" "${OLD}" "${XRAY_CONF_DIR}" "${KEEP}" "${SKIP}" ${EXTRA} <<<"${IN}"'
PP_SB_PICK='pickInboundPort "${ID}" "${OLD}" "${SINGBOX_FRAGMENT_DIR}" "${KEEP}" "" <<<"${IN}"'
# pp_pick xray|sb ID OLD KEEP SKIP EXTRA INPUT → pickInboundPort 选出的端口
pp_pick() {
    local code=${PP_XRAY_PICK}
    [[ "$1" == "sb" ]] && code=${PP_SB_PICK}
    pp_run "ID='$2' OLD='$3' KEEP='$4' SKIP='$5' EXTRA='$6' IN=\$'$7'; ${code}"
}

pp_reset
assert_equals "443" "$(pp_pick xray 7 '' '' '' '' '')" "端口池：空机器回车取 443"
assert_equals "8443" "$(LIVE_TCP=443 pp_pick xray 7 '' '' '' '' '')" "端口池：443 被别的程序占着，回车取 8443"
assert_equals "2083" "$(LIVE_TCP='443 8443 2053' pp_pick xray 7 '' '' '' '' '')" "端口池：按 443 8443 2053 2083 的顺序取第一个空的"
_ppRandom=$(LIVE_TCP='443 8443 2053 2083 2087 2096' pp_pick xray 7 '' '' '' '' '')
assert_equals "yes" "$([[ ${_ppRandom:-0} -ge 10000 && ${_ppRandom:-0} -le 30000 ]] && echo yes || echo no)" "端口池：六个全被占，回车落回 10000-30000 随机（${_ppRandom}）"
_ppRandom=$(pp_pick sb 1 '' '' '' '' '')
assert_equals "yes" "$([[ ${_ppRandom:-0} -ge 10000 && ${_ppRandom:-0} -le 30000 ]] && echo yes || echo no)" "端口池：VLESS WS 不进池，空机器回车也是随机（${_ppRandom}）"
assert_equals "2053" "$(pp_pick xray 7 '' '' '' '' '2053')" "端口池：手输的空闲端口照收"
assert_equals "443" "$(LIVE_TCP=8443 pp_pick xray 7 '' '' '' '' '8443\n')" "端口池：手输撞上已占端口要重问，再回车取默认"

pp_xray 07_VLESS_vision_reality_inbounds.json '{"inbounds":[{"tag":"dokodemo-in-VLESSReality","port":443,"protocol":"dokodemo-door"},{"listen":"127.0.0.1","port":45987,"protocol":"vless"}]}'
pp_xray 04_trojan_TCP_inbounds.json '{"inbounds":[{"listen":"127.0.0.1","port":8443,"protocol":"trojan"}]}'
assert_equals "8443" "$(LIVE_TCP=443 pp_pick xray 12 '' '' '' '' '')" "查重：7 的对外端口算占用，只听回环的回落入站不算"
assert_equals "443" "$(LIVE_TCP=443 pp_pick xray 7 443 '' '' '' 'y')" "查重：自己的旧端口可沿用，旧 Xray 还占着它也不算外来占用"
assert_equals "443" "$(LIVE_TCP=443 pp_pick xray 12 '' ',12,' '' '' '')" "查重：非追加安装里没选的协议随后会被删，旧端口不算占用"
assert_equals "8443" "$(pp_pick xray 12 '' '' '' '' '')" "查重：KEEP 为空时目录里别的协议的旧端口都算占用"

pp_reset
pp_xray 02_VLESS_TCP_inbounds.json '{"inbounds":[{"port":8443,"protocol":"vless"}]}'
assert_equals "8443" "$(pp_pick xray 7 '' '' ',0,' 443 '')" "查重：0 本次选定的端口还没落盘，按 EXTRA 算占用；0 的旧文件不作数"
assert_equals "8443" "$(pp_pick xray 7 443 '' ',0,' 443 '')" "查重：7 的旧端口已被这次的 0 拿走，不再问沿用，回车取下一个"
assert_equals "2053" "$(pp_pick xray 7 2053 '' ',0,' 443 'y')" "查重：旧端口空着，答 y 沿用"
assert_equals "2053" "$(pp_run 'lastInstallationConfig=true; pickInboundPort 7 2053 "${XRAY_CONF_DIR}" "" ",0," 443 <<<""')" "查重：沿用上次配置时不问、直接用旧端口"

pp_reset
pp_sb 13_anytls_inbounds.json '{"inbounds":[{"type":"anytls","listen":"::","listen_port":443}]}'
assert_equals "8443" "$(LIVE_TCP=443 pp_pick sb 0 '' ',0,13,' '' '' '')" "sing-box：会留下的 13 在 443，0 默认取 8443"
assert_equals "443" "$(LIVE_TCP=443 pp_pick sb 0 '' ',0,' '' '' '')" "sing-box：13 这次不装、sing-box 还在跑旧配置占着 443，0 照样默认 443"
assert_equals "443" "$(pp_pick sb 6 '' '' '' '' '')" "sing-box：TCP 的 443 不挡 Hysteria2 的 443/udp"
assert_equals "8443" "$(LIVE_UDP=443 pp_pick sb 6 '' '' '' '' '')" "sing-box：443/udp 被别的程序占着，Hysteria2 默认 8443"
pp_sb 06_hysteria2_inbounds.json '{"inbounds":[{"type":"hysteria2","listen":"::","listen_port":443}]}'
assert_equals "8443" "$(pp_pick sb 9 '' '' '' '' '')" "sing-box：Hysteria2 占了 443/udp，TUIC 默认 8443"
assert_equals "8443" "$(pp_pick sb 10 '' ',6,10,' '' '' '')" "sing-box：naive 同时听 TCP 和 UDP，TCP 443 空着、UDP 443 被占也要避开"
assert_equals "443" "$(LIVE_UDP=443 pp_pick sb 6 443 '' '' '' 'y')" "sing-box：Hysteria2 沿用自己的 443/udp"
pp_sb 11_VMess_HTTPUpgrade_inbounds.json '{"inbounds":[{"type":"vmess","listen":"127.0.0.1","listen_port":31306}]}'
printf 'server {\n\tlisten 8443 so_keepalive=on ssl;http2 on;\n}\n' >"${PP_ROOT}/nginx/sing_box_VMess_HTTPUpgrade.conf"
assert_equals "2053" "$(pp_pick sb 4 '' '' '' '' '')" "sing-box：11 的对外端口在 nginx 配置里，也算占用"
assert_equals "2053" "$(LIVE_TCP=8443 pp_pick sb 4 '' '' '' '' '')" "sing-box：nginx 为 11 占着的端口不当外来占用重复算，结果不变"

pp_reset
pp_xray 07_VLESS_vision_reality_inbounds.json '{"inbounds":[{"port":443,"protocol":"dokodemo-door"}]}'
pp_cpf() { pp_run "currentPort= customPort= lastInstallationConfig= btDomain= port= selectCustomInstallType='$1'; customPortFunction <<<\$'$2' >/dev/null; echo \"\${port}\""; }
assert_equals "443" "$(LIVE_TCP=443 pp_cpf ',0,7,' '')" "customPortFunction：7 已在 443、旧 Xray 还占着它，带域名重装时 0 照样默认 443"
assert_equals "443" "$(pp_cpf '' '')" "customPortFunction：全装同样 0 优先"
assert_equals "443" "$(pp_cpf ',0,7,' '443')" "customPortFunction：手填 443 也收，7 的旧端口不挡 0"
rm -f "${PP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
assert_equals "8443" "$(LIVE_TCP=443 pp_cpf ',0,' '')" "customPortFunction：443 被别的程序占着才让到 8443"

pp_redirect() { pp_run "domain=example.com port='$1' btDomain='${2:-}'; writeHttpRedirectNginxConf; cat \"\${nginxConfigPath}http_redirect.conf\" 2>/dev/null || echo absent"; }
pp_reset
assert_contains "$(pp_redirect 443)" 'return 301 https://example.com$request_uri;' "80 跳转：0 在 443 时跳到不带端口的 https"
assert_contains "$(pp_redirect 443)" 'listen 80;' "80 跳转：监听 80"
assert_contains "$(pp_redirect 8443)" 'return 301 https://example.com:8443$request_uri;' "80 跳转：0 不在 443 时带上端口"
# 这个块常是 :80 唯一的 server：别的 Host（含不带 Host 的 HTTP/1.0）也会落进来，要先断开再谈跳转
assert_contains "$(pp_redirect 443)" $'\tif ($http_host !~* "^example\\.com(:80)?$") {\n\t\treturn 444;\n\t}\n\treturn 301' "80 跳转：只有 Host 是本域名才跳，其余 444 断开（看 \$http_host，点号转义）"
assert_equals "absent" "$(pp_redirect 443 bt.example.com)" "80 跳转：宝塔 / 1Panel 场景不写，旧文件也删掉"
assert_equals "absent" "$(LIVE_TCP=80 pp_redirect 443)" "80 跳转：80 被别的程序占着就不写"
assert_equals "absent" "$(pp_redirect 80)" "80 跳转：0 自己就在 80 上时不写"
rm -rf "${PP_ROOT}"

echo ""

echo -e "${YELLOW}=== 测试 addSingBoxDNSConfig predefined ===${NC}"

# 函数体里的 heredoc 有顶格 }，按 sed 范围抽会提前截断；抽到下一个函数定义为止
DNS_FN=$(awk 'f && /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/ {exit} /^addSingBoxDNSConfig\(\) \{/ {f=1} f' install.sh)
assert_not_empty "${DNS_FN}" "addSingBoxDNSConfig：抽到函数原文"
DNS_DIR="${MOCK_ROOT}/sbdns/"
mkdir -p "${DNS_DIR}"
# 子 shell 里跑：桩掉规则生成，只看 predefined 怎么拼
run_dns_predefined() (
    initSingBoxRules() { echo '{"domainRules":[],"ruleSet":[]}'; }
    singBoxConfigPath="${DNS_DIR}"
    eval "${DNS_FN}"
    addSingBoxDNSConfig "$1" "$2" predefined >/dev/null 2>&1
    jq -c '.dns.servers[] | select(.tag == "hosts") | .predefined' "${DNS_DIR}dns.json" 2>/dev/null || echo invalid
)
assert_equals '{"a.example":"1.2.3.4","b.example":"1.2.3.4"}' "$(run_dns_predefined 1.2.3.4 'a.example,b.example')" "addSingBoxDNSConfig：predefined 按域名映射到 IP"
assert_equals '{"x\"y":"1.2.3.4"}' "$(run_dns_predefined 1.2.3.4 'x"y')" "addSingBoxDNSConfig：域名只当数据进 jq，带引号也不会改写过滤器"
rm -rf "${DNS_DIR}"

echo ""

echo -e "${YELLOW}=== 测试 ensureAlpineProcps ===${NC}"

PROCPS_FN=$(sed -n '/^ensureAlpineProcps() {/,/^}/p' install.sh)
assert_not_empty "${PROCPS_FN}" "ensureAlpineProcps：抽到函数原文"
# 子 shell 里跑：$1 release，$2 pgrep -V 的输出；调两次，打印实际调了几次包管理器
run_procps() (
    echoContent() { :; }
    pgrep() { echo "$PGREP_OUT"; }
    PGREP_OUT="$2"
    release="$1"
    installType="record_install"
    record_install() { echo "install $*" >>"${MOCK_ROOT}/procps.calls"; }
    rm -f "${MOCK_ROOT}/procps.calls"
    eval "${PROCPS_FN}"
    ensureAlpineProcps
    ensureAlpineProcps
    grep -c . "${MOCK_ROOT}/procps.calls" 2>/dev/null || echo 0
)
assert_equals "1" "$(run_procps alpine 'pgrep: unrecognized option')" "ensureAlpineProcps：Alpine 上是 BusyBox pgrep 时装 procps，同一次运行只装一次"
assert_equals "0" "$(run_procps alpine 'pgrep from procps-ng 4.0.4')" "ensureAlpineProcps：已有 procps 时不装"
assert_equals "0" "$(run_procps debian 'pgrep: unrecognized option')" "ensureAlpineProcps：非 Alpine 不装"

echo ""

echo -e "${YELLOW}=== 测试 releaseAssetSHA256 ===${NC}"

ASSET_FN=$(sed -n '/^releaseAssetSHA256() {/,/^}/p' install.sh)
assert_not_empty "${ASSET_FN}" "releaseAssetSHA256：抽到函数原文"
eval "${ASSET_FN}"
ASSET_JSON='[
 {"tag_name":"v1.15.0-alpha.1","assets":[{"name":"sing-box-1.15.0-alpha.1-linux-arm64.tar.gz","digest":"sha256:aaaa"}]},
 {"tag_name":"v1.14.2","assets":[
   {"name":"sing-box-1.14.2-linux-arm64.tar.gz","digest":"sha256:b43a"},
   {"name":"sing-box-1.14.2-linux-arm64-musl.tar.gz","digest":"sha256:6752"},
   {"name":"sing-box-1.14.2-linux-amd64.tar.gz","digest":null},
   {"name":"sing-box-1.14.2-linux-armv7.tar.gz","digest":"sha512:ffff"}]}]'
assert_equals "6752" "$(releaseAssetSHA256 "${ASSET_JSON}" v1.14.2 sing-box-1.14.2-linux-arm64-musl.tar.gz)" "releaseAssetSHA256：按 tag 与资产名取到去掉前缀的摘要"
assert_equals "b43a" "$(releaseAssetSHA256 "${ASSET_JSON}" v1.14.2 sing-box-1.14.2-linux-arm64.tar.gz)" "releaseAssetSHA256：-musl 与无后缀是两个资产，不串"
assert_equals "" "$(releaseAssetSHA256 "${ASSET_JSON}" v1.14.2 sing-box-1.14.2-linux-amd64.tar.gz)" "releaseAssetSHA256：digest 为 null 时为空"
assert_equals "" "$(releaseAssetSHA256 "${ASSET_JSON}" v1.14.2 sing-box-1.14.2-linux-armv7.tar.gz)" "releaseAssetSHA256：非 sha256 摘要视为没有"
assert_equals "" "$(releaseAssetSHA256 "${ASSET_JSON}" v1.14.1 sing-box-1.14.2-linux-arm64.tar.gz)" "releaseAssetSHA256：tag 不符时为空"
assert_equals "" "$(releaseAssetSHA256 '' v1.14.2 sing-box-1.14.2-linux-arm64.tar.gz)" "releaseAssetSHA256：响应为空时为空"

echo ""

# ============================================================================
# 测试：出错路径的退出码——报错与失败要绑在一起（这些函数自己 exit，全部在子 shell 里跑）
# ============================================================================

echo -e "${YELLOW}=== 测试出错路径的退出码 ===${NC}"

CRON_FN=$(sed -n '/^cronFunction() {/,/^}/p' install.sh)
assert_not_empty "${CRON_FN}" "cronFunction：抽到函数原文"
CRON_ROOT="${MOCK_ROOT}/cron"; mkdir -p "${CRON_ROOT}"
# PROXY_AGENT_DIR 是 readonly，改根只能另起 bash。$1 cron 任务名，$2 桩函数的返回码；
# cronFunction 必须 exit，落到 fell-through 就是没退出
run_cron() {
    rm -f "${CRON_ROOT}/crontab_updateGeoSite.log"
    env PROXY_AGENT_DIR="${CRON_ROOT}" CRON_FN="${CRON_FN}" bash -c '
        cronName="$1"; stubRc="$2"
        renewalTLS() { return "${stubRc}"; }
        updateGeoSite() { return "${stubRc}"; }
        echoContent() { printf "%s\n" "$2"; }
        eval "${CRON_FN}"
        cronFunction
        echo fell-through' _ "$1" "$2"
}
run_cron RenewTLS 1 >/dev/null; assert_equals "1" "$?" "cronFunction RenewTLS：续期失败时退出码 1"
run_cron RenewTLS 0 >/dev/null; assert_equals "0" "$?" "cronFunction RenewTLS：续期成功时退出码 0"
run_cron UpdateGeo 1 >/dev/null; assert_equals "1" "$?" "cronFunction UpdateGeo：更新失败时退出码 1"
assert_equals "0" "$(grep -c 'geo更新日期' "${CRON_ROOT}/crontab_updateGeoSite.log")" \
    "cronFunction UpdateGeo：更新失败时日志里不写「更新日期」"
run_cron UpdateGeo 0 >/dev/null; assert_equals "0" "$?" "cronFunction UpdateGeo：更新成功时退出码 0"
assert_equals "1" "$(grep -c 'geo更新日期' "${CRON_ROOT}/crontab_updateGeoSite.log")" \
    "cronFunction UpdateGeo：更新成功时日志里写一行「更新日期」"
assert_equals "0" "$(run_cron RenewTLS 0 | grep -c fell-through)" "cronFunction：认出 cron 任务名后进程一定退出"
# Debian / RHEL 的 cron 只给任务 PATH=/usr/bin:/bin（2026-10-31 实测）；任务里要能找到 sbin 下的 nginx、rc-service
CRON_JOB_PATH=$(env -i PATH=/usr/bin:/bin PROXY_AGENT_DIR="${CRON_ROOT}" CRON_FN="${CRON_FN}" "${BASH}" -c '
    cronName=CarpoolTick
    carpoolTick() { printf "%s\n" "${PATH}" >&3; }
    carpoolTickExitTrap() { :; }
    eval "${CRON_FN}"
    cronFunction' 3>&1 >/dev/null 2>&1)
assert_contains ":${CRON_JOB_PATH}:" ":/usr/sbin:" "cron 任务在 PATH=/usr/bin:/bin 下启动，跑到任务时 PATH 含 /usr/sbin"
assert_contains ":${CRON_JOB_PATH}:" ":/sbin:" "cron 任务在 PATH=/usr/bin:/bin 下启动，跑到任务时 PATH 含 /sbin"

DNS_FN=$(sed -n '/^checkDNSIP() {/,/^}/p' install.sh)
assert_not_empty "${DNS_FN}" "checkDNSIP：抽到函数原文"
# $1 是本机公网 IP 桩值；dig 固定解析到 203.0.113.10
run_check_dns() (
    publicIpStub="$1"
    dig() { echo "203.0.113.10"; }
    getPublicIP() { echo "${publicIpStub}"; }
    echoContent() { :; }
    eval "${DNS_FN}"
    checkDNSIP example.com
)
run_check_dns 203.0.113.10; assert_equals "0" "$?" "checkDNSIP：解析 IP 与本机一致时返回 0"
run_check_dns 203.0.113.20; assert_equals "1" "$?" "checkDNSIP：解析 IP 与本机不一致时退出码 1"

DNSAPI_FN=$(sed -n '/^initDNSAPIConfig() {/,/^}/p' install.sh)
assert_not_empty "${DNSAPI_FN}" "initDNSAPIConfig：抽到函数原文"
# 域名没有点就申请不了通配符证书；凭据从 stdin 喂
run_dns_api() (
    dnsTLSDomain="localhost"
    echoContent() { :; }
    eval "${DNSAPI_FN}"
    initDNSAPIConfig "$1"
)
run_dns_api cloudflare <<<'token' >/dev/null; assert_equals "1" "$?" "initDNSAPIConfig cloudflare：域名不支持通配符时退出码 1"
run_dns_api aliyun <<<$'key\nsecret' >/dev/null; assert_equals "1" "$?" "initDNSAPIConfig aliyun：域名不支持通配符时退出码 1"

SUB_MENU_FN=$(sed -n '/^addSubscribeMenu() {/,/^}/p' install.sh)
assert_not_empty "${SUB_MENU_FN}" "addSubscribeMenu：抽到函数原文"
# 订阅清单路径从 PROXY_AGENT_DIR 派生，同样另起 bash 指到 mock 根；选「2.移除」后编号留空
run_sub_menu() {
    env PROXY_AGENT_DIR="${CRON_ROOT}" SUB_MENU_FN="${SUB_MENU_FN}" bash -c '
        source lib/constants.sh
        mkdir -p "${SUBSCRIBE_REMOTE_DIR}"
        echo "https://example.com/sub:alice" >"${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl"
        echoContent() { :; }
        subscribe() { :; }
        eval "${SUB_MENU_FN}"
        (addSubscribeMenu >/dev/null); rc=$?
        echo "rc=${rc} lines=$(grep -c . "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl")"' <<<$'2\n'
}
assert_equals "rc=1 lines=1" "$(run_sub_menu)" "addSubscribeMenu：删除时编号为空退出码 1，订阅清单没被动"

NGINX302_FN=$(sed -n '/^checkNginx302() {/,/^}/p' install.sh)
assert_not_empty "${NGINX302_FN}" "checkNginx302：抽到函数原文"
# $1 是 curl 回包桩值
run_check_302() (
    currentHost="example.com"; currentPort="443"; responseStub="$1"
    curl() { printf '%s' "${responseStub}"; }
    backupNginxConfig() { :; }
    echoContent() { :; }
    eval "${NGINX302_FN}"
    checkNginx302
)
run_check_302 "HTTP/1.1 302 Found"; assert_equals "0" "$?" "checkNginx302：看到 302 返回 0"
run_check_302 "HTTP/1.1 200 OK"; assert_equals "1" "$?" "checkNginx302：没看到 302 返回 1"

echo ""

# ============================================================================
# 测试：证书续期——按真实到期时间判窗口，按 acme.sh 证书名续与装
# ============================================================================

echo -e "${YELLOW}=== 测试 renewalTLS ===${NC}"

RENEW_FN=$(sed -n '/^renewalTLS() {/,/^}/p; /^verifyCertKeyMatch() {/,/^}/p' install.sh)
assert_not_empty "${RENEW_FN}" "renewalTLS：抽到函数原文"
RENEW_ROOT="${MOCK_ROOT}/renew"
RENEW_HOME="${RENEW_ROOT}/home"
RENEW_LOG="${RENEW_HOME}/acme-calls.log"
RENEW_CRT="${RENEW_ROOT}/tls/www.example.test.crt"
RENEW_WINDOW=$((15 * 86400))
mkdir -p "${RENEW_HOME}/.acme.sh"

# $1 目录，$2 文件名（不含扩展名），$3 有效天数：写一对 .cer / .key
renew_cert() {
    mkdir -p "$1"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days "$3" \
        -subj "/CN=renew-test" -keyout "$1/$2.key" -out "$1/$2.cer" >/dev/null 2>&1
}

# acme.sh 桩：记下参数。--renew 按 FAKE_RENEW 重签 90 天（noop 不动、fail 失败），
# --installcert 像真 acme.sh 一样只认证书名，找不到 <名>_ecc 目录就报错
cat >"${RENEW_HOME}/.acme.sh/acme.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${HOME}/acme-calls.log"
action="" name="" full="" key=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --renew) action=renew ;;
        --installcert) action=install ;;
        -d) name=$2; shift ;;
        --fullchainpath) full=$2; shift ;;
        --keypath) key=$2; shift ;;
    esac
    shift
done
dir="${HOME}/.acme.sh/${name}_ecc"
if [[ "${action}" == "renew" ]]; then
    [[ "${FAKE_RENEW}" == "fail" ]] && exit 1
    [[ "${FAKE_RENEW}" == "noop" ]] && exit 0
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 90 \
        -subj "/CN=renew-test" -keyout "${dir}/${name}.key" -out "${dir}/${name}.cer" >/dev/null 2>&1
elif [[ "${action}" == "install" ]]; then
    [[ -d "${dir}" ]] || { echo "'${name}' is not a cert name" >&2; exit 1; }
    cp "${dir}/${name}.cer" "${full}" && cp "${dir}/${name}.key" "${key}"
fi
EOF
chmod +x "${RENEW_HOME}/.acme.sh/acme.sh"

# $1 acme.sh 里的证书名，$2 它的有效天数，$3 已装进 tls/ 那张的有效天数
renew_setup() {
    rm -rf "${RENEW_HOME}/.acme.sh/"*_ecc "${RENEW_ROOT}/tls" "${RENEW_LOG}"
    renew_cert "${RENEW_HOME}/.acme.sh/$1_ecc" "$1" "$2"
    renew_cert "${RENEW_ROOT}/tls" www.example.test "$3"
    mv "${RENEW_ROOT}/tls/www.example.test.cer" "${RENEW_CRT}"
}
# TLS_DIR 在本进程是 readonly，另起 bash；$1 是 FAKE_RENEW。服务启停全桩掉，t 只回显键名
run_renew() {
    env HOME="${RENEW_HOME}" TLS_DIR="${RENEW_ROOT}/tls" FAKE_RENEW="${1:-}" RENEW_FN="${RENEW_FN}" bash -c '
        currentHost=www.example.test; coreKind=1
        echoContent() { printf "%s\n" "$2"; }
        t() { printf "%s\n" "$1"; }
        handleNginx() { :; }; handleXray() { :; }; reloadCore() { :; }
        eval "${RENEW_FN}"
        renewalTLS'
}
renew_calls() { cat "${RENEW_LOG}" 2>/dev/null; }
renew_fresh() { openssl x509 -in "${RENEW_CRT}" -noout -checkend "${RENEW_WINDOW}" >/dev/null 2>&1; }

renew_setup www.example.test 90 90
run_renew >/dev/null; assert_equals "0" "$?" "renewalTLS：离到期还远时返回 0"
assert_equals "" "$(renew_calls)" "renewalTLS：离到期还远时不调 acme.sh"

# 重装途中 tls/ 下还没有证书：按 acme.sh 那份判，装证书留给 installTLS
renew_setup www.example.test 90 90; rm -f "${RENEW_CRT}"
run_renew >/dev/null; assert_equals "0" "$?" "renewalTLS：tls/ 下没装、acme.sh 那份离到期还远时返回 0"
assert_equals "" "$(renew_calls)" "renewalTLS：tls/ 下没装时不在安装中途续期或重装"

# 刚签的短证书：按文件修改时间加 90 天推算会以为还剩 90 天，要按真实到期时间判
renew_setup www.example.test 3 3
run_renew >/dev/null; assert_equals "0" "$?" "renewalTLS：3 天后到期的证书进窗口、续期成功"
assert_contains "$(renew_calls)" "--renew -d www.example.test --ecc --force" "renewalTLS：单域名证书按证书名强制续期"
renew_fresh; assert_equals "0" "$?" "renewalTLS：续完 tls/ 下是新证书"

renew_setup '*.example.test' 3 3
run_renew >/dev/null; assert_equals "0" "$?" "renewalTLS：通配符证书续期成功"
assert_contains "$(renew_calls)" "--renew -d *.example.test" "renewalTLS：通配符证书按 *.父域 续期"
assert_contains "$(renew_calls)" "--installcert -d *.example.test" "renewalTLS：通配符证书按 *.父域 安装，拿主机名装会被 acme.sh 拒"

renew_setup www.example.test 90 3
run_renew >/dev/null; assert_equals "0" "$?" "renewalTLS：acme.sh 里已是新证书时只重装"
assert_equals "0" "$(renew_calls | grep -c -- '--renew')" "renewalTLS：acme.sh 里已是新证书时不再续期"
renew_fresh; assert_equals "0" "$?" "renewalTLS：重装后 tls/ 下是新证书"

renew_setup www.example.test 3 3
RENEW_BEFORE=$(cksum <"${RENEW_CRT}")
RENEW_OUT=$(run_renew noop); assert_equals "1" "$?" "renewalTLS：acme.sh 没换出新证书时返回 1"
assert_contains "${RENEW_OUT}" "TLS_RENEW_NOT_EXTENDED" "renewalTLS：没换出新证书时报「续期后仍在窗口内」"
assert_equals "${RENEW_BEFORE}" "$(cksum <"${RENEW_CRT}")" "renewalTLS：续期失败后 tls/ 下还是原来那张"
assert_equals "0" "$(find "${RENEW_ROOT}/tls" -name '*.renew-bak' | wc -l | tr -d ' ')" "renewalTLS：失败后不留 .renew-bak"

renew_setup www.example.test 3 3
RENEW_OUT=$(run_renew fail); assert_equals "1" "$?" "renewalTLS：acme.sh 续期失败返回 1"
assert_contains "${RENEW_OUT}" "TLS_RENEW_ACME_FAILED" "renewalTLS：acme.sh 续期失败时报续期失败"

echo ""

echo -e "${YELLOW}=== 测试 installSubscribe ===${NC}"

# installSubscribe 的 heredoc 里有顶格的 }，按下一个函数的开头截取
SUB_FN=$(awk '/^installSubscribe\(\) \{/{f=1} /^unInstallSubscribe\(\) \{/{f=0} f' install.sh; sed -n '/^readNginxSubscribe() {/,/^}/p' install.sh)
assert_not_empty "${SUB_FN}" "installSubscribe：抽到函数原文"
SUB_ROOT="${MOCK_ROOT}/subscribe-conf"
SUB_CONF="${SUB_ROOT}/nginx/subscribe.conf"
SUB_HEX=0123456789abcdef0123456789abcdef

# $1 nginx -v 报的版本（none = 还没装，装上后报 1.27.3），$2 cert|nocert，$3 v6|v4，$4 可选：nginx -T 输出的文件；
# 输出读回的「端口|协议」。nocert 按 IP 装（Reality-only），没有 currentHost
run_sub() {
    rm -rf "${SUB_ROOT}"; mkdir -p "${SUB_ROOT}/nginx" "${SUB_ROOT}/tls"
    local host=
    if [[ "$2" == "cert" ]]; then host=example.com; : >"${SUB_ROOT}/tls/example.com.crt"; : >"${SUB_ROOT}/tls/example.com.key"; fi
    printf 'y\ny\n' | env PROXY_AGENT_DIR="${SUB_ROOT}" V2RAY_LANG=zh_CN SUB_HOST="${host}" SUB_ROOT="${SUB_ROOT}" SUB_FN="${SUB_FN}" SUB_NGINX="$1" SUB_V6="$3" SUB_T="${4:-}" bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh
        nginxConfigPath="${SUB_ROOT}/nginx/"
        nginxStaticPath=/usr/share/nginx/html; currentHost="${SUB_HOST}"
        echoContent() { :; }
        nginx() {
            if [[ "$1" == "-T" && -n "${SUB_T}" ]]; then cat "${SUB_T}"; return 0; fi
            [[ "$1" == "-v" ]] || return 0
            if [[ "${SUB_NGINX}" != none || -f "${SUB_ROOT}/installed" ]]; then
                echo "nginx version: nginx/${SUB_NGINX/none/1.27.3}" >&2
            else
                echo "bash: nginx: command not found" >&2
            fi
        }
        installNginxTools() { : >"${SUB_ROOT}/installed"; }
        initSingBoxPort() { echo 23456; }
        nginxBlog() { :; }; bootStartup() { :; }; handleNginx() { :; }; pgrep() { echo 1; }
        curl() { [[ "${SUB_V6}" == v6 ]] && echo "ip=2001:db8::1"; return 0; }
        eval "${SUB_FN}"
        installSubscribe >/dev/null 2>&1
        readNginxSubscribe
        printf "%s|%s\n" "${subscribePort}" "${subscribeType}"'
}
# 订阅 location 的正则（去掉 nginx 的引号与命名捕获）对 $1 是否命中，任一 location 命中即算
sub_location_matches() {
    local re
    re=$(sed -n 's/^    location ~ "\(\^\/s\/.*\$\)" {$/\1/p' "${SUB_CONF}" | sed 's/(?<[A-Za-z]*>/(/g')
    [[ -n "${re}" ]] && grep -qE "${re}" <<<"$1"
}

assert_equals "23456|https" "$(run_sub 1.27.3 cert v6)" "installSubscribe：有证书时读回订阅端口与 https（多了拒握手块也只取主块的 listen）"
assert_equals "1" "$(grep -c 'ssl_reject_handshake on;' "${SUB_CONF}")" "installSubscribe：nginx ≥ 1.19.4 时 SNI 不对的握手直接拒"
assert_contains "$(cat "${SUB_CONF}")" "listen 23456 ssl default_server;listen [::]:23456 ssl default_server;" "installSubscribe：拒握手块是这个端口 v4 / v6 的默认 server"
assert_contains "$(grep -m1 listen "${SUB_CONF}")" "so_keepalive=on" "installSubscribe：第一行 listen 属于主 server 块"
assert_equals "1" "$(grep -c '^    server_tokens off;' "${SUB_CONF}")" "installSubscribe：响应头不带 nginx 版本号"
sub_location_matches "/s/default/${SUB_HEX}"; assert_equals "0" "$?" "installSubscribe：32 位十六进制的订阅文件名命中"
sub_location_matches "/s/sing-box_profiles/${SUB_HEX}"; assert_equals "0" "$?" "installSubscribe：sing-box_profiles 命中"
sub_location_matches "/s/default/../../etc/passwd"; assert_equals "1" "$?" "installSubscribe：带 .. 的路径不命中"
sub_location_matches "/s/default/${SUB_HEX}/x"; assert_equals "1" "$?" "installSubscribe：文件名后再带路径不命中"
sub_location_matches "/s/default/${SUB_HEX%?}"; assert_equals "1" "$?" "installSubscribe：31 位不命中"
sub_location_matches "/s/carpool/${SUB_HEX}"; assert_equals "1" "$?" "installSubscribe：不在白名单的目录不命中"

assert_equals "23456|https" "$(run_sub 1.18.0 cert v4)" "installSubscribe：nginx 1.18 有证书时照常读回"
assert_equals "0" "$(grep -c 'ssl_reject_handshake\|default_server' "${SUB_CONF}")" "installSubscribe：nginx < 1.19.4 不写拒握手块"
assert_equals "1" "$(grep -c '^    server_tokens off;' "${SUB_CONF}")" "installSubscribe：nginx 1.18 也不带版本号"

assert_equals "23456|http" "$(run_sub 1.27.3 nocert v4)" "installSubscribe：没证书时走 http"
assert_equals "0" "$(grep -c 'ssl_reject_handshake' "${SUB_CONF}")" "installSubscribe：http 订阅不写拒握手块"

assert_equals "23456|https" "$(run_sub none cert v4)" "installSubscribe：先装 nginx 再配订阅"
assert_equals "1" "$(grep -c 'ssl_reject_handshake on;' "${SUB_CONF}")" "installSubscribe：按装完后的 nginx 版本判，不用装之前的 not found"
assert_contains "$(grep -m1 listen "${SUB_CONF}")" "http2 on;" "installSubscribe：装完后的 nginx ≥ 1.25.1 时开 http2"

# --- 通用订阅地址与更新间隔（G / F）---
run_sub 1.27.3 cert v4 >/dev/null
assert_contains "$(head -1 "${SUB_CONF}")" "# proxy-agent subscribe.conf r" "订阅渲染：第一行是模板修订号（旧号的机器进菜单时按原设置重写）"
sub_location_matches "/s/${SUB_HEX}"; assert_equals "0" "$?" "通用订阅：/s/<32 位十六进制> 命中"
sub_location_matches "/s/${SUB_HEX}x"; assert_equals "1" "$?" "通用订阅：33 位不命中"
assert_equals "2|1" "$(grep -c 'add_header Profile-Update-Interval 12 always;' "${SUB_CONF}")|$(grep -c 'add_header Vary User-Agent always;' "${SUB_CONF}")" \
    "订阅响应：两种地址都带更新间隔（整数小时），通用地址带 Vary: User-Agent"
assert_contains "$(cat "${SUB_CONF}")" 'try_files /$paSubFormat/$paSubKey /default/$paSubKey =404;' \
    "通用订阅：文件名用命名捕获（map 求值会冲掉 \$1），选中的格式没有文件时退回默认订阅"

# sub_ua_format UA → 按 subscribe.conf 里 map 的规则自上而下第一个命中给出的格式
sub_ua_format() {
    perl -e '
        my ($ua, $conf) = @ARGV; my ($in, $dflt) = (0, "");
        open my $fh, "<", $conf or die;
        while (<$fh>) {
            if (/^map \$http_user_agent/) { $in = 1; next }
            last if $in && /^\}/;
            next unless $in;
            if (/^\s*default\s+(\S+);/) { $dflt = $1; next }
            if (/^\s*"~(\*?)(.*)"\s+(\S+);/) { my ($re, $fmt) = ($1 ? qr/$2/i : qr/$2/, $3); if ($ua =~ $re) { print "$fmt\n"; exit } }
        }
        print "$dflt\n";' "$1" "${SUB_CONF}"
}
while IFS='|' read -r _ua _want; do
    assert_equals "${_want}" "$(sub_ua_format "${_ua}")" "通用订阅：${_ua:-空 UA} → ${_want}"
done <<'UAS'
clash-verge/v2.5.10|clashMetaProfiles
mihomo.party/v2.0.4 (clash.meta)|clashMetaProfiles
ClashMetaForAndroid/2.11.18.Meta|clashMetaProfiles
FlClash/v0.8.90 clash-verge Platform/android|clashMetaProfiles
clash.meta/v1.19.15|clashMeta
SFA (sing-box 1.12.0; language zh_CN)|sing-box
SFI/1.8.0 (Build 1; sing-box 1.8.0; language en_US)|sing-box
HiddifyNext/2.5.7 (android) like ClashMeta v2ray sing-box|sing-box
NekoBox/Android/1.3.9 (Prefer ClashMeta Format)|default
Karing/1.2.25 platform/windows mihomo/1.19.28 clash-verge sing-box 1.14.0|sing-box
v2rayN/7.10.5|default
Shadowrocket/2070 CFNetwork/1568 Darwin/24.0.0|default
|default
UAS

# --- 同端口别的配置已有 default_server：不加拒握手块 ---
_subT="${MOCK_ROOT}/subscribe-nginx-T.txt"
printf '# configuration file /etc/nginx/conf.d/site.conf:\nserver {\n    listen 23456 ssl default_server; # site\n}\n' >"${_subT}"
assert_equals "23456|https" "$(run_sub 1.27.3 cert v4 "${_subT}")" "订阅渲染（同端口已有 default_server）：照常装上"
assert_equals "0" "$(grep -c 'default_server\|ssl_reject_handshake' "${SUB_CONF}")" \
    "订阅渲染：同端口别的配置已有 default_server 时不加拒握手块（两个 default_server 让 nginx 拒载）"
printf '# configuration file %s/nginx/subscribe.conf:\nserver {\n    listen 23456 ssl default_server;\n}\n# configuration file /etc/nginx/conf.d/site.conf:\nserver { listen 127.0.0.1:23456 default_server; listen 8443 default_server; }\n' "${SUB_ROOT}" >"${_subT}"
run_sub 1.27.3 cert v4 "${_subT}" >/dev/null
assert_equals "1" "$(grep -c 'ssl_reject_handshake on;' "${SUB_CONF}")" \
    "订阅渲染：自己那份、别的地址或别的端口上的 default_server 不算冲突，拒握手块照加"
rm -f "${_subT}"

# --- 旧模板的 subscribe.conf：进菜单时按原端口、原域名重写 ---
UPG_ROOT="${MOCK_ROOT}/subscribe-upgrade"
UPG_CONF="${UPG_ROOT}/nginx/subscribe.conf"
UPG_FN=$(awk '/^installSubscribe\(\) \{/{f=1} /^unInstallSubscribe\(\) \{/{f=0} f' install.sh; sed -n '/^carpoolReloadNginx() {/,/^}/p;/^carpoolInsertPageBlock() {/,/^}/p' install.sh)
# upg_ensure [nginx -t 的返回码] → 以 UPG_ROOT 为安装根跑 ensureSubscribeConfCurrent，nginx 调用记进 calls；输出它打印的内容
upg_ensure() {
    : >"${UPG_ROOT}/calls"
    env PROXY_AGENT_DIR="${UPG_ROOT}" UPG_FN="${UPG_FN}" UPG_T_RC="${1:-0}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/carpool.sh
        eval "${UPG_FN}"
        nginx() {
            echo "nginx $*" >>"${PROXY_AGENT_DIR}/calls"
            [[ "$1" == "-v" ]] && echo "nginx version: nginx/1.27.3" >&2
            [[ "$1" == "-t" ]] && return "${UPG_T_RC}"
            return 0
        }
        pgrep() { echo 1; }; curl() { return 0; }
        nginxConfigPath="${PROXY_AGENT_DIR}/nginx/"; nginxStaticPath=/var/www/html
        ensureSubscribeConfCurrent' 2>&1
}
# run_upg 旧 conf 的 listen 后缀（"" 是 http，ssl 是 https） [nginx -t 的返回码] [cert 时放上域名证书] → 从旧模板的 conf 起跑 upg_ensure
run_upg() {
    rm -rf "${UPG_ROOT}"; mkdir -p "${UPG_ROOT}/nginx" "${UPG_ROOT}/tls" "${UPG_ROOT}/carpool"
    [[ "$3" == cert ]] && : >"${UPG_ROOT}/tls/sub.example.org.crt" && : >"${UPG_ROOT}/tls/sub.example.org.key"
    printf 'server {\n    listen 50188 %s so_keepalive=on;\n    %s\n    root /var/www/html;\n    location ~ "^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([0-9a-f]{32})$" {\n        alias /x/$1/$2;\n    }\n    location / {\n    }\n}\n' \
        "$1" "$([[ "$1" == ssl ]] && echo 'server_name sub.example.org;')" >"${UPG_CONF}"
    upg_ensure "$2"
}
_upgOut=$(run_upg "")
assert_contains "$(head -1 "${UPG_CONF}")" "# proxy-agent subscribe.conf r" "订阅升级：旧模板重写成当前修订号"
assert_contains "$(grep -m1 listen "${UPG_CONF}")" "listen 50188 " "订阅升级：端口不变"
assert_equals "0" "$(grep -c 'listen 50188 ssl' "${UPG_CONF}")" "订阅升级：原来是 http 的仍是 http"
assert_equals "1|1" "$(grep -c '^nginx -t$' "${UPG_ROOT}/calls")|$(grep -c '^nginx -s reload$' "${UPG_ROOT}/calls")" "订阅升级：nginx -t 过了才 reload"
assert_contains "${_upgOut}" "订阅地址不变" "订阅升级：告诉车主重写了、地址没变"
_upgBefore=$(cat "${UPG_CONF}")
_upgOut=$(upg_ensure)
assert_equals "|${_upgBefore}" "$(cat "${UPG_ROOT}/calls")${_upgOut}|$(cat "${UPG_CONF}")" "订阅升级：已经是当前模板就什么都不做"

run_upg "" >/dev/null
sed -i.bak '1s/.*/# proxy-agent subscribe.conf r1/' "${UPG_CONF}" && rm -f "${UPG_CONF}.bak"
awk '/^    location \/ \{/ && !d { print "    # carpool-page-begin"; print "    location = /old {}"; print "    # carpool-page-end"; d = 1 } { print }' "${UPG_CONF}" >"${UPG_CONF}.new" && mv "${UPG_CONF}.new" "${UPG_CONF}"
upg_ensure >/dev/null
assert_equals "1" "$(grep -c '# carpool-page-begin' "${UPG_CONF}")" "订阅升级：拼车页面块补回、只有一份"
assert_equals "yes" "$(awk '/carpool-page-end/{e=NR} /^    location \/ \{/{l=NR} END{print (e && l && e < l) ? "yes" : "no"}' "${UPG_CONF}")" "订阅升级：页面块在 location / 之前"
assert_equals "0" "$(grep -c 'location = /old' "${UPG_CONF}")" "订阅升级：页面块是按当前模板重新生成的"

run_upg "" 1 >/dev/null
assert_equals "server {|0" "$(head -1 "${UPG_CONF}")|$(grep -c paSubFormat "${UPG_CONF}")" "订阅升级（nginx -t 不过）：还原成旧配置"
assert_equals "0" "$(grep -c 'nginx -s reload' "${UPG_ROOT}/calls")" "订阅升级（nginx -t 不过）：不 reload"

run_upg ssl >/dev/null
assert_contains "$(head -1 "${UPG_CONF}")" "server {" "订阅升级：https 订阅的证书不在了就不动（重写会降成 http）"
run_upg ssl 0 cert >/dev/null
assert_equals "server_name sub.example.org;|yes" "$(grep -m1 -o 'server_name [^ ]*' "${UPG_CONF}")|$(grep -m1 listen "${UPG_CONF}" | grep -q 'listen 50188 ssl' && echo yes)" "订阅升级：https 订阅重写后仍是 https、域名不变"

echo ""

echo -e "${YELLOW}=== 测试 rollbackScript 从 GitHub 回滚 ===${NC}"

RB_FN=$(sed -n '/^rollbackScript() {/,/^}/p' install.sh)
assert_not_empty "${RB_FN}" "rollbackScript：抽到函数原文"
RB_ROOT="${MOCK_ROOT}/rollback.root"
RB_TAG="${MOCK_ROOT}/rollback.tag"

# $1：目标 tag 的 install.sh 提不提 carpool.sh（yes|no）；$2：那个 tag 下有没有 lib/carpool.sh（yes|no）。输出退出码
run_rb() {
    local m
    rm -rf "${RB_ROOT}" "${RB_TAG}"
    mkdir -p "${RB_ROOT}/lib" "${RB_ROOT}/shell/lang" "${RB_TAG}/lib" "${RB_TAG}/shell/lang"
    for m in i18n constants utils json-utils system-detect protocol-registry carpool; do
        echo "# new ${m}" >"${RB_ROOT}/lib/${m}.sh"
        echo "# old ${m}" >"${RB_TAG}/lib/${m}.sh"
    done
    [[ "$2" == yes ]] || rm -f "${RB_TAG}/lib/carpool.sh"
    printf 'libFiles=(i18n.sh constants.sh utils.sh json-utils.sh system-detect.sh protocol-registry.sh%s)\n' "$([[ "$1" == yes ]] && echo ' carpool.sh')" >"${RB_TAG}/install.sh"
    echo '# zh' >"${RB_TAG}/shell/lang/zh_CN.sh"
    echo '# en' >"${RB_TAG}/shell/lang/en_US.sh"
    echo 1.5.0 >"${RB_ROOT}/VERSION"
    printf '1\ny\n' | env PROXY_AGENT_DIR="${RB_ROOT}" RB_TAG="${RB_TAG}" RB_FN="${RB_FN}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/utils.sh
        listScriptVersions() { scriptVersionList=("github:v1.4.1"); }
        backupScript() { echo "${PROXY_AGENT_DIR}/backup/x"; }
        verifyInstallSHA256() { return 0; }
        wget() {
            local out url
            while [[ $# -gt 0 ]]; do case "$1" in -O) out=$2; shift 2 ;; -*) shift ;; *) url=$1; shift ;; esac; done
            [[ -f "${RB_TAG}/${url#*/v1.4.1/}" ]] || return 8
            cp "${RB_TAG}/${url#*/v1.4.1/}" "${out}"
        }
        eval "${RB_FN}"
        rollbackScript' >/dev/null 2>&1
    echo $?
}

assert_equals "0" "$(run_rb no no)" "rollbackScript（GitHub）：回到还没有 carpool 的版本照样成功"
assert_equals "1.4.1|# old i18n" "$(cat "${RB_ROOT}/VERSION")|$(cat "${RB_ROOT}/lib/i18n.sh")" "rollbackScript（GitHub）：版本号与旧模块落盘"
assert_equals "no" "$([[ -f "${RB_ROOT}/lib/carpool.sh" ]] && echo yes || echo no)" "rollbackScript（GitHub）：目标版本没有的模块删掉，与本地备份回滚一致"
assert_equals "1" "$(run_rb yes no)" "rollbackScript（GitHub）：目标版本要 carpool 却下不到时中止"
assert_equals "1.5.0|# new carpool" "$(cat "${RB_ROOT}/VERSION")|$(cat "${RB_ROOT}/lib/carpool.sh")" "rollbackScript（GitHub）：中止时一个文件都不动"
assert_equals "0" "$(run_rb yes yes)" "rollbackScript（GitHub）：目标版本有 carpool 时照常下"
assert_equals "# old carpool" "$(cat "${RB_ROOT}/lib/carpool.sh")" "rollbackScript（GitHub）：carpool 换成目标版本的"
rm -rf "${RB_ROOT}" "${RB_TAG}"

# 本地备份回滚 + 配置快照：快照里 sing-box 片段是空的、Xray 有入站时跳过 sing-box 那半，不把整个回退撤销
RB_LOCAL_FN=$(sed -n '/^rollbackScript() {/,/^}/p;/^backupConfigSnapshot() {/,/^}/p;/^restoreConfigSnapshot() {/,/^}/p' install.sh)
RB_BAK="${MOCK_ROOT}/rollback.bak"
rm -rf "${RB_ROOT}" "${RB_BAK}"
mkdir -p "${RB_ROOT}/xray/conf" "${RB_ROOT}/sing-box/conf/config" "${RB_BAK}/config/xray/conf" "${RB_BAK}/config/sing-box/conf/config"
touch "${RB_ROOT}/sing-box/sing-box"
echo '{"inbounds": [{"tag": "now"}]}' >"${RB_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
echo '{"inbounds": [{"tag": "chain"}]}' >"${RB_ROOT}/sing-box/conf/config/chain_inbound.json"
echo '{"inbounds": [{"tag": "old"}]}' >"${RB_BAK}/config/xray/conf/07_VLESS_vision_reality_inbounds.json"
echo 1.4.1 >"${RB_BAK}/VERSION"
_out=$(printf '1\ny\ny\n' | env PROXY_AGENT_DIR="${RB_ROOT}" RB_BAK="${RB_BAK}" RB_LOCAL_FN="${RB_LOCAL_FN}" V2RAY_LANG=zh_CN bash -c '
    source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh
    listScriptVersions() { scriptVersionList=("local:${RB_BAK}"); }
    backupScript() { mkdir -p "${PROXY_AGENT_DIR}/backup/x"; echo "${PROXY_AGENT_DIR}/backup/x"; }
    handleXray() { :; }; handleSingBox() { :; }
    singBoxMergeConfig() { echo MERGE; return 1; }
    reloadCore() { echo RELOAD; }
    eval "${RB_LOCAL_FN}"
    rollbackScript' 2>&1; echo "rc=$?")
assert_contains "${_out}" "rc=0" "rollbackScript（本地，快照 sing-box 片段为空）：返回 0"
assert_contains "${_out}" "跳过 sing-box 那一半" "rollbackScript（本地，快照 sing-box 片段为空）：黄字说明跳过"
assert_equals "no|yes" "$([[ "${_out}" == *MERGE* ]] && echo yes || echo no)|$([[ "${_out}" == *RELOAD* ]] && echo yes || echo no)" "rollbackScript（本地，快照 sing-box 片段为空）：不合并零片段，照常重载"
assert_equals "old" "$(jq -r '.inbounds[0].tag' "${RB_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")" "rollbackScript（本地，快照 sing-box 片段为空）：Xray 配置恢复成快照里的，没被撤销"
rm -rf "${RB_ROOT}" "${RB_BAK}"

echo ""

echo -e "${YELLOW}=== 测试 IPv6 / WARP 分流的状态显示 ===${NC}"

RT_FN=$(sed -n '/^xrayRoutingHasOutbound() {/,/^}/p;/^showIPv6Routing() {/,/^}/p;/^showWireGuardDomain() {/,/^}/p' install.sh)
assert_equals "3" "$(grep -c '^[a-zA-Z0-9]*() {$' <<<"${RT_FN}")" "分流显示：三个函数都抽到了"
RT_DIR="${MOCK_ROOT}/routing-show/"
# $1 = 09_routing.json 的内容（none 表示没有这个文件），其余参数是要建的出站文件名；输出两个显示函数打印的内容
run_rt() {
    local f
    rm -rf "${RT_DIR}"; mkdir -p "${RT_DIR}"
    [[ "$1" == none ]] || printf '%s\n' "$1" >"${RT_DIR}09_routing.json"
    shift
    for f in "$@"; do echo '{}' >"${RT_DIR}${f}.json"; done
    env RT_DIR="${RT_DIR}" RT_FN="${RT_FN}" bash -c '
        source lib/utils.sh
        configPath="${RT_DIR}"; coreKind=1; singBoxConfigPath=
        eval "${RT_FN}"
        showIPv6Routing; showWireGuardDomain IPv4' 2>&1
}
RT_BLOCK='{"routing":{"rules":[{"type":"field","ruleTag":"local-block-port","port":"31111-31210","outboundTag":"local_block"}]}}'
assert_contains "$(run_rt "${RT_BLOCK}" IPv6_out)" "已设置IPv6全局分流" "分流显示：全局模式下 09_routing.json 只剩本机封锁规则，仍认得出是 IPv6 全局"
assert_contains "$(run_rt "${RT_BLOCK}" wireguard_out_IPv4)" "已设置warp IPv4全局分流" "分流显示：WARP 全局同理"
assert_contains "$(run_rt none IPv6_out)" "已设置IPv6全局分流" "分流显示：还没起过 Xray、文件真不在时照旧"
_rtOut=$(run_rt '{"routing":{"rules":[{"type":"field","domain":["geosite:netflix"],"outboundTag":"IPv6_out"}]}}' IPv6_out)
assert_contains "${_rtOut}" "geosite:netflix" "分流显示：按域名分流时列出域名"
assert_contains "${_rtOut}" "未安装warp IPv4分流" "分流显示：没有 WARP 出站时显示未安装"
rm -rf "${RT_DIR}"

echo ""

echo ""

# --- 分享片段：Xray 上的 Trojan 不进 Clash 订阅；VMess WS 的 sing-box 片段用两种服务端都认的 xudp ---
DB_FN=$(sed -n '/^defaultBase64Code() {/,/^}/p;/^shareQrCode() {/,/^}/p' install.sh)
DB_SUB="${MOCK_ROOT}/sharecode.root/subscribe_local"
# run_db COREKIND ARGS... → 装在 sharecode.root、内核为 COREKIND 时跑 defaultBase64Code ARGS
run_db() (
    env PROXY_AGENT_DIR="${MOCK_ROOT}/sharecode.root" DB_FN="${DB_FN}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh
        eval "${DB_FN}"
        coreKind=$1; shift; currentHost=example.org
        defaultBase64Code "$@"' _ "$@"
)
db_reset() { rm -rf "${MOCK_ROOT}/sharecode.root" && mkdir -p "${DB_SUB}/default" "${DB_SUB}/clashMeta" "${DB_SUB}/sing-box"; }
db_reset
_dbOut=$(run_db 1 trojan 443 tro-x pw123 2>&1)
assert_equals "0" "$(cat "${DB_SUB}/clashMeta/tro" 2>/dev/null | grep -c 'type: trojan')" \
    "Trojan（Xray）：不进 Clash 订阅（mihomo 带指纹时报 h2，被 443 回落给 nginx）"
assert_contains "$(cat "${DB_SUB}/default/tro")" "trojan://pw123@example.org:443" "Trojan（Xray）：通用订阅照发"
assert_equals "trojan" "$(jq -r '.[0].type' "${DB_SUB}/sing-box/tro")" "Trojan（Xray）：sing-box 订阅照发（sing-box 的 utls 认 alpn）"
assert_contains "${_dbOut}" "    alpn:
      - http/1.1" "Trojan（Xray）：打印一段只报 http/1.1 的 Clash 配置供测试"
assert_equals "0" "$(grep -c 'client-fingerprint' <<<"${_dbOut}")" "Trojan（Xray）：测试用的那段不带指纹（带了 mihomo 就不理 alpn）"
db_reset
run_db 2 trojan 8443 tro-x pw123 >/dev/null 2>&1
assert_equals "1" "$(grep -c 'type: trojan' "${DB_SUB}/clashMeta/tro")" "Trojan（sing-box）：照进 Clash 订阅（自带 TLS，没有按 ALPN 的回落）"
# Clash 的 Reality 节点要开 support-x25519mlkem768，并且缩进在 reality-opts 里：写错层 mihomo 不报错，只是连不上新版 Xray
db_reset
run_db 1 vlessReality 443 rea-x uuid1 >/dev/null 2>&1
run_db 1 vlessXHTTP 8443 rea-y uuid2 example.org /path >/dev/null 2>&1
assert_equals "2" "$(grep -A3 'reality-opts:' "${DB_SUB}/clashMeta/rea" | grep -c '^      support-x25519mlkem768: true$')" \
    "Clash 订阅：Xray 的 Reality Vision 与 XHTTP 都开 support-x25519mlkem768"
db_reset
run_db 2 vlessReality 443 rea-x uuid1 >/dev/null 2>&1
assert_equals "1" "$(grep -A3 'reality-opts:' "${DB_SUB}/clashMeta/rea" | grep -c '^      support-x25519mlkem768: true$')" \
    "Clash 订阅：sing-box 的 Reality Vision 也开 support-x25519mlkem768"
# 15 的地址可以是 CDN，SNI 和 Host 始终是本机域名；sing-box 没有 XHTTP，写进它的订阅整份配置都起不来
db_reset
run_db 1 vlessXHTTPTLS 443 xt-x uuid3 cdn.example.net /abcdxhttp >/dev/null 2>&1
assert_equals "vless://uuid3@cdn.example.net:443?encryption=none&security=tls&type=xhttp&mode=auto&host=example.org&sni=example.org&fp=chrome&alpn=h2&path=/abcdxhttp#xt-x" \
    "$(cat "${DB_SUB}/default/xt")" "XHTTP+TLS：分享链接"
assert_equals "$(printf '%s\n' '  - name: "xt-x"' '    type: vless' '    server: cdn.example.net' '    port: 443' '    uuid: uuid3' '    udp: true' '    tls: true' \
    '    network: xhttp' '    client-fingerprint: chrome' '    alpn:' '      - h2' '    servername: example.org' '    xhttp-opts:' '      path: /abcdxhttp' '      host: example.org')" \
    "$(cat "${DB_SUB}/clashMeta/xt")" "XHTTP+TLS：Clash 节点没有 reality-opts，SNI 和 Host 是本机域名"
assert_equals "[]" "$(jq -c . "${DB_SUB}/sing-box/xt")" "XHTTP+TLS：不进 sing-box 订阅"
# 16：通用订阅一行都不写（v2rayN、mihomo 的链接解析器会丢掉 plugin，退化成裸 SS2022），两种带它的订阅都要有 UDP 通路
db_reset
getPublicIP() { echo 203.0.113.9; }; export -f getPublicIP
_dbOut=$(run_db 2 shadowtls 8443 st-x stpw upsk== srvkey== dl.google.com 2>&1)
unset -f getPublicIP
assert_equals "no" "$([[ -s "${DB_SUB}/default/st" ]] && echo yes || echo no)" "ShadowTLS：不进通用订阅"
assert_contains "${_dbOut}" "plugin=shadow-tls%3Bhost%3Ddl.google.com%3Bpassword%3Dstpw%3Bversion%3D3#st-x" "ShadowTLS：账号页打印分享链接"
assert_contains "${_dbOut}" "v2rayN" "ShadowTLS：分享链接旁边说明哪些客户端用不了"
assert_equals "$(printf '%s\n' '  - name: "st-x"' '    type: ss' '    server: 203.0.113.9' '    port: 8443' '    cipher: 2022-blake3-aes-128-gcm' '    password: "srvkey==:upsk=="' '    udp: true' \
    '    client-fingerprint: chrome' '    plugin: shadow-tls' '    plugin-opts:' '      host: dl.google.com' '      password: "stpw"' '      version: 3' '    smux:' '      enabled: true' '      protocol: h2mux')" \
    "$(cat "${DB_SUB}/clashMeta/st")" "ShadowTLS：Clash 节点带 plugin 与 smux（没有 smux 时 mihomo 的 UDP 不通）"
assert_equals '["shadowsocks","st-st-x",true,"srvkey==:upsk=="]' "$(jq -c '.[0] | [.type, .detour, .multiplex.enabled, .password]' "${DB_SUB}/sing-box/st")" "ShadowTLS：sing-box 的 SS 出站经 detour 走外层，开 multiplex（UDP 靠它）"
assert_equals '["shadowtls","st-st-x","203.0.113.9",8443,3,"stpw","dl.google.com","chrome"]' "$(jq -c '.[1] | [.type, .tag, .server, .server_port, .version, .password, .tls.server_name, .tls.utls.fingerprint]' "${DB_SUB}/sing-box/st")" \
    "ShadowTLS：sing-box 的外层出站，SNI 是握手目标"
# Naive 进 sing-box 订阅：UDP 要显式开，用户名与入站写的一致
db_reset
run_db 2 naive 8443 nv-singbox_naive nvpw >/dev/null 2>&1
assert_equals '[{"tag":"nv-singbox_naive","type":"naive","server":"example.org","server_port":8443,"username":"nv-singbox_naive","password":"nvpw","udp_over_tcp":true,"tls":{"enabled":true,"server_name":"example.org"}}]' \
    "$(jq -c . "${DB_SUB}/sing-box/nv")" "Naive：sing-box 节点带 udp_over_tcp（naive 出站默认不带 UDP）"
assert_contains "$(cat "${DB_SUB}/default/nv")" "naive+https://nv-singbox_naive:nvpw@example.org:8443" "Naive：分享链接照旧"
assert_equals "no" "$([[ -s "${DB_SUB}/clashMeta/nv" ]] && echo yes || echo no)" "Naive：不进 Clash 订阅（mihomo 不支持）"
db_reset
run_db 1 vmessws 443 vm-x 0f3c8a4e-1b2d-4c5e-8f90-123456789abc example.net /vws >/dev/null 2>&1
assert_equals "xudp" "$(jq -r '.[0].packet_encoding' "${DB_SUB}/sing-box/vm")" "VMess WS：sing-box 片段的 UDP 用 xudp（packetaddr 只有 sing-box 服务端认，Xray 上 UDP 全丢）"
# hy2_client OBFSTYPE OBFSPW UP DOWN → 打印出的官方客户端 JSON（从「v2rayN(hysteria+TLS)」那行之后截到下一个提示或输出结束）
hy2_client() {
    db_reset
    run_db 2 hysteria 443 hy-x pw123 2>&1 <<<"" | sed -n '/v2rayN(hysteria+TLS)/,/--->/p' | sed '1d;/--->/d' | sed 's/\x1b\[[0-9;]*m//g'
}
_hyJson=$(hysteria2ObfsType='' hysteria2ObfsPassword='' hysteria2ClientUploadSpeed='' hysteria2ClientDownloadSpeed='' singBoxHysteria2Port=443 hy2_client)
assert_equals 'null|null|example.org:443|pw123' "$(jq -r '[.obfs, .bandwidth, .server, .auth] | map(tostring) | join("|")' <<<"${_hyJson}")" \
    "Hysteria2 官方客户端 JSON：没开混淆、BBR 时不带 obfs 与 bandwidth"
_hyJson=$(hysteria2ObfsType=salamander hysteria2ObfsPassword='a&b=c' singBoxHysteria2Port=443 hy2_client)
assert_equals '{"type":"salamander","salamander":{"password":"a&b=c"}}' "$(jq -c .obfs <<<"${_hyJson}")" \
    "Hysteria2 官方客户端 JSON：带上 salamander 混淆（按类型嵌一层，缺了连不上开着混淆的服务端）"
_hyJson=$(hysteria2ObfsType=gecko hysteria2ObfsPassword=pw hysteria2ClientUploadSpeed=20 hysteria2ClientDownloadSpeed=200 singBoxHysteria2Port=443 hy2_client)
assert_equals '{"type":"gecko","gecko":{"password":"pw"}}|{"up":"20 mbps","down":"200 mbps"}' "$(jq -c .obfs <<<"${_hyJson}")|$(jq -c .bandwidth <<<"${_hyJson}")" \
    "Hysteria2 官方客户端 JSON：gecko 混淆与 Brutal 的带宽"
rm -rf "${MOCK_ROOT}/sharecode.root"

# --- Reality 密钥：sing-box 入站只存私钥，订阅读的公钥在 reality_key；沿用旧密钥时也要写 ---
RK_FN=$(sed -n '/^initRealityKey() {/,/^}/p' install.sh)
RK_ROOT="${MOCK_ROOT}/realitykey.root"
# run_rk SELECTCORE COREKIND LAST CURPUB → 跑 initRealityKey（桩 sing-box 生成 genpub），打印 reality_key 里记的公钥
run_rk() {
    rm -rf "${RK_ROOT}" && mkdir -p "${RK_ROOT}/sing-box/conf/config"
    printf '#!/bin/sh\necho "PrivateKey: genpriv"\necho "PublicKey: genpub"\n' >"${RK_ROOT}/sing-box/sing-box"
    chmod +x "${RK_ROOT}/sing-box/sing-box"
    env PROXY_AGENT_DIR="${RK_ROOT}" RK_FN="${RK_FN}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh
        eval "${RK_FN}"
        selectCoreType=$1 coreKind=$2 lastInstallationConfig=$3 currentRealityPublicKey=$4 currentRealityPrivateKey=${4:+priv-$4}
        initRealityKey </dev/null >/dev/null 2>&1
        sed -n "s/^publicKey://p" "${SINGBOX_FRAGMENT_DIR}/reality_key" 2>/dev/null' _ "$@"
}
assert_equals "oldpub" "$(run_rk 2 1 1 oldpub)" "Reality 密钥：从 Xray 切到 sing-box、沿用上次配置时也记下公钥（不记订阅里的 public_key 是空的，整份 sing-box 订阅加载失败）"
assert_equals "genpub" "$(run_rk 2 "" "" "")" "Reality 密钥：sing-box 新装记下新生成的公钥"
assert_equals "" "$(run_rk 1 1 1 oldpub)" "Reality 密钥：Xray 内核上不写 sing-box 的公钥文件"
rm -rf "${RK_ROOT}"

# --- SS2022 不走 initSingBoxPort，端口要自己放行 ---
SS_FN=$(sed -n '/^initSS2022Config() {/,/^}/p' install.sh)
_ssCalls=$(env SS_FN="${SS_FN}" bash -c '
    eval "${SS_FN}"
    allowPort() { echo "allow $*"; }
    readValidPort() { printf -v "$2" %s 23456; }
    echoContent() { :; }
    singBoxConfigPath=/nonexistent/ ss2022Method=2022-blake3-aes-128-gcm ss2022ServerKey=k
    initSS2022Config </dev/null' 2>&1)
assert_equals "allow 23456|allow 23456 udp" "$(paste -sd'|' - <<<"${_ssCalls}")" "SS2022：端口的 TCP、UDP 都放行（两个都监听，漏了防火墙直接拒连）"

# --- 带域名安装中途退出：起步时在跑的服务按旧配置拉回来；写了新配置之后再退出就不管 ---
IA_FN=$(sed -n '/^installAbortArm() {/,/^}/p;/^installAbortDisarm() {/,/^}/p;/^installAbortRestore() {/,/^}/p;/^xrayCoreInstall() {/,/^}/p;/^singBoxInstall() {/,/^}/p' install.sh)
assert_equals "5" "$(grep -c '^[a-zA-Z]*() {$' <<<"${IA_FN}")" "安装中途退出：抽到五个函数原文"
# run_ia FN FAILAT RUNNING → 桩掉 FN 的每一步、在 FAILAT 那步 exit 1，RUNNING 是起步时在跑的服务；打印 handle* start 的调用
run_ia() {
    env IA_FN="${IA_FN}" IA_FAIL="$2" IA_RUNNING=" $3 " bash -c '
        eval "${IA_FN}"
        for f in chainRefuseCoreSwitch readLastInstallationConfig installTools initTLSNginxConfig installTLS customPortFunction \
            randomPathFunction installXray installXrayService initXrayConfig cleanUp syncSidecarTlsDomain installCronTLS nginxBlog updateRedirectNginxConf \
            reloadCore refreshSubscribeAfterInstall checkGFWStatue showAccounts installSingBox installSingBoxService initSingBoxConfig echoContent; do
            eval "$f() { [[ \"\${IA_FAIL}\" == $f ]] && exit 1; return 0; }"
        done
        handleXray() { [[ "$1" == start ]] && echo xray-start; return 0; }
        handleSingBox() { [[ "$1" == start ]] && echo singbox-start; return 0; }
        handleNginx() { [[ "$1" == start ]] && echo nginx-start; return 0; }
        xrayDaemonRunning() { [[ "${IA_RUNNING}" == *" xray "* ]]; }
        pgrep() { [[ "${IA_RUNNING}" == *" $2 "* ]] && echo 42; return 0; }
        "$0"' "$1" 2>&1 | paste -sd' ' -
}
assert_equals "xray-start singbox-start nginx-start" "$(run_ia xrayCoreInstall initTLSNginxConfig "xray sing-box nginx")" \
    "安装中途退出（Xray，端口自检那步）：起步时在跑的 Xray、旁挂 sing-box、nginx 都拉回来"
assert_equals "xray-start" "$(run_ia xrayCoreInstall installTLS "xray")" "安装中途退出（Xray，证书没签下来）：只拉起步时在跑的（没在跑的不碰）"
assert_equals "" "$(run_ia xrayCoreInstall installCronTLS "xray sing-box nginx")" "安装中途退出（Xray，新配置已写）：不拉旧服务"
assert_equals "nginx-start" "$(run_ia xrayCoreInstall "" "xray sing-box nginx")" "安装正常走完：退出时不再多拉一遍（只剩流程自己的 nginx 启动）"
assert_equals "xray-start nginx-start" "$(run_ia singBoxInstall installTLS "xray nginx")" "安装中途退出（从 Xray 切 sing-box，证书没签下来）：把原来的 Xray 拉回来"
assert_equals "" "$(run_ia singBoxInstall initSingBoxConfig "sing-box nginx")" "安装中途退出（sing-box，片段写到一半）：不拉半新半旧的配置"

# --- 只装 Reality 的安装（菜单 19、菜单 2 只选 7）不起 nginx，但开着订阅时收尾得把它起来 ---
RS_FN=$(sed -n '/^handleNginx() {/,/^}/p;/^refreshSubscribeAfterInstall() {/,/^}/p' install.sh)
RS_DIR="${MOCK_ROOT}/refreshsub"
# run_rs SELECTION CALL → 桩掉 systemctl 与订阅重建的各步，SELECTION 是本次安装选的协议；打印 systemctl 调用
run_rs() {
    rm -rf "${RS_DIR}" && mkdir -p "${RS_DIR}/nginx"
    printf '%s\n' 'server {' '    listen 50930;' >"${RS_DIR}/nginx/subscribe.conf"
    env RS_FN="${RS_FN}" RS_DIR="${RS_DIR}" PROXY_AGENT_DIR="${RS_DIR}" SEL="$1" bash -c '
        eval "${RS_FN}"
        for f in ensureAlpineProcps labelNginxPorts echoContent subscribeConfPort readInstallType readInstallProtocolType readConfigHostPathUUID \
            renderSubscribeConf carpoolEnsureNginxLocation bootStartup carpoolRefreshSubscribe sleep nginx; do eval "$f() { :; }"; done
        subscribeConfPort() { echo 50930; }
        systemctl() { echo "systemctl $*"; [[ "$1" == start ]] && : >"${RS_DIR}/up"; return 0; }
        pgrep() { [[ -f "${RS_DIR}/up" ]] && echo 42; return 0; }
        nginxConfigPath="${RS_DIR}/nginx/" release=debian selectCustomInstallType="${SEL}"
        '"$2" 2>&1 | paste -sd'|' -
}
assert_equals "systemctl start nginx" "$(run_rs ",7," refreshSubscribeAfterInstall)" \
    "只装 Reality 后开着订阅：收尾照样把 nginx 起来（不起订阅就一直连不上，到重启才好）"
assert_equals "" "$(run_rs ",7," 'handleNginx start')" "只装 Reality 的安装流程里，不带 force 的 handleNginx start 照旧不起 nginx"
assert_equals "systemctl start nginx" "$(run_rs ",0,7," 'handleNginx start')" "带 TLS 协议的安装照常起 nginx"
rm -rf "${RS_DIR}"

# --- handleNginx start 起不来一律退出；要收尾、要接着走的调用方用子 shell 接住 ---
# checkPortOpen 的 heredoc 里有顶格的 }，按下一个函数名截
NS_FN=$(sed -n '/^handleNginx() {/,/^}/p;/^carpoolReloadNginx() {/,/^}/p;/^updateNginxBlog() {/,/^}/p;/^customSingBoxInstall() {/,/^}/p' install.sh
    sed -n '/^checkPortOpen() {/,/^initTLSNginxConfig() {/p' install.sh | sed '$d')
assert_equals "5" "$(grep -c '^[a-zA-Z0-9]*() {$' <<<"${NS_FN}")" "nginx 起不来：抽到五个函数原文"
NS_DIR="${MOCK_ROOT}/nginxstart"
# run_ns RELEASE MODE CALL → 桩掉服务管理器与 nginx 进程。MODE：ok 服务起得来 · flap 服务报成功、进程却没了 ·
# dead 都起不来 · manual 只有手动 nginx 起得来 · badconf 配置坏着时起不来、恢复备份后才行
run_ns() {
    rm -rf "${NS_DIR}" && mkdir -p "${NS_DIR}/nginx" "${NS_DIR}/log"
    env NS_FN="${NS_FN}" NS_DIR="${NS_DIR}" NS_MODE="$2" PROXY_AGENT_DIR="${NS_DIR}" release="$1" bash -c '
        eval "${NS_FN}"
        for f in ensureAlpineProcps labelNginxPorts sleep handleSingBox handleXray allowPort checkIP checkNginx302 removeNginx302 isValidRedirectUrl; do eval "$f() { :; }"; done
        echoContent() { printf "%s\n" "$2"; }
        t() { printf "%s\n" "$1"; }
        curl() { :; }
        nsCanStart() { case "${NS_MODE}" in ok) return 0 ;; badconf) [[ ! -f "${NS_DIR}/bad" ]] ;; *) return 1 ;; esac; }
        systemctl() {
            [[ "$1" == start ]] || return 0
            nsCanStart && { : >"${NS_DIR}/up"; return 0; }
            [[ "${NS_MODE}" == flap ]] && return 0
            printf "%s\n" "Job for nginx.service failed." "See \"systemctl status nginx.service\" and \"journalctl -xe\" for details." >&2
            return 1
        }
        rc-service() {
            [[ "$2" == start ]] || return 0
            nsCanStart && { : >"${NS_DIR}/up"; return 0; }
            [[ "${NS_MODE}" == manual ]] && { echo " * WARNING: nginx has already been started" >&2; return 0; }
            echo " * start-stop-daemon: failed to start" >&2
            return 1
        }
        nginx() {
            [[ "${NS_MODE}" == manual ]] && { : >"${NS_DIR}/up"; return 0; }
            [[ "$*" == "-s reload" ]] && return 1
            echo "nginx: bind() failed" >&2
            return 1
        }
        pgrep() { [[ -f "${NS_DIR}/up" ]] && echo 42; return 0; }
        addNginx302() { : >"${NS_DIR}/bad"; }
        backupNginxConfig() { echo "backup $1"; [[ "$1" == restoreBackup ]] && mv "${NS_DIR}/bad" "${NS_DIR}/log/bad"; return 0; }
        nginxConfigPath="${NS_DIR}/nginx/" selectCustomInstallType= coreKind=1 currentInstallProtocolType=,0, nginxStaticPath="${NS_DIR}" totalProgress=1
        '"$3" 2>&1
}
_ns=$(run_ns debian ok 'handleNginx start'); _rc=$?
assert_equals "0" "${_rc}" "nginx 起得来：handleNginx start 返回 0"
assert_contains "${_ns}" "Nginx启动成功" "nginx 起得来：打出成功"
_ns=$(run_ns alpine dead 'handleNginx start'); _rc=$?
assert_equals "1" "${_rc}" "nginx 起不来（OpenRC，错误里没有 journalctl）：退出码 1，之前这里返回 0"
assert_equals "0" "$(grep -c "Nginx启动成功" <<<"${_ns}")" "nginx 起不来：不打成功"
run_ns debian flap 'handleNginx start' >/dev/null; assert_equals "1" "$?" "systemd 报成功、进程却没了：退出码 1，之前这里返回 0"
_ns=$(run_ns debian dead 'handleNginx start'); _rc=$?
assert_equals "1" "${_rc}" "nginx 起不来（systemd）：退出码 1"
assert_equals "1" "$(grep -c "Nginx启动失败" <<<"${_ns}")" "nginx 起不来（systemd）：只试一次，不循环重试"
run_ns alpine manual 'handleNginx start' >/dev/null; assert_equals "0" "$?" "OpenRC 记成 started、进程没了：手动那条 nginx 救回来就算起来了"
_ns=$(run_ns debian manual 'handleNginx start'); _rc=$?
assert_equals "0" "${_rc}" "systemd 起不来但手动起来了：不再退出（否则留下一个没人管的 nginx）"
assert_contains "${_ns}" "NGINX_STARTED_DIRECTLY" "systemd 起不来但手动起来了：说清它是直接运行的，不停在「启动失败」上"

_ns=$(run_ns debian dead 'checkPortOpen 12345 example.test; echo "after=$?"'); _rc=$?
assert_equals "1" "${_rc}" "端口自检时 nginx 起不来：退出码 1"
assert_equals "0" "$(grep -c "after=" <<<"${_ns}")" "端口自检时 nginx 起不来：不往下走"
assert_equals "0" "$(grep -c "未检测到" <<<"${_ns}")" "端口自检时 nginx 起不来：不误报成端口没开放"
assert_equals "0" "$(ls -A "${NS_DIR}/nginx" | grep -c checkPortOpen)" "端口自检时 nginx 起不来：临时配置删掉了（留着的话之后每次起 nginx 都多听这个端口）"

_ns=$(run_ns debian dead 'carpoolReloadNginx; echo "after=$?"'); _rc=$?
assert_equals "0" "${_rc}" "拼车重载 nginx 起不来：不退出（关拼车还要接着把账号放回去）"
assert_contains "${_ns}" "after=1" "拼车重载 nginx 起不来：把失败返回给调用方"

_ns=$(run_ns debian badconf 'updateNginxBlog 1' <<<$'10\n1\nhttps://example.test\n'); _rc=$?
assert_equals "1" "${_rc}" "302 配置让 nginx 起不来：退出码 1"
assert_contains "${_ns}" "backup restoreBackup" "302 配置让 nginx 起不来：配置回滚（之前 systemd 上走不到这里）"
assert_contains "${_ns}" "NGINX_302_ROLLED_BACK" "302 配置让 nginx 起不来：告诉用户已回滚"
assert_equals "up" "$(ls "${NS_DIR}" | grep -x up)" "302 配置让 nginx 起不来：回滚后 nginx 重新起来了"
rm -rf "${NS_DIR}"

# run_csb SELECTION → 自定义安装 sing-box 到收尾，打印 handleNginx 的调用
run_csb() {
    env NS_FN="${NS_FN}" REG_FILE="$(pwd)/lib/protocol-registry.sh" bash -c '
        eval "${NS_FN}"
        source "${REG_FILE}"
        for f in echoContent t validateCustomInstallTokens chainRefuseCoreSwitch readLastInstallationConfig installAbortArm installAbortDisarm installTools initTLSNginxConfig installTLS \
            installSingBox installSingBoxService initSingBoxConfig cleanUp installCronTLS handleSingBox refreshSubscribeAfterInstall checkGFWStatue showAccounts; do eval "$f() { :; }"; done
        handleNginx() { echo "handleNginx $*"; }
        customSingBoxInstall' <<<"$1" 2>&1 | paste -sd'|' -
}
assert_equals "handleNginx stop" "$(run_csb 14)" "sing-box 只选 SS2022：没装 nginx，不去起它"
assert_equals "handleNginx stop" "$(run_csb 7,14)" "sing-box 选 7、14：同样不要证书，不去起 nginx"
assert_equals "handleNginx stop|handleNginx stop|handleNginx start" "$(run_csb 0,14)" "sing-box 选了要证书的协议：照常起 nginx"

# --- 链式与账号菜单的几处：抽真函数，注册表和 JSON 工具都用真的，只桩内核、探测与合并 ---
# 这些函数里的 heredoc 有顶格的 }，按下一个函数名截
ah_src() {
    local n
    for n in "$@"; do
        awk -v n="${n}" 'f && /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/ {exit} index($0, n "() {") == 1 {f=1} f' install.sh
    done
}
AH_NAMES="testChainConnection getExternalNodeById initExternalNodeFile updateChainKey configureProtocolChainRouting applyProtocolChainRouting generateProtocolChainRoute saveProtocolRoutingPreference writeChainEntryRoute writeChainInfoAtomic multiChainRestoreAccounts chainAccountAssignPorts chainAccountReadState chainAccountStateFile setupMultiChainEntry removeUser shareQrCode"
AH_FN=$(ah_src ${AH_NAMES})
assert_equals "$(wc -w <<<"${AH_NAMES}" | tr -d ' ')" "$(grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{$' <<<"${AH_FN}")" "链式与账号菜单：函数都抽到了"
AH_ROOT="${MOCK_ROOT}/ah.root"
AH_CONF="${AH_ROOT}/sing-box/conf"
AH_FRAG="${AH_CONF}/config"
ah_reset() {
    rm -rf "${AH_ROOT}"
    mkdir -p "${AH_FRAG}" "${AH_ROOT}/xray/conf"
    : >"${AH_ROOT}/sing-box/sing-box"
}
# run_ah CALL → 跑 CALL，stdin 照传；AH_MERGE_FAIL=1 让合并失败
run_ah() {
    env PROXY_AGENT_DIR="${AH_ROOT}" AH_FN="${AH_FN}" V2RAY_LANG=zh_CN AH_MERGE_FAIL="${AH_MERGE_FAIL:-}" bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh
        eval "${AH_FN}"
        echoContent() { printf "%s\n" "$2"; }
        _chainTCPProbe() { echo "PROBE $1:$2"; return 1; }
        singBoxMergeConfig() { [[ -z "${AH_MERGE_FAIL}" ]]; }
        reloadCore() { echo RELOAD; }
        listeningPorts() { :; }
        planAction() { return 1; }
        ensureSingBoxInstalled() { return 0; }
        '"$1" 2>&1
}

# 外部节点当唯一出口时，测链路测的是节点本身
ah_reset
printf '%s\n' '{"role":"entry","mode":"external_single","external_node_id":"n1"}' >"${AH_CONF}/chain_entry_info.json"
printf '%s\n' '{"nodes":[{"id":"n1","name":"hk","server":"node.example","server_port":8388}]}' >"${AH_CONF}/external_node_info.json"
_out=$(run_ah 'testChainConnection; echo "rc=$?"' </dev/null)
assert_contains "${_out}" "PROBE node.example:8388" "外部节点唯一出口（测链路）：探测的是节点的地址和端口"
assert_equals "0" "$(grep -c 'null' <<<"${_out}")" "外部节点唯一出口（测链路）：不再显示 null:null"
printf '%s\n' '{"nodes":[]}' >"${AH_CONF}/external_node_info.json"
_out=$(run_ah 'testChainConnection; echo "rc=$?"' </dev/null)
assert_contains "${_out}" "节点未找到" "外部节点唯一出口（测链路，节点已删）：说明找不到节点"
assert_equals "rc=1|0" "$(tail -n 1 <<<"${_out}")|$(grep -c 'PROBE' <<<"${_out}")" "外部节点唯一出口（测链路，节点已删）：返回 1，不去探测"

# 中继上更新密钥：说清楚怎么换，不说没配置
ah_reset
printf '%s\n' '{"role":"relay"}' >"${AH_CONF}/chain_relay_info.json"
_out=$(run_ah 'updateChainKey' </dev/null)
assert_contains "${_out}" "中继节点的密钥在配置时生成" "中继（更新密钥）：说明要重新配置中继"
assert_equals "0" "$(grep -c '未配置链式代理' <<<"${_out}")" "中继（更新密钥）：不打「未配置链式代理」"
ah_reset
_out=$(run_ah 'updateChainKey' </dev/null)
assert_contains "${_out}" "未配置链式代理" "没有链式配置（更新密钥）：照旧提示未配置"

# 按协议分流：外部节点唯一出口拒绝；能开能关；合并失败原样还原
ah_reset
printf '%s\n' '{"role":"entry","mode":"external_single"}' >"${AH_CONF}/chain_entry_info.json"
: >"${AH_FRAG}/chain_outbound.json"
_out=$(run_ah 'configureProtocolChainRouting; echo "rc=$?"' </dev/null)
assert_contains "${_out}" "外部节点当唯一出口时不支持按协议分流" "按协议分流（外部节点唯一出口）：拒绝并说明"
assert_equals "rc=1|no" "$(tail -n 1 <<<"${_out}")|$([[ -f "${AH_FRAG}/chain_route.json" ]] && echo yes || echo no)" "按协议分流（外部节点唯一出口）：返回 1，不写路由"

ah_routing_setup() {
    ah_reset
    printf '%s\n' '{"role":"entry","mode":"single_hop"}' >"${AH_CONF}/chain_entry_info.json"
    : >"${AH_FRAG}/chain_outbound.json"
    printf '%s\n' '{"inbounds":[]}' >"${AH_FRAG}/07_VLESS_vision_reality_inbounds.json"
    printf '%s\n' '{"route":{"final":"chain_outbound","default_domain_resolver":"google"}}' >"${AH_FRAG}/chain_route.json"
}
ah_routing_setup
_before=$(cat "${AH_FRAG}/chain_route.json" "${AH_CONF}/chain_entry_info.json")
_out=$(printf '1\ny\n' | AH_MERGE_FAIL=1 run_ah 'configureProtocolChainRouting; echo "rc=$?"')
assert_equals "rc=1|0" "$(tail -n 1 <<<"${_out}")|$(grep -c RELOAD <<<"${_out}")" "按协议分流（开启时合并失败）：返回 1，不重载"
assert_equals "${_before}" "$(cat "${AH_FRAG}/chain_route.json" "${AH_CONF}/chain_entry_info.json")" "按协议分流（开启时合并失败）：路由与状态逐字还原"
_out=$(printf '0\n' | run_ah 'configureProtocolChainRouting; echo "rc=$?"')
assert_equals "0" "$(grep -c '关闭按协议分流' <<<"${_out}")" "按协议分流（没开过）：菜单没有关闭项"
assert_equals "rc=1" "$(tail -n 1 <<<"${_out}")" "按协议分流（没开过）：输入 0 算选错"
_out=$(printf '1\ny\n' | run_ah 'configureProtocolChainRouting; echo "rc=$?"')
assert_equals "rc=0|1" "$(tail -n 1 <<<"${_out}")|$(grep -c RELOAD <<<"${_out}")" "按协议分流（开启）：成功并重载"
assert_equals 'direct|["VLESSReality"]|true' "$(jq -r '.route.final' "${AH_FRAG}/chain_route.json")|$(jq -c '.route.rules[0].inbound' "${AH_FRAG}/chain_route.json")|$(jq -r '.protocol_routing.enabled' "${AH_CONF}/chain_entry_info.json")" \
    "按协议分流（开启）：选中的协议走链路，其余直连，状态记下"
_before=$(cat "${AH_FRAG}/chain_route.json" "${AH_CONF}/chain_entry_info.json")
_out=$(printf '0\n' | AH_MERGE_FAIL=1 run_ah 'configureProtocolChainRouting; echo "rc=$?"')
assert_contains "${_out}" "0. 关闭按协议分流" "按协议分流（开过）：菜单有关闭项"
assert_equals "${_before}" "$(cat "${AH_FRAG}/chain_route.json" "${AH_CONF}/chain_entry_info.json")" "按协议分流（关闭时合并失败）：路由与状态逐字还原"
_out=$(printf '0\n' | run_ah 'configureProtocolChainRouting; echo "rc=$?"')
assert_equals "rc=0|1" "$(tail -n 1 <<<"${_out}")|$(grep -c RELOAD <<<"${_out}")" "按协议分流（关闭）：成功并重载"
assert_contains "${_out}" "按协议分流已关闭" "按协议分流（关闭）：告诉用户"
assert_equals 'chain_outbound|null|null' "$(jq -r '.route.final' "${AH_FRAG}/chain_route.json")|$(jq -c '.route.rules' "${AH_FRAG}/chain_route.json")|$(jq -c '.protocol_routing' "${AH_CONF}/chain_entry_info.json")" \
    "按协议分流（关闭）：路由写回全走链路，状态清掉"
: >"${AH_FRAG}/chain_bridge_inbound.json"
printf '%s\n' '{"role":"entry","mode":"single_hop","protocol_routing":{"enabled":true}}' >"${AH_CONF}/chain_entry_info.json"
printf '0\n' | run_ah 'configureProtocolChainRouting' >/dev/null
assert_equals '"chain_bridge_in"' "$(jq -c '.route.rules[0].inbound' "${AH_FRAG}/chain_route.json")" "按协议分流（关闭，有 Xray 桥）：路由带上桥的规则"

# 重新配置多链路：账号的出口映射带过去，指向没了的当场列出；结果必须过映射校验，否则 sing-box 整个合并失败
ah_multi_state() {
    jq -n '{role: "entry", mode: "multi_chain", chains: [{name: "a"}, {name: "b", bridge_port: 31120}], rules: [], default_chain: "direct"}' >"${AH_CONF}/chain_multi_info.json"
}
ah_reset; ah_multi_state
_out=$(run_ah 'multiChainCarriedAccounts='"'"'{"alice":"a","bob":"gone","carol":"direct","dan":"b"}'"'"'; multiChainRestoreAccounts "${CHAIN_MULTI_INFO}"; echo "rc=$?"; chainAccountReadState >/dev/null; echo "valid=$?"' </dev/null)
assert_equals '{"alice":"a","carol":"direct","dan":"b"}' "$(jq -cS '.accounts' "${AH_CONF}/chain_multi_info.json")" "多链路重配：指向还在的链路和直连的映射带上"
assert_contains "${_out}" "bob→gone" "多链路重配：指向没了的链路当场列出"
assert_contains "${_out}" "已带上 3 个账号" "多链路重配：说明带上了几个"
assert_contains "${_out}" "rc=0" "多链路重配：返回 0"
assert_contains "${_out}" "valid=0" "多链路重配：结果过映射校验（缺桥端口时不过，sing-box 就合并失败）"
assert_equals "31112|31120" "$(jq -r '[.chains[].bridge_port] | map(tostring) | join("|")' "${AH_CONF}/chain_multi_info.json")" "多链路重配：新被引用的链路分到空着的桥端口，已有的不变"
ah_reset; ah_multi_state
_before=$(cat "${AH_CONF}/chain_multi_info.json")
_out=$(run_ah 'multiChainRestoreAccounts "${CHAIN_MULTI_INFO}"; echo "rc=$?"' </dev/null)
assert_equals "rc=0|${_before}" "$(tail -n 1 <<<"${_out}")|$(cat "${AH_CONF}/chain_multi_info.json")" "多链路（首次配置，没有要带的映射）：文件不动"
# 走向导的真实分支：旧状态删掉之前要先记下映射
ah_reset
jq -n '{role: "entry", mode: "multi_chain", chains: [{name: "a", bridge_port: 31111}], accounts: {alice: "a"}}' >"${AH_CONF}/chain_multi_info.json"
printf '2\ny\n1\n' | run_ah 'setupMultiChainInteractive() { jq -n "{role: \"entry\", mode: \"multi_chain\", chains: [{name: \"a\"}]}" >"${CHAIN_MULTI_INFO}"; multiChainRestoreAccounts "${CHAIN_MULTI_INFO}"; }; setupMultiChainEntry' >/dev/null
assert_equals '{"alice":"a"}' "$(jq -c '.accounts' "${AH_CONF}/chain_multi_info.json")" "多链路向导（选重新配置）：账号的出口映射没丢"

# 删除用户要确认
ah_rm_setup() {
    ah_reset
    jq -n '{inbounds: [{settings: {clients: [{id: "u1", email: "alice-VLESS_TCP"}]}}]}' >"${AH_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
}
AH_RM='carpoolGuardAccountMenu() { return 1; }; applyAccountChangeAllProtocols() { echo "APPLY $*"; }; chainAccountForget() { :; }; readNginxSubscribe() { :; }; subscribe() { :; }; manageAccount() { echo MENU; }; configPath="${XRAY_CONF_DIR}/" coreKind=1 frontingType=02_VLESS_TCP_inbounds; removeUser'
ah_rm_setup
_out=$(printf '1\nn\n' | run_ah "${AH_RM}")
assert_equals "0|1|1" "$(grep -c APPLY <<<"${_out}")|$(grep -c '已取消' <<<"${_out}")|$(grep -c MENU <<<"${_out}")" "删除用户（答 n）：不删，回到菜单"
_out=$(printf '1\n\n' | run_ah "${AH_RM}")
assert_equals "0" "$(grep -c APPLY <<<"${_out}")" "删除用户（直接回车）：不删"
_out=$(run_ah "${AH_RM}" </dev/null)
assert_equals "0" "$(grep -c APPLY <<<"${_out}")" "删除用户（没有输入）：不删"
_out=$(printf '1\ny\n' | run_ah "${AH_RM}")
assert_contains "${_out}" "APPLY delName alice" "删除用户（答 y）：按名字删"
assert_contains "$(printf '1\ny\n' | run_ah 'read -r -p "$(t REMOVE_USER_CONFIRM alice)" x; printf "%s" "$(t REMOVE_USER_CONFIRM alice)"')" "确认删除用户 alice" "删除用户：确认提示点名"

# 二维码只在本机生成，分享链接不发给第三方
assert_equals "0" "$(grep -c 'qrserver' install.sh)" "二维码：脚本里没有第三方二维码服务"
ah_reset
assert_equals "" "$(run_ah 'qrencode() { echo QR; }; shareQrCode title vless://x' </dev/null)" "二维码：输出不是终端时什么都不打（订阅重建不用白画）"
assert_equals "13" "$(sed -n '/^defaultBase64Code() {/,/^}/p' install.sh | grep -cF 'shareQrCode "')" "二维码：账号页每种协议都接上了"
assert_equals "13" "$(sed -n '/^defaultBase64Code() {/,/^}/p' install.sh | grep -F 'shareQrCode "' | grep -cF '"$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"')" "二维码：账号页都画刚写进订阅的那条链接"
# run_db_qr ARGS... → 同 run_db，只把画二维码换成打印它拿到的链接
run_db_qr() {
    env PROXY_AGENT_DIR="${MOCK_ROOT}/sharecode.root" DB_FN="${DB_FN}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh
        eval "${DB_FN}"
        shareQrCode() { printf "QR:%s\n" "$2"; }
        coreKind=1; currentHost=example.org
        defaultBase64Code "$@"' _ "$@" 2>&1 | grep '^QR:'
}
db_reset
assert_equals "QR:$(run_db 1 trojan 443 tro-x pw123 >/dev/null 2>&1; tail -n 1 "${DB_SUB}/default/tro")" "$(db_reset; run_db_qr trojan 443 tro-x pw123)" "二维码（Trojan）：内容就是订阅里那条链接"
assert_contains "$(tail -n 1 "${DB_SUB}/default/tro")" "trojan://pw123@example.org:443" "二维码（Trojan）：订阅里确实是分享链接"
db_reset
_qr=$(run_db_qr vlesstcp 443 vl-x 0f3c8a4e-1b2d-4c5e-8f90-123456789abc)
assert_equals "QR:$(tail -n 1 "${DB_SUB}/default/vl")" "${_qr}" "二维码（VLESS）：内容就是订阅里那条链接"
assert_contains "${_qr}" "QR:vless://0f3c8a4e-1b2d-4c5e-8f90-123456789abc@example.org:443" "二维码（VLESS）：是未转义的原始链接，客户端才能识别"

# 进度显示：最后一步不超过总步数
AH_PROG=$(ah_src singBoxInstall)
_prog=$(env AH_PROG="${AH_PROG}" bash -c '
    eval "${AH_PROG}"
    for f in chainRefuseCoreSwitch readLastInstallationConfig installAbortArm installAbortDisarm installTools initTLSNginxConfig installTLS installSingBox installSingBoxService \
        initSingBoxConfig cleanUp installCronTLS handleSingBox handleXray handleNginx refreshSubscribeAfterInstall checkGFWStatue echoContent; do eval "$f() { :; }"; done
    showAccounts() { echo "$1/${totalProgress}"; }
    singBoxInstall' 2>&1)
assert_equals "9/9" "${_prog}" "sing-box 全量安装：最后一步是 9/9，不是 9/8"
rm -rf "${AH_ROOT}"

# --- 防火墙放行按「端口/协议」整条比对：443 是 8443 的子串，按子串查会把没放行的端口当成已放行 ---
AP_FN=$(sed -n '/^allowPort() {/,/^}/p;/^checkUFWAllowPort() {/,/^}/p' install.sh)
AP_DIR="${MOCK_ROOT}/allowport"
# run_ap FIREWALL EXISTING PORT [TYPE] → 桩出 ufw 或 iptables（netfilter-persistent）防火墙，EXISTING 是已放行的「端口/协议」；
# 打印 allowPort 真正下的放行命令与它的退出码。nftables 装着但没在跑（nft 在 PATH 里、服务 inactive）
run_ap() {
    rm -rf "${AP_DIR}" && mkdir -p "${AP_DIR}/bin"
    printf '#!/bin/sh\nexit 1\n' >"${AP_DIR}/bin/nft" && chmod +x "${AP_DIR}/bin/nft"
    tr ' ' '\n' <<<"$2" | grep . >"${AP_DIR}/rules"
    env AP_FN="${AP_FN}" AP_DIR="${AP_DIR}" FW="$1" PATH="${AP_DIR}/bin:${PATH}" bash -c '
        set -o pipefail
        eval "${AP_FN}"
        echoContent() { :; }
        netfilter-persistent() { :; }
        rc-update() { return 1; }
        if [[ "${FW}" == ufw ]]; then
            dpkg() { echo "ii  ufw  0.36.2"; }
        else
            dpkg() { echo "ii  netfilter-persistent  1.0.20"; }
        fi
        systemctl() {
            [[ "$1 $2" == "status netfilter-persistent" ]] && { echo "Active: active (exited)"; return 0; }
            return 3
        }
        ufw() {
            if [[ "$1" == status ]]; then
                # 一次写完：分两次写时 grep -q 可能先退出，SIGPIPE 被忽略的环境里 sed 的报错会混进断言
                printf "Status: active\n%s\n" "$(sed "s/$/ ALLOW Anywhere/" "${AP_DIR}/rules")"
            else
                echo "ufw $*"
                echo "$2" >>"${AP_DIR}/rules"
            fi
        }
        iptables() {
            local spec="$*"
            [[ "$1" == -C ]] && { grep -qx -- "${spec#-C }" "${AP_DIR}/iptables" 2>/dev/null; return; }
            [[ "$1" == -L ]] && { sed "s/^/ACCEPT /" "${AP_DIR}/iptables" 2>/dev/null; return 0; }
            [[ "$1" == -I ]] && { echo "iptables $*"; echo "${spec#-I }" >>"${AP_DIR}/iptables"; }
            return 0
        }
        while read -r r; do
            [[ "${FW}" == iptables ]] && echo "INPUT -p ${r#*/} --dport ${r%/*} -m comment --comment allow ${r}(Proxy-agent) -j ACCEPT" >>"${AP_DIR}/iptables"
        done <"${AP_DIR}/rules"
        allowPort "$0" "$1"
        echo "rc=$?"' "$3" "${4:-}" 2>&1 | paste -sd'|' -
}
assert_equals "ufw allow 443/tcp|rc=0" "$(run_ap ufw "8443/tcp" 443)" "ufw：已放行 8443/tcp 时照样放行 443/tcp"
assert_equals "ufw allow 443/udp|rc=0" "$(run_ap ufw "8443/udp 443/tcp" 443 udp)" "ufw：已放行 8443/udp 与 443/tcp 时照样放行 443/udp"
assert_equals "ufw allow 30000:30020/udp|rc=0" "$(run_ap ufw "" 30000:30020 udp)" "ufw：端口区间照常放行"
assert_equals "iptables -I INPUT -p tcp --dport 443 -m comment --comment allow 443/tcp(Proxy-agent) -j ACCEPT|rc=0" \
    "$(run_ap iptables "8443/tcp" 443)" "iptables：已放行 8443/tcp 时照样放行 443/tcp（nftables 装着没在跑，不走它）"
assert_equals "rc=0" "$(run_ap iptables "443/tcp" 443)" "iptables：同一条规则已在就不重复加"

# --- 装了 ufw 的机器不装 iptables-persistent：两包互斥，apt -y 会卸掉 ufw，整机防火墙失效 ---
BT_FN=$(sed -n '/^installBaseTools() {/,/^}/p' install.sh)
# run_bt UFW_STATE → 桩掉包管理器（记下要装的包）与 dpkg-query（ufw 的安装状态），打印 installBaseTools 要装的包里跟防火墙有关的
run_bt() {
    rm -rf "${AP_DIR}" && mkdir -p "${AP_DIR}"
    env BT_FN="${BT_FN}" AP_DIR="${AP_DIR}" UFW_STATE="$1" bash -c '
        eval "${BT_FN}"
        for f in echoContent t ensureCronService ensureAlpineProcps sleep debconf-set-selections; do eval "$f() { :; }"; done
        pgrep() { return 1; }
        dpkg-query() { [[ -n "${UFW_STATE}" ]] && printf "%s" "${UFW_STATE}"; [[ -n "${UFW_STATE}" ]]; }
        instRec() { shift 2; echo "$*" >>"${AP_DIR}/installed"; }
        release=debian upgrade=true installType="instRec -y install" PROXY_AGENT_DIR="${AP_DIR}"
        installBaseTools
        grep -E "iptables|ufw" "${AP_DIR}/installed" 2>/dev/null' 2>&1 | paste -sd'|' -
}
if command -v netfilter-persistent >/dev/null 2>&1; then
    echo -e "${YELLOW}跳过 iptables-persistent 的两条：本机已有 netfilter-persistent，installBaseTools 不会去装${NC}"
else
    assert_equals "" "$(run_bt "install ok installed")" "装了 ufw：installBaseTools 不装 iptables-persistent"
    assert_equals "iptables-persistent" "$(run_bt "")" "没装 ufw：照常装 iptables-persistent（端口跳跃靠它活过重启）"
fi

# --- 端口跳跃菜单认 iptables：find | grep -q 在 pipefail 下会因 SIGPIPE 误判没有 ---
PH_FN=$(sed -n '/^portHoppingMenu() {/,/^}/p' install.sh)
mkdir -p "${AP_DIR}/bin" && printf '#!/bin/sh\nexit 0\n' >"${AP_DIR}/bin/iptables" && chmod +x "${AP_DIR}/bin/iptables"
phOut=$(env PH_FN="${PH_FN}" PATH="${AP_DIR}/bin:${PATH}" bash -c '
    set -o pipefail
    eval "${PH_FN}"
    for f in echoContent readPortHopping addPortHopping deletePortHoppingRules carpoolRefreshSubscribe; do eval "$f() { :; }"; done
    for i in $(seq 1 20); do echo 3 | portHoppingMenu hysteria2 >/dev/null 2>&1 || { echo "exit at try ${i}"; break; }; done
    echo done' 2>&1)
assert_equals "done" "${phOut}" "端口跳跃菜单：有 iptables 时连进 20 次都不误判退出"

# --- cron 不装推荐包（Debian 上会拉进常驻 25 端口的 exim4）；不再为 ping6 换掉系统的 iputils-ping ---
mkdir -p "${AP_DIR}"
: >"${AP_DIR}/installed"
btPkgs=$(env BT_FN="${BT_FN}" AP_DIR="${AP_DIR}" bash -c '
    eval "${BT_FN}"
    for f in echoContent t ensureCronService ensureAlpineProcps sleep debconf-set-selections; do eval "$f() { :; }"; done
    pgrep() { return 1; }
    crontab() { return 1; }
    ping6() { return 2; }
    dpkg-query() { return 1; }
    instRec() { shift 2; echo "$*" >>"${AP_DIR}/installed"; }
    release=debian upgrade=true installType="instRec -y install" PROXY_AGENT_DIR="${AP_DIR}"
    installBaseTools
    grep -E "cron|ping" "${AP_DIR}/installed"' 2>&1 | paste -sd'|' -)
assert_equals "--no-install-recommends cron" "${btPkgs}" "installBaseTools：cron 不带推荐包，也不再装 inetutils-ping"

# --- 确认一律走 isYesInput（裸比较不认 Y / yes，同一句提示在不同菜单行为不一样）；脚本只以 root 跑，不用 sudo（主机名解析不了时它还会打噪音） ---
assert_equals "0" "$(grep -cE '(==|!=) "[Yy]"' install.sh)" "install.sh 里没有裸的 y / Y 比较"
assert_equals "0" "$(grep -cE '(^|[^A-Za-z_-])sudo( |$)' install.sh)" "install.sh 里没有 sudo"

# --- qrencode 的包名按发行版来：Alpine 没有叫 qrencode 的包，装错名字是静默失败，账号页一直没有二维码 ---
# run_bt_qr RELEASE → 本机有没有 qrencode 都当没有，打印 installBaseTools 要装的跟二维码有关的包
run_bt_qr() {
    : >"${AP_DIR}/installed"
    env BT_FN="${BT_FN}" AP_DIR="${AP_DIR}" RELEASE="$1" bash -c '
        eval "${BT_FN}"
        for f in echoContent t ensureCronService ensureAlpineProcps sleep debconf-set-selections; do eval "$f() { :; }"; done
        pgrep() { return 1; }
        dpkg-query() { return 1; }
        qrencode() { return 127; }
        instRec() { shift 2; echo "$*" >>"${AP_DIR}/installed"; }
        release="${RELEASE}" upgrade=true installType="instRec -y install" PROXY_AGENT_DIR="${AP_DIR}"
        installBaseTools
        grep qrencode "${AP_DIR}/installed"' 2>&1 | paste -sd'|' -
}
assert_equals "libqrencode-tools" "$(run_bt_qr alpine)" "installBaseTools：Alpine 装 libqrencode-tools"
assert_equals "qrencode" "$(run_bt_qr debian)" "installBaseTools：其他发行版装 qrencode"

# --- 端口跳跃只给 Hysteria2；加规则时不放行区间（INPUT 看到的是 DNAT 之后的目标端口，那条放行匹配不到） ---
MT_FN=$(sed -n '/^manageTuic() {/,/^}/p;/^manageHysteria() {/,/^}/p' install.sh)
MT_DIR="${MOCK_ROOT}/managehop"
mkdir -p "${MT_DIR}"
: >"${MT_DIR}/06_hysteria2_inbounds.json"
: >"${MT_DIR}/09_tuic_inbounds.json"
run_mt() {
    env MT_FN="${MT_FN}" MT_DIR="${MT_DIR}" bash -c '
        eval "${MT_FN}"
        singBoxConfigPath="${MT_DIR}/" SINGBOX_FRAGMENT_DIR="${MT_DIR}"
        for f in echoContent singBoxTuicInstall singBoxHysteria2Install unInstallSingBox; do eval "$f() { :; }"; done
        portHoppingMenu() { echo "hop $1"; }
        echo 3 | "$0"' "$1" 2>&1
}
assert_equals "" "$(run_mt manageTuic)" "TUIC 菜单：没有端口跳跃入口（三种订阅都带不了区间，服务端 DNAT 白开）"
assert_equals "hop hysteria2" "$(run_mt manageHysteria)" "Hysteria2 菜单：端口跳跃入口还在"

AH_FN=$(sed -n '/^addPortHopping() {/,/^}/p' install.sh)
ahOut=$(env AH_FN="${AH_FN}" bash -c '
    eval "${AH_FN}"
    echoContent() { :; }
    t() { :; }
    allowPort() { echo "allowPort $*"; }
    iptables() { echo "iptables $*"; }
    iptables-save() { echo "Proxy-agent_hysteria2_portHopping"; }
    netfilter-persistent() { :; }
    release=debian
    echo 30000-30010 | addPortHopping hysteria2 443' 2>&1)
assert_equals "iptables -t nat -A PREROUTING -p udp --dport 30000:30010 -m comment --comment Proxy-agent_hysteria2_portHopping -j DNAT --to-destination :443" \
    "${ahOut}" "加端口跳跃：只写 DNAT，不放行区间"

mkdir -p "${AP_DIR}/bin" && printf '#!/bin/sh\nexit 0\n' >"${AP_DIR}/bin/iptables" && chmod +x "${AP_DIR}/bin/iptables"
phType=$(env PH_FN="${PH_FN}" PATH="${AP_DIR}/bin:${PATH}" bash -c '
    eval "${PH_FN}"
    for f in echoContent addPortHopping deletePortHoppingRules carpoolRefreshSubscribe; do eval "$f() { :; }"; done
    readPortHopping() { echo "$1"; }
    printf "x\n3\n" | portHoppingMenu hysteria2' 2>&1 | paste -sd' ' -)
assert_equals "hysteria2 hysteria2" "${phType}" "端口跳跃菜单：选错重来时协议类型不丢"

# --- doctor 查时钟：容差最小的 SS2022 是 30 秒，两台机器各偏一半就到头，15 秒起告警；只告警，取不到对时源就跳过 ---
CK_FN=$(sed -n '/^_doctorCheckClock() {/,/^}/p' install.sh)
# run_ck TRACE_TS LOCAL_TS IN_CONTAINER → 桩掉 curl / date / systemd-detect-virt，打印 状态 明细键 差值
run_ck() {
    env CK_FN="${CK_FN}" TS="$1" NOW="$2" CT="${3:-}" bash -c '
        eval "${CK_FN}"
        t() { echo "$*"; }
        _doctorRow() { echo "$2 $3"; }
        curl() { [[ -n "${TS}" ]] || return 7; printf "fl=1\nts=%s.000\nip=1.2.3.4\n" "${TS}"; }
        date() { echo "${NOW}"; }
        systemd-detect-virt() { [[ -n "${CT}" ]]; }
        _doctorCheckClock' 2>&1
}
assert_equals "pass DOCTOR_DETAIL_CLOCK_OK 14" "$(run_ck 1000 1014)" "时钟：快 14 秒不告警"
assert_equals "pass DOCTOR_DETAIL_CLOCK_OK 14" "$(run_ck 1014 1000)" "时钟：慢 14 秒不告警"
assert_equals "warn DOCTOR_DETAIL_CLOCK_DRIFT 15" "$(run_ck 1000 1015)" "时钟：差 15 秒告警"
assert_equals "warn DOCTOR_DETAIL_CLOCK_DRIFT 300" "$(run_ck 1300 1000)" "时钟：慢的方向一样告警"
assert_equals "warn DOCTOR_DETAIL_CLOCK_DRIFT_CONTAINER 300" "$(run_ck 1000 1300 yes)" "时钟：容器里提示去宿主机校"
assert_equals "skip unreachable / timeout" "$(run_ck "" 1000)" "时钟：取不到对时源就跳过，不告警"

# --- 已有证书也要对得上私钥：不查的话写完配置内核才起不来，那时服务已停 ---
IT_FN=$(sed -n '/^installTLS() {/,/^}/p' install.sh)
IT_DIR="${MOCK_ROOT}/installtls"
mkdir -p "${IT_DIR}/tls"
echo cert >"${IT_DIR}/tls/a.example.crt"
echo key >"${IT_DIR}/tls/a.example.key"
# run_it MATCH_RC → verifyCertKeyMatch 返回 MATCH_RC；走完打印 finished 和退出码
run_it() {
    env IT_FN="${IT_FN}" IT_DIR="${IT_DIR}" MATCH_RC="$1" HOME="${IT_DIR}" bash -c '
        eval "${IT_FN}"
        for f in echoContent readAcmeTLS renewalTLS verifyCertExpiry; do eval "$f() { :; }"; done
        verifyCertKeyMatch() { return "${MATCH_RC}"; }
        TLS_DIR="${IT_DIR}/tls" domain=a.example lastInstallationConfig=true
        installTLS 3
        echo finished' 2>&1
    echo "rc=$?"
}
assert_equals "finished|rc=0" "$(run_it 0 | paste -sd'|' -)" "已有证书且匹配：安装接着走"
assert_equals "rc=1" "$(run_it 1 | paste -sd'|' -)" "已有证书与私钥不匹配：退出（还在保护区间内，旧服务会拉回来）"

# --- 协议卸载带走跳跃规则：iptables 按标记删；firewalld 只能按目标端口认，读不到端口就不动 ---
RH_FN=$(sed -n '/^readPortHopping() {/,/^}/p;/^deletePortHoppingRules() {/,/^}/p;/^removeProtocolPortHopping() {/,/^}/p' install.sh)
RH_DIR="${MOCK_ROOT}/hoprm"
mkdir -p "${RH_DIR}"
echo '{"inbounds":[{"listen_port":443}]}' >"${RH_DIR}/06.json"
# run_rh_ipt TYPE FRAGMENT → iptables 桩：第 2、4 条是 hysteria2 的跳跃规则；打印删除与保存的调用
run_rh_ipt() {
    env RH_FN="${RH_FN}" bash -c '
        eval "${RH_FN}"
        iptables-save() { echo "-A PREROUTING -p udp -m udp --dport 30000:30010 -m comment --comment Proxy-agent_hysteria2_portHopping -j DNAT --to-destination :443"; }
        iptables() {
            if [[ "$*" == *--line-numbers* ]]; then
                printf "1 DNAT mine\n2 DNAT /* Proxy-agent_hysteria2_portHopping */\n3 DNAT mine\n4 DNAT /* Proxy-agent_hysteria2_portHopping */\n"
            else
                echo "iptables $*"
            fi
        }
        exec 3>&1
        netfilter-persistent() { echo "persist $*" >&3; }
        release=debian
        removeProtocolPortHopping "$0" "$1"' "$1" "$2" 2>&1 | paste -sd'|' -
}
assert_equals "iptables -t nat -D PREROUTING 4|iptables -t nat -D PREROUTING 2|persist save" "$(run_rh_ipt hysteria2 "${RH_DIR}/06.json")" \
    "iptables：只删带标记的跳跃规则，行号降序，再保存"
assert_equals "iptables -t nat -D PREROUTING 4|iptables -t nat -D PREROUTING 2|persist save" "$(run_rh_ipt hysteria2 "${RH_DIR}/missing.json")" \
    "iptables：片段没了也能按标记收"
assert_equals "" "$(run_rh_ipt tuic "${RH_DIR}/06.json")" "iptables：这个协议没有跳跃规则就什么都不动"
# run_rh_fw FRAGMENT → firewalld 桩：两条指向 443 的跳跃、一条用户自己指向 4430 的转发；删除调用打到 stderr（真代码把 stdout 丢了）
run_rh_fw() {
    env RH_FN="${RH_FN}" bash -c '
        eval "${RH_FN}"
        systemctl() { return 0; }
        firewall-cmd() {
            case "$*" in
                --list-forward-ports) printf "port=30000:proto=udp:toport=443:toaddr=\nport=30001:proto=udp:toport=443:toaddr=\nport=8080:proto=tcp:toport=4430:toaddr=\n" ;;
                *remove-forward-port*) echo "$*" >&2 ;;
            esac
        }
        release=centos
        removeProtocolPortHopping hysteria2 "$0"' "$1" 2>&1 | paste -sd'|' -
}
assert_equals "--permanent --remove-forward-port=port=30000:proto=udp:toport=443|--permanent --remove-forward-port=port=30001:proto=udp:toport=443" \
    "$(run_rh_fw "${RH_DIR}/06.json")" "firewalld：只删指向这个协议端口的转发，4430 不是 443"
assert_equals "" "$(run_rh_fw "${RH_DIR}/missing.json")" "firewalld：读不到目标端口就不动（空端口的 toport= 会匹配到用户自己的转发）"

# --- 卸载收回带标记的放行：没标记的是用户自己的；ufw、firewalld 认不出，列出来不动 ---
RF_FN=$(sed -n '/^sshListenPorts() {/,/^}/p;/^isOwnRuleOnSshPort() {/,/^}/p;/^removeOwnFirewallRules() {/,/^}/p' install.sh)
# run_rf IPT_LIST NFT_LIST [SSH_LISTEN] [SSH_CONFIG] [SSH_CONNECTION] → 桩掉 iptables / nft / ss / sshd，打印删除、保存与保留提示
run_rf() {
    env -u SSH_CONNECTION RF_FN="${RF_FN}" IPT="$1" NFT="$2" SSH_LISTEN="${3:-}" SSH_CONFIG="${4:-}" ${5:+SSH_CONNECTION="$5"} bash -c '
        eval "${RF_FN}"
        t() { echo "$1"; }
        echoContent() { echo "$2"; }
        ss() { [[ -n "${SSH_LISTEN}" ]] && echo "LISTEN 0 128 0.0.0.0:${SSH_LISTEN} 0.0.0.0:* users:((\"sshd\",pid=1,fd=3))"; echo "LISTEN 0 128 0.0.0.0:443 0.0.0.0:* users:((\"xray\",pid=2,fd=3))"; }
        sshd() { [[ -n "${SSH_CONFIG}" ]] && printf "port %s\naddressfamily any\n" "${SSH_CONFIG}"; return 0; }
        iptables() { if [[ "$*" == *--line-numbers* ]]; then printf "%b" "${IPT}"; else echo "iptables $*"; fi; }
        exec 3>&1
        netfilter-persistent() { echo "persist $*" >&3; }
        nft() {
            case "$*" in
                "list chain inet filter input") ;;
                "-a list chain inet filter input") printf "%b" "${NFT}" ;;
                *) echo "nft $*" ;;
            esac
        }
        systemctl() { return 1; }
        removeOwnFirewallRules' 2>&1 | paste -sd'|' -
}
RF_IPT='num target\n1 ACCEPT tcp dpt:22 /* ssh */\n2 ACCEPT udp dpt:443 /* allow 443/udp(Proxy-agent) */\n3 ACCEPT tcp dpt:80\n4 ACCEPT tcp dpt:443 /* allow 443/tcp(Proxy-agent) */\n'
RF_NFT='\t\ttcp dport 22 accept comment "mine" # handle 3\n\t\tip saddr 0.0.0.0/0 tcp dport 443 counter packets 0 bytes 0 accept comment "allow 443/tcp(Proxy-agent)" # handle 7\n'
assert_equals "iptables -D INPUT 4|iptables -D INPUT 2|persist save|nft delete rule inet filter input handle 7" "$(run_rf "${RF_IPT}" "${RF_NFT}")" \
    "卸载：iptables、nft 里带标记的放行都收回，行号降序，用户自己的规则不动"
assert_equals "" "$(run_rf 'num target\n1 ACCEPT tcp dpt:22 /* ssh */\n' '\t\ttcp dport 22 accept comment "mine" # handle 3\n')" "卸载：没有带标记的规则就不删也不保存"
RF_IPT_SSH='num target\n1 ACCEPT tcp dpt:2222 /* allow 2222/tcp(Proxy-agent) */\n2 ACCEPT tcp dpt:443 /* allow 443/tcp(Proxy-agent) */\n3 ACCEPT udp dpt:2222 /* allow 2222/udp(Proxy-agent) */\n'
RF_NFT_SSH='\t\tip saddr 0.0.0.0/0 tcp dport 2222 counter accept comment "allow 2222/tcp(Proxy-agent)" # handle 8\n\t\tip saddr 0.0.0.0/0 tcp dport 443 counter accept comment "allow 443/tcp(Proxy-agent)" # handle 9\n'
RF_KEEP="iptables -D INPUT 3|iptables -D INPUT 2| ---> UNINSTALL_KEEP_SSH_RULE|persist save| ---> UNINSTALL_KEEP_SSH_RULE|nft delete rule inet filter input handle 9"
assert_equals "${RF_KEEP}" "$(run_rf "${RF_IPT_SSH}" "${RF_NFT_SSH}" 2222)" "卸载：sshd 在听的端口的放行留着（只留 tcp），其余照收"
assert_equals "${RF_KEEP}" "$(run_rf "${RF_IPT_SSH}" "${RF_NFT_SSH}" "" 2222)" "卸载：ss 看不到 sshd（ssh.socket）时按 sshd -T 认"
assert_equals "${RF_KEEP}" "$(run_rf "${RF_IPT_SSH}" "${RF_NFT_SSH}" "" "" "1.2.3.4 5555 10.0.0.1 2222")" "卸载：这条 SSH 连接自己的端口也算"

RL_FN=$(sed -n '/^reportUninstallLeftovers() {/,/^}/p' install.sh)
# run_rl HAVE → HAVE 里的工具算装着 / 在跑；打印列出来的键。nginx 源的两个路径没法桩，这里只看其余几项
run_rl() {
    env RL_FN="${RL_FN}" HAVE=" $1 " bash -c '
        eval "${RL_FN}"
        t() { echo "$1"; }
        echoContent() { echo "$2"; }
        command() { [[ "${HAVE}" == *" $2 "* ]]; }
        ufw() { echo "Status: active"; }
        systemctl() { [[ "${HAVE}" == *" firewalld "* ]]; }
        firewall-cmd() { [[ "${HAVE}" == *" masq "* ]]; }
        semanage() { echo "/etc/Proxy-agent/xray/xray all files bin_t"; }
        reportUninstallLeftovers' 2>&1 | paste -sd' ' -
}
assert_contains "$(run_rl "ufw")" "UNINSTALL_LEFT_UFW" "卸载结尾：ufw 在用就列出它的放行"
assert_contains "$(run_rl "firewalld masq")" "UNINSTALL_LEFT_FIREWALLD" "卸载结尾：firewalld 在跑就列出它的放行"
assert_contains "$(run_rl "firewalld masq")" "UNINSTALL_LEFT_MASQUERADE" "卸载结尾：masquerade 开着就列出来"
assert_contains "$(run_rl "semanage")" "UNINSTALL_LEFT_SELINUX" "卸载结尾：SELinux 里登记过就列出来"
assert_contains "$(run_rl "nginx")" "UNINSTALL_LEFT_NGINX" "卸载结尾：nginx 软件包还在就说一声"
assert_equals "no" "$(run_rl "" | grep -qE 'UFW|FIREWALLD|MASQUERADE|SELINUX|LEFT_NGINX( |$)' && echo yes || echo no)" "卸载结尾：没有的东西不列"

# --- 安装走到这些提示时服务已停，输错要重问：退出会把整机留在断线状态 ---
RA_FN=$(sed -n '/^readInstallAccount() {/,/^}/p' install.sh)
run_ra() {
    printf "$1" | env RA_FN="${RA_FN}" bash -c '
        eval "${RA_FN}"
        echoContent() { :; }
        readInstallAccount "echo aaaaaaaa-0000-4000-8000-000000000000"
        echo "${uuid}|${customEmail}"' 2>&1
}
assert_equals "aaaaaaaa-0000-4000-8000-000000000000|alice" "$(run_ra 'not-a-uuid\n\nbad name!\nalice\n')" "UUID、用户名输错都重问，改对后照常往下走"
assert_equals "11111111-2222-3333-4444-555555555555|11111111-VLESS_TCP/TLS_Vision" "$(run_ra '11111111-2222-3333-4444-555555555555\n\n')" "合法 UUID 照收，用户名回车取默认"
assert_equals "aaaaaaaa-0000-4000-8000-000000000000|aaaaaaaa-VLESS_TCP/TLS_Vision" "$(run_ra '')" "stdin 关了也不空转：两项都取默认"

RP_FN=$(sed -n '/^randomPathFunction() {/,/^}/p' install.sh)
assert_equals "valid1" "$(printf 'ab\nvalid1\n' | env RP_FN="${RP_FN}" bash -c '
    eval "${RP_FN}"
    echoContent() { :; }
    currentPath= lastInstallationConfig=
    randomPathFunction
    echo "${currentPath}"' 2>&1 | tail -n 1)" "path 输错重问，不退出"

SS_FN=$(sed -n '/^readValidPort() {/,/^}/p;/^initSS2022Config() {/,/^}/p' install.sh)
assert_equals "23456" "$(printf 'abc\n70000\n23456\n\n' | env SS_FN="${SS_FN}" bash -c '
    eval "${SS_FN}"
    echoContent() { :; }
    t() { :; }
    allowPort() { :; }
    singBoxConfigPath=/nonexistent/
    initSS2022Config
    echo "${ss2022Port}"' 2>&1 | tail -n 1)" "SS2022 端口输错重问，不退出"

RDT_FN=$(sed -n '/^realityDestBehindCloudflare() {/,/^}/p;/^checkRealityDest() {/,/^}/p;/^realityDestList() {/,/^}/p;/^pickRandomDest() {/,/^}/p;/^initRealityClientServersName() {/,/^}/p' install.sh)
# run_rd_typed INPUT CF_HOSTS → 手输 Reality 目标；打印最后定下的 目标:端口
run_rd_typed() {
    printf "$1" | env RDT_FN="${RDT_FN}" CF="$2" bash -c '
        eval "${RDT_FN}"
        echoContent() { :; }
        t() { echo "$1"; }
        isYesInput() { [[ "${1,,}" == y ]]; }
        isValidDomain() { [[ "$1" != *"!"* ]]; }
        curl() { local u="${*: -1}"; u=${u#https://}; u=${u%%/*}; [[ " ${CF} " == *" ${u} "* ]] && echo "visit_scheme=https"; return 0; }
        realityServerName= domain= lastInstallationConfig=
        initRealityClientServersName >/dev/null 2>&1
        echo "${realityServerName}:${realityDomainPort}"' 2>&1
}
assert_equals "ok.example:443" "$(run_rd_typed 'bad!name\nok.example\n' "")" "Reality 目标：格式不对重问，不退出"
assert_equals "ok.example:443" "$(run_rd_typed 'cf.example\nn\nok.example\n' "cf.example")" "Reality 目标：挂 Cloudflare 答否重问，不退出"
assert_equals "ok.example:8443" "$(run_rd_typed 'cf.example:9443\nn\nok.example:8443\n' "cf.example")" "Reality 目标：重问后端口跟新输入走，不留上一次的"
assert_equals "cf.example:443" "$(run_rd_typed 'cf.example\ny\n' "cf.example")" "Reality 目标：挂 Cloudflare 答是照用"
assert_equals "no" "$(run_rd_typed 'cf.example\n' "cf.example" | grep -q '^cf\.example:' && echo yes || echo no)" "Reality 目标：确认时 stdin 关了算答否，回车随机不空转"

# --- Xray 机上卸 Hysteria2：片段里还有链式的入站就留着 sing-box，不能把链式的片段、状态文件连二进制一起删 ---
US_FN=$(sed -n '/^unInstallSingBox() {/,/^}/p;/^singBoxFragmentsHaveInbounds() {/,/^}/p' install.sh)
US_DIR="${MOCK_ROOT}/uninstallsb"
# run_us WITH_CHAIN [NODES] → 造一台 Xray 机：旁挂 6，WITH_CHAIN 非空时再有链式入口的桥片段与状态文件，NODES 是外部节点清单；
# 卸掉 6 后打印 sing-box 目录里还剩什么
run_us() {
    rm -rf "${US_DIR}" && mkdir -p "${US_DIR}/sing-box/conf/config"
    : >"${US_DIR}/sing-box/sing-box"
    echo '{"inbounds":[{"type":"hysteria2","tag":"hy2"}]}' >"${US_DIR}/sing-box/conf/config/06_hysteria2_inbounds.json"
    echo '{"inbounds":[{"type":"hysteria2"}]}' >"${US_DIR}/sing-box/conf/config.json"
    if [[ -n "$1" ]]; then
        echo '{"inbounds":[{"type":"socks","tag":"chain_bridge_in"}]}' >"${US_DIR}/sing-box/conf/config/chain_bridge_inbound.json"
        echo '{"role":"entry"}' >"${US_DIR}/sing-box/conf/chain_entry_info.json"
    fi
    [[ -n "$2" ]] && echo "$2" >"${US_DIR}/sing-box/conf/external_node_info.json"
    mkdir -p "${US_DIR}/etc/systemd/system" "${US_DIR}/etc/init.d"
    : >"${US_DIR}/etc/systemd/system/sing-box.service"
    : >"${US_DIR}/etc/init.d/sing-box"
    env US_FN="${US_FN}" US_DIR="${US_DIR}" bash -c '
        SINGBOX_DIR="${US_DIR}/sing-box" SINGBOX_BIN="${US_DIR}/sing-box/sing-box" SINGBOX_CONF_DIR="${US_DIR}/sing-box/conf"
        SINGBOX_FRAGMENT_DIR="${US_DIR}/sing-box/conf/config" SINGBOX_MERGED_CONFIG="${US_DIR}/sing-box/conf/config.json"
        EXTERNAL_NODE_FILE="${SINGBOX_CONF_DIR}/external_node_info.json"
        singBoxConfigPath="${SINGBOX_FRAGMENT_DIR}/"
        eval "${US_FN}"
        for f in echoContent t handleSingBox singBoxAutostart refreshSubscribeAfterInstall rm_service removeProtocolPortHopping; do eval "$f() { :; }"; done
        readInstallType() { singBoxConfigPath=; [[ -f "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" ]] && singBoxConfigPath="${SINGBOX_FRAGMENT_DIR}/"; }
        rm() { local a=() x; for x in "$@"; do a+=("${x/#\/etc\//${US_DIR}/etc/}"); done; command rm "${a[@]}"; }
        unInstallSingBox hysteria2
        cd "${SINGBOX_DIR}" && find . -type f | sort | paste -sd" " -' 2>&1
}
assert_equals "./conf/chain_entry_info.json ./conf/config/chain_bridge_inbound.json ./sing-box" "$(run_us chain)" \
    "Xray 机上卸 Hysteria2：链式的桥片段、入口状态与 sing-box 二进制都留着"
assert_equals "" "$(run_us "")" "Xray 机上卸 Hysteria2、没有别的入站：sing-box 整个删掉"
assert_equals "" "$(cd "${US_DIR}/etc" && find . -type f)" "没有别的入站：systemd 单元和 OpenRC 服务脚本都删掉"
US_NODES='{"nodes":[{"id":"n1","password":"secret"}]}'
assert_equals "./conf/external_node_info.json" "$(run_us "" "${US_NODES}")" "卸掉最后一个入站：存着的外部节点留下，其余全删"
assert_equals "secret" "$(jq -r '.nodes[0].password' "${US_DIR}/sing-box/conf/external_node_info.json")" "卸掉最后一个入站：节点内容原样"
assert_equals "" "$(run_us "" '{"nodes":[]}')" "外部节点清单是空的：照样整个删掉，不留空目录之外的东西"
assert_equals "./conf/chain_entry_info.json ./conf/config/chain_bridge_inbound.json ./conf/external_node_info.json ./sing-box" \
    "$(run_us chain "${US_NODES}")" "还有链式入站：外部节点清单和其余状态一样留着"

# --- Xray 带域名重装换了域名：旁挂的 6 / 9 跟着换证书，不然按新域名校验必失败 ---
SC_FN=$(sed -n '/^syncSidecarTlsDomain() {/,/^}/p' install.sh)
SC_DIR="${MOCK_ROOT}/sidecarcert"
rm -rf "${SC_DIR}" && mkdir -p "${SC_DIR}/tls" "${SC_DIR}/config"
: >"${SC_DIR}/tls/new.example.crt"
: >"${SC_DIR}/tls/new.example.key"
for f in 06_hysteria2_inbounds 09_tuic_inbounds; do
    jq -n --arg d "${SC_DIR}/tls/old.example" '{inbounds: [{type: "x", tls: {enabled: true, server_name: "old.example", certificate_path: "\($d).crt", key_path: "\($d).key"}}]}' \
        >"${SC_DIR}/config/${f}.json"
done
env SC_FN="${SC_FN}" SC_DIR="${SC_DIR}" bash -c '
    source lib/json-utils.sh
    eval "${SC_FN}"
    TLS_DIR="${SC_DIR}/tls" SINGBOX_FRAGMENT_DIR="${SC_DIR}/config" domain=new.example
    syncSidecarTlsDomain' >/dev/null 2>&1
for f in 06_hysteria2_inbounds 09_tuic_inbounds; do
    assert_equals "new.example ${SC_DIR}/tls/new.example.crt ${SC_DIR}/tls/new.example.key" \
        "$(jq -r '.inbounds[0].tls | "\(.server_name) \(.certificate_path) \(.key_path)"' "${SC_DIR}/config/${f}.json")" \
        "换域名重装：${f} 的证书换成新域名的"
done

# --- Reality 回车随机目标：挑到挂在 Cloudflare 后面的就换一个，不问（问了回车即退出，服务已停着） ---
RD_FN=$(sed -n '/^realityDestBehindCloudflare() {/,/^}/p;/^checkRealityDest() {/,/^}/p;/^realityDestList() {/,/^}/p;/^pickRandomDest() {/,/^}/p;/^initRealityClientServersName() {/,/^}/p' install.sh)
# run_rd CF_HOSTS → curl 桩：CF_HOSTS 里的域名回 Cloudflare trace；回车选随机 30 次，打印挑中过的目标（去重），
# 30 次都没被追问、没退出才在末尾打 END（追问后回车会 exit，END 就打不出来）
run_rd() {
    env RD_FN="${RD_FN}" CF="$1" bash -c '
        eval "${RD_FN}"
        echoContent() { :; }
        t() { echo "$1"; }
        isValidDomain() { return 0; }
        curl() { local u="${*: -1}"; u=${u#https://}; u=${u%%/*}; [[ " ${CF} " == *" ${u} "* ]] && echo "visit_scheme=https"; return 0; }
        for i in $(seq 1 30); do
            realityServerName= domain= lastInstallationConfig=
            initRealityClientServersName </dev/null >/dev/null 2>&1
            echo "${realityServerName}"
        done
        echo END' 2>&1 | LC_ALL=C sort -u | paste -sd' ' -
}
rdAll=$(sed -n 's/^    local realityDestDomainList="\(.*\)"$/\1/p' install.sh | tr ',' ' ')
assert_equals "END $(cut -d' ' -f1 <<<"${rdAll}")" "$(run_rd "$(cut -d' ' -f2- <<<"${rdAll}")")" \
    "随机目标：只剩一个没挂 Cloudflare 时 30 次都挑它，不追问也不退出"
assert_equals "yes" "$(run_rd "" | awk '{ok = ($1 == "END" && NF > 2); print (ok ? "yes" : "no")}')" "随机目标：都没挂时照常随机（30 次挑中不止一个）"

# --- 开了端口跳跃：sing-box 订阅也要带上区间，不然 sing-box 系客户端只连固定端口 ---
assert_contains "$(grep -F 'singBoxPorts=",' install.sh)" '\"server_ports\":[\"${port/-/:}' \
    "Hysteria2 的 sing-box 出站在跳跃时写 server_ports，区间换成 sing-box 认的 a:b"

# --- SELinux 没禁用时 nginx 的 listen 端口先登记成 http_port_t：不然回到 Enforcing（含重启）后 nginx 绑不上、整个起不来 ---
LN_FN=$(sed -n '/^labelNginxPorts() {/,/^}/p' install.sh)
LN_DIR="${MOCK_ROOT}/selinuxnginx"
rm -rf "${LN_DIR}" && mkdir -p "${LN_DIR}/conf.d"
printf '%s\n' 'server {' '    listen 2087 so_keepalive=on ssl;' '    listen [::]:2087 ssl;' '}' >"${LN_DIR}/conf.d/a.conf"
printf '%s\n' 'server {' '    listen 127.0.0.1:31305 ssl;' '    listen 443 ssl;' '    # listen 9999;' '    location /site/ {' '        proxy_pass http://127.0.0.1:8080;' '    }' '}' >"${LN_DIR}/conf.d/b.conf"
printf '%s\n' 'server {' '    location /a/ {' '        grpc_pass grpc://127.0.0.1:31307;' '    }' '}' >"${LN_DIR}/conf.d/alone.conf"
printf '%s\n' 'server {' '    location /b {' '        proxy_pass                          http://127.0.0.1:31306;' '    }' '}' >"${LN_DIR}/conf.d/sing_box_VMess_HTTPUpgrade.conf"
# run_ln ENFORCE → getenforce 报 ENFORCE；semanage 桩：已登记 80 443 8443，打印它被要求登记的端口
run_ln() {
    env LN_FN="${LN_FN}" LN_DIR="${LN_DIR}" ENF="$1" RELAY="${2:-off}" bash -c '
        eval "${LN_FN}"
        echoContent() { :; }
        getenforce() { echo "${ENF}"; }
        getsebool() { echo "httpd_can_network_relay --> ${RELAY}"; }
        setsebool() { echo "setsebool $*"; }
        semanage() {
            [[ "$1 $2" == "port -l" ]] && { echo "http_port_t                    tcp      80, 81, 443, 8443"; return 0; }
            echo "$*"
        }
        nginxConfigPath="${LN_DIR}/conf.d/"
        labelNginxPorts' 2>&1 | paste -sd'|' -
}
LN_RELAY="setsebool -P httpd_can_network_relay on"
LN_PORTS="port -a -t http_port_t -p tcp 2087|port -a -t http_port_t -p tcp 31305|port -a -t http_port_t -p tcp 31306|port -a -t http_port_t -p tcp 31307"
assert_equals "${LN_PORTS}|${LN_RELAY}" "$(run_ln Enforcing)" \
    "SELinux Enforcing：只登记还不是 http_port_t 的 listen 端口（IPv6、带地址的写法都认，注释掉的不算），以及 15 / 11 要连的回环端口；别人站点的 proxy_pass 不算"
assert_equals "${LN_PORTS}|${LN_RELAY}" "$(run_ln Permissive)" "Permissive 也登记：之后切回 Enforcing 或重启照样能绑"
assert_equals "${LN_PORTS}" "$(run_ln Enforcing on)" "relay 已经开着就不再 setsebool（-P 要改策略存储）"
assert_equals "" "$(run_ln Disabled)" "SELinux 关掉时什么都不做"
rm -f "${LN_DIR}/conf.d/alone.conf"
assert_equals "port -a -t http_port_t -p tcp 2087|port -a -t http_port_t -p tcp 31305|port -a -t http_port_t -p tcp 31306|${LN_RELAY}" "$(run_ln Enforcing)" "只有 11 也要 relay"
rm -f "${LN_DIR}/conf.d/sing_box_VMess_HTTPUpgrade.conf"
assert_equals "port -a -t http_port_t -p tcp 2087|port -a -t http_port_t -p tcp 31305" "$(run_ln Enforcing)" "没装 15 和 11：别人站点里的 proxy_pass 不让脚本开 relay"

# --- 15 的 location 只进 h2 块：Xray 只把 h2 回落给 31302。全部安装时 selectCustomInstallType 是空的，靠 all 参数 ---
UR_FN=$(sed -n '/^xhttpTlsNginxLocation() {/,/^}/p;/^updateRedirectNginxConf() {/,/^# writeHttpRedirectNginxConf/p' install.sh)
UR_DIR="${MOCK_ROOT}/redirectnginx"
# run_ur SELECTION ARG → 跑 updateRedirectNginxConf，打印 31302 那个 server 块里的 location 行与 grpc_pass，再打印一行 h1= 另一个块的 grpc_pass 数
run_ur() {
    rm -rf "${UR_DIR}" && mkdir -p "${UR_DIR}"
    env UR_FN="${UR_FN}" UR_DIR="${UR_DIR}" SEL="$1" ARG="$2" bash -c '
        source lib/constants.sh
        eval "${UR_FN}"
        nginx() { echo "nginx version: nginx/1.22.1" >&2; }
        handleNginx() { :; }; writeHttpRedirectNginxConf() { :; }
        nginxConfigPath="${UR_DIR}/"; domain=ex.org; port=443; nginxStaticPath=/www; customPath=abcd; selectCustomInstallType="${SEL}"
        updateRedirectNginxConf ${ARG}' >/dev/null 2>&1
    awk '/^server \{/ { block = "" } /listen 127.0.0.1:31302/ { block = "h2" } /listen 127.0.0.1:31300/ { block = "h1" }
        block == "h2" && /location \/[a-z]+xhttp|grpc_pass/ { gsub(/^[ \t]+/, ""); print }
        block == "h1" && /grpc_pass/ { h1++ } END { print "h1=" h1 + 0 }' "${UR_DIR}/alone.conf" | paste -sd'|' -
}
_urWant="location /abcdxhttp/ {|grpc_pass grpc://127.0.0.1:${XHTTP_TLS_LOCAL_PORT:-31307};|h1=0"
assert_equals "${_urWant}" "$(run_ur "" all)" "15 的 location：全部安装写进 h2 块，路径与端口对得上入站"
assert_equals "${_urWant}" "$(run_ur ",0,15," "")" "15 的 location：个性化选了 15 也写"
assert_equals "h1=0" "$(run_ur ",0,1," "")" "15 的 location：没选 15 不写，猜中路径也只看到伪装站"

# --- 16 的配置：内层只听回环、只开 TCP；重装沿用目标与密钥；验证连不出去时不能卡死安装 ---
SC_FN=$(sed -n '/^shadowTlsUserKey() {/,/^}/p;/^shadowTlsWithInnerUsers() {/,/^}/p;/^shadowTlsInbound() {/,/^}/p;/^initShadowTlsConfig() {/,/^}/p;/^ensureSingBoxLocalDns() {/,/^}/p' install.sh)
_scConf=$(env SC_FN="${SC_FN}" bash -c 'eval "${SC_FN}"; shadowTlsWithInnerUsers "$(shadowTlsInbound 8443 dl.google.com srvkey '"'"'[{"name":"a-ShadowTLS","password":"p1"}]'"'"')"')
assert_equals '["shadowtls",8443,"shadowtls-ss-in",3,true,"dl.google.com",443]' "$(jq -c '.inbounds[0] | [.type, .listen_port, .detour, .version, .strict_mode, .handshake.server, .handshake.server_port]' <<<"${_scConf}")" \
    "16：外层 v3 + strict，detour 给内层"
assert_equals '["shadowsocks","shadowtls-ss-in","127.0.0.1","tcp",null,true]' "$(jq -c '.inbounds[1] | [.type, .tag, .listen, .network, .listen_port, .multiplex.enabled]' <<<"${_scConf}")" \
    "16：内层只听回环、只开 TCP，不占固定端口，开 multiplex"
assert_equals "24" "$(jq -r '.inbounds[1].users[0].password | length' <<<"${_scConf}")" "16：uPSK 是 16 字节的 base64（长度错了 sing-box 起不来）"
SC_DIR="${MOCK_ROOT}/shadowtlscfg"
# run_sc LAST TLS13 FILE_JSON INPUT → 跑 initShadowTlsConfig，打印目标与密钥（目标随机时固定是 random.example）
run_sc() {
    rm -rf "${SC_DIR}" && mkdir -p "${SC_DIR}"
    [[ -n "$3" ]] && printf '%s\n' "$3" >"${SC_DIR}/16_shadowtls_inbounds.json"
    printf '%b' "$4" | env SC_FN="${SC_FN}" SC_DIR="${SC_DIR}" LAST="$1" TLS13="$2" bash -c '
        eval "${SC_FN}"
        SINGBOX_FRAGMENT_DIR="${SC_DIR}"; lastInstallationConfig="${LAST}"
        getProtocolConfigFileName() { echo 16_shadowtls_inbounds.json; }
        t() { echo "$1"; }; echoContent() { :; }
        jsonWriteFile() { echo "$2" >"$1"; }
        isYesInput() { [[ "$1" == "y" ]]; }; isValidDomain() { [[ "$1" != *" "* ]]; }; checkRealityDest() { return 0; }
        pickRandomDest() { echo random.example; }
        destSupportsTls13() { [[ "${TLS13}" == yes ]]; }
        initShadowTlsConfig >/dev/null 2>&1
        echo "${shadowTlsTarget}|${shadowTlsServerKey}"'
}
SC_OLD='{"inbounds":[{"handshake":{"server":"old.example"}},{"password":"oldkey"}]}'
assert_equals "old.example|oldkey" "$(run_sc y yes "${SC_OLD}" "")" "16：沿用上次配置时不问，目标与密钥都不变（已发出去的节点才不失效）"
assert_equals "old.example|oldkey" "$(run_sc "" yes "${SC_OLD}" "y\n")" "16：问要不要沿用，答 y"
assert_equals "new.example|oldkey" "$(run_sc "" yes "${SC_OLD}" "n\nnew.example\n")" "16：换目标时密钥不变"
assert_equals "random.example" "$(run_sc "" yes "" "\n" | cut -d'|' -f1)" "16：新装回车就随机"
assert_equals '{"dns":{"servers":[{"type":"local","tag":"local"}]}}' "$(cat "${SC_DIR}/02_dns_local.json" 2>/dev/null)" "16：singBoxConfigPath 还是空的（从 Xray 切过来）时也写出握手目标要用的 local DNS"
assert_equals "24" "$(run_sc "" yes "" "\n" | cut -d'|' -f2 | tr -d '\n' | wc -c | tr -d ' ')" "16：新装生成 16 字节服务端密钥"
assert_equals "random.example" "$(run_sc "" no "" "" | cut -d'|' -f1)" "16：TLS 1.3 一直验不过、输入也读完了：试几次后用最后一个，不卡死安装"
assert_equals "good.example" "$(run_sc "" yes "" "bad domain\ngood.example\n" | cut -d'|' -f1)" "16：输错重问"
rm -rf "${SC_DIR}"

# --- Clash 的 TUIC 节点按域名发 SNI 并校验证书：mihomo 见 disable-sni 会直接关掉证书校验 ---
tuicClash=$(sed -n '/^    type: tuic$/,/^EOF$/p' install.sh)
assert_equals "" "$(grep -F 'disable-sni' <<<"${tuicClash}")" "Clash 的 TUIC 节点不写 disable-sni（mihomo 遇到它就不校验证书）"
assert_contains "${tuicClash}" 'sni: ${currentHost}' "Clash 的 TUIC 节点 SNI 是本机域名"

# ============================================================================
# 测试结果汇总
# ============================================================================

# --- 发版只改 VERSION 就推的话两份 README 还写着旧版本号 ---
assert_contains "$(cat README.md)" "当前版本: v$(cat VERSION)" "README.md 的版本号跟 VERSION 一致"
assert_contains "$(cat README.en.md)" "Version: v$(cat VERSION)" "README.en.md 的版本号跟 VERSION 一致"

# --- SELinux 入口检查：菜单照旧退出，只读入口、定时任务和服务停止钩子放行。定时任务被挡的话证书到期也续不上 ---
SE_BLOCK=$(awk '/^# 只读入口、定时任务和服务停止钩子/{f=1} f{print} f && /^esac$/{exit}' install.sh)
SE_STUB=$(mktemp -d)
printf '#!/bin/sh\necho Enforcing\n' >"${SE_STUB}/getenforce"
chmod +x "${SE_STUB}/getenforce"
# run_se ARG → 用 install.sh 的那段判断处理 ARG，再过入口检查；放行打印 passed
run_se() {
    env SE_BLOCK="${SE_BLOCK}" PATH="${SE_STUB}:${PATH}" bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/system-detect.sh
        echoContent() { :; }
        eval "${SE_BLOCK}"
        checkCentosSELinux
        echo passed' _ "$1" 2>/dev/null
}
for _seEntry in doctor topo RenewTLS UpdateGeo CarpoolTick CarpoolCollect; do
    assert_equals "passed" "$(run_se "${_seEntry}")" "SELinux Enforcing：${_seEntry} 放行"
done
assert_equals "" "$(run_se "")" "SELinux Enforcing：菜单照旧退出"
assert_equals "" "$(run_se "--dry-run")" "SELinux Enforcing：别的入口照旧退出"
rm -rf "${SE_STUB}"

# --- 路由总览：采集器在 mock 树上跑。断言画出来的走向，也断言密钥进不了模型和页面 ---
TP_FN_NAMES="topoInbounds topoDirectExit topoPlainExit topoRoutingPlain topoRoutingMulti topoRoutingEntry topoRouting topoCoreStart topoIssues topoCoresText topoCollect topoServe topoCommand chainRuleLabel getPresetDisplayName chainExternalSingleOnXray carpoolEnabled singBoxFragmentsHaveInbounds"
TP_FNS=""
for _tpName in ${TP_FN_NAMES}; do
    TP_FNS+=$(sed -n "/^${_tpName}() {/,/^}/p" install.sh)$'\n'
done
TP_ROOT="${MOCK_ROOT}/topo.root"
TP_X="${TP_ROOT}/xray/conf"
TP_F="${TP_ROOT}/sing-box/conf/config"
TP_C="${TP_ROOT}/sing-box/conf"
# run_tp CODE → 装在 TP_ROOT、内核为 TP_CORE（默认 1）时跑 CODE。getPublicIP、pgrep 桩掉：不打外网；pgrep 答这个刚起的子进程，
# 所以 mock 文件都比它旧，TP_PID 置空就是内核没在跑
run_tp() (
    env PROXY_AGENT_DIR="${TP_ROOT}" TP_FNS="${TP_FNS}" TP_CORE="${TP_CORE-1}" TP_PID="${TP_PID-1}" V2RAY_LANG=zh_CN bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh; source lib/carpool.sh; source lib/topo.sh
        eval "${TP_FNS}"
        getPublicIP() { if [[ "${1:-}" == 6 ]]; then echo 2001:db8::10; else echo 203.0.113.10; fi; }
        pgrep() { [[ -n "${TP_PID}" ]] && echo "$$"; }
        readInstallType() { coreKind=${TP_CORE}; }
        coreKind=${TP_CORE}; nginxConfigPath=/nonexistent/; nginxStaticPath=/nonexistent/static/
        eval "$1"' _ "$1"
)
tp_reset() {
    rm -rf "${TP_ROOT}" && mkdir -p "${TP_X}" "${TP_F}"
    jq -n '{inbounds: [{port: 443, protocol: "vless", settings: {clients: [{id: "uuid-secret-1", email: "alice-VLESS_TCP"}, {id: "uuid-secret-2", email: "carol-VLESS_TCP"}]}}]}' >"${TP_X}/02_VLESS_TCP_inbounds.json"
    jq -n '{inbounds: [{port: 2053, protocol: "dokodemo-door", tag: "dokodemo-in-VLESSReality"}, {port: 45987, listen: "127.0.0.1", settings: {clients: [{id: "uuid-secret-1", email: "alice-VLESS_Reality_Vision"}]}}]}' >"${TP_X}/07_VLESS_vision_reality_inbounds.json"
    printf '%s\n' '{"outbounds":[{"tag":"z_direct_outbound","protocol":"freedom"}]}' >"${TP_X}/z_direct_outbound.json"
    jq -n '{routing: {rules: [{ruleTag: "local-block-ip", ip: ["127.0.0.0/8"], outboundTag: "local_block"}, {domain: ["domain:gstatic.com"], outboundTag: "z_direct_outbound"}]}}' >"${TP_X}/09_routing.json"
}
tp_model() { run_tp "topoCollect ${1:-false}" 2>/dev/null; }

# 没接链式：入站全称、账号的协议集合、默认走直连
tp_reset
_tp=$(tp_model)
assert_equals 'VLESS+TCP[TLS_Vision]|tcp :443|VLESS+Reality+Vision|tcp :2053' "$(jq -r '.inbounds | "\(.[0].name)|\(.[0].sub)|\(.[1].name)|\(.[1].sub)"' <<<"${_tp}")" \
    "路由总览：入站写全称，Reality 的端口取对外的那个，不取回环上的"
assert_equals 'all|[0]' "$(jq -r '.accounts[] | select(.name == "alice") | .protocols' <<<"${_tp}")|$(jq -c '.accounts[] | select(.name == "carol") | .protocols' <<<"${_tp}")" \
    "路由总览：alice 开了全部协议，carol 只开一个"
assert_equals 'direct|全部|203.x.x.x' "$(jq -r '"\(.flows[0].exit)|\(.flows[0].when)|\(.exits[0].host)"' <<<"${_tp}")" \
    "路由总览：没接链式、没有分流时全走直连，本机地址默认也打码；指向默认出口的 gstatic 不算一条分流"
assert_equals "0" "$(grep -c 'uuid-secret\|rawHost\|203.0.113.10' <<<"${_tp}")" "路由总览：模型里没有 UUID，也没有未打码的地址"
assert_contains "$(tp_model true)" "203.0.113.10" "路由总览：--full 才显示本机地址"
assert_equals "" "$(jq -r '.host' <<<"${_tp}")" "路由总览：默认不写主机名，截图和地址打码一样认不出机器"
assert_not_empty "$(tp_model true | jq -r '.host')" "路由总览：--full 才写主机名"

# 分流工具：条件写在连线上；规则指向不存在的出站要报出来（Xray 会直接断连接）
jq '.routing.rules += [{domain: ["geosite:netflix", "domain:example.org"], outboundTag: "IPv6_out"}, {domain: ["a.example"], outboundTag: "gone_out"}]' "${TP_X}/09_routing.json" >"${TP_X}/r.tmp" && mv "${TP_X}/r.tmp" "${TP_X}/09_routing.json"
printf '%s\n' '{"outbounds":[{"tag":"IPv6_out","protocol":"freedom"}]}' >"${TP_X}/IPv6_out.json"
_tp=$(tp_model)
assert_equals 'IPv6_out|geosite:netflix 等 2 项' "$(jq -r '.flows[] | select(.exit == "IPv6_out") | "\(.exit)|\(.when)"' <<<"${_tp}")" "路由总览：分流条件写在线上"
assert_equals 'direct|其余（默认）' "$(jq -r '.flows[-1] | "\(.exit)|\(.when)"' <<<"${_tp}")" "路由总览：有分流时默认那条写成其余"
assert_contains "$(jq -r '.issues[]' <<<"${_tp}")" "gone_out" "路由总览：规则指向不存在的出站要报出来"

# 多链路：密钥和 ip、port 并排放在状态文件里，只能取需要的字段；出口标下一跳，下一跳是中继时注明，出站配置缺失的标红
tp_reset
jq -n '{mode: "multi_chain", default_chain: "a", accounts: {alice: "b", zed: "nosuch"},
    rules: [{type: "custom", value: "x.example", chain: "b"}, {type: "ip_cidr", value: "1.2.3.0/24", chain: "b"}, {type: "custom", value: "y.example", chain: "a"}],
    chains: [{name: "a", ip: "198.51.100.20", port: 50080, method: "m", password: "pw-secret-a"}, {name: "b", ip: "198.51.100.30", port: 44074, method: "m", password: "pw-secret-b"},
             {name: "c", ip: "198.51.100.40", port: 1, method: "m", password: "pw-secret-c"}]}' >"${TP_C}/chain_multi_info.json"
printf '%s\n' '{"outbounds":[{"tag":"a","server":"198.51.100.20","server_port":50080,"password":"pw-secret-a"}]}' >"${TP_F}/chain_outbound_a.json"
printf '%s\n' '{"outbounds":[{"tag":"b-hop-1","server":"192.0.2.1","server_port":40000,"password":"pw-secret-r"},{"tag":"b","server":"198.51.100.30","server_port":44074,"password":"pw-secret-b"}]}' >"${TP_F}/chain_outbound_b.json"
_tp=$(tp_model)
assert_equals '198.x.x.x:50080|192.x.x.x:40000|下一跳是中继，共 2 跳' "$(jq -r '[.exits[] | select(.key == "a" or .key == "b")] | "\(.[0].host):\(.[0].port)|\(.[1].host):\(.[1].port)|\(.[1].note)"' <<<"${_tp}")" \
    "路由总览（多链路）：出口标下一跳的地址和端口，不标最终出口；下一跳是中继时注明"
assert_equals 'b' "$(jq -r '.accounts[] | select(.name == "alice") | .exit' <<<"${_tp}")" "路由总览（多链路）：账号指定的出口带上"
assert_equals 'b|自定义域名 等 2 项' "$(jq -r '.flows[0] | "\(.exit)|\(.when)"' <<<"${_tp}")" "路由总览（多链路）：同一条链路的规则合成一根线；指向默认链路的规则不重复画"
assert_equals 'a|其余（默认）' "$(jq -r '.flows[-1] | "\(.exit)|\(.when)"' <<<"${_tp}")" "路由总览（多链路）：默认链路"
assert_equals 'true' "$(jq -r '.exits[] | select(.key == "c") | .bad' <<<"${_tp}")" "路由总览（多链路）：状态里有、出站配置没有的链路标红"
assert_contains "$(jq -r '.issues[]' <<<"${_tp}")" "账号 zed 指定的出口 nosuch 不存在" "路由总览（多链路）：指向不存在链路的账号要报出来"
assert_equals "0" "$(grep -c 'pw-secret\|192.0.2.1' <<<"${_tp}")" "路由总览（多链路）：模型里没有密钥"
assert_equals "0" "$(run_tp 'topoRenderHtml "$(topoCollect true)"' 2>/dev/null | grep -c 'pw-secret')" "路由总览（多链路）：--full 的页面里也没有密钥"

# 单链路与多跳：中继给的配置码带全部跳，出口标第一跳
tp_reset
jq -n '{role: "entry", exit_ip: "198.51.100.20", exit_port: 50080, key: "pw-secret-a", accounts: {alice: "direct"}}' >"${TP_C}/chain_entry_info.json"
printf '%s\n' '{"outbounds":[{"tag":"chain_outbound"}]}' >"${TP_F}/chain_outbound.json"
_tp=$(tp_model)
assert_equals 'chain|全部|direct|null' "$(jq -r '"\(.flows[0].exit)|\(.flows[0].when)|\(.accounts[] | select(.name == "alice") | .exit)|\(.exits[] | select(.key == "chain") | .note)"' <<<"${_tp}")" \
    "路由总览（单链路）：默认走链路，指定直连的账号单独走，没有中继"
jq -n '{role: "entry", mode: "multi_hop", hop_count: 2, hops: [{ip: "192.0.2.1", port: 1000, key: "pw-secret-r", method: "m"}, {ip: "198.51.100.20", port: 50080, key: "pw-secret-a", method: "m"}], default_chain: "direct"}' >"${TP_C}/chain_entry_info.json"
_tp=$(tp_model true)
assert_equals '192.0.2.1|1000|下一跳是中继，共 2 跳|direct' "$(jq -r '"\(.exits[] | select(.key == "chain") | "\(.host)|\(.port)|\(.note)")|\(.flows[0].exit)"' <<<"${_tp}")" \
    "路由总览（多跳）：标第一跳的地址并注明是中继；默认直连时全走直连"
assert_equals "0" "$(grep -c 'pw-secret' <<<"${_tp}")" "路由总览（多跳）：模型里没有密钥"
rm -f "${TP_F}/chain_outbound.json"
assert_equals 'true' "$(tp_model | jq -r '.exits[] | select(.key == "chain") | .bad')" "路由总览（单链路）：出站配置不在就标红"

# 按协议分流（sing-box 内核）：入站决定出口，选中的单独连线，其余走 final
tp_reset
rm -f "${TP_X}"/*.json
printf '%s\n' '{"outbounds":[{"tag":"chain_outbound"}]}' >"${TP_F}/chain_outbound.json"
jq -n '{inbounds: [{listen_port: 443, tag: "VLESSReality", users: [{name: "alice-VLESS_Reality_Vision", uuid: "uuid-secret-1"}]}]}' >"${TP_F}/07_VLESS_vision_reality_inbounds.json"
jq -n '{inbounds: [{listen_port: 2087, tag: "Hysteria2", users: [{name: "alice-Hysteria2", password: "pw-secret-h"}]}]}' >"${TP_F}/06_hysteria2_inbounds.json"
jq -n '{route: {rules: [{inbound: ["Hysteria2"], outbound: "chain_outbound"}], final: "direct"}}' >"${TP_F}/chain_route.json"
jq -n '{role: "entry", exit_ip: "198.51.100.20", exit_port: 50080, protocol_routing: {enabled: true, selection: "1", protocols: "Hysteria2"}}' >"${TP_C}/chain_entry_info.json"
_tp=$(TP_CORE=2 tp_model)
assert_equals '6|chain|按协议|direct|其余协议' "$(jq -r '"\(.inboundExits[0].inbound)|\(.inboundExits[0].exit)|\(.inboundExits[0].when)|\(.flows[0].exit)|\(.flows[0].when)"' <<<"${_tp}")" \
    "路由总览（按协议分流）：选中的入站直接连到链路，其余协议走直连"
assert_equals "0" "$(grep -c 'pw-secret\|uuid-secret' <<<"${_tp}")" "路由总览（sing-box）：模型里没有密码和 UUID"

# 本机当链式出口或中继：多一个收别的机器流量的入站
tp_reset
jq -n '{role: "exit", ip: "203.0.113.10", port: 50080, key: "pw-secret-a"}' >"${TP_C}/chain_exit_info.json"
_tp=$(tp_model)
assert_equals 'chain|tcp :50080|direct|来自入口' "$(jq -r '"\(.inbounds[-1].id)|\(.inbounds[-1].sub)|\(.inboundExits[0].exit)|\(.inboundExits[0].when)"' <<<"${_tp}")" "路由总览（链式出口）：入口来的流量从本机出去"
assert_equals 'all' "$(jq -r '.accounts[] | select(.name == "alice") | .protocols' <<<"${_tp}")" "路由总览（链式出口）：链式入站不算账号要开的协议"
rm -f "${TP_C}/chain_exit_info.json"
jq -n '{role: "relay", port: 40000, key: "pw-secret-a", downstream_hops: [{ip: "192.0.2.1", port: 1000, key: "pw-secret-r"}, {ip: "198.51.100.20", port: 50080, key: "pw-secret-b"}], total_hops: 3}' >"${TP_C}/chain_relay_info.json"
_tp=$(tp_model true)
assert_equals 'next|192.0.2.1|下一跳是中继，共 2 跳' "$(jq -r '.inboundExits[0].exit as $k | .exits[] | select(.key == $k) | "\(.key)|\(.host)|\(.note)"' <<<"${_tp}")" "路由总览（中继）：标下一跳的地址，后面还有中继时注明"
assert_equals "0" "$(grep -c 'pw-secret' <<<"${_tp}")" "路由总览（中继）：模型里没有密钥"

# 拼车与对不上的检查
tp_reset
mkdir -p "${TP_ROOT}/carpool"
jq -n '{enabled: true, billing: "both", members: {alice: {status: "active", upBytes: 0, downBytes: 0, quotaBytes: 0, expire: ""}, bob: {status: "disabled", reason: "quota", upBytes: 0, downBytes: 0, quotaBytes: 1, expire: ""}}}' >"${TP_ROOT}/carpool/state.json"
jq -n '{members: {alice: {}, bob: {}}}' >"${TP_ROOT}/carpool/members.json"
_tp=$(tp_model)
assert_equals 'disabled|未纳入计量' "$(jq -r '"\(.accounts[] | select(.name == "bob") | .status)|\(.accounts[] | select(.name == "carol") | .sub)"' <<<"${_tp}")" "路由总览（拼车）：停用的成员列出来，表外账号标未纳入计量"
assert_equals "[]" "$(jq -c '.issues' <<<"${_tp}")" "路由总览（拼车）：内核在跑、成员表一致时不报对不上"
jq -n '{members: {alice: {}, bob: {}, newbie: {}}}' >"${TP_ROOT}/carpool/members.json"
assert_contains "$(tp_model | jq -r '.issues[]')" "members.json 改过还没应用" "路由总览（拼车）：成员表改了没应用要报出来"
assert_contains "$(TP_PID="" tp_model | jq -r '.issues[]')" "Xray 没在运行" "路由总览：内核没在跑要报出来"
if [[ -r /proc/self/stat ]]; then
    touch -t 209901010000 "${TP_X}/09_routing.json"
    assert_contains "$(tp_model | jq -r '.issues[]')" "Xray 的配置比进程新" "路由总览：配置比进程新要报出来"
fi

# 入口：写文件的权限、拒绝写进 nginx 对外的目录、参数错误、没装内核
tp_reset
_tpOut="${MOCK_ROOT}/topo.html"
: >"${_tpOut}" && chmod 644 "${_tpOut}"
run_tp "topoCommand --out ${_tpOut}" >/dev/null 2>&1
assert_equals "0" "$?" "路由总览：--out 退出码 0"
assert_contains "$(cat "${_tpOut}")" "<svg" "路由总览：--out 写出页面"
if stat -c %a "${_tpOut}" >/dev/null 2>&1; then
    assert_equals "600" "$(stat -c %a "${_tpOut}")" "路由总览：页面文件只有 root 可读，已有文件的权限也收紧"
fi
mkdir -p "${TP_ROOT}/subscribe"
_tpSub=$(run_tp "topoCommand --out ${TP_ROOT}/subscribe/x.html; echo rc=\$?" 2>&1)
assert_contains "${_tpSub}" "rc=1" "路由总览：拒绝写进订阅目录（nginx 对外提供）"
assert_equals "no" "$([[ -e "${TP_ROOT}/subscribe/x.html" ]] && echo yes || echo no)" "路由总览：拒绝时文件没写出来"
assert_contains "$(run_tp 'topoCommand --bogus; echo rc=$?' 2>&1)" "rc=1" "路由总览：不认识的参数返回 1"
assert_contains "$(TP_CORE="" run_tp 'topoCommand; echo rc=$?' 2>&1)" "rc=1" "路由总览：没装内核返回 1"

# 页面端口在桥端口段里，分桥端口时要让开：撞上的话开页面会占掉一条链路的桥
_tpChains=$(jq -cn '{mode: "multi_chain", chains: [range(1; 99) | {name: "c\(.)", ip: "x", port: 1}], accounts: ([range(1; 99) | {key: "u\(.)", value: "c\(.)"}] | from_entries)}')
printf '%s\n' "${_tpChains}" >"${MOCK_ROOT}/topo-chains.json"
assert_equals "31209" "$(run_ca "chainAccountAssignPorts \"\$(cat ${MOCK_ROOT}/topo-chains.json)\"" 2>/dev/null | jq '[.chains[].bridge_port] | max')" "路由总览：桥端口分配让开页面端口 31210"
assert_equals "31210" "$(bash -c 'source lib/constants.sh; echo "${TOPO_PAGE_PORT}"')" "路由总览：页面端口是被两边封住的桥端口段的最后一个"

echo "=============================================="
echo -e "${YELLOW}测试结果汇总${NC}"
echo "=============================================="
echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}所有集成测试通过！${NC}"
    exit 0
else
    echo -e "${RED}有 ${TESTS_FAILED} 个测试失败！${NC}"
    exit 1
fi
