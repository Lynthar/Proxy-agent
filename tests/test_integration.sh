#!/usr/bin/env bash
# ============================================================================
# test_integration.sh - 集成测试 (模拟 VPS 环境)
# ============================================================================
# 用法: bash tests/test_integration.sh
# 此脚本创建模拟的安装环境来测试配置读取功能
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
mkdir -p "${MOCK_ROOT}/etc/v2ray-agent/xray/conf"
mkdir -p "${MOCK_ROOT}/etc/v2ray-agent/sing-box/conf/config"
mkdir -p "${MOCK_ROOT}/etc/v2ray-agent/tls"
mkdir -p "${MOCK_ROOT}/etc/v2ray-agent/subscribe"

# 创建模拟的 Xray 二进制文件
touch "${MOCK_ROOT}/etc/v2ray-agent/xray/xray"
chmod +x "${MOCK_ROOT}/etc/v2ray-agent/xray/xray"

# 创建模拟的 sing-box 二进制文件
touch "${MOCK_ROOT}/etc/v2ray-agent/sing-box/sing-box"
chmod +x "${MOCK_ROOT}/etc/v2ray-agent/sing-box/sing-box"

echo -e "${GREEN}✓${NC} 创建目录结构"

# ============================================================================
# 创建 Xray 配置文件
# ============================================================================

# VLESS TCP TLS Vision 配置
cat > "${MOCK_ROOT}/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" << 'EOF'
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
                            "certificateFile": "/etc/v2ray-agent/tls/test.example.com.crt",
                            "keyFile": "/etc/v2ray-agent/tls/test.example.com.key"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

# VLESS WebSocket 配置
cat > "${MOCK_ROOT}/etc/v2ray-agent/xray/conf/03_VLESS_WS_inbounds.json" << 'EOF'
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
cat > "${MOCK_ROOT}/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json" << 'EOF'
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
cat > "${MOCK_ROOT}/etc/v2ray-agent/sing-box/conf/config/06_hysteria2_inbounds.json" << 'EOF'
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
cat > "${MOCK_ROOT}/etc/v2ray-agent/sing-box/conf/config/09_tuic_inbounds.json" << 'EOF'
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
cat > "${MOCK_ROOT}/etc/v2ray-agent/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json" << 'EOF'
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

touch "${MOCK_ROOT}/etc/v2ray-agent/tls/test.example.com.crt"
touch "${MOCK_ROOT}/etc/v2ray-agent/tls/test.example.com.key"

# 创建 CDN 配置文件
echo "cdn.example.com" > "${MOCK_ROOT}/etc/v2ray-agent/cdn"

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
source lib/service-control.sh

# 定义测试路径变量
_TEST_V2RAY_AGENT_DIR="${MOCK_ROOT}/etc/v2ray-agent"
_TEST_XRAY_CONFIG_DIR="${_TEST_V2RAY_AGENT_DIR}/xray/conf"
_TEST_SINGBOX_CONFIG_DIR="${_TEST_V2RAY_AGENT_DIR}/sing-box/conf/config"
_TEST_TLS_CERT_DIR="${_TEST_V2RAY_AGENT_DIR}/tls"

echo -e "${GREEN}✓${NC} 模块加载完成"
echo ""

# ============================================================================
# 测试 JSON 读取功能
# ============================================================================

echo -e "${YELLOW}=== 测试 JSON 读取功能 ===${NC}"

# 测试读取 Xray VLESS TCP 配置
port=$(xrayGetInboundPort "${_TEST_XRAY_CONFIG_DIR}/02_VLESS_TCP_inbounds.json")
assert_equals "443" "${port}" "读取 Xray VLESS TCP 端口"

protocol=$(xrayGetInboundProtocol "${_TEST_XRAY_CONFIG_DIR}/02_VLESS_TCP_inbounds.json")
assert_equals "vless" "${protocol}" "读取 Xray VLESS TCP 协议"

uuid=$(xrayGetClientUUID "${_TEST_XRAY_CONFIG_DIR}/02_VLESS_TCP_inbounds.json")
assert_equals "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11" "${uuid}" "读取 Xray 客户端 UUID"

