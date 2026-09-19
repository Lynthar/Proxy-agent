#!/usr/bin/env bash
# ============================================================================
# utils.sh - 纯工具函数（无副作用，不写全局变量）
# ============================================================================

# 防止重复加载
[[ -n "${_UTILS_LOADED:-}" ]] && return 0
readonly _UTILS_LOADED=1

# ============================================================================
# 颜色输出函数
# ============================================================================

# 彩色输出。red 是错误通道：打印后返回 1，让「打了错误」等于「失败」，调用方可以
# `echoContent red …` 收尾或 `fn || …` 直接把失败传上去；其余颜色返回 0。
# 用法: echoContent red "错误信息" / echoContent green "成功信息"
echoContent() {
    local color="$1"
    local content="$2"

    case "${color}" in
        red)
            echo -e "\033[31m${content}\033[0m"
            return 1
            ;;
        green)
            echo -e "\033[32m${content}\033[0m"
            ;;
        yellow)
            echo -e "\033[33m${content}\033[0m"
            ;;
        blue)
            echo -e "\033[34m${content}\033[0m"
            ;;
        purple)
            echo -e "\033[35m${content}\033[0m"
            ;;
        skyBlue)
            # 粗体青（[1;36m）与历史 inline 版本一致；视觉上比普通青更突出，
            # 适合标题/分隔符。改这个会让全脚本所有 skyBlue 输出加粗。
            echo -e "\033[1;36m${content}\033[0m"
            ;;
        white)
            echo -e "\033[37m${content}\033[0m"
            ;;
        *)
            echo -e "${content}"
            ;;
    esac
}

# ============================================================================
# 字符串处理函数
# ============================================================================

# stripAnsi TEXT → 去掉 ANSI 控制序列
# 终止符按 [a-zA-Z] 宽匹配（不止 m/J/K），cursor 移动等序列同样要清掉——
# install.sh 用它洗用户粘贴的凭据。
stripAnsi() {
    echo -e "$@" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

# 去除字符串首尾空格
# 用法: trimmed=$(trim "  hello  ")
trim() {
    local str="$1"
    # 去除开头空格
    str="${str#"${str%%[![:space:]]*}"}"
    # 去除结尾空格
    str="${str%"${str##*[![:space:]]}"}"
    echo "${str}"
}

# ============================================================================
# 数值处理函数
# ============================================================================

# 生成随机数 - 使用更安全的随机源
# 用法: num=$(randomNum 1000 9999)
# 注意: 对于非敏感场景，使用 /dev/urandom 提供足够的随机性
randomNum() {
    local min="${1:-0}"
    local max="${2:-65535}"
    local range=$((max - min + 1))

    # 优先使用 /dev/urandom（更安全）
    if [[ -r /dev/urandom ]]; then
        local random_bytes
        random_bytes=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
        echo $((random_bytes % range + min))
    # 回退到 shuf（如果可用）
    elif command -v shuf &>/dev/null; then
        shuf -i "${min}-${max}" -n 1
    # 最后回退到 $RANDOM（不够安全，但保证兼容性）
    else
        echo $((RANDOM % range + min))
    fi
}

# 生成随机端口 (10000-30000)
# 用法: port=$(randomPort)
randomPort() {
    randomNum 10000 30000
}

# ============================================================================
# 版本比较函数
# ============================================================================

# 比较版本号
# 用法: if versionGreaterThan "1.2.3" "1.2.0"; then ...
# 返回: 0 如果 v1 > v2
versionGreaterThan() {
    local v1="$1"
    local v2="$2"
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" != "$v1" ]]
}

# 比较版本号 (大于等于)
# 用法: if versionGreaterOrEqual "1.2.3" "1.2.0"; then ...
versionGreaterOrEqual() {
    local v1="$1"
    local v2="$2"
    [[ "$v1" == "$v2" ]] || versionGreaterThan "$v1" "$v2"
}

# ============================================================================
# 时间相关函数
# ============================================================================

# 获取当前时间戳
# 用法: ts=$(timestamp)
timestamp() {
    date +%s
}

# ============================================================================
# 用户输入解析
# ============================================================================

# isYesInput STR → 0=是。只认 y/yes（大小写不敏感）；yy/yep/yeah/空串一律否。
# 放宽之前先想清楚哪个破坏性操作会因此被误触发。
isYesInput() {
    case "${1,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# geosite 分类清单
# ============================================================================

# geositeListHasCategory LISTFILE NAME → 0 表示 NAME 是清单里的一个分类（大小写不敏感）。
# LISTFILE 是 v2fly domain-list-community 发布的 dlc.dat_plain.yml，条目形如 `- name: "google"`
geositeListHasCategory() {
    local listFile="$1" name="${2,,}"
    if [[ ! -s "${listFile}" || -z "${name}" ]]; then
        return 1
    fi
    sed -nE 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "${listFile}" \
        | tr '[:upper:]' '[:lower:]' | grep -qxF -- "${name}"
}

# ============================================================================
# 分享链接 / ACME 参数拼装
# ============================================================================

# realityPqvParam VERIFY [qr] → "&pqv=VERIFY"；qr 形态输出百分号编码的 "%26pqv%3DVERIFY"。
# VERIFY 为空输出空串——否则链接里会出现 pqv=&… 这种空参数
realityPqvParam() {
    local verify="$1"
    if [[ -z "${verify}" ]]; then
        return 0
    fi
    if [[ "$2" == "qr" ]]; then
        printf '%%26pqv%%3D%s' "${verify}"
    else
        printf '&pqv=%s' "${verify}"
    fi
}

# acmeIssueDomainArgs DOMAIN PARENT WILDCARD → acme.sh --issue 的 -d 参数串（值带单引号，供 bash -c 拼装）。
# WILDCARD 为是时签 *.PARENT + PARENT，否则只签 DOMAIN——非通配符再追加 PARENT，
# 公共后缀下的域名（xx.dpdns.org）会因根域不归用户而签发失败
acmeIssueDomainArgs() {
    if isYesInput "$3"; then
        printf -- "-d '*.%s' -d '%s'" "$2" "$2"
    else
        printf -- "-d '%s'" "$1"
    fi
}

# Dry-run 计划模式：DRY_RUN=1 时 mutator 入口回显计划并直接返回，不写配置、不申请证书、
# 不改 firewall、不重启服务。bootstrap 与 doctor 不受影响。

# 是否处于 dry-run 模式
# 用法: if isDryRun; then ... fi
isDryRun() {
    [[ "${DRY_RUN:-0}" == "1" ]]
}

# planAction TEXT → 0=dry-run 已生效（调用方须立即 return 0）；1=非 dry-run，继续真实逻辑
# 用法: if planAction "$(t PLAN_UNINSTALL_ALL)"; then return 0; fi
planAction() {
    if isDryRun; then
        echoContent yellow "[plan] $*"
        return 0
    fi
    return 1
}
