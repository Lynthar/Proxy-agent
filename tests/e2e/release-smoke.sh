#!/usr/bin/env bash
# release-smoke.sh OLD_TAG STAGE → 一次性 Debian 容器里从 Release 装机。readme / update 验已发布的 Release（run.sh release 调）：README 那一行
# 原样装一次，再从 OLD_TAG 装起、菜单 17 自更新到最新、菜单 22 回滚。tree 从 OLD_TAG 装起后把工作树盖上去，等于自更新到这棵树（run.sh upgrade 调）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assert.sh"

OLD_TAG=$1
STAGE=$2
INSTALL_ROOT=/etc/Proxy-agent
REPO_URL=https://github.com/Lynthar/Proxy-agent
LOG=/tmp/proxy-agent-release-smoke.log
E2E_UUID="11111111-2222-3333-4444-555555555555"

if [[ ! -f /.dockerenv ]]; then
    echo -e "${RED}只在一次性容器里跑${NC}"
    exit 2
fi
# README 默认机器上有 wget（云镜像大多带）；精简容器里没有，先补上
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq wget >/dev/null 2>&1
latestTag=$(wget -qO- --max-redirect=0 --server-response "${REPO_URL}/releases/latest" 2>&1 | tr -d '\r' | sed -n 's#^ *Location: .*/tag/\([^ ]*\).*#\1#p' | head -n 1)
assert_not_empty "${latestTag}" "取到最新 Release 的 tag（${latestTag}）"

# realityQuick → 菜单 19 → 1：Xray 一键 Reality（UUID、用户名、端口回车、目标、私钥回车），打印退出码
realityQuick() {
    local rc
    printf '19\n1\n%s\nsmoke\n\ndl.google.com:443\n\n' "${E2E_UUID}" | V2RAY_LANG=en bash "$1" >>"${LOG}" 2>&1
    rc=$?
    [[ ${rc} -ne 0 ]] && sed 's/\x1b\[[0-9;]*m//g' "${LOG}" | tail -n 25 >&2
    echo "${rc}"
}

# installOldTag → 一台当年按 OLD_TAG 装的机器：脚本、lib 与 VERSION 都是那一版的（只下 install.sh 会按 Releases API 记成最新版、拉最新的 lib），
# 装一键 Reality，打印退出码
installOldTag() {
    (cd /root && wget -qO /root/install.sh "${REPO_URL}/releases/download/${OLD_TAG}/install.sh" &&
        wget -qO /tmp/old-bundle.tgz "${REPO_URL}/releases/download/${OLD_TAG}/lib_bundle.tar.gz" &&
        tar -xzf /tmp/old-bundle.tgz -C /root && echo "${OLD_TAG#v}" >/root/VERSION && chmod 700 /root/install.sh) || { echo 1; return; }
    realityQuick /root/install.sh
}

# localBlockHas ADDR → Xray 本机封锁的 IP 名单里有没有这个字面地址，打印 true / false
localBlockHas() {
    jq --arg a "$1" '[.routing.rules[]? | select(.ruleTag == "local-block-ip") | .ip[]?] | index($a) != null' \
        "${INSTALL_ROOT}/xray/conf/09_routing.json" 2>/dev/null || echo false
}

