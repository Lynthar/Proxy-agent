#!/usr/bin/env bash
# Language Loader for v2ray-agent
# This script loads the appropriate language file based on LANG_CODE environment variable
# Usage: source this file after setting LANG_CODE (default: zh_CN)

_LANG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LANG_CODE:=zh_CN}"

# Map common language codes to our supported languages
case "${LANG_CODE}" in
    en*|EN*) LANG_CODE="en_US" ;;
    zh*|ZH*) LANG_CODE="zh_CN" ;;
esac

# Load language file
if [[ -f "${_LANG_DIR}/${LANG_CODE}.sh" ]]; then
    source "${_LANG_DIR}/${LANG_CODE}.sh"
else
    # Fallback to Chinese
    source "${_LANG_DIR}/zh_CN.sh"
fi

unset _LANG_DIR
