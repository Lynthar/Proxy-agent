#!/usr/bin/env bash
# =============================================================================
# i18n Language Loader — V2RAY_LANG=en|zh bash install.sh
# =============================================================================

# 语言文件目录：优先 ${_SCRIPT_DIR}/shell/lang，否则退到本文件上一级的 shell/lang/。
# 后者兜住「主脚本与 lib/ 不同源」——不要改回 ${_SCRIPT_DIR:-fallback}，那种写法只在变量
# 为空时兜底，而故障形态是它被设到了错误目录。
if [[ -n "${_SCRIPT_DIR:-}" && -d "${_SCRIPT_DIR}/shell/lang" ]]; then
    _I18N_DIR="${_SCRIPT_DIR}/shell/lang"
else
    _I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shell/lang"
fi

# 语言检测优先级: V2RAY_LANG > 持久配置文件 > 默认 zh_CN
# 不看 $LANG / $LANGUAGE —— install.sh 顶部 export LANG=en_US.UTF-8 会把默认值劫持成英文。
_detect_language() {
    local lang=""
    local langFile="/etc/Proxy-agent/lang_pref"

    # 优先级 1: 环境变量 V2RAY_LANG
    if [[ -n "${V2RAY_LANG:-}" ]]; then
        lang="${V2RAY_LANG}"
    # 优先级 2: 持久化语言配置文件
    elif [[ -f "${langFile}" ]]; then
        lang=$(cat "${langFile}" 2>/dev/null)
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

# t KEY [ARG...] → 取翻译，ARG 填 %s 占位符
# 用法: echoContent red "$(t ERR_PORT_OCCUPIED "${port}")"
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