clients=$(xrayGetClients "${_TEST_XRAY_CONFIG_DIR}/02_VLESS_TCP_inbounds.json")
assert_contains "${clients}" "user1-VLESS_TCP" "读取 Xray 客户端列表"

# 测试读取 Xray WebSocket 路径
wsPath=$(xrayGetStreamPath "${_TEST_XRAY_CONFIG_DIR}/03_VLESS_WS_inbounds.json" "ws")
assert_equals "/testpath123ws" "${wsPath}" "读取 Xray WebSocket 路径"

# 测试读取 Xray Reality 配置
realityResult=$(xrayGetRealityConfig "${_TEST_XRAY_CONFIG_DIR}/07_VLESS_vision_reality_inbounds.json" 1)
eval "${realityResult}"
assert_equals "www.microsoft.com" "${realityServerName}" "读取 Reality serverName"
assert_equals "O3gPFZ1Tc0FBi0VYRzfhkEAhVPZs1_n5hH_Df3eDOT0" "${realityPublicKey}" "读取 Reality publicKey"
assert_equals "WDrcaQ0SVSc0nh1SVrPmQsBkIjPQgXwZb8_z8L5kGGw" "${realityPrivateKey}" "读取 Reality privateKey"
assert_equals "testSeed12345" "${realityMldsa65Seed}" "读取 Reality mldsa65Seed"

echo ""

# ============================================================================
# 测试 sing-box 配置读取
# ============================================================================

echo -e "${YELLOW}=== 测试 sing-box 配置读取 ===${NC}"

# 测试读取 Hysteria2 配置
hysteria2Result=$(singboxGetHysteria2Config "${_TEST_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json")
eval "${hysteria2Result}"
assert_equals "8844" "${hysteria2Port}" "读取 Hysteria2 端口"
assert_equals "100" "${hysteria2UpMbps}" "读取 Hysteria2 上行速度"
assert_equals "50" "${hysteria2DownMbps}" "读取 Hysteria2 下行速度"
assert_equals "obfspassword456" "${hysteria2ObfsPassword}" "读取 Hysteria2 混淆密码"

# 测试读取 TUIC 配置
tuicResult=$(singboxGetTuicConfig "${_TEST_SINGBOX_CONFIG_DIR}/09_tuic_inbounds.json")
eval "${tuicResult}"
assert_equals "8845" "${tuicPort}" "读取 TUIC 端口"
assert_equals "bbr" "${tuicAlgorithm}" "读取 TUIC 拥塞控制算法"

# 测试读取 sing-box Reality 配置
singboxRealityResult=$(singboxGetRealityConfig "${_TEST_SINGBOX_CONFIG_DIR}/07_VLESS_vision_reality_inbounds.json" 0)
eval "${singboxRealityResult}"
assert_equals "www.google.com" "${singboxRealityServerName}" "读取 sing-box Reality serverName"
assert_equals "SingboxPrivateKey123" "${singboxRealityPrivateKey}" "读取 sing-box Reality privateKey"
assert_equals "443" "${singboxRealityHandshakePort}" "读取 sing-box Reality handshake port"

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
# 测试从证书路径提取域名
# ============================================================================

echo -e "${YELLOW}=== 测试域名提取 ===${NC}"

domain=$(xrayGetTLSDomain "${_TEST_XRAY_CONFIG_DIR}/02_VLESS_TCP_inbounds.json")
assert_equals "test.example.com" "${domain}" "从 TLS 证书路径提取域名"

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
    result=$(jsonGetValue "${TEST_WRITE_FILE}" ".test")
    assert_equals "modified" "${result}" "jsonWriteFile() 写入成功"

    newValue=$(jsonGetValue "${TEST_WRITE_FILE}" ".new")
    assert_equals "value" "${newValue}" "jsonWriteFile() 新字段存在"
else
    echo -e "${RED}✗${NC} jsonWriteFile() 失败"
    ((TESTS_FAILED++))
fi

# 测试 jsonModifyFile
if jsonModifyFile "${TEST_WRITE_FILE}" '.test = "final"' false; then
    result=$(jsonGetValue "${TEST_WRITE_FILE}" ".test")
    assert_equals "final" "${result}" "jsonModifyFile() 修改成功"
else
    echo -e "${RED}✗${NC} jsonModifyFile() 失败"
    ((TESTS_FAILED++))
fi

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
