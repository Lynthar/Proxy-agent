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

echo ""

# ============================================================================
# 测试 removeUser 删除过滤器语义（镜像 install.sh removeUser 的 jq 过滤器）
# 回归背景：只写 .settings.clients 的过滤器在 sing-box 形态（.users）上是静默
# no-op——命令成功退出但用户没删掉，凭据继续有效
# ============================================================================

echo -e "${YELLOW}=== 测试 removeUser 删除过滤器语义 ===${NC}"

REMOVE_USER_FILTER='del(.inbounds[0].settings.clients[$idx]//.inbounds[0].users[$idx])'
REMOVE_USER_TMP="${MOCK_ROOT}/remove_user_semantics.json"

# sing-box 形态（.users）——组合过滤器必须真的删掉目标用户
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"type": "vless", "users": [{"uuid": "u-aaa", "name": "alice-VLESS_WS"}, {"uuid": "u-bbb", "name": "bob-VLESS_WS"}]}]}
EOF
result=$(jq -r --argjson idx 0 "${REMOVE_USER_FILTER}" "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].users | length')
assert_equals "1" "${result}" "sing-box .users 形态：删除后剩 1 个用户"
result=$(jq -r --argjson idx 0 "${REMOVE_USER_FILTER}" "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].users[0].uuid')
assert_equals "u-bbb" "${result}" "sing-box .users 形态：删除的是选中下标的用户"

# 旧过滤器（仅 settings.clients）在同一文件上是静默 no-op——钉死这个缺陷不再回归
result=$(jq -r --argjson idx 0 'del(.inbounds[0].settings.clients[$idx])' "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].users | length')
assert_equals "2" "${result}" "旧的仅 settings.clients 过滤器在 sing-box 形态上确实是 no-op（回归钉）"

# Xray 形态（.settings.clients，含 XHTTP 的 12_ 文件同构）
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"protocol": "vless", "settings": {"clients": [{"id": "u-ccc", "email": "carol-VLESS_TCP/TLS_Vision"}, {"id": "u-ddd", "email": "dave-VLESS_TCP/TLS_Vision"}]}}]}
EOF
result=$(jq -r --argjson idx 1 "${REMOVE_USER_FILTER}" "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].settings.clients | length')
assert_equals "1" "${result}" "Xray .settings.clients 形态：删除后剩 1 个用户"
result=$(jq -r --argjson idx 1 "${REMOVE_USER_FILTER}" "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].settings.clients[0].id')
assert_equals "u-ccc" "${result}" "Xray .settings.clients 形态：保留未选中的用户"

# Xray Reality 07 形态（clients 在 inbounds[1]）——removeUser 协议 7 的三路组合过滤器
REMOVE_REALITY_FILTER='del(.inbounds[0].settings.clients[$idx]//.inbounds[1].settings.clients[$idx]//.inbounds[0].users[$idx])'
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"port": 443, "protocol": "dokodemo-door", "settings": {}}, {"protocol": "vless", "settings": {"clients": [{"id": "u-eee", "email": "erin-vless_reality_vision"}, {"id": "u-fff", "email": "frank-vless_reality_vision"}]}}]}
EOF
result=$(jq -r --argjson idx 0 "${REMOVE_REALITY_FILTER}" "${REMOVE_USER_TMP}" | jq -r '.inbounds[1].settings.clients | length')
assert_equals "1" "${result}" "Reality 07 形态：inbounds[1] 中删除成功"

