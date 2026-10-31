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

# 应有的模板全集独立写死（加协议时同步）：抽漏一块就对不上，不能靠「至少抽到一块」放行
SINGBOX_TEMPLATE_WANT=$(for _pid in 0 1 3 4 6 7 9 10 11 13 14; do getProtocolConfigFileName "${_pid}"; done | sort)
assert_equals "${SINGBOX_TEMPLATE_WANT}" "$(cut -d'|' -f1 <<< "${SINGBOX_TEMPLATE_ROWS}" | sort)" \
    "initSingBoxConfig：抽到的 inbound 模板恰好是每个 sing-box 协议各一块"

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
DOTTED_FNS=$(sed -n '/^readInstallType() {/,/^}/p;/^readInstallProtocolType() {/,/^}/p;/^initXrayClients() {/,/^}/p;/^applyAccountChangeAllProtocols() {/,/^}/p' install.sh)
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
CLIENTS_LIVE_1="0 1 3 4 6 7 9 12"
CLIENTS_LIVE_2="0 1 3 4 6 7 9 10 11 13 14 20"
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
assert_contains "$(sed -n '/^_required_lib_fns=(/,/^)/p' install.sh)" "carpoolJudge" "_required_lib_fns 含拼车入口函数，lib/carpool.sh 没加载会在启动时报出"

echo ""

# ============================================================================
# 拼车：ensure 钩子、set 事务、tick、占位、cron 分支、快照（抽 install.sh 原文；服务、crontab、xray 二进制都桩掉）
# ============================================================================

echo -e "${YELLOW}=== 测试拼车钩子与 tick ===${NC}"

CP_FN_NAMES="applyAccountChangeAllProtocols readInstallType readInstallProtocolType carpoolLock carpoolUnlock carpoolEnabled carpoolCurrentClientsMap ensureCarpoolCron ensureCarpoolXray carpoolReconcile carpoolCollect carpoolCollectBeforeStop carpoolSubscribeMd5 carpoolWritePlaceholders carpoolRefreshSubscribe carpoolJudgeAndWrite carpoolSettle carpoolTick carpoolRefuseIfEnabled carpoolGuardAccountMenu carpoolCheckPrerequisites carpoolPortFree carpoolPickApiPort carpoolAllAccounts carpoolFillUuids carpoolRemoveCron carpoolRemoveSubscriptionFiles carpoolEnable carpoolDisable carpoolApply carpoolResetUsage carpoolShowUsage carpoolWritePage carpoolRemovePages carpoolReloadNginx carpoolEnsureNginxLocation carpoolPendingText carpoolRenderPages carpoolPageUrlBase carpoolShowPageLinks carpoolPageSetToken carpoolPageEnable carpoolPageDisable carpoolTelegramSend carpoolNotifyEvents carpoolTickExitTrap carpoolTelegramMask carpoolTelegramConfigure carpoolTelegramTest carpoolTelegramDisable carpoolPageMenu carpoolMenu addUser removeUser cronFunction backupConfigSnapshot restoreConfigSnapshot installCronTLS removeOwnCronEntries"
CP_FNS=$(sed -n "$(for _f in ${CP_FN_NAMES}; do printf '/^%s() {/,/^}/p;' "${_f}"; done)" install.sh)
assert_not_empty "${CP_FNS}" "拼车：抽到 install.sh 原文"
assert_equals "$(wc -w <<<"${CP_FN_NAMES}" | tr -d ' ')" "$(grep -c '^[a-zA-Z0-9]*() {$' <<<"${CP_FNS}")" "拼车：每个函数都抽到了（抽不到说明函数体里出现了顶格的 }）"

