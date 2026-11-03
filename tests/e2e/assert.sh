#!/usr/bin/env bash
# assert.sh → 真装机测试共用的断言与计数（被 test_install_e2e.sh / test_install_domain_e2e.sh source），末尾 e2eSummary 打印汇总并按失败数退出

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

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

# e2eSummary LABEL LOG → 打印通过 / 失败数；有失败时指向完整安装输出，按失败数决定退出码
e2eSummary() {
    echo ""
    echo "=============================================="
    echo -e "${YELLOW}测试结果汇总${NC}"
    echo "=============================================="
    echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
    echo ""
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}$1全部通过！${NC}"
        exit 0
    fi
    echo -e "${RED}有 ${TESTS_FAILED} 个测试失败！完整安装输出在 $2${NC}"
    exit 1
}
