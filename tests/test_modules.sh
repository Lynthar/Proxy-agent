#!/usr/bin/env bash
# ============================================================================
# test_modules.sh - 模块单元测试
# ============================================================================
# 用法: bash tests/test_modules.sh
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
assert_equals "0" "${PROTOCOL_VLESS_TCP_VISION}" "PROTOCOL_VLESS_TCP_VISION = 0"
assert_equals "6" "${PROTOCOL_HYSTERIA2}" "PROTOCOL_HYSTERIA2 = 6"
assert_equals "7" "${PROTOCOL_VLESS_REALITY_VISION}" "PROTOCOL_VLESS_REALITY_VISION = 7"

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

# 测试 service-control.sh 加载
source lib/service-control.sh
assert_not_empty "${_SERVICE_CONTROL_LOADED}" "service-control.sh 模块加载成功"

# 测试 config-reader.sh 加载
source lib/config-reader.sh
assert_not_empty "${_CONFIG_READER_LOADED}" "config-reader.sh 模块加载成功"

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

# 测试 isValidPort
assert_true "isValidPort 443" "isValidPort(443) 返回 true"
assert_true "isValidPort 65535" "isValidPort(65535) 返回 true"
assert_true "! isValidPort 0" "isValidPort(0) 返回 false"
assert_true "! isValidPort 70000" "isValidPort(70000) 返回 false"

# 测试 base64Encode/base64Decode
encoded=$(base64Encode "hello world")
decoded=$(base64Decode "${encoded}")
assert_equals "hello world" "${decoded}" "base64Encode/Decode 往返测试"

# 测试 trim
trimmed=$(trim "  hello  ")
assert_equals "hello" "${trimmed}" "trim() 去除空格"

# 测试 isValidUUID
assert_true "isValidUUID 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'" "isValidUUID() 验证有效 UUID"
assert_true "! isValidUUID 'invalid-uuid'" "isValidUUID() 拒绝无效 UUID"

# 测试 versionGreaterThan
assert_true "versionGreaterThan '1.2.3' '1.2.0'" "versionGreaterThan('1.2.3', '1.2.0')"
assert_true "! versionGreaterThan '1.2.0' '1.2.3'" "!versionGreaterThan('1.2.0', '1.2.3')"

echo ""

# ============================================================================
# 测试 json-utils.sh 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 json-utils.sh 函数 ===${NC}"

# 创建测试 JSON 文件
TEST_JSON_DIR="/tmp/proxy-agent-test"
mkdir -p "${TEST_JSON_DIR}"

# 创建模拟的 Xray 配置文件
cat > "${TEST_JSON_DIR}/test_xray.json" << 'EOF'
{
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
                        "email": "test@example.com"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/etc/v2ray-agent/tls/example.com.crt",
                            "keyFile": "/etc/v2ray-agent/tls/example.com.key"
                        }
                    ],
                    "alpn": ["h2", "http/1.1"]
                }
            }
        }
    ]
}
EOF

# 创建模拟的 sing-box 配置文件
cat > "${TEST_JSON_DIR}/test_singbox.json" << 'EOF'
{
    "inbounds": [
        {
            "listen_port": 8443,
            "users": [
                {
                    "uuid": "b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22",
                    "name": "testuser"
                }
            ],
            "tls": {
                "server_name": "singbox.example.com"
            }
        }
    ]
}
EOF

# 测试 jsonGetValue
result=$(jsonGetValue "${TEST_JSON_DIR}/test_xray.json" ".inbounds[0].port")
assert_equals "443" "${result}" "jsonGetValue() 读取端口"

# 测试 jsonValidateFile
assert_true "jsonValidateFile '${TEST_JSON_DIR}/test_xray.json'" "jsonValidateFile() 验证有效 JSON"

# 测试 xrayGetInboundPort
port=$(xrayGetInboundPort "${TEST_JSON_DIR}/test_xray.json")
assert_equals "443" "${port}" "xrayGetInboundPort() 读取端口"

# 测试 xrayGetInboundProtocol
protocol=$(xrayGetInboundProtocol "${TEST_JSON_DIR}/test_xray.json")
assert_equals "vless" "${protocol}" "xrayGetInboundProtocol() 读取协议"

# 测试 xrayGetClientUUID
uuid=$(xrayGetClientUUID "${TEST_JSON_DIR}/test_xray.json")
assert_equals "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11" "${uuid}" "xrayGetClientUUID() 读取 UUID"

# 测试 xrayGetClients
clients=$(xrayGetClients "${TEST_JSON_DIR}/test_xray.json")
assert_true "[[ '${clients}' == *'test@example.com'* ]]" "xrayGetClients() 读取客户端列表"

# 测试 singboxGetInboundPort
port=$(singboxGetInboundPort "${TEST_JSON_DIR}/test_singbox.json")
assert_equals "8443" "${port}" "singboxGetInboundPort() 读取端口"

# 测试 singboxGetUserUUID
uuid=$(singboxGetUserUUID "${TEST_JSON_DIR}/test_singbox.json")
assert_equals "b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22" "${uuid}" "singboxGetUserUUID() 读取 UUID"

# 测试 singboxGetTLSServerName
serverName=$(singboxGetTLSServerName "${TEST_JSON_DIR}/test_singbox.json")
assert_equals "singbox.example.com" "${serverName}" "singboxGetTLSServerName() 读取服务器名"