CP_ROOT="${MOCK_ROOT}/carpool.root"
CP_TABLE="${MOCK_ROOT}/carpool_crontab"
CP_CALLS="${MOCK_ROOT}/carpool_calls"
CP_STATS="${MOCK_ROOT}/carpool_stats.json"
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
        pageEnabled: false, pageToken: "", collectFailures: 0, notified: {}, events: [],
        members: {
          alice: {uuid: $u1, quotaBytes: $q, expire: "", protocols: [0, 7], upBytes: 0, downBytes: 0, status: "active", reason: ""},
          bob: {uuid: $u2, quotaBytes: 0, expire: "", protocols: [0, 7], upBytes: 0, downBytes: 0, status: "active", reason: ""}}}' >"${CP_ROOT}/carpool/state.json"
    echo testsalt >"${CP_ROOT}/subscribe_local/subscribeSalt"
    mkdir -p "${CP_ROOT}/nginx"
    cat >"${CP_ROOT}/nginx/subscribe.conf" <<'EOF'
server {
    listen 12345 ssl;
    server_name example.com;
    root /usr/share/nginx/html;
    location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {
        default_type 'text/plain; charset=utf-8';
        alias /etc/Proxy-agent/subscribe/$1/$2;
    }
    location / {
    }
}
EOF
    : >"${CP_TABLE}"
    : >"${CP_CALLS}"
    rm -f "${CP_STATS}"
}