case "${STAGE}" in
readme)
    echo -e "${YELLOW}=== README 那一行：从 releases/latest 装 ===${NC}"
    rc=$(cd /root && wget -P /root -N "${REPO_URL}/releases/latest/download/install.sh" >>"${LOG}" 2>&1 &&
        chmod 700 /root/install.sh && realityQuick /root/install.sh)
    assert_equals "0" "${rc}" "README 的命令装一键 Reality 退出码 0"
    assert_equals "${latestTag#v}" "$(cat "${INSTALL_ROOT}/VERSION" 2>/dev/null)" "装上的是最新 Release ${latestTag}"
    wget -qO /tmp/bundle.tgz "${REPO_URL}/releases/download/${latestTag}/lib_bundle.tar.gz"
    assert_equals "" "$(tar -tzf /tmp/bundle.tgz | grep -E '\.sh$' | while read -r f; do [[ -s "${INSTALL_ROOT}/${f#./}" ]] || echo "${f}"; done)" \
        "只下了 install.sh，lib/ 与 shell/lang/ 由 Release 的 lib_bundle 补齐"
    assert_equals "" "$(find "${INSTALL_ROOT}/lib" "${INSTALL_ROOT}/shell/lang" "${INSTALL_ROOT}/VERSION" ! -uid 0 -o ! -gid 0 2>&1)" \
        "自举补齐的文件都归 root（root 每次运行都 source 它们，归了别的 uid 那个账号就能以 root 执行）"
    assert_equals "active" "$(systemctl is-active xray 2>/dev/null)" "Xray 在跑"
    ;;
update)
    echo -e "${YELLOW}=== 从 ${OLD_TAG} 装起，菜单 17 自更新到 ${latestTag}，菜单 22 回滚到 ${OLD_TAG} ===${NC}"
    assert_equals "0" "$(installOldTag)" "${OLD_TAG} 装一键 Reality 退出码 0"
    assert_equals "${OLD_TAG#v}" "$(cat "${INSTALL_ROOT}/VERSION" 2>/dev/null)" "起点是 ${OLD_TAG}"
    printf '17\n' | V2RAY_LANG=en pasly >>"${LOG}" 2>&1
    assert_equals "0" "$?" "菜单 17 自更新退出码 0"
    assert_equals "${latestTag#v}" "$(cat "${INSTALL_ROOT}/VERSION" 2>/dev/null)" "自更新到 ${latestTag}"
    wget -qO /tmp/latest.sha256 "${REPO_URL}/releases/download/${latestTag}/install.sh.sha256"
    assert_equals "$(awk '{print $1}' /tmp/latest.sha256)" "$(sha256sum "${INSTALL_ROOT}/install.sh" | awk '{print $1}')" \
        "装上的 install.sh 与 Release 资产的 SHA256 一致"
    assert_equals "active" "$(systemctl is-active xray 2>/dev/null)" "自更新后 Xray 照常在跑"
    # 旧版的更新程序只认它自己那份模块清单，新模块要靠新脚本启动时从 lib_bundle 补齐，补不上这个子命令就跑不起来
    V2RAY_LANG=en pasly topo --out /tmp/smoke-topo.html >>"${LOG}" 2>&1
    assert_equals "0" "$?" "自更新后新模块补齐：pasly topo 退出码 0"
    assert_contains "$(cat /tmp/smoke-topo.html 2>/dev/null)" "<svg" "自更新后 pasly topo 生成了页面"
    # 旧版本装下的 loader.sh 更新后还留在盘上：现在的代码不读它，更新程序也不管它的属主
    assert_equals "" "$(find "${INSTALL_ROOT}/lib" "${INSTALL_ROOT}/shell/lang" -name '*.sh' ! -name loader.sh \( ! -uid 0 -o ! -gid 0 \) 2>&1)" \
        "自更新后模块与语言文件都归 root"
    listing=$(printf '22\n2\n0\n' | V2RAY_LANG=en pasly 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    idx=$(sed -n "s/^\([0-9][0-9]*\)\. ${OLD_TAG} (GitHub)$/\1/p" <<<"${listing}")
    assert_not_empty "${idx}" "回滚菜单列出 ${OLD_TAG}（GitHub）"
    printf '22\n2\n%s\ny\n' "${idx}" | V2RAY_LANG=en pasly >>"${LOG}" 2>&1
    assert_equals "0" "$?" "菜单 22 从 GitHub 回滚退出码 0"
    assert_equals "${OLD_TAG#v}" "$(cat "${INSTALL_ROOT}/VERSION" 2>/dev/null)" "回滚到 ${OLD_TAG}"
    assert_contains "$(V2RAY_LANG=en pasly </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')" "Core: Xray-core [Running]" "回滚后 pasly 打得开，Xray 照常在跑"
    ;;
tree)
    echo -e "${YELLOW}=== 从 ${OLD_TAG} 装起、盖上工作树：入口提示内核是旧版起的，终端上确认重启后用上本版的启动前修正 ===${NC}"
    assert_equals "0" "$(installOldTag)" "${OLD_TAG} 装一键 Reality 退出码 0"
    # 网卡地址进 Xray 本机封锁名单是 v1.5.2 起的，起点得比它早，才验得到「换了脚本、内核没重启就还没生效」
    addr=$(ip -o -4 addr show scope global | awk '{ sub(/\/.*/, "", $4); print $4; exit }')
    assert_not_empty "${addr}" "容器网卡有全局地址（${addr}）"
    assert_equals "false" "$(localBlockHas "${addr}")" "起点 ${OLD_TAG} 的本机封锁名单里没有网卡地址"
    # 自更新换的就是这几样，内核与配置不动、不重启
    cp -f /src/install.sh "${INSTALL_ROOT}/install.sh" && chmod 700 "${INSTALL_ROOT}/install.sh" &&
        cp -f /src/lib/*.sh "${INSTALL_ROOT}/lib/" && cp -f /src/shell/lang/*.sh "${INSTALL_ROOT}/shell/lang/" &&
        cp -f /src/VERSION "${INSTALL_ROOT}/VERSION"
    assert_equals "0" "$?" "工作树盖上安装根"
    newVer="v$(tr -d '[:space:]' </src/VERSION)"
    out=$(V2RAY_LANG=en pasly </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "${out}" "Xray was started by an older version of this script" "不是终端时打开菜单：说明 Xray 是旧版脚本起的"
    assert_equals "false" "$(localBlockHas "${addr}")" "不是终端时只提示、不重启：名单照旧"
    assert_contains "$(V2RAY_LANG=en pasly doctor 2>&1 | sed 's/\x1b\[[0-9;]*m//g')" "Core started by this script version — Xray was started by an older script version" \
        "doctor 报内核是旧版脚本起的"
    # script 给菜单一个终端；标准输入读完后它把 EOF 交给子进程并等它退出，重启不会被挂断
    printf 'y\n' | script -qec 'V2RAY_LANG=en pasly' /dev/null >>"${LOG}" 2>&1
    assert_equals "${newVer}" "$(cat "${INSTALL_ROOT}/xray/started_version" 2>/dev/null)" "终端上答 y：Xray 由本版脚本重启，记下 ${newVer}"
    assert_equals "true" "$(localBlockHas "${addr}")" "重启后本机封锁名单里有网卡地址"
    assert_equals "active" "$(systemctl is-active xray 2>/dev/null)" "重启后 Xray 在跑"
    assert_equals "0" "$(V2RAY_LANG=en pasly </dev/null 2>&1 | grep -c 'started by an older version')" "再打开菜单不再提示"
    ;;
*)
    echo "usage: $0 OLD_TAG readme|update|tree" >&2
    exit 2
    ;;
esac

e2eSummary "发版冒烟（${STAGE}）" "${LOG}"
