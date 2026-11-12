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

# 出口配色：直连固定 e0，其余按出口顺序在 e1–e4 里循环，相邻两个出口在常见色觉缺陷下也分得开（浅色、深色两套各自校验过）。
# 橙色只表示用量过 80%、红色只表示配置没生效，出口不用这两种色
readonly _TOPO_PAGE_CSS=':root{--bg:#f5f6f8;--surface:#fff;--ink:#1b2230;--muted:#5a6575;--line:#d3d9e2;--edge:#8d99aa;--warn:#a86a00;--bad:#c0322a;--off:#8b95a3;--e0:#1baf7a;--e1:#2a78d6;--e2:#008300;--e3:#6250d6;--e4:#e87ba4}
@media (prefers-color-scheme:dark){:root{color-scheme:dark;--bg:#12161d;--surface:#1a202a;--ink:#e7ebf1;--muted:#95a1b2;--line:#2c3543;--edge:#6c7a8e;--warn:#e0b050;--bad:#f27d73;--off:#6e7886;--e0:#199e70;--e1:#3987e5;--e2:#008300;--e3:#9085e9;--e4:#d55181}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 system-ui,-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
main{max-width:1240px;margin:0 auto;padding:24px 20px 40px;display:flex;flex-direction:column;gap:14px}h1{font-size:22px;margin:0;font-weight:600}
p{margin:0}.muted{color:var(--muted);font-size:13.5px}.issues{border:1px solid var(--bad);border-radius:8px;padding:10px 14px;color:var(--bad)}.issues ul{margin:4px 0 0;padding-left:20px}
.chart{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:12px 0;overflow-x:auto}.chart svg{display:block;width:100%;min-width:980px;height:auto}
svg text{fill:currentColor;font-size:12.5px}svg .n{font-weight:600;font-size:13px}svg .n-off{font-weight:600;font-size:13px;fill:var(--off);text-decoration:line-through}svg .n-bad{font-weight:600;font-size:13px;fill:var(--bad)}
svg .s{fill:var(--muted);font-size:11.5px}svg .s-warn{fill:var(--warn);font-size:11.5px}svg .s-bad{fill:var(--bad);font-size:11.5px}svg .colh{font-weight:600;font-size:14px}svg .lb{font-size:11.5px}svg .lbs{fill:var(--muted);font-size:12px}
svg .ip{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:15px;font-weight:700}svg .ip2{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;font-weight:600}svg .ip-bad{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;fill:var(--bad)}
svg .port{fill:var(--muted);font-size:12.5px;font-weight:400}svg .pid{fill:var(--muted);font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}
.node{fill:var(--surface);stroke:var(--line);stroke-width:1}.node-warn{stroke:var(--warn)}.node-off{stroke-dasharray:4 3;fill:none}.node-bad{fill:none;stroke:var(--bad);stroke-dasharray:5 3}
.edge{fill:none;stroke-width:1.5}.e-strong{stroke-width:2}.e-all{stroke:var(--edge);stroke-width:2.2}.e-proto{stroke-dasharray:6 4}.brace{fill:none;stroke:var(--edge);stroke-width:1.8;stroke-linecap:round}
.lbg{fill:var(--surface);stroke-width:1}.badge{fill:var(--surface);stroke:var(--edge);stroke-width:1}.bar-bg{fill:var(--line)}.bar-ok{fill:var(--edge)}.bar-hot{fill:var(--warn)}
.legend{display:flex;flex-wrap:wrap;gap:6px 20px;margin:0;padding:0;list-style:none;color:var(--muted);font-size:13px}.legend li{display:flex;align-items:center;gap:7px}.legend svg{flex:none;overflow:visible}
.c0{stroke:var(--e0)}.c1{stroke:var(--e1)}.c2{stroke:var(--e2)}.c3{stroke:var(--e3)}.c4{stroke:var(--e4)}.f0{fill:var(--e0)}.f1{fill:var(--e1)}.f2{fill:var(--e2)}.f3{fill:var(--e3)}.f4{fill:var(--e4)}'

# topoRenderHtml MODEL → 完整的 HTML。行为一致的账号只画一根线：开了全部协议的合一束连入站，走向相同的合一束连出口，不然人一多线就糊了。
# 模型里的文本一律经 @html，坐标全在这里算完：页面不带脚本，也不加载外部资源
topoRenderHtml() {
    jq -r --arg css "${_TOPO_PAGE_CSS}" '
      def n: (. * 10 | floor) / 10 | tostring;
      def str: (. // "") | tostring;
      def units: str | explode | map(if . >= 11904 then 2 else 1 end) | add // 0;
      def clip($max):
        if units <= $max then str
        else (str | explode | reduce .[] as $c ({out: [], u: 0, done: false};
                if .done then . else (if $c >= 11904 then 2 else 1 end) as $w
                  | if .u + $w > $max - 1 then .done = true else .out += [$c] | .u += $w end end)
              | .out | implode) + "…" end;
      # 放不下的截断，整串放进 <title>，鼠标停上去看得到
      def fit($s; $max): ($s | str) as $t | if ($t | units) > $max then "\($t | clip($max) | @html)<title>\($t | @html)</title>" else ($t | @html) end;
      def txt($x; $y; $cls; $s; $max): "<text x=\"\($x | n)\" y=\"\($y | n)\" class=\"\($cls)\">\(fit($s; $max))</text>";
      def txtEnd($x; $y; $cls; $s; $max): "<text x=\"\($x | n)\" y=\"\($y | n)\" class=\"\($cls)\" text-anchor=\"end\">\(fit($s; $max))</text>";
      def txtMid($x; $y; $cls; $s; $max): "<text x=\"\($x | n)\" y=\"\($y | n)\" class=\"\($cls)\" text-anchor=\"middle\">\(fit($s; $max))</text>";
      def box($x; $y; $w; $h; $cls): "<rect x=\"\($x | n)\" y=\"\($y | n)\" width=\"\($w | n)\" height=\"\($h | n)\" rx=\"6\" class=\"\($cls)\"/>";
      def runsBy(f): reduce .[] as $r ([]; if length > 0 and (.[-1][-1] | f) == ($r | f) then .[:-1] + [.[-1] + [$r]] else . + [[$r]] end);
      def brace($x; $y1; $y2; $w; $cls):
        (($y1 + $y2) / 2) as $m | (if ($y2 - $y1) / 4 < 9 then ($y2 - $y1) / 4 else 9 end) as $r | ($x + $w / 2) as $q
        | "<path class=\"brace \($cls)\" d=\"M\($x | n) \($y1 | n) Q\($q | n) \($y1 | n) \($q | n) \($y1 + $r | n) L\($q | n) \($m - $r | n) Q\($q | n) \($m | n) \($x + $w | n) \($m | n) Q\($q | n) \($m | n) \($q | n) \($m + $r | n) L\($q | n) \($y2 - $r | n) Q\($q | n) \($y2 | n) \($x | n) \($y2 | n)\"/>";
      def curve($x1; $y1; $x2; $y2; $cls; $arrow):
        (if ($x2 - $x1) * 0.5 < 30 then 30 else ($x2 - $x1) * 0.5 end) as $d
        | "<path d=\"M\($x1 | n) \($y1 | n) C\($x1 + $d | n) \($y1 | n) \($x2 - $d | n) \($y2 | n) \($x2 | n) \($y2 | n)\" class=\"edge \($cls)\"\(if $arrow == "" then "" else " marker-end=\"url(#\($arrow))\"" end)/>";
      # 先在起点附近拐到目标高度再水平走：入站那束线不能斜穿账号左侧的协议编号
      def bend($x1; $y1; $x2; $y2; $cls):
        (if ($x2 - $x1) / 4 < 30 then ($x2 - $x1) / 4 else 30 end) as $k
        | "<path d=\"M\($x1 | n) \($y1 | n) C\($x1 + $k | n) \($y1 | n) \($x1 + $k | n) \($y2 | n) \($x1 + 2 * $k | n) \($y2 | n) L\($x2 | n) \($y2 | n)\" class=\"edge \($cls)\"/>";
      # 线上的标签：$cx 是中心；pillW 按截断后的字数估宽，左对齐、右对齐的调用方据此换算中心
      def pillW($s; $max): ($s | if units > $max then clip($max) else . end | units) * 6.3 + 14;
      def pill($cx; $cy; $cls; $s; $max):
        pillW($s; $max) as $w
        | "<rect x=\"\($cx - $w / 2 | n)\" y=\"\($cy - 9.5 | n)\" width=\"\($w | n)\" height=\"19\" rx=\"9.5\" class=\"\($cls)\"/>" + txtMid($cx; $cy + 4; "lb"; $s; $max);
      def bar($x; $y; $w; $ratio; $hot):
        "<rect x=\"\($x | n)\" y=\"\($y | n)\" width=\"\($w | n)\" height=\"4\" rx=\"2\" class=\"bar-bg\"/><rect x=\"\($x | n)\" y=\"\($y | n)\" width=\"\($w * (if $ratio > 1 then 1 else $ratio end) | n)\" height=\"4\" rx=\"2\" class=\"\(if $hot then "bar-hot" else "bar-ok" end)\"/>";

      # 默认只有一个去向时，指定到同一出口的账号行为和跟随默认的没有区别，并进那一束；标签另外写明哪些人是指定的
      (if (.flows | length) == 1 then .flows[0].exit else null end) as $onlyFlow
      | .accounts |= map(if $onlyFlow != null and .exit == $onlyFlow then .exit = null | .mergedPin = true else . end)
      | . as $m
      | 16 as $IX | 216 as $IW | 410 as $AX | 226 as $AW | 960 as $EX | 244 as $EW | 1220 as $W | 46 as $top
      | ($m.labels) as $L
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
      | (if ($rows | length) > 0 then ($rows | length) * $step - $step + $h + $top else $top + $h end) as $bottom
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

      # 去出口的线：账号指定的一束一根（标签在起点），跟随默认的按条件各一根、入站直接决定出口的各一根（标签在终点）
      | (($folA + $folB) | length) as $nF
      | ($top + ($pinA | length) * $step) as $f1
      | ($f1 + ($nF - 1) * $step + $h) as $f2
      | (($f1 + $f2) / 2) as $fm
      | (if $nF > 1 then $AX + $AW + 28 else $AX + $AW end) as $fFrom
      | ([[$rows[] | select(.status != "disabled")] | runsBy(.exit)[] | select(.[0].exit != null) | . as $run
          | ($run | length) as $cnt | ($run[0].y) as $y1 | ($run[-1].y + $h) as $y2
          | {exit: $run[0].exit, x1: (if $cnt > 1 then $AX + $AW + 28 else $AX + $AW end), y1: (($y1 + $y2) / 2), top: $y1, bottom: $y2, cnt: $cnt, kind: "pin",
             label: (if $cnt == 1 then $L.pinned else ($L.pinnedN | sub("%s"; ($cnt | tostring))) end)}]
         + (if $nF > 0 then [$m.flows[] | {exit, x1: $fFrom, y1: $fm, kind: "flow", label: .when}] else [] end)
         + [$m.inboundExits[]? | select($iy[.inbound | tostring] != null) | {exit, x1: ($IX + $IW), y1: ($iy[.inbound | tostring] + $ih / 2), kind: "proto", label: .when}]
         | map(select($exitIdx[.exit] != null))) as $edges0

      # 每个出口按进来的线数定高，线的终点在出口左边缘上错开 21 像素，终点的标签就不会叠在一起
      | ($m.exits | reduce .[] as $x ({list: [], k: 0};
          if $x.key == "direct" then .list += [$x + {idx: 0}] else .list += [$x + {idx: (1 + (.k % 4))}] | .k += 1 end) | .list) as $exits1
      | ($exits1 | map(. as $x | ([$edges0[] | select(.exit == $x.key)] | length) as $cnt
          | . + {nIn: $cnt, eh: ([(if (.host2 // "") != "" and (.note // "") != "" then 90 else 72 end), 21 * $cnt + 10] | max)})) as $exits2
      | (($exits2 | map(.eh) | add // 0)) as $sumH
      | (($exits2 | length) - 1) as $gaps
      | (if $gaps > 0 and (($bottom - $top - $sumH) / $gaps) > 18 then ($bottom - $top - $sumH) / $gaps else 18 end) as $egap
      | ($exits2 | reduce .[] as $x ({list: [], y: $top}; .list += [$x + {y: .y}] | .y += $x.eh + $egap) | .list) as $exits
      | ($exits | map(select(.bad != true))) as $goodExits
      | ([$exits[] | . as $x | [$edges0[] | select(.exit == $x.key)] | sort_by(.y1) | to_entries[]
          | .value + {y2: ($x.y + ($x.eh - 21 * $x.nIn) / 2 + 10.5 + 21 * .key), idx: $x.idx}]) as $edges
      | ([$bottom, ($itop + $ispan), ($exits | map(.y + .eh) | max // $top)] | max + 14) as $H

      # 开了全部协议的账号合成一束连到入站；只开部分协议的不连线，行左侧写协议编号
      | (if $nA > 0 and ($plainIn | length) > 0 then
           ($plainIn | map(.y)) as $ys
           | ($ys | min) as $i1 | (($ys | max) + $ih) as $i2 | (($i1 + $i2) / 2) as $midI | (($a1 + $a2) / 2) as $midA
           | ($IX + $IW + 8) as $bxL | ($AX - 8) as $bxR
           | (if ($plainIn | length) > 1 then $bxL + 20 else $IX + $IW end) as $from
           | (if $nA > 1 then $bxR - 20 else $AX end) as $to
           | { lines: ((if ($plainIn | length) > 1 then brace($bxL; $i1; $i2; 20; "") else "" end)
                       + (if $nA > 1 then brace($bxR; $a1; $a2; -20; "") else "" end)
                       + bend($from; $midI; $to; $midA; "e-all")),
               x: (pillW($L.allProtocols | sub("%s"; ($nA | tostring)); 30) as $w
                   | (($from + (if ($to - $from) / 4 < 30 then ($to - $from) / 2 else 60 end) + $to) / 2) as $mid
                   | if $mid + $w / 2 > $to - 4 then $to - 4 - $w / 2 else $mid end),
               y: $midA }
         else {lines: "", x: 0, y: 0} end) as $bundle
      | (if $nA > 0 and ($plainIn | length) > 0 then
           pill($bundle.x; $bundle.y; "lbg"; ($L.allProtocols | sub("%s"; ($nA | tostring))); 30) | sub("class=\"lbg\""; "class=\"lbg\" stroke=\"currentColor\" stroke-opacity=\"0.3\"")
         else "" end) as $bundleLabel
      | ([[$rows[] | select(.protocols != "all" and .status != "disabled")] | runsBy(.protocols)[] as $run
          | ($run | length) as $cnt | ($run[0].y) as $y1 | ($run[-1].y + $h) as $y2 | (($y1 + $y2) / 2) as $ym
          | (($L.onlyProtocols // "%s") | sub("%s"; ($run[0].protocols | map(tostring) | join(" · ")))) as $s
          | (if $cnt > 1 then $AX - 30 else $AX - 6 end) as $right
          | (if $cnt > 1 then brace($AX - 8; $y1; $y2; -20; "") else "" end) + pill($right - pillW($s; 18) / 2; $ym; "badge"; $s; 18)] | join("")) as $onlyBadges

      | ([$edges[] | select(.kind == "pin" and .cnt > 1) | brace($AX + $AW + 8; .top; .bottom; 20; "c\(.idx)")] | join("")) as $pinBraces
      | (if $nF > 1 then brace($AX + $AW + 8; $f1; $f2; 20; "") else "" end) as $folBrace
      | ([$edges[] | curve(.x1; .y1; $EX - 1; .y2; (if .kind == "flow" then "e-strong " elif .kind == "proto" then "e-proto " else "" end) + "c\(.idx)"; "a\(.idx)")] | join("")) as $edgeLines
      | ([$edges[] | if .kind == "pin" then pill(.x1 + 4 + pillW(.label; 16) / 2; .y1; "lbg c\(.idx)"; .label; 16)
                     else pill($EX - 14 - pillW(.label; 24) / 2; .y2; "lbg c\(.idx)"; .label; 24) end] | join("")) as $edgeLabels
      | ([$rows[] | select(.mergedPin == true and .status != "disabled")]) as $merged
      | (if $nF > 1 or ($merged | length) > 0 then
           ($merged | length) as $nM
           | (if $nM == 0 then ($L.followDefault | sub("%s"; ($nF | tostring)))
              else (if $nM <= 3 then ($merged | map(.name) | join($L.listSep // ", ")) else (($L.people // "%s") | sub("%s"; ($nM | tostring))) end) as $who
                   | (($L.followDefaultPinned // "%s, %s") | sub("%s"; (($nF - $nM) | tostring)) | sub("%s"; $who)) end) as $s
           | txt($AX + $AW + (if $nF > 1 then 26 else 6 end); $f2 + (if $nF > 1 then -2 else 13 end); "lbs"; $s; 44)
         else "" end) as $folLabel

      | ([$inbounds[] | box($IX; .y; $IW; $ih; "node") + txt($IX + 12; .y + 20; "n"; .name; 24) + txt($IX + 12; .y + 36; "s"; .sub; 32)
          + (if .chain == true then "" else txtEnd($IX + $IW - 10; .y + 20; "pid"; (.id | tostring); 4) end)] | join("")) as $inNodes
      | ([$rows[] | . as $a
          | if $a.status == "disabled" then
              box($AX; $a.y; $AW; $h; "node node-off")
              + (if $compact then txt($AX + 10; $a.y + 15; "n-off"; $a.name; 12) + txtEnd($AX + $AW - 10; $a.y + 15; "s"; $a.short; 14)
                 else txt($AX + 12; $a.y + 19; "n-off"; $a.name; 27) + txt($AX + 12; $a.y + 35; "s"; $a.sub; 32) end)
            else
              box($AX; $a.y; $AW; $h; (if $a.hot == true then "node node-warn" else "node" end))
              + (if $compact then
                   (if $a.ratio != null then
                      txt($AX + 10; $a.y + 15; "n"; $a.name; 9)
                      + txt($AX + 84; $a.y + 15; (if $a.hot == true then "s-warn" else "s" end); $a.short; 9) + bar($AX + 146; $a.y + 8; 68; $a.ratio; ($a.hot == true))
                    else txt($AX + 10; $a.y + 15; "n"; $a.name; 14) + txtEnd($AX + $AW - 10; $a.y + 15; (if $a.warn == true then "s-warn" else "s" end); $a.short; 12) end)
                 else
                   (if $a.sub == "" then txt($AX + 12; $a.y + 27; "n"; $a.name; (if $a.ratio != null then 18 else 27 end))
                    else txt($AX + 12; $a.y + 19; "n"; $a.name; (if $a.ratio != null then 18 else 27 end))
                         + txt($AX + 12; $a.y + 35; (if $a.hot == true or $a.warn == true then "s-warn" else "s" end); $a.sub; 32) end)
                   + (if $a.ratio != null then bar($AX + 156; $a.y + 13; 58; $a.ratio; ($a.hot == true)) else "" end)
                 end)
            end] | join("")) as $acctNodes
      | ([$exits[] | . as $x | (($x.kind // "") | units) as $ku | ((($EW - 34 - $ku * 6.2) / 7.4) | floor) as $nameMax
          | if $x.bad == true then
              box($EX; $x.y; $EW; $x.eh; "node node-bad") + txt($EX + 14; $x.y + 20; "n-bad"; $x.name; 28) + txt($EX + 14; $x.y + 40; "ip-bad"; $x.host; 26) + txt($EX + 14; $x.y + 60; "s-bad"; ($x.note // ""); 36)
            else
              box($EX; $x.y; $EW; $x.eh; "node")
              + "<rect x=\"\($EX | n)\" y=\"\($x.y + 8 | n)\" width=\"4\" height=\"\($x.eh - 16 | n)\" rx=\"2\" class=\"f\($x.idx)\"/>"
              + txt($EX + 14; $x.y + 20; "n"; $x.name; $nameMax) + txtEnd($EX + $EW - 12; $x.y + 20; "s"; ($x.kind // ""); 14)
              + "<text x=\"\($EX + 14 | n)\" y=\"\($x.y + 44 | n)\" class=\"ip\">\($x.host | @html)<tspan class=\"port\">\(if ($x.port // "") == "" then "" else ":" + ($x.port | tostring | @html) end)</tspan></text>"
              + (if ($x.host2 // "") != "" then txt($EX + 14; $x.y + 62; "ip2"; $x.host2; 30) + txt($EX + 14; $x.y + 80; "s"; ($x.note // ""); 36)
                 else txt($EX + 14; $x.y + 62; "s"; ($x.note // ""); 36) end)
            end] | join("")) as $exitNodes
      | ([$goodExits[] | .idx] | unique | map("<marker id=\"a\(.)\" viewBox=\"0 0 8 8\" refX=\"7\" refY=\"4\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\"><path d=\"M0 0L8 4L0 8z\" class=\"f\(.)\"/></marker>") | join("")) as $markers

      # 图例只列这张图上出现的画法
      | def sw($body): "<svg width=\"34\" height=\"14\" viewBox=\"0 0 34 14\" aria-hidden=\"true\">\($body)</svg>";
        def item($on; $body; $s): if $on and ($s // "") != "" then "<li>\(sw($body))\($s | @html)</li>" else "" end;
        (item($bundle.lines != ""; "<path d=\"M2 7H32\" class=\"edge e-all\"/>"; $L.legendBundle)
         + item($onlyBadges != ""; "<rect x=\"2\" y=\"1.5\" width=\"30\" height=\"11\" rx=\"5.5\" class=\"badge\"/>"; $L.legendOnly)
         + item(([$edges[] | select(.kind != "proto")] | length) > 0; "<path d=\"M2 7H26\" class=\"edge e-strong c1\"/><path d=\"M26 3L33 7L26 11z\" class=\"f1\"/>"; $L.legendRoute)
         + item(([$edges[] | select(.kind == "proto")] | length) > 0; "<path d=\"M2 7H26\" class=\"edge e-proto c1\"/><path d=\"M26 3L33 7L26 11z\" class=\"f1\"/>"; $L.legendInbound)
         + item(([$rows[] | select(.hot == true)] | length) > 0; "<rect x=\"2\" y=\"1.5\" width=\"30\" height=\"11\" rx=\"3\" class=\"node node-warn\"/>"; $L.legendHot)
         + item(([$exits[] | select(.bad == true)] | length) > 0; "<rect x=\"2\" y=\"1.5\" width=\"30\" height=\"11\" rx=\"3\" class=\"node node-bad\"/>"; $L.legendBad)
         + item(($off | length) > 0; "<rect x=\"2\" y=\"1.5\" width=\"30\" height=\"11\" rx=\"3\" class=\"node node-off\"/>"; $L.legendOff)) as $legend

      | "<!DOCTYPE html>\n<html lang=\"\($m.lang | @html)\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><meta name=\"referrer\" content=\"no-referrer\">"
        + "<title>\($L.title | @html)</title><style>\($css)</style></head><body><main>"
        + "<h1>\($L.title | @html)</h1><p class=\"muted\">\([$m.host, $m.cores, $m.generated, $m.maskNote] | map(select(. != "")) | join(" · ") | @html)</p>"
        + (if ($m.issues | length) > 0 then "<div class=\"issues\"><strong>\($L.issuesTitle | @html)</strong><ul>\([$m.issues[] | "<li>\(. | @html)</li>"] | join(""))</ul></div>" else "" end)
        + "<div class=\"chart\" tabindex=\"0\"><svg viewBox=\"0 0 \($W) \($H | n)\" role=\"img\" aria-label=\"\($L.title | @html)\"><defs>\($markers)</defs>"
        + txt($IX; 22; "colh"; $L.colInbound; 30) + txt($AX; 22; "colh"; $L.colAccount; 30) + txt($EX; 22; "colh"; $L.colExit; 30)
        + $bundle.lines + $pinBraces + $folBrace + $edgeLines + $onlyBadges + $bundleLabel + $edgeLabels + $folLabel
        + $inNodes + $acctNodes + $exitNodes
        + "</svg></div>"
        + (if $legend == "" then "" else "<ul class=\"legend\">\($legend)</ul>" end)
        + "<p class=\"muted\">\($L.footnote | @html)</p></main></body></html>"
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

# topoFinalize MODEL FULL → 收尾：rawHost / rawHost2 变成页面上显示的 host / host2，rawName（外部节点名，取自导入链接的备注，
# 常带服务器名）变成 name。默认打码，直连的本机地址也算在内，否则截图照样认得出机器；问题列表里提到的链路名跟着换
topoFinalize() {
    jq -c --argjson full "$2" "${_TOPO_JQ_MASK}"'
        def host($k): if has("raw" + $k) then (.["raw" + $k] // "" | tostring) as $h | del(.["raw" + $k]) | .[$k | ascii_downcase] = (if $full then $h else ($h | topoMask) end) else . end;
        ((.labels.externalMasked // "%s") | tostring) as $tmpl
        | (reduce .exits[] as $x ({out: [], k: 0, pairs: []};
             if ($x | has("rawName")) then
               (.k + 1) as $k | ($x.rawName // "" | tostring) as $raw | ($tmpl | sub("%s"; ($k | tostring))) as $masked
               | .k = $k
               | .out += [$x | del(.rawName) | .name = (if $full and $raw != "" then $raw else $masked end)]
               | .pairs += (if $full or ($raw | test("^[A-Za-z0-9_]+$") | not) then [] else [{raw: $raw, masked: $masked}] end)
             else .out += [$x] end)) as $r
        | .exits = ($r.out | map(host("Host") | host("Host2")))
        | .issues = [(.issues // [])[] | . as $s | reduce $r.pairs[] as $p ($s; gsub("(?<![A-Za-z0-9_])" + $p.raw + "(?![A-Za-z0-9_])"; $p.masked))]' <<<"$1"
}
