#!/usr/bin/env bash
# ============================================================================
# carpool.sh - 拼车纯逻辑：成员文件校验、统计汇总、周期与判定、期望 clients、占位与页面（需先加载 i18n / constants / json-utils / protocol-registry）
# ============================================================================

# 防止重复加载
[[ -n "${_CARPOOL_LOADED:-}" ]] && return 0
readonly _CARPOOL_LOADED=1

# 可纳入拼车计量的协议：Xray 自己承载的入站。6/9 在 Xray 内核下跑在 sing-box sidecar，v2ray_api 计不到
readonly CARPOOL_PROTOCOLS=",0,1,3,4,7,12,"

# 日期算术只有这一份实现（Hinnant days_from_civil），bash 侧与 jq 判定共用；输入 "YYYY-MM-DD"
readonly _CARPOOL_JQ_DEFS='
def carpoolDays:
  (split("-") | map(tonumber)) as [$y0, $m, $d]
  | (if $m <= 2 then $y0 - 1 else $y0 end) as $y
  | ($y / 400 | floor) as $era
  | ($y - $era * 400) as $yoe
  | ((((153 * (if $m > 2 then $m - 3 else $m + 9 end) + 2) / 5) | floor) + $d - 1) as $doy
  | ($yoe * 365 + ($yoe / 4 | floor) - ($yoe / 100 | floor) + $doy) as $doe
  | $era * 146097 + $doe - 719468;
def carpoolFmtBytes:
  if . >= 1073741824 then "\(. / 1073741824 * 100 | floor / 100) GiB"
  elif . >= 1048576 then "\(. / 1048576 * 10 | floor / 10) MiB"
  elif . >= 1024 then "\(. / 1024 | floor) KiB"
  else "\(.) B" end;
'

# ============================================================================
# 名字与两个键
# ============================================================================

# carpoolMemberKey EMAIL → 账户名去掉最后一段协议后缀（与 initXrayClients / delName 同一剥法）
carpoolMemberKey() {
    printf '%s\n' "${1%-*}"
}

# carpoolSubscribeKey KEY → 成员键的第一段；订阅文件名与 md5 都按它算（defaultBase64Code 的口径）
carpoolSubscribeKey() {
    printf '%s\n' "${1%%-*}"
}

# carpoolIsValidMemberName NAME → 0=合法。与 customUserEmail 同一正则
carpoolIsValidMemberName() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$ ]]
}

# carpoolIsValidUUID UUID → 0=8-4-4-4-12 位十六进制
carpoolIsValidUUID() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# carpoolInstalledProtocolsJson ",0,6,7," → 其中可纳入拼车的 ID 升序数组 [0,7]
carpoolInstalledProtocolsJson() {
    local id out=
    for id in ${1//,/ }; do
        [[ "${CARPOOL_PROTOCOLS}" == *",${id},"* ]] && out+="${id},"
    done
    jq -cn --arg ids "${out}" '$ids | split(",") | map(select(. != "") | tonumber) | unique'
}

# ============================================================================
# 日期
# ============================================================================

# carpoolDaysInMonth YEAR MONTH → 该月天数
carpoolDaysInMonth() {
    local y=$1 m=$2
    case "${m}" in
        1 | 3 | 5 | 7 | 8 | 10 | 12) echo 31 ;;
        4 | 6 | 9 | 11) echo 30 ;;
        2) if (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)); then echo 29; else echo 28; fi ;;
        *) return 1 ;;
    esac
}

