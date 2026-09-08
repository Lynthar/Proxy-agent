#!/usr/bin/env bash
# ============================================================================
# json-utils.sh - JSON 读取、校验、原子写入（封装 jq，统一错误处理）
# ============================================================================

# 防止重复加载
[[ -n "${_JSON_UTILS_LOADED:-}" ]] && return 0
readonly _JSON_UTILS_LOADED=1

# ============================================================================
# 原子文件写入函数
# ============================================================================

# jsonWriteFile FILE CONTENT [BACKUP=true] → 0=成功 1=失败
# 验证语法 → 可选备份 → 写 mktemp → 原子 rename；任一步失败原文件不变。
jsonWriteFile() {
    local file="$1"
    local content="$2"
    local backup="${3:-true}"

    # 验证 JSON 语法
    if ! echo "${content}" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    # 可选备份
    if [[ "${backup}" == "true" && -f "${file}" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # 临时文件建在目标同目录——/tmp 与目标跨文件系统时 mv 退化为 copy+unlink，不再原子
    local tmpFile
    tmpFile=$(mktemp "${file}.tmp.XXXXXXXX") || return 1
    if ! echo "${content}" | jq . > "${tmpFile}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    # 原子移动
    if ! mv "${tmpFile}" "${file}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    return 0
}

# jsonModifyFile FILE JQ_FILTER [BACKUP=true] → 0=成功 1=失败
# 验证源文件 → 可选备份 → jq 到 mktemp → 验证结果 → 原子 rename。
jsonModifyFile() {
    local file="$1"
    local filter="$2"
    local backup="${3:-true}"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # 验证源文件
    if ! jq -e . "${file}" >/dev/null 2>&1; then
        return 1
    fi

    # 可选备份
    if [[ "${backup}" == "true" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # 临时文件建在目标同目录——/tmp 与目标跨文件系统时 mv 退化为 copy+unlink，不再原子
    local tmpFile
    tmpFile=$(mktemp "${file}.tmp.XXXXXXXX") || return 1
    if ! jq "${filter}" "${file}" > "${tmpFile}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    # 验证结果
    if ! jq -e . "${tmpFile}" >/dev/null 2>&1; then
        rm -f "${tmpFile}"
        return 1
    fi

    # 原子移动
    if ! mv "${tmpFile}" "${file}" 2>/dev/null; then
        rm -f "${tmpFile}"
        return 1
    fi

    return 0
}

# ============================================================================
# 多文件写事务（Begin → Track 逐文件快照 → 修改 → Commit / Rollback）
# ============================================================================

# jsonTxBegin [BASE_DIR=/etc/Proxy-agent] → 0=事务已开启
# 快照目录建在 BASE_DIR 下（与目标文件同文件系统，恢复用 cp 不依赖 rename 语义）。
jsonTxBegin() {
    local baseDir="${1:-/etc/Proxy-agent}"
    [[ -d "${baseDir}" ]] || return 1
    _JSON_TX_DIR=$(mktemp -d "${baseDir}/.txn.XXXXXX") || return 1
    _JSON_TX_FILES=()
    return 0
}

# jsonTxTrack FILE → 把 FILE 纳入事务保护（必须在修改它之前调用）
# 首次 Track 快照当前内容；文件不存在则记为「回滚时删除」；重复 Track 只记第一次。
jsonTxTrack() {
    local file="$1"
    [[ -z "${_JSON_TX_DIR:-}" || -z "${file}" ]] && return 1
    local entry
    for entry in "${_JSON_TX_FILES[@]}"; do
        [[ "${entry}" == "${file}" ]] && return 0
    done
    local idx=${#_JSON_TX_FILES[@]}
    if [[ -f "${file}" ]]; then
        cp -p "${file}" "${_JSON_TX_DIR}/${idx}.snap" || return 1
    fi
    _JSON_TX_FILES+=("${file}")
    return 0
}

# jsonTxRollback → 所有 Track 过的文件恢复到快照（Track 前不存在的删除），关闭事务
jsonTxRollback() {
    [[ -z "${_JSON_TX_DIR:-}" ]] && return 1
    local i file
    for ((i = ${#_JSON_TX_FILES[@]} - 1; i >= 0; i--)); do
        file="${_JSON_TX_FILES[$i]}"
        if [[ -f "${_JSON_TX_DIR}/${i}.snap" ]]; then
            cp -p "${_JSON_TX_DIR}/${i}.snap" "${file}"
        else
            rm -f "${file}"
        fi
    done
    rm -rf "${_JSON_TX_DIR}"
    _JSON_TX_DIR=
    _JSON_TX_FILES=()
    return 0
}

# jsonTxCommit → 丢弃快照并关闭事务（写入在修改时已落盘，本调用只做收尾）
jsonTxCommit() {
    [[ -z "${_JSON_TX_DIR:-}" ]] && return 1
    rm -rf "${_JSON_TX_DIR}"
    _JSON_TX_DIR=
    _JSON_TX_FILES=()
    return 0
}
