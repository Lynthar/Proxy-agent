#!/usr/bin/env bash
# run.sh alpine|debian [xray|singbox] — 在一次性容器里跑 tests/test_install_e2e.sh（真装机），内核默认 xray。
# alpine 用 OpenRC；debian 先把 systemd 当 PID 1 起来再 exec 进去，两条服务管理路径各验一遍。
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${E2E_DIR}/../.." && pwd)"
E2E_CORE="${2:-xray}"

case "${1:-}" in
alpine)
    # 真 Alpine 机器由 OpenRC 引导，容器镜像里没有，补上；bash 是脚本自己的硬要求
    docker run --rm -e "E2E_CORE=${E2E_CORE}" -v "${PROJECT_ROOT}:/src:ro" alpine:3.20 \
        sh -c 'apk add -q bash openrc && bash /src/tests/test_install_e2e.sh'
    ;;
debian)
    docker build -q -t proxy-agent-e2e-debian -f "${E2E_DIR}/debian-systemd.Dockerfile" "${E2E_DIR}" >/dev/null
    cid=$(docker run -d --rm --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v "${PROJECT_ROOT}:/src:ro" proxy-agent-e2e-debian)
    trap 'docker stop -t 2 "${cid}" >/dev/null' EXIT
    for _ in $(seq 1 30); do
        state=$(docker exec "${cid}" systemctl is-system-running 2>/dev/null || true)
        [[ "${state}" == "running" || "${state}" == "degraded" ]] && break
        sleep 1
    done
    docker exec -e "E2E_CORE=${E2E_CORE}" "${cid}" bash /src/tests/test_install_e2e.sh
    ;;
*)
    echo "usage: $0 alpine|debian [xray|singbox]" >&2
    exit 2
    ;;
esac