# carpoolIsValidDate YYYY-MM-DD → 0=真实存在的日期（闰年与大小月都查）
carpoolIsValidDate() {
    [[ "$1" =~ ^([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || return 1
    local y=$((10#${BASH_REMATCH[1]})) m=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
    [[ ${d} -le $(carpoolDaysInMonth "${y}" "${m}") ]]
}

# carpoolDaysBetween FROM TO → TO - FROM 的天数（可为负）
carpoolDaysBetween() {
    jq -rn --arg from "$1" --arg to "$2" "${_CARPOOL_JQ_DEFS}"'($to | carpoolDays) - ($from | carpoolDays)'
}

# carpoolPeriodStart TODAY RESETDAY → 当前周期起始日：本月的 RESETDAY，今天的日小于它则取上月的
carpoolPeriodStart() {
    local y m d r=$2
    IFS=- read -r y m d <<<"$1"
    y=$((10#${y})) m=$((10#${m})) d=$((10#${d}))
    if ((d < r)); then
        if ((m == 1)); then m=12 y=$((y - 1)); else m=$((m - 1)); fi
    fi
    printf '%04d-%02d-%02d\n' "${y}" "${m}" "${r}"
}

# carpoolNextPeriodStart TODAY RESETDAY → 下一次清零日
carpoolNextPeriodStart() {
    local y m d r=$2
    IFS=- read -r y m d <<<"$1"
    y=$((10#${y})) m=$((10#${m})) d=$((10#${d}))
    if ((d >= r)); then
        if ((m == 12)); then m=1 y=$((y + 1)); else m=$((m + 1)); fi
    fi
    printf '%04d-%02d-%02d\n' "${y}" "${m}" "${r}"
}

# ============================================================================
# members.json：校验、归一化、播种
# ============================================================================

# carpoolValidateMembers FILE INSTALLED [FOREIGN_JSON] → 0=合法；否则逐行打印原因（已本地化）并返回 1
# INSTALLED 形如 ",0,7,"；FOREIGN_JSON 是 inbound 里不归拼车管的账号 {name: uuid}，查 uuid 撞车
carpoolValidateMembers() {
    local file=$1 installed=$2 foreign=${3:-"{}"}
    if [[ ! -f "${file}" ]]; then
        t CARPOOL_ERR_FILE_MISSING "${file}"
        echo
        return 1
    fi
    if ! jq -e . "${file}" >/dev/null 2>&1; then
        t CARPOOL_ERR_BAD_JSON "${file}"
        echo
        return 1
    fi

    local installedJson raw
    installedJson=$(carpoolInstalledProtocolsJson "${installed}")
    raw=$(jq -r --argjson installed "${installedJson}" --argjson foreign "${foreign}" \
        --argjson allowed "$(carpoolInstalledProtocolsJson "${CARPOOL_PROTOCOLS}")" '
      if type != "object" then "NOT_OBJECT\t" else
        ( keys[] | select(. != "resetDay" and . != "notify" and . != "members") | "UNKNOWN_FIELD\t\(.)" ),
        ( if has("resetDay") and ((.resetDay | type) != "number" or .resetDay != (.resetDay | floor) or .resetDay < 1 or .resetDay > 28)
          then "BAD_RESET_DAY\t\(.resetDay | tojson)" else empty end ),
        ( if has("notify") then
            if (.notify | type) != "object" then "BAD_NOTIFY\tnotify" else
              .notify as $n
              | ( $n | keys[] | select(. != "label" and . != "warnPercent" and . != "digestHour" and . != "expireNoticeDays") | "UNKNOWN_FIELD\tnotify.\(.)" ),
                ( if $n.label != null and (($n.label | type) != "string" or ($n.label | length) == 0 or ($n.label | length) > 32) then "BAD_NOTIFY\tlabel" else empty end ),
                ( if $n.warnPercent != null and (($n.warnPercent | type) != "number" or $n.warnPercent != ($n.warnPercent | floor) or $n.warnPercent < 0 or $n.warnPercent > 100) then "BAD_NOTIFY\twarnPercent" else empty end ),
                ( if $n.digestHour != null and (($n.digestHour | type) != "number" or $n.digestHour != ($n.digestHour | floor) or $n.digestHour < 0 or $n.digestHour > 23) then "BAD_NOTIFY\tdigestHour" else empty end ),
                ( if $n.expireNoticeDays != null and (($n.expireNoticeDays | type) != "number" or $n.expireNoticeDays != ($n.expireNoticeDays | floor) or $n.expireNoticeDays < 0 or $n.expireNoticeDays > 365) then "BAD_NOTIFY\texpireNoticeDays" else empty end )
            end
          else empty end ),
        ( if (.members | type) != "object" then "NO_MEMBERS\t" else
            .members as $m
            | ( $m | keys_unsorted[] | select(test("^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$") | not) | "BAD_NAME\t\(.)" ),
              ( [$m | keys_unsorted[]] | group_by(ascii_downcase) | .[] | select(length > 1) | "DUP_NAME_CASE\t\(join(","))" ),
              ( [$m | keys_unsorted[]] | group_by(split("-")[0]) | .[] | select(length > 1) | "DUP_SUB_KEY\t\(join(","))" ),
              ( [$m | to_entries[] | select((.value | type) == "object" and (.value.uuid | type) == "string")] | group_by(.value.uuid) | .[] | select(length > 1) | "DUP_UUID\t\(map(.key) | join(","))" ),
              ( $m | to_entries[] | .key as $name | .value as $v
                | if ($v | type) != "object" then "BAD_MEMBER\t\($name)" else
                    ( $v | keys[] | select(. != "quotaGiB" and . != "expire" and . != "protocols" and . != "uuid") | "UNKNOWN_FIELD\t\($name).\(.)" ),
                    ( if $v.quotaGiB != null and (($v.quotaGiB | type) != "number" or $v.quotaGiB != ($v.quotaGiB | floor) or $v.quotaGiB < 0) then "BAD_QUOTA\t\($name)" else empty end ),
                    ( if $v.expire != null and (($v.expire | type) != "string" or ($v.expire != "" and ($v.expire | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not))) then "BAD_EXPIRE\t\($name)" else empty end ),
                    ( if $v.protocols != null and $v.protocols != "all" then
                        if ($v.protocols | type) != "array" or ($v.protocols | length) == 0 or ($v.protocols | all(type == "number" and . == floor) | not) then "BAD_PROTOCOLS\t\($name)"
                        else
                          ( $v.protocols[] | select(. as $p | $allowed | index($p) | not) | "PROTOCOL_UNSUPPORTED\t\($name)\t\(.)" ),
                          ( $v.protocols[] | select(. as $p | ($allowed | index($p)) != null and ($installed | index($p)) == null) | "PROTOCOL_NOT_INSTALLED\t\($name)\t\(.)" ),
                          ( [0, 7][] | select(. as $p | ($installed | index($p)) != null and ($v.protocols | index($p)) == null) | "PROTOCOL_REQUIRED\t\($name)\t\(.)" )
                        end
                      else empty end ),
                    ( if $v.uuid != null and (($v.uuid | type) != "string" or ($v.uuid | test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") | not)) then "BAD_UUID\t\($name)"
                      elif ($v.uuid | type) == "string" and ([$foreign | to_entries[] | select(.key != $name) | .value] | index($v.uuid)) != null then "UUID_TAKEN\t\($name)"
                      else empty end )
                  end )
          end )
      end' "${file}" 2>&1) || raw="INTERNAL"$'\t'"${raw}"

    # 日期是否真实存在（2 月 30 日之类）只在 bash 里查，jq 只查格式
    local name expire
    while IFS=$'\t' read -r name expire; do
        [[ -z "${name}" ]] && continue
        carpoolIsValidDate "${expire}" || raw+=$'\n'"BAD_EXPIRE"$'\t'"${name}"
    done < <(jq -r '.members? // {} | to_entries[]? | select((.value | type) == "object" and (.value.expire | type) == "string" and (.value.expire | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))) | "\(.key)\t\(.value.expire)"' "${file}" 2>/dev/null)

    local code a b failed=
    while IFS=$'\t' read -r code a b; do
        [[ -z "${code}" ]] && continue
        failed=1
        case "${code}" in
            NOT_OBJECT) t CARPOOL_ERR_NOT_OBJECT ;;
            NO_MEMBERS) t CARPOOL_ERR_NO_MEMBERS ;;
            UNKNOWN_FIELD) t CARPOOL_ERR_UNKNOWN_FIELD "${a}" ;;
            BAD_RESET_DAY) t CARPOOL_ERR_BAD_RESET_DAY "${a}" ;;
            BAD_NOTIFY) t CARPOOL_ERR_BAD_NOTIFY "${a}" ;;
            BAD_NAME) t CARPOOL_ERR_BAD_NAME "${a}" ;;
            DUP_NAME_CASE) t CARPOOL_ERR_DUP_NAME_CASE "${a}" ;;
            DUP_SUB_KEY) t CARPOOL_ERR_DUP_SUB_KEY "${a}" ;;
            DUP_UUID) t CARPOOL_ERR_DUP_UUID "${a}" ;;
            BAD_MEMBER) t CARPOOL_ERR_BAD_MEMBER "${a}" ;;
            BAD_QUOTA) t CARPOOL_ERR_BAD_QUOTA "${a}" ;;
            BAD_EXPIRE) t CARPOOL_ERR_BAD_EXPIRE "${a}" ;;
            BAD_PROTOCOLS) t CARPOOL_ERR_BAD_PROTOCOLS "${a}" ;;
            PROTOCOL_UNSUPPORTED) t CARPOOL_ERR_PROTOCOL_UNSUPPORTED "${a}" "${b}" ;;
            PROTOCOL_NOT_INSTALLED) t CARPOOL_ERR_PROTOCOL_NOT_INSTALLED "${a}" "${b}" ;;
            PROTOCOL_REQUIRED) t CARPOOL_ERR_PROTOCOL_REQUIRED "${a}" "${b}" ;;
            BAD_UUID) t CARPOOL_ERR_BAD_UUID "${a}" ;;
            UUID_TAKEN) t CARPOOL_ERR_UUID_TAKEN "${a}" ;;
            *) printf '%s %s %s' "${code}" "${a}" "${b}" ;;
        esac
        echo
    done <<<"${raw}"
    [[ -z "${failed}" ]]
}

