#!/usr/bin/env bash
# =============================================================================
# i18n Language Loader for v2ray-agent
# 国际化语言加载器
# =============================================================================
# Usage:
#   V2RAY_LANG=en bash install.sh    # English
#   V2RAY_LANG=zh bash install.sh    # Chinese (default)
# =============================================================================

# 语言文件目录
_I18N_DIR="${_SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}/shell/lang"

# =============================================================================
# 语言检测 - Language Detection
# 优先级: V2RAY_LANG > LANGUAGE > LANG > 默认中文
# =============================================================================
_detect_language() {
    local lang="${V2RAY_LANG:-${LANGUAGE:-${LANG:-zh_CN}}}"
    case "${lang}" in
        en*|EN*) echo "en_US" ;;
        zh*|ZH*|*) echo "zh_CN" ;;  # 默认中文
    esac
}

# =============================================================================
# 加载语言文件 - Load Language File
# =============================================================================
_load_i18n() {
    local lang_code
    lang_code=$(_detect_language)
    local lang_file="${_I18N_DIR}/${lang_code}.sh"

    if [[ -f "${lang_file}" ]]; then
        # shellcheck source=/dev/null
        source "${lang_file}"
        export CURRENT_LANG="${lang_code}"
    else
        # 回退到中文
        if [[ -f "${_I18N_DIR}/zh_CN.sh" ]]; then
            # shellcheck source=/dev/null
            source "${_I18N_DIR}/zh_CN.sh"
            export CURRENT_LANG="zh_CN"
        fi
    fi
}

# =============================================================================
# 消息获取函数 - Message Getter Function
# =============================================================================
# 用法 / Usage:
#   $(t "KEY")                    # 简单消息
#   $(t "KEY" "arg1" "arg2")      # 带参数 (使用 %s 占位符)
#
# 示例 / Examples:
#   echoContent yellow "$(t PROMPT_SELECT)"
#   echoContent red "$(t ERR_PORT_OCCUPIED "${port}")"
# =============================================================================
t() {
    local key="MSG_$1"
    local text="${!key:-$1}"  # 如果找不到则显示 key 本身
    shift

    if [[ $# -gt 0 ]]; then
        # 支持 printf 格式化 (%s, %d 等)
        # shellcheck disable=SC2059
        printf "${text}" "$@"
    else
        echo "${text}"
    fi
}

# =============================================================================
# 初始化 - Initialize
# =============================================================================
_load_i18n

# 清理内部变量
unset _I18N_DIR
