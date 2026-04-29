#!/usr/bin/env bash
# =============================================================================
# i18n Language Loader for Proxy-agent
# 国际化语言加载器
# =============================================================================
# Usage:
#   V2RAY_LANG=en bash install.sh    # English
#   V2RAY_LANG=zh bash install.sh    # Chinese (default)
# =============================================================================

# 语言文件目录
# 优先用 install.sh 设的 ${_SCRIPT_DIR}/shell/lang；当主脚本与 lib/ 不同源时
# （例如 lib/ 从 /etc/Proxy-agent/lib fallback 加载、_SCRIPT_DIR 仍指向 /root），
# 退回到 lib/i18n.sh 自身位置上一级的 shell/lang/，与 lib/ 配套。
# 旧的 ${_SCRIPT_DIR:-fallback} 写法只在 _SCRIPT_DIR 为空时才走 fallback，
# _SCRIPT_DIR 设到了错误目录时反而不会兜底。
if [[ -n "${_SCRIPT_DIR:-}" && -d "${_SCRIPT_DIR}/shell/lang" ]]; then
    _I18N_DIR="${_SCRIPT_DIR}/shell/lang"
else
    _I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shell/lang"
fi

# =============================================================================
# 语言检测 - Language Detection
# 优先级: V2RAY_LANG > 持久配置文件 > LANGUAGE > LANG > 默认中文
# =============================================================================
_detect_language() {
    local lang=""
    local langFile="/etc/Proxy-agent/lang_pref"

    # 优先级1: 环境变量 V2RAY_LANG
    if [[ -n "${V2RAY_LANG:-}" ]]; then
        lang="${V2RAY_LANG}"
    # 优先级2: 持久化语言配置文件
    elif [[ -f "${langFile}" ]]; then
        lang=$(cat "${langFile}" 2>/dev/null)
    # 优先级3: 系统环境变量
    else
        lang="${LANGUAGE:-${LANG:-zh_CN}}"
    fi

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
    local text="${!key-}"
    if [[ -z "${text}" ]]; then
        # 找不到翻译：回退到 key 名，便于定位
        text="$1"
        # 仅在调试模式下记录缺失键，避免正常运行写磁盘
        if [[ -n "${V2RAY_I18N_DEBUG:-}" ]]; then
            local logFile="${V2RAY_I18N_LOG:-/tmp/proxy-agent-i18n-missing.log}"
            echo "$(date +%FT%T) ${CURRENT_LANG:-?} MSG_$1" >>"${logFile}" 2>/dev/null || true
        fi
    fi
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