# carpoolNormalizeMembers FILE INSTALLED → 默认值填好、"all" 展开、配额换成字节的 JSON；先过校验再调
# digestHour 为 null 表示关闭，保留 null
carpoolNormalizeMembers() {
    local installedJson
    installedJson=$(carpoolInstalledProtocolsJson "$2")
    jq -c --argjson installed "${installedJson}" --arg defaultLabel "$(t CARPOOL_DEFAULT_LABEL)" '
      (.notify // {}) as $n
      | {
          resetDay: (.resetDay // 1),
          notify: {
            label: ($n.label // $defaultLabel),
            warnPercent: ($n.warnPercent // 80),
            digestHour: (if ($n | has("digestHour")) then $n.digestHour else 8 end),
            expireNoticeDays: ($n.expireNoticeDays // 3)
          },
          members: ((.members // {}) | with_entries(.value |= {
            quotaBytes: ((.quotaGiB // 0) * 1073741824),
            expire: (.expire // ""),
            protocols: (if (.protocols // "all") == "all" then $installed else (.protocols | unique) end),
            uuid: (.uuid // "")
          }))
        }' "$1"
}

# carpoolAccountsFromClients CLIENTS_JSON → [{name, uuid}]，name 已剥协议后缀，凭据取 id 或 password
carpoolAccountsFromClients() {
    jq -c '[ .[]? | {name: ((.email // "") | sub("-[^-]*$"; "")), uuid: (.id // .password // "")} | select(.name != "") ]' <<<"$1"
}

# carpoolSeedMembers ACCOUNTS_JSON → 从现有账号生成初始 members.json：全员不限额、不限期、全协议
# 不写 uuid——state 开启时从 inbound 采用，文件里不留凭据
carpoolSeedMembers() {
    jq --arg defaultLabel "$(t CARPOOL_DEFAULT_LABEL)" '{
        resetDay: 1,
        notify: {label: $defaultLabel, warnPercent: 80, digestHour: 8, expireNoticeDays: 3},
        members: (map({key: .name, value: {quotaGiB: 0, expire: "", protocols: "all"}}) | from_entries)
      }' <<<"$1"
}

# ============================================================================
# 统计采集结果 → 成员用量
# ============================================================================

# carpoolSumStats STATS_JSON → {"<成员键>": {"up": N, "down": N}}
# statsquery 的 value 有数字、字符串、0 时整键省略三种形态，都认；非 user>>> 的计数器忽略
carpoolSumStats() {
    jq -c '
      [ .stat[]? | (.name | split(">>>")) as $p
        | select(($p | length) == 4 and $p[0] == "user" and $p[2] == "traffic")
        | {key: ($p[1] | sub("-[^-]*$"; "")), dir: $p[3], value: ((.value // 0) | tonumber)} ]
      | group_by(.key)
      | map({key: .[0].key, value: {
          up: (map(select(.dir == "uplink") | .value) | add // 0),
          down: (map(select(.dir == "downlink") | .value) | add // 0)}})
      | from_entries' <<<"$1"
}

# carpoolAddUsage STATE SUMS → 把增量累加进 state 里已有成员；不是成员的键丢弃
carpoolAddUsage() {
    jq -c --argjson sums "$2" '
      .members |= with_entries(.key as $k
        | if $sums[$k] then .value.upBytes += $sums[$k].up | .value.downBytes += $sums[$k].down else . end)' <<<"$1"
}

# ============================================================================
# state.json
# ============================================================================

# carpoolInitialState APIPORT PERIOD → 开启时的 state 内容；成员、resetDay 与 notify 由 carpoolMergeState 填
# resetDay / notify 是「已应用的副本」：members.json 校验不过的那个 tick 仍要有周期可算
carpoolInitialState() {
    jq -cn --argjson apiPort "$1" --arg period "$2" --arg defaultLabel "$(t CARPOOL_DEFAULT_LABEL)" '{
        enabled: true, apiPort: $apiPort, period: $period, lastTick: "", resetDay: 1,
        notify: {label: $defaultLabel, warnPercent: 80, digestHour: 8, expireNoticeDays: 3},
        pageEnabled: false, pageToken: "", collectFailures: 0, notified: {}, events: [], members: {}
      }'
}

# carpoolReadState [FILE] → 打印 state JSON；文件缺失或不是合法 JSON 返回 1
carpoolReadState() {
    local file=${1:-${CARPOOL_STATE_FILE}}
    [[ -f "${file}" ]] || return 1
    jq -ce . "${file}" 2>/dev/null
}

# carpoolWriteState JSON [FILE] → 原子写入（不留 .bak，state 每个 tick 都变）
carpoolWriteState() {
    jsonWriteFile "${2:-${CARPOOL_STATE_FILE}}" "$1" false
}

# carpoolMergeState OLD_STATE NORMALIZED INBOUND_JSON → 成员表按文件重建：顺序随文件，计数与状态沿用，
# 文件里没有的成员删掉；uuid 采用顺序 文件 → 旧 state → inbound 同名账号 → 空（由调用方生成）
carpoolMergeState() {
    jq -c --argjson members "$2" --argjson inbound "$3" '
      . as $old
      | ($members.members | to_entries | map(.key as $n | .value as $m
          | ($old.members[$n] // {}) as $o
          | {key: $n, value: {
              uuid: (if $m.uuid != "" then $m.uuid elif ($o.uuid // "") != "" then $o.uuid else ($inbound[$n] // "") end),
              quotaBytes: $m.quotaBytes, expire: $m.expire, protocols: $m.protocols,
              upBytes: ($o.upBytes // 0), downBytes: ($o.downBytes // 0),
              status: ($o.status // "active"), reason: ($o.reason // "")}})
        | from_entries) as $nm
      | $old | .members = $nm | .resetDay = $members.resetDay | .notify = $members.notify' <<<"$1"
}

# carpoolSyncLimits STATE NORMALIZED → 文件里的即时类字段同步进 state：resetDay、notify、在册成员的 quotaBytes 与 expire
# protocols 与 uuid 是「需应用」类不动；文件里没有的成员也不动（增删只在应用时做）
carpoolSyncLimits() {
    jq -c --argjson m "$2" '
      .resetDay = $m.resetDay | .notify = $m.notify
      | .members |= with_entries(.key as $k
          | if $m.members[$k] then .value.quotaBytes = $m.members[$k].quotaBytes | .value.expire = $m.members[$k].expire else . end)' <<<"$1"
}

# carpoolForeignAccounts STATE CURRENT_MAP → {name: uuid}，inbound 里不归拼车管的账号（校验 uuid 撞车用）
# CURRENT_MAP 形如 {"<ID>": [clients…]}
carpoolForeignAccounts() {
    jq -c --argjson state "$1" '
      [.[] | .[]?] | map({key: ((.email // "") | sub("-[^-]*$"; "")), value: (.id // .password // "")})
      | map(select(.key != "" and (.key as $k | $state.members | has($k) | not))) | from_entries' <<<"$2"
}

# carpoolDiffMembers OLD_STATE NORMALIZED INBOUND_JSON → 应用前给车主看的差异：
# {added, removed, protocols:[{name,from,to}], uuid:[name], quota:[{name,from,to}], expire:[{name,from,to}], unmanaged:[name]}
carpoolDiffMembers() {
    jq -c --argjson members "$2" --argjson inbound "$3" '
      .members as $old | $members.members as $new
      | {
          added: [$new | keys_unsorted[] | select($old[.] == null)],
          removed: [$old | keys_unsorted[] | select($new[.] == null)],
          protocols: [$new | to_entries[] | select($old[.key] != null and ($old[.key].protocols | sort) != (.value.protocols | sort))
                      | {name: .key, from: $old[.key].protocols, to: .value.protocols}],
          uuid: [$new | to_entries[] | select($old[.key] != null and .value.uuid != "" and ($old[.key].uuid // "") != "" and .value.uuid != $old[.key].uuid) | .key],
          quota: [$new | to_entries[] | select($old[.key] != null and $old[.key].quotaBytes != .value.quotaBytes)
                  | {name: .key, from: $old[.key].quotaBytes, to: .value.quotaBytes}],
          expire: [$new | to_entries[] | select($old[.key] != null and $old[.key].expire != .value.expire)
                   | {name: .key, from: $old[.key].expire, to: .value.expire}],
          unmanaged: [$inbound | keys_unsorted[] | select($new[.] == null)]
        }' <<<"$1"
}

# ============================================================================
# 判定
# ============================================================================

# carpoolJudge STATE NOTIFY TODAY PERIOD_START → {"state": …, "events": […]}，一次过：
# 换周期清零 → 逐人按到期 / 配额定目标状态（到期优先于超额，manual 永不自动恢复）→ 预警与到期提醒
# 预警 / 提醒的去重键记在 state.notified，换周期清空；events 元素形如 {type, name, …}
carpoolJudge() {
    jq -c --argjson notify "$2" --arg today "$3" --arg period "$4" "${_CARPOOL_JQ_DEFS}"'
      def usage: .upBytes + .downBytes;
      def overQuota: .quotaBytes > 0 and usage >= .quotaBytes;
      def expired: .expire != "" and .expire < $today;
      def target:
        if .status == "disabled" and .reason == "manual" then {status: "disabled", reason: "manual"}
        elif expired then {status: "disabled", reason: "expired"}
        elif overQuota then {status: "disabled", reason: "quota"}
        else {status: "active", reason: ""} end;
      def daysLeft: (.expire | carpoolDays) - ($today | carpoolDays);

      (if .period != $period then
         {type: "period", previous: .period, usage: (.members | map_values({up: .upBytes, down: .downBytes}))} as $ev
         | .members |= map_values(.upBytes = 0 | .downBytes = 0)
         | .notified = {} | .period = $period | .pendingEvents = [$ev]
       else .pendingEvents = [] end)
      | reduce (.members | to_entries[]) as $e (.;
          $e.key as $n | $e.value as $m | ($m | target) as $t
          | .members[$n].status = $t.status | .members[$n].reason = $t.reason
          | if $m.status == "active" and $t.status == "disabled" then
              .pendingEvents += [{type: "disabled", name: $n, reason: $t.reason}]
            elif $m.status == "disabled" and $t.status == "active" then
              .pendingEvents += [{type: "restored", name: $n}]
            else . end
          | if $t.status == "active" and $notify.warnPercent > 0 and $m.quotaBytes > 0
               and (($m | usage) * 100 / $m.quotaBytes | floor) >= $notify.warnPercent
               and ((.notified["warn:" + $n] // false) | not) then
              .notified["warn:" + $n] = true
              | .pendingEvents += [{type: "warn", name: $n, percent: (($m | usage) * 100 / $m.quotaBytes | floor), used: ($m | usage), quota: $m.quotaBytes}]
            else . end
          | if $t.status == "active" and $notify.expireNoticeDays > 0 and $m.expire != ""
               and ($m | daysLeft) >= 0 and ($m | daysLeft) <= $notify.expireNoticeDays
               and ((.notified["expire:" + $n + ":" + $m.expire] // false) | not) then
              .notified["expire:" + $n + ":" + $m.expire] = true
              | .pendingEvents += [{type: "expiring", name: $n, date: $m.expire, days: ($m | daysLeft)}]
            else . end)
      | {state: del(.pendingEvents), events: .pendingEvents}' <<<"$1"
}

# carpoolAppendEvents STATE EVENTS NOW → 事件记进 state.events（只留 type/name/reason，最近 50 条，页面用）
carpoolAppendEvents() {
    jq -c --argjson events "$2" --arg now "$3" '
      .events = ((.events // []) + ($events | map(select(.type != "digest")) | map({time: $now, type, name, reason, count} | with_entries(select(.value != null))))) | .events |= .[-50:]' <<<"$1"
}

# carpoolCloseGroups STATE TODAY → 关闭拼车时停用者的分组：restore（超额且未到期）、expiredNow（超额且已过期）、keepExpired、keepManual
carpoolCloseGroups() {
    jq -c --arg today "$2" '
      [.members | to_entries[] | select(.value.status == "disabled")] as $d
      | {
          restore: [$d[] | select(.value.reason == "quota" and (.value.expire == "" or .value.expire >= $today)) | .key],
          expiredNow: [$d[] | select(.value.reason == "quota" and .value.expire != "" and .value.expire < $today) | .key],
          keepExpired: [$d[] | select(.value.reason == "expired") | .key],
          keepManual: [$d[] | select(.value.reason == "manual") | .key]
        }' <<<"$1"
}

# carpoolApplyClose STATE GROUPS RESTORE_ALL → restore 组恢复，expiredNow 翻成 expired；RESTORE_ALL=true 时其余停用者也恢复
carpoolApplyClose() {
    jq -c --argjson g "$2" --argjson all "$3" '
      .members |= with_entries(.key as $k
        | if ($g.restore | index($k)) != null or ($all and (($g.keepExpired + $g.keepManual) | index($k)) != null)
          then .value.status = "active" | .value.reason = ""
          elif ($g.expiredNow | index($k)) != null then .value.reason = "expired"
          else . end)' <<<"$1"
}

# carpoolResetUsageState STATE [NAME] → 清零一人或全员的用量并清掉对应的预警去重键；状态翻转交给随后的判定
carpoolResetUsageState() {
    jq -c --arg n "${2:-}" '
      .members |= with_entries(if $n == "" or .key == $n then .value.upBytes = 0 | .value.downBytes = 0 else . end)
      | .notified |= with_entries(select(if (.key | startswith("warn:")) then ($n != "" and .key != ("warn:" + $n)) else true end))' <<<"$1"
}

# carpoolDiffIsEmpty DIFF → 0=除「未纳入」以外没有任何差异
carpoolDiffIsEmpty() {
    jq -e '(.added + .removed + .protocols + .uuid + .quota + .expire) | length == 0' <<<"$1" >/dev/null 2>&1
}

# carpoolDiffNeedsConfirm DIFF → 0=含删除成员或换 UUID，应用前要逐项确认
carpoolDiffNeedsConfirm() {
    jq -e '(.removed + .uuid) | length > 0' <<<"$1" >/dev/null 2>&1
}

# carpoolDiffText DIFF → 应用前给车主看的差异，一行一条（已本地化）
carpoolDiffText() {
    local d=$1 line unlimited
    unlimited=$(t CARPOOL_UNLIMITED)
    while IFS= read -r line; do [[ -n "${line}" ]] && t CARPOOL_DIFF_ADDED "${line}" && echo; done < <(jq -r '.added[]' <<<"${d}")
    while IFS= read -r line; do [[ -n "${line}" ]] && t CARPOOL_DIFF_REMOVED "${line}" && echo; done < <(jq -r '.removed[]' <<<"${d}")
    while IFS=$'\t' read -r name from to; do
        [[ -n "${name}" ]] && t CARPOOL_DIFF_PROTOCOLS "${name}" "${from}" "${to}" && echo
    done < <(jq -r '.protocols[] | "\(.name)\t\(.from | tojson)\t\(.to | tojson)"' <<<"${d}")
    while IFS= read -r line; do [[ -n "${line}" ]] && t CARPOOL_DIFF_UUID "${line}" && echo; done < <(jq -r '.uuid[]' <<<"${d}")
    while IFS=$'\t' read -r name from to; do
        [[ -n "${name}" ]] && t CARPOOL_DIFF_QUOTA "${name}" "${from}" "${to}" && echo
    done < <(jq -r --arg u "${unlimited}" "${_CARPOOL_JQ_DEFS}"'def q: if . > 0 then carpoolFmtBytes else $u end; .quota[] | "\(.name)\t\(.from | q)\t\(.to | q)"' <<<"${d}")
    while IFS=$'\t' read -r name from to; do
        [[ -n "${name}" ]] && t CARPOOL_DIFF_EXPIRE "${name}" "${from}" "${to}" && echo
    done < <(jq -r '.expire[] | "\(.name)\t\(if .from == "" then "-" else .from end)\t\(if .to == "" then "-" else .to end)"' <<<"${d}")
    line=$(jq -r '.unmanaged | join(", ")' <<<"${d}")
    if [[ -n "${line}" ]]; then
        t CARPOOL_DIFF_UNMANAGED "${line}"
        echo
    fi
}

# ============================================================================
# 期望 clients
# ============================================================================

# carpoolExpectedClients ID STATE CURRENT_CLIENTS → 该协议文件应有的 clients 数组：
# [不归拼车管的账号，原序] + [active、协议含 ID、uuid 已定的成员，members 顺序]；对象形状与 initXrayClients 一致
carpoolExpectedClients() {
    local id=$1 suffix
    [[ "${CARPOOL_PROTOCOLS}" == *",${id},"* ]] || return 1
    suffix=$(getProtocolEmailSuffix 1 "${id}") || return 1
    jq -c --argjson id "${id}" --arg suffix "${suffix}" --argjson state "$2" '
      def shape($n; $u):
        if $id == 0 then {id: $u, flow: "xtls-rprx-vision", email: ($n + "-" + $suffix)}
        elif $id == 7 then {id: $u, email: ($n + "-" + $suffix), flow: "xtls-rprx-vision"}
        elif $id == 3 then {id: $u, email: ($n + "-" + $suffix), alterId: 0}
        elif $id == 4 then {password: $u, email: ($n + "-" + $suffix)}
        else {id: $u, email: ($n + "-" + $suffix)} end;
      [ .[]? | select(((.email // "") | sub("-[^-]*$"; "")) as $k | ($state.members | has($k)) | not) ]
      + [ $state.members | to_entries[]
          | select(.value.status == "active" and (.value.protocols | index($id)) != null and .value.uuid != "")
          | shape(.key; .value.uuid) ]' <<<"$3"
}

# carpoolClientsEqual A B → 0=两个 clients 数组内容一致（键序无关，元素顺序有关）
carpoolClientsEqual() {
    [[ "$(jq -Sc . <<<"$1")" == "$(jq -Sc . <<<"$2")" ]]
}

# carpoolReconcilePayload STATE CURRENT_MAP → 只含有差异协议的 {"<ID>": [期望 clients]}，交给账户事务的 set；
# 全部一致时输出空串、返回 0
carpoolReconcilePayload() {
    local id current expected payload="{}" changed=
    for id in $(jq -r 'keys_unsorted[]' <<<"$2"); do
        current=$(jq -c --arg k "${id}" '.[$k]' <<<"$2")
        expected=$(carpoolExpectedClients "${id}" "$1" "${current}") || return 1
        if ! carpoolClientsEqual "${current}" "${expected}"; then
            payload=$(jq -c --arg k "${id}" --argjson v "${expected}" '.[$k] = $v' <<<"${payload}")
            changed=1
        fi
    done
    [[ -n "${changed}" ]] && printf '%s\n' "${payload}"
    return 0
}

# ============================================================================
# 停用者的订阅占位
# ============================================================================

# carpoolReasonText REASON → quota / expired / manual 的本地化文案
carpoolReasonText() {
    case "$1" in
        quota) t CARPOOL_REASON_QUOTA ;;
        expired) t CARPOOL_REASON_EXPIRED ;;
        manual) t CARPOOL_REASON_MANUAL ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# carpoolUrlEncode TEXT → 百分号编码，只保留 RFC 3986 unreserved；按字节处理，多字节字符也安全
carpoolUrlEncode() {
    local LC_ALL=C s=$1 i c out=
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:i:1}
        case "${c}" in
            [A-Za-z0-9.~_-]) out+="${c}" ;;
            *) out+=$(printf '%%%02X' "'${c}") ;;
        esac
    done
    printf '%s\n' "${out}"
}

# carpoolPlaceholderDefault LABEL → default 订阅内容：一条指向 127.0.0.1:1 的 vless 链接，base64
carpoolPlaceholderDefault() {
    printf 'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:1?encryption=none&security=none&type=tcp#%s\n' \
        "$(carpoolUrlEncode "$1")" | base64 | tr -d '\n'
    echo
}

# carpoolPlaceholderClash LABEL → clashMeta 订阅内容：一个指向 127.0.0.1:1 的 socks5 节点
carpoolPlaceholderClash() {
    printf 'proxies:\n  - name: %s\n    type: socks5\n    server: 127.0.0.1\n    port: 1\n' "$(jq -cn --arg l "$1" '$l')"
}

# carpoolPlaceholderSingBoxProfile LABEL → sing-box_profiles 内容：出站数组
carpoolPlaceholderSingBoxProfile() {
    jq -cn --arg tag "$1" '[{tag: $tag, type: "socks", server: "127.0.0.1", server_port: 1}]'
}

# carpoolPlaceholderSingBoxConfig LABEL → sing-box 完整配置：最小可解析，不下载模板
carpoolPlaceholderSingBoxConfig() {
    jq -n --arg tag "$1" '{log: {level: "warn"}, outbounds: [{tag: $tag, type: "socks", server: "127.0.0.1", server_port: 1}, {tag: "direct", type: "direct"}]}'
}

# ============================================================================
# 事件文案与页面
# ============================================================================

# carpoolFormatBytes BYTES → 人读的量（GiB 两位小数 / MiB 一位 / KiB / B）
carpoolFormatBytes() {
    jq -rn --argjson n "$1" "${_CARPOOL_JQ_DEFS}"'$n | carpoolFmtBytes'
}

# carpoolEventText EVENT_JSON → 一条本地化的事件描述（通知与页面共用）
carpoolEventText() {
    local type name
    type=$(jq -r '.type' <<<"$1")
    name=$(jq -r '.name // ""' <<<"$1")
    case "${type}" in
        disabled) t CARPOOL_EVENT_DISABLED "${name}" "$(carpoolReasonText "$(jq -r '.reason' <<<"$1")")" ;;
        restored) t CARPOOL_EVENT_RESTORED "${name}" ;;
        warn) t CARPOOL_EVENT_WARN "${name}" "$(jq -r '.percent' <<<"$1")" \
            "$(carpoolFormatBytes "$(jq -r '.used' <<<"$1")")" "$(carpoolFormatBytes "$(jq -r '.quota' <<<"$1")")" ;;
        expiring) t CARPOOL_EVENT_EXPIRING "${name}" "$(jq -r '.date' <<<"$1")" "$(jq -r '.days' <<<"$1")" ;;
        period)
            t CARPOOL_EVENT_PERIOD
            jq -r "${_CARPOOL_JQ_DEFS}"'.usage // {} | to_entries[] | "  \(.key): \((.value.up + .value.down) | carpoolFmtBytes)"' <<<"$1"
            return 0
            ;;
        applied) t CARPOOL_EVENT_APPLIED "$(jq -r '.summary // ""' <<<"$1")" ;;
        invalid) t CARPOOL_EVENT_INVALID "$(jq -r '.reasons // ""' <<<"$1")" ;;
        collectFailed) t CARPOOL_EVENT_COLLECT_FAILED "$(jq -r '.count' <<<"$1")" ;;
        collectRecovered) t CARPOOL_EVENT_COLLECT_RECOVERED ;;
        txFailed) t CARPOOL_EVENT_TX_FAILED ;;
        inactive) t CARPOOL_EVENT_INACTIVE ;;
        closed) t CARPOOL_EVENT_CLOSED "$(jq -r '.restored // "-"' <<<"$1")" "$(jq -r '.kept // "-"' <<<"$1")" ;;
        digest) t CARPOOL_DIGEST_TITLE "$(jq -r '.date // ""' <<<"$1")" ;;
        *) printf '%s %s' "${type}" "${name}" ;;
    esac
    echo
}

# carpoolDigestText STATE TODAY → 每日摘要正文：标题 + 每人一行（名字 已用/配额 状态）
carpoolDigestText() {
    t CARPOOL_DIGEST_TITLE "$2"
    echo
    carpoolUsageTable "$1" | awk -F'\t' '{ printf "%s: %s / %s · %s\n", $1, $2, $3, $5 }'
}

# carpoolNotifyText LABEL EVENTS → 一条通知的正文：第一行标签，之后每个事件一行；没有事件输出空
# 只含标签、成员名、数字、日期，不含 UUID、链接、主机名、IP
carpoolNotifyText() {
    local ev body=
    while read -r ev; do
        [[ -n "${ev}" ]] || continue
        body+="$(carpoolEventText "${ev}")"$'\n'
    done < <(jq -c '.[]?' <<<"$2")
    [[ -n "${body}" ]] || return 0
    printf '[%s]\n%s' "$1" "${body}"
}

# carpoolReadTelegramConf FILE → 两行输出：bot token、chat id；文件缺失、字段缺失或格式不对返回 1
# token 形如 123456789:AAxxxx（≥30 位），chat id 是整数（群组 / 频道为负）
carpoolReadTelegramConf() {
    local token chat
    [[ -f "$1" ]] || return 1
    token=$(sed -n 's/^TG_BOT_TOKEN=//p' "$1" | head -1 | tr -d '[:space:]"'"'"'')
    chat=$(sed -n 's/^TG_CHAT_ID=//p' "$1" | head -1 | tr -d '[:space:]"'"'"'')
    [[ "${token}" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] || return 1
    [[ "${chat}" =~ ^-?[0-9]{1,20}$ ]] || return 1
    printf '%s\n%s\n' "${token}" "${chat}"
}

# carpoolTickNotices STATE TODAY HOUR MEMBERS_OK FILE_ID → {"state", "events"}：tick 级通知的去重判断
# 文件无效按 FILE_ID（内容摘要）一次；采集连续失败满 3 次一次、恢复一次；每日摘要在 digestHour 之后的第一次 tick 一次
carpoolTickNotices() {
    jq -c --arg today "$2" --argjson hour "$3" --argjson ok "$4" --arg fid "$5" '
      .pendingEvents = []
      | if ($ok | not) and ((.notified["invalid:" + $fid] // false) | not) then
          .notified["invalid:" + $fid] = true | .pendingEvents += [{type: "invalid"}]
        else . end
      | if .collectFailures >= 3 and ((.notified["collect:failed"] // false) | not) then
          .notified["collect:failed"] = true | .pendingEvents += [{type: "collectFailed", count: .collectFailures}]
        elif .collectFailures == 0 and (.notified["collect:failed"] // false) then
          del(.notified["collect:failed"]) | .pendingEvents += [{type: "collectRecovered"}]
        else . end
      | if (.notify.digestHour != null) and $hour >= .notify.digestHour and ((.notified["digest:" + $today] // false) | not) then
          .notified["digest:" + $today] = true | .pendingEvents += [{type: "digest", date: $today}]
        else . end
      | {state: del(.pendingEvents), events: .pendingEvents}' <<<"$1"
}

# carpoolUsageTable STATE → 文本表（菜单「查看用量」与每日摘要共用）：名字 已用 配额 到期 状态
carpoolUsageTable() {
    jq -r --arg unlimited "$(t CARPOOL_UNLIMITED)" --arg active "$(t CARPOOL_STATUS_ACTIVE)" \
        --arg quota "$(t CARPOOL_REASON_QUOTA)" --arg expired "$(t CARPOOL_REASON_EXPIRED)" --arg manual "$(t CARPOOL_REASON_MANUAL)" \
        "${_CARPOOL_JQ_DEFS}"'
      .members | to_entries[] | .value as $m
      | "\(.key)\t\($m.upBytes + $m.downBytes | carpoolFmtBytes)\t\(if $m.quotaBytes > 0 then ($m.quotaBytes | carpoolFmtBytes) else $unlimited end)\t\(if $m.expire == "" then "-" else $m.expire end)\t\(if $m.status == "active" then $active elif $m.reason == "quota" then $quota elif $m.reason == "expired" then $expired else $manual end)"' <<<"$1"
}

# carpoolNginxLocationBlock PAGE_DIR → 嵌进 subscribe.conf 的 location 块：路径只收 32–64 位十六进制、只读静态文件、
# 禁脚本禁外链、不进搜索引擎；带起止标记，撤掉时按标记整段删。正则必须带引号：nginx 把裸 {32,64} 当块的花括号
carpoolNginxLocationBlock() {
    cat <<EOF
    # carpool-page-begin
    location ~ "^/s/carpool/([0-9a-f]{32,64})\$" {
        default_type 'text/html; charset=utf-8';
        alias $1/\$1;
        add_header X-Robots-Tag noindex;
        add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'";
    }
    # carpool-page-end
EOF
}

# _carpoolPageStrings → 页面用的本地化字串对象（jq --argjson）
_carpoolPageStrings() {
    jq -cn --arg generated "$(t CARPOOL_PAGE_GENERATED)" --arg period "$(t CARPOOL_PAGE_PERIOD)" \
        --arg nextReset "$(t CARPOOL_PAGE_NEXT_RESET)" --arg name "$(t CARPOOL_PAGE_NAME)" --arg used "$(t CARPOOL_PAGE_USED)" \
        --arg quota "$(t CARPOOL_PAGE_QUOTA)" --arg expire "$(t CARPOOL_PAGE_EXPIRE)" --arg status "$(t CARPOOL_PAGE_STATUS)" \
        --arg others "$(t CARPOOL_PAGE_OTHERS)" --arg events "$(t CARPOOL_PAGE_EVENTS)" --arg noMembers "$(t CARPOOL_PAGE_NO_MEMBERS)" \
        --arg unlimited "$(t CARPOOL_UNLIMITED)" --arg active "$(t CARPOOL_STATUS_ACTIVE)" --arg disabled "$(t CARPOOL_STATUS_DISABLED)" \
        --arg rQuota "$(t CARPOOL_REASON_QUOTA)" --arg rExpired "$(t CARPOOL_REASON_EXPIRED)" --arg rManual "$(t CARPOOL_REASON_MANUAL)" \
        --arg evDisabled "$(t CARPOOL_EVENT_DISABLED '%s' '%s')" --arg evRestored "$(t CARPOOL_EVENT_RESTORED '%s')" \
        --arg evWarn "$(t CARPOOL_PAGE_EV_WARN '%s')" --arg evExpiring "$(t CARPOOL_PAGE_EV_EXPIRING '%s')" \
        --arg evPeriod "$(t CARPOOL_PAGE_EV_PERIOD)" --arg evApplied "$(t CARPOOL_PAGE_EV_APPLIED)" \
        --arg evInvalid "$(t CARPOOL_PAGE_FILE_INVALID)" --arg evCollectFailed "$(t CARPOOL_EVENT_COLLECT_FAILED '%s')" \
        --arg evCollectRecovered "$(t CARPOOL_EVENT_COLLECT_RECOVERED)" --arg evTxFailed "$(t CARPOOL_EVENT_TX_FAILED)" \
        --arg lang "${CURRENT_LANG:-zh_CN}" \
        '$ARGS.named'
}

# 页面壳：无脚本、无外链、无版本字样；CSP 只放行内联样式
readonly _CARPOOL_PAGE_CSS='body{font:15px/1.5 system-ui,sans-serif;margin:0 auto;max-width:720px;padding:16px;color:#222;background:#fafafa}h1{font-size:1.4em;margin:.2em 0}h2{font-size:1.1em;margin:1.2em 0 .4em}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #ddd;white-space:nowrap}tr.disabled td{color:#999}.bar{height:6px;background:#e5e5e5;border-radius:3px;overflow:hidden}.bar i{display:block;height:100%;background:#3b7}.bar i.hot{background:#d55}.warn{color:#b60;background:#fff3e0;padding:8px;border-radius:4px}.muted{color:#777;font-size:.9em}ul{padding-left:1.2em}'

# carpoolRenderOwnerPage STATE NORMALIZED TODAY NOW [OTHERS_JSON] [PENDING_TEXT] → 车主全员页 HTML
# OTHERS_JSON 是未纳入拼车的账号名数组；PENDING_TEXT 是配置文件待应用 / 无效的提示，空则不显示
carpoolRenderOwnerPage() {
    local state=$1 members=$2 today=$3 now=$4 others=${5:-"[]"} pending=${6:-}
    local resetDay nextReset
    resetDay=$(jq -r '.resetDay' <<<"${members}")
    nextReset=$(carpoolNextPeriodStart "${today}" "${resetDay}")
    jq -rn --argjson s "${state}" --argjson m "${members}" --argjson L "$(_carpoolPageStrings)" --argjson others "${others}" \
        --arg now "${now}" --arg nextReset "${nextReset}" --arg pending "${pending}" --arg css "${_CARPOOL_PAGE_CSS}" "${_CARPOOL_JQ_DEFS}"'
      def esc: tostring | @html;
      def statusText($m): if $m.status == "active" then $L.active else "\($L.disabled) · \(if $m.reason == "quota" then $L.rQuota elif $m.reason == "expired" then $L.rExpired else $L.rManual end)" end;
      def pct($m): if $m.quotaBytes > 0 then (($m.upBytes + $m.downBytes) * 100 / $m.quotaBytes | floor) else null end;
      def row: .key as $n | .value as $m | pct($m) as $p
        | "<tr class=\"\($m.status)\"><td>\($n | esc)</td><td>\(($m.upBytes + $m.downBytes) | carpoolFmtBytes)"
          + (if $p != null then "<div class=\"bar\"><i class=\"\(if $p >= 80 then "hot" else "" end)\" style=\"width:\([$p, 100] | min)%\"></i></div>" else "" end)
          + "</td><td>\(if $m.quotaBytes > 0 then ($m.quotaBytes | carpoolFmtBytes) else $L.unlimited end)</td>"
          + "<td>\(if $p != null then "\($p)%" else "-" end)</td><td>\(if $m.expire == "" then "-" else $m.expire end)</td><td>\(statusText($m) | esc)</td></tr>";
      def eventLine: . as $e | "\($e.time | esc) · "
        + (if $e.type == "disabled" then ($L.evDisabled | sub("%s"; ($e.name | esc)) | sub("%s"; (if $e.reason == "quota" then $L.rQuota elif $e.reason == "expired" then $L.rExpired else $L.rManual end)))
           elif $e.type == "restored" then ($L.evRestored | sub("%s"; ($e.name | esc)))
           elif $e.type == "warn" then ($L.evWarn | sub("%s"; ($e.name | esc)))
           elif $e.type == "expiring" then ($L.evExpiring | sub("%s"; ($e.name | esc)))
           elif $e.type == "period" then $L.evPeriod
           elif $e.type == "applied" then $L.evApplied
           elif $e.type == "invalid" then $L.evInvalid
           elif $e.type == "collectFailed" then ($L.evCollectFailed | sub("%s"; ($e.count // "" | tostring)))
           elif $e.type == "collectRecovered" then $L.evCollectRecovered
           elif $e.type == "txFailed" then $L.evTxFailed
           else "\($e.type | esc) \($e.name // "" | esc)" end);
      "<!DOCTYPE html><html lang=\"\($L.lang | sub("_"; "-"))\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex\"><title>\($m.notify.label | esc)</title><style>\($css)</style></head><body>"
      + "<h1>\($m.notify.label | esc)</h1>"
      + "<p class=\"muted\">\($L.generated | esc) \($now | esc) · \($L.period | esc) \($s.period | esc) · \($L.nextReset | esc) \($nextReset | esc)</p>"
      + (if $pending != "" then "<p class=\"warn\">\($pending | esc)</p>" else "" end)
      + (if ($s.members | length) == 0 then "<p>\($L.noMembers | esc)</p>" else
          "<table><thead><tr><th>\($L.name | esc)</th><th>\($L.used | esc)</th><th>\($L.quota | esc)</th><th>%</th><th>\($L.expire | esc)</th><th>\($L.status | esc)</th></tr></thead><tbody>"
          + ([$s.members | to_entries[] | row] | join("")) + "</tbody></table>" end)
      + (if ($others | length) > 0 then "<p class=\"muted\">\($L.others | esc): \($others | map(esc) | join(", "))</p>" else "" end)
      + (if ($s.events | length) > 0 then "<h2>\($L.events | esc)</h2><ul>" + ([$s.events | reverse | .[0:20][] | "<li>\(eventLine)</li>"] | join("")) + "</ul>" else "" end)
      + "</body></html>"'
}

# carpoolRenderMemberPage STATE NORMALIZED NAME TODAY NOW → 成员本人页 HTML；NAME 不是成员时返回 1
carpoolRenderMemberPage() {
    local state=$1 members=$2 name=$3 today=$4 now=$5
    jq -e --arg n "${name}" '.members[$n]' <<<"${state}" >/dev/null 2>&1 || return 1
    local resetDay nextReset
    resetDay=$(jq -r '.resetDay' <<<"${members}")
    nextReset=$(carpoolNextPeriodStart "${today}" "${resetDay}")
    jq -rn --argjson s "${state}" --argjson m "${members}" --argjson L "$(_carpoolPageStrings)" --arg n "${name}" \
        --arg now "${now}" --arg nextReset "${nextReset}" --arg css "${_CARPOOL_PAGE_CSS}" "${_CARPOOL_JQ_DEFS}"'
      def esc: tostring | @html;
      $s.members[$n] as $u
      | (if $u.quotaBytes > 0 then (($u.upBytes + $u.downBytes) * 100 / $u.quotaBytes | floor) else null end) as $p
      | "<!DOCTYPE html><html lang=\"\($L.lang | sub("_"; "-"))\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex\"><title>\($m.notify.label | esc)</title><style>\($css)</style></head><body>"
      + "<h1>\($m.notify.label | esc) · \($n | esc)</h1>"
      + "<p class=\"muted\">\($L.generated | esc) \($now | esc) · \($L.period | esc) \($s.period | esc) · \($L.nextReset | esc) \($nextReset | esc)</p>"
      + "<table><tbody>"
      + "<tr><th>\($L.used | esc)</th><td>\(($u.upBytes + $u.downBytes) | carpoolFmtBytes)"
      + (if $p != null then " (\($p)%)<div class=\"bar\"><i class=\"\(if $p >= 80 then "hot" else "" end)\" style=\"width:\([$p, 100] | min)%\"></i></div>" else "" end) + "</td></tr>"
      + "<tr><th>\($L.quota | esc)</th><td>\(if $u.quotaBytes > 0 then ($u.quotaBytes | carpoolFmtBytes) else $L.unlimited end)</td></tr>"
      + "<tr><th>\($L.expire | esc)</th><td>\(if $u.expire == "" then "-" else $u.expire end)</td></tr>"
      + "<tr><th>\($L.status | esc)</th><td>\(if $u.status == "active" then $L.active else "\($L.disabled) · \(if $u.reason == "quota" then $L.rQuota elif $u.reason == "expired" then $L.rExpired else $L.rManual end)" end | esc)</td></tr>"
      + "</tbody></table></body></html>"'
}