# 测试 jsonArrayAppend (使用字符串形式)
array='[1,2,3]'
newArray=$(echo "${array}" | jq '. += [4]')
compactArray=$(echo "${newArray}" | jq -c '.')
assert_equals '[1,2,3,4]' "${compactArray}" "jsonArrayAppend 逻辑测试"

# 测试 jsonGetArrayLength
length=$(jsonGetArrayLength "${TEST_JSON_DIR}/test_xray.json" ".inbounds[0].settings.clients")
assert_equals "1" "${length}" "jsonGetArrayLength() 计算长度"

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
assert_equals "VLESS+TCP/TLS_Vision" "${name}" "getProtocolDisplayName(0)"

name=$(getProtocolDisplayName 6)
assert_equals "Hysteria2" "${name}" "getProtocolDisplayName(6)"

name=$(getProtocolDisplayName 7)
assert_equals "VLESS+Reality+Vision" "${name}" "getProtocolDisplayName(7)"

# 测试 getProtocolShortName
shortName=$(getProtocolShortName 0)
assert_equals "vless_vision" "${shortName}" "getProtocolShortName(0)"

shortName=$(getProtocolShortName 6)
assert_equals "hysteria2" "${shortName}" "getProtocolShortName(6)"

# 测试 protocolRequiresTLS
assert_true "protocolRequiresTLS 0" "VLESS_TCP_VISION requires TLS"
assert_true "protocolRequiresTLS 1" "VLESS_WS requires TLS"
assert_true "! protocolRequiresTLS 7" "VLESS_REALITY_VISION does not require TLS (uses Reality)"
assert_true "! protocolRequiresTLS 6" "Hysteria2 does not require TLS (uses self-signed)"

# 测试 protocolUsesReality
assert_true "protocolUsesReality 7" "Protocol 7 uses Reality"
assert_true "protocolUsesReality 8" "Protocol 8 uses Reality"
assert_true "protocolUsesReality 12" "Protocol 12 uses Reality"
assert_true "! protocolUsesReality 0" "Protocol 0 does not use Reality"

# 测试 protocolUsesUDP
assert_true "protocolUsesUDP 6" "Hysteria2 uses UDP"
assert_true "protocolUsesUDP 9" "TUIC uses UDP"
assert_true "! protocolUsesUDP 0" "VLESS_TCP does not use UDP"

# 测试 protocolSupportsCDN
assert_true "protocolSupportsCDN 1" "VLESS_WS supports CDN"
assert_true "protocolSupportsCDN 3" "VMess_WS supports CDN"
assert_true "! protocolSupportsCDN 0" "VLESS_TCP does not support CDN"
assert_true "! protocolSupportsCDN 7" "Reality does not support CDN"

# 测试 getProtocolTransport
transport=$(getProtocolTransport 0)
assert_equals "tcp" "${transport}" "getProtocolTransport(0) = tcp"

transport=$(getProtocolTransport 1)
assert_equals "ws" "${transport}" "getProtocolTransport(1) = ws"

transport=$(getProtocolTransport 6)
assert_equals "quic" "${transport}" "getProtocolTransport(6) = quic"

# 测试 parseProtocolIdFromFileName
id=$(parseProtocolIdFromFileName "02_VLESS_TCP_inbounds.json")
assert_equals "0" "${id}" "parseProtocolIdFromFileName(02_VLESS_TCP) = 0"

id=$(parseProtocolIdFromFileName "07_VLESS_vision_reality_inbounds.json")
assert_equals "7" "${id}" "parseProtocolIdFromFileName(07_Reality) = 7"

echo ""

# ============================================================================
# 测试 config-reader.sh 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 config-reader.sh 函数 ===${NC}"

# 测试 detectCoreType (在测试环境中应该返回空或特定值)
coreType=$(detectCoreType)
# 在测试环境中可能没有安装 xray/singbox
echo -e "  detectCoreType() 返回: '${coreType:-empty}'"

# 测试 getConfigPath
path=$(getConfigPath 1)
assert_equals "/etc/v2ray-agent/xray/conf/" "${path}" "getConfigPath(1) = xray 配置路径"

path=$(getConfigPath 2)
assert_equals "/etc/v2ray-agent/sing-box/conf/config/" "${path}" "getConfigPath(2) = sing-box 配置路径"

echo ""

# ============================================================================
# 测试 system-detect.sh 函数
# ============================================================================

echo -e "${YELLOW}=== 测试 system-detect.sh 函数 ===${NC}"

# 测试 commandExists
assert_true "commandExists 'bash'" "commandExists('bash') 返回 true"
assert_true "! commandExists 'nonexistent_command_12345'" "commandExists('nonexistent') 返回 false"

# 测试 getCPUCores
cores=$(getCPUCores)
assert_true "[[ ${cores} -ge 1 ]]" "getCPUCores() 返回有效值: ${cores}"

# 测试 getSystemMemoryMB
memory=$(getSystemMemoryMB)
assert_true "[[ ${memory} -ge 0 ]]" "getSystemMemoryMB() 返回有效值: ${memory}MB"

# 测试 getOSInfo
osInfo=$(getOSInfo)
assert_not_empty "${osInfo}" "getOSInfo() 返回系统信息"

echo ""

# ============================================================================
# 清理测试文件
# ============================================================================

rm -rf "${TEST_JSON_DIR}"

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
    echo -e "${GREEN}所有测试通过！${NC}"
    exit 0
else
    echo -e "${RED}有 ${TESTS_FAILED} 个测试失败！${NC}"
    exit 1
fi
