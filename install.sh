#!/usr/bin/env bash
# 检测区
# -------------------------------------------------------------
# 检查系统
export LANG=en_US.UTF-8

# ============================================================================
# 不用 set -e（大量命令允许失败），但开 pipefail 让管道错误可见
# ============================================================================
set -o pipefail

# Debian / RHEL 的 cron 给任务的 PATH 只有 /usr/bin:/bin，nginx、iptables、getenforce、rc-service 都在 sbin，
# 不补就当成没装：定时任务起不了 nginx，cron 里跑的 doctor 报假的「没有防火墙」
PATH="/usr/local/sbin:/usr/sbin:/sbin:${PATH}"

# Bash 4.3+ 硬要求：用到 nameref（local -n）与负数组下标 ${arr[-1]}，CentOS 7 的
# 4.2.46 会在这些路径上静默失败。守卫自身只用 4.3 以前的语法。
if [[ -z "${BASH_VERSINFO:-}" ]] || (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "[Proxy-agent] 需要 Bash 4.3 或更高版本，当前为 ${BASH_VERSION:-非 bash}。" >&2
    echo "[Proxy-agent] requires Bash >= 4.3, current: ${BASH_VERSION:-not bash}." >&2
    exit 1
fi

# ============================================================================
# 模块加载：lib/ 存在则加载模块化组件
# ============================================================================

# 解析符号链接：pasly 是 /usr/bin/pasly → ${PROXY_AGENT_DIR}/install.sh 的
# symlink。不解析的话 _SCRIPT_DIR 会停在 /usr/bin，找不到 lib/。
# readlink -f 在 BusyBox（Alpine）和 GNU coreutils 上都默认支持。
_SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    _SCRIPT_PATH="$(readlink -f "${_SCRIPT_PATH}" 2>/dev/null || echo "${_SCRIPT_PATH}")"
fi
_SCRIPT_DIR="$(cd "$(dirname "${_SCRIPT_PATH}")" && pwd)"

# 安装根：环境变量可覆盖，lib/constants.sh 的整套布局都从它派生。unInstall 会对它 rm -rf，
# 所以只收「至少两级、只含 [A-Za-z0-9._-]」的绝对路径，根目录 / 一级目录 / 带通配符的一律拒绝。
PROXY_AGENT_DIR="${PROXY_AGENT_DIR:-/etc/Proxy-agent}"
PROXY_AGENT_DIR="${PROXY_AGENT_DIR%/}"
if [[ ! "${PROXY_AGENT_DIR}" =~ ^(/\.*[A-Za-z0-9_-][A-Za-z0-9._-]*){2,}$ ]]; then
    echo "[Proxy-agent] PROXY_AGENT_DIR 必须是至少两级、只含 [A-Za-z0-9._-] 的绝对路径：${PROXY_AGENT_DIR}" >&2
    echo "[Proxy-agent] PROXY_AGENT_DIR must be an absolute path at least two levels deep, using only [A-Za-z0-9._-]: ${PROXY_AGENT_DIR}" >&2
    exit 1
fi

# lib/ 优先与 install.sh 同级；否则回退到运行时安装根下的 lib/。
# 让"pasly 调用"和"用户重新 wget /root/install.sh 但本机已装过一次"
# 这两条路径都能找到模块。
_LIB_FALLBACK_DIR="${PROXY_AGENT_DIR}/lib"
_LANG_FALLBACK_DIR="${PROXY_AGENT_DIR}/shell/lang"
_LIB_DIR="${_SCRIPT_DIR}/lib"
if [[ ! -d "${_LIB_DIR}" && -d "${_LIB_FALLBACK_DIR}" ]]; then
    _LIB_DIR="${_LIB_FALLBACK_DIR}"
fi

# 自举下载：lib/ 与 shell/lang/ 本机缺失、或存在但 bash -n 不通过时从 GitHub 拉。
# 先全下到 mktemp、校验通过才原子 mv，失败时目标位置零污染。
# 旁路：PROXY_AGENT_NO_BOOTSTRAP / PROXY_AGENT_BOOTSTRAP_REF / PROXY_AGENT_BOOTSTRAP_MODE。
_lib_health_ok=1
if [[ -z "${PROXY_AGENT_NO_BOOTSTRAP:-}" || "${BASH_SOURCE[0]}" != "$0" ]]; then
    for _f in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
        if [[ ! -f "${_LIB_DIR}/${_f}.sh" ]] || ! bash -n "${_LIB_DIR}/${_f}.sh" 2>/dev/null; then
            _lib_health_ok=
            break
        fi
    done
fi
# source 只加载完整的本地库；自动修复会下载或删除文件，必须留给直接执行。
if [[ "${BASH_SOURCE[0]}" != "$0" && -z "${_lib_health_ok}" ]]; then
    printf '[Proxy-agent] source requires a complete local lib/ directory.\n' >&2
    return 1
fi
if [[ -z "${_lib_health_ok}" && -z "${PROXY_AGENT_NO_BOOTSTRAP:-}" ]]; then
    # 删除可能残留的损坏文件，确保 bootstrap 后是干净状态（避免半新半旧混合）
    if [[ -d "${_LIB_DIR}" ]]; then
        for _f in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
            if [[ -f "${_LIB_DIR}/${_f}.sh" ]] && ! bash -n "${_LIB_DIR}/${_f}.sh" 2>/dev/null; then
                printf '\033[33m[bootstrap] 检测到损坏的 %s/%s.sh，将重新下载\033[0m\n' "${_LIB_DIR}" "${_f}" >&2
                rm -f "${_LIB_DIR}/${_f}.sh"
            fi
        done
    fi
    _bootstrap_libs() {
        local ref="${PROXY_AGENT_BOOTSTRAP_REF:-master}"
        local mode="${PROXY_AGENT_BOOTSTRAP_MODE:-auto}"
        local rawBase="https://raw.githubusercontent.com/Lynthar/Proxy-agent/${ref}"
        local apiUrl="https://api.github.com/repos/Lynthar/Proxy-agent/releases/latest"
        local libDst="${_LIB_FALLBACK_DIR}"
        local langDst="${_LANG_FALLBACK_DIR}"
        local libFiles=(i18n.sh constants.sh utils.sh json-utils.sh system-detect.sh protocol-registry.sh carpool.sh topo.sh)
        local langFiles=(zh_CN.sh en_US.sh)
        local fetcher tmpDir

        if command -v curl >/dev/null 2>&1; then
            fetcher=curl
        elif command -v wget >/dev/null 2>&1; then
            fetcher=wget
        else
            printf '\033[31m[FATAL] lib/ 缺失，且本机既无 curl 也无 wget，无法自举下载\033[0m\n' >&2
            printf '\033[31m[FATAL] lib/ missing; neither curl nor wget available for bootstrap\033[0m\n' >&2
            return 1
        fi

        printf '\033[36m[bootstrap] lib/ 不存在，开始拉取依赖文件（mode=%s）...\033[0m\n' "${mode}" >&2

        if ! tmpDir="$(mktemp -d -t proxy-agent-bootstrap-XXXXXX 2>/dev/null)"; then
            printf '\033[31m[FATAL] 无法创建临时目录用于自举下载\033[0m\n' >&2
            return 1
        fi

        # 内层 helper：URL → 文件
        _fetch_to_file() {
            local _url="$1" _dst="$2"
            if [[ "${fetcher}" == curl ]]; then
                curl -fsSL --connect-timeout 10 -m 60 -o "${_dst}" "${_url}" 2>/dev/null
            else
                wget -q --timeout=15 -O "${_dst}" "${_url}" 2>/dev/null
            fi
        }

        # 内层 helper：URL → stdout（用于抓 GitHub API 响应）
        _fetch_to_stdout() {
            local _url="$1"
            if [[ "${fetcher}" == curl ]]; then
                curl -fsSL --connect-timeout 10 -m 30 "${_url}" 2>/dev/null
            else
                wget -q --timeout=15 -O - "${_url}" 2>/dev/null
            fi
        }

        # ----------------------------------------------------------------
        # 模式 1：release tarball + SHA256（强校验），解到 tmpDir
        # ----------------------------------------------------------------
        _try_release_bundle() {
            local releaseInfo bundleUrl shaUrl
            local bundleFile="${tmpDir}/lib_bundle.tar.gz"
            local shaFile="${tmpDir}/lib_bundle.tar.gz.sha256"
            local expectedHash actualHash

            printf '\033[36m[bootstrap] 探测最新 release 的 lib_bundle.tar.gz...\033[0m\n' >&2

            releaseInfo="$(_fetch_to_stdout "${apiUrl}")" || {
                printf '\033[33m[bootstrap] 抓不到 release 元信息（API 不可达或限流）\033[0m\n' >&2
                return 1
            }

            # 从 GitHub API JSON 抓 browser_download_url——尾随 lib_bundle.tar.gz 的取 bundle，
            # 尾随 .sha256 的取 sha 文件。sed 一行一行匹配，head -1 防多 release 历史资产串入。
            bundleUrl="$(printf '%s' "${releaseInfo}" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*lib_bundle\.tar\.gz\)".*/\1/p' | head -1)"
            shaUrl="$(printf '%s' "${releaseInfo}" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*lib_bundle\.tar\.gz\.sha256\)".*/\1/p' | head -1)"

            if [[ -z "${bundleUrl}" || -z "${shaUrl}" ]]; then
                printf '\033[33m[bootstrap] 当前 release 没有 lib_bundle 资产（旧 release / pre-release）\033[0m\n' >&2
                return 1
            fi

            if ! _fetch_to_file "${bundleUrl}" "${bundleFile}"; then
                printf '\033[33m[bootstrap] 下载 lib_bundle.tar.gz 失败\033[0m\n' >&2
                return 1
            fi
            if ! _fetch_to_file "${shaUrl}" "${shaFile}"; then
                printf '\033[33m[bootstrap] 下载 lib_bundle.tar.gz.sha256 失败\033[0m\n' >&2
                return 1
            fi

            # SHA256 文件格式："<64-hex>  lib_bundle.tar.gz"，取第一列
            expectedHash="$(awk '{print $1}' "${shaFile}" 2>/dev/null)"
            if [[ ! "${expectedHash}" =~ ^[0-9a-fA-F]{64}$ ]]; then
                printf '\033[31m[bootstrap] sha256 文件内容异常（不是 64 位 hex）\033[0m\n' >&2
                return 1
            fi
            if ! command -v sha256sum >/dev/null 2>&1; then
                printf '\033[33m[bootstrap] 缺少 sha256sum 命令，无法做强校验\033[0m\n' >&2
                return 1
            fi
            actualHash="$(sha256sum "${bundleFile}" 2>/dev/null | awk '{print $1}')"
            if [[ "${actualHash}" != "${expectedHash}" ]]; then
                printf '\033[31m[FATAL] tarball SHA256 不匹配，丢弃\033[0m\n' >&2
                printf '\033[31m  expected: %s\033[0m\n' "${expectedHash}" >&2
                printf '\033[31m  actual:   %s\033[0m\n' "${actualHash}" >&2
                return 1
            fi

            # 不还原包里的属主：root 解包默认照搬，旧版 Release 的包归 CI runner 的 uid，root 要 source 的脚本就归了它
            if ! tar --no-same-owner -xzf "${bundleFile}" -C "${tmpDir}" 2>/dev/null; then
                printf '\033[31m[bootstrap] 解压 tarball 失败\033[0m\n' >&2
                return 1
            fi

            # 验证：解压结果包含期望的目录结构 + 关键文件能 bash -n
            local f
            for f in "${libFiles[@]}"; do
                if [[ ! -f "${tmpDir}/lib/${f}" ]]; then
                    printf '\033[31m[bootstrap] tarball 缺少 lib/%s\033[0m\n' "${f}" >&2
                    return 1
                fi
                if ! bash -n "${tmpDir}/lib/${f}" 2>/dev/null; then
                    printf '\033[31m[bootstrap] tarball 内 lib/%s 语法不合法\033[0m\n' "${f}" >&2
                    return 1
                fi
            done
            for f in "${langFiles[@]}"; do
                if [[ ! -f "${tmpDir}/shell/lang/${f}" ]]; then
                    printf '\033[31m[bootstrap] tarball 缺少 shell/lang/%s\033[0m\n' "${f}" >&2
                    return 1
                fi
                if ! bash -n "${tmpDir}/shell/lang/${f}" 2>/dev/null; then
                    printf '\033[31m[bootstrap] tarball 内 shell/lang/%s 语法不合法\033[0m\n' "${f}" >&2
                    return 1
                fi
            done

            rm -f "${bundleFile}" "${shaFile}"
            printf '\033[32m[bootstrap] release tarball 校验通过（SHA256 匹配）\033[0m\n' >&2
            return 0
        }

        # ----------------------------------------------------------------
        # 模式 2：raw 单文件下载（弱校验，仅 bash -n）
        # ----------------------------------------------------------------
        _try_raw_files() {
            printf '\033[36m[bootstrap] 从 GitHub raw @ %s 单文件下载...\033[0m\n' "${ref}" >&2
            local _subdir _name _url _dst
            _fetch_one() {
                _subdir="$1" _name="$2"
                _url="${rawBase}/${_subdir}/${_name}"
                _dst="${tmpDir}/${_subdir}/${_name}"
                mkdir -p "$(dirname "${_dst}")" || return 1
                if ! _fetch_to_file "${_url}" "${_dst}"; then
                    printf '\033[31m[bootstrap] 下载 %s/%s 失败 (%s)\033[0m\n' "${_subdir}" "${_name}" "${_url}" >&2
                    return 1
                fi
                if ! bash -n "${_dst}" 2>/dev/null; then
                    printf '\033[31m[bootstrap] %s/%s 内容不是合法 bash 脚本（可能是 GitHub 错误页）\033[0m\n' "${_subdir}" "${_name}" >&2
                    return 1
                fi
            }
            local f
            for f in "${libFiles[@]}"; do
                _fetch_one lib "${f}" || { unset -f _fetch_one; return 1; }
            done
            for f in "${langFiles[@]}"; do
                _fetch_one shell/lang "${f}" || { unset -f _fetch_one; return 1; }
            done
            # VERSION 是 best-effort：拉到就部署，拉不到就让 _load_version 走 API 兜底，
            # 不让它失败把整个 raw 流程拖死。release 模式自带 VERSION 在 tarball 里。
            _fetch_to_file "${rawBase}/VERSION" "${tmpDir}/VERSION" 2>/dev/null || true
            unset -f _fetch_one
            return 0
        }

        # 主流程：按 mode 串起 release / raw
        local got=
        case "${mode}" in
            release)
                _try_release_bundle && got=release
                ;;
            raw)
                _try_raw_files && got=raw
                ;;
            auto|*)
                if _try_release_bundle; then
                    got=release
                else
                    # release 失败时清掉 tmpDir 里可能残留的部分文件后再尝试 raw
                    rm -rf "${tmpDir}"/lib "${tmpDir}"/shell 2>/dev/null
                    if _try_raw_files; then
                        got=raw
                    fi
                fi
                ;;
        esac

        if [[ -z "${got}" ]]; then
            rm -rf "${tmpDir}"
            unset -f _fetch_to_file _fetch_to_stdout _try_release_bundle _try_raw_files
            return 1
        fi

        # 部署：tmpDir/lib/* → libDst，tmpDir/shell/lang/* → langDst
        if ! mkdir -p "${libDst}" "${langDst}"; then
            printf '\033[31m[FATAL] 无法创建 %s 或 %s（请确认 root 权限）\033[0m\n' "${libDst}" "${langDst}" >&2
            rm -rf "${tmpDir}"
            unset -f _fetch_to_file _fetch_to_stdout _try_release_bundle _try_raw_files
            return 1
        fi
        local f
        for f in "${libFiles[@]}"; do
            if ! mv -f "${tmpDir}/lib/${f}" "${libDst}/${f}"; then
                printf '\033[31m[FATAL] 部署 lib/%s 到 %s 失败\033[0m\n' "${f}" "${libDst}" >&2
                rm -rf "${tmpDir}"
                unset -f _fetch_to_file _fetch_to_stdout _try_release_bundle _try_raw_files
                return 1
            fi
        done
        for f in "${langFiles[@]}"; do
            if ! mv -f "${tmpDir}/shell/lang/${f}" "${langDst}/${f}"; then
                printf '\033[31m[FATAL] 部署 shell/lang/%s 到 %s 失败\033[0m\n' "${f}" "${langDst}" >&2
                rm -rf "${tmpDir}"
                unset -f _fetch_to_file _fetch_to_stdout _try_release_bundle _try_raw_files
                return 1
            fi
        done

        # VERSION 部署到 ${PROXY_AGENT_DIR}/VERSION，让 _load_version 走本地文件档而非每次打 API。
        # 失败不致命。
        if [[ -f "${tmpDir}/VERSION" ]]; then
            mkdir -p ${PROXY_AGENT_DIR} 2>/dev/null
            mv -f "${tmpDir}/VERSION" ${PROXY_AGENT_DIR}/VERSION 2>/dev/null || true
        fi

        rm -rf "${tmpDir}"
        unset -f _fetch_to_file _fetch_to_stdout _try_release_bundle _try_raw_files
        printf '\033[32m[bootstrap] 拉取完成（%s 模式）：%d 个 lib + %d 个 lang 文件已部署\033[0m\n' \
            "${got}" "${#libFiles[@]}" "${#langFiles[@]}" >&2
    }

    if _bootstrap_libs; then
        _LIB_DIR="${_LIB_FALLBACK_DIR}"
    fi
    unset -f _bootstrap_libs
fi

# 加载模块（如果存在）
if [[ -d "${_LIB_DIR}" ]]; then
    # 加载顺序不可换：i18n → constants → utils → json-utils → system-detect → protocol-registry → carpool → topo
    for _module in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
        if [[ -f "${_LIB_DIR}/${_module}.sh" ]]; then
            # shellcheck source=/dev/null
            source "${_LIB_DIR}/${_module}.sh"
        fi
    done
fi

# 模块加载自检：install.sh 直接调用、且无 inline 兜底的 lib 函数清单。
# 这些缺一个，脚本就会在中后段以"版本过低"/"链式信息写入失败"/"协议列表为空"
# 等误导性消息崩溃。在源头先打出明确诊断，避免后续让人误判。
_required_lib_fns=(
    versionGreaterOrEqual
    jsonWriteFile
    parseProtocolIdFromFileName
    getProtocolDisplayName
    getProtocolInboundTag
    anyProtocolRequiresTLS
    carpoolJudge
    topoRenderHtml
)
_missing_lib_fns=()
for _fn in "${_required_lib_fns[@]}"; do
    if ! declare -F "${_fn}" >/dev/null 2>&1; then
        _missing_lib_fns+=("${_fn}")
    fi
done
if [[ ${#_missing_lib_fns[@]} -gt 0 ]]; then
    # echoContent 在本文件后段才定义；这里用裸 printf，确保自检在任何
    # 加载状态下都能打印诊断。
    printf '\033[31m[FATAL] 未能加载 lib/ 模块，缺失关键函数: %s\033[0m\n' "${_missing_lib_fns[*]}" >&2
    printf '\033[31m[FATAL] Failed to load lib/ modules. Missing required functions: %s\033[0m\n' "${_missing_lib_fns[*]}" >&2
    printf '\033[33m已查找路径 / Tried paths:\n  - %s/lib\n  - %s\033[0m\n' "${_SCRIPT_DIR}" "${_LIB_FALLBACK_DIR}" >&2
    printf '\033[33m请确认 lib/ 目录与 install.sh 同级，或位于 %s。\033[0m\n' "${_LIB_FALLBACK_DIR}" >&2
    printf '\033[33mEnsure lib/ is co-located with install.sh, or installed under %s.\033[0m\n' "${_LIB_FALLBACK_DIR}" >&2
    exit 1
fi

# 清理临时变量
unset _LIB_DIR _LIB_FALLBACK_DIR _LANG_FALLBACK_DIR _SCRIPT_PATH _module _fn _required_lib_fns _missing_lib_fns _lib_health_ok _f

# ============================================================================
# 版本号来源优先级：VERSION 文件 > GitHub Release > 硬编码默认值
# ============================================================================
_load_version() {
    local versionFile="${_SCRIPT_DIR}/VERSION"
    local installedVersionFile="${PROXY_AGENT_DIR}/VERSION"

    # 优先从脚本目录读取
    if [[ -f "${versionFile}" ]]; then
        SCRIPT_VERSION="v$(cat "${versionFile}" 2>/dev/null | tr -d '[:space:]')"
    # 其次从安装目录读取
    elif [[ -f "${installedVersionFile}" ]]; then
        SCRIPT_VERSION="v$(cat "${installedVersionFile}" 2>/dev/null | tr -d '[:space:]')"
    else
        # 尝试从 GitHub Releases 获取最新版本（初次安装时使用）
        local remoteVersion
        local apiUrl="https://api.github.com/repos/Lynthar/Proxy-agent/releases/latest"
        remoteVersion=$(curl -s --connect-timeout 3 -m 5 "${apiUrl}" 2>/dev/null | \
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

        if [[ -n "${remoteVersion}" ]]; then
            # 确保版本号以 v 开头
            [[ "${remoteVersion}" != v* ]] && remoteVersion="v${remoteVersion}"
            SCRIPT_VERSION="${remoteVersion}"
        else
            # 网络不可用时显示初始版本标识
            SCRIPT_VERSION="(initial)"
        fi
    fi
    export SCRIPT_VERSION
}

# ============================================================================
# 从 GitHub API 取最新 Release 版本号
# ============================================================================
GITHUB_REPO="Lynthar/Proxy-agent"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# 获取最新 Release 版本号
# 返回: 版本号 (如 v3.6.0) 或空字符串
getLatestReleaseVersion() {
    local response
    local version

    # 使用 curl 获取 GitHub API 响应
    response=$(curl -s --connect-timeout 5 -m 10 "${GITHUB_API_URL}" 2>/dev/null)

    if [[ -n "${response}" ]]; then
        # 提取 tag_name 字段
        version=$(echo "${response}" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' 2>/dev/null)

        # 如果 grep -P 不可用，尝试其他方法
        if [[ -z "${version}" ]]; then
            version=$(echo "${response}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        fi

        # 确保版本号以 v 开头
        if [[ -n "${version}" && "${version}" != v* ]]; then
            version="v${version}"
        fi

        echo "${version}"
    fi
}

# 比较版本号
# 参数: $1 = 当前版本, $2 = 远程版本
# 返回: 0 = 需要更新, 1 = 已是最新, 2 = 无法比较
compareVersions() {
    local current="$1"
    local remote="$2"

    # 去除 v 前缀
    current="${current#v}"
    remote="${remote#v}"

    if [[ -z "${current}" || -z "${remote}" ]]; then
        return 2
    fi

    if [[ "${current}" == "${remote}" ]]; then
        return 1
    fi

    # 使用 sort -V 比较版本号
    local higher
    higher=$(printf '%s\n%s' "${current}" "${remote}" | sort -V | tail -1)

    if [[ "${higher}" == "${remote}" ]]; then
        return 0  # 需要更新
    else
        return 1  # 已是最新
    fi
}

# 检查更新并显示提示
# 启动路径的更新检查带 24h 本地缓存——GitHub 不通时不必每次打开菜单都等满 curl 超时；
# 手动更新入口（updateV2RayAgent）直接调 getLatestReleaseVersion，不走缓存
checkForUpdates() {
    local latestVersion=
    local cacheFile="${PROXY_AGENT_DIR}/latest_version_cache"

    if [[ -f "${cacheFile}" ]]; then
        local cacheMtime cacheAge
        cacheMtime=$(stat -c %Y "${cacheFile}" 2>/dev/null || echo 0)
        cacheAge=$(($(date +%s) - cacheMtime))
        if [[ ${cacheAge} -lt 86400 ]]; then
            latestVersion=$(cat "${cacheFile}")
            if ! [[ "${latestVersion}" =~ ^v[0-9][0-9.]*$ ]]; then
                latestVersion=
            fi
        fi
    fi

    if [[ -z "${latestVersion}" ]]; then
        latestVersion=$(getLatestReleaseVersion)
        if [[ "${latestVersion}" =~ ^v[0-9][0-9.]*$ ]] && [[ -d ${PROXY_AGENT_DIR} ]] && ! isDryRun; then
            echo "${latestVersion}" >"${cacheFile}"
        fi
    fi

    if [[ -n "${latestVersion}" ]]; then
        if compareVersions "${SCRIPT_VERSION}" "${latestVersion}"; then
            export LATEST_VERSION="${latestVersion}"
            return 0  # 有新版本
        fi
    fi
    return 1  # 无新版本或检查失败
}

# ============================================================================
# i18n 后备机制 - 当模块未加载时提供基本翻译支持
# ============================================================================
if ! type t &>/dev/null; then
    # t() 函数未定义，加载内嵌的基本语言消息
    # 基本消息定义（中文）
    MSG_MENU_AUTHOR="作者"
    MSG_MENU_VERSION="当前版本"
    MSG_MENU_GITHUB="Github"
    MSG_MENU_DESC="描述"
    MSG_MENU_TITLE="八合一共存脚本"
    MSG_MENU_INSTALL="安装"
    MSG_MENU_REINSTALL="重新安装"
    MSG_MENU_COMBO_INSTALL="任意组合安装"
    MSG_MENU_CHAIN_PROXY="链式代理管理"
    MSG_MENU_HYSTERIA2="Hysteria2 管理"
    MSG_MENU_REALITY="REALITY 管理"
    MSG_MENU_REALITY_QUICK="一键无域名 Reality 安装"
    MSG_REALITY_QUICK_TITLE="一键无域名 Reality 安装"
    MSG_REALITY_QUICK_CORE_SELECT="请选择核心：1.Xray-core  2.sing-box"
    MSG_MENU_TUIC="Tuic 管理"
    MSG_MENU_USER="用户管理"
    MSG_MENU_DISGUISE="伪装站管理"
    MSG_MENU_CERT="证书管理"
    MSG_MENU_ROUTING="分流工具"
    MSG_MENU_ADD_PORT="添加新端口"
    MSG_MENU_CORE="Core 管理"
    MSG_MENU_UPDATE_SCRIPT="更新脚本"
    MSG_MENU_BBR="安装 BBR、DD 脚本"
    MSG_MENU_UNINSTALL="卸载脚本"
    MSG_MENU_TOOL_MGMT="工具管理"
    MSG_MENU_VERSION_MGMT="版本管理"
    MSG_MENU_SCRIPT_MGMT="脚本管理"
    MSG_MENU_SCRIPT_VERSION="脚本版本管理"
    MSG_PROMPT_SELECT="请选择"
    MSG_NOTICE="注意事项"
    MSG_SYS_SELINUX_NOTICE="检测到 SELinux 已启用，请手动禁用（在 /etc/selinux/config 设置 SELINUX=disabled 并重启）"
    MSG_SYS_NOT_SUPPORTED="本脚本不支持此系统，请将下方日志反馈给开发者"
    MSG_SYS_CPU_NOT_SUPPORTED="不支持此 CPU 架构"
    MSG_SYS_CPU_DEFAULT_AMD64="无法识别 CPU 架构，默认使用 amd64/x86_64"
    MSG_CORE_CURRENT_RUNNING="核心: %s [运行中]"
    MSG_CORE_CURRENT_STOPPED="核心: %s [未运行]"
    MSG_PROTOCOLS_INSTALLED="已安装协议"
    MSG_PROGRESS_STEP="进度 %s/%s"
    MSG_PROG_INSTALL_TOOLS="安装工具"
    MSG_INSTALL_CHECKING="检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"
    MSG_INSTALL_TOOL="安装 %s"
    # 链式代理菜单
    MSG_CHAIN_MENU_WIZARD="快速配置向导"
    MSG_CHAIN_MENU_STATUS="查看链路状态"
    MSG_CHAIN_MENU_TEST="测试链路连通性"
    MSG_CHAIN_MENU_ADVANCED="高级设置"
    MSG_CHAIN_MENU_UNINSTALL="卸载链式代理"
    MSG_CHAIN_MENU_PROTOCOL_ROUTING="按协议分流设置"
    MSG_EXT_MENU_TITLE="外部节点管理"
    MSG_RECOMMENDED="推荐"

    # === IP CIDR 和 GeoIP 相关 ===
    MSG_CHAIN_RULE_IP_CIDR="IP CIDR 规则"
    MSG_CHAIN_RULE_GEOIP="GeoIP 规则"
    MSG_CHAIN_IP_CIDR_HINT="请输入 IP CIDR (逗号分隔)"
    MSG_CHAIN_IP_CIDR_EXAMPLE="格式示例: 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
    MSG_CHAIN_IP_CIDR_INVALID="IP CIDR 格式无效"
    MSG_IP_CIDR="IP CIDR"
    MSG_CHAIN_GEOIP_SELECT="选择 GeoIP 规则"
    MSG_CHAIN_GEOIP_CN="中国大陆"
    MSG_CHAIN_GEOIP_US="美国"
    MSG_CHAIN_GEOIP_JP="日本"
    MSG_CHAIN_GEOIP_HK="香港"
    MSG_CHAIN_GEOIP_TW="台湾"
    MSG_CHAIN_GEOIP_SG="新加坡"
    MSG_CHAIN_GEOIP_PRIVATE="私有 IP"
    MSG_CHAIN_GEOIP_CUSTOM="自定义 GeoIP"
    MSG_CHAIN_GEOIP_CUSTOM_HINT="请输入 GeoIP 代码 (如: kr, de, fr)"

    # === 多链路配置相关 ===
    MSG_CHAIN_MULTI_TITLE="配置入口节点 (多链路分流模式)"
    MSG_CHAIN_MULTI_DESC="此模式允许将不同流量分流到不同的出口节点"
    MSG_CHAIN_MULTI_EXAMPLE="例如: Netflix → 美国出口, OpenAI → 香港出口"
    MSG_CHAIN_SINGLE_EXISTS="检测到已存在单链路配置"
    MSG_CHAIN_SINGLE_UNINSTALL_HINT="如需使用多链路分流模式，请先卸载现有链式代理配置"
    MSG_CHAIN_MENU_PATH="菜单路径: 链式代理管理 → 卸载链式代理"
    MSG_CHAIN_MULTI_EXISTS="检测到已存在多链路配置"
    MSG_CHAIN_CONTINUE_ADD_NEW="继续添加新链路"
    MSG_CHAIN_RECONFIGURE="重新配置 (将清除现有配置)"
    MSG_CHAIN_CONFIRM_CLEAR="确认清除现有多链路配置？"
    MSG_CHAIN_SELECT_CONFIG_MODE="请选择配置方式"
    MSG_CHAIN_ADD_INTERACTIVE="逐个添加链路"
    MSG_CHAIN_BATCH_IMPORT="批量导入配置码"
    MSG_CHAIN_BATCH_TITLE="批量导入配置码"
    MSG_CHAIN_BATCH_HINT="请逐行粘贴配置码，每行一个"
    MSG_CHAIN_BATCH_END_HINT="输入完成后输入空行结束"
    MSG_CHAIN_CODE_PROMPT="配置码"
    MSG_CHAIN_CODE_PARSE_FAILED="配置码解析失败，已跳过"
    MSG_CHAIN_NO_CHAINS_ADDED="未添加任何链路，配置已取消"
    MSG_CHAIN_IMPORT_SUCCESS="成功导入 %s 条链路"
    MSG_CHAIN_IMPORT_NONE="未导入任何链路，配置已取消"
    MSG_CHAIN_CONFIG_RULES_NOW="是否现在配置分流规则？"

    # === 规则配置相关 ===
    MSG_CHAIN_STEP_IMPORT="步骤 1/3: 导入配置"
    MSG_CHAIN_STEP_NAME="步骤: 命名此链路"
    MSG_CHAIN_STEP_RULES="步骤 3/3: 设置分流规则"
    MSG_CHAIN_RULES_SELECT="选择此链路的分流规则"
    MSG_CHAIN_RULE_CUSTOM_DOMAIN="自定义域名"
    MSG_CHAIN_DEFAULT_HINT="提示: 如果不设置默认链路，未匹配规则的流量将从入口节点直连访问"
    MSG_CHAIN_PASTE_CODE="请粘贴出口/中继节点的配置码"
    MSG_CHAIN_CODE_EMPTY="配置码不能为空"
    MSG_CHAIN_PARSE_SUCCESS="解析成功"
    MSG_CHAIN_NODE_IP="节点IP"
    MSG_CHAIN_PORT="端口"
    MSG_CHAIN_PROTOCOL="协议"
    MSG_CHAIN_DOMAIN_HINT="请输入域名 (逗号分隔，如: example.com,test.org)"
    MSG_CHAIN_DOMAIN="域名"
    MSG_CHAIN_DOMAIN_EMPTY="域名不能为空"
    MSG_CHAIN_RULES_TITLE="配置分流规则"
    MSG_CHAIN_CURRENT_CHAINS="当前链路"
    MSG_CHAIN_SELECT_CHAIN="选择要添加规则的链路编号"
    MSG_CHAIN_INDEX="链路编号"
    MSG_CHAIN_INVALID_CHAIN="无效的选择"
    MSG_CHAIN_NO_CHAINS="没有可用的链路"
    MSG_CHAIN_NO_CONFIG="未找到多链路配置"
    MSG_CHAIN_RULE_FOR="为链路"
    MSG_CHAIN_RULE_TYPE_SELECT="选择规则类型"
    MSG_CHAIN_GENERATING="正在生成配置..."
    MSG_CHAIN_CONFIG_COMPLETE="多链路分流配置完成！"
    MSG_CHAIN_NO_DEFAULT_SET="当前未设置默认链路，未匹配规则的流量将直连访问"
    MSG_CHAIN_SET_DEFAULT_NOW="是否现在设置默认链路？"
    MSG_CHAIN_NO_DEFAULT_OPTION="不设置 (未匹配流量直连)"
    MSG_CHAIN_CONFIGURED_COUNT="已配置 %s 条链路"
    MSG_CHAIN_SET_DEFAULT_SUCCESS="已将 [%s] 设为默认链路"
    MSG_CHAIN_XRAY_DETECTED="检测到 Xray 代理协议，将同时配置 Xray 链式转发"
    MSG_CHAIN_TARGET="目标"
    MSG_CHAIN_RULE_ADDED="规则已添加"
    MSG_CONFIRM="确认"
    MSG_CANCELLED="已取消"
    MSG_CHAIN_MERGING_SINGBOX="正在合并 sing-box 配置..."
    MSG_CHAIN_STARTING_SINGBOX="正在启动 sing-box..."
    MSG_CHAIN_SINGBOX_START_FAILED="sing-box 启动失败"
    MSG_CHAIN_SINGBOX_START_SUCCESS="sing-box 启动成功"
    MSG_CHAIN_SINGBOX_DEBUG="请手动执行:"
    MSG_CHAIN_CONFIGURING_XRAY="正在配置 Xray 链式转发..."
    MSG_CHAIN_RESTARTING_XRAY="正在重启 Xray..."
    MSG_CHAIN_TESTING_CONNECTIVITY="正在测试链路连通性..."
    MSG_CHAIN_TESTING_PARALLEL="正在并行测试 %s 条链路..."
    MSG_CHAIN_XRAY_RESTART_SUCCESS="Xray 重启成功，链式转发已启用"
    MSG_CHAIN_XRAY_RESTART_FAILED="Xray 重启失败"
    MSG_CHAIN_XRAY_CHECK_CONFIG="请检查配置:"
    MSG_CHAIN_SUMMARY_NAME="链路名称"
    MSG_CHAIN_SUMMARY_TARGET="目标节点"
    MSG_CHAIN_SUMMARY_RULES="分流规则"
    MSG_CHAIN_RULE_PENDING="待配置"
    MSG_CHAIN_DEFAULT_ALL_TRAFFIC="默认 (所有其他流量)"
    MSG_CHAIN_DEFAULT_OUTBOUND="默认出站"
    MSG_CHAIN_DEFAULT_OUTBOUND_DIRECT="默认出站: 直连 (未匹配规则的流量直连访问)"
    MSG_CHAIN_TEST_MULTI_TITLE="测试多链路连通性"
    MSG_CHAIN_TEST_PROBE_OK="经链路取到出口 IP %s，耗时 %sms"
    MSG_CHAIN_TEST_CONN_FAIL="经这条链路访问外网失败"
    MSG_CHAIN_TEST_COMPLETE="测试完成: %s 通过, %s 失败"
    MSG_CHAIN_TEST_CHECK_HINT="请检查失败链路的:"
    MSG_CHAIN_TEST_CHECK_1="1. 出口节点防火墙是否开放端口"
    MSG_CHAIN_TEST_CHECK_2="2. 出口节点 sing-box 是否运行"
    MSG_CHAIN_TEST_CHECK_3="3. IP、端口与密钥是否正确（出口重装过要重新导入配置码），出口是否只放行了别的入口"
    MSG_CHAIN_STATUS_RUNNING="运行中"
    MSG_CHAIN_STATUS_STOPPED="未运行"
    MSG_CHAIN_STATUS_TITLE="链式代理状态"
    MSG_CHAIN_STATUS_ROLE="当前角色"
    MSG_CHAIN_STATUS_ROLE_ENTRY="入口节点 (Entry) - 多链路分流模式"
    MSG_CHAIN_STATUS_RUN="运行状态"
    MSG_CHAIN_STATUS_COUNT="链路数量"
    MSG_CHAIN_STATUS_DETAILS="链路详情"
    MSG_CHAIN_STATUS_DEFAULT_MARK="[默认]"

    # 协议分流相关
    MSG_CHAIN_PROTOCOL_ROUTING_TITLE="按协议节点分流配置"
    MSG_CHAIN_PROTOCOL_ROUTING_DESC="选择哪些协议的流量应通过链式代理"
    MSG_CHAIN_PROTOCOL_ROUTING_DESC2="未选中的协议将直接连接"
    MSG_CHAIN_PROTOCOL_NOT_ENTRY_NODE="当前不是入口节点，无法配置协议分流"
    MSG_CHAIN_PROTOCOL_NO_CHAIN_OUTBOUND="未找到链式代理出站配置"
    MSG_CHAIN_PROTOCOL_NO_PROTOCOLS="未安装任何协议"
    MSG_CHAIN_PROTOCOL_SELECT_PROMPT="已安装的协议列表："
    MSG_CHAIN_PROTOCOL_INPUT_HINT="请输入要通过链式代理的协议编号 (多选用逗号分隔，如: 1,2,3)"
    MSG_CHAIN_PROTOCOL_NO_SELECTION="未选择任何协议"
    MSG_CHAIN_PROTOCOL_INVALID_SELECTION="无效的选择"
    MSG_CHAIN_PROTOCOL_SELECTED="已选择的协议"
    MSG_CHAIN_PROTOCOL_CONFIRM="确认配置？"
    MSG_CHAIN_PROTOCOL_RELOADING="正在重载配置..."
    MSG_CHAIN_PROTOCOL_RELOAD_FAILED="配置重载失败"
    MSG_CHAIN_PROTOCOL_SUCCESS="协议分流配置成功！"
    MSG_CHAIN_PROTOCOL_SINGBOX_ONLY="按协议分流仅支持 sing-box 核心"

    # 后备 t() 函数
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

# ============================================================================

# 域名验证函数 - 防止命令注入
# 返回 0 表示有效，返回 1 表示无效
isValidDomain() {
    local domain="$1"
    # 空值无效
    [[ -z "${domain}" ]] && return 1
    # 基本域名格式验证（允许子域名、顶级域名等）
    # 格式: 允许字母、数字、连字符和点，但不能以点或连字符开头/结尾
    if [[ ! "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    # 不允许连续的点
    if [[ "${domain}" =~ \.\. ]]; then
        return 1
    fi
    return 0
}

# readValidPort PROMPT OUT_VAR [DEFAULT|"RANDOM"] [MIN] [MAX] → 0=成功，值写入 OUT_VAR
# DEFAULT="RANDOM" 时回车在 [MIN, MAX] 里取随机端口；手输的只要是 1-65535 就收。
# 空且无 default、或不是合法端口返回 1——统一入口，杜绝"先动手再校验"。
readValidPort() {
    local prompt="$1"
    local -n __rvp_out="$2"
    local default="${3:-}"
    local randomMin="${4:-1}"
    local randomMax="${5:-65535}"
    local __rvp_input
    read -r -p "${prompt}" __rvp_input
    if [[ -z "${__rvp_input}" ]]; then
        if [[ "${default}" == "RANDOM" ]]; then
            __rvp_out=$(randomNum "${randomMin}" "${randomMax}")
            return 0
        elif [[ -n "${default}" ]]; then
            __rvp_out="${default}"
            return 0
        fi
        echoContent red " ---> $(t ERR_PORT_EMPTY)"
        return 1
    fi
    # 拒绝前导 0 / 0 本身 / 非数字；位数先卡住，免得超长数字在算术比较里溢出
    if [[ ! "${__rvp_input}" =~ ^[1-9][0-9]{0,4}$ ]] || (( __rvp_input > 65535 )); then
        echoContent red " ---> $(t ERR_PORT_RANGE 1 65535)"
        return 1
    fi
    __rvp_out="${__rvp_input}"
    return 0
}

# readValidDomain PROMPT OUT_VAR [DEFAULT] → 0=成功
# 校验走 isValidDomain（含命令注入字符过滤）。
readValidDomain() {
    local prompt="$1"
    local -n __rvd_out="$2"
    local default="${3:-}"
    local __rvd_input
    read -r -p "${prompt}" __rvd_input
    if [[ -z "${__rvd_input}" ]]; then
        if [[ -n "${default}" ]]; then
            __rvd_out="${default}"
            return 0
        fi
        echoContent red " ---> $(t ERR_DOMAIN_EMPTY)"
        return 1
    fi
    if ! isValidDomain "${__rvd_input}"; then
        echoContent red " ---> $(t ERR_DOMAIN_INVALID)"
        return 1
    fi
    __rvd_out="${__rvd_input}"
    return 0
}

# isValidRedirectUrl URL → http(s) 地址白名单。结果原样进 nginx 的 return 302 '…';，引号、分号、空白、$、花括号、反斜杠
# 都能改写那一行，一个都不放。不用黑名单：方括号字符类里写 \] 会让类提前结束，结果什么都放行
isValidRedirectUrl() {
    local pattern='^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%/?=&+,:@-]*)?$'
    [[ "$1" =~ ${pattern} ]]
}

# SHA256校验和验证函数
# 用法: verifySHA256 <文件路径> <预期的SHA256值>
# 返回: 0=验证成功, 1=验证失败
verifySHA256() {
    local file="$1"
    local expectedHash="$2"

    if [[ ! -f "${file}" ]]; then
        echoContent red " ---> 校验失败: 文件不存在"
        return 1
    fi

    local actualHash
    if command -v sha256sum &>/dev/null; then
        actualHash=$(sha256sum "${file}" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actualHash=$(shasum -a 256 "${file}" | awk '{print $1}')
    else
        echoContent yellow " ---> 警告: 未找到sha256sum工具，跳过校验"
        return 0
    fi

    if [[ "${actualHash,,}" == "${expectedHash,,}" ]]; then
        return 0
    else
        echoContent red " ---> 校验失败: SHA256不匹配"
        echoContent red "     预期: ${expectedHash}"
        echoContent red "     实际: ${actualHash}"
        return 1
    fi
}

# 从Xray .dgst文件中提取SHA256值
# 用法: extractXrayHash <dgst文件路径>
extractXrayHash() {
    local dgstFile="$1"
    if [[ -f "${dgstFile}" ]]; then
        grep "SHA2-256" "${dgstFile}" | awk '{print $2}' | head -1
    fi
}

# 从 GitHub releases API 响应里取某个资产的 SHA256（资产的 digest 字段）
# 用法: releaseAssetSHA256 <releases JSON> <tag> <资产文件名>；没有 sha256 摘要时输出为空
releaseAssetSHA256() {
    jq -r --arg tag "$2" --arg name "$3" '.[] | select(.tag_name == $tag) | .assets[]?
        | select(.name == $name) | .digest // "" | select(startswith("sha256:")) | ltrimstr("sha256:")' \
        <<<"$1" 2>/dev/null | head -1
}

# verifyInstallSHA256 FILE TAG → 0=通过或软降级跳过，1=校验失败
# sha256 来自 Release 资产 install.sh.sha256。无 tag / 无资产 / 无 sha256sum 工具时
# 跳过并警告，不阻断旧版本升级。
verifyInstallSHA256() {
    local file="$1"
    local tag="$2"

    if [[ -z "${tag}" ]]; then
        echoContent yellow "$(t UPDATE_SHA256_SKIP "$(t UPDATE_SHA256_REASON_NOTAG)")"
        return 0
    fi

    local sha256Url="https://github.com/Lynthar/Proxy-agent/releases/download/${tag}/install.sh.sha256"
    local sha256File
    sha256File=$(mktemp)

    if ! wget -q --timeout=10 --tries=2 -O "${sha256File}" "${sha256Url}" 2>/dev/null || [[ ! -s "${sha256File}" ]]; then
        rm -f "${sha256File}"
        echoContent yellow "$(t UPDATE_SHA256_SKIP "$(t UPDATE_SHA256_REASON_NOASSET)")"
        return 0
    fi

    local expectedHash
    expectedHash=$(awk '{print $1}' "${sha256File}" | head -1)
    rm -f "${sha256File}"

    if [[ ${#expectedHash} -ne 64 ]]; then
        echoContent yellow "$(t UPDATE_SHA256_SKIP "$(t UPDATE_SHA256_REASON_BADFORMAT)")"
        return 0
    fi

    echoContent yellow " ---> $(t UPDATE_SHA256_CHECKING)"
    if verifySHA256 "${file}" "${expectedHash}"; then
        echoContent green " ---> $(t UPDATE_SHA256_OK)"
        return 0
    else
        return 1
    fi
}

# TLS证书与私钥匹配验证函数
# 用法: verifyCertKeyMatch <证书文件路径> <私钥文件路径>
# 返回: 0=匹配成功, 1=匹配失败或文件不存在
verifyCertKeyMatch() {
    local certFile="$1"
    local keyFile="$2"

    # 检查文件是否存在
    if [[ ! -f "${certFile}" ]]; then
        echoContent red " ---> 证书验证失败: 证书文件不存在 ${certFile}"
        return 1
    fi
    if [[ ! -f "${keyFile}" ]]; then
        echoContent red " ---> 证书验证失败: 私钥文件不存在 ${keyFile}"
        return 1
    fi

    # 检查文件是否为空
    if [[ ! -s "${certFile}" ]]; then
        echoContent red " ---> 证书验证失败: 证书文件为空"
        return 1
    fi
    if [[ ! -s "${keyFile}" ]]; then
        echoContent red " ---> 证书验证失败: 私钥文件为空"
        return 1
    fi

    # 提取证书和私钥的公钥哈希进行比对
    local certHash keyHash

    # 检测密钥类型（ECC或RSA）
    if openssl x509 -in "${certFile}" -noout -text 2>/dev/null | grep -q "EC Public Key\|id-ecPublicKey"; then
        # ECC证书
        certHash=$(openssl x509 -in "${certFile}" -pubkey -noout 2>/dev/null | openssl ec -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
        keyHash=$(openssl ec -in "${keyFile}" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
    else
        # RSA证书
        certHash=$(openssl x509 -in "${certFile}" -noout -modulus 2>/dev/null | sha256sum | awk '{print $1}')
        keyHash=$(openssl rsa -in "${keyFile}" -noout -modulus 2>/dev/null | sha256sum | awk '{print $1}')
    fi

    if [[ -z "${certHash}" || -z "${keyHash}" ]]; then
        echoContent yellow " ---> 证书验证警告: 无法提取证书/私钥信息进行匹配验证"
        return 0
    fi

    if [[ "${certHash}" == "${keyHash}" ]]; then
        return 0
    else
        echoContent red " ---> 证书验证失败: 证书与私钥不匹配"
        echoContent red "     证书公钥哈希: ${certHash:0:16}..."
        echoContent red "     私钥公钥哈希: ${keyHash:0:16}..."
        return 1
    fi
}

# 验证证书有效期
# 用法: verifyCertExpiry <证书文件路径>
# 返回: 0=有效, 1=已过期或即将过期(7天内)
verifyCertExpiry() {
    local certFile="$1"

    if [[ ! -f "${certFile}" ]]; then
        return 1
    fi

    # 用 openssl -checkend 判定有效期：避免 BusyBox(Alpine) 的 date -d 无法解析 openssl
    # enddate 文本（如 "Jul  2 12:00:00 2026 GMT"）。checkend N：N 秒后仍有效则退出 0。
    if ! openssl x509 -in "${certFile}" -noout -checkend 0 >/dev/null 2>&1; then
        echoContent red " ---> 证书已过期"
        return 1
    fi

    if ! openssl x509 -in "${certFile}" -noout -checkend 604800 >/dev/null 2>&1; then
        echoContent yellow " ---> 警告: 证书将在 7 天内过期"
    fi

    return 0
}

# echoContent 由 lib/utils.sh 提供（colors: red green yellow blue purple skyBlue white）。
# 旧 inline 版本依赖 ${echoType}（initVar 才赋值）和未定义的 ${printN}，启动早期
# 调用时实际是空命令；lib 版用裸 echo -e，不依赖任何先前初始化。

# 验证IP地址格式
# 参数1: IP地址字符串
# 返回: 0=有效, 1=无效
isValidIP() {
    local ip=$1
    # IPv4 验证
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    # IPv6 验证 (简化版，支持完整格式和压缩格式)
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] || \
       [[ "$ip" =~ ^::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$ ]] || \
       [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){1,6}:$ ]]; then
        return 0
    fi
    return 1
}

# SELinux / 系统 / CPU 探测由 lib/system-detect.sh 提供；
# SELinux enforcing 与 checkSystem 失败都 exit 1。

# 初始化全局变量
initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
    #    sudoCMD=""

    # 核心支持的cpu版本
    xrayCoreCPUVendor=""
    warpRegCoreCPUVendor=""
    cpuVendor=""

    # 域名
    domain=
    # 安装总进度
    totalProgress=1

    # 当前安装的核心类型：1=xray-core，2=sing-box（早期的 v2ray 值已下线）
    coreKind=

    # 核心安装path
    # coreInstallPath=

    # v2ctl Path
    ctlPath=
    # 1.全部安装
    # 2.个性化安装
    # v2rayAgentInstallType=

    # 当前的个性化安装方式 01234
    currentInstallProtocolType=

    # 当前alpn的顺序
    currentAlpn=

    # 前置类型
    frontingType=

    # 选择的个性化安装方式
    selectCustomInstallType=

    # v2ray-core、xray-core配置文件的路径
    configPath=

    # xray-core reality状态
    realityStatus=

    # sing-box配置文件路径
    singBoxConfigPath=

    # sing-box端口

    singBoxVLESSVisionPort=
    singBoxVLESSRealityVisionPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=
    singBoxTuicPort=
    singBoxNaivePort=
    singBoxVMessWSPort=
    singBoxVLESSWSPort=
    singBoxVMessHTTPUpgradePort=

    # nginx订阅端口
    subscribePort=

    subscribeType=

    # sing-box reality serverName publicKey
    singBoxVLESSRealityGRPCServerName=
    singBoxVLESSRealityVisionServerName=
    singBoxVLESSRealityPublicKey=

    # xray-core reality serverName publicKey
    xrayVLESSRealityServerName=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPServerName=
    xrayVLESSRealityXHTTPort=
    #    xrayVLESSRealityPublicKey=

    #    interfaceName=
    # 端口跳跃
    portHoppingStart=
    portHoppingEnd=
    portHopping=

    hysteria2PortHoppingStart=
    hysteria2PortHoppingEnd=
    hysteria2PortHopping=

    # tuic配置文件路径
    #    tuicConfigPath=
    tuicAlgorithm=
    tuicPort=

    # 配置文件的path
    currentPath=

    # 配置文件的host
    currentHost=

    # 安装时选择的core类型
    selectCoreType=

    # 默认core版本
    #    v2rayCoreVersion=

    # 随机路径
    customPath=

    # centos version
    centosVersion=

    # UUID
    currentUUID=

    # clients
    currentClients=

    # previousClients
    #    previousClients=

    localIP=

    # 定时任务执行任务名称 RenewTLS-更新证书 UpdateGeo-更新geo文件
    cronName=${1:-}

    # tls安装失败后尝试的次数
    installTLSCount=

    # BTPanel状态
    #	BTPanelStatus=
    # 宝塔域名
    btDomain=
    # nginx配置文件路径
    nginxConfigPath=/etc/nginx/conf.d/
    nginxStaticPath=/usr/share/nginx/html/

    # 是否为预览版
    prereleaseStatus=false

    # ssl类型
    sslType=
    # SSL CF API Token
    cfAPIToken=

    # ssl邮箱
    sslEmail=

    # dns ssl状态
    #    dnsSSLStatus=

    # dns tls domain
    dnsTLSDomain=
    ipType=

    # 该域名是否通过dns安装通配符证书
    #    installDNSACMEStatus=

    # 自定义端口
    customPort=

    # hysteria端口
    hysteriaPort=

    # hysteria协议
    #    hysteriaProtocol=

    # hysteria延迟
    #    hysteriaLag=

    # hysteria下行速度
    hysteria2ClientDownloadSpeed=

    # hysteria上行速度
    hysteria2ClientUploadSpeed=

    # Hysteria2 混淆类型（salamander / gecko，空 = 不混淆）与密码
    hysteria2ObfsType=
    hysteria2ObfsPassword=

    # Reality
    realityPrivateKey=
    realityServerName=


    # wget show progress
    wgetShowProgressStatus=

    # warp
    reservedWarpReg=
    publicKeyWarpReg=
    addressWarpReg=
    secretKeyWarpReg=

    # 上次安装配置状态
    lastInstallationConfig=

}

# stripAnsi 由 lib/utils.sh 提供（同样的 [a-zA-Z] 宽匹配）。

# 读取tls证书详情
readAcmeTLS() {
    # 重置 DNS API 状态，避免上次调用的残留值
    installedDNSAPIStatus=""

    local readAcmeDomain=
    if [[ -n "${currentHost}" ]]; then
        readAcmeDomain="${currentHost}"
    fi

    if [[ -n "${domain}" ]]; then
        readAcmeDomain="${domain}"
    fi

    # 如果没有域名，直接返回
    if [[ -z "${readAcmeDomain}" ]]; then
        return
    fi

    dnsTLSDomain=$(echo "${readAcmeDomain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    # 检查通配符证书目录是否存在
    # 注意：通配符证书目录名以字面 "*." 开头，如 *.example.com_ecc
    # 使用 \* 匹配字面星号，避免匹配普通证书目录如 sub.example.com_ecc
    local acmeEccDir
    acmeEccDir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name '\*.'"${dnsTLSDomain}_ecc" 2>/dev/null | head -1)
    if [[ -n "${acmeEccDir}" ]]; then
        local keyFile certFile
        # 通配符证书文件名也以字面 "*." 开头
        keyFile=$(find "${acmeEccDir}" -maxdepth 1 -type f -name '\*.'"${dnsTLSDomain}.key" 2>/dev/null | head -1)
        certFile=$(find "${acmeEccDir}" -maxdepth 1 -type f -name '\*.'"${dnsTLSDomain}.cer" 2>/dev/null | head -1)
        if [[ -n "${keyFile}" && -n "${certFile}" ]]; then
            installedDNSAPIStatus=true
        fi
    fi
}

# 读取默认自定义端口
readCustomPort() {
    if [[ -n "${configPath}" && -z "${realityStatus}" && "${coreKind}" == "1" ]]; then
        local port=
        port=$(jq -r .inbounds[0].port "${configPath}${frontingType}.json")
        if [[ "${port}" != "443" ]]; then
            customPort=${port}
        fi
    fi
}

# 读取nginx订阅端口
readNginxSubscribe() {
    subscribeType="https"
    if [[ -f "${nginxConfigPath}subscribe.conf" ]]; then
        if grep -q "sing-box" "${nginxConfigPath}subscribe.conf"; then
            subscribePort=$(grep -m1 "listen" "${nginxConfigPath}subscribe.conf" | awk '{print $2}')
            subscribeDomain=$(grep "server_name" "${nginxConfigPath}subscribe.conf" | awk '{print $2}')
            subscribeDomain=${subscribeDomain//;/}
            if [[ -n "${currentHost}" && "${subscribeDomain}" != "${currentHost}" ]]; then
                subscribePort=
                subscribeType=
            else
                if ! grep "listen" "${nginxConfigPath}subscribe.conf" | grep -q "ssl"; then
                    subscribeType="http"
                fi
            fi

        fi
    fi
}

# 检测安装方式
# coreKind: 1=xray-core, 2=sing-box, 空=未安装
readInstallType() {
    coreKind=
    configPath=
    singBoxConfigPath=

    # 1.检测安装目录
    if [[ -d "${PROXY_AGENT_DIR}" ]]; then
        if [[ -f "${XRAY_BIN}" ]]; then
            # 检测xray-core
            if [[ -d "${XRAY_CONF_DIR}" ]] && [[ -f "${XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json" || -f "${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json" || -f "${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json" ]]; then
                # xray-core
                configPath=${XRAY_CONF_DIR}/
                ctlPath=${XRAY_BIN}
                coreKind=1
                if [[ -f "${configPath}07_VLESS_vision_reality_inbounds.json" ]]; then
                    realityStatus=1
                fi
                if [[ -f "${SINGBOX_BIN}" ]] && [[ -f "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" || -f "${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json" ]]; then
                    singBoxConfigPath=${SINGBOX_FRAGMENT_DIR}/
                fi
            fi
        elif [[ -f "${SINGBOX_BIN}" && -f "${SINGBOX_MERGED_CONFIG}" ]]; then
            # 检测sing-box
            ctlPath=${SINGBOX_BIN}
            coreKind=2
            configPath=${SINGBOX_FRAGMENT_DIR}/
            singBoxConfigPath=${SINGBOX_FRAGMENT_DIR}/
        fi
    fi
}

# 读取协议类型
readInstallProtocolType() {
    currentInstallProtocolType=
    frontingType=

    xrayVLESSRealityPort=
    xrayVLESSRealityServerName=

    xrayVLESSRealityXHTTPort=
    xrayVLESSRealityXHTTPServerName=

    #    currentRealityXHTTPPrivateKey=
    currentRealityXHTTPPublicKey=
    currentRealityXHTTPShortId=

    currentRealityPrivateKey=
    currentRealityPublicKey=
    currentRealityShortId=
    currentRealityShortId2=
    realityDestHost=

    currentRealityMldsa65Seed=
    currentRealityMldsa65Verify=

    singBoxVLESSVisionPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=

    frontingTypeReality=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityVisionServerName=
    singBoxVLESSRealityGRPCServerName=
    singBoxAnyTLSPort=
    singBoxShadowTlsPort=
    singBoxTuicPort=
    singBoxNaivePort=
    singBoxVMessWSPort=

    # row 是去掉 .json 的完整路径；分支只看文件名——安装根允许含点和下划线
    while read -r row; do
        if echo "${row##*/}" | grep -q VLESS_TCP_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}0,"
            frontingType=02_VLESS_TCP_inbounds
            if [[ "${coreKind}" == "2" ]]; then
                singBoxVLESSVisionPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q VLESS_WS_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}1,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=03_VLESS_WS_inbounds
                singBoxVLESSWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q VLESS_XHTTP_TLS_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}15,"
        fi
        if echo "${row##*/}" | grep -q VLESS_XHTTP_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}12,"
            xrayVLESSRealityXHTTPort=$(jq -r .inbounds[0].port "${row}.json")

            xrayVLESSRealityXHTTPServerName=$(jq -r .inbounds[0].streamSettings.realitySettings.serverNames[0] "${row}.json")

            currentRealityXHTTPPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey "${row}.json")
            currentRealityXHTTPShortId=$(jq -r .inbounds[0].streamSettings.realitySettings.shortIds[0] "${row}.json")
            #            currentRealityXHTTPPrivateKey=$(jq -r .inbounds[0].streamSettings.realitySettings.privateKey "${row}.json")

            # ML-DSA-65 后量子签名（与 Vision 配置对齐）。// empty 兜底见 Vision 分支注释——
            # 旧 XHTTP 配置缺这俩字段时不加兜底会得到字面 "null"，导致 initRealityMldsa65 复用
            # 假值。empty 兜底后 jq 返回空串，触发重新生成。
            currentRealityMldsa65Seed=$(jq -r '.inbounds[0].streamSettings.realitySettings.mldsa65Seed // empty' "${row}.json")
            currentRealityMldsa65Verify=$(jq -r '.inbounds[0].streamSettings.realitySettings.mldsa65Verify // empty' "${row}.json")

        fi

        if echo "${row##*/}" | grep -q trojan_gRPC_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}2,"
        fi
        if echo "${row##*/}" | grep -q VMess_WS_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}3,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=05_VMess_WS_inbounds
                singBoxVMessWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q trojan_TCP_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}4,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=04_trojan_TCP_inbounds
                singBoxTrojanPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q VLESS_gRPC_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}5,"
        fi
        if echo "${row##*/}" | grep -q hysteria2_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}6,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=06_hysteria2_inbounds
                singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q VLESS_vision_reality_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}7,"
            if [[ "${coreKind}" == "1" ]]; then
                xrayVLESSRealityServerName=$(jq -r .inbounds[1].streamSettings.realitySettings.serverNames[0] "${row}.json")
                realityServerName=${xrayVLESSRealityServerName}
                xrayVLESSRealityPort=$(jq -r .inbounds[0].port "${row}.json")

                realityDomainPort=$(jq -r .inbounds[1].streamSettings.realitySettings.target "${row}.json" | awk -F '[:]' '{print $2}')
                realityDestHost=$(jq -r '.inbounds[1].streamSettings.realitySettings.target // "" | split(":")[0] | if . == "127.0.0.1" then . else empty end' "${row}.json")

                currentRealityPublicKey=$(jq -r .inbounds[1].streamSettings.realitySettings.publicKey "${row}.json")
                currentRealityPrivateKey=$(jq -r .inbounds[1].streamSettings.realitySettings.privateKey "${row}.json")
                currentRealityShortId=$(jq -r .inbounds[1].streamSettings.realitySettings.shortIds[0] "${row}.json")
                currentRealityShortId2=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds[1] // empty' "${row}.json")

                # // empty 兜底：很老的 Vision 配置（mldsa65 特性引入之前生成）没这俩字段，
                # 不加 // empty 会让 jq -r 输出字面字符串 "null"，再被 initRealityMldsa65
                # 当作合法 seed 复用、写进新配置，PQ 握手会失败。
                currentRealityMldsa65Seed=$(jq -r '.inbounds[1].streamSettings.realitySettings.mldsa65Seed // empty' "${row}.json")
                currentRealityMldsa65Verify=$(jq -r '.inbounds[1].streamSettings.realitySettings.mldsa65Verify // empty' "${row}.json")

                frontingTypeReality=07_VLESS_vision_reality_inbounds

            elif [[ "${coreKind}" == "2" ]]; then
                frontingTypeReality=07_VLESS_vision_reality_inbounds
                singBoxVLESSRealityVisionPort=$(jq -r .inbounds[0].listen_port "${row}.json")
                singBoxVLESSRealityVisionServerName=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                realityDomainPort=$(jq -r .inbounds[0].tls.reality.handshake.server_port "${row}.json")
                realityDestHost=$(jq -r '.inbounds[0].tls.reality.handshake.server // "" | if . == "127.0.0.1" then . else empty end' "${row}.json")
                currentRealityShortId=$(jq -r '.inbounds[0].tls.reality.short_id[0] // empty' "${row}.json")
                currentRealityShortId2=$(jq -r '.inbounds[0].tls.reality.short_id[1] // empty' "${row}.json")

                realityServerName=${singBoxVLESSRealityVisionServerName}
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')

                    currentRealityPrivateKey=$(jq -r .inbounds[0].tls.reality.private_key "${row}.json")
                    currentRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
            fi
        fi
        if echo "${row##*/}" | grep -q VLESS_vision_gRPC_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}8,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingTypeReality=08_VLESS_vision_gRPC_inbounds
                singBoxVLESSRealityGRPCServerName=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
            fi
        fi
        if echo "${row##*/}" | grep -q tuic_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}9,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=09_tuic_inbounds
                singBoxTuicPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q naive_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}10,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=10_naive_inbounds
                singBoxNaivePort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q anytls_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}13,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=13_anytls_inbounds
                singBoxAnyTLSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q ss2022_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}14,"
            if [[ "${coreKind}" == "2" ]]; then
                # ss2022 的 users[].password 是派生 uPSK、逆推不出 UUID——14_ 排序恒最后，
                # 无条件赋值会覆盖其他协议；只在没有别的身份源时才让它当 frontingType
                if [[ -z "${frontingType}" ]]; then
                    frontingType=14_ss2022_inbounds
                fi
                ss2022Port=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q shadowtls_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}16,"
            if [[ "${coreKind}" == "2" ]]; then
                # 外层密码就是 UUID，比 ss2022 的派生 uPSK 适合当身份源
                if [[ -z "${frontingType}" || "${frontingType}" == "14_ss2022_inbounds" ]]; then
                    frontingType=16_shadowtls_inbounds
                fi
                singBoxShadowTlsPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if echo "${row##*/}" | grep -q VMess_HTTPUpgrade_inbounds; then
            currentInstallProtocolType="${currentInstallProtocolType}11,"
            if [[ "${coreKind}" == "2" ]]; then
                frontingType=11_VMess_HTTPUpgrade_inbounds
                singBoxVMessHTTPUpgradePort=$(grep 'listen' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
            fi
        fi

    done < <([[ -n "${configPath}" ]] && find "${configPath}" -name "*inbounds.json" | sort | sed 's/\.json$//')

    if [[ "${coreKind}" == "1" && -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            currentInstallProtocolType="${currentInstallProtocolType}6,"
            singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            currentInstallProtocolType="${currentInstallProtocolType}9,"
            singBoxTuicPort=$(jq .inbounds[0].listen_port "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
    fi
    if [[ "${currentInstallProtocolType:0:1}" != "," ]]; then
        currentInstallProtocolType=",${currentInstallProtocolType}"
    fi
}

# 检查是否安装宝塔
checkBTPanel() {
    if [[ -n $(pgrep -f "BT-Panel") ]]; then
        # 读取域名
        if [[ -d '/www/server/panel/vhost/cert/' && -n $(find /www/server/panel/vhost/cert/*/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\n读取宝塔配置\n"

                find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}'

                read -r -p "请输入编号选择:" selectBTDomain
            else
                selectBTDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep -e "^${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> 选择错误，请重新选择"
                    checkBTPanel
                else
                    domain=${btDomain}
                    if [[ ! -f "${TLS_DIR}/${btDomain}.crt" && ! -f "${TLS_DIR}/${btDomain}.key" ]]; then
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/fullchain.pem" "${TLS_DIR}/${btDomain}.crt"
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/privkey.pem" "${TLS_DIR}/${btDomain}.key"
                    fi

                    nginxStaticPath="/www/wwwroot/${btDomain}/html/"

                    mkdir -p "/www/wwwroot/${btDomain}/html/"

                    if [[ -f "/www/wwwroot/${btDomain}/.user.ini" ]]; then
                        chattr -i "/www/wwwroot/${btDomain}/.user.ini"
                    fi
                    nginxConfigPath="/www/server/panel/vhost/nginx/"
                fi
            else
                echoContent red " ---> 选择错误，请重新选择"
                checkBTPanel
            fi
        fi
    fi
}
check1Panel() {
    if [[ -n $(pgrep -f "1panel") ]]; then
        # 读取域名
        if [[ -d '/opt/1panel/apps/openresty/openresty/www/sites/' && -n $(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\n读取1Panel配置\n"

                find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}'

                read -r -p "请输入编号选择:" selectBTDomain
            else
                selectBTDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> 选择错误，请重新选择"
                    check1Panel
                else
                    domain=${btDomain}
                    if [[ ! -f "${TLS_DIR}/${btDomain}.crt" && ! -f "${TLS_DIR}/${btDomain}.key" ]]; then
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/fullchain.pem" "${TLS_DIR}/${btDomain}.crt"
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/privkey.pem" "${TLS_DIR}/${btDomain}.key"
                    fi

                    nginxStaticPath="/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/index/"
                fi
            else
                echoContent red " ---> 选择错误，请重新选择"
                check1Panel
            fi
        fi
    fi
}
# 检查防火墙
allowPort() {
    local type=$2
    local sourceRange=$3
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+ufw"; then
        if ufw status | grep -q "Status: active"; then
            # 不先 grep 查重（ufw 自己跳过已有的同一条）：443/tcp 是 8443/tcp 的子串，按子串查会把没放行的端口当成已放行
            if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
                ufw allow from "${sourceRange}" to any port "$1" proto "${type}"
            else
                ufw allow "$1/${type}"
            fi
            checkUFWAllowPort "$1" "${type}"
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        # 不写 --zone：加、查、检查都落在默认区。写死 public 的话，默认区不是 public 的机器上规则全落进没挂网卡的区，一条不生效
        local updateFirewalldStatus=
        if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
            local richRule="rule family=\"ipv4\" source address=\"${sourceRange}\" port protocol=\"${type}\" port=\"$1\" accept"
            if ! firewall-cmd --permanent --query-rich-rule="${richRule}" >/dev/null 2>&1; then
                updateFirewalldStatus=true
                firewall-cmd --permanent --add-rich-rule="${richRule}"
                checkFirewalldAllowPort "$1"
            fi
        elif ! firewall-cmd --list-ports --permanent | grep -qw "$1/${type}"; then
            updateFirewalldStatus=true
            local firewallPort=$1
            if echo "${firewallPort}" | grep -q ":"; then
                firewallPort=$(echo "${firewallPort}" | awk -F ":" '{print $1"-"$2}')
            fi
            firewall-cmd --add-port="${firewallPort}/${type}" --permanent
            checkFirewalldAllowPort "${firewallPort}"
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            firewall-cmd --reload
        fi
    elif rc-update show 2>/dev/null | grep -q ufw; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$1/${type}"
            checkUFWAllowPort "$1" "${type}"
        fi
    elif command -v nft >/dev/null 2>&1 && systemctl is-active --quiet nftables 2>/dev/null; then
        if nft list chain inet filter input >/dev/null 2>&1; then
            local nftComment="allow $1/${type}(Proxy-agent)"
            local nftSourceRange="${sourceRange:-0.0.0.0/0}"
            local nftRules
            local updateNftablesStatus=
            nftRules=$(nft list chain inet filter input)
            if ! echo "${nftRules}" | grep -q "${nftComment}" || ! echo "${nftRules}" | grep -q "${nftSourceRange}"; then
                updateNftablesStatus=true
                # nft 的端口区间写 a-b，不认 iptables 的 a:b
                nft add rule inet filter input ip saddr "${nftSourceRange}" ${type} dport "${1/:/-}" counter accept comment "${nftComment}"
            fi

            if echo "${updateNftablesStatus}" | grep -q "true"; then
                nft list ruleset >/etc/nftables.conf
                systemctl reload nftables >/dev/null 2>&1 || nft -f /etc/nftables.conf
            fi
        fi
    elif command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+netfilter-persistent" && systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local updateFirewalldStatus=
        if [[ -n "${sourceRange}" && "${sourceRange}" != "0.0.0.0/0" ]]; then
            if ! iptables -C INPUT -p ${type} -s "${sourceRange}" --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT 2>/dev/null; then
                updateFirewalldStatus=true
                iptables -I INPUT -p ${type} -s "${sourceRange}" --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT
            fi
        elif ! iptables -C INPUT -p ${type} --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT 2>/dev/null; then
            updateFirewalldStatus=true
            iptables -I INPUT -p ${type} --dport "$1" -m comment --comment "allow $1/${type}(Proxy-agent)" -j ACCEPT
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            netfilter-persistent save
        fi
    fi
}

# firewallDefaultDenies → 0 = allowPort 会用的那个防火墙默认拒绝入站，按源放行才真把端口藏起来；
# 没有在用的防火墙、默认放行、firewalld 默认区 target 是 ACCEPT（trusted）都返回 1。判断顺序必须与 allowPort 一致
firewallDefaultDenies() {
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+ufw"; then
        ufw status verbose 2>/dev/null | grep -q "Status: active" || return 1
        ufw status verbose | grep -qE "Default: (deny|reject) \(incoming\)"
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        [[ "$(firewall-cmd --permanent --zone="$(firewall-cmd --get-default-zone)" --get-target 2>/dev/null)" != "ACCEPT" ]]
    elif rc-update show 2>/dev/null | grep -q ufw; then
        ufw status verbose 2>/dev/null | grep -q "Status: active" || return 1
        ufw status verbose | grep -qE "Default: (deny|reject) \(incoming\)"
    elif command -v nft >/dev/null 2>&1 && systemctl is-active --quiet nftables 2>/dev/null; then
        nft list chain inet filter input 2>/dev/null | grep -q "policy drop"
    elif command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+netfilter-persistent" && systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        iptables -S INPUT 2>/dev/null | head -n 1 | grep -qE "^-P INPUT (DROP|REJECT)"
    else
        return 1
    fi
}
# getPublicIP 由 lib/system-detect.sh 提供（同样的接口：默认 IPv4，
# 第一参数可指定 4/6；保留 currentHost==Reality serverName 时短路返回 currentHost）。

# checkUFWAllowPort PORT TYPE → 按「端口/协议」整列比对 ufw status 的第一列；子串比对会把 8443/tcp 当成 443/tcp
checkUFWAllowPort() {
    if ufw status | awk -v rule="$1/$2" '$1 == rule {found = 1} END {exit !found}'; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 1
    fi
}

# 输出firewall-cmd端口开放状态
checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1" || firewall-cmd --list-rich-rules --permanent | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 1
    fi
}

# 读取Tuic配置
readSingBoxConfig() {
    tuicPort=
    hysteriaPort=
    if [[ -n "${singBoxConfigPath}" ]]; then

        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            tuicPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}09_tuic_inbounds.json")
            tuicAlgorithm=$(jq -r '.inbounds[0].congestion_control' "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            hysteriaPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            # 落盘约定：up_mbps 存客户端下行、down_mbps 存客户端上行（服务端上行 = 客户端下行），读回按同一约定，
            # 否则重新生成订阅时上下行对调。BBR 的配置不写带宽，读回为空，订阅随之不给客户端带宽
            hysteria2ClientDownloadSpeed=$(jq -r '.inbounds[0].up_mbps // empty' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ClientUploadSpeed=$(jq -r '.inbounds[0].down_mbps // empty' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ObfsType=$(jq -r '.inbounds[0].obfs.type // empty' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ObfsPassword=$(jq -r '.inbounds[0].obfs.password // empty' "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
    fi
}

# 读取上次安装的配置
readLastInstallationConfig() {
    # 只有链式片段的 sing-box 机也有 configPath，那里没有可复用的协议配置
    if [[ -n "${configPath}" && "$(scanInstalledProtocols "${configPath}")" != "," ]]; then
        read -r -p "读取到上次安装的配置，是否使用 ？[y/n]:" lastInstallationConfigStatus
        if isYesInput "${lastInstallationConfigStatus}"; then
            lastInstallationConfig=true
        fi
    fi
}
# 卸载 sing-box
unInstallSingBox() {
    local type=$1
    if [[ -n "${singBoxConfigPath}" ]]; then
        if grep -q 'tuic' <${SINGBOX_MERGED_CONFIG} && [[ "${type}" == "tuic" ]]; then
            removeProtocolPortHopping tuic "${singBoxConfigPath}09_tuic_inbounds.json"
            rm "${singBoxConfigPath}09_tuic_inbounds.json"
            echoContent green " ---> 删除sing-box tuic配置成功"
        fi

        if grep -q 'hysteria2' <${SINGBOX_MERGED_CONFIG} && [[ "${type}" == "hysteria2" ]]; then
            removeProtocolPortHopping hysteria2 "${singBoxConfigPath}06_hysteria2_inbounds.json"
            rm "${singBoxConfigPath}06_hysteria2_inbounds.json"
            echoContent green " ---> 删除sing-box hysteria2配置成功"
        fi
        # 删除合并后的 config.json，让下一次 handleSingBox start 走 singBoxMergeConfig 重新生成。
        # 用绝对路径而非 ${singBoxConfigPath}（后者是 .../config/ 片段目录，不是 config.json 父目录）。
        rm -f ${SINGBOX_MERGED_CONFIG}
    fi

    readInstallType

    # 片段里还有入站（链式的桥、出口）也得留：singBoxConfigPath 只看 6 / 9，按它删会把链式的片段、状态文件连同二进制一起删掉
    if [[ -n "${singBoxConfigPath}" ]] || singBoxFragmentsHaveInbounds; then
        echoContent yellow " ---> 检测到有其他配置，保留sing-box核心"
        handleSingBox stop
        handleSingBox start
    else
        handleSingBox stop
        singBoxAutostart off
        rm -f /etc/systemd/system/sing-box.service /etc/init.d/sing-box
        # 外部节点清单是用户填的，没有片段能重建；清单空了才整个删
        local extNodes entry
        extNodes=$(jq -r '.nodes | length' "${EXTERNAL_NODE_FILE}" 2>/dev/null)
        if [[ "${extNodes:-0}" -gt 0 ]]; then
            for entry in "${SINGBOX_DIR}"/* "${SINGBOX_CONF_DIR}"/*; do
                [[ "${entry}" == "${SINGBOX_CONF_DIR}" || "${entry}" == "${EXTERNAL_NODE_FILE}" ]] || rm -rf "${entry}"
            done
            echoContent yellow " ---> $(t EXT_NODES_KEPT "${extNodes}")"
        else
            rm -rf ${SINGBOX_DIR}/*
        fi
        echoContent green " ---> sing-box 卸载完成"
    fi
    refreshSubscribeAfterInstall
}

# 检查文件目录以及path路径
readConfigHostPathUUID() {
    currentPath=
    currentDefaultPort=
    currentUUID=
    currentClients=
    currentHost=
    currentPort=
    currentCDNAddress=
    xrayVLESSRealityVisionPort=
    singBoxVMessWSPath=
    singBoxVLESSWSPath=
    singBoxVMessHTTPUpgradePath=

    if [[ "${coreKind}" == "1" ]]; then

        # 安装
        if [[ -n "${frontingType}" ]]; then
            currentHost=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}${frontingType}.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '[.][c][r][t]' '{print $1}')

            currentPort=$(jq .inbounds[0].port ${configPath}${frontingType}.json)

            local defaultPortFile=
            defaultPortFile=$(find ${configPath}* | grep "default")

            if [[ -n "${defaultPortFile}" ]]; then
                currentDefaultPort=$(echo "${defaultPortFile}" | awk -F [_] '{print $4}')
            else
                currentDefaultPort=$(jq -r .inbounds[0].port ${configPath}${frontingType}.json)
            fi
            currentUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].settings.clients ${configPath}${frontingType}.json)
        fi

        # reality
        if echo ${currentInstallProtocolType} | grep -q ",7,"; then

            currentClients=$(jq -r .inbounds[1].settings.clients ${configPath}07_VLESS_vision_reality_inbounds.json)
            currentUUID=$(jq -r .inbounds[1].settings.clients[0].id ${configPath}07_VLESS_vision_reality_inbounds.json)
            xrayVLESSRealityVisionPort=$(jq -r .inbounds[0].port ${configPath}07_VLESS_vision_reality_inbounds.json)
            if [[ "${currentPort}" == "${xrayVLESSRealityVisionPort}" ]]; then
                xrayVLESSRealityVisionPort="${currentDefaultPort}"
            fi
        fi
    elif [[ "${coreKind}" == "2" ]]; then
        # fronting 落在 ss2022 上且装有 Reality 时改用 Reality 文件当身份源——ss2022 的 password 是派生 uPSK
        if [[ "${frontingType}" == "14_ss2022_inbounds" && -n "${frontingTypeReality}" ]]; then
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingTypeReality}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingTypeReality}.json)
        elif [[ -n "${frontingType}" ]]; then
            # 14 / 16 没有 tls 块：读成字面 null 会被当成域名，订阅每次查看都重配、换端口
            currentHost=$(jq -r '.inbounds[0].tls.server_name // empty' "${configPath}${frontingType}.json")
            if echo ${currentInstallProtocolType} | grep -q ",11," && [[ -z "${currentHost}" ]]; then
                currentHost=$(grep 'server_name' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
                currentHost=${currentHost//;/}
            fi
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingType}.json)
        elif [[ -n "${frontingTypeReality}" ]]; then
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingTypeReality}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingTypeReality}.json)
        fi
    fi

    # 读取path
    if [[ -n "${configPath}" && -n "${frontingType}" ]]; then
        if [[ "${coreKind}" == "1" ]]; then
            local fallback
            fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' ${configPath}${frontingType}.json | head -1)

            local path
            path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}')

            if [[ $(echo "${fallback}" | jq -r .dest) == 31297 ]]; then
                currentPath=$(echo "${path}" | awk -F "[w][s]" '{print $1}')
            elif [[ $(echo "${fallback}" | jq -r .dest) == 31299 ]]; then
                currentPath=$(echo "${path}" | awk -F "[v][w][s]" '{print $1}')
            fi

            # 尝试读取alpn h2 Path
            if [[ -z "${currentPath}" ]]; then
                dest=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.alpn)|.dest' ${configPath}${frontingType}.json | head -1)
                if [[ "${dest}" == "31302" || "${dest}" == "31304" ]]; then
                    if grep -q "trojangrpc {" <${nginxConfigPath}alone.conf; then
                        currentPath=$(grep "trojangrpc {" <${nginxConfigPath}alone.conf | awk -F "[/]" '{print $2}' | awk -F "[t][r][o][j][a][n]" '{print $1}')
                    elif grep -q "grpc {" <${nginxConfigPath}alone.conf; then
                        currentPath=$(grep "grpc {" <${nginxConfigPath}alone.conf | head -1 | awk -F "[/]" '{print $2}' | awk -F "[g][r][p][c]" '{print $1}')
                    fi
                fi
            fi
            if [[ -z "${currentPath}" && -f "${configPath}15_VLESS_XHTTP_TLS_inbounds.json" ]]; then
                currentPath=$(jq -r .inbounds[0].streamSettings.xhttpSettings.path "${configPath}15_VLESS_XHTTP_TLS_inbounds.json" | sed -e 's#^/##' -e 's#xhttp$##')
            fi
            if [[ -z "${currentPath}" && -f "${configPath}12_VLESS_XHTTP_inbounds.json" ]]; then
                currentPath=$(jq -r .inbounds[0].streamSettings.xhttpSettings.path "${configPath}12_VLESS_XHTTP_inbounds.json" | awk -F "[x][H][T][T][P]" '{print $1}' | awk -F "[/]" '{print $2}')
            fi
        elif [[ "${coreKind}" == "2" && -f "${singBoxConfigPath}05_VMess_WS_inbounds.json" ]]; then
            singBoxVMessWSPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}05_VMess_WS_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}05_VMess_WS_inbounds.json" | awk -F "[/]" '{print $2}')
        fi
        if [[ "${coreKind}" == "2" && -f "${singBoxConfigPath}03_VLESS_WS_inbounds.json" ]]; then
            singBoxVLESSWSPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}03_VLESS_WS_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}03_VLESS_WS_inbounds.json" | awk -F "[/]" '{print $2}')
            currentPath=${currentPath::-2}
        fi
        if [[ "${coreKind}" == "2" && -f "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
            singBoxVMessHTTPUpgradePath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" | awk -F "[/]" '{print $2}')
            # currentPath=${currentPath::-2}
        fi
    fi
    if [[ -f "${PROXY_AGENT_DIR}/cdn" ]] && [[ -n "$(head -1 ${PROXY_AGENT_DIR}/cdn)" ]]; then
        currentCDNAddress=$(head -1 ${PROXY_AGENT_DIR}/cdn)
    else
        currentCDNAddress="${currentHost}"
    fi
}

# 状态展示
showInstallStatus() {
    if [[ -n "${coreKind}" ]]; then
        if [[ "${coreKind}" == 1 ]]; then
            if xrayDaemonRunning; then
                echoContent yellow "\n$(t CORE_CURRENT_RUNNING "Xray-core")"
            else
                echoContent yellow "\n$(t CORE_CURRENT_STOPPED "Xray-core")"
            fi

        elif [[ "${coreKind}" == 2 ]]; then
            if [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
                echoContent yellow "\n$(t CORE_CURRENT_RUNNING "sing-box")"
            else
                echoContent yellow "\n$(t CORE_CURRENT_STOPPED "sing-box")"
            fi
        fi
        # 读取协议类型
        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            local pid
            echoContent yellow "$(t PROTOCOLS_INSTALLED): \c"
            # 各项用 \c 抑制换行、按 ID 升序打印；末尾补一个换行，否则菜单首项会接在协议行末
            for pid in $(tr ',' '\n' <<<"${currentInstallProtocolType}" | sort -n); do
                echoContent yellow "$(getProtocolDisplayName "${pid}") \c"
            done
            echo
        fi
    fi
}

# chainRefuseCoreSwitch TARGET_CORE → 本机是链式入口时拒绝换内核：入口在两种内核下结构不同，换过去旧内核那半被删，
# 留下的那半再没有流量进来，链路静默失效。出口 / 中继只在 sing-box 片段里，换内核不受影响
chainRefuseCoreSwitch() {
    [[ -n "${coreKind}" && "${coreKind}" != "$1" ]] || return 0
    [[ -f "${CHAIN_ENTRY_INFO}" || -f "${CHAIN_MULTI_INFO}" ]] || return 0
    echoContent red " ---> $(t CHAIN_REFUSE_CORE_SWITCH)"
    exit 1
}

# 清理旧残留。singBoxProtocolsDel PREV_CORE：Xray 安装只在从 sing-box 内核（PREV_CORE=2）切过来时删它的协议入站，
# 已是 Xray 内核时旁挂的 6 / 9 与链式出口 / 中继原样留着；删完片段里还有入站（出口、中继）就让 sing-box 接着跑
cleanUp() {
    if [[ "$1" == "xrayDel" ]]; then
        handleXray stop
        # 服务单元连同自启一起撤：留着的话每次开机都去拉一个已删掉的二进制
        if [[ "${release}" == "alpine" ]]; then
            rc-update del xray default >/dev/null 2>&1
            rm -f /etc/init.d/xray
        elif [[ -f /etc/systemd/system/xray.service ]]; then
            systemctl disable xray.service >/dev/null 2>&1
            rm -f /etc/systemd/system/xray.service
            systemctl daemon-reload >/dev/null 2>&1
        fi
        rm -rf ${XRAY_DIR}/*
        rm -f "${nginxConfigPath}http_redirect.conf"
    elif [[ "$1" == "singBoxProtocolsDel" ]]; then
        local file
        if [[ "$2" != "2" ]]; then
            if [[ -f "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" || -f "${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json" ]]; then
                echoContent yellow " ---> $(t CLEANUP_SIDECAR_KEPT)"
            fi
            return 0
        fi
        handleSingBox stop
        rm -f "${SINGBOX_MERGED_CONFIG}"
        for file in "${SINGBOX_FRAGMENT_DIR}"/*_inbounds.json; do
            if [[ -f "${file}" && -n "$(parseProtocolIdFromFileName "${file}")" ]]; then
                rm -f "${file}"
            fi
        done
        if singBoxFragmentsHaveInbounds; then
            handleSingBox start
        fi
    fi
}
# -------------------------------------------------------------

# 初始化安装目录
mkdirTools() {
    # TLS证书目录 - 设置严格权限保护私钥
    mkdir -p ${TLS_DIR}
    chmod 700 ${TLS_DIR}

    # subscribe_local/_remote 存明文节点配置（含 UUID），收紧到 root-only；
    # nginx 只读对外发布目录 subscribe/，不受影响
    mkdir -p ${SUBSCRIBE_LOCAL_DIR}/default
    mkdir -p ${SUBSCRIBE_LOCAL_DIR}/clashMeta
    chmod 700 ${SUBSCRIBE_LOCAL_DIR}

    mkdir -p ${SUBSCRIBE_REMOTE_DIR}/default
    mkdir -p ${SUBSCRIBE_REMOTE_DIR}/clashMeta
    chmod 700 ${SUBSCRIBE_REMOTE_DIR}

    mkdir -p ${SUBSCRIBE_DIR}/default
    mkdir -p ${SUBSCRIBE_DIR}/clashMetaProfiles
    mkdir -p ${SUBSCRIBE_DIR}/clashMeta

    mkdir -p ${SUBSCRIBE_DIR}/sing-box
    mkdir -p ${SUBSCRIBE_DIR}/sing-box_profiles
    mkdir -p ${SUBSCRIBE_LOCAL_DIR}/sing-box

    # Xray配置目录 - 设置适当权限
    mkdir -p ${XRAY_CONF_DIR}
    chmod 700 ${XRAY_CONF_DIR}
    mkdir -p ${XRAY_DIR}/tmp
    mkdir -p /etc/systemd/system/

    # WARP配置目录 - 包含私钥
    mkdir -p ${WARP_DIR}
    chmod 700 ${WARP_DIR}

    # sing-box配置目录 - 设置适当权限
    mkdir -p ${SINGBOX_FRAGMENT_DIR}
    chmod 700 ${SINGBOX_CONF_DIR}

    mkdir -p /usr/share/nginx/html/
}
# checkRoot 由 lib/system-detect.sh 提供（非 root 直接 exit 1；
# 旧 inline 仅打印不退出是隐藏 bug——后续大量写 /etc/、systemctl 操作必然失败）。

# 安装工具包
installTools() {
    echoContent skyBlue "\n$(t PROGRESS_STEP "$1" "${totalProgress}") : $(t PROG_INSTALL_TOOLS)"
    installBaseTools

    # 检测nginx版本，并提供是否卸载的选项
    # 个性化安装里一个要证书的协议都没选（7、12 这类 Reality）就不装 nginx 与 acme.sh；全部安装时清单为空，照装
    if [[ -n "${selectCustomInstallType}" ]] && ! anyProtocolRequiresTLS "${selectCustomInstallType}"; then
        echoContent green " ---> 检测到无需依赖Nginx的服务，跳过安装"
    else
        if ! command -v nginx >/dev/null 2>&1; then
            echoContent green " ---> 安装nginx"
            installNginxTools || exit 1
        else
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            if [[ ${nginxVersion} -lt 14 ]]; then
                read -r -p "读取到当前的Nginx版本过旧（低于1.14），是否卸载后重新安装 ？[y/n]:" unInstallNginxStatus
                if isYesInput "${unInstallNginxStatus}"; then
                    ${removeType} nginx >/dev/null 2>&1
                    echoContent yellow " ---> nginx卸载完成"
                    echoContent green " ---> 安装nginx"
                    installNginxTools || exit 1
                else
                    exit 0
                fi
            fi
        fi
    fi

    if [[ -n "${selectCustomInstallType}" ]] && ! anyProtocolRequiresTLS "${selectCustomInstallType}"; then
        echoContent green " ---> 检测到无需依赖证书的服务，跳过安装"
    else
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            echoContent green " ---> 安装acme.sh"
            # acme.sh 把 curl 的响应头写进 HTTP_HEADER 指的文件；不给就自己在 /tmp 建一个、装完不删
            local acmeHttpHeader=
            acmeHttpHeader=$(mktemp "${TLS_DIR}/.acme-header.XXXXXX") || acmeHttpHeader=
            curl -s https://get.acme.sh | HTTP_HEADER="${acmeHttpHeader}" sh >${TLS_DIR}/acme.log 2>&1
            [[ -n "${acmeHttpHeader}" ]] && rm -f "${acmeHttpHeader}"

            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent red "  acme安装失败--->"
                tail -n 100 ${TLS_DIR}/acme.log
                echoContent yellow "错误排查:"
                echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
                echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
                echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他NAT64"
                echoContent skyBlue "  sed -i \"1i\\\nameserver 2a00:1098:2b::1\\\nnameserver 2a00:1098:2c::1\\\nnameserver 2a01:4f8:c2c:123f::1\\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                exit 1
            fi
        fi
    fi

}

# installBaseTools → 等包管理器空闲、刷新索引、补齐脚本自己要用的命令行工具（jq / wget / curl / tar 等，不含 nginx 与 acme.sh）。
# 只配链式角色的裸机从没跑过安装流程，也必须先过这里：installSingBox 缺 jq / wget 时会被误报成网络问题
installBaseTools() {
    # 修复ubuntu个别系统问题
    if [[ "${release}" == "ubuntu" ]]; then
        dpkg --configure -a
    fi

    # 等 apt/dpkg 跑完而不是 kill -9：SIGKILL 截断 dpkg 事务会损坏包数据库。unattended-upgrades 按命令行认——
    # 常驻的 unattended-upgrade-shutdown 进程名同样截断成 unattended-upgr，按名字认会等满超时、装机必败
    if [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        local aptWaited=0
        while pgrep -x "apt|apt-get|dpkg|aptitude" >/dev/null 2>&1 || pgrep -f "(^|/)unattended-upgrade( |$)" >/dev/null 2>&1; do
            if [[ ${aptWaited} -eq 0 ]]; then
                echoContent yellow " ---> $(t PKG_MANAGER_WAIT)"
            fi
            if [[ ${aptWaited} -ge 120 ]]; then
                echoContent red " ---> $(t PKG_MANAGER_WAIT_TIMEOUT)"
                exit 1
            fi
            sleep 5
            aptWaited=$((aptWaited + 5))
        done
    fi

    echoContent green " ---> $(t INSTALL_CHECKING)"

    ${upgrade} >${PROXY_AGENT_DIR}/install.log 2>&1
    if grep <"${PROXY_AGENT_DIR}/install.log" -q "changed"; then
        ${updateReleaseInfoChange} >/dev/null 2>&1
    fi

    if [[ "${release}" == "centos" ]]; then
        # 只清确认已死的陈旧锁；删活锁会让两个 yum 并发写包数据库
        if [[ -f "/var/run/yum.pid" ]]; then
            local yumPid
            yumPid=$(cat /var/run/yum.pid 2>/dev/null)
            if [[ -n "${yumPid}" ]] && kill -0 "${yumPid}" 2>/dev/null; then
                echoContent red " ---> $(t PKG_MANAGER_YUM_LIVE "${yumPid}")"
                exit 1
            fi
            rm -f /var/run/yum.pid
        fi
        ${installType} epel-release >/dev/null 2>&1
    fi

    if ! wget --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "wget")"
        ${installType} wget >/dev/null 2>&1
    fi

    # 装了 ufw 就不装 iptables-persistent：两包互斥，apt -y 会直接卸掉 ufw，用户的默认拒绝随之失效、整机全开
    if ! command -v netfilter-persistent >/dev/null 2>&1 && ! dpkg-query -W -f '${Status}' ufw 2>/dev/null | grep -q 'ok installed'; then
        if [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
            echoContent green " ---> $(t INSTALL_TOOL "iptables")"
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
            ${installType} iptables-persistent >/dev/null 2>&1
        fi
    fi

    if ! curl --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "curl")"
        ${installType} curl >/dev/null 2>&1
    fi

    if ! unzip >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "unzip")"
        ${installType} unzip >/dev/null 2>&1
    fi

    if ! socat -h >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "socat")"
        ${installType} socat >/dev/null 2>&1
    fi

    if ! tar --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "tar")"
        ${installType} tar >/dev/null 2>&1
    fi

    if ! crontab -l >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "crontabs")"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            # 不装推荐包：Debian 上 cron 推荐的 MTA 会拉进常驻 127.0.0.1:25 的 exim4，本脚本的定时任务输出都写日志、用不上邮件
            ${installType} --no-install-recommends cron >/dev/null 2>&1
        else
            ${installType} crontabs >/dev/null 2>&1
        fi
    fi
    ensureCronService
    if ! jq --help >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "jq")"
        ${installType} jq >/dev/null 2>&1
    fi

    if ! command -v ld >/dev/null 2>&1; then
        echoContent green " ---> $(t INSTALL_TOOL "binutils")"
        ${installType} binutils >/dev/null 2>&1
    fi

    if ! openssl help >/dev/null 2>&1; then
        echoContent green " ---> 安装openssl"
        ${installType} openssl >/dev/null 2>&1
    fi

    if ! qrencode --help >/dev/null 2>&1; then
        echoContent green " ---> 安装qrencode"
        # Alpine 的命令行工具在 libqrencode-tools 里，没有叫 qrencode 的包，按这个名字装会静默失败、一直没有二维码
        if [[ "${release}" == "alpine" ]]; then
            ${installType} libqrencode-tools >/dev/null 2>&1
        else
            ${installType} qrencode >/dev/null 2>&1
        fi
    fi

    if ! command -v lsb_release >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            ${installType} lsb-release >/dev/null 2>&1
        elif [[ "${release}" == "centos" ]]; then
            ${installType} redhat-lsb-core >/dev/null 2>&1
        else
            ${installType} lsb-release >/dev/null 2>&1
        fi
    fi

    if ! lsof -h >/dev/null 2>&1; then
        echoContent green " ---> 安装lsof"
        ${installType} lsof >/dev/null 2>&1
    fi

    ensureAlpineProcps

    if ! dig -h >/dev/null 2>&1; then
        echoContent green " ---> 安装dig"
        if echo "${installType}" | grep -qw "apt"; then
            ${installType} dnsutils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "yum"; then
            ${installType} bind-utils >/dev/null 2>&1
        elif echo "${installType}" | grep -qw "apk"; then
            ${installType} bind-tools >/dev/null 2>&1
        fi
    fi
}
# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload
        systemctl enable "${serviceName}"
    fi
}
# 让 cron 守护进程真的在跑：BusyBox 自带 crontab 但 Alpine 从不自启 crond，定时任务会静默不执行
ensureCronService() {
    local serviceName=cron
    if [[ "${release}" == "alpine" || "${release}" == "centos" ]]; then
        serviceName=crond
    fi
    if [[ "${release}" == "alpine" ]]; then
        rc-service "${serviceName}" status >/dev/null 2>&1 && return 0
    else
        systemctl is-active --quiet "${serviceName}" 2>/dev/null && return 0
    fi
    bootStartup "${serviceName}" >/dev/null 2>&1
    local startOk=true
    if [[ "${release}" == "alpine" ]]; then
        rc-service "${serviceName}" start >/dev/null 2>&1 || startOk=false
    else
        systemctl start "${serviceName}" >/dev/null 2>&1 || startOk=false
    fi
    if [[ "${startOk}" != "true" ]]; then
        echoContent yellow " ---> $(t CRON_SERVICE_START_FAILED "${serviceName}")"
        return 1
    fi
    echoContent green " ---> $(t CRON_SERVICE_STARTED "${serviceName}")"
}
# 安装Nginx
installNginxTools() {

    if [[ "${release}" == "debian" ]]; then
        apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb https://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        apt update >/dev/null 2>&1

    elif [[ "${release}" == "ubuntu" ]]; then
        apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb https://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        # gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
        mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        apt update >/dev/null 2>&1

    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        cat <<EOF >/etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    elif [[ "${release}" == "alpine" ]]; then
        rm "${nginxConfigPath}default.conf"
    fi
    if ! ${installType} nginx >/dev/null 2>&1; then
        echoContent red " ---> $(t NGINX_INSTALL_FAILED)"
        return 1
    fi
    bootStartup nginx
}

# 通过dns检查域名的IP
checkDNSIP() {
    local domain=$1
    local dnsIP=
    ipType=4
    dnsIP=$(dig @1.1.1.1 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    if [[ -z "${dnsIP}" ]]; then
        dnsIP=$(dig @8.8.8.8 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
    fi
    if echo "${dnsIP}" | grep -q "timed out" || [[ -z "${dnsIP}" ]]; then
        echo
        echoContent red " ---> 无法通过DNS获取域名 IPv4 地址"
        echoContent green " ---> 尝试检查域名 IPv6 地址"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if echo "${dnsIP}" | grep -q "network unreachable" || [[ -z "${dnsIP}" ]]; then
            echoContent red " ---> 无法通过DNS获取域名IPv6地址，退出安装"
            exit 1
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        echoContent red " ---> 域名解析IP与当前服务器IP不一致\n"
        echoContent yellow " ---> 请检查域名解析是否生效以及正确"
        echoContent green " ---> 当前VPS IP：${publicIP}"
        echoContent green " ---> DNS解析 IP：${dnsIP}"
        exit 1
    else
        echoContent green " ---> 域名IP校验通过"
    fi
}
# 检查端口实际开放状态
checkPortOpen() {
    handleSingBox stop >/dev/null 2>&1
    handleXray stop >/dev/null 2>&1

    local port=$1
    local domain=$2
    local checkPortOpenResult=
    allowPort "${port}"

    if [[ -z "${btDomain}" ]]; then

        handleNginx stop
        # 初始化nginx配置
        touch ${nginxConfigPath}checkPortOpen.conf
        local listenIPv6PortConfig=

        if [[ -n $(curl -s -6 -m 4 https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2) ]]; then
            listenIPv6PortConfig="listen [::]:${port};"
        fi
        cat <<EOF >${nginxConfigPath}checkPortOpen.conf
server {
    listen ${port};
    ${listenIPv6PortConfig}
    server_name ${domain};
    location /checkPort {
        return 200 'fjkvymb6len';
    }
    location /ip {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header REMOTE-HOST \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        default_type text/plain;
        return 200 \$proxy_add_x_forwarded_for;
    }
}
EOF
        # 子 shell 接住 handleNginx 的退出才删得掉临时配置：留着它，之后每次起 nginx 都多听这个端口
        if ! (handleNginx start); then
            rm "${nginxConfigPath}checkPortOpen.conf"
            exit 1
        fi
        # 检查域名+端口的开放
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        rm "${nginxConfigPath}checkPortOpen.conf"
        handleNginx stop
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            echoContent green " ---> 检测到${port}端口已开放"
        else
            echoContent green " ---> 未检测到${port}端口开放，退出安装"
            if echo "${checkPortOpenResult}" | grep -q "cloudflare"; then
                echoContent yellow " ---> 请关闭云朵后等待三分钟重新尝试"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    echoContent red " ---> 请检查是否有网页防火墙，比如Oracle等云服务商"
                    echoContent red " ---> 检查是否自己安装过nginx并且有配置冲突，可以尝试DD纯净系统后重新尝试"
                else
                    echoContent red " ---> 错误日志：${checkPortOpenResult}，请将此错误日志通过issues提交反馈"
                fi
            fi
            exit 1
        fi
        checkIP "${localIP}"
    fi
}

# 初始化Nginx申请证书配置
initTLSNginxConfig() {
    handleNginx stop
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
    # 域名采集：复用 readValidDomain 做"输入即校验"，失败统一回到本函数自身重试
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
        if isYesInput "${historyDomainStatus}"; then
            domain=${currentHost}
            echoContent yellow "\n ---> 域名: ${domain}"
        else
            echo
            echoContent yellow "请输入要配置的域名 例: example.com --->"
            if ! readValidDomain "域名:" domain; then
                initTLSNginxConfig 3
                return
            fi
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        echoContent yellow "请输入要配置的域名 例: example.com --->"
        if ! readValidDomain "域名:" domain; then
            initTLSNginxConfig 3
            return
        fi
    fi

    # 沿用历史域名时再做一次校验（防止历史值被外部篡改）
    if ! isValidDomain "${domain}"; then
        echoContent red "  域名格式无效或包含不安全字符--->"
        initTLSNginxConfig 3
        return
    fi

    dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    if [[ "${selectCoreType}" == "1" ]]; then
        customPortFunction
    fi
    # 修改配置
    handleNginx stop
}

# 删除nginx默认的配置
removeNginxDefaultConf() {
    if [[ -f "${nginxConfigPath}default.conf" ]]; then
        if [[ "$(grep -c "server_name" <"${nginxConfigPath}default.conf")" == "1" ]] && [[ "$(grep -c "server_name  localhost;" <"${nginxConfigPath}default.conf")" == "1" ]]; then
            echoContent green " ---> 删除Nginx默认配置"
            rm -rf "${nginxConfigPath}default.conf" >/dev/null 2>&1
        fi
    fi
}
# xhttpTlsNginxLocation CUSTOM_PATH → 15 在 h2 块里的 location，路径与 initXrayConfig 写进入站的同源（/CUSTOM_PATHxhttp）。
# 超时要长过 Xray 默认的 300 秒空闲：nginx 默认 60 秒，代理连接一空闲就被掐。一个包一条 POST，access_log 开着日志会暴涨
xhttpTlsNginxLocation() {
    cat <<EOF
location /${1}xhttp/ {
		access_log off;
		client_max_body_size 0;
		client_body_timeout 5m;
		grpc_read_timeout 315s;
		grpc_send_timeout 5m;
		grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		grpc_pass grpc://127.0.0.1:${XHTTP_TLS_LOCAL_PORT};
	}
EOF
}

# 修改nginx重定向配置。全部安装传 all（此时 selectCustomInstallType 是空的）
updateRedirectNginxConf() {
    local redirectDomain=
    redirectDomain=${domain}:${port}

    local xhttpLocation=
    if [[ "$1" == "all" || "${selectCustomInstallType}" == *",15,"* ]]; then
        xhttpLocation=$(xhttpTlsNginxLocation "${customPath}")
    fi

    local nginxH2Conf=
    nginxH2Conf="listen 127.0.0.1:31302 http2 so_keepalive=on proxy_protocol;"
    nginxVersion=$(nginx -v 2>&1)

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen 127.0.0.1:31302 so_keepalive=on proxy_protocol;http2 on;"
    fi

    cat <<EOF >${nginxConfigPath}alone.conf
    server {
    		listen 127.0.0.1:31300;
    		server_name _;
    		return 403;
    }
EOF

    # gRPC nginx配置块已移除（协议2和5已废弃）
    cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	# 安全头部
	server_tokens off;
	add_header X-Content-Type-Options "nosniff" always;
	add_header X-Frame-Options "SAMEORIGIN" always;

	${xhttpLocation}
	location / {
		try_files \$uri \$uri/ =404;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt { log_not_found off; access_log off; }
}
EOF

    cat <<EOF >>${nginxConfigPath}alone.conf
server {
	listen 127.0.0.1:31300 proxy_protocol;
	server_name ${domain};

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	root ${nginxStaticPath};

	# 安全头部
	server_tokens off;

	location / {
		try_files \$uri \$uri/ =404;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt { log_not_found off; access_log off; }
}
EOF
    handleNginx stop
    writeHttpRedirectNginxConf
}

# writeHttpRedirectNginxConf → 80 上把域名 301 到 0 的 https 端口，和普通网站一样。nginx 须已停：80 是否空闲靠它判
# 只给 Xray 的 0 用（443 背后有伪装站）；宝塔 / 1Panel 自己管 80，80 被别的程序占着也不写，免得 nginx 整个起不来
writeHttpRedirectNginxConf() {
    local conf="${nginxConfigPath}http_redirect.conf" listen="listen 80;" target="https://${domain}"
    rm -f "${conf}"
    if [[ -n "${btDomain}" || "${port}" == "80" ]]; then
        return 0
    fi
    if portListed 80 "$(listeningPorts tcp)"; then
        echoContent yellow " ---> $(t NGINX_HTTP_REDIRECT_SKIPPED)"
        return 0
    fi
    if [[ -f /proc/net/if_inet6 ]]; then
        listen="${listen} listen [::]:80;"
    fi
    if [[ "${port}" != "443" ]]; then
        target="${target}:${port}"
    fi
    # 只对带本域名 Host 的请求跳转：这个块常是 :80 唯一的 server，别的 Host 也落到这里，跳转就把域名交给了按 IP 扫的人。
    # 看 $http_host 不看 $host：请求不带 Host 时 $host 回落成 server_name，照样会跳
    cat <<EOF >"${conf}"
server {
	${listen}
	server_name ${domain};
	server_tokens off;
	if (\$http_host !~* "^${domain//./\\.}(:80)?\$") {
		return 444;
	}
	return 301 ${target}\$request_uri;
}
EOF
    allowPort 80
}
# singbox Nginx config
singBoxNginxConfig() {
    local type=$1
    local port=$2

    local nginxH2Conf=
    nginxH2Conf="listen ${port} http2 so_keepalive=on ssl;"
    nginxVersion=$(nginx -v 2>&1)

    local singBoxNginxSSL=
    singBoxNginxSSL="ssl_certificate ${TLS_DIR}/${domain}.crt;ssl_certificate_key ${TLS_DIR}/${domain}.key;"

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen ${port} so_keepalive=on ssl;http2 on;"
    fi

    if echo "${selectCustomInstallType}" | grep -q ",11," || [[ "$1" == "all" ]]; then
        cat <<EOF >>${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf
server {
	${nginxH2Conf}

	server_name ${domain};
	root ${nginxStaticPath};
    ${singBoxNginxSSL}

    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;

    location /${currentPath} {
    	if (\$http_upgrade != "websocket") {
            return 444;
        }

        proxy_pass                          http://127.0.0.1:31306;
        proxy_http_version                  1.1;
        proxy_set_header Upgrade            \$http_upgrade;
        proxy_set_header Connection         "upgrade";
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header Host               \$host;
        proxy_redirect                      off;
	}
}
EOF
    fi
}

# 检查ip
checkIP() {
    echoContent skyBlue "\n ---> 检查域名ip中"
    local localIP=$1

    if [[ -z ${localIP} ]] || ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q '\.' && ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q ':'; then
        echoContent red "\n ---> 未检测到当前域名的ip"
        echoContent skyBlue " ---> 请依次进行下列检查"
        echoContent yellow " --->  1.检查域名是否书写正确"
        echoContent yellow " --->  2.检查域名dns解析是否正确"
        echoContent yellow " --->  3.如解析正确，请等待dns生效，预计三分钟内生效"
        echoContent yellow " --->  4.如报Nginx启动问题，请手动启动nginx查看错误，如自己无法处理请提issues"
        echo
        echoContent skyBlue " ---> 如以上设置都正确，请重新安装纯净系统后再次尝试"

        if [[ -n ${localIP} ]]; then
            echoContent yellow " ---> 检测返回值异常，建议手动卸载nginx后重新执行脚本"
            echoContent red " ---> 异常结果：${localIP}"
        fi
        exit 1
    else
        if echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q "." || echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q ":"; then
            echoContent red "\n ---> 检测到多个ip，请确认是否关闭cloudflare的云朵"
            echoContent yellow " ---> 关闭云朵后等待三分钟后重试"
            echoContent yellow " ---> 检测到的ip如下:[${localIP}]"
            exit 1
        fi
        echoContent green " ---> 检查当前域名IP正确"
    fi
}
# 自定义email
customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if isYesInput "${sslEmailStatus}"; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
                echoContent green " ---> 添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                customSSLEmail
            fi
        fi
    fi

}
# DNS API申请证书
switchDNSAPI() {
    read -r -p "是否使用DNS API申请证书[支持NAT]？[y/n]:" dnsAPIStatus
    if isYesInput "${dnsAPIStatus}"; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.cloudflare[默认]"
        echoContent yellow "2.aliyun"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectDNSAPIType
        case ${selectDNSAPIType} in
        1)
            dnsAPIType="cloudflare"
            ;;
        2)
            dnsAPIType="aliyun"
            ;;
        *)
            dnsAPIType="cloudflare"
            ;;
        esac
        initDNSAPIConfig "${dnsAPIType}"
    fi
}
# 初始化dns配置
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        echoContent yellow "\n 请在 Cloudflare 控制台为 DNS 编辑权限创建 API Token 并填入 CF_Token/CF_Account_ID。\n"
        read -r -p "请输入API Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent red " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 1
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        read -r -p "请输入Ali Key:" aliKey
        read -r -p "请输入Ali Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent red " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 1
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    fi
}
# 选择ssl安装类型
switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.letsencrypt[默认]"
        echoContent yellow "2.zerossl"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectSSLType
        case ${selectSSLType} in
        1)
            sslType="letsencrypt"
            ;;
        2)
            sslType="zerossl"
            ;;
        *)
            sslType="letsencrypt"
            ;;
        esac
        echo "${sslType}" >${TLS_DIR}/ssl_type
    fi
}

# 选择acme安装证书方式
selectAcmeInstallSSL() {
    #    local sslIPv6=
    #    local currentIPType=
    if [[ "${ipType}" == "6" ]]; then
        sslIPv6="--listen-v6"
    fi


    acmeInstallSSL

    readAcmeTLS
}

# 安装SSL证书
acmeInstallSSL() {
    local acmeDomainArgs
    acmeDomainArgs=$(acmeIssueDomainArgs "${tlsDomain}" "${dnsTLSDomain}" "${dnsAPIStatus}")

    if [[ "${dnsAPIType}" == "cloudflare" ]]; then
        echoContent green " ---> DNS API 生成证书中"
        # 使用临时环境文件避免在进程列表中暴露API Token
        local acmeEnvFile
        acmeEnvFile=$(mktemp)
        chmod 600 "${acmeEnvFile}"
        cat > "${acmeEnvFile}" << ACME_ENV_EOF
export CF_Token="${cfAPIToken}"
ACME_ENV_EOF
        # shellcheck source=/dev/null
        bash -c "source '${acmeEnvFile}' && '$HOME/.acme.sh/acme.sh' --issue ${acmeDomainArgs} --dns dns_cf -k ec-256 --server '${sslType}' ${sslIPv6}" 2>&1 | tee -a ${TLS_DIR}/acme.log >/dev/null
        rm -f "${acmeEnvFile}"
    elif [[ "${dnsAPIType}" == "aliyun" ]]; then
        echoContent green " --->  DNS API 生成证书中"
        # 使用临时环境文件避免在进程列表中暴露API Key/Secret
        local acmeEnvFile
        acmeEnvFile=$(mktemp)
        chmod 600 "${acmeEnvFile}"
        cat > "${acmeEnvFile}" << ACME_ENV_EOF
export Ali_Key="${aliKey}"
export Ali_Secret="${aliSecret}"
ACME_ENV_EOF
        # shellcheck source=/dev/null
        bash -c "source '${acmeEnvFile}' && '$HOME/.acme.sh/acme.sh' --issue ${acmeDomainArgs} --dns dns_ali -k ec-256 --server '${sslType}' ${sslIPv6}" 2>&1 | tee -a ${TLS_DIR}/acme.log >/dev/null
        rm -f "${acmeEnvFile}"
    else
        echoContent green " ---> 生成证书中"
        "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a ${TLS_DIR}/acme.log >/dev/null
    fi
}
# 自定义端口
customPortFunction() {
    local historyCustomPortStatus= reuseLastPort=
    if [[ -n "${customPort}" || -n "${currentPort}" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口？[y/n]:" historyCustomPortStatus
            if isYesInput "${historyCustomPortStatus}"; then
                port=${currentPort}
                reuseLastPort=true
                echoContent yellow "\n ---> 端口: ${port}"
            fi
        elif [[ -n "${lastInstallationConfig}" ]]; then
            port=${currentPort}
            reuseLastPort=true
        fi
    fi
    # 没明确沿用就重新问：回车之类的回答若两头都不进，port 为空，写出的入站配置不是合法 JSON
    if [[ -z "${currentPort}" || -z "${reuseLastPort}" ]]; then
        echo

        if [[ -n "${btDomain}" ]]; then
            echoContent yellow "请输入端口[不可与BT Panel/1Panel端口相同，回车随机]"
            # 回车随机生成 10000-30000；输入需为合法端口
            readValidPort "端口:" port "RANDOM" 10000 30000 || exit 1
        else
            # 0 优先：KEEP 只列 0 自己（又被跳过），别的协议的旧端口都不算占用——它们都在 0 之后重配，撞上的会被改走。
            # 这样带域名的 Xray 不论先装过什么，0 都拿 443，和全新安装的布局一致
            port=$(pickInboundPort 0 "" "${XRAY_CONF_DIR}" ",0," "")
            if [[ "${port}" == "${xrayVLESSRealityPort}" ]]; then
                handleXray stop
            fi
        fi

        allowPort "${port}"
        echoContent yellow "\n ---> 端口: ${port}"
        if [[ -z "${btDomain}" ]]; then
            checkDNSIP "${domain}"
            removeNginxDefaultConf
            checkPortOpen "${port}" "${domain}"
        fi
    fi
}

# listeningPorts tcp|udp → 本机此刻占着的端口，每行一个（TCP 只算 LISTEN，UDP 绑上就算）
# 读 /proc/net：UDP 套接字没有 LISTEN 状态，按 lsof 的 LISTEN 过滤查不出来
listeningPorts() {
    local state= hex
    [[ "$1" == "tcp" ]] && state=0A
    awk -v s="${state}" 'FNR > 1 && (s == "" || $4 == s) { split($2, a, ":"); print a[2] }' \
        "/proc/net/$1" "/proc/net/${1}6" 2>/dev/null | sort -u | while read -r hex; do
        printf '%d\n' "$((16#${hex}))"
    done
}

# configuredPorts DIR tcp|udp [KEEP] [SKIP] → DIR 下入站配置在该网络上的对外端口，每行一个
# KEEP 非空时只算其中的协议，SKIP 里的不算（都是 ",0,7," 形式）；只听 127.0.0.1 的回落入站不算
configuredPorts() {
    local dir=$1 network=$2 keep=${3:-} skip=${4:-} file id listenNetwork
    while IFS= read -r file; do
        id=$(parseProtocolIdFromFileName "${file}") || continue
        [[ -n "${keep}" && "${keep}" != *",${id},"* ]] && continue
        [[ "${skip}" == *",${id},"* ]] && continue
        listenNetwork=$(getProtocolListenNetwork "${id}") || continue
        [[ "${listenNetwork}" == "both" || "${listenNetwork}" == "${network}" ]] || continue
        if [[ "${id}" == "11" ]]; then
            # sing-box 的 11 入站只听回环，对外那一端是 nginx
            grep 'listen' <"${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" 2>/dev/null | awk '{print $2}'
        else
            jq -r '.inbounds[]? | select((.listen // "") | startswith("127.") | not) | (.port // .listen_port // empty)' "${file}" 2>/dev/null
        fi
    done < <(find "${dir}" -maxdepth 1 -name '*_inbounds.json' -type f 2>/dev/null)
}

# portsTakenFor ID DIR KEEP SKIP [EXTRA...] → 给 ID 选端口时已被占的端口，每行一个。DIR 是 ID 所在内核的配置目录，
# KEEP / SKIP 同 configuredPorts（ID 自己总被跳过），EXTRA 是本次已选定、还没写进文件的端口
portsTakenFor() {
    local id=$1 dir=$2 keep=$3 skip="$4,$1," network ours port net
    shift 4
    network=$(getProtocolListenNetwork "${id}") || network=tcp
    for net in tcp udp; do
        [[ "${network}" == "both" || "${network}" == "${net}" ]] || continue
        configuredPorts "${dir}" "${net}" "${keep}" "${skip}"
        # 订阅端口是 nginx 在听，安装流程里 nginx 停着，/proc 看不到它
        [[ "${net}" == "tcp" ]] && subscribeConfPort
        # 自己的内核可能还在跑旧配置，它占的端口由上一行按配置判；活着的监听只算本脚本配置里没有的
        ours=$(configuredPorts "${XRAY_CONF_DIR}" "${net}"; configuredPorts "${SINGBOX_FRAGMENT_DIR}" "${net}")
        while IFS= read -r port; do
            portListed "${port}" "${ours}" || printf '%s\n' "${port}"
        done < <(listeningPorts "${net}")
    done
    if (($#)); then printf '%s\n' "$@"; fi
}

# pickInboundPort ID OLD_PORT DIR KEEP SKIP [EXTRA...] → 选定的端口打到 stdout，提示走 stderr；其余参数同 portsTakenFor
# 跑在 $(…) / <(…) 里，所以不 exit：OLD_PORT 已被别的协议或程序占着就不再沿用，手输撞上已占端口就重问
pickInboundPort() {
    local id=$1 oldPort=$2 taken port= reuse= defaultPort= network
    shift 2
    taken=$(portsTakenFor "${id}" "$@")
    if [[ -n "${oldPort}" ]]; then
        if portListed "${oldPort}" "${taken}"; then
            echoContent yellow " ---> $(t PORT_REUSE_TAKEN "${oldPort}")" >&2
        elif [[ -n "${lastInstallationConfig}" ]]; then
            port=${oldPort}
        else
            read -r -p "$(t PORT_REUSE_PROMPT "${oldPort}")" reuse
            if isYesInput "${reuse}"; then
                port=${oldPort}
            fi
        fi
    fi
    if [[ -z "${port}" ]] && protocolUsesPortPool "${id}"; then
        network=$(getProtocolListenNetwork "${id}")
        # shellcheck disable=SC2086 # 池是空格分隔的端口表，按词展开
        if ! defaultPort=$(firstFreePort "${taken}" ${TLS_PORT_POOL}); then
            echoContent yellow " ---> $(t PORT_POOL_FULL "${TLS_PORT_POOL}")" >&2
        elif [[ "${defaultPort}" != "${TLS_PORT_POOL%% *}" ]]; then
            echoContent yellow " ---> $(t PORT_POOL_SHIFTED "${TLS_PORT_POOL%% *}/${network/both/tcp+udp}" "${defaultPort}")" >&2
        fi
    fi
    while [[ -z "${port}" ]]; do
        if [[ -n "${defaultPort}" ]]; then
            readValidPort "$(t PORT_PROMPT_DEFAULT "${defaultPort}")" port "${defaultPort}" >&2 || continue
        else
            readValidPort "$(t PORT_PROMPT_RANDOM)" port RANDOM 10000 30000 >&2 || continue
        fi
        if portListed "${port}" "${taken}"; then
            echoContent yellow " ---> $(t PORT_TAKEN "${port}")" >&2
            port=
        fi
    done
    printf '%s\n' "${port}"
}

# 安装TLS
installTLS() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
    readAcmeTLS
    local tlsDomain=${domain}

    # 安装tls
    if [[ -f "${TLS_DIR}/${tlsDomain}.crt" && -f "${TLS_DIR}/${tlsDomain}.key" && -n $(cat "${TLS_DIR}/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        echoContent green " ---> 检测到证书"
        renewalTLS

        if [[ -z $(find ${TLS_DIR}/ -name "${tlsDomain}.crt") ]] || [[ -z $(find ${TLS_DIR}/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "${TLS_DIR}/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus}" == "true" ]]; then
                # 验证通配符证书确实存在于 acme.sh 中（目录名以字面 *. 开头）
                local wildcardCertDir wildcardCertFile
                wildcardCertDir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name '\*.'"${dnsTLSDomain}_ecc" 2>/dev/null | head -1)
                if [[ -n "${wildcardCertDir}" ]]; then
                    wildcardCertFile=$(find "${wildcardCertDir}" -maxdepth 1 -type f -name '\*.'"${dnsTLSDomain}.cer" 2>/dev/null | head -1)
                fi
                if [[ -n "${wildcardCertFile}" ]]; then
                    local wildcardDomain
                    wildcardDomain=$(basename "${wildcardCertDir}" | sed 's/_ecc$//')
                    "$HOME/.acme.sh/acme.sh" --installcert -d "${wildcardDomain}" --fullchainpath "${TLS_DIR}/${tlsDomain}.crt" --keypath "${TLS_DIR}/${tlsDomain}.key" --ecc >/dev/null
                else
                    echoContent red " ---> 未找到有效的通配符证书，将尝试申请新证书"
                    installedDNSAPIStatus=""
                    rm -rf ${TLS_DIR}/*
                    installTLS "$1"
                    return
                fi
            else
                "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "${TLS_DIR}/${tlsDomain}.crt" --keypath "${TLS_DIR}/${tlsDomain}.key" --ecc >/dev/null
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
                    read -r -p "是否重新安装？[y/n]:" reInstallStatus
                    if isYesInput "${reInstallStatus}"; then
                        rm -rf ${TLS_DIR}/*
                        installTLS "$1"
                    fi
                fi
            fi
        fi

        # 已有的证书（自定义的、上次留下的）也要对得上私钥：不查的话写完配置内核才起不来，那时服务已停、旧配置也没了
        if ! verifyCertKeyMatch "${TLS_DIR}/${tlsDomain}.crt" "${TLS_DIR}/${tlsDomain}.key"; then
            echoContent red " ---> 证书验证失败，请检查证书文件"
            exit 1
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI
        if [[ -z "${dnsAPIType}" ]]; then
            echoContent yellow "\n ---> 不采用API申请证书"
            echoContent green " ---> 安装TLS证书，需要依赖80端口"
            allowPort 80
        fi

        switchSSLType
        customSSLEmail
        selectAcmeInstallSSL

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            # 从实际目录名获取正确的证书域名
            local wildcardCertDir
            wildcardCertDir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name '\*.'"${dnsTLSDomain}_ecc" 2>/dev/null | head -1)
            if [[ -n "${wildcardCertDir}" ]]; then
                local wildcardDomain
                wildcardDomain=$(basename "${wildcardCertDir}" | sed 's/_ecc$//')
                "$HOME/.acme.sh/acme.sh" --installcert -d "${wildcardDomain}" --fullchainpath "${TLS_DIR}/${tlsDomain}.crt" --keypath "${TLS_DIR}/${tlsDomain}.key" --ecc >/dev/null
            else
                echoContent red " ---> 通配符证书目录不存在"
            fi
        else
            "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "${TLS_DIR}/${tlsDomain}.crt" --keypath "${TLS_DIR}/${tlsDomain}.key" --ecc >/dev/null
        fi

        if [[ ! -f "${TLS_DIR}/${tlsDomain}.crt" || ! -f "${TLS_DIR}/${tlsDomain}.key" ]] || [[ -z $(cat "${TLS_DIR}/${tlsDomain}.key") || -z $(cat "${TLS_DIR}/${tlsDomain}.crt") ]]; then
            tail -n 10 ${TLS_DIR}/acme.log
            if [[ ${installTLSCount} == "1" ]]; then
                echoContent red " ---> TLS安装失败，请检查acme日志"
                echoContent yellow "     日志文件: ${TLS_DIR}/acme.log"
                exit 1
            fi

            installTLSCount=1
            echo

            if tail -n 10 ${TLS_DIR}/acme.log | grep -q "Could not validate email address as valid"; then
                echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
                echo
                customSSLEmail "validate email"
                installTLS "$1"
            else
                installTLS "$1"
            fi
        fi

        # 验证证书与私钥匹配
        echoContent green " ---> 验证证书与私钥..."
        if ! verifyCertKeyMatch "${TLS_DIR}/${tlsDomain}.crt" "${TLS_DIR}/${tlsDomain}.key"; then
            echoContent red " ---> 证书验证失败，请检查证书文件"
            exit 1
        fi

        # 验证证书有效期
        verifyCertExpiry "${TLS_DIR}/${tlsDomain}.crt"

        echoContent green " ---> TLS生成成功"
    else
        echoContent yellow " ---> 未安装acme.sh"
        exit 1
    fi
}

# 初始化随机字符串 - 使用更安全的随机源
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    local charLen=${#chars}
    # 8 位 ≈ 2^36（23^8）；4 位只有 28 万组合，对 nginx 枚举几分钟即穷尽
    for i in {1..8}; do
        local idx
        idx=$(randomNum 0 $((charLen - 1)))
        initCustomPath+="${chars:idx:1}"
    done
    customPath=${initCustomPath}
}

# 自定义/随机路径
randomPathFunction() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"
    else
        echoContent skyBlue "生成随机路径"
    fi

    if [[ -n "${currentPath}" && -z "${lastInstallationConfig}" ]]; then
        echo
        read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
        echo
    elif [[ -n "${currentPath}" && -n "${lastInstallationConfig}" ]]; then
        historyPathStatus="y"
    fi

    if isYesInput "${historyPathStatus}"; then
        customPath=${currentPath}
        echoContent green " ---> 使用成功\n"
    else
        echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
        read -r -p '路径:' customPath
        if [[ -z "${customPath}" ]]; then
            initRandomPath
            currentPath=${customPath}
        else
            # URL path 片段白名单：字母数字与 . _ -，长度 4-32（点号放行是为了 api.v1 这种写法；
            # 下限 4 挡住 /a 这类可枚举短路径）。引号/斜杠/空白/jq-shell 元字符一律禁——
            # 它会同时嵌入 JSON、Nginx location 与 fallback path。
            if ! [[ "${customPath}" =~ ^[A-Za-z0-9._-]{4,32}$ ]]; then
                echoContent red " ---> 路径格式非法，仅允许字母数字及 . _ -，长度 4-32"
                # 重问不退出：sing-box 的安装走到这里时服务已停，退出会把整机留在断线状态
                randomPathFunction "$1"
                return
            fi
            if [[ "${customPath: -2}" == "ws" ]]; then
                echo
                echoContent red " ---> 自定义path结尾不可用ws结尾，否则无法区分分流路径"
                randomPathFunction "$1"
            else
                currentPath=${customPath}
            fi
        fi
    fi
    echoContent yellow "\n path:${currentPath}"
    echoContent skyBlue "\n----------------------------"
}
# randomNum / randomPort 由 lib/utils.sh 提供（实现完全一致）。

# nginxStaticHasForeignContent → 0=伪装站目录里有不是本脚本、也不是 nginx 软件包放的东西（用户自己的站）。
# nginx 包自带的欢迎页、错误页与图标不算，否则新装的机器每次都要问
nginxStaticHasForeignContent() {
    local f
    [[ -d "${nginxStaticPath}" ]] || return 1
    for f in "${nginxStaticPath%/}"/* "${nginxStaticPath%/}"/.[!.]*; do
        [[ -e "${f}" ]] || continue
        case "${f##*/}" in
            50x.html | 404.html | nginx-logo.png | poweredby.png | system_noindex_logo.png | icons) continue ;;
            index.html) grep -qi 'nginx' "${f}" 2>/dev/null && continue ;;
        esac
        return 0
    done
    return 1
}

# Nginx伪装博客
nginxBlog() {
    if [[ -n "${1:-}" ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加伪装站点"
    else
        echoContent yellow "\n开始添加伪装站点"
    fi

    # 伪装站模板列表 (来自 Lynthar/website-examples)
    local templates=("cloud-drive" "game-zone" "net-disk" "play-hub" "stream-box" "video-portal" "music-flow" "podcast-hub" "ai-forge")
    local templateCount=${#templates[@]}
    local repoUrl="https://github.com/Lynthar/website-examples/archive/refs/heads/main.zip"
    local tempDir="/tmp/website-examples-$$"

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "检测到安装伪装站点，是否需要重新安装[y/n]:" nginxBlogInstallStatus
        else
            nginxBlogInstallStatus="n"
        fi

        if isYesInput "${nginxBlogInstallStatus}"; then
            # 随机选择模板
            randomNum=$(randomNum 0 $((templateCount - 1)))
            local selectedTemplate="${templates[$randomNum]}"

            # 下载并解压仓库（必须先全部成功才动 nginxStaticPath，
            # 否则下载失败会清空伪装站留空目录）
            mkdir -p "${tempDir}"
            local _wgetExit=0
            if [[ "${release}" == "alpine" ]]; then
                wget -q -O "${tempDir}/repo.zip" "${repoUrl}" || _wgetExit=$?
            else
                wget -q ${wgetShowProgressStatus} -O "${tempDir}/repo.zip" "${repoUrl}" || _wgetExit=$?
            fi
            if [[ ${_wgetExit} -ne 0 ]] || [[ ! -s "${tempDir}/repo.zip" ]]; then
                echoContent red " ---> 下载伪装站模板失败，保留现有内容不变"
                rm -rf "${tempDir}"
                return 1
            fi
            if ! unzip -q -o "${tempDir}/repo.zip" -d "${tempDir}"; then
                echoContent red " ---> 解压伪装站模板失败，保留现有内容不变"
                rm -rf "${tempDir}"
                return 1
            fi
            local _srcDir="${tempDir}/website-examples-main/${selectedTemplate}"
            if [[ ! -d "${_srcDir}" ]]; then
                echoContent red " ---> 模板目录缺失 ${_srcDir}，保留现有内容不变"
                rm -rf "${tempDir}"
                return 1
            fi

            # 至此下载+解压都已通过，可以安全替换静态目录
            rm -rf "${nginxStaticPath}"*
            mkdir -p "${nginxStaticPath}"
            cp -rf "${_srcDir}/"* "${nginxStaticPath}"

            # 创建 check 标记文件
            echo "${selectedTemplate}" > "${nginxStaticPath}/check"

            # 清理临时文件
            rm -rf "${tempDir}"
            echoContent green " ---> 添加伪装站点成功 [${selectedTemplate}]"
        fi
    else
        if nginxStaticHasForeignContent; then
            read -r -p "$(t NGINX_BLOG_FOREIGN_CONFIRM "${nginxStaticPath}")" nginxBlogInstallStatus
            if ! isYesInput "${nginxBlogInstallStatus}"; then
                echoContent yellow " ---> $(t NGINX_BLOG_FOREIGN_KEPT "${nginxStaticPath}")"
                return 0
            fi
        fi
        # 随机选择模板
        randomNum=$(randomNum 0 $((templateCount - 1)))
        local selectedTemplate="${templates[$randomNum]}"

        mkdir -p "${tempDir}"

        # 下载并解压仓库（与上方同款：必须先全部成功才动 nginxStaticPath）
        local _wgetExit=0
        if [[ "${release}" == "alpine" ]]; then
            wget -q -O "${tempDir}/repo.zip" "${repoUrl}" || _wgetExit=$?
        else
            wget -q ${wgetShowProgressStatus} -O "${tempDir}/repo.zip" "${repoUrl}" || _wgetExit=$?
        fi
        if [[ ${_wgetExit} -ne 0 ]] || [[ ! -s "${tempDir}/repo.zip" ]]; then
            echoContent red " ---> 下载伪装站模板失败，保留现有内容不变"
            rm -rf "${tempDir}"
            return 1
        fi
        if ! unzip -q -o "${tempDir}/repo.zip" -d "${tempDir}"; then
            echoContent red " ---> 解压伪装站模板失败，保留现有内容不变"
            rm -rf "${tempDir}"
            return 1
        fi
        local _srcDir="${tempDir}/website-examples-main/${selectedTemplate}"
        if [[ ! -d "${_srcDir}" ]]; then
            echoContent red " ---> 模板目录缺失 ${_srcDir}，保留现有内容不变"
            rm -rf "${tempDir}"
            return 1
        fi

        # 至此下载+解压都已通过，可以安全替换静态目录
        rm -rf "${nginxStaticPath}"*
        mkdir -p "${nginxStaticPath}"
        cp -rf "${_srcDir}/"* "${nginxStaticPath}"

        # 创建 check 标记文件
        echo "${selectedTemplate}" > "${nginxStaticPath}/check"

        # 清理临时文件
        rm -rf "${tempDir}"
        echoContent green " ---> 添加伪装站点成功 [${selectedTemplate}]"
    fi

}

# 修改http_port_t端口
# BusyBox 的 pgrep -x 比对的是 argv[0] 而非进程名，认不出 nginx 与 sing-box，服务启停判定全靠它。
# 自更新不跑 installTools，所以服务控制函数也调一次，旧版装的 Alpine 机器更新后同样补上
ensureAlpineProcps() {
    # 一次运行只试一次：离线时 apk 装不上，不该让每次启停服务都再连一遍软件源
    if [[ "${release}" != "alpine" || -n "${alpineProcpsTried:-}" ]]; then
        return 0
    fi
    alpineProcpsTried=true
    if ! pgrep -V 2>&1 | grep -q procps; then
        echoContent green " ---> 安装procps"
        ${installType} procps >/dev/null 2>&1
        hash -r
    fi
}

# nginxPids → 本机 nginx 的进程号。按进程名精确匹配：-f 按整条命令行认，root 下会连 "vim nginx.conf" 一起 kill -9；
# 只认与脚本同一个 PID 命名空间的：宿主上看得到 Docker 容器里的 nginx，混进来的话启动时以为已在跑而跳过、停止时把它们一起杀掉
nginxPids() {
    pgrep --ns $$ --nslist pid -x nginx
}

# 操作Nginx
handleNginx() {
    ensureAlpineProcps

    # 只装 Reality 的安装流程不起 nginx（没有伪装站要它）；订阅这类确实要它的地方传 force
    if { [[ "$2" == "force" ]] || ! echo "${selectCustomInstallType}" | grep -qwE ",7,|,8,|,7,8,"; } && [[ -z $(nginxPids) ]] && [[ "$1" == "start" ]]; then
        labelNginxPorts
        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx start
        else
            systemctl start nginx
        fi

        sleep 0.5

        if [[ -z $(nginxPids) ]]; then
            echoContent red " ---> Nginx启动失败"
            echoContent red " ---> 请将下方日志反馈给开发者"
            nginx
            # 这条 nginx 能救回 OpenRC 记成 started、进程却没了的情形
            if [[ -n $(nginxPids) ]]; then
                echoContent yellow " ---> $(t NGINX_STARTED_DIRECTLY)"
                return 0
            fi
            # 还是没起来就退出，调用方才不会接着打「成功」
            [[ -n $(nginxPids) ]] || exit 1
        else
            echoContent green " ---> Nginx启动成功"
        fi

    elif [[ -n $(nginxPids) ]] && [[ "$1" == "stop" ]]; then

        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx stop
        else
            systemctl stop nginx
        fi
        sleep 0.5

        if [[ -z ${btDomain} && -n $(nginxPids) ]]; then
            nginxPids | xargs kill -9
        fi
        echoContent green " ---> Nginx关闭成功"
    fi
}

# 定时任务更新tls证书。cron 行带 PROXY_AGENT_DIR 前缀：脚本不记住安装根，非默认根的机器 cron 里才找得到自己
installCronTLS() {
    if [[ -z "${btDomain}" ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加定时维护证书"
        # 只换掉自己的 RenewTLS 行与 v2ray-agent / acme.sh 的遗留行，别的行（含 UpdateGeo）原样保留
        {
            crontab -l 2>/dev/null | grep -v -F -e "${PROXY_AGENT_DIR}/install.sh RenewTLS" -e "v2ray-agent" -e "acme.sh"
            echo "30 1 * * * PROXY_AGENT_DIR=${PROXY_AGENT_DIR} /bin/bash ${PROXY_AGENT_DIR}/install.sh RenewTLS >> ${PROXY_AGENT_DIR}/crontab_tls.log 2>&1"
        } >${PROXY_AGENT_DIR}/backup_crontab.cron
        crontab ${PROXY_AGENT_DIR}/backup_crontab.cron
        echoContent green "\n ---> 添加定时维护证书成功"
    fi
}
# 定时任务更新geo文件
installCronUpdateGeo() {
    if [[ "${coreKind}" == "1" ]]; then
        if crontab -l | grep -q "UpdateGeo"; then
            echoContent red "\n ---> 已添加自动更新定时任务，请不要重复添加"
            exit 1
        fi
        echoContent skyBlue "\n进度 1/1 : 添加定时更新geo文件"
        crontab -l >${PROXY_AGENT_DIR}/backup_crontab.cron
        echo "35 1 * * * PROXY_AGENT_DIR=${PROXY_AGENT_DIR} /bin/bash ${PROXY_AGENT_DIR}/install.sh UpdateGeo >> ${PROXY_AGENT_DIR}/crontab_tls.log 2>&1" >>${PROXY_AGENT_DIR}/backup_crontab.cron
        crontab ${PROXY_AGENT_DIR}/backup_crontab.cron
        echoContent green "\n ---> 添加定时更新geo文件成功"
    fi
}
# 删掉 crontab 里指向本安装根 install.sh 的全部定时任务；卸载后它们只会指向一个不存在的脚本
removeOwnCronEntries() {
    local current remaining
    current=$(crontab -l 2>/dev/null) || return 0
    remaining=$(grep -v -F "${PROXY_AGENT_DIR}/install.sh" <<<"${current}" || true)
    if ! crontab - <<<"${remaining}"; then
        echoContent yellow " ---> $(t CRON_REMOVE_FAILED)"
        return 1
    fi
}

# 更新证书
renewalTLS() {

    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/1 : 更新证书"
    fi
    local domain=${currentHost}
    if [[ -z "${currentHost}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi

    # acme.sh 续期与安装都按证书名寻址：通配符证书名是字面的 *.<父域>，拿主机名去装会被拒。
    # 不调 readAcmeTLS：它按全局 domain 改写 installTLS 随后要用的通配符状态，换域名重装时两边不是同一个域名
    local acmeCertName=
    local wildcardCertName="*.${domain#*.}"
    if [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
        acmeCertName=${domain}
    elif [[ -f "$HOME/.acme.sh/${wildcardCertName}_ecc/${wildcardCertName}.key" && -f "$HOME/.acme.sh/${wildcardCertName}_ecc/${wildcardCertName}.cer" ]]; then
        acmeCertName=${wildcardCertName}
    fi

    if [[ -n "${acmeCertName}" ]]; then
        # 按证书真实到期时间判窗口：CA 在缩短有效期（LE 2027 起 64 天、2028 起 45 天），按固定天数推算会过期了才续。
        # 用 -checkend 不用 date -d：BusyBox 的 date 解析不了 openssl 的日期格式
        local renewWindowDays=15
        local renewWindow=$((renewWindowDays * 86400))
        local renewCertFile="${TLS_DIR}/${domain}.crt"
        local renewKeyFile="${TLS_DIR}/${domain}.key"
        local acmeCertFile="$HOME/.acme.sh/${acmeCertName}_ecc/${acmeCertName}.cer"
        # tls/ 下还没装（重装途中）就判 acme.sh 那份：装进来归 installTLS，这里不在安装中途启停服务
        local checkCertFile=${renewCertFile}
        [[ -s "${checkCertFile}" ]] || checkCertFile=${acmeCertFile}

        echoContent skyBlue " ---> 证书检查日期:$(date "+%F %H:%M:%S")"
        echoContent skyBlue " ---> $(t TLS_RENEW_EXPIRY "$(openssl x509 -in "${checkCertFile}" -noout -enddate 2>/dev/null | cut -d= -f2)")"
        echoContent skyBlue " ---> $(t TLS_RENEW_POLICY "${renewWindowDays}")"

        if ! openssl x509 -in "${checkCertFile}" -noout -checkend "${renewWindow}" >/dev/null 2>&1; then
            echoContent yellow " ---> 重新生成证书"
            handleNginx stop

            if [[ "${coreKind}" == "1" ]]; then
                handleXray stop
            elif [[ "${coreKind}" == "2" ]]; then
                handleSingBox stop
            fi

            # 这是唯一的续期入口（acme.sh 自身的 cron 已被 installCronTLS 删除），
            # 写半截/错配直接 reload 会断线到下次人工介入——先备份，验证不过就还原旧证书再拉起服务
            cp -fp "${renewCertFile}" "${renewCertFile}.renew-bak" 2>/dev/null
            cp -fp "${renewKeyFile}" "${renewKeyFile}.renew-bak" 2>/dev/null

            # acme.sh 那张已在窗口外（它续过、只是没装进来）就只重装。必须 --force：
            # acme.sh ≤3.1.2 按签发后第 60 天排期且不看到期，遇上 45 天证书 --cron 永远轮不到
            local renewFailed=
            if ! openssl x509 -in "${acmeCertFile}" -noout -checkend "${renewWindow}" >/dev/null 2>&1 &&
                ! "$HOME/.acme.sh/acme.sh" --renew -d "${acmeCertName}" --ecc --force --home "$HOME/.acme.sh"; then
                echoContent red " ---> $(t TLS_RENEW_ACME_FAILED)"
                renewFailed=true
            elif ! "$HOME/.acme.sh/acme.sh" --installcert -d "${acmeCertName}" --fullchainpath "${renewCertFile}" --keypath "${renewKeyFile}" --ecc; then
                echoContent red " ---> $(t TLS_RENEW_INSTALL_FAILED)"
                renewFailed=true
            elif ! verifyCertKeyMatch "${renewCertFile}" "${renewKeyFile}"; then
                echoContent red " ---> $(t TLS_RENEW_VERIFY_FAILED)"
                renewFailed=true
            elif ! openssl x509 -in "${renewCertFile}" -noout -checkend "${renewWindow}" >/dev/null 2>&1; then
                echoContent red " ---> $(t TLS_RENEW_NOT_EXTENDED "${renewWindowDays}")"
                renewFailed=true
            fi

            if [[ -n "${renewFailed}" ]]; then
                if [[ -f "${renewCertFile}.renew-bak" && -f "${renewKeyFile}.renew-bak" ]]; then
                    cp -fp "${renewCertFile}.renew-bak" "${renewCertFile}"
                    cp -fp "${renewKeyFile}.renew-bak" "${renewKeyFile}"
                fi
                rm -f "${renewCertFile}.renew-bak" "${renewKeyFile}.renew-bak"
                reloadCore
                handleNginx start
                return 1
            fi
            rm -f "${renewCertFile}.renew-bak" "${renewKeyFile}.renew-bak"
            reloadCore
            handleNginx start
        else
            echoContent green " ---> 证书有效"
        fi
    elif [[ -f "${TLS_DIR}/${tlsDomain}.crt" && -f "${TLS_DIR}/${tlsDomain}.key" && -n $(cat "${TLS_DIR}/${tlsDomain}.crt") ]]; then
        echoContent yellow " ---> 检测到使用自定义证书，无法执行renew操作。"
    else
        echoContent red " ---> 未安装"
    fi
}

# labelNginxPorts → SELinux 没禁用时把 nginx 各 listen 端口登记成 http_port_t。不登记的话回到 Enforcing（含重启）后
# 订阅口、31300 这类端口绑不上，整个 nginx 起不来。只增不删；没有 semanage 就不管（labelCoreBinary 会去装它）
labelNginxPorts() {
    local httpPorts port upstreams
    command -v getenforce >/dev/null 2>&1 && command -v semanage >/dev/null 2>&1 || return 0
    [[ "$(getenforce 2>/dev/null)" == "Disabled" || -z "$(getenforce 2>/dev/null)" ]] && return 0
    httpPorts=$(semanage port -l 2>/dev/null | awk '$1 == "http_port_t" && $2 == "tcp" {$1 = $2 = ""; print}' | tr -d ' ' | tr ',' '\n')
    # 自家配置里 nginx 要连的回环端口（15 的 grpc_pass、11 的 proxy_pass）。只看这两个文件：别人的站点不该让脚本改策略
    upstreams=$(grep -hoE '^[[:space:]]*(grpc_pass[[:space:]]+grpc|proxy_pass[[:space:]]+http)://127\.0\.0\.1:[0-9]+' "${nginxConfigPath}alone.conf" "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" 2>/dev/null | grep -oE '[0-9]+$')
    for port in $({ grep -hoE '^[[:space:]]*listen[[:space:]]+(\[[^]]*\]:|[0-9.]+:)?[0-9]+' "${nginxConfigPath}"*.conf 2>/dev/null | grep -oE '[0-9]+$'; echo "${upstreams}"; } | sort -un); do
        grep -qx "${port}" <<<"${httpPorts}" && continue
        if ! semanage port -a -t http_port_t -p tcp "${port}" 2>/dev/null && ! semanage port -m -t http_port_t -p tcp "${port}" 2>/dev/null; then
            echoContent yellow " ---> $(t SELINUX_NGINX_PORT_FAILED "${port}")"
        fi
    done
    # 连回环也受策略管：端口是 http_port_t 还不够，不开这个布尔值 nginx 照样连不上，15 和 11 全 502
    if [[ -n "${upstreams}" && "$(getsebool httpd_can_network_relay 2>/dev/null)" != *" on" ]]; then
        setsebool -P httpd_can_network_relay on 2>/dev/null || echoContent yellow " ---> $(t SELINUX_NGINX_RELAY_FAILED)"
    fi
}

# labelCoreBinary BIN → SELinux 没禁用时把核心二进制登记成 bin_t 并 restorecon：留在 etc_t 下 systemd 拉起后跑在 init_t，
# 连本机回环（Reality 的 dokodemo 那一跳）、拨目标站都被拒，bin_t 才跑成第三方服务的常规域 unconfined_service_t。
# 登记按路径，换版本、全盘 relabel 都照样适用；没有 semanage 又装不上时退回 chcon。只告警不失败
labelCoreBinary() {
    local bin=$1
    command -v getenforce >/dev/null 2>&1 || return 0
    [[ "$(getenforce 2>/dev/null)" == "Disabled" || -z "$(getenforce 2>/dev/null)" || ! -f "${bin}" ]] && return 0
    [[ "$(stat -c %C "${bin}" 2>/dev/null)" == *:bin_t:* ]] && return 0
    if ! command -v semanage >/dev/null 2>&1; then
        ${installType} policycoreutils-python-utils >/dev/null 2>&1
    fi
    if command -v semanage >/dev/null 2>&1; then
        if { semanage fcontext -a -t bin_t "${bin}" 2>/dev/null || semanage fcontext -m -t bin_t "${bin}"; } && restorecon "${bin}"; then
            return 0
        fi
    elif chcon -t bin_t "${bin}"; then
        echoContent yellow " ---> $(t SELINUX_LABEL_CHCON_ONLY "${bin}")"
        return 0
    fi
    echoContent yellow " ---> $(t SELINUX_LABEL_FAILED "${bin}")"
}

# 安装 sing-box
installSingBox() {
    readInstallType
    if [[ -n "${1:-}" ]]; then
        echoContent skyBlue "\n进度  $1/${totalProgress} : 安装sing-box"
    else
        echoContent skyBlue "\n安装sing-box"
    fi

    if [[ ! -f "${SINGBOX_BIN}" ]]; then

        # 缓存原始响应，区分"GitHub 完全访问不到"vs"访问到但筛选后为空"两种失败模式
        # per_page=30：与 Xray 对齐，足以覆盖近期所有稳定版
        local releasesJson
        releasesJson=$(curl -s --connect-timeout 10 "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=30")

        version=$(echo "${releasesJson}" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        # 优雅降级：30 个里都没有稳定版的极端情况下，让用户决定是否使用最新预览版
        if [[ -z "${version}" && "${prereleaseStatus}" == "false" && -n "${releasesJson}" ]]; then
            local latestAnyVersion
            latestAnyVersion=$(echo "${releasesJson}" | jq -r '.[].tag_name' | head -1)
            if [[ -n "${latestAnyVersion}" ]]; then
                echoContent yellow "\n ---> 最近 30 个 release 中没有找到稳定版"
                echoContent yellow " ---> 最新版本: ${latestAnyVersion} (预览版)"
                read -r -p "是否使用此预览版继续安装？[y/n]" usePrereleaseStatus
                if isYesInput "${usePrereleaseStatus}"; then
                    version="${latestAnyVersion}"
                else
                    echoContent yellow " ---> 已取消安装（如需稳定版请稍后重试，或从菜单选择预览版安装）"
                    return 1
                fi
            fi
        fi

        # 检查版本获取是否成功（网络/API 失败导致空）
        if [[ -z "${version}" ]]; then
            echoContent red " ---> 获取 sing-box 版本失败，请检查网络连接或 GitHub API 访问"
            echoContent yellow "     可能原因: 网络超时、GitHub API 限流、DNS 解析失败"
            read -r -p "是否重新尝试？[y/n]" retryStatus
            if isYesInput "${retryStatus}"; then
                installSingBox "$1"
                return $?
            fi
            return 1
        fi

        echoContent green " ---> 最新版本:${version}"

        # 前置版本守门：下载前就拒绝低于最低版本，避免低版本二进制落盘后再退出留残留
        # （兜底的 post-extract 版本检查保留，作为 belt-and-suspenders）
        local _targetVer="${version#v}"
        if [[ -n "${_targetVer}" ]] && ! versionGreaterOrEqual "${_targetVer}" "${SINGBOX_MIN_VERSION}"; then
            echoContent red " ---> 目标 sing-box 版本 ${version} 低于本脚本要求的最低版本 ${SINGBOX_MIN_VERSION}"
            echoContent yellow " ---> 路由级 sniff/resolve action 需 1.11、domain_resolver 与新格式 DNS 需 1.12；旧版本会启动失败"
            echoContent yellow " ---> 参见 https://sing-box.sagernet.org/migration/"
            exit 1
        fi

        local singBoxPackage="sing-box-${version/v/}${singBoxCoreCPUVendor}"
        local singBoxTarFileName="${singBoxPackage}.tar.gz"
        local singBoxTarFile="${SINGBOX_DIR}/${singBoxTarFileName}"

        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P ${SINGBOX_DIR}/ "https://github.com/SagerNet/sing-box/releases/download/${version}/${singBoxTarFileName}"
        else
            wget -c -q ${wgetShowProgressStatus} -P ${SINGBOX_DIR}/ "https://github.com/SagerNet/sing-box/releases/download/${version}/${singBoxTarFileName}"
        fi

        if [[ ! -f "${singBoxTarFile}" ]]; then
            read -r -p "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if isYesInput "${downloadStatus}"; then
                installSingBox "$1"
                return $?
            fi
            return 1
        else
            # 上游不发校验和文件；摘要取自同一份 releases 响应里 GitHub 给每个资产记的 digest
            local expectedHash
            expectedHash=$(releaseAssetSHA256 "${releasesJson}" "${version}" "${singBoxTarFileName}")
            if [[ -z "${expectedHash}" ]]; then
                rm -f "${singBoxTarFile}"
                echoContent red " ---> $(t SINGBOX_DIGEST_MISSING "${singBoxTarFileName}")"
                return 1
            fi
            echoContent green " ---> 验证文件完整性..."
            if ! verifySHA256 "${singBoxTarFile}" "${expectedHash}"; then
                echoContent red " ---> 文件校验失败，可能已被篡改，请重新下载"
                rm -f "${singBoxTarFile}"
                read -r -p "是否重新尝试？[y/n]" retryStatus
                if isYesInput "${retryStatus}"; then
                    installSingBox "$1"
                    return $?
                fi
                return 1
            fi
            echoContent green " ---> 文件校验通过"

            if ! tar -xzf "${singBoxTarFile}" -C "${SINGBOX_DIR}/" ||
                ! mv "${SINGBOX_DIR}/${singBoxPackage}/sing-box" ${SINGBOX_BIN}; then
                rm -rf ${SINGBOX_DIR}/sing-box-*
                echoContent red " ---> $(t SINGBOX_UNPACK_FAILED "${singBoxTarFileName}")"
                return 1
            fi
            rm -rf ${SINGBOX_DIR}/sing-box-*
            chmod 655 ${SINGBOX_BIN}

            # 包与本机的架构或 libc 不配时文件在、exec 却报 not found，配置与服务都会建在它上面
            if ! ${SINGBOX_BIN} version >/dev/null 2>&1; then
                rm -f ${SINGBOX_BIN}
                echoContent red " ---> $(t SINGBOX_NOT_RUNNABLE "${singBoxTarFileName}")"
                return 1
            fi

            # 版本守门（兜底）：配置用 1.11+ 的路由级 sniff/resolve action，1.11 以下不识别会启动失败。
            # 下载前已按 tag 检查过一次，这里用实际二进制版本再验一次。
            local installedSingBoxVer
            installedSingBoxVer=$(singBoxInstalledVersion)
            if [[ -z "${installedSingBoxVer}" ]]; then
                # 解析格式变化会让守门被静默跳过——显式告警让这种情况可见
                echoContent yellow " ---> 无法解析 sing-box 版本号（格式可能已变），跳过兜底版本校验"
            elif ! versionGreaterOrEqual "${installedSingBoxVer}" "${SINGBOX_MIN_VERSION}"; then
                echoContent red " ---> 已安装的 sing-box 版本 (${installedSingBoxVer}) 低于本脚本要求的最低版本 ${SINGBOX_MIN_VERSION}"
                echoContent yellow " ---> 路由级 sniff/resolve action 在 sing-box 1.11 引入；旧版本会启动失败"
                echoContent yellow " ---> 请安装 ≥ ${SINGBOX_MIN_VERSION} 版本后重试"
                exit 1
            fi
        fi
    else
        echoContent green " ---> 当前版本:v$(singBoxInstalledVersion)"

        version=$(curl -s --connect-timeout 10 "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=30" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        if [[ -n "${version}" ]]; then
            echoContent green " ---> 最新版本:${version}"
        else
            echoContent yellow " ---> 无法获取最新版本信息"
        fi

        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "是否更新、升级？[y/n]:" reInstallSingBoxStatus
            if isYesInput "${reInstallSingBoxStatus}"; then
                # 先挪走而不是删掉：下载/校验失败时恢复原二进制，避免服务下次重启后拉不起来
                local singBoxUpgradeBakBin="${SINGBOX_DIR}/sing-box.update-bak"
                mv -f ${SINGBOX_BIN} "${singBoxUpgradeBakBin}"
                if installSingBox "$1"; then
                    rm -f "${singBoxUpgradeBakBin}"
                    return 0
                fi
                mv -f "${singBoxUpgradeBakBin}" ${SINGBOX_BIN}
                echoContent red " ---> $(t UPDATE_CORE_FAIL_RESTORED)"
                return 1
            fi
        fi
    fi

    # 最终防线：函数返回前确认二进制确实就位
    # 上面任何路径若漏掉显式 return，都会被这里兜住，避免 caller 在二进制缺失时继续执行
    if [[ ! -f "${SINGBOX_BIN}" ]]; then
        return 1
    fi
    return 0
}

# checkWgetShowProgress 由 lib/system-detect.sh 提供（Alpine 上跳过探测的语义已 port）。

# 回显要装的 Xray-core 标签：pinned 不联网，latest / prerelease 查 GitHub 取最新稳定版 / 预览版
resolveXrayVersion() {
    local mode=${1:-pinned}
    if [[ "${mode}" == "pinned" ]]; then
        echo "${XRAY_PINNED_VERSION}"
        return 0
    fi
    local wantPrerelease=false
    if [[ "${mode}" == "prerelease" ]]; then
        wantPrerelease=true
    fi
    # per_page=30：XTLS 偶尔会连续发好几个 prerelease，5 个窗口太窄
    curl -s --connect-timeout 10 -m 30 "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=30" |
        jq -r --argjson pre "${wantPrerelease}" '.[] | select(.prerelease == $pre) | .tag_name' | head -1
}

# 安装xray
installXray() {
    readInstallType
    local versionMode=pinned
    if [[ "$2" == "true" ]]; then
        versionMode=prerelease
    fi

    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"

    if [[ ! -f "${XRAY_BIN}" ]]; then
        version=$(resolveXrayVersion "${versionMode}")

        # 检查版本获取是否成功（网络/API 失败导致空）
        if [[ -z "${version}" ]]; then
            echoContent red " ---> 获取 Xray-core 版本失败，请检查网络连接或 GitHub API 访问"
            echoContent yellow "     可能原因: 网络超时、GitHub API 限流、DNS 解析失败"
            read -r -p "是否重新尝试？[y/n]" retryStatus
            if isYesInput "${retryStatus}"; then
                installXray "$1" "$2"
                return $?
            fi
            return 1
        fi

        echoContent green " ---> Xray-core版本:${version}"

        local xrayZipFile="${XRAY_DIR}/${xrayCoreCPUVendor}.zip"
        local xrayDgstFile="${XRAY_DIR}/${xrayCoreCPUVendor}.zip.dgst"

        # 下载Xray核心文件
        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
            wget -c -q -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip.dgst"
        else
            wget -c -q ${wgetShowProgressStatus} -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
            wget -c -q ${wgetShowProgressStatus} -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip.dgst"
        fi

        if [[ ! -f "${xrayZipFile}" ]]; then
            read -r -p "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if isYesInput "${downloadStatus}"; then
                installXray "$1" "$2"
                return $?
            fi
            return 1
        else
            # 校验SHA256
            local expectedHash
            expectedHash=$(extractXrayHash "${xrayDgstFile}")
            if [[ -n "${expectedHash}" ]]; then
                echoContent green " ---> 验证文件完整性..."
                if ! verifySHA256 "${xrayZipFile}" "${expectedHash}"; then
                    echoContent red " ---> 文件校验失败，可能已被篡改，请重新下载"
                    rm -f "${xrayZipFile}" "${xrayDgstFile}"
                    read -r -p "是否重新尝试？[y/n]" retryStatus
                    if isYesInput "${retryStatus}"; then
                        installXray "$1" "$2"
                        return $?
                    fi
                    return 1
                fi
                echoContent green " ---> 文件校验通过"
            else
                echoContent yellow " ---> 警告: 未能获取校验信息，跳过完整性验证"
            fi

            unzip -o "${xrayZipFile}" -d ${XRAY_DIR} >/dev/null
            rm -f "${xrayZipFile}" "${xrayDgstFile}"

            # 默认配置不读 geo 文件，只有 geosite 分流才用：下载失败不值得中止安装（服务这时已停），但要说出来，不然配分流时 Xray 才起不来
            if ! fetchGeoFiles "${XRAY_DIR}/"; then
                echoContent yellow " ---> $(t GEO_INSTALL_SKIPPED)"
            fi

            chmod 655 ${XRAY_BIN}
        fi
    else
        if [[ -z "${lastInstallationConfig}" ]]; then
            echoContent green " ---> Xray-core版本:$(${XRAY_BIN} --version | awk '{print $2}' | head -1)"
            read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
            if isYesInput "${reInstallXrayStatus}"; then
                # 先挪走而不是删掉：下载/校验失败时恢复原二进制，避免服务下次重启后拉不起来
                local xrayUpgradeBakBin="${XRAY_DIR}/xray.update-bak"
                mv -f ${XRAY_BIN} "${xrayUpgradeBakBin}"
                if installXray "$1" "$2"; then
                    rm -f "${xrayUpgradeBakBin}"
                    return 0
                fi
                mv -f "${xrayUpgradeBakBin}" ${XRAY_BIN}
                echoContent red " ---> $(t UPDATE_CORE_FAIL_RESTORED)"
                return 1
            fi
        fi
    fi

    # 最终防线：函数返回前确认二进制确实就位
    # 上面任何路径若漏掉显式 return，都会被这里兜住，避免 caller 在二进制缺失时继续执行
    if [[ ! -f "${XRAY_BIN}" ]]; then
        return 1
    fi
    return 0
}

# xray版本管理
xrayVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    if [[ "${coreKind}" != "1" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 1
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.更新geosite、geoip"
    echoContent yellow "8.设置自动更新geo文件[每天凌晨更新]"
    echoContent yellow "9.查看日志"
    echoContent yellow "$(t XRAY_MENU_LATEST)"
    echoContent red "=============================================================="
    echoContent yellow "$(t XRAY_PINNED_NOTE "${XRAY_PINNED_VERSION}")"
    read -r -p "请选择:" selectXrayType
    if [[ "${selectXrayType}" == "1" ]]; then
        xrayVersionMode=pinned
        updateXray
    elif [[ "${selectXrayType}" == "2" ]]; then
        xrayVersionMode=prerelease
        echoContent yellow " ---> $(t XRAY_UNPINNED_WARN)"
        updateXray
    elif [[ "${selectXrayType}" == "3" ]]; then
        local rollbackVersions
        echoContent yellow "\n$(t XRAY_ROLLBACK_SCOPE "${XRAY_PINNED_VERSION}")"
        echoContent yellow "2.不保证回退后一定可以正常使用"
        echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        # 一页 50 条：前几条常是预发布与高于钉版的新版，只取 5 条时列表可能一个可回退的都没有
        rollbackVersions=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=50" | xrayRollbackVersions "${XRAY_PINNED_VERSION}")
        if [[ -z "${rollbackVersions}" ]]; then
            echoContent red " ---> $(t UPDATE_CORE_VERSION_FAIL)"
            exit 1
        fi
        awk '{print NR ":" $0}' <<<"${rollbackVersions}"
        echoContent skyBlue "--------------------------------------------------------------"
        read -r -p "请输入要回退的版本:" selectXrayVersionType
        version=
        if [[ "${selectXrayVersionType}" =~ ^[1-9][0-9]*$ ]]; then
            version=$(sed -n "${selectXrayVersionType}p" <<<"${rollbackVersions}")
        fi
        if [[ -n "${version}" ]]; then
            updateXray "${version}"
        else
            echoContent red "\n ---> 输入有误，请重新输入"
            xrayVersionManageMenu 1
        fi
    elif [[ "${selectXrayType}" == "4" ]]; then
        handleXray stop
    elif [[ "${selectXrayType}" == "5" ]]; then
        handleXray start
    elif [[ "${selectXrayType}" == "6" ]]; then
        reloadCore
    elif [[ "${selectXrayType}" == "7" ]]; then
        updateGeoSite
    elif [[ "${selectXrayType}" == "8" ]]; then
        installCronUpdateGeo
    elif [[ "${selectXrayType}" == "9" ]]; then
        checkLog 1
    elif [[ "${selectXrayType}" == "10" ]]; then
        xrayVersionMode=latest
        echoContent yellow " ---> $(t XRAY_UNPINNED_WARN)"
        updateXray
    fi
}

# fetchGeoFiles DIR → 把 DIR 里的 geosite.dat、geoip.dat 换成最新版，失败返回 1（已打印原因）。两个都下到才换，中途失败时 DIR 里还是旧文件。
# 走 releases/latest/download 的固定地址，不查 GitHub API：未认证额度按出口 IP 算，一小时 60 次，用完就取不到版本号
fetchGeoFiles() {
    local geoDir=$1 stagingDir file
    stagingDir=$(mktemp -d "${geoDir}geo-update.XXXXXX") || return 1
    for file in geosite.dat geoip.dat; do
        if ! wget -q --timeout=30 --tries=3 ${wgetShowProgressStatus} -O "${stagingDir}/${file}" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/${file}" \
            || [[ ! -s "${stagingDir}/${file}" ]]; then
            rm -rf "${stagingDir}"
            echoContent red " ---> $(t GEO_DOWNLOAD_FAILED "${file}")"
            return 1
        fi
    done
    if ! mv -f "${stagingDir}/geosite.dat" "${stagingDir}/geoip.dat" "${geoDir}"; then
        rm -rf "${stagingDir}"
        echoContent red " ---> $(t GEO_PUBLISH_FAILED "${geoDir}")"
        return 1
    fi
    rm -rf "${stagingDir}"
}

# 更新 geosite
updateGeoSite() {
    echoContent yellow "\n来源 https://github.com/Loyalsoldier/v2ray-rules-dat"
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> $(t GEO_NO_CORE)"
        return 1
    fi

    fetchGeoFiles "${configPath}../" || return 1
    reloadCore || return 1
    echoContent green " ---> 更新完毕"
}

# 更新Xray
# 下载/校验全部通过前不停服务、不动旧二进制；失败时从 xray.update-bak 恢复。
# 调用侧先 mv 旧二进制到 .update-bak（而非 rm），让本分支的失败路径有东西可恢复。
updateXray() {
    readInstallType
    local xrayBakBin="${XRAY_DIR}/xray.update-bak"

    if [[ -z "${coreKind}" || "${coreKind}" != "1" ]]; then
        if [[ -n "${1:-}" ]]; then
            version=$1
        else
            version=$(resolveXrayVersion "${xrayVersionMode:-pinned}")
        fi

        if [[ -z "${version}" ]]; then
            [[ -f "${xrayBakBin}" ]] && mv -f "${xrayBakBin}" ${XRAY_BIN}
            echoContent red " ---> $(t UPDATE_CORE_VERSION_FAIL)"
            return 1
        fi

        echoContent green " ---> Xray-core版本:${version}"

        local xrayZipFile="${XRAY_DIR}/${xrayCoreCPUVendor}.zip"
        local xrayDgstFile="${xrayZipFile}.dgst"
        # 清掉可能的残留半截文件——wget -c 会在其上续传拼出损坏包
        rm -f "${xrayZipFile}" "${xrayDgstFile}"
        if [[ "${release}" == "alpine" ]]; then
            wget -c -q -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
            wget -c -q -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip.dgst"
        else
            wget -c -q ${wgetShowProgressStatus} -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
            wget -c -q ${wgetShowProgressStatus} -P ${XRAY_DIR}/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip.dgst"
        fi

        if [[ ! -s "${xrayZipFile}" ]]; then
            rm -f "${xrayZipFile}" "${xrayDgstFile}"
            [[ -f "${xrayBakBin}" ]] && mv -f "${xrayBakBin}" ${XRAY_BIN}
            echoContent red " ---> $(t UPDATE_CORE_DL_FAIL_KEEP)"
            return 1
        fi

        local expectedHash
        expectedHash=$(extractXrayHash "${xrayDgstFile}")
        if [[ -n "${expectedHash}" ]]; then
            if ! verifySHA256 "${xrayZipFile}" "${expectedHash}"; then
                rm -f "${xrayZipFile}" "${xrayDgstFile}"
                [[ -f "${xrayBakBin}" ]] && mv -f "${xrayBakBin}" ${XRAY_BIN}
                echoContent red " ---> $(t UPDATE_CORE_VERIFY_FAIL_KEEP)"
                return 1
            fi
            echoContent green " ---> 文件校验通过"
        else
            echoContent yellow " ---> 警告: 未能获取校验信息，跳过完整性验证"
        fi

        if ! unzip -o "${xrayZipFile}" -d ${XRAY_DIR} >/dev/null || [[ ! -f "${XRAY_BIN}" ]]; then
            rm -f "${xrayZipFile}" "${xrayDgstFile}"
            [[ -f "${xrayBakBin}" ]] && mv -f "${xrayBakBin}" ${XRAY_BIN}
            echoContent red " ---> $(t UPDATE_CORE_EXTRACT_FAIL_KEEP)"
            return 1
        fi
        rm -f "${xrayZipFile}" "${xrayDgstFile}" "${xrayBakBin}"
        chmod 655 ${XRAY_BIN}
        handleXray stop
        handleXray start
    else
        local currentVersion
        currentVersion="v$(${XRAY_BIN} --version | awk '{print $2}' | head -1)"
        echoContent green " ---> 当前版本:${currentVersion}"

        if [[ -n "${1:-}" ]]; then
            version=$1
        else
            version=$(resolveXrayVersion "${xrayVersionMode:-pinned}")
        fi
        if [[ -z "${version}" ]]; then
            echoContent red " ---> $(t UPDATE_CORE_VERSION_FAIL)"
            return 1
        fi
        echoContent green " ---> $(t XRAY_TARGET_VERSION "${version}")"

        if [[ -n "${1:-}" ]]; then
            read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if isYesInput "${rollbackXrayStatus}"; then
                mv -f ${XRAY_BIN} "${xrayBakBin}"
                updateXray "${version}"
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" == "${currentVersion}" ]]; then
            read -r -p "$(t XRAY_SAME_VERSION "${version}")" reInstallXrayStatus
            if isYesInput "${reInstallXrayStatus}"; then
                mv -f ${XRAY_BIN} "${xrayBakBin}"
                updateXray
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            read -r -p "$(t XRAY_SWITCH_CONFIRM "${currentVersion}" "${version}")" installXrayStatus
            if isYesInput "${installXrayStatus}"; then
                mv -f ${XRAY_BIN} "${xrayBakBin}"
                updateXray
            else
                echoContent green " ---> 放弃更新"
            fi
        fi
    fi
}

# 验证整个服务是否可用
checkGFWStatue() {
    readInstallType
    echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ "${coreKind}" == "1" ]] && xrayDaemonRunning; then
        echoContent green " ---> 服务启动成功"
    elif [[ "${coreKind}" == "2" ]] && [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
        echoContent green " ---> 服务启动成功"
    else
        echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
        exit 1
    fi
}

# 安装alpine开机启动
installAlpineStartup() {
    local serviceName=$1
    if [[ "${serviceName}" == "sing-box" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="sing-box service"
command="${SINGBOX_BIN}"
command_args="run -c ${SINGBOX_MERGED_CONFIG}"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF
    elif [[ "${serviceName}" == "xray" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="xray service"
command="${XRAY_BIN}"
command_args="run -confdir ${XRAY_CONF_DIR}"
command_background=true
pidfile="/var/run/xray.pid"
EOF
    fi

    chmod +x "/etc/init.d/${serviceName}"
}

# sing-box开机自启
installSingBoxService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置sing-box开机自启"
    execStart="${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"

    if [[ -n $(find /bin /usr/bin -name "systemctl") && "${release}" != "alpine" ]]; then
        rm -rf /etc/systemd/system/sing-box.service
        touch /etc/systemd/system/sing-box.service
        cat <<EOF >/etc/systemd/system/sing-box.service
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${execStart}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        bootStartup "sing-box.service"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "sing-box"
        bootStartup "sing-box"
    fi

    echoContent green " ---> 配置sing-box开机启动完毕"
}

# Xray开机自启
installXrayService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    execStart="${XRAY_BIN} run -confdir ${XRAY_CONF_DIR}"
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        touch /etc/systemd/system/xray.service
        cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=infinity
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        bootStartup "xray.service"
        echoContent green " ---> 配置Xray开机自启成功"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "xray"
        bootStartup "xray"
    fi
}

# 操作sing-box
handleSingBox() {
    ensureAlpineProcps
    local startResult=0
    local mergeResult=0
    [[ "$1" == "start" ]] && labelCoreBinary "${SINGBOX_BIN}"

    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        if [[ "$1" == "start" ]]; then
            # 先确保停止旧进程
            if [[ -n $(pgrep -x "sing-box") ]]; then
                systemctl stop sing-box.service
                # 等待进程完全退出
                local waitCount=0
                while [[ -n $(pgrep -x "sing-box") ]] && [[ ${waitCount} -lt 10 ]]; do
                    sleep 0.5
                    ((waitCount++))
                done
            fi
            singBoxMergeConfig || mergeResult=$?
            if [[ ${mergeResult} -ne 0 ]]; then
                echoContent red " ---> sing-box 配置合并失败，无法启动服务"
                exit 1
            fi
            systemctl start sing-box.service || startResult=$?
        elif [[ "$1" == "stop" ]] && [[ -n $(pgrep -x "sing-box") ]]; then
            systemctl stop sing-box.service
            # 等待进程完全退出
            local waitCount=0
            while [[ -n $(pgrep -x "sing-box") ]] && [[ ${waitCount} -lt 10 ]]; do
                sleep 0.5
                ((waitCount++))
            done
        fi
    elif [[ -f "/etc/init.d/sing-box" ]]; then
        if [[ "$1" == "start" ]]; then
            # 先确保停止旧进程
            if [[ -n $(pgrep -x "sing-box") ]]; then
                rc-service sing-box stop
                local waitCount=0
                while [[ -n $(pgrep -x "sing-box") ]] && [[ ${waitCount} -lt 10 ]]; do
                    sleep 0.5
                    ((waitCount++))
                done
            fi
            singBoxMergeConfig || mergeResult=$?
            if [[ ${mergeResult} -ne 0 ]]; then
                echoContent red " ---> sing-box 配置合并失败，无法启动服务"
                exit 1
            fi
            rc-service sing-box start || startResult=$?
        elif [[ "$1" == "stop" ]] && [[ -n $(pgrep -x "sing-box") ]]; then
            rc-service sing-box stop
            local waitCount=0
            while [[ -n $(pgrep -x "sing-box") ]] && [[ ${waitCount} -lt 10 ]]; do
                sleep 0.5
                ((waitCount++))
            done
        fi
    fi
    sleep 1.5

    if [[ "$1" == "start" ]]; then
        # 用 -x（comm 精确匹配）而非 -f（命令行子串）。-f "sing-box" 会误匹配
        # 命令行里含该字符串的任意进程（例如 install.sh 自己派生的 sing-box 子调用），
        # 导致 sing-box 实际未起来时误报"启动成功"。stop 路径上方已统一用 -x。
        if [[ -n $(pgrep -x "sing-box") ]]; then
            echoContent green " ---> sing-box启动成功"
        else
            echoContent red "sing-box启动失败 (systemctl 返回码: ${startResult})"
            # 显示 systemd 服务状态以帮助诊断
            if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
                echoContent yellow "\n ---> systemd 服务状态:"
                systemctl status sing-box.service --no-pager -l 2>&1 | head -20
                echoContent yellow "\n ---> 最近日志:"
                journalctl -u sing-box.service --no-pager -n 15 2>/dev/null || true
            fi
            echoContent yellow "\n请手动执行【 ${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG} 】，查看详细错误日志"
            exit 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -x "sing-box") ]]; then
            echoContent green " ---> sing-box关闭成功"
        else
            echoContent red " ---> sing-box关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep sing-box|awk '{print \$2}'|xargs kill -9】"
            exit 1
        fi
    fi
}

# 剥离旧版 socks5_outbound.json 里的 allowInsecure（Xray-core ≥ v26.2.6 遇 true 拒绝启动）。
# 只剥字段、保留出站与分流规则——删出站会让命中规则的流量静默直连。
removeLegacyAllowInsecure() {
    local legacySocks5Outbound="${XRAY_CONF_DIR}/socks5_outbound.json"
    if [[ -f "${legacySocks5Outbound}" ]] && grep -q '"allowInsecure"' "${legacySocks5Outbound}"; then
        if jsonModifyFile "${legacySocks5Outbound}" 'del(.outbounds[]?.streamSettings.tlsSettings.allowInsecure)' false; then
            echoContent yellow " ---> $(t XRAY_ALLOWINSECURE_STRIPPED)"
        else
            echoContent yellow " ---> $(t XRAY_ALLOWINSECURE_STRIP_FAILED)"
        fi
    fi
}

# 老 Reality 配置缺 minClientVer 的补成 REALITY_MIN_CLIENT_VER，已有值不动（理由见该常量）
ensureRealityMinClientVer() {
    local file
    for file in ${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json ${XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json; do
        [[ -f "${file}" ]] || continue
        if jq -e '[.inbounds[]? | (.streamSettings.realitySettings | type) == "object" and (.streamSettings.realitySettings | has("minClientVer") | not)] | any' "${file}" >/dev/null 2>&1; then
            if jsonModifyFile "${file}" ".inbounds |= map(if (.streamSettings.realitySettings | type) == \"object\" and (.streamSettings.realitySettings | has(\"minClientVer\") | not) then .streamSettings.realitySettings.minClientVer = \"${REALITY_MIN_CLIENT_VER}\" else . end)" false; then
                echoContent yellow " ---> $(t XRAY_REALITY_MIN_CLIENT_VER_SET "${REALITY_MIN_CLIENT_VER}")"
            fi
        fi
    done
}

# hostHasRouteTo IP → 0=内核有到它的路由。UDP connect 不发包，Xray 探测本机网络也是这个做法
hostHasRouteTo() {
    (exec 3<>"/dev/udp/$1/53") 2>/dev/null
}

# UseIP 每次从 A + AAAA 里随机选：机器缺一个地址族时选中它就拨不通，5 次全中就断连（约 1/32）。只改恰好是 UseIP 的，手改过的值不动。
# 别改成 AsIs（绕过内置 DNS，DNS 解锁的 hosts 失效），也别用 dns.queryStrategy（WARP 隧道里的解析会一起被过滤）
ensureXrayDirectStrategy() {
    local file="${XRAY_CONF_DIR}/z_direct_outbound.json" strategy hasV4=no hasV6=no
    [[ -f "${file}" ]] || return 0
    jq -e 'any(.outbounds[]?; .tag == "z_direct_outbound" and .settings.domainStrategy == "UseIP")' "${file}" >/dev/null 2>&1 || return 0
    hostHasRouteTo 192.33.4.12 && hasV4=yes
    hostHasRouteTo 2001:500:2::c && hasV6=yes
    case "${hasV4}${hasV6}" in
        yesno) strategy=UseIPv4v6 ;;
        noyes) strategy=UseIPv6v4 ;;
        *) return 0 ;;
    esac
    if jsonModifyFile "${file}" "(.outbounds[] | select(.tag == \"z_direct_outbound\")).settings.domainStrategy = \"${strategy}\"" false; then
        echoContent yellow " ---> $(t XRAY_DIRECT_STRATEGY_SET "${strategy}")"
    fi
}

# localBlockApiPort → 拼车统计 API 的端口（12_stats_api.json 的 api.listen），没开拼车时为空
localBlockApiPort() {
    local file="${XRAY_CONF_DIR}/12_stats_api.json"
    [[ -f "${file}" ]] || return 0
    jq -r '.api.listen // "" | if test(":[0-9]+$") then sub("^.*:"; "") else "" end' "${file}"
}

# localGlobalAddrs → 本机网卡上的全局地址（JSON 数组）。发往它们的连接经 lo 送达、绕过 INPUT 防火墙，绑 0.0.0.0 靠防火墙挡外网的服务
# 会被经代理摸到。云厂商 NAT 的公网 IP 不在网卡上，走网关回来，防火墙看得到，不用管。没有 ip 命令时是空数组，封锁少这一块而已
localGlobalAddrs() {
    { ip -o addr show scope global 2>/dev/null || true; } | awk '{ sub(/\/.*/, "", $4); print $4 }' | jq -Rsc 'split("\n") | map(select(length > 0)) | unique'
}

# ensureXrayLocalBlock → Xray 启动前把「代理用户不许连本机与内网」放到 09_routing.json 最前（幂等）：
# 统计 API 端口与桥端口段按端口封（写成域名、DNS rebinding 都绕不过），回环 / 私网 / 链路本地 / 未指定 / 本机网卡地址按字面 IP 封。
# 不封的话成员能经代理连到统计 API 清零自己的计数。09_routing.json 有好几个写入者，所以每次启动前补，不在写入处补
ensureXrayLocalBlock() {
    local routing="${XRAY_CONF_DIR}/09_routing.json" outbound="${XRAY_CONF_DIR}/local_block_tail_outbound.json"
    local outbounds apiPort hops current updated file addrs
    [[ -d "${XRAY_CONF_DIR}" ]] || return 0
    # 文件名必须带 tail：不带的出站会被插到最前当默认出站，z_direct_outbound 被 WARP / IPv6 全局模式删掉时就是它，全部流量进黑洞
    outbounds='{"outbounds":[{"tag":"local_block","protocol":"blackhole"},{"tag":"local_pass","protocol":"freedom"}]}'
    if [[ "$(jq -c . "${outbound}" 2>/dev/null)" != "${outbounds}" ]]; then
        jsonWriteFile "${outbound}" "${outbounds}" false || return 1
    fi
    apiPort=$(localBlockApiPort) || return 1
    # dokodemo-door 入站（Reality 的 443、附加端口）经路由把连接转给 127.0.0.1 上写死的端口，用户改不了目标：先放行，不然 Reality 全断
    if ! hops=$(jq -sc '[.[] | .inbounds[]? | select(.protocol == "dokodemo-door") | .tag | select(type == "string")] | unique' "${XRAY_CONF_DIR}"/*.json 2>/dev/null); then
        for file in "${XRAY_CONF_DIR}"/*.json; do
            jq -e . "${file}" >/dev/null || echoContent red " ---> $(t XRAY_CONF_UNPARSABLE "${file}")"
        done
        return 1
    fi
    current='{"routing":{"rules":[]}}'
    if [[ -f "${routing}" ]]; then
        current=$(cat "${routing}") || return 1
    fi
    addrs=$(localGlobalAddrs)
    # ruleTag 各不相同、都以 local-block 开头（按前缀认、整组替换）：Xray 26.9.9 起启动时就查 ruleTag 重复，撞了直接起不来
    updated=$(jq --arg ports "${CHAIN_BRIDGE_PORT}-${CHAIN_BRIDGE_PORT_LAST}${apiPort:+,${apiPort}}" --argjson hops "${hops}" --argjson addrs "${addrs}" '
        ((if ($hops | length) > 0 then [{type: "field", ruleTag: "local-block-pass", inboundTag: $hops, outboundTag: "local_pass"}] else [] end)
         + [{type: "field", ruleTag: "local-block-port", port: $ports, outboundTag: "local_block"},
         {type: "field", ruleTag: "local-block-ip", outboundTag: "local_block",
          ip: (["0.0.0.0/8", "10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4",
               "255.255.255.255/32", "::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8"] + $addrs)}]) as $block
        | .routing.rules = ($block + [(.routing.rules // [])[] | select((.ruleTag // "") | startswith("local-block") | not)])' <<<"${current}") || return 1
    [[ "${updated}" == "$(jq . <<<"${current}")" ]] && return 0
    jsonWriteFile "${routing}" "${updated}" false
}

# localBlockInject MERGED → sing-box 那半：同一套封锁插到路由最前（旁挂的 6 / 9 连得到 Xray 统计 API、链式出口收入口的流量，一样要封）。
# 走 direct 类出站的规则与默认出站前再插「没解析就解析、按 IP 拒」：只封字面 IP 时，解析到内网或云元数据地址的域名照通。
# 解析器照抄该出站拨号时用的（同一份缓存与地址族，不多查一次）；DNS 分流解析过的不重解析，否则分流结果被覆盖
localBlockInject() {
    local merged=$1 apiPort out
    apiPort=$(localBlockApiPort) || return 1
    out=$(jq --arg ports "${CHAIN_BRIDGE_PORT}:${CHAIN_BRIDGE_PORT_LAST}" --arg api "${apiPort}" --argjson addrs "$(localGlobalAddrs)" '
        [{ip_is_private: true, action: "reject"}, {ip_cidr: (["0.0.0.0/8", "::ffff:0:0/96"] + $addrs), action: "reject"}] as $ipBlock
        | ($ipBlock + [{port_range: [$ports], action: "reject"}]
           + (if $api == "" then [] else [{port: [($api | tonumber)], action: "reject"}] end)) as $block
        | ([.outbounds[]? | select(.type == "direct") | {key: .tag, value: .domain_resolver}] | from_entries) as $direct
        | .route.default_domain_resolver as $fallback
        | {ip_cidr: ["0.0.0.0/0", "::/0"], invert: true} as $unresolved
        | def resolveFor($tag): {action: "resolve"} + (($direct[$tag] // $fallback)
            | if type == "string" then {server: .}
              elif type == "object" then with_entries(select(.key | . == "server" or . == "strategy" or . == "disable_cache" or . == "rewrite_ttl" or . == "client_subnet"))
              else {} end);
          def guard($tag): del(.action, .outbound, .override_address, .override_port, .network_strategy, .network_type, .fallback_network_type,
                .fallback_delay, .udp_disable_domain_unmapping, .udp_connect, .udp_timeout, .tls_fragment, .tls_fragment_fallback_delay, .tls_record_fragment)
            | (if . == {} then $unresolved else {type: "logical", mode: "and", rules: [$unresolved, .]} end) + resolveFor($tag);
          (.route.final // .outbounds[0].tag // "") as $final
        | .route.rules = $block
            + [(.route.rules // [])[] | (.outbound // "") as $o
               | if (.action // "route") == "route" and ($direct | has($o)) then guard($o), $ipBlock[], . else . end]
            + (if $direct | has($final) then [$unresolved + resolveFor($final)] + $ipBlock else [] end)' "${merged}") || return 1
    jsonWriteFile "${merged}" "${out}" false
}

# chainExitSourceInject MERGED → 出口设了只允许入口 IP 时，别的来源连进 chain_inbound 一律 reject，TCP / UDP 都管，不靠防火墙。
# 中继也有 chain_inbound：中继状态在就不注入。出口状态读不懂让合并失败——跳过等于对所有人放开
chainExitSourceInject() {
    local merged=$1 allowed out
    [[ -f "${CHAIN_EXIT_INFO}" && ! -f "${CHAIN_RELAY_INFO}" ]] || return 0
    allowed=$(jq -r '.allowed_ip // "" | strings' "${CHAIN_EXIT_INFO}") || return 1
    [[ -n "${allowed}" ]] || return 0
    jq -e 'any(.inbounds[]?; .tag == "chain_inbound")' "${merged}" >/dev/null || return 0
    out=$(jq --arg ip "${allowed}" '.route.rules = [{type: "logical", mode: "and",
        rules: [{inbound: ["chain_inbound"]}, {source_ip_cidr: [$ip], invert: true}], action: "reject"}] + (.route.rules // [])' "${merged}") || return 1
    jsonWriteFile "${merged}" "${out}" false
}

# globalEgressChainNotice → IPv6 / WARP 全局的确认前提一句：链式出口 / 中继上经链路转来的流量走链式路由里显式的 direct，不走全局出口
globalEgressChainNotice() {
    [[ -f "${CHAIN_EXIT_INFO}" || -f "${CHAIN_RELAY_INFO}" ]] || return 0
    echoContent yellow "$(t GLOBAL_EGRESS_CHAIN_NOTICE)\n"
}

# directOutboundInject MERGED → final 或规则指向 direct、却没有这个出站时补一个：IPv6 / WARP 全局会删掉 01_direct_outbound，
# 链式出口、中继、入口的直连都指向它，缺了 sing-box 起不来（check 查不出）。没人指向时不补，免得没有出站时补成默认出口
directOutboundInject() {
    local merged=$1 out
    out=$(jq 'if (any(.outbounds[]?; .tag == "direct") | not) and (.route.final == "direct" or any(.route.rules[]?; .outbound == "direct"))
        then .outbounds = ((.outbounds // []) + [{type: "direct", tag: "direct"}]) else . end' "${merged}") || return 1
    jsonWriteFile "${merged}" "${out}" false
}

# defaultDomainResolverInject MERGED → 有两个以上 DNS server 又没定 default_domain_resolver 时指向 local（没有就补一个）：
# sing-box 1.13 起出站拨域名找不到解析器就拒绝启动。已有的值不碰，链式写的 google 靠这一条保住
defaultDomainResolverInject() {
    local merged=$1 out
    out=$(jq 'if ((.dns.servers // []) | length) > 1 and .route.default_domain_resolver == null
        then (if any(.dns.servers[]; .tag == "local") then . else .dns.servers += [{type: "local", tag: "local"}] end)
            | .route.default_domain_resolver = "local"
        else . end' "${merged}") || return 1
    jsonWriteFile "${merged}" "${out}" false
}

# xrayDaemonRunning → 0=Xray 服务进程在跑。只认服务那条 `run -confdir` 命令行：拼车统计的 `xray api statsquery`、
# 配置检查的 `xray run -test` 也含 xray/xray，算进来会把它们当成服务——启动被跳过、停止报失败
xrayDaemonRunning() {
    [[ -n $(pgrep -f "xray/xray run -confdir") ]]
}

# 操作xray
handleXray() {
    local startResult=0

    if [[ "$1" == "start" ]]; then
        labelCoreBinary "${XRAY_BIN}"
        removeLegacyAllowInsecure
        ensureRealityMinClientVer
        ensureXrayDirectStrategy
        ensureCorePortTargets || echoContent yellow " ---> $(t CORE_PORT_TARGET_FAILED)"
        ensureCarpoolXray
        # 链式入口的路由每次启动前写回：重装的模板、WARP / IPv6 全局都会整份换掉 09_routing.json，指定了出口的人就静默走本机直连
        if [[ -f "${XRAY_CONF_DIR}/chain_outbound.json" ]] && ! writeXrayChainConfig "${CHAIN_BRIDGE_PORT}"; then
            echoContent red " ---> $(t XRAY_CHAIN_ROUTING_FAILED "${XRAY_CONF_DIR}/09_routing.json")"
            exit 1
        fi
        if ! ensureXrayLocalBlock; then
            echoContent red " ---> $(t XRAY_LOCAL_BLOCK_FAILED "${XRAY_CONF_DIR}/09_routing.json")"
            exit 1
        fi
    elif [[ "$1" == "stop" ]]; then
        carpoolCollectBeforeStop
    fi

    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if ! xrayDaemonRunning && [[ "$1" == "start" ]]; then
            systemctl start xray.service || startResult=$?
        elif xrayDaemonRunning && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -f "/etc/init.d/xray" ]]; then
        if ! xrayDaemonRunning && [[ "$1" == "start" ]]; then
            rc-service xray start || startResult=$?
        elif xrayDaemonRunning && [[ "$1" == "stop" ]]; then
            rc-service xray stop
        fi
    fi

    sleep 1.5

    if [[ "$1" == "start" ]]; then
        if xrayDaemonRunning; then
            echoContent green " ---> Xray启动成功"
        else
            echoContent red "Xray启动失败 (systemctl 返回码: ${startResult})"
            # 显示 systemd 服务状态以帮助诊断
            if [[ -f "/etc/systemd/system/xray.service" ]]; then
                echoContent yellow "\n ---> systemd 服务状态:"
                systemctl status xray.service --no-pager -l 2>&1 | head -20
                echoContent yellow "\n ---> 最近日志:"
                journalctl -u xray.service --no-pager -n 15 2>/dev/null || true
            fi
            echoContent yellow "\n请手动执行【${XRAY_BIN} -confdir ${XRAY_CONF_DIR}】查看详细错误日志"
            exit 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if ! xrayDaemonRunning; then
            echoContent green " ---> Xray关闭成功"
        else
            echoContent red "Xray关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
            exit 1
        fi
    fi
}

# 读取 currentClients 数组并重新映射到目标协议格式，可选追加一个新用户。
# 全量走 jq --arg/--argjson 参数化（§11.3）。
initXrayClients() {
    local type=",$1,"
    local newUUID="$2"
    local newEmail="$3"

    if [[ -n "${newUUID}" ]]; then
        currentClients=$(echo "${currentClients}" | jq \
            --arg id "${newUUID}" \
            --arg email "${newEmail}-VLESS_TCP/TLS_Vision" \
            '. += [{id: $id, flow: "xtls-rprx-vision", email: $email}]')
    fi

    local users="[]"
    local user uuid email
    while read -r user; do
        uuid=$(echo "${user}" | jq -r '.id // .uuid')
        email=$(echo "${user}" | jq -r '.email // .name')
        # 只剥最后一段 "-协议后缀"（后缀不含连字符）。按第一个连字符切会把含连字符的
        # 用户名与默认 email（完整 UUID）截断成第一段，每次 remap 都改写存量用户身份
        email="${email%-*}"

        # VLESS+TCP+Vision (id 0)
        if [[ "${type}" == *",0,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg id "${uuid}" \
                --arg email "${email}-VLESS_TCP/TLS_Vision" \
                '. += [{id: $id, flow: "xtls-rprx-vision", email: $email}]')
        fi
        # VLESS WS (id 1)
        if [[ "${type}" == *",1,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg id "${uuid}" \
                --arg email "${email}-VLESS_WS" \
                '. += [{id: $id, email: $email}]')
        fi
        # VLESS XHTTP (id 12)
        if [[ "${type}" == *",12,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg id "${uuid}" \
                --arg email "${email}-VLESS_Reality_XHTTP" \
                '. += [{id: $id, email: $email}]')
        fi
        # VLESS XHTTP TLS (id 15)
        if [[ "${type}" == *",15,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg id "${uuid}" \
                --arg email "${email}-VLESS_XHTTP_TLS" \
                '. += [{id: $id, email: $email}]')
        fi
        # VMess WS (id 3)
        if [[ "${type}" == *",3,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg id "${uuid}" \
                --arg email "${email}-VMess_WS" \
                '. += [{id: $id, email: $email, alterId: 0}]')
        fi
        # Trojan TCP (id 4)
        if [[ "${type}" == *",4,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg email "${email}-trojan_tcp" \
                '. += [{password: $password, email: $email}]')
        fi
        # Hysteria2 (id 6) -- 历史上 Xray 路径也写过这个分支，保留原 schema
        if [[ "${type}" == *",6,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg name "${email}-singbox_hysteria2" \
                '. += [{password: $password, name: $name}]')
        fi
        # VLESS Reality Vision (id 7)
        if [[ "${type}" == *",7,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg id "${uuid}" \
                --arg email "${email}-vless_reality_vision" \
                '. += [{id: $id, email: $email, flow: "xtls-rprx-vision"}]')
        fi
        # TUIC (id 9) -- Xray 路径与 sing-box 共用 currentClients，保留原 schema
        if [[ "${type}" == *",9,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${email}-singbox_tuic" \
                '. += [{uuid: $uuid, password: $uuid, name: $name}]')
        fi
    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}
# 把 currentClients 重映射到目标协议的用户字段格式，可选追加一个新用户。
# jq 一律 --arg/--argjson，不做字符串拼接。协议 8（VLESS Reality gRPC）不实现。
initSingBoxClients() {
    local type=",$1,"
    local newUUID="$2"
    local newName="$3"

    if [[ -n "${newUUID}" ]]; then
        currentClients=$(echo "${currentClients}" | jq \
            --arg uuid "${newUUID}" \
            --arg name "${newName}-VLESS_TCP/TLS_Vision" \
            '. += [{uuid: $uuid, flow: "xtls-rprx-vision", name: $name}]')
    fi

    local users="[]"
    local user uuid name
    while read -r user; do
        uuid=$(echo "${user}" | jq -r '.uuid // .id // .password')
        name=$(echo "${user}" | jq -r '.name // .email // .username')
        # 同 initXrayClients：只剥最后一段协议后缀，不能按第一个连字符截断
        name="${name%-*}"

        # VLESS+TCP+Vision (id 0)
        if [[ "${type}" == *",0,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${name}-VLESS_TCP/TLS_Vision" \
                '. += [{uuid: $uuid, flow: "xtls-rprx-vision", name: $name}]')
        fi
        # VLESS WS (id 1)
        if [[ "${type}" == *",1,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${name}-VLESS_WS" \
                '. += [{uuid: $uuid, name: $name}]')
        fi
        # VMess WS (id 3)
        if [[ "${type}" == *",3,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${name}-VMess_WS" \
                '. += [{uuid: $uuid, name: $name, alterId: 0}]')
        fi
        # Trojan TCP (id 4)
        if [[ "${type}" == *",4,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg name "${name}-Trojan_TCP" \
                '. += [{password: $password, name: $name}]')
        fi
        # Hysteria2 (id 6)
        if [[ "${type}" == *",6,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg name "${name}-singbox_hysteria2" \
                '. += [{password: $password, name: $name}]')
        fi
        # VLESS Reality Vision (id 7)
        if [[ "${type}" == *",7,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${name}-VLESS_Reality_Vision" \
                '. += [{uuid: $uuid, flow: "xtls-rprx-vision", name: $name}]')
        fi
        # TUIC (id 9)
        if [[ "${type}" == *",9,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${name}-singbox_tuic" \
                '. += [{uuid: $uuid, password: $uuid, name: $name}]')
        fi
        # NaiveProxy (id 10) -- 使用 username 字段（sing-box docs 与其他协议不同）
        if [[ "${type}" == *",10,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg username "${name}-singbox_naive" \
                '. += [{password: $password, username: $username}]')
        fi
        # VMess HTTPUpgrade (id 11)
        if [[ "${type}" == *",11,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg uuid "${uuid}" \
                --arg name "${name}-VMess_HTTPUpgrade" \
                '. += [{uuid: $uuid, name: $name, alterId: 0}]')
        fi
        # AnyTLS (id 13)
        if [[ "${type}" == *",13,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg name "${name}-anytls" \
                '. += [{password: $password, name: $name}]')
        fi
        # SS2022 (id 14) 的 uPSK 长度必须等于方法密钥长度（SIP022）：128-gcm=16B，其余 32B，
        # 否则 sing-box check 报 bad user PSK length。方法优先取全局，否则从现有 inbound 读。
        if [[ "${type}" == *",14,"* ]]; then
            local ss2022Method14="${ss2022Method:-}"
            if [[ -z "${ss2022Method14}" && -f "${singBoxConfigPath}14_ss2022_inbounds.json" ]]; then
                ss2022Method14=$(jq -r '.inbounds[0].method' "${singBoxConfigPath}14_ss2022_inbounds.json")
            fi
            local ss2022UserKeyLen=16
            if [[ "${ss2022Method14}" == "2022-blake3-aes-256-gcm" || "${ss2022Method14}" == "2022-blake3-chacha20-poly1305" ]]; then
                ss2022UserKeyLen=32
            fi
            local ss2022UserKey
            # currentClients 来自 ss2022 inbound 时 password 已是派生 uPSK（16B→22 字符+"=="、32B→43 字符+"="；
            # UUID 恒 36 位含连字符不会误中），二次派生会静默改写全部存量用户密码
            if [[ "${uuid}" =~ ^[A-Za-z0-9+/]{22}==$ || "${uuid}" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
                ss2022UserKey="${uuid}"
            else
                ss2022UserKey=$(echo -n "${uuid}" | head -c "${ss2022UserKeyLen}" | base64)
            fi
            users=$(echo "${users}" | jq \
                --arg password "${ss2022UserKey}" \
                --arg name "${name}-SS2022" \
                '. += [{password: $password, name: $name}]')
        fi
        # ShadowTLS (id 16) 外层：密码就是 UUID，内层 uPSK 由 shadowTlsWithInnerUsers 派生
        if [[ "${type}" == *",16,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg password "${uuid}" \
                --arg name "${name}-ShadowTLS" \
                '. += [{password: $password, name: $name}]')
        fi
        # SOCKS5 内部 inbound (id 20) -- {username, password}，无 name 字段
        if [[ "${type}" == *",20,"* ]]; then
            users=$(echo "${users}" | jq \
                --arg username "${uuid}" \
                --arg password "${uuid}" \
                '. += [{username: $username, password: $password}]')
        fi
    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}

# initHysteria2Network → 问拥塞控制与混淆。BBR 时 hysteria2ClientDownloadSpeed / UploadSpeed 为空，
# 不混淆时 hysteria2ObfsType / hysteria2ObfsPassword 为空；gecko 要 sing-box ≥ 1.14，低于它不给选
initHysteria2Network() {
    local choice= gecko=
    hysteria2ClientDownloadSpeed=
    hysteria2ClientUploadSpeed=
    hysteria2ObfsType=
    hysteria2ObfsPassword=

    echoContent yellow "$(t HY2_CC_MENU)"
    read -r -p "$(t HY2_SELECT_DEFAULT_1)" choice
    if [[ "${choice}" == "2" ]]; then
        readHysteria2Speed "$(t HY2_SPEED_DOWN 100)" hysteria2ClientDownloadSpeed 100
        readHysteria2Speed "$(t HY2_SPEED_UP 50)" hysteria2ClientUploadSpeed 50
        echoContent green " ---> $(t HY2_BRUTAL_SET "${hysteria2ClientDownloadSpeed}" "${hysteria2ClientUploadSpeed}")"
    else
        echoContent green " ---> BBR"
    fi

    if versionGreaterOrEqual "$(singBoxInstalledVersion)" 1.14.0; then
        gecko=true
    fi
    echoContent yellow "$(t HY2_OBFS_MENU)"
    if [[ -n "${gecko}" ]]; then
        echoContent yellow "$(t HY2_OBFS_GECKO)"
    fi
    read -r -p "$(t HY2_SELECT_DEFAULT_1)" choice
    case "${choice}" in
    2) hysteria2ObfsType=salamander ;;
    3) [[ -n "${gecko}" ]] && hysteria2ObfsType=gecko ;;
    esac
    if [[ -z "${hysteria2ObfsType}" ]]; then
        echoContent green " ---> $(t HY2_OBFS_OFF)"
        return 0
    fi
    # 只收 URL 不保留字符：密码要原样进 hysteria2:// 链接与 clashMeta 的 YAML，别的字符会把两者写坏
    while true; do
        read -r -p "$(t HY2_OBFS_PASSWORD)" hysteria2ObfsPassword
        if [[ -z "${hysteria2ObfsPassword}" ]]; then
            hysteria2ObfsPassword=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
        fi
        if [[ "${hysteria2ObfsPassword}" =~ ^[A-Za-z0-9._~-]{1,128}$ ]]; then
            break
        fi
        echoContent red " ---> $(t HY2_OBFS_PASSWORD_INVALID)"
    done
    echoContent green " ---> obfs: ${hysteria2ObfsType}"
}

# readHysteria2Speed PROMPT OUT_VAR DEFAULT → 读 1-999999 的整数（Mbps）写进 OUT_VAR，回车取 DEFAULT，输错重问
readHysteria2Speed() {
    local -n __rhs_out="$2"
    local input
    while true; do
        read -r -p "$1" input
        input=${input:-$3}
        if [[ "${input}" =~ ^[1-9][0-9]{0,5}$ ]]; then
            __rhs_out=${input}
            return 0
        fi
        echoContent red " ---> $(t HY2_SPEED_INVALID)"
    done
}

# hysteria2InboundJson PORT USERS_JSON SNI UP DOWN OBFS_TYPE OBFS_PASSWORD SITE_DIR → 06 片段的完整 JSON
# UP / DOWN 是服务端的 up_mbps / down_mbps，留空即 BBR，并用 ignore_client_bandwidth 让客户端也走 BBR；
# OBFS_TYPE 空 = 不混淆；SITE_DIR 空 = 不配 masquerade，未认证的 HTTP/3 请求得到内核自带的 404
hysteria2InboundJson() {
    jq -n --argjson port "$1" --argjson users "$2" --arg sni "$3" --arg up "$4" --arg down "$5" \
        --arg obfsType "$6" --arg obfsPassword "$7" --arg site "$8" \
        --arg cert "${TLS_DIR}/$3.crt" --arg keyFile "${TLS_DIR}/$3.key" '
        {type: "hysteria2", tag: "hysteria2-in", listen: "::", listen_port: $port, users: $users}
        + (if $up == "" then {ignore_client_bandwidth: true}
           else {up_mbps: ($up | tonumber), down_mbps: ($down | tonumber), ignore_client_bandwidth: false} end)
        + (if $obfsType == "" then {} else {obfs: {type: $obfsType, password: $obfsPassword}} end)
        + (if $site == "" then {} else {masquerade: {type: "file", directory: $site}} end)
        + {tls: {enabled: true, server_name: $sni, alpn: ["h3"], certificate_path: $cert, key_path: $keyFile}}
        | {inbounds: [.]}'
}

# 初始化 Shadowsocks 2022 配置
initSS2022Config() {
    # 读取现有配置
    if [[ -f "${singBoxConfigPath}14_ss2022_inbounds.json" ]]; then
        ss2022Port=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}14_ss2022_inbounds.json")
        ss2022ServerKey=$(jq -r '.inbounds[0].password' "${singBoxConfigPath}14_ss2022_inbounds.json")
        ss2022Method=$(jq -r '.inbounds[0].method' "${singBoxConfigPath}14_ss2022_inbounds.json")
    fi

    if [[ -n "${ss2022Port}" ]]; then
        read -r -p "读取到上次安装时的端口 ${ss2022Port}，是否使用？[y/n]:" historySS2022PortStatus
        if ! isYesInput "${historySS2022PortStatus}"; then
            ss2022Port=
            ss2022ServerKey=
        fi
    fi

    if [[ -z "${ss2022Port}" ]]; then
        echoContent yellow "请输入Shadowsocks 2022端口[回车随机10000-30000]"
        # 回车随机；非法重问不退出：安装走到这里时服务已停，退出会把整机留在断线状态
        until readValidPort "端口:" ss2022Port "RANDOM" 10000 30000; do :; done
        echoContent green "\n ---> 端口: ${ss2022Port}"
    fi
    # TCP、UDP 都监听，两个都要放行：漏了防火墙直接拒连
    allowPort "${ss2022Port}"
    allowPort "${ss2022Port}" udp

    # 选择加密方式
    if [[ -z "${ss2022Method}" ]]; then
        echoContent yellow "\n请选择加密方式:"
        echoContent yellow "1.2022-blake3-aes-128-gcm [推荐，密钥较短]"
        echoContent yellow "2.2022-blake3-aes-256-gcm"
        echoContent yellow "3.2022-blake3-chacha20-poly1305"
        read -r -p "请选择[默认1]:" ss2022MethodChoice
        case ${ss2022MethodChoice} in
        2)
            ss2022Method="2022-blake3-aes-256-gcm"
            ss2022KeyLen=32
            ;;
        3)
            ss2022Method="2022-blake3-chacha20-poly1305"
            ss2022KeyLen=32
            ;;
        *)
            ss2022Method="2022-blake3-aes-128-gcm"
            ss2022KeyLen=16
            ;;
        esac
        echoContent green "\n ---> 加密方式: ${ss2022Method}"
    else
        if [[ "${ss2022Method}" == "2022-blake3-aes-128-gcm" ]]; then
            ss2022KeyLen=16
        else
            ss2022KeyLen=32
        fi
    fi

    # 生成服务器密钥
    if [[ -z "${ss2022ServerKey}" ]]; then
        ss2022ServerKey=$(openssl rand -base64 ${ss2022KeyLen})
        echoContent green " ---> 服务器密钥已自动生成"
    fi
}

# shadowTlsUserKey PASSWORD → 16 内层 SS2022 的 uPSK（16 字节）。哈希而不是截断：UUID 前 16 个字符只有约 52 比特
shadowTlsUserKey() {
    printf '%s' "$1" | openssl dgst -sha256 -binary | head -c 16 | base64
}

# shadowTlsWithInnerUsers CONFIG_JSON → 内层 users 按外层重写：名字相同，uPSK 由外层密码派生。
# auth_user 只认内层用户名，内层单密钥时按账号选出口静默失效；两层都按人发，删人也是两层都没了
shadowTlsWithInnerUsers() {
    local inner='[]' name password
    while IFS=$'\t' read -r name password; do
        inner=$(jq -c --arg n "${name}" --arg p "$(shadowTlsUserKey "${password}")" '. + [{name: $n, password: $p}]' <<<"${inner}") || return 1
    done < <(jq -r '.inbounds[0].users[] | [.name, .password] | @tsv' <<<"$1")
    jq --argjson inner "${inner}" '.inbounds[1].users = $inner' <<<"$1"
}

# shadowTlsInbound PORT TARGET SERVER_KEY USERS_JSON → 16 的配置（内层 users 待填）。内层只听回环、不开 UDP：
# ShadowTLS 只有 TCP，UDP 靠客户端的 multiplex 走同一条连接，所以 multiplex 不能关
shadowTlsInbound() {
    jq -n --argjson port "$1" --arg target "$2" --arg key "$3" --argjson users "$4" '{inbounds: [
        {type: "shadowtls", listen: "::", tag: "shadowtls-in", listen_port: $port, detour: "shadowtls-ss-in", version: 3, users: $users,
         handshake: {server: $target, server_port: 443, domain_resolver: "local"}, strict_mode: true},
        {type: "shadowsocks", tag: "shadowtls-ss-in", listen: "127.0.0.1", network: "tcp", method: "2022-blake3-aes-128-gcm",
         password: $key, users: [], multiplex: {enabled: true}}]}'
}

# destSupportsTls13 HOST → 0=目标在 443 上能谈 TLS 1.3。strict 模式只认这种目标，别的目标客户端全部握手失败、也不报错
destSupportsTls13() {
    echo | timeout 8 openssl s_client -connect "$1:443" -servername "$1" -tls1_3 2>/dev/null | grep -q 'TLSv1.3'
}

# initShadowTlsConfig → 定 16 的握手目标与内层服务端密钥，写进 shadowTlsTarget、shadowTlsServerKey。重装时沿用，已发出去的节点才不失效
initShadowTlsConfig() {
    local file="${SINGBOX_FRAGMENT_DIR}/$(getProtocolConfigFileName 16)" reuse tries=0
    shadowTlsTarget=
    shadowTlsServerKey=
    if [[ -f "${file}" ]]; then
        shadowTlsTarget=$(jq -r '.inbounds[0].handshake.server // empty' "${file}")
        shadowTlsServerKey=$(jq -r '.inbounds[1].password // empty' "${file}")
        if [[ -n "${shadowTlsTarget}" && -z "${lastInstallationConfig}" ]]; then
            read -r -p "$(t SHADOWTLS_TARGET_REUSE "${shadowTlsTarget}")" reuse
            isYesInput "${reuse}" || shadowTlsTarget=
        fi
    fi
    # 试几次还不行就用最后一个并告警：验证连不出去时不能卡死在这里，安装走到这儿服务已经停了
    while [[ -z "${shadowTlsTarget}" ]]; do
        tries=$((tries + 1))
        read -r -p "$(t SHADOWTLS_TARGET_PROMPT)" shadowTlsTarget
        if [[ -z "${shadowTlsTarget}" ]]; then
            shadowTlsTarget=$(pickRandomDest)
        elif ! isValidDomain "${shadowTlsTarget}"; then
            echoContent red " ---> $(t SHADOWTLS_TARGET_INVALID)"
            shadowTlsTarget=
            continue
        elif ! checkRealityDest "${shadowTlsTarget}"; then
            shadowTlsTarget=
            continue
        fi
        if ! destSupportsTls13 "${shadowTlsTarget}"; then
            echoContent yellow " ---> $(t SHADOWTLS_TARGET_NO_TLS13 "${shadowTlsTarget}")"
            ((tries < 5)) && shadowTlsTarget=
        fi
    done
    [[ -n "${shadowTlsServerKey}" ]] || shadowTlsServerKey=$(openssl rand -base64 16)
    # 从 Xray 切过来时 singBoxConfigPath 还是空的，它会什么都不写，握手目标就解析不了、sing-box 起不来
    singBoxConfigPath="${SINGBOX_FRAGMENT_DIR}/" ensureSingBoxLocalDns
    echoContent green "\n ---> $(t SHADOWTLS_TARGET_CHOSEN "${shadowTlsTarget}")"
}

# addFirewalldPortHopping START END TARGET → 一条区间转发：逐端口加的话 1000 个端口要一分半，删也一样。
# 本机转发落成 nft 的 redirect，用不着 masquerade；开 masquerade 会顺带打开 ip_forward，把主机变成路由器
addFirewalldPortHopping() {
    firewall-cmd --permanent --add-forward-port=port="$1-$2":proto=udp:toport="$3" && firewall-cmd --reload
}

# 端口跳跃
addPortHopping() {
    local type=$1
    local targetPort=$2
    if [[ -n "${portHoppingStart}" || -n "${portHoppingEnd}" ]]; then
        echoContent red " ---> 已添加不可重复添加，可删除后重新添加"
        exit 1
    fi
    if [[ "${release}" == "centos" ]]; then
        if ! systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
            echoContent red " ---> 未启动firewalld防火墙，无法设置端口跳跃。"
            exit 1
        fi
    fi

    echoContent skyBlue "\n进度 1/1 : 端口跳跃"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项\n"
    echoContent yellow "仅支持Hysteria2"
    echoContent yellow "端口跳跃的起始位置为30000"
    echoContent yellow "端口跳跃的结束位置为40000"
    echoContent yellow "可以在30000-40000范围中选一段"
    echoContent yellow "建议1000个左右"
    echoContent yellow "注意不要和其他的端口跳跃设置范围一样，设置相同会覆盖。"

    echoContent yellow "请输入端口跳跃的范围，例如[30000-31000]"

    read -r -p "范围:" portHoppingRange
    if [[ -z "${portHoppingRange}" ]]; then
        echoContent red " ---> 范围不可为空"
        addPortHopping "${type}" "${targetPort}"
    elif echo "${portHoppingRange}" | grep -q "-"; then

        local portStart=
        local portEnd=
        portStart=$(echo "${portHoppingRange}" | awk -F '-' '{print $1}')
        portEnd=$(echo "${portHoppingRange}" | awk -F '-' '{print $2}')

        if [[ -z "${portStart}" || -z "${portEnd}" ]]; then
            echoContent red " ---> 范围不合法"
            addPortHopping "${type}" "${targetPort}"
        elif ((portStart < 30000 || portStart > 40000 || portEnd < 30000 || portEnd > 40000 || portEnd < portStart)); then
            echoContent red " ---> 范围不合法"
            addPortHopping "${type}" "${targetPort}"
        else
            echoContent green "\n端口范围: ${portHoppingRange}\n"
            if [[ "${release}" == "centos" ]]; then
                addFirewalldPortHopping "${portStart}" "${portEnd}" "${targetPort}"
                if ! firewall-cmd --list-forward-ports | grep -q "toport=${targetPort}"; then
                    echoContent red " ---> 端口跳跃添加失败"
                    exit 1
                fi
            else
                iptables -t nat -A PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "Proxy-agent_${type}_portHopping" -j DNAT --to-destination ":${targetPort}"
                if ! iptables-save | grep -q "Proxy-agent_${type}_portHopping"; then
                    echoContent red " ---> 端口跳跃添加失败"
                    exit 1
                fi
                # 没有 netfilter-persistent（装了 ufw 的机器不装它）规则只活到重启，要明说，不能只报成功
                if ! command -v netfilter-persistent >/dev/null 2>&1 || ! netfilter-persistent save >/dev/null 2>&1; then
                    echoContent yellow " ---> $(t PORT_HOPPING_NOT_PERSISTENT)"
                fi
            fi
            echoContent green " ---> 端口跳跃添加成功"
        fi
    fi
}

# firewallForwardPortSpecs TARGET → 转发到本机 TARGET 端口的 udp 规则的源端口，一行一个（30000 或 30000-30999）。
# 旧版逐端口加、现在一条区间，两种都认；转发到别的主机（toaddr 非空）的不是跳跃规则
firewallForwardPortSpecs() {
    [[ -n "$1" ]] || return 0
    firewall-cmd --list-forward-ports | sed -nE "s/^port=([0-9]+(-[0-9]+)?):proto=udp:toport=$1:toaddr=\$/\1/p"
}

# 读取端口跳跃的配置
readPortHopping() {
    local type=$1
    local targetPort=$2
    local portHoppingStart=
    local portHoppingEnd=

    if [[ "${release}" == "centos" ]]; then
        read -r portHoppingStart portHoppingEnd < <(firewallForwardPortSpecs "${targetPort}" | awk -F- '
            { s = $1 + 0; e = (NF > 1 ? $2 : $1) + 0; if (min == "" || s < min) min = s; if (max == "" || e > max) max = e }
            END { if (min != "") print min, max }')
    else
        if iptables-save | grep -q "Proxy-agent_${type}_portHopping"; then
            local portHopping=
            portHopping=$(iptables-save | grep "Proxy-agent_${type}_portHopping" | cut -d " " -f 8)

            portHoppingStart=$(echo "${portHopping}" | cut -d ":" -f 1)
            portHoppingEnd=$(echo "${portHopping}" | cut -d ":" -f 2)
        fi
    fi
    if [[ "${type}" == "hysteria2" ]]; then
        hysteria2PortHoppingStart="${portHoppingStart}"
        hysteria2PortHoppingEnd=${portHoppingEnd}
        hysteria2PortHopping="${portHoppingStart}-${portHoppingEnd}"
    elif [[ "${type}" == "tuic" ]]; then
        tuicPortHoppingStart="${portHoppingStart}"
        tuicPortHoppingEnd="${portHoppingEnd}"
    fi
}
# 删除端口跳跃iptables规则
deletePortHoppingRules() {
    local type=$1
    local start=$2
    local end=$3
    local targetPort=$4

    if [[ "${release}" == "centos" ]]; then
        local spec
        while read -r spec; do
            [[ -n "${spec}" ]] && firewall-cmd --permanent --remove-forward-port=port="${spec}":proto=udp:toport="${targetPort}" >/dev/null
        done < <(firewallForwardPortSpecs "${targetPort}")
        firewall-cmd --reload >/dev/null
    else
        # 必须按读到的行号降序删：本脚本的规则是 -A 追加在链尾，固定删
        # PREROUTING 1 删的是别人的规则；升序删则每删一条后面的行号就前移一位。
        local hoppingLines line
        hoppingLines=$(iptables -t nat -L PREROUTING --line-numbers | grep "Proxy-agent_${type}_portHopping" | awk '{print $1}' | sort -rn)
        if [[ -n "${hoppingLines}" ]]; then
            while read -r line; do
                iptables -t nat -D PREROUTING "${line}"
            done <<<"${hoppingLines}"
            command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}

# removeProtocolPortHopping TYPE FRAGMENT → 协议卸载时带走它的跳跃规则：留着的话重装换了端口，规则还指向旧端口。
# iptables 的规则带协议标记；firewalld 的只能按目标端口认，读不到端口就不动，否则 toport= 会匹配到用户自己的转发
removeProtocolPortHopping() {
    local type=$1 targetPort= start= end=
    targetPort=$(jq -r '.inbounds[0].listen_port // empty' "$2" 2>/dev/null)
    if [[ "${release}" == "centos" ]]; then
        [[ -n "${targetPort}" ]] && systemctl is-active --quiet firewalld || return 0
    else
        command -v iptables >/dev/null 2>&1 || return 0
    fi
    readPortHopping "${type}" "${targetPort}"
    case "${type}" in
        hysteria2) start=${hysteria2PortHoppingStart} end=${hysteria2PortHoppingEnd} ;;
        tuic) start=${tuicPortHoppingStart} end=${tuicPortHoppingEnd} ;;
    esac
    if [[ -n "${start}" && -n "${end}" ]]; then
        deletePortHoppingRules "${type}" "${start}" "${end}" "${targetPort}"
    fi
}

# 端口跳跃菜单
portHoppingMenu() {
    local type=$1
    # 不能用 find | grep -q：grep 命中即退出，find 吃到 SIGPIPE，pipefail 下整条管道算失败，有 iptables 也常被判成没有
    if ! command -v iptables >/dev/null 2>&1; then
        echoContent red " ---> 无法识别iptables工具，无法使用端口跳跃，退出安装"
        exit 1
    fi

    local targetPort=${singBoxHysteria2Port}
    local portHoppingStart=
    local portHoppingEnd=

    readPortHopping "${type}" "${targetPort}"
    portHoppingStart=${hysteria2PortHoppingStart}
    portHoppingEnd=${hysteria2PortHoppingEnd}

    echoContent skyBlue "\n进度 1/1 : 端口跳跃"
    echoContent red "\n=============================================================="
    echoContent yellow "1.添加端口跳跃"
    echoContent yellow "2.删除端口跳跃"
    echoContent yellow "3.查看端口跳跃"
    read -r -p "请选择:" selectPortHoppingStatus
    # 加、删之后按原 salt 重建订阅：跳跃区间写在订阅里，不重建的话客户端拿到的还是旧端口
    if [[ "${selectPortHoppingStatus}" == "1" ]]; then
        addPortHopping "${type}" "${targetPort}"
        carpoolRefreshSubscribe
    elif [[ "${selectPortHoppingStatus}" == "2" ]]; then
        deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${targetPort}"
        carpoolRefreshSubscribe
        echoContent green " ---> 删除成功"
    elif [[ "${selectPortHoppingStatus}" == "3" ]]; then
        if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
            echoContent green " ---> 当前端口跳跃范围为: ${portHoppingStart}-${portHoppingEnd}"
        else
            echoContent yellow " ---> 未设置端口跳跃"
        fi
    else
        portHoppingMenu "${type}"
    fi
}

# 初始化tuic的协议
initTuicProtocol() {
    if [[ -n "${tuicAlgorithm}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次使用的算法，是否使用 ？[y/n]:" historyTuicAlgorithm
        if ! isYesInput "${historyTuicAlgorithm}"; then
            tuicAlgorithm=
        else
            echoContent yellow "\n ---> 算法: ${tuicAlgorithm}\n"
        fi
    elif [[ -n "${tuicAlgorithm}" && -n "${lastInstallationConfig}" ]]; then
        echoContent yellow "\n ---> 算法: ${tuicAlgorithm}\n"
    fi

    if [[ -z "${tuicAlgorithm}" ]]; then

        echoContent skyBlue "\n请选择算法类型"
        echoContent red "=============================================================="
        echoContent yellow "1.bbr(默认)"
        echoContent yellow "2.cubic"
        echoContent yellow "3.new_reno"
        echoContent red "=============================================================="
        read -r -p "请选择:" selectTuicAlgorithm
        case ${selectTuicAlgorithm} in
        1)
            tuicAlgorithm="bbr"
            ;;
        2)
            tuicAlgorithm="cubic"
            ;;
        3)
            tuicAlgorithm="new_reno"
            ;;
        *)
            tuicAlgorithm="bbr"
            ;;
        esac
        echoContent yellow "\n ---> 算法: ${tuicAlgorithm}\n"
    fi
}

# geosite 分类清单：v2fly domain-list-community 发布的 dlc.dat_plain.yml，sing-geosite 沿用同一套名字。
# 本地缺失或超过 30 天就重新下载；下载失败时留用旧文件，一份都没有才返回失败
ensureGeositeCategoryList() {
    local dir tmp
    dir=$(dirname "${GEOSITE_LIST_FILE}")
    if [[ -s "${GEOSITE_LIST_FILE}" ]] && [[ -z "$(find "${GEOSITE_LIST_FILE}" -mtime +30 2>/dev/null)" ]]; then
        return 0
    fi
    mkdir -p "${dir}"
    tmp=$(mktemp "${dir}/dlc.XXXXXX") || return 1
    if curl -fsSL --connect-timeout 10 -m 120 -o "${tmp}" "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat_plain.yml" 2>/dev/null \
        && grep -qE '^[[:space:]]*-[[:space:]]*name:' "${tmp}"; then
        mv -f "${tmp}" "${GEOSITE_LIST_FILE}"
        return 0
    fi
    rm -f "${tmp}"
    echoContent yellow " ---> $(t GEOSITE_LIST_DOWNLOAD_FAILED)"
    [[ -s "${GEOSITE_LIST_FILE}" ]]
}

# geositeCategoryExists NAME → 0 表示 NAME 是 geosite 分类；清单拿不到时一律按不是处理
geositeCategoryExists() {
    ensureGeositeCategoryList || return 1
    geositeListHasCategory "${GEOSITE_LIST_FILE}" "$1"
}

# xrayDomainRuleValue ENTRY → Xray 路由/DNS 的域名匹配项：geosite 分类给 "geosite:NAME"，其余给
# "domain:ENTRY"。分类名没有点，带点的直接判为域名；统一小写，geosite 文件名区分大小写
xrayDomainRuleValue() {
    local entry="${1,,}"
    if [[ "${entry}" != *.* ]] && geositeCategoryExists "${entry}"; then
        printf 'geosite:%s\n' "${entry}"
    else
        printf 'domain:%s\n' "${entry}"
    fi
}

# initSingBoxRules DOMAIN_CSV NAME_SUFFIX → {"domainRules":[],"ruleSet":[]}
# geosite 分类走 remote rule_set，其余出 domain_regex
initSingBoxRules() {
    local domainRules=[]
    local ruleSet=[]
    while read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        line="${line,,}"
        if [[ "${line}" != *.* ]] && geositeCategoryExists "${line}"; then
            ruleSet=$(echo "${ruleSet}" | jq -r --arg tag "${line}_$2" --arg url "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${line}.srs" \
                '. += [{tag: $tag, type: "remote", format: "binary", url: $url, http_client: "rule_set_http"}]')
        else
            local escapedLine="${line//./\\.}"
            domainRules=$(echo "${domainRules}" | jq -r --arg reg "^([a-zA-Z0-9_-]+\\.)*${escapedLine}" '. += [$reg]')
        fi
    done < <(echo "$1" | tr ',' '\n' | grep -v '^$' | sort -u)
    echo "{ \"domainRules\":${domainRules},\"ruleSet\":${ruleSet}}"
}

# 添加sing-box路由规则
addSingBoxRouteRule() {
    local outboundTag=$1
    # 域名列表
    local domainList=$2
    # 路由文件名称
    local routingName=$3
    # 读取上次安装内容
    if [[ -f "${singBoxConfigPath}${routingName}.json" ]]; then
        read -r -p "读取到上次的配置，是否保留 ？[y/n]:" historyRouteStatus
        if isYesInput "${historyRouteStatus}"; then
            domainList="${domainList},$(jq -rc .route.rules[0].rule_set[] "${singBoxConfigPath}${routingName}.json" | awk -F "[_]" '{print $1}' | paste -sd ',')"
            domainList="${domainList},$(jq -rc .route.rules[0].domain_regex[] "${singBoxConfigPath}${routingName}.json" | awk -F "[*]" '{print $2}' | paste -sd ',' | sed 's/\\//g')"
        fi
    fi
    local rules=
    rules=$(initSingBoxRules "${domainList}" "${routingName}")
    # domain精确匹配规则
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    # ruleSet规则集
    local ruleSet=
    ruleSet=$(echo "${rules}" | jq .ruleSet)

    # ruleSet规则tag
    local ruleSetTag=[]
    if [[ "$(echo "${ruleSet}" | jq '.|length')" != "0" ]]; then
        ruleSetTag=$(echo "${ruleSet}" | jq '.|map(.tag)')
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then

        cat <<EOF >"${singBoxConfigPath}${routingName}.json"
{
  "route": {
    "rules": [
      {
        "rule_set":${ruleSetTag},
        "domain_regex":${domainRules},
        "outbound": "${outboundTag}"
      }
    ],
    "rule_set":${ruleSet}
  }
}
EOF
        jq 'if .route.rule_set == [] then del(.route.rule_set) else . end' "${singBoxConfigPath}${routingName}.json" >"${singBoxConfigPath}${routingName}_tmp.json" && mv "${singBoxConfigPath}${routingName}_tmp.json" "${singBoxConfigPath}${routingName}.json"
    fi

}

# 确保基础 direct 出站存在（tag 恒为 "direct"）。
# 别改调 addSingBoxOutbound——它会把 tag 覆盖成文件名，分流里所有 "direct" 引用一起失效。
ensureDirectOutbound() {
    if [[ -z "${singBoxConfigPath}" ]]; then
        return 1
    fi
    cat <<'EOF' >"${singBoxConfigPath}01_direct_outbound.json"
{
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
}

# local 型 DNS server（走系统解析器），给 IPv4_out/IPv6_out 的 domain_resolver 引用。
# 文件名排在 01_dns.json 之后：dns.final 默认取首个 server，chain 场景的 google 不能被抢占。
ensureSingBoxLocalDns() {
    if [[ -z "${singBoxConfigPath}" ]]; then
        return 1
    fi
    jsonWriteFile "${singBoxConfigPath}02_dns_local.json" '{"dns":{"servers":[{"type":"local","tag":"local"}]}}' false
}

# 读运行中 sing-box 内核版本（形如 1.14.0）；二进制缺失或输出异常时为空
singBoxInstalledVersion() {
    ${SINGBOX_BIN} version 2>/dev/null | awk '/^sing-box version/ {print $3; exit}'
}

# 顶层 http_clients 片段：remote rule_set 的下载通道，不带 detour 即直连拨号。别加 detour 指向 direct 出站：
# 指向无拨号参数的 direct 在 1.14 上启动即 FATAL（detour to an empty direct outbound makes no sense），sing-box check 查不出
ensureSingBoxHttpClient() {
    jsonWriteFile "${1}02_http_client.json" '{"http_clients":[{"tag":"rule_set_http"}],"route":{"default_http_client":"rule_set_http"}}' false
}

# sing-box 1.14 起 remote rule_set 用 http_client 引用顶层 http_clients（download_detour 与隐式
# 默认 client 同在 1.14 弃用、1.15 起启动 FATAL），1.14 以下又不识别这两个字段。写入端只写
# 新形态，这里在合并前按运行中的内核把片段统一成它认得的那一种。
normalizeSingBoxRuleSetHttpClient() {
    local fragmentDir="$1"
    local ver file hasRemote=0 changed=0
    ver=$(singBoxInstalledVersion)
    if [[ -z "${ver}" ]]; then
        return 0
    fi
    if versionGreaterOrEqual "${ver}" "1.14.0"; then
        for file in "${fragmentDir}"*.json; do
            [[ -f "${file}" ]] || continue
            if jq -e '[.route.rule_set[]? | has("download_detour")] | any' "${file}" >/dev/null 2>&1; then
                if jsonModifyFile "${file}" '.route.rule_set |= map(if has("download_detour") then .http_client = "rule_set_http" | del(.download_detour) else . end)' false; then
                    changed=1
                fi
            fi
            if jq -e '[.route.rule_set[]? | .type == "remote"] | any' "${file}" >/dev/null 2>&1; then
                hasRemote=1
            fi
        done
        if [[ ${hasRemote} -eq 1 ]]; then
            ensureSingBoxHttpClient "${fragmentDir}"
        fi
        if [[ ${changed} -eq 1 ]]; then
            echoContent yellow " ---> $(t SINGBOX_RULESET_HTTP_CLIENT_MIGRATED)"
        fi
    else
        for file in "${fragmentDir}"*.json; do
            [[ -f "${file}" ]] || continue
            if jq -e '[.route.rule_set[]? | has("http_client")] | any' "${file}" >/dev/null 2>&1; then
                if jsonModifyFile "${file}" '.route.rule_set |= map(del(.http_client))' false; then
                    changed=1
                fi
            fi
        done
        if [[ -f "${fragmentDir}02_http_client.json" ]]; then
            rm -f "${fragmentDir}02_http_client.json"
            changed=1
        fi
        if [[ ${changed} -eq 1 ]]; then
            echoContent yellow " ---> $(t SINGBOX_RULESET_HTTP_CLIENT_STRIPPED)"
        fi
    fi
}

# 片段里上游已撤的规则集换成替代名：sing-box 下载远程规则集 404 就拒绝启动，而旧版「开发者」预设写过 stackoverflow。
# 链路状态只存预设名，不改片段的话要等下次链路改动重新生成才换掉
migrateRetiredRuleSets() {
    local fragmentDir="$1" file changed=0
    for file in "${fragmentDir}"*.json; do
        [[ -f "${file}" ]] || continue
        jq -e 'any(.route.rule_set[]?; .tag == "geosite-stackoverflow")' "${file}" >/dev/null 2>&1 || continue
        if jsonModifyFile "${file}" '
            def rename: if . == "geosite-stackoverflow" then "geosite-stackexchange" else . end;
            .route.rule_set |= (map(if .tag == "geosite-stackoverflow"
                then .tag = "geosite-stackexchange" | .url |= sub("/stackoverflow[.]srs$"; "/stackexchange.srs")
                else . end) | unique_by(.tag))
            | if .route.rules then .route.rules |= map(if has("rule_set")
                then .rule_set |= (if type == "array" then map(rename) | unique else rename end)
                else . end) else . end' false; then
            changed=1
        fi
    done
    if [[ ${changed} -eq 1 ]]; then
        echoContent yellow " ---> $(t SINGBOX_RULESET_RENAMED geosite-stackoverflow geosite-stackexchange)"
    fi
}

# migrateSingBoxDnsSplit DIR → 旧版 DNS / SNI 分流写的 dns.json 改成 addSingBoxDNSConfig 现在的形状；旧版卸载留下的
# 单个无 tag local 直接删。旧形状自带的 local 与 02_dns_local.json 重名、又缺解析器，sing-box 1.13 起拒绝启动。别的形状不动
migrateSingBoxDnsSplit() {
    local file="$1dns.json" out
    [[ -f "${file}" ]] || return 0
    if jq -e '. == {dns: {servers: [{type: "local"}]}}' "${file}" >/dev/null 2>&1; then
        rm -f "${file}"
        return 0
    fi
    jq -e '.dns.servers as $s | .dns.rules as $r
        | ($s | length) == 2 and $s[0] == {tag: "local", type: "local"}
        and ($s[1].tag == "dnsRouting" or $s[1].tag == "hosts")
        and ($r | type) == "array" and ($r | length) > 0 and all($r[]; .server == $s[1].tag)' "${file}" >/dev/null 2>&1 || return 0
    out=$(jq --arg cache "${SINGBOX_CONF_DIR}/cache.db" '
        .dns.servers[1] as $srv | .dns.rules as $r
        | .dns = {servers: [$srv]}
        | .route.rules = [$r[] | del(.server)
            | (if (.domain_regex // []) | length > 0 then {domain_regex} else empty end),
              (if (.rule_set // []) | length > 0 then {rule_set} else empty end)
            | . + {action: "resolve", server: $srv.tag}]
        | if ((.route.rule_set // []) | length) > 0 then .experimental.cache_file = {enabled: true, path: $cache} else . end' \
        "${file}") || return 1
    jsonWriteFile "${file}" "${out}" false || return 1
    singBoxConfigPath="$1" ensureSingBoxLocalDns || return 1
    echoContent yellow " ---> $(t SINGBOX_DNS_SPLIT_MIGRATED)"
}

addSingBoxOutbound() {
    local tag=$1
    local type="ipv4"
    local detour=$2
    if echo "${tag}" | grep -q "IPv6"; then
        type=ipv6
    fi
    # 强制地址族用 domain_resolver（dial 字段 domain_strategy 已在 1.12 弃用、1.14 移除），
    # 它引用的 local server 由 02_dns_local.json 提供
    ensureSingBoxLocalDns
    if [[ -n "${detour}" ]]; then
        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}",
             "detour": "${detour}",
             "domain_resolver": {
                 "server": "local",
                 "strategy": "${type}_only"
             }
        }
    ]
}
EOF
    elif echo "${tag}" | grep -q "direct"; then

        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}"
        }
    ]
}
EOF
    else
        cat <<EOF >"${singBoxConfigPath}${tag}.json"
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}",
             "domain_resolver": {
                 "server": "local",
                 "strategy": "${type}_only"
             }
        }
    ]
}
EOF
    fi
}

# 添加Xray-core 出站
addXrayOutbound() {
    local tag=$1
    local domainStrategy=

    if echo "${tag}" | grep -q "IPv4"; then
        domainStrategy="ForceIPv4"
    elif echo "${tag}" | grep -q "IPv6"; then
        domainStrategy="ForceIPv6"
    fi

    if [[ -n "${domainStrategy}" ]]; then
        cat <<EOF >"${XRAY_CONF_DIR}/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings":{
                "domainStrategy":"${domainStrategy}"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # direct
    if echo "${tag}" | grep -q "direct"; then
        cat <<EOF >"${XRAY_CONF_DIR}/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings": {
                "domainStrategy":"UseIP"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # blackhole
    if echo "${tag}" | grep -q "blackhole"; then
        cat <<EOF >"${XRAY_CONF_DIR}/${tag}.json"
{
    "outbounds":[
        {
            "protocol":"blackhole",
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv4"; then
        cat <<EOF >"${XRAY_CONF_DIR}/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "wireguard_out_IPv6"; then
        cat <<EOF >"${XRAY_CONF_DIR}/${tag}.json"
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if echo "${tag}" | grep -q "vmess-out"; then
        cat <<EOF >"${XRAY_CONF_DIR}/${tag}.json"
{
  "outbounds": [
    {
      "tag": "${tag}",
      "protocol": "vmess",
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {},
        "wsSettings": {
          "path": "${setVMessWSTLSPath}"
        }
      },
      "mux": {
        "enabled": true,
        "concurrency": 8
      },
      "settings": {
        "vnext": [
          {
            "address": "${setVMessWSTLSAddress}",
            "port": "${setVMessWSTLSPort}",
            "users": [
              {
                "id": "${setVMessWSTLSUUID}",
                "security": "auto",
                "alterId": 0
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
    fi
}

# 删除 Xray-core出站
removeXrayOutbound() {
    local tag=$1
    if [[ -f "${XRAY_CONF_DIR}/${tag}.json" ]]; then
        rm "${XRAY_CONF_DIR}/${tag}.json" >/dev/null 2>&1
    fi
}
# 移除sing-box配置
removeSingBoxConfig() {

    local tag=$1
    if [[ -f "${singBoxConfigPath}${tag}.json" ]]; then
        rm "${singBoxConfigPath}${tag}.json"
    fi
}

# 初始化wireguard出站信息
addSingBoxWireGuardEndpoints() {
    local type=$1

    readConfigWarpReg

    cat <<EOF >"${singBoxConfigPath}wireguard_endpoints_${type}.json"
{
     "endpoints": [
        {
            "type": "wireguard",
            "tag": "wireguard_endpoints_${type}",
            "address": [
                "${address}"
            ],
            "private_key": "${secretKeyWarpReg}",
            "peers": [
                {
                  "address": "162.159.192.1",
                  "port": 2408,
                  "public_key": "${publicKeyWarpReg}",
                  "reserved":${reservedWarpReg},
                  "allowed_ips": ["0.0.0.0/0","::/0"]
                }
            ]
        }
    ]
}
EOF
}

# sing-box Tuic安装
singBoxTuicInstall() {
    carpoolRefuseIfEnabled
    if ! anyProtocolRequiresTLS "${currentInstallProtocolType}"; then
        echoContent red "\n ---> 由于需要依赖证书，如安装Tuic，请先安装带有TLS标识协议"
        exit 1
    fi

    totalProgress=5
    installSingBox 1 || { echoContent red "\n ---> sing-box 安装失败，已中止安装流程"; exit 1; }
    selectCustomInstallType=",9,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    # 订阅装过就按原 salt 重建：不然新装的协议进不了用户手里的订阅，要等下次手动「查看订阅」
    refreshSubscribeAfterInstall
    showAccounts 4
}

# sing-box hy2安装
singBoxHysteria2Install() {
    carpoolRefuseIfEnabled
    if ! anyProtocolRequiresTLS "${currentInstallProtocolType}"; then
        echoContent red "\n ---> 由于需要依赖证书，如安装Hysteria2，请先安装带有TLS标识协议"
        exit 1
    fi

    totalProgress=5
    installSingBox 1 || { echoContent red "\n ---> sing-box 安装失败，已中止安装流程"; exit 1; }
    selectCustomInstallType=",6,"
    initSingBoxConfig custom 2 true
    installSingBoxService 3
    reloadCore
    # 订阅装过就按原 salt 重建：不然新装的协议进不了用户手里的订阅，要等下次手动「查看订阅」
    refreshSubscribeAfterInstall
    showAccounts 4
}

# 原子写入 chain/external 状态 JSON：$1=路径 $2=JSON。走 jsonWriteFile，backup=false
# （避免 conf/ 堆积 .bak）。返回 1 时旧文件保持不变。
writeChainInfoAtomic() {
    local file="$1"
    local content="$2"
    if jsonWriteFile "${file}" "${content}" false; then
        return 0
    fi
    echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${file}")"
    return 1
}

# 合并 config：不先 rm 旧文件——merge 自带 O_TRUNC，先 rm 会制造"失败即丢文件"的窗口，
# systemd 会进 restart loop。输出到 mktemp，sing-box check 通过才原子 mv。
singBoxMergeConfig() {
    local targetFile="${SINGBOX_MERGED_CONFIG}"
    local fragmentDir="${SINGBOX_FRAGMENT_DIR}/"
    local tmpFile mergeOutput mergeResult checkOutput checkResult

    # 一次性迁移：移除已下线的「菜单 15 域名黑名单」遗留片段。
    # block 类 outbound 是 sing-box 1.11 起弃用的旧写法（1.14.4 的 check 还认），这些文件没有菜单管了，留着也用不上。
    # 没用过黑名单菜单的用户这些文件不存在；什么都不打印。
    local _orphanFile _orphanCleaned=0
    for _orphanFile in block_domain_outbound block_domain_route \
                       cn_block_outbound cn_block_route cn_01_google_play_route; do
        if [[ -f "${fragmentDir}${_orphanFile}.json" ]]; then
            rm -f "${fragmentDir}${_orphanFile}.json"
            _orphanCleaned=1
        fi
    done
    if [[ ${_orphanCleaned} -eq 1 ]]; then
        echoContent yellow " ---> 已移除已废弃的「域名黑名单」配置片段（功能已下线，详见用户指南升级与迁移提示）"
    fi

    # 一次性迁移：outbound 的 domain_strategy（1.12 弃用、1.14 移除）换成等价的
    # domain_resolver{local}——local 走系统解析器，与旧字段的隐式默认一致
    local _dsFile _dsMigrated=0
    for _dsFile in "${fragmentDir}"*.json; do
        [[ -f "${_dsFile}" ]] || continue
        if jq -e '[.outbounds[]? | has("domain_strategy")] | any' "${_dsFile}" >/dev/null 2>&1; then
            if jsonModifyFile "${_dsFile}" '.outbounds |= map(if has("domain_strategy") then .domain_resolver = {server: "local", strategy: .domain_strategy} | del(.domain_strategy) else . end)'; then
                _dsMigrated=1
            fi
        fi
    done
    if [[ ${_dsMigrated} -eq 1 ]]; then
        ensureSingBoxLocalDns
        echoContent yellow " ---> $(t SINGBOX_DOMAIN_STRATEGY_MIGRATED)"
    fi

    migrateRetiredRuleSets "${fragmentDir}"
    migrateSingBoxDnsSplit "${fragmentDir}"
    normalizeSingBoxRuleSetHttpClient "${fragmentDir}"

    # 建在 config.json 同目录：mv 才是同一文件系统里的原子替换，SELinux 下也不会带着 /tmp 的 user_tmp_t 标签过去。
    # 不能放进片段目录（merge 会把它当片段读）；BusyBox 的 mktemp 要求模板以 XXXXXX 结尾
    if ! tmpFile=$(mktemp "${SINGBOX_CONF_DIR}/.config.json.XXXXXX"); then
        echoContent red " ---> sing-box 配置合并失败：无法创建临时文件"
        return 1
    fi

    # sing-box merge 接受绝对输出路径；省 -D 避免它把相对名拼到 conf/ 根。
    mergeOutput=$(${SINGBOX_BIN} merge "${tmpFile}" -C "${fragmentDir}" 2>&1)
    mergeResult=$?

    if [[ ${mergeResult} -ne 0 ]]; then
        echoContent red " ---> sing-box 配置合并失败"
        echoContent red " ---> 错误信息:"
        echo "${mergeOutput}" | head -20
        rm -f "${tmpFile}"
        return 1
    fi

    if [[ ! -s "${tmpFile}" ]]; then
        echoContent red " ---> sing-box 配置合并失败：临时文件为空"
        rm -f "${tmpFile}"
        return 1
    fi

    if ! chainAccountInject "${tmpFile}"; then
        echoContent red " ---> $(t CHAIN_ACCOUNT_INJECT_FAILED)"
        rm -f "${tmpFile}"
        return 1
    fi
    if ! chainExitSourceInject "${tmpFile}"; then
        echoContent red " ---> $(t CHAIN_EXIT_SOURCE_INJECT_FAILED "${CHAIN_EXIT_INFO}")"
        rm -f "${tmpFile}"
        return 1
    fi
    if ! directOutboundInject "${tmpFile}"; then
        echoContent red " ---> $(t SINGBOX_DIRECT_INJECT_FAILED)"
        rm -f "${tmpFile}"
        return 1
    fi
    if ! defaultDomainResolverInject "${tmpFile}"; then
        echoContent red " ---> $(t SINGBOX_DNS_RESOLVER_INJECT_FAILED)"
        rm -f "${tmpFile}"
        return 1
    fi
    # 排在账号规则之后注入，插到最前，所以封锁规则在最前面
    if ! localBlockInject "${tmpFile}"; then
        echoContent red " ---> $(t SINGBOX_LOCAL_BLOCK_FAILED)"
        rm -f "${tmpFile}"
        return 1
    fi

    # 运行时校验：sing-box check 检查端口冲突、tag 唯一性、协议字段一致性
    # 等 merge 不查的项。失败保留旧 config.json，不替换。
    checkOutput=$(${SINGBOX_BIN} check -c "${tmpFile}" 2>&1)
    checkResult=$?
    if [[ ${checkResult} -ne 0 ]]; then
        echoContent red " ---> sing-box 配置校验失败（保留旧配置）"
        echoContent red " ---> 错误信息:"
        echo "${checkOutput}" | head -20
        rm -f "${tmpFile}"
        return 1
    fi

    if ! mv "${tmpFile}" "${targetFile}"; then
        echoContent red " ---> sing-box 配置写入失败：无法替换 ${targetFile}"
        rm -f "${tmpFile}"
        return 1
    fi

    return 0
}

# initSingBoxPort OLD_PORT [ID KEEP] → 端口打到最后一行。带 ID 按协议取默认端口并查重（KEEP 同 configuredPorts），
# 不带 ID 的是订阅端口，回车随机
initSingBoxPort() {
    local port=$1
    if [[ -n "${2:-}" ]]; then
        port=$(pickInboundPort "$2" "${port}" "${SINGBOX_FRAGMENT_DIR}" "${3:-}" "")
        allowPort "${port}"
        allowPort "${port}" "udp"
        echo "${port}"
        return 0
    fi
    if [[ -n "${port}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次使用的端口，是否使用 ？[y/n]:" historyPort
        if ! isYesInput "${historyPort}"; then
            port=
        else
            echo "${port}"
        fi
    elif [[ -n "${port}" && -n "${lastInstallationConfig}" ]]; then
        echo "${port}"
    fi
    if [[ -z "${port}" ]]; then
        # 本函数跑在 <(...) 里，exit 只退子 shell、调用方会把报错当端口写进配置；输错就重问
        until readValidPort '请输入自定义端口[需合法]，端口不可重复，[回车]随机端口:' port "RANDOM" 10000 60000 >&2; do :; done
        allowPort "${port}"
        allowPort "${port}" "udp"
        echo "${port}"
    fi
}

# 初始化Xray 配置文件
# readInstallAccount UUID_CMD → 问自定义 UUID 与用户名，写进 uuid、customEmail；UUID_CMD 生成随机 UUID。
# 输错重问不退出：安装走到这里时服务已停，退出会把整机留在断线状态
readInstallAccount() {
    while true; do
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        read -r -p 'UUID:' customUUID
        if [[ -z "${customUUID}" ]]; then
            uuid=$($1)
            break
        # 8-4-4-4-12 十六进制，挡住特殊字符进入下游 JSON 构造（与 addUser 走的 customUUID() 同一规则）
        elif [[ "${customUUID}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            uuid=${customUUID}
            break
        fi
        echoContent red " ---> UUID 格式非法，需 8-4-4-4-12 位十六进制（例：550e8400-e29b-41d4-a716-446655440000）"
    done

    while true; do
        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        read -r -p '用户名:' customEmail
        if [[ -z "${customEmail}" ]]; then
            # 默认值含 '/'（JSON 合法），不走下面的校验
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
            break
        elif [[ "${customEmail}" =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$ ]]; then
            break
        fi
        echoContent red " ---> email 格式非法，仅允许字母数字及 . _ @ + -，长度 1-64"
    done
}

initXrayConfig() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化Xray配置"
    echo
    # 二进制预检：本函数依赖 ${XRAY_BIN} 生成 UUID（5152/5165 行）。
    # 主安装路径已在 installXray 失败时退出，这里是 belt-and-suspenders，覆盖 addUser 等独立调用。
    if [[ ! -f "${XRAY_BIN}" ]]; then
        echoContent red " ---> Xray-core 二进制不存在，无法初始化配置"
        echoContent yellow "     预期路径: ${XRAY_BIN}"
        exit 1
    fi
    # 端口查重：非追加的自定义安装里没选的协议随后会被删，旧端口不算占用；0 的端口已在 customPortFunction 定下、文件还没写
    local portKeep=${selectCustomInstallType} portSkip= portExtra=
    if [[ "$1" == "all" || -n "${3:-}" ]]; then
        portKeep=
    fi
    if [[ "$1" == "all" ]] || echo "${selectCustomInstallType}" | grep -q ",0,"; then
        portSkip=",0,"
        portExtra=${port}
    fi
    local uuid=
    local addClientsStatus=
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，是否使用上次安装的配置 ？[y/n]:" historyUUIDStatus
        if isYesInput "${historyUUIDStatus}"; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        readInstallAccount "${XRAY_BIN} uuid"
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(${XRAY_BIN} uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"id":"'${uuid}'","add":"'${add}'","flow":"xtls-rprx-vision","email":"'${customEmail}'"}]'
        echoContent green "\n ${customEmail}:${uuid}"
        echo
    fi

    # log
    if [[ ! -f "${XRAY_CONF_DIR}/00_log.json" ]]; then

        cat <<EOF >${XRAY_CONF_DIR}/00_log.json
{
  "log": {
    "error": "${XRAY_DIR}/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF
    fi

    if [[ ! -f "${XRAY_CONF_DIR}/12_policy.json" ]]; then
        local handshakeVal connIdleVal
        handshakeVal=$(randomNum 1 4)
        connIdleVal=$(randomNum 250 300)
        cat <<EOF >${XRAY_CONF_DIR}/12_policy.json
{
  "policy": {
      "levels": {
          "0": {
              "handshake": ${handshakeVal},
              "connIdle": ${connIdleVal}
          }
      }
  }
}
EOF
    fi

    addXrayOutbound "z_direct_outbound"
    # dns
    if [[ ! -f "${XRAY_CONF_DIR}/11_dns.json" ]]; then
        cat <<EOF >${XRAY_CONF_DIR}/11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF
    fi
    # routing
    cat <<EOF >${XRAY_CONF_DIR}/09_routing.json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:gstatic.com",
          "domain:googleapis.com",
	  "domain:googleapis.cn"
        ],
        "outboundTag": "z_direct_outbound"
      }
    ]
  }
}
EOF
    # VLESS_TCP_TLS_Vision
    # 回落nginx
    local fallbacksList='{"dest":31300,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'

    # trojan
    if echo "${selectCustomInstallType}" | grep -q ",4," || [[ "$1" == "all" ]]; then
        fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'
        cat <<EOF >${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json
{
"inbounds":[
	{
	  "port": 31296,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag":"trojanTCP",
	  "settings": {
		"clients": $(initXrayClients 4),
		"fallbacks":[
			{
			    "dest":"31300",
			    "xver":1
			}
		]
	  },
	  "streamSettings": {
		"network": "tcp",
		"security": "none",
		"tcpSettings": {
			"acceptProxyProtocol": true
		}
	  }
	}
	]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_WS_TLS
    if echo "${selectCustomInstallType}" | grep -q ",1," || [[ "$1" == "all" ]]; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
        cat <<EOF >${XRAY_CONF_DIR}/03_VLESS_WS_inbounds.json
{
"inbounds":[
    {
	  "port": 31297,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSWS",
	  "settings": {
		"clients": $(initXrayClients 1),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${customPath}ws"
		}
	  }
	}
]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_Reality_XHTTP_TLS
    if echo "${selectCustomInstallType}" | grep -q ",12," || [[ "$1" == "all" ]]; then
        echoContent skyBlue "\n================== $(t CONFIG_PROTOCOL_TITLE "VLESS+Reality+XHTTP") ==================\n"
        initXrayXHTTPort "${portKeep}" "${portSkip}" ${portExtra:+"${portExtra}"}
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        initRealityMldsa65
        cat <<EOF >${XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json
{
"inbounds":[
    {
	  "port": ${xHTTPort},
	  "listen": "0.0.0.0",
	  "protocol": "vless",
	  "tag":"VLESSRealityXHTTP",
	  "settings": {
		"clients": $(initXrayClients 12),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "xhttp",
		"security": "reality",
		"realitySettings": {
            "show": false,
            "target": "${realityDestHost:-${realityServerName}}:${realityDomainPort}",
            "xver": 0,
            "serverNames": [
                "${realityServerName}"
            ],
            "privateKey": "${realityPrivateKey}",
            "publicKey": "${realityPublicKey}",
            "mldsa65Seed": "${realityMldsa65Seed}",
            "mldsa65Verify": "${realityMldsa65Verify}",
            "minClientVer": "${REALITY_MIN_CLIENT_VER}",
            "maxTimeDiff": 60000,
            "shortIds": [
                "${realityShortId1}",
                "${realityShortId2}"
            ]
        },
        "xhttpSettings": {
            "host": "${realityServerName}",
            "path": "/${customPath}xHTTP",
            "mode": "auto",
            "extra": {
                "xPaddingBytes": "100-1000"
            }
        }
	  }
	}
]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_XHTTP_TLS：只听回环，0 把 h2 回落给 nginx，nginx 按路径转进来；host 不写，校验交给 nginx 的 server_name
    if echo "${selectCustomInstallType}" | grep -q ",15," || [[ "$1" == "all" ]]; then
        cat <<EOF >${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json
{
"inbounds":[
    {
	  "port": ${XHTTP_TLS_LOCAL_PORT},
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSXHTTPTLS",
	  "settings": {
		"clients": $(initXrayClients 15),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "xhttp",
		"security": "none",
		"xhttpSettings": {
		  "path": "/${customPath}xhttp",
		  "mode": "auto"
		}
	  }
	}
]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/15_VLESS_XHTTP_TLS_inbounds.json >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",3," || [[ "$1" == "all" ]]; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'vws","dest":31299,"xver":1}'
        cat <<EOF >${XRAY_CONF_DIR}/05_VMess_WS_inbounds.json
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31299,
          "protocol": "vmess",
          "tag":"VMessWS",
          "settings": {
            "clients": $(initXrayClients 3)
          },
          "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
              "acceptProxyProtocol": true,
              "path": "/${customPath}vws"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_gRPC - 已移除，推荐使用XHTTP
    # gRPC协议已废弃，清理旧配置文件
    if [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/06_VLESS_gRPC_inbounds.json >/dev/null 2>&1
    fi

    # VLESS Vision
    if echo "${selectCustomInstallType}" | grep -q ",0," || [[ "$1" == "all" ]]; then

        cat <<EOF >${XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json
{
    "inbounds":[
        {
          "port": ${port},
          "protocol": "vless",
          "tag":"VLESSTCP",
          "settings": {
            "clients":$(initXrayClients 0),
            "decryption": "none",
            "fallbacks": [
                ${fallbacksList}
            ]
          },
          "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
              "alpn": ["h2", "http/1.1"],
              "rejectUnknownSni": true,
              "minVersion": "1.2",
              "certificates": [
                {
                  "certificateFile": "${TLS_DIR}/${domain}.crt",
                  "keyFile": "${TLS_DIR}/${domain}.key",
                  "ocspStapling": 3600
                }
              ]
            }
          }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
        rm -f "${nginxConfigPath}http_redirect.conf"
    fi

    # VLESS_TCP/reality
    if echo "${selectCustomInstallType}" | grep -q ",7," || [[ "$1" == "all" ]]; then
        echoContent skyBlue "\n===================== 配置VLESS+Reality =====================\n"

        initXrayRealityPort "${portKeep}" "${portSkip}" ${portExtra:+"${portExtra}"}
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        initRealityMldsa65
        cat <<EOF >${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json
{
  "inbounds": [
    {
      "tag": "dokodemo-in-VLESSReality",
      "port": ${realityPort},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 45987,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 45987,
      "protocol": "vless",
      "settings": {
        "clients": $(initXrayClients 7),
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${realityDestHost:-${realityServerName}}:${realityDomainPort}",
          "xver": 0,
          "serverNames": [
            "${realityServerName}"
          ],
          "privateKey": "${realityPrivateKey}",
          "publicKey": "${realityPublicKey}",
          "mldsa65Seed": "${realityMldsa65Seed}",
          "mldsa65Verify": "${realityMldsa65Verify}",
          "minClientVer": "${REALITY_MIN_CLIENT_VER}",
          "maxTimeDiff": 60000,
          "shortIds": [
            "${realityShortId1}",
            "${realityShortId2}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "${realityServerName}"
        ],
        "outboundTag": "z_direct_outbound"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "blackhole_out"
      }
    ]
  }
}
EOF
    # 上方两条 dokodemo-in 规则永不命中（tag 是精确字符串匹配），是有意保留的 dead routing：
    # Reality 靠内层 realitySettings.target 兜底反代真实伪装站，改成命中会让鉴权失败或暴露
    # fingerprint。不要"修"它们。
    elif [[ -z "${3:-}" ]]; then
        rm ${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
        rm ${XRAY_CONF_DIR}/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi
    installSniffing
    if [[ -z "${3:-}" ]]; then
        removeXrayOutbound wireguard_out_IPv4_route
        removeXrayOutbound wireguard_out_IPv6_route
        removeXrayOutbound wireguard_outbound
        removeXrayOutbound IPv4_out
        removeXrayOutbound IPv6_out
        removeXrayOutbound socks5_outbound
        removeXrayOutbound blackhole_out
        removeXrayOutbound wireguard_out_IPv6
        removeXrayOutbound wireguard_out_IPv4
        addXrayOutbound z_direct_outbound
        addXrayOutbound blackhole_out
    fi
}

# 初始化sing-box配置文件
initSingBoxConfig() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化sing-box配置"

    echo
    # 二进制预检：本函数依赖 ${SINGBOX_BIN} 生成 UUID。
    # 主安装路径已在 installSingBox 失败时退出，这里是 belt-and-suspenders，覆盖独立调用。
    if [[ ! -f "${SINGBOX_BIN}" ]]; then
        echoContent red " ---> sing-box 二进制不存在，无法初始化配置"
        echoContent yellow "     预期路径: ${SINGBOX_BIN}"
        exit 1
    fi
    # 端口查重：非追加的自定义安装里没选的协议随后会被删，旧端口不算占用
    local portKeep=${selectCustomInstallType}
    if [[ "$1" == "all" || -n "${3:-}" ]]; then
        portKeep=
    fi
    local uuid=
    local addClientsStatus=
    local sslDomain=
    if [[ -n "${domain}" ]]; then
        sslDomain="${domain}"
    elif [[ -n "${currentHost}" ]]; then
        sslDomain="${currentHost}"
    fi
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，是否使用上次安装的配置 ？[y/n]:" historyUUIDStatus
        if isYesInput "${historyUUIDStatus}"; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        readInstallAccount "${SINGBOX_BIN} generate uuid"
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(${SINGBOX_BIN} generate uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"uuid":"'${uuid}'","flow":"xtls-rprx-vision","name":"'${customEmail}'"}]'
        echoContent yellow "\n ${customEmail}:${uuid}"
    fi

    # VLESS Vision
    if echo "${selectCustomInstallType}" | grep -q ",0," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VLESS+Vision =====================\n"
        echoContent skyBlue "\n开始配置VLESS+Vision协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSVisionPort}" 0 "${portKeep}")
        echoContent green "\n ---> VLESS_Vision端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop

        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/02_VLESS_TCP_inbounds.json
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSTCP",
          "users":$(initSingBoxClients 0),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
            "key_path": "${TLS_DIR}/${sslDomain}.key"
          }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",1," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VLESS+WS =====================\n"
        echoContent skyBlue "\n开始配置VLESS+WS协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSWSPort}" 1 "${portKeep}")
        echoContent green "\n ---> VLESS_WS端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/03_VLESS_WS_inbounds.json
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSWS",
          "users":$(initSingBoxClients 1),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
            "key_path": "${TLS_DIR}/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}ws",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",3," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VMess+ws =====================\n"
        echoContent skyBlue "\n开始配置VMess+ws协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessWSPort}" 3 "${portKeep}")
        echoContent green "\n ---> VMess_ws端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/05_VMess_WS_inbounds.json
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VMessWS",
          "users":$(initSingBoxClients 3),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
            "key_path": "${TLS_DIR}/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_Reality_Vision
    if echo "${selectCustomInstallType}" | grep -q ",7," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================= 配置VLESS+Reality+Vision =================\n"
        initRealityClientServersName
        initRealityKey
        initRealityShortIds
        echoContent skyBlue "\n开始配置VLESS+Reality+Vision协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityVisionPort}" 7 "${portKeep}")
        echoContent green "\n ---> VLESS_Reality_Vision端口：${result[-1]}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/07_VLESS_vision_reality_inbounds.json
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "tag": "VLESSReality",
      "users":$(initSingBoxClients 7),
      "tls": {
        "enabled": true,
        "server_name": "${realityServerName}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server": "${realityDestHost:-${realityServerName}}",
                "server_port":${realityDomainPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "${realityShortId1}",
                "${realityShortId2}"
            ]
        }
      }
    }
  ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
    fi

    # VLESS+Reality+gRPC - 已移除，推荐使用XHTTP
    # 清理旧配置文件
    if [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",6," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 Hysteria2 ==================\n"
        echoContent skyBlue "\n开始配置Hysteria2协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxHysteria2Port}" 6 "${portKeep}")
        echoContent green "\n ---> Hysteria2端口：${result[-1]}"
        initHysteria2Network

        # masquerade 用伪装站的静态文件，sing-box 内核没装过就先装一个。宝塔 / 1Panel 的目录是用户自己的站点，
        # 可能有 PHP 源码，文件服务器会原样吐出去，所以不配
        local hysteria2SiteDir= hysteria2Json=
        if [[ -z "${btDomain}" ]]; then
            if [[ ! -f "${nginxStaticPath}/check" ]]; then
                nginxBlog
            fi
            if [[ -f "${nginxStaticPath}/check" ]]; then
                hysteria2SiteDir=${nginxStaticPath%/}
            fi
        fi
        if [[ -z "${hysteria2SiteDir}" ]]; then
            echoContent yellow " ---> $(t HY2_MASQUERADE_NONE)"
        fi
        if ! hysteria2Json=$(hysteria2InboundJson "${result[-1]}" "$(initSingBoxClients 6)" "${sslDomain}" \
            "${hysteria2ClientDownloadSpeed}" "${hysteria2ClientUploadSpeed}" \
            "${hysteria2ObfsType}" "${hysteria2ObfsPassword}" "${hysteria2SiteDir}") ||
            ! jsonWriteFile "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" "${hysteria2Json}" false; then
            echoContent red " ---> $(t HY2_WRITE_FAILED)"
            exit 1
        fi
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",4," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 Trojan ==================\n"
        echoContent skyBlue "\n开始配置Trojan协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTrojanPort}" 4 "${portKeep}")
        echoContent green "\n ---> Trojan端口：${result[-1]}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/04_trojan_TCP_inbounds.json
{
    "inbounds": [
        {
            "type": "trojan",
            "tag": "trojanTCP",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 4),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
                "key_path": "${TLS_DIR}/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",9," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n==================== 配置 Tuic =====================\n"
        echoContent skyBlue "\n开始配置Tuic协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTuicPort}" 9 "${portKeep}")
        echoContent green "\n ---> Tuic端口：${result[-1]}"
        initTuicProtocol
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json
{
     "inbounds": [
        {
            "type": "tuic",
            "listen": "::",
            "tag": "singbox-tuic-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 9),
            "congestion_control": "${tuicAlgorithm}",
            "auth_timeout": "3s",
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
                "key_path": "${TLS_DIR}/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",10," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n==================== 配置 Naive =====================\n"
        echoContent skyBlue "\n开始配置Naive协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxNaivePort}" 10 "${portKeep}")
        echoContent green "\n ---> Naive端口：${result[-1]}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/10_naive_inbounds.json
{
     "inbounds": [
        {
            "type": "naive",
            "listen": "::",
            "tag": "singbox-naive-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 10),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
                "key_path": "${TLS_DIR}/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/10_naive_inbounds.json >/dev/null 2>&1
    fi
    if echo "${selectCustomInstallType}" | grep -q ",11," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n===================== 配置VMess+HTTPUpgrade =====================\n"
        echoContent skyBlue "\n开始配置VMess+HTTPUpgrade协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessHTTPUpgradePort}" 11 "${portKeep}")
        echoContent green "\n ---> VMess_HTTPUpgrade端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
        checkPortOpen "${result[-1]}" "${domain}"
        singBoxNginxConfig "$1" "${result[-1]}"
        bootStartup nginx
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/11_VMess_HTTPUpgrade_inbounds.json
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"127.0.0.1",
          "listen_port":31306,
          "tag":"VMessHTTPUpgrade",
          "users":$(initSingBoxClients 11),
          "transport": {
            "type": "httpupgrade",
            "path": "/${currentPath}"
          }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/11_VMess_HTTPUpgrade_inbounds.json >/dev/null 2>&1
    fi

    if echo "${selectCustomInstallType}" | grep -q ",13," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 AnyTLS ==================\n"
        echoContent skyBlue "\n开始配置AnyTLS协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxAnyTLSPort}" 13 "${portKeep}")
        echoContent green "\n ---> AnyTLS端口：${result[-1]}"
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/13_anytls_inbounds.json
{
    "inbounds": [
        {
            "type": "anytls",
            "listen": "::",
            "tag":"anytls",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 13),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "${TLS_DIR}/${sslDomain}.crt",
                "key_path": "${TLS_DIR}/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/13_anytls_inbounds.json >/dev/null 2>&1
    fi

    # Shadowsocks 2022
    if echo "${selectCustomInstallType}" | grep -q ",14," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== 配置 Shadowsocks 2022 ==================\n"
        echoContent skyBlue "\n开始配置Shadowsocks 2022协议"
        echo
        initSS2022Config
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/14_ss2022_inbounds.json
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "listen": "::",
            "tag": "ss2022-in",
            "listen_port": ${ss2022Port},
            "method": "${ss2022Method}",
            "password": "${ss2022ServerKey}",
            "users": $(initSingBoxClients 14),
            "multiplex": {
                "enabled": true
            }
        }
    ]
}
EOF
        echoContent green " ---> Shadowsocks 2022配置完成"
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/14_ss2022_inbounds.json >/dev/null 2>&1
    fi

    # ShadowTLS v3 + SS2022
    if echo "${selectCustomInstallType}" | grep -q ",16," || [[ "$1" == "all" ]]; then
        echoContent yellow "\n================== $(t CONFIG_PROTOCOL_TITLE "ShadowTLS+SS2022") ==================\n"
        mapfile -t result < <(initSingBoxPort "${singBoxShadowTlsPort}" 16 "${portKeep}")
        echoContent green "\n ---> ShadowTLS端口：${result[-1]}"
        initShadowTlsConfig
        jsonWriteFile "${SINGBOX_FRAGMENT_DIR}/16_shadowtls_inbounds.json" \
            "$(shadowTlsWithInnerUsers "$(shadowTlsInbound "${result[-1]}" "${shadowTlsTarget}" "${shadowTlsServerKey}" "$(initSingBoxClients 16)")")" false
    elif [[ -z "${3:-}" ]]; then
        rm ${SINGBOX_FRAGMENT_DIR}/16_shadowtls_inbounds.json >/dev/null 2>&1
    fi

    if [[ -z "${3:-}" ]]; then
        removeSingBoxConfig wireguard_endpoints_IPv4_route
        removeSingBoxConfig wireguard_endpoints_IPv6_route
        removeSingBoxConfig wireguard_endpoints_IPv4
        removeSingBoxConfig wireguard_endpoints_IPv6

        removeSingBoxConfig IPv4_out
        removeSingBoxConfig IPv6_out
        removeSingBoxConfig IPv6_route
        removeSingBoxConfig block
        removeSingBoxConfig cn_block_outbound
        removeSingBoxConfig cn_block_route
        removeSingBoxConfig 01_direct_outbound
        removeSingBoxConfig socks5_outbound.json
        removeSingBoxConfig block_domain_outbound
        removeSingBoxConfig dns

        # 确保基础 direct 出站存在，sing-box 需要至少一个默认出站
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json
{
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
    fi
}
# 初始化 sing-box订阅配置
initSubscribeLocalConfig() {
    rm -rf ${SUBSCRIBE_LOCAL_DIR}/sing-box/*
}
# shareQrCode TITLE LINK → 在终端里画分享链接的二维码。只在本机生成：链接含 UUID，交给第三方网站就是把凭据发出去。
# stdout 不是终端（订阅重建把账号输出丢进 /dev/null，每个成员每个协议画一遍是白耗）或没有 qrencode 时什么都不打
shareQrCode() {
    [[ -t 1 ]] && command -v qrencode >/dev/null 2>&1 || return 0
    [[ -n "$1" ]] && echoContent yellow "$1"
    printf '%s' "$2" | qrencode -m 1 -t UTF8
}

# 通用
defaultBase64Code() {
    local type=$1
    local port=$2
    local email=$3
    local id=$4
    local add=$5
    local path=$6
    local user=
    user=$(echo "${email}" | awk -F "[-]" '{print $1}')
    if [[ ! -f "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}" ]]; then
        echo [] >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"
    fi
    local singBoxSubscribeLocalConfig=
    if [[ "${type}" == "vlesstcp" ]]; then

        echoContent yellow " ---> 通用格式(VLESS+TCP+TLS_Vision)"
        echoContent green "    vless://${id}@${currentHost}:${port}?encryption=none&security=tls&fp=chrome&type=tcp&host=${currentHost}&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+TCP+TLS_Vision)"
        echoContent green "协议类型:VLESS，地址:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，client-fingerprint: chrome，传输方式:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
vless://${id}@${currentHost}:${port}?encryption=none&security=tls&type=tcp&host=${currentHost}&fp=chrome&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}
EOF
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${currentHost}
    port: ${port}
    uuid: ${id}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    client-fingerprint: chrome
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${currentHost}\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"xudp\"}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 VLESS(VLESS+TCP+TLS_Vision)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "vmessws" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 | tr -d '\n')
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+WS+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> 通用vmess(VMess+WS+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
vmess://${qrCodeBase64Default}
EOF
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vmess
    server: ${add}
    port: ${port}
    uuid: ${id}
    alterId: 0
    cipher: none
    udp: true
    tls: true
    client-fingerprint: chrome
    servername: ${currentHost}
    network: ws
    ws-opts:
      path: ${path}
      headers:
        Host: ${currentHost}
EOF
        # xudp 两种服务端都认；packetaddr 只有 sing-box 认，Xray 上 UDP 全丢
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"max_early_data\":2048,\"early_data_header_name\":\"Sec-WebSocket-Protocol\"}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")

        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 vmess(VMess+WS+TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "vlessws" ]]; then

        echoContent yellow " ---> 通用格式(VLESS+WS+TLS)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+WS+TLS)"
        echoContent green "    协议类型:VLESS，地址:${add}，伪装域名/SNI:${currentHost}，端口:${port}，client-fingerprint: chrome,用户ID:${id}，安全:tls，传输方式:ws，路径:${path}，账户名:${email}\n"

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}
EOF
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: ws
    client-fingerprint: chrome
    servername: ${currentHost}
    ws-opts:
      path: ${path}
      headers:
        Host: ${currentHost}
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"headers\":{\"Host\":\"${currentHost}\"}}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 VLESS(VLESS+WS+TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "vlessXHTTP" ]]; then
        local pqvParam pqvParamQr
        pqvParam=$(realityPqvParam "${currentRealityMldsa65Verify}")
        pqvParamQr=$(realityPqvParam "${currentRealityMldsa65Verify}" qr)

        echoContent yellow " ---> 通用格式(VLESS+reality+XHTTP)"
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality${pqvParam}&type=xhttp&sni=${xrayVLESSRealityXHTTPServerName}&host=${xrayVLESSRealityXHTTPServerName}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=${currentRealityXHTTPShortId}#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+XHTTP)"
        echoContent green "协议类型:VLESS reality，地址:$(getPublicIP)，publicKey:${currentRealityXHTTPPublicKey}，shortId: ${currentRealityXHTTPShortId}${currentRealityMldsa65Verify:+，pqv=${currentRealityMldsa65Verify}}，serverNames：${xrayVLESSRealityXHTTPServerName}，端口:${port}，路径：${path}，SNI:${xrayVLESSRealityXHTTPServerName}，伪装域名:${xrayVLESSRealityXHTTPServerName}，用户ID:${id}，传输方式:xhttp，账户名:${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality${pqvParam}&type=xhttp&sni=${xrayVLESSRealityXHTTPServerName}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=${currentRealityXHTTPShortId}#${email}
EOF

        # clashMeta（mihomo）订阅：reality-opts 必须含 publicKey + shortId，否则 clashMeta 客户端连不上 Reality；
        # support-x25519mlkem768 不写时 mihomo 会剥掉 ML-KEM 份额，Xray ≥ 26.9.9 的 Reality 按认证失败处理。
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: $(getPublicIP)
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: xhttp
    client-fingerprint: chrome
    alpn:
      - h2
    servername: ${xrayVLESSRealityXHTTPServerName}
    reality-opts:
      public-key: ${currentRealityXHTTPPublicKey}
      short-id: ${currentRealityXHTTPShortId}
      support-x25519mlkem768: true
    xhttp-opts:
      path: ${path}
      host: ${xrayVLESSRealityXHTTPServerName}
EOF

        shareQrCode " ---> 二维码 VLESS(VLESS+reality+XHTTP)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "vlessXHTTPTLS" ]]; then
        local xhttpTlsLink="vless://${id}@${add}:${port}?encryption=none&security=tls&type=xhttp&mode=auto&host=${currentHost}&sni=${currentHost}&fp=chrome&alpn=h2&path=${path}#${email}"
        echoContent yellow " ---> $(t ACCOUNT_LINK_XHTTP_TLS)"
        echoContent green "    ${xhttpTlsLink}\n"

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
${xhttpTlsLink}
EOF
        # 不进 sing-box 订阅：官方 sing-box 没有 XHTTP
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: xhttp
    client-fingerprint: chrome
    alpn:
      - h2
    servername: ${currentHost}
    xhttp-opts:
      path: ${path}
      host: ${currentHost}
EOF

        shareQrCode " ---> $(t ACCOUNT_QR_XHTTP_TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "trojan" ]]; then
        # URLEncode
        echoContent yellow " ---> Trojan(TLS)"
        echoContent green "    trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${currentHost}_Trojan\n"

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${email}_Trojan
EOF

        # Xray 的 443 把 ALPN 为 h2 的连接回落给 nginx，mihomo 带 TLS 指纹时不理会 alpn、总报 h2：进了 Clash 订阅也连不上，
        # 所以只在 sing-box 内核（Trojan 自带 TLS、没有回落）上进订阅，Xray 上打印一段去掉指纹的配置供测试
        if [[ "${coreKind}" == "1" ]]; then
            echoContent yellow " ---> $(t ACCOUNT_TROJAN_CLASH_TEST_ONLY)"
            echoContent green "  - name: \"${email}\"\n    type: trojan\n    server: ${currentHost}\n    port: ${port}\n    password: ${id}\n    udp: true\n    sni: ${currentHost}\n    alpn:\n      - http/1.1\n"
        else
            cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: trojan
    server: ${currentHost}
    port: ${port}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
EOF
        fi
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${currentHost}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"alpn\":[\"http/1.1\"],\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 Trojan(TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "hysteria" ]]; then
        echoContent yellow " ---> Hysteria(TLS)"
        local clashMetaPortContent="port: ${port}"
        local multiPort=
        local multiPortEncode
        local singBoxPorts=
        if echo "${port}" | grep -q "-"; then
            clashMetaPortContent="ports: ${port}"
            multiPort="mport=${port}&"
            multiPortEncode="mport%3D${port}%26"
            # sing-box 的区间写 a:b；不写 server_ports 的话 sing-box 系客户端只连固定端口，开了跳跃也不跳
            singBoxPorts=",\"server_ports\":[\"${port/-/:}\"]"
        fi

        # 构建obfs参数（密码按上下文做编码，避免特殊字符破坏 URL/JSON）
        local obfsUrlParam=""
        local obfsUrlParamEncode=""
        local clashMetaObfs=""
        local singBoxObfs=""
        if [[ -n "${hysteria2ObfsPassword}" ]]; then
            local _obfsPwUriEnc _obfsPwQrEnc _obfsPwJson
            # 第一层 percent-encode（jq @uri，RFC 3986 query）：用于 hysteria2:// URL 的 query。
            # 客户端 URL-decode 还原回原始密码；密码含 & = # 等保留字符时不能裸塞 URL。
            _obfsPwUriEnc=$(printf '%s' "${hysteria2ObfsPassword}" | jq -sRr @uri)
            # 第二层 percent-encode（再过一遍 @uri，等价于把 % 都变 %25）：
            # 用于 QR API ?data= 参数 —— 整个 hysteria2:// URL 嵌入 data= 时
            # 需要再编码一次，否则 password 里的 % 会被外层 URL 解析误吃。
            _obfsPwQrEnc=$(printf '%s' "${_obfsPwUriEnc}" | jq -sRr @uri)
            # JSON string literal：用于 sing-box 订阅 JSON 片段（与 4925/5760 同款）
            _obfsPwJson=$(printf '%s' "${hysteria2ObfsPassword}" | jq -Rs '.')

            local obfsType=${hysteria2ObfsType:-salamander}
            obfsUrlParam="obfs=${obfsType}&obfs-password=${_obfsPwUriEnc}&"
            obfsUrlParamEncode="obfs%3D${obfsType}%26obfs-password%3D${_obfsPwQrEnc}%26"
            # 加引号：裸写时 true / null / 纯数字这类合法密码会被 YAML 读成布尔、空或整数（字符集已排除引号与反斜杠）
            clashMetaObfs="    obfs: ${obfsType}
    obfs-password: \"${hysteria2ObfsPassword}\""
            singBoxObfs=',"obfs":{"type":"'"${obfsType}"'","password":'"${_obfsPwJson}"'}'
        fi

        # 只有 Brutal 才把带宽发给客户端；BBR 的配置不写带宽，客户端没有带宽就走 BBR
        local clashMetaBandwidth= singBoxBandwidth=
        if [[ -n "${hysteria2ClientDownloadSpeed}" ]]; then
            clashMetaBandwidth="    up: \"${hysteria2ClientUploadSpeed} Mbps\"
    down: \"${hysteria2ClientDownloadSpeed} Mbps\""
            singBoxBandwidth=",\"up_mbps\":${hysteria2ClientUploadSpeed},\"down_mbps\":${hysteria2ClientDownloadSpeed}"
        fi

        echoContent green "    hysteria2://${id}@${currentHost}:${singBoxHysteria2Port}?${multiPort}${obfsUrlParam}peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
hysteria2://${id}@${currentHost}:${singBoxHysteria2Port}?${multiPort}${obfsUrlParam}peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}
EOF
        echoContent yellow " ---> v2rayN(hysteria+TLS)"
        # 官方客户端格式：混淆按类型再嵌一层；少了它，开着混淆的服务端一个包都不认
        jq -n --arg server "${currentHost}:${port}" --arg auth "${id}" --arg sni "${currentHost}" \
            --arg obfsType "${hysteria2ObfsPassword:+${hysteria2ObfsType:-salamander}}" --arg obfsPw "${hysteria2ObfsPassword}" \
            --arg up "${hysteria2ClientUploadSpeed}" --arg down "${hysteria2ClientDownloadSpeed}" \
            '{server: $server, socks5: {listen: "127.0.0.1:7798", timeout: 300}, auth: $auth, tls: {sni: $sni}}
            + (if $obfsType == "" then {} else {obfs: {type: $obfsType, ($obfsType): {password: $obfsPw}}} end)
            + (if $down == "" then {} else {bandwidth: {up: "\($up) mbps", down: "\($down) mbps"}} end)'

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: hysteria2
    server: ${currentHost}
    ${clashMetaPortContent}
    password: ${id}
    alpn:
        - h3
    sni: ${currentHost}
${clashMetaBandwidth}
${clashMetaObfs}
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"hysteria2\",\"server\":\"${currentHost}\",\"server_port\":${singBoxHysteria2Port}${singBoxPorts}${singBoxBandwidth},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"alpn\":[\"h3\"]}${singBoxObfs}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 Hysteria2(TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "vlessReality" ]]; then
        local realityServerName=${xrayVLESSRealityServerName}
        local publicKey=${currentRealityPublicKey}
        local pqvParam pqvParamQr
        pqvParam=$(realityPqvParam "${currentRealityMldsa65Verify}")
        pqvParamQr=$(realityPqvParam "${currentRealityMldsa65Verify}" qr)

        if [[ "${coreKind}" == "2" ]]; then
            realityServerName=${singBoxVLESSRealityVisionServerName}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi
        echoContent yellow " ---> 通用格式(VLESS+reality+uTLS+Vision)"
        echoContent green "    vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality${pqvParam}&type=tcp&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=${currentRealityShortId}&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+uTLS+Vision)"
        echoContent green "协议类型:VLESS reality，地址:$(getPublicIP)，publicKey:${publicKey}，shortId: ${currentRealityShortId}${currentRealityMldsa65Verify:+，pqv=${currentRealityMldsa65Verify}}，serverNames：${realityServerName}，端口:${port}，用户ID:${id}，传输方式:tcp，账户名:${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
vless://${id}@$(getPublicIP):${port}?encryption=none&security=reality${pqvParam}&type=tcp&sni=${realityServerName}&fp=chrome&pbk=${publicKey}&sid=${currentRealityShortId}&flow=xtls-rprx-vision#${email}
EOF
        # support-x25519mlkem768 不写时 mihomo 会剥掉 ML-KEM 份额，Xray ≥ 26.9.9 的 Reality 按认证失败处理
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: $(getPublicIP)
    port: ${port}
    uuid: ${id}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${realityServerName}
    reality-opts:
      public-key: ${publicKey}
      short-id: ${currentRealityShortId}
      support-x25519mlkem768: true
    client-fingerprint: chrome
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"$(getPublicIP)\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${realityServerName}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"${currentRealityShortId}\"}},\"packet_encoding\":\"xudp\"}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 VLESS(VLESS+reality+uTLS+Vision)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "tuic" ]]; then
        local tuicUUID=
        tuicUUID=$(echo "${id}" | awk -F "[_]" '{print $1}')

        local tuicPassword=
        tuicPassword=$(echo "${id}" | awk -F "[_]" '{print $2}')

        if [[ -z "${email}" ]]; then
            echoContent red " ---> 读取配置失败，请重新安装"
            exit 1
        fi

        echoContent yellow " ---> 格式化明文(Tuic+TLS)"
        echoContent green "    协议类型:Tuic，地址:${currentHost}，端口：${port}，uuid：${tuicUUID}，password：${tuicPassword}，congestion-controller:${tuicAlgorithm}，alpn: h3，账户名:${email}\n"

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
tuic://${tuicUUID}:${tuicPassword}@${currentHost}:${port}?congestion_control=${tuicAlgorithm}&alpn=h3&sni=${currentHost}&udp_relay_mode=quic&allow_insecure=0#${email}
EOF
        echoContent yellow " ---> v2rayN(Tuic+TLS)"
        echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    server: ${currentHost}
    type: tuic
    port: ${port}
    uuid: ${tuicUUID}
    password: ${tuicPassword}
    alpn:
     - h3
    congestion-controller: ${tuicAlgorithm}
    reduce-rtt: true
    sni: ${currentHost}
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\": \"tuic\",\"server\": \"${currentHost}\",\"server_port\": ${port},\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"congestion_control\": \"${tuicAlgorithm}\",\"tls\": {\"enabled\": true,\"server_name\": \"${currentHost}\",\"alpn\": [\"h3\"]}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode "\n ---> 二维码 Tuic" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"
    elif [[ "${type}" == "naive" ]]; then
        echoContent yellow " ---> Naive(TLS)"

        echoContent green "    naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}
EOF
        # udp_over_tcp 不能省：naive 出站默认不带 UDP，TUN 下选中这个节点时 UDP 全断。sing-box 1.13 以下不认 naive 类型，整份订阅加载失败，用户指南写明
        singBoxSubscribeLocalConfig=$(jq --arg tag "${email}" --arg host "${currentHost}" --argjson port "${port}" --arg pw "${id}" \
            '. + [{tag: $tag, type: "naive", server: $host, server_port: $port, username: $tag, password: $pw, udp_over_tcp: true, tls: {enabled: true, server_name: $host}}]' "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"
        shareQrCode " ---> 二维码 Naive(TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"
    elif [[ "${type}" == "vmessHTTPUpgrade" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 | tr -d '\n')
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+HTTPUpgrade+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> 通用vmess(VMess+HTTPUpgrade+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"

        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
vmess://${qrCodeBase64Default}
EOF
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: vmess
    server: ${add}
    port: ${port}
    uuid: ${id}
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    client-fingerprint: chrome
    servername: ${currentHost}
    network: ws
    ws-opts:
     path: ${path}
     headers:
       Host: ${currentHost}
     v2ray-http-upgrade: true
EOF
        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"security\":\"auto\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"httpupgrade\",\"path\":\"${path}\"}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")

        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 vmess(VMess+HTTPUpgrade+TLS)" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "anytls" ]]; then
        echoContent yellow " ---> AnyTLS"

        echoContent yellow " ---> 格式化明文(AnyTLS)"
        echoContent green "协议类型:anytls，地址:${currentHost}，端口:${singBoxAnyTLSPort}，用户ID:${id}，传输方式:tcp，账户名:${email}\n"

        echoContent green "    anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}
EOF
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: anytls
    port: ${singBoxAnyTLSPort}
    server: ${currentHost}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
    alpn:
      - h2
      - http/1.1
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"anytls\",\"server\":\"${currentHost}\",\"server_port\":${singBoxAnyTLSPort},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\"}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 AnyTLS" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "ss2022" ]]; then
        local ss2022ServerKey=$5
        local ss2022Method=$6
        # SS2022 无域名，服务器地址取公网 IP（取一次复用，避免 getPublicIP 多次外网探测）
        local ss2022ServerAddr; ss2022ServerAddr=$(getPublicIP)
        # SS2022 密码格式: serverKey:userKey
        local ss2022Password="${ss2022ServerKey}:${id}"
        local ss2022PasswordBase64
        ss2022PasswordBase64=$(echo -n "${ss2022Password}" | base64 | tr -d '\n')

        echoContent yellow " ---> Shadowsocks 2022"

        echoContent yellow " ---> 格式化明文(SS2022)"
        echoContent green "协议类型:ss2022，地址:${ss2022ServerAddr}，端口:${port}，加密方式:${ss2022Method}，密码:${ss2022Password}，账户名:${email}\n"

        # SIP002 URL格式: ss://BASE64(method:password)@host:port#name
        local ss2022UrlPassword
        ss2022UrlPassword=$(echo -n "${ss2022Method}:${ss2022Password}" | base64 | tr -d '\n')
        echoContent green "    ss://${ss2022UrlPassword}@${ss2022ServerAddr}:${port}#${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/default/${user}"
ss://${ss2022UrlPassword}@${ss2022ServerAddr}:${port}#${email}
EOF
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: ss
    server: ${ss2022ServerAddr}
    port: ${port}
    cipher: ${ss2022Method}
    password: "${ss2022Password}"
    udp: true
EOF

        singBoxSubscribeLocalConfig=$(jq -r ". += [{\"tag\":\"${email}\",\"type\":\"shadowsocks\",\"server\":\"${ss2022ServerAddr}\",\"server_port\":${port},\"method\":\"${ss2022Method}\",\"password\":\"${ss2022Password}\",\"multiplex\":{\"enabled\":true}}]" "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"

        shareQrCode " ---> 二维码 SS2022" "$(tail -n 1 "${SUBSCRIBE_LOCAL_DIR}/default/${user}")"

    elif [[ "${type}" == "shadowtls" ]]; then
        # 4=外层密码 5=内层 uPSK 6=内层服务端密钥 7=握手目标（也是客户端 SNI）
        local stUserKey=$5 stServerKey=$6 stSni=$7 stAddr stMethod="2022-blake3-aes-128-gcm"
        stAddr=$(getPublicIP)
        local stPassword="${stServerKey}:${stUserKey}"
        echoContent yellow " ---> $(t ACCOUNT_SHADOWTLS_PLAIN_TITLE)"
        echoContent green "    $(t ACCOUNT_SHADOWTLS_PLAIN "${stAddr}" "${port}" "${stMethod}" "${stPassword}" "${id}" "${stSni}" "${email}")\n"
        # 不写通用订阅、不画二维码：v2rayN、mihomo 的链接解析器不认 shadow-tls，会静默丢掉 plugin，把全加密的裸 SS2022 发到这个端口
        echoContent yellow " ---> $(t ACCOUNT_SHADOWTLS_LINK_WARN)"
        echoContent green "    ss://$(echo -n "${stMethod}:${stPassword}" | base64 | tr -d '\n')@${stAddr}:${port}/?plugin=shadow-tls%3Bhost%3D${stSni}%3Bpassword%3D${id}%3Bversion%3D3#${email}\n"
        cat <<EOF >>"${SUBSCRIBE_LOCAL_DIR}/clashMeta/${user}"
  - name: "${email}"
    type: ss
    server: ${stAddr}
    port: ${port}
    cipher: ${stMethod}
    password: "${stPassword}"
    udp: true
    client-fingerprint: chrome
    plugin: shadow-tls
    plugin-opts:
      host: ${stSni}
      password: "${id}"
      version: 3
    smux:
      enabled: true
      protocol: h2mux
EOF
        singBoxSubscribeLocalConfig=$(jq --arg tag "${email}" --arg addr "${stAddr}" --argjson port "${port}" --arg method "${stMethod}" --arg pw "${stPassword}" \
            --arg stPw "${id}" --arg sni "${stSni}" '. + [{tag: $tag, type: "shadowsocks", method: $method, password: $pw, detour: ("st-" + $tag), multiplex: {enabled: true}},
                {tag: ("st-" + $tag), type: "shadowtls", server: $addr, server_port: $port, version: 3, password: $stPw,
                 tls: {enabled: true, server_name: $sni, utls: {enabled: true, fingerprint: "chrome"}}}]' "${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}")
        echo "${singBoxSubscribeLocalConfig}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${user}"
    fi

}

# Reality 订阅端口按内核取：两个端口变量各自只在自己内核的读取路径里赋值，同一会话
# 切换内核后旧值残留，拼接在一起就成了 443443
getRealitySubscriptionPort() {
    if [[ "${coreKind}" == "2" ]]; then
        printf '%s\n' "${singBoxVLESSRealityVisionPort}"
    else
        printf '%s\n' "${xrayVLESSRealityVisionPort}"
    fi
}

# 账号
showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readSingBoxConfig
    # 下面的 $(getPublicIP) 都在子 shell 里，缓存写不回来；在本 shell 先取一次，它们才都命中缓存，不再各打一轮外网
    getPublicIP >/dev/null 2>&1

    echo
    echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"

    initSubscribeLocalConfig
    # VLESS TCP
    if echo ${currentInstallProtocolType} | grep -q ",0,"; then

        echoContent skyBlue "============================= VLESS TCP TLS_Vision [推荐] ==============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}02_VLESS_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            defaultBase64Code vlesstcp "${currentDefaultPort}${singBoxVLESSVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi

    # VLESS WS
    if echo ${currentInstallProtocolType} | grep -q ",1,"; then
        echoContent skyBlue "\n================================ VLESS WS TLS [仅CDN推荐] ================================\n"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}03_VLESS_WS_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vlessWSPort=${currentDefaultPort}
            if [[ "${coreKind}" == "2" ]]; then
                vlessWSPort="${singBoxVLESSWSPort}"
            fi
            echo
            local path="${currentPath}ws"

            if [[ ${coreKind} == "1" ]]; then
                path="/${currentPath}ws"
            elif [[ "${coreKind}" == "2" ]]; then
                path="${singBoxVLESSWSPath}"
            fi

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessws "${vlessWSPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # trojan grpc - 已移除

    # VMess WS
    if echo ${currentInstallProtocolType} | grep -q ",3,"; then
        echoContent skyBlue "\n================================ $(t ACCOUNT_TITLE_VMESS_WS) ================================\n"
        local path="${currentPath}vws"
        if [[ ${coreKind} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreKind}" == "2" ]]; then
            path="${singBoxVMessWSPath}"
        fi
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}05_VMess_WS_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vmessPort=${currentDefaultPort}
            if [[ "${coreKind}" == "2" ]]; then
                vmessPort="${singBoxVMessWSPort}"
            fi

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessws "${vmessPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi

    # trojan tcp
    if echo ${currentInstallProtocolType} | grep -q ",4,"; then
        echoContent skyBlue "\n================================== $(t ACCOUNT_TITLE_TROJAN) ==================================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echoContent skyBlue "\n ---> 账号:${email}"

            defaultBase64Code trojan "${currentDefaultPort}${singBoxTrojanPort}" "${email}" "$(echo "${user}" | jq -r .password)"
        done
    fi
    # VLESS grpc - 已移除

    # hysteria2
    if echo ${currentInstallProtocolType} | grep -q ",6," || [[ -n "${hysteriaPort}" ]]; then
        readPortHopping "hysteria2" "${singBoxHysteria2Port}"
        echoContent skyBlue "\n================================  Hysteria2 TLS [推荐] ================================\n"
        local path="${configPath}"
        if [[ "${coreKind}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        local hysteria2DefaultPort=
        if [[ -n "${hysteria2PortHoppingStart}" && -n "${hysteria2PortHoppingEnd}" ]]; then
            hysteria2DefaultPort="${hysteria2PortHopping}"
        else
            hysteria2DefaultPort=${singBoxHysteria2Port}
        fi

        jq -r -c '.inbounds[]|.users[]' "${path}06_hysteria2_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code hysteria "${hysteria2DefaultPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # VLESS reality vision
    if echo ${currentInstallProtocolType} | grep -q ",7,"; then
        echoContent skyBlue "============================= VLESS reality_vision [推荐]  ==============================\n"
        jq .inbounds[1].settings.clients//.inbounds[0].users ${configPath}07_VLESS_vision_reality_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            defaultBase64Code vlessReality "$(getRealitySubscriptionPort)" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # VLESS reality gRPC - 已移除

    # tuic
    if echo ${currentInstallProtocolType} | grep -q ",9," || [[ -n "${tuicPort}" ]]; then
        echoContent skyBlue "\n================================  Tuic TLS [推荐]  ================================\n"
        local path="${configPath}"
        if [[ "${coreKind}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[].users[]' "${path}09_tuic_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code tuic "${singBoxTuicPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .uuid)_$(echo "${user}" | jq -r .password)"
        done

    fi
    # naive
    if echo ${currentInstallProtocolType} | grep -q ",10," || [[ -n "${singBoxNaivePort}" ]]; then
        echoContent skyBlue "\n================================  naive TLS [推荐，不支持ClashMeta]  ================================\n"
        local path="${configPath}"
        if [[ "${coreKind}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[]|.users[]' "${path}10_naive_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .username)"
            echo
            defaultBase64Code naive "${singBoxNaivePort}" "$(echo "${user}" | jq -r .username)" "$(echo "${user}" | jq -r .password)"
        done

    fi
    # VMess HTTPUpgrade
    if echo ${currentInstallProtocolType} | grep -q ",11,"; then
        echoContent skyBlue "\n================================ $(t ACCOUNT_TITLE_VMESS_HTTPUPGRADE) ================================\n"
        local path="${currentPath}vws"
        if [[ ${coreKind} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreKind}" == "2" ]]; then
            path="${singBoxVMessHTTPUpgradePath}"
        fi
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}11_VMess_HTTPUpgrade_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vmessHTTPUpgradePort=${currentDefaultPort}
            if [[ "${coreKind}" == "2" ]]; then
                vmessHTTPUpgradePort="${singBoxVMessHTTPUpgradePort}"
            fi

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessHTTPUpgrade "${vmessHTTPUpgradePort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # VLESS Reality XHTTP
    if echo ${currentInstallProtocolType} | grep -q ",12,"; then
        echoContent skyBlue "\n================================ VLESS Reality XHTTP ================================\n"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}12_VLESS_XHTTP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echo
            local path="${currentPath}xHTTP"

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessXHTTP "${xrayVLESSRealityXHTTPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # VLESS XHTTP TLS
    if echo ${currentInstallProtocolType} | grep -q ",15,"; then
        echoContent skyBlue "\n================================ $(t ACCOUNT_TITLE_XHTTP_TLS) ================================\n"
        jq -c '.inbounds[0].settings.clients[]' "${configPath}15_VLESS_XHTTP_TLS_inbounds.json" | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email)

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessXHTTPTLS "${currentDefaultPort}" "${email}${count}" "$(echo "${user}" | jq -r .id)" "${line}" "/${currentPath}xhttp"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # AnyTLS
    if echo ${currentInstallProtocolType} | grep -q ",13,"; then
        echoContent skyBlue "\n================================  AnyTLS ================================\n"

        jq -r -c '.inbounds[]|.users[]' "${configPath}13_anytls_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code anytls "${singBoxAnyTLSPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # Shadowsocks 2022
    if echo ${currentInstallProtocolType} | grep -q ",14," || [[ -n "${ss2022Port}" ]]; then
        echoContent skyBlue "\n================================  Shadowsocks 2022 ================================\n"
        local path="${singBoxConfigPath}"
        if [[ -f "${path}14_ss2022_inbounds.json" ]]; then
            local serverKey
            local method
            serverKey=$(jq -r '.inbounds[0].password' "${path}14_ss2022_inbounds.json")
            method=$(jq -r '.inbounds[0].method' "${path}14_ss2022_inbounds.json")
            local port
            port=$(jq -r '.inbounds[0].listen_port' "${path}14_ss2022_inbounds.json")

            jq -r -c '.inbounds[]|.users[]' "${path}14_ss2022_inbounds.json" | while read -r user; do
                echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
                echo
                defaultBase64Code ss2022 "${port}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)" "${serverKey}" "${method}"
            done
        fi
    fi
    # ShadowTLS v3 + SS2022
    if echo ${currentInstallProtocolType} | grep -q ",16,"; then
        echoContent skyBlue "\n================================ $(t ACCOUNT_TITLE_SHADOWTLS) ================================\n"
        local stFile="${configPath}16_shadowtls_inbounds.json" stName stPw stKey
        jq -r '(.inbounds[1].users | map({(.name): .password}) | add) as $inner | .inbounds[0].users[] | [.name, .password, $inner[.name]] | @tsv' "${stFile}" |
            while IFS=$'\t' read -r stName stPw stKey; do
                echoContent skyBlue "\n ---> 账号:${stName}"
                echo
                defaultBase64Code shadowtls "$(jq -r '.inbounds[0].listen_port' "${stFile}")" "${stName}" "${stPw}" "${stKey}" \
                    "$(jq -r '.inbounds[1].password' "${stFile}")" "$(jq -r '.inbounds[0].handshake.server' "${stFile}")"
            done
    fi
}
# 移除nginx302配置
removeNginx302() {
    local count=
    grep -n "return 302" <"${nginxConfigPath}alone.conf" | while read -r line; do

        if ! echo "${line}" | grep -q "request_uri"; then
            local removeIndex=
            removeIndex=$(echo "${line}" | awk -F "[:]" '{print $1}')
            removeIndex=$((removeIndex + count))
            sed -i "${removeIndex}d" ${nginxConfigPath}alone.conf
            count=$((count - 1))
        fi
    done
}

# 检查302是否成功
checkNginx302() {
    local domain302Status=
    domain302Status=$(curl -s "https://${currentHost}:${currentPort}")
    if echo "${domain302Status}" | grep -q "302"; then
        echoContent green " ---> 302重定向设置完毕"
        return 0
    fi
    echoContent red " ---> 302重定向设置失败，请仔细检查是否和示例相同"
    backupNginxConfig restoreBackup
    return 1
}

# 备份恢复nginx文件
backupNginxConfig() {
    if [[ "$1" == "backup" ]]; then
        cp ${nginxConfigPath}alone.conf ${PROXY_AGENT_DIR}/alone_backup.conf
        echoContent green " ---> nginx配置文件备份成功"
    fi

    if [[ "$1" == "restoreBackup" ]] && [[ -f "${PROXY_AGENT_DIR}/alone_backup.conf" ]]; then
        cp ${PROXY_AGENT_DIR}/alone_backup.conf ${nginxConfigPath}alone.conf
        echoContent green " ---> nginx配置文件恢复备份成功"
        rm ${PROXY_AGENT_DIR}/alone_backup.conf
    fi

}
# 添加302配置
addNginx302() {

    local count=1
    grep -n "location / {" <"${nginxConfigPath}alone.conf" | while read -r line; do
        if [[ -n "${line}" ]]; then
            local insertIndex=
            insertIndex="$(echo "${line}" | awk -F "[:]" '{print $1}')"
            insertIndex=$((insertIndex + count))
            sed "${insertIndex}i return 302 '$1';" ${nginxConfigPath}alone.conf >${nginxConfigPath}tmpfile && mv ${nginxConfigPath}tmpfile ${nginxConfigPath}alone.conf
            count=$((count + 1))
        else
            echoContent red " ---> 302添加失败"
            backupNginxConfig restoreBackup
        fi

    done
}

# 更新伪装站
updateNginxBlog() {
    if [[ "${coreKind}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 1
    fi

    echoContent skyBlue "\n进度 $1/${totalProgress} : 更换伪装站点"

    if ! echo "${currentInstallProtocolType}" | grep -q ",0," || [[ -z "${coreKind}" ]]; then
        echoContent red "\n ---> 由于环境依赖，请先安装Xray-core的VLESS_TCP_TLS_Vision"
        exit 1
    fi

    # 伪装站模板列表 (来自 Lynthar/website-examples)
    local templates=("cloud-drive" "game-zone" "net-disk" "play-hub" "stream-box" "video-portal" "music-flow" "podcast-hub" "ai-forge")
    local templateNames=("云存储网站" "游戏平台" "网盘系统" "游戏中心" "流媒体平台" "视频门户" "音乐平台" "播客平台" "AI平台")
    local templateCount=${#templates[@]}
    local repoUrl="https://github.com/Lynthar/website-examples/archive/refs/heads/main.zip"
    local tempDir="/tmp/website-examples-$$"

    # 显示当前模板
    local currentTemplate=""
    if [[ -f "${nginxStaticPath}/check" ]]; then
        currentTemplate=$(cat "${nginxStaticPath}/check")
    fi

    echoContent red "=============================================================="
    echoContent yellow "# 模板来源: https://github.com/Lynthar/website-examples"
    echoContent yellow "# 如需自定义，请手动复制模版文件到 ${nginxStaticPath} \n"
    if [[ -n "${currentTemplate}" ]]; then
        echoContent green "# 当前模板: ${currentTemplate}\n"
    fi

    local i=1
    for name in "${templateNames[@]}"; do
        local marker=""
        if [[ "${templates[$((i-1))]}" == "${currentTemplate}" ]]; then
            marker=" [当前]"
        fi
        echoContent yellow "${i}.${name}${marker}"
        ((i++))
    done
    echoContent yellow "10.302重定向网站"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectInstallNginxBlogType

    if [[ "${selectInstallNginxBlogType}" == "10" ]]; then
        if [[ "${coreKind}" == "2" ]]; then
            echoContent red "\n ---> 此功能仅支持Xray-core内核，请等待后续更新"
            exit 1
        fi
        echoContent red "\n=============================================================="
        echoContent yellow "重定向的优先级更高，配置302之后如果更改伪装站点，根路由下伪装站点将不起作用"
        echoContent yellow "如想要伪装站点实现作用需删除302重定向配置\n"
        echoContent yellow "1.添加"
        echoContent yellow "2.删除"
        echoContent red "=============================================================="
        read -r -p "请选择:" redirectStatus

        if [[ "${redirectStatus}" == "1" ]]; then
            backupNginxConfig backup
            read -r -p "请输入要重定向的域名,例如 https://www.baidu.com:" redirectDomain
            if ! isValidRedirectUrl "${redirectDomain}"; then
                echoContent red " ---> URL格式无效，必须以 http:// 或 https:// 开头且不含特殊字符"
                exit 1
            fi
            removeNginx302
            addNginx302 "${redirectDomain}"
            handleNginx stop
            # 子 shell 接住 handleNginx 的退出，回滚才走得到
            if ! (handleNginx start); then
                backupNginxConfig restoreBackup
                handleNginx start
                echoContent red " ---> $(t NGINX_302_ROLLED_BACK)"
                exit 1
            fi
            checkNginx302
            exit $?
        fi
        if [[ "${redirectStatus}" == "2" ]]; then
            removeNginx302
            # 只改文件不重载的话线上照旧 302，直到下次重启 nginx
            handleNginx stop
            handleNginx start
            echoContent green " ---> 移除302重定向成功"
            exit 0
        fi
    fi

    if [[ "${selectInstallNginxBlogType}" =~ ^[1-9]$ ]]; then
        local selectedTemplate="${templates[$((selectInstallNginxBlogType - 1))]}"
        local selectedName="${templateNames[$((selectInstallNginxBlogType - 1))]}"

        echoContent yellow " ---> 正在下载模板 [${selectedName}]..."

        mkdir -p "${tempDir}"

        # 下载并解压仓库（必须先全部成功才动 nginxStaticPath，否则下载失败会清空已有伪装站留空目录）
        # 旧实现的 [[ ! -f file ]] 检查无效——wget -O 总会创建文件（即使内容为空 / HTML 错误页）
        local _wgetExit=0
        if [[ "${release}" == "alpine" ]]; then
            wget -q -O "${tempDir}/repo.zip" "${repoUrl}" || _wgetExit=$?
        else
            wget -q ${wgetShowProgressStatus} -O "${tempDir}/repo.zip" "${repoUrl}" || _wgetExit=$?
        fi
        if [[ ${_wgetExit} -ne 0 ]] || [[ ! -s "${tempDir}/repo.zip" ]]; then
            echoContent red " ---> 下载伪装站模板失败，保留现有内容不变"
            rm -rf "${tempDir}"
            exit 1
        fi
        if ! unzip -q -o "${tempDir}/repo.zip" -d "${tempDir}"; then
            echoContent red " ---> 解压伪装站模板失败，保留现有内容不变"
            rm -rf "${tempDir}"
            exit 1
        fi
        local _srcDir="${tempDir}/website-examples-main/${selectedTemplate}"
        if [[ ! -d "${_srcDir}" ]]; then
            echoContent red " ---> 模板目录缺失 ${_srcDir}，保留现有内容不变"
            rm -rf "${tempDir}"
            exit 1
        fi

        # 至此下载+解压都已通过，可以安全替换静态目录
        rm -rf "${nginxStaticPath}"*
        mkdir -p "${nginxStaticPath}"
        cp -rf "${_srcDir}/"* "${nginxStaticPath}"

        # 创建 check 标记文件
        echo "${selectedTemplate}" > "${nginxStaticPath}/check"

        # 清理临时文件
        rm -rf "${tempDir}"
        echoContent green " ---> 更换伪站成功 [${selectedName}]"
    elif [[ "${selectInstallNginxBlogType}" != "7" ]]; then
        echoContent red " ---> 选择错误，请重新选择"
        updateNginxBlog
    fi
}

# corePortTarget → 菜单 12 的附加端口该转去的本机端口：装了 0 是它的前置端口（1 / 3 / 4 都从它回落），只装 Reality 是 Reality 对外那一端；都没有返回 1
corePortTarget() {
    local file
    for file in "${XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json" "${XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json"; do
        [[ -f "${file}" ]] && jq -er '.inbounds[0].port | numbers' "${file}" 2>/dev/null && return 0
    done
    return 1
}

# ensureCorePortTargets → Xray 启动前把附加端口改指当前的主端口（Hysteria2 那份指 Hysteria2 的端口），内容相同不写：
# 它们记的是添加那一刻的端口，菜单 5 或重装换了主端口后就静默转进没人听的端口。自己就是目标端口的不动，免得转回自己
ensureCorePortTargets() {
    local file target hy want out
    target=$(corePortTarget) || return 0
    hy=$(jq -er '.inbounds[0].listen_port | numbers' "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" 2>/dev/null)
    for file in "${XRAY_CONF_DIR}"/02_dokodemodoor_inbounds_*.json; do
        [[ -f "${file}" ]] || continue
        want=${target}
        if [[ "${file##*/}" == 02_dokodemodoor_inbounds_hysteria_* ]]; then
            [[ -n "${hy}" ]] || continue
            want=${hy}
        fi
        jq -e --argjson p "${want}" '.inbounds[0].settings.port == $p or .inbounds[0].port == $p' "${file}" >/dev/null 2>&1 && continue
        out=$(jq --argjson p "${want}" '.inbounds[0].settings.port = $p' "${file}") || return 1
        jsonWriteFile "${file}" "${out}" false || return 1
    done
}

# 删掉一个附加端口的全部 dokodemo-door 片段。只删这三个精确文件名：通配 "*${port}*"
# 会让端口 2 命中 02_VLESS_TCP / 12_VLESS_XHTTP，紧随的 reloadCore 就把协议停了；
# 默认端口那份带 _default 后缀，漏掉它就是菜单里永远删不掉的那一条。
removeCorePortFiles() {
    local port="$1"
    if [[ -n "${configPath}" && -n "${port}" ]]; then
        rm -f "${configPath}02_dokodemodoor_inbounds_${port}.json" \
            "${configPath}02_dokodemodoor_inbounds_${port}_default.json" \
            "${configPath}02_dokodemodoor_inbounds_hysteria_${port}.json"
    fi
}

# 添加新端口
addCorePort() {

    if [[ "${coreKind}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 1
    fi

    echoContent skyBlue "\n功能 1/${totalProgress} : 添加新端口"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项\n"
    echoContent yellow "支持批量添加"
    echoContent yellow "不影响默认端口的使用"
    echoContent yellow "查看账号时，只会展示默认端口的账号"
    echoContent yellow "不允许有特殊字符，注意逗号的格式"
    echoContent yellow "如已安装hysteria，会同时安装hysteria新端口"
    echoContent yellow "录入示例:2053,2083,2087\n"

    echoContent yellow "1.查看已添加端口"
    echoContent yellow "2.添加端口"
    echoContent yellow "3.删除端口"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        exit 0
    elif [[ "${selectNewPortType}" == "2" ]]; then
        read -r -p "请输入端口号:" newPort
        read -r -p "请输入默认的端口号，同时会更改订阅端口以及节点端口，[回车]默认443:" defaultPort

        # defaultPort 校验：必须 1-65535 整数（空表示用默认 443）。非法直接退出，
        # 不进 find 删除阶段——避免内插非法字符干扰文件匹配。
        if [[ -n "${defaultPort}" ]] && { ! [[ "${defaultPort}" =~ ^[1-9][0-9]{0,4}$ ]] || (( defaultPort > 65535 )); }; then
            echoContent red " ---> 默认端口非法: ${defaultPort}（必须 1-65535 整数）"
            exit 1
        fi

        # 只有一个端口能带 _default 后缀；只认 dokodemo-door 片段，别的文件名里的 default 不归这里管
        if [[ -n "${defaultPort}" && -n "${configPath}" ]]; then
            find "${configPath}" -maxdepth 1 -type f -name "02_dokodemodoor_inbounds_*_default.json" -exec rm -f {} \;
        fi

        if [[ -n "${newPort}" ]]; then

            while read -r port; do
                # 端口校验：每条都要 1-65535 整数。旧实现未校验，
                # 输入 "8080,abcd,5678" 中间项会让 reloadCore 解析 JSON 失败、Xray 启不起来。
                if [[ ! "${port}" =~ ^[1-9][0-9]{0,4}$ ]] || (( port > 65535 )); then
                    echoContent yellow " ---> 跳过非法端口: ${port}"
                    continue
                fi
                removeCorePortFiles "${port}"

                local fileName=
                local hysteriaFileName=
                if [[ -n "${defaultPort}" && "${port}" == "${defaultPort}" ]]; then
                    fileName="${configPath}02_dokodemodoor_inbounds_${port}_default.json"
                else
                    fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"
                fi

                if [[ -n ${hysteriaPort} ]]; then
                    hysteriaFileName="${configPath}02_dokodemodoor_inbounds_hysteria_${port}.json"
                fi

                # 开放端口
                allowPort "${port}"
                allowPort "${port}" "udp"

                local settingsPort
                settingsPort=$(corePortTarget) || settingsPort=443

                if [[ -n ${hysteriaFileName} ]]; then
                    cat <<EOF >"${hysteriaFileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${hysteriaPort},
		"network": "udp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-hysteria-${port}"
	}
  ]
}
EOF
                fi
                cat <<EOF >"${fileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${settingsPort},
		"network": "tcp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-${port}"
	}
  ]
}
EOF
            done < <(echo "${newPort}" | tr ',' '\n')

            echoContent green " ---> 添加完毕"
            reloadCore
            addCorePort
        fi
    elif [[ "${selectNewPortType}" == "3" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        read -r -p "请输入要删除的端口编号:" portIndex
        # 编号必须是正整数：非法输入拦在匹配之外，避免元字符误匹配
        if ! [[ "${portIndex}" =~ ^[1-9][0-9]*$ ]]; then
            echoContent red "\n ---> 编号必须为正整数"
            addCorePort
            return
        fi
        local dokoConfig
        # 编号列必须整列比较。子串匹配下编号 1 会同时命中 11、21，
        # 拼出带换行的文件名，rm 报错而端口其实没删掉。
        dokoConfig=$(find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}' | awk -F ':' -v idx="${portIndex}" '$1 == idx')
        if [[ -n "${dokoConfig}" ]]; then
            removeCorePortFiles "${dokoConfig#*:}"
            reloadCore
            addCorePort
        else
            echoContent yellow "\n ---> 编号输入错误，请重新选择"
            addCorePort
        fi
    fi
}

# sshListenPorts → 一行一个 sshd 在用的端口：此刻这条连接的、在听的（Ubuntu 的 ssh.socket 下监听者可能只有 systemd，所以再问 sshd -T）
sshListenPorts() {
    [[ -n "${SSH_CONNECTION:-}" ]] && echo "${SSH_CONNECTION##* }"
    ss -ltnp 2>/dev/null | awk '/"sshd"/ {n = split($4, a, ":"); print a[n]}'
    sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'
}

# isOwnRuleOnSshPort RULE_LINE SSH_PORTS → 0 = 这条带标记的放行正是 sshd 的端口，要留着：默认拒绝的机器上收了它，SSH 就再也连不上
isOwnRuleOnSshPort() {
    local port
    port=$(sed -nE 's/.*allow ([0-9]+)\/tcp\(Proxy-agent\).*/\1/p' <<<"$1")
    [[ -n "${port}" ]] && grep -qxF "${port}" <<<"$2"
}

# removeOwnFirewallRules → 收回 allowPort 留下的放行，只认带 (Proxy-agent) 注释的（iptables、nft），sshd 在用的端口除外。
# ufw、firewalld 的放行没有标记，认不出是不是用户自己加的，不动，由 reportUninstallLeftovers 列出来
removeOwnFirewallRules() {
    local line changed= sshPorts
    sshPorts=$(sshListenPorts)
    if command -v iptables >/dev/null 2>&1; then
        # 行号降序删：升序删一条，后面的行号就前移一位
        while read -r line; do
            [[ -n "${line}" ]] || continue
            if isOwnRuleOnSshPort "${line}" "${sshPorts}"; then
                echoContent yellow " ---> $(t UNINSTALL_KEEP_SSH_RULE)"
                continue
            fi
            iptables -D INPUT "${line%% *}" && changed=true
        done < <(iptables -L INPUT -n --line-numbers 2>/dev/null | grep -F '(Proxy-agent)' | sort -rn)
        if [[ -n "${changed}" ]] && command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
    changed=
    if command -v nft >/dev/null 2>&1 && nft list chain inet filter input >/dev/null 2>&1; then
        while read -r line; do
            [[ -n "${line}" ]] || continue
            if isOwnRuleOnSshPort "${line}" "${sshPorts}"; then
                echoContent yellow " ---> $(t UNINSTALL_KEEP_SSH_RULE)"
                continue
            fi
            nft delete rule inet filter input handle "${line##* }" && changed=true
        done < <(nft -a list chain inet filter input | grep -F '(Proxy-agent)')
        if [[ -n "${changed}" ]] && systemctl is-active --quiet nftables 2>/dev/null; then
            nft list ruleset >/etc/nftables.conf
        fi
    fi
}

# reportUninstallLeftovers → 列出还留在系统里、脚本不敢删的东西（可能是用户自己的配置），只列确实存在的
reportUninstallLeftovers() {
    local lines=()
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        lines+=("$(t UNINSTALL_LEFT_UFW)")
    fi
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        lines+=("$(t UNINSTALL_LEFT_FIREWALLD)")
        if firewall-cmd --query-masquerade >/dev/null 2>&1; then
            lines+=("$(t UNINSTALL_LEFT_MASQUERADE)")
        fi
    fi
    if command -v semanage >/dev/null 2>&1 && semanage fcontext -l -C 2>/dev/null | grep -qE 'xray|sing-box'; then
        lines+=("$(t UNINSTALL_LEFT_SELINUX)")
    fi
    if [[ -f /etc/apt/sources.list.d/nginx.list || -f /etc/yum.repos.d/nginx.repo ]]; then
        lines+=("$(t UNINSTALL_LEFT_NGINX_REPO)")
    fi
    if command -v nginx >/dev/null 2>&1; then
        lines+=("$(t UNINSTALL_LEFT_NGINX)")
    fi
    [[ ${#lines[@]} -gt 0 ]] || return 0
    echoContent yellow "\n ---> $(t UNINSTALL_LEFTOVERS_TITLE)"
    local line
    for line in "${lines[@]}"; do
        echoContent yellow "     ${line}"
    done
}

# 卸载脚本
unInstall() {
    if planAction "$(t PLAN_UNINSTALL)"; then return 0; fi
    read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if ! isYesInput "${unInstallStatus}"; then
        echoContent green " ---> 放弃卸载"
        menu
        exit 0
    fi
    echoContent yellow " ---> 脚本不会删除acme相关配置，删除请手动执行 [rm -rf /root/.acme.sh]"
    handleNginx stop
    if [[ -z $(nginxPids) ]]; then
        echoContent green " ---> 停止Nginx成功"
    fi
    carpoolXrayServiceEnv off
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${coreKind}" == "1" || -f /etc/init.d/xray ]]; then
            handleXray stop
            rc-update del xray default
            rm -rf /etc/init.d/xray
            echoContent green " ---> 删除Xray开机自启完成"
        fi
        # 看服务文件而不是 singBoxConfigPath：Xray 机上链式角色起的 sing-box 不算 6 / 9，漏掉它就留下一个照常转发的进程
        if [[ "${coreKind}" == "2" || -n "${singBoxConfigPath}" || -f /etc/init.d/sing-box ]]; then
            handleSingBox stop
            rc-update del sing-box default
            rm -rf /etc/init.d/sing-box
            echoContent green " ---> 删除sing-box开机自启完成"
        fi
    else
        # 先 disable 再删单元文件：只删文件会在 multi-user.target.wants 里留下悬空的自启链接。
        # 看单元文件而不只看 coreKind：旧版从 Xray 换到 sing-box 时没撤 xray.service
        if [[ "${coreKind}" == "1" || -f /etc/systemd/system/xray.service ]]; then
            handleXray stop
            systemctl disable xray.service >/dev/null 2>&1
            rm -rf /etc/systemd/system/xray.service
            echoContent green " ---> 删除Xray开机自启完成"
        fi
        if [[ "${coreKind}" == "2" || -n "${singBoxConfigPath}" || -f /etc/systemd/system/sing-box.service ]]; then
            handleSingBox stop
            systemctl disable sing-box.service >/dev/null 2>&1
            rm -rf /etc/systemd/system/sing-box.service
            echoContent green " ---> 删除sing-box开机自启完成"
        fi
        systemctl daemon-reload >/dev/null 2>&1
    fi

    removeOwnCronEntries
    # 跳跃规则要趁片段还在时收：firewalld 的只能按片段里的目标端口认
    removeProtocolPortHopping hysteria2 "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json"
    removeProtocolPortHopping tuic "${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json"
    removeOwnFirewallRules
    rm -rf ${PROXY_AGENT_DIR}
    # 旧版本建过、从没用过的空目录
    rm -rf /tmp/Proxy-agent-tls
    rm -rf "${nginxConfigPath}alone.conf"
    rm -rf "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1
    rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
    rm -f "${nginxConfigPath}http_redirect.conf"
    rm -f "${nginxConfigPath}reality_dest.conf"

    unInstallSubscribe

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        rm -rf "${nginxStaticPath}"
        echoContent green " ---> 删除伪装网站完成"
    fi

    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
    rm -rf /usr/bin/pasly
    rm -rf /usr/sbin/pasly
    echoContent green " ---> 卸载快捷方式完成"
    echoContent green " ---> 卸载 Proxy-agent 脚本完成"
    reportUninstallLeftovers
}

# 自定义uuid
customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    echo
    if [[ -z "${currentCustomUUID}" ]]; then
        if [[ "${selectInstallType}" == "1" || "${coreKind}" == "1" ]]; then
            currentCustomUUID=$(${ctlPath} uuid)
        elif [[ "${selectInstallType}" == "2" || "${coreKind}" == "2" ]]; then
            currentCustomUUID=$(${ctlPath} generate uuid)
        fi

        echoContent yellow "uuid：${currentCustomUUID}\n"

    else
        # 格式校验：UUID v1-v5 通用 8-4-4-4-12 十六进制
        # 防止特殊字符进入 JSON 构造 / jq 过滤器 / grep 模式等下游
        if ! [[ "${currentCustomUUID}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            echoContent red " ---> UUID 格式非法，需 8-4-4-4-12 位十六进制（例：550e8400-e29b-41d4-a716-446655440000）"
            exit 1
        fi
        # 仅 Reality 安装时 frontingType 为空，回退到 frontingTypeReality（同 removeUser）
        local dupCheckFile="${frontingType:-${frontingTypeReality}}"
        local checkUUID=
        if [[ "${coreKind}" == "1" ]]; then
            # Xray 客户端字段是 id（trojan 为 password），不是 uuid——查错字段查重永远通过，
            # 而同 inbound 内重复凭据会让 Xray 拒绝启动
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" '(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]? | select((.id // .password) == $currentUUID) | .email' ${configPath}${dupCheckFile}.json 2>/dev/null)
        elif [[ "${coreKind}" == "2" ]]; then
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" '.inbounds[0].users[]? | select((.uuid // .password) == $currentUUID) | .name // .username' ${configPath}${dupCheckFile}.json 2>/dev/null)
        fi

        if [[ -n "${checkUUID}" ]]; then
            echoContent red " ---> UUID不可重复"
            exit 1
        fi
    fi
}

# 自定义email：不合法、重复或订阅键撞车就重问；重问时读不到输入（不在终端）才退出，不拿随机名顶替明确给过的名字
customUserEmail() {
    local checkEmail emailCheckFile subKeyClash usersFilter retried=
    while true; do
        if ! read -r -p "请输入合法的email，[回车]随机email:" currentCustomEmail && [[ -n "${retried}" ]]; then
            exit 1
        fi
        echo
        if [[ -z "${currentCustomEmail}" ]]; then
            currentCustomEmail="${currentCustomUUID}"
            echoContent yellow "email: ${currentCustomEmail}\n"
            return 0
        fi
        retried=1
        # 格式校验：只允许字母数字与 . _ @ + -，长度 1-64
        # 此值下游会嵌入 JSON 字符串（user.email/user.name）并经 jq 过滤器处理；
        # 禁用 " \ 空白与 shell/jq 元字符可阻断注入与 JSON 破坏
        if ! [[ "${currentCustomEmail}" =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$ ]]; then
            echoContent red " ---> email 格式非法，仅允许字母数字及 . _ @ + -，长度 1-64"
            continue
        fi
        # 存量条目形如 "<base>-<协议后缀>"，按 base 精确比对（兼容无后缀的历史条目）。
        # Xray 字段是 email 不是 name；同 inbound 内 email 重复会让 Xray 拒绝启动
        checkEmail=
        emailCheckFile="${frontingType:-${frontingTypeReality}}"
        if [[ "${coreKind}" == "1" ]]; then
            checkEmail=$(jq -r --arg currentEmail "$currentCustomEmail" '(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]? | (.email // .name) as $e | select($e == $currentEmail or ($e | sub("-[^-]*$"; "")) == $currentEmail) | $e' ${configPath}${emailCheckFile}.json 2>/dev/null)
        elif [[ "${coreKind}" == "2" ]]; then
            checkEmail=$(jq -r --arg currentEmail "$currentCustomEmail" '.inbounds[0].users[]? | (.name // .username) as $e | select($e == $currentEmail or ($e | sub("-[^-]*$"; "")) == $currentEmail) | $e' ${configPath}${emailCheckFile}.json 2>/dev/null)
        fi
        if [[ -n "${checkEmail}" ]]; then
            echoContent red " ---> email不可重复"
            continue
        fi
        # 订阅文件按名字的第一个 - 段分（与拼车同一规则）：第一段相同的两个账号共用一份订阅、互相看得到对方的凭据
        usersFilter='(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]? | (.email // .name)'
        [[ "${coreKind}" == "2" ]] && usersFilter='.inbounds[0].users[]? | (.name // .username)'
        subKeyClash=$(jq -r --arg k "${currentCustomEmail%%-*}" "[${usersFilter} | sub(\"-[^-]*\$\"; \"\") | select(split(\"-\")[0] == \$k)] | first // empty" \
            "${configPath}${emailCheckFile}.json" 2>/dev/null)
        if [[ -n "${subKeyClash}" ]]; then
            echoContent red " ---> $(t ACCOUNT_SUB_KEY_TAKEN "${currentCustomEmail}" "${subKeyClash}")"
            continue
        fi
        return 0
    done
}

# xrayConfigTest → 用 `xray run -test` 校验整个 confdir（无副作用），不过时打出前 20 行原因并返回 1；没装 Xray 或它不认 -test 时放行
xrayConfigTest() {
    local out
    [[ -f "${XRAY_BIN}" ]] && ${XRAY_BIN} help run 2>/dev/null | grep -q -- "-test" || return 0
    out=$(${XRAY_BIN} run -test -confdir "${XRAY_CONF_DIR}" 2>&1) && return 0
    head -20 <<<"${out}"
    return 1
}

# 把一次账户变更（add UUID EMAIL / delName KEY / set FILE）按协议注册表应用到全部已装协议；KEY 是去掉协议后缀的
# 账户名，按名删是因为各协议文件的用户顺序不保证一致；set 的 FILE 是 {"<协议ID>": [clients…]}，只写里面有的协议，
# 空数组合法（能否启动由内核校验兜底）。全程 jsonTx 事务：任一文件写失败即整体回滚；落盘后、reload 前过内核级校验。
applyAccountChangeAllProtocols() {
    local action=$1
    local arg1=$2
    local arg2=$3

    if [[ "${action}" != "add" && "${action}" != "delName" && "${action}" != "set" ]]; then
        echoContent red " ---> $(t ACCOUNT_TX_BAD_ACTION "${action}")"
        return 1
    fi
    if [[ "${action}" == "set" ]] && ! jq -e 'type == "object"' "${arg1}" >/dev/null 2>&1; then
        echoContent red " ---> $(t ACCOUNT_TX_BAD_SET_FILE)"
        return 1
    fi

    # 快照建在安装根下（与 xray/ 和 sing-box/ 两个目标目录同文件系统，恢复用 cp 才可靠）
    if ! jsonTxBegin "${PROXY_AGENT_DIR}"; then
        echoContent red " ---> $(t ACCOUNT_TX_BEGIN_FAILED)"
        return 1
    fi

    local protocolId targetDir targetFile usersPath nameField delFilter clients newContent
    local touchedXray= touchedSingBox=
    for protocolId in ${currentInstallProtocolType//,/ }; do
        # 覆盖面与旧的手写分支一致：2/5/8 已废弃冻结，20 是内部 inbound，12 仅 Xray
        case "${protocolId}" in
        0 | 1 | 3 | 4 | 6 | 7 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16) ;;
        *) continue ;;
        esac
        if [[ "${protocolId}" == "12" && "${coreKind}" != "1" ]]; then
            continue
        fi

        # hy2/tuic 恒在 sing-box 树（Xray 内核下是 sidecar），其余跟随当前内核目录
        targetDir="${configPath}"
        if [[ "${protocolId}" == "6" || "${protocolId}" == "9" ]]; then
            targetDir="${singBoxConfigPath}"
        fi
        targetFile=$(getProtocolConfigPath "${protocolId}" "${targetDir}")
        usersPath=$(getProtocolUsersPath "${coreKind}" "${protocolId}")
        # set 只碰 FILE 里列出的协议，不在里面的连快照都不做
        if [[ "${action}" == "set" ]]; then
            clients=$(jq -c --arg k "${protocolId}" '.[$k] // empty' "${arg1}" 2>/dev/null)
            [[ -z "${clients}" ]] && continue
        fi
        if [[ -z "${targetFile}" || -z "${usersPath}" || ! -f "${targetFile}" ]]; then
            echoContent red " ---> $(t ACCOUNT_TX_FILE_MISSING) [$(getProtocolDisplayName "${protocolId}")]"
            jsonTxRollback
            return 1
        fi

        if ! jsonTxTrack "${targetFile}"; then
            echoContent red " ---> $(t ACCOUNT_TX_BEGIN_FAILED)"
            jsonTxRollback
            return 1
        fi

        if [[ "${action}" == "add" ]]; then
            if [[ "${coreKind}" == "1" ]]; then
                clients=$(initXrayClients "${protocolId}" "${arg1}" "${arg2}")
            else
                clients=$(initSingBoxClients "${protocolId}" "${arg1}" "${arg2}")
            fi
            # 生成器若给出空数组，写进去就是把这个协议的用户整个清空还报成功
            if [[ "$(jq 'length' <<<"${clients}" 2>/dev/null)" -lt 1 ]]; then
                echoContent red " ---> $(t ACCOUNT_TX_EMPTY_CLIENTS) [$(getProtocolDisplayName "${protocolId}")]"
                jsonTxRollback
                return 1
            fi
            newContent=$(jq --argjson newClients "${clients}" "${usersPath} = \$newClients" "${targetFile}" 2>/dev/null)
        elif [[ "${action}" == "set" ]]; then
            newContent=$(jq --argjson newClients "${clients}" "${usersPath} = \$newClients" "${targetFile}" 2>/dev/null)
        else
            nameField=$(getProtocolNameField "${coreKind}" "${protocolId}")
            if [[ -z "${nameField}" ]]; then
                echoContent red " ---> $(t ACCOUNT_TX_NAME_FIELD_MISSING) [$(getProtocolDisplayName "${protocolId}")]"
                jsonTxRollback
                return 1
            fi
            delFilter="${usersPath}"' |= map(select(((.[$f] // "") | sub("-[^-]*$"; "")) != $key))'
            newContent=$(jq --arg f "${nameField}" --arg key "${arg1}" "${delFilter}" "${targetFile}" 2>/dev/null)
        fi
        # 16 有两层用户，registry 只认外层，内层每次跟着重写，不然删掉的人内层还在
        if [[ "${protocolId}" == "16" && -n "${newContent}" ]]; then
            newContent=$(shadowTlsWithInnerUsers "${newContent}")
        fi
        if [[ -z "${newContent}" ]] || ! jsonWriteFile "${targetFile}" "${newContent}" false; then
            echoContent red " ---> $(t ACCOUNT_TX_WRITE_FAILED) [$(getProtocolDisplayName "${protocolId}")]"
            jsonTxRollback
            return 1
        fi

        if [[ "${targetDir}" == "${singBoxConfigPath}" && -n "${singBoxConfigPath}" ]]; then
            touchedSingBox=true
        else
            touchedXray=true
        fi
    done

    # 提交前内核级校验，失败即回滚。先 xray（-test 无副作用）后 sing-box（merge 会写 config.json，
    # 但 handleSingBox start 每次重新 merge，回滚后的下一次启动会覆盖掉它）
    if [[ -n "${touchedXray}" && "${coreKind}" == "1" ]] && ! xrayConfigTest; then
        echoContent red " ---> $(t ACCOUNT_TX_VALIDATE_FAILED)"
        jsonTxRollback
        return 1
    fi
    if [[ -n "${touchedSingBox}" && -f "${SINGBOX_BIN}" ]]; then
        if ! singBoxMergeConfig; then
            echoContent red " ---> $(t ACCOUNT_TX_VALIDATE_FAILED)"
            jsonTxRollback
            return 1
        fi
    fi

    jsonTxCommit
}

# 添加用户
addUser() {
    if carpoolGuardAccountMenu add; then return; fi
    read -r -p "请输入要添加的用户数量:" userNum
    echo
    if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
        echoContent red " ---> 输入有误，请重新输入"
        exit 1
    fi
    while [[ ${userNum} -gt 0 ]]; do
        readConfigHostPathUUID
        ((userNum--)) || true

        customUUID
        customUserEmail

        uuid=${currentCustomUUID}
        email=${currentCustomEmail}

        if ! applyAccountChangeAllProtocols add "${uuid}" "${email}"; then
            manageAccount 1
            return
        fi
    done
    reloadCore
    echoContent green " ---> 添加完成"
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    manageAccount 1
}
# 移除用户
removeUser() {
    if carpoolGuardAccountMenu remove; then return; fi
    local userConfigType= delUserKey=
    if [[ -n "${frontingType}" ]]; then
        userConfigType="${frontingType}"
    elif [[ -n "${frontingTypeReality}" ]]; then
        userConfigType="${frontingTypeReality}"
    fi

    if [[ -n "${userConfigType}" ]]; then
        # 列表字段按注册表取（fronting 可能是 TLS/Reality/naive/ss2022，路径与名字段各不同）
        local frontingProtocolId listUsersPath listNameField
        frontingProtocolId=$(parseProtocolIdFromFileName "${userConfigType}.json")
        listUsersPath=$(getProtocolUsersPath "${coreKind}" "${frontingProtocolId}")
        listNameField=$(getProtocolNameField "${coreKind}" "${frontingProtocolId}")
        if [[ -z "${listUsersPath}" || -z "${listNameField}" ]]; then
            echoContent red " ---> $(t ACCOUNT_TX_FILE_MISSING) [${userConfigType}]"
            manageAccount 1
            return
        fi
        jq -r "${listUsersPath}[].${listNameField}" "${configPath}${userConfigType}.json" | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
        # 必须是正整数；非法输入直接清空，跳过后续删除分支，避免注入进 jq 过滤器
        if ! [[ "${delUserIndex}" =~ ^[1-9][0-9]*$ ]]; then
            echoContent red " ---> 用户编号必须为正整数"
            delUserIndex=
        elif [[ $(jq -r "${listUsersPath}|length" "${configPath}${userConfigType}.json") -lt ${delUserIndex} ]]; then
            echoContent red " ---> 选择错误"
            delUserIndex=
        else
            # 编号只用来在前置协议文件里取名字；各协议文件的用户顺序不保证一致，真正删除按去掉协议后缀的名字
            delUserKey=$(jq -r --argjson idx "$((delUserIndex - 1))" "${listUsersPath}[\$idx].${listNameField} // empty" "${configPath}${userConfigType}.json")
            delUserKey=${delUserKey%-*}
            if [[ -z "${delUserKey}" ]]; then
                echoContent red " ---> $(t REMOVE_USER_NO_NAME)"
            fi
        fi
    fi

    if [[ -n "${delUserKey}" ]]; then
        local confirmDelete
        read -r -p "$(t REMOVE_USER_CONFIRM "${delUserKey}")" confirmDelete
        if ! isYesInput "${confirmDelete}"; then
            echoContent yellow " ---> $(t CANCELLED)"
            manageAccount 1
            return
        fi
        if ! applyAccountChangeAllProtocols delName "${delUserKey}"; then
            manageAccount 1
            return
        fi
        if ! chainAccountForget "${delUserKey}"; then
            echoContent red " ---> $(t CHAIN_ACCOUNT_FORGET_FAILED "${delUserKey}")"
        fi
        reloadCore
        readNginxSubscribe
        if [[ -n "${subscribePort}" ]]; then
            subscribe false
        fi
        # 订阅文件按名字第一段命名，剩下的账号还有同一段时那份文件是它的，不能删
        if [[ ! -e "${SUBSCRIBE_LOCAL_DIR}/default/$(carpoolSubscribeKey "${delUserKey}")" ]]; then
            removeSubscriptionFiles "${delUserKey}"
        fi
    fi
    manageAccount 1
}

# ======================= 拼车 =======================

# carpoolLock → 0=拿到 state 读-改-写锁（fd 9，最多等 10 秒）；flock 缺失或超时返回 1。锁只包 state 的读写，不包 reload
# BusyBox 的 flock 没有 -w，等待用 -n 轮询
carpoolLock() {
    local i
    if ! command -v flock >/dev/null 2>&1; then
        echoContent red " ---> $(t CARPOOL_FLOCK_MISSING)"
        return 1
    fi
    mkdir -p "${CARPOOL_DIR}"
    exec 9>>"${CARPOOL_LOCK_FILE}" || return 1
    for i in $(seq 1 20); do
        flock -n 9 && return 0
        sleep 0.5
    done
    exec 9>&-
    return 1
}

carpoolUnlock() {
    flock -u 9 2>/dev/null
    exec 9>&-
}

# carpoolEnabled → 0=state.json 存在且 enabled
carpoolEnabled() {
    local state
    state=$(carpoolReadState) || return 1
    [[ "$(jq -r '.enabled' <<<"${state}")" == "true" ]]
}

# carpoolCurrentClientsMap → {"<ID>": [clients…]}，每个已装拼车协议文件当前的用户数组（按目录扫，不信全局变量）
carpoolCurrentClientsMap() {
    local id file usersPath current map="{}"
    for id in $(carpoolInstalledProtocolsJson "$(scanInstalledProtocols "${XRAY_CONF_DIR}")" | jq -r '.[]'); do
        file=$(getProtocolConfigPath "${id}" "${XRAY_CONF_DIR}/")
        usersPath=$(getProtocolUsersPath 1 "${id}")
        [[ -f "${file}" && -n "${usersPath}" ]] || continue
        current=$(jq -c "${usersPath} // []" "${file}" 2>/dev/null) || return 1
        map=$(jq -c --arg k "${id}" --argjson v "${current}" '.[$k] = $v' <<<"${map}") || return 1
    done
    printf '%s\n' "${map}"
}

# ensureCarpoolCron → crontab 里确保有一条 CarpoolTick；按 "install.sh CarpoolTick" 子串判重，车主改过间隔的行不会被再加一条
ensureCarpoolCron() {
    local current
    current=$(crontab -l 2>/dev/null)
    grep -q -F "${PROXY_AGENT_DIR}/install.sh CarpoolTick" <<<"${current}" && return 0
    {
        if [[ -n "${current}" ]]; then printf '%s\n' "${current}"; fi
        echo "*/5 * * * * PROXY_AGENT_DIR=${PROXY_AGENT_DIR} /bin/bash ${PROXY_AGENT_DIR}/install.sh CarpoolTick >> ${CARPOOL_LOG_FILE} 2>&1"
    } | crontab - || echoContent yellow " ---> $(t CARPOOL_CRON_FAILED)"
}

# carpoolXrayServiceEnv on|off → Xray 服务带不带 XRAY_BUF_SPLICE=disable 与停止钩子；systemd 写 drop-in（有改动才 daemon-reload），OpenRC 写 conf.d。
# 拼车开着必须带：Vision 下行走 splice 时要到连接关闭才计入用户统计，重载时在途的整段丢；
# 关机、重启不经 handleXray，停止钩子不挂上，上次 tick 之后的计数随进程丢。须在 Xray 启动前调
carpoolXrayServiceEnv() {
    local dropIn=/etc/systemd/system/xray.service.d/carpool.conf confD=/etc/conf.d/xray
    local hook="PROXY_AGENT_DIR=${PROXY_AGENT_DIR} /bin/bash ${PROXY_AGENT_DIR}/install.sh CarpoolCollect"
    local unit=$'[Service]\nEnvironment=XRAY_BUF_SPLICE=disable\nExecStop=-/usr/bin/env '"${hook}"
    local line='export XRAY_BUF_SPLICE=disable' stopPre="stop_pre() { ${hook}; }" kept want
    if [[ -f /etc/systemd/system/xray.service ]]; then
        if [[ "$1" == "on" && "$(cat "${dropIn}" 2>/dev/null)" != "${unit}" ]]; then
            if ! { mkdir -p "${dropIn%/*}" && printf '%s\n' "${unit}" >"${dropIn}"; }; then
                echoContent red " ---> $(t CARPOOL_ENSURE_WRITE_FAILED "${dropIn}")"
                return 1
            fi
        elif [[ "$1" == "off" && -e "${dropIn}" ]]; then
            rm -f "${dropIn}"
            rmdir "${dropIn%/*}" 2>/dev/null
        else
            return 0
        fi
        systemctl daemon-reload
    elif [[ -f /etc/init.d/xray ]]; then
        # 车主自己写在 conf.d 里的行原样留着；init 脚本不定义 stop_pre，openrc-run 先读 conf.d，这里定义的就是停止前钩子
        kept=$(grep -vxF -e "${line}" -e "${stopPre}" "${confD}" 2>/dev/null)
        want=${kept}
        [[ "$1" == "on" ]] && want=${kept:+${kept}$'\n'}${line}$'\n'${stopPre}
        [[ "${want}" == "$(cat "${confD}" 2>/dev/null)" ]] && return 0
        if [[ -z "${want}" ]]; then
            rm -f "${confD}"
        elif ! printf '%s\n' "${want}" >"${confD}"; then
            echoContent red " ---> $(t CARPOOL_ENSURE_WRITE_FAILED "${confD}")"
            return 1
        fi
    fi
}

# ensureCarpoolXray → 拼车开着：补齐 Xray 服务环境、policy 统计字段与 12_stats_api.json、确保 cron 行、对账 clients；
# 关着：撤掉前三样。挂在 handleXray start，绝不 exit：对账失败只打一行，事务已回滚，下个 tick 重试
ensureCarpoolXray() {
    local statsFile="${XRAY_CONF_DIR}/12_stats_api.json" policyFile="${XRAY_CONF_DIR}/12_policy.json"
    local state want
    # 从没开过拼车（没有 state）就什么都不碰：车主自己开的 policy 统计字段不是拼车加的
    [[ -f "${CARPOOL_STATE_FILE}" ]] || return 0
    if ! state=$(carpoolReadState) || [[ "$(jq -r '.enabled' <<<"${state}")" != "true" ]]; then
        carpoolXrayServiceEnv off
        [[ -f "${statsFile}" ]] && rm -f "${statsFile}"
        if [[ -f "${policyFile}" ]] && jq -e '.policy.levels."0" | has("statsUserUplink") or has("statsUserDownlink")' "${policyFile}" >/dev/null 2>&1; then
            jsonModifyFile "${policyFile}" 'del(.policy.levels."0".statsUserUplink, .policy.levels."0".statsUserDownlink)' false
        fi
        return 0
    fi
    carpoolXrayServiceEnv on || return 1
    if [[ ! -f "${policyFile}" ]]; then
        echoContent red " ---> $(t CARPOOL_POLICY_MISSING "${policyFile}")"
        return 1
    fi
    if ! jq -e '.policy.levels."0".statsUserUplink == true and .policy.levels."0".statsUserDownlink == true' "${policyFile}" >/dev/null 2>&1; then
        if ! jsonModifyFile "${policyFile}" '.policy.levels."0".statsUserUplink = true | .policy.levels."0".statsUserDownlink = true' false; then
            echoContent red " ---> $(t CARPOOL_ENSURE_WRITE_FAILED "${policyFile}")"
            return 1
        fi
    fi
    want=$(jq -cn --arg listen "127.0.0.1:$(jq -r '.apiPort' <<<"${state}")" '{stats: {}, api: {tag: "api", listen: $listen, services: ["StatsService"]}}')
    if [[ "$(jq -Sc . "${statsFile}" 2>/dev/null)" != "$(jq -Sc . <<<"${want}")" ]]; then
        if ! jsonWriteFile "${statsFile}" "${want}" false; then
            echoContent red " ---> $(t CARPOOL_ENSURE_WRITE_FAILED "${statsFile}")"
            return 1
        fi
    fi
    ensureCarpoolCron
    carpoolReconcile "${state}" >/dev/null || echoContent yellow " ---> $(t CARPOOL_RECONCILE_FAILED)"
}

# carpoolReconcile STATE → 各协议文件的 clients 对齐到期望值：有差异走账户事务 set；输出 changed / unchanged
carpoolReconcile() {
    local map payload tmp
    map=$(carpoolCurrentClientsMap) || return 1
    payload=$(carpoolReconcilePayload "$1" "${map}") || return 1
    if [[ -z "${payload}" ]]; then
        echo unchanged
        return 0
    fi
    tmp=$(mktemp "${CARPOOL_DIR}/.set.XXXXXX") || return 1
    printf '%s\n' "${payload}" >"${tmp}"
    readInstallProtocolType
    if ! applyAccountChangeAllProtocols set "${tmp}"; then
        rm -f "${tmp}"
        return 1
    fi
    rm -f "${tmp}"
    echo changed
}

# carpoolCollect STATE → 向 StatsService 取一次增量（-reset）累加进 state 并输出；Xray 没在跑原样输出；查询失败返回 1
carpoolCollect() {
    local apiPort raw sums
    if ! xrayDaemonRunning; then
        printf '%s\n' "$1"
        return 0
    fi
    apiPort=$(jq -r '.apiPort' <<<"$1")
    if ! raw=$(${XRAY_BIN} api statsquery -s "127.0.0.1:${apiPort}" -t 3 -pattern 'user>>>' -reset 2>/dev/null); then
        return 1
    fi
    sums=$(carpoolSumStats "${raw}") || return 1
    carpoolAddUsage "$1" "${sums}"
}

# carpoolMachineSample [IFACE] → {"bootId", "counters": {网卡: {rx, tx}}}：IFACE 为空就取默认路由所在的网卡（v4 / v6 各一）；
# 一块都读不到返回 1。bootId 用来认出重启：重启后内核计数从 0 起
carpoolMachineSample() {
    local ifaces counters
    if [[ -n "$1" ]]; then
        ifaces=$(jq -cn --arg i "$1" '[$i]')
    else
        ifaces=$(carpoolDefaultRouteIfaces "$(cat /proc/net/route 2>/dev/null)" "$(cat /proc/net/ipv6_route 2>/dev/null)") || return 1
    fi
    counters=$(carpoolNetDevCounters "$(cat /proc/net/dev 2>/dev/null)" "${ifaces}") || return 1
    [[ "$(jq 'length' <<<"${counters}")" -gt 0 ]] || return 1
    jq -cn --arg b "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" --argjson c "${counters}" '{bootId: $b, counters: $c}'
}

# carpoolMachineStep STATE → 按 plan.interface（空就取默认路由的网卡）读一次网卡计数、累加进 .machine，输出新 state；读不到网卡返回 1
carpoolMachineStep() {
    local sample machine
    sample=$(carpoolMachineSample "$(jq -r '.plan.interface // ""' <<<"$1")") || return 1
    machine=$(carpoolMachineAdvance "$(jq -c '.machine // {}' <<<"$1")" "${sample}") || return 1
    jq -c --argjson m "${machine}" '.machine = $m' <<<"$1"
}

# carpoolCollectBeforeStop → 停 Xray 前的钩子（handleXray stop，与服务单元的停止钩子 CarpoolCollect）：拼车开着且 Xray 在跑就把内存里的计数
# 收进 state，整机网卡也记一次（重启后从 0 起），否则上次 tick 之后的都丢。只写 state 不判定：判定可能要重载，停机途中不能重载
carpoolCollectBeforeStop() {
    local state newState
    state=$(carpoolReadState) || return 0
    [[ "$(jq -r '.enabled' <<<"${state}")" == "true" ]] || return 0
    xrayDaemonRunning || return 0
    carpoolLock || return 0
    state=$(carpoolReadState)
    newState=$(carpoolCollect "${state}") && state=${newState}
    newState=$(carpoolMachineStep "${state}") && state=${newState}
    carpoolWriteState "${state}"
    carpoolUnlock
}

# carpoolSubscribeMd5 NAME → 该成员订阅文件的文件名 = md5(订阅键 + salt)，与 subscribe 同一算法；无 salt 返回 1
carpoolSubscribeMd5() {
    local salt md5
    [[ -s "${SUBSCRIBE_LOCAL_DIR}/subscribeSalt" ]] || return 1
    salt=$(cat "${SUBSCRIBE_LOCAL_DIR}/subscribeSalt")
    md5=$(echo -n "$(carpoolSubscribeKey "$1")${salt}"$'\n' | md5sum | awk '{print $1}')
    [[ "${md5}" =~ ^[0-9a-f]{32}$ ]] || return 1
    printf '%s\n' "${md5}"
}

# carpoolMemberPageKey TOKEN NAME → 成员页文件名 = md5(车主页令牌:成员名)。不能用订阅 md5：转发成员页链接就等于转发订阅；
# 车主重生成令牌时成员页链接一起换
carpoolMemberPageKey() {
    local key
    key=$(printf '%s:%s' "$1" "$2" | md5sum | awk '{print $1}')
    [[ "${key}" =~ ^[0-9a-f]{32}$ ]] || return 1
    printf '%s\n' "${key}"
}

# carpoolWritePlaceholders STATE → 给每个 disabled 且已不在 inbound 里的成员覆盖写四个占位订阅文件；没有 salt 或订阅目录就跳过
carpoolWritePlaceholders() {
    local name reason label md5 present
    [[ -s "${SUBSCRIBE_LOCAL_DIR}/subscribeSalt" && -d "${SUBSCRIBE_DIR}/default" ]] || return 0
    present=$(carpoolCurrentClientsMap | jq -c '[.[] | .[]? | (.email // "") | sub("-[^-]*$"; "")]')
    while IFS=$'\t' read -r name reason; do
        [[ -z "${name}" ]] && continue
        jq -e --arg n "${name}" 'index($n) != null' <<<"${present}" >/dev/null 2>&1 && continue
        md5=$(carpoolSubscribeMd5 "${name}") || continue
        label=$(carpoolReasonText "${reason}")
        carpoolPlaceholderDefault "${label}" >"${SUBSCRIBE_DIR}/default/${md5}"
        carpoolPlaceholderClash "${label}" >"${SUBSCRIBE_DIR}/clashMeta/${md5}"
        carpoolPlaceholderSingBoxProfile "${label}" >"${SUBSCRIBE_DIR}/sing-box_profiles/${md5}"
        carpoolPlaceholderSingBoxConfig "${label}" >"${SUBSCRIBE_DIR}/sing-box/${md5}"
    done < <(jq -r '.members | to_entries[] | select(.value.status == "disabled") | "\(.key)\t\(.value.reason)"' <<<"$1")
}

# carpoolRefreshSubscribe → 有人恢复后重建订阅文件；只在订阅已装且 salt 已存在时调，否则 subscribe 在 cron 下会交互
carpoolRefreshSubscribe() {
    readNginxSubscribe
    [[ -n "${subscribePort}" && -s "${SUBSCRIBE_LOCAL_DIR}/subscribeSalt" ]] || return 0
    subscribe false true >/dev/null 2>&1 || true
}

# carpoolJudgeAndWrite STATE TODAY NOW [EXTRA_EVENTS] → 判定、记事件（EXTRA 在前）、写 state，输出 events；调用方持锁
carpoolJudgeAndWrite() {
    local state=$1 verdict events period
    period=$(carpoolPeriodStart "$2" "$(jq -r '.resetDay' <<<"${state}")")
    verdict=$(carpoolJudge "${state}" "$(jq -c '.notify' <<<"${state}")" "$2" "${period}")
    events=$(jq -c --argjson extra "${4:-[]}" '$extra + .events' <<<"${verdict}")
    state=$(carpoolAppendEvents "$(jq -c --arg now "$3" '.state | .lastTick = $now' <<<"${verdict}")" "${events}" "$3")
    carpoolWriteState "${state}" || return 1
    printf '%s\n' "${events}"
}

# carpoolSetNotified KEY true|false → 持锁改 state.notified[KEY]；只有值真的翻转了才返回 0，调用方据此只发一次通知
carpoolSetNotified() {
    local state rc
    carpoolLock || return 1
    if ! state=$(carpoolReadState) || [[ "$(jq -r --arg k "$1" '.notified[$k] // false' <<<"${state}")" == "$2" ]]; then
        carpoolUnlock
        return 1
    fi
    carpoolWriteState "$(jq -c --arg k "$1" --argjson v "$2" 'if $v then .notified[$k] = true else del(.notified[$k]) end' <<<"${state}")"
    rc=$?
    carpoolUnlock
    return "${rc}"
}

# carpoolSettle EVENTS [FORCE_REFRESH] → 放锁之后：对账 clients → 占位 → 有变更就重载 → 有恢复（或 FORCE）就重建订阅。
# state 从磁盘重读，不用调用方的副本：reload 里的 stop 钩子还会再写一笔
carpoolSettle() {
    local events=$1 state result now ev rc=1
    now=$(date '+%F %H:%M')
    while read -r ev; do
        [[ -n "${ev}" ]] && echoContent yellow " ---> ${now} $(carpoolEventText "${ev}")"
    done < <(jq -c '.[]' <<<"${events}")
    # 读 state 和对账在同一把锁里：锁外读到的旧 state 晚写进协议文件，会盖掉关闭拼车时放回的用户；只放开 reload
    if carpoolLock; then
        state=$(carpoolReadState) && result=$(carpoolReconcile "${state}")
        rc=$?
        carpoolUnlock
    fi
    # 对账失败时每个 tick 都会重试：txFailed 只在第一次失败时发，成功一次后清掉去重键
    if [[ ${rc} -ne 0 ]]; then
        echoContent red " ---> ${now} $(t CARPOOL_RECONCILE_FAILED)"
        carpoolSetNotified "tx:failed" true && events=$(jq -c '. + [{type: "txFailed"}]' <<<"${events}")
        carpoolNotifyEvents "${events}"
        return 1
    fi
    if [[ "$(jq -r '.notified["tx:failed"] // false' <<<"${state}")" == "true" ]]; then
        carpoolSetNotified "tx:failed" false
    fi
    carpoolWritePlaceholders "${state}"
    if [[ "${result}" == "changed" ]]; then
        reloadCore
    fi
    if [[ -n "${2:-}" ]] || jq -e 'any(.type == "restored")' <<<"${events}" >/dev/null 2>&1; then
        carpoolRefreshSubscribe
    fi
    carpoolRenderPages
    carpoolSyncUserinfo
    carpoolNotifyEvents "${events}"
    return 0
}

# carpoolTelegramSend TEXT → 有合法的 telegram.conf 就发一条纯文本（curl 带超时，正文截到 4000 字符：Bot API 上限 4096）；
# 没配置静默返回 0，发失败打一行返回 1。失败文案里不放 curl 的原话：它可能带上含 token 的 URL
carpoolTelegramSend() {
    local conf token chat resp
    conf=$(carpoolReadTelegramConf "${CARPOOL_TELEGRAM_FILE}") || return 0
    token=$(sed -n 1p <<<"${conf}")
    chat=$(sed -n 2p <<<"${conf}")
    if ! resp=$(curl -s --connect-timeout 5 -m 15 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=${chat}" --data-urlencode "text=${1:0:4000}" 2>/dev/null); then
        echoContent yellow " ---> $(t CARPOOL_TG_SEND_FAILED "curl")"
        return 1
    fi
    if ! jq -e '.ok == true' <<<"${resp}" >/dev/null 2>&1; then
        echoContent yellow " ---> $(t CARPOOL_TG_SEND_FAILED "$(jq -r '.description // "bad response"' <<<"${resp}" 2>/dev/null | head -c 120)")"
        return 1
    fi
    return 0
}

# carpoolNotifyEvents EVENTS → 事件合成一条消息发出去，每日摘要另发一条；没有 telegram.conf 就什么都不做，失败不影响退出码
carpoolNotifyEvents() {
    local state label text today
    [[ -f "${CARPOOL_TELEGRAM_FILE}" ]] || return 0
    state=$(carpoolReadState) || return 0
    label=$(jq -r '.notify.label' <<<"${state}")
    text=$(carpoolNotifyText "${label}" "$(jq -c 'map(select(.type != "digest"))' <<<"$1")")
    [[ -n "${text}" ]] && carpoolTelegramSend "${text}"
    if jq -e 'any(.type == "digest")' <<<"$1" >/dev/null 2>&1; then
        today=$(jq -r 'map(select(.type == "digest"))[0].date' <<<"$1")
        carpoolTelegramSend "[${label}]"$'\n'"$(carpoolDigestText "${state}" "${today}")"
    fi
    return 0
}

# carpoolTickExitTrap RC → cron 入口的 EXIT 陷阱：tick 没走完就退出（多半是内核重载失败 exit 1）时发一条
carpoolTickExitTrap() {
    [[ "$1" -ne 0 && -z "${_carpoolTickFinished:-}" ]] || return 0
    local label
    label=$(carpoolReadState 2>/dev/null | jq -r '.notify.label // "carpool"' 2>/dev/null)
    carpoolTelegramSend "[${label:-carpool}]"$'\n'"$(t CARPOOL_EVENT_TICK_ABORTED "$1")" || true
}

# carpoolTick → cron 入口 CarpoolTick（手动跑也行）：采集 → 同步 members.json 即时字段 → 判定写 state（持锁恰好一次）→ settle
carpoolTick() {
    local state newState today now installed errors normalized events
    state=$(carpoolReadState) || return 0
    [[ "$(jq -r '.enabled' <<<"${state}")" == "true" ]] || return 0
    today=$(date +%F)
    now=$(date '+%F %H:%M')
    if [[ "${coreKind}" != "1" ]]; then
        echoContent yellow " ---> ${now} $(t CARPOOL_TICK_NOT_XRAY)"
        carpoolLock || return 0
        state=$(carpoolReadState)
        local firstTime=
        if [[ "$(jq -r '.notified["inactive:core"] // false' <<<"${state}")" != "true" ]]; then
            carpoolWriteState "$(jq -c '.notified["inactive:core"] = true' <<<"${state}")" && firstTime=1
        fi
        carpoolUnlock
        [[ -n "${firstTime}" ]] && carpoolNotifyEvents '[{"type": "inactive"}]'
        return 0
    fi
    if ! carpoolLock; then
        echoContent red " ---> ${now} $(t CARPOOL_TICK_LOCK_FAILED)"
        return 1
    fi
    state=$(carpoolReadState)
    # 等锁时拼车可能刚被关掉：再判定会把关闭时恢复的人又停掉，之后也没有 tick 能纠正
    if [[ "$(jq -r '.enabled' <<<"${state}")" != "true" ]]; then
        carpoolUnlock
        return 0
    fi
    if newState=$(carpoolCollect "${state}"); then
        state=$(jq -c '.collectFailures = 0' <<<"${newState}")
    else
        state=$(jq -c '.collectFailures += 1' <<<"${state}")
        echoContent yellow " ---> ${now} $(t CARPOOL_TICK_COLLECT_FAILED "$(jq -r '.collectFailures' <<<"${state}")")"
    fi
    local membersOk=true fileId notices extra iface map
    installed=$(scanInstalledProtocols "${XRAY_CONF_DIR}")
    if map=$(carpoolCurrentClientsMap); then
        state=$(carpoolPruneRemoved "${state}" "${map}")
    fi
    if errors=$(carpoolValidateMembers "${CARPOOL_MEMBERS_FILE}" "${installed}" "$(carpoolForeignAccounts "${state}" "${map:-"{}"}")" "$(carpoolRetiredNames "${state}")" "$(carpoolMemberUuids "${state}")"); then
        normalized=$(carpoolNormalizeMembers "${CARPOOL_MEMBERS_FILE}")
        state=$(carpoolSyncLimits "${state}" "${normalized}")
    else
        membersOk=false
        echoContent yellow " ---> ${now} $(t CARPOOL_TICK_MEMBERS_INVALID "${CARPOOL_MEMBERS_FILE}")"
        echo "${errors}"
    fi
    # 整机读网卡，不看 Xray 在不在跑；网卡按刚同步的 plan.interface 取
    iface=$(jq -r '.plan.interface // ""' <<<"${state}")
    if newState=$(carpoolMachineStep "${state}"); then
        state=${newState}
    elif [[ -n "${iface}" ]]; then
        echoContent yellow " ---> ${now} $(t CARPOOL_TICK_NO_IFACE "${iface}")"
    else
        echoContent yellow " ---> ${now} $(t CARPOOL_TICK_NO_ROUTE)"
    fi
    # 文件无效按内容摘要只提醒一次；采集失败满 3 次 / 恢复各一次；每日摘要到点一次
    fileId=$(md5sum "${CARPOOL_MEMBERS_FILE}" 2>/dev/null | awk '{print $1}')
    notices=$(carpoolTickNotices "${state}" "${today}" "$((10#$(date +%H)))" "${membersOk}" "${fileId:-missing}")
    state=$(jq -c '.state' <<<"${notices}")
    extra=$(jq -c --arg r "$(tr '\n' ';' <<<"${errors}")" '.events | map(if .type == "invalid" then .reasons = $r else . end)' <<<"${notices}")
    if ! events=$(carpoolJudgeAndWrite "${state}" "${today}" "${now}" "${extra}"); then
        carpoolUnlock
        echoContent red " ---> ${now} $(t CARPOOL_TICK_STATE_WRITE_FAILED)"
        return 1
    fi
    carpoolUnlock
    carpoolSettle "${events}"
}

# carpoolRefuseIfEnabled → 拼车开着时拒绝切内核与装 6 / 9（它们让计量失真），红字并退出
carpoolRefuseIfEnabled() {
    carpoolEnabled || return 0
    echoContent red " ---> $(t CARPOOL_REFUSE_ENABLED)"
    exit 1
}

# carpoolGuardAccountMenu add|remove → 拼车开着时 addUser / removeUser 转到成员管理的加成员 / 移除成员；拦住了返回 0
carpoolGuardAccountMenu() {
    carpoolEnabled || return 1
    echoContent yellow " ---> $(t CARPOOL_ACCOUNTS_MANAGED)"
    if [[ "$1" == "remove" ]]; then
        carpoolMemberEdit remove
    else
        carpoolMemberAdd
    fi
    manageAccount 1
    return 0
}

# carpoolCheckPrerequisites → 开启前的五项检查，逐条打印不满足的原因，任一不满足返回 1
carpoolCheckPrerequisites() {
    local ok=1 ver
    if [[ "${coreKind}" != "1" ]]; then
        echoContent red " ---> $(t CARPOOL_REQ_XRAY)"
        ok=
    else
        ver=$(${XRAY_BIN} version 2>/dev/null | head -1 | awk '{print $2}')
        if [[ -z "${ver}" ]] || ! versionGreaterOrEqual "${ver}" "${CARPOOL_XRAY_MIN_VERSION}"; then
            echoContent red " ---> $(t CARPOOL_REQ_XRAY_VERSION "${ver:-?}" "${CARPOOL_XRAY_MIN_VERSION}")"
            ok=
        fi
    fi
    if [[ "${currentInstallProtocolType}" == *",6,"* || "${currentInstallProtocolType}" == *",9,"* ]]; then
        echoContent red " ---> $(t CARPOOL_REQ_NO_SIDECAR)"
        ok=
    fi
    local id
    for id in $(carpoolUnmanagedProtocols "$(scanInstalledProtocols "${XRAY_CONF_DIR}")"); do
        echoContent red " ---> $(t CARPOOL_REQ_UNMANAGED_PROTOCOL "$(getProtocolDisplayName "${id}")" "$(getProtocolConfigPath "${id}" "${XRAY_CONF_DIR}/")")"
        ok=
    done
    if ! command -v flock >/dev/null 2>&1; then
        echoContent red " ---> $(t CARPOOL_FLOCK_MISSING)"
        ok=
    fi
    if ! ensureCronService >/dev/null 2>&1; then
        echoContent red " ---> $(t CARPOOL_REQ_CROND)"
        ok=
    fi
    [[ -n "${ok}" ]]
}

# carpoolPickApiPort → CARPOOL_API_PORT_FIRST–LAST 里第一个没被监听的端口给统计 API
carpoolPickApiPort() {
    # shellcheck disable=SC2046
    firstFreePort "$(listeningPorts tcp)" $(seq "${CARPOOL_API_PORT_FIRST}" "${CARPOOL_API_PORT_LAST}")
}

# carpoolAllAccounts CURRENT_MAP → {name: uuid}，inbound 里全部账号
carpoolAllAccounts() {
    carpoolForeignAccounts '{"members": {}}' "$1"
}

# carpoolFillUuids STATE → uuid 为空的成员各生成一个（xray uuid）
carpoolFillUuids() {
    local state=$1 name u
    for name in $(jq -r '.members | to_entries[] | select(.value.uuid == "") | .key' <<<"${state}"); do
        u=$(${XRAY_BIN} uuid 2>/dev/null)
        if ! carpoolIsValidUUID "${u}"; then
            echoContent red " ---> $(t CARPOOL_UUID_GEN_FAILED)"
            return 1
        fi
        state=$(jq -c --arg n "${name}" --arg u "${u}" '.members[$n].uuid = $u' <<<"${state}")
    done
    printf '%s\n' "${state}"
}

# carpoolRemoveCron → 删掉 CarpoolTick 的 cron 行
carpoolRemoveCron() {
    local current remaining
    current=$(crontab -l 2>/dev/null) || return 0
    # CarpoolTick 是唯一一行时 grep -v 没有输出、返回 1，接在管道里会把成功报成失败
    remaining=$(grep -v -F "${PROXY_AGENT_DIR}/install.sh CarpoolTick" <<<"${current}" || true)
    crontab - <<<"${remaining}" || echoContent yellow " ---> $(t CRON_REMOVE_FAILED)"
}

# removeSubscriptionFiles NAME → 删掉这个账号的五个订阅文件（含拼车占位）；拼车成员页由 carpoolRenderPages 按期望集合清掉。
# subscribe 发布前只清 default/ 与 clashMeta/，删掉的账号不走这里，另外三种格式就一直按老地址给出去
removeSubscriptionFiles() {
    local md5 dir
    md5=$(carpoolSubscribeMd5 "$1") || return 0
    for dir in default clashMeta clashMetaProfiles sing-box sing-box_profiles; do
        rm -f "${SUBSCRIBE_DIR}/${dir}/${md5}"
    done
}

# carpoolEnable → 检查 → 没有 members.json 就按现有账号播种 → 写 state → reloadCore（start 钩子写片段、cron 行、对账）→ 第一次 tick
# carpoolConfirmReenable MERGED_STATE ACCOUNTS → 重开前把客户端看得见的改动列出来、逐项确认：0=照常开启，1=不在 tty 上（已报错），2=车主取消
# 关闭期间在菜单里删掉、改过的账号，state 还记着旧凭据；不问就开，删掉的人会带着旧 UUID 回来
carpoolConfirmReenable() {
    local changes name from to answer
    changes=$(carpoolReenableChanges "$1" "$2") || return 1
    jq -e '(.restore + .uuid) | length == 0' <<<"${changes}" >/dev/null && return 0
    echoContent skyBlue "\n$(t CARPOOL_REENABLE_TITLE)"
    for name in $(jq -r '.restore[]' <<<"${changes}"); do
        echoContent yellow " ---> $(t CARPOOL_REENABLE_RESTORE "${name}")"
    done
    while IFS=$'\t' read -r name from to; do
        [[ -n "${name}" ]] && echoContent yellow " ---> $(t CARPOOL_REENABLE_UUID "${name}" "${from}" "${to}")"
    done < <(jq -r '.uuid[] | "\(.name)\t\(.from)\t\(.to)"' <<<"${changes}")
    if ! carpoolHasTty; then
        echoContent red " ---> $(t CARPOOL_REENABLE_NEEDS_TTY)"
        return 1
    fi
    for name in $(jq -r '.restore[], .uuid[].name' <<<"${changes}"); do
        read -r -p "$(t CARPOOL_REENABLE_CONFIRM "${name}")" answer
        isYesInput "${answer}" || return 2
    done
}

# carpoolApiReady PORT → 0=统计 API 片段写着这个端口、且本机已在监听。start 钩子失败时 Xray 照样起来，
# 不核对就会报「已开启」而一笔流量都采不到
carpoolApiReady() {
    local i
    [[ "$(jq -r '.api.listen // empty' "${XRAY_CONF_DIR}/12_stats_api.json" 2>/dev/null)" == "127.0.0.1:$1" ]] || return 1
    for i in 1 2 3; do
        portListed "$1" "$(listeningPorts tcp)" && return 0
        sleep 1
    done
    return 1
}

carpoolEnable() {
    local installed map accounts seed fileMembers errors normalized state oldState= retired='[]' memberUuids='{}' today apiPort rc
    if carpoolEnabled; then
        echoContent yellow " ---> $(t CARPOOL_ALREADY_ENABLED)"
        return 0
    fi
    carpoolCheckPrerequisites || return 1
    mkdir -p "${CARPOOL_DIR}" && chmod 700 "${CARPOOL_DIR}"
    installed=$(scanInstalledProtocols "${XRAY_CONF_DIR}")
    map=$(carpoolCurrentClientsMap) || return 1
    accounts=$(carpoolAllAccounts "${map}")
    if [[ ! -f "${CARPOOL_MEMBERS_FILE}" ]]; then
        seed=$(carpoolSeedMembers "$(jq -c 'to_entries | map({name: .key, uuid: .value})' <<<"${accounts}")")
        if ! jsonWriteFile "${CARPOOL_MEMBERS_FILE}" "${seed}" false; then
            echoContent red " ---> $(t CARPOOL_ENSURE_WRITE_FAILED "${CARPOOL_MEMBERS_FILE}")"
            return 1
        fi
        echoContent green " ---> $(t CARPOOL_SEEDED "${CARPOOL_MEMBERS_FILE}" "$(jq 'length' <<<"${accounts}")")"
    fi
    fileMembers=$(jq -c '{members: (.members // {})}' "${CARPOOL_MEMBERS_FILE}" 2>/dev/null) || fileMembers='{"members": {}}'
    if oldState=$(carpoolReadState); then
        retired=$(carpoolRetiredNames "${oldState}")
        memberUuids=$(carpoolMemberUuids "${oldState}")
    fi
    if ! errors=$(carpoolValidateMembers "${CARPOOL_MEMBERS_FILE}" "${installed}" "$(carpoolForeignAccounts "${fileMembers}" "${map}")" "${retired}" "${memberUuids}"); then
        echoContent red " ---> $(t CARPOOL_MEMBERS_INVALID "${CARPOOL_MEMBERS_FILE}")"
        echo "${errors}"
        return 1
    fi
    normalized=$(carpoolNormalizeMembers "${CARPOOL_MEMBERS_FILE}")
    today=$(date +%F)
    if [[ -n "${oldState}" ]]; then
        # 关着时改过清零日的，开启就是应用它：后果与应用时一样先说出来
        carpoolDiffText "$(carpoolDiffMembers "${oldState}" "${normalized}" "${accounts}" | jq -c '{added: [], removed: [], protocols: [], uuid: [], quota: [], expire: [], resetDay, unmanaged: []}')"
        carpoolConfirmReenable "$(carpoolMergeState "${oldState}" "${normalized}" "${accounts}")" "${accounts}"
        rc=$?
        if [[ ${rc} -eq 2 ]]; then
            echoContent yellow " ---> $(t CARPOOL_CANCELLED)"
            return 0
        fi
        [[ ${rc} -eq 0 ]] || return 1
        # 之前关过：沿用计数；旧的 apiPort 被别人占了就换一个
        state=$(jq -c '.enabled = true' <<<"${oldState}")
        if portListed "$(jq -r '.apiPort' <<<"${state}")" "$(listeningPorts tcp)"; then
            apiPort=$(carpoolPickApiPort) || { echoContent red " ---> $(t CARPOOL_API_PORT_FAILED)"; return 1; }
            state=$(jq -c --argjson p "${apiPort}" '.apiPort = $p' <<<"${state}")
        fi
    else
        apiPort=$(carpoolPickApiPort) || { echoContent red " ---> $(t CARPOOL_API_PORT_FAILED)"; return 1; }
        state=$(carpoolInitialState "${apiPort}" "$(carpoolPeriodStart "${today}" "$(jq -r '.resetDay' <<<"${normalized}")")")
    fi
    carpoolLock || return 1
    state=$(carpoolMergeState "${state}" "${normalized}" "${accounts}")
    if ! state=$(carpoolFillUuids "${state}"); then
        carpoolUnlock
        return 1
    fi
    if ! carpoolWriteState "${state}"; then
        carpoolUnlock
        echoContent red " ---> $(t CARPOOL_TICK_STATE_WRITE_FAILED)"
        return 1
    fi
    carpoolUnlock
    reloadCore
    apiPort=$(jq -r '.apiPort' <<<"${state}")
    if ! carpoolApiReady "${apiPort}"; then
        if carpoolLock; then
            state=$(carpoolReadState) && carpoolWriteState "$(jq -c '.enabled = false' <<<"${state}")"
            carpoolUnlock
        fi
        carpoolRemoveCron
        reloadCore
        echoContent red " ---> $(t CARPOOL_API_NOT_READY "${XRAY_CONF_DIR}/12_stats_api.json" "${apiPort}")"
        return 1
    fi
    carpoolTick
    echoContent green " ---> $(t CARPOOL_ENABLED)"
    echoContent yellow " ---> $(t CARPOOL_ENABLED_HINT "${CARPOOL_MEMBERS_FILE}")"
}

# carpoolDisable → 关闭 = 不再计量：Xray 在跑就先采一次，超额停用者恢复、到期与手动停用者保持（可选一并恢复）；
# 确认之后从重读 state 到翻 enabled=false 整段持锁（对账事务不 reload），事务失败整体不关闭
carpoolDisable() {
    local state newState groups today answer restoreAll=false kept
    if ! carpoolEnabled; then
        echoContent yellow " ---> $(t CARPOOL_NOT_ENABLED)"
        return 0
    fi
    carpoolCollectBeforeStop
    state=$(carpoolReadState) || return 1
    today=$(date +%F)
    groups=$(carpoolCloseGroups "${state}" "${today}")
    kept=$(jq -r '(.expiredNow + .keepExpired + .keepManual) | join(", ")' <<<"${groups}")
    echoContent skyBlue "\n$(t CARPOOL_CLOSE_TITLE)"
    echoContent yellow " ---> $(t CARPOOL_CLOSE_WILL_RESTORE): $(jq -r '.restore | join(", ") | if . == "" then "-" else . end' <<<"${groups}")"
    echoContent yellow " ---> $(t CARPOOL_CLOSE_KEEP_DISABLED): ${kept:--}"
    echoContent yellow " ---> $(t CARPOOL_CLOSE_UNTOUCHED): $(jq -r '[.members | to_entries[] | select(.value.status == "active") | .key] | join(", ") | if . == "" then "-" else . end' <<<"${state}")"
    read -r -p "$(t CARPOOL_CLOSE_CONFIRM)" answer
    if ! isYesInput "${answer}"; then
        echoContent yellow " ---> $(t CARPOOL_CANCELLED)"
        return 0
    fi
    if [[ -n "${kept}" ]]; then
        read -r -p "$(t CARPOOL_CLOSE_RESTORE_ALL)" answer
        isYesInput "${answer}" && restoreAll=true
    fi
    carpoolLock || return 1
    state=$(carpoolReadState)
    # 停在提示上的这段流量只能在这里收：enabled 翻掉后停止钩子直接返回，重载一清就没了
    newState=$(carpoolCollect "${state}") && state=${newState}
    newState=$(carpoolMachineStep "${state}") && state=${newState}
    groups=$(carpoolCloseGroups "${state}" "${today}")
    state=$(carpoolApplyClose "${state}" "${groups}" "${restoreAll}")
    if ! carpoolWriteState "${state}" || ! carpoolReconcile "${state}" >/dev/null; then
        carpoolUnlock
        echoContent red " ---> $(t CARPOOL_CLOSE_TX_FAILED)"
        return 1
    fi
    state=$(jq -c '.enabled = false | .pageEnabled = false | .pageToken = "" | del(.removing)' <<<"${state}")
    if ! carpoolWriteState "${state}"; then
        carpoolUnlock
        echoContent red " ---> $(t CARPOOL_TICK_STATE_WRITE_FAILED)"
        return 1
    fi
    carpoolUnlock
    carpoolRemoveCron
    carpoolRemovePages
    carpoolEnsureNginxLocation off
    carpoolSyncUserinfo
    reloadCore
    carpoolRefreshSubscribe
    carpoolWritePlaceholders "$(carpoolReadState)"
    local restoredList keptList
    restoredList=$(jq -r --argjson all "${restoreAll}" '(.restore + (if $all then .keepExpired + .keepManual else [] end)) | join(", ") | if . == "" then "-" else . end' <<<"${groups}")
    keptList=$(jq -r --argjson all "${restoreAll}" '(.expiredNow + (if $all then [] else .keepExpired + .keepManual end)) | join(", ") | if . == "" then "-" else . end' <<<"${groups}")
    echoContent green " ---> $(t CARPOOL_DISABLED)"
    echoContent yellow " ---> $(t CARPOOL_CLOSE_WILL_RESTORE): ${restoredList}"
    echoContent yellow " ---> $(t CARPOOL_CLOSE_KEEP_DISABLED): ${keptList}"
    echoContent yellow " ---> $(t CARPOOL_DISABLED_HINT)"
    carpoolNotifyEvents "$(jq -cn --arg r "${restoredList}" --arg k "${keptList}" '[{type: "closed", restored: $r, kept: $k}]')"
}

# carpoolHasTty → 0=标准输入是终端，删除成员与换 UUID 才能逐项确认
carpoolHasTty() {
    [[ -t 0 ]]
}

# carpoolApply → 应用 members.json：校验 → 显示差异 → 删除 / 换 UUID 逐项确认（非 tty 拒绝）→ 持锁重建成员表并判定 → settle
carpoolApply() {
    local installed map fileMembers errors normalized state accounts diff answer events name force=
    if ! carpoolEnabled; then
        echoContent yellow " ---> $(t CARPOOL_NOT_ENABLED)"
        return 1
    fi
    installed=$(scanInstalledProtocols "${XRAY_CONF_DIR}")
    map=$(carpoolCurrentClientsMap) || return 1
    fileMembers=$(jq -c '{members: (.members // {})}' "${CARPOOL_MEMBERS_FILE}" 2>/dev/null) || fileMembers='{"members": {}}'
    state=$(carpoolReadState) || return 1
    if ! errors=$(carpoolValidateMembers "${CARPOOL_MEMBERS_FILE}" "${installed}" "$(carpoolForeignAccounts "${fileMembers}" "${map}")" "$(carpoolRetiredNames "${state}")" "$(carpoolMemberUuids "${state}")"); then
        echoContent red " ---> $(t CARPOOL_MEMBERS_INVALID "${CARPOOL_MEMBERS_FILE}")"
        echo "${errors}"
        return 1
    fi
    normalized=$(carpoolNormalizeMembers "${CARPOOL_MEMBERS_FILE}")
    accounts=$(carpoolAllAccounts "${map}")
    diff=$(carpoolDiffMembers "${state}" "${normalized}" "${accounts}")
    if carpoolDiffIsEmpty "${diff}"; then
        echoContent green " ---> $(t CARPOOL_APPLY_NO_CHANGES)"
        return 0
    fi
    echoContent skyBlue "\n$(t CARPOOL_APPLY_TITLE)"
    carpoolDiffText "${diff}"
    if carpoolDiffNeedsConfirm "${diff}"; then
        if ! carpoolHasTty; then
            echoContent red " ---> $(t CARPOOL_APPLY_NEEDS_TTY)"
            return 1
        fi
        for name in $(jq -r '.removed[]' <<<"${diff}"); do
            read -r -p "$(t CARPOOL_APPLY_CONFIRM_REMOVE "${name}")" answer
            if ! isYesInput "${answer}"; then
                echoContent yellow " ---> $(t CARPOOL_CANCELLED)"
                return 0
            fi
        done
        for name in $(jq -r '.uuid[]' <<<"${diff}"); do
            read -r -p "$(t CARPOOL_APPLY_CONFIRM_UUID "${name}")" answer
            if ! isYesInput "${answer}"; then
                echoContent yellow " ---> $(t CARPOOL_CANCELLED)"
                return 0
            fi
        done
        force=1
    fi
    jq -e '(.added | length) > 0' <<<"${diff}" >/dev/null 2>&1 && force=1
    carpoolLock || return 1
    state=$(carpoolMergeState "$(carpoolReadState)" "${normalized}" "${accounts}")
    state=$(carpoolMarkRemoved "${state}" "$(jq -c '.removed' <<<"${diff}")")
    if ! state=$(carpoolFillUuids "${state}"); then
        carpoolUnlock
        return 1
    fi
    local summary applied
    summary=$(carpoolDiffText "$(jq -c '.unmanaged = []' <<<"${diff}")" | paste -sd ';' - | sed 's/;/ · /g')
    applied=$(jq -cn --arg s "${summary}" '[{type: "applied", summary: $s}]')
    if ! events=$(carpoolJudgeAndWrite "${state}" "$(date +%F)" "$(date '+%F %H:%M')" "${applied}"); then
        carpoolUnlock
        echoContent red " ---> $(t CARPOOL_TICK_STATE_WRITE_FAILED)"
        return 1
    fi
    carpoolUnlock
    for name in $(jq -r '.removed[]' <<<"${diff}"); do
        removeSubscriptionFiles "${name}"
        if ! chainAccountForget "${name}"; then
            echoContent red " ---> $(t CHAIN_ACCOUNT_FORGET_FAILED "${name}")"
        fi
    done
    carpoolSettle "${events}" "${force}" || return 1
    echoContent green " ---> $(t CARPOOL_APPLIED)"
}

# carpoolResetUsage → 菜单：清零单人或全员，随后判定一次（因超额停用的随之恢复）
carpoolResetUsage() {
    local choice name="" state events
    if ! carpoolEnabled; then
        echoContent yellow " ---> $(t CARPOOL_NOT_ENABLED)"
        return 1
    fi
    echoContent yellow "1.$(t CARPOOL_RESET_ALL)"
    echoContent yellow "2.$(t CARPOOL_RESET_ONE)"
    read -r -p "$(t CARPOOL_MENU_PROMPT)" choice
    case "${choice}" in
        1) ;;
        2)
            read -r -p "$(t CARPOOL_RESET_NAME_PROMPT)" name
            if ! carpoolIsValidMemberName "${name}" || ! jq -e --arg n "${name}" '.members[$n]' <<<"$(carpoolReadState)" >/dev/null 2>&1; then
                echoContent red " ---> $(t CARPOOL_RESET_NOT_MEMBER "${name}")"
                return 1
            fi
            ;;
        *)
            echoContent red " ---> $(t CARPOOL_MENU_BAD_CHOICE)"
            return 1
            ;;
    esac
    carpoolLock || return 1
    state=$(carpoolResetUsageState "$(carpoolReadState)" "${name}")
    if ! events=$(carpoolJudgeAndWrite "${state}" "$(date +%F)" "$(date '+%F %H:%M')"); then
        carpoolUnlock
        echoContent red " ---> $(t CARPOOL_TICK_STATE_WRITE_FAILED)"
        return 1
    fi
    carpoolUnlock
    carpoolSettle "${events}" || return 1
    echoContent green " ---> $(t CARPOOL_RESET_DONE)"
}

# carpoolShowUsage → 菜单：文本表（与页面同一份数据）
carpoolShowUsage() {
    local state n u q e st others
    if ! state=$(carpoolReadState); then
        echoContent yellow " ---> $(t CARPOOL_NOT_ENABLED)"
        return 0
    fi
    echoContent skyBlue "\n$(jq -r '.notify.label' <<<"${state}") · $(if [[ "$(jq -r '.enabled' <<<"${state}")" == "true" ]]; then t CARPOOL_USAGE_STATE_ON; else t CARPOOL_USAGE_STATE_OFF; fi)"
    echoContent yellow " ---> $(t CARPOOL_PAGE_PERIOD) $(jq -r '.period' <<<"${state}") · $(t CARPOOL_PAGE_NEXT_RESET) $(carpoolNextPeriodStart "$(date +%F)" "$(jq -r '.resetDay' <<<"${state}")") · $(t CARPOOL_USAGE_LAST_TICK) $(jq -r '.lastTick | if . == "" then "-" else . end' <<<"${state}")"
    echoContent yellow " ---> $(carpoolMachineSummary "${state}") · $(t CARPOOL_USAGE_IFACES "$(jq -r '(.machine.ifaces // []) | if length == 0 then "-" else join(", ") end' <<<"${state}")")"
    echoContent yellow " ---> $(t CARPOOL_UNIT_NOTE)\n"
    printf '%-24s %-12s %-12s %-12s %s\n' "$(t CARPOOL_PAGE_NAME)" "$(t CARPOOL_PAGE_USED)" "$(t CARPOOL_PAGE_QUOTA)" "$(t CARPOOL_PAGE_EXPIRE)" "$(t CARPOOL_PAGE_STATUS)"
    while IFS=$'\t' read -r n u q e st; do
        [[ -n "${n}" ]] && printf '%-24s %-12s %-12s %-12s %s\n' "${n}" "${u}" "${q}" "${e}" "${st}"
    done < <(carpoolUsageTable "${state}")
    others=$(carpoolForeignAccounts "${state}" "$(carpoolCurrentClientsMap)" | jq -r 'keys | join(", ")')
    [[ -n "${others}" ]] && echoContent yellow "\n ---> $(t CARPOOL_PAGE_OTHERS): ${others}"
    echo
}

# carpoolWritePage FILE HTML → mktemp + mv 原子落盘，644（nginx 要读）
carpoolWritePage() {
    local tmp
    tmp=$(mktemp "${CARPOOL_PAGE_DIR}/.page.XXXXXX") || return 1
    if ! printf '%s\n' "$2" >"${tmp}"; then
        rm -f "${tmp}"
        return 1
    fi
    chmod 644 "${tmp}"
    mv -f "${tmp}" "$1"
}

# carpoolRemovePages → 清空页面目录（只放页面，所以整目录清）
carpoolRemovePages() {
    [[ -d "${CARPOOL_PAGE_DIR}" ]] || return 0
    find "${CARPOOL_PAGE_DIR}" -maxdepth 1 -type f -delete
}

# carpoolReloadNginx → 配置已过 nginx -t 之后让它生效：在跑就 reload，没在跑就 start。
# 起不来只返回非零、不退出：关拼车要接着把账号放回去，菜单启动时升级订阅配置也不能把菜单挡在外面
carpoolReloadNginx() {
    if [[ -n $(nginxPids) ]]; then
        nginx -s reload >/dev/null 2>&1 && return 0
    fi
    (handleNginx start)
}

# carpoolInsertPageBlock SRC DEST → SRC 加上页面的 location 块（插在 location / 之前）写进 DEST。
# 块经临时文件喂给 awk：BSD awk 的 -v 不吃多行串
carpoolInsertPageBlock() {
    local blockFile rc=0
    blockFile=$(mktemp "${CARPOOL_DIR}/.nginx.XXXXXX") || return 1
    carpoolNginxLocationBlock "${CARPOOL_PAGE_DIR}" >"${blockFile}"
    awk -v f="${blockFile}" '/^    location \/ \{/ && !done { while ((getline line < f) > 0) print line; close(f); done = 1 } { print }' "$1" >"$2" || rc=1
    rm -f "${blockFile}"
    return "${rc}"
}

# carpoolSyncUserinfo → 成员用量写进 map，订阅响应才带 subscription-userinfo。用量每个 tick 都变，重载限成每小时至多一次；成员、配额、到期变了立刻生效。
# 只读 state，不拿锁。不用 carpoolReloadNginx：它会拉起没在跑的 nginx，tick 撞上安装流程停服的窗口会抢走 80 端口
carpoolSyncUserinfo() {
    local conf="${nginxConfigPath}subscribe.conf" state name value md5 body= tmp
    [[ -f "${conf}" ]] && grep -q 'paSubUserinfo' "${conf}" || return 0
    state=$(carpoolReadState) || return 0
    while IFS=$'\t' read -r name value; do
        [[ -n "${name}" ]] || continue
        md5=$(carpoolSubscribeMd5 "${name}") || continue
        body+="~/${md5}\$ \"${value}\";"$'\n'
    done < <(carpoolUserinfoTable "${state}")
    [[ "${body%$'\n'}" == "$(cat "${SUBSCRIBE_USERINFO_MAP}" 2>/dev/null)" ]] && return 0
    if [[ "$(sed -E 's/download=[0-9]+//' <<<"${body%$'\n'}")" == "$(sed -E 's/download=[0-9]+//' "${SUBSCRIBE_USERINFO_MAP}" 2>/dev/null)" ]] \
        && [[ -z "$(find "${SUBSCRIBE_USERINFO_MAP}" -mmin +59 2>/dev/null)" ]]; then
        return 0
    fi
    # map 里有订阅地址的 md5，mktemp 的 0600 正好；nginx 的 master 是 root，读得到
    tmp=$(mktemp "${SUBSCRIBE_USERINFO_MAP}.XXXXXX") || return 0
    printf '%s' "${body}" >"${tmp}" && mv -f "${tmp}" "${SUBSCRIBE_USERINFO_MAP}"
    if [[ -n $(nginxPids) ]] && nginx -t >/dev/null 2>&1; then
        nginx -s reload >/dev/null 2>&1
    fi
    return 0
}

# carpoolEnsureNginxLocation on|off → subscribe.conf 里加 / 删页面的 location 块（按标记判重）；
# 改完过 nginx -t，不过就还原，不动订阅现有 location 的形状
carpoolEnsureNginxLocation() {
    local conf="${nginxConfigPath}subscribe.conf" has=
    [[ -f "${conf}" ]] || return 0
    grep -q '# carpool-page-begin' "${conf}" && has=1
    if [[ "$1" == "on" && -z "${has}" ]]; then
        cp -f "${conf}" "${conf}.carpool.bak"
        carpoolInsertPageBlock "${conf}.carpool.bak" "${conf}" || { mv -f "${conf}.carpool.bak" "${conf}"; return 1; }
    elif [[ "$1" == "off" && -n "${has}" ]]; then
        cp -f "${conf}" "${conf}.carpool.bak"
        sed '/# carpool-page-begin/,/# carpool-page-end/d' "${conf}.carpool.bak" >"${conf}" || { mv -f "${conf}.carpool.bak" "${conf}"; return 1; }
    else
        return 0
    fi
    if nginx -t >/dev/null 2>&1; then
        rm -f "${conf}.carpool.bak"
        carpoolReloadNginx
    else
        mv -f "${conf}.carpool.bak" "${conf}"
        echoContent red " ---> $(t CARPOOL_PAGE_NGINX_FAILED)"
        return 1
    fi
}

# carpoolPendingText STATE → 页面顶部的提示：members.json 与 state 有差异就列出来，文件无效就说明；都没有输出空
carpoolPendingText() {
    local installed map fileMembers normalized diff
    installed=$(scanInstalledProtocols "${XRAY_CONF_DIR}")
    map=$(carpoolCurrentClientsMap) || return 0
    fileMembers=$(jq -c '{members: (.members // {})}' "${CARPOOL_MEMBERS_FILE}" 2>/dev/null) || fileMembers='{"members": {}}'
    if ! carpoolValidateMembers "${CARPOOL_MEMBERS_FILE}" "${installed}" "$(carpoolForeignAccounts "${fileMembers}" "${map}")" "$(carpoolRetiredNames "$1")" "$(carpoolMemberUuids "$1")" >/dev/null; then
        t CARPOOL_PAGE_FILE_INVALID
        echo
        return 0
    fi
    normalized=$(carpoolNormalizeMembers "${CARPOOL_MEMBERS_FILE}")
    diff=$(carpoolDiffMembers "$1" "${normalized}" "$(carpoolAllAccounts "${map}")")
    carpoolDiffIsEmpty "${diff}" && return 0
    t CARPOOL_PAGE_PENDING "$(carpoolDiffText "$(jq -c '.unmanaged = []' <<<"${diff}")" | paste -sd ';' - | sed 's/;/ · /g')"
    echo
}

# carpoolRenderPages → 页面开着就重生成车主页与成员页（期望集合之外的文件删掉），并确保 nginx location 在；关着就清空目录
carpoolRenderPages() {
    local state token today now meta others pending name key html keep=() file base
    state=$(carpoolReadState) || return 0
    if [[ "$(jq -r '.enabled and .pageEnabled' <<<"${state}")" != "true" ]]; then
        carpoolRemovePages
        return 0
    fi
    token=$(jq -r '.pageToken' <<<"${state}")
    [[ "${token}" =~ ^[0-9a-f]{32,64}$ ]] || return 1
    mkdir -p "${CARPOOL_PAGE_DIR}" && chmod 755 "${CARPOOL_PAGE_DIR}"
    today=$(date +%F)
    now=$(date '+%F %H:%M')
    meta=$(jq -c '{resetDay, notify}' <<<"${state}")
    others=$(carpoolForeignAccounts "${state}" "$(carpoolCurrentClientsMap)" | jq -c 'keys')
    pending=$(carpoolPendingText "${state}")
    html=$(carpoolRenderOwnerPage "${state}" "${meta}" "${today}" "${now}" "${others}" "${pending}") || return 1
    if ! carpoolWritePage "${CARPOOL_PAGE_DIR}/${token}" "${html}"; then
        echoContent red " ---> $(t CARPOOL_PAGE_WRITE_FAILED "${CARPOOL_PAGE_DIR}/${token}")"
        return 1
    fi
    keep+=("${token}")
    for name in $(jq -r '.members | keys_unsorted[]' <<<"${state}"); do
        key=$(carpoolMemberPageKey "${token}" "${name}") || continue
        html=$(carpoolRenderMemberPage "${state}" "${meta}" "${name}" "${today}" "${now}") || continue
        carpoolWritePage "${CARPOOL_PAGE_DIR}/${key}" "${html}" && keep+=("${key}")
    done
    while IFS= read -r file; do
        base=${file##*/}
        [[ " ${keep[*]} " == *" ${base} "* ]] || find "${CARPOOL_PAGE_DIR}" -maxdepth 1 -type f -name "${base}" -delete
    done < <(find "${CARPOOL_PAGE_DIR}" -maxdepth 1 -type f)
    carpoolEnsureNginxLocation on
}

# carpoolPageUrlBase → 页面链接前缀，与订阅同一域名 / 端口 / 协议；订阅没装返回 1
carpoolPageUrlBase() {
    local domain
    readNginxSubscribe
    [[ -n "${subscribePort}" ]] || return 1
    if [[ "${subscribeType}" == "http" ]]; then
        domain="$(getPublicIP):${subscribePort}"
    else
        domain="${currentHost}:${subscribePort}"
    fi
    printf '%s://%s/s/carpool/\n' "${subscribeType}" "${domain}"
}

# carpoolShowPageLinks → 打印车主页与各成员页链接
carpoolShowPageLinks() {
    local state base name key token
    state=$(carpoolReadState) || return 1
    if [[ "$(jq -r '.pageEnabled' <<<"${state}")" != "true" ]]; then
        echoContent yellow " ---> $(t CARPOOL_PAGE_STATUS_OFF)"
        return 0
    fi
    if ! base=$(carpoolPageUrlBase); then
        echoContent red " ---> $(t CARPOOL_PAGE_NEEDS_SUBSCRIBE)"
        return 1
    fi
    token=$(jq -r '.pageToken' <<<"${state}")
    echoContent green " ---> $(t CARPOOL_PAGE_OWNER_LINK): ${base}${token}"
    for name in $(jq -r '.members | keys_unsorted[]' <<<"${state}"); do
        key=$(carpoolMemberPageKey "${token}" "${name}") || continue
        echoContent yellow " ---> $(t CARPOOL_PAGE_MEMBER_LINK) ${name}: ${base}${key}"
    done
}

# carpoolPageSetToken TOKEN|"" → 持锁改 state 的 pageEnabled / pageToken（空串即关闭）
carpoolPageSetToken() {
    local state
    carpoolLock || return 1
    state=$(jq -c --arg tk "$1" '.pageToken = $tk | .pageEnabled = ($tk != "")' <<<"$(carpoolReadState)")
    if ! carpoolWriteState "${state}"; then
        carpoolUnlock
        echoContent red " ---> $(t CARPOOL_TICK_STATE_WRITE_FAILED)"
        return 1
    fi
    carpoolUnlock
}

# carpoolPageEnable → 开启页面：要订阅已装；HTTP 订阅提示一次；生成 32 位十六进制令牌，渲染并发布
carpoolPageEnable() {
    local token
    if ! carpoolEnabled; then
        echoContent yellow " ---> $(t CARPOOL_NOT_ENABLED)"
        return 1
    fi
    readNginxSubscribe
    if [[ -z "${subscribePort}" ]]; then
        echoContent red " ---> $(t CARPOOL_PAGE_NEEDS_SUBSCRIBE)"
        return 1
    fi
    [[ "${subscribeType}" == "http" ]] && echoContent yellow " ---> $(t CARPOOL_PAGE_HTTP_WARNING)"
    token=$(openssl rand -hex 16 2>/dev/null)
    [[ "${token}" =~ ^[0-9a-f]{32}$ ]] || return 1
    carpoolPageSetToken "${token}" || return 1
    carpoolRenderPages || return 1
    echoContent green " ---> $(t CARPOOL_PAGE_STATUS_ON)"
    carpoolShowPageLinks
}

# carpoolPageDisable → 关闭页面：删文件、撤 location、清 state 里的令牌
carpoolPageDisable() {
    carpoolPageSetToken "" || return 1
    carpoolRemovePages
    carpoolEnsureNginxLocation off
    echoContent green " ---> $(t CARPOOL_PAGE_DISABLED)"
}

# carpoolTelegramMask → 配置状态一行（只露 token 的数字段，不露密钥）
carpoolTelegramMask() {
    local conf
    if conf=$(carpoolReadTelegramConf "${CARPOOL_TELEGRAM_FILE}"); then
        printf '%s (%s:*** → %s)\n' "$(t CARPOOL_TG_STATUS_ON)" "$(sed -n 1p <<<"${conf}" | cut -d: -f1)" "$(sed -n 2p <<<"${conf}")"
    else
        t CARPOOL_TG_STATUS_OFF
        echo
    fi
}

# carpoolTelegramConfigure → 读 token（不回显）与 chat id，格式校验后写 telegram.conf（0600），再发一条测试消息
carpoolTelegramConfigure() {
    local token chat
    read -r -s -p "$(t CARPOOL_TG_TOKEN_PROMPT)" token
    echo
    if ! [[ "${token}" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]]; then
        echoContent red " ---> $(t CARPOOL_TG_BAD_TOKEN)"
        return 1
    fi
    read -r -p "$(t CARPOOL_TG_CHAT_PROMPT)" chat
    if ! [[ "${chat}" =~ ^-?[0-9]{1,20}$ ]]; then
        echoContent red " ---> $(t CARPOOL_TG_BAD_CHAT)"
        return 1
    fi
    mkdir -p "${CARPOOL_DIR}" && chmod 700 "${CARPOOL_DIR}"
    (umask 077 && printf 'TG_BOT_TOKEN=%s\nTG_CHAT_ID=%s\n' "${token}" "${chat}" >"${CARPOOL_TELEGRAM_FILE}") || return 1
    chmod 600 "${CARPOOL_TELEGRAM_FILE}"
    echoContent green " ---> $(t CARPOOL_TG_SAVED "${CARPOOL_TELEGRAM_FILE}")"
    carpoolTelegramTest
}

# carpoolTelegramTest → 发一条测试消息
carpoolTelegramTest() {
    local label
    if ! carpoolReadTelegramConf "${CARPOOL_TELEGRAM_FILE}" >/dev/null; then
        echoContent yellow " ---> $(t CARPOOL_TG_STATUS_OFF)"
        return 1
    fi
    label=$(carpoolReadState 2>/dev/null | jq -r '.notify.label // empty' 2>/dev/null)
    if carpoolTelegramSend "[${label:-$(t CARPOOL_DEFAULT_LABEL)}]"$'\n'"$(t CARPOOL_TG_TEST_TEXT)"; then
        echoContent green " ---> $(t CARPOOL_TG_SENT)"
    fi
}

# carpoolTelegramDisable → 删掉 telegram.conf
carpoolTelegramDisable() {
    rm -f "${CARPOOL_TELEGRAM_FILE}"
    echoContent green " ---> $(t CARPOOL_TG_DISABLED "${CARPOOL_TELEGRAM_FILE}")"
}

# carpoolPageMenu → 拼车管理 → 页面与通知
carpoolPageMenu() {
    local choice pageOn=
    [[ "$(carpoolReadState 2>/dev/null | jq -r '.pageEnabled' 2>/dev/null)" == "true" ]] && pageOn=1
    echoContent skyBlue "\n$(t CARPOOL_PAGE_TITLE)"
    echoContent yellow " ---> $(if [[ -n "${pageOn}" ]]; then t CARPOOL_PAGE_STATUS_ON; else t CARPOOL_PAGE_STATUS_OFF; fi) · $(carpoolTelegramMask)"
    echoContent skyBlue "=============================================================="
    if [[ -n "${pageOn}" ]]; then
        echoContent yellow "1.$(t CARPOOL_PAGE_OFF)"
    else
        echoContent yellow "1.$(t CARPOOL_PAGE_ON)"
    fi
    echoContent yellow "2.$(t CARPOOL_PAGE_LINKS)"
    echoContent yellow "3.$(t CARPOOL_PAGE_REGEN)"
    echoContent yellow "4.$(t CARPOOL_TG_CONFIGURE)"
    echoContent yellow "5.$(t CARPOOL_TG_TEST)"
    echoContent yellow "6.$(t CARPOOL_TG_DISABLE)"
    echoContent skyBlue "=============================================================="
    read -r -p "$(t CARPOOL_MENU_PROMPT)" choice
    case "${choice}" in
        1) if [[ -n "${pageOn}" ]]; then carpoolPageDisable; else carpoolPageEnable; fi ;;
        2) carpoolShowPageLinks ;;
        3)
            if [[ -z "${pageOn}" ]]; then
                echoContent yellow " ---> $(t CARPOOL_PAGE_STATUS_OFF)"
            elif carpoolPageEnable; then
                echoContent yellow " ---> $(t CARPOOL_PAGE_TOKEN_REGENERATED)"
            fi
            ;;
        4) carpoolTelegramConfigure ;;
        5) carpoolTelegramTest ;;
        6) carpoolTelegramDisable ;;
        *) echoContent red " ---> $(t CARPOOL_MENU_BAD_CHOICE)" ;;
    esac
}

# carpoolMembersClean → 0=members.json 过得了校验、也没有没应用的改动。成员管理只在这时动文件：
# 否则车主手改了一半的东西会跟着菜单这一项一起应用
carpoolMembersClean() {
    local state pending
    state=$(carpoolReadState) || return 1
    pending=$(carpoolPendingText "${state}")
    [[ -z "${pending}" ]] && return 0
    echoContent yellow " ---> ${pending}"
    echoContent yellow " ---> $(t CARPOOL_MEMBER_PENDING_HINT)"
    return 1
}

# carpoolMembersEditApply FILTER [JQ_ARGS...] → 用 jq 改 members.json 再走 carpoolApply；没应用成（校验不过、车主取消、失败）
# 就把文件逐字改回，不留一份和 state 对不上的文件。0=已应用
carpoolMembersEditApply() {
    local filter=$1 backup="${CARPOOL_DIR}/.members.menu.bak" new
    shift
    cp -f "${CARPOOL_MEMBERS_FILE}" "${backup}" || return 1
    if ! new=$(jq "$@" "${filter}" "${CARPOOL_MEMBERS_FILE}") || ! jsonWriteFile "${CARPOOL_MEMBERS_FILE}" "${new}" false; then
        rm -f "${backup}"
        return 1
    fi
    carpoolApply
    if [[ -n "$(carpoolPendingText "$(carpoolReadState)")" ]]; then
        cp -f "${backup}" "${CARPOOL_MEMBERS_FILE}"
        rm -f "${backup}"
        echoContent yellow " ---> $(t CARPOOL_MEMBER_REVERTED)"
        return 1
    fi
    rm -f "${backup}"
}

# carpoolPickMember → 列出 members.json 里的成员让车主选，名字放在 carpoolPicked；没有成员或输错返回 1
carpoolPickMember() {
    local names=() i pick
    mapfile -t names < <(jq -r '.members | keys_unsorted[]' "${CARPOOL_MEMBERS_FILE}")
    if ((${#names[@]} == 0)); then
        echoContent yellow " ---> $(t CARPOOL_MEMBER_NONE)"
        return 1
    fi
    for i in "${!names[@]}"; do
        echoContent yellow "$((i + 1)).$(jq -r --arg n "${names[i]}" --arg u "$(t CARPOOL_UNLIMITED)" '.members[$n] as $m
            | "\($n) · \(if ($m.quotaGiB // 0) > 0 then "\($m.quotaGiB) GiB" else $u end) · \(if ($m.expire // "") == "" then "-" else $m.expire end)"
              + " · \($m.protocols // "all" | if type == "array" then map(tostring) | join(",") else tostring end)"' "${CARPOOL_MEMBERS_FILE}")"
    done
    read -r -p "$(t CARPOOL_MEMBER_PICK)" pick
    if [[ ! "${pick}" =~ ^[0-9]{1,4}$ ]] || ((10#${pick} < 1 || 10#${pick} > ${#names[@]})); then
        echoContent red " ---> $(t CARPOOL_MENU_BAD_CHOICE)"
        return 1
    fi
    carpoolPicked=${names[10#${pick} - 1]}
}

# carpoolAsk quota|expire|protocols PROMPT [CURRENT_EXPIRE] → 读一项成员设置，输错就重问，结果放在 carpoolAnswer：
# quota 是整数 GiB，expire 是日期，protocols 是 JSON（"all" 或编号数组）。直接回车返回 2（取消还是取默认由调用方定），读不到输入返回 1
carpoolAsk() {
    local input
    while true; do
        read -r -p "$2" input || return 1
        [[ -z "${input}" ]] && return 2
        case "$1" in
            quota)
                if [[ "${input}" =~ ^[0-9]{1,9}$ ]]; then
                    carpoolAnswer=$((10#${input}))
                    return 0
                fi
                echoContent red " ---> $(t CARPOOL_MEMBER_QUOTA_BAD)"
                ;;
            expire)
                if carpoolAnswer=$(carpoolExpireFromInput "${input}" "${3:-}" "$(date +%F)") && [[ -n "${carpoolAnswer}" ]]; then
                    return 0
                fi
                echoContent red " ---> $(t CARPOOL_MEMBER_EXPIRE_BAD)"
                ;;
            protocols)
                if [[ "${input,,}" == "all" ]]; then
                    carpoolAnswer='"all"'
                    return 0
                fi
                if [[ "${input}" =~ ^[0-9]{1,2}([[:space:],]+[0-9]{1,2})*$ ]]; then
                    carpoolAnswer=$(jq -cn --arg s "${input}" '[$s | splits("[\\s,]+") | select(. != "") | tonumber] | unique')
                    return 0
                fi
                echoContent red " ---> $(t CARPOOL_MEMBER_PROTOCOLS_BAD)"
                ;;
        esac
    done
}

# carpoolShowProtocolChoices → 列出成员可选的协议（本机装了、拼车能计量的）
carpoolShowProtocolChoices() {
    local id
    echoContent yellow "$(t CARPOOL_MEMBER_PROTOCOLS_LIST)"
    for id in $(carpoolInstalledProtocolsJson "$(scanInstalledProtocols "${XRAY_CONF_DIR}")" | jq -r '.[]'); do
        echoContent yellow "  ${id}: $(getProtocolDisplayName "${id}")"
    done
}

# carpoolShowMemberLinks NAME → 打印这个成员的通用订阅地址，页面开着时再打印成员页；没装订阅就指到「查看账号」
carpoolShowMemberLinks() {
    local base md5 state key
    if ! base=$(carpoolPageUrlBase) || ! md5=$(carpoolSubscribeMd5 "$1"); then
        echoContent yellow " ---> $(t CARPOOL_MEMBER_NO_SUB "$1")"
        return 0
    fi
    echoContent green " ---> $(t CARPOOL_MEMBER_SUB_LINK "$1" "${base%carpool/}${md5}")"
    state=$(carpoolReadState) || return 0
    if [[ "$(jq -r '.pageEnabled' <<<"${state}")" == "true" ]] && key=$(carpoolMemberPageKey "$(jq -r '.pageToken' <<<"${state}")" "$1"); then
        echoContent green " ---> $(t CARPOOL_MEMBER_PAGE_LINK "$1" "${base}${key}")"
    fi
}

# carpoolMemberAdd → 加成员：名字、每周期额度、到期、协议；UUID 留给应用时生成，应用成功后打印他的订阅与成员页地址
carpoolMemberAdd() {
    local name quota expire protocols rc
    carpoolMembersClean || return 1
    while true; do
        read -r -p "$(t CARPOOL_MEMBER_NAME_PROMPT)" name || return 1
        if [[ -z "${name}" ]]; then
            echoContent yellow " ---> $(t CARPOOL_CANCELLED)"
            return 0
        fi
        if ! carpoolIsValidMemberName "${name}"; then
            echoContent red " ---> $(t CARPOOL_MEMBER_NAME_BAD)"
        elif jq -e --arg n "${name}" '.members | has($n)' "${CARPOOL_MEMBERS_FILE}" >/dev/null 2>&1; then
            echoContent red " ---> $(t CARPOOL_MEMBER_NAME_EXISTS "${name}")"
        else
            break
        fi
    done
    carpoolAsk quota "$(t CARPOOL_MEMBER_QUOTA_PROMPT)"
    rc=$?
    case ${rc} in 0) quota=${carpoolAnswer} ;; 2) quota=0 ;; *) return 1 ;; esac
    carpoolAsk expire "$(t CARPOOL_MEMBER_EXPIRE_PROMPT)"
    rc=$?
    case ${rc} in 0) expire=${carpoolAnswer} ;; 2) expire= ;; *) return 1 ;; esac
    carpoolShowProtocolChoices
    carpoolAsk protocols "$(t CARPOOL_MEMBER_PROTOCOLS_ADD_PROMPT)"
    rc=$?
    case ${rc} in 0) protocols=${carpoolAnswer} ;; 2) protocols='"all"' ;; *) return 1 ;; esac
    carpoolMembersEditApply '.members[$n] = {quotaGiB: $q, expire: $e, protocols: $p}' \
        --arg n "${name}" --argjson q "${quota}" --arg e "${expire}" --argjson p "${protocols}" || return 1
    carpoolShowMemberLinks "${name}"
}

# carpoolMemberEdit renew|quota|protocols|uuid|remove → 选一个成员改一项，删人与换 UUID 的逐项确认在 carpoolApply 里
carpoolMemberEdit() {
    local name current rc u
    carpoolMembersClean || return 1
    carpoolPickMember || return 1
    name=${carpoolPicked}
    case "$1" in
        renew)
            current=$(jq -r --arg n "${name}" '.members[$n].expire // ""' "${CARPOOL_MEMBERS_FILE}")
            carpoolAsk expire "$(t CARPOOL_MEMBER_RENEW_PROMPT "${current:-$(t CARPOOL_UNLIMITED)}")" "${current}"
            rc=$?
            ;;
        quota)
            current=$(jq -r --arg n "${name}" '.members[$n].quotaGiB // 0' "${CARPOOL_MEMBERS_FILE}")
            carpoolAsk quota "$(t CARPOOL_MEMBER_QUOTA_EDIT_PROMPT "${current}")"
            rc=$?
            ;;
        protocols)
            carpoolShowProtocolChoices
            carpoolAsk protocols "$(t CARPOOL_MEMBER_PROTOCOLS_EDIT_PROMPT)"
            rc=$?
            ;;
        *) rc=0 ;;
    esac
    if ((rc == 2)); then
        echoContent yellow " ---> $(t CARPOOL_CANCELLED)"
        return 0
    fi
    ((rc == 0)) || return 1
    case "$1" in
        renew) carpoolMembersEditApply '.members[$n].expire = $e' --arg n "${name}" --arg e "${carpoolAnswer}" ;;
        quota) carpoolMembersEditApply '.members[$n].quotaGiB = $q' --arg n "${name}" --argjson q "${carpoolAnswer}" ;;
        protocols) carpoolMembersEditApply '.members[$n].protocols = $p' --arg n "${name}" --argjson p "${carpoolAnswer}" ;;
        remove) carpoolMembersEditApply 'del(.members[$n])' --arg n "${name}" ;;
        uuid)
            u=$(${XRAY_BIN} uuid 2>/dev/null)
            if ! carpoolIsValidUUID "${u}"; then
                echoContent red " ---> $(t CARPOOL_UUID_GEN_FAILED)"
                return 1
            fi
            carpoolMembersEditApply '.members[$n].uuid = $u' --arg n "${name}" --arg u "${u}" || return 1
            # 新凭据已在 state 里，文件里不留（与开启时播种的文件一样）；文件里没有 uuid 时应用沿用 state 的
            jsonWriteFile "${CARPOOL_MEMBERS_FILE}" "$(jq --arg n "${name}" 'del(.members[$n].uuid)' "${CARPOOL_MEMBERS_FILE}")" false
            echoContent green " ---> $(t CARPOOL_MEMBER_UUID_DONE "${name}")"
            ;;
    esac
}

# carpoolMemberMenu → 拼车管理 → 成员管理；每项只改 members.json，再走与「应用配置文件」同一条路
carpoolMemberMenu() {
    local choice
    echoContent skyBlue "\n$(t CARPOOL_MENU_MEMBERS)"
    echoContent skyBlue "=============================================================="
    echoContent yellow "1.$(t CARPOOL_MEMBER_ADD)"
    echoContent yellow "2.$(t CARPOOL_MEMBER_RENEW)"
    echoContent yellow "3.$(t CARPOOL_MEMBER_QUOTA)"
    echoContent yellow "4.$(t CARPOOL_MEMBER_PROTOCOLS)"
    echoContent yellow "5.$(t CARPOOL_MEMBER_UUID)"
    echoContent yellow "6.$(t CARPOOL_MEMBER_REMOVE)"
    echoContent skyBlue "=============================================================="
    read -r -p "$(t CARPOOL_MENU_PROMPT)" choice
    case "${choice}" in
        1) carpoolMemberAdd ;;
        2) carpoolMemberEdit renew ;;
        3) carpoolMemberEdit quota ;;
        4) carpoolMemberEdit protocols ;;
        5) carpoolMemberEdit uuid ;;
        6) carpoolMemberEdit remove ;;
        *) echoContent red " ---> $(t CARPOOL_MENU_BAD_CHOICE)" ;;
    esac
}

# carpoolMenu → 账号管理 → 拼车管理
carpoolMenu() {
    local choice
    echoContent skyBlue "\n$(t CARPOOL_MENU_TITLE)"
    echoContent skyBlue "=============================================================="
    echoContent yellow "1.$(t CARPOOL_MENU_USAGE)"
    echoContent yellow "2.$(t CARPOOL_MENU_APPLY)"
    echoContent yellow "3.$(t CARPOOL_MENU_RESET)"
    if carpoolEnabled; then
        echoContent yellow "4.$(t CARPOOL_MENU_DISABLE)"
    else
        echoContent yellow "4.$(t CARPOOL_MENU_ENABLE)"
    fi
    echoContent yellow "5.$(t CARPOOL_MENU_PAGE)"
    if carpoolEnabled; then
        echoContent yellow "6.$(t CARPOOL_MENU_MEMBERS)"
    fi
    echoContent skyBlue "=============================================================="
    read -r -p "$(t CARPOOL_MENU_PROMPT)" choice
    case "${choice}" in
        1) carpoolShowUsage ;;
        2) carpoolApply ;;
        3) carpoolResetUsage ;;
        4) if carpoolEnabled; then carpoolDisable; else carpoolEnable; fi ;;
        5) carpoolPageMenu ;;
        6) if carpoolEnabled; then carpoolMemberMenu; else echoContent red " ---> $(t CARPOOL_MENU_BAD_CHOICE)"; fi ;;
        *) echoContent red " ---> $(t CARPOOL_MENU_BAD_CHOICE)" ;;
    esac
}

# ======================= 脚本版本管理 =======================

# snapshotConfig DEST_DIR → 0=至少快照了一项，1=全部源缺失或目标不可写
# 快照 xray / sing-box / tls / lang_pref，供 backupScript 与 rollback 用。
backupConfigSnapshot() {
    local destDir="$1"
    local installDir="${PROXY_AGENT_DIR}"
    [[ -z "${destDir}" ]] && return 1
    mkdir -p "${destDir}" || return 1

    local copied=0
    # xray 配置目录（含 inbound/routing 片段）
    if [[ -d "${installDir}/xray/conf" ]]; then
        mkdir -p "${destDir}/xray"
        cp -rf "${installDir}/xray/conf" "${destDir}/xray/" 2>/dev/null && copied=1
    fi
    # sing-box 配置目录的整个父目录（含 conf/config/ 片段 + chain_*_info.json + external_node_info.json）
    if [[ -d "${installDir}/sing-box/conf" ]]; then
        mkdir -p "${destDir}/sing-box"
        cp -rf "${installDir}/sing-box/conf" "${destDir}/sing-box/" 2>/dev/null && copied=1
    fi
    # TLS 证书与 acme 账户状态
    if [[ -d "${installDir}/tls" ]]; then
        cp -rf "${installDir}/tls" "${destDir}/" 2>/dev/null && copied=1
    fi
    # 语言偏好
    if [[ -f "${installDir}/lang_pref" ]]; then
        cp -f "${installDir}/lang_pref" "${destDir}/" 2>/dev/null && copied=1
    fi
    # 拼车成员文件与状态
    if [[ -d "${installDir}/carpool" ]]; then
        cp -rf "${installDir}/carpool" "${destDir}/" 2>/dev/null && copied=1
    fi

    [[ ${copied} -eq 1 ]]
}

# restoreConfig SRC_DIR → 0=成功（至少一项），1=源不存在或全缺
# 调用方负责 stop/start，且必须先做 pre-restore 快照——失败时已替换的部分不自动回滚。
restoreConfigSnapshot() {
    local sourceDir="$1"
    local installDir="${PROXY_AGENT_DIR}"
    [[ -z "${sourceDir}" || ! -d "${sourceDir}" ]] && return 1

    local restored=0
    if [[ -d "${sourceDir}/xray/conf" ]]; then
        mkdir -p "${installDir}/xray"
        rm -rf "${installDir}/xray/conf"
        cp -rf "${sourceDir}/xray/conf" "${installDir}/xray/" 2>/dev/null && restored=1
    fi
    if [[ -d "${sourceDir}/sing-box/conf" ]]; then
        mkdir -p "${installDir}/sing-box"
        rm -rf "${installDir}/sing-box/conf"
        cp -rf "${sourceDir}/sing-box/conf" "${installDir}/sing-box/" 2>/dev/null && restored=1
    fi
    if [[ -d "${sourceDir}/tls" ]]; then
        rm -rf "${installDir}/tls"
        cp -rf "${sourceDir}/tls" "${installDir}/" 2>/dev/null && restored=1
    fi
    if [[ -f "${sourceDir}/lang_pref" ]]; then
        cp -f "${sourceDir}/lang_pref" "${installDir}/" 2>/dev/null && restored=1
    fi
    # 快照里有 carpool/ 才覆盖：回滚到开拼车之前的快照不能把车主手写的 members.json 删掉。
    # 现场的 state.json 留着：它是计量数据，换成快照里的就把用量倒回快照那天，停机钩子刚收的那笔也丢了
    if [[ -d "${sourceDir}/carpool" ]]; then
        local liveState=
        if [[ -f "${installDir}/carpool/state.json" ]]; then
            liveState=$(mktemp "${installDir}/.carpool-state.XXXXXX") && cp -pf "${installDir}/carpool/state.json" "${liveState}" || return 1
        fi
        rm -rf "${installDir}/carpool"
        cp -rf "${sourceDir}/carpool" "${installDir}/" 2>/dev/null && restored=1
        if [[ -n "${liveState}" ]]; then
            mkdir -p "${installDir}/carpool" && mv -f "${liveState}" "${installDir}/carpool/state.json"
        else
            rm -f "${installDir}/carpool/state.json"
        fi
    fi

    [[ ${restored} -eq 1 ]]
}

# 备份脚本
# 参数: $1 - 备份原因 (update/manual/rollback)
backupScript() {
    local reason="${1:-manual}"
    local installDir="${PROXY_AGENT_DIR}"
    local backupDir="${installDir}/backup"
    local maxBackups=5

    # 确保备份目录存在
    mkdir -p "${backupDir}"

    # 获取当前版本号
    local currentVersion=""
    if [[ -f "${installDir}/VERSION" ]]; then
        currentVersion=$(cat "${installDir}/VERSION" 2>/dev/null | tr -d '[:space:]')
    else
        currentVersion="unknown"
    fi

    # 生成备份文件名 (版本_日期时间)
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backupName="v${currentVersion}_${timestamp}"
    local backupPath="${backupDir}/${backupName}"

    mkdir -p "${backupPath}"

    # 备份核心文件
    if [[ -f "${installDir}/install.sh" ]]; then
        cp -f "${installDir}/install.sh" "${backupPath}/"
    fi
    if [[ -f "${installDir}/VERSION" ]]; then
        cp -f "${installDir}/VERSION" "${backupPath}/"
    fi
    if [[ -d "${installDir}/lib" ]]; then
        cp -rf "${installDir}/lib" "${backupPath}/"
    fi
    if [[ -d "${installDir}/shell/lang" ]]; then
        mkdir -p "${backupPath}/shell"
        cp -rf "${installDir}/shell/lang" "${backupPath}/shell/"
    fi

    # 配置快照（xray/sing-box/tls/lang_pref）。stderr 走 /dev/null
    # 失败不阻断脚本备份本身——首装、未配置等场景全源缺失是正常的
    local hasConfig="false"
    if backupConfigSnapshot "${backupPath}/config" 2>/dev/null; then
        hasConfig="true"
    fi

    # 记录备份信息
    cat > "${backupPath}/backup_info.json" << EOF
{
    "version": "${currentVersion}",
    "timestamp": "${timestamp}",
    "reason": "${reason}",
    "date": "$(date '+%Y-%m-%d %H:%M:%S')",
    "has_config": ${hasConfig}
}
EOF

    # 清理旧备份，保留最近 N 个
    local backupCount
    backupCount=$(ls -1d "${backupDir}"/v* 2>/dev/null | wc -l)
    if [[ ${backupCount} -gt ${maxBackups} ]]; then
        ls -1td "${backupDir}"/v* 2>/dev/null | tail -n +$((maxBackups + 1)) | xargs rm -rf 2>/dev/null
    fi

    echo "${backupPath}"
}

# 列出可用的脚本版本（本地备份 + GitHub 历史版本）
listScriptVersions() {
    local installDir="${PROXY_AGENT_DIR}"
    local backupDir="${installDir}/backup"

    echoContent skyBlue "\n$(t SCRIPT_VERSION_ROLLBACK)"
    echoContent red "\n=============================================================="
    echoContent yellow "# $(t NOTE)"
    echoContent yellow "# 1. $(t SCRIPT_ROLLBACK_NOTE1)"
    echoContent yellow "# 2. $(t SCRIPT_ROLLBACK_NOTE2)"
    echoContent yellow "# 3. $(t SCRIPT_ROLLBACK_NOTE3)\n"

    # 显示当前版本
    local currentVersion=""
    if [[ -f "${installDir}/VERSION" ]]; then
        currentVersion=$(cat "${installDir}/VERSION" 2>/dev/null | tr -d '[:space:]')
    fi
    echoContent green "$(t SCRIPT_VERSION_CURRENT): v${currentVersion:-unknown}\n"

    # 列出本地备份
    echoContent skyBlue "------------------------$(t SCRIPT_ROLLBACK_LOCAL)-------------------------------"
    local index=1
    local backupList=()

    if [[ -d "${backupDir}" ]]; then
        while IFS= read -r backup; do
            if [[ -n "${backup}" && -d "${backup}" ]]; then
                local backupName
                backupName=$(basename "${backup}")
                local backupInfo=""
                if [[ -f "${backup}/backup_info.json" ]]; then
                    local backupDate
                    backupDate=$(jq -r '.date // "unknown"' "${backup}/backup_info.json" 2>/dev/null)
                    local backupReason
                    backupReason=$(jq -r '.reason // "unknown"' "${backup}/backup_info.json" 2>/dev/null)
                    backupInfo=" [${backupDate}] (${backupReason})"
                fi
                # 标记是否包含配置快照（旧版备份没有 config/，回退时不会触发配置恢复提示）
                local configMark=""
                if [[ -d "${backup}/config" ]]; then
                    configMark=" [+config]"
                fi
                echoContent yellow "${index}. ${backupName}${backupInfo}${configMark}"
                backupList+=("local:${backup}")
                ((index++))
            fi
        done < <(ls -1td "${backupDir}"/v* 2>/dev/null)
    fi

    if [[ ${#backupList[@]} -eq 0 ]]; then
        echoContent yellow "  ($(t SCRIPT_NO_BACKUPS))"
    fi

    # 列出 GitHub 历史版本
    echoContent skyBlue "------------------------$(t SCRIPT_ROLLBACK_GITHUB)----------------------------"
    local githubVersions
    githubVersions=$(curl -s "https://api.github.com/repos/Lynthar/Proxy-agent/releases?per_page=5" 2>/dev/null | jq -r '.[].tag_name' 2>/dev/null)

    if [[ -n "${githubVersions}" && "${githubVersions}" != "null" ]]; then
        while IFS= read -r version; do
            if [[ -n "${version}" ]]; then
                local mark=""
                if [[ "${version}" == "v${currentVersion}" ]]; then
                    mark=" [$(t CURRENT)]"
                fi
                echoContent yellow "${index}. ${version}${mark} (GitHub)"
                backupList+=("github:${version}")
                ((index++))
            fi
        done <<< "${githubVersions}"
    else
        echoContent yellow "  ($(t SCRIPT_GITHUB_UNAVAILABLE))"
    fi

    echoContent skyBlue "--------------------------------------------------------------"
    echoContent yellow "0. $(t BACK)"

    # 把可选版本交给调用方：写入全局数组，而不是 echo 到 stdout。
    # 旧实现 echo 数据后被命令替换连同上面的彩色菜单一起捕获，read 只读到第一行
    # （ANSI 转义码）——回退菜单因此永远拿不到真正的版本数组。
    scriptVersionList=("${backupList[@]}")
}

# 回退脚本版本
rollbackScript() {
    local installDir="${PROXY_AGENT_DIR}"
    local backupDir="${installDir}/backup"
    local rawBase="https://raw.githubusercontent.com/Lynthar/Proxy-agent"

    # 获取版本列表：listScriptVersions 直接把彩色菜单打印到终端，并通过全局数组
    # scriptVersionList 回传可选项（不能用命令替换，否则会把菜单文本一起吞进来）。
    scriptVersionList=()
    listScriptVersions
    local versionList=("${scriptVersionList[@]}")

    if [[ ${#versionList[@]} -eq 0 ]]; then
        echoContent red "\n ---> $(t SCRIPT_ROLLBACK_NO_VERSIONS)"
        return 1
    fi

    read -r -p "$(t SCRIPT_ROLLBACK_SELECT): " selectVersion
    if [[ "${selectVersion}" == "0" || -z "${selectVersion}" ]]; then
        return 0
    fi

    # 验证选择
    local selectedIndex=$((selectVersion - 1))
    if [[ ${selectedIndex} -lt 0 || ${selectedIndex} -ge ${#versionList[@]} ]]; then
        echoContent red " ---> 选择无效"
        return 1
    fi

    local selected="${versionList[${selectedIndex}]}"
    local sourceType="${selected%%:*}"
    local sourcePath="${selected#*:}"

    echoContent yellow "\n选择: ${sourcePath}"

    # 确认回退
    read -r -p "$(t SCRIPT_ROLLBACK_CONFIRM) [y/n]: " confirmRollback
    if ! isYesInput "${confirmRollback}"; then
        echoContent green " ---> $(t CANCEL)"
        return 0
    fi

    # 备份当前版本
    echoContent yellow " ---> $(t SCRIPT_BACKUP_BEFORE_UPDATE)"
    local backupPath
    backupPath=$(backupScript "rollback")
    echoContent green " ---> $(t SCRIPT_BACKUP_COMPLETE): ${backupPath}"

    if [[ "${sourceType}" == "local" ]]; then
        # 从本地备份恢复
        echoContent yellow " ---> 从本地备份恢复..."

        if [[ -f "${sourcePath}/install.sh" ]]; then
            cp -f "${sourcePath}/install.sh" "${installDir}/"
            chmod 700 "${installDir}/install.sh"
        fi
        if [[ -f "${sourcePath}/VERSION" ]]; then
            cp -f "${sourcePath}/VERSION" "${installDir}/"
        fi
        if [[ -d "${sourcePath}/lib" ]]; then
            rm -rf "${installDir}/lib"
            cp -rf "${sourcePath}/lib" "${installDir}/"
        fi
        if [[ -d "${sourcePath}/shell/lang" ]]; then
            mkdir -p "${installDir}/shell"
            rm -rf "${installDir}/shell/lang"
            cp -rf "${sourcePath}/shell/lang" "${installDir}/shell/"
        fi

        echoContent green "\n ---> $(t SCRIPT_ROLLBACK_SUCCESS)!"

        # 可选：同步恢复配置快照（仅本地备份分支；GitHub 分支无配置可恢复）
        if [[ -d "${sourcePath}/config" ]]; then
            echoContent yellow "\n$(t SCRIPT_ROLLBACK_CONFIG_PROMPT)"
            local restoreConfig
            read -r -p "[y/n]: " restoreConfig
            if isYesInput "${restoreConfig}"; then
                # 在覆盖前先把"当前配置"快照到本次回退创建的备份目录里，让回退本身可逆
                local preRestoreSnapshot="${backupPath}/pre_rollback_config"
                if backupConfigSnapshot "${preRestoreSnapshot}" 2>/dev/null; then
                    echoContent green " ---> $(t SCRIPT_ROLLBACK_CONFIG_SAVED "${preRestoreSnapshot}")"
                fi

                # 释放服务对配置文件的句柄。输出不能吞：停不掉时它们自己 exit 1，吞了回滚就一声不响地断在这里
                handleXray stop
                handleSingBox stop

                if restoreConfigSnapshot "${sourcePath}/config"; then
                    echoContent green " ---> $(t SCRIPT_ROLLBACK_CONFIG_RESTORED)"
                    # 提醒：恢复的 TLS 证书可能已临近过期，下次 cron 续签时会更新
                    if [[ -d "${installDir}/tls" ]]; then
                        echoContent yellow " ---> $(t SCRIPT_ROLLBACK_TLS_NOTICE)"
                    fi
                    # 回滚重启前必须 merge 一次，且不能吞错：旧片段对新二进制可能 schema 不兼容，
                    # 吞掉会让 reloadCore 启动到无配置状态。失败时从 pre_rollback_config 恢复。
                    # 快照里 sing-box 片段是空的而 Xray 有入站：sing-box 那半没东西可合并，零片段合并必败、会把整个回退撤销
                    if [[ -f "${installDir}/sing-box/sing-box" ]] && ! compgen -G "${SINGBOX_FRAGMENT_DIR}/*.json" >/dev/null \
                        && compgen -G "${XRAY_CONF_DIR}/*_inbounds.json" >/dev/null; then
                        echoContent yellow " ---> $(t SCRIPT_ROLLBACK_SINGBOX_EMPTY)"
                    elif [[ -f "${installDir}/sing-box/sing-box" ]]; then
                        if ! singBoxMergeConfig; then
                            echoContent red " ---> $(t SCRIPT_ROLLBACK_CONFIG_FAILED)"
                            if [[ -d "${preRestoreSnapshot}" ]]; then
                                echoContent yellow " ---> 自动撤销回滚的配置变更..."
                                if restoreConfigSnapshot "${preRestoreSnapshot}" >/dev/null 2>&1; then
                                    singBoxMergeConfig >/dev/null 2>&1 || true
                                    echoContent yellow " ---> 已恢复回滚前的配置"
                                fi
                            fi
                            reloadCore
                            return 1
                        fi
                    fi
                    reloadCore
                else
                    echoContent red " ---> $(t SCRIPT_ROLLBACK_CONFIG_FAILED)"
                fi
            fi
        fi

    elif [[ "${sourceType}" == "github" ]]; then
        # 整包先下到 staging 校验（非空 + bash -n + SHA256），全部通过才逐文件 .new + mv 落盘。
        # 旧实现直接覆盖活动 install.sh 再逐个下模块，中途断网会留下混版本残局
        local version="${sourcePath}"
        echoContent yellow " ---> 从 GitHub 下载版本 ${version}..."

        local stagingDir
        if ! stagingDir=$(mktemp -d /tmp/proxy-agent-rollback-XXXXXX); then
            echoContent red " ---> $(t ROLLBACK_STAGING_FAIL)"
            return 1
        fi
        mkdir -p "${stagingDir}/lib" "${stagingDir}/shell/lang"

        local stagedOk=1
        if [[ "${release}" == "alpine" ]]; then
            wget -q -O "${stagingDir}/install.sh" "${rawBase}/${version}/install.sh" || stagedOk=
        else
            wget -q ${wgetShowProgressStatus} -O "${stagingDir}/install.sh" "${rawBase}/${version}/install.sh" || stagedOk=
        fi
        if [[ -n "${stagedOk}" ]] && { [[ ! -s "${stagingDir}/install.sh" ]] || ! bash -n "${stagingDir}/install.sh" 2>/dev/null; }; then
            stagedOk=
        fi
        # Release 有 install.sh.sha256 资产时强校验；无 tag/资产时 verifyInstallSHA256 软放行
        if [[ -n "${stagedOk}" ]] && ! verifyInstallSHA256 "${stagingDir}/install.sh" "${version}"; then
            stagedOk=
        fi

        local failedModules=()
        if [[ -n "${stagedOk}" ]]; then
            echoContent yellow " ---> 下载模块文件..."
            for module in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
                # 目标版本的 install.sh 没提到的模块是之后才加的（v1.4.1 及以前没有 carpool），那个 tag 下不存在，不下也不装
                grep -qF -- "${module}.sh" "${stagingDir}/install.sh" || continue
                if ! wget -q -O "${stagingDir}/lib/${module}.sh" "${rawBase}/${version}/lib/${module}.sh" ||
                    [[ ! -s "${stagingDir}/lib/${module}.sh" ]] ||
                    ! bash -n "${stagingDir}/lib/${module}.sh" 2>/dev/null; then
                    failedModules+=("${module}")
                fi
            done
            if [[ ${#failedModules[@]} -gt 0 ]]; then
                echoContent red " ---> $(t UPDATE_MODULE_DOWNLOAD_FAIL "${failedModules[*]}")"
                stagedOk=
            fi
        fi

        local failedLangs=()
        if [[ -n "${stagedOk}" ]]; then
            echoContent yellow " ---> 下载语言文件..."
            for langFile in zh_CN en_US; do
                if ! wget -q -O "${stagingDir}/shell/lang/${langFile}.sh" "${rawBase}/${version}/shell/lang/${langFile}.sh" ||
                    [[ ! -s "${stagingDir}/shell/lang/${langFile}.sh" ]] ||
                    ! bash -n "${stagingDir}/shell/lang/${langFile}.sh" 2>/dev/null; then
                    failedLangs+=("${langFile}")
                fi
            done
            if [[ ${#failedLangs[@]} -gt 0 ]]; then
                echoContent red " ---> $(t UPDATE_LANG_DOWNLOAD_FAIL "${failedLangs[*]}")"
                stagedOk=
            fi
        fi

        if [[ -z "${stagedOk}" ]]; then
            rm -rf "${stagingDir}"
            echoContent red " ---> $(t ROLLBACK_STAGING_FAIL)"
            return 1
        fi

        # 提交：staging 可能在别的文件系统，逐文件 cp 成 .new 再同目录 mv 保持原子
        cp -f "${stagingDir}/install.sh" "${installDir}/install.sh.new" && mv -f "${installDir}/install.sh.new" "${installDir}/install.sh"
        chmod 700 "${installDir}/install.sh"
        mkdir -p "${installDir}/lib" "${installDir}/shell/lang"
        for module in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
            # 没下的模块删掉，与本地备份分支整目录替换的结果一致
            if [[ ! -f "${stagingDir}/lib/${module}.sh" ]]; then
                rm -f "${installDir}/lib/${module}.sh"
                continue
            fi
            cp -f "${stagingDir}/lib/${module}.sh" "${installDir}/lib/${module}.sh.new" && mv -f "${installDir}/lib/${module}.sh.new" "${installDir}/lib/${module}.sh"
        done
        for langFile in zh_CN en_US; do
            cp -f "${stagingDir}/shell/lang/${langFile}.sh" "${installDir}/shell/lang/${langFile}.sh.new" && mv -f "${installDir}/shell/lang/${langFile}.sh.new" "${installDir}/shell/lang/${langFile}.sh"
        done
        echo "${version#v}" > "${installDir}/VERSION"
        rm -rf "${stagingDir}"

        echoContent green "\n ---> $(t SCRIPT_ROLLBACK_SUCCESS)!"
    fi

    # 显示回退后版本
    local newVersion=""
    if [[ -f "${installDir}/VERSION" ]]; then
        newVersion=$(cat "${installDir}/VERSION" 2>/dev/null | tr -d '[:space:]')
    fi
    echoContent green " ---> $(t SCRIPT_VERSION_CURRENT): v${newVersion:-unknown}"
    echoContent yellow " ---> $(t SCRIPT_ROLLBACK_RESTART)\n"

    exit 0
}

# 脚本版本管理菜单
scriptVersionMenu() {
    echoContent skyBlue "\n$(t SCRIPT_VERSION_TITLE)"
    echoContent red "\n=============================================================="

    local currentVersion=""
    if [[ -f "${PROXY_AGENT_DIR}/VERSION" ]]; then
        currentVersion=$(cat "${PROXY_AGENT_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]')
    fi
    echoContent green "$(t SCRIPT_VERSION_CURRENT): v${currentVersion:-unknown}\n"

    echoContent yellow "1.$(t SCRIPT_VERSION_UPDATE)"
    echoContent yellow "2.$(t SCRIPT_VERSION_ROLLBACK)"
    echoContent yellow "3.$(t SCRIPT_VERSION_BACKUP)"
    echoContent yellow "4.$(t SCRIPT_VERSION_LIST)"
    echoContent yellow "0.$(t SCRIPT_VERSION_BACK)"

    read -r -p "$(t PROMPT_SELECT): " selectType
    case ${selectType} in
    1)
        updateV2RayAgent 1
        ;;
    2)
        rollbackScript
        ;;
    3)
        echoContent yellow "\n ---> $(t PROCESSING)..."
        local backupPath
        backupPath=$(backupScript "manual")
        echoContent green " ---> $(t SCRIPT_BACKUP_SUCCESS): ${backupPath}"
        ;;
    4)
        local backupDir="${PROXY_AGENT_DIR}/backup"
        echoContent skyBlue "\n$(t SCRIPT_VERSION_LIST)"
        echoContent skyBlue "=============================================================="
        if [[ -d "${backupDir}" ]]; then
            ls -1td "${backupDir}"/v* 2>/dev/null | while read -r backup; do
                local backupName
                backupName=$(basename "${backup}")
                local backupInfo=""
                if [[ -f "${backup}/backup_info.json" ]]; then
                    local backupDate
                    backupDate=$(jq -r '.date // "unknown"' "${backup}/backup_info.json" 2>/dev/null)
                    backupInfo=" [${backupDate}]"
                fi
                echoContent yellow "  ${backupName}${backupInfo}"
            done
        else
            echoContent yellow "  ($(t SCRIPT_NO_BACKUPS))"
        fi
        echoContent skyBlue "=============================================================="
        ;;
    esac
}

# 更新脚本
updateV2RayAgent() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 更新 Proxy-agent 脚本"

    local installDir="${PROXY_AGENT_DIR}"
    local latestVersion=""
    local rawBase=""

    # 检查 GitHub Release 最新版本
    echoContent yellow " ---> 检查最新版本..."

    # 确保函数存在才调用
    if type getLatestReleaseVersion &>/dev/null; then
        latestVersion=$(getLatestReleaseVersion 2>/dev/null)
    fi

    if [[ -n "${latestVersion}" && "${latestVersion}" != "null" ]]; then
        # 使用 Release 标签下载，确保代码与版本号一致
        rawBase="https://raw.githubusercontent.com/Lynthar/Proxy-agent/${latestVersion}"
        echoContent green " ---> 发现最新 Release: ${latestVersion}"
        echoContent green " ---> 从 Release ${latestVersion} 下载"

        # 比较版本（确保函数存在）
        if type compareVersions &>/dev/null; then
            if ! compareVersions "${SCRIPT_VERSION}" "${latestVersion}"; then
                echoContent green " ---> 当前已是最新版本 (${SCRIPT_VERSION})"
                read -r -p "是否继续更新? [y/N]: " forceUpdate
                if ! isYesInput "${forceUpdate}"; then
                    menu
                    return
                fi
            fi
        fi
    else
        # 无法获取 Release 版本时回退到 master 分支
        rawBase="https://raw.githubusercontent.com/Lynthar/Proxy-agent/master"
        echoContent yellow " ---> 从 master 分支下载"
        latestVersion=""
    fi

    # 更新前自动备份当前版本，捕获路径用于 SHA256 校验失败时回滚
    echoContent yellow " ---> 备份当前版本..."
    local backupPath=""
    if backupPath=$(backupScript "update"); then
        echoContent green " ---> 备份完成: ${backupPath}"
    else
        backupPath=""
        echoContent yellow " ---> 备份跳过 (首次安装或备份失败)"
    fi

    # 下载新版 install.sh：先写 .new、bash -n 验语法，通过才原子 mv 到 live。
    # bash -n 拦的是"200 OK 但内容是 HTML 错误页"。不要用 wget -c（续传会拼出损坏文件）。
    echoContent yellow " ---> 下载脚本文件..."
    local _scriptTmp="${installDir}/install.sh.new"
    rm -f "${_scriptTmp}"

    if [[ "${release}" == "alpine" ]]; then
        wget -q -O "${_scriptTmp}" "${rawBase}/install.sh" 2>/dev/null
    else
        wget -q ${wgetShowProgressStatus} -O "${_scriptTmp}" "${rawBase}/install.sh" 2>/dev/null
    fi

    # 如果从 Release tag 下载失败或文件不合法，回退到 master 分支
    if [[ ! -s "${_scriptTmp}" ]] || ! bash -n "${_scriptTmp}" 2>/dev/null; then
        rm -f "${_scriptTmp}"
        if [[ -n "${latestVersion}" ]]; then
            echoContent yellow " ---> Release ${latestVersion} 下载失败或语法不合法，尝试从 master 分支下载..."
            rawBase="https://raw.githubusercontent.com/Lynthar/Proxy-agent/master"
            latestVersion=""  # 清空版本号，避免版本号与代码不一致

            if [[ "${release}" == "alpine" ]]; then
                wget -q -O "${_scriptTmp}" "${rawBase}/install.sh" 2>/dev/null
            else
                wget -q ${wgetShowProgressStatus} -O "${_scriptTmp}" "${rawBase}/install.sh" 2>/dev/null
            fi
        fi
    fi

    # 最终校验：文件非空且语法合法
    if [[ ! -s "${_scriptTmp}" ]] || ! bash -n "${_scriptTmp}" 2>/dev/null; then
        rm -f "${_scriptTmp}"
        echoContent red " ---> 下载脚本失败或语法不合法!"
        if [[ -n "${backupPath}" && -f "${backupPath}/install.sh" ]]; then
            cp -f "${backupPath}/install.sh" "${installDir}/install.sh"
            chmod 700 "${installDir}/install.sh"
            echoContent green " ---> $(t UPDATE_SHA256_RESTORED "${backupPath}")"
        else
            echoContent yellow "请手动执行: wget -P /root -N ${rawBase}/install.sh"
        fi
        exit 1
    fi

    # 原子 mv 替换 live install.sh。在此之前 live 文件保持旧版本不动，
    # 即使本进程崩溃，pasly 仍可工作。
    rm -f "${installDir}/install.sh"
    if ! mv -f "${_scriptTmp}" "${installDir}/install.sh"; then
        rm -f "${_scriptTmp}"
        echoContent red " ---> 替换 install.sh 失败!"
        if [[ -n "${backupPath}" && -f "${backupPath}/install.sh" ]]; then
            cp -f "${backupPath}/install.sh" "${installDir}/install.sh"
            chmod 700 "${installDir}/install.sh"
            echoContent green " ---> $(t UPDATE_SHA256_RESTORED "${backupPath}")"
        fi
        exit 1
    fi

    # 校验 SHA256。失败则从备份恢复 install.sh，避免 pasly 指向损坏文件
    if ! verifyInstallSHA256 "${installDir}/install.sh" "${latestVersion}"; then
        echoContent red " ---> $(t UPDATE_SHA256_FAIL)"
        rm -f "${installDir}/install.sh"
        if [[ -n "${backupPath}" && -f "${backupPath}/install.sh" ]]; then
            cp -f "${backupPath}/install.sh" "${installDir}/install.sh"
            chmod 700 "${installDir}/install.sh"
            echoContent green " ---> $(t UPDATE_SHA256_RESTORED "${backupPath}")"
        else
            echoContent red " ---> 无可用备份，请手动重装: wget -P /root -N ${rawBase}/install.sh"
        fi
        exit 1
    fi

    chmod 700 "${installDir}/install.sh"

    # 更新 lib 模块 + 语言文件：全部下到 .new 校验，全部成功才统一 mv。
    # 任一失败就删掉所有 .new 并回滚 install.sh——逐个 mv 会留下混版态。
    echoContent yellow " ---> 下载模块与语言文件..."
    mkdir -p "${installDir}/lib" "${installDir}/shell/lang"

    local _stagedSrc=()   # 校验通过、待提交的 .new 路径
    local _stagedDst=()   # 对应目标路径（与 _stagedSrc 同序）
    local failedModules=()
    local failedLangs=()
    local _dst _tmp module langFile

    for module in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
        _dst="${installDir}/lib/${module}.sh"
        _tmp="${_dst}.new"
        if wget -q -O "${_tmp}" "${rawBase}/lib/${module}.sh" && bash -n "${_tmp}" 2>/dev/null; then
            _stagedSrc+=("${_tmp}")
            _stagedDst+=("${_dst}")
        else
            rm -f "${_tmp}"
            failedModules+=("${module}")
        fi
    done

    for langFile in zh_CN en_US; do
        _dst="${installDir}/shell/lang/${langFile}.sh"
        _tmp="${_dst}.new"
        if wget -q -O "${_tmp}" "${rawBase}/shell/lang/${langFile}.sh" && bash -n "${_tmp}" 2>/dev/null; then
            _stagedSrc+=("${_tmp}")
            _stagedDst+=("${_dst}")
        else
            rm -f "${_tmp}"
            failedLangs+=("${langFile}")
        fi
    done

    if [[ ${#failedModules[@]} -gt 0 || ${#failedLangs[@]} -gt 0 ]]; then
        # 放弃本次更新：删掉所有暂存 .new（未提交任何文件），回滚 install.sh
        local _staged
        for _staged in "${_stagedSrc[@]}"; do
            rm -f "${_staged}"
        done
        if [[ ${#failedModules[@]} -gt 0 ]]; then
            echoContent red " ---> $(t UPDATE_MODULE_DOWNLOAD_FAIL "${failedModules[*]}")"
        fi
        if [[ ${#failedLangs[@]} -gt 0 ]]; then
            echoContent red " ---> $(t UPDATE_LANG_DOWNLOAD_FAIL "${failedLangs[*]}")"
        fi
        if [[ -n "${backupPath}" && -f "${backupPath}/install.sh" ]]; then
            cp -f "${backupPath}/install.sh" "${installDir}/install.sh"
            chmod 700 "${installDir}/install.sh"
            echoContent green " ---> $(t UPDATE_SHA256_RESTORED "${backupPath}")"
        fi
        exit 1
    fi

    # 全部校验通过，统一落地（同分区 mv 原子，几乎不会失败）
    local _i
    for _i in "${!_stagedSrc[@]}"; do
        mv -f "${_stagedSrc[$_i]}" "${_stagedDst[$_i]}"
    done
    echoContent green " ---> 已更新 ${#_stagedDst[@]} 个模块/语言文件"

    # 所有文件下载完成后，更新版本文件
    # 确保版本号与实际下载的代码一致
    echoContent yellow " ---> 更新版本文件..."
    if [[ -n "${latestVersion}" ]]; then
        # 使用 Release 版本号
        echo "${latestVersion#v}" > "${installDir}/VERSION"
    else
        # 从 master 分支下载 VERSION 文件（VERSION 失败不致命，仅记日志，旧 VERSION 留底）
        # 不用 -c：旧 VERSION 文件大小不同会导致续传拼接，得到无效内容
        if ! wget -q -O "${installDir}/VERSION" "${rawBase}/VERSION"; then
            echoContent yellow " ---> VERSION 文件下载失败，保留旧版本号"
        fi
    fi
    # 覆盖写不改属主，旧版自举装上的 VERSION 归 CI runner 的 uid
    chown 0:0 "${installDir}/VERSION" 2>/dev/null

    # 读取新版本号
    local version=""
    if [[ -f "${installDir}/VERSION" && -s "${installDir}/VERSION" ]]; then
        version="v$(cat "${installDir}/VERSION" 2>/dev/null | tr -d '[:space:]')"
    elif [[ -n "${latestVersion}" ]]; then
        version="${latestVersion}"
    else
        version="latest"
    fi

    echoContent green "\n ---> 更新完毕"
    echoContent yellow " ---> 请手动执行[pasly]打开脚本"
    echoContent green " ---> 当前版本: ${version}"
    echoContent yellow "\n如更新不成功，请手动执行下面命令\n"
    echoContent skyBlue "wget -P /root -N ${rawBase}/install.sh && chmod 700 /root/install.sh && /root/install.sh"
    echo
    exit 0
}

# 安装BBR
bbrInstall() {
    echoContent red "\n=============================================================="
    echoContent green "BBR、DD脚本用的[ylx2016]的成熟作品，地址[https://github.com/ylx2016/Linux-NetSpeed]，请熟知"
    echoContent yellow "1.安装脚本【推荐原版BBR+FQ】"
    echoContent yellow "2.TCP 缓冲区优化（内存自适应）"
    echoContent yellow "3.回退主目录"
    echoContent red "=============================================================="
    read -r -p "请选择:" installBBRStatus
    if [[ "${installBBRStatus}" == "1" ]]; then
        wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
    elif [[ "${installBBRStatus}" == "2" ]]; then
        optimizeTCPBuffers
    else
        menu
    fi
}

# TCP缓冲区内存自适应优化
optimizeTCPBuffers() {
    echoContent skyBlue "\n===== TCP 缓冲区内存自适应优化 ====="

    # 检测当前 BBR 状态
    local currentCC
    currentCC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "${currentCC}" != "bbr" ]]; then
        echoContent yellow " ---> 当前拥塞控制算法: ${currentCC}"
        echoContent yellow " ---> 建议先安装 BBR 再进行缓冲区优化"
        read -r -p "是否继续优化? [y/n]:" confirmOptimize
        if ! isYesInput "${confirmOptimize}"; then
            return
        fi
    else
        echoContent green " ---> 检测到 BBR 已启用"
    fi

    # 检测系统内存
    local memMB
    memMB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    if [[ -z "${memMB}" || "${memMB}" -le 0 ]]; then
        echoContent red " ---> 无法检测系统内存，退出"
        return 1
    fi
    echoContent green " ---> 检测到系统内存: ${memMB} MB"

    # 根据内存计算缓冲区参数
    local rmemMax wmemMax tcpRmem tcpWmem somaxconn fileMax netdevMaxBacklog

    if [[ ${memMB} -le 512 ]]; then
        echoContent yellow " ---> 小内存模式 (≤512MB)"
        rmemMax=8388608
        wmemMax=8388608
        tcpRmem="4096 65536 8388608"
        tcpWmem="4096 65536 8388608"
        somaxconn=32768
        fileMax=262144
        netdevMaxBacklog=16384
    elif [[ ${memMB} -le 1024 ]]; then
        echoContent yellow " ---> 标准模式 (512MB-1GB)"
        rmemMax=16777216
        wmemMax=16777216
        tcpRmem="4096 65536 16777216"
        tcpWmem="4096 65536 16777216"
        somaxconn=49152
        fileMax=524288
        netdevMaxBacklog=32768
    elif [[ ${memMB} -le 2048 ]]; then
        echoContent yellow " ---> 高性能模式 (1GB-2GB)"
        rmemMax=33554432
        wmemMax=33554432
        tcpRmem="4096 87380 33554432"
        tcpWmem="4096 65536 33554432"
        somaxconn=65535
        fileMax=1048576
        netdevMaxBacklog=32768
    else
        echoContent yellow " ---> 大内存模式 (>2GB)"
        rmemMax=67108864
        wmemMax=67108864
        tcpRmem="4096 131072 67108864"
        tcpWmem="4096 87380 67108864"
        somaxconn=65535
        fileMax=2097152
        netdevMaxBacklog=65536
    fi

    # 备份现有配置
    local configFile="/etc/sysctl.d/99-proxy-agent-tcp.conf"
    if [[ -f "${configFile}" ]]; then
        cp "${configFile}" "${configFile}.bak.$(date +%Y%m%d%H%M%S)"
        echoContent green " ---> 已备份现有配置"
    fi

    # 写入配置文件
    cat > "${configFile}" << EOF
# Proxy-agent TCP Buffer Optimization
# Generated: $(date)
# System Memory: ${memMB} MB

# TCP Buffer Sizes (Memory Adaptive)
net.core.rmem_max = ${rmemMax}
net.core.wmem_max = ${wmemMax}
net.ipv4.tcp_rmem = ${tcpRmem}
net.ipv4.tcp_wmem = ${tcpWmem}

# Connection Backlog
net.core.somaxconn = ${somaxconn}
net.ipv4.tcp_max_syn_backlog = ${somaxconn}
net.core.netdev_max_backlog = ${netdevMaxBacklog}

# File Descriptors
fs.file-max = ${fileMax}

# TCP Optimization
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# Memory Management
vm.swappiness = 10
EOF

    # 应用配置
    if sysctl -p "${configFile}" >/dev/null 2>&1; then
        echoContent green " ---> TCP 缓冲区优化配置已应用"
        echoContent green " ---> 配置文件: ${configFile}"

        # 显示关键参数
        echoContent skyBlue "\n===== 当前生效的关键参数 ====="
        echoContent yellow " rmem_max: $(sysctl -n net.core.rmem_max) bytes"
        echoContent yellow " wmem_max: $(sysctl -n net.core.wmem_max) bytes"
        echoContent yellow " tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control)"
        echoContent yellow " somaxconn: $(sysctl -n net.core.somaxconn)"
    else
        echoContent red " ---> 配置应用失败，请检查系统权限"
        return 1
    fi
}

# 查看、检查日志
# setRealityLogShow true|false：改 Xray 每个 Reality 入站的 realitySettings.show（07 的 Reality 在 inbounds[1]，[0] 是 dokodemo）
setRealityLogShow() {
    if [[ "${1}" != "true" && "${1}" != "false" ]]; then
        echoContent red " ---> setRealityLogShow: invalid arg '${1}'"
        return 1
    fi
    local file
    for file in "${configPath}07_VLESS_vision_reality_inbounds.json" "${configPath}12_VLESS_XHTTP_inbounds.json"; do
        [[ -f "${file}" ]] || continue
        if ! jsonModifyFile "${file}" ".inbounds |= map(if (.streamSettings.realitySettings | type) == \"object\" then .streamSettings.realitySettings.show = ${1} else . end)" false; then
            echoContent red " ---> setRealityLogShow: 写入失败 ${file}"
            return 1
        fi
    done
}

checkLog() {
    if [[ "${coreKind}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 1
    fi
    if [[ -z "${configPath}" && -z "${realityStatus}" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 1
    fi
    local realityLogShow=
    local logStatus=false
    local currentLogLevel="warning"
    local accessLogPath=
    local errorLogPath=
    if [[ -f "${configPath}00_log.json" ]]; then
        if grep -q "access" ${configPath}00_log.json; then
            logStatus=true
        fi
        currentLogLevel=$(jq -r '.log.loglevel // "warning"' ${configPath}00_log.json)
        accessLogPath=$(jq -r '.log.access // empty' ${configPath}00_log.json)
        errorLogPath=$(jq -r '.log.error // empty' ${configPath}00_log.json)
    fi

    writeLogConfig() {
        local accessPath=$1
        local errorPath=$2
        local level=$3
        {
            echo "{"
            echo "  \"log\": {"
            if [[ -n "${accessPath}" ]]; then
                echo "    \"access\": \"${accessPath}\"," 
            fi
            echo "    \"error\": \"${errorPath}\"," 
            echo "    \"loglevel\": \"${level}\"," 
            echo "    \"dnsLog\": false"
            echo "  }"
            echo "}"
        } >${configPath}00_log.json
    }

    echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
    echoContent red "\n=============================================================="
    echoContent yellow "# 建议仅调试时打开access日志\n"

    if [[ "${logStatus}" == "false" ]]; then
        echoContent yellow "1.打开access日志"
    else
        echoContent yellow "1.关闭access日志"
    fi

    echoContent yellow "2.监听access日志"
    echoContent yellow "3.监听error日志"
    echoContent yellow "4.查看证书定时任务日志"
    echoContent yellow "5.查看证书安装日志"
    echoContent yellow "6.清空日志"
    echoContent yellow "7.日志级别(当前:${currentLogLevel})"
    echoContent red "=============================================================="

    read -r -p "请选择:" selectAccessLogType
    local configPathLog=${configPath//conf\//}
    local defaultAccessPath=${accessLogPath:-${configPathLog}access.log}
    local defaultErrorPath=${errorLogPath:-${configPathLog}error.log}

    case ${selectAccessLogType} in
    1)
        if [[ "${logStatus}" == "false" ]]; then
            realityLogShow=true
            writeLogConfig "${defaultAccessPath}" "${defaultErrorPath}" "${currentLogLevel}"
        elif [[ "${logStatus}" == "true" ]]; then
            realityLogShow=false
            writeLogConfig "" "${defaultErrorPath}" "${currentLogLevel}"
        fi

        setRealityLogShow "${realityLogShow}"
        reloadCore
        checkLog 1
        ;;
    2)
        tail -f ${defaultAccessPath}
        ;;
    3)
        tail -f ${defaultErrorPath}
        ;;
    4)
        if [[ ! -f "${PROXY_AGENT_DIR}/crontab_tls.log" ]]; then
            touch ${PROXY_AGENT_DIR}/crontab_tls.log
        fi
        tail -n 100 ${PROXY_AGENT_DIR}/crontab_tls.log
        ;;
    5)
        tail -n 100 ${TLS_DIR}/acme.log
        ;;
    6)
        echo >${defaultAccessPath}
        echo >${defaultErrorPath}
        ;;
    7)
        echoContent yellow "\n日志级别切换(当前:${currentLogLevel})"
        echoContent yellow "1.warning(默认)"
        echoContent yellow "2.info"
        echoContent yellow "3.debug"
        echoContent yellow "4.最小日志(写入/tmp，适合无盘/调试完毕后使用)"
        read -r -p "请选择:" selectLogLevel
        local targetAccessPath=""
        case ${selectLogLevel} in
        1)
            currentLogLevel="warning"
            ;;
        2)
            currentLogLevel="info"
            ;;
        3)
            currentLogLevel="debug"
            ;;
        4)
            local tmpLogDir="/tmp/Proxy-agent"
            mkdir -p "${tmpLogDir}"
            currentLogLevel="warning"
            writeLogConfig "${tmpLogDir}/access.log" "${tmpLogDir}/error.log" "${currentLogLevel}"
            setRealityLogShow "false"
            reloadCore
            echoContent green "\n ---> 已切换为最小日志模式"
            echoContent yellow " ---> access/error 将写入 ${tmpLogDir}/，系统临时目录会在重启或周期清理时自动清空，如需立即清理可执行 [rm -f ${tmpLogDir}/*.log]"
            checkLog 1
            ;;
        esac
        if [[ "${selectLogLevel}" != "4" ]]; then
            if [[ "${logStatus}" == "true" ]]; then
                targetAccessPath=${defaultAccessPath}
                realityLogShow=true
            else
                realityLogShow=false
            fi
            writeLogConfig "${targetAccessPath}" "${defaultErrorPath}" "${currentLogLevel}"
            setRealityLogShow "${realityLogShow}"
            reloadCore
            checkLog 1
        fi
        ;;
    esac
}

# 脚本快捷方式
aliasInstall() {
    # 从哪儿跑的就从哪儿装（curl 下到 $HOME、git clone 的目录都算）：漏装的话没有 pasly、安装根里没有脚本，
    # cron 的 RenewTLS 却照样指向安装根，证书到期前静默续不上。从安装根自己跑（pasly）时什么都不做
    local src="${_SCRIPT_DIR}/install.sh"
    [[ -f "${src}" && -d "${PROXY_AGENT_DIR}" ]] || return 0
    [[ "$(cd "${_SCRIPT_DIR}" && pwd -P)" == "$(cd "${PROXY_AGENT_DIR}" && pwd -P)" ]] && return 0
    if grep -Eq "作者[:：]Lynthar|Proxy-agent" "${src}"; then
        if ! cp -f "${src}" "${PROXY_AGENT_DIR}/install.sh" || ! chmod 700 "${PROXY_AGENT_DIR}/install.sh"; then
            echoContent red " ---> $(t INSTALL_STAGE_FAIL "install.sh")"
            exit 1
        fi

        # 复制 VERSION 文件（如果存在于脚本目录）
        if [[ -f "${_SCRIPT_DIR}/VERSION" ]]; then
            if ! cp -f "${_SCRIPT_DIR}/VERSION" ${PROXY_AGENT_DIR}/VERSION; then
                echoContent yellow " ---> $(t INSTALL_STAGE_FAIL "VERSION")"
            fi
        fi

        # 复制 lib 目录（如果存在）；失败致命——pasly 会因找不到 lib 函数崩溃
        if [[ -d "${_SCRIPT_DIR}/lib" ]]; then
            mkdir -p ${PROXY_AGENT_DIR}/lib
            if ! cp -rf "${_SCRIPT_DIR}/lib/"*.sh ${PROXY_AGENT_DIR}/lib/; then
                echoContent red " ---> $(t INSTALL_STAGE_FAIL "lib/*.sh")"
                exit 1
            fi
        fi

        # 复制 shell/lang 目录；失败致命——i18n 全失效
        if [[ -d "${_SCRIPT_DIR}/shell/lang" ]]; then
            mkdir -p ${PROXY_AGENT_DIR}/shell/lang
            if ! cp -rf "${_SCRIPT_DIR}/shell/lang/"*.sh ${PROXY_AGENT_DIR}/shell/lang/; then
                echoContent red " ---> $(t INSTALL_STAGE_FAIL "shell/lang/*.sh")"
                exit 1
            fi
        fi

        local paslyType=
        if [[ -d "/usr/bin/" ]]; then
            rm -f "/usr/bin/vasma"
            if [[ ! -f "/usr/bin/pasly" ]]; then
                ln -s ${PROXY_AGENT_DIR}/install.sh /usr/bin/pasly
                chmod 700 /usr/bin/pasly
                paslyType=true
            fi
        elif [[ -d "/usr/sbin" ]]; then
            rm -f "/usr/sbin/vasma"
            if [[ ! -f "/usr/sbin/pasly" ]]; then
                ln -s ${PROXY_AGENT_DIR}/install.sh /usr/sbin/pasly
                chmod 700 /usr/sbin/pasly
                paslyType=true
            fi
        fi
        # curl 一行命令下到 $HOME 的那份装完就删（原先的行为）；clone 下来的仓库里的文件不动
        if [[ "$(cd "${_SCRIPT_DIR}" && pwd -P)" == "$(cd "${HOME}" && pwd -P)" ]]; then
            rm -f "${src}"
        fi
        if [[ "${paslyType}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[pasly]重新打开脚本"
        fi
    fi
}

# 检查ipv6、ipv4
checkIPv6() {
    currentIPv6IP=$(curl -s -6 -m 4 https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)

    if [[ -z "${currentIPv6IP}" ]]; then
        echoContent red " ---> 不支持ipv6"
        exit 1
    fi
}

# ipv6 分流
ipv6Routing() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi

    checkIPv6
    echoContent skyBlue "\n功能 1/${totalProgress} : IPv6分流"
    echoContent red "\n=============================================================="
    echoContent yellow "1.查看已分流域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.设置IPv6全局"
    echoContent yellow "4.卸载IPv6分流"
    echoContent red "=============================================================="
    read -r -p "请选择:" ipv6Status
    if [[ "${ipv6Status}" == "1" ]]; then
        showIPv6Routing
        exit 0
    elif [[ "${ipv6Status}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "录入示例:netflix,openai\n"
        read -r -p "请按照上面示例录入域名:" domainList
        if [[ "${coreKind}" == "1" ]]; then
            addXrayRouting IPv6_out outboundTag "${domainList}"
            addXrayOutbound IPv6_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "IPv6_out" "${domainList}" "IPv6_route"
            ensureDirectOutbound
            addSingBoxOutbound IPv6_out
            addSingBoxOutbound IPv4_out
        fi

        echoContent green " ---> 添加完毕"

    elif [[ "${ipv6Status}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.会删除所有设置的分流规则"
        echoContent yellow "2.会删除IPv6之外的所有出站规则\n"
        globalEgressChainNotice
        read -r -p "是否确认设置？[y/n]:" IPv6OutStatus

        if isYesInput "${IPv6OutStatus}"; then
            if [[ "${coreKind}" == "1" ]]; then
                addXrayOutbound IPv6_out
                removeXrayOutbound IPv4_out
                removeXrayOutbound z_direct_outbound
                removeXrayOutbound blackhole_out
                removeXrayOutbound wireguard_out_IPv4
                removeXrayOutbound wireguard_out_IPv6
                removeXrayOutbound socks5_outbound

                rm ${configPath}09_routing.json >/dev/null 2>&1
            fi
            if [[ -n "${singBoxConfigPath}" ]]; then

                removeSingBoxConfig IPv4_out

                removeSingBoxConfig wireguard_endpoints_IPv4_route
                removeSingBoxConfig wireguard_endpoints_IPv6_route
                removeSingBoxConfig wireguard_endpoints_IPv4
                removeSingBoxConfig wireguard_endpoints_IPv6

                removeSingBoxConfig socks5_02_inbound_route

                removeSingBoxConfig IPv6_route

                removeSingBoxConfig 01_direct_outbound

                addSingBoxOutbound IPv6_out

            fi

            echoContent green " ---> IPv6全局出站设置完毕"
        else

            echoContent green " ---> 放弃设置"
            exit 0
        fi

    elif [[ "${ipv6Status}" == "4" ]]; then
        if [[ "${coreKind}" == "1" ]]; then
            unInstallRouting IPv6_out outboundTag

            removeXrayOutbound IPv6_out
            addXrayOutbound "z_direct_outbound"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig IPv6_out
            removeSingBoxConfig "IPv6_route"
            ensureDirectOutbound
        fi

        echoContent green " ---> IPv6分流卸载成功"
    else
        echoContent red " ---> 选择错误"
        exit 1
    fi

    reloadCore
}

# xrayRoutingHasOutbound TAG → 0=09_routing.json 里有规则指向出站 TAG（按域名分流）。全局模式靠「没有这类规则」判断，
# 不能看文件在不在：全局模式删掉的 09_routing.json 会在下次启动时被 ensureXrayLocalBlock 补回来
xrayRoutingHasOutbound() {
    jq -e --arg tag "$1" 'any(.routing.rules[]?; .outboundTag == $tag)' "${configPath}09_routing.json" >/dev/null 2>&1
}

# ipv6分流规则展示
showIPv6Routing() {
    if [[ "${coreKind}" == "1" ]]; then
        if xrayRoutingHasOutbound IPv6_out; then
            echoContent yellow "Xray-core："
            jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6_out")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ -f "${configPath}IPv6_out.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已设置IPv6全局分流"
        else
            echoContent yellow " ---> 未安装IPv6分流"
        fi

    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}IPv6_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]|select (.outbound=="IPv6_out")' "${singBoxConfigPath}IPv6_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}IPv6_route.json" && -f "${singBoxConfigPath}IPv6_out.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已设置IPv6全局分流"
        else
            echoContent yellow " ---> 未安装IPv6分流"
        fi
    fi
}
# 添加routing配置
# 全量使用 jq --arg/--argjson 传值，避免 tag/domain 拼接进过滤器
addXrayRouting() {

    local tag=$1    # warp-socks 等内部 outboundTag
    local type=$2   # outboundTag/inboundTag（作为 jq key 名称）
    local domain=$3 # 域名列表（逗号分隔）

    if [[ -z "${tag}" || -z "${type}" || -z "${domain}" ]]; then
        echoContent red " ---> 参数错误"
        exit 1
    fi
    # tag 形式校验：字母数字 _ - 长度 1-64，防止嵌入 JSON / jq 时破坏结构
    if ! [[ "${tag}" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
        echoContent red " ---> addXrayRouting: tag 非法 '${tag}'"
        exit 1
    fi
    # type 必须是已知 jq key 之一（后续会作为 .[$k] 访问），白名单防注入
    case "${type}" in
        outboundTag|inboundTag) ;;
        *)
            echoContent red " ---> addXrayRouting: type 非法 '${type}'"
            exit 1
            ;;
    esac

    local routingRule=
    if [[ ! -f "${configPath}09_routing.json" ]]; then
        # 初始骨架：用 jq -n 安全构造
        jq -n --arg tag "${tag}" \
            '{routing:{type:"field",rules:[{type:"field",domain:[],outboundTag:$tag}]}}' \
            > ${configPath}09_routing.json
    fi
    local routingRule=
    # outboundTag 是固定 key，tag 作为值用 --arg
    routingRule=$(jq -r --arg tag "${tag}" \
        '.routing.rules[]|select(.outboundTag==$tag and (.protocol == null))' \
        ${configPath}09_routing.json)

    if [[ -z "${routingRule}" ]]; then
        routingRule=$(jq -n --arg tag "${tag}" \
            '{type:"field",domain:[],outboundTag:$tag}')
    fi

    while read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        # 放行域名与 geosite 分类名（字母数字 ! _ - .），拒绝其他（避免 URL/过滤器污染）
        if ! [[ "${line}" =~ ^[A-Za-z0-9!._-]{1,64}$ ]]; then
            echoContent yellow " ---> 跳过非法域名条目: ${line}"
            continue
        fi
        if echo "${routingRule}" | grep -qF "${line}"; then
            echoContent yellow " ---> ${line}已存在，跳过"
        else
            routingRule=$(echo "${routingRule}" | jq -r --arg rule "$(xrayDomainRuleValue "${line}")" '.domain += [$rule]')
        fi
    done < <(echo "${domain}" | tr ',' '\n')

    unInstallRouting "${tag}" "${type}"
    # routingRule 本身是 jq 产物的合法 JSON，改用 --argjson 明示
    local routing=
    routing=$(jq -r --argjson rule "${routingRule}" '.routing.rules += [$rule]' ${configPath}09_routing.json)
    echo "${routing}" | jq . >${configPath}09_routing.json
}
# 根据tag卸载Routing
unInstallRouting() {
    local tag=$1
    local type=$2
    local protocol=$3

    # type 必须是已知 jq key；用 .[$k] 动态访问，tag/protocol 作值传入
    case "${type}" in
        outboundTag|inboundTag) ;;
        *)
            echoContent red " ---> unInstallRouting: type 非法 '${type}'"
            return 1
            ;;
    esac

    if [[ -f "${configPath}09_routing.json" ]]; then
        local routing=
        if [[ -n "${protocol}" ]]; then
            routing=$(jq -r --arg key "${type}" --arg tag "${tag}" --arg proto "${protocol}" \
                'del(.routing.rules[] | select(.[$key] == $tag and (.protocol | index($proto))))' \
                ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        else
            routing=$(jq -r --arg key "${type}" --arg tag "${tag}" \
                'del(.routing.rules[] | select(.[$key] == $tag and (.protocol == null )))' \
                ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        fi
    fi
}

# 安装嗅探
installSniffing() {
    readInstallType
    if [[ "${coreKind}" == "1" ]]; then
        if [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]]; then
            if ! grep -q "destOverride" <"${configPath}02_VLESS_TCP_inbounds.json"; then
                sniffing=$(jq -r '.inbounds[0].sniffing = {"enabled":true,"destOverride":["http","tls","quic"]}' "${configPath}02_VLESS_TCP_inbounds.json")
                echo "${sniffing}" | jq . >"${configPath}02_VLESS_TCP_inbounds.json"
            fi
        fi
    fi
}

# 读取第三方warp配置
readConfigWarpReg() {
    if [[ ! -f "${WARP_DIR}/config" ]]; then
        ${WARP_DIR}/warp-reg >${WARP_DIR}/config
    fi

    secretKeyWarpReg=$(grep <"${WARP_DIR}/config" private_key | awk '{print $2}')

    addressWarpReg=$(grep <"${WARP_DIR}/config" v6 | awk '{print $2}')

    publicKeyWarpReg=$(grep <"${WARP_DIR}/config" public_key | awk '{print $2}')

    reservedWarpReg=$(grep <"${WARP_DIR}/config" reserved | awk -F "[:]" '{print $2}')

}
# 安装warp-reg工具
installWarpReg() {
    if [[ ! -f "${WARP_DIR}/warp-reg" ]]; then
        echo
        echoContent yellow "# 注意事项"
        echoContent yellow "# 依赖第三方程序，请熟知其中风险"
        echoContent yellow "# 项目地址：https://github.com/badafans/warp-reg \n"

        read -r -p "warp-reg未安装，是否安装 ？[y/n]:" installWarpRegStatus

        if isYesInput "${installWarpRegStatus}"; then

            # v1.0 资产 SHA256（2026-08-23 实测钉定）。上游 release 资产可被替换，
            # root 直接执行的第三方二进制必须校验；不匹配即拒装
            local warpRegExpectedHash=
            case "${warpRegCoreCPUVendor}" in
            main-linux-amd64) warpRegExpectedHash="95e97d92bda8f343e0ba0b7a7402c5947fb4204fdb0d368fd53dbddb664de895" ;;
            main-linux-arm64) warpRegExpectedHash="eb7a29853466f805755caddcebeedfbfb36cccd73a4eb950a1eb82915fa17f9b" ;;
            main-linux-arm) warpRegExpectedHash="7def80f34b206bbb44df24b7bd04edfc03e5507d0ae17ac379d15ef81a2ca33f" ;;
            esac

            local warpRegTmp="${WARP_DIR}/warp-reg.download"
            curl -sLo "${warpRegTmp}" "https://github.com/badafans/warp-reg/releases/download/v1.0/${warpRegCoreCPUVendor}"
            if [[ ! -s "${warpRegTmp}" ]] || { [[ -n "${warpRegExpectedHash}" ]] && ! verifySHA256 "${warpRegTmp}" "${warpRegExpectedHash}"; }; then
                rm -f "${warpRegTmp}"
                echoContent red " ---> $(t WARP_REG_VERIFY_FAIL)"
                exit 1
            fi
            mv -f "${warpRegTmp}" ${WARP_DIR}/warp-reg
            chmod 655 ${WARP_DIR}/warp-reg

        else
            echoContent yellow " ---> 放弃安装"
            exit 0
        fi
    fi
}

# 展示warp分流域名
showWireGuardDomain() {
    local type=$1
    # xray
    if [[ "${coreKind}" == "1" ]]; then
        if xrayRoutingHasOutbound "wireguard_out_${type}"; then
            echoContent yellow "Xray-core"
            jq -r -c '.routing.rules[]|select (.outboundTag=="wireguard_out_'"${type}"'")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ -f "${configPath}wireguard_out_${type}.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已设置warp ${type}全局分流"
        else
            echoContent yellow " ---> 未安装warp ${type}分流"
        fi
    fi

    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]' "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" && -f "${singBoxConfigPath}wireguard_endpoints_${type}.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已设置warp ${type}全局分流"
        else
            echoContent yellow " ---> 未安装warp ${type}分流"
        fi
    fi

}

# 添加WireGuard分流
addWireGuardRoute() {
    local type=$1
    local tag=$2
    local domainList=$3
    # xray
    if [[ "${coreKind}" == "1" ]]; then

        addXrayRouting "wireguard_out_${type}" "${tag}" "${domainList}"
        addXrayOutbound "wireguard_out_${type}"
    fi
    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then

        # rule
        addSingBoxRouteRule "wireguard_endpoints_${type}" "${domainList}" "wireguard_endpoints_${type}_route"
        # addSingBoxOutbound "wireguard_out_${type}" "wireguard_out"
        if [[ -n "${domainList}" ]]; then
            ensureDirectOutbound
        fi

        # outbound
        addSingBoxWireGuardEndpoints "${type}"
    fi
}

# warp分流-第三方IPv4
warpRoutingReg() {
    local type=$2
    echoContent skyBlue "\n进度  $1/${totalProgress} : WARP分流[第三方]"
    echoContent red "=============================================================="

    echoContent yellow "1.查看已分流域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.设置WARP全局"
    echoContent yellow "4.卸载WARP分流"
    echoContent red "=============================================================="
    read -r -p "请选择:" warpStatus
    installWarpReg
    readConfigWarpReg
    local address=
    if [[ ${type} == "IPv4" ]]; then
        address="172.16.0.2/32"
    elif [[ ${type} == "IPv6" ]]; then
        address="${addressWarpReg}/128"
    else
        echoContent red " ---> IP获取失败，退出安装"
        exit 1
    fi

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        exit 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent yellow "# 注意事项"
        echoContent yellow "# 支持sing-box、Xray-core"
        echoContent yellow "录入示例:netflix,openai\n"
        read -r -p "请按照上面示例录入域名:" domainList
        addWireGuardRoute "${type}" outboundTag "${domainList}"
        echoContent green " ---> 添加完毕"

    elif [[ "${warpStatus}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.会删除所有设置的分流规则"
        echoContent yellow "2.会删除除WARP[第三方]之外的所有出站规则\n"
        globalEgressChainNotice
        read -r -p "是否确认设置？[y/n]:" warpOutStatus

        if isYesInput "${warpOutStatus}"; then
            readConfigWarpReg
            if [[ "${coreKind}" == "1" ]]; then
                addXrayOutbound "wireguard_out_${type}"
                if [[ "${type}" == "IPv4" ]]; then
                    removeXrayOutbound "wireguard_out_IPv6"
                elif [[ "${type}" == "IPv6" ]]; then
                    removeXrayOutbound "wireguard_out_IPv4"
                fi

                removeXrayOutbound IPv4_out
                removeXrayOutbound IPv6_out
                removeXrayOutbound z_direct_outbound
                removeXrayOutbound blackhole_out
                removeXrayOutbound socks5_outbound

                rm ${configPath}09_routing.json >/dev/null 2>&1
            fi

            if [[ -n "${singBoxConfigPath}" ]]; then

                removeSingBoxConfig IPv4_out
                removeSingBoxConfig IPv6_out
                removeSingBoxConfig 01_direct_outbound

                # 删除所有分流规则
                removeSingBoxConfig wireguard_endpoints_IPv4_route
                removeSingBoxConfig wireguard_endpoints_IPv6_route

                removeSingBoxConfig IPv6_route
                removeSingBoxConfig socks5_02_inbound_route

                addSingBoxWireGuardEndpoints "${type}"
                addWireGuardRoute "${type}" outboundTag ""
                if [[ "${type}" == "IPv4" ]]; then
                    removeSingBoxConfig wireguard_endpoints_IPv6
                else
                    removeSingBoxConfig wireguard_endpoints_IPv4
                fi

                # outbound
                # addSingBoxOutbound "wireguard_out_${type}" "wireguard_out"

            fi

            echoContent green " ---> WARP全局出站设置完毕"
        else
            echoContent green " ---> 放弃设置"
            exit 0
        fi

    elif [[ "${warpStatus}" == "4" ]]; then
        if [[ "${coreKind}" == "1" ]]; then
            unInstallRouting "wireguard_out_${type}" outboundTag

            removeXrayOutbound "wireguard_out_${type}"
            addXrayOutbound "z_direct_outbound"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig "wireguard_endpoints_${type}_route"

            removeSingBoxConfig "wireguard_endpoints_${type}"
            ensureDirectOutbound
        fi

        echoContent green " ---> 卸载WARP ${type}分流完毕"
    else

        echoContent red " ---> 选择错误"
        exit 1
    fi
    reloadCore
}

# ======================= 链式代理功能 =======================

# 链式代理主菜单
chainProxyMenu() {
    echoContent skyBlue "\n功能: 链式代理管理"
    echoContent red "\n=============================================================="
    echoContent yellow "# 链式代理说明"
    echoContent yellow "# 用于在多台境外VPS之间建立加密转发链路"
    echoContent yellow "# 支持多层中继: 入口 → 中继1 → 中继2 → ... → 出口 → 互联网"
    echoContent yellow "# 使用 Shadowsocks 2022 协议，加密安全、性能优秀\n"
    chainExternalSingleOnXray && echoContent red " ---> $(t EXT_SINGLE_EXIT_XRAY_WARNING)\n"

    echoContent yellow "1.$(t CHAIN_MENU_WIZARD) [$(t RECOMMENDED)]"
    echoContent yellow "2.$(t CHAIN_MENU_STATUS)"
    echoContent yellow "3.$(t CHAIN_MENU_TEST)"
    echoContent yellow "4.$(t CHAIN_MENU_ADVANCED)"
    echoContent yellow "5.$(t CHAIN_MENU_UNINSTALL)"
    echoContent yellow "6.$(t EXT_MENU_TITLE)"
    echoContent yellow "7.$(t CHAIN_MENU_PROTOCOL_ROUTING)"
    echoContent yellow "8.$(t CHAIN_MENU_ACCOUNT_EXIT)"

    read -r -p "$(t PROMPT_SELECT):" selectType

    case ${selectType} in
    1)
        chainProxyWizard
        ;;
    2)
        showChainStatus
        ;;
    3)
        testChainConnection
        ;;
    4)
        chainProxyAdvanced
        ;;
    5)
        removeChainProxy
        ;;
    6)
        externalNodeMenu
        ;;
    7)
        configureProtocolChainRouting
        ;;
    8)
        chainAccountExitMenu
        ;;
    esac
}

# 链式代理配置向导
chainProxyWizard() {
    echoContent skyBlue "\n链式代理配置向导"
    echoContent red "\n=============================================================="
    echoContent yellow "请选择本机角色:\n"
    echoContent yellow "1.出口节点 (Exit) - 链路终点，直接访问互联网"
    echoContent yellow "  └─ 生成配置码，供中继或入口节点导入"
    echoContent yellow ""
    echoContent yellow "2.中继节点 (Relay) - 链路中间节点，转发流量"
    echoContent yellow "  └─ 导入下游配置码，生成新配置码供上游使用"
    echoContent yellow "  └─ 支持多层中继: 入口→中继1→中继2→...→出口"
    echoContent yellow ""
    echoContent yellow "3.入口节点 (Entry) - 单链路模式"
    echoContent yellow "  └─ 导入出口或中继节点的配置码"
    echoContent yellow ""
    echoContent yellow "4.入口节点 (Entry) - 多链路分流模式"
    echoContent yellow "  └─ 配置多条链路，按规则分流到不同出口"
    echoContent yellow ""
    echoContent yellow "5.手动配置入口节点"
    echoContent yellow "  └─ 手动输入出口节点信息 (仅支持单跳)"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setupChainExit
        ;;
    2)
        setupChainRelay
        ;;
    3)
        setupChainEntryByCode
        ;;
    4)
        setupMultiChainEntry
        ;;
    5)
        setupChainEntryManual
        ;;
    esac
}

# 确保 sing-box 已安装
ensureSingBoxInstalled() {
    if [[ ! -f "${SINGBOX_BIN}" ]]; then
        echoContent yellow "\n检测到 sing-box 未安装，正在安装..."
        installBaseTools
        installSingBox
        if [[ ! -f "${SINGBOX_BIN}" ]]; then
            echoContent red " ---> sing-box 安装失败"
            return 1
        fi
    fi

    # 确保配置目录存在
    mkdir -p ${SINGBOX_FRAGMENT_DIR}/

    # 确保基础配置存在
    if [[ ! -f "${SINGBOX_FRAGMENT_DIR}/00_log.json" ]]; then
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/00_log.json
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    }
}
EOF
    fi

    # 确保 DNS 配置存在，并把 legacy 的 {tag,address} 迁到 1.12+ 的 {type,server}。
    # 不迁的话 merge 会以 ENABLE_DEPRECATED_LEGACY_DNS_SERVERS 为由 FATAL。
    local _dnsConf="${SINGBOX_FRAGMENT_DIR}/01_dns.json"
    if [[ ! -f "${_dnsConf}" ]] || \
       { grep -q '"address"' "${_dnsConf}" 2>/dev/null && ! grep -q '"type"' "${_dnsConf}" 2>/dev/null; }; then
        if [[ -f "${_dnsConf}" ]]; then
            echoContent yellow " ---> 检测到旧版 sing-box DNS 格式（1.11 legacy），自动迁移到 1.12+ 格式"
        fi
        cat <<EOF >"${_dnsConf}"
{
    "dns": {
        "servers": [
            {
                "type": "udp",
                "tag": "google",
                "server": "8.8.8.8"
            },
            {
                "type": "udp",
                "tag": "cloudflare",
                "server": "1.1.1.1"
            }
        ]
    }
}
EOF
    fi

    # 确保直连出站存在。outbound 不带 domain_strategy（sing-box 1.12 弃用 / 1.14 删除）：
    # chain proxy 流量在 chain_route.json 的 resolve action 里按 prefer_ipv4 解析；
    # 非 chain 流量由客户端送 IP，outbound 自己不发起域名解析。
    if [[ ! -f "${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json" ]]; then
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json
{
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
    fi

    # 已有 01_direct_outbound.json 含 domain_strategy 时自动剥离（in-place migration）。
    # 1.12 起仅打 deprecation 警告，1.14 移除后会 FATAL；现在剥掉避免后续踩坑 +
    # 让 sing-box 启动日志干净。
    local _directOut="${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json"
    if [[ -f "${_directOut}" ]] && jq -e . "${_directOut}" >/dev/null 2>&1; then
        if jq -e '[.outbounds[]? | has("domain_strategy")] | any' "${_directOut}" >/dev/null 2>&1; then
            echoContent yellow " ---> 检测到旧版 01_direct_outbound.json 含 domain_strategy（1.14 移除），自动剥离"
            local _migrated
            _migrated=$(jq '.outbounds |= map(del(.domain_strategy))' "${_directOut}" 2>/dev/null)
            if [[ -n "${_migrated}" ]]; then
                echo "${_migrated}" > "${_directOut}"
            fi
        fi
    fi

    # 已有 chain_route.json 缺 default_domain_resolver 时 in-place 补全——1.13 起缺它直接 FATAL。
    # 后续 chain* 流程会重写该文件，但用户只"重启 sing-box"不重跑配置就会卡住。
    local _chainRoute="${SINGBOX_FRAGMENT_DIR}/chain_route.json"
    if [[ -f "${_chainRoute}" ]] && jq -e . "${_chainRoute}" >/dev/null 2>&1; then
        if ! jq -e '.route | has("default_domain_resolver")' "${_chainRoute}" >/dev/null 2>&1; then
            echoContent yellow " ---> 检测到旧版 chain_route.json 缺 default_domain_resolver，自动补全"
            local _migrated
            _migrated=$(jq '.route.default_domain_resolver = "google"' "${_chainRoute}" 2>/dev/null)
            if [[ -n "${_migrated}" ]]; then
                echo "${_migrated}" > "${_chainRoute}"
            fi
        fi
    fi

    # 确保 systemd 服务已安装且路径正确（修复：链式代理需要服务才能启动）
    # 检查服务文件是否存在，以及是否指向正确的路径
    local needUpdateService=false
    if [[ ! -f "/etc/systemd/system/sing-box.service" ]] && [[ ! -f "/etc/init.d/sing-box" ]]; then
        needUpdateService=true
        echoContent yellow "\n检测到 sing-box 服务未配置，正在配置..."
    elif [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        # 检查服务文件是否指向正确路径（修复从 v2ray-agent 迁移的问题）
        if grep -q "v2ray-agent" /etc/systemd/system/sing-box.service; then
            needUpdateService=true
            echoContent yellow "\n检测到 sing-box 服务路径需要更新..."
        fi
    fi

    if [[ "${needUpdateService}" == "true" ]]; then
        local execStart="${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"

        if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ "${release}" != "alpine" ]]; then
            cat <<EOF >/etc/systemd/system/sing-box.service
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${execStart}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable sing-box.service >/dev/null 2>&1
            echoContent green " ---> sing-box 服务配置完成"
        elif [[ "${release}" == "alpine" ]]; then
            cat <<EOF >/etc/init.d/sing-box
#!/sbin/openrc-run

name="sing-box"
description="Sing-Box Service"
command="${SINGBOX_BIN}"
command_args="run -c ${SINGBOX_MERGED_CONFIG}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
    after firewall
}
EOF
            chmod +x /etc/init.d/sing-box
            rc-update add sing-box default >/dev/null 2>&1
            echoContent green " ---> sing-box 服务配置完成 (Alpine)"
        fi
    fi

    return 0
}

# 生成链式代理密钥 (Shadowsocks 2022 需要 Base64 编码)
generateChainKey() {
    # AES-128-GCM 需要 16 字节密钥
    openssl rand -base64 16
}

# 获取本机公网 IP
getChainPublicIP() {
    local ip=""
    # 尝试多个服务获取公网IP
    ip=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
    if [[ -z "${ip}" ]]; then
        ip=$(curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null)
    fi
    if [[ -z "${ip}" ]]; then
        ip=$(curl -s4 --connect-timeout 5 https://ip.sb 2>/dev/null)
    fi
    echo "${ip}"
}

# 配置出口节点 (Exit)
setupChainExit() {
    if planAction "$(t PLAN_CHAIN_EXIT)"; then return 0; fi
    echoContent skyBlue "\n配置出口节点 (Exit)"
    echoContent red "\n=============================================================="

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理入站
    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_inbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if ! isYesInput "${confirmOverwrite}"; then
            # 显示现有配置码
            showExistingChainCode
            return 0
        fi
    fi

    # 生成随机端口 (10000-60000)
    local chainPort
    chainPort=$(randomNum 10000 60000)
    echoContent yellow "\n请输入链式代理端口 [回车使用随机端口: ${chainPort}]"
    read -r -p "端口:" inputPort
    if [[ -n "${inputPort}" ]]; then
        if [[ ! "${inputPort}" =~ ^[0-9]+$ ]] || [[ "${inputPort}" -lt 1 ]] || [[ "${inputPort}" -gt 65535 ]]; then
            echoContent red " ---> 端口格式错误"
            return 1
        fi
        chainPort=${inputPort}
    fi

    # 生成密钥
    local chainKey
    chainKey=$(generateChainKey)
    echoContent green "\n ---> 已生成随机密钥"

    # 加密方法
    local chainMethod="2022-blake3-aes-128-gcm"

    # 获取公网IP
    local publicIP
    publicIP=$(getChainPublicIP)
    if [[ -z "${publicIP}" ]]; then
        echoContent yellow "\n无法自动获取公网IP，请手动输入"
        read -r -p "公网IP:" publicIP
        if [[ -z "${publicIP}" ]]; then
            echoContent red " ---> IP不能为空"
            return 1
        fi
        if ! isValidIP "${publicIP}"; then
            echoContent red " ---> IP地址格式无效"
            return 1
        fi
    fi
    echoContent green " ---> 本机公网IP: ${publicIP}"

    # 询问是否限制入口IP
    echoContent yellow "\n是否限制只允许特定IP连接？(提高安全性)"
    echoContent yellow "1.不限制 [回车默认]"
    echoContent yellow "2.限制特定IP"
    read -r -p "请选择:" limitIPChoice

    local allowedIP=""
    if [[ "${limitIPChoice}" == "2" ]]; then
        read -r -p "请输入允许连接的入口节点IP:" allowedIP
        if [[ -z "${allowedIP}" ]]; then
            echoContent red " ---> IP不能为空"
            return 1
        fi
        if ! isValidIP "${allowedIP}"; then
            echoContent red " ---> IP地址格式无效"
            return 1
        fi
    fi

    # 询问网络策略（IPv4/IPv6）
    echoContent yellow "\n选择出站网络策略："
    echoContent yellow "1.优先IPv4 [回车默认] - 推荐：出口机只有IPv4或网络不稳定时使用"
    echoContent yellow "2.优先IPv6 - 出口机双栈且希望优先使用IPv6"
    echoContent yellow "3.双栈自动 - 出口机双栈，按DNS返回顺序连接"
    read -r -p "请选择:" networkStrategyChoice

    local domainStrategy="prefer_ipv4"
    local strategyDesc="优先IPv4"
    case "${networkStrategyChoice}" in
        2)
            domainStrategy="prefer_ipv6"
            strategyDesc="优先IPv6"
            ;;
        3)
            domainStrategy=""
            strategyDesc="双栈自动"
            ;;
        *)
            domainStrategy="prefer_ipv4"
            strategyDesc="优先IPv4"
            ;;
    esac
    echoContent green " ---> 网络策略: ${strategyDesc}"

    # 创建入站配置
    # sniff/resolve 通过路由级 action 实现（见下方 chain_route.json），inbound 不再带 sniff 字段
    cat <<EOF >${SINGBOX_FRAGMENT_DIR}/chain_inbound.json
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "tag": "chain_inbound",
            "listen": "::",
            "listen_port": ${chainPort},
            "method": "${chainMethod}",
            "password": "${chainKey}",
            "multiplex": {
                "enabled": true
            }
        }
    ]
}
EOF

    # 同步 direct 出站：不再写 domain_strategy（1.12 deprecated、1.14 移除）。
    # 用户选的策略由 chain_route.json 的 action: resolve 路由级 action 落地。
    cat <<EOF >${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json
{
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF

    # 创建路由配置（链式入站走直连）：先 sniff 再按 domainStrategy 重解析，显式绑 inbound + timeout 1s。
    # default_domain_resolver 指向 01_dns.json 的 google tag——1.13 起没有它直接 FATAL。
    if [[ -n "${domainStrategy}" ]]; then
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/chain_route.json
{
    "route": {
        "rules": [
            { "inbound": "chain_inbound", "action": "sniff", "timeout": "1s" },
            { "inbound": "chain_inbound", "action": "resolve", "strategy": "${domainStrategy}" },
            { "inbound": ["chain_inbound"], "outbound": "direct" }
        ],
        "final": "direct",
        "default_domain_resolver": "google"
    }
}
EOF
    else
        cat <<EOF >${SINGBOX_FRAGMENT_DIR}/chain_route.json
{
    "route": {
        "rules": [
            { "inbound": "chain_inbound", "action": "sniff", "timeout": "1s" },
            { "inbound": ["chain_inbound"], "outbound": "direct" }
        ],
        "final": "direct",
        "default_domain_resolver": "google"
    }
}
EOF
    fi

    # 保存配置信息用于生成配置码（包含网络策略），原子写入避免半写入
    # schema_version: 1 是当前字段集；未来字段调整请提升此版本号，并在读取端按版本兼容
    local __chainExitInfo
    __chainExitInfo=$(cat <<EOF
{
    "schema_version": 1,
    "role": "exit",
    "ip": "${publicIP}",
    "port": ${chainPort},
    "method": "${chainMethod}",
    "password": "${chainKey}",
    "allowed_ip": "${allowedIP}",
    "domain_strategy": "${domainStrategy}"
}
EOF
)
    writeChainInfoAtomic "${CHAIN_EXIT_INFO}" "${__chainExitInfo}" || return 1
    # 中继状态还在的话 chainExitSourceInject 不注入来源限制（分不清哪份是覆盖前留下的）
    rm -f "${CHAIN_RELAY_INFO}"

    # 开放防火墙端口
    if [[ -n "${allowedIP}" ]]; then
        allowPort "${chainPort}" "tcp" "${allowedIP}/32"
        echoContent green " ---> $(t CHAIN_EXIT_SOURCE_LIMITED "${chainPort}" "${allowedIP}")"
        if ! firewallDefaultDenies; then
            echoContent yellow " ---> $(t CHAIN_EXIT_PORT_VISIBLE "${chainPort}")"
        fi
    else
        allowPort "${chainPort}" "tcp"
        echoContent green " ---> 已开放端口 ${chainPort}"
    fi

    # 出口只改了 sing-box，必须显式重启它：Xray 内核上 sing-box 是旁挂，reloadCore 只在装了 6 / 9 时才碰，出口会根本没起来
    if ! singBoxMergeConfig; then
        return 1
    fi
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: ${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"
        return 1
    fi

    # 生成并显示配置码
    echoContent green "\n=============================================================="
    echoContent green "出口节点配置完成！"
    echoContent green "=============================================================="
    echoContent yellow "\n链式代理配置码 (请复制到入口节点):\n"

    # IPv6 字面地址必须用 [host]:port 包裹，否则入口的 host:port 拆分（依赖最后一个 `:`）会切错
    local chainCode hostInCode="${publicIP}"
    if [[ "${publicIP}" == *:* ]]; then
        hostInCode="[${publicIP}]"
    fi
    chainCode="chain://ss2022@${hostInCode}:${chainPort}?key=$(echo -n "${chainKey}" | base64 | tr -d '\n')&method=${chainMethod}"
    echoContent skyBlue "${chainCode}"

    echoContent yellow "\n或手动配置:"
    echoContent green "  IP地址: ${publicIP}"
    echoContent green "  端口: ${chainPort}"
    echoContent green "  密钥: ${chainKey}"
    echoContent green "  加密方式: ${chainMethod}"

    echoContent yellow "\n请妥善保管配置码，切勿泄露！"
}

# 显示现有配置码
showExistingChainCode() {
    if [[ ! -f "${CHAIN_EXIT_INFO}" ]]; then
        echoContent red " ---> 未找到出口节点配置信息"
        return 1
    fi

    local publicIP port method password
    publicIP=$(jq -r '.ip' ${CHAIN_EXIT_INFO})
    port=$(jq -r '.port' ${CHAIN_EXIT_INFO})
    method=$(jq -r '.method' ${CHAIN_EXIT_INFO})
    password=$(jq -r '.password' ${CHAIN_EXIT_INFO})

    echoContent green "\n=============================================================="
    echoContent green "现有出口节点配置"
    echoContent green "=============================================================="

    # IPv6 字面地址同样需要 [host]:port 包裹
    local chainCode hostInCode="${publicIP}"
    if [[ "${publicIP}" == *:* ]]; then
        hostInCode="[${publicIP}]"
    fi
    chainCode="chain://ss2022@${hostInCode}:${port}?key=$(echo -n "${password}" | base64 | tr -d '\n')&method=${method}"
    echoContent yellow "\n配置码:\n"
    echoContent skyBlue "${chainCode}"

    echoContent yellow "\n手动配置信息:"
    echoContent green "  IP地址: ${publicIP}"
    echoContent green "  端口: ${port}"
    echoContent green "  密钥: ${password}"
    echoContent green "  加密方式: ${method}"
}

# SS2022 method 白名单与对应 base64 key 长度：16B → 24 chars，32B → 44 chars。
# 校验的是 sing-box password 字段那一层（URL 层 base64 -d 一次拿到的就是它）。
_chainSS2022PasswordOK() {
    local method="$1" key="$2"
    case "${method}" in
        2022-blake3-aes-128-gcm)
            [[ "${key}" =~ ^[A-Za-z0-9+/]{22}==$ ]]
            ;;
        2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305)
            [[ "${key}" =~ ^[A-Za-z0-9+/]{43}=$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# 把 URL-safe base64（"_-" 替换 "+/"，可能缺 padding）规范化成标准 base64
# 容忍 IM/链接预览常见的 URL 转码（%2B、%2F 已经被 cut 解析、_/- 字符替换、丢 padding）
_chainNormalizeBase64() {
    local s="$1"
    # URL-safe → standard
    s="${s//-/+}"
    s="${s//_//}"
    # 补齐 padding
    local mod=$(( ${#s} % 4 ))
    if [[ ${mod} -eq 2 ]]; then
        s="${s}=="
    elif [[ ${mod} -eq 3 ]]; then
        s="${s}="
    elif [[ ${mod} -eq 1 ]]; then
        # base64 解码后 1-mod 不合法，直接返回让上游识别错误
        echo "${s}"
        return 1
    fi
    echo "${s}"
}

# 从 host:port 字符串拆出 host/port，处理 IPv6 [host]:port 与 IPv4 host:port
# 输出到全局变量 _chainParsedHost / _chainParsedPort（caller 取用）
_chainSplitHostPort() {
    local s="$1"
    _chainParsedHost=""
    _chainParsedPort=""
    if [[ "${s}" == \[* ]]; then
        # IPv6: [2001:db8::1]:443
        _chainParsedHost="${s#[}"
        _chainParsedHost="${_chainParsedHost%%]:*}"
        _chainParsedPort="${s##*]:}"
    else
        # IPv4 / 域名: 1.2.3.4:443
        _chainParsedHost="${s%:*}"
        _chainParsedPort="${s##*:}"
    fi
    [[ -n "${_chainParsedHost}" && -n "${_chainParsedPort}" ]]
}

# 从 query string 中按 key 取 value（POSIX 工具，跨 grep 实现兼容）
# 例：_chainQueryGet "key=A&method=B" "method" → "B"
# Alpine BusyBox grep 没有 -P，旧版 parseChainCode 用 grep -oP 在 Alpine 上失效。
_chainQueryGet() {
    local query="$1" wantKey="$2"
    awk -F= -v k="${wantKey}" 'BEGIN{RS="&"} $1==k {print substr($0, length(k)+2); exit}' <<< "${query}"
}

# _chainTCPProbe HOST PORT [TIMEOUT] → 0=连得上。优先 nc -z，缺 nc 回退 bash /dev/tcp。
# Debian/Ubuntu 最小化镜像不带 netcat，只用 nc 会因 exit 127 把通的链路报成 ❌。
_chainTCPProbe() {
    local host=$1 port=$2 timeoutSec=${3:-5}
    if command -v nc >/dev/null 2>&1; then
        nc -z -w "${timeoutSec}" "${host}" "${port}" >/dev/null 2>&1
        return $?
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "${timeoutSec}" bash -c "exec 3<>/dev/tcp/${host}/${port} && exec 3<&-" >/dev/null 2>&1
        return $?
    fi
    (exec 3<>/dev/tcp/"${host}"/"${port}" && exec 3<&-) >/dev/null 2>&1
}

# 解析配置码 → chainHops (JSON 数组) + chainHopCount。
# V1: chain://ss2022@IP:PORT?key=&method=（IPv4 / [IPv6] / 域名）  V2: chain://v2@BASE64_JSON_ARRAY
# method 严格白名单不接受 silent fallback；base64 上限 64 KiB，跳数上限 8。
parseChainCode() {
    local code=$1

    # 初始化全局变量
    chainHops=""
    chainHopCount=0
    chainExitIP=""
    chainExitPort=""
    chainExitKey=""
    chainExitMethod=""

    # V2 多跳格式
    if [[ "${code}" =~ ^chain://v2@ ]]; then
        local base64Data
        base64Data="${code#chain://v2@}"

        # 体积上限：8 跳 * 200 字节字段 + JSON 包装 远小于 64 KiB
        if [[ ${#base64Data} -gt 65536 ]]; then
            echoContent red " ---> V2 配置码体积超限（>64KiB）"
            return 1
        fi

        # URL-safe → standard，再补 padding
        local normalized
        if ! normalized=$(_chainNormalizeBase64 "${base64Data}"); then
            echoContent red " ---> V2 配置码 base64 长度无效"
            return 1
        fi

        # 解码 Base64
        chainHops=$(echo "${normalized}" | base64 -d 2>/dev/null)
        if [[ -z "${chainHops}" ]] || ! echo "${chainHops}" | jq empty 2>/dev/null; then
            echoContent red " ---> V2 配置码解析失败，JSON 格式错误"
            return 1
        fi

        chainHopCount=$(echo "${chainHops}" | jq 'length')
        if [[ "${chainHopCount}" -lt 1 ]]; then
            echoContent red " ---> 配置码不包含任何跳转节点"
            return 1
        fi
        if [[ "${chainHopCount}" -gt 8 ]]; then
            echoContent red " ---> 配置码跳数超限（${chainHopCount} > 8）"
            return 1
        fi

        # 逐跳校验：ip/port/method/key 都必须合规，否则拒绝整个配置码
        local i=1
        while [[ $i -le ${chainHopCount} ]]; do
            local hopIP hopPort hopKey hopMethod
            hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip // empty")
            hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port // empty")
            hopKey=$(echo "${chainHops}" | jq -r ".[$((i-1))].key // empty")
            hopMethod=$(echo "${chainHops}" | jq -r ".[$((i-1))].method // empty")

            if [[ -z "${hopIP}" || -z "${hopPort}" || -z "${hopKey}" || -z "${hopMethod}" ]]; then
                echoContent red " ---> V2 配置码第 ${i} 跳缺少必要字段"
                return 1
            fi
            # IP/host 校验：允许 IPv4/IPv6 或域名（带 . 的非空字符串）
            if ! isValidIP "${hopIP}" && [[ ! "${hopIP}" =~ ^[A-Za-z0-9.-]+$ ]]; then
                echoContent red " ---> V2 配置码第 ${i} 跳 host 非法: ${hopIP}"
                return 1
            fi
            # port：1-65535
            if ! [[ "${hopPort}" =~ ^[0-9]+$ ]] || (( hopPort < 1 || hopPort > 65535 )); then
                echoContent red " ---> V2 配置码第 ${i} 跳端口非法: ${hopPort}"
                return 1
            fi
            # method/key 严格白名单 + 长度匹配
            if ! _chainSS2022PasswordOK "${hopMethod}" "${hopKey}"; then
                echoContent red " ---> V2 配置码第 ${i} 跳 method/key 不匹配 SS2022 规范"
                return 1
            fi
            ((i++))
        done

        echoContent green " ---> V2 多跳配置码解析成功"
        echoContent green "  总跳数: ${chainHopCount}"

        # 显示链路
        i=1
        while [[ $i -le ${chainHopCount} ]]; do
            local hopIP hopPort
            hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
            hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
            if [[ $i -eq ${chainHopCount} ]]; then
                echoContent green "  第${i}跳 (出口): ${hopIP}:${hopPort}"
            else
                echoContent green "  第${i}跳 (中继): ${hopIP}:${hopPort}"
            fi
            ((i++))
        done

        # 兼容性：设置最后一跳为出口
        chainExitIP=$(echo "${chainHops}" | jq -r '.[-1].ip')
        chainExitPort=$(echo "${chainHops}" | jq -r '.[-1].port')
        chainExitKey=$(echo "${chainHops}" | jq -r '.[-1].key')
        chainExitMethod=$(echo "${chainHops}" | jq -r '.[-1].method')

        return 0
    fi

    # V1 单跳格式
    if [[ "${code}" =~ ^chain://ss2022@ ]]; then
        # 拆 host:port?params
        local hostPart paramPart
        hostPart="${code#chain://ss2022@}"
        if [[ "${hostPart}" == *\?* ]]; then
            paramPart="${hostPart#*\?}"
            hostPart="${hostPart%%\?*}"
        else
            paramPart=""
        fi

        # 处理 IPv4/IPv6 host:port 拆分（IPv6 用 [host]:port）
        if ! _chainSplitHostPort "${hostPart}"; then
            echoContent red " ---> 配置码 host:port 解析失败: ${hostPart}"
            return 1
        fi
        chainExitIP="${_chainParsedHost}"
        chainExitPort="${_chainParsedPort}"
        unset _chainParsedHost _chainParsedPort

        # 校验 host
        if ! isValidIP "${chainExitIP}" && [[ ! "${chainExitIP}" =~ ^[A-Za-z0-9.-]+$ ]]; then
            echoContent red " ---> 配置码 host 非法: ${chainExitIP}"
            return 1
        fi
        # 校验 port
        if ! [[ "${chainExitPort}" =~ ^[0-9]+$ ]] || (( chainExitPort < 1 || chainExitPort > 65535 )); then
            echoContent red " ---> 配置码端口非法: ${chainExitPort}"
            return 1
        fi

        # 提取 key（POSIX awk 抽取，避免 grep -oP 在 Alpine BusyBox grep 上失效）
        local keyBase64
        keyBase64=$(_chainQueryGet "${paramPart}" "key")
        if [[ -z "${keyBase64}" ]]; then
            echoContent red " ---> 配置码缺少 key 参数"
            return 1
        fi

        # URL-safe → standard，再 base64 -d；解码失败拒绝（不再 fallback）
        local normalizedKey
        if ! normalizedKey=$(_chainNormalizeBase64 "${keyBase64}"); then
            echoContent red " ---> 配置码 key 编码无效"
            return 1
        fi
        chainExitKey=$(echo "${normalizedKey}" | base64 -d 2>/dev/null)
        if [[ -z "${chainExitKey}" ]]; then
            echoContent red " ---> 配置码 key base64 解码失败"
            return 1
        fi

        # 提取 method（必填，不再 silent fallback）
        chainExitMethod=$(_chainQueryGet "${paramPart}" "method")
        if [[ -z "${chainExitMethod}" ]]; then
            echoContent red " ---> 配置码缺少 method 参数"
            return 1
        fi

        # method/key 长度联合校验
        if ! _chainSS2022PasswordOK "${chainExitMethod}" "${chainExitKey}"; then
            echoContent red " ---> 配置码 method/key 不匹配 SS2022 规范"
            echoContent red "      method=${chainExitMethod}, key 长度=${#chainExitKey}"
            return 1
        fi

        # 转换为 V2 格式的单跳数组
        chainHops=$(jq -n --arg ip "${chainExitIP}" --argjson port "${chainExitPort}" \
            --arg key "${chainExitKey}" --arg method "${chainExitMethod}" \
            '[{ip: $ip, port: $port, key: $key, method: $method}]')
        chainHopCount=1

        echoContent green " ---> V1 配置码解析成功"
        echoContent green "  出口IP: ${chainExitIP}"
        echoContent green "  出口端口: ${chainExitPort}"
        echoContent green "  加密方式: ${chainExitMethod}"

        return 0
    fi

    echoContent red " ---> 配置码格式错误，不支持的格式"
    return 1
}

# 通过配置码配置入口节点
setupChainEntryByCode() {
    if planAction "$(t PLAN_CHAIN_ENTRY)"; then return 0; fi
    echoContent skyBlue "\n配置入口节点 (Entry) - 配置码模式"
    echoContent red "\n=============================================================="

    echoContent yellow "请粘贴出口或中继节点的配置码:"
    read -r -p "配置码:" chainCode

    if [[ -z "${chainCode}" ]]; then
        echoContent red " ---> 配置码不能为空"
        return 1
    fi

    # 解析配置码 (支持 V1 单跳和 V2 多跳)
    if ! parseChainCode "${chainCode}"; then
        return 1
    fi

    # 根据跳数调用不同的配置函数
    if [[ ${chainHopCount} -gt 1 ]]; then
        # 多跳模式 - 使用全局 chainHops 变量
        setupChainEntryMultiHop
    else
        # 单跳模式 - 向后兼容
        setupChainEntry "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}"
    fi
}

# 手动配置入口节点
setupChainEntryManual() {
    if planAction "$(t PLAN_CHAIN_ENTRY)"; then return 0; fi
    echoContent skyBlue "\n配置入口节点 (Entry) - 手动模式"
    echoContent red "\n=============================================================="

    read -r -p "出口节点IP:" chainExitIP
    if [[ -z "${chainExitIP}" ]]; then
        echoContent red " ---> IP不能为空"
        return 1
    fi
    if ! isValidIP "${chainExitIP}"; then
        echoContent red " ---> IP地址格式无效"
        return 1
    fi

    read -r -p "出口节点端口:" chainExitPort
    if [[ -z "${chainExitPort}" ]]; then
        echoContent red " ---> 端口不能为空"
        return 1
    fi

    read -r -p "密钥:" chainExitKey
    if [[ -z "${chainExitKey}" ]]; then
        echoContent red " ---> 密钥不能为空"
        return 1
    fi

    echoContent yellow "\n加密方式 [回车默认: 2022-blake3-aes-128-gcm]"
    read -r -p "加密方式:" chainExitMethod
    if [[ -z "${chainExitMethod}" ]]; then
        chainExitMethod="2022-blake3-aes-128-gcm"
    fi

    setupChainEntry "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}"
}

# chainHopOutbounds HOPS [TAG HOP_PREFIX] → 多跳出站片段：第 i 跳经第 i-1 跳拨出，最后一跳叫 TAG（默认 chain_outbound），
# 前面的叫 HOP_PREFIX+i（默认 chain_hop_）；HOPS 为空时失败。不能用 direct 出站加 detour 当别名：
# sing-box 1.12 起拒绝（`detour` is not supported in direct context），整份配置合并失败
chainHopOutbounds() {
    jq -n --argjson hops "$1" --arg last "${2:-chain_outbound}" --arg prefix "${3:-chain_hop_}" '
        ($hops | length) as $n
        | if $n == 0 then error("no hops") else
            {outbounds: [$hops | to_entries[] | .key as $i | .value as $h
                | {
                    type: "shadowsocks",
                    tag: (if $i == $n - 1 then $last else $prefix + (($i + 1) | tostring) end),
                    server: $h.ip,
                    server_port: $h.port,
                    method: $h.method,
                    password: $h.key,
                    multiplex: {enabled: true, protocol: "h2mux", max_connections: 4, min_streams: 4}
                } + (if $i > 0 then {detour: ($prefix + ($i | tostring))} else {} end)]}
        end'
}

# chainRelayRouteJson DOWNSTREAM_HOPS → 中继的 chain_route.json。入口把后面各跳嵌套着拨，发往下一跳本身的连接是入口包好的内层：
# 原样直连给下一跳；再套进下游链会多一层封装，下一跳还得回连自己的公网口（只放行中继或云上不支持回环时链路就断）
chainRelayRouteJson() {
    jq -n --argjson hops "$1" '
        $hops[0] as $next
        | (if ($next.ip | test("^[0-9.]+$") or test(":")) then {ip_cidr: [$next.ip]} else {domain: [$next.ip]} end) as $dest
        | {route: {
            rules: [
                ({inbound: ["chain_inbound"]} + $dest + {port: [$next.port], outbound: "direct"}),
                {inbound: "chain_inbound", action: "sniff", timeout: "1s"},
                {inbound: ["chain_inbound"], outbound: "chain_outbound"}
            ],
            final: "direct",
            default_domain_resolver: "google"
        }}'
}

# 配置中继节点 (Relay)
# 中继节点同时作为上游的"出口"（接收流量）和下游的"入口"（转发流量）
setupChainRelay() {
    if planAction "$(t PLAN_CHAIN_RELAY)"; then return 0; fi
    echoContent skyBlue "\n配置中继节点 (Relay)"
    echoContent red "\n=============================================================="
    echoContent yellow "中继节点工作原理:"
    echoContent yellow "  上游节点 → [本机] → 下游节点 → ... → 出口 → 互联网"
    echoContent yellow "  本机将接收上游流量并转发到下游链路\n"

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理配置
    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_inbound.json" ]] || \
       [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if ! isYesInput "${confirmOverwrite}"; then
            return 0
        fi
    fi

    # 步骤1: 导入下游配置码
    echoContent yellow "步骤 1/3: 导入下游节点配置码"
    echoContent yellow "请粘贴下游节点（出口或其他中继）的配置码:"
    read -r -p "配置码:" downstreamCode

    if [[ -z "${downstreamCode}" ]]; then
        echoContent red " ---> 配置码不能为空"
        return 1
    fi

    # 解析下游配置码
    if ! parseChainCode "${downstreamCode}"; then
        return 1
    fi

    # chainHops 现在包含下游所有节点

    # 步骤2: 配置本机监听
    echoContent yellow "\n步骤 2/3: 配置本机监听端口"

    # 生成随机端口 (10000-60000)
    local chainPort
    chainPort=$(randomNum 10000 60000)
    echoContent yellow "请输入本机链式代理端口 [回车使用随机端口: ${chainPort}]"
    read -r -p "端口:" inputPort
    if [[ -n "${inputPort}" ]]; then
        if [[ ! "${inputPort}" =~ ^[0-9]+$ ]] || [[ "${inputPort}" -lt 1 ]] || [[ "${inputPort}" -gt 65535 ]]; then
            echoContent red " ---> 端口格式错误"
            return 1
        fi
        chainPort=${inputPort}
    fi

    # 生成密钥
    local chainKey
    chainKey=$(generateChainKey)
    local chainMethod="2022-blake3-aes-128-gcm"

    # 获取公网IP
    local publicIP
    publicIP=$(getChainPublicIP)
    if [[ -z "${publicIP}" ]]; then
        echoContent yellow "\n无法自动获取公网IP，请手动输入"
        read -r -p "公网IP:" publicIP
        if [[ -z "${publicIP}" ]]; then
            echoContent red " ---> IP不能为空"
            return 1
        fi
        if ! isValidIP "${publicIP}"; then
            echoContent red " ---> IP地址格式无效"
            return 1
        fi
    fi
    echoContent green " ---> 本机公网IP: ${publicIP}"

    # 步骤3: 生成配置
    echoContent yellow "\n步骤 3/3: 生成配置..."

    # 创建入站配置 (接收上游流量)
    # sniff 通过路由级 action 实现（见 chain_route.json）
    cat <<EOF >${SINGBOX_FRAGMENT_DIR}/chain_inbound.json
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "tag": "chain_inbound",
            "listen": "::",
            "listen_port": ${chainPort},
            "method": "${chainMethod}",
            "password": "${chainKey}",
            "multiplex": {
                "enabled": true
            }
        }
    ]
}
EOF

    local chainOutboundJson
    if ! chainOutboundJson=$(chainHopOutbounds "${chainHops}") || [[ -z "${chainOutboundJson}" ]]; then
        echoContent red " ---> 链式出站配置生成失败"
        return 1
    fi
    printf '%s\n' "${chainOutboundJson}" > ${SINGBOX_FRAGMENT_DIR}/chain_outbound.json

    local relayRouteJson
    if ! relayRouteJson=$(chainRelayRouteJson "${chainHops}") || ! jsonWriteFile "${SINGBOX_FRAGMENT_DIR}/chain_route.json" "${relayRouteJson}" false; then
        echoContent red " ---> 链式路由配置生成失败"
        return 1
    fi

    # 构建新的 hops 数组 (本机 + 下游所有节点)
    local newHops
    newHops=$(jq -n --arg ip "${publicIP}" --argjson port "${chainPort}" \
        --arg key "${chainKey}" --arg method "${chainMethod}" \
        --argjson downstream "${chainHops}" \
        '[{ip: $ip, port: $port, key: $key, method: $method}] + $downstream')

    # 保存配置信息（原子写入）
    local __chainRelayInfo
    __chainRelayInfo=$(cat <<EOF
{
    "schema_version": 1,
    "role": "relay",
    "ip": "${publicIP}",
    "port": ${chainPort},
    "method": "${chainMethod}",
    "password": "${chainKey}",
    "downstream_hops": ${chainHops},
    "total_hops": $((chainHopCount + 1))
}
EOF
)
    writeChainInfoAtomic "${CHAIN_RELAY_INFO}" "${__chainRelayInfo}" || return 1
    rm -f "${CHAIN_EXIT_INFO}"

    # 开放防火墙端口
    allowPort "${chainPort}" "tcp"
    echoContent green " ---> 已开放端口 ${chainPort}"

    # 合并配置并重启
    if ! singBoxMergeConfig; then
        return 1
    fi
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: ${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"
        return 1
    fi

    # 生成 V2 配置码
    local newChainCode
    newChainCode="chain://v2@$(echo -n "${newHops}" | base64 | tr -d '\n')"

    echoContent green "\n=============================================================="
    echoContent green "中继节点配置完成！"
    echoContent green "=============================================================="
    echoContent yellow "\n当前链路 (${chainHopCount} + 1 = $((chainHopCount + 1)) 跳):"
    echoContent green "  上游 → 本机(${publicIP}:${chainPort})"

    i=1
    while [[ $i -le ${chainHopCount} ]]; do
        local hopIP hopPort
        hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
        if [[ $i -eq ${chainHopCount} ]]; then
            echoContent green "        → 出口(${hopIP}:${hopPort}) → 互联网"
        else
            echoContent green "        → 中继${i}(${hopIP}:${hopPort})"
        fi
        ((i++))
    done

    echoContent yellow "\n配置码 (供上游入口或中继节点使用):\n"
    echoContent skyBlue "${newChainCode}"

    echoContent yellow "\n请妥善保管配置码，切勿泄露！"
}

# writeChainBridgeInbound PORT → sing-box 片段 chain_bridge_inbound.json：Xray 经本机回环 socks 进 sing-box 的桥
writeChainBridgeInbound() {
    cat <<EOF >"${SINGBOX_FRAGMENT_DIR}/chain_bridge_inbound.json"
{
    "inbounds": [
        {
            "type": "socks",
            "tag": "chain_bridge_in",
            "listen": "127.0.0.1",
            "listen_port": $1
        }
    ]
}
EOF
}

# writeChainEntryRoute HAS_XRAY → 单链路 / 多跳入口的 chain_route.json，兜底都是 chain_outbound
# 有桥时先 sniff 再 prefer_ipv4 重解析（出口机可能没有 IPv6）；default_domain_resolver 1.13 起必填
writeChainEntryRoute() {
    if [[ "$1" == "true" ]]; then
        cat <<EOF >"${SINGBOX_FRAGMENT_DIR}/chain_route.json"
{
    "route": {
        "rules": [
            { "inbound": "chain_bridge_in", "action": "sniff", "timeout": "1s" },
            { "inbound": "chain_bridge_in", "action": "resolve", "strategy": "prefer_ipv4" },
            { "inbound": ["chain_bridge_in"], "outbound": "chain_outbound" }
        ],
        "final": "chain_outbound",
        "default_domain_resolver": "google"
    }
}
EOF
    else
        cat <<EOF >"${SINGBOX_FRAGMENT_DIR}/chain_route.json"
{
    "route": {
        "final": "chain_outbound",
        "default_domain_resolver": "google"
    }
}
EOF
    fi
}

# ======================= 按账号选出口 =======================
# 映射 accounts {账号名: 出口} 存在入口的链式状态文件里，出口写 sing-box 出站 tag：direct、单链路 / 多跳的 chain_outbound、
# 多链路的链路名；没写的账号走 default_chain（单链路 / 多跳缺省 chain_outbound）。被指定的账号以映射为终态，域名分流只管没指定的

# chainAccountStateFile → 能按账号选出口的入口状态文件（多链路、单链路、多跳）；没有或明说是别的角色 / external_single 返回 1
# 读不懂、缺 role 也照样打印路径，让 chainAccountReadState 报错或照常读映射，不当成「没有映射」
chainAccountStateFile() {
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        echo "${CHAIN_MULTI_INFO}"
        return 0
    fi
    [[ -f "${CHAIN_ENTRY_INFO}" ]] || return 1
    jq -e '((.role | type) == "string" and .role != "entry") or ((.mode | type) == "string" and .mode != "multi_hop")' \
        "${CHAIN_ENTRY_INFO}" >/dev/null 2>&1 && return 1
    echo "${CHAIN_ENTRY_INFO}"
}

# chainAccountReadState → 打印当前入口的链式状态（一行 JSON），没有能选出口的入口时打印 {}
# 状态读不懂或映射不合法返回 1：调用方必须中止，跳过映射等于让指定了出口的人静默走默认出口
chainAccountReadState() {
    local file state invalid
    if ! file=$(chainAccountStateFile); then
        echo '{}'
        return 0
    fi
    if ! state=$(jq -ce 'select(type == "object")' "${file}" 2>/dev/null) || [[ -z "${state}" ]]; then
        echoContent red " ---> $(t CHAIN_ACCOUNT_STATE_BAD "${file}")" >&2
        return 1
    fi
    invalid=$(jq -r --argjson base "${CHAIN_BRIDGE_PORT}" --argjson last "${CHAIN_BRIDGE_PORT_LAST}" '
        ((if .mode == "multi_chain" then [.chains[]?.name] else ["chain_outbound"] end) + ["direct"]) as $exits
        | ([(.accounts // {})[] | select(. != "direct")] | unique) as $refs
        | ( (.accounts // {}) | to_entries[]
            | select((.key | test("\\A[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}\\z") | not) or ((.value as $v | $exits | index($v)) == null))
            | "\(.key)=\(.value)" ),
          ( select(.mode != "multi_chain" and .default_chain != null and .default_chain != "chain_outbound" and .default_chain != "direct")
            | "default_chain=\(.default_chain)" ),
          ( select(.mode == "multi_chain") | .chains[]? | select(.name as $n | $refs | index($n))
            | select((.bridge_port | type) != "number" or .bridge_port <= $base or .bridge_port > $last) | "bridge_port(\(.name))=\(.bridge_port)" ),
          ( select(.mode == "multi_chain") | [.chains[]?.bridge_port | select(. != null)] | select(length != (unique | length))
            | "bridge_port=\(.)" )' <<<"${state}" 2>&1) || invalid="${invalid:-accounts}"
    if [[ -n "${invalid}" ]]; then
        echoContent red " ---> $(t CHAIN_ACCOUNT_STATE_INVALID "${file}" "$(paste -sd ' ' - <<<"${invalid}")")" >&2
        return 1
    fi
    printf '%s\n' "${state}"
}

# chainAccountBridges STATE → 多链路里被映射引用的链路 [{name, port}]（按名字排序）；单链路 / 多跳返回 []
# 端口是链路自己的 bridge_port，Xray 出站与 sing-box 入站都从这里取
chainAccountBridges() {
    jq -c 'if .mode == "multi_chain"
        then ([(.accounts // {})[] | select(. != "direct")] | unique) as $refs
            | [.chains[]? | select(.name as $n | $refs | index($n)) | {name, port: .bridge_port}] | sort_by(.name)
        else [] end' <<<"$1"
}

# chainAccountAssignPorts STATE → 给多链路里新被引用、还没有 bridge_port 的链路分一个空着的桥端口；分过的链路在就一直留着。
# 端口跟着链路不跟着排序：重载时两个内核先后重启，旧 sing-box 与新 Xray 端口对不上时只会连不上，不会进到别的出口。
# 本机已有进程在听的端口也跳过：sing-box 绑不上是 exit 1，chainAccountSave 的回滚到不了
chainAccountAssignPorts() {
    jq -c --argjson base "${CHAIN_BRIDGE_PORT}" --argjson last "$((TOPO_PAGE_PORT - 1))" \
        --argjson busy "$(listeningPorts tcp | jq -sc .)" '
        if .mode != "multi_chain" then . else
            ([(.accounts // {})[] | select(. != "direct")] | unique) as $refs
            | reduce (.chains | to_entries[] | select((.value.name as $n | $refs | index($n)) and .value.bridge_port == null) | .key) as $i (.;
                (([range($base + 1; $last + 1)] - [.chains[].bridge_port | select(. != null)] - $busy) | first) as $p
                | if $p == null then error("no free bridge port") else .chains[$i].bridge_port = $p end)
        end' <<<"$1"
}

# writeXrayChainConfig PORT → Xray 侧两件：chain_proxy 系列出站指向本机的桥；09_routing.json 整份换成链式路由：先按账号映射分
# （user 正则，. + 转义——Xray 静默丢弃写坏的正则），其余交给默认出口；没变就不写，写了当场补封本机的规则（被 systemd 拉起时没有那一步）。
# 原路由只在第一次被换掉时存成 .bak.chain：改映射、每次启动 Xray 都调这里，覆盖掉的话 removeChainProxy 就恢复不出原样
writeXrayChainConfig() {
    local port=$1 state bridges outbounds routing current
    state=$(chainAccountReadState) || return 1
    bridges=$(chainAccountBridges "${state}") || return 1
    # 直连走链式自己的 chain_direct：WARP / IPv6 全局会删掉 z_direct_outbound，指向它的账号就全断。它不能排第一，Xray 把第一个出站当默认
    outbounds=$(jq -n --argjson port "${port}" --argjson bridges "${bridges}" '
        def socksOut($tag; $p): {tag: $tag, protocol: "socks", settings: {servers: [{address: "127.0.0.1", port: $p}]}};
        {outbounds: ([socksOut("chain_proxy"; $port)] + [$bridges[] | socksOut("chain_proxy_" + .name; .port)] + [{tag: "chain_direct", protocol: "freedom"}])}') || return 1
    routing=$(jq -n --argjson s "${state}" '
        ($s.mode // "") as $mode
        | (if $mode != "multi_chain" and $s.default_chain == "direct" then "chain_direct" else "chain_proxy" end) as $dflt
        | {routing: {domainStrategy: "AsIs", rules: (
            ([($s.accounts // {}) | to_entries[]
                | {re: ("regexp:^" + ([.key | explode[] | if . == 46 or . == 43 then [92, .] else [.] end] | add | implode) + "-[^-]*$"),
                   tag: (if .value == "direct" then "chain_direct" elif $mode == "multi_chain" then "chain_proxy_" + .value else "chain_proxy" end)}]
               | group_by(.tag) | map({type: "field", user: map(.re), outboundTag: .[0].tag}))
            + [{type: "field", domain: ["domain:gstatic.com", "domain:googleapis.com", "domain:googleapis.cn"], outboundTag: $dflt},
               {type: "field", network: "tcp,udp", outboundTag: $dflt}])}}') || return 1

    if [[ "$(jq -cS . "${XRAY_CONF_DIR}/chain_outbound.json" 2>/dev/null)" != "$(jq -cS . <<<"${outbounds}")" ]]; then
        jsonWriteFile "${XRAY_CONF_DIR}/chain_outbound.json" "${outbounds}" false || return 1
    fi
    # local-block 组是 ensureXrayLocalBlock 补的，不算链式路由，比较时去掉
    current=$(jq -cS '.routing.rules |= map(select((.ruleTag // "") | startswith("local-block") | not))' "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null)
    if [[ "${current}" != "$(jq -cS . <<<"${routing}")" ]]; then
        if [[ -f "${XRAY_CONF_DIR}/09_routing.json" && ! -f "${XRAY_CONF_DIR}/09_routing.json.bak.chain" ]]; then
            cp "${XRAY_CONF_DIR}/09_routing.json" "${XRAY_CONF_DIR}/09_routing.json.bak.chain" || return 1
        fi
        jsonWriteFile "${XRAY_CONF_DIR}/09_routing.json" "${routing}" false || return 1
    fi
    ensureXrayLocalBlock
}

# chainAccountInject MERGED → 把映射写进合并后的 sing-box 配置，规则插在最前：多链路被引用的链路各一条桥（有 Xray 的桥时），
# 再按 users[].name 全名匹配 sing-box 承载的用户（auth_user 只认全名，所以合并时现生成）。
# 单链路 / 多跳 default_chain 为 direct 时 final 改成 direct。返回 1 时合并必须随之失败
chainAccountInject() {
    local merged=$1 state bridges out
    state=$(chainAccountReadState) || return 1
    [[ "${state}" == "{}" ]] && return 0
    bridges=$(chainAccountBridges "${state}") || return 1
    out=$(jq --argjson s "${state}" --argjson bridges "${bridges}" '
        ($s.accounts // {}) as $acc
        | (if ([.inbounds[]? | select(.tag == "chain_bridge_in")] | length) > 0
           then [$bridges[] | {type: "socks", tag: ("chain_acct_in_" + .name), listen: "127.0.0.1", listen_port: .port}]
           else [] end) as $inb
        | ($inb | map(.tag)) as $tags
        | ([.inbounds[]? | .users[]? | (.name // .username // .Username) | select(type == "string" and test("-"))] | unique
           | map(. as $n | {name: $n, out: $acc[$n | sub("-[^-]*$"; "")]}) | map(select(.out != null))) as $hits
        | ((if ($tags | length) > 0
              then [{inbound: $tags, action: "sniff", timeout: "1s"}, {inbound: $tags, action: "resolve", strategy: "prefer_ipv4"}]
              else [] end)
           + [$inb[] | {inbound: [.tag], outbound: (.tag | ltrimstr("chain_acct_in_"))}]
           + ($hits | group_by(.out) | map({auth_user: map(.name), outbound: .[0].out}))) as $pre
        | .inbounds = ((.inbounds // []) + $inb)
        | .route.rules = ($pre + (.route.rules // []))
        | (if ($s.mode // "") != "multi_chain" and $s.default_chain == "direct" then .route.final = "direct" else . end)
    ' "${merged}") || return 1
    jsonWriteFile "${merged}" "${out}" false
}

# chainAccountCarry INFO → 单链路 / 多跳的新状态带上旧状态的 accounts 与 default_chain；换出口配置码时不丢映射，
# 否则标了直连的人会全进链路。旧状态读不懂返回 1，不带着空映射继续
chainAccountCarry() {
    local old='{}'
    if [[ -f "${CHAIN_ENTRY_INFO}" ]] && ! old=$(jq -ce '
            if (.role | type) == "string" and .role != "entry" or ((.mode | type) == "string" and .mode != "multi_hop") then {}
            else {accounts, default_chain} | with_entries(select(.value != null)) end' "${CHAIN_ENTRY_INFO}" 2>/dev/null); then
        echoContent red " ---> $(t CHAIN_ACCOUNT_CARRY_FAILED "${CHAIN_ENTRY_INFO}")" >&2
        return 1
    fi
    jq -c --argjson old "${old}" '. + $old' <<<"$1"
}

# chainAccountApply → 映射或默认出口改过之后：Xray 侧（有的话）重写并过 -test，sing-box 重新合并（注入在合并里，合并自带 check），
# 两边都过了才重载内核。重载里起不来是 exit 1，到不了调用方的回滚，所以配置错误必须在重载之前返回 1
chainAccountApply() {
    if [[ ! -f "${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json" ]]; then
        singBoxConfigPath="${SINGBOX_FRAGMENT_DIR}/" ensureDirectOutbound || return 1
    fi
    if [[ -f "${XRAY_CONF_DIR}/chain_outbound.json" ]]; then
        writeXrayChainConfig "${CHAIN_BRIDGE_PORT}" || return 1
        xrayConfigTest || return 1
    fi
    singBoxMergeConfig || return 1
    reloadCore
}

# chainAccountSave FILE NEW OLD → 写入新状态并生效；没能生效就写回旧状态再生效一次，不留一半新一半旧的路由
chainAccountSave() {
    local file=$1 new=$2 old=$3
    writeChainInfoAtomic "${file}" "${new}" || return 1
    chainAccountApply && return 0
    writeChainInfoAtomic "${file}" "${old}" && chainAccountApply
    echoContent red " ---> $(t CHAIN_ACCOUNT_APPLY_FAILED)"
}

# chainAccountForget NAME → 账号删掉时连映射一起删，否则以后同名新建的账号会继承旧出口；调用方随后要 reloadCore
chainAccountForget() {
    local file state
    file=$(chainAccountStateFile) || return 0
    state=$(chainAccountReadState) || return 1
    jq -e --arg n "$1" '(.accounts // {}) | has($n)' <<<"${state}" >/dev/null 2>&1 || return 0
    writeChainInfoAtomic "${file}" "$(jq -c --arg n "$1" 'del(.accounts[$n])' <<<"${state}")" || return 1
    if [[ -f "${XRAY_CONF_DIR}/chain_outbound.json" ]]; then
        writeXrayChainConfig "${CHAIN_BRIDGE_PORT}" || return 1
    fi
}

# chainAccountAllNames → 本机全部账号名（去掉协议后缀，升序去重）：Xray 与 sing-box 两边按注册表找到的入站文件
chainAccountAllNames() {
    local dir id file files=()
    for dir in "${XRAY_CONF_DIR}/" "${SINGBOX_FRAGMENT_DIR}/"; do
        [[ -d "${dir}" ]] || continue
        for id in $(scanInstalledProtocols "${dir}" | tr ',' ' '); do
            file=$(getProtocolConfigPath "${id}" "${dir}")
            [[ -f "${file}" ]] && files+=("${file}")
        done
    done
    ((${#files[@]})) || return 0
    jq -rn '[inputs | .inbounds[]? | (.settings.clients[]?.email, (.users[]? | .name // .username))
        | select(type == "string" and test("-")) | sub("-[^-]*$"; "")] | unique | .[]' "${files[@]}"
}

# chainAccountExitLabel VALUE → 出口的显示名
chainAccountExitLabel() {
    case "$1" in
        direct) t CHAIN_ACCOUNT_DIRECT ;;
        chain_outbound) t CHAIN_ACCOUNT_CHAIN ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# chainAccountExitMenu → 菜单：给账号指定出口（直连、链路或多链路里的某条），或改回跟随默认
chainAccountExitMenu() {
    local file state mode names name dflt i pick exitPick target new
    local -a nameList exitList
    if ! file=$(chainAccountStateFile); then
        echoContent red " ---> $(t CHAIN_ACCOUNT_NOT_ENTRY)"
        return 1
    fi
    state=$(chainAccountReadState) || return 1
    mode=$(jq -r '.mode // ""' <<<"${state}")
    # 配链路时还没装 Xray 协议的话，Xray 一侧根本没接进链路，映射对 Xray 账号不起作用
    if xrayChainUnwired; then
        echoContent red " ---> $(t CHAIN_ACCOUNT_XRAY_UNWIRED)"
        return 1
    fi
    if ! names=$(chainAccountAllNames); then
        echoContent red " ---> $(t CHAIN_ACCOUNT_LIST_FAILED)"
        return 1
    fi
    # 拼车停用中的成员不在入站里、chainAccountAllNames 看不到，恢复后照样按映射走，所以从拼车状态里补上
    mapfile -t nameList < <({ printf '%s\n' "${names}"; jq -r '(.accounts // {}) | keys[]' <<<"${state}"
        carpoolReadState 2>/dev/null | jq -r 'select(.enabled == true) | .members | keys[]'; } | grep -v '^$' | sort -u)
    dflt=$(jq -r 'if .mode == "multi_chain" then (.default_chain // "direct") else (.default_chain // "chain_outbound") end' <<<"${state}")

    echoContent skyBlue "\n$(t CHAIN_ACCOUNT_TITLE)"
    echoContent red "=============================================================="
    if [[ "${mode}" == "multi_chain" ]]; then
        echoContent yellow "$(t CHAIN_ACCOUNT_DEFAULT_LINE_MULTI "$(chainAccountExitLabel "${dflt}")")"
    else
        echoContent yellow "$(t CHAIN_ACCOUNT_DEFAULT_LINE "$(chainAccountExitLabel "${dflt}")")"
    fi
    if [[ "${mode}" != "multi_chain" && "${dflt}" != "direct" ]] && jq -e '.protocol_routing.enabled == true' <<<"${state}" >/dev/null 2>&1; then
        echoContent yellow "$(t CHAIN_ACCOUNT_PROTOCOL_ROUTING_HINT)"
    fi
    echoContent yellow "$(t CHAIN_ACCOUNT_STRICT_HINT)\n"
    for i in "${!nameList[@]}"; do
        target=$(jq -r --arg n "${nameList[$i]}" '.accounts[$n]? // empty' <<<"${state}")
        echoContent yellow "  $((i + 1)). ${nameList[$i]} → $(if [[ -n "${target}" ]]; then chainAccountExitLabel "${target}"; else t CHAIN_ACCOUNT_FOLLOW_DEFAULT; fi)"
    done
    echoContent yellow "  0. $(t CHAIN_ACCOUNT_SET_DEFAULT)"
    read -r -p "$(t PROMPT_SELECT):" pick

    if [[ "${pick}" == "0" ]]; then
        if [[ "${mode}" == "multi_chain" ]]; then
            setDefaultChain
            return $?
        fi
        echoContent yellow "  1. $(t CHAIN_ACCOUNT_CHAIN)"
        echoContent yellow "  2. $(t CHAIN_ACCOUNT_DIRECT)"
        read -r -p "$(t PROMPT_SELECT):" exitPick
        case "${exitPick}" in
            1) target=chain_outbound ;;
            2) target=direct ;;
            *) echoContent red " ---> $(t INVALID_SELECTION)"; return 1 ;;
        esac
        new=$(jq -c --arg v "${target}" '.default_chain = $v' <<<"${state}") || return 1
        chainAccountSave "${file}" "${new}" "${state}" || return 1
        echoContent green " ---> $(t CHAIN_ACCOUNT_DEFAULT_SAVED "$(chainAccountExitLabel "${target}")")"
        return 0
    fi

    if [[ ! "${pick}" =~ ^[1-9][0-9]*$ ]] || ((pick > ${#nameList[@]})); then
        echoContent red " ---> $(t INVALID_SELECTION)"
        return 1
    fi
    name=${nameList[$((pick - 1))]}
    exitList=("" direct)
    if [[ "${mode}" == "multi_chain" ]]; then
        mapfile -t -O 2 exitList < <(jq -r '.chains[]?.name' <<<"${state}")
    else
        exitList+=(chain_outbound)
    fi
    echoContent yellow "\n$(t CHAIN_ACCOUNT_PICK_EXIT "${name}")"
    echoContent yellow "  1. $(t CHAIN_ACCOUNT_FOLLOW_DEFAULT)"
    for i in "${!exitList[@]}"; do
        ((i == 0)) && continue
        echoContent yellow "  $((i + 1)). $(chainAccountExitLabel "${exitList[$i]}")"
    done
    read -r -p "$(t PROMPT_SELECT):" exitPick
    if [[ ! "${exitPick}" =~ ^[1-9][0-9]*$ ]] || ((exitPick > ${#exitList[@]})); then
        echoContent red " ---> $(t INVALID_SELECTION)"
        return 1
    fi
    target=${exitList[$((exitPick - 1))]}
    if [[ -z "${target}" ]]; then
        new=$(jq -c --arg n "${name}" 'del(.accounts[$n])' <<<"${state}") || return 1
    else
        new=$(jq -c --arg n "${name}" --arg v "${target}" '.accounts[$n] = $v' <<<"${state}") || return 1
    fi
    if ! new=$(chainAccountAssignPorts "${new}"); then
        echoContent red " ---> $(t CHAIN_ACCOUNT_NO_BRIDGE_PORT "${CHAIN_BRIDGE_PORT}" "${CHAIN_BRIDGE_PORT_LAST}")"
        return 1
    fi
    chainAccountSave "${file}" "${new}" "${state}" || return 1
    echoContent green " ---> $(t CHAIN_ACCOUNT_SAVED "${name}" "$(if [[ -n "${target}" ]]; then chainAccountExitLabel "${target}"; else t CHAIN_ACCOUNT_FOLLOW_DEFAULT; fi)")"
}

# 配置入口节点 - 多跳模式
# 使用全局变量 chainHops (由 parseChainCode 设置)
setupChainEntryMultiHop() {
    local chainBridgePort=${CHAIN_BRIDGE_PORT}

    # 多链路状态在的时候写单链路会留下两套入口状态，与多链路那边拒绝单链路对称
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        echoContent yellow "$(t CHAIN_MULTI_EXISTS)"
        echoContent yellow "$(t CHAIN_MULTI_UNINSTALL_HINT)"
        echoContent yellow "$(t CHAIN_MENU_PATH)"
        return 1
    fi

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理配置
    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if ! isYesInput "${confirmOverwrite}"; then
            return 0
        fi
    fi

    echoContent yellow "\n正在配置入口节点 (多跳模式, ${chainHopCount}跳)..."

    # 检测是否有 Xray 代理协议在运行
    local hasXrayProtocols=false
    # 扫描 xray/conf 下所有已注册代理协议(含 WS/XHTTP/HTTPUpgrade 等，见 lib/protocol-registry.sh)；
    # 仅查 02/07/04 会漏掉 XHTTP 等 → hasXrayProtocols=false → 不建桥接/不改路由 → 链路静默失效
    local _xrayProtos; _xrayProtos=$(scanInstalledProtocols "${XRAY_CONF_DIR}/")
    if [[ -n "${_xrayProtos//,/}" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> 检测到 Xray 代理协议，将同时配置 Xray 链式转发"
    fi

    # ============= sing-box 配置 =============

    local chainOutboundJson
    if ! chainOutboundJson=$(chainHopOutbounds "${chainHops}") || [[ -z "${chainOutboundJson}" ]]; then
        echoContent red " ---> 链式出站配置生成失败"
        return 1
    fi
    printf '%s\n' "${chainOutboundJson}" > ${SINGBOX_FRAGMENT_DIR}/chain_outbound.json

    if [[ "${hasXrayProtocols}" == "true" ]]; then
        writeChainBridgeInbound "${chainBridgePort}"
    fi
    writeChainEntryRoute "${hasXrayProtocols}"

    # 保存配置信息（原子写入）
    local __chainEntryInfo
    __chainEntryInfo=$(cat <<EOF
{
    "schema_version": 1,
    "role": "entry",
    "mode": "multi_hop",
    "hop_count": ${chainHopCount},
    "hops": ${chainHops},
    "bridge_port": ${chainBridgePort},
    "has_xray": ${hasXrayProtocols}
}
EOF
)
    __chainEntryInfo=$(chainAccountCarry "${__chainEntryInfo}") || return 1
    writeChainInfoAtomic "${CHAIN_ENTRY_INFO}" "${__chainEntryInfo}" || return 1

    # 合并 sing-box 配置（统一走 singBoxMergeConfig，错误会带上 sing-box 实际报错前 20 行）
    if ! singBoxMergeConfig; then
        return 1
    fi

    # 启动 sing-box
    echoContent yellow "正在启动 sing-box..."
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证 sing-box 启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: ${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"
        return 1
    fi
    echoContent green " ---> sing-box 启动成功"

    # ============= Xray 配置 (如果存在) =============
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "正在配置 Xray 链式转发..."
        writeXrayChainConfig "${chainBridgePort}" || return 1

        # 重启 Xray
        echoContent yellow "正在重启 Xray..."
        handleXray stop >/dev/null 2>&1
        handleXray start

        sleep 1
        if xrayDaemonRunning; then
            echoContent green " ---> Xray 重启成功，链式转发已启用"
        else
            echoContent red " ---> Xray 重启失败"
            echoContent yellow "请检查配置: ${XRAY_BIN} run -confdir ${XRAY_CONF_DIR}"
            return 1
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green "入口节点配置完成！(多跳模式)"
    echoContent green "=============================================================="

    # 显示链路
    echoContent yellow "\n当前链路 (${chainHopCount} 跳):"
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent green "  客户端 → Xray → sing-box"
    else
        echoContent green "  客户端 → sing-box"
    fi

    i=1
    while [[ $i -le ${chainHopCount} ]]; do
        local hopIP hopPort
        hopIP=$(echo "${chainHops}" | jq -r ".[$((i-1))].ip")
        hopPort=$(echo "${chainHops}" | jq -r ".[$((i-1))].port")
        if [[ $i -eq ${chainHopCount} ]]; then
            echoContent green "           → 出口(${hopIP}:${hopPort}) → 互联网"
        else
            echoContent green "           → 中继${i}(${hopIP}:${hopPort})"
        fi
        ((i++))
    done

    # 自动测试连通性
    echoContent yellow "\n正在测试链路连通性..."
    sleep 2
    testChainConnection
}

# 配置入口节点 (单跳模式，向后兼容)
setupChainEntry() {
    local exitIP=$1
    local exitPort=$2
    local exitKey=$3
    local exitMethod=$4
    local chainBridgePort=${CHAIN_BRIDGE_PORT}

    # 多链路状态在的时候写单链路会留下两套入口状态，与多链路那边拒绝单链路对称
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        echoContent yellow "$(t CHAIN_MULTI_EXISTS)"
        echoContent yellow "$(t CHAIN_MULTI_UNINSTALL_HINT)"
        echoContent yellow "$(t CHAIN_MENU_PATH)"
        return 1
    fi

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 检查是否已存在链式代理出站
    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound.json" ]]; then
        echoContent yellow "\n检测到已存在链式代理配置"
        read -r -p "是否覆盖现有配置？[y/n]:" confirmOverwrite
        if ! isYesInput "${confirmOverwrite}"; then
            return 0
        fi
    fi

    echoContent yellow "\n正在配置入口节点..."

    # 检测是否有 Xray 代理协议在运行
    local hasXrayProtocols=false
    # 扫描 xray/conf 下所有已注册代理协议(含 WS/XHTTP/HTTPUpgrade 等，见 lib/protocol-registry.sh)；
    # 仅查 02/07/04 会漏掉 XHTTP 等 → hasXrayProtocols=false → 不建桥接/不改路由 → 链路静默失效
    local _xrayProtos; _xrayProtos=$(scanInstalledProtocols "${XRAY_CONF_DIR}/")
    if [[ -n "${_xrayProtos//,/}" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> 检测到 Xray 代理协议，将同时配置 Xray 链式转发"
    fi

    # ============= sing-box 配置 =============

    # 创建 Shadowsocks 出站 (到出口节点)
    # exitIP / exitMethod / exitKey 来自 parseChainCode（V1 用正则切片）或用户手输（setupChainEntryManual），
    # 字段里若含 " 或 \ 会破坏 heredoc JSON；走 jq -n + --arg 让 jq 自己 escape。
    local _chainOutboundJson
    if ! _chainOutboundJson=$(jq -n \
            --arg server "${exitIP}" \
            --argjson port "${exitPort}" \
            --arg method "${exitMethod}" \
            --arg password "${exitKey}" \
            '{
                outbounds: [{
                    type: "shadowsocks",
                    tag: "chain_outbound",
                    server: $server,
                    server_port: $port,
                    method: $method,
                    password: $password,
                    multiplex: {
                        enabled: true,
                        protocol: "h2mux",
                        max_connections: 4,
                        min_streams: 4
                    }
                }]
            }') || [[ -z "${_chainOutboundJson}" ]]; then
        echoContent red " ---> 链式出站配置生成失败"
        return 1
    fi
    printf '%s\n' "${_chainOutboundJson}" > ${SINGBOX_FRAGMENT_DIR}/chain_outbound.json

    if [[ "${hasXrayProtocols}" == "true" ]]; then
        writeChainBridgeInbound "${chainBridgePort}"
    fi
    writeChainEntryRoute "${hasXrayProtocols}"

    # 保存配置信息（原子写入）
    local __chainEntryInfo
    __chainEntryInfo=$(cat <<EOF
{
    "schema_version": 1,
    "role": "entry",
    "exit_ip": "${exitIP}",
    "exit_port": ${exitPort},
    "method": "${exitMethod}",
    "password": "${exitKey}",
    "bridge_port": ${chainBridgePort},
    "has_xray": ${hasXrayProtocols}
}
EOF
)
    __chainEntryInfo=$(chainAccountCarry "${__chainEntryInfo}") || return 1
    writeChainInfoAtomic "${CHAIN_ENTRY_INFO}" "${__chainEntryInfo}" || return 1

    # 合并 sing-box 配置（统一走 singBoxMergeConfig，错误会带上 sing-box 实际报错前 20 行）
    if ! singBoxMergeConfig; then
        return 1
    fi

    # 启动 sing-box
    echoContent yellow "正在启动 sing-box..."
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证 sing-box 启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> sing-box 启动失败"
        echoContent yellow "请手动执行: ${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"
        return 1
    fi
    echoContent green " ---> sing-box 启动成功"

    # ============= Xray 配置 (如果存在) =============
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "正在配置 Xray 链式转发..."
        writeXrayChainConfig "${chainBridgePort}" || return 1

        # 重启 Xray
        echoContent yellow "正在重启 Xray..."
        handleXray stop >/dev/null 2>&1
        handleXray start

        sleep 1
        if xrayDaemonRunning; then
            echoContent green " ---> Xray 重启成功，链式转发已启用"
        else
            echoContent red " ---> Xray 重启失败"
            echoContent yellow "请检查配置: ${XRAY_BIN} run -confdir ${XRAY_CONF_DIR}"
            return 1
        fi
    fi

    echoContent green "\n=============================================================="
    echoContent green "入口节点配置完成！"
    echoContent green "=============================================================="
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        echoContent yellow "流量路径: 客户端 → Xray → sing-box → 出口节点"
    else
        echoContent yellow "流量路径: 客户端 → sing-box → 出口节点"
    fi

    # 自动测试连通性
    echoContent yellow "\n正在测试链路连通性..."
    sleep 2
    testChainConnection
}

# 查看链路状态
showChainStatus() {
    echoContent skyBlue "\n链式代理状态"
    echoContent red "\n=============================================================="

    # 检查是否为多链路模式
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        showMultiChainStatus
        return $?
    fi

    local role="未配置"
    local exitIP=""
    local exitPort=""
    local status="❌ 未配置"

    # 检查是否为出口节点
    if [[ -f "${CHAIN_EXIT_INFO}" ]]; then
        role="出口节点 (Exit)"
        local ip port
        ip=$(jq -r '.ip' ${CHAIN_EXIT_INFO})
        port=$(jq -r '.port' ${CHAIN_EXIT_INFO})
        local allowedIP
        allowedIP=$(jq -r '.allowed_ip' ${CHAIN_EXIT_INFO})

        # 检查 sing-box 是否运行
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ 运行中"
        else
            status="❌ 未运行"
        fi

        echoContent green "╔══════════════════════════════════════════════════════════════╗"
        echoContent green "║                      链式代理状态                              ║"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  当前角色: ${role}"
        echoContent yellow "  监听端口: ${port}"
        echoContent yellow "  本机IP: ${ip}"
        echoContent yellow "  允许连接: ${allowedIP:-所有IP}"
        echoContent yellow "  运行状态: ${status}"
        echoContent green "╚══════════════════════════════════════════════════════════════╝"

        # 显示配置码
        showExistingChainCode

    # 检查是否为中继节点
    elif [[ -f "${CHAIN_RELAY_INFO}" ]]; then
        role="中继节点 (Relay)"
        local ip port totalHops
        ip=$(jq -r '.ip' ${CHAIN_RELAY_INFO})
        port=$(jq -r '.port' ${CHAIN_RELAY_INFO})
        totalHops=$(jq -r '.total_hops' ${CHAIN_RELAY_INFO})
        local downstreamHops
        downstreamHops=$(jq -r '.downstream_hops' ${CHAIN_RELAY_INFO})

        # 检查 sing-box 是否运行
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ 运行中"
        else
            status="❌ 未运行"
        fi

        echoContent green "╔══════════════════════════════════════════════════════════════╗"
        echoContent green "║                      链式代理状态                              ║"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  当前角色: ${role}"
        echoContent yellow "  监听端口: ${port}"
        echoContent yellow "  本机IP: ${ip}"
        echoContent yellow "  链路总跳数: ${totalHops}"
        echoContent yellow "  运行状态: ${status}"
        echoContent green "╠══════════════════════════════════════════════════════════════╣"
        echoContent yellow "  下游链路:"

        local i=0
        local hopCount
        hopCount=$(echo "${downstreamHops}" | jq 'length')
        while [[ $i -lt ${hopCount} ]]; do
            local hopIP hopPort
            hopIP=$(echo "${downstreamHops}" | jq -r ".[$i].ip")
            hopPort=$(echo "${downstreamHops}" | jq -r ".[$i].port")
            if [[ $i -eq $((hopCount - 1)) ]]; then
                echoContent yellow "    → 出口(${hopIP}:${hopPort}) → 互联网"
            else
                echoContent yellow "    → 中继$((i+1))(${hopIP}:${hopPort})"
            fi
            ((i++))
        done
        echoContent green "╚══════════════════════════════════════════════════════════════╝"

        # 显示配置码
        showRelayChainCode

    # 检查是否为入口节点
    elif [[ -f "${CHAIN_ENTRY_INFO}" ]]; then
        local mode
        mode=$(jq -r '.mode // "single_hop"' ${CHAIN_ENTRY_INFO})

        # 检查 sing-box 是否运行
        if pgrep -x "sing-box" >/dev/null 2>&1; then
            status="✅ 运行中"
        else
            status="❌ 未运行"
        fi

        if [[ "${mode}" == "multi_hop" ]]; then
            role="入口节点 (Entry) - 多跳模式"
            local hopCount hops
            hopCount=$(jq -r '.hop_count' ${CHAIN_ENTRY_INFO})
            hops=$(jq -r '.hops' ${CHAIN_ENTRY_INFO})

            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      链式代理状态                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  当前角色: ${role}"
            echoContent yellow "  链路跳数: ${hopCount}"
            echoContent yellow "  运行状态: ${status}"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  链路详情:"

            local i=0
            while [[ $i -lt ${hopCount} ]]; do
                local hopIP hopPort
                hopIP=$(echo "${hops}" | jq -r ".[$i].ip")
                hopPort=$(echo "${hops}" | jq -r ".[$i].port")
                if [[ $i -eq $((hopCount - 1)) ]]; then
                    echoContent yellow "    → 出口(${hopIP}:${hopPort}) → 互联网"
                else
                    echoContent yellow "    → 中继$((i+1))(${hopIP}:${hopPort})"
                fi
                ((i++))
            done
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        elif [[ "${mode}" == "external_single" ]]; then
            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      链式代理状态                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  当前角色: 入口节点 (Entry)"
            echoContent yellow "  $(t EXT_SINGLE_EXIT_STATUS "$(jq -r '.external_node_name' "${CHAIN_ENTRY_INFO}")")"
            echoContent yellow "  运行状态: ${status}"
            chainExternalSingleOnXray && echoContent red "  $(t EXT_SINGLE_EXIT_XRAY_WARNING)"
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        else
            role="入口节点 (Entry)"
            exitIP=$(jq -r '.exit_ip' ${CHAIN_ENTRY_INFO})
            exitPort=$(jq -r '.exit_port' ${CHAIN_ENTRY_INFO})

            echoContent green "╔══════════════════════════════════════════════════════════════╗"
            echoContent green "║                      链式代理状态                              ║"
            echoContent green "╠══════════════════════════════════════════════════════════════╣"
            echoContent yellow "  当前角色: ${role}"
            echoContent yellow "  出口地址: ${exitIP}:${exitPort}"
            echoContent yellow "  运行状态: ${status}"
            echoContent green "╚══════════════════════════════════════════════════════════════╝"
        fi

    else
        echoContent yellow "未配置链式代理"
        echoContent yellow "请使用 '快速配置向导' 进行配置"
    fi
}

# 显示中继节点配置码
showRelayChainCode() {
    if [[ ! -f "${CHAIN_RELAY_INFO}" ]]; then
        echoContent red " ---> 未找到中继节点配置信息"
        return 1
    fi

    local publicIP port method password downstreamHops
    publicIP=$(jq -r '.ip' ${CHAIN_RELAY_INFO})
    port=$(jq -r '.port' ${CHAIN_RELAY_INFO})
    method=$(jq -r '.method' ${CHAIN_RELAY_INFO})
    password=$(jq -r '.password' ${CHAIN_RELAY_INFO})
    downstreamHops=$(jq -r '.downstream_hops' ${CHAIN_RELAY_INFO})

    # 构建新的 hops 数组 (本机 + 下游所有节点)
    local newHops
    newHops=$(jq -n --arg ip "${publicIP}" --argjson port "${port}" \
        --arg key "${password}" --arg method "${method}" \
        --argjson downstream "${downstreamHops}" \
        '[{ip: $ip, port: $port, key: $key, method: $method}] + $downstream')

    local chainCode
    chainCode="chain://v2@$(echo -n "${newHops}" | base64 | tr -d '\n')"

    echoContent yellow "\n配置码 (供上游入口或中继节点使用):\n"
    echoContent skyBlue "${chainCode}"
}

# 测试链路连通性
testChainConnection() {
    # 检测多链路模式，使用专用测试函数
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        testMultiChainConnection
        return $?
    fi

    echoContent skyBlue "\n测试链路连通性"
    echoContent red "\n=============================================================="

    # 确定节点角色并获取首跳信息
    local firstHopIP=""
    local firstHopPort=""
    local role=""

    if [[ -f "${CHAIN_ENTRY_INFO}" ]]; then
        role="entry"
        local mode
        mode=$(jq -r '.mode // "single_hop"' ${CHAIN_ENTRY_INFO})

        if [[ "${mode}" == "multi_hop" ]]; then
            # 多跳模式，获取第一跳
            firstHopIP=$(jq -r '.hops[0].ip' ${CHAIN_ENTRY_INFO})
            firstHopPort=$(jq -r '.hops[0].port' ${CHAIN_ENTRY_INFO})
        elif [[ "${mode}" == "external_single" ]]; then
            # 外部节点当唯一出口：状态里只有节点 id，地址在节点列表里
            local externalNode
            externalNode=$(getExternalNodeById "$(jq -r '.external_node_id // empty' ${CHAIN_ENTRY_INFO})")
            firstHopIP=$(jq -r '.server // empty' <<<"${externalNode}" 2>/dev/null)
            firstHopPort=$(jq -r '.server_port // empty' <<<"${externalNode}" 2>/dev/null)
            if [[ -z "${firstHopIP}" || -z "${firstHopPort}" ]]; then
                echoContent red " ---> $(t EXT_NODE_NOT_FOUND)"
                return 1
            fi
        else
            # 单跳模式
            firstHopIP=$(jq -r '.exit_ip' ${CHAIN_ENTRY_INFO})
            firstHopPort=$(jq -r '.exit_port' ${CHAIN_ENTRY_INFO})
        fi

    elif [[ -f "${CHAIN_RELAY_INFO}" ]]; then
        role="relay"
        # 中继节点获取下游第一跳
        firstHopIP=$(jq -r '.downstream_hops[0].ip' ${CHAIN_RELAY_INFO})
        firstHopPort=$(jq -r '.downstream_hops[0].port' ${CHAIN_RELAY_INFO})

    elif [[ -f "${CHAIN_EXIT_INFO}" ]]; then
        role="exit"
        echoContent yellow "当前为出口节点，无需测试链路"
        echoContent yellow "请在入口节点测试连通性"

        # 测试出口节点自身网络
        echoContent yellow "\n测试出口节点网络..."
        local testIP
        testIP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null)
        if [[ -n "${testIP}" ]]; then
            echoContent green "✅ 出口节点网络正常"
            echoContent green "   出口IP: ${testIP}"
        else
            echoContent red "❌ 出口节点网络异常"
        fi
        return 0
    else
        echoContent red " ---> 未配置链式代理"
        return 1
    fi

    echoContent yellow "首跳节点: ${firstHopIP}:${firstHopPort}\n"

    # 测试1: TCP端口连通性 (到第一跳)
    echoContent yellow "测试1: TCP端口连通性..."
    if _chainTCPProbe "${firstHopIP}" "${firstHopPort}" 5; then
        echoContent green "  ✅ TCP端口连通 (${firstHopIP}:${firstHopPort})"
    else
        echoContent red "  ❌ TCP端口不通"
        echoContent red "  请检查:"
        echoContent red "  1. 目标节点防火墙是否开放端口 ${firstHopPort}"
        echoContent red "  2. 目标节点 sing-box 是否运行"
        echoContent red "  3. IP地址是否正确"
        return 1
    fi

    # 测试2 走链路访问外网：必须经 sing-box 出口，直 curl 量到的是本机直连出口会假阳性。
    # entry+Xray 走本机 SOCKS5 桥接口；entry 无 Xray 与 relay 都无法在本机端到端测。
    echoContent yellow "测试2: 链路转发测试..."

    # 检查 sing-box 是否运行
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red "  ❌ sing-box 未运行"
        return 1
    fi

    local viaProxy=()
    if [[ "${role}" == "entry" ]]; then
        local hasXray bridgePort
        hasXray=$(jq -r '.has_xray // false' ${CHAIN_ENTRY_INFO} 2>/dev/null)
        bridgePort=$(jq -r '.bridge_port // empty' ${CHAIN_ENTRY_INFO} 2>/dev/null)
        if [[ "${hasXray}" == "true" && -n "${bridgePort}" ]]; then
            viaProxy=(--socks5 "127.0.0.1:${bridgePort}")
        fi
    fi

    if [[ ${#viaProxy[@]} -gt 0 ]]; then
        sleep 1
        local outIP
        outIP=$(curl -s --connect-timeout 10 "${viaProxy[@]}" https://api.ipify.org 2>/dev/null)

        if [[ -n "${outIP}" ]]; then
            echoContent green "  ✅ 链路转发正常"
            echoContent green "  出口IP: ${outIP}"

            # 测试延迟（同样走链路，否则量到的是直连延迟）
            local startTime endTime latency
            startTime=$(date +%s%N)
            curl -s --connect-timeout 5 "${viaProxy[@]}" https://www.google.com >/dev/null 2>&1
            endTime=$(date +%s%N)
            latency=$(( (endTime - startTime) / 1000000 ))
            echoContent green "  延迟: ${latency}ms"
        else
            echoContent red "  ❌ 链路转发失败"
            echoContent red "  请检查各节点配置和网络"
            return 1
        fi

        echoContent green "\n=============================================================="
        echoContent green "链路测试通过！"
        echoContent green "=============================================================="
    else
        echoContent yellow "  ⚠️  本节点未启用 Xray 桥接（或为中继角色），脚本无法从本机直接发起经链测试"
        echoContent yellow "     首跳 TCP 已可达；端到端连通性请在客户端连接入口节点后验证"

        echoContent green "\n=============================================================="
        echoContent green "链路基础测试完成（端到端测试需客户端验证）"
        echoContent green "=============================================================="
    fi
}

# 高级设置
chainProxyAdvanced() {
    # 检查是否为多链路模式
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        multiChainAdvancedMenu
        return $?
    fi

    echoContent skyBlue "\n链式代理高级设置"
    echoContent red "\n=============================================================="

    echoContent yellow "1.显示配置码 (出口/中继节点)"
    echoContent yellow "2.更新密钥"
    echoContent yellow "3.修改端口"
    echoContent yellow "4.查看详细配置"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        if [[ -f "${CHAIN_EXIT_INFO}" ]]; then
            showExistingChainCode
        elif [[ -f "${CHAIN_RELAY_INFO}" ]]; then
            showRelayChainCode
        else
            echoContent red " ---> 当前不是出口或中继节点"
        fi
        ;;
    2)
        updateChainKey
        ;;
    3)
        updateChainPort
        ;;
    4)
        showChainDetailConfig
        ;;
    esac
}

# 更新密钥
updateChainKey() {
    echoContent yellow "\n更新链式代理密钥"

    if [[ -f "${CHAIN_EXIT_INFO}" ]]; then
        # 出口节点：旧密钥一换就失效，接在上面的入口立刻断，先问
        local answer
        echoContent yellow " ---> $(t CHAIN_KEY_UPDATE_WARN)"
        read -r -p "$(t CHAIN_KEY_UPDATE_CONFIRM)" answer
        if ! isYesInput "${answer}"; then
            echoContent yellow " ---> $(t CANCELLED)"
            return 0
        fi
        local port method
        port=$(jq -r '.port' ${CHAIN_EXIT_INFO})
        method=$(jq -r '.method' ${CHAIN_EXIT_INFO})
        local publicIP
        publicIP=$(jq -r '.ip' ${CHAIN_EXIT_INFO})

        # 生成新密钥
        local newKey
        newKey=$(generateChainKey)

        # 更新入站配置 - 使用安全的临时文件（校验 jq 成功且产物是合法 JSON 再 mv，避免半写入）
        local tmpInboundFile
        tmpInboundFile=$(mktemp) || return 1
        chmod 600 "${tmpInboundFile}"
        if ! jq --arg key "${newKey}" '.inbounds[0].password = $key' \
                ${SINGBOX_FRAGMENT_DIR}/chain_inbound.json > "${tmpInboundFile}" 2>/dev/null \
            || ! jq -e . "${tmpInboundFile}" >/dev/null 2>&1; then
            rm -f "${tmpInboundFile}"
            echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${SINGBOX_FRAGMENT_DIR}/chain_inbound.json")"
            return 1
        fi
        mv "${tmpInboundFile}" ${SINGBOX_FRAGMENT_DIR}/chain_inbound.json

        # 更新信息文件 - 使用安全的临时文件（同上校验）
        local tmpInfoFile
        tmpInfoFile=$(mktemp) || return 1
        chmod 600 "${tmpInfoFile}"
        if ! jq --arg key "${newKey}" '.password = $key' \
                ${CHAIN_EXIT_INFO} > "${tmpInfoFile}" 2>/dev/null \
            || ! jq -e . "${tmpInfoFile}" >/dev/null 2>&1; then
            rm -f "${tmpInfoFile}"
            echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${CHAIN_EXIT_INFO}")"
            return 1
        fi
        mv "${tmpInfoFile}" ${CHAIN_EXIT_INFO}

        if ! singBoxMergeConfig; then
            return 1
        fi
        reloadCore

        echoContent green " ---> 密钥已更新"
        echoContent yellow "\n新配置码:\n"
        local chainCode hostInCode="${publicIP}"
        if [[ "${publicIP}" == *:* ]]; then
            hostInCode="[${publicIP}]"
        fi
        chainCode="chain://ss2022@${hostInCode}:${port}?key=$(echo -n "${newKey}" | base64 | tr -d '\n')&method=${method}"
        echoContent skyBlue "${chainCode}"
        echoContent yellow "\n请更新入口节点配置！"

    elif [[ -f "${CHAIN_RELAY_INFO}" ]]; then
        echoContent yellow " ---> $(t CHAIN_KEY_UPDATE_RELAY)"
    elif [[ -f "${CHAIN_ENTRY_INFO}" ]]; then
        echoContent red " ---> 入口节点请从出口节点获取新配置码后重新配置"
    else
        echoContent red " ---> 未配置链式代理"
    fi
}

# 更新端口
updateChainPort() {
    echoContent yellow "\n更新链式代理端口"

    local infoFile=""
    if [[ -f "${CHAIN_EXIT_INFO}" ]]; then
        infoFile="${CHAIN_EXIT_INFO}"
    elif [[ -f "${CHAIN_RELAY_INFO}" ]]; then
        infoFile="${CHAIN_RELAY_INFO}"
    else
        echoContent red " ---> 仅出口或中继节点可修改端口"
        return 1
    fi

    local oldPort
    oldPort=$(jq -r '.port' "${infoFile}")

    read -r -p "新端口 [当前: ${oldPort}]:" newPort
    if [[ -z "${newPort}" ]]; then
        return 0
    fi

    if [[ ! "${newPort}" =~ ^[0-9]+$ ]] || [[ "${newPort}" -lt 1 ]] || [[ "${newPort}" -gt 65535 ]]; then
        echoContent red " ---> 端口格式错误"
        return 1
    fi

    # 更新入站配置 - 使用安全的临时文件（校验 jq 成功且产物是合法 JSON 再 mv）
    local tmpInboundFile
    tmpInboundFile=$(mktemp) || return 1
    chmod 600 "${tmpInboundFile}"
    if ! jq --argjson port "${newPort}" '.inbounds[0].listen_port = $port' \
            ${SINGBOX_FRAGMENT_DIR}/chain_inbound.json > "${tmpInboundFile}" 2>/dev/null \
        || ! jq -e . "${tmpInboundFile}" >/dev/null 2>&1; then
        rm -f "${tmpInboundFile}"
        echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${SINGBOX_FRAGMENT_DIR}/chain_inbound.json")"
        return 1
    fi
    mv "${tmpInboundFile}" ${SINGBOX_FRAGMENT_DIR}/chain_inbound.json

    # 更新信息文件 - 使用安全的临时文件（同上校验）
    local tmpInfoFile
    tmpInfoFile=$(mktemp) || return 1
    chmod 600 "${tmpInfoFile}"
    if ! jq --argjson port "${newPort}" '.port = $port' \
            "${infoFile}" > "${tmpInfoFile}" 2>/dev/null \
        || ! jq -e . "${tmpInfoFile}" >/dev/null 2>&1; then
        rm -f "${tmpInfoFile}"
        echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${infoFile}")"
        return 1
    fi
    mv "${tmpInfoFile}" "${infoFile}"

    # 更新防火墙
    allowPort "${newPort}" "tcp"

    if ! singBoxMergeConfig; then
        return 1
    fi
    reloadCore

    echoContent green " ---> 端口已更新为 ${newPort}"

    # 显示相应的配置码
    if [[ "${infoFile}" == *"exit"* ]]; then
        showExistingChainCode
    else
        showRelayChainCode
    fi
    echoContent yellow "\n请更新上游节点配置！"
}

# 显示详细配置
showChainDetailConfig() {
    echoContent skyBlue "\n链式代理详细配置"
    echoContent red "\n=============================================================="

    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_inbound.json" ]]; then
        echoContent yellow "\n入站配置 (chain_inbound.json):"
        jq . ${SINGBOX_FRAGMENT_DIR}/chain_inbound.json
    fi

    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound.json" ]]; then
        echoContent yellow "\n出站配置 (chain_outbound.json):"
        jq . ${SINGBOX_FRAGMENT_DIR}/chain_outbound.json
    fi

    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_route.json" ]]; then
        echoContent yellow "\n路由配置 (chain_route.json):"
        jq . ${SINGBOX_FRAGMENT_DIR}/chain_route.json
    fi
}

# 卸载链式代理
removeChainProxy() {
    echoContent skyBlue "\n卸载链式代理"
    echoContent red "\n=============================================================="

    # 检测链式代理模式
    local isMultiChain=false
    local isSingleChain=false

    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        isMultiChain=true
        local chainCount
        chainCount=$(jq -r '.chains | length' ${CHAIN_MULTI_INFO} 2>/dev/null || echo "0")
        echoContent yellow "\n检测到多链路分流模式，共 ${chainCount} 条链路"
    elif [[ -f "${CHAIN_RELAY_INFO}" ]]; then
        isSingleChain=true
        echoContent yellow "\n$(t CHAIN_REMOVE_ROLE_RELAY)"
    elif [[ -f "${CHAIN_EXIT_INFO}" ]]; then
        isSingleChain=true
        echoContent yellow "\n$(t CHAIN_REMOVE_ROLE_EXIT)"
    elif [[ -f "${CHAIN_ENTRY_INFO}" ]]; then
        isSingleChain=true
        echoContent yellow "\n检测到单链路模式"
    else
        echoContent red "\n未检测到链式代理配置"
        return 0
    fi

    read -r -p "确认卸载链式代理？[y/n]:" confirmRemove
    if ! isYesInput "${confirmRemove}"; then
        return 0
    fi

    # 删除 sing-box 配置文件 - 单链路模式
    rm -f ${SINGBOX_FRAGMENT_DIR}/chain_inbound.json
    rm -f ${SINGBOX_FRAGMENT_DIR}/chain_outbound.json
    rm -f ${SINGBOX_FRAGMENT_DIR}/chain_route.json
    rm -f ${SINGBOX_FRAGMENT_DIR}/chain_bridge_inbound.json
    rm -f ${CHAIN_EXIT_INFO}
    rm -f ${CHAIN_ENTRY_INFO}
    rm -f ${CHAIN_RELAY_INFO}

    # 删除外部节点单链路配置（兼容旧配置）
    rm -f ${SINGBOX_FRAGMENT_DIR}/external_outbound.json
    rm -f ${SINGBOX_FRAGMENT_DIR}/external_route.json
    rm -f ${SINGBOX_CONF_DIR}/external_entry_info.json

    # 01_direct_outbound.json 不能删（共享基础出站），但旧 chain 装的 domain_strategy 会让
    # 1.14 启动 FATAL——调 ensureDirectOutbound 重写为最小形态，剥掉 legacy 字段。
    if [[ -f "${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json" ]] && declare -F ensureDirectOutbound >/dev/null 2>&1; then
        ensureDirectOutbound
    fi

    # 01_dns.json 是 chain 路由的 default_domain_resolver 依赖（grep 全文只有 chain 代码引用），
    # 非 chain 配置不需要。删除避免残留；下次安装 chain 时 ensureSingBoxInstalled 会重建。
    rm -f ${SINGBOX_FRAGMENT_DIR}/01_dns.json

    # 删除 sing-box 配置文件 - 多链路模式
    if [[ "${isMultiChain}" == "true" ]]; then
        # 删除所有链路出站配置文件
        rm -f ${SINGBOX_FRAGMENT_DIR}/chain_outbound_*.json 2>/dev/null
        # 删除多链路路由配置
        rm -f ${SINGBOX_FRAGMENT_DIR}/chain_multi_route.json 2>/dev/null
        # 删除多链路信息文件
        rm -f ${CHAIN_MULTI_INFO}
        echoContent yellow " ---> 已删除多链路分流配置"
    fi

    # 删除 Xray 链式代理配置
    if [[ -f "${XRAY_CONF_DIR}/chain_outbound.json" ]]; then
        rm -f ${XRAY_CONF_DIR}/chain_outbound.json
        echoContent yellow " ---> 已删除 Xray 链式出站配置"

        # 恢复原路由配置
        if [[ -f "${XRAY_CONF_DIR}/09_routing.json.bak.chain" ]]; then
            mv ${XRAY_CONF_DIR}/09_routing.json.bak.chain ${XRAY_CONF_DIR}/09_routing.json
            echoContent yellow " ---> 已恢复 Xray 原路由配置"
        else
            # 没有备份：重置成默认路由。直连出站被 WARP / IPv6 全局删掉时不写这条：规则指向不存在的出站，Xray 会直接断连接
            local defaultRules='[]'
            if [[ -f "${XRAY_CONF_DIR}/z_direct_outbound.json" ]]; then
                defaultRules='[{"type":"field","domain":["domain:gstatic.com","domain:googleapis.com","domain:googleapis.cn"],"outboundTag":"z_direct_outbound"}]'
            fi
            jsonWriteFile "${XRAY_CONF_DIR}/09_routing.json" "$(jq -n --argjson rules "${defaultRules}" '{routing: {rules: $rules}}')" false
            echoContent yellow " ---> 已重置 Xray 路由配置为默认"
        fi

        # 重启 Xray
        handleXray stop >/dev/null 2>&1
        handleXray start
    fi

    # 重新合并 sing-box 配置
    # 卸载语义：清理动作已完成（链式相关片段都已 rm），merge 失败说明还有别的片段问题，
    # 但用户的主目标"移除链式代理"已经达到，只警告不 return 1。
    if ! singBoxMergeConfig; then
        echoContent yellow " ---> 警告：sing-box 配置合并失败，请检查其他片段"
    fi
    reloadCore

    echoContent green " ---> 链式代理已卸载"
}

# ======================= 按协议分流功能 =======================

# 生成协议分流路由配置
# 参数: $@ - 要走链式代理的 inbound tag 列表
generateProtocolChainRoute() {
    local selectedTags=("$@")
    local inboundArray
    local routeConfig

    # 构建 JSON 数组
    inboundArray=$(printf '"%s",' "${selectedTags[@]}")
    inboundArray="[${inboundArray%,}]"

    # 检查是否存在 bridge inbound（Xray 桥接）
    local hasBridge=false
    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_bridge_inbound.json" ]]; then
        hasBridge=true
    fi

    if [[ "${hasBridge}" == "true" ]]; then
        # 包含 bridge inbound 的路由配置
        # default_domain_resolver 见 chainExit 注释，1.13 起必填
        routeConfig=$(cat <<EOF
{
    "route": {
        "rules": [
            {
                "inbound": ["chain_bridge_in"],
                "outbound": "chain_outbound"
            },
            {
                "inbound": ${inboundArray},
                "outbound": "chain_outbound"
            }
        ],
        "final": "direct",
        "default_domain_resolver": "google"
    }
}
EOF
)
    else
        # 标准路由配置
        routeConfig=$(cat <<EOF
{
    "route": {
        "rules": [
            {
                "inbound": ${inboundArray},
                "outbound": "chain_outbound"
            }
        ],
        "final": "direct",
        "default_domain_resolver": "google"
    }
}
EOF
)
    fi

    echo "${routeConfig}" | jq . > ${SINGBOX_FRAGMENT_DIR}/chain_route.json
}

# 保存协议分流偏好设置
saveProtocolRoutingPreference() {
    local selection="$1"
    local protocolNames="$2"
    local entryInfo="${CHAIN_ENTRY_INFO}"

    if [[ -f "${entryInfo}" ]]; then
        local updatedInfo
        updatedInfo=$(jq --arg sel "${selection}" --arg names "${protocolNames}" \
            '. + {protocol_routing: {enabled: true, selection: $sel, protocols: $names}}' \
            "${entryInfo}")
        echo "${updatedInfo}" | jq . > "${entryInfo}"
    fi
}

# 按协议分流配置主函数
configureProtocolChainRouting() {
    echoContent skyBlue "\n$(t CHAIN_PROTOCOL_ROUTING_TITLE)"
    echoContent red "\n=============================================================="
    echoContent yellow "$(t CHAIN_PROTOCOL_ROUTING_DESC)"
    echoContent yellow "$(t CHAIN_PROTOCOL_ROUTING_DESC2)\n"

    # 检查是否运行 sing-box 核心
    if [[ ! -f "${SINGBOX_BIN}" ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_SINGBOX_ONLY)"
        return 1
    fi

    # 检查是否为入口节点
    if [[ ! -f "${CHAIN_ENTRY_INFO}" ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_NOT_ENTRY_NODE)"
        return 1
    fi

    # 外部节点唯一出口的出站 tag 不是 chain_outbound，这里写的路由指向不存在的出站，合并必失败
    if [[ "$(jq -r '.mode // empty' "${CHAIN_ENTRY_INFO}" 2>/dev/null)" == "external_single" ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_EXTERNAL_UNSUPPORTED)"
        return 1
    fi

    # 检查链式代理出站是否已配置
    if [[ ! -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound.json" ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_NO_CHAIN_OUTBOUND)"
        return 1
    fi

    # 获取已安装的协议（sing-box）
    local cfgPath="${SINGBOX_FRAGMENT_DIR}/"
    local installedProtocols=""
    local protocolCount=0

    # 扫描 sing-box 配置文件
    for configFile in "${cfgPath}"*_inbounds.json "${cfgPath}"*_inbounds_s.json; do
        [[ ! -f "${configFile}" ]] && continue
        local filename
        filename=$(basename "${configFile}")
        # 跳过链式代理相关的 inbound
        [[ "${filename}" == *chain* ]] && continue

        local protocolId
        protocolId=$(parseProtocolIdFromFileName "${filename}")
        [[ -z "${protocolId}" ]] && continue

        installedProtocols="${installedProtocols}${protocolId}\n"
        ((protocolCount++))
    done

    if [[ ${protocolCount} -eq 0 ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_NO_PROTOCOLS)"
        return 1
    fi

    # 显示已安装的协议列表
    echoContent yellow "$(t CHAIN_PROTOCOL_SELECT_PROMPT)"
    echoContent yellow "--------------------------------------------------------------"

    local idx=1
    local protocolMap=""
    while IFS= read -r protocolId; do
        [[ -z "${protocolId}" ]] && continue
        local displayName
        displayName=$(getProtocolDisplayName "${protocolId}")
        local inboundTag
        inboundTag=$(getProtocolInboundTag "${protocolId}")

        [[ -z "${inboundTag}" ]] && continue

        echoContent yellow "${idx}. ${displayName} [tag: ${inboundTag}]"
        protocolMap="${protocolMap}${idx}:${protocolId}:${inboundTag},"
        ((idx++))
    done <<< "$(echo -e "${installedProtocols}" | sort -n | uniq)"

    local routingEnabled=false
    jq -e '.protocol_routing.enabled == true' "${CHAIN_ENTRY_INFO}" >/dev/null 2>&1 && routingEnabled=true
    [[ "${routingEnabled}" == "true" ]] && echoContent yellow "0. $(t CHAIN_PROTOCOL_DISABLE)"

    echoContent yellow "--------------------------------------------------------------"
    echoContent yellow "$(t CHAIN_PROTOCOL_INPUT_HINT)"

    # 读取用户选择
    local userSelection
    read -r -p "$(t PROMPT_SELECT):" userSelection

    if [[ -z "${userSelection}" ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_NO_SELECTION)"
        return 1
    fi

    if [[ "${userSelection}" == "0" && "${routingEnabled}" == "true" ]]; then
        applyProtocolChainRouting
        return $?
    fi

    # 解析选择并构建 inbound tag 列表
    local selectedTags=()
    local selectedProtocolNames=()
    IFS=',' read -ra selections <<< "${userSelection}"

    for sel in "${selections[@]}"; do
        sel=$(echo "${sel}" | tr -d ' ')
        [[ -z "${sel}" ]] && continue

        # 查找匹配的协议
        local match
        match=$(echo "${protocolMap}" | tr ',' '\n' | grep "^${sel}:" | head -1)
        if [[ -n "${match}" ]]; then
            local protocolId tag displayName
            protocolId=$(echo "${match}" | cut -d':' -f2)
            tag=$(echo "${match}" | cut -d':' -f3)
            displayName=$(getProtocolDisplayName "${protocolId}")
            selectedTags+=("${tag}")
            selectedProtocolNames+=("${displayName}")
        fi
    done

    if [[ ${#selectedTags[@]} -eq 0 ]]; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_INVALID_SELECTION)"
        return 1
    fi

    # 显示已选择的协议
    echoContent green "\n$(t CHAIN_PROTOCOL_SELECTED):"
    for name in "${selectedProtocolNames[@]}"; do
        echoContent yellow "  - ${name}"
    done

    # 确认
    read -r -p "$(t CHAIN_PROTOCOL_CONFIRM) [y/n]:" confirmChoice
    if ! isYesInput "${confirmChoice}"; then
        echoContent yellow " ---> $(t CANCELLED)"
        return 0
    fi

    applyProtocolChainRouting "${userSelection}" "${selectedProtocolNames[*]}" "${selectedTags[@]}"
}

# applyProtocolChainRouting [SELECTION NAMES TAG...] → 按协议分流写进路由并生效；不带参数是关闭，写回所有协议走链路。
# 合并失败要还原：写坏的片段留着，此后每次合并都失败，sing-box 一重启就起不来
applyProtocolChainRouting() {
    local routeFile="${SINGBOX_FRAGMENT_DIR}/chain_route.json" selection=${1:-} names=${2:-}
    if ! jsonTxBegin || ! jsonTxTrack "${routeFile}" || ! jsonTxTrack "${CHAIN_ENTRY_INFO}"; then
        jsonTxRollback
        echoContent red " ---> $(t CHAIN_PROTOCOL_RELOAD_FAILED)"
        return 1
    fi
    if (($# > 2)); then
        shift 2
        generateProtocolChainRoute "$@"
        saveProtocolRoutingPreference "${selection}" "${names}"
    else
        writeChainEntryRoute "$([[ -f "${SINGBOX_FRAGMENT_DIR}/chain_bridge_inbound.json" ]] && echo true || echo false)"
        writeChainInfoAtomic "${CHAIN_ENTRY_INFO}" "$(jq -c 'del(.protocol_routing)' "${CHAIN_ENTRY_INFO}")"
    fi

    echoContent yellow " ---> $(t CHAIN_PROTOCOL_RELOADING)"
    if ! singBoxMergeConfig; then
        jsonTxRollback
        echoContent red " ---> $(t CHAIN_PROTOCOL_RELOAD_FAILED)"
        return 1
    fi
    jsonTxCommit

    if ! reloadCore; then
        echoContent red " ---> $(t CHAIN_PROTOCOL_RELOAD_FAILED)"
        return 1
    fi

    if [[ -n "${selection}" ]]; then
        echoContent green " ---> $(t CHAIN_PROTOCOL_SUCCESS)"
    else
        echoContent green " ---> $(t CHAIN_PROTOCOL_DISABLED)"
    fi
}

# ======================= 多链路分流功能 =======================

# multiChainRuleSetUrl TAG → geosite-* / geoip-* 规则集在 MetaCubeX/meta-rules-dat 的下载地址，写配置与预检都从这里取同一个地址
multiChainRuleSetUrl() {
    case "$1" in
        geosite-*) echo "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/${1#geosite-}.srs" ;;
        geoip-*) echo "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/${1#geoip-}.srs" ;;
        *) return 1 ;;
    esac
}

# multiChainRuleSetsAvailable TAG... → 逐个 HEAD 一遍，404 或连不上都打红返回 1：sing-box 起步时有一个远程规则集下载不到就整个退出
multiChainRuleSetsAvailable() {
    local tag url code
    for tag in "$@"; do
        url=$(multiChainRuleSetUrl "${tag}") || return 1
        code=$(curl -sI -o /dev/null -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null)
        case "${code}" in
            200) ;;
            404)
                echoContent red " ---> $(t CHAIN_RULESET_MISSING "${tag}")"
                return 1
                ;;
            *)
                echoContent red " ---> $(t CHAIN_RULESET_UNREACHABLE "${tag}" "${code:-000}")"
                return 1
                ;;
        esac
    done
}

# 预设规则集定义
# 返回预设规则对应的 geosite 规则集名称
getPresetRulesets() {
    local preset=$1
    case "${preset}" in
        streaming)
            echo "geosite-netflix,geosite-disney,geosite-youtube,geosite-hbo,geosite-hulu,geosite-primevideo"
            ;;
        ai)
            echo "geosite-openai,geosite-bing"
            ;;
        social)
            echo "geosite-telegram,geosite-twitter,geosite-instagram,geosite-facebook"
            ;;
        developer)
            echo "geosite-github,geosite-gitlab,geosite-stackexchange"
            ;;
        gaming)
            echo "geosite-steam,geosite-epicgames"
            ;;
        google)
            echo "geosite-google"
            ;;
        microsoft)
            echo "geosite-microsoft"
            ;;
        apple)
            echo "geosite-apple"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 获取预设规则显示名称
getPresetDisplayName() {
    local preset=$1
    case "${preset}" in
        streaming) echo "流媒体 (Netflix/Disney+/YouTube/...)" ;;
        ai) echo "AI服务 (OpenAI/Bing/...)" ;;
        social) echo "社交媒体 (Telegram/Twitter/...)" ;;
        developer) echo "开发者 (GitHub/GitLab/...)" ;;
        gaming) echo "游戏 (Steam/Epic/...)" ;;
        google) echo "谷歌服务" ;;
        microsoft) echo "微软服务" ;;
        apple) echo "苹果服务" ;;
        *) echo "${preset}" ;;
    esac
}

# 验证链路名称格式（仅允许英文字母、数字、下划线）
validateChainName() {
    local name=$1
    if [[ -z "${name}" ]]; then
        return 1
    fi
    if [[ ! "${name}" =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 1
    fi
    # direct 是直连出站的 tag，也是按账号选出口里「直连」的写法，用作链路名两处都分不清
    if [[ "${name}" == "direct" ]]; then
        return 1
    fi
    # 名称长度限制
    if [[ ${#name} -gt 32 ]]; then
        return 1
    fi
    return 0
}

# 验证 IP CIDR 格式
validateIpCidrs() {
    local input=$1
    IFS=',' read -ra cidrArray <<< "${input}"

    for cidr in "${cidrArray[@]}"; do
        cidr=$(echo "${cidr}" | xargs)  # trim whitespace

        # IPv4 CIDR 格式: x.x.x.x/prefix
        if [[ "${cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            # 验证 IP 部分
            local ip="${cidr%/*}"
            local prefix="${cidr#*/}"

            IFS='.' read -ra octets <<< "${ip}"
            for octet in "${octets[@]}"; do
                if [[ ${octet} -gt 255 ]]; then
                    return 1
                fi
            done

            # 验证前缀长度
            if [[ ${prefix} -gt 32 ]]; then
                return 1
            fi
        # IPv6 CIDR 格式: xxxx:xxxx::/prefix
        elif [[ "${cidr}" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}/[0-9]{1,3}$ ]]; then
            local prefix="${cidr#*/}"
            if [[ ${prefix} -gt 128 ]]; then
                return 1
            fi
        else
            return 1
        fi
    done

    return 0
}

# 生成下一个可用的链路名称
generateNextChainName() {
    local infoFile="${CHAIN_MULTI_INFO}"
    local index=1

    if [[ -f "${infoFile}" ]]; then
        # 找出已有的最大编号
        local existingNames
        existingNames=$(jq -r '.chains[].name' "${infoFile}" 2>/dev/null | grep -E '^chain_[0-9]+$' | sed 's/chain_//' | sort -n | tail -1)
        if [[ -n "${existingNames}" ]]; then
            index=$((existingNames + 1))
        fi
    fi

    echo "chain_${index}"
}

# 检查链路名称是否已存在
isChainNameExists() {
    local name=$1
    local infoFile="${CHAIN_MULTI_INFO}"

    if [[ ! -f "${infoFile}" ]]; then
        return 1
    fi

    if jq -e ".chains[] | select(.name == \"${name}\")" "${infoFile}" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# 多链路入口配置向导
setupMultiChainEntry() {
    local multiChainCarriedAccounts=
    if planAction "$(t PLAN_CHAIN_ENTRY_MULTI)"; then return 0; fi
    echoContent skyBlue "\n$(t CHAIN_MULTI_TITLE)"
    echoContent red "\n=============================================================="
    echoContent yellow "$(t CHAIN_MULTI_DESC)"
    echoContent yellow "$(t CHAIN_MULTI_EXAMPLE)\n"

    # 检查是否已存在单链路配置
    if [[ -f "${CHAIN_ENTRY_INFO}" ]] && \
       [[ ! -f "${CHAIN_MULTI_INFO}" ]]; then
        echoContent yellow "$(t CHAIN_SINGLE_EXISTS)"
        echoContent yellow "$(t CHAIN_SINGLE_UNINSTALL_HINT)"
        echoContent yellow "$(t CHAIN_MENU_PATH)"
        return 1
    fi

    # 检查是否已存在多链路配置
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        echoContent yellow "$(t CHAIN_MULTI_EXISTS)"
        echoContent yellow "1.$(t CHAIN_CONTINUE_ADD_NEW)"
        echoContent yellow "2.$(t CHAIN_RECONFIGURE)"
        echoContent yellow "3.$(t CANCEL)"
        read -r -p "$(t PROMPT_SELECT):" existingChoice

        case "${existingChoice}" in
            1)
                multiChainAddChain
                return $?
                ;;
            2)
                echoContent yellow "$(t CHAIN_CONFIRM_CLEAR)[y/n]"
                read -r -p "$(t CONFIRM):" confirmClear
                if ! isYesInput "${confirmClear}"; then
                    return 0
                fi
                # 账号的出口映射留到新链路都定下来再带回去，见 multiChainRestoreAccounts
                multiChainCarriedAccounts=$(jq -c '.accounts // {}' "${CHAIN_MULTI_INFO}" 2>/dev/null) || multiChainCarriedAccounts=
                # 清除现有多链路配置
                rm -f ${CHAIN_MULTI_INFO}
                rm -f ${SINGBOX_FRAGMENT_DIR}/chain_outbound_*.json
                rm -f ${SINGBOX_FRAGMENT_DIR}/chain_route.json
                rm -f ${SINGBOX_FRAGMENT_DIR}/chain_ruleset.json
                rm -f ${SINGBOX_FRAGMENT_DIR}/chain_bridge_inbound.json
                ;;
            *)
                return 0
                ;;
        esac
    fi

    # 确保 sing-box 已安装
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    echoContent yellow "$(t CHAIN_SELECT_CONFIG_MODE):\n"
    echoContent yellow "1.$(t CHAIN_ADD_INTERACTIVE) [$(t RECOMMENDED)]"
    echoContent yellow "2.$(t CHAIN_BATCH_IMPORT)"
    read -r -p "$(t PROMPT_SELECT):" configMode

    case "${configMode}" in
        1)
            # 逐个添加模式
            setupMultiChainInteractive
            ;;
        2)
            # 批量导入模式
            setupMultiChainBatch
            ;;
        *)
            return 0
            ;;
    esac
}

# 交互式逐个添加链路
setupMultiChainInteractive() {
    local chainCount=0
    local continueAdding="y"

    # 初始化多链路信息文件（原子写入）
    local __chainMultiInit
    __chainMultiInit=$(cat <<'EOF'
{
    "schema_version": 1,
    "role": "entry",
    "mode": "multi_chain",
    "chains": [],
    "rules": [],
    "default_chain": "direct",
    "bridge_port": 31111,
    "has_xray": false
}
EOF
)
    writeChainInfoAtomic "${CHAIN_MULTI_INFO}" "${__chainMultiInit}" || return 1

    while isYesInput "${continueAdding}"; do
        ((chainCount++))
        echoContent skyBlue "\n$(t CHAIN_ADD_NUMBER) #${chainCount}"
        echoContent red "=============================================================="

        # 选择添加方式
        echoContent yellow "$(t CHAIN_ADD_TYPE_SELECT):\n"
        echoContent yellow "1.$(t CHAIN_ADD_BY_CODE)"
        echoContent yellow "2.$(t CHAIN_ADD_BY_EXTERNAL)"
        echoContent yellow "0.$(t CANCEL)"

        read -r -p "$(t PROMPT_SELECT): " addType

        local addResult=1
        case "${addType}" in
            1)
                addSingleChainOutbound
                addResult=$?
                ;;
            2)
                addExternalNodeAsChain
                addResult=$?
                ;;
            0|"")
                ((chainCount--))
                ;;
            *)
                ((chainCount--))
                echoContent yellow " ---> $(t INVALID_SELECTION)"
                ;;
        esac

        if [[ ${addResult} -ne 0 && "${addType}" != "0" && -n "${addType}" ]]; then
            ((chainCount--))
            echoContent yellow "\n$(t CHAIN_ADD_FAILED)"
        fi

        echoContent yellow "\n$(t CHAIN_CONTINUE_ADD)? [y/n]"
        read -r -p "$(t CONTINUE):" continueAdding
    done

    # 检查是否至少添加了一条链路
    local totalChains
    totalChains=$(jq '.chains | length' ${CHAIN_MULTI_INFO})

    if [[ "${totalChains}" -lt 1 ]]; then
        echoContent red "\n ---> $(t CHAIN_NO_CHAINS_ADDED)"
        rm -f ${CHAIN_MULTI_INFO}
        return 1
    fi

    # 完成配置
    finalizeMultiChainConfig
}

# 批量导入配置码
setupMultiChainBatch() {
    echoContent skyBlue "\n$(t CHAIN_BATCH_TITLE)"
    echoContent red "=============================================================="
    echoContent yellow "$(t CHAIN_BATCH_HINT)"
    echoContent yellow "$(t CHAIN_BATCH_END_HINT)\n"

    # 初始化多链路信息文件（原子写入）
    local __chainMultiInit
    __chainMultiInit=$(cat <<'EOF'
{
    "schema_version": 1,
    "role": "entry",
    "mode": "multi_chain",
    "chains": [],
    "rules": [],
    "default_chain": "direct",
    "bridge_port": 31111,
    "has_xray": false
}
EOF
)
    writeChainInfoAtomic "${CHAIN_MULTI_INFO}" "${__chainMultiInit}" || return 1

    local chainIndex=0
    local line

    while true; do
        read -r -p "$(t CHAIN_CODE_PROMPT) #$((chainIndex + 1)): " line

        # 空行结束输入
        if [[ -z "${line}" ]]; then
            break
        fi

        # 解析配置码
        if ! parseChainCode "${line}"; then
            echoContent red " ---> $(t CHAIN_CODE_PARSE_FAILED)"
            continue
        fi

        # 生成链路名称
        local chainName
        chainName=$(generateNextChainName)

        # 添加链路
        if addChainToConfig "${chainName}" "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}" false "${chainHops}"; then
            echoContent green " ---> $(t CHAIN_ADDED): [${chainName}] (${chainExitIP}:${chainExitPort})"
            ((chainIndex++))
        fi
    done

    if [[ ${chainIndex} -lt 1 ]]; then
        echoContent red "\n ---> $(t CHAIN_IMPORT_NONE)"
        rm -f ${CHAIN_MULTI_INFO}
        return 1
    fi

    echoContent green "\n ---> $(t CHAIN_IMPORT_SUCCESS "${chainIndex}")"

    # 配置分流规则
    echoContent yellow "\n$(t CHAIN_CONFIG_RULES_NOW)[y/n]"
    read -r -p "$(t CONFIRM):" configRules

    if isYesInput "${configRules}"; then
        configureMultiChainRules
    fi

    # 完成配置
    finalizeMultiChainConfig
}

# 添加外部节点作为链路
addExternalNodeAsChain() {
    initExternalNodeFile

    local nodeCount
    nodeCount=$(getExternalNodeCount)

    if [[ "${nodeCount}" == "0" ]]; then
        echoContent red "\n ---> $(t EXT_NO_NODES)"
        echoContent yellow "$(t EXT_ADD_NODE_HINT)"
        return 1
    fi

    echoContent yellow "\n$(t EXT_SELECT_FOR_CHAIN):"
    echoContent red "=============================================================="

    # 列出可用的外部节点
    local index=1
    local nodeIds=()
    while IFS= read -r node; do
        local id name type server port
        id=$(echo "${node}" | jq -r '.id')
        name=$(echo "${node}" | jq -r '.name')
        type=$(echo "${node}" | jq -r '.type')
        server=$(echo "${node}" | jq -r '.server')
        port=$(echo "${node}" | jq -r '.server_port')

        local typeLabel=""
        case "${type}" in
            "shadowsocks") typeLabel="SS" ;;
            "socks") typeLabel="SOCKS5" ;;
            "trojan") typeLabel="Trojan" ;;
            "vless") typeLabel="VLESS" ;;
            "vmess") typeLabel="VMess" ;;
            *) typeLabel="${type}" ;;
        esac

        echoContent yellow "  ${index}. [${typeLabel}] ${name} (${server}:${port})"
        nodeIds+=("${id}")
        ((index++))
    done < <(jq -c '.nodes[]' "${EXTERNAL_NODE_FILE}" 2>/dev/null)

    echoContent yellow "  0. $(t CANCEL)"

    read -r -p "$(t PROMPT_SELECT): " selectIndex

    if [[ -z "${selectIndex}" || "${selectIndex}" == "0" ]]; then
        return 1
    fi

    # 获取选择的节点
    local selectedIndex=$((selectIndex - 1))
    if [[ ${selectedIndex} -lt 0 || ${selectedIndex} -ge ${#nodeIds[@]} ]]; then
        echoContent red " ---> $(t EXT_INVALID_SELECTION)"
        return 1
    fi

    local selectedNodeId="${nodeIds[${selectedIndex}]}"
    local selectedNode
    selectedNode=$(getExternalNodeById "${selectedNodeId}")

    if [[ -z "${selectedNode}" ]]; then
        echoContent red " ---> $(t EXT_NODE_NOT_FOUND)"
        return 1
    fi

    local nodeName nodeType
    nodeName=$(echo "${selectedNode}" | jq -r '.name')
    nodeType=$(echo "${selectedNode}" | jq -r '.type')

    echoContent green "\n ---> $(t EXT_SELECTED): ${nodeName}"

    # 步骤2: 命名链路
    echoContent yellow "\n$(t CHAIN_STEP_NAME)"
    echoContent yellow "$(t CHAIN_NAME_HINT)"

    local defaultName
    defaultName=$(generateNextChainName)

    read -r -p "$(t CHAIN_NAME_PROMPT) [${defaultName}]: " inputName

    local chainName="${inputName:-${defaultName}}"

    # 验证名称格式
    if ! validateChainName "${chainName}"; then
        echoContent red " ---> $(t CHAIN_NAME_INVALID)"
        return 1
    fi

    # 检查名称是否已存在
    if isChainNameExists "${chainName}"; then
        echoContent red " ---> $(t CHAIN_NAME_EXISTS)"
        return 1
    fi

    # 步骤3: 设置分流规则
    echoContent yellow "\n$(t CHAIN_STEP_RULES)"
    echoContent yellow "$(t CHAIN_RULES_HINT):\n"
    echoContent skyBlue "$(t CHAIN_DEFAULT_HINT)\n"
    chainReadRule later || return 1
    local isDefault=false
    [[ "${chainRuleType}" == "default" ]] && isDefault=true

    # 添加外部节点链路到配置
    if ! addExternalChainToConfig "${chainName}" "${selectedNodeId}" "${isDefault}"; then
        return 1
    fi
    case "${chainRuleType}" in
        preset | custom | ip_cidr | geoip) addRuleToConfig "${chainRuleType}" "${chainRuleValue}" "${chainName}" ;;
    esac

    if [[ "${isDefault}" == "true" ]]; then
        echoContent green "\n ---> $(t CHAIN_ADDED): [${chainName}] ($(t DEFAULT_CHAIN))"
    else
        echoContent green "\n ---> $(t CHAIN_ADDED): [${chainName}]"
    fi
    echoContent green "   $(t EXT_NODE): ${nodeName} (${nodeType})"
    echoContent green "   $(t RULES): $(chainRuleLabel "${chainRuleType}" "${chainRuleValue}")"

    return 0
}

# 添加外部节点链路到配置文件
addExternalChainToConfig() {
    local name=$1
    local nodeId=$2
    local isDefault=${3:-false}

    local infoFile="${CHAIN_MULTI_INFO}"

    # 获取外部节点信息
    local node
    node=$(getExternalNodeById "${nodeId}")

    if [[ -z "${node}" ]]; then
        echoContent red " ---> $(t EXT_NODE_NOT_FOUND)"
        return 1
    fi

    local nodeType server port
    nodeType=$(echo "${node}" | jq -r '.type')
    server=$(echo "${node}" | jq -r '.server')
    port=$(echo "${node}" | jq -r '.server_port')

    # 添加到 chains 数组 (标记为外部节点)
    local tmpFile
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"

    jq --arg name "${name}" \
       --arg server "${server}" \
       --argjson port "${port}" \
       --arg nodeType "${nodeType}" \
       --arg nodeId "${nodeId}" \
       --argjson isDefault "${isDefault}" \
       '.chains += [{
           "name": $name,
           "ip": $server,
           "port": $port,
           "source": "external",
           "external_node_id": $nodeId,
           "external_type": $nodeType,
           "is_default": $isDefault
       }]' "${infoFile}" > "${tmpFile}"

    mv "${tmpFile}" "${infoFile}"

    # 如果设为默认链路，更新 default_chain
    if [[ "${isDefault}" == "true" ]]; then
        tmpFile=$(mktemp)
        chmod 600 "${tmpFile}"
        jq --arg name "${name}" '.default_chain = $name' "${infoFile}" > "${tmpFile}"
        mv "${tmpFile}" "${infoFile}"
    fi

    # 生成链路出站配置文件 (使用外部节点配置)
    # generateExternalOutboundConfig 现在通过 jq -n 输出已经合法的单个 outbound JSON 对象，
    # 这里再用 jq -n --argjson 把它包进 {outbounds:[...]}，全程不做字符串拼接。
    local outboundConfig
    outboundConfig=$(generateExternalOutboundConfig "${nodeId}" "${name}")

    if [[ -z "${outboundConfig}" ]]; then
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi

    local outFile="${SINGBOX_FRAGMENT_DIR}/chain_outbound_${name}.json"
    local wrapped
    if ! wrapped=$(jq -n --argjson ob "${outboundConfig}" '{outbounds: [$ob]}') || [[ -z "${wrapped}" ]]; then
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi
    printf '%s\n' "${wrapped}" > "${outFile}"

    return 0
}

# 添加单条链路
addSingleChainOutbound() {
    echoContent yellow "\n$(t CHAIN_STEP_IMPORT)"
    echoContent yellow "$(t CHAIN_PASTE_CODE):"
    read -r -p "$(t CHAIN_CODE):" inputCode

    if [[ -z "${inputCode}" ]]; then
        echoContent red " ---> $(t CHAIN_CODE_EMPTY)"
        return 1
    fi

    # 解析配置码
    if ! parseChainCode "${inputCode}"; then
        return 1
    fi

    echoContent green "\n ---> $(t CHAIN_PARSE_SUCCESS):"
    echoContent green "   $(t CHAIN_NODE_IP): ${chainExitIP}"
    echoContent green "   $(t CHAIN_PORT): ${chainExitPort}"
    echoContent green "   $(t CHAIN_PROTOCOL): Shadowsocks 2022"

    # 步骤2: 命名链路
    echoContent yellow "\n$(t CHAIN_STEP_NAME)"
    echoContent yellow "$(t CHAIN_NAME_HINT)"

    local defaultName
    defaultName=$(generateNextChainName)

    read -r -p "$(t CHAIN_NAME_PROMPT) [${defaultName}]: " inputName

    local chainName="${inputName:-${defaultName}}"

    # 验证名称格式
    if ! validateChainName "${chainName}"; then
        echoContent red " ---> $(t CHAIN_NAME_INVALID)"
        return 1
    fi

    # 检查名称是否已存在
    if isChainNameExists "${chainName}"; then
        echoContent red " ---> $(t CHAIN_NAME_EXISTS)"
        return 1
    fi

    # 步骤3: 设置分流规则
    echoContent yellow "\n$(t CHAIN_STEP_RULES)"
    echoContent yellow "$(t CHAIN_RULES_SELECT):\n"
    echoContent skyBlue "$(t CHAIN_DEFAULT_HINT)\n"
    chainReadRule later || return 1
    local isDefault=false
    [[ "${chainRuleType}" == "default" ]] && isDefault=true

    # 添加链路到配置
    if ! addChainToConfig "${chainName}" "${chainExitIP}" "${chainExitPort}" "${chainExitKey}" "${chainExitMethod}" "${isDefault}" "${chainHops}"; then
        return 1
    fi
    case "${chainRuleType}" in
        preset | custom | ip_cidr | geoip) addRuleToConfig "${chainRuleType}" "${chainRuleValue}" "${chainName}" ;;
    esac
    local chainTarget
    chainTarget=$(jq -r '[.[] | "\(.ip):\(.port)"] | join(" → ")' <<<"${chainHops}")

    if [[ "${isDefault}" == "true" ]]; then
        echoContent green "\n ---> $(t CHAIN_ADDED): [${chainName}] ($(t DEFAULT_CHAIN))"
    else
        echoContent green "\n ---> $(t CHAIN_ADDED): [${chainName}]"
    fi
    echoContent green "   $(t CHAIN_TARGET): ${chainTarget}"
    echoContent green "   $(t RULES): $(chainRuleLabel "${chainRuleType}" "${chainRuleValue}")"

    return 0
}

# 添加链路到配置文件
addChainToConfig() {
    local name=$1
    local ip=$2
    local port=$3
    local key=$4
    local method=$5
    local isDefault=${6:-false}
    local hops=${7:-}

    local infoFile="${CHAIN_MULTI_INFO}"

    # 中继给的多跳码要经中继嵌套着拨（中继把发往下一跳的连接直连过去），只拨出口会静默绕过中继。
    # 前面各跳的 tag 带 -，链路名不许有 -，撞不上别的链路
    if [[ -z "${hops}" ]]; then
        hops=$(jq -n --arg ip "${ip}" --argjson port "${port}" --arg key "${key}" --arg method "${method}" \
            '[{ip: $ip, port: $port, key: $key, method: $method}]') || return 1
    fi
    local outFile="${SINGBOX_FRAGMENT_DIR}/chain_outbound_${name}.json"
    local outboundJson
    if ! outboundJson=$(chainHopOutbounds "${hops}" "${name}" "${name}-hop-") || [[ -z "${outboundJson}" ]]; then
        echoContent red " ---> 链路出站配置生成失败: ${name}"
        return 1
    fi

    # 添加到 chains 数组
    local tmpFile
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"

    jq --arg name "${name}" \
       --arg ip "${ip}" \
       --argjson port "${port}" \
       --arg key "${key}" \
       --arg method "${method}" \
       --argjson isDefault "${isDefault}" \
       '.chains += [{
           "name": $name,
           "ip": $ip,
           "port": $port,
           "method": $method,
           "password": $key,
           "is_default": $isDefault
       }]' "${infoFile}" > "${tmpFile}"

    mv "${tmpFile}" "${infoFile}"

    # 如果设为默认链路，更新 default_chain
    if [[ "${isDefault}" == "true" ]]; then
        tmpFile=$(mktemp)
        chmod 600 "${tmpFile}"
        jq --arg name "${name}" '.default_chain = $name' "${infoFile}" > "${tmpFile}"
        mv "${tmpFile}" "${infoFile}"
    fi

    printf '%s\n' "${outboundJson}" > "${outFile}"

    return 0
}

# 添加规则到配置
addRuleToConfig() {
    local ruleType=$1
    local ruleValue=$2
    local chainName=$3

    local infoFile="${CHAIN_MULTI_INFO}"
    local tmpFile
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"

    jq --arg type "${ruleType}" \
       --arg value "${ruleValue}" \
       --arg chain "${chainName}" \
       '.rules += [{
           "type": $type,
           "value": $value,
           "chain": $chain
       }]' "${infoFile}" > "${tmpFile}"

    mv "${tmpFile}" "${infoFile}"
}

# chainReadRule [later] → 交互选一条分流规则，结果放在 chainRuleType（none / preset / custom / ip_cidr / geoip / default）与 chainRuleValue。
# 传 later 时第一项是「稍后统一配置」。输错或留空就重问，不静默落成没有规则——那样流量全走默认出口、看不出配错了。读不到输入返回 1
chainReadRule() {
    local later=$1 base=0 choice sub value sets
    chainRuleType=
    chainRuleValue=
    [[ -n "${later}" ]] && base=1
    while true; do
        [[ -n "${later}" ]] && echoContent yellow "1.$(t CHAIN_RULE_LATER)"
        echoContent yellow "$((base + 1)).$(t CHAIN_RULE_PRESET)"
        echoContent yellow "$((base + 2)).$(t CHAIN_RULE_CUSTOM_DOMAIN)"
        echoContent yellow "$((base + 3)).$(t CHAIN_RULE_IP_CIDR)"
        echoContent yellow "$((base + 4)).$(t CHAIN_RULE_GEOIP)"
        echoContent yellow "$((base + 5)).$(t CHAIN_RULE_DEFAULT)"
        read -r -p "$(t PROMPT_SELECT): " choice || return 1
        if [[ "${choice}" =~ ^[0-9]{1,3}$ ]]; then
            choice=$((10#${choice}))
        else
            choice=-1
        fi
        value=
        case $((choice - base)) in
            0)
                if [[ -n "${later}" ]]; then
                    chainRuleType=none
                    return 0
                fi
                ;;
            1)
                echoContent yellow "\n$(t CHAIN_RULE_PRESET):\n"
                echoContent yellow "1.$(t CHAIN_PRESET_STREAMING)"
                echoContent yellow "2.$(t CHAIN_PRESET_AI)"
                echoContent yellow "3.$(t CHAIN_PRESET_SOCIAL)"
                echoContent yellow "4.$(t CHAIN_PRESET_DEV)"
                echoContent yellow "5.$(t CHAIN_PRESET_GAMING)"
                echoContent yellow "6.$(t CHAIN_PRESET_GOOGLE)"
                echoContent yellow "7.$(t CHAIN_PRESET_MICROSOFT)"
                echoContent yellow "8.$(t CHAIN_PRESET_APPLE)"
                read -r -p "$(t PROMPT_SELECT): " sub || return 1
                case "${sub}" in
                    1) value=streaming ;;
                    2) value=ai ;;
                    3) value=social ;;
                    4) value=developer ;;
                    5) value=gaming ;;
                    6) value=google ;;
                    7) value=microsoft ;;
                    8) value=apple ;;
                esac
                if [[ -n "${value}" ]]; then
                    IFS=',' read -ra sets <<<"$(getPresetRulesets "${value}")"
                    multiChainRuleSetsAvailable "${sets[@]}" || continue
                    chainRuleType=preset
                    chainRuleValue=${value}
                    return 0
                fi
                ;;
            2)
                echoContent yellow "$(t CHAIN_DOMAIN_HINT):"
                read -r -p "$(t CHAIN_DOMAIN): " value || return 1
                if [[ -n "${value}" ]]; then
                    chainRuleType=custom
                    chainRuleValue=${value}
                    return 0
                fi
                echoContent red " ---> $(t CHAIN_DOMAIN_EMPTY)"
                continue
                ;;
            3)
                echoContent yellow "$(t CHAIN_IP_CIDR_HINT):"
                echoContent yellow "$(t CHAIN_IP_CIDR_EXAMPLE)"
                read -r -p "$(t IP_CIDR): " value || return 1
                if [[ -z "${value}" ]]; then
                    echoContent red " ---> $(t IP_CIDR_EMPTY)"
                    continue
                fi
                if ! validateIpCidrs "${value}"; then
                    echoContent red " ---> $(t CHAIN_IP_CIDR_INVALID)"
                    continue
                fi
                chainRuleType=ip_cidr
                chainRuleValue=${value}
                return 0
                ;;
            4)
                echoContent yellow "\n$(t CHAIN_GEOIP_SELECT):\n"
                echoContent yellow "1.$(t CHAIN_GEOIP_CN) (geoip-cn)"
                echoContent yellow "2.$(t CHAIN_GEOIP_US) (geoip-us)"
                echoContent yellow "3.$(t CHAIN_GEOIP_JP) (geoip-jp)"
                echoContent yellow "4.$(t CHAIN_GEOIP_HK) (geoip-hk)"
                echoContent yellow "5.$(t CHAIN_GEOIP_TW) (geoip-tw)"
                echoContent yellow "6.$(t CHAIN_GEOIP_SG) (geoip-sg)"
                echoContent yellow "7.$(t CHAIN_GEOIP_PRIVATE) (geoip-private)"
                echoContent yellow "8.$(t CHAIN_GEOIP_CUSTOM)"
                read -r -p "$(t PROMPT_SELECT): " sub || return 1
                case "${sub}" in
                    1) value=cn ;;
                    2) value=us ;;
                    3) value=jp ;;
                    4) value=hk ;;
                    5) value=tw ;;
                    6) value=sg ;;
                    7) value=private ;;
                    8)
                        echoContent yellow "$(t CHAIN_GEOIP_CUSTOM_HINT):"
                        read -r -p "GeoIP: " value || return 1
                        value=$(tr '[:upper:]' '[:lower:]' <<<"${value}")
                        ;;
                esac
                # 代码拼进规则集的 tag 与下载地址，只收字母数字和 - _
                if [[ "${value}" =~ ^[a-z0-9_-]{1,32}$ ]]; then
                    multiChainRuleSetsAvailable "geoip-${value}" || continue
                    chainRuleType=geoip
                    chainRuleValue=${value}
                    return 0
                fi
                ;;
            5)
                chainRuleType=default
                return 0
                ;;
        esac
        echoContent red " ---> $(t INVALID_SELECTION)"
    done
}

# chainRuleLabel TYPE VALUE → 一条分流规则的显示名（TYPE 同 chainRuleType）
chainRuleLabel() {
    case "$1" in
        preset) getPresetDisplayName "$2" ;;
        custom) t CUSTOM_DOMAIN ;;
        ip_cidr) echo "IP CIDR" ;;
        geoip) echo "geoip-$2" ;;
        default) t ALL_UNMATCHED ;;
        *) t PENDING_CONFIG ;;
    esac
}

# 配置多链路分流规则
configureMultiChainRules() {
    local infoFile="${CHAIN_MULTI_INFO}"

    if [[ ! -f "${infoFile}" ]]; then
        echoContent red " ---> $(t CHAIN_NO_CONFIG)"
        return 1
    fi

    # 获取所有链路
    local chains
    chains=$(jq -r '.chains[].name' "${infoFile}")

    if [[ -z "${chains}" ]]; then
        echoContent red " ---> $(t CHAIN_NO_CHAINS)"
        return 1
    fi

    echoContent skyBlue "\n$(t CHAIN_RULES_TITLE)"
    echoContent red "=============================================================="
    echoContent yellow "$(t CHAIN_CURRENT_CHAINS):\n"

    local index=1
    while IFS= read -r chain; do
        local chainIP chainPort
        chainIP=$(jq -r ".chains[] | select(.name == \"${chain}\") | .ip" "${infoFile}")
        chainPort=$(jq -r ".chains[] | select(.name == \"${chain}\") | .port" "${infoFile}")
        echoContent yellow "  ${index}. ${chain} (${chainIP}:${chainPort})"
        ((index++))
    done <<< "${chains}"

    echoContent yellow "\n$(t CHAIN_SELECT_CHAIN):"
    read -r -p "$(t CHAIN_INDEX): " chainIndex

    # 获取选中的链路名称
    local selectedChain
    selectedChain=$(echo "${chains}" | sed -n "${chainIndex}p")

    if [[ -z "${selectedChain}" ]]; then
        echoContent red " ---> $(t CHAIN_INVALID_CHAIN)"
        return 1
    fi

    echoContent yellow "\n$(t CHAIN_RULE_FOR) [${selectedChain}] $(t CHAIN_RULE_TYPE_SELECT):\n"
    chainReadRule || return 1

    case "${chainRuleType}" in
        preset)
            addRuleToConfig "preset" "${chainRuleValue}" "${selectedChain}"
            echoContent green " ---> $(t CHAIN_RULE_ADDED): $(chainRuleLabel "${chainRuleType}" "${chainRuleValue}") → ${selectedChain}"
            ;;
        custom)
            addRuleToConfig "custom" "${chainRuleValue}" "${selectedChain}"
            echoContent green " ---> $(t CHAIN_CUSTOM_RULE_ADDED) → ${selectedChain}"
            ;;
        ip_cidr)
            addRuleToConfig "ip_cidr" "${chainRuleValue}" "${selectedChain}"
            echoContent green " ---> $(t CHAIN_IP_CIDR_RULE_ADDED) → ${selectedChain}"
            ;;
        geoip)
            addRuleToConfig "geoip" "${chainRuleValue}" "${selectedChain}"
            echoContent green " ---> $(t CHAIN_GEOIP_RULE_ADDED): $(chainRuleLabel "${chainRuleType}" "${chainRuleValue}") → ${selectedChain}"
            ;;
        default)
            local tmpFile
            tmpFile=$(mktemp)
            chmod 600 "${tmpFile}"
            jq --arg name "${selectedChain}" '.default_chain = $name' "${infoFile}" > "${tmpFile}"
            mv "${tmpFile}" "${infoFile}"

            # 更新链路的 is_default 标志
            tmpFile=$(mktemp)
            chmod 600 "${tmpFile}"
            jq --arg name "${selectedChain}" '
                .chains = [.chains[] | if .name == $name then .is_default = true else .is_default = false end]
            ' "${infoFile}" > "${tmpFile}"
            mv "${tmpFile}" "${infoFile}"

            echoContent green " ---> $(t CHAIN_SET_DEFAULT_SUCCESS "${selectedChain}")"
            ;;
    esac

    return 0
}

# multiChainRestoreAccounts INFO → 重新配置多链路时带回账号的出口映射：指向还在的链路或直连的留下，其余当场列出、回到跟随默认。
# 指向不存在的链路或被引用的链路没有 bridge_port 都算非法映射，sing-box 整个合并失败，所以先过滤，端口走 chainAccountAssignPorts
multiChainRestoreAccounts() {
    local infoFile=$1 state kept dropped
    [[ -n "${multiChainCarriedAccounts:-}" && "${multiChainCarriedAccounts}" != "{}" ]] || return 0
    state=$(cat "${infoFile}") || return 1
    kept=$(jq -c --argjson old "${multiChainCarriedAccounts}" '([.chains[].name] + ["direct"]) as $exits
        | $old | with_entries(select(.value as $v | $exits | index($v)))' <<<"${state}") || return 1
    dropped=$(jq -r --argjson kept "${kept}" '[to_entries[] | select(.key as $k | $kept | has($k) | not) | "\(.key)→\(.value)"] | join(", ")' \
        <<<"${multiChainCarriedAccounts}") || return 1
    state=$(jq -c --argjson kept "${kept}" '.accounts = $kept' <<<"${state}") || return 1
    if ! state=$(chainAccountAssignPorts "${state}"); then
        echoContent red " ---> $(t CHAIN_ACCOUNT_NO_BRIDGE_PORT "${CHAIN_BRIDGE_PORT}" "${CHAIN_BRIDGE_PORT_LAST}")"
        return 1
    fi
    writeChainInfoAtomic "${infoFile}" "${state}" || return 1
    [[ "${kept}" != "{}" ]] && echoContent green " ---> $(t CHAIN_ACCOUNT_CARRY_KEPT "$(jq 'length' <<<"${kept}")")"
    [[ -n "${dropped}" ]] && echoContent yellow " ---> $(t CHAIN_ACCOUNT_CARRY_DROPPED "${dropped}")"
    return 0
}

# 完成多链路配置
finalizeMultiChainConfig() {
    local infoFile="${CHAIN_MULTI_INFO}"

    echoContent yellow "\n$(t CHAIN_GENERATING)"

    # 检查是否设置了默认链路
    local defaultChain
    defaultChain=$(jq -r '.default_chain' "${infoFile}")

    if [[ "${defaultChain}" == "direct" ]]; then
        echoContent yellow "\n$(t CHAIN_NO_DEFAULT_SET)"
        echoContent yellow "$(t CHAIN_SET_DEFAULT_NOW)\n"

        local chains
        chains=$(jq -r '.chains[].name' "${infoFile}")

        local index=1
        while IFS= read -r chain; do
            echoContent yellow "  ${index}. ${chain}"
            ((index++))
        done <<< "${chains}"
        echoContent yellow "  ${index}. $(t CHAIN_NO_DEFAULT_OPTION)"

        read -r -p "$(t PROMPT_SELECT) [${index}]: " defaultChoice

        if [[ -n "${defaultChoice}" ]] && [[ "${defaultChoice}" != "${index}" ]]; then
            local selectedDefault
            selectedDefault=$(echo "${chains}" | sed -n "${defaultChoice}p")

            if [[ -n "${selectedDefault}" ]]; then
                local tmpFile
                tmpFile=$(mktemp)
                chmod 600 "${tmpFile}"
                jq --arg name "${selectedDefault}" '.default_chain = $name' "${infoFile}" > "${tmpFile}"
                mv "${tmpFile}" "${infoFile}"

                defaultChain="${selectedDefault}"
                echoContent green " ---> $(t CHAIN_SET_DEFAULT_SUCCESS "${selectedDefault}")"
            fi
        fi
    fi

    # 检测是否有 Xray 代理协议在运行
    local hasXrayProtocols=false
    # 扫描 xray/conf 下所有已注册代理协议(含 WS/XHTTP/HTTPUpgrade 等，见 lib/protocol-registry.sh)；
    # 仅查 02/07/04 会漏掉 XHTTP 等 → hasXrayProtocols=false → 不建桥接/不改路由 → 链路静默失效
    local _xrayProtos; _xrayProtos=$(scanInstalledProtocols "${XRAY_CONF_DIR}/")
    if [[ -n "${_xrayProtos//,/}" ]]; then
        hasXrayProtocols=true
        echoContent green " ---> $(t CHAIN_XRAY_DETECTED)"
    fi

    # 更新 has_xray 标志
    local tmpFile
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"
    jq --argjson hasXray "${hasXrayProtocols}" '.has_xray = $hasXray' "${infoFile}" > "${tmpFile}"
    mv "${tmpFile}" "${infoFile}"

    multiChainRestoreAccounts "${infoFile}" || return 1

    # 生成路由配置
    generateMultiChainRouteConfig

    # 如果有 Xray，创建 SOCKS5 桥接入站并先接好 Xray：之后 sing-box 起不来时 Xray 用户是断网，不是静默直连
    # sniff/resolve 在 generateMultiChainRouteConfig 路由配置中以 action 形式注入
    local chainBridgePort=${CHAIN_BRIDGE_PORT}
    if [[ "${hasXrayProtocols}" == "true" ]]; then
        writeChainBridgeInbound "${chainBridgePort}"
        configureXrayForMultiChain "${chainBridgePort}" || return 1
    fi

    # 合并配置
    echoContent yellow "$(t CHAIN_MERGING_SINGBOX)"
    if ! singBoxMergeConfig; then
        return 1
    fi

    # 启动 sing-box
    echoContent yellow "$(t CHAIN_STARTING_SINGBOX)"
    handleSingBox stop >/dev/null 2>&1
    handleSingBox start

    # 验证 sing-box 启动成功
    sleep 1
    if ! pgrep -x "sing-box" >/dev/null 2>&1; then
        echoContent red " ---> $(t CHAIN_SINGBOX_START_FAILED)"
        echoContent yellow "$(t CHAIN_SINGBOX_DEBUG) ${SINGBOX_BIN} run -c ${SINGBOX_MERGED_CONFIG}"
        return 1
    fi
    echoContent green " ---> $(t CHAIN_SINGBOX_START_SUCCESS)"

    # 显示配置摘要
    showMultiChainSummary

    # 测试连通性
    echoContent yellow "\n$(t CHAIN_TESTING_CONNECTIVITY)"
    sleep 2
    testMultiChainConnection
}

# 生成多链路路由配置
generateMultiChainRouteConfig() {
    local infoFile="${CHAIN_MULTI_INFO}"

    # 获取默认链路
    local defaultChain
    defaultChain=$(jq -r '.default_chain' "${infoFile}")

    # 获取是否有 Xray
    local hasXray
    hasXray=$(jq -r '.has_xray' "${infoFile}")

    # 路由级 sniff/resolve 替代 inbound 上的 sniff 字段（1.11+）。
    # 仅当存在 chain_bridge_in（has_xray）时才加 sniff/resolve，否则留空。
    local routeRules="[]"
    local ruleSetDefs="[]"
    local usedRuleSets=""

    # 如果有 SOCKS5 桥接入站（来自 Xray 的流量），仅 prepend sniff/resolve（非终态 action），
    # 让后续 preset/custom/ip_cidr/geoip 规则仍能按域名/IP 命中分流；未命中由 route.final（=defaultChain）兜底。
    # 不要在这里 prepend 终态规则（如 inbound→outbound:defaultChain），那会让预设分流永远不命中。
    if [[ "${hasXray}" == "true" ]]; then
        routeRules=$(echo "${routeRules}" | jq '. + [
            {"inbound":"chain_bridge_in","action":"sniff","timeout":"1s"},
            {"inbound":"chain_bridge_in","action":"resolve","strategy":"prefer_ipv4"}
        ]')
    fi

    # 处理预设规则
    local rules
    rules=$(jq -c '.rules[]' "${infoFile}" 2>/dev/null)

    while IFS= read -r rule; do
        [[ -z "${rule}" ]] && continue

        local ruleType ruleValue ruleChain
        ruleType=$(echo "${rule}" | jq -r '.type')
        ruleValue=$(echo "${rule}" | jq -r '.value')
        ruleChain=$(echo "${rule}" | jq -r '.chain')

        if [[ "${ruleType}" == "preset" ]]; then
            # 获取预设规则对应的规则集
            local rulesets
            rulesets=$(getPresetRulesets "${ruleValue}")

            IFS=',' read -ra rulesetArray <<< "${rulesets}"
            local rulesetNames="[]"

            for ruleset in "${rulesetArray[@]}"; do
                rulesetNames=$(echo "${rulesetNames}" | jq --arg rs "${ruleset}" '. + [$rs]')

                # 如果规则集未添加，添加定义
                if [[ ! "${usedRuleSets}" =~ "${ruleset}" ]]; then
                    usedRuleSets="${usedRuleSets},${ruleset}"

                    local rulesetUrl
                    rulesetUrl=$(multiChainRuleSetUrl "${ruleset}")

                    ruleSetDefs=$(echo "${ruleSetDefs}" | jq --arg tag "${ruleset}" --arg url "${rulesetUrl}" '. + [{
                        "tag": $tag,
                        "type": "remote",
                        "format": "binary",
                        "url": $url,
                        "http_client": "rule_set_http",
                        "update_interval": "1d"
                    }]')
                fi
            done

            # 添加路由规则
            routeRules=$(echo "${routeRules}" | jq --argjson rs "${rulesetNames}" --arg chain "${ruleChain}" '. + [{
                "rule_set": $rs,
                "outbound": $chain
            }]')

        elif [[ "${ruleType}" == "custom" ]]; then
            # 自定义域名规则
            local domains="[]"
            IFS=',' read -ra domainArray <<< "${ruleValue}"
            for domain in "${domainArray[@]}"; do
                domain=$(echo "${domain}" | xargs)  # trim
                domains=$(echo "${domains}" | jq --arg d "${domain}" '. + [$d]')
            done

            routeRules=$(echo "${routeRules}" | jq --argjson ds "${domains}" --arg chain "${ruleChain}" '. + [{
                "domain_suffix": $ds,
                "outbound": $chain
            }]')

        elif [[ "${ruleType}" == "ip_cidr" ]]; then
            # IP CIDR 规则
            local ipCidrs="[]"
            IFS=',' read -ra cidrArray <<< "${ruleValue}"
            for cidr in "${cidrArray[@]}"; do
                cidr=$(echo "${cidr}" | xargs)  # trim
                ipCidrs=$(echo "${ipCidrs}" | jq --arg c "${cidr}" '. + [$c]')
            done

            routeRules=$(echo "${routeRules}" | jq --argjson ips "${ipCidrs}" --arg chain "${ruleChain}" '. + [{
                "ip_cidr": $ips,
                "outbound": $chain
            }]')

        elif [[ "${ruleType}" == "geoip" ]]; then
            # GeoIP 规则
            local geoipTag="geoip-${ruleValue}"

            # 如果规则集未添加，添加定义
            if [[ ! "${usedRuleSets}" =~ "${geoipTag}" ]]; then
                usedRuleSets="${usedRuleSets},${geoipTag}"

                local geoipUrl
                geoipUrl=$(multiChainRuleSetUrl "${geoipTag}")

                ruleSetDefs=$(echo "${ruleSetDefs}" | jq --arg tag "${geoipTag}" --arg url "${geoipUrl}" '. + [{
                    "tag": $tag,
                    "type": "remote",
                    "format": "binary",
                    "url": $url,
                    "http_client": "rule_set_http",
                    "update_interval": "1d"
                }]')
            fi

            # 添加路由规则
            routeRules=$(echo "${routeRules}" | jq --arg rs "${geoipTag}" --arg chain "${ruleChain}" '. + [{
                "rule_set": [$rs],
                "outbound": $chain
            }]')
        fi
    done <<< "${rules}"

    # 确保 direct 出站存在（不写 domain_strategy，详见 ensureSingBoxInstalled 注释）
    if [[ ! -f "${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json" ]]; then
        jq -n '{outbounds: [{type: "direct", tag: "direct"}]}' >"${SINGBOX_FRAGMENT_DIR}/01_direct_outbound.json"
    fi

    # 生成最终路由配置
    local finalOutbound="${defaultChain}"

    # 构建完整的路由配置 JSON；default_domain_resolver 见 chainExit 注释，1.13 起必填
    # 有远程规则集就开 cache_file：sing-box 起步时下载不到任何一个规则集就整个退出，有缓存的机器断了 GitHub 也能起；
    # 路径写死在 sing-box 目录下，不然按服务的 WorkingDirectory 落到 /root
    local routeConfig
    routeConfig=$(jq -n \
        --argjson rules "${routeRules}" \
        --argjson ruleSets "${ruleSetDefs}" \
        --arg final "${finalOutbound}" \
        --arg cache "${SINGBOX_CONF_DIR}/cache.db" \
        '{
            "route": {
                "rule_set": $ruleSets,
                "rules": $rules,
                "final": $final,
                "auto_detect_interface": true,
                "default_domain_resolver": "google"
            }
        } + (if ($ruleSets | length) > 0 then {experimental: {cache_file: {enabled: true, path: $cache}}} else {} end)')

    echo "${routeConfig}" > ${SINGBOX_FRAGMENT_DIR}/chain_route.json
}

# 配置 Xray 链式转发
configureXrayForMultiChain() {
    local bridgePort=$1

    echoContent yellow "$(t CHAIN_CONFIGURING_XRAY)"
    writeXrayChainConfig "${bridgePort}" || return 1

    # 重启 Xray
    echoContent yellow "$(t CHAIN_RESTARTING_XRAY)"
    handleXray stop >/dev/null 2>&1
    handleXray start

    sleep 1
    if xrayDaemonRunning; then
        echoContent green " ---> $(t CHAIN_XRAY_RESTART_SUCCESS)"
    else
        echoContent red " ---> $(t CHAIN_XRAY_RESTART_FAILED)"
        echoContent yellow "$(t CHAIN_XRAY_CHECK_CONFIG) ${XRAY_BIN} run -confdir ${XRAY_CONF_DIR}"
    fi
}

# xrayChainUnwired → 装了 Xray 协议、Xray 侧却没有 chain_outbound.json：链路对 Xray 账号不起作用，它们的流量从本机直连出去
xrayChainUnwired() {
    [[ -n "$(scanInstalledProtocols "${XRAY_CONF_DIR}/" 2>/dev/null | tr -d ',')" && ! -f "${XRAY_CONF_DIR}/chain_outbound.json" ]]
}

# multiChainEnsureXrayWired → 多链路改动前把没接上的 Xray 接进来（向导在起 sing-box 处失败过，或链路配好后才装 Xray）：
# 补 has_xray、桥入站、Xray 的出站与路由，重启交给随后的 reloadCore。要在生成路由与合并之前调，桥的 sniff 规则跟着 has_xray 走
multiChainEnsureXrayWired() {
    xrayChainUnwired || return 0
    echoContent yellow "$(t CHAIN_CONFIGURING_XRAY)"
    jsonModifyFile "${CHAIN_MULTI_INFO}" '.has_xray = true' false || return 1
    writeChainBridgeInbound "${CHAIN_BRIDGE_PORT}"
    writeXrayChainConfig "${CHAIN_BRIDGE_PORT}"
}

# 显示多链路配置摘要
showMultiChainSummary() {
    local infoFile="${CHAIN_MULTI_INFO}"

    echoContent green "\n=============================================================="
    echoContent green "$(t CHAIN_CONFIG_COMPLETE)"
    echoContent green "=============================================================="

    local chainCount
    chainCount=$(jq '.chains | length' "${infoFile}")

    echoContent yellow "\n$(t CHAIN_CONFIGURED_COUNT "${chainCount}"):\n"

    # 表头
    printf "  %-15s %-20s %-20s\n" "$(t CHAIN_SUMMARY_NAME)" "$(t CHAIN_SUMMARY_TARGET)" "$(t CHAIN_SUMMARY_RULES)"
    printf "  %-15s %-20s %-20s\n" "---------------" "--------------------" "--------------------"

    # 遍历链路
    local chains
    chains=$(jq -c '.chains[]' "${infoFile}")

    while IFS= read -r chain; do
        local name ip port isDefault
        name=$(echo "${chain}" | jq -r '.name')
        ip=$(echo "${chain}" | jq -r '.ip')
        port=$(echo "${chain}" | jq -r '.port')
        isDefault=$(echo "${chain}" | jq -r '.is_default')

        # 获取此链路的规则
        local ruleDesc
        ruleDesc="$(t CHAIN_RULE_PENDING)"
        local rules
        rules=$(jq -r ".rules[] | select(.chain == \"${name}\") | .type + \":\" + .value" "${infoFile}" 2>/dev/null)

        if [[ -n "${rules}" ]]; then
            local firstRule
            firstRule=$(echo "${rules}" | head -1)
            local ruleType ruleValue
            ruleType=$(echo "${firstRule}" | cut -d: -f1)
            ruleValue=$(echo "${firstRule}" | cut -d: -f2-)

            ruleDesc=$(chainRuleLabel "${ruleType}" "${ruleValue}")
        fi

        if [[ "${isDefault}" == "true" ]]; then
            ruleDesc="$(t CHAIN_DEFAULT_ALL_TRAFFIC)"
        fi

        printf "  %-15s %-20s %-20s\n" "${name}" "${ip}:${port}" "${ruleDesc}"
    done <<< "${chains}"

    # 显示默认链路
    local defaultChain
    defaultChain=$(jq -r '.default_chain' "${infoFile}")

    if [[ "${defaultChain}" == "direct" ]]; then
        echoContent yellow "\n$(t CHAIN_DEFAULT_OUTBOUND_DIRECT)"
    else
        echoContent yellow "\n$(t CHAIN_DEFAULT_OUTBOUND): ${defaultChain}"
    fi
}

# 并行测试多链路连通性
testMultiChainConnection() {
    local infoFile="${CHAIN_MULTI_INFO}"

    if [[ ! -f "${infoFile}" ]]; then
        # 如果不是多链路模式，使用原有测试函数
        testChainConnection
        return $?
    fi

    echoContent skyBlue "\n$(t CHAIN_TEST_MULTI_TITLE)"
    echoContent red "=============================================================="

    local chains
    chains=$(jq -c '.chains[]' "${infoFile}")
    local chainCount
    chainCount=$(jq '.chains | length' "${infoFile}")

    echoContent yellow "$(t CHAIN_TESTING_PARALLEL "${chainCount}")\n"

    # 创建临时目录存放测试结果
    local tmpDir
    tmpDir=$(mktemp -d)

    # 并行测试每条链路
    local pids=""
    local index=0

    while IFS= read -r chain; do
        local name ip port
        name=$(echo "${chain}" | jq -r '.name')
        ip=$(echo "${chain}" | jq -r '.ip')
        port=$(echo "${chain}" | jq -r '.port')

        # 端口通不等于链路通：密钥不对、出口限源、经中继的链路照样连得上出口端口。按链路自己的出站真取一次出口 IP，不碰在跑的 sing-box
        (
            local result="fail" took="" outIP="" probeConf="${tmpDir}/probe_${index}.json" startTime
            if jq '{log: {level: "error"}, dns: {servers: [{type: "local", tag: "local"}]},
                    outbounds: [.outbounds[] | del(.domain_resolver)], route: {default_domain_resolver: "local"}}' \
                "${SINGBOX_FRAGMENT_DIR}/chain_outbound_${name}.json" >"${probeConf}" 2>/dev/null; then
                startTime=$(date +%s%N)
                # tools fetch 只要拿到响应就退出 0，握手或认证失败才非零；没有超时，靠 timeout 兜住
                if outIP=$(timeout 15 "${SINGBOX_BIN}" tools fetch -c "${probeConf}" -o "${name}" https://api.ipify.org 2>/dev/null) \
                    && [[ "${outIP}" =~ ^[0-9a-fA-F.:]+$ ]]; then
                    result="pass"
                    took=$(( ($(date +%s%N) - startTime) / 1000000 ))
                fi
            fi
            echo "${name}|${ip}:${port}|${result}|${took}|${outIP}" > "${tmpDir}/result_${index}"
        ) &

        pids="${pids} $!"
        ((index++))
    done <<< "${chains}"

    # 等待所有测试完成
    for pid in ${pids}; do
        wait "${pid}" 2>/dev/null
    done

    # 读取并显示结果
    local passCount=0
    local failCount=0

    for resultFile in "${tmpDir}"/result_*; do
        if [[ -f "${resultFile}" ]]; then
            local name target status took outIP
            IFS='|' read -r name target status took outIP <"${resultFile}"

            if [[ "${status}" == "pass" ]]; then
                echoContent green "  ✅ ${name} (${target}) - $(t CHAIN_TEST_PROBE_OK "${outIP}" "${took}")"
                ((passCount++))
            else
                echoContent red "  ❌ ${name} (${target}) - $(t CHAIN_TEST_CONN_FAIL)"
                ((failCount++))
            fi
        fi
    done

    # 清理临时文件
    rm -rf "${tmpDir}"

    # 显示汇总
    echoContent yellow "\n$(t CHAIN_TEST_COMPLETE "${passCount}" "${failCount}")"

    if [[ ${failCount} -gt 0 ]]; then
        echoContent yellow "\n$(t CHAIN_TEST_CHECK_HINT)"
        echoContent yellow "  $(t CHAIN_TEST_CHECK_1)"
        echoContent yellow "  $(t CHAIN_TEST_CHECK_2)"
        echoContent yellow "  $(t CHAIN_TEST_CHECK_3)"
    fi
}

# 显示多链路状态
showMultiChainStatus() {
    local infoFile="${CHAIN_MULTI_INFO}"

    if [[ ! -f "${infoFile}" ]]; then
        return 1
    fi

    local status="❌ $(t CHAIN_STATUS_STOPPED)"
    if pgrep -x "sing-box" >/dev/null 2>&1; then
        status="✅ $(t CHAIN_STATUS_RUNNING)"
    fi

    local chainCount
    chainCount=$(jq '.chains | length' "${infoFile}")
    local defaultChain
    defaultChain=$(jq -r '.default_chain' "${infoFile}")

    echoContent green "╔══════════════════════════════════════════════════════════════╗"
    echoContent green "║                      $(t CHAIN_STATUS_TITLE)                              ║"
    echoContent green "╠══════════════════════════════════════════════════════════════╣"
    echoContent yellow "  $(t CHAIN_STATUS_ROLE): $(t CHAIN_STATUS_ROLE_ENTRY)"
    echoContent yellow "  $(t CHAIN_STATUS_RUN): ${status}"
    echoContent yellow "  $(t CHAIN_STATUS_COUNT): ${chainCount}"
    echoContent yellow "  $(t CHAIN_DEFAULT_OUTBOUND): ${defaultChain}"
    echoContent green "╠══════════════════════════════════════════════════════════════╣"
    echoContent yellow "  $(t CHAIN_STATUS_DETAILS):"

    local chains
    chains=$(jq -c '.chains[]' "${infoFile}")

    while IFS= read -r chain; do
        local name ip port isDefault
        name=$(echo "${chain}" | jq -r '.name')
        ip=$(echo "${chain}" | jq -r '.ip')
        port=$(echo "${chain}" | jq -r '.port')
        isDefault=$(echo "${chain}" | jq -r '.is_default')

        local defaultMark=""
        if [[ "${isDefault}" == "true" ]]; then
            defaultMark=" $(t CHAIN_STATUS_DEFAULT_MARK)"
        fi

        echoContent yellow "    • ${name}: ${ip}:${port}${defaultMark}"
    done <<< "${chains}"

    echoContent green "╚══════════════════════════════════════════════════════════════╝"

    return 0
}

# multiChainAddChain → 往已有多链路里加一条：加完出站要重建路由、合并、重载，只加出站的话新链路的分流规则一直不生效
multiChainAddChain() {
    local addType
    echoContent yellow "$(t CHAIN_ADD_TYPE_SELECT):\n"
    echoContent yellow "1.$(t CHAIN_ADD_BY_CODE)"
    echoContent yellow "2.$(t CHAIN_ADD_BY_EXTERNAL)"
    echoContent yellow "0.$(t CANCEL)"
    read -r -p "$(t PROMPT_SELECT): " addType
    case "${addType}" in
        1) addSingleChainOutbound || return 1 ;;
        2) addExternalNodeAsChain || return 1 ;;
        0 | "") return 0 ;;
        *)
            echoContent red " ---> $(t INVALID_SELECTION)"
            return 1
            ;;
    esac
    multiChainEnsureXrayWired || return 1
    generateMultiChainRouteConfig
    if ! singBoxMergeConfig; then
        echoContent red " ---> 配置合并失败，链路未生效"
        return 1
    fi
    reloadCore
    echoContent green " ---> 配置已更新"
}

# 多链路高级管理菜单
multiChainAdvancedMenu() {
    echoContent skyBlue "\n多链路高级管理"
    echoContent red "=============================================================="

    echoContent yellow "1.添加链式出站"
    echoContent yellow "2.删除链式出站"
    echoContent yellow "3.配置分流规则"
    echoContent yellow "4.设置默认链路"
    echoContent yellow "5.查看详细配置"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        multiChainAddChain
        ;;
    2)
        removeMultiChainOutbound
        ;;
    3)
        configureMultiChainRules
        multiChainEnsureXrayWired
        generateMultiChainRouteConfig
        if singBoxMergeConfig; then
            reloadCore
            echoContent green " ---> 配置已更新"
        else
            echoContent red " ---> 配置合并失败，规则未生效"
        fi
        ;;
    4)
        setDefaultChain
        ;;
    5)
        showMultiChainDetailConfig
        ;;
    esac
}

# 删除链路
removeMultiChainOutbound() {
    local infoFile="${CHAIN_MULTI_INFO}"

    if [[ ! -f "${infoFile}" ]]; then
        echoContent red " ---> 未找到多链路配置"
        return 1
    fi

    echoContent yellow "\n当前链路:\n"

    local chains
    chains=$(jq -r '.chains[].name' "${infoFile}")
    local chainCount
    chainCount=$(jq '.chains | length' "${infoFile}")

    if [[ ${chainCount} -lt 1 ]]; then
        echoContent red " ---> 没有可删除的链路"
        return 1
    fi

    local index=1
    while IFS= read -r chain; do
        local chainIP chainPort isDefault
        chainIP=$(jq -r ".chains[] | select(.name == \"${chain}\") | .ip" "${infoFile}")
        chainPort=$(jq -r ".chains[] | select(.name == \"${chain}\") | .port" "${infoFile}")
        isDefault=$(jq -r ".chains[] | select(.name == \"${chain}\") | .is_default" "${infoFile}")

        local defaultMark=""
        if [[ "${isDefault}" == "true" ]]; then
            defaultMark=" $(t CHAIN_STATUS_DEFAULT_MARK)"
        fi

        echoContent yellow "  ${index}. ${chain} (${chainIP}:${chainPort})${defaultMark}"
        ((index++))
    done <<< "${chains}"

    read -r -p "请选择要删除的链路编号: " deleteIndex

    local selectedChain
    selectedChain=$(echo "${chains}" | sed -n "${deleteIndex}p")

    if [[ -z "${selectedChain}" ]]; then
        echoContent red " ---> 无效的选择"
        return 1
    fi

    # 还有账号指定它为出口就不删：删了它们只能改走别的出口或直连，那是车主没选过的去向
    local mappedAccounts
    mappedAccounts=$(jq -r --arg n "${selectedChain}" '[(.accounts // {}) | to_entries[] | select(.value == $n) | .key] | join(", ")' "${infoFile}") || return 1
    if [[ -n "${mappedAccounts}" ]]; then
        echoContent red " ---> $(t CHAIN_ACCOUNT_EXIT_IN_USE "${selectedChain}" "${mappedAccounts}")"
        return 1
    fi

    echoContent yellow "\n确认删除链路 [${selectedChain}]？[y/n]"
    read -r -p "确认: " confirmDelete

    if ! isYesInput "${confirmDelete}"; then
        return 0
    fi

    # 删除链路配置文件
    rm -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound_${selectedChain}.json"

    # 从 info 文件中删除
    local tmpFile
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"

    jq --arg name "${selectedChain}" '
        .chains = [.chains[] | select(.name != $name)] |
        .rules = [.rules[] | select(.chain != $name)]
    ' "${infoFile}" > "${tmpFile}"
    mv "${tmpFile}" "${infoFile}"

    # 如果删除的是默认链路，重置为 direct
    local wasDefault
    wasDefault=$(jq -r ".default_chain" "${infoFile}")
    if [[ "${wasDefault}" == "${selectedChain}" ]]; then
        tmpFile=$(mktemp)
        chmod 600 "${tmpFile}"
        jq '.default_chain = "direct"' "${infoFile}" > "${tmpFile}"
        mv "${tmpFile}" "${infoFile}"
        echoContent yellow " ---> 已重置默认链路为直连"
    fi

    # 重新生成路由配置
    multiChainEnsureXrayWired
    generateMultiChainRouteConfig
    # 删除语义：物理删除已完成，merge 失败说明剩余配置仍有问题，告警不阻断
    if ! singBoxMergeConfig; then
        echoContent yellow " ---> 警告：sing-box 配置合并失败，链路记录已删除但配置未刷新"
    fi
    reloadCore

    echoContent green " ---> 链路 [${selectedChain}] 已删除"
}

# 设置默认链路
setDefaultChain() {
    local infoFile="${CHAIN_MULTI_INFO}"

    if [[ ! -f "${infoFile}" ]]; then
        echoContent red " ---> 未找到多链路配置"
        return 1
    fi

    echoContent yellow "\n选择默认链路:\n"

    local chains
    chains=$(jq -r '.chains[].name' "${infoFile}")

    local index=1
    while IFS= read -r chain; do
        echoContent yellow "  ${index}. ${chain}"
        ((index++))
    done <<< "${chains}"
    echoContent yellow "  ${index}. 直连 (未匹配流量直连访问)"

    read -r -p "请选择: " defaultChoice

    local newDefault
    if [[ "${defaultChoice}" == "${index}" ]]; then
        newDefault="direct"
    else
        newDefault=$(echo "${chains}" | sed -n "${defaultChoice}p")
    fi

    if [[ -z "${newDefault}" ]]; then
        echoContent red " ---> 无效的选择"
        return 1
    fi

    local tmpFile
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"
    jq --arg name "${newDefault}" '.default_chain = $name' "${infoFile}" > "${tmpFile}"
    mv "${tmpFile}" "${infoFile}"

    # 更新 is_default 标志
    tmpFile=$(mktemp)
    chmod 600 "${tmpFile}"
    if [[ "${newDefault}" == "direct" ]]; then
        jq '.chains = [.chains[] | .is_default = false]' "${infoFile}" > "${tmpFile}"
    else
        jq --arg name "${newDefault}" '
            .chains = [.chains[] | if .name == $name then .is_default = true else .is_default = false end]
        ' "${infoFile}" > "${tmpFile}"
    fi
    mv "${tmpFile}" "${infoFile}"

    # 重新生成路由配置
    generateMultiChainRouteConfig
    if ! singBoxMergeConfig; then
        echoContent red " ---> 配置合并失败，默认链路设置未生效"
        return 1
    fi
    reloadCore

    echoContent green " ---> 默认链路已设置为: ${newDefault}"
}

# 显示多链路详细配置
showMultiChainDetailConfig() {
    echoContent skyBlue "\n多链路详细配置"
    echoContent red "=============================================================="

    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        echoContent yellow "\n元数据 (chain_multi_info.json):"
        jq . ${CHAIN_MULTI_INFO}
    fi

    echoContent yellow "\n链路出站配置:"
    for f in ${SINGBOX_FRAGMENT_DIR}/chain_outbound_*.json; do
        if [[ -f "${f}" ]]; then
            echoContent yellow "\n$(basename "${f}"):"
            jq . "${f}"
        fi
    done

    if [[ -f "${SINGBOX_FRAGMENT_DIR}/chain_route.json" ]]; then
        echoContent yellow "\n路由配置 (chain_route.json):"
        jq . ${SINGBOX_FRAGMENT_DIR}/chain_route.json
    fi
}

# ======================= 多链路分流功能结束 =======================

# ======================= 链式代理功能结束 =======================

# ======================= 外部节点功能开始 =======================

# 初始化外部节点配置文件
initExternalNodeFile() {
    local confDir="${SINGBOX_CONF_DIR}"
    mkdir -p "${confDir}"

    if [[ ! -f "${EXTERNAL_NODE_FILE}" ]]; then
        # 原子写入，避免中断导致半写文件被下游 jq 读到
        writeChainInfoAtomic "${EXTERNAL_NODE_FILE}" '{"nodes": []}' || return 1
        chmod 600 "${EXTERNAL_NODE_FILE}"
    fi
}

# 生成唯一节点ID
generateNodeId() {
    echo "ext_$(date +%s)_${RANDOM}"
}

# 获取外部节点数量
getExternalNodeCount() {
    initExternalNodeFile
    jq -r '.nodes | length' "${EXTERNAL_NODE_FILE}" 2>/dev/null || echo "0"
}

# 添加外部节点到配置文件
# 原子写入: mktemp + jq 返回码检查 + 结果 JSON 语法验证 + 原子 rename
# 失败时保留原文件不变并返回 1
addExternalNodeToFile() {
    local nodeJson="$1"
    initExternalNodeFile || return 1

    local tempFile
    tempFile=$(mktemp "${EXTERNAL_NODE_FILE}.XXXXXX") || return 1
    if ! jq --argjson node "${nodeJson}" '.nodes += [$node]' "${EXTERNAL_NODE_FILE}" > "${tempFile}" 2>/dev/null; then
        rm -f "${tempFile}"
        echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${EXTERNAL_NODE_FILE}")"
        return 1
    fi
    if ! jq -e . "${tempFile}" >/dev/null 2>&1; then
        rm -f "${tempFile}"
        echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${EXTERNAL_NODE_FILE}")"
        return 1
    fi
    mv "${tempFile}" "${EXTERNAL_NODE_FILE}" || return 1
    chmod 600 "${EXTERNAL_NODE_FILE}"
}

# 删除外部节点（与 addExternalNodeToFile 同样的原子保障）
removeExternalNodeFromFile() {
    local nodeId="$1"
    initExternalNodeFile || return 1

    local tempFile
    tempFile=$(mktemp "${EXTERNAL_NODE_FILE}.XXXXXX") || return 1
    if ! jq --arg id "${nodeId}" '.nodes = [.nodes[] | select(.id != $id)]' "${EXTERNAL_NODE_FILE}" > "${tempFile}" 2>/dev/null; then
        rm -f "${tempFile}"
        echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${EXTERNAL_NODE_FILE}")"
        return 1
    fi
    if ! jq -e . "${tempFile}" >/dev/null 2>&1; then
        rm -f "${tempFile}"
        echoContent red " ---> $(t CHAIN_INFO_WRITE_FAIL "${EXTERNAL_NODE_FILE}")"
        return 1
    fi
    mv "${tempFile}" "${EXTERNAL_NODE_FILE}" || return 1
    chmod 600 "${EXTERNAL_NODE_FILE}"
}

# 获取单个节点信息
getExternalNodeById() {
    local nodeId="$1"
    initExternalNodeFile
    jq -r --arg id "${nodeId}" '.nodes[] | select(.id == $id)' "${EXTERNAL_NODE_FILE}" 2>/dev/null
}

# Shadowsocks 加密方式列表
SS_METHODS=(
    "aes-128-gcm"
    "aes-256-gcm"
    "chacha20-ietf-poly1305"
    "xchacha20-ietf-poly1305"
    "2022-blake3-aes-128-gcm"
    "2022-blake3-aes-256-gcm"
    "2022-blake3-chacha20-poly1305"
)

# 显示加密方式选择菜单。调用方用 $() 接结果，菜单必须走 stderr，否则菜单文字一起存进节点，sing-box 合并必败
selectSSMethod() {
    echoContent yellow "\n$(t EXT_SELECT_METHOD):" >&2
    local i=1
    for method in "${SS_METHODS[@]}"; do
        echoContent yellow "  ${i}. ${method}" >&2
        ((i++))
    done

    read -r -p "$(t PROMPT_SELECT): " methodIndex
    if [[ "${methodIndex}" -ge 1 && "${methodIndex}" -le ${#SS_METHODS[@]} ]]; then
        echo "${SS_METHODS[$((methodIndex-1))]}"
    else
        echo "aes-256-gcm"
    fi
}

# 手动添加 Shadowsocks 节点
addExternalNodeSS() {
    echoContent skyBlue "\n$(t EXT_ADD_SS)"
    echoContent red "=============================================================="

    # 服务器地址
    read -r -p "$(t EXT_INPUT_SERVER): " server
    if [[ -z "${server}" ]]; then
        echoContent red " ---> $(t EXT_SERVER_REQUIRED)"
        return 1
    fi

    # 端口
    read -r -p "$(t EXT_INPUT_PORT): " port
    if [[ -z "${port}" || ! "${port}" =~ ^[0-9]+$ ]]; then
        echoContent red " ---> $(t EXT_PORT_INVALID)"
        return 1
    fi

    # 加密方式
    local method
    method=$(selectSSMethod)

    # 密码
    read -r -p "$(t EXT_INPUT_PASSWORD): " password
    if [[ -z "${password}" ]]; then
        echoContent red " ---> $(t EXT_PASSWORD_REQUIRED)"
        return 1
    fi

    # 节点名称
    read -r -p "$(t EXT_INPUT_NAME) [SS-${server}]: " nodeName
    if [[ -z "${nodeName}" ]]; then
        nodeName="SS-${server}"
    fi

    # 生成节点JSON
    local nodeId
    nodeId=$(generateNodeId)
    local nodeJson
    nodeJson=$(jq -n \
        --arg id "${nodeId}" \
        --arg name "${nodeName}" \
        --arg server "${server}" \
        --argjson server_port "${port}" \
        --arg method "${method}" \
        --arg password "${password}" \
        --arg created_at "$(date -Iseconds)" \
        '{id: $id, name: $name, type: "shadowsocks", server: $server, server_port: $server_port, method: $method, password: $password, enabled: true, created_at: $created_at}')

    # 添加到配置文件
    addExternalNodeToFile "${nodeJson}"

    echoContent green "\n ---> $(t EXT_NODE_ADDED): ${nodeName}"
    echoContent yellow " ---> ID: ${nodeId}"
}

# 手动添加 SOCKS5 节点
addExternalNodeSOCKS() {
    echoContent skyBlue "\n$(t EXT_ADD_SOCKS)"
    echoContent red "=============================================================="

    # 服务器地址
    read -r -p "$(t EXT_INPUT_SERVER): " server
    if [[ -z "${server}" ]]; then
        echoContent red " ---> $(t EXT_SERVER_REQUIRED)"
        return 1
    fi

    # 端口
    read -r -p "$(t EXT_INPUT_PORT): " port
    if [[ -z "${port}" || ! "${port}" =~ ^[0-9]+$ ]]; then
        echoContent red " ---> $(t EXT_PORT_INVALID)"
        return 1
    fi

    # 用户名 (可选)
    read -r -p "$(t EXT_INPUT_USERNAME) ($(t OPTIONAL)): " username

    # 密码 (可选)
    local password=""
    if [[ -n "${username}" ]]; then
        read -r -p "$(t EXT_INPUT_PASSWORD): " password
    fi

    # 节点名称
    read -r -p "$(t EXT_INPUT_NAME) [SOCKS5-${server}]: " nodeName
    if [[ -z "${nodeName}" ]]; then
        nodeName="SOCKS5-${server}"
    fi

    # 生成节点JSON
    local nodeId
    nodeId=$(generateNodeId)
    local nodeJson

    if [[ -n "${username}" ]]; then
        nodeJson=$(jq -n \
            --arg id "${nodeId}" \
            --arg name "${nodeName}" \
            --arg server "${server}" \
            --argjson server_port "${port}" \
            --arg username "${username}" \
            --arg password "${password}" \
            --arg created_at "$(date -Iseconds)" \
            '{id: $id, name: $name, type: "socks", server: $server, server_port: $server_port, version: "5", username: $username, password: $password, enabled: true, created_at: $created_at}')
    else
        nodeJson=$(jq -n \
            --arg id "${nodeId}" \
            --arg name "${nodeName}" \
            --arg server "${server}" \
            --argjson server_port "${port}" \
            --arg created_at "$(date -Iseconds)" \
            '{id: $id, name: $name, type: "socks", server: $server, server_port: $server_port, version: "5", enabled: true, created_at: $created_at}')
    fi

    # 添加到配置文件
    addExternalNodeToFile "${nodeJson}"

    echoContent green "\n ---> $(t EXT_NODE_ADDED): ${nodeName}"
    echoContent yellow " ---> ID: ${nodeId}"
}

# 手动添加 Trojan 节点
addExternalNodeTrojan() {
    echoContent skyBlue "\n$(t EXT_ADD_TROJAN)"
    echoContent red "=============================================================="

    # 服务器地址
    read -r -p "$(t EXT_INPUT_SERVER): " server
    if [[ -z "${server}" ]]; then
        echoContent red " ---> $(t EXT_SERVER_REQUIRED)"
        return 1
    fi

    # 端口
    read -r -p "$(t EXT_INPUT_PORT) [443]: " port
    if [[ -z "${port}" ]]; then
        port=443
    fi
    if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
        echoContent red " ---> $(t EXT_PORT_INVALID)"
        return 1
    fi

    # 密码
    read -r -p "$(t EXT_INPUT_PASSWORD): " password
    if [[ -z "${password}" ]]; then
        echoContent red " ---> $(t EXT_PASSWORD_REQUIRED)"
        return 1
    fi

    # SNI (可选)
    read -r -p "$(t EXT_INPUT_SNI) [${server}]: " sni
    if [[ -z "${sni}" ]]; then
        sni="${server}"
    fi

    # 是否跳过证书验证
    echoContent yellow "\n$(t EXT_SKIP_CERT_VERIFY)?"
    echoContent yellow "  1. $(t NO) ($(t RECOMMENDED))"
    echoContent yellow "  2. $(t YES)"
    read -r -p "$(t PROMPT_SELECT) [1]: " insecureChoice
    local insecure="false"
    if [[ "${insecureChoice}" == "2" ]]; then
        insecure="true"
    fi

    # 节点名称
    read -r -p "$(t EXT_INPUT_NAME) [Trojan-${server}]: " nodeName
    if [[ -z "${nodeName}" ]]; then
        nodeName="Trojan-${server}"
    fi

    # 生成节点JSON
    local nodeId
    nodeId=$(generateNodeId)
    local nodeJson
    nodeJson=$(jq -n \
        --arg id "${nodeId}" \
        --arg name "${nodeName}" \
        --arg server "${server}" \
        --argjson server_port "${port}" \
        --arg password "${password}" \
        --arg sni "${sni}" \
        --argjson insecure "${insecure}" \
        --arg created_at "$(date -Iseconds)" \
        '{id: $id, name: $name, type: "trojan", server: $server, server_port: $server_port, password: $password, tls: {enabled: true, server_name: $sni, insecure: $insecure, alpn: ["h2", "http/1.1"]}, enabled: true, created_at: $created_at}')

    # 添加到配置文件
    addExternalNodeToFile "${nodeJson}"

    echoContent green "\n ---> $(t EXT_NODE_ADDED): ${nodeName}"
    echoContent yellow " ---> ID: ${nodeId}"
}

# 兼容 url-safe (RFC 4648 §5) 与 standard (§4) 两种 base64 字母表 + 自动补 padding。
# 多数 SS 客户端导出链接采用 url-safe 编码（用 -_ 替代 +/，且常省略 =）；
# GNU coreutils base64 默认只接受 standard 字母表 + 严格 padding，url-safe 输入会失败。
_linkBase64Decode() {
    local s="$1"
    # url-safe → standard
    s="${s//-/+}"
    s="${s//_//}"
    # 补齐 padding 到 4 的倍数
    local pad=$(( (4 - ${#s} % 4) % 4 ))
    while ((pad > 0)); do
        s="${s}="
        ((pad--))
    done
    printf '%s' "${s}" | base64 -d 2>/dev/null
}

# _linkPercentDecode S → 百分号解码。带反斜杠的原样返回：%b 会把它当转义，链接内容不可信
_linkPercentDecode() {
    if [[ "$1" != *\\* ]]; then
        printf '%b' "${1//%/\\x}"
    else
        printf '%s' "$1"
    fi
}

# 解析 SS 链接
parseSSLink() {
    local link="$1"

    # 移除 ss:// 前缀
    link="${link#ss://}"

    # 分离名称 (# 后面的部分)
    local name=""
    if [[ "${link}" == *"#"* ]]; then
        name=$(echo "${link}" | sed 's/.*#//' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "${link##*#}")
        link="${link%%#*}"
    fi

    # 分离服务器和端口
    local serverPart=""
    local userInfo=""

    if [[ "${link}" == *"@"* ]]; then
        userInfo="${link%%@*}"
        serverPart="${link#*@}"
    else
        # 整个是 base64 编码的（兼容 url-safe / standard 两种字母表）
        local decoded
        decoded=$(_linkBase64Decode "${link}")
        if [[ -n "${decoded}" && "${decoded}" == *"@"* ]]; then
            userInfo="${decoded%%@*}"
            serverPart="${decoded#*@}"
        else
            echo ""
            return 1
        fi
    fi

    # 解析 userInfo (可能是 base64 编码的 method:password)
    local method=""
    local password=""

    # SIP022（2022-blake3-*）的 userinfo 不做 base64，是百分号编码的 method:password；base64 字母表里没有 : 和 %，
    # 带这两个字符的先按明文解码，不然 base64 解出乱码，或者 %2F 原样进了密码，认证必然失败
    local decodedUser
    if [[ "${userInfo}" == *":"* || "${userInfo}" == *"%"* ]]; then
        decodedUser=$(_linkPercentDecode "${userInfo}")
    else
        decodedUser=$(_linkBase64Decode "${userInfo}")
    fi
    if [[ -n "${decodedUser}" && "${decodedUser}" == *":"* ]]; then
        method="${decodedUser%%:*}"
        password="${decodedUser#*:}"
    else
        echo ""
        return 1
    fi

    # 分离服务器和端口（处理可能的查询参数）
    serverPart="${serverPart%%\?*}"
    serverPart="${serverPart%%/*}"

    local server="${serverPart%%:*}"
    local port="${serverPart##*:}"

    if [[ -z "${server}" || -z "${port}" || -z "${method}" ]] || ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        echo ""
        return 1
    fi

    # 如果没有名称，使用服务器地址
    if [[ -z "${name}" ]]; then
        name="SS-${server}"
    fi

    # 输出 JSON
    jq -n \
        --arg name "${name}" \
        --arg server "${server}" \
        --argjson server_port "${port}" \
        --arg method "${method}" \
        --arg password "${password}" \
        '{name: $name, type: "shadowsocks", server: $server, server_port: $server_port, method: $method, password: $password}'
}

# 解析 Trojan 链接
parseTrojanLink() {
    local link="$1"

    # 移除 trojan:// 前缀
    link="${link#trojan://}"

    # 分离名称
    local name=""
    if [[ "${link}" == *"#"* ]]; then
        name=$(echo "${link}" | sed 's/.*#//' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "${link##*#}")
        link="${link%%#*}"
    fi

    # 分离参数
    local params=""
    if [[ "${link}" == *"?"* ]]; then
        params="${link#*\?}"
        link="${link%%\?*}"
    fi

    # 解析密码和服务器
    local password="${link%%@*}"
    local serverPart="${link#*@}"

    local server="${serverPart%%:*}"
    local port="${serverPart##*:}"

    # 解析参数
    local sni="${server}"
    local insecure="false"

    if [[ -n "${params}" ]]; then
        # 解析 sni/peer/host
        # 用纯 bash 参数展开提取，避免 grep -oP（Alpine/BusyBox grep 不支持 -P/\K，
        # 会让 sni 解析失败、server_name 变空）。与本仓库别处（如 parseChainCode）一致。
        if [[ "${params}" == *"sni="* ]]; then
            sni="${params#*sni=}"
            sni="${sni%%&*}"
        elif [[ "${params}" == *"peer="* ]]; then
            sni="${params#*peer=}"
            sni="${sni%%&*}"
        fi

        # 解析 allowInsecure
        if [[ "${params}" == *"allowInsecure=1"* || "${params}" == *"allowInsecure=true"* ]]; then
            insecure="true"
        fi
    fi

    if [[ -z "${server}" || -z "${port}" || -z "${password}" ]] || ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        echo ""
        return 1
    fi

    if [[ -z "${name}" ]]; then
        name="Trojan-${server}"
    fi

    jq -n \
        --arg name "${name}" \
        --arg server "${server}" \
        --argjson server_port "${port}" \
        --arg password "${password}" \
        --arg sni "${sni}" \
        --argjson insecure "${insecure}" \
        '{name: $name, type: "trojan", server: $server, server_port: $server_port, password: $password, tls: {enabled: true, server_name: $sni, insecure: $insecure, alpn: ["h2", "http/1.1"]}}'
}

# 解析 SOCKS5 链接
parseSOCKS5Link() {
    local link="$1"

    # 移除 socks5:// 或 socks:// 前缀
    link="${link#socks5://}"
    link="${link#socks://}"

    # 分离名称
    local name=""
    if [[ "${link}" == *"#"* ]]; then
        name=$(echo "${link}" | sed 's/.*#//' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "${link##*#}")
        link="${link%%#*}"
    fi

    local username=""
    local password=""
    local serverPart=""

    if [[ "${link}" == *"@"* ]]; then
        local userInfo="${link%%@*}"
        serverPart="${link#*@}"

        if [[ "${userInfo}" == *":"* ]]; then
            username="${userInfo%%:*}"
            password="${userInfo#*:}"
        fi
    else
        serverPart="${link}"
    fi

    local server="${serverPart%%:*}"
    local port="${serverPart##*:}"

    if [[ -z "${server}" || -z "${port}" ]] || ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        echo ""
        return 1
    fi

    if [[ -z "${name}" ]]; then
        name="SOCKS5-${server}"
    fi

    if [[ -n "${username}" ]]; then
        jq -n \
            --arg name "${name}" \
            --arg server "${server}" \
            --argjson server_port "${port}" \
            --arg username "${username}" \
            --arg password "${password}" \
            '{name: $name, type: "socks", server: $server, server_port: $server_port, version: "5", username: $username, password: $password}'
    else
        jq -n \
            --arg name "${name}" \
            --arg server "${server}" \
            --argjson server_port "${port}" \
            '{name: $name, type: "socks", server: $server, server_port: $server_port, version: "5"}'
    fi
}

# _linkQueryGet QUERY KEY → 按整个键名取查询参数并解码，没有就打印空串
_linkQueryGet() {
    local pair
    while IFS= read -r -d '&' pair; do
        if [[ "${pair%%=*}" == "$2" ]]; then
            _linkPercentDecode "${pair#*=}"
            return 0
        fi
    done <<<"$1&"
}

# _linkRefuse FIELD VALUE → 说明这个节点用不了，返回 1。走 stderr：调用方用 $() 只收节点 JSON
_linkRefuse() {
    echoContent red " ---> $(t EXT_LINK_REFUSED "$1" "$2")" >&2
    return 1
}

# _linkCheckEndpoint HOST PORT → 地址与端口都合法返回 0。端口不收前导零：后面 --argjson 按 JSON 数字解析
_linkCheckEndpoint() {
    if ! isValidDomain "$1" && ! isValidIP "$1"; then
        _linkRefuse server "$1"
        return 1
    fi
    if [[ ! "$2" =~ ^[1-9][0-9]{0,4}$ ]] || (($2 > 65535)); then
        _linkRefuse port "$2"
        return 1
    fi
}

# _linkTlsJson SECURITY SNI FP ALPN INSECURE PBK SID → sing-box 的 tls 对象，不加密打印 null。INSECURE 是 true / false。
# 指纹不在 sing-box 的列表里就拒：写进片段后合并失败，整个 sing-box 起不来；Reality 要 uTLS，没给指纹用 chrome
_linkTlsJson() {
    local fp=$3
    case "$1" in
    "" | none)
        echo null
        return 0
        ;;
    tls | reality) ;;
    *)
        _linkRefuse security "$1"
        return 1
        ;;
    esac
    case "${fp}" in
    "" | chrome | firefox | edge | safari | 360 | qq | ios | android | random | randomized) ;;
    *)
        _linkRefuse fp "${fp}"
        return 1
        ;;
    esac
    if [[ "$1" == "reality" ]]; then
        if [[ -z "$6" ]]; then
            _linkRefuse pbk ""
            return 1
        fi
        fp=${fp:-chrome}
    fi
    jq -cn --arg security "$1" --arg sni "$2" --arg fp "${fp}" --arg alpn "$4" --argjson insecure "$5" --arg pbk "$6" --arg sid "$7" '
        {enabled: true, server_name: $sni}
        + (if $insecure and $security == "tls" then {insecure: true} else {} end)
        + (if $alpn == "" then {} else {alpn: ($alpn | split(","))} end)
        + (if $fp == "" then {} else {utls: {enabled: true, fingerprint: $fp}} end)
        + (if $security == "reality" then {reality: {enabled: true, public_key: $pbk, short_id: $sid}} else {} end)'
}

# _linkTransportJson NET PATH HOST SERVICE → sing-box 的 transport 对象，裸 TCP 打印 null；sing-box 没有的传输（XHTTP、mKCP 等）拒绝
_linkTransportJson() {
    case "$1" in
    "" | tcp | raw) echo null ;;
    ws) jq -cn --arg p "${2:-/}" --arg h "$3" '{type: "ws", path: $p} + (if $h == "" then {} else {headers: {Host: $h}} end)' ;;
    httpupgrade) jq -cn --arg p "${2:-/}" --arg h "$3" '{type: "httpupgrade", path: $p} + (if $h == "" then {} else {host: $h} end)' ;;
    grpc) jq -cn --arg s "$4" '{type: "grpc", service_name: $s}' ;;
    *) _linkRefuse type "$1" ;;
    esac
}

# parseVlessLink LINK → 节点 JSON，字段形状就是 sing-box 出站。sing-box 连不了的节点在这里拒，留到合并时整个 sing-box 都起不来
parseVlessLink() {
    local link=${1#vless://} name= query= uuid hostPort host port
    if [[ "${link}" == *"#"* ]]; then
        name=$(_linkPercentDecode "${link##*#}")
        link=${link%%#*}
    fi
    if [[ "${link}" == *"?"* ]]; then
        query=${link#*\?}
        link=${link%%\?*}
    fi
    uuid=${link%%@*}
    hostPort=${link#*@}
    hostPort=${hostPort%/}
    if [[ "${hostPort}" == \[* ]]; then
        host=${hostPort%%]*}
        host=${host#\[}
    else
        host=${hostPort%%:*}
    fi
    port=${hostPort##*:}
    if [[ ! "${uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        _linkRefuse uuid "${uuid}"
        return 1
    fi
    _linkCheckEndpoint "${host}" "${port}" || return 1

    local encryption flow headerType hostHeader insecure=false tls transport value
    encryption=$(_linkQueryGet "${query}" encryption)
    if [[ -n "${encryption}" && "${encryption}" != "none" ]]; then
        _linkRefuse encryption "${encryption}"
        return 1
    fi
    flow=$(_linkQueryGet "${query}" flow)
    if [[ -n "${flow}" && "${flow}" != "xtls-rprx-vision" ]]; then
        _linkRefuse flow "${flow}"
        return 1
    fi
    headerType=$(_linkQueryGet "${query}" headerType)
    if [[ -n "${headerType}" && "${headerType}" != "none" ]]; then
        _linkRefuse headerType "${headerType}"
        return 1
    fi
    hostHeader=$(_linkQueryGet "${query}" host)
    for value in "$(_linkQueryGet "${query}" allowInsecure)" "$(_linkQueryGet "${query}" insecure)"; do
        [[ "${value}" == "1" || "${value}" == "true" ]] && insecure=true
    done
    value=$(_linkQueryGet "${query}" sni)
    tls=$(_linkTlsJson "$(_linkQueryGet "${query}" security)" "${value:-${hostHeader:-${host}}}" "$(_linkQueryGet "${query}" fp)" \
        "$(_linkQueryGet "${query}" alpn)" "${insecure}" "$(_linkQueryGet "${query}" pbk)" "$(_linkQueryGet "${query}" sid)") || return 1
    transport=$(_linkTransportJson "$(_linkQueryGet "${query}" type)" "$(_linkQueryGet "${query}" path)" "${hostHeader}" "$(_linkQueryGet "${query}" serviceName)") || return 1

    jq -n --arg name "${name:-VLESS-${host}}" --arg server "${host}" --argjson port "${port}" --arg uuid "${uuid}" --arg flow "${flow}" \
        --argjson tls "${tls}" --argjson transport "${transport}" '
        {name: $name, type: "vless", server: $server, server_port: $port, uuid: $uuid}
        + (if $flow == "" then {} else {flow: $flow} end)
        + (if $tls == null then {} else {tls: $tls} end)
        + (if $transport == null then {} else {transport: $transport} end)'
}

# _vmessField JSON KEY → 取 vmess 链接里的字段：各家把端口、aid 写成数字或字符串都有，一律转成字符串，没有打印空串
_vmessField() {
    jq -r --arg k "$2" '(.[$k] // "") | tostring' <<<"$1"
}

# parseVmessLink LINK → 节点 JSON，同 parseVlessLink。UDP 用 xudp：packetaddr 只有 sing-box 服务端认，Xray 上 UDP 全丢
parseVmessLink() {
    local json
    json=$(_linkBase64Decode "${1#vmess://}")
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"${json}"; then
        return 1
    fi

    local name host port uuid alterId security headerType hostHeader insecure=false tls transport value
    name=$(_vmessField "${json}" ps)
    host=$(_vmessField "${json}" add)
    port=$(_vmessField "${json}" port)
    uuid=$(_vmessField "${json}" id)
    if [[ ! "${uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        _linkRefuse id "${uuid}"
        return 1
    fi
    _linkCheckEndpoint "${host}" "${port}" || return 1
    alterId=$(_vmessField "${json}" aid)
    if [[ ! "${alterId:-0}" =~ ^[0-9]{1,5}$ ]]; then
        _linkRefuse aid "${alterId}"
        return 1
    fi
    security=$(_vmessField "${json}" scy)
    case "${security}" in
    "" | auto | none | zero | aes-128-gcm | chacha20-poly1305 | aes-128-ctr) ;;
    *)
        _linkRefuse scy "${security}"
        return 1
        ;;
    esac
    headerType=$(_vmessField "${json}" type)
    if [[ -n "${headerType}" && "${headerType}" != "none" ]]; then
        _linkRefuse type "${headerType}"
        return 1
    fi
    hostHeader=$(_vmessField "${json}" host)
    value=$(_vmessField "${json}" allowInsecure)
    [[ "${value}" == "1" || "${value}" == "true" ]] && insecure=true
    value=$(_vmessField "${json}" sni)
    tls=$(_linkTlsJson "$(_vmessField "${json}" tls)" "${value:-${hostHeader:-${host}}}" "$(_vmessField "${json}" fp)" "$(_vmessField "${json}" alpn)" "${insecure}" "" "") || return 1
    transport=$(_linkTransportJson "$(_vmessField "${json}" net)" "$(_vmessField "${json}" path)" "${hostHeader}" "$(_vmessField "${json}" path)") || return 1

    jq -n --arg name "${name:-VMess-${host}}" --arg server "${host}" --argjson port "${port}" --arg uuid "${uuid}" --argjson alterId "$((10#${alterId:-0}))" \
        --arg security "${security}" --argjson tls "${tls}" --argjson transport "${transport}" '
        {name: $name, type: "vmess", server: $server, server_port: $port, uuid: $uuid, packet_encoding: "xudp"}
        + (if $alterId == 0 then {} else {alter_id: $alterId} end)
        + (if $security == "" then {} else {security: $security} end)
        + (if $tls == null then {} else {tls: $tls} end)
        + (if $transport == null then {} else {transport: $transport} end)'
}

# 通过链接添加外部节点
addExternalNodeByLink() {
    echoContent skyBlue "\n$(t EXT_ADD_BY_LINK)"
    echoContent red "=============================================================="
    echoContent yellow "$(t EXT_SUPPORTED_LINKS):"
    echoContent yellow "  - ss://..."
    echoContent yellow "  - trojan://..."
    echoContent yellow "  - socks5://..."
    echoContent yellow "  - vless://..."
    echoContent yellow "  - vmess://...\n"

    read -r -p "$(t EXT_PASTE_LINK): " link

    if [[ -z "${link}" ]]; then
        echoContent red " ---> $(t EXT_LINK_EMPTY)"
        return 1
    fi

    local nodeJson=""
    local nodeType=""

    if [[ "${link}" == ss://* ]]; then
        nodeType="Shadowsocks"
        nodeJson=$(parseSSLink "${link}")
    elif [[ "${link}" == trojan://* ]]; then
        nodeType="Trojan"
        nodeJson=$(parseTrojanLink "${link}")
    elif [[ "${link}" == socks5://* || "${link}" == socks://* ]]; then
        nodeType="SOCKS5"
        nodeJson=$(parseSOCKS5Link "${link}")
    elif [[ "${link}" == vless://* ]]; then
        nodeType="VLESS"
        nodeJson=$(parseVlessLink "${link}")
    elif [[ "${link}" == vmess://* ]]; then
        nodeType="VMess"
        nodeJson=$(parseVmessLink "${link}")
    else
        echoContent red " ---> $(t EXT_LINK_UNSUPPORTED)"
        return 1
    fi

    if [[ -z "${nodeJson}" ]]; then
        echoContent red " ---> $(t EXT_LINK_PARSE_FAILED)"
        return 1
    fi

    # 显示解析结果
    echoContent green "\n$(t EXT_PARSE_RESULT):"
    echoContent yellow "  $(t EXT_PROTOCOL): ${nodeType}"
    echoContent yellow "  $(t EXT_SERVER): $(echo "${nodeJson}" | jq -r '.server')"
    echoContent yellow "  $(t EXT_PORT): $(echo "${nodeJson}" | jq -r '.server_port')"
    echoContent yellow "  $(t EXT_NAME): $(echo "${nodeJson}" | jq -r '.name')"
    if jq -e '.tls.reality.enabled == true' >/dev/null 2>&1 <<<"${nodeJson}"; then
        echoContent yellow "  $(t EXT_REALITY_NOTE)"
    fi

    echo
    read -r -p "$(t EXT_CONFIRM_ADD)? [y/n]: " confirmAdd
    if ! isYesInput "${confirmAdd}"; then
        echoContent yellow " ---> $(t CANCEL)"
        return 0
    fi

    # 添加节点ID和时间戳
    local nodeId
    nodeId=$(generateNodeId)
    nodeJson=$(echo "${nodeJson}" | jq --arg id "${nodeId}" --arg time "$(date -Iseconds)" '. + {id: $id, enabled: true, created_at: $time}')

    addExternalNodeToFile "${nodeJson}"

    local nodeName
    nodeName=$(echo "${nodeJson}" | jq -r '.name')
    echoContent green "\n ---> $(t EXT_NODE_ADDED): ${nodeName}"
}

# 显示外部节点列表
listExternalNodes() {
    initExternalNodeFile

    echoContent skyBlue "\n$(t EXT_NODE_LIST)"
    echoContent red "=============================================================="

    local nodeCount
    nodeCount=$(getExternalNodeCount)

    if [[ "${nodeCount}" == "0" ]]; then
        echoContent yellow "  ($(t EXT_NO_NODES))"
        return
    fi

    local index=1
    while IFS= read -r node; do
        local name type server port enabled
        name=$(echo "${node}" | jq -r '.name')
        type=$(echo "${node}" | jq -r '.type')
        server=$(echo "${node}" | jq -r '.server')
        port=$(echo "${node}" | jq -r '.server_port')
        enabled=$(echo "${node}" | jq -r '.enabled')

        local typeLabel=""
        case "${type}" in
            "shadowsocks") typeLabel="SS" ;;
            "socks") typeLabel="SOCKS5" ;;
            "trojan") typeLabel="Trojan" ;;
            "vless") typeLabel="VLESS" ;;
            "vmess") typeLabel="VMess" ;;
            *) typeLabel="${type}" ;;
        esac

        local status=""
        if [[ "${enabled}" == "false" ]]; then
            status=" [$(t DISABLED)]"
        fi

        echoContent yellow "  ${index}. [${typeLabel}] ${name} (${server}:${port})${status}"
        ((index++))
    done < <(jq -c '.nodes[]' "${EXTERNAL_NODE_FILE}" 2>/dev/null)
}

# 删除外部节点
# externalNodeUsers ID → 引用这个外部节点的链路名，逗号分隔；配成唯一出口（external_single）的算一条
externalNodeUsers() {
    local names=""
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        names=$(jq -r --arg id "$1" '[.chains[]? | select(.external_node_id == $id) | .name] | join(", ")' "${CHAIN_MULTI_INFO}") || return 1
    fi
    if [[ -f "${CHAIN_ENTRY_INFO}" ]] && jq -e --arg id "$1" '.mode == "external_single" and .external_node_id == $id' "${CHAIN_ENTRY_INFO}" >/dev/null 2>&1; then
        names="${names:+${names}, }$(t EXT_SINGLE_EXIT_LABEL)"
    fi
    printf '%s' "${names}"
}

deleteExternalNode() {
    listExternalNodes

    local nodeCount
    nodeCount=$(getExternalNodeCount)

    if [[ "${nodeCount}" == "0" ]]; then
        return
    fi

    echoContent red "=============================================================="
    read -r -p "$(t EXT_SELECT_DELETE): " selectIndex

    if [[ -z "${selectIndex}" || "${selectIndex}" == "0" ]]; then
        return
    fi

    # 获取节点ID
    local nodeId
    nodeId=$(jq -r --argjson idx "$((selectIndex-1))" '.nodes[$idx].id' "${EXTERNAL_NODE_FILE}" 2>/dev/null)

    if [[ -z "${nodeId}" || "${nodeId}" == "null" ]]; then
        echoContent red " ---> $(t EXT_INVALID_SELECTION)"
        return 1
    fi

    local nodeName
    nodeName=$(jq -r --argjson idx "$((selectIndex-1))" '.nodes[$idx].name' "${EXTERNAL_NODE_FILE}" 2>/dev/null)

    # 还有链路在用它就不删：链路的出站里抄着它的凭据，删了节点那条链路照样走，只是再也看不见、改不动
    local users
    users=$(externalNodeUsers "${nodeId}") || return 1
    if [[ -n "${users}" ]]; then
        echoContent red " ---> $(t EXT_NODE_IN_USE "${nodeName}" "${users}")"
        return 1
    fi

    read -r -p "$(t EXT_CONFIRM_DELETE) [${nodeName}]? [y/n]: " confirmDelete
    if ! isYesInput "${confirmDelete}"; then
        return
    fi

    removeExternalNodeFromFile "${nodeId}"
    echoContent green " ---> $(t EXT_NODE_DELETED): ${nodeName}"
}

# 生成外部节点的 sing-box 出站配置
generateExternalOutboundConfig() {
    local nodeId="$1"
    local tag="$2"

    local node
    node=$(getExternalNodeById "${nodeId}")

    if [[ -z "${node}" ]]; then
        return 1
    fi

    local type
    type=$(echo "${node}" | jq -r '.type')

    # 全部走 jq -n 构造，避免 server / password / username 等用户输入字段含 " 或 \
    # 时破坏 JSON。tag 已被上游 validateChainName 限制字符集，但保持一致性也走 --arg。
    case "${type}" in
        "shadowsocks")
            local server port method password
            server=$(echo "${node}" | jq -r '.server')
            port=$(echo "${node}" | jq -r '.server_port')
            method=$(echo "${node}" | jq -r '.method')
            password=$(echo "${node}" | jq -r '.password')
            # 旧版手动添加的节点 method 里是整段菜单：写进片段后每次合并都失败，sing-box 一重启就起不来，在这里拦下
            if [[ "${method}" =~ [[:space:]] ]]; then
                echoContent red " ---> $(t EXT_NODE_METHOD_INVALID "$(echo "${node}" | jq -r '.name')")" >&2
                return 1
            fi

            jq -n \
                --arg tag "${tag}" \
                --arg server "${server}" \
                --argjson port "${port}" \
                --arg method "${method}" \
                --arg password "${password}" \
                '{
                    type: "shadowsocks",
                    tag: $tag,
                    server: $server,
                    server_port: $port,
                    method: $method,
                    password: $password
                }'
            ;;
        "socks")
            local server port username password
            server=$(echo "${node}" | jq -r '.server')
            port=$(echo "${node}" | jq -r '.server_port')
            username=$(echo "${node}" | jq -r '.username // empty')
            password=$(echo "${node}" | jq -r '.password // empty')

            if [[ -n "${username}" ]]; then
                jq -n \
                    --arg tag "${tag}" \
                    --arg server "${server}" \
                    --argjson port "${port}" \
                    --arg username "${username}" \
                    --arg password "${password}" \
                    '{
                        type: "socks",
                        tag: $tag,
                        server: $server,
                        server_port: $port,
                        version: "5",
                        username: $username,
                        password: $password
                    }'
            else
                jq -n \
                    --arg tag "${tag}" \
                    --arg server "${server}" \
                    --argjson port "${port}" \
                    '{
                        type: "socks",
                        tag: $tag,
                        server: $server,
                        server_port: $port,
                        version: "5"
                    }'
            fi
            ;;
        "trojan")
            local server port password tlsConfig
            server=$(echo "${node}" | jq -r '.server')
            port=$(echo "${node}" | jq -r '.server_port')
            password=$(echo "${node}" | jq -r '.password')
            # 默认 tls 对象通过 --arg sn 注入 server，避免老写法 '.tls // {"server_name":"'${server}'"}'
            # 在 server 含 " 时把 jq 过滤器自身打成无效语法。
            tlsConfig=$(echo "${node}" | jq -c --arg sn "${server}" '.tls // {enabled: true, server_name: $sn, insecure: false}')

            jq -n \
                --arg tag "${tag}" \
                --arg server "${server}" \
                --argjson port "${port}" \
                --arg password "${password}" \
                --argjson tls "${tlsConfig}" \
                '{
                    type: "trojan",
                    tag: $tag,
                    server: $server,
                    server_port: $port,
                    password: $password,
                    tls: $tls
                }'
            ;;
        "vless" | "vmess")
            # 节点是按 sing-box 出站的形状存的，这里只挑出站字段：id、name、enabled 这些 sing-box 不认，合并会失败
            jq --arg tag "${tag}" '{type, tag: $tag, server, server_port, uuid}
                + with_entries(select(.key as $k | ["flow", "security", "alter_id", "packet_encoding", "tls", "transport"] | index($k)))' <<<"${node}"
            ;;
    esac
}

# chainExternalSingleOnXray → Xray 内核上留着外部节点唯一出口（旧版配得出来）：Xray 的流量没经过它，一直从本机直出
chainExternalSingleOnXray() {
    [[ "${coreKind}" == "1" && -f "${CHAIN_ENTRY_INFO}" ]] &&
        [[ "$(jq -r '.mode // ""' "${CHAIN_ENTRY_INFO}" 2>/dev/null)" == "external_single" ]]
}

# 将外部节点设置为链式代理出口（单出口模式）。只写 sing-box 片段，Xray 的流量到不了这里，所以 Xray 内核上拒绝：
# 接了只会报成功、流量照样从本机出去。Xray 机器用多链路接外部节点，那条路有桥、也改 Xray 路由
setupExternalAsSingleExit() {
    if [[ "${coreKind}" == "1" ]]; then
        echoContent red "\n ---> $(t EXT_SINGLE_EXIT_XRAY_REFUSED)"
        return 1
    fi

    listExternalNodes

    local nodeCount
    nodeCount=$(getExternalNodeCount)

    if [[ "${nodeCount}" == "0" ]]; then
        echoContent red "\n ---> $(t EXT_ADD_NODE_FIRST)"
        return 1
    fi

    echoContent red "=============================================================="
    read -r -p "$(t EXT_SELECT_AS_EXIT): " selectIndex

    if [[ -z "${selectIndex}" || "${selectIndex}" == "0" ]]; then
        return
    fi

    # 获取节点信息
    local nodeId nodeName
    nodeId=$(jq -r --argjson idx "$((selectIndex-1))" '.nodes[$idx].id' "${EXTERNAL_NODE_FILE}" 2>/dev/null)
    nodeName=$(jq -r --argjson idx "$((selectIndex-1))" '.nodes[$idx].name' "${EXTERNAL_NODE_FILE}" 2>/dev/null)

    if [[ -z "${nodeId}" || "${nodeId}" == "null" ]]; then
        echoContent red " ---> $(t EXT_INVALID_SELECTION)"
        return 1
    fi

    echoContent yellow "\n$(t EXT_CONFIGURING): ${nodeName}"

    # chain_route.json 的 default_domain_resolver 引用 01_dns.json 的 google tag，
    # 该文件只有 ensureSingBoxInstalled 会创建——纯 sing-box 安装没有它，缺了 1.13 起启动即 FATAL
    if ! ensureSingBoxInstalled; then
        return 1
    fi

    # 生成出站配置
    local outboundConfig
    outboundConfig=$(generateExternalOutboundConfig "${nodeId}" "chain_external_outbound")

    if [[ -z "${outboundConfig}" ]]; then
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi

    # 保存出站配置（jq -n 包装，不做字符串拼接，避免 outboundConfig 内部含特殊字符破坏 JSON）
    local configDir="${SINGBOX_FRAGMENT_DIR}"
    mkdir -p "${configDir}"

    local _wrapped
    if ! _wrapped=$(jq -n --argjson ob "${outboundConfig}" '{outbounds: [$ob]}') || [[ -z "${_wrapped}" ]]; then
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi

    # 合并失败要还原：写坏的片段留着，此后每次合并都失败，sing-box 一重启就起不来
    if ! jsonTxBegin; then
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi
    if ! jsonTxTrack "${configDir}/chain_outbound.json" || ! jsonTxTrack "${configDir}/chain_route.json" || ! jsonTxTrack "${CHAIN_ENTRY_INFO}"; then
        jsonTxRollback
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi
    printf '%s\n' "${_wrapped}" > "${configDir}/chain_outbound.json"

    # 生成路由配置 - 所有流量走外部节点
    # default_domain_resolver 见 chainExit 注释，1.13 起必填
    jq -n '{route: {rules: [], final: "chain_external_outbound", default_domain_resolver: "google"}}' \
        >"${configDir}/chain_route.json"

    # 保存外部节点入口信息（原子写入）。节点名来自用户输入，走 --arg，带引号也不会写坏状态文件
    local __chainEntryInfo
    __chainEntryInfo=$(jq -n --arg id "${nodeId}" --arg name "${nodeName}" \
        '{schema_version: 1, role: "entry", mode: "external_single", external_node_id: $id, external_node_name: $name}')
    if ! writeChainInfoAtomic "${CHAIN_ENTRY_INFO}" "${__chainEntryInfo}"; then
        jsonTxRollback
        return 1
    fi

    # 合并配置
    if ! singBoxMergeConfig; then
        jsonTxRollback
        return 1
    fi
    jsonTxCommit

    # 重启服务
    reloadCore

    echoContent green "\n ---> $(t EXT_CONFIG_SUCCESS)"
    echoContent yellow " ---> $(t EXT_TRAFFIC_ROUTE): $(t USER) → $(t ENTRY_NODE) → ${nodeName} → $(t INTERNET)"
}

# 测试外部节点连通性
testExternalNodeConnection() {
    listExternalNodes

    local nodeCount
    nodeCount=$(getExternalNodeCount)

    if [[ "${nodeCount}" == "0" ]]; then
        return
    fi

    echoContent red "=============================================================="
    read -r -p "$(t EXT_SELECT_TEST): " selectIndex

    if [[ -z "${selectIndex}" || "${selectIndex}" == "0" ]]; then
        return
    fi

    local node
    node=$(jq -c --argjson idx "$((selectIndex-1))" '.nodes[$idx]' "${EXTERNAL_NODE_FILE}" 2>/dev/null)

    if [[ -z "${node}" || "${node}" == "null" ]]; then
        echoContent red " ---> $(t EXT_INVALID_SELECTION)"
        return 1
    fi

    local server port nodeName
    server=$(echo "${node}" | jq -r '.server')
    port=$(echo "${node}" | jq -r '.server_port')
    nodeName=$(echo "${node}" | jq -r '.name')

    echoContent yellow "\n$(t EXT_TESTING): ${nodeName} (${server}:${port})"

    if ! timeout 5 bash -c "echo >/dev/tcp/${server}/${port}" 2>/dev/null; then
        echoContent red " ---> $(t EXT_TCP_FAILED)"
        return 1
    fi
    echoContent green " ---> $(t EXT_TCP_SUCCESS)"

    # 端口通不等于能用：密码或加密方式错了照样通。经这个节点真取一次出口 IP，不起常驻进程、不占端口
    if [[ ! -x "${SINGBOX_BIN}" ]]; then
        echoContent yellow " ---> $(t EXT_PROBE_NO_SINGBOX)"
        return 0
    fi
    local outbound probeConf outIP
    if ! outbound=$(generateExternalOutboundConfig "$(jq -r '.id' <<<"${node}")" probe) || [[ -z "${outbound}" ]] \
        || ! probeConf=$(mktemp); then
        echoContent red " ---> $(t EXT_CONFIG_FAILED)"
        return 1
    fi
    chmod 600 "${probeConf}"
    jq -n --argjson ob "${outbound}" '{log: {level: "error"}, dns: {servers: [{type: "local", tag: "local"}]},
        outbounds: [$ob], route: {default_domain_resolver: "local"}}' >"${probeConf}"
    # tools fetch 只要拿到响应就退出 0（不看状态码），握手或认证失败才非零；没有超时，靠 timeout 兜住
    outIP=$(timeout 15 "${SINGBOX_BIN}" tools fetch -c "${probeConf}" -o probe https://api.ipify.org 2>/dev/null)
    local rc=$?
    rm -f "${probeConf}"
    if [[ ${rc} -eq 0 && "${outIP}" =~ ^[0-9a-fA-F.:]+$ ]]; then
        echoContent green " ---> $(t EXT_PROBE_OK "${outIP}")"
    else
        echoContent red " ---> $(t EXT_PROBE_FAILED)"
    fi
}

# 外部节点管理菜单
externalNodeMenu() {
    echoContent skyBlue "\n$(t EXT_MENU_TITLE)"
    echoContent red "\n=============================================================="

    listExternalNodes

    echoContent red "=============================================================="
    echoContent yellow "\n$(t EXT_MENU_OPTIONS):"
    echoContent yellow "  1. $(t EXT_ADD_BY_LINK)"
    echoContent yellow "  2. $(t EXT_ADD_MANUAL)"
    echoContent yellow "  3. $(t EXT_DELETE_NODE)"
    echoContent yellow "  4. $(t EXT_TEST_NODE)"
    echoContent yellow "  5. $(t EXT_SET_AS_EXIT)"
    echoContent yellow "  0. $(t BACK)"

    read -r -p "$(t PROMPT_SELECT): " menuChoice

    case "${menuChoice}" in
        1)
            addExternalNodeByLink
            externalNodeMenu
            ;;
        2)
            echoContent yellow "\n$(t EXT_SELECT_PROTOCOL):"
            echoContent yellow "  1. Shadowsocks"
            echoContent yellow "  2. SOCKS5"
            echoContent yellow "  3. Trojan"
            read -r -p "$(t PROMPT_SELECT): " protocolChoice
            case "${protocolChoice}" in
                1) addExternalNodeSS ;;
                2) addExternalNodeSOCKS ;;
                3) addExternalNodeTrojan ;;
            esac
            externalNodeMenu
            ;;
        3)
            deleteExternalNode
            externalNodeMenu
            ;;
        4)
            testExternalNodeConnection
            externalNodeMenu
            ;;
        5)
            setupExternalAsSingleExit
            ;;
        0|"")
            chainProxyMenu
            ;;
        *)
            externalNodeMenu
            ;;
    esac
}

# ======================= 外部节点功能结束 =======================

# 分流工具。Xray 链式入口上拒绝：链式路由最后一条兜底接住所有流量，这里追加的规则排在它后面永远不命中，
# 下次启动还被写回的链式路由冲掉，菜单却报成功。sing-box 的分流片段排在链式路由前面，照常生效
routingToolsMenu() {
    if [[ "${coreKind}" == "1" && -f "${XRAY_CONF_DIR}/chain_outbound.json" ]]; then
        echoContent red " ---> $(t ROUTING_TOOLS_CHAIN_ENTRY_REFUSED)"
        exit 1
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : 分流工具"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 用于服务端的流量分流，可用于解锁ChatGPT、流媒体等相关内容\n"

    echoContent yellow "1.WARP分流【第三方 IPv4】"
    echoContent yellow "2.WARP分流【第三方 IPv6】"
    echoContent yellow "3.IPv6分流"
    echoContent yellow "4.DNS分流"
    echoContent yellow "5.SNI反向代理分流"

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        warpRoutingReg 1 IPv4
        ;;
    2)
        warpRoutingReg 1 IPv6
        ;;
    3)
        ipv6Routing 1
        ;;
    4)
        dnsRouting 1
        ;;
    5)
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent red "\n ---> 此功能不支持Hysteria2、Tuic"
        fi
        sniRouting 1
        ;;
    esac

}

# 设置VMess+WS+TLS【仅出站】
setVMessWSRoutingOutbounds() {
    read -r -p "请输入VMess+WS+TLS的地址:" setVMessWSTLSAddress
    echoContent red "=============================================================="
    echoContent yellow "录入示例:netflix,openai\n"
    read -r -p "请按照上面示例录入域名:" domainList

    if [[ -z ${domainList} ]]; then
        echoContent red " ---> 域名不可为空"
        setVMessWSRoutingOutbounds
    fi

    if [[ -n "${setVMessWSTLSAddress}" ]]; then
        removeXrayOutbound VMess-out

        echo
        read -r -p "请输入VMess+WS+TLS的端口:" setVMessWSTLSPort
        echo
        if [[ -z "${setVMessWSTLSPort}" ]]; then
            echoContent red " ---> 端口不可为空"
        fi

        read -r -p "请输入VMess+WS+TLS的UUID:" setVMessWSTLSUUID
        echo
        if [[ -z "${setVMessWSTLSUUID}" ]]; then
            echoContent red " ---> UUID不可为空"
        fi

        read -r -p "请输入VMess+WS+TLS的Path路径:" setVMessWSTLSPath
        echo
        if [[ -z "${setVMessWSTLSPath}" ]]; then
            echoContent red " ---> 路径不可为空"
        elif ! echo "${setVMessWSTLSPath}" | grep -q "/"; then
            setVMessWSTLSPath="/${setVMessWSTLSPath}"
        fi
        addXrayOutbound "VMess-out"
        addXrayRouting VMess-out outboundTag "${domainList}"
        reloadCore
        echoContent green " ---> 添加分流成功"
        exit 0
    fi
    echoContent red " ---> 地址不可为空"
    setVMessWSRoutingOutbounds
}

# 重启核心
# singBoxFragmentsHaveInbounds → 0=sing-box 片段目录里还有入站（链式的出口与桥、6 / 9）；没装 sing-box 或一个入站都没有返回 1。
# 片段读不懂也返回 0：交给 handleSingBox start 的合并去报错，不能当成「没东西」把它停掉
singBoxFragmentsHaveInbounds() {
    local count
    [[ -f "${SINGBOX_BIN}" ]] && compgen -G "${SINGBOX_FRAGMENT_DIR}/*.json" >/dev/null || return 1
    count=$(jq -s '[.[].inbounds[]?] | length' "${SINGBOX_FRAGMENT_DIR}"/*.json 2>/dev/null) || return 0
    [[ "${count}" -gt 0 ]]
}

# singBoxAutostart on|off → sing-box 开机自启跟着它该不该跑：旁挂停了还自启，重启后会起一个空 sing-box；
# 再配链式时 ensureSingBoxInstalled 见服务文件已在就不再 enable，所以开的那头也在这里补
singBoxAutostart() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        if [[ "$1" == "on" ]]; then
            systemctl is-enabled --quiet sing-box.service 2>/dev/null || systemctl enable sing-box.service >/dev/null 2>&1
        else
            # --now：单元可能卡在崩溃重启循环里（老版本删了二进制、留着单元），这时没有进程，handleSingBox stop 看不到它
            systemctl disable --now sing-box.service >/dev/null 2>&1
        fi
    elif [[ -f "/etc/init.d/sing-box" ]]; then
        if [[ "$1" == "on" ]]; then
            rc-update add sing-box default >/dev/null 2>&1
        else
            rc-update del sing-box default >/dev/null 2>&1
        fi
    fi
    return 0
}

reloadCore() {
    readInstallType

    if [[ "${coreKind}" == "1" ]]; then
        handleXray stop
        handleXray start
    fi
    # Xray 内核上 sing-box 是旁挂：片段里还有入站就跟着重启，一个都不剩就停掉并关掉自启——链式拆掉后不能留一条通到出口的桥
    if echo "${currentInstallProtocolType}" | grep -q ",20," || [[ "${coreKind}" == "2" || -n "${singBoxConfigPath}" ]] || singBoxFragmentsHaveInbounds; then
        handleSingBox stop
        handleSingBox start
        singBoxAutostart on
    elif [[ "${coreKind}" == "1" ]]; then
        if [[ -n $(pgrep -x "sing-box") ]]; then
            handleSingBox stop
        fi
        singBoxAutostart off
    fi
}

# dns分流
dnsRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : DNS分流"
    echoContent red "\n=============================================================="

    echoContent yellow "1.添加"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockDNS
        ;;
    2)
        removeUnlockDNS
        ;;
    esac
}

# SNI反向代理分流
sniRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 1
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : SNI反向代理分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# sing-box 侧只能填具体域名，不支持规则集。\n"

    echoContent yellow "1.添加"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockSNI
        ;;
    2)
        removeUnlockSNI
        ;;
    esac
}
# 设置SNI分流
setUnlockSNI() {
    read -r -p "请输入分流的SNI IP:" setSNIP
    if [[ -n ${setSNIP} ]]; then
        # 验证IP格式
        if ! isValidIP "${setSNIP}"; then
            echoContent red " ---> $(t ERR_IP_INVALID)"
            exit 1
        fi
        echoContent red "=============================================================="

        if [[ "${coreKind}" == 1 ]]; then
            echoContent yellow "录入示例:netflix,disney,hulu"
            read -r -p "请按照上面示例录入域名:" xrayDomainList
            local hosts={}
            while read -r domain; do
                if [[ -z "${domain}" ]]; then
                    continue
                fi
                hosts=$(echo "${hosts}" | jq -r --arg key "$(xrayDomainRuleValue "${domain}")" --arg value "${setSNIP}" '. + {($key): $value}')
            done < <(echo "${xrayDomainList}" | tr ',' '\n')
            cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "hosts":${hosts},
        "servers": [
            "8.8.8.8",
            "1.1.1.1"
        ]
    }
}
EOF
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent yellow "录入示例:www.netflix.com,www.google.com"
            read -r -p "请按照上面示例录入域名:" singboxDomainList
            local singboxDomain singboxDomains
            IFS=',' read -r -a singboxDomains <<<"${singboxDomainList}"
            for singboxDomain in "${singboxDomains[@]}"; do
                if [[ -n "${singboxDomain}" ]] && ! isValidDomain "${singboxDomain}"; then
                    echoContent red " ---> $(t ERR_DOMAIN_INVALID): ${singboxDomain}"
                    exit 1
                fi
            done
            if ! addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined"; then
                echoContent red " ---> $(t SINGBOX_DNS_SPLIT_WRITE_FAILED)"
                exit 1
            fi
        fi
        echoContent yellow " ---> SNI反向代理分流成功"
        reloadCore
        exit 0
    fi
    echoContent red " ---> SNI IP不可为空"
    exit 1
}

# 添加xray dns 配置
addXrayDNSConfig() {
    local ip=$1
    local domainList=$2
    local domains=[]
    while read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        domains=$(echo "${domains}" | jq -r --arg rule "$(xrayDomainRuleValue "${line}")" '. += [$rule]')
    done < <(echo "${domainList}" | tr ',' '\n')

    if [[ "${coreKind}" == "1" ]]; then

        cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
            {
                "address": "${ip}",
                "port": 53,
                "domains": ${domains}
            },
        "localhost"
        ]
    }
}
EOF
    fi
}

# addSingBoxDNSConfig SERVER DOMAIN_CSV [predefined] → 写 dns.json：命中的域名在路由里 resolve 到分流 server
# （DNS 分流是上游 SERVER，SNI 分流是把域名定到 SERVER 的 hosts）。必须是路由级 resolve：出站拨号只问
# default_domain_resolver，写成 dns.rules 的分流起得来却不生效
addSingBoxDNSConfig() {
    local server=$1 domainList=$2 actionType=${3:-} rules serverJson json
    [[ -n "${singBoxConfigPath}" ]] || return 0
    rules=$(initSingBoxRules "${domainList}" "dns") || return 1
    if [[ "${actionType}" == "predefined" ]]; then
        # hosts 只认精确域名，规则集命中的域名在这里解析不出来，所以只留域名规则
        rules=$(jq '.ruleSet = []' <<<"${rules}") || return 1
        serverJson=$(jq -n --arg ip "${server}" --arg list "${domainList}" '{type: "hosts", tag: "hosts",
            predefined: ($list | split(",") | map(select(length > 0)) | unique | map({key: ., value: $ip}) | from_entries)}') || return 1
    else
        serverJson=$(jq -n --arg ip "${server}" '{type: "udp", tag: "dnsRouting", server: $ip}') || return 1
    fi
    json=$(jq -n --argjson r "${rules}" --argjson srv "${serverJson}" --arg cache "${SINGBOX_CONF_DIR}/cache.db" '
        ($r.ruleSet | length) as $remote
        | {dns: {servers: [$srv]},
           route: ({rules: ([if ($r.domainRules | length) > 0 then {domain_regex: $r.domainRules} else empty end,
                             if $remote > 0 then {rule_set: ($r.ruleSet | map(.tag))} else empty end]
                            | map(. + {action: "resolve", server: $srv.tag}))}
                   + (if $remote > 0 then {rule_set: $r.ruleSet} else {} end))}
        + (if $remote > 0 then {experimental: {cache_file: {enabled: true, path: $cache}}} else {} end)') || return 1
    # local 只由 02_dns_local.json 定义：它排在 dns.json 前面，dns.final 缺省取首个 server 才是 local；这里再写就重名，1.14.3 起拒绝启动
    ensureSingBoxLocalDns || return 1
    jsonWriteFile "${singBoxConfigPath}dns.json" "${json}" false
}
# 设置dns
setUnlockDNS() {
    local setDNS domainList item items=()
    read -r -p "请输入分流的DNS:" setDNS
    if [[ -z ${setDNS} ]]; then
        echoContent red " ---> dns不可为空"
        exit 1
    fi
    # 地址与域名都会写进核心配置，一个非法值就让配置校验失败、核心停着
    if ! isValidIP "${setDNS}"; then
        echoContent red " ---> $(t ERR_IP_INVALID)"
        exit 1
    fi
    echoContent red "=============================================================="
    echoContent yellow "录入示例:netflix,disney,hulu"
    read -r -p "请按照上面示例录入域名:" domainList
    IFS=',' read -r -a items <<<"${domainList}"
    for item in "${items[@]}"; do
        if [[ -n "${item}" ]] && ! isValidDomain "${item}"; then
            echoContent red " ---> $(t ERR_DOMAIN_INVALID): ${item}"
            exit 1
        fi
    done
    if [[ -z "${domainList//,/}" ]]; then
        echoContent red " ---> $(t ERR_DOMAIN_EMPTY)"
        exit 1
    fi

    if [[ "${coreKind}" == "1" ]]; then
        addXrayDNSConfig "${setDNS}" "${domainList}"
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        ensureDirectOutbound
        if ! addSingBoxDNSConfig "${setDNS}" "${domainList}"; then
            echoContent red " ---> $(t SINGBOX_DNS_SPLIT_WRITE_FAILED)"
            exit 1
        fi
    fi

    reloadCore

    echoContent yellow "\n ---> 如还无法观看可以尝试以下两种方案"
    echoContent yellow " 1.重启vps"
    echoContent yellow " 2.卸载dns解锁后，修改本地的[/etc/resolv.conf]DNS设置并重启vps\n"
    exit 0
}

# 移除 DNS分流
removeUnlockDNS() {
    if [[ "${coreKind}" == "1" && -f "${configPath}11_dns.json" ]]; then
        cat <<EOF >${configPath}11_dns.json
{
	"dns": {
		"servers": [
			"localhost"
		]
	}
}
EOF
    fi

    # 整个删掉：留一个无 tag 的 local 会和 02_dns_local.json 凑成两个 server，缺解析器起不来
    if [[ -n "${singBoxConfigPath}" ]]; then
        rm -f "${singBoxConfigPath}dns.json"
    fi

    reloadCore

    echoContent green " ---> 卸载成功"

    exit 0
}

# 移除SNI分流
removeUnlockSNI() {
    if [[ "${coreKind}" == 1 ]]; then
        cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
            "localhost"
        ]
    }
}
EOF
    fi

    # 同 removeUnlockDNS：整个删掉，不留无 tag 的 local
    if [[ -n "${singBoxConfigPath}" ]]; then
        rm -f "${singBoxConfigPath}dns.json"
    fi

    reloadCore
    echoContent green " ---> 卸载成功"

    exit 0
}

# validateCustomInstallTokens SELECTION ALLOWED... → 0=合法；非法时打印红字并返回 1
# 旧的字符级正则（^[0-9]+$ / ^[0-7]+$）会放过 999、70 之类未知项，下游 grep 静默忽略——
# 用户以为装了 A 实际装了 B，甚至带着空协议集把安装流程跑完、破坏现有配置
validateCustomInstallTokens() {
    local selection="$1"
    shift
    if ! [[ "${selection}" =~ ^[0-9,]+$ && -n "${selection//,/}" ]]; then
        echoContent red " ---> 输入不合法"
        return 1
    fi
    local token allowed bad=
    for token in ${selection//,/ }; do
        local ok=
        for allowed in "$@"; do
            if [[ "${token}" == "${allowed}" ]]; then
                ok=1
                break
            fi
        done
        if [[ -z "${ok}" ]]; then
            bad="${bad} ${token}"
        fi
    done
    if [[ -n "${bad}" ]]; then
        echoContent red " ---> $(t CUSTOM_INSTALL_INVALID_TOKENS "${bad}")"
        return 1
    fi
    return 0
}

# syncSidecarTlsDomain → Xray 带域名重装后，旁挂 sing-box 的 6 / 9 换成这次域名的证书：它们的片段不在 Xray 重装的重写范围里，
# 换了域名还留着旧证书，客户端按订阅里的新域名校验必失败
syncSidecarTlsDomain() {
    local f content
    [[ -n "${domain}" && -f "${TLS_DIR}/${domain}.crt" && -f "${TLS_DIR}/${domain}.key" ]] || return 0
    for f in "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" "${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json"; do
        [[ -f "${f}" ]] || continue
        content=$(jq --arg d "${domain}" --arg crt "${TLS_DIR}/${domain}.crt" --arg key "${TLS_DIR}/${domain}.key" \
            '.inbounds |= map(if .tls then .tls.server_name = $d | .tls.certificate_path = $crt | .tls.key_path = $key else . end)' "${f}") &&
            jsonWriteFile "${f}" "${content}" false
    done
}

# installAbortArm / installAbortDisarm 夹住带域名安装里「已经停了服务、还没写新配置」那一段：中间不论怎么退出
# （端口自检不过、证书没签下来、输错），都把起步时在跑的 Xray / sing-box / nginx 按磁盘上的旧配置拉回来，不然整机断着
installAbortArm() {
    installAbortRunning=
    xrayDaemonRunning && installAbortRunning+=" xray"
    [[ -n $(pgrep -x sing-box) ]] && installAbortRunning+=" singbox"
    [[ -n $(nginxPids) ]] && installAbortRunning+=" nginx"
    trap installAbortRestore EXIT
}

installAbortDisarm() {
    installAbortRunning=
    trap - EXIT
}

installAbortRestore() {
    local service
    for service in ${installAbortRunning}; do
        case "${service}" in
            xray) handleXray start ;;
            singbox) handleSingBox start ;;
            nginx) handleNginx start force ;;
        esac
    done
}

# sing-box 个性化安装
customSingBoxInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "0.VLESS+TLS_Vision+TCP"
    echoContent yellow "1.VLESS+TLS+WS[仅CDN推荐]"
    echoContent yellow "$(t INSTALL_ITEM_VMESS_WS)"
    echoContent yellow "$(t INSTALL_ITEM_TROJAN)"
    echoContent yellow "6.Hysteria2"
    echoContent yellow "7.VLESS+Reality+Vision"
    echoContent yellow "9.Tuic"
    echoContent yellow "10.Naive"
    echoContent yellow "$(t INSTALL_ITEM_VMESS_HTTPUPGRADE)"
    echoContent yellow "13.AnyTLS"
    echoContent yellow "14.Shadowsocks 2022[无需TLS证书]"
    echoContent yellow "$(t INSTALL_ITEM_SHADOWTLS)"

    read -r -p "请选择[多选]，[例如:1,2,3]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 1
    fi
    if [[ "${selectCustomInstallType}" != "10" ]] && [[ "${selectCustomInstallType}" != "11" ]] && [[ "${selectCustomInstallType}" != "13" ]] && [[ "${selectCustomInstallType}" != "14" ]] && [[ "${selectCustomInstallType}" != "16" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> 多选请使用英文逗号分隔"
        exit 1
    fi
    if [[ "${selectCustomInstallType: -1}" != "," ]]; then
        selectCustomInstallType="${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi

    if validateCustomInstallTokens "${selectCustomInstallType}" 0 1 3 4 6 7 9 10 11 13 14 16; then
        # 走 CDN 的协议提示：sing-box 下每个协议单独监听，随机端口 CDN 不转发
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,|,11,"; then
            echoContent yellow "\n ---> 提示: WS / HTTPUpgrade 只在走 CDN 时才值得用；不走 CDN 选 7（Reality）抗检测更好，但 Reality 不能挂在 CDN 后面"
            echoContent yellow " ---> 走 CDN 时端口要选 CDN 会转发的，Cloudflare 的 HTTPS 只转发 443、2053、2083、2087、2096、8443\n"
        fi

        chainRefuseCoreSwitch 2
        readLastInstallationConfig
        totalProgress=9
        installAbortArm
        installTools 1
        # 申请tls
        if anyProtocolRequiresTLS "${selectCustomInstallType}"; then
            initTLSNginxConfig 2
            installTLS 3
            handleNginx stop
        fi

        installSingBox 4 || { echoContent red "\n ---> sing-box 安装失败，已中止安装流程"; exit 1; }
        installSingBoxService 5
        installAbortDisarm
        initSingBoxConfig custom 6
        cleanUp xrayDel
        installCronTLS 7
        handleSingBox stop
        handleSingBox start
        handleNginx stop
        # 不要证书的选择（7、14）没装 nginx；开着订阅的话下面的收尾会把它起来
        if anyProtocolRequiresTLS "${selectCustomInstallType}"; then
            handleNginx start
        fi
        # 生成账号
        refreshSubscribeAfterInstall
        checkGFWStatue 8
        showAccounts 9
    else
        customSingBoxInstall
    fi
}

# Xray-core个性化安装
customXrayInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "VLESS前置：选了 1 / 3 / 4 / 15 会自动带上 0；无域名只装 Reality 选 7 或 7,12"
    echoContent yellow "0.VLESS+TLS_Vision+TCP[推荐]"
    echoContent yellow "1.VLESS+TLS+WS[仅CDN推荐]"
    echoContent yellow "$(t INSTALL_ITEM_VMESS_WS)"
    echoContent yellow "$(t INSTALL_ITEM_TROJAN)"
    echoContent yellow "7.VLESS+Reality+uTLS+Vision[推荐]"
    echoContent yellow "12.VLESS+Reality+XHTTP"
    echoContent yellow "$(t INSTALL_ITEM_XHTTP_TLS)"
    read -r -p "请选择[多选]，[例如:1,2,3]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 1
    fi
    if [[ ! "${selectCustomInstallType}" =~ ^(12|15)$ ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> 多选请使用英文逗号分隔"
        exit 1
    fi

    selectCustomInstallType=",${selectCustomInstallType},"
    # 1 / 3 / 4 / 15 是 0 的 TLS 回落，没选 0 就补上；12 也要 0 或 7 当前置（readInstallType 与账号管理只认它们）。
    # 7、7,12 不补：补了 0 就要域名和证书，无域名的机器装不上
    if [[ ("${selectCustomInstallType}" =~ ,(1|3|4|15), || ("${selectCustomInstallType}" == *",12,"* && "${selectCustomInstallType}" != *",7,"*)) \
        && "${selectCustomInstallType}" != *",0,"* ]]; then
        selectCustomInstallType=",0${selectCustomInstallType}"
    fi

    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi
    if validateCustomInstallTokens "${selectCustomInstallType}" 0 1 3 4 7 12 15; then
        # 走 CDN 的协议提示：Reality 的 TLS 必须直连本机，挂在 CDN 后面连不上
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,"; then
            echoContent yellow "\n ---> 提示: WS 只在走 CDN 时才值得用；不走 CDN 选 7 或 12（Reality）抗检测更好，但 Reality 不能挂在 CDN 后面"
        fi
        if echo "${selectCustomInstallType}" | grep -q -E ",1,|,3,|,15,"; then
            echoContent yellow " ---> 走 CDN 时端口要选 CDN 会转发的，Cloudflare 的 HTTPS 只转发 443、2053、2083、2087、2096、8443\n"
        fi

        chainRefuseCoreSwitch 1
        local previousCoreKind=${coreKind}
        readLastInstallationConfig
        totalProgress=12
        installAbortArm
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\n进度  3/${totalProgress} : 检测到宝塔面板/1Panel，跳过申请TLS步骤"
            handleXray stop
            if anyProtocolRequiresTLS "${selectCustomInstallType}"; then
                customPortFunction
            fi
        else
            # 申请tls
            if anyProtocolRequiresTLS "${selectCustomInstallType}"; then
                initTLSNginxConfig 2
                handleXray stop
                installTLS 3
            else
                echoContent skyBlue "\n进度  2/${totalProgress} : 检测到仅安装Reality，跳过TLS证书步骤"
            fi
        fi

        handleNginx stop
        # 随机path
        if echo "${selectCustomInstallType}" | grep -qE ",1,|,2,|,3,|,5,|,12,|,15,"; then
            randomPathFunction 4
        fi
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\n进度  6/${totalProgress} : 检测到宝塔面板/1Panel，跳过伪装网站"
        else
            nginxBlog 6
        fi
        if anyProtocolRequiresTLS "${selectCustomInstallType}"; then
            updateRedirectNginxConf
            handleNginx start
        fi

        # 安装Xray
        installXray 7 false || { echoContent red "\n ---> Xray-core 安装失败，已中止安装流程"; exit 1; }
        installXrayService 8
        installAbortDisarm
        initXrayConfig custom 9
        cleanUp singBoxProtocolsDel "${previousCoreKind}"
        syncSidecarTlsDomain
        if anyProtocolRequiresTLS "${selectCustomInstallType}"; then
            installCronTLS 10
        fi

        # 端口自检停过旁挂的 sing-box（链式、6 / 9），重启要连它一起按片段拉回来，只起 Xray 会让它一直停着
        reloadCore
        # 生成账号
        refreshSubscribeAfterInstall
        checkGFWStatue 11
        showAccounts 12
    else
        customXrayInstall
    fi
}

# 选择核心安装sing-box、xray-core
selectCoreInstall() {
    if planAction "$(t PLAN_INSTALL)"; then return 0; fi
    echoContent skyBlue "\n功能 1/${totalProgress} : 选择核心安装"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.sing-box"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectCoreType
    case ${selectCoreType} in
    1)
        if [[ "${selectInstallType}" == "2" ]]; then
            customXrayInstall
        else
            xrayCoreInstall
        fi
        ;;
    2)
        carpoolRefuseIfEnabled
        if [[ "${selectInstallType}" == "2" ]]; then
            customSingBoxInstall
        else
            singBoxInstall
        fi
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        selectCoreInstall
        ;;
    esac
}

# realityQuickDropped TARGET_CORE → 一键 Reality 装完会删掉的已装协议 ID，每行一个：它按「只装 7」重配目标内核，
# 换内核时另一个内核的协议入站整份删；Xray 机旁挂的 6 / 9 在 Xray 这条路上留着。7 原地重配，不算删
realityQuickDropped() {
    local xray sing
    xray=$(scanInstalledProtocols "${XRAY_CONF_DIR}/" 2>/dev/null)
    sing=$(scanInstalledProtocols "${SINGBOX_FRAGMENT_DIR}/" 2>/dev/null)
    if [[ "$1" == "1" ]]; then
        [[ "${coreKind}" == "2" ]] || sing=
    fi
    tr ',' '\n' <<<"${xray}${sing}" | grep -vx -e '' -e 7 | sort -nu
}

# realityQuickConfirm TARGET_CORE → 会删掉别的协议时先列出来、要 y 才继续，答别的就退出：
# 在已有全套协议的机器上跑一键 Reality，其余协议连同订阅里的节点一起没了，以前不打招呼
realityQuickConfirm() {
    local dropped names= id answer
    dropped=$(realityQuickDropped "$1")
    [[ -n "${dropped}" ]] || return 0
    while IFS= read -r id; do
        names+="${names:+, }$(getProtocolDisplayName "${id}")"
    done <<<"${dropped}"
    echoContent yellow " ---> $(t REALITY_QUICK_DROPS "${names}")"
    read -r -p "$(t REALITY_QUICK_CONFIRM)" answer
    if ! isYesInput "${answer}"; then
        echoContent green " ---> $(t REALITY_QUICK_ABORTED)"
        exit 0
    fi
}

# 一键无域名 Reality 安装：仅安装 VLESS+Reality+Vision (协议 7)，跳过域名/TLS 申请
installXrayRealityOnly() {
    chainRefuseCoreSwitch 1
    realityQuickConfirm 1
    local previousCoreKind=${coreKind}
    selectCoreType=1
    selectCustomInstallType=",7,"
    readLastInstallationConfig
    totalProgress=6
    installTools 1
    handleNginx stop
    installXray 2 false || { echoContent red "\n ---> Xray-core 安装失败，已中止安装流程"; exit 1; }
    installXrayService 3
    initXrayConfig custom 4
    cleanUp singBoxProtocolsDel "${previousCoreKind}"
    handleXray stop
    handleXray start
    refreshSubscribeAfterInstall
    checkGFWStatue 5
    showAccounts 6
}

installSingBoxRealityOnly() {
    carpoolRefuseIfEnabled
    chainRefuseCoreSwitch 2
    realityQuickConfirm 2
    selectCoreType=2
    selectCustomInstallType=",7,"
    readLastInstallationConfig
    totalProgress=6
    installTools 1
    installSingBox 2 || { echoContent red "\n ---> sing-box 安装失败，已中止安装流程"; exit 1; }
    installSingBoxService 3
    initSingBoxConfig custom 4
    cleanUp xrayDel
    handleSingBox stop
    handleSingBox start
    refreshSubscribeAfterInstall
    checkGFWStatue 5
    showAccounts 6
}

# 一键无域名 Reality 核心选择
selectRealityCoreInstall() {
    if planAction "$(t PLAN_REALITY_QUICK)"; then return 0; fi
    echoContent skyBlue "\n$(t REALITY_QUICK_TITLE)"
    echoContent red "=============================================================="
    echoContent yellow "$(t REALITY_QUICK_CORE_SELECT)"
    read -r -p "$(t PROMPT_SELECT):" realityCoreType
    case ${realityCoreType} in
        1) installXrayRealityOnly ;;
        2) installSingBoxRealityOnly ;;
        *)
            echoContent red ' ---> 选择错误，重新选择'
            selectRealityCoreInstall
            ;;
    esac
}

# xray-core 安装
xrayCoreInstall() {
    chainRefuseCoreSwitch 1
    local previousCoreKind=${coreKind}
    readLastInstallationConfig
    selectCustomInstallType=
    totalProgress=12
    installAbortArm
    installTools 2
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n进度  3/${totalProgress} : 检测到宝塔面板/1Panel，跳过申请TLS步骤"
        handleXray stop
        customPortFunction
    else
        # 申请tls
        initTLSNginxConfig 3
        handleXray stop
        installTLS 4
    fi

    handleNginx stop
    randomPathFunction 5

    # 安装Xray
    installXray 6 false || { echoContent red "\n ---> Xray-core 安装失败，已中止安装流程"; exit 1; }
    installXrayService 7
    installAbortDisarm
    initXrayConfig all 8
    cleanUp singBoxProtocolsDel "${previousCoreKind}"
    syncSidecarTlsDomain
    installCronTLS 9
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n进度  11/${totalProgress} : 检测到宝塔面板/1Panel，跳过伪装网站"
    else
        nginxBlog 10
    fi
    updateRedirectNginxConf all
    # 端口自检停过旁挂的 sing-box（链式、6 / 9），重启要连它一起按片段拉回来，只起 Xray 会让它一直停着
    reloadCore

    handleNginx start
    # 生成账号
    refreshSubscribeAfterInstall
    checkGFWStatue 11
    showAccounts 12
}

# sing-box 全部安装
singBoxInstall() {
    chainRefuseCoreSwitch 2
    readLastInstallationConfig
    selectCustomInstallType=
    totalProgress=9
    installAbortArm
    installTools 2

    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n进度  3/${totalProgress} : 检测到宝塔面板/1Panel，跳过申请TLS步骤"
        handleXray stop
        customPortFunction
    else
        # 申请tls
        initTLSNginxConfig 3
        handleXray stop
        installTLS 4
    fi

    handleNginx stop

    installSingBox 5 || { echoContent red "\n ---> sing-box 安装失败，已中止安装流程"; exit 1; }
    installSingBoxService 6
    installAbortDisarm
    initSingBoxConfig all 7

    cleanUp xrayDel
    installCronTLS 8

    handleSingBox stop
    handleSingBox start
    handleNginx stop
    handleNginx start
    refreshSubscribeAfterInstall
    # 生成账号
    showAccounts 9
}

# 核心管理
coreVersionManageMenu() {

    if [[ -z "${coreKind}" ]]; then
        echoContent red "\n ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 1
    fi
    echoContent skyBlue "\n功能 1/1 : 请选择核心"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core"
    echoContent yellow "2.sing-box"
    echoContent red "=============================================================="
    read -r -p "请输入:" selectCore

    if [[ "${selectCore}" == "1" ]]; then
        xrayVersionManageMenu 1
    elif [[ "${selectCore}" == "2" ]]; then
        singBoxVersionManageMenu 1
    fi
}
# 定时任务检查
cronFunction() {
    if [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit $?
    elif [[ "${cronName}" == "UpdateGeo" ]]; then
        local geoLog="${PROXY_AGENT_DIR}/crontab_updateGeoSite.log"
        if updateGeoSite >>"${geoLog}"; then
            echoContent green " ---> geo更新日期:$(date "+%F %H:%M:%S")" >>"${geoLog}"
            exit 0
        fi
        exit 1
    elif [[ "${cronName}" == "CarpoolTick" ]]; then
        trap 'carpoolTickExitTrap $?' EXIT
        carpoolTick
        local tickRc=$?
        _carpoolTickFinished=1
        exit "${tickRc}"
    elif [[ "${cronName}" == "CarpoolApply" ]]; then
        carpoolApply
        exit $?
    fi
}
# 账号管理
manageAccount() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 账号管理"
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装"
        exit 1
    fi

    echoContent red "\n=============================================================="
    echoContent yellow "# 添加单个用户时可自定义email和uuid"
    echoContent yellow "# 如安装了Hysteria或者Tuic，账号会同时添加到相应的类型下面\n"
    echoContent yellow "1.查看账号"
    echoContent yellow "2.查看订阅"
    echoContent yellow "3.管理其他订阅"
    echoContent yellow "4.添加用户"
    echoContent yellow "5.删除用户"
    echoContent yellow "6.$(t CARPOOL_MENU_ENTRY)"
    echoContent red "=============================================================="
    read -r -p "请输入:" manageAccountStatus
    if [[ "${manageAccountStatus}" == "1" ]]; then
        showAccounts 1
    elif [[ "${manageAccountStatus}" == "2" ]]; then
        subscribe
    elif [[ "${manageAccountStatus}" == "3" ]]; then
        addSubscribeMenu 1
    elif [[ "${manageAccountStatus}" == "4" ]]; then
        addUser
    elif [[ "${manageAccountStatus}" == "5" ]]; then
        removeUser
    elif [[ "${manageAccountStatus}" == "6" ]]; then
        carpoolMenu
    else
        echoContent red " ---> 选择错误"
    fi
}

# 安装订阅
installSubscribe() {
    readNginxSubscribe
    if [[ -z "${subscribePort}" ]]; then

        nginxVersion=$(nginx -v 2>&1)

        if echo "${nginxVersion}" | grep -q "not found" || [[ -z "${nginxVersion}" ]]; then
            echoContent yellow "未检测到nginx，无法使用订阅服务\n"
            read -r -p "是否安装[y/n]？" installNginxStatus
            if isYesInput "${installNginxStatus}"; then
                installNginxTools || exit 1
                nginxVersion=$(nginx -v 2>&1)
            else
                echoContent red " ---> 放弃安装nginx\n"
                exit 1
            fi
        fi
        echoContent yellow "开始配置订阅，请输入订阅的端口\n"

        mapfile -t result < <(initSingBoxPort "${subscribePort}")
        echo
        echoContent yellow " ---> 开始配置订阅的伪装站点\n"
        nginxBlog
        echo
        local subscribeServerName="${currentHost:-${domain}}"
        if [[ -z "${subscribeServerName}" || ! -f "${TLS_DIR}/${subscribeServerName}.crt" || ! -f "${TLS_DIR}/${subscribeServerName}.key" ]]; then
            echoContent yellow "未发现tls证书，使用无加密订阅，可能被运营商拦截，请注意风险。"
            echo
            read -r -p "是否使用http订阅[y/n]？" addNginxSubscribeStatus
            echo
            if ! isYesInput "${addNginxSubscribeStatus}"; then
                echoContent yellow " ---> 退出安装"
                exit
            fi
        fi
        renderSubscribeConf "${result[-1]}" "${subscribeServerName}"
        bootStartup nginx
        handleNginx stop
        handleNginx start
    fi
    if [[ -z $(nginxPids) ]]; then
        handleNginx start
    fi
}

# renderSubscribeConf PORT SERVER_NAME → 不交互地写 subscribe.conf：有 SERVER_NAME 的证书就是 https，没有就是 http。
# 端口与 http / https 是只问一次的设置，这份文件从设置渲染：安装流程收尾按原端口重写，域名换了跟着换
# 用量头的 map 用通配 include：文件不在时 nginx -t 照过；写成精确路径的话，文件一丢整个 nginx 都起不来
renderSubscribeConf() {
    local port=$1 subscribeServerName=$2 SSLType= serverName= nginxSubscribeSSL= listenIPv6= nginxSubscribeListen
    nginxVersion=$(nginx -v 2>&1)
    if [[ -n "${subscribeServerName}" && -f "${TLS_DIR}/${subscribeServerName}.crt" && -f "${TLS_DIR}/${subscribeServerName}.key" ]]; then
        SSLType="ssl"
        serverName="server_name ${subscribeServerName};"
        nginxSubscribeSSL="ssl_certificate ${TLS_DIR}/${subscribeServerName}.crt;ssl_certificate_key ${TLS_DIR}/${subscribeServerName}.key;"
    fi
    if [[ -n "$(curl --connect-timeout 2 -s -6 https://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)" ]]; then
        listenIPv6="listen [::]:${port} ${SSLType};"
    fi
    # 不带 SNI 或 SNI 不对的握手直接拒，按 IP 扫的拿不到域名证书（与 0 的 rejectUnknownSni 一致）；
    # ssl_reject_handshake 从 nginx 1.19.4 起才有，旧版写进去 nginx -t 不过、整个 nginx 起不来。
    # 同端口别的配置已有 default_server 时不加：两个 default_server 让 nginx 拒载
    local rejectUnknownSniBlock= rejectListen="listen ${port} ssl default_server;" otherDefault=
    if [[ "${SSLType}" == "ssl" ]] && versionGreaterOrEqual "$(sed -n 's|.*nginx/\([0-9][0-9.]*\).*|\1|p' <<<"${nginxVersion}")" 1.19.4; then
        otherDefault=$(nginxDefaultServerFile "${port}" "${nginxConfigPath}subscribe.conf")
        if [[ -n "${otherDefault}" ]]; then
            echoContent yellow " ---> $(t SUBSCRIBE_DEFAULT_SERVER_TAKEN "${port}" "${otherDefault}")"
        else
            if [[ -n "${listenIPv6}" ]]; then
                rejectListen+="listen [::]:${port} ssl default_server;"
            fi
            rejectUnknownSniBlock=$(printf 'server {\n    %s\n    ssl_reject_handshake on;\n}' "${rejectListen}")
        fi
    fi
    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxSubscribeListen="listen ${port} ${SSLType} so_keepalive=on;http2 on;${listenIPv6}"
    else
        nginxSubscribeListen="listen ${port} ${SSLType} so_keepalive=on;${listenIPv6}"
    fi

    # 订阅文件名一律是 32 位十六进制 md5，location 只收这种名字：$2 里没有 / 和 .，alias 拼不出目录外的路径。正则带花括号，
    # 必须加引号，否则 nginx 当成块的开头；readNginxSubscribe 取第一行 listen、靠 sing-box 这个词认文件，主 server 块要排在最前
    # 通用地址按 UA 给格式：规则锚定开头（Hiddify / NekoBox / Karing 的 UA 带着别家的名字），map 求值会冲掉 $1，文件名用命名捕获
    cat <<EOF >${nginxConfigPath}subscribe.conf
# proxy-agent subscribe.conf r${SUBSCRIBE_CONF_REVISION}
map \$http_user_agent \$paSubFormat {
    default                            default;
    "~*^karing/"                       sing-box;
    "~*^hiddifynext"                   sing-box;
    "~*^(?:nekobox|throne)/"           default;
    "~^SF[AIMT]\b"                     sing-box;
    "~*^clash\.meta/"                  clashMeta;
    "~*^(?:clash|mihomo|flclash|stash)" clashMetaProfiles;
    "~*sing-?box"                      sing-box;
}
map \$uri \$paSubUserinfo {
    default "";
    include ${PROXY_AGENT_DIR}/subscribe_userinfo*.map;
}
server {
    ${nginxSubscribeListen}
    ${serverName}
    ${nginxSubscribeSSL}
    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;
    server_tokens off;
    root ${nginxStaticPath};
    location ~ "^/s/(?<paSubKey>[0-9a-f]{32})\$" {
        default_type 'text/plain; charset=utf-8';
        add_header Profile-Update-Interval 12 always;
        add_header Subscription-Userinfo \$paSubUserinfo always;
        add_header Vary User-Agent always;
        root ${SUBSCRIBE_DIR};
        try_files /\$paSubFormat/\$paSubKey /default/\$paSubKey =404;
    }
    location ~ "^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([0-9a-f]{32})\$" {
        default_type 'text/plain; charset=utf-8';
        add_header Profile-Update-Interval 12 always;
        add_header Subscription-Userinfo \$paSubUserinfo always;
        alias ${SUBSCRIBE_DIR}/\$1/\$2;
    }
    location / {
    }
}
${rejectUnknownSniBlock}
EOF
}

# nginxDefaultServerFile PORT SELF → 别的 nginx 配置在 PORT 的通配地址上声明了 default_server 就输出那个文件，没有输出空。
# 读 nginx -T 的全量配置，SELF 这份不算；nginx -T 失败时输出空
nginxDefaultServerFile() {
    nginx -T 2>/dev/null | awk -v port="$1" -v self="$2" '
        /^# configuration file / { file = $4; sub(/:$/, "", file); next }
        file == self { next }
        {
            sub(/#.*/, "")
            n = split($0, parts, ";")
            for (i = 1; i <= n; i++) {
                if (split(parts[i], w, " ") < 2 || w[1] != "listen" || parts[i] !~ /[ \t]default_server([ \t]|$)/) continue
                if (w[2] == port || w[2] == "*:" port || w[2] == "0.0.0.0:" port || w[2] == "[::]:" port) { print file; exit }
            }
        }'
}

# ensureSubscribeConfCurrent → subscribe.conf 第一行不是当前模板修订号（旧版脚本写的）就按原端口、原域名重写，
# 拼车页面块补回；nginx -t 不过就逐字还原。原来是 https、证书已不在的不动（重写会降成 http）
ensureSubscribeConfCurrent() {
    local conf="${nginxConfigPath}subscribe.conf" port serverNameValue hadPage=
    [[ -n "${nginxConfigPath}" && -f "${conf}" ]] && command -v nginx >/dev/null 2>&1 || return 0
    [[ "$(head -1 "${conf}")" == "# proxy-agent subscribe.conf r${SUBSCRIBE_CONF_REVISION}" ]] && return 0
    port=$(subscribeConfPort)
    [[ -n "${port}" ]] || return 0
    serverNameValue=$(grep -m1 'server_name' "${conf}" | awk '{print $2}' | tr -d ';')
    if grep -m1 "listen" "${conf}" | grep -q " ssl" && [[ ! -f "${TLS_DIR}/${serverNameValue}.crt" || ! -f "${TLS_DIR}/${serverNameValue}.key" ]]; then
        return 0
    fi
    grep -q '# carpool-page-begin' "${conf}" && hadPage=1
    cp -f "${conf}" "${conf}.upgrade.bak" || return 0
    renderSubscribeConf "${port}" "${serverNameValue}"
    if [[ -n "${hadPage}" ]] && carpoolInsertPageBlock "${conf}" "${conf}.new"; then
        mv -f "${conf}.new" "${conf}"
    fi
    rm -f "${conf}.new"
    if nginx -t >/dev/null 2>&1; then
        rm -f "${conf}.upgrade.bak"
        carpoolReloadNginx
        echoContent green " ---> $(t SUBSCRIBE_CONF_UPGRADED)"
    else
        mv -f "${conf}.upgrade.bak" "${conf}"
        echoContent yellow " ---> $(t SUBSCRIBE_CONF_UPGRADE_FAILED "${conf}")"
    fi
}

# renderRealityLocalDest DOMAIN → reality_dest.conf：Reality 目标选本机域名时转交来的连接由它应答（该域名证书 + 伪装站），
# 只听回环、要能 TLS 1.3 与 h2。没有这个域名的证书就不写，返回 1
renderRealityLocalDest() {
    local domainName=$1 h2Listen= h2Line=
    [[ -n "${nginxConfigPath}" && -f "${TLS_DIR}/${domainName}.crt" && -f "${TLS_DIR}/${domainName}.key" ]] || return 1
    nginxVersion=$(nginx -v 2>&1)
    if versionGreaterOrEqual "$(sed -n 's|.*nginx/\([0-9][0-9.]*\).*|\1|p' <<<"${nginxVersion}")" 1.25.1; then
        h2Line="http2 on;"
    else
        h2Listen=" http2"
    fi
    cat <<EOF >"${nginxConfigPath}reality_dest.conf"
server {
    listen 127.0.0.1:${REALITY_LOCAL_DEST_PORT} ssl${h2Listen};
    ${h2Line}
    server_name ${domainName};
    ssl_certificate ${TLS_DIR}/${domainName}.crt;
    ssl_certificate_key ${TLS_DIR}/${domainName}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;
    root ${nginxStaticPath};
    location / {
    }
}
EOF
}

# subscribeConfPort → 已装订阅的端口（subscribe.conf 第一行 listen），没装输出空
subscribeConfPort() {
    [[ -n "${nginxConfigPath}" && -f "${nginxConfigPath}subscribe.conf" ]] || return 0
    grep -m1 "listen" "${nginxConfigPath}subscribe.conf" | awk '{print $2}' | grep -E '^[0-9]+$'
}

# refreshSubscribeAfterInstall → 安装流程收尾：订阅装过就按原端口重写配置（域名换了跟着换，拼车页面的 location 补回去），
# 再用原 salt 静默重建订阅文件，订阅地址不变、内容换成这次装出来的账号。原来是 https、这次没有该域名的证书就不降级，文件不动
refreshSubscribeAfterInstall() {
    local port serverNameValue hadPage=
    port=$(subscribeConfPort)
    [[ -n "${port}" ]] && command -v nginx >/dev/null 2>&1 || return 0
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    serverNameValue=${domain:-${currentHost}}
    if ! grep -m1 "listen" "${nginxConfigPath}subscribe.conf" | grep -q " ssl" \
        || [[ -n "${serverNameValue}" && -f "${TLS_DIR}/${serverNameValue}.crt" && -f "${TLS_DIR}/${serverNameValue}.key" ]]; then
        grep -q '# carpool-page-begin' "${nginxConfigPath}subscribe.conf" && hadPage=1
        renderSubscribeConf "${port}" "${serverNameValue}"
        [[ -n "${hadPage}" ]] && carpoolEnsureNginxLocation on
    fi
    bootStartup nginx
    handleNginx stop
    handleNginx start force
    # 与拼车恢复成员时同一条静默重建：订阅端口读不出来（域名对不上）就跳过，不会掉进交互
    carpoolRefreshSubscribe
}
# 卸载订阅
unInstallSubscribe() {
    rm -rf "${nginxConfigPath}subscribe.conf" >/dev/null 2>&1
}

# 添加订阅
addSubscribeMenu() {
    echoContent skyBlue "\n===================== 添加其他机器订阅 ======================="
    echoContent yellow "1.添加"
    echoContent yellow "2.移除"
    echoContent red "=============================================================="
    read -r -p "请选择:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        if [[ ! -f "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl" ]]; then
            echoContent green " ---> 未安装其他订阅"
            exit 0
        fi
        grep -v '^$' "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl" | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的订阅编号[仅支持单个删除]:" delSubscribeIndex
        if [[ -z "${delSubscribeIndex}" ]]; then
            echoContent red " ---> 不可以为空"
            exit 1
        fi

        sed -i "$((delSubscribeIndex))d" "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl" >/dev/null 2>&1

        echoContent green " ---> 其他机器订阅删除成功"
        subscribe
    fi
}
# 添加其他机器clashMeta订阅
addOtherSubscribe() {
    echoContent yellow "#注意事项:"
    echoContent yellow "请输入目标站点信息，确保与 Reality 配置相匹配。"
    echoContent skyBlue "录入示例：www.example.com:443:vps1\n"
    read -r -p "请输入域名 端口 机器别名:" remoteSubscribeUrl
    if [[ -z "${remoteSubscribeUrl}" ]]; then
        echoContent red " ---> 不可为空"
        addOtherSubscribe
    elif ! echo "${remoteSubscribeUrl}" | grep -q ":"; then
        echoContent red " ---> 规则不合法"
    else

        if [[ -f "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl" ]] && grep -q "${remoteSubscribeUrl}" ${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl; then
            echoContent red " ---> 此订阅已添加"
            exit 1
        fi
        echo
        read -r -p "是否是HTTP订阅？[y/n]" httpSubscribeStatus
        if isYesInput "${httpSubscribeStatus}"; then
            remoteSubscribeUrl="${remoteSubscribeUrl}:http"
        fi
        echo "${remoteSubscribeUrl}" >>${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl
        subscribe
    fi
}
# clashMeta配置文件
clashMetaConfig() {
    local url=$1
    local id=$2
    cat <<EOF >"${SUBSCRIBE_DIR}/clashMetaProfiles/${id}"
log-level: info
mode: rule
ipv6: true
mixed-port: 7890
# 默认不向局域网开放本地代理端口（公共 Wi-Fi 下 7890 无认证对全网段可见）。
# 需要给局域网设备共享时把 allow-lan 改为 true——下面两项已按共享场景配好。
allow-lan: false
bind-address: "*"
lan-allowed-ips:
  - 0.0.0.0/0
  - ::/0
find-process-mode: strict
# external-controller 仅绑 loopback：避免共享 LAN（公司/学校/酒店 Wi-Fi）上其他设备
# 直连 Yacd / Clash Verge API 偷节点信息或切换出口。Yacd/Verge 在本机运行，loopback 够用。
external-controller: 127.0.0.1:9090

geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
geo-auto-update: true
geo-update-interval: 24

external-controller-cors:
  allow-private-network: true

# global-client-fingerprint 已被 mihomo 弃用；每个 proxy 内部已显式声明 client-fingerprint。

profile:
  store-selected: true
  store-fake-ip: true

sniffer:
  enable: true
  override-destination: false
  sniff:
    QUIC:
      ports: [ 443 ]
    TLS:
      ports: [ 443 ]
    HTTP:
      ports: [80]


dns:
  enable: true
  prefer-h3: false
  # 与 allow-lan: false 配套仅监听回环；开共享时改 0.0.0.0:1053
  listen: 127.0.0.1:1053
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'dns.google'
    - "localhost.ptlogin2.qq.com"
  use-hosts: true
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - 1.1.1.1
    - 8.8.8.8
  proxy-server-nameserver:
    - https://223.5.5.5/dns-query
    - https://1.12.12.12/dns-query
  nameserver-policy:
    "geosite:cn,private":
      - https://doh.pub/dns-query
      - https://dns.alidns.com/dns-query

proxy-providers:
  ${subscribeSalt}_provider:
    type: http
    path: ./${subscribeSalt}_provider.yaml
    url: ${url}
    interval: 3600
    proxy: DIRECT
    health-check:
      enable: true
      url: https://cp.cloudflare.com/generate_204
      interval: 300

proxy-groups:
  - name: 手动切换
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies: null
  - name: 自动选择
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 36000
    tolerance: 50
    use:
      - ${subscribeSalt}_provider
    proxies: null

  - name: 全球代理
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: 流媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: DNS_Proxy
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 自动选择
      - 手动切换
      - DIRECT

  - name: Telegram
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Google
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: YouTube
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Netflix
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Spotify
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
      - DIRECT
  - name: HBO
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Bing
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择


  - name: OpenAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: ClaudeAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: Disney
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: GitHub
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT

  - name: 国内媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
  - name: 本地直连
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 自动选择
  - name: 漏网之鱼
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 手动切换
      - 自动选择
rule-providers:
  lan:
    type: http
    behavior: classical
    interval: 86400
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Lan/Lan.yaml
    path: ./Rules/lan.yaml
  reject:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt
    path: ./ruleset/reject.yaml
    interval: 86400
  proxy:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt
    path: ./ruleset/proxy.yaml
    interval: 86400
  direct:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt
    path: ./ruleset/direct.yaml
    interval: 86400
  private:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt
    path: ./ruleset/private.yaml
    interval: 86400
  gfw:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/gfw.txt
    path: ./ruleset/gfw.yaml
    interval: 86400
  greatfire:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/greatfire.txt
    path: ./ruleset/greatfire.yaml
    interval: 86400
  tld-not-cn:
    type: http
    behavior: domain
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400
  telegramcidr:
    type: http
    behavior: ipcidr
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/telegramcidr.txt
    path: ./ruleset/telegramcidr.yaml
    interval: 86400
  applications:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt
    path: ./ruleset/applications.yaml
    interval: 86400
  Disney:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Disney/Disney.yaml
    path: ./ruleset/disney.yaml
    interval: 86400
  Netflix:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Netflix/Netflix.yaml
    path: ./ruleset/netflix.yaml
    interval: 86400
  YouTube:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/YouTube/YouTube.yaml
    path: ./ruleset/youtube.yaml
    interval: 86400
  HBO:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/HBO/HBO.yaml
    path: ./ruleset/hbo.yaml
    interval: 86400
  OpenAI:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml
    path: ./ruleset/openai.yaml
    interval: 86400
  ClaudeAI:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.yaml
    path: ./ruleset/claudeai.yaml
    interval: 86400
  Bing:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Bing/Bing.yaml
    path: ./ruleset/bing.yaml
    interval: 86400
  Google:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Google/Google.yaml
    path: ./ruleset/google.yaml
    interval: 86400
  GitHub:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml
    path: ./ruleset/github.yaml
    interval: 86400
  Spotify:
    type: http
    behavior: classical
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Spotify/Spotify.yaml
    path: ./ruleset/spotify.yaml
    interval: 86400
  ChinaMaxDomain:
    type: http
    behavior: domain
    interval: 86400
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_Domain.yaml
    path: ./Rules/ChinaMaxDomain.yaml
  ChinaMaxIPNoIPv6:
    type: http
    behavior: ipcidr
    interval: 86400
    url: https://gh-proxy.com/https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_IP_No_IPv6.yaml
    path: ./Rules/ChinaMaxIPNoIPv6.yaml
rules:
  - RULE-SET,YouTube,YouTube,no-resolve
  - RULE-SET,Google,Google,no-resolve
  - RULE-SET,GitHub,GitHub
  - RULE-SET,telegramcidr,Telegram,no-resolve
  - RULE-SET,Spotify,Spotify,no-resolve
  - RULE-SET,Netflix,Netflix
  - RULE-SET,HBO,HBO
  - RULE-SET,Bing,Bing
  - RULE-SET,OpenAI,OpenAI
  - RULE-SET,ClaudeAI,ClaudeAI
  - RULE-SET,Disney,Disney
  - RULE-SET,proxy,全球代理
  - RULE-SET,gfw,全球代理
  - RULE-SET,applications,本地直连
  - RULE-SET,ChinaMaxDomain,本地直连
  - RULE-SET,ChinaMaxIPNoIPv6,本地直连,no-resolve
  - RULE-SET,lan,本地直连,no-resolve
  - GEOIP,CN,本地直连
  - MATCH,漏网之鱼
EOF

}
# 随机salt - 使用更安全的随机源
initRandomSalt() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    local charLen=${#chars}
    for i in {1..10}; do
        local idx
        idx=$(randomNum 0 $((charLen - 1)))
        initCustomPath+="${chars:idx:1}"
    done
    echo "${initCustomPath}"
}
# 读取自定义 salt：回车走随机，<8 位拒绝重询。
# 订阅 URL 由 md5(email+salt) 派生且 nginx 侧无鉴权，弱 salt 会让 URL 可枚举、泄漏完整节点配置。
readSubscribeSalt() {
    subscribeSalt=
    while true; do
        read -r -p "$(t SUBSCRIBE_SALT_PROMPT)" subscribeSalt
        if [[ -z "${subscribeSalt}" ]]; then
            subscribeSalt=$(initRandomSalt)
            break
        elif [[ ${#subscribeSalt} -lt 8 ]]; then
            echoContent red " ---> $(t SUBSCRIBE_SALT_TOO_SHORT)"
        else
            break
        fi
    done
}

# subscribeLocalHasEmptyHost → 0=本地生成的节点里有空地址：取不到公网 IP 时通用链接写成 @:端口，
# Clash 的 server 与 sing-box 的 "server" 是空的
subscribeLocalHasEmptyHost() {
    grep -qsE '@:[0-9]' "${SUBSCRIBE_LOCAL_DIR}"/default/* \
        || grep -qsE '^[[:space:]]*server:[[:space:]]*$' "${SUBSCRIBE_LOCAL_DIR}"/clashMeta/* \
        || grep -qsE '"server":[[:space:]]*""' "${SUBSCRIBE_LOCAL_DIR}"/sing-box/*
}

# 订阅
subscribe() {
    readInstallProtocolType
    installSubscribe

    readNginxSubscribe
    local renewSalt=$1
    local showStatus=$2
    if [[ "${coreKind}" == "1" || "${coreKind}" == "2" ]]; then

        echoContent skyBlue "-------------------------备注---------------------------------"
        echoContent yellow "# 查看订阅会重新生成本地账号的订阅"
        echoContent yellow "# 首次生成或更换 salt 时才要输入 md5 加密的 salt 值，如果不了解使用随机即可"
        echoContent yellow "# 不影响已添加的远程订阅的内容\n"

        if [[ -f "${SUBSCRIBE_LOCAL_DIR}/subscribeSalt" && -n $(cat "${SUBSCRIBE_LOCAL_DIR}/subscribeSalt") ]]; then
            if [[ -z "${renewSalt}" ]]; then
                # 只有明确答 n 才换：换 salt 等于换掉所有人的订阅地址，查看一次不该有这种后果
                read -r -p "$(t SUBSCRIBE_SALT_REUSE_PROMPT)" historySaltStatus
                case "${historySaltStatus,,}" in
                    n | no) readSubscribeSalt ;;
                    *) subscribeSalt=$(cat ${SUBSCRIBE_LOCAL_DIR}/subscribeSalt) ;;
                esac
            else
                subscribeSalt=$(cat ${SUBSCRIBE_LOCAL_DIR}/subscribeSalt)
            fi
        else
            readSubscribeSalt
            showStatus=
        fi
        echoContent yellow "\n ---> Salt: ${subscribeSalt}"

        echo "${subscribeSalt}" >${SUBSCRIBE_LOCAL_DIR}/subscribeSalt

        rm -rf ${SUBSCRIBE_LOCAL_DIR}/default/*
        rm -rf ${SUBSCRIBE_LOCAL_DIR}/clashMeta/*
        rm -rf ${SUBSCRIBE_LOCAL_DIR}/sing-box/*
        showAccounts >/dev/null
        # 先在本地生成、查过再动已发布的：取不到公网 IP 时节点地址是空的，发出去客户端一更新就全坏，留着旧的至少还能用
        if subscribeLocalHasEmptyHost; then
            echoContent red " ---> $(t SUBSCRIBE_EMPTY_HOST)"
            return 1
        fi
        rm -rf ${SUBSCRIBE_DIR}/default/*
        rm -rf ${SUBSCRIBE_DIR}/clashMeta/*
        if [[ -n $(ls ${SUBSCRIBE_LOCAL_DIR}/default/) ]]; then
            if [[ -f "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl" && -n $(cat "${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl") ]]; then
                if [[ -z "${renewSalt}" ]]; then
                    read -r -p "读取到其他订阅，是否更新？[y/n]" updateOtherSubscribeStatus
                else
                    updateOtherSubscribeStatus=y
                fi
            fi
            local subscribePortLocal="${subscribePort}"
            # sing-box 通用配置的模板从本仓库 docs/sing-box.json 拉，一轮只拉一次（cron 下逐人拉太慢）；
            # 拉不到或不是合法 JSON 就不动已有的 sing-box 配置文件：一次瞬时失败不该让能用的配置变成 404
            local _singboxTplUrl="https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/docs/sing-box.json"
            local _singboxTpl= _singboxTplExit=0
            if [[ -n $(ls "${SUBSCRIBE_LOCAL_DIR}/sing-box/" 2>/dev/null) ]] && _singboxTpl=$(mktemp); then
                echoContent skyBlue " ---> 下载 sing-box 通用配置文件"
                if [[ "${release}" == "alpine" ]]; then
                    wget -O "${_singboxTpl}" -q --timeout=15 --tries=2 "${_singboxTplUrl}" || _singboxTplExit=$?
                else
                    wget -O "${_singboxTpl}" -q --timeout=15 --tries=2 ${wgetShowProgressStatus} "${_singboxTplUrl}" || _singboxTplExit=$?
                fi
                if [[ ${_singboxTplExit} -ne 0 ]] || [[ ! -s "${_singboxTpl}" ]] || ! jq -e . "${_singboxTpl}" >/dev/null 2>&1; then
                    echoContent red " ---> sing-box 订阅模板下载或解析失败，跳过本次 sing-box 订阅 (URL: ${_singboxTplUrl})"
                    rm -f "${_singboxTpl}"
                    _singboxTpl=
                fi
            fi
            find ${SUBSCRIBE_LOCAL_DIR}/default/* | while read -r email; do
                email=$(echo "${email}" | awk -F "[d][e][f][a][u][l][t][/]" '{print $2}')

                local emailMd5=
                emailMd5=$(echo -n "${email}${subscribeSalt}"$'\n' | md5sum | awk '{print $1}')

                cat "${SUBSCRIBE_LOCAL_DIR}/default/${email}" >>"${SUBSCRIBE_DIR}/default/${emailMd5}"
                if isYesInput "${updateOtherSubscribeStatus}"; then
                    updateRemoteSubscribe "${emailMd5}" "${email}"
                fi
                local base64Result
                base64Result=$(base64 < "${SUBSCRIBE_DIR}/default/${emailMd5}" | tr -d '\n')
                echo "${base64Result}" >"${SUBSCRIBE_DIR}/default/${emailMd5}"
                echoContent yellow "--------------------------------------------------------------"
                local currentDomain=${currentHost}

                if [[ -n "${currentDefaultPort}" && "${currentDefaultPort}" != "443" ]]; then
                    currentDomain="${currentHost}:${currentDefaultPort}"
                fi
                if [[ -n "${subscribePortLocal}" ]]; then
                    if [[ "${subscribeType}" == "http" ]]; then
                        currentDomain="$(getPublicIP):${subscribePort}"
                    else
                        currentDomain="${currentHost}:${subscribePort}"
                    fi
                fi
                # 三种格式的文件不管打不打印都要重建：上面已经删光了 clashMeta，只建 default 会让所有人的 Clash 订阅 404
                if [[ -z "${showStatus}" ]]; then
                    echoContent skyBlue "\n----------$(t SUBSCRIBE_UNIVERSAL_TITLE)----------\n"
                    echoContent green "email:${email}\n"
                    echoContent yellow "url:${subscribeType}://${currentDomain}/s/${emailMd5}\n"
                    echoContent yellow "$(t SUBSCRIBE_UNIVERSAL_HINT)\n"
                    shareQrCode "" "${subscribeType}://${currentDomain}/s/${emailMd5}"
                    echoContent skyBlue "\n----------默认订阅----------\n"
                    echoContent yellow "url:${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    shareQrCode "" "${subscribeType}://${currentDomain}/s/default/${emailMd5}"
                fi

                # clashMeta
                if [[ -f "${SUBSCRIBE_LOCAL_DIR}/clashMeta/${email}" ]]; then
                    { echo "proxies:"; cat "${SUBSCRIBE_LOCAL_DIR}/clashMeta/${email}"; } >"${SUBSCRIBE_DIR}/clashMeta/${emailMd5}"
                    local clashProxyUrl="${subscribeType}://${currentDomain}/s/clashMeta/${emailMd5}"
                    clashMetaConfig "${clashProxyUrl}" "${emailMd5}"
                    if [[ -z "${showStatus}" ]]; then
                        echoContent skyBlue "\n----------clashMeta订阅----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        shareQrCode "" "${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}"
                    fi
                fi
                # sing-box
                if [[ -f "${SUBSCRIBE_LOCAL_DIR}/sing-box/${email}" ]]; then
                    cp "${SUBSCRIBE_LOCAL_DIR}/sing-box/${email}" "${SUBSCRIBE_DIR}/sing-box_profiles/${emailMd5}"
                    local _singboxFile="${SUBSCRIBE_DIR}/sing-box/${emailMd5}"
                    if [[ -n "${_singboxTpl}" ]] && jq --slurpfile p "${SUBSCRIBE_LOCAL_DIR}/sing-box/${email}" \
                        '($p[0] | map(select(.type != "shadowtls") | .tag)) as $tags | .outbounds |= map(if has("outbounds") then .outbounds += $tags else . end) | .outbounds += $p[0]' \
                        "${_singboxTpl}" >"${_singboxFile}.tmp" && mv "${_singboxFile}.tmp" "${_singboxFile}" && [[ -z "${showStatus}" ]]; then
                        echoContent skyBlue "\n----------sing-box订阅----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        shareQrCode "" "${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}"
                    fi
                    rm -f "${_singboxFile}.tmp"
                fi

                if [[ -z "${showStatus}" ]]; then
                    echoContent skyBlue "--------------------------------------------------------------"
                else
                    echoContent green " ---> email:${email}，订阅已更新，请使用客户端重新拉取"
                fi

            done
            if [[ -n "${_singboxTpl}" ]]; then
                rm -f "${_singboxTpl}"
            fi
        fi
        # 停用的拼车成员不在 inbound 里、上面没给他们生成文件，补上占位（关闭后保持停用的也算）
        if [[ -f "${CARPOOL_STATE_FILE}" ]]; then
            carpoolWritePlaceholders "$(carpoolReadState)"
        fi
    else
        echoContent red " ---> 未安装伪装站点，无法使用订阅服务"
    fi
}

# 更新远程订阅
updateRemoteSubscribe() {

    local emailMD5=$1
    local email=$2
    while read -r line; do
        local subscribeType=
        subscribeType="https"

        local serverAlias=
        serverAlias=$(echo "${line}" | awk -F "[:]" '{print $3}')

        local remoteUrl=
        remoteUrl=$(echo "${line}" | awk -F "[:]" '{print $1":"$2}')

        local subscribeTypeRemote=
        subscribeTypeRemote=$(echo "${line}" | awk -F "[:]" '{print $4}')

        if [[ -n "${subscribeTypeRemote}" ]]; then
            subscribeType="${subscribeTypeRemote}"
        fi
        local clashMetaProxies=

        clashMetaProxies=$(curl -s --connect-timeout 5 -m 20 "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" | sed '/proxies:/d' | sed "s/\"${email}/\"${email}_${serverAlias}/g")

        if ! echo "${clashMetaProxies}" | grep -q "nginx" && [[ -n "${clashMetaProxies}" ]]; then
            echo "${clashMetaProxies}" >>"${SUBSCRIBE_DIR}/clashMeta/${emailMD5}"
            echoContent green " ---> clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> clashMeta订阅 ${remoteUrl}:${email}不存在"
        fi

        local default=
        default=$(curl -s --connect-timeout 5 -m 20 "${subscribeType}://${remoteUrl}/s/default/${emailMD5}")

        if ! echo "${default}" | grep -q "nginx" && [[ -n "${default}" ]]; then
            default=$(echo "${default}" | base64 -d | sed "s/#${email}/#${email}_${serverAlias}/g")
            echo "${default}" >>"${SUBSCRIBE_DIR}/default/${emailMD5}"

            echoContent green " ---> 通用订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 不存在"
        fi

        local singBoxSubscribe=
        singBoxSubscribe=$(curl -s --connect-timeout 5 -m 20 "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}")

        # 远程订阅是半可信内容：先做标签重命名，再 jq -e 预校验为合法 JSON，最后用
        # --argjson 传入（jq 自动 escape），避免把远程响应直接拼进 jq 过滤器。
        singBoxSubscribe=${singBoxSubscribe//tag\": \"${email}/tag\": \"${email}_${serverAlias}}
        if ! echo "${singBoxSubscribe}" | grep -q "nginx" && [[ -n "${singBoxSubscribe}" ]] && echo "${singBoxSubscribe}" | jq -e . >/dev/null 2>&1; then
            singBoxSubscribe=$(jq --argjson remote "${singBoxSubscribe}" '. += $remote' "${SUBSCRIBE_LOCAL_DIR}/sing-box/${email}")
            echo "${singBoxSubscribe}" | jq . >"${SUBSCRIBE_LOCAL_DIR}/sing-box/${email}"

            echoContent green " ---> 通用订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 不存在"
        fi

    done < <(grep -v '^$' <"${SUBSCRIBE_REMOTE_DIR}/remoteSubscribeUrl")
}

# 切换alpn
switchAlpn() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 切换alpn"
    if [[ -z ${currentAlpn} ]]; then
        echoContent red " ---> 无法读取alpn，请检查是否安装"
        exit 1
    fi

    echoContent red "\n=============================================================="
    echoContent green "当前alpn首位为:${currentAlpn}"
    echoContent yellow "  1.当http/1.1首位时，trojan可用，gRPC部分客户端可用【客户端支持手动选择alpn的可用】"
    echoContent yellow "  2.当h2首位时，gRPC可用，trojan部分客户端可用【客户端支持手动选择alpn的可用】"
    echoContent yellow "  3.如客户端不支持手动更换alpn，建议使用此功能更改服务端alpn顺序，来使用相应的协议"
    echoContent red "=============================================================="

    if [[ "${currentAlpn}" == "http/1.1" ]]; then
        echoContent yellow "1.切换alpn h2 首位"
    elif [[ "${currentAlpn}" == "h2" ]]; then
        echoContent yellow "1.切换alpn http/1.1 首位"
    else
        echoContent red '不符合'
    fi

    echoContent red "=============================================================="

    read -r -p "请选择:" selectSwitchAlpnType
    if [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "http/1.1" ]]; then

        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn = [\"h2\",\"http/1.1\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json

    elif [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "h2" ]]; then
        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn =[\"http/1.1\",\"h2\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json
    else
        echoContent red " ---> 选择错误"
        exit 1
    fi
    reloadCore
}

# 初始化realityKey
initRealityKey() {
    echoContent skyBlue "\n生成Reality key\n"
    if [[ -n "${currentRealityPublicKey}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的PublicKey/PrivateKey ？[y/n]:" historyKeyStatus
        if isYesInput "${historyKeyStatus}"; then
            realityPrivateKey=${currentRealityPrivateKey}
            realityPublicKey=${currentRealityPublicKey}
        fi
    elif [[ -n "${currentRealityPublicKey}" && -n "${lastInstallationConfig}" ]]; then
        realityPrivateKey=${currentRealityPrivateKey}
        realityPublicKey=${currentRealityPublicKey}
    fi
    if [[ -z "${realityPrivateKey}" ]]; then
        if [[ "${selectCoreType}" == "2" || "${coreKind}" == "2" ]]; then
            # 二进制预检：缺失会导致 reality-keypair 输出为空 → 后续 JSON 拼接出无效配置
            if [[ ! -f "${SINGBOX_BIN}" ]]; then
                echoContent red "\n ---> sing-box 二进制不存在，无法生成 Reality 密钥"
                echoContent yellow "     预期路径: ${SINGBOX_BIN}"
                exit 1
            fi
            realityX25519Key=$(${SINGBOX_BIN} generate reality-keypair)
            realityPrivateKey=$(echo "${realityX25519Key}" | head -1 | awk '{print $2}')
            realityPublicKey=$(echo "${realityX25519Key}" | tail -n 1 | awk '{print $2}')
        else
            # 二进制预检：缺失会让下方 x25519 输出为空，私钥为空又会触发本函数自递归 → 死循环
            if [[ ! -f "${XRAY_BIN}" ]]; then
                echoContent red "\n ---> Xray-core 二进制不存在，无法生成 Reality 密钥"
                echoContent yellow "     预期路径: ${XRAY_BIN}"
                exit 1
            fi
            read -r -p "请输入Private Key[回车自动生成]:" historyPrivateKey
            if [[ -n "${historyPrivateKey}" ]]; then
                realityX25519Key=$(${XRAY_BIN} x25519 -i "${historyPrivateKey}")
            else
                realityX25519Key=$(${XRAY_BIN} x25519)
            fi
            # 兼容新旧版本 Xray x25519 输出格式
            # 旧版: "Private key: xxx" / "Public key: xxx"
            # 新版: "PrivateKey: xxx" / "Password: xxx"
            realityPrivateKey=$(echo "${realityX25519Key}" | grep -E "Private|PrivateKey" | awk '{print $NF}')
            realityPublicKey=$(echo "${realityX25519Key}" | grep -E "Public|Password" | awk '{print $NF}')
            if [[ -z "${realityPrivateKey}" ]]; then
                echoContent red "输入的Private Key不合法"
                initRealityKey
            else
                echoContent green "\n privateKey:${realityPrivateKey}"
                echoContent green "\n publicKey:${realityPublicKey}"
            fi
        fi
    fi
    # sing-box 入站只存私钥，订阅读的公钥在这个文件里：沿用旧密钥（含从 Xray 切过来）也得写，不然发出去的 public_key 是空的
    if [[ "${selectCoreType}" == "2" || "${coreKind}" == "2" ]]; then
        echo "publicKey:${realityPublicKey}" >"${SINGBOX_FRAGMENT_DIR}/reality_key"
    fi
}

# 生成随机 Reality shortIds
# 密钥沿用上次的就连 shortId 一起沿用：重新随机后客户端手里的旧链接 sid 对不上，握手全被 reset
initRealityShortIds() {
    if [[ -z "${realityShortId1}" && -n "${currentRealityShortId}" && "${currentRealityShortId}" != "null" \
        && -n "${realityPublicKey}" && "${realityPublicKey}" == "${currentRealityPublicKey}" ]]; then
        realityShortId1=${currentRealityShortId}
        realityShortId2=${currentRealityShortId2:-$(openssl rand -hex 8)}
    fi
    if [[ -z "${realityShortId1}" ]]; then
        realityShortId1=$(openssl rand -hex 8)
        realityShortId2=$(openssl rand -hex 8)
    fi
}

# 初始化 mldsa65Seed
initRealityMldsa65() {
    echoContent skyBlue "\n生成Reality mldsa65\n"
    # 二进制预检：缺失会让 tls ping 报 No such file，下面的 -gt 比较还会因 length 为空报数值错误
    if [[ ! -f "${XRAY_BIN}" ]]; then
        echoContent red "\n ---> Xray-core 二进制不存在，无法检测目标域名能力，跳过 ML-DSA-65"
        echoContent yellow "     预期路径: ${XRAY_BIN}"
        exit 1
    fi
    if ${XRAY_BIN} tls ping "${realityServerName}:${realityDomainPort}" 2>/dev/null | grep -q "X25519MLKEM768"; then
        length=$(${XRAY_BIN} tls ping "${realityServerName}:${realityDomainPort}" | grep "Certificate chain's total length:" | awk '{print $5}' | head -1)

        if [ "$length" -gt 3500 ]; then
            if [[ -n "${currentRealityMldsa65Seed}" && -z "${lastInstallationConfig}" ]]; then
                read -r -p "读取到上次安装记录，是否使用上次安装时的Seed/Verify ？[y/n]:" historyMldsa65Status
                if isYesInput "${historyMldsa65Status}"; then
                    realityMldsa65Seed=${currentRealityMldsa65Seed}
                    realityMldsa65Verify=${currentRealityMldsa65Verify}
                fi
            elif [[ -n "${currentRealityMldsa65Seed}" && -n "${lastInstallationConfig}" ]]; then
                realityMldsa65Seed=${currentRealityMldsa65Seed}
                realityMldsa65Verify=${currentRealityMldsa65Verify}
            fi
            if [[ -z "${realityMldsa65Seed}" ]]; then
                realityMldsa65=$(${XRAY_BIN} mldsa65)
                realityMldsa65Seed=$(echo "${realityMldsa65}" | head -1 | awk '{print $2}')
                realityMldsa65Verify=$(echo "${realityMldsa65}" | tail -n 1 | awk '{print $2}')
            fi
        else
            echoContent green " 目标域名支持X25519MLKEM768，但是证书的长度不足，忽略ML-DSA-65。"
        fi
    else
        echoContent green " 目标域名不支持X25519MLKEM768，忽略ML-DSA-65。"
    fi
}
# realityDestBehindCloudflare DOMAIN → 0 = 目标挂在 Cloudflare 代理后面：Reality 会把 VPS 变成别人的免费中转。探测失败（无网/超时）按没挂
realityDestBehindCloudflare() {
    curl -s --connect-timeout 5 --max-time 10 "https://$1/cdn-cgi/trace" 2>/dev/null | grep -q "visit_scheme=https"
}

# checkRealityDest DOMAIN → 用户自己输的目标挂在 Cloudflare 代理后面时要二次确认，答否返回 1（由调用方重问）
checkRealityDest() {
    if realityDestBehindCloudflare "$1"; then
        echoContent red "\n ---> $(t REALITY_CF_WARNING)\n"
        read -r -p "$(t PROMPT_CONTINUE):" setRealityDestStatus
        if ! isYesInput "${setRealityDestStatus}"; then
            return 1
        fi
        echoContent yellow "\n ---> $(t REALITY_IGNORE_RISK)"
    fi
}

# 初始化客户端可用的ServersName
# realityDestList → Reality 与 ShadowTLS 握手目标的默认候选，逗号分隔。不含 Apple/MS 系：TLS 握手行为变化、Reality 伪装失败率高；
# 不含挂在 Cloudflare 代理后面的站（见 checkRealityDest）；不含 AWS CloudFront 与 Akamai 托管的站（按服务器上解析到的 IP 归属判）：
# 已有工具能比对它们的 TLS 栈，认出拿它们当目标的 Reality；不含 GFW 规则表上单独列出的域名：SNI 被封时节点连不上，也没有提示
realityDestList() {
    local realityDestDomainList="download-installer.cdn.mozilla.net,dl.google.com,www.google-analytics.com,www.python.org,vuejs-jp.org,vuejs.org,zh-hk.vuejs.org,react.dev,cname.vercel-dns.com,vercel-dns.com,www.fom-international.com,go.dev,pkg.go.dev,nextjs.org,svelte.dev,nuxt.com,vite.dev,pypi.org,rubygems.org,www.kernel.org,www.mozilla.org,www.firefox.com,www.php.net"
    printf '%s\n' "${realityDestDomainList}"
}

# pickRandomDest → 乱序取第一个没挂在 Cloudflare 后面的候选；全挂着就取乱序后的第一个并返回 1。随机挑的不问用户：问了而用户回车，安装会在服务已停时退出
pickRandomDest() {
    local candidate first=
    while read -r candidate; do
        [[ -z "${first}" ]] && first=${candidate}
        if ! realityDestBehindCloudflare "${candidate}"; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done < <(tr ',' '\n' <<<"$(realityDestList)" | awk -v seed="${RANDOM}" 'BEGIN {srand(seed)} {print rand() "\t" $0}' | sort -n | cut -f2-)
    printf '%s\n' "${first}"
    return 1
}

initRealityClientServersName() {
    local realityDestRandom=
    if [[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]; then
        if realityDestList | grep -q "${realityServerName}"; then
            read -r -p "读取到上次安装设置的Reality域名，是否使用？[y/n]:" realityServerNameStatus
            if ! isYesInput "${realityServerNameStatus}"; then
                realityServerName=
                realityDomainPort=
            fi
        else
            realityServerName=
            realityDomainPort=
        fi
    fi

    if [[ -z "${realityServerName}" ]]; then
        realityDestHost=
        if [[ -n "${domain}" ]]; then
            echo
            read -r -p "是否使用 ${domain} 此域名作为Reality目标域名 ？[y/n]:" realityServerNameCurrentDomainStatus
            if isYesInput "${realityServerNameCurrentDomainStatus}"; then
                if renderRealityLocalDest "${domain}"; then
                    realityServerName="${domain}"
                    realityDestHost=127.0.0.1
                    realityDomainPort=${REALITY_LOCAL_DEST_PORT}
                else
                    echoContent yellow " ---> $(t REALITY_LOCAL_DEST_NO_CERT "${domain}")"
                fi
            fi
        fi
        if [[ -z "${realityServerName}" ]]; then
            realityDomainPort=443
            echoContent skyBlue "\n================ 配置客户端可用的serverNames ===============\n"
            echoContent yellow "#注意事项"
            echoContent green "请确保所选 Reality 目标域名支持 TLS，且为可直连的常见站点。\n"
            echoContent yellow "录入示例:www.python.org:443\n"
            read -r -p "请输入目标域名，[回车]随机域名，默认端口443:" realityServerName
            if [[ -z "${realityServerName}" ]]; then
                realityServerName=$(pickRandomDest) && realityDestRandom=1
            else
                # 验证用户输入的域名（可能包含端口，先提取域名部分验证）
                local realityDomainCheck="${realityServerName%%:*}"
                if ! isValidDomain "${realityDomainCheck}"; then
                    echoContent red " ---> 域名格式无效或包含不安全字符"
                    # 重问不退出：安装走到这里时服务已停，退出会把整机留在断线状态
                    realityServerName=
                    initRealityClientServersName
                    return
                fi
            fi
            if echo "${realityServerName}" | grep -q ":"; then
                realityDomainPort=$(echo "${realityServerName}" | awk -F "[:]" '{print $2}')
                realityServerName=$(echo "${realityServerName}" | awk -F "[:]" '{print $1}')
            fi
        fi
    fi

    if [[ -z "${realityDestRandom}" ]] && ! checkRealityDest "${realityServerName}"; then
        realityServerName=
        initRealityClientServersName
        return
    fi
    echoContent yellow "\n ---> 客户端可用域名: ${realityServerName}:${realityDomainPort}\n"
}
# initXrayRealityPort KEEP SKIP [EXTRA...] → 选 7 的对外端口写进 realityPort，参数同 portsTakenFor
# 选出的端口若还被旧的 Xray 占着，handleXray start 重启时随新配置接管，这里不用先停
initXrayRealityPort() {
    realityPort=$(pickInboundPort 7 "${xrayVLESSRealityPort}" "${XRAY_CONF_DIR}" "$@")
    allowPort "${realityPort}"
    echoContent yellow "\n ---> 端口: ${realityPort}"
}
# initXrayXHTTPort KEEP SKIP [EXTRA...] → 选 12 的对外端口写进 xHTTPort，同上
initXrayXHTTPort() {
    xHTTPort=$(pickInboundPort 12 "${xrayVLESSRealityXHTTPort}" "${XRAY_CONF_DIR}" "$@")
    allowPort "${xHTTPort}"
    allowPort "${xHTTPort}" "udp"
    echoContent yellow "\n ---> 端口: ${xHTTPort}"
}

# reality管理
manageReality() {
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig

    if ! echo "${currentInstallProtocolType}" | grep -q -E ",7,|,8," || [[ -z "${coreKind}" ]]; then
        echoContent red "\n ---> 请先安装Reality协议，并确认已配置可用的 serverName/公钥。"
        exit 1
    fi

    if [[ "${coreKind}" == "1" ]]; then
        selectCustomInstallType=",7,"
        initXrayConfig custom 1 true
    elif [[ "${coreKind}" == "2" ]]; then
        if echo "${currentInstallProtocolType}" | grep -q ",7,"; then
            selectCustomInstallType=",7,"
        fi
        if echo "${currentInstallProtocolType}" | grep -q ",8,"; then
            selectCustomInstallType="${selectCustomInstallType},8,"
        fi
        initSingBoxConfig custom 1 true
    fi

    reloadCore
    # 没配过订阅的（菜单 19 装的 Reality）不拖进订阅初始化：那里答 n 就退出，开好的端口和下载的站点文件都留着
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    else
        totalProgress=1
        showAccounts 1
    fi
}

# hysteria管理
manageHysteria() {
    echoContent skyBlue "\n进度  1/1 : Hysteria2 管理"
    echoContent red "\n=============================================================="
    local hysteria2Status=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "${SINGBOX_FRAGMENT_DIR}/06_hysteria2_inbounds.json" ]]; then
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.重新安装"
        echoContent yellow "2.卸载"
        echoContent yellow "3.端口跳跃管理"
        hysteria2Status=true
    else
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.安装"
    fi

    echoContent red "=============================================================="
    read -r -p "请选择:" installHysteria2Status
    if [[ "${installHysteria2Status}" == "1" ]]; then
        singBoxHysteria2Install
    elif [[ "${installHysteria2Status}" == "2" && "${hysteria2Status}" == "true" ]]; then
        unInstallSingBox hysteria2
    elif [[ "${installHysteria2Status}" == "3" && "${hysteria2Status}" == "true" ]]; then
        portHoppingMenu hysteria2
    fi
}

# tuic管理
manageTuic() {
    echoContent skyBlue "\n进度  1/1 : Tuic管理"
    echoContent red "\n=============================================================="
    local tuicStatus=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "${SINGBOX_FRAGMENT_DIR}/09_tuic_inbounds.json" ]]; then
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.重新安装"
        echoContent yellow "2.卸载"
        tuicStatus=true
    else
        echoContent yellow "依赖sing-box内核\n"
        echoContent yellow "1.安装"
    fi

    echoContent red "=============================================================="
    read -r -p "请选择:" installTuicStatus
    if [[ "${installTuicStatus}" == "1" ]]; then
        singBoxTuicInstall
    elif [[ "${installTuicStatus}" == "2" && "${tuicStatus}" == "true" ]]; then
        unInstallSingBox tuic
    fi
}
# sing-box log日志
singBoxLog() {
    cat <<EOF >${SINGBOX_FRAGMENT_DIR}/log.json
{
  "log": {
    "disabled": $1,
    "level": "warn",
    "output": "${SINGBOX_CONF_DIR}/box.log",
    "timestamp": true
  }
}
EOF

    handleSingBox stop
    handleSingBox start
}

# sing-box 版本管理
singBoxVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : sing-box 版本管理"
    if [[ -z "${singBoxConfigPath}" ]]; then
        echoContent red " ---> 没有检测到安装程序，请执行脚本安装内容"
        menu
        exit 1
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级 sing-box"
    echoContent yellow "2.关闭 sing-box"
    echoContent yellow "3.打开 sing-box"
    echoContent yellow "4.重启 sing-box"
    echoContent yellow "=============================================================="
    local logStatus=
    if [[ -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}log.json" && "$(jq -r .log.disabled "${singBoxConfigPath}log.json")" == "false" ]]; then
        echoContent yellow "5.关闭日志"
        logStatus=true
    else
        echoContent yellow "5.启用日志"
        logStatus=false
    fi

    echoContent yellow "6.查看日志"
    echoContent red "=============================================================="

    read -r -p "请选择:" selectSingBoxType
    if [[ ! -f "${singBoxConfigPath}../box.log" ]]; then
        touch "${singBoxConfigPath}../box.log" >/dev/null 2>&1
    fi
    if [[ "${selectSingBoxType}" == "1" ]]; then
        installSingBox 1 || { echoContent red "\n ---> sing-box 安装失败"; exit 1; }
        handleSingBox stop
        handleSingBox start
    elif [[ "${selectSingBoxType}" == "2" ]]; then
        handleSingBox stop
    elif [[ "${selectSingBoxType}" == "3" ]]; then
        handleSingBox start
    elif [[ "${selectSingBoxType}" == "4" ]]; then
        handleSingBox stop
        handleSingBox start
    elif [[ "${selectSingBoxType}" == "5" ]]; then
        singBoxLog ${logStatus}
        if [[ "${logStatus}" == "false" ]]; then
            tail -f "${singBoxConfigPath}../box.log"
        fi
    elif [[ "${selectSingBoxType}" == "6" ]]; then
        tail -f "${singBoxConfigPath}../box.log"
    fi
}

# ============================================================================
# 切换语言 / Switch Language
# ============================================================================
switchLanguage() {
    local langFile="${PROXY_AGENT_DIR}/lang_pref"
    local currentLang="${CURRENT_LANG:-zh_CN}"
    local scriptPath="${PROXY_AGENT_DIR}/install.sh"

    # 如果安装目录的脚本不存在，使用当前脚本路径
    if [[ ! -f "${scriptPath}" ]]; then
        scriptPath="${_SCRIPT_DIR}/install.sh"
    fi

    echoContent red "\n=============================================================="
    echoContent skyBlue "当前语言 / Current Language: ${currentLang}"
    echoContent red "=============================================================="
    echoContent yellow "1. 中文 (Chinese)"
    echoContent yellow "2. English"
    echoContent yellow "0. 返回 / Back"
    echoContent red "=============================================================="

    read -r -p "请选择 / Select: " langChoice

    case "${langChoice}" in
        1)
            echo "zh_CN" > "${langFile}"
            export V2RAY_LANG="zh_CN"
            echoContent green "语言已设置为中文，重新加载菜单..."
            sleep 1
            exec bash "${scriptPath}"
            ;;
        2)
            echo "en_US" > "${langFile}"
            export V2RAY_LANG="en_US"
            echoContent green "Language set to English, reloading menu..."
            sleep 1
            exec bash "${scriptPath}"
            ;;
        0|*)
            menu
            ;;
    esac
}

# ============================================================================
# doctor —— 只读诊断（不写配置 / 防火墙 / 证书 / 服务）。任意 FAIL 返回非零。
# ============================================================================

_doctor_pass=0
_doctor_warn=0
_doctor_fail=0
_doctor_skip=0

_doctorSection() {
    echoContent skyBlue "\n--- $1 ---"
}

# 用法: _doctorRow LABEL pass|warn|fail|skip [DETAIL]
_doctorRow() {
    local label="$1"
    local status="$2"
    local detail="${3:-}"
    local statusText
    case "${status}" in
        pass)
            ((_doctor_pass++)) || true
            statusText="$(echoContent green "[$(t DOCTOR_STATUS_PASS)]")"
            ;;
        warn)
            ((_doctor_warn++)) || true
            statusText="$(echoContent yellow "[$(t DOCTOR_STATUS_WARN)]")"
            ;;
        fail)
            ((_doctor_fail++)) || true
            statusText="$(echoContent red "[$(t DOCTOR_STATUS_FAIL)]")"
            ;;
        skip|*)
            ((_doctor_skip++)) || true
            statusText="$(echoContent yellow "[$(t DOCTOR_STATUS_SKIP)]")"
            ;;
    esac
    if [[ -n "${detail}" ]]; then
        printf '  %s %s — %s\n' "${statusText}" "${label}" "${detail}"
    else
        printf '  %s %s\n' "${statusText}" "${label}"
    fi
}

_doctorCheckSystem() {
    _doctorSection "$(t DOCTOR_SECTION_SYSTEM)"

    if [[ "$(id -u)" == "0" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_ROOT)" pass "uid=0"
    else
        _doctorRow "$(t DOCTOR_CHECK_ROOT)" fail "uid=$(id -u)"
    fi

    if [[ -r /etc/os-release ]]; then
        local osID osVer
        osID=$(. /etc/os-release && echo "${ID:-unknown}")
        osVer=$(. /etc/os-release && echo "${VERSION_ID:-?}")
        _doctorRow "$(t DOCTOR_CHECK_OS)" pass "${osID} ${osVer}"
    else
        _doctorRow "$(t DOCTOR_CHECK_OS)" warn "/etc/os-release not found"
    fi

    _doctorRow "$(t DOCTOR_CHECK_CPU)" pass "$(uname -m)"

    local cmd missing=""
    for cmd in jq openssl curl wget; do
        command -v "${cmd}" >/dev/null 2>&1 || missing="${missing}${missing:+, }${cmd}"
    done
    if [[ -z "${missing}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_COMMANDS)" pass "jq openssl curl wget"
    else
        _doctorRow "$(t DOCTOR_CHECK_COMMANDS)" fail "missing: ${missing}"
    fi

    if command -v getenforce >/dev/null 2>&1; then
        local sel
        sel=$(getenforce 2>/dev/null || echo unknown)
        case "${sel}" in
            Disabled|Permissive)
                _doctorRow "$(t DOCTOR_CHECK_SELINUX)" pass "${sel}"
                ;;
            Enforcing)
                _doctorRow "$(t DOCTOR_CHECK_SELINUX)" warn "${sel} (may block proxy ports — see checkCentosSELinux)"
                ;;
            *)
                _doctorRow "$(t DOCTOR_CHECK_SELINUX)" warn "${sel}"
                ;;
        esac
    else
        _doctorRow "$(t DOCTOR_CHECK_SELINUX)" skip "$(t DOCTOR_DETAIL_NOT_CENTOS)"
    fi
}

_doctorCheckInstall() {
    _doctorSection "$(t DOCTOR_SECTION_INSTALL)"

    if [[ -d ${PROXY_AGENT_DIR} ]]; then
        _doctorRow "$(t DOCTOR_CHECK_INSTALLED)" pass "${PROXY_AGENT_DIR}"
    else
        _doctorRow "$(t DOCTOR_CHECK_INSTALLED)" fail "missing ${PROXY_AGENT_DIR}"
    fi

    if [[ -r ${PROXY_AGENT_DIR}/VERSION ]]; then
        local ver
        ver=$(tr -d '[:space:]' <${PROXY_AGENT_DIR}/VERSION 2>/dev/null)
        _doctorRow "$(t DOCTOR_CHECK_VERSION)" pass "${ver:-?}"
    elif [[ -n "${SCRIPT_VERSION:-}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_VERSION)" pass "${SCRIPT_VERSION} (from running script)"
    else
        _doctorRow "$(t DOCTOR_CHECK_VERSION)" warn "VERSION file not found"
    fi

    local libDir mod libMissing=""
    libDir="${_LIB_DIR:-${PROXY_AGENT_DIR}/lib}"
    for mod in i18n constants utils json-utils system-detect protocol-registry carpool topo; do
        [[ -f "${libDir}/${mod}.sh" ]] || libMissing="${libMissing}${libMissing:+, }${mod}.sh"
    done
    if [[ -z "${libMissing}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_LIB)" pass "${libDir}"
    else
        _doctorRow "$(t DOCTOR_CHECK_LIB)" fail "missing: ${libMissing}"
    fi

    local langDir f langMissing=""
    if [[ -d "${_SCRIPT_DIR}/shell/lang" ]]; then
        langDir="${_SCRIPT_DIR}/shell/lang"
    else
        langDir="${_LANG_FALLBACK_DIR:-${PROXY_AGENT_DIR}/shell/lang}"
    fi
    for f in zh_CN.sh en_US.sh; do
        [[ -f "${langDir}/${f}" ]] || langMissing="${langMissing}${langMissing:+, }${f}"
    done
    if [[ -z "${langMissing}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_LANG)" pass "${langDir}"
    else
        _doctorRow "$(t DOCTOR_CHECK_LANG)" fail "missing: ${langMissing}"
    fi
}

_doctorCheckCore() {
    _doctorSection "$(t DOCTOR_SECTION_CORE)"

    if [[ -z "${coreKind}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CORE_KIND)" skip "$(t DOCTOR_DETAIL_NO_CORE)"
        return
    fi

    # 判活与 handle* 同一口径：Xray 用 xrayDaemonRunning，sing-box 用 pgrep -x sing-box
    local coreName binaryPath serviceName running=
    if [[ "${coreKind}" == "1" ]]; then
        coreName="Xray-core"
        binaryPath="${XRAY_BIN}"
        serviceName="xray"
    else
        coreName="sing-box"
        binaryPath="${SINGBOX_BIN}"
        serviceName="sing-box"
    fi
    _doctorRow "$(t DOCTOR_CHECK_CORE_KIND)" pass "${coreName}"

    if [[ -x "${binaryPath}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CORE_BINARY)" pass "${binaryPath}"
        local ver
        if [[ "${coreKind}" == "1" ]]; then
            ver=$("${binaryPath}" --version 2>/dev/null | awk '{print $2}' | head -1)
        else
            ver=$("${binaryPath}" version 2>/dev/null | head -1 | awk '{print $3}')
        fi
        if [[ -n "${ver}" ]]; then
            _doctorRow "$(t DOCTOR_CHECK_CORE_VERSION)" pass "${ver}"
        else
            _doctorRow "$(t DOCTOR_CHECK_CORE_VERSION)" warn "could not parse version output"
        fi
    else
        _doctorRow "$(t DOCTOR_CHECK_CORE_BINARY)" fail "missing or not executable: ${binaryPath}"
        _doctorRow "$(t DOCTOR_CHECK_CORE_VERSION)" skip "binary missing"
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${serviceName}.service" 2>/dev/null | grep -q "^${serviceName}\.service"; then
        if systemctl is-active --quiet "${serviceName}.service" 2>/dev/null; then
            _doctorRow "$(t DOCTOR_CHECK_SERVICE)" pass "systemd: ${serviceName}.service active"
        else
            _doctorRow "$(t DOCTOR_CHECK_SERVICE)" warn "systemd: ${serviceName}.service inactive"
        fi
    elif [[ -f "/etc/init.d/${serviceName}" ]]; then
        if rc-service "${serviceName}" status >/dev/null 2>&1; then
            _doctorRow "$(t DOCTOR_CHECK_SERVICE)" pass "OpenRC: ${serviceName} started"
        else
            _doctorRow "$(t DOCTOR_CHECK_SERVICE)" warn "OpenRC: ${serviceName} stopped"
        fi
    else
        _doctorRow "$(t DOCTOR_CHECK_SERVICE)" warn "service unit not found"
    fi

    if [[ "${coreKind}" == "1" ]]; then
        xrayDaemonRunning && running=1
    elif pgrep -x sing-box >/dev/null 2>&1; then
        running=1
    fi
    if [[ -n "${running}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_PROCESS)" pass "running"
    else
        _doctorRow "$(t DOCTOR_CHECK_PROCESS)" warn "not running"
    fi
}

_doctorCheckConfig() {
    _doctorSection "$(t DOCTOR_SECTION_CONFIG)"

    if [[ -z "${coreKind}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CONFIG)" skip "$(t DOCTOR_DETAIL_NO_CORE)"
        _doctorRow "$(t DOCTOR_CHECK_PROTOCOLS)" skip "$(t DOCTOR_DETAIL_NO_CORE)"
        return
    fi

    if chainExternalSingleOnXray; then
        _doctorRow "$(t DOCTOR_CHECK_CHAIN_EXIT)" fail "$(t EXT_SINGLE_EXIT_XRAY_WARNING)"
    fi

    if [[ "${coreKind}" == "1" ]]; then
        local confDir="${XRAY_CONF_DIR}"
        local f base total=0 bad=0 badList=""
        if [[ -d "${confDir}" ]]; then
            shopt -s nullglob
            for f in "${confDir}"/*.json; do
                ((total++)) || true
                if ! jsonIsSingleValue <"${f}"; then
                    ((bad++)) || true
                    base=$(basename "${f}")
                    badList="${badList}${badList:+, }${base}"
                fi
            done
            shopt -u nullglob
        fi
        if [[ "${total}" -eq 0 ]]; then
            _doctorRow "$(t DOCTOR_CHECK_CONFIG)" warn "no JSON files in ${confDir}"
        elif [[ "${bad}" -eq 0 ]]; then
            _doctorRow "$(t DOCTOR_CHECK_CONFIG)" pass "${total} files OK"
        else
            _doctorRow "$(t DOCTOR_CHECK_CONFIG)" fail "${bad}/${total} invalid: ${badList}"
        fi
    else
        local mergedConfig="${SINGBOX_MERGED_CONFIG}"
        local binary="${SINGBOX_BIN}"
        if [[ -x "${binary}" && -f "${mergedConfig}" ]]; then
            if "${binary}" check -c "${mergedConfig}" >/dev/null 2>&1; then
                _doctorRow "$(t DOCTOR_CHECK_CONFIG)" pass "sing-box check OK"
            else
                _doctorRow "$(t DOCTOR_CHECK_CONFIG)" fail "sing-box check failed: ${mergedConfig}"
            fi
        else
            _doctorRow "$(t DOCTOR_CHECK_CONFIG)" warn "merged config or binary not found"
        fi
    fi

    local count=0 trimmed
    if [[ -n "${currentInstallProtocolType}" ]]; then
        trimmed="${currentInstallProtocolType#,}"
        trimmed="${trimmed%,}"
        if [[ -n "${trimmed}" ]]; then
            count=$(echo "${trimmed}" | tr ',' '\n' | grep -c .)
        fi
    fi
    _doctorRow "$(t DOCTOR_CHECK_PROTOCOLS)" pass "${count}"
}

_doctorCheckNetwork() {
    _doctorSection "$(t DOCTOR_SECTION_NETWORK)"

    local pubIP
    pubIP=$(curl --max-time 5 -fsSL https://api.ipify.org 2>/dev/null)
    if [[ -n "${pubIP}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_PUBLICIP)" pass "${pubIP}"
    else
        _doctorRow "$(t DOCTOR_CHECK_PUBLICIP)" warn "unreachable / timeout"
    fi

    if curl --max-time 5 -fsS -o /dev/null https://api.github.com/zen 2>/dev/null; then
        _doctorRow "$(t DOCTOR_CHECK_GITHUB)" pass "reachable"
    else
        _doctorRow "$(t DOCTOR_CHECK_GITHUB)" warn "unreachable / timeout"
    fi

    _doctorCheckClock
}

# _doctorCheckClock → 本机时钟与 Cloudflare 的差。容差最小的是 SS2022 的 30 秒（链式桥也用它），两台机器各偏一半就到头，所以 15 秒起告警。
# 只告警不动系统：校时服务是用户自己的，容器里也校不了
_doctorCheckClock() {
    local remoteTs drift
    remoteTs=$(curl --max-time 5 -fsS https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | sed -n 's/^ts=\([0-9]*\).*/\1/p')
    if [[ -z "${remoteTs}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CLOCK)" skip "unreachable / timeout"
        return 0
    fi
    drift=$(($(date +%s) - remoteTs))
    if ((drift < 0)); then
        drift=$((-drift))
    fi
    if ((drift < 15)); then
        _doctorRow "$(t DOCTOR_CHECK_CLOCK)" pass "$(t DOCTOR_DETAIL_CLOCK_OK "${drift}")"
    elif systemd-detect-virt -cq 2>/dev/null; then
        _doctorRow "$(t DOCTOR_CHECK_CLOCK)" warn "$(t DOCTOR_DETAIL_CLOCK_DRIFT_CONTAINER "${drift}")"
    else
        _doctorRow "$(t DOCTOR_CHECK_CLOCK)" warn "$(t DOCTOR_DETAIL_CLOCK_DRIFT "${drift}")"
    fi
}

_doctorCheckCert() {
    _doctorSection "$(t DOCTOR_SECTION_CERT)"

    local tlsDir="${TLS_DIR}"
    if [[ ! -d "${tlsDir}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_DIR)" skip "$(t DOCTOR_DETAIL_NO_TLS)"
        return
    fi
    _doctorRow "$(t DOCTOR_CHECK_CERT_DIR)" pass "${tlsDir}"

    local needsCert=0 trimmed pid
    if [[ -n "${currentInstallProtocolType}" ]]; then
        trimmed="${currentInstallProtocolType#,}"
        trimmed="${trimmed%,}"
        for pid in ${trimmed//,/ }; do
            if protocolRequiresTLS "${pid}" 2>/dev/null; then
                needsCert=1
                break
            fi
        done
    fi

    if [[ "${needsCert}" == "0" ]]; then
        if [[ -z "${currentInstallProtocolType//,/}" ]]; then
            # 只跑链式角色的 sing-box 机器没有协议入站，但核心是装着的
            local why
            if [[ -n "${coreKind}" ]] || { [[ -f "${SINGBOX_BIN}" ]] && compgen -G "${SINGBOX_FRAGMENT_DIR}/*.json" >/dev/null; }; then
                why=$(t DOCTOR_DETAIL_NO_TLS_PROTOCOL)
            else
                why=$(t DOCTOR_DETAIL_NO_CORE)
            fi
            _doctorRow "$(t DOCTOR_CHECK_CERT_EXPIRY)" skip "${why}"
            _doctorRow "$(t DOCTOR_CHECK_CERT_MATCH)" skip "${why}"
        else
            _doctorRow "$(t DOCTOR_CHECK_CERT_EXPIRY)" skip "$(t DOCTOR_DETAIL_REALITY_ONLY)"
            _doctorRow "$(t DOCTOR_CHECK_CERT_MATCH)" skip "$(t DOCTOR_DETAIL_REALITY_ONLY)"
        fi
        return
    fi

    local crt key pairs
    pairs=$(_doctorCertsInUse)
    if [[ -z "${pairs}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_EXPIRY)" warn "$(t DOCTOR_DETAIL_NO_CERT_IN_USE)"
        _doctorRow "$(t DOCTOR_CHECK_CERT_MATCH)" skip "$(t DOCTOR_DETAIL_NO_CERT_IN_USE)"
        return
    fi
    while IFS=$'\t' read -r crt key; do
        _doctorCheckOneCert "${crt}" "${key}"
    done <<<"${pairs}"
}

# _doctorConfigFiles → 这台机器的内核在读的配置片段，一行一个（Xray 机上的旁挂 sing-box 也算）
_doctorConfigFiles() {
    local f
    for f in "${XRAY_CONF_DIR}"/*.json "${SINGBOX_FRAGMENT_DIR}"/*.json; do
        [[ -f "${f}" ]] || continue
        [[ "${f}" == "${XRAY_CONF_DIR}/"* && "${coreKind}" != "1" ]] && continue
        [[ "${f}" == "${SINGBOX_FRAGMENT_DIR}/"* && "${coreKind}" != "2" && ! -f "${SINGBOX_BIN}" ]] && continue
        printf '%s\n' "${f}"
    done
}

# _doctorJqFiles FILTER FILE... → 逐个文件跑 jq -r；读不了的文件跳过，它们由配置那一节报
_doctorJqFiles() {
    local filter=$1 f
    shift
    for f in "$@"; do
        jq -r "${filter}" "${f}" 2>/dev/null
    done
}

# _doctorCertsInUse → 在用的证书「证书路径<TAB>私钥路径」，一行一对：配置里引用的，加当前域名的（11 的证书只写在 nginx 里）。
# 不能按 tls/ 取：换域名后旧证书还留在那里，查到它就是假 FAIL 或假 PASS
_doctorCertsInUse() {
    local files=()
    mapfile -t files < <(_doctorConfigFiles)
    {
        _doctorJqFiles '.. | objects | select(.certificateFile? or .certificate_path?)
            | "\(.certificateFile // .certificate_path)\t\(.keyFile // .key_path // "")"' "${files[@]}"
        if [[ -n "${currentHost}" && -f "${TLS_DIR}/${currentHost}.crt" ]]; then
            printf '%s\t%s\n' "${TLS_DIR}/${currentHost}.crt" "${TLS_DIR}/${currentHost}.key"
        fi
    } | sort -u
}

# _doctorCheckOneCert CRT KEY → 一张在用证书的到期、配对、自签、域名覆盖、证书链
_doctorCheckOneCert() {
    local crt=$1 key=$2 name renewDays=14 blocks out
    name=$(basename "${crt}")
    # 续期窗口 15 天、cron 每天跑一次，少于 14 天还没换说明续期出了问题；设成 15 健康机器会黄一天
    if ! verifyCertExpiry "${crt}" >/dev/null 2>&1; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_EXPIRY)" fail "$(t DOCTOR_DETAIL_CERT_EXPIRED "${name}")"
        return
    elif ! openssl x509 -in "${crt}" -noout -checkend $((renewDays * 86400)) >/dev/null 2>&1; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_EXPIRY)" warn "$(t DOCTOR_DETAIL_CERT_EXPIRING "${name}" "${renewDays}")"
    else
        _doctorRow "$(t DOCTOR_CHECK_CERT_EXPIRY)" pass "${name}"
    fi

    if verifyCertKeyMatch "${crt}" "${key}" >/dev/null 2>&1; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_MATCH)" pass "${name}"
    else
        _doctorRow "$(t DOCTOR_CHECK_CERT_MATCH)" fail "$(t DOCTOR_DETAIL_CERT_MISMATCH "${name}")"
    fi

    local selfSigned=no
    if [[ "$(openssl x509 -in "${crt}" -noout -issuer_hash 2>/dev/null)" == "$(openssl x509 -in "${crt}" -noout -subject_hash 2>/dev/null)" ]]; then
        selfSigned=yes
        _doctorRow "$(t DOCTOR_CHECK_CERT_SELF_SIGNED)" fail "$(t DOCTOR_DETAIL_CERT_SELF_SIGNED "${name}")"
    fi

    # 脚本的证书都叫 tls/<域名>.crt；手改成别的路径时读不出域名，不猜。-checkhost 不匹配时各版本退出码不一，看文字
    if [[ "${crt}" == "${TLS_DIR}/"*.crt ]]; then
        out=$(openssl x509 -in "${crt}" -noout -checkhost "${name%.crt}" 2>/dev/null)
        case "${out}" in
            *"does match"*) _doctorRow "$(t DOCTOR_CHECK_CERT_HOST)" pass "${name%.crt}" ;;
            *"does NOT match"*) _doctorRow "$(t DOCTOR_CHECK_CERT_HOST)" fail "$(t DOCTOR_DETAIL_CERT_HOST "${name%.crt}")" ;;
            *) _doctorRow "$(t DOCTOR_CHECK_CERT_HOST)" skip "${name%.crt}" ;;
        esac
    fi

    blocks=$(grep -c 'BEGIN CERTIFICATE' "${crt}" 2>/dev/null)
    if [[ "${selfSigned}" == "no" && "${blocks:-0}" -lt 2 ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_CHAIN)" warn "$(t DOCTOR_DETAIL_CERT_CHAIN "${name}")"
    elif [[ "${selfSigned}" == "no" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_CERT_CHAIN)" pass "${name}"
    fi
}

# auditUuidWeak UUID → 0=公开的示例值或全同一位，谁都猜得到
auditUuidWeak() {
    local hex=${1//-/}
    hex=${hex,,}
    [[ -z "${hex//${hex:0:1}/}" ]] && return 0
    case "${hex}" in
        550e8400e29b41d4a716446655440000 | 123e4567e89b12d3a456426614174000 | f47ac10b58cc4372a5670e02b2c3d479 | \
            123456781234123412341234567890ab | 12345678123412341234123456789012 | 0123456789abcdef0123456789abcdef)
            return 0
            ;;
    esac
    return 1
}

# _doctorCheckSecurity → 配置里读得出来的安全问题：只读、不联网。只有确定的缺陷才 fail（退出码归它们管）
_doctorCheckSecurity() {
    _doctorSection "$(t DOCTOR_SECTION_SECURITY)"
    local files=()
    mapfile -t files < <(_doctorConfigFiles)
    if [[ ${#files[@]} -eq 0 ]]; then
        _doctorRow "$(t DOCTOR_CHECK_WEAK_UUID)" skip "$(t DOCTOR_DETAIL_NO_CORE)"
        return
    fi

    local u name total=0 weak="" list
    while IFS=$'\t' read -r u name; do
        ((total++)) || true
        auditUuidWeak "${u}" && weak+="${name%-*}"$'\n'
    done < <(_doctorJqFiles '.inbounds[]? | .. | objects | (.id? // .uuid? // .password?) as $u
        | select(($u | type) == "string" and ($u | test("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")))
        | "\($u)\t\(.email // .name // "-")"' "${files[@]}")
    if [[ -n "${weak}" ]]; then
        list=$(sort -u <<<"${weak}" | grep . | paste -sd, -)
        _doctorRow "$(t DOCTOR_CHECK_WEAK_UUID)" fail "$(t DOCTOR_DETAIL_WEAK_UUID "${list}")"
    else
        _doctorRow "$(t DOCTOR_CHECK_WEAK_UUID)" pass "${total}"
    fi

    list=$(_doctorJqFiles '.outbounds[]? | select(.tls.insecure? == true or .streamSettings.tlsSettings.allowInsecure? == true) | .tag // "-"' "${files[@]}" | sort -u | paste -sd, -)
    if [[ -n "${list}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_TLS_VERIFY)" warn "$(t DOCTOR_DETAIL_TLS_VERIFY "${list}")"
    else
        _doctorRow "$(t DOCTOR_CHECK_TLS_VERIFY)" pass
    fi

    list=$(_doctorJqFiles '.log.loglevel? // .log.level? // empty' "${files[@]}" | sort -u | paste -sd, -)
    case ",${list}," in
        *,debug,* | *,trace,*) _doctorRow "$(t DOCTOR_CHECK_LOG_LEVEL)" warn "$(t DOCTOR_DETAIL_LOG_LEVEL "${list}")" ;;
        *) _doctorRow "$(t DOCTOR_CHECK_LOG_LEVEL)" pass "${list}" ;;
    esac

    if [[ "${coreKind}" == "1" ]]; then
        local accessLog
        accessLog=$(_doctorJqFiles '.log.access? // empty' "${files[@]}" | grep -v -x -F none | head -n 1)
        if [[ -n "${accessLog}" ]]; then
            _doctorRow "$(t DOCTOR_CHECK_ACCESS_LOG)" warn "$(t DOCTOR_DETAIL_ACCESS_LOG "${accessLog}" "$(wc -c <"${accessLog}" 2>/dev/null | tr -d ' ')")"
        else
            _doctorRow "$(t DOCTOR_CHECK_ACCESS_LOG)" pass
        fi
    fi
}

_doctorCheckFirewall() {
    _doctorSection "$(t DOCTOR_SECTION_FIREWALL)"

    local detected=""
    if command -v ufw >/dev/null 2>&1; then
        local ufwStatus
        ufwStatus=$(ufw status 2>/dev/null | head -1)
        detected="ufw: ${ufwStatus}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
            detected="firewalld: running"
        else
            detected="firewalld: not running"
        fi
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q .; then
        detected="nftables: ruleset present"
    elif command -v iptables >/dev/null 2>&1; then
        local rules
        rules=$(iptables -S 2>/dev/null | wc -l | tr -d '[:space:]')
        detected="iptables: ${rules} rules"
    fi

    if [[ -n "${detected}" ]]; then
        _doctorRow "$(t DOCTOR_CHECK_FIREWALL)" pass "${detected}"
    else
        _doctorRow "$(t DOCTOR_CHECK_FIREWALL)" warn "no firewall manager detected"
    fi
}

# 主入口：仅读取，不修改任何东西。返回值：FAIL>0 时非零，方便脚本化调用。
doctor() {
    _doctor_pass=0
    _doctor_warn=0
    _doctor_fail=0
    _doctor_skip=0

    echoContent skyBlue "\n=============================================================="
    echoContent skyBlue "  $(t DOCTOR_HEADER)"
    echoContent skyBlue "=============================================================="

    _doctorCheckSystem
    _doctorCheckInstall
    _doctorCheckCore
    _doctorCheckConfig
    _doctorCheckNetwork
    _doctorCheckCert
    _doctorCheckSecurity
    _doctorCheckFirewall

    echoContent skyBlue "\n=============================================================="
    echoContent green "  $(t DOCTOR_SUMMARY): $(t DOCTOR_STATUS_PASS)=${_doctor_pass}  $(t DOCTOR_STATUS_WARN)=${_doctor_warn}  $(t DOCTOR_STATUS_FAIL)=${_doctor_fail}  $(t DOCTOR_STATUS_SKIP)=${_doctor_skip}"
    echoContent yellow "  $(t DOCTOR_FOOTER_HINT)"
    echoContent skyBlue "=============================================================="

    if [[ "${_doctor_fail}" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# 主菜单
menu() {
    cd "$HOME" || exit
    if isDryRun; then
        echoContent yellow "\n$(t DRY_RUN_BANNER)"
    else
        ensureSubscribeConfCurrent
    fi
    echoContent red "\n=============================================================="
    echoContent green "$(t MENU_AUTHOR): Lynthar"

    # 显示版本号，并在后台检查更新
    local versionDisplay="${SCRIPT_VERSION}"
    if [[ -n "${LATEST_VERSION}" ]] && compareVersions "${SCRIPT_VERSION}" "${LATEST_VERSION}"; then
        versionDisplay="${SCRIPT_VERSION} -> ${LATEST_VERSION} [有更新/Update Available]"
        echoContent yellow "$(t MENU_VERSION): ${versionDisplay}"
    else
        echoContent green "$(t MENU_VERSION): ${versionDisplay}"
    fi

    echoContent green "$(t MENU_GITHUB): https://github.com/Lynthar/Proxy-agent"
    echoContent green "$(t MENU_DESC): $(t MENU_TITLE)"
    showInstallStatus
    checkWgetShowProgress
    if [[ -n "${coreKind}" ]]; then
        echoContent yellow "1.$(t MENU_REINSTALL)"
    else
        echoContent yellow "1.$(t MENU_INSTALL)"
    fi

    echoContent yellow "2.$(t MENU_COMBO_INSTALL)"
    echoContent yellow "3.$(t MENU_CHAIN_PROXY)"
    echoContent yellow "4.$(t MENU_HYSTERIA2)"
    echoContent yellow "5.$(t MENU_REALITY)"
    echoContent yellow "6.$(t MENU_TUIC)"

    echoContent skyBlue "-------------------------$(t MENU_TOOL_MGMT)-----------------------------"
    echoContent yellow "7.$(t MENU_USER)"
    echoContent yellow "8.$(t MENU_DISGUISE)"
    echoContent yellow "9.$(t MENU_CERT)"
    echoContent yellow "11.$(t MENU_ROUTING)"
    echoContent yellow "12.$(t MENU_ADD_PORT)"
    echoContent skyBlue "-------------------------$(t MENU_VERSION_MGMT)-----------------------------"
    echoContent yellow "16.$(t MENU_CORE)"
    echoContent yellow "17.$(t MENU_UPDATE_SCRIPT)"
    echoContent yellow "18.$(t MENU_BBR)"
    echoContent yellow "19.$(t MENU_REALITY_QUICK)"
    echoContent skyBlue "-------------------------$(t MENU_SCRIPT_MGMT)-----------------------------"
    echoContent yellow "20.$(t MENU_UNINSTALL)"
    echoContent yellow "21.切换语言 / Switch Language"
    echoContent yellow "22.$(t MENU_SCRIPT_VERSION)"
    echoContent yellow "23.$(t MENU_DOCTOR)"
    echoContent yellow "24.$(t MENU_TOPO)"
    echoContent red "=============================================================="
    # dry-run 下不建目录树、不装 pasly 别名——mkdirTools/aliasInstall 都是真实写盘
    if ! isDryRun; then
        mkdirTools
        aliasInstall
    fi
    read -r -p "$(t PROMPT_SELECT):" selectInstallType
    case ${selectInstallType} in
    1)
        selectCoreInstall
        ;;
    2)
        selectCoreInstall
        ;;
    3)
        chainProxyMenu
        ;;
    4)
        manageHysteria
        ;;
    5)
        manageReality 1
        ;;
    6)
        manageTuic
        ;;
    7)
        manageAccount 1
        ;;
    8)
        updateNginxBlog 1
        ;;
    9)
        renewalTLS 1
        ;;
    11)
        routingToolsMenu 1
        ;;
    12)
        addCorePort 1
        ;;
    14)
        switchAlpn 1
        ;;
    16)
        coreVersionManageMenu 1
        ;;
    17)
        updateV2RayAgent 1
        ;;
    18)
        bbrInstall
        ;;
    19)
        selectRealityCoreInstall
        ;;
    20)
        unInstall 1
        ;;
    21)
        switchLanguage
        ;;
    22)
        scriptVersionMenu
        ;;
    23)
        doctor
        ;;
    24)
        topoCommand
        ;;
    esac
}

# ============================================================================
# 路由总览（pasly topo / 菜单 24）：只读。把生效配置采成模型交给 lib/topo.sh 渲染，不写配置、不重启服务
# ============================================================================

# topoInbounds → [{id, tag, name, sub, users}]：两个目录里带用户的入站。users 只留账号名，协议后缀去掉
topoInbounds() {
    local out='[]' pair dir core id file usersPath nameField network port sub users tag fallbackPort=
    fallbackPort=$(jq -r '.inbounds[0].port // empty' "${XRAY_CONF_DIR}/$(getProtocolConfigFileName 0)" 2>/dev/null)
    for pair in "${XRAY_CONF_DIR}/:1" "${SINGBOX_FRAGMENT_DIR}/:2"; do
        dir=${pair%:*}
        core=${pair##*:}
        [[ -d "${dir}" ]] || continue
        for id in $(scanInstalledProtocols "${dir}" | tr ',' ' '); do
            file=$(getProtocolConfigPath "${id}" "${dir}") || continue
            usersPath=$(getProtocolUsersPath "${core}" "${id}") || continue
            nameField=$(getProtocolNameField "${core}" "${id}") || continue
            network=$(getProtocolListenNetwork "${id}") || network=tcp
            [[ "${network}" == "both" ]] && network="tcp/udp"
            if [[ "${core}" == "2" && "${id}" == "11" ]]; then
                port=$(grep 'listen' <"${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" 2>/dev/null | awk 'NR == 1 { gsub(/;/, ""); print $2 }')
            else
                port=$(jq -r '[.inbounds[]? | select((.listen // "") | startswith("127.") | not) | (.port // .listen_port // empty)] | first // empty' "${file}" 2>/dev/null)
            fi
            if [[ -n "${port}" ]]; then
                sub="${network} :${port}"
            else
                sub=$(t TOPO_SUB_FALLBACK "${network}" "${fallbackPort:-?}")
            fi
            [[ "${coreKind}" == "1" && "${core}" == "2" ]] && sub+=" · $(t TOPO_SUB_SIDECAR)"
            users=$(jq -c --arg f "${nameField}" "(${usersPath} // []) | map(.[\$f] // empty | tostring | sub(\"-[^-]*\$\"; \"\")) | unique" "${file}" 2>/dev/null) || users='[]'
            tag=$(jq -r '.inbounds[0].tag // ""' "${file}" 2>/dev/null)
            out=$(jq -c --argjson id "${id}" --arg tag "${tag}" --arg name "$(getProtocolDisplayName "${id}")" --arg sub "${sub}" --argjson users "${users:-[]}" \
                '. + [{id: $id, tag: $tag, name: $name, sub: $sub, users: $users}]' <<<"${out}") || return 1
        done
    done
    printf '%s\n' "${out}"
}

# topoDirectExit → 本机直连的出口节点。rawHost 是原始地址，打码在 topoFinalize 统一做，这里不判断
topoDirectExit() {
    jq -cn --arg name "$(t TOPO_EXIT_DIRECT)" --arg kind "$(t TOPO_KIND_LOCAL)" --arg host "$(getPublicIP 2>/dev/null)" \
        '{key: "direct", name: $name, kind: $kind, rawHost: $host, port: ""}'
}

# topoPlainExit TAG → 没接链式时，一个出站标签对应的出口节点
topoPlainExit() {
    case "$1" in
        direct | z_direct_outbound) topoDirectExit ;;
        IPv4_out) jq -cn --arg name "IPv4" --arg kind "$(t TOPO_KIND_LOCAL)" --arg host "$(getPublicIP 4 2>/dev/null)" '{key: "IPv4_out", name: $name, kind: $kind, rawHost: $host, port: ""}' ;;
        IPv6_out) jq -cn --arg name "IPv6" --arg kind "$(t TOPO_KIND_LOCAL)" --arg host "$(getPublicIP 6 2>/dev/null)" '{key: "IPv6_out", name: $name, kind: $kind, rawHost: $host, port: ""}' ;;
        wireguard_out_IPv4 | wireguard_endpoints_IPv4) jq -cn --arg key "$1" '{key: $key, name: "WARP IPv4", kind: "WireGuard", host: "Cloudflare", port: ""}' ;;
        wireguard_out_IPv6 | wireguard_endpoints_IPv6) jq -cn --arg key "$1" '{key: $key, name: "WARP IPv6", kind: "WireGuard", host: "Cloudflare", port: ""}' ;;
        *) jq -cn --arg key "$1" '{key: $key, name: $key, kind: "", host: "", port: ""}' ;;
    esac
}

# topoRoutingPlain → 没接链式：出口是本机直连与分流工具加的出站，条件从生效配置读
topoRoutingPlain() {
    local dflt= candidate rules tag exits='[]' flows='[]' issues='[]' when
    if [[ "${coreKind}" == "1" ]]; then
        for candidate in z_direct_outbound IPv4_out IPv6_out wireguard_out_IPv4 wireguard_out_IPv6; do
            if [[ -f "${XRAY_CONF_DIR}/${candidate}.json" ]]; then
                dflt=${candidate}
                break
            fi
        done
        rules=$(jq -c '[.routing.rules[]? | select(.domain != null and (((.ruleTag // "") | startswith("local-block")) | not)) | {tag: .outboundTag, domain}]' "${XRAY_CONF_DIR}/09_routing.json" 2>/dev/null) || rules='[]'
    else
        dflt=$(jq -r '.route.final // .outbounds[0].tag // "direct"' "${SINGBOX_MERGED_CONFIG}" 2>/dev/null)
        rules=$(jq -c '[.route.rules[]? | select(.outbound != null) | {tag: .outbound, domain: ([.domain, .domain_suffix, .domain_keyword, .rule_set] | map(select(. != null)) | flatten)} | select((.domain | length) > 0)]' "${SINGBOX_MERGED_CONFIG}" 2>/dev/null) || rules='[]'
    fi
    dflt=${dflt:-direct}
    while IFS= read -r tag; do
        [[ -n "${tag}" && "${tag}" != "${dflt}" ]] || continue
        when=$(jq -r --arg t "${tag}" --arg more "$(t TOPO_FLOW_MORE)" '[.[] | select(.tag == $t) | .domain[]] as $d
            | ($d[0] | sub("^domain:"; "")) + (if ($d | length) > 1 then ($more | sub("%s"; ($d | length | tostring))) else "" end)' <<<"${rules:-[]}")
        exits=$(jq -c --argjson x "$(topoPlainExit "${tag}")" '. + [$x]' <<<"${exits}") || return 1
        flows=$(jq -c --arg k "${tag}" --arg w "${when}" '. + [{exit: $k, when: $w}]' <<<"${flows}") || return 1
        # 规则指向不存在的出站时 Xray 直接断连接，不走默认出站，这种机器要看得到
        if [[ "${coreKind}" == "1" && ! -f "${XRAY_CONF_DIR}/${tag}.json" ]]; then
            issues=$(jq -c --arg s "$(t TOPO_ISSUE_MISSING_OUTBOUND "${tag}")" '. + [$s]' <<<"${issues}")
        fi
    done < <(jq -r '.[].tag' <<<"${rules:-[]}" | awk '!seen[$0]++')
    exits=$(jq -c --argjson x "$(topoPlainExit "${dflt}")" '[$x] + .' <<<"${exits}") || return 1
    jq -cn --argjson exits "${exits}" --argjson flows "${flows}" --argjson issues "${issues}" --arg dflt "$(jq -r '.key' <<<"$(topoPlainExit "${dflt}")")" --arg w "$(t TOPO_FLOW_DEFAULT)" \
        '{exits: $exits, flows: ($flows + [{exit: $dflt, when: $w}]), pins: {}, inboundExits: [], issues: $issues}'
}

# topoRoutingMulti → 多链路。只取画图要的字段：状态文件里 password 和 ip、port 并排，整块转储就把密钥写进页面了
topoRoutingMulti() {
    local state name file hops='{}' missing='[]' rules='[]' type value chain
    state=$(jq -c '{chains: [.chains[]? | {name, ip, port, source, external_type}], rules: [.rules[]? | {type, value, chain}], default_chain, accounts: (.accounts // {})}' "${CHAIN_MULTI_INFO}") || return 1
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        file="${SINGBOX_FRAGMENT_DIR}/chain_outbound_${name}.json"
        if [[ -f "${file}" ]]; then
            hops=$(jq -c --arg n "${name}" --argjson o "$(jq -c '{count: ([.outbounds[]?] | length), server: .outbounds[0].server, port: .outbounds[0].server_port}' "${file}" 2>/dev/null || echo '{}')" '. + {($n): $o}' <<<"${hops}")
        else
            missing=$(jq -c --arg n "${name}" '. + [$n]' <<<"${missing}")
        fi
    done < <(jq -r '.chains[].name' <<<"${state}")
    while IFS=$'\t' read -r type value chain; do
        [[ -n "${chain}" ]] || continue
        rules=$(jq -c --arg c "${chain}" --arg w "$(chainRuleLabel "${type}" "${value}")" '. + [{exit: $c, when: $w}]' <<<"${rules}")
    done < <(jq -r '.rules[] | [.type, (.value | tostring), .chain] | @tsv' <<<"${state}")
    jq -c --argjson direct "$(topoDirectExit)" --argjson hops "${hops}" --argjson missing "${missing}" --argjson rules "${rules}" \
        --arg chainKind "$(t TOPO_KIND_CHAIN)" --arg relayNote "$(t TOPO_NOTE_RELAYS)" --arg badNote "$(t TOPO_NOTE_NOT_APPLIED)" --arg badIssue "$(t TOPO_ISSUE_MISSING_CHAIN)" \
        --arg badPin "$(t TOPO_ISSUE_PIN_MISSING)" --arg more "$(t TOPO_FLOW_MORE)" --arg w "$(t TOPO_FLOW_DEFAULT)" '
        (.default_chain // "direct") as $dflt
        | ([.chains[].name] + ["direct"]) as $known
        | {
            exits: ([$direct] + [.chains[] | . as $c
                | ($hops[$c.name] // {}) as $h
                | {key: .name, name: .name, kind: (if .source == "external" then (.external_type // "") else $chainKind end), rawHost: ($h.server // .ip), port: ($h.port // .port)}
                  + (if ($missing | index($c.name)) != null then {bad: true, note: $badNote}
                     elif ($h.count // 1) > 1 then {note: ($relayNote | sub("%s"; ($h.count | tostring)))} else {} end)]),
            flows: (($rules | map(select(.exit != $dflt)) | group_by(.exit)
                     | map(length as $c | {exit: .[0].exit, when: (.[0].when + (if $c > 1 then ($more | sub("%s"; ($c | tostring))) else "" end))}))
                    + [{exit: $dflt, when: $w}]),
            pins: .accounts,
            inboundExits: [],
            issues: (($missing | map(. as $n | $badIssue | sub("%s"; $n)))
                     + ([.accounts | to_entries[] | .key as $k | .value as $v | select(($known | index($v)) == null) | ($badPin | sub("%s"; $k) | sub("%s"; $v))]))
          }' <<<"${state}"
}

# topoRoutingEntry → 单链路、多跳、外部节点唯一出口。出口节点标这台机器真正连的下一跳，下一跳是中继时注明
topoRoutingEntry() {
    local state mode node selected='[]' exitObj issues='[]' dflt flows inboundExits='[]'
    state=$(jq -c '{mode: (.mode // ""), exit_ip, exit_port, hops: [(.hops // [])[] | {ip, port}], default_chain, accounts: (.accounts // {}),
        protocolRouting: (.protocol_routing.enabled == true), external_node_id, external_node_name}' "${CHAIN_ENTRY_INFO}") || return 1
    mode=$(jq -r '.mode' <<<"${state}")
    if [[ "${mode}" == "external_single" ]]; then
        node=$(jq -c --arg id "$(jq -r '.external_node_id // ""' <<<"${state}")" 'first(.nodes[]? | select(.id == $id) | {type, server, server_port}) // {}' "${EXTERNAL_NODE_FILE}" 2>/dev/null) || node='{}'
        exitObj=$(jq -cn --argjson n "${node:-{\}}" --arg name "$(jq -r '.external_node_name // ""' <<<"${state}")" '{key: "chain", name: $name, kind: ($n.type // ""), rawHost: ($n.server // ""), port: ($n.server_port // "")}')
        if chainExternalSingleOnXray; then
            issues=$(jq -cn --arg s "$(t TOPO_ISSUE_EXTERNAL_XRAY)" '[$s]')
            jq -cn --argjson x "${exitObj}" --argjson d "$(topoDirectExit)" --argjson issues "${issues}" --arg w "$(t TOPO_FLOW_ALL)" \
                '{exits: [$d, $x], flows: [{exit: "direct", when: $w}], pins: {}, inboundExits: [], issues: $issues}'
            return 0
        fi
        jq -cn --argjson x "${exitObj}" --arg w "$(t TOPO_FLOW_ALL)" '{exits: [$x], flows: [{exit: "chain", when: $w}], pins: {}, inboundExits: [], issues: []}'
        return 0
    fi
    exitObj=$(jq -c --arg name "$(t TOPO_EXIT_CHAIN)" --arg kind "$(t TOPO_KIND_CHAIN)" --arg relayNote "$(t TOPO_NOTE_RELAYS)" '
        (if (.hops | length) > 0 then .hops[0] else {ip: .exit_ip, port: .exit_port} end) as $next
        | {key: "chain", name: $name, kind: $kind, rawHost: ($next.ip // ""), port: ($next.port // "")}
          + ((.hops | length) as $n | if $n > 1 then {note: ($relayNote | sub("%s"; ($n | tostring)))} else {} end)' <<<"${state}")
    if [[ ! -f "${SINGBOX_FRAGMENT_DIR}/chain_outbound.json" ]]; then
        exitObj=$(jq -c --arg note "$(t TOPO_NOTE_NOT_APPLIED)" '. + {bad: true, note: $note}' <<<"${exitObj}")
        issues=$(jq -cn --arg s "$(t TOPO_ISSUE_MISSING_CHAIN chain_outbound)" '[$s]')
    fi
    dflt=$(jq -r 'if .default_chain == "direct" then "direct" else "chain" end' <<<"${state}")
    flows=$(jq -cn --arg d "${dflt}" --arg w "$(t TOPO_FLOW_ALL)" '[{exit: $d, when: $w}]')
    # 按协议分流：选中的入站走链路，其余走 route.final。Xray 经桥进来的流量不看这条，只有 sing-box 自己的入站才分
    if [[ "$(jq -r '.protocolRouting' <<<"${state}")" == "true" ]]; then
        selected=$(jq -c '[.route.rules[]? | select(.outbound == "chain_outbound" and .inbound != null) | .inbound[] | select(. != "chain_bridge_in")] | unique' "${SINGBOX_FRAGMENT_DIR}/chain_route.json" 2>/dev/null) || selected='[]'
        inboundExits=$(jq -c --argjson sel "${selected}" --arg w "$(t TOPO_WHEN_PROTOCOL)" '[.[] | select(.tag as $t | $sel | index($t)) | {inbound: .id, exit: "chain", when: $w}]' <<<"$(topoInbounds)")
        if [[ "${coreKind}" == "2" ]]; then
            flows=$(jq -cn --arg w "$(t TOPO_FLOW_OTHER_PROTOCOLS)" '[{exit: "direct", when: $w}]')
        fi
    fi
    jq -c --argjson x "${exitObj}" --argjson d "$(topoDirectExit)" --argjson flows "${flows}" --argjson ie "${inboundExits}" --argjson issues "${issues}" '
        {exits: [$d, $x], flows: $flows, pins: (.accounts | map_values(if . == "chain_outbound" then "chain" else . end)), inboundExits: $ie, issues: $issues}' <<<"${state}"
}

# topoRouting → {exits, flows, pins, inboundExits, issues, extraInbounds}。本机当链式出口或中继时，多一个收别的机器流量的入站
topoRouting() {
    local base extra='{"extraInbounds":[],"extraExits":[],"inboundExits":[]}' port chainKind
    if [[ -f "${CHAIN_MULTI_INFO}" ]]; then
        base=$(topoRoutingMulti) || return 1
    elif [[ -f "${CHAIN_ENTRY_INFO}" ]]; then
        base=$(topoRoutingEntry) || return 1
    else
        base=$(topoRoutingPlain) || return 1
    fi
    chainKind=$(t TOPO_KIND_CHAIN)
    if [[ -f "${CHAIN_RELAY_INFO}" ]]; then
        extra=$(jq -c --arg in "$(t TOPO_CHAIN_INBOUND)" --arg when "$(t TOPO_WHEN_FROM_ENTRY)" --arg name "$(t TOPO_EXIT_NEXT_HOP)" --arg kind "${chainKind}" --arg relayNote "$(t TOPO_NOTE_RELAYS)" '
            ([(.downstream_hops // [])[] | {ip, port}]) as $hops
            | {extraInbounds: [{id: "chain", chain: true, tag: "", name: $in, sub: "tcp :\(.port // "?")", users: []}],
               extraExits: [{key: "next", name: $name, kind: $kind, rawHost: ($hops[0].ip // ""), port: ($hops[0].port // "")}
                            + (if ($hops | length) > 1 then {note: ($relayNote | sub("%s"; ($hops | length | tostring)))} else {} end)],
               inboundExits: [{inbound: "chain", exit: "next", when: $when}]}' "${CHAIN_RELAY_INFO}") || return 1
    elif [[ -f "${CHAIN_EXIT_INFO}" ]]; then
        port=$(jq -r '.port // "?"' "${CHAIN_EXIT_INFO}" 2>/dev/null)
        extra=$(jq -cn --arg in "$(t TOPO_CHAIN_INBOUND)" --arg when "$(t TOPO_WHEN_FROM_ENTRY)" --arg sub "tcp :${port}" \
            '{extraInbounds: [{id: "chain", chain: true, tag: "", name: $in, sub: $sub, users: []}], extraExits: [], inboundExits: [{inbound: "chain", exit: "direct", when: $when}]}')
    fi
    jq -c --argjson e "${extra}" --argjson d "$(topoDirectExit)" '
        .extraInbounds = $e.extraInbounds
        | .exits = (.exits + $e.extraExits)
        | .inboundExits = (.inboundExits + $e.inboundExits)
        | if ([.inboundExits[].exit] | index("direct")) != null and ([.exits[].key] | index("direct")) == null then .exits = [$d] + .exits else . end' <<<"${base}"
}

# topoCoreStart PID → 进程启动的 epoch 秒。/proc/PID 目录的 mtime 是 inode 建立的时间，不是进程启动时间，所以从 stat 算
topoCoreStart() {
    local ticks btime
    ticks=$(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{ print $20 }')
    btime=$(awk '$1 == "btime" { print $2 }' /proc/stat 2>/dev/null)
    [[ -n "${ticks}" && -n "${btime}" ]] && printf '%s\n' "$((btime + ticks / 100))"
}

# topoIssues → 生效配置和磁盘、状态文件对不上的地方（JSON 字符串数组）：内核没在跑、配置比进程新、members.json 还没应用
topoIssues() {
    local issues='[]' pid start newest state
    if [[ "${coreKind}" == "1" ]]; then
        pid=$(pgrep -f "${XRAY_BIN}" | head -n 1)
        if [[ -z "${pid}" ]]; then
            issues=$(jq -c --arg s "$(t TOPO_ISSUE_NOT_RUNNING Xray)" '. + [$s]' <<<"${issues}")
        else
            start=$(topoCoreStart "${pid}")
            newest=$(stat -c %Y "${XRAY_CONF_DIR}"/*.json 2>/dev/null | sort -n | tail -n 1)
            if [[ -n "${start}" && -n "${newest}" && "${newest}" -gt "$((start + 2))" ]]; then
                issues=$(jq -c --arg s "$(t TOPO_ISSUE_STALE Xray)" '. + [$s]' <<<"${issues}")
            fi
        fi
    fi
    if [[ "${coreKind}" == "2" ]] || singBoxFragmentsHaveInbounds; then
        pid=$(pgrep -x sing-box | head -n 1)
        if [[ -z "${pid}" ]]; then
            issues=$(jq -c --arg s "$(t TOPO_ISSUE_NOT_RUNNING sing-box)" '. + [$s]' <<<"${issues}")
        else
            start=$(topoCoreStart "${pid}")
            newest=$(stat -c %Y "${SINGBOX_MERGED_CONFIG}" 2>/dev/null)
            if [[ -n "${start}" && -n "${newest}" && "${newest}" -gt "$((start + 2))" ]]; then
                issues=$(jq -c --arg s "$(t TOPO_ISSUE_STALE sing-box)" '. + [$s]' <<<"${issues}")
            fi
        fi
    fi
    if carpoolEnabled 2>/dev/null && [[ -f "${CARPOOL_MEMBERS_FILE}" ]]; then
        state=$(carpoolReadState)
        if ! jq -e --argjson s "${state}" '(.members // {} | keys) == ($s.members | keys)' "${CARPOOL_MEMBERS_FILE}" >/dev/null 2>&1; then
            issues=$(jq -c --arg s "$(t TOPO_ISSUE_MEMBERS_PENDING)" '. + [$s]' <<<"${issues}")
        fi
    fi
    printf '%s\n' "${issues}"
}

# topoCoresText → 页头的内核与版本
topoCoresText() {
    local xray sing
    [[ "${coreKind}" == "1" ]] && xray="Xray $("${XRAY_BIN}" version 2>/dev/null | awk 'NR == 1 { print $2 }')"
    if [[ -x "${SINGBOX_BIN}" ]] && { [[ "${coreKind}" == "2" ]] || singBoxFragmentsHaveInbounds; }; then
        sing="sing-box $("${SINGBOX_BIN}" version 2>/dev/null | awk 'NR == 1 { print $NF }')"
    fi
    printf '%s\n' "${xray:-}${xray:+${sing:+ + }}${sing:-}"
}

# topoCollect FULL → 渲染用的模型。FULL 为 true 时出口地址不打码
topoCollect() {
    local full=$1 inbounds routing state='null' labels accounts issues lang=en maskNote hostName=
    [[ "${CURRENT_LANG:-}" == "zh_CN" ]] && lang=zh-CN
    inbounds=$(topoInbounds) || return 1
    routing=$(topoRouting) || return 1
    if carpoolEnabled 2>/dev/null; then
        state=$(carpoolReadState) || state='null'
    fi
    labels=$(jq -cn --arg title "$(t TOPO_TITLE)" --arg colInbound "$(t TOPO_COL_INBOUND)" --arg colAccount "$(t TOPO_COL_ACCOUNT)" --arg colExit "$(t TOPO_COL_EXIT)" \
        --arg allProtocols "$(t TOPO_ALL_PROTOCOLS)" --arg followDefault "$(t TOPO_FOLLOW_DEFAULT)" --arg pinned "$(t TOPO_PINNED)" --arg pinnedN "$(t TOPO_PINNED_N)" \
        --arg issuesTitle "$(t TOPO_ISSUES_TITLE)" --arg footnote "$(t TOPO_FOOTNOTE)" --arg foreign "$(t TOPO_ACCOUNT_FOREIGN)" \
        --arg expire "$(t TOPO_ACCOUNT_EXPIRE)" --arg disabled "$(t TOPO_ACCOUNT_DISABLED)" --arg reasonQuota "$(t TOPO_REASON_QUOTA)" --arg reasonExpired "$(t TOPO_REASON_EXPIRED)" --arg reasonManual "$(t TOPO_REASON_MANUAL)" \
        '$ARGS.named')
    accounts=$(topoAccounts "$(jq -c --argjson r "${routing}" '. + $r.extraInbounds' <<<"${inbounds}")" "${state}" "$(jq -c '.pins' <<<"${routing}")" "${labels}") || return 1
    issues=$(topoIssues)
    if [[ "${full}" == "true" ]]; then
        maskNote=""
        hostName=$(hostname 2>/dev/null)
    else
        maskNote=$(t TOPO_MASK_NOTE)
    fi
    topoFinalize "$(jq -cn --argjson in "${inbounds}" --argjson r "${routing}" --argjson acc "${accounts}" --argjson issues "${issues}" --argjson labels "${labels}" \
        --arg lang "${lang}" --arg host "${hostName}" --arg cores "$(topoCoresText)" --arg generated "$(date '+%F %H:%M')" --arg maskNote "${maskNote}" --arg all "$(t TOPO_FLOW_ALL)" --arg dfltText "$(t TOPO_FLOW_DEFAULT)" '
        {lang: $lang, host: $host, cores: $cores, generated: $generated, maskNote: $maskNote, labels: $labels,
         inbounds: (($in + $r.extraInbounds) | map(del(.users, .tag))),
         accounts: $acc, exits: $r.exits, inboundExits: $r.inboundExits,
         flows: (if ($r.flows | length) == 1 and $r.flows[0].when == $dfltText then [$r.flows[0] + {when: $all}] else $r.flows end),
         issues: ($r.issues + $issues)}')" "${full}"
}

# topoServe PAGE_FILE → 只在 127.0.0.1 上提供这一个页面，前台跑，回车或 Ctrl+C 就撤。不走 nginx：不用动线上配置和重载。
# 端口在桥端口段里，两边内核早就按端口封了，成员写成解析到 127.0.0.1 的域名也连不到，开页面不用重启内核
topoServe() {
    local page=$1 dir=$2 handler pid sshPart
    if listeningPorts tcp | grep -qx "${TOPO_PAGE_PORT}"; then
        echoContent red " ---> $(t TOPO_PORT_BUSY "${TOPO_PAGE_PORT}")"
        return 1
    fi
    handler="${dir}/handler.sh"
    # Host 只认回环：防 DNS 重绑定，不然恶意网页能让车主的浏览器把这一页读走
    cat <<'EOF' >"${handler}"
page=$1
port=$2
IFS= read -r -t 5 request || exit 0
host=
while IFS= read -r -t 5 line; do
    line=${line%$'\r'}
    [[ -z "${line}" ]] && break
    case "${line,,}" in
        host:*) host=${line#*:}; host=${host# } ;;
    esac
done
reply() { printf 'HTTP/1.0 %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n' "$1"; exit 0; }
[[ "${host}" == "127.0.0.1:${port}" || "${host}" == "localhost:${port}" ]] || reply "403 Forbidden"
[[ "${request}" == "GET / HTTP/"* ]] || reply "404 Not Found"
printf 'HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %s\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src '"'"'none'"'"'; style-src '"'"'unsafe-inline'"'"'; base-uri '"'"'none'"'"'; form-action '"'"'none'"'"'; frame-ancestors '"'"'none'"'"'\r\nConnection: close\r\n\r\n' "$(wc -c <"${page}")"
cat "${page}"
EOF
    socat "TCP-LISTEN:${TOPO_PAGE_PORT},bind=127.0.0.1,reuseaddr,fork" "EXEC:bash ${handler} ${page} ${TOPO_PAGE_PORT}" 2>/dev/null &
    pid=$!
    trap 'kill "${pid}" 2>/dev/null; rm -rf "${dir}"; trap - INT TERM; echo; exit 0' INT TERM
    sleep 0.5
    if ! kill -0 "${pid}" 2>/dev/null; then
        echoContent red " ---> $(t TOPO_SERVE_FAILED "${TOPO_PAGE_PORT}")"
        trap - INT TERM
        return 1
    fi
    # SSH_CONNECTION 是这次登录真实用的地址和端口，照着抄就能连上
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        sshPart="-p $(awk '{ print $4 }' <<<"${SSH_CONNECTION}") $(id -un)@$(awk '{ print $3 }' <<<"${SSH_CONNECTION}")"
    else
        sshPart="root@<server>"
    fi
    echoContent green "\n ---> $(t TOPO_SERVE_READY)"
    echoContent yellow "  1. $(t TOPO_SERVE_STEP_TUNNEL)"
    echoContent skyBlue "     ssh -N -L ${TOPO_PAGE_PORT}:127.0.0.1:${TOPO_PAGE_PORT} ${sshPart}"
    echoContent yellow "  2. $(t TOPO_SERVE_STEP_OPEN)"
    echoContent skyBlue "     http://127.0.0.1:${TOPO_PAGE_PORT}/"
    read -r -p "$(t TOPO_SERVE_WAIT)" _ || true
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    trap - INT TERM
    return 0
}

# topoCommand [--full] [--out FILE] → 生成路由总览。给了 FILE 就写文件，否则开一个只听回环的页面等隧道连。页面只读
topoCommand() {
    local full=false out= model html dir
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full) full=true ;;
            --out)
                out=${2:-}
                [[ -n "${out}" ]] || { echoContent red " ---> $(t TOPO_USAGE)"; return 1; }
                shift
                ;;
            *)
                echoContent red " ---> $(t TOPO_USAGE)"
                return 1
                ;;
        esac
        shift
    done
    readInstallType
    if [[ -z "${coreKind}" ]]; then
        echoContent red " ---> $(t TOPO_NOT_INSTALLED)"
        return 1
    fi
    if ! model=$(topoCollect "${full}") || ! html=$(topoRenderHtml "${model}") || [[ -z "${html}" ]]; then
        echoContent red " ---> $(t TOPO_RENDER_FAILED)"
        return 1
    fi
    if [[ -n "${out}" ]]; then
        # 这些目录都被 nginx 对外提供，写进去就是公网可取
        case "$(cd "$(dirname "${out}")" 2>/dev/null && pwd)/" in
            "${SUBSCRIBE_DIR%/}/"* | "${nginxStaticPath%/}/"*)
                echoContent red " ---> $(t TOPO_OUT_PUBLIC_DIR "${out}")"
                return 1
                ;;
        esac
        if ! (umask 077 && printf '%s\n' "${html}" >"${out}") || ! chmod 600 "${out}"; then
            echoContent red " ---> $(t TOPO_OUT_WRITE_FAILED "${out}")"
            return 1
        fi
        echoContent green " ---> $(t TOPO_OUT_DONE "${out}")"
        return 0
    fi
    dir=$(mktemp -d) || return 1
    printf '%s\n' "${html}" >"${dir}/index.html"
    topoServe "${dir}/index.html" "${dir}"
    local rc=$?
    rm -rf "${dir}"
    return "${rc}"
}

# source 提供函数和布局常量；调用方在独立 Bash 子进程里显式 initVar 并设置生成参数。
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

_load_version
initVar "${1:-}"
# 只读入口、定时任务和服务停止钩子不能在初始化期就退出：doctor 要报告的正是 SELinux；定时任务退出的话，setenforce 0 装完、
# 重启回到 Enforcing 的机器证书到期也续不上，停止钩子退出则丢用量。root 的 cron 跑在 unconfined_t，这些路径在 Enforcing 下真跑过、没有拒绝
case "${1:-}" in
    doctor | topo | RenewTLS | UpdateGeo | CarpoolTick | CarpoolCollect)
        PROXY_AGENT_SELINUX_NONFATAL=1
        ;;
esac
checkSystem
checkCPUVendor

readInstallType
readInstallProtocolType
readConfigHostPathUUID
readCustomPort
readSingBoxConfig

# ============================================================================
# 顶层入口分发（doctor / --dry-run / 菜单）：必须在所有函数定义之后、menu 调用之前
# ============================================================================
case "${1:-}" in
    doctor)
        doctor
        exit $?
        ;;
    # 服务单元的停止钩子：关机途中网络可能已断，不能等下面的更新检查超时
    CarpoolCollect)
        carpoolCollectBeforeStop
        exit 0
        ;;
    # 只读，要读 600 的配置，所以要 root；开着页面时不走菜单，也不查更新
    topo)
        checkRoot
        shift
        topoCommand "$@"
        exit $?
        ;;
    --dry-run|-n)
        export DRY_RUN=1
        shift
        ;;
esac

# root 权限校验：doctor（只读诊断允许非 root）与 CarpoolCollect 上面已 exit，其余路径（含 --dry-run）
# 都会落到这里。脚本随后大量写 /etc、systemd、防火墙，非 root 必然中途失败，这里统一拦截。
checkRoot

# 启动时检查更新（使用短超时，避免阻塞太久）
checkForUpdates 2>/dev/null

cronFunction
menu