# 注册表驱动的账户过滤器语义（镜像 applyAccountChangeAllProtocols：路径来自
# getProtocolUsersPath，add 用 --argjson 整组替换，del 用精确路径不再靠 // 猜测链）
# (core=1, id=7)：del 精确打 inbounds[1]，与旧三路组合链等价，且 [0] 的 dokodemo 不动
result=$(jq -r --argjson idx 0 'del(.inbounds[1].settings.clients[$idx])' "${REMOVE_USER_TMP}" | jq -r '.inbounds[1].settings.clients | length')
assert_equals "1" "${result}" "注册表 del(1,7)：精确 inbounds[1] 删除，与旧组合链等价"
result=$(jq -r --argjson idx 0 'del(.inbounds[1].settings.clients[$idx])' "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].protocol')
assert_equals "dokodemo-door" "${result}" "注册表 del(1,7)：inbounds[0] 的 dokodemo 分发器不受影响"

# (core=1, id=7)：add 整组替换写 inbounds[1]，[0] 不长出 clients
result=$(jq --argjson newClients '[{"id":"u-new","email":"new-vless_reality_vision"}]' '.inbounds[1].settings.clients = $newClients' "${REMOVE_USER_TMP}" | jq -r '.inbounds[1].settings.clients[0].id')
assert_equals "u-new" "${result}" "注册表 add(1,7)：整组替换落在 inbounds[1]"
result=$(jq --argjson newClients '[{"id":"u-new","email":"n"}]' '.inbounds[1].settings.clients = $newClients' "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].settings | has("clients")')
assert_equals "false" "${result}" "注册表 add(1,7)：dokodemo 的 settings 不长出 clients"

# (core=2)：add/del 精确打 .inbounds[0].users（B02 家族的 add/del 两侧一并钉死）
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"type": "vless", "users": [{"uuid": "u-ggg", "name": "gina-VLESS_WS"}, {"uuid": "u-hhh", "name": "hank-VLESS_WS"}]}]}
EOF
result=$(jq --argjson newClients '[{"uuid":"u-1","name":"a"},{"uuid":"u-2","name":"b"},{"uuid":"u-3","name":"c"}]' '.inbounds[0].users = $newClients' "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].users | length')
assert_equals "3" "${result}" "注册表 add(2,*)：整组替换落在 .users"
result=$(jq -r --argjson idx 1 'del(.inbounds[0].users[$idx])' "${REMOVE_USER_TMP}" | jq -r '.inbounds[0].users[0].uuid')
assert_equals "u-ggg" "${result}" "注册表 del(2,*)：按 index 删 .users 保留其余"

# removeUser 列表端组合：naive fronting 的名字段是 username（旧的 name//username 整流链已废）
cat > "${REMOVE_USER_TMP}" << 'EOF'
{"inbounds": [{"type": "naive", "users": [{"username": "ivy-singbox_naive", "password": "u-iii"}]}]}
EOF
result=$(jq -r '.inbounds[0].users[].username' "${REMOVE_USER_TMP}")
assert_equals "ivy-singbox_naive" "${result}" "注册表列表(2,10)：usersPath[].username 取到显示名"

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

# 只抽 initSingBoxConfig 内 cat <<EOF >…/NN_xxx_inbounds.json 到 EOF 的块，一块一行：文件名|tag|有无证书
SINGBOX_TEMPLATE_ROWS=$(awk '
    /^initSingBoxConfig\(\)/ { inFn = 1 }
    inFn && !inBlk && /^}/ { inFn = 0 }
    inFn && /cat <<EOF >/ && match($0, /[0-9][0-9]_[A-Za-z0-9_]+_inbounds\.json/) {
        name = substr($0, RSTART, RLENGTH); tag = ""; cert = "no"; inBlk = 1; next
    }
    inBlk && /^EOF$/ { print name "|" tag "|" cert; inBlk = 0 }
    inBlk && /"tag"/ { t = $0; sub(/.*"tag"[ ]*:[ ]*"/, "", t); sub(/".*/, "", t); tag = t }
    inBlk && /certificate_path/ { cert = "yes" }
' install.sh)
assert_not_empty "${SINGBOX_TEMPLATE_ROWS}" "initSingBoxConfig：抽到 inbound 模板块"

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

# ============================================================================
# showInstallStatus 的协议行（抽 install.sh 原文执行，不抄副本）
# ============================================================================

echo -e "${BLUE}[showInstallStatus] 协议显示行${NC}"

SHOW_STATUS_FN=$(sed -n '/^showInstallStatus() {/,/^}/p' install.sh)
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
    'VMess+TLS+HTTPUpgrade' 'VLESS+Reality+XHTTP' 'AnyTLS' 'SS2022' '')" \
    "$(render_install_status 2 ",0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,")" \
    "showInstallStatus：全部 15 个协议按 ID 升序、用菜单文案显示"
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

# nginx 在不在跑只能按进程名精确判：-f 会把 "vim nginx.conf" 当成 nginx
NGINX_PGREP_SUBSTR=$(grep -nE '^[^#]*pgrep -f "nginx"' install.sh)
assert_equals "" "${NGINX_PGREP_SUBSTR}" "install.sh 判 nginx 进程一律 pgrep -x，没有 -f 子串匹配"

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

REGISTRY_IDS=$(for _n in $(grep -oE '[0-9]{2}_[A-Za-z0-9_]+_inbounds\.json' lib/protocol-registry.sh | sort -u); do
    parseProtocolIdFromFileName "${_n}"; done | sort -nu)
for _core in 1 2; do
    for _pid in ${REGISTRY_IDS}; do
        _idField=$(getProtocolIdField "${_core}" "${_pid}") || continue
        _nameField=$(getProtocolNameField "${_core}" "${_pid}")
        _keys=$(render_clients "${_core}" "${_pid}" 2>/dev/null | jq -r '.[0] // empty | keys[]' 2>/dev/null | tr '\n' ' ')
        if [[ -z "${_keys}" ]]; then
            echo "  - core ${_core} id ${_pid}: 生成器没有这个分支，跳过"
            continue
        fi
        assert_contains " ${_keys}" " ${_idField} " "core ${_core} id ${_pid}: 写侧带 registry 身份字段 ${_idField}"
        if [[ -n "${_nameField}" ]]; then
            assert_contains " ${_keys}" " ${_nameField} " "core ${_core} id ${_pid}: 写侧带 registry 显示名字段 ${_nameField}"
        fi
    done
done

echo ""

# ============================================================================
# 测试结果汇总
# ============================================================================

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
