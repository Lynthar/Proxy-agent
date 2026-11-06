#!/usr/bin/env bash
# ============================================================================
# topo.sh - 路由总览的纯函数：出口地址打码、模型 JSON → HTML。不读文件、不跑别的命令，采集在 install.sh 的 topoCollect
# ============================================================================

# 防止重复加载
[[ -n "${_TOPO_LOADED:-}" ]] && return 0
readonly _TOPO_LOADED=1

# IPv4 留首段、IPv6 留首组、域名只留顶级域：页面会被转发和截图，默认打码后要认不出是哪台机器。主机名同理，topoCollect 只在 --full 时才给
readonly _TOPO_JQ_MASK='
def topoMask:
  if test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$") then (split(".")[0]) + ".x.x.x"
  elif test(":") then (split(":")[0]) + ":x::"
  elif . == "" then ""
  else "*." + (split(".")[-1]) end;
'

# topoMaskHost HOST → 打码后的地址
topoMaskHost() {
    jq -nr --arg h "$1" "${_TOPO_JQ_MASK}"'$h | topoMask'
}

readonly _TOPO_PAGE_CSS=':root{--bg:#f5f6f8;--surface:#fff;--ink:#1b2230;--muted:#5a6575;--line:#d3d9e2;--edge:#8d99aa;--warn:#a86a00;--bad:#c0322a;--off:#8b95a3;--e0:#0f7f6c;--e1:#2563c9;--e2:#8a3fc4;--e3:#b8620c;--e4:#0e7490;--e5:#a21caf}
@media (prefers-color-scheme:dark){:root{color-scheme:dark;--bg:#12161d;--surface:#1a202a;--ink:#e7ebf1;--muted:#95a1b2;--line:#2c3543;--edge:#6c7a8e;--warn:#e0b050;--bad:#f27d73;--off:#6e7886;--e0:#4cc4ad;--e1:#6fa3ff;--e2:#bb95f4;--e3:#e6a356;--e4:#5cc8e0;--e5:#e58ae8}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 system-ui,-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
main{max-width:1180px;margin:0 auto;padding:24px 20px 40px;display:flex;flex-direction:column;gap:14px}h1{font-size:22px;margin:0;font-weight:600}
p{margin:0}.muted{color:var(--muted);font-size:13.5px}.issues{border:1px solid var(--bad);border-radius:8px;padding:10px 14px;color:var(--bad)}.issues ul{margin:4px 0 0;padding-left:20px}
.chart{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:12px 0;overflow-x:auto}.chart svg{display:block;width:100%;min-width:980px;height:auto}
svg text{fill:currentColor;font-size:12.5px}svg .n{font-weight:600;font-size:13px}svg .n-off{font-weight:600;font-size:13px;fill:var(--off);text-decoration:line-through}svg .n-bad{font-weight:600;font-size:13px;fill:var(--bad)}
svg .s{fill:var(--muted);font-size:11.5px}svg .s-warn{fill:var(--warn);font-size:11.5px}svg .s-bad{fill:var(--bad);font-size:11.5px}svg .colh{font-weight:600;font-size:14px}svg .lb{font-size:11.5px}svg .lbs{fill:var(--muted);font-size:12px}
svg .ip{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:15px;font-weight:700}svg .ip-bad{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;fill:var(--bad)}svg .port{fill:var(--muted);font-size:12.5px;font-weight:400}
.node{fill:var(--surface);stroke:var(--line);stroke-width:1}.node-warn{stroke:var(--warn)}.node-off{stroke-dasharray:4 3;fill:none}.node-bad{fill:none;stroke:var(--bad);stroke-dasharray:5 3}
.edge{fill:none;stroke-width:1.5}.e-strong{stroke-width:2}.e-all{stroke:var(--edge);stroke-width:2.2}.e-sub{stroke:var(--warn)}.e-proto{stroke-dasharray:6 4}.brace{fill:none;stroke:var(--edge);stroke-width:1.8;stroke-linecap:round}.brace.e-sub{stroke:var(--warn)}
.lbg{fill:var(--surface);stroke-width:1}.bar-bg{fill:var(--line)}.bar-ok{fill:var(--e0)}.bar-hot{fill:var(--warn)}
.c0{stroke:var(--e0)}.c1{stroke:var(--e1)}.c2{stroke:var(--e2)}.c3{stroke:var(--e3)}.c4{stroke:var(--e4)}.c5{stroke:var(--e5)}.f0{fill:var(--e0)}.f1{fill:var(--e1)}.f2{fill:var(--e2)}.f3{fill:var(--e3)}.f4{fill:var(--e4)}.f5{fill:var(--e5)}'

# topoRenderHtml MODEL → 完整的 HTML。行为一致的账号只画一根线：协议集合相同的合一束连入站，走向相同的合一束连出口，不然人一多线就糊了。
# 模型里的文本一律经 @html，坐标全在这里算完：页面不带脚本，也不加载外部资源
topoRenderHtml() {
    jq -r --arg css "${_TOPO_PAGE_CSS}" '
      def n: (. * 10 | floor) / 10 | tostring;
      def txt($x; $y; $cls; $s): "<text x=\"\($x | n)\" y=\"\($y | n)\" class=\"\($cls)\">\($s | @html)</text>";
      def txtEnd($x; $y; $cls; $s): "<text x=\"\($x | n)\" y=\"\($y | n)\" class=\"\($cls)\" text-anchor=\"end\">\($s | @html)</text>";
      def txtMid($x; $y; $cls; $s): "<text x=\"\($x | n)\" y=\"\($y | n)\" class=\"\($cls)\" text-anchor=\"middle\">\($s | @html)</text>";
      def box($x; $y; $w; $h; $cls): "<rect x=\"\($x | n)\" y=\"\($y | n)\" width=\"\($w | n)\" height=\"\($h | n)\" rx=\"6\" class=\"\($cls)\"/>";
      def runsBy(f): reduce .[] as $r ([]; if length > 0 and (.[-1][-1] | f) == ($r | f) then .[:-1] + [.[-1] + [$r]] else . + [[$r]] end);
      def brace($x; $y1; $y2; $w; $cls):
        (($y1 + $y2) / 2) as $m | (if ($y2 - $y1) / 4 < 9 then ($y2 - $y1) / 4 else 9 end) as $r | ($x + $w / 2) as $q
        | "<path class=\"brace \($cls)\" d=\"M\($x | n) \($y1 | n) Q\($q | n) \($y1 | n) \($q | n) \($y1 + $r | n) L\($q | n) \($m - $r | n) Q\($q | n) \($m | n) \($x + $w | n) \($m | n) Q\($q | n) \($m | n) \($q | n) \($m + $r | n) L\($q | n) \($y2 - $r | n) Q\($q | n) \($y2 | n) \($x | n) \($y2 | n)\"/>";
      def ctrl($x1; $x2): (if ($x2 - $x1) * 0.5 < 30 then 30 else ($x2 - $x1) * 0.5 end);
      def curve($x1; $y1; $x2; $y2; $cls; $arrow):
        ctrl($x1; $x2) as $d
        | "<path d=\"M\($x1 | n) \($y1 | n) C\($x1 + $d | n) \($y1 | n) \($x2 - $d | n) \($y2 | n) \($x2 | n) \($y2 | n)\" class=\"edge \($cls)\"\(if $arrow == "" then "" else " marker-end=\"url(#\($arrow))\"" end)/>";
      def pill($x1; $y1; $x2; $y2; $t; $cls; $s):
        ctrl($x1; $x2) as $d | (1 - $t) as $u
        | ($u * $u * $u * $x1 + 3 * $u * $u * $t * ($x1 + $d) + 3 * $u * $t * $t * ($x2 - $d) + $t * $t * $t * $x2) as $lx
        | ($u * $u * $u * $y1 + 3 * $u * $u * $t * $y1 + 3 * $u * $t * $t * $y2 + $t * $t * $t * $y2) as $ly
        | (($s | explode | map(if . >= 11904 then 2 else 1 end) | add // 0) * 6.3 + 14) as $w
        | "<rect x=\"\($lx - $w / 2 | n)\" y=\"\($ly - 9.5 | n)\" width=\"\($w | n)\" height=\"19\" rx=\"9.5\" class=\"lbg \($cls)\"/>" + txtMid($lx; $ly + 4; "lb"; $s);
      def bar($x; $y; $w; $ratio; $hot):
        "<rect x=\"\($x | n)\" y=\"\($y | n)\" width=\"\($w | n)\" height=\"4\" rx=\"2\" class=\"bar-bg\"/><rect x=\"\($x | n)\" y=\"\($y | n)\" width=\"\($w * (if $ratio > 1 then 1 else $ratio end) | n)\" height=\"4\" rx=\"2\" class=\"\(if $hot then "bar-hot" else "bar-ok" end)\"/>";

      # 默认只有一个去向时，指定到同一出口的账号行为和跟随默认的没有区别，并进那一束
      (if (.flows | length) == 1 then .flows[0].exit else null end) as $onlyFlow
      | .accounts |= map(if $onlyFlow != null and .exit == $onlyFlow then .exit = null else . end)
      | . as $m
      | 16 as $IX | 216 as $IW | 410 as $AX | 226 as $AW | 880 as $EX | 244 as $EW | 1140 as $W | 46 as $top
      | ($m.exits | to_entries | map({key: .value.key, value: .key}) | from_entries) as $exitIdx
      | ($m.accounts | map(select(.status != "disabled"))) as $active
      | ($active | map(select(.protocols == "all"))) as $groupA
      | ($active | map(select(.protocols != "all"))) as $groupB
      | ($groupA | map(select(.exit != null)) | sort_by($exitIdx[.exit])) as $pinA
      | ($groupA | map(select(.exit == null))) as $folA
      | ($groupB | map(select(.exit == null)) | sort_by(.protocols)) as $folB
      | ($groupB | map(select(.exit != null)) | sort_by([$exitIdx[.exit], .protocols])) as $pinB
      | ($m.accounts | map(select(.status == "disabled"))) as $off
      | (($pinA + $folA + $folB + $pinB + $off) | length > 8) as $compact
      | (if $compact then 22 else 46 end) as $h | (if $compact then 28 else 56 end) as $step
      | (($pinA + $folA + $folB + $pinB + $off) | to_entries | map(.value + {y: ($top + .key * $step)})) as $rows
      | (($rows | length) * $step - $step + $h + $top) as $bottom
      | (($pinA + $folA) | length) as $nA
      | (if $nA > 0 then $top else 0 end) as $a1
      | (if $nA > 0 then $top + ($nA - 1) * $step + $h else 0 end) as $a2
      | 46 as $ih | 58 as $istep
      | ($m.inbounds | length) as $nI
      | (($nI - 1) * $istep + $ih) as $ispan
      | (if $nA > 0 and (($a1 + $a2) / 2 - $ispan / 2) > $top then ($a1 + $a2) / 2 - $ispan / 2 else $top end) as $itop
      | ($m.inbounds | to_entries | map(.value + {y: ($itop + .key * $istep)})) as $inbounds
      | ($inbounds | map({key: (.id | tostring), value: .y}) | from_entries) as $iy
      | ($inbounds | map(select(.chain != true))) as $plainIn
      | 72 as $eh
      | (($m.exits | length) - 1) as $gaps
      | (if $gaps > 0 and (($bottom - $top - $eh) / $gaps) > ($eh + 18) then ($bottom - $top - $eh) / $gaps else $eh + 18 end) as $estep
      | ($m.exits | to_entries | map(.value + {y: ($top + .key * $estep), idx: (.key % 6)})) as $exits
      | ($exits | map({key: .key, value: .}) | from_entries) as $E
      | ($exits | map(select(.bad != true))) as $goodExits
      | ([$bottom, ($itop + $ispan), ($top + (($m.exits | length) - 1) * $estep + $eh)] | max + 14) as $H
      | ($m.labels) as $L

      # 入站合成一束连到开了全部协议的账号；只开部分协议的账号单独连
      | (if $nA > 0 and ($plainIn | length) > 0 then
           ($plainIn | map(.y)) as $ys
           | ($ys | min) as $i1 | (($ys | max) + $ih) as $i2 | (($i1 + $i2) / 2) as $midI | (($a1 + $a2) / 2) as $midA
           | ($IX + $IW + 8) as $bxL | ($AX - 8) as $bxR
           | (if ($plainIn | length) > 1 then $bxL + 20 else $IX + $IW end) as $from
           | (if $nA > 1 then $bxR - 20 else $AX end) as $to
           | { lines: ((if ($plainIn | length) > 1 then brace($bxL; $i1; $i2; 20; "") else "" end)
                       + (if $nA > 1 then brace($bxR; $a1; $a2; -20; "") else "" end)
                       + curve($from; $midI; $to; $midA; "e-all"; "")),
               x: (($from + $to) / 2), y: (($midI + $midA) / 2) }
         else {lines: "", x: 0, y: 0} end) as $bundle
      | ([[$rows[] | select(.protocols != "all" and .status != "disabled")] | runsBy(.protocols)[] as $run
          | ($run | length) as $cnt | ($run[0].protocols | length) as $np
          | ($run[0].y) as $y1 | ($run[-1].y + $h) as $y2 | (($y1 + $y2) / 2) as $ym
          | (if $cnt > 1 then $AX - 28 else $AX end) as $tip
          | (if $cnt > 1 then brace($AX - 8; $y1; $y2; -20; "e-sub") else "" end)
            + ([($run[0].protocols | to_entries[]) as $p | select($iy[$p.value | tostring] != null)
                | curve($IX + $IW; $iy[$p.value | tostring] + $ih / 2; $tip; $ym + ($p.key - ($np - 1) / 2) * 5; "e-sub"; "")] | join(""))] | join("")) as $subLines
      | (if $nA > 0 and ($plainIn | length) > 0 then
           ($L.allProtocols | sub("%s"; ($nA | tostring))) as $s
           | ((($s | explode | map(if . >= 11904 then 2 else 1 end) | add // 0) * 6.3 + 16)) as $lw
           | "<rect x=\"\($bundle.x - $lw / 2 | n)\" y=\"\($bundle.y - 10 | n)\" width=\"\($lw | n)\" height=\"20\" rx=\"10\" class=\"lbg\" stroke=\"currentColor\" stroke-opacity=\"0.3\"/>" + txtMid($bundle.x; $bundle.y + 4; "lb"; $s)
         else "" end) as $bundleLabel

      # 相邻且指定同一出口的账号合一束，一根线；其余账号也合一束，按条件连到出口
      | ([[$rows[] | select(.status != "disabled")] | runsBy(.exit)[] | select(.[0].exit != null) | . as $run
          | ($run | length) as $cnt | $E[$run[0].exit] as $x
          | select($x != null)
          | ($run[0].y) as $y1 | ($run[-1].y + $h) as $y2 | (($y1 + $y2) / 2) as $ym
          | (if $cnt > 1 then $AX + $AW + 28 else $AX + $AW end) as $x1 | ($EX - 1) as $x2 | ($x.y + $eh / 2) as $y2e
          | (if $cnt > 1 then brace($AX + $AW + 8; $y1; $y2; 20; "c\($x.idx)") else "" end)
            + curve($x1; $ym; $x2; $y2e; "c\($x.idx)"; "a\($x.idx)")
            + pill($x1; $ym; $x2; $y2e; 0.5; "c\($x.idx)"; (if $cnt == 1 then $L.pinned else ($L.pinnedN | sub("%s"; ($cnt | tostring))) end))] | join("")) as $pinLines
      | (($folA + $folB) | length) as $nF
      | (if $nF > 0 then
           ($top + (($pinA | length)) * $step) as $f1
           | ($f1 + ($nF - 1) * $step + $h) as $f2
           | (($f1 + $f2) / 2) as $fm
           | ($AX + $AW + 8) as $fx
           | (if $nF > 1 then $fx + 20 else $AX + $AW end) as $from
           | (if $nF > 1 then brace($fx; $f1; $f2; 20; "") else "" end)
             + ([$m.flows[] | . as $fl | $E[$fl.exit] as $x | select($x != null)
                 | curve($from; $fm; $EX - 1; $x.y + $eh / 2; "e-strong c\($x.idx)"; "a\($x.idx)")
                   + pill($from; $fm; $EX - 1; $x.y + $eh / 2; 0.78; "c\($x.idx)"; $fl.when)] | join(""))
             + (if $nF > 1 then txt($fx + 26; $f2 - 2; "lbs"; ($L.followDefault | sub("%s"; ($nF | tostring)))) else "" end)
         else "" end) as $folLines

      # 入站直接决定出口的例外：按协议分流、本机当链式出口或中继时收到的流量
      | ([$m.inboundExits[]? | . as $ie | $E[$ie.exit] as $x | select($x != null and $iy[$ie.inbound | tostring] != null)
          | ($IX + $IW) as $x1 | ($iy[$ie.inbound | tostring] + $ih / 2) as $y1 | ($EX - 1) as $x2 | ($x.y + $eh / 2) as $y2
          | curve($x1; $y1; $x2; $y2; "e-proto c\($x.idx)"; "a\($x.idx)") + pill($x1; $y1; $x2; $y2; 0.8; "c\($x.idx)"; $ie.when)] | join("")) as $protoLines

      | ([$inbounds[] | box($IX; .y; $IW; $ih; "node") + txt($IX + 12; .y + 20; "n"; .name) + txt($IX + 12; .y + 36; "s"; .sub)] | join("")) as $inNodes
      | ([$rows[] | . as $a
          | if $a.status == "disabled" then
              box($AX; $a.y; $AW; $h; "node node-off")
              + (if $compact then txt($AX + 10; $a.y + 15; "n-off"; $a.name) + txtEnd($AX + $AW - 10; $a.y + 15; "s"; $a.short)
                 else txt($AX + 12; $a.y + 19; "n-off"; $a.name) + txt($AX + 12; $a.y + 35; "s"; $a.sub) end)
            else
              box($AX; $a.y; $AW; $h; (if $a.hot == true then "node node-warn" else "node" end))
              + (if $compact then
                   txt($AX + 10; $a.y + 15; "n"; $a.name)
                   + (if $a.ratio != null then
                        txt($AX + 84; $a.y + 15; (if $a.hot == true then "s-warn" else "s" end); $a.short) + bar($AX + 146; $a.y + 8; 68; $a.ratio; ($a.hot == true))
                      else txtEnd($AX + $AW - 10; $a.y + 15; (if $a.warn == true then "s-warn" else "s" end); $a.short) end)
                 else
                   (if $a.sub == "" then txt($AX + 12; $a.y + 27; "n"; $a.name)
                    else txt($AX + 12; $a.y + 19; "n"; $a.name) + txt($AX + 12; $a.y + 35; (if $a.hot == true or $a.warn == true then "s-warn" else "s" end); $a.sub) end)
                   + (if $a.ratio != null then bar($AX + 156; $a.y + 13; 58; $a.ratio; ($a.hot == true)) else "" end)
                 end)
            end] | join("")) as $acctNodes
      | ([$exits[] | . as $x
          | if $x.bad == true then
              box($EX; $x.y; $EW; $eh; "node node-bad") + txt($EX + 14; $x.y + 20; "n-bad"; $x.name) + txt($EX + 14; $x.y + 40; "ip-bad"; $x.host) + txt($EX + 14; $x.y + 60; "s-bad"; $x.note)
            else
              box($EX; $x.y; $EW; $eh; "node")
              + "<rect x=\"\($EX | n)\" y=\"\($x.y + 8 | n)\" width=\"4\" height=\"\($eh - 16 | n)\" rx=\"2\" class=\"f\($x.idx)\"/>"
              + txt($EX + 14; $x.y + 20; "n"; $x.name) + txtEnd($EX + $EW - 12; $x.y + 20; "s"; $x.kind)
              + "<text x=\"\($EX + 14 | n)\" y=\"\($x.y + 44 | n)\" class=\"ip\">\($x.host | @html)<tspan class=\"port\">\(if ($x.port // "") == "" then "" else ":" + ($x.port | tostring | @html) end)</tspan></text>"
              + txt($EX + 14; $x.y + 62; "s"; ($x.note // ""))
            end] | join("")) as $exitNodes
      | ([$goodExits[] | "<marker id=\"a\(.idx)\" viewBox=\"0 0 8 8\" refX=\"7\" refY=\"4\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\"><path d=\"M0 0L8 4L0 8z\" class=\"f\(.idx)\"/></marker>"] | join("")) as $markers

      | "<!DOCTYPE html>\n<html lang=\"\($m.lang | @html)\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><meta name=\"referrer\" content=\"no-referrer\">"
        + "<title>\($L.title | @html)</title><style>\($css)</style></head><body><main>"
        + "<h1>\($L.title | @html)</h1><p class=\"muted\">\([$m.host, $m.cores, $m.generated, $m.maskNote] | map(select(. != "")) | join(" · ") | @html)</p>"
        + (if ($m.issues | length) > 0 then "<div class=\"issues\"><strong>\($L.issuesTitle | @html)</strong><ul>\([$m.issues[] | "<li>\(. | @html)</li>"] | join(""))</ul></div>" else "" end)
        + "<div class=\"chart\" tabindex=\"0\"><svg viewBox=\"0 0 \($W) \($H | n)\" role=\"img\" aria-label=\"\($L.title | @html)\"><defs>\($markers)</defs>"
        + txt($IX; 22; "colh"; $L.colInbound) + txt($AX; 22; "colh"; $L.colAccount) + txt($EX; 22; "colh"; $L.colExit)
        + $bundle.lines + $subLines + $bundleLabel + $protoLines + $pinLines + $folLines
        + $inNodes + $acctNodes + $exitNodes
        + "</svg></div><p class=\"muted\">\($L.footnote | @html)</p></main></body></html>"
    ' <<<"$1"
}

# topoAccounts INBOUNDS STATE PINS LABELS → 账号行。STATE 是拼车 state（没开是 null）：用量只走 carpoolUsage，手算会丢计费口径系数
topoAccounts() {
    jq -cn --argjson in "$1" --argjson state "$2" --argjson pins "$3" --argjson L "$4" "${_CARPOOL_JQ_DEFS}"'
        ($state.members // {}) as $members
        | ($state.billing // "both") as $billing
        | ($in | map(select(.chain != true) | .id)) as $allIds
        | ([$in[] | . as $i | .users[]? | {name: ., id: $i.id}] | group_by(.name) | map({name: .[0].name, ids: (map(.id) | unique)})) as $seen
        | def info($m):
            (($m | carpoolUsage($billing)) as $used
             | ($m.quotaBytes // 0) as $quota
             | {used: ($used | carpoolFmtBytes),
                ratio: (if $quota > 0 then $used / $quota else null end),
                hot: ($quota > 0 and $used / $quota >= 0.8),
                detail: ((if $quota > 0 then "\($used | carpoolFmtBytes) / \($quota | carpoolFmtBytes)" else "\($used | carpoolFmtBytes)" end)
                         + (if ($m.expire // "") != "" then " · " + ($L.expire | sub("%s"; $m.expire)) else "" end))});
        ([$seen[] | . as $s | $members[$s.name] as $m
          | {name: $s.name, status: "active", exit: ($pins[$s.name] // null),
             protocols: (if ($s.ids | length) == ($allIds | length) then "all" else $s.ids end)}
            + (if $m != null then
                 info($m) as $i | {sub: $i.detail, short: $i.used, ratio: $i.ratio, hot: $i.hot}
               elif $state != null then {sub: $L.foreign, short: $L.foreign, ratio: null, warn: true}
               else {sub: "", short: "", ratio: null} end)]) as $active
        | ($active | map(.name)) as $names
        | ([$members | to_entries[] | .key as $n | .value as $m
            | select($m.status == "disabled" and ($names | index($n)) == null)
            | info($m) as $i
            | ({quota: $L.reasonQuota, expired: $L.reasonExpired, manual: $L.reasonManual}[$m.reason // ""] // ($m.reason // "")) as $why
            | {name: $n, status: "disabled", exit: null, protocols: "all", ratio: null,
               sub: ($L.disabled | sub("%s"; $why)), short: ($L.disabled | sub("%s"; $why))}]) as $off
        | $active + $off'
}

# topoFinalize MODEL FULL → 收尾：rawHost 变成页面上显示的 host。默认打码，直连的本机地址也算在内，否则截图照样认得出机器
topoFinalize() {
    jq -c --argjson full "$2" "${_TOPO_JQ_MASK}"'
        .exits |= map(
            if has("rawHost") then
                (.rawHost // "" | tostring) as $h | del(.rawHost) | .host = (if $full then $h else ($h | topoMask) end)
            else . end)' <<<"$1"
}
