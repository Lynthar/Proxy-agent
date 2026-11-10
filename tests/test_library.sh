#!/usr/bin/env bash
# 库加载不得探测宿主、联网或进入 doctor/菜单；配置函数由调用方显式执行。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/blocked" "$WORK/complete" "$WORK/incomplete/lib"
cp "$ROOT/install.sh" "$WORK/complete/"
cp -r "$ROOT/lib" "$ROOT/shell" "$WORK/complete/"
cp "$ROOT/install.sh" "$WORK/incomplete/"
cp "$ROOT/lib/constants.sh" "$WORK/incomplete/lib/"
cat > "$WORK/blocked/command" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >> "$LIBRARY_TEST_CALLS"
exit 87
SH
chmod 755 "$WORK/blocked/command"
for cmd in curl wget uname find systemctl id; do
    ln -s command "$WORK/blocked/$cmd"
done
export LIBRARY_TEST_CALLS="$WORK/calls"
export PATH="$WORK/blocked:$PATH"

for arg in '' doctor --dry-run RenewTLS; do
    output="$(PROXY_AGENT_DIR="$WORK/output" bash -s -- "$WORK/complete/install.sh" "$arg" <<'SH'
set -eo pipefail
currentClients=preserved
trap 'printf "caller-trap\n"' EXIT
# shellcheck source=/dev/null
source "$1" "$2"
[[ "$currentClients" == preserved ]]
[[ "$XRAY_CONF_DIR" == "$PROXY_AGENT_DIR/xray/conf" ]]
declare -F initXrayConfig initSingBoxConfig initVar >/dev/null
initVar
[[ -z "$currentClients" ]]
printf 'loaded\n'
SH
    )"
    [[ "$output" == $'loaded\ncaller-trap' ]]
    [[ ! -e "$WORK/output" && ! -e "$LIBRARY_TEST_CALLS" ]]
done

for noBootstrap in '' 1; do
    if PROXY_AGENT_DIR="$WORK/output" PROXY_AGENT_NO_BOOTSTRAP="$noBootstrap" \
        bash -c 'source "$1"' _ "$WORK/incomplete/install.sh" \
        > "$WORK/failure.out" 2> "$WORK/failure.err"; then
        echo 'incomplete source unexpectedly loaded' >&2
        exit 1
    fi
    [[ ! -s "$WORK/failure.out" && ! -e "$LIBRARY_TEST_CALLS" ]]
    [[ "$(cat "$WORK/failure.err")" == '[Proxy-agent] source requires a complete local lib/ directory.' ]]
    [[ -f "$WORK/incomplete/lib/constants.sh" && ! -e "$WORK/output" ]]
done
# 直接执行时自举的提示要分得出「整个 lib/ 不在」与「缺了几个」；curl、wget 是立刻失败的桩，自举失败后模块自检以 1 退出
mkdir -p "$WORK/nolib"
cp "$ROOT/install.sh" "$WORK/nolib/"
for case in incomplete nolib; do
    if LIBRARY_TEST_CALLS="$WORK/calls-$case" PROXY_AGENT_DIR="$WORK/output" \
        bash "$WORK/$case/install.sh" </dev/null >/dev/null 2>"$WORK/boot-$case.err"; then
        echo "$case install.sh unexpectedly ran" >&2
        exit 1
    fi
done
missing='i18n.sh utils.sh json-utils.sh system-detect.sh protocol-registry.sh carpool.sh topo.sh'
if ! grep -qF "[bootstrap] lib/ 缺 7 个模块（${missing}）" "$WORK/boot-incomplete.err" \
    || grep -qF 'lib/ 不存在' "$WORK/boot-incomplete.err"; then
    echo 'bootstrap with a partial lib/ should name the missing modules' >&2
    cat "$WORK/boot-incomplete.err" >&2
    exit 1
fi
if ! grep -qF '[bootstrap] lib/ 不存在' "$WORK/boot-nolib.err"; then
    echo 'bootstrap without lib/ should say it does not exist' >&2
    cat "$WORK/boot-nolib.err" >&2
    exit 1
fi
echo '8 library loading cases passed'
