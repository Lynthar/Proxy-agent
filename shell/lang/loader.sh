#!/usr/bin/env bash
# =============================================================================
# Language Loader for v2ray-agent (Legacy Compatibility)
# 语言加载器 - 向后兼容层
# =============================================================================
# NOTE: This file is kept for backward compatibility.
# The main i18n system is now in lib/i18n.sh
#
# New Usage:
#   V2RAY_LANG=en bash install.sh    # English
#   V2RAY_LANG=zh bash install.sh    # Chinese (default)
# =============================================================================

# If lib/i18n.sh exists, delegate to it
_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_I18N="${_LOADER_DIR}/../../lib/i18n.sh"

if [[ -f "${_LIB_I18N}" ]]; then
    # shellcheck source=/dev/null
    source "${_LIB_I18N}"
else
    # Fallback: Direct loading (legacy mode)
    : "${LANG_CODE:=${V2RAY_LANG:-zh_CN}}"

    case "${LANG_CODE}" in
        en*|EN*) LANG_CODE="en_US" ;;
        zh*|ZH*|*) LANG_CODE="zh_CN" ;;
    esac

    if [[ -f "${_LOADER_DIR}/${LANG_CODE}.sh" ]]; then
        # shellcheck source=/dev/null
        source "${_LOADER_DIR}/${LANG_CODE}.sh"
    else
        # shellcheck source=/dev/null
        source "${_LOADER_DIR}/zh_CN.sh"
    fi

    # Legacy t() function
    t() {
        local key="MSG_$1"
        local text="${!key:-$1}"
        shift
        if [[ $# -gt 0 ]]; then
            # shellcheck disable=SC2059
            printf "${text}" "$@"
        else
            echo "${text}"
        fi
    }
fi

unset _LOADER_DIR _LIB_I18N
