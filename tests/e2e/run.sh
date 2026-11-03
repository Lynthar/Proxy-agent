#!/usr/bin/env bash
# run.sh alpine|debian [xray|singbox] [xray|singbox] | chain [xray|singbox] | domain | release OLD_TAG — 在一次性容器里跑真装机测试（domain 跑 test_install_domain_e2e.sh，release 验已发布的 Release，其余跑 test_install_e2e.sh）。
# 第二参是服务端内核（默认 xray），第三参是握手用的客户端内核（默认同服务端；singbox 对 xray 是交叉腿）。
# alpine 用 OpenRC；debian 先把 systemd 当 PID 1 起来再 exec 进去。chain 是两台 Debian：入口 Xray 开拼车接链式，出口内核取第二参
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${E2E_DIR}/../.." && pwd)"
E2E_CORE="${2:-xray}"
E2E_CLIENT="${3:-${E2E_CORE}}"

# startDebian [docker run 参数…] → 起一个 systemd 当 PID 1 的 Debian 容器，等它进入 running / degraded，打印容器 ID
startDebian() {
    local cid state
    docker build -q -t proxy-agent-e2e-debian -f "${E2E_DIR}/debian-systemd.Dockerfile" "${E2E_DIR}" >/dev/null
    cid=$(docker run -d --rm --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw "$@" \
        -v "${PROJECT_ROOT}:/src:ro" proxy-agent-e2e-debian)
    for _ in $(seq 1 30); do
        state=$(docker exec "${cid}" systemctl is-system-running 2>/dev/null || true)
        [[ "${state}" == "running" || "${state}" == "degraded" ]] && break
        sleep 1
    done
    printf '%s\n' "${cid}"
}

# txBytes CID → 容器里 eth0 累计发出的字节数
txBytes() {
    docker exec "$1" awk '/^ *eth0:/ { sub(/.*:/, ""); print $9 }' /proc/net/dev
}

case "${1:-}" in
alpine)
    # 真 Alpine 机器由 OpenRC 引导并带 BusyBox 的 init 脚本（crond 那份在 busybox-openrc 里），
    # 容器镜像里都没有，补上；bash 是脚本自己的硬要求
    docker run --rm -e "E2E_CORE=${E2E_CORE}" -e "E2E_CLIENT=${E2E_CLIENT}" -v "${PROJECT_ROOT}:/src:ro" alpine:3.20 \
        sh -c 'apk add -q bash openrc busybox-openrc && bash /src/tests/test_install_e2e.sh'
    ;;
debian)
    cid=$(startDebian)
    trap 'docker stop -t 2 "${cid}" >/dev/null' EXIT
    docker exec -e "E2E_CORE=${E2E_CORE}" -e "E2E_CLIENT=${E2E_CLIENT}" "${cid}" bash /src/tests/test_install_e2e.sh
    ;;
domain)
    # 带域名的那条：Debian + systemd，证书由测试 CA 签，域名走 sslip.io
    cid=$(startDebian)
    trap 'docker stop -t 2 "${cid}" >/dev/null' EXIT
    docker exec "${cid}" bash /src/tests/test_install_domain_e2e.sh
    ;;
release)
    # 发版之后验已发布的 Release：README 那一行、从第二参（上一版 tag）自更新再回滚，各起一个新容器
    rc=0
    for stage in readme update; do
        cid=$(startDebian)
        docker exec "${cid}" bash /src/tests/e2e/release-smoke.sh "${2:?run.sh release OLD_TAG}" "${stage}" || rc=1
        docker stop -t 2 "${cid}" >/dev/null
    done
    exit "${rc}"
    ;;
chain)
    net="proxy-agent-e2e-chain-$$"
    exitCid=
    entryCid=
    docker network create "${net}" >/dev/null
    trap 'docker stop -t 2 ${exitCid} ${entryCid} >/dev/null 2>&1; docker network rm "${net}" >/dev/null' EXIT
    exitCid=$(startDebian --network "${net}")
    entryCid=$(startDebian --network "${net}")
    chainCode=$(docker exec -e "E2E_EXIT_CORE=${E2E_CORE}" "${exitCid}" bash /src/tests/e2e/chain-exit.sh)
    # 配置码里是出口机自己探到的公网 IP，容器里探到的是宿主机的出口，入口连不过去；换成出口容器在这个网络里的地址
    exitIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${exitCid}")
    codeRest=${chainCode#*@}
    chainCode="chain://ss2022@${exitIP}:${codeRest#*:}"
    exitTxBefore=$(txBytes "${exitCid}")
    rc=0
    docker exec -e E2E_CORE=xray -e E2E_CLIENT=xray -e "E2E_CHAIN_CODE=${chainCode}" "${entryCid}" \
        bash /src/tests/test_install_e2e.sh || rc=$?
    # 入口那边经链式下了 4 MB：这段时间出口机必须真的往外发了这么多，否则流量没走出口
    exitTx=$(($(txBytes "${exitCid}") - exitTxBefore))
    if ((exitTx >= 4000000)); then
        echo "✓ 出口机在入口测试期间发出 ${exitTx} 字节，经链式的 4 MB 下载确实由出口转发"
    else
        echo "✗ 出口机在入口测试期间只发出 ${exitTx} 字节，不到经链式下载的 4 MB"
        rc=1
    fi
    # 出口机不拆链式直接卸载：sing-box 只为链式而起（没有 6 / 9），也得停掉、删掉服务单元，否则卸完照常转发、重启后无限重试
    docker exec "${exitCid}" bash -c "printf '20\ny\n' | pasly" >/dev/null 2>&1
    left=$(docker exec "${exitCid}" bash -c 'pgrep -x sing-box; ls /etc/systemd/system/sing-box.service 2>/dev/null' || true)
    if [[ -z "${left}" ]]; then
        echo "✓ 出口机直接卸载后 sing-box 已停、服务单元已删"
    else
        echo "✗ 出口机卸载后 sing-box 还在：${left}"
        rc=1
    fi
    exit "${rc}"
    ;;
*)
    echo "usage: $0 alpine|debian [xray|singbox] [xray|singbox] | chain [xray|singbox] | domain | release OLD_TAG" >&2
    exit 2
    ;;
esac