# run_cp CMD → 在干净 bash 里以模拟树为安装根执行 CMD；可用环境变量：CP_CORE（内核）、CP_SUBPORT（订阅端口）、
# XRAY_TEST_RC（桩 xray 的 -test 退出码）、CP_RELOAD_INJECT（reloadCore 桩往 state 里塞一笔用量）
run_cp() (
    env PROXY_AGENT_DIR="${CP_ROOT}" CP_FNS="${CP_FNS}" CP_TABLE="${CP_TABLE}" CP_CALLS="${CP_CALLS}" CP_STATS="${CP_STATS}" \
        V2RAY_LANG=zh_CN XRAY_TEST_RC="${XRAY_TEST_RC:-0}" CP_CORE="${CP_CORE:-1}" CP_SUBPORT="${CP_SUBPORT:-}" CP_RELOAD_INJECT="${CP_RELOAD_INJECT:-}" \
        CP_XRAY_VERSION="${CP_XRAY_VERSION:-26.3.27}" CP_CROND_RC="${CP_CROND_RC:-0}" CP_PROTOS="${CP_PROTOS:-}" \
        CP_SUBTYPE="${CP_SUBTYPE:-https}" CP_NGINX_T_RC="${CP_NGINX_T_RC:-0}" CP_CURL_FAIL="${CP_CURL_FAIL:-}" bash -c '
        source lib/i18n.sh; source lib/constants.sh; source lib/utils.sh; source lib/json-utils.sh; source lib/protocol-registry.sh; source lib/carpool.sh
        eval "${CP_FNS}"
        export CP_CALLS CP_STATS XRAY_TEST_RC CP_XRAY_VERSION
        crontab() { case "$1" in -l) cat "${CP_TABLE}" 2>/dev/null ;; -) cat >"${CP_TABLE}" ;; *) cat "$1" >"${CP_TABLE}" ;; esac; }
        pgrep() { echo 4242; }
        command -v flock >/dev/null 2>&1 || flock() { :; }
        command -v md5sum >/dev/null 2>&1 || md5sum() { md5 -q "$@"; }
        lsof() { :; }
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
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "ensure（关）：12_stats_api.json 撤掉"
assert_equals '{"connIdle":280,"handshake":2}' "$(jq -Sc '.policy.levels."0"' "${CP_ROOT}/xray/conf/12_policy.json")" "ensure（关）：统计开关撤掉，其余字段原样"
rm -f "${CP_ROOT}/carpool/state.json"
run_cp 'ensureCarpoolXray' >/dev/null 2>&1
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "ensure（没开过）：什么都不生成"
cp_reset_tree
rm -f "${CP_ROOT}/xray/conf/12_policy.json"
_out=$(run_cp 'ensureCarpoolXray; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=1" "ensure：12_policy.json 缺失时返回 1、不自己造一份"
assert_contains "${_out}" "不存在，无法开启按用户统计" "ensure：缺 policy 时红字说清"
assert_equals "no" "$([[ -f "${CP_ROOT}/xray/conf/12_policy.json" ]] && echo yes || echo no)" "ensure：缺 policy 时不凭空创建"

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
assert_equals "$((50 * GiB))|2099-01-01|20|10" "$(cp_state '"\(.members.alice.quotaBytes)|\(.members.alice.expire)|\(.resetDay)|\(.notify.warnPercent)"')" "tick：即时类字段（配额、到期、resetDay、notify）从文件同步进 state"

# 没开 / 不是 Xray：静默退出，不碰 state
cp_reset_tree
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_iState=$(cp_inode "${CP_ROOT}/carpool/state.json")
assert_equals "0|" "$(run_cp 'carpoolTick' 2>&1; echo "$?|")" "tick（关着）：静默返回 0"
assert_equals "${_iState}" "$(cp_inode "${CP_ROOT}/carpool/state.json")" "tick（关着）：state 不写"
cp_reset_tree
_out=$(CP_CORE=2 run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "tick（内核不是 Xray）：返回 0"
assert_contains "${_out}" "拼车已失效" "tick（内核不是 Xray）：说明原因"

# 恢复路径：配额调高 → 放回协议文件、重建订阅（只在订阅已装时）
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
jq 'del(.inbounds[0].settings.clients[1])' "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json"
jq 'del(.inbounds[1].settings.clients[1])' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json" >"${CP_ROOT}/t.json" && mv "${CP_ROOT}/t.json" "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json"
printf '%s\n' '{"members": {"alice": {"quotaGiB": 10}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(CP_SUBPORT=12345 run_cp 'carpoolTick; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "alice 已恢复" "tick（恢复）：日志里有恢复事件"
assert_equals "active|" "$(cp_state '.members.alice | "\(.status)|\(.reason)"')" "tick（恢复）：配额调高后 alice 恢复"
assert_equals '["zed","alice","bob"]' "$(cp_emails 02_VLESS_TCP_inbounds.json '.inbounds[0].settings.clients')" "tick（恢复）：alice 按 members 顺序放回 02"
assert_equals "${CP_U1}" "$(jq -r '.inbounds[1].settings.clients[1].id' "${CP_ROOT}/xray/conf/07_VLESS_vision_reality_inbounds.json")" "tick（恢复）：07 里放回的是 state 里的 uuid"
assert_equals "1" "$(grep -c '^subscribe false true$' "${CP_CALLS}")" "tick（恢复）：订阅已装时以 subscribe false true 重建"
cp_reset_tree
jq --argjson six $((6 * GiB)) '.members.alice.status = "disabled" | .members.alice.reason = "quota" | .members.alice.upBytes = $six' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
printf '%s\n' '{"members": {"alice": {"quotaGiB": 10}, "bob": {}}}' >"${CP_ROOT}/carpool/members.json"
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
run_cp "restoreConfigSnapshot ${_snap}" >/dev/null 2>&1
assert_equals '{"notify":{"label":"车","digestHour":null},"members":{"alice":{"quotaGiB":5},"bob":{}}}' "$(jq -c . "${CP_ROOT}/carpool/members.json")" "restoreConfigSnapshot：快照里的 carpool/ 覆盖回来"
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
assert_equals "yes" "$([[ "$(cp_state '.apiPort')" -ge 10000 && "$(cp_state '.apiPort')" -le 30000 ]] && echo yes || echo no)" "开启：apiPort 在 10000–30000"
assert_equals "zz|${CP_U1}|${CP_U2}" "$(cp_state '[.members[].uuid] | join("|")')" "开启：uuid 从 inbound 采用"
assert_equals "active|active|active" "$(cp_state '[.members[].status] | join("|")')" "开启：全员 active"
assert_equals "1" "$(grep -c '^reloadCore$' "${CP_CALLS}")" "开启：重载一次"
assert_equals "yes" "$([[ -f "${CP_ROOT}/xray/conf/12_stats_api.json" ]] && echo yes || echo no)" "开启：start 钩子写了 12_stats_api.json"
assert_equals "1" "$(grep -c 'install.sh CarpoolTick' "${CP_TABLE}")" "开启：cron 行加上"
assert_not_empty "$(cp_state '.lastTick')" "开启：第一次 tick 跑过"
assert_equals "drwx------" "$(ls -ld "${CP_ROOT}/carpool" | awk '{print $1}' | cut -c1-10)" "开启：carpool/ 目录 700"
_out=$(run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "拼车已经开着" "开启：已开着时提示"

# 开启被拒的五种情形都不写 state
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
assert_equals "no" "$([[ -f "${CP_ROOT}/carpool/state.json" ]] && echo yes || echo no)" "开启（被拒 ×5）：仍没有 state"

# 再次开启：沿用上次的 members.json 与计数
cp_reset_tree
jq '.enabled = false | .members.alice.upBytes = 12345' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
printf '%s\n' '{}' >"${CP_STATS}"
_out=$(run_cp 'carpoolEnable; echo "rc=$?"' 2>&1)
assert_contains "${_out}" "rc=0" "重开：返回 0"
assert_equals "true|12345|23456" "$(cp_state '"\(.enabled)|\(.members.alice.upBytes)|\(.apiPort)"')" "重开：计数与 apiPort 沿用"
assert_equals "no" "$([[ "${_out}" == *"已按现有账号生成"* ]] && echo yes || echo no)" "重开：已有 members.json 不再播种"

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
# 删除成员在非 tty 下拒绝，文件不动
printf '%s\n' '{"members": {"alice": {"quotaGiB": 5}, "carol": {"quotaGiB": 1, "protocols": [0, 7]}}}' >"${CP_ROOT}/carpool/members.json"
_before02=$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")
_out=$(run_cp 'carpoolApply; echo "rc=$?"' 2>&1 </dev/null)
assert_contains "${_out}" "rc=1" "应用（非 tty 删人）：返回 1"
assert_contains "${_out}" "删除成员 bob" "应用（非 tty 删人）：先显示差异"
assert_contains "${_out}" "需要在终端里逐项确认" "应用（非 tty 删人）：说明要交互"
assert_equals "${_before02}" "$(cat "${CP_ROOT}/xray/conf/02_VLESS_TCP_inbounds.json")" "应用（非 tty 删人）：协议文件不动"
assert_equals "true" "$(cp_state '.members | has("bob")')" "应用（非 tty 删人）：state 不动"
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
assert_equals "0" "$(ls "${CP_ROOT}"/subscribe/*/"${CP_ALICE_MD5}" 2>/dev/null | wc -l | tr -d ' ')" "carpoolRemoveSubscriptionFiles：五个订阅目录与成员页都删"

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
_out=$(run_cp 'read() { echo READ-CALLED; }; addUser; removeUser' 2>&1 </dev/null)
assert_equals "2" "$(grep -c '拼车开启期间账号由' <<<"${_out}")" "守卫：拼车开着时 addUser / removeUser 都提示由配置文件管理"
assert_equals "2" "$(grep -c '^MENU 1$' <<<"${_out}")" "守卫：拦住后回账号菜单"
assert_equals "0" "$(grep -c 'READ-CALLED' <<<"${_out}")" "守卫：没有走到交互"
jq '.enabled = false' "${CP_ROOT}/carpool/state.json" >"${CP_ROOT}/carpool/s.tmp" && mv "${CP_ROOT}/carpool/s.tmp" "${CP_ROOT}/carpool/state.json"
_out=$(run_cp 'read() { echo READ-CALLED; userNum=0; }; addUser' 2>&1 </dev/null)
assert_equals "1" "$(grep -c 'READ-CALLED' <<<"${_out}")" "守卫：关着时 addUser 照常进入交互"
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
assert_equals "yes" "$([[ -f "${CP_ROOT}/subscribe/carpool/${CP_ALICE_MD5}" ]] && echo yes || echo no)" "页面开启：成员页文件 = md5(订阅键+salt)"
assert_equals "3" "$(find "${CP_ROOT}/subscribe/carpool" -type f | wc -l | tr -d ' ')" "页面开启：车主页 + 两个成员页，没有别的文件"
assert_equals "-rw-r--r--" "$(ls -l "${CP_ROOT}/subscribe/carpool/${_token}" | awk '{print $1}' | cut -c1-10)" "页面开启：文件 644（nginx 要读）"
_page=$(cat "${CP_ROOT}/subscribe/carpool/${_token}")
assert_contains "${_page}" "<td>alice</td>" "车主页：有成员行"
assert_contains "${_page}" "未纳入拼车的账号: zed" "车主页：列出未纳入的账号"
assert_equals "no" "$([[ "${_page}" == *"${CP_U1}"* ]] && echo yes || echo no)" "车主页：不含 UUID"
_member=$(cat "${CP_ROOT}/subscribe/carpool/${CP_ALICE_MD5}")
assert_contains "${_member}" "· alice</h1>" "成员页：本人"
assert_equals "no" "$([[ "${_member}" == *"bob"* ]] && echo yes || echo no)" "成员页：看不到别人"
assert_equals "1" "$(grep -c 'location ~ "^/s/carpool/' "${CP_ROOT}/nginx/subscribe.conf")" "页面开启：subscribe.conf 多一个 location"
assert_equals "1" "$(grep -c '^    location ~ ^/s/(clashMeta' "${CP_ROOT}/nginx/subscribe.conf")" "页面开启：订阅原有 location 原样"
assert_equals "yes" "$(awk '/carpool-page-end/{e=NR} /^    location \/ \{/{l=NR} END{print (e && l && e < l) ? "yes" : "no"}' "${CP_ROOT}/nginx/subscribe.conf")" "页面开启：块插在 location / 之前"
assert_equals "1|1" "$(grep -c '^nginx -t$' "${CP_CALLS}")|$(grep -c '^nginx -s reload$' "${CP_CALLS}")" "页面开启：nginx -t 过了才 reload"
assert_contains "${_out}" "车主页: https://example.com:12345/s/carpool/${_token}" "页面开启：车主链接走订阅的域名与端口"
assert_contains "${_out}" "成员页 alice: https://example.com:12345/s/carpool/${CP_ALICE_MD5}" "页面开启：成员链接"
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
assert_contains "$(cat "${CP_ROOT}/subscribe/carpool/${CP_ALICE_MD5}")" "已停用 · 流量已用尽" "tick 后：成员页同步"
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
SUBSCRIBE_FN=$(sed -n '/^subscribe() {/,/^}/p' install.sh)
assert_equals "1" "$(grep -c 'carpoolWritePlaceholders' <<<"${SUBSCRIBE_FN}")" "subscribe 末尾给停用成员补占位"
assert_equals "2" "$(grep -c 'wget -O "${_singboxTplFile}" -q --timeout=15' <<<"${SUBSCRIBE_FN}")" "subscribe：sing-box 模板的两处 wget 带超时（cron 下不能挂死）"

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

# installTools 装完 crontab 包就得确保守护进程在跑，而不是只在刚装包时
INSTALL_TOOLS_FN=$(sed -n '/^installTools() {/,/^}/p' install.sh)
assert_equals "1" "$(grep -c '^    ensureCronService$' <<<"${INSTALL_TOOLS_FN}")" "installTools：无条件调用 ensureCronService（Alpine 自带 crontab、不会走装包分支）"
UNINSTALL_FN=$(sed -n '/^unInstall() {/,/^}/p' install.sh)
assert_equals "yes" "$(grep -n -E 'removeOwnCronEntries|rm -rf \$\{PROXY_AGENT_DIR\}$' <<<"${UNINSTALL_FN}" | head -1 | grep -q removeOwnCronEntries && echo yes || echo no)" \
    "unInstall：先清 cron 行再 rm -rf 安装根"
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

GEO_FN=$(sed -n '/^updateGeoSite() {/,/^}/p' install.sh)
assert_not_empty "${GEO_FN}" "updateGeoSite：抽到函数原文"
GEO_DIR="${MOCK_ROOT}/geo/xray/"
mkdir -p "${GEO_DIR}conf"

# 子 shell 里跑：桩掉 GitHub API、wget 与内核重载；wget 按第一个参数成功（写 -O 目标）或失败
run_update_geo() (
    configPath="${GEO_DIR}conf/"
    release="debian"; wgetShowProgressStatus=""
    GEO_WGET_MODE="$1"; GEO_API_JSON="$2"
    [[ "${3:-}" == "mv-fail" ]] && mv() { return 1; }
    curl() { printf '%s' "${GEO_API_JSON}"; }
    wget() {
        local out=""
        while [[ $# -gt 0 ]]; do [[ "$1" == "-O" ]] && out="$2"; shift; done
        [[ "${GEO_WGET_MODE}" == "ok" && -n "${out}" ]] || return 8
        printf 'new' >"${out}"
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
run_update_geo fail '[{"tag_name":"v2099"}]'
assert_equals "1" "$?" "updateGeoSite：下载失败返回 1"
assert_equals "old old" "$(geo_files)" "updateGeoSite：下载失败时旧 geo 文件原样保留"
assert_equals "0" "$(geo_staging_left)" "updateGeoSite：下载失败不留暂存目录"

run_update_geo ok ''
assert_equals "1" "$?" "updateGeoSite：取不到版本号返回 1"
assert_equals "old old" "$(geo_files)" "updateGeoSite：取不到版本号时旧文件原样保留"

# 发布失败：mv 整体失败（一个都没换），以及 geoip.dat 被同名目录占着（只换掉 geosite）
rm -f "${GEO_DIR}reloaded"
run_update_geo ok '[{"tag_name":"v2099"}]' mv-fail
assert_equals "1" "$?" "updateGeoSite：新文件挪不进去时返回 1"
assert_equals "old old" "$(geo_files)" "updateGeoSite：挪不进去时旧 geo 文件原样保留"
assert_equals "0" "$(geo_staging_left)" "updateGeoSite：挪不进去也不留暂存目录"
rm -f "${GEO_DIR}geoip.dat" && mkdir "${GEO_DIR}geoip.dat"
run_update_geo ok '[{"tag_name":"v2099"}]'
assert_equals "1" "$?" "updateGeoSite：只发布了一部分也返回 1"
assert_equals "no" "$([[ -e "${GEO_DIR}reloaded" ]] && echo yes || echo no)" "updateGeoSite：发布失败不重载内核"
rmdir "${GEO_DIR}geoip.dat"

run_update_geo ok '[{"tag_name":"v2099"}]'
assert_equals "0" "$?" "updateGeoSite：两个文件都下到后返回 0"
assert_equals "yes" "$([[ -e "${GEO_DIR}reloaded" ]] && echo yes || echo no)" "updateGeoSite：发布成功后重载内核"
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
# 子 shell 里跑：$1 currentPort，$2 lastInstallationConfig，$3 喂给 read 的输入；打印最终的 port
run_custom_port() (
    echoContent() { :; }
    allowPort() { :; }
    checkDNSIP() { :; }
    removeNginxDefaultConf() { :; }
    checkPortOpen() { :; }
    handleXray() { :; }
    eval "${PORT_FN}"
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

SELINUX_FN=$(sed -n '/^updateSELinuxHTTPPortT() {/,/^}/p' install.sh)
assert_not_empty "${SELINUX_FN}" "updateSELinuxHTTPPortT：抽到函数原文"
# 只在 handleNginx 起不来时被调；机器上没有 semanage 就是「起不来且修不了」
run_selinux() {
    env PROXY_AGENT_DIR="${CRON_ROOT}" SELINUX_FN="${SELINUX_FN}" bash -c '
        find() { :; }
        echoContent() { :; }
        eval "${SELINUX_FN}"
        updateSELinuxHTTPPortT 2>/dev/null'
}
run_selinux; assert_equals "1" "$?" "updateSELinuxHTTPPortT：不是 SELinux 端口问题时退出码 1"

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
        sudo() { "$@"; }
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
