# Proxy-agent 开发者技术指南

本文档面向希望对 Proxy-agent 脚本进行定制开发的开发者。

---

## 目录

1. [项目概述](#1-项目概述)
2. [目录结构](#2-目录结构)
3. [模块系统](#3-模块系统)
4. [协议注册系统](#4-协议注册系统)
5. [i18n 国际化系统](#5-i18n-国际化系统)
6. [配置文件系统](#6-配置文件系统)
7. [服务管理系统](#7-服务管理系统)
8. [链式代理系统](#8-链式代理系统)
9. [输入校验与原子写入](#9-输入校验与原子写入)
10. [开发指南](#10-开发指南)
11. [最佳实践](#11-最佳实践)
12. [诊断与计划模式](#12-诊断与计划模式)

---

## 1. 项目概述

### 1.1 技术栈

- **语言**：Bash 4+
- **依赖**：`jq` · `curl` · `wget` · `openssl`
- **支持核心**：Xray-core · sing-box（最低 1.11，由 `lib/constants.sh::SINGBOX_MIN_VERSION` 锁定，`installSingBox` 安装后会校验，低版本拒绝继续）
- **支持系统**：Debian / Ubuntu · CentOS / RHEL · Alpine Linux

### 1.2 架构原则

| 原则 | 说明 |
|------|------|
| 模块化分层 | install.sh 主流程 + `lib/` 共享工具层 |
| 双核心抽象 | Xray 和 sing-box 通过 `coreKind` 变量分支处理 |
| 协议 ID 不可变 | 每个协议有唯一整数 ID，持久化字段内也使用，不可变更 |
| 原子写入 | JSON 通过 mktemp + 校验 + rename 写入，失败保留旧文件 |
| 输入即校验 | UUID / 域名 / 端口 / 路径在用户输入点立即正则校验 |
| i18n 优先 | 所有用户可见文本通过 `t KEY` 调用 |
| 不使用 `set -e` | 显式 `||` 检查错误；`set -o pipefail` 已启用 |

### 1.3 脚本入口

用户执行 `pasly` 或 `bash /etc/Proxy-agent/install.sh [args...]`，三段式：

```
[ 加载期 ] trap → source lib/*.sh → _load_version
            → initVar → checkSystem → checkCPUVendor
            → readInstallType → readInstallProtocolType → readConfigHostPathUUID
            → readCustomPort → readSingBoxConfig
[ 分发期 ] case "${1:-}" in
              doctor)               doctor; exit $?               ;;  # 跳过菜单
              --dry-run | -n)       export DRY_RUN=1; shift       ;;  # 仍进菜单
            esac
[ 菜单期 ] checkForUpdates → cronFunction → menu
```

加载期所有探测函数都在脚本顶层（不在某个函数内）执行——任何后续函数都能直接读 `release` / `coreKind` / `currentInstallProtocolType` 等全局变量。分发期的 `doctor` 子命令意图绕开 cron 与更新检查，让 `pasly doctor` 在脚本化场景（cron 自检 / CI）下尽量轻；`--dry-run` / `DRY_RUN=1` 则进入只读计划模式（详见 §12）。

---

## 2. 目录结构

### 2.1 源码目录

```
Proxy-agent/
├── install.sh                  # 主脚本（~17.2k 行，~261 函数）
├── VERSION                     # 版本号文件
│
├── lib/                        # 共享工具模块（55 函数，6 个文件）
│   ├── i18n.sh                 # 国际化入口
│   ├── constants.sh            # 常量（协议 ID、路径、服务单元名）
│   ├── utils.sh                # 通用工具
│   ├── json-utils.sh           # JSON 读取与原子写入
│   ├── system-detect.sh        # 系统 / CPU / IP 探测
│   └── protocol-registry.sh    # 协议元数据查询
│
├── shell/lang/                 # 语言文件（双语对齐）
│   ├── zh_CN.sh
│   ├── en_US.sh
│   └── loader.sh               # 兼容占位 stub（仅供旧版 install.sh 升级时下载用，新代码不 source）
│
├── docs/                       # 使用与开发文档（本文件所在）
├── tests/
│   ├── test_modules.sh         # 单元测试（69 用例）
│   └── test_integration.sh     # 集成测试（32 用例，mock VPS 环境）
└── .github/workflows/
    ├── ci.yml                  # shellcheck + bash -n + 双语对齐 + 测试
    └── create_release.yml      # 版本发布（含 SHA256 资产生成）
```

### 2.2 运行时目录

```
/etc/Proxy-agent/
├── install.sh                  # 主脚本（aliasInstall 时从源码目录拷入）
├── VERSION                     # 当前版本号
├── lang_pref                   # 语言偏好
├── backup/                     # 版本备份（脚本 + 配置快照，最多保留 5 份）
│   └── v<ver>_<ts>/
│       ├── install.sh
│       ├── VERSION
│       ├── lib/
│       ├── shell/lang/
│       ├── backup_info.json
│       └── config/             # 配置快照（xray/ + sing-box/ + tls/ + lang_pref）
│
├── xray/
│   ├── xray                    # 二进制
│   └── conf/
│       ├── 00_log.json
│       ├── 02_VLESS_TCP_inbounds.json
│       └── ...                 # Xray 按 -confdir 自动合并所有 .json
│
├── sing-box/
│   ├── sing-box                # 二进制
│   └── conf/
│       ├── config/             # 片段（sing-box merge 的输入）
│       │   ├── 00_log.json
│       │   └── ...
│       ├── config.json         # 合并后的运行时配置
│       ├── chain_exit_info.json        # 链式代理状态（见 §8）
│       ├── chain_relay_info.json
│       ├── chain_entry_info.json
│       ├── chain_multi_info.json
│       └── external_node_info.json
│
├── tls/                        # acme.sh 证书目录
├── subscribe/                  # 订阅文件
└── lib/ · shell/lang/          # 从源码同步来的模块镜像
```

---

## 3. 模块系统

### 3.1 模块加载顺序

install.sh 启动期按下列顺序 `source` 模块（顶部的 `for _module in i18n constants utils json-utils system-detect protocol-registry; do ...` 循环）：

```
i18n → constants → utils → json-utils → system-detect → protocol-registry
```

依赖关系：

- `i18n` 无依赖（最先加载，其余模块可调 `t`）
- `constants` 无依赖（只有 `readonly` 定义）
- `utils` 无依赖（echoContent 是 lib 内通用）
- `json-utils` 依赖 `utils`（echoContent 打错误）
- `system-detect` 依赖 `utils`、`i18n`
- `protocol-registry` 依赖 `constants`

每个模块头部通过 `[[ -n "${_<NAME>_LOADED:-}" ]] && return 0` 防止重复加载。

### 3.2 模块职责

| 模块 | 职责 | 主要函数 |
|------|------|---------|
| `i18n.sh` | 国际化 | `t`（翻译查询，支持 `printf` 占位符） |
| `constants.sh` | 常量定义 | `PROTOCOL_*` ID、`PROXY_AGENT_DIR`、`XRAY_CONFIG_DIR`、服务单元路径等 |
| `utils.sh` | 通用工具 | `echoContent` · `randomNum` · `randomPort` · `timestamp` · `isValidPort` · `isValidUUID` · `trim` · `stripAnsi` · `base64Encode/Decode` · `versionGreaterThan` · `versionGreaterOrEqual` · `isDryRun` · `planAction` |
| `json-utils.sh` | JSON 读写 | `jsonValidateFile` · `jsonGetValue` · `jsonGetArray` · `jsonGetArrayLength` · `jsonArrayAppend` · `jsonWriteFile` · `jsonModifyFile` · 13 个协议专用读取器（见 §4.4） |
| `system-detect.sh` | 系统探测 | `checkSystem` · `checkCPUVendor` · `checkRoot` · `checkCentosSELinux` · `checkWgetShowProgress` · `getPublicIP` · `getSystemMemoryMB` · `getCPUCores` · `commandExists` · `getOSInfo` |
| `protocol-registry.sh` | 协议元数据 | `getProtocolConfigFileName` · `parseProtocolIdFromFileName` · `getProtocolDisplayName` · `getProtocolShortName` · `getProtocolInboundTag` · `protocolRequiresTLS` · `protocolUsesReality/UsesUDP/SupportsCDN` · `getProtocolTransport` · `scanInstalledProtocols` · `getProtocolConfigPath` |

> **服务控制与配置读取放在 install.sh 主脚本内**：`handleXray` / `handleSingBox` / `handleNginx` / `singBoxMergeConfig` / `readInstallType` / `readCustomPort` 等直接在 install.sh 定义。这是有意的——它们与安装流和菜单的上下文耦合度高，不宜抽到独立库。

### 3.3 utils.sh 常用函数

```bash
# 彩色输出（install.sh 1700+ 处调用）
echoContent red "错误信息"
echoContent green "成功信息"
echoContent yellow "警告信息"
echoContent skyBlue "标题信息"

# 随机数 / 端口
port=$(randomNum 10000 30000)
port=$(randomPort)      # 等价 randomNum 10000 30000

# 字符串
trimmed=$(trim "  hello  ")
clean=$(stripAnsi "$coloredText")
b64=$(base64Encode "hello")
raw=$(base64Decode "${b64}")

# 校验谓词
isValidPort 443         # 返回 0 表示合法
isValidUUID "${id}"

# 版本比较
versionGreaterThan "1.2.3" "1.2.0"     # 0 = v1 > v2
versionGreaterOrEqual "1.11" "1.11"    # 0 = v1 >= v2（用于 SINGBOX_MIN_VERSION 校验）

# 时间戳
ts=$(timestamp)         # date +%s

# Dry-run / 计划模式（详见 §12）
if isDryRun; then
    # DRY_RUN=1 已设置
    ...
fi
# planAction 是"短路 + 计划输出"的语法糖：dry-run 时打印 plan 行并返回 0，
# 调用方须立即 return；非 dry-run 时返回 1，调用方继续真实逻辑
if planAction "$(t MSG_PLAN_UNINSTALL)"; then return 0; fi
```

### 3.4 install.sh 内的用户输入 helper

以下 helper 定义在 `install.sh` 自身，而不是 lib/：

```bash
# 端口（支持 RANDOM 触发随机、数字默认值、空默认拒绝）
readValidPort "端口: " port              # 必输
readValidPort "端口: " port 443          # 回车默认 443
readValidPort "端口: " port "RANDOM" 10000 30000   # 回车随机

# 域名
readValidDomain "域名: " domain
readValidDomain "域名: " domain "${currentHost}"   # 回车沿用

# 相关 install.sh 内的独立校验（不在 lib/ 中）
isValidDomain "example.com"              # 兼 RFC 格式 + 注入字符过滤
isValidRedirectUrl "https://..."
verifyCertKeyMatch "<crt>" "<key>"
verifyCertExpiry "<crt>"
verifySHA256 "<file>" "<hash>"
verifyInstallSHA256 "<file>" "<tag>"     # 自更新时调
```

---

## 4. 协议注册系统

### 4.1 协议 ID 定义

协议 ID 是**不可变**的整数常量，在 `constants.sh` 定义。这些值被持久化到 `currentInstallProtocolType=",0,1,7,"` 等标记字符串中，**任何修改都会让旧机器识别不出已装协议**。

```bash
readonly PROTOCOL_VLESS_TCP_VISION=0
readonly PROTOCOL_VLESS_WS=1
readonly PROTOCOL_TROJAN_GRPC=2       # 已废弃
readonly PROTOCOL_VMESS_WS=3
readonly PROTOCOL_TROJAN_TCP=4
readonly PROTOCOL_VLESS_GRPC=5        # 已废弃
readonly PROTOCOL_HYSTERIA2=6
readonly PROTOCOL_VLESS_REALITY_VISION=7
readonly PROTOCOL_VLESS_REALITY_GRPC=8 # 已废弃
readonly PROTOCOL_TUIC=9
readonly PROTOCOL_NAIVE=10
readonly PROTOCOL_VMESS_HTTPUPGRADE=11
readonly PROTOCOL_XHTTP=12            # VLESS+Reality+XHTTP
readonly PROTOCOL_ANYTLS=13
readonly PROTOCOL_SS2022=14
readonly PROTOCOL_SOCKS5=20
```

### 4.2 协议属性查询

`protocol-registry.sh` 以 `case` 语句封装协议元数据查询：

```bash
getProtocolConfigFileName 0      # → 02_VLESS_TCP_inbounds.json
parseProtocolIdFromFileName "02_VLESS_TCP_inbounds.json"   # → 0
getProtocolDisplayName 0         # → VLESS+TCP/TLS_Vision
getProtocolShortName 0           # → vless_vision
getProtocolInboundTag 0          # → VLESSTCP（sing-box inbound tag）
getProtocolTransport 0           # → tcp / ws / grpc / quic / ...

protocolRequiresTLS 0            # 0 = 需要 TLS
protocolUsesReality 7            # 0 = 是 Reality
protocolUsesUDP 6                # 0 = 是 UDP
protocolSupportsCDN 1            # 0 = 支持 CDN
```

### 4.3 安装状态扫描

```bash
# 扫描指定目录下 *_inbounds.json 文件，返回 ",0,1,7," 格式字符串
scanInstalledProtocols "/etc/Proxy-agent/xray/conf/"

# 组装协议配置完整路径
getProtocolConfigPath 0 "/etc/Proxy-agent/xray/conf/"
# → /etc/Proxy-agent/xray/conf/02_VLESS_TCP_inbounds.json
```

主流程惯例：`currentInstallProtocolType` 全局变量持有当前安装状态，用 `grep -q ",N,"` 检查指定协议是否已装。

### 4.4 协议配置读取器（json-utils.sh）

json-utils.sh 为每个协议提供专用读取器。输出写入**全局变量**（不再返回 heredoc eval 文本），避免 `eval "$(fn ...)"` 注入面：

```bash
# Xray
xrayGetInboundPort      file [index]     # → 回显端口
xrayGetInboundProtocol  file [index]
xrayGetClientUUID       file [iIdx] [cIdx]
xrayGetClients          file [index]     # → 回显 JSON 数组
xrayGetTLSDomain        file
xrayGetRealityConfig    file [index]     # 写入 realityServerName / realityPublicKey / ...
xrayGetStreamPath       file ws|grpc|xhttp

# sing-box
singboxGetInboundPort      file [index]
singboxGetUserUUID         file [iIdx] [uIdx]
singboxGetTLSServerName    file [index]
singboxGetRealityConfig    file [index]  # 写入 singboxRealityServerName / ...
singboxGetHysteria2Config  file          # 写入 hysteria2Port / hysteria2UpMbps / ...
singboxGetTuicConfig       file          # 写入 tuicPort / tuicAlgorithm
```

---

## 5. i18n 国际化系统

### 5.1 使用

```bash
# 纯字符串
echoContent yellow "$(t MENU_INSTALL)"

# 带 printf 占位符
echoContent green "$(t PROGRESS_STEP "${current}" "${total}")"
```

### 5.2 新增翻译

两个语言文件必须键数对齐（CI 会校验，见 `.github/workflows/ci.yml`）。

```bash
# shell/lang/zh_CN.sh
MSG_NEW_KEY="新消息内容"

# shell/lang/en_US.sh
MSG_NEW_KEY="New message content"
```

### 5.3 缺键调试

设置环境变量开启：

```bash
V2RAY_I18N_DEBUG=1 pasly
# miss key 追加到 /tmp/proxy-agent-i18n-missing.log
```

发版前 `grep` 一下即可发现漏翻。

### 5.4 命名约定

| 前缀 | 用途 | 示例 |
|------|------|------|
| `MSG_SYS_` | 系统消息 | `MSG_SYS_CHECKING` |
| `MSG_MENU_` | 菜单项 | `MSG_MENU_INSTALL` · `MSG_MENU_DOCTOR` |
| `MSG_ERR_` | 错误消息 | `MSG_ERR_PORT_RANGE` |
| `MSG_UPDATE_` | 更新流程 | `MSG_UPDATE_SHA256_OK` |
| `MSG_CHAIN_` | 链式代理 | `MSG_CHAIN_MENU_WIZARD` |
| `MSG_EXT_` | 外部节点 | `MSG_EXT_ADD_SS` |
| `MSG_SCRIPT_` | 脚本版本管理 | `MSG_SCRIPT_ROLLBACK_CONFIG_PROMPT` |
| `MSG_DRY_RUN_` | dry-run banner | `MSG_DRY_RUN_BANNER` |
| `MSG_PLAN_` | dry-run 计划行（mutator 入口短路时打印） | `MSG_PLAN_UNINSTALL` · `MSG_PLAN_INSTALL` · `MSG_PLAN_REALITY_QUICK` · `MSG_PLAN_CHAIN_EXIT` |
| `MSG_DOCTOR_` | doctor 输出（section / check / status） | `MSG_DOCTOR_HEADER` · `MSG_DOCTOR_CHECK_CORE_VERSION` · `MSG_DOCTOR_STATUS_PASS` |

### 5.5 语言检测优先级

`V2RAY_LANG` > `/etc/Proxy-agent/lang_pref` > `zh_CN`（默认）。

不查 `$LANGUAGE` / `$LANG`：`install.sh` 顶部 `export LANG=en_US.UTF-8`（为子进程 grep/sort 锁定 locale）会污染 i18n 检测，让默认强制变英文，所以这一档已移除。

---

## 6. 配置文件系统

### 6.1 文件命名规范

```
XX_PROTOCOL_inbounds.json
│  │
│  └── 协议 / 功能名
└── 序号（决定加载顺序）
```

序号分配：

- `00` 日志
- `01` API
- `02-14` 协议入站
- `20+` 特殊功能（SOCKS5 等）

### 6.2 Xray 配置结构

Xray 用 `-confdir` 自动合并多个 JSON 文件：

```json
// 02_VLESS_TCP_inbounds.json
{
    "inbounds": [{
        "port": 443,
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "uuid-here", "flow": "xtls-rprx-vision"}],
            "decryption": "none"
        },
        "streamSettings": { "network": "tcp", "security": "tls", ... }
    }]
}
```

### 6.3 sing-box 配置结构

sing-box 需要合并为单一 `config.json`。片段在 `conf/config/` 下，由 `singBoxMergeConfig` 合并。

```json
// 合并前 conf/config/06_hysteria2_inbounds.json
{ "inbounds": [{ "type": "hysteria2", "tag": "hysteria2-in", ... }] }

// 合并后 conf/config.json
{ "log": {...}, "inbounds": [...], "outbounds": [...], "route": {...} }
```

### 6.4 sing-box 合并

```bash
singBoxMergeConfig        # 合并 conf/config/*.json 到 conf/config.json
```

**实现要点**（install.sh `singBoxMergeConfig` 函数）：

1. **mktemp 模式**：先 `sing-box merge` 输出到 `/tmp/Proxy-agent-singbox-merge-XXXXXX.json`，**不**先删除现有 `config.json`。
2. **运行时校验**：用 `sing-box check -c <tmp>` 做端口冲突 / tag 唯一性等 merge 不查的项。
3. **原子 mv**：上面两步通过后才 `mv` 替换 `config.json`。任何失败保留旧 config 不动，避免 systemd `Restart=on-failure` 在配置坏掉时陷入 restart loop。
4. **失败行为**：返回 1 + 打印 sing-box 实际报错前 20 行；**不 exit**，调用方负责决策（典型为 `if ! singBoxMergeConfig; then return 1; fi`）。

**sing-box 服务启动前必须合并**：`handleSingBox start` 已自动先调 `singBoxMergeConfig` 再启动；merge 失败 `handleSingBox` 会 `exit 1`（与其他 handle* 一致）。

### 6.5 sing-box 域名嗅探（1.11+）

sing-box **1.11** 引入路由级 `action` 字段（参见官方迁移文档 <https://sing-box.sagernet.org/migration/>），1.12 移除了 inbound 上的 `sniff` / `sniff_override_destination` / `domain_strategy` 字段。本脚本统一使用路由级实现，与上游 mack-a/v2ray-agent v3.5.10 同款：

```jsonc
// inbound 不再带 sniff
{"type":"shadowsocks","tag":"chain_inbound","listen":"::","listen_port":12345, "method":"...","password":"..."}

// 路由顺序：sniff → resolve → 业务规则 → final
// 显式绑定 inbound + timeout 1s（上游模式 / 官方推荐）
{"route":{"rules":[
    {"inbound":"chain_bridge_in","action":"sniff","timeout":"1s"},
    {"inbound":"chain_bridge_in","action":"resolve","strategy":"prefer_ipv4"},
    {"inbound":["chain_bridge_in"],"outbound":"chain_outbound"}
],"final":"chain_outbound"}}
```

约定：
- `{"inbound":"<tag>","action":"sniff","timeout":"1s"}` 嗅探指定 inbound 的连接，等价于旧 inbound 的 `sniff: true` + `sniff_override_destination: true`
- `{"inbound":"<tag>","action":"resolve","strategy":"<策略>"}` 用嗅探到的域名重新解析；替代旧 inbound 的 `domain_strategy`，可选策略：`prefer_ipv4` / `prefer_ipv6` / `ipv4_only` / `ipv6_only`
- 中继节点不重解析（沿用上游已嗅探到的域名），只 prepend sniff 即可

### 6.6 链式代理状态文件

`chain_*_info.json` 和 `external_node_info.json` 在 `sing-box/conf/` 根目录（**不在 `conf/config/` 片段目录**），不参与 sing-box merge。它们是**链式代理模块自己的状态存储**，被 chain 代码读取后再派生出 `conf/config/chain_*.json` 片段。

---

## 7. 服务管理系统

### 7.1 服务控制总览

服务控制代码在 `install.sh` 内直接定义，按 `${release}`（Alpine / Debian / Ubuntu / CentOS）分派到 `systemctl` 或 `rc-service`。

| 函数 | 位置 | 职责 |
|------|------|------|
| `handleXray start\|stop` | install.sh | Xray 启停 + pgrep 验证 + 失败时打印 systemctl status / journalctl 诊断 |
| `handleSingBox start\|stop` | install.sh | sing-box 启停 + **自动合并配置** + 10×0.5s 等待退出循环 |
| `handleNginx start\|stop` | install.sh | Nginx 启停 + Reality-only 场景跳过 + CentOS SELinux 自动修复 |
| `reloadCore` | install.sh | 根据 `${coreKind}` 和 `currentInstallProtocolType` 决定重启 xray / sing-box |

### 7.2 行为约定

- **handle\* 启停失败**：服务函数会打印红字错误 + 诊断信息（如 `systemctl status` 前 20 行、`journalctl` 前 15 行），然后 `exit 1` 终止整个脚本。调用方**不需要**自己加 `|| exit 1`。
- **`singBoxMergeConfig` 失败**：与 handle* 不同，**不 exit，仅返回 1**。调用方需自行决策：
  - 安装 / 链式代理配置流程：`if ! singBoxMergeConfig; then return 1; fi`
  - 卸载流程（清理已完成）：警告但不阻断
  - `rollbackScript`：失败时自动撤销回滚到 `pre_rollback_config` 快照
- **启动前检查**：`handleSingBox start` 会先调 `singBoxMergeConfig`；合并失败 `handleSingBox` 会 `exit 1`（启停语义），不会带着旧 `config.json` 或缺失 config 启动。
- **pgrep 匹配**：`handleSingBox` 用 `pgrep -x sing-box`（精确匹配进程名）；`handleXray` 用 `pgrep -f "xray/xray"`（命令行模式）。

### 7.3 防火墙

```bash
allowPort <port> [tcp|udp] [allowedIP]
```

自动检测 ufw / firewalld / iptables / nftables / netfilter-persistent，开放指定端口。`allowedIP` 用于链式代理出口节点的 "仅允许入口节点 IP" 白名单。

---

## 8. 链式代理系统

### 8.1 架构

```
用户 → 入口节点 → [中继节点...] → 出口节点 → 互联网
         │              │              │
     可控 (root)    可控 (root)   可控或外部节点
```

### 8.2 节点角色

| 角色 | 职责 | 状态文件 |
|------|------|---------|
| 出口节点 | 接收上游流量，直连互联网 | `chain_exit_info.json` |
| 中继节点 | 转发到下游（支持多跳） | `chain_relay_info.json` |
| 入口节点 | 接收用户流量，转发到出口或中继 | `chain_entry_info.json` |
| 多链路入口 | 按分流规则挑选链路 | `chain_multi_info.json` |

状态文件路径均为 `/etc/Proxy-agent/sing-box/conf/<name>.json`（不在 `conf/config/` 片段目录）。

### 8.3 配置码格式

```
# V1（单跳）
chain://ss2022@IP:PORT?key=BASE64_KEY&method=2022-blake3-aes-128-gcm#NAME

# V2（多跳）
chain://v2@BASE64_ENCODED_JSON_ARRAY
```

### 8.4 多链路分流状态

```json
// chain_multi_info.json
{
    "role": "entry",
    "mode": "multi_chain",
    "chains": [
        {"name": "chain_us", "ip": "us.example.com", "port": 5000, "method": "...", "password": "...", "is_default": true},
        {"name": "chain_hk", "ip": "hk.example.com", "port": 5001, "...": "..."}
    ],
    "rules": [
        {"type": "preset", "value": "streaming", "chain": "chain_us"},
        {"type": "preset", "value": "ai",        "chain": "chain_hk"}
    ]
}
```

### 8.5 外部节点

无 root 的第三方节点（机场 / 拼车）可作为出口挂入多链路。

```json
// external_node_info.json
{
    "nodes": [
        {
            "id": "ext_xxx", "name": "US-SS-Node", "type": "shadowsocks",
            "server": "us.example.com", "server_port": 8388,
            "method": "aes-256-gcm", "password": "xxx"
        },
        {
            "id": "ext_yyy", "name": "HK-Trojan", "type": "trojan",
            "server": "hk.example.com", "server_port": 443, "password": "xxx",
            "tls": {"enabled": true, "server_name": "hk.example.com"}
        }
    ]
}
```

支持类型：Shadowsocks（含 SS2022）· SOCKS5 · Trojan。

### 8.6 原子写入

所有链式状态文件通过 `writeChainInfoAtomic`（install.sh 内的 wrapper，转调 `lib/json-utils.sh::jsonWriteFile`）写入：JSON 语法校验 → mktemp → rename。失败保留旧文件不变。外部节点 add/remove 用 `addExternalNodeToFile` / `removeExternalNodeFromFile`，同样走原子写入 + jq 返回码检查。

每个链式状态文件包含 `"schema_version": 1` 字段，未来 schema 变更时升版本号；新读端可按 `schema_version` 决定字段映射。

---

## 9. 输入校验与原子写入

### 9.1 输入即校验

用户输入点立即正则校验，拒绝元字符/非法值，让下游 JSON 构造和 jq 过滤器天然安全：

| 输入点 | 校验规则 |
|---|---|
| `customUUID` | `^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-...{12}$` |
| `customUserEmail` | `^[A-Za-z0-9][A-Za-z0-9._@+-]{0,63}$` |
| `customPath` | `^[A-Za-z0-9._-]{1,32}$` |
| `readValidPort` | `^[1-9][0-9]*$` + `[min, max]` 范围 |
| `readValidDomain` | `isValidDomain`（含命令注入字符过滤） |
| `addCorePort::portIndex` | `^[1-9][0-9]*$` + 后续 `grep -F` 固定字符串 |

### 9.2 jq 参数传递

所有 jq 过滤器调用使用 `--arg` / `--argjson`，**不要字符串拼接**：

```bash
# ✗ 不要这么写
jq "del(.clients[${idx}])" config.json

# ✓ 用 --argjson
jq --argjson idx "${idx}" 'del(.clients[$idx])' config.json

# ✓ 动态 key 用白名单 + .[$k] 访问
case "${type}" in outboundTag|inboundTag) ;; *) return 1 ;; esac
jq --arg key "${type}" --arg tag "${tag}" 'del(.rules[] | select(.[$key] == $tag))' f.json
```

### 9.3 原子 JSON 写入

用 `lib/json-utils.sh::jsonWriteFile` 或 `jsonModifyFile`：

```bash
# 从字符串写入
jsonWriteFile "<path>" "<json content>" [backup=true|false]

# 基于 jq 过滤器修改现有文件
jsonModifyFile "<path>" "<jq filter>" [backup=true|false]
```

流程：语法校验 → `mktemp` → 写入 → `jq -e .` 验证 → 原子 `mv`。失败时保留原文件不变，返回 1。

链式代理状态文件的专用 wrapper：

```bash
writeChainInfoAtomic "<path>" "<json content>"       # backup=false + 统一错误消息
```

### 9.4 自更新 SHA256

```bash
# .github/workflows/create_release.yml 同时上传 install.sh + install.sh.sha256
#   （install.sh 资产让 README 可以钉到 releases/latest/download/install.sh，
#    避免 master raw 路径绕开 verifyInstallSHA256 的软降级窗口）
# install.sh::verifyInstallSHA256 下载时核对
# 校验失败 → 删坏文件 + 从 /etc/Proxy-agent/backup/v<ver>_<ts>/install.sh 恢复 + exit 1
# 软降级：无 tag（master 分支）/ 无资产（老 Release）/ 格式异常 → 警告但不阻断升级
```

`updateV2RayAgent` 的下载流程统一走 `.new + bash -n + 原子 mv` 模式：

- **install.sh 主下载**：先下到 `${installDir}/install.sh.new` → `bash -n` 语法校验 → release tag 失败回退到 master → 最终校验通过才 `mv` 到 live install.sh。这样 GitHub 偶发返回 200 OK 但 body 是 HTML 错误页（HTML 不合法 bash → bash -n 必失败）也能被拦下，master 分支用户（无 SHA256 资产软降级）也有最低限度的完整性校验。
- **lib/ 模块下载**：每个文件下到 `<dst>.new` → bash -n → mv。任一文件失败累积到 `failedModules[]`，最后从备份回滚 install.sh。
- **shell/lang 下载**：同 lib/ 模式。
- **不使用 `wget -c`**：续传模式遇到本地残留旧版本文件会拼接出 [旧前 N 字节][新文件后续] 的损坏文件。已知历史 bug，禁用。

### 9.5 备份与回滚

- `backupScript update|manual|rollback` → `/etc/Proxy-agent/backup/v<ver>_<ts>/`
  - 复制 `install.sh` + `VERSION` + `lib/` + `shell/lang/`
  - 调 `backupConfigSnapshot` 把 `xray/conf/` + `sing-box/conf/` + `tls/` + `lang_pref` 拷到 `config/` 子目录
  - 写 `backup_info.json`（含 `has_config` 布尔）
  - 自动轮替，保留最近 5 份
- `rollbackScript` 本地分支支持 opt-in 配置恢复：恢复前先快照当前配置到 `pre_rollback_config/`，让回滚本身可逆

---

## 10. 开发指南

### 10.1 添加新协议

1. **分配 ID**：`constants.sh` 新增 `readonly PROTOCOL_NEW=15`。ID 一旦发布就不能改。
2. **注册元数据**：`protocol-registry.sh` 10 个 `case` 分支加上 15：
   - `getProtocolConfigFileName`
   - `parseProtocolIdFromFileName`
   - `getProtocolDisplayName`
   - `getProtocolShortName`
   - `getProtocolInboundTag`（若为 sing-box 协议）
   - `protocolRequiresTLS` / `protocolUsesReality` / `protocolUsesUDP` / `protocolSupportsCDN`
   - `getProtocolTransport`
3. **生成入站配置**：`install.sh` 新增 handler 按协议写入站 JSON 到 `configPath${fileName}`。建议用 `writeChainInfoAtomic` 风格封装（heredoc 捕获 + `jsonWriteFile`），避免 half-write。
4. **接入 addUser / removeUser / showAccounts**：3 个函数内按 `currentInstallProtocolType | grep -q ",15,"` 加分支。
5. **接入安装菜单**：`customInstall` 或 `initXrayConfig` / `initSingBoxConfig` 按核心类型注册。
6. **双语翻译**：为所有新菜单和提示加 `MSG_*` 键，zh_CN 和 en_US 同步对齐。
7. **测试**：`tests/test_integration.sh` 加断言验证 `parseProtocolIdFromFileName` 和 `getProtocolConfigFileName` 正确。

### 10.2 添加新菜单功能

命名规范：`<action><feature>Menu`

```bash
newFeatureMenu() {
    echoContent skyBlue "\n$(t NEW_FEATURE_TITLE)"
    echoContent red "=============================================================="
    echoContent yellow "1. $(t OPTION_1)"
    echoContent yellow "2. $(t OPTION_2)"
    echoContent yellow "0. $(t BACK)"

    read -r -p "$(t PROMPT_SELECT): " choice
    case "$choice" in
        1) handleOption1 ;;
        2) handleOption2 ;;
        0) return 0 ;;
        *) newFeatureMenu ;;
    esac
}
```

### 10.3 添加新语言

1. 复制 `shell/lang/zh_CN.sh` 为 `shell/lang/<code>.sh`，逐个翻译 `MSG_*`。
2. 修改 `lib/i18n.sh::_detect_language` 添加你的 locale 映射。
3. 修改 `install.sh` 的 "21. 切换语言" 菜单列表。
4. CI 的双语对齐 job 会在 PR 时校验新语言文件键对齐。

### 10.4 测试

```bash
# 语法检查
bash -n install.sh lib/*.sh shell/lang/*.sh

# 单元测试（lib/）
bash tests/test_modules.sh

# 集成测试（mock /etc/Proxy-agent/ 树）
bash tests/test_integration.sh

# 双语对齐检查
diff <(grep -oE '^MSG_[A-Z_0-9]+' shell/lang/zh_CN.sh | sort) \
     <(grep -oE '^MSG_[A-Z_0-9]+' shell/lang/en_US.sh | sort)

# 语言环境测试
V2RAY_LANG=en bash install.sh
```

### 10.5 本地开发的调试开关

```bash
bash -x install.sh                          # 完整命令追踪
V2RAY_I18N_DEBUG=1 pasly                    # 记录 i18n miss key
bash -u install.sh                          # 检测未定义变量（启动路径已支持，安装流尚未全覆盖）
```

---

## 11. 最佳实践

### 11.1 编码规范

```bash
# 函数：camelCase
handleXray()
singBoxMergeConfig()
parseChainCode()

# 变量：camelCase
currentInstallProtocolType
chainExitIP

# 常量：UPPER_SNAKE + readonly
readonly PROTOCOL_VLESS_TCP_VISION=0
readonly PROXY_AGENT_DIR="/etc/Proxy-agent"

# 局部变量：local 声明
local port="$1"
```

### 11.2 错误处理

不使用 `set -e`。每个可能失败的命令显式检查：

```bash
if ! someCommand; then
    echoContent red " ---> 操作失败"
    return 1
fi

if [[ ! -f "${configFile}" ]]; then
    echoContent red " ---> 配置文件不存在"
    return 1
fi
```

### 11.3 JSON 操作

永远不要字符串拼接到 jq 过滤器；永远不要直写 heredoc 到 JSON 文件：

```bash
# ✓ 原子写入 + jq 校验
jsonWriteFile "${file}" "${content}" false

# ✓ 参数化 jq
jq --arg val "${value}" '.field = $val' "${file}"

# ✓ 链式状态文件
writeChainInfoAtomic "${file}" "${content}"
```

### 11.4 用户交互

```bash
# 用统一 helper（输入即校验 + 本地化错误）
readValidPort "端口: " port 443 || exit 1
readValidDomain "域名: " domain || return 1

# 确认危险操作
read -r -p "确认删除? [y/N]: " confirm
[[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && return 0

# 本地化提示
read -r -p "$(t PROMPT_SELECT): " choice
```

### 11.5 服务重启

```bash
# 按当前安装的核心分派
if [[ "${coreKind}" == "1" ]]; then
    handleXray stop
    handleXray start
elif [[ "${coreKind}" == "2" ]]; then
    handleSingBox stop
    handleSingBox start
fi

# 或用 reloadCore 一键重启当前核心
reloadCore
```

### 11.6 向后兼容

```bash
# 老代码路径保护
if [[ -f "/old/path/config.json" ]]; then
    mv "/old/path/config.json" "/new/path/config.json"
fi
```

> 早先版本曾保留 `coreInstallType` 作为 `coreKind` 的 mirror alias，
> 已确认无读端后从主分支移除。新代码统一读 `coreKind`。

---

## 12. 诊断与计划模式

两个互不相关、但都属于「不动配置」的运维特性。doctor 是只读体检，dry-run 是写入前的预演。两者都通过同一套顶层入口分发暴露。

### 12.1 顶层入口分发

`install.sh` 在所有函数定义之后、`checkForUpdates` / `cronFunction` / `menu` 调用之前，根据 `$1` 决定走哪条路：

```bash
case "${1:-}" in
    doctor)              doctor; exit $? ;;          # 跳过更新检查 / cron / 菜单
    --dry-run | -n)      export DRY_RUN=1; shift ;;  # 进入 dry-run，仍走菜单
esac
```

向后兼容：无参 / 无识别参数维持原样。环境变量 `DRY_RUN=1 pasly` 不经过 case，直接被 `isDryRun` 命中——`--dry-run` 选项只是 argv 形式的语法糖。

### 12.2 doctor 子命令

只读系统诊断。**不写任何配置、不重启服务、不申请证书、不动防火墙**。覆盖 7 个 section：

| Section | 检查项 |
|---|---|
| System | root 权限 / OS / CPU 架构 / 必需命令（jq curl wget openssl） / SELinux 状态（仅 RHEL 系） |
| Install | `/etc/Proxy-agent` 目录 / VERSION 文件 / lib 模块完整性 / shell/lang 文件 |
| Core | `coreKind` / 二进制存在与可执行 / 核心版本 / systemd 或 OpenRC 服务状态 / 进程是否在运行 |
| Config | Xray：`xray/conf/*.json` 全部 jq -e 校验<br>sing-box：`sing-box check -c <merged config>` |
| Network | 公网 IP（5s 超时）/ GitHub 可达性（5s 超时） |
| Cert | TLS 目录存在 / 第一对 `<domain>.crt` + `.key` 的有效期 + 私钥匹配（用现有 `verifyCertExpiry` / `verifyCertKeyMatch`，仅 Reality 时跳过） |
| Firewall | ufw / firewalld / nftables / iptables 中第一个能用的，输出当前状态 |

每行用 `_doctorRow LABEL pass|warn|fail|skip [DETAIL]` 输出。函数末尾 FAIL 计数 > 0 时返回 1，方便 `pasly doctor || alert` 之类脚本化使用。

**调用入口**：

- `pasly doctor` 子命令（不进菜单，无更新检查）
- 菜单 23 「系统诊断（只读）」

**不写**到 `lib/`：`doctor` 直接用 `coreKind` / `currentInstallProtocolType` / `verifyCertExpiry` / `verifyCertKeyMatch` 等 install.sh 自带的全局变量与函数，剥离到独立模块的成本不抵收益。

**扩展新检查项**：在 `_doctorCheck<Section>` 内 grep 想要的事实，调 `_doctorRow`。新增 status 类型在 case 里加分支，并在 i18n 加 `MSG_DOCTOR_STATUS_*`。新增 section 需同时改 i18n（`MSG_DOCTOR_SECTION_*`）和 `doctor()` 主入口。

### 12.3 dry-run 计划模式

预演模式：用户走完所有菜单提示，但 mutator 入口在动手前打印「[plan] 将做什么」并立即返回。**不申请证书、不写配置、不改防火墙、不重启服务**。

实现是两个 lib 函数（`lib/utils.sh`）：

```bash
isDryRun()    # [[ "${DRY_RUN:-0}" == "1" ]]
planAction()  # dry-run 时打印 "[plan] $*" 并 return 0；非 dry-run 时 return 1
```

惯用法：在 mutator 入口最顶端一行：

```bash
unInstall() {
    if planAction "$(t MSG_PLAN_UNINSTALL)"; then return 0; fi
    # 真实卸载逻辑...
}
```

**已插桩的入口**（共 8 处，全部是用户菜单可触发的 mutator 顶层）：

| 函数 | 触发菜单 | 计划 key |
|---|---|---|
| `unInstall` | 20 卸载 | `MSG_PLAN_UNINSTALL` |
| `selectCoreInstall` | 1 安装 / 2 组合安装 | `MSG_PLAN_INSTALL` |
| `selectRealityCoreInstall` | 19 一键 Reality 安装 | `MSG_PLAN_REALITY_QUICK` |
| `setupChainExit` | 3 → 1 → 1 链式出口 | `MSG_PLAN_CHAIN_EXIT` |
| `setupChainRelay` | 3 → 1 → 2 链式中继 | `MSG_PLAN_CHAIN_RELAY` |
| `setupChainEntryByCode` | 3 → 1 → 3 配置码入口 | `MSG_PLAN_CHAIN_ENTRY` |
| `setupChainEntryManual` | 3 → 1 → 5 手动入口 | `MSG_PLAN_CHAIN_ENTRY` |
| `setupMultiChainEntry` | 3 → 1 → 4 多链路入口 | `MSG_PLAN_CHAIN_ENTRY_MULTI` |

**有意未插桩**：

- 菜单 **4 / 5 / 6 / 8 / 9 / 11 / 12 / 14 / 16 / 17 / 18 / 22**（含 Hysteria2 / Reality / TUIC 管理、伪装站、证书续签、分流工具、添加端口、内核升级、自更新、BBR、脚本回滚等）目前**仍执行真实操作**——dry-run banner 不覆盖这些路径。`pasly --dry-run` 在这些菜单下与正常运行无区别。
- 底层的 `jq` / `handle*` / `systemctl` / `acme.sh` 调用全部不动。粒度故意停在「用户菜单调用的 mutator 顶层」一层——这是「会装 Reality 协议、会改 firewall」级别的预告，不是「`jsonModifyFile` 会被调 17 次」级别的逐行 trace。
- 这种粗粒度是 P0-4 阶段的初始 scope。完整覆盖所有菜单 mutator（约 40-50 个函数）属于后续工作，建议跟 `state.json` declarative 状态层一起设计——光插桩没有 single source of truth 的话，dry-run 输出还是只能讲「会做什么」、讲不出「最终系统会是什么样」。

**banner**：`menu()` 顶部检测 `isDryRun` 并打印 `MSG_DRY_RUN_BANNER`。直接 `pasly doctor` 不进菜单，不会显示 banner——doctor 本身不写东西，不需要 dry-run 兜底。

**新加协议时**：如果新协议有独立的 mutator 菜单入口（不是走 `selectCoreInstall` 的统一路径），记得在该入口顶部插一行 `planAction`，并在两个 lang 文件加对应 `MSG_PLAN_*` 键。

---

## 附录 A: 函数速查

### 系统探测

| 函数 | 模块 | 用途 |
|------|------|------|
| `checkSystem` | lib/system-detect | 检测 OS 类型，设置 `${release}` |
| `checkCPUVendor` | lib/system-detect | 检测 CPU 架构 |
| `checkRoot` | lib/system-detect | 非 root 直接 exit 1 |
| `getPublicIP` | lib/system-detect | 多源回退获取公网 IP |
| `checkCentosSELinux` | lib/system-detect | SELinux 启用检测 + 提示 |

### 协议查询

| 函数 | 用途 |
|------|------|
| `getProtocolConfigFileName ID` | 协议配置文件名 |
| `parseProtocolIdFromFileName NAME` | 从文件名反查 ID |
| `getProtocolDisplayName ID` | 显示名称 |
| `getProtocolInboundTag ID` | sing-box inbound tag |
| `protocolRequiresTLS ID` / `protocolUsesReality ID` | 属性查询 |
| `scanInstalledProtocols DIR` | 扫描目录返回 `,0,1,7,` 字符串 |

### 服务控制（install.sh）

| 函数 | 用途 |
|------|------|
| `handleXray start\|stop` | Xray 启停 + 诊断输出 |
| `handleSingBox start\|stop` | sing-box 启停（含自动合并） |
| `handleNginx start\|stop` | Nginx 启停（含 SELinux 修复） |
| `singBoxMergeConfig` | 合并 sing-box 配置并验证 |
| `reloadCore` | 重启当前核心 |
| `allowPort PORT [PROTO] [IP]` | 开放防火墙端口（ufw / firewalld / iptables / nftables / netfilter-persistent） |

### 工具函数（lib/utils.sh）

| 函数 | 用途 |
|------|------|
| `echoContent COLOR TEXT` | 彩色输出（red / green / yellow / skyBlue 等） |
| `randomNum MIN MAX` · `randomPort` | 随机数 |
| `isValidPort` · `isValidUUID` | 校验谓词 |
| `base64Encode` · `base64Decode` | Base64 跨平台兼容 |
| `versionGreaterThan V1 V2` · `versionGreaterOrEqual V1 V2` | 版本比较 |
| `isDryRun` · `planAction MSG` | dry-run 探测 / 短路 helper（详见 §12.3） |
| `timestamp` | `date +%s` |
| `trim` · `stripAnsi` | 字符串 |
| `t KEY [ARGS...]` | i18n 翻译（实际在 lib/i18n.sh） |

### JSON 操作（lib/json-utils.sh）

| 函数 | 用途 |
|------|------|
| `jsonValidateFile FILE` | 校验 JSON 语法 |
| `jsonGetValue FILE PATH [DEFAULT]` | 读取单值 |
| `jsonGetArray FILE PATH` | 读取数组（空时返回 `[]`） |
| `jsonWriteFile FILE CONTENT [BACKUP]` | 原子写入（验证 + mv） |
| `jsonModifyFile FILE FILTER [BACKUP]` | 基于 jq 过滤器原子修改 |
| `xrayGet*` / `singboxGet*` | 13 个协议专用读取器 |

---

## 附录 B: 配置模板

### Xray VLESS+TLS 入站

```json
{
    "inbounds": [{
        "port": 443,
        "listen": "0.0.0.0",
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "UUID", "flow": "xtls-rprx-vision"}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
                "certificates": [{
                    "certificateFile": "/etc/Proxy-agent/tls/<domain>.crt",
                    "keyFile": "/etc/Proxy-agent/tls/<domain>.key"
                }]
            }
        }
    }]
}
```

### sing-box Hysteria2 入站

```json
{
    "inbounds": [{
        "type": "hysteria2",
        "tag": "hysteria2-in",
        "listen": "::",
        "listen_port": 443,
        "users": [{"password": "PASSWORD"}],
        "tls": {
            "enabled": true,
            "certificate_path": "/etc/Proxy-agent/tls/<domain>.crt",
            "key_path": "/etc/Proxy-agent/tls/<domain>.key"
        }
    }]
}
```

### 外部节点 Shadowsocks 出站

```json
{
    "type": "shadowsocks",
    "tag": "external_ss",
    "server": "example.com",
    "server_port": 8388,
    "method": "aes-256-gcm",
    "password": "PASSWORD"
}
```

---

## 附录 C: 常见开发问题

### Q: 如何调试脚本？

```bash
bash -x install.sh       # 完整命令追踪
bash -n install.sh       # 仅语法检查
```

### Q: 如何查看服务日志？

```bash
# Xray
tail -f /etc/Proxy-agent/xray/error.log
journalctl -u xray -f

# sing-box
tail -f /etc/Proxy-agent/sing-box/box.log
journalctl -u sing-box -f
```

### Q: 配置修改后不生效？

```bash
# Xray：重启即可
handleXray stop && handleXray start

# sing-box：必须先合并再重启
singBoxMergeConfig && handleSingBox stop && handleSingBox start

# 或一键：
reloadCore
```

### Q: 如何禁用 i18n 看调试原始 key？

```bash
# 所有翻译 miss 都会回显 key 名
V2RAY_I18N_DEBUG=1 V2RAY_LANG=xx_XX pasly
```

---

## 附录 D: 已知上游问题（暂不修复）

### D.1 VLESS+Reality dokodemo-door routing 规则死代码

**位置**：`install.sh` 生成 `07_VLESS_vision_reality_inbounds.json` 的 heredoc 块（搜 `cat <<EOF >/etc/Proxy-agent/xray/conf/07_VLESS_vision_reality_inbounds.json` 定位）。install.sh 在该 heredoc 紧后已加 bash 注释指向本附录。

**现象**：dokodemo-door inbound 的 tag 为 `dokodemo-in-VLESSReality`，但同文件 `routing.rules` 内引用 `inboundTag: ["dokodemo-in"]`（Xray 是精确字符串匹配，不支持前缀），两者从不匹配 → 这两条 routing 规则**永远不会命中**。

**来源**：直接继承自上游 `mack-a/v2ray-agent` commit `1e890619`（"feat(脚本): xray-core reality增加防止流量盗刷配置"），本 fork 未引入此 bug，也未修复。

**为什么暂不修复**（"改 tag 让规则命中"会让伪装变弱，不是改进）：

1. dokodemo-door 的 sniffing 是 `routeOnly: true`：嗅探到的 SNI 只用于路由匹配，不重写连接的 destination。所以即使把 tag 改对、规则命中、流量被路由到 `z_direct_outbound`（freedom），freedom 拨号的目标仍是 dokodemo-door 自己的 `address: 127.0.0.1, port: 45987`（内层 VLESS-Reality）—— **匹配 SNI 流量的最终行为与"规则死掉"完全相同**。
2. 不匹配 SNI 的分支会被 `blackhole_out` 即时 RST，而真实的 nginx/apache 对错的 SNI 不会这样断 —— **会成为 Reality 自身想避免的指纹信号**。
3. 现状（规则死掉）让所有进入 realityPort 的流量统一进内层 VLESS-Reality，由 `realitySettings.target` 兜底无指纹反向代理到真实伪装站。这正是 Reality 协议设计的标准防探测路径，比修过的 routing 行为更隐蔽。

**理论上的"正确实现"**（也不该上线）：把 sniffing 改成 `routeOnly: false`，让嗅探到的 SNI 重写 destination，freedom 直接拨到真实伪装站 IP。但这会**破坏合法 Reality 客户端**——合法客户端的 SNI 也是 `realityServerName`，会被规则 1 直接转发到真实伪装站，永远到不了内层 VLESS-Reality 完成 Reality 协议鉴权。

所以 dokodemo-door + routing 这套设计在"既要骗探测者又要让 Reality 客户端通过"两个目标之间无解。等上游决定怎么办（要么整套重做、要么删除这段死代码）我们再跟进。

**当前影响评估**：**无安全/可用性影响**。Reality 协议的内层鉴权 + `realitySettings.target` 已经独立处理所有边界情况，dead routing 规则只是无害的 noise。

---

## 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|---------|
| 2.3 | 2026-05-04 | 脚本 v1.3.0 release：删除菜单 10（CDN 节点管理）/ 13（BT 下载管理）/ 15（域名黑名单）三个 niche 功能（详见用户指南升级与迁移提示）；`singBoxMergeConfig` 顶部一次性清理菜单 15 旧片段以避免 sing-box 1.13 FATAL；`addCorePort` 端口输入加 1-65535 正则校验；`nginxBlog` / `updateNginxBlog` 三处下载顺序改成「下载校验通过才 rm 静态目录」；ClashMeta 订阅 `external-controller` 绑回 loopback、移除已弃用 `global-client-fingerprint`；WARP 安装从 `apt-key add` 迁到 `gpg --dearmor + signed-by`；sing-box 客户端订阅模板 vendor refresh 到当前上游（路由级 sniff，含 1.13 schema 兼容）；`unInstallSingBox` rm 路径修正；`base64 -w 0` 改用通用形态以支持 Alpine BusyBox；`manageReality` 协议成员检测正则补前导逗号；systemd `sing-box.service` `ExecReload` 中 `\$MAINPID` 转义；删除 dead code `initSingBoxRouteConfig` / `downloadSingBoxGeositeDB`；`create_release.yml` 不再用 commit message 当 release body（让维护者手动填）；`documents/` 目录改名 `docs/`，所有内部引用同步；约 30 处历史性 / 上游溯源注释清理。 |
| 2.2 | 2026-05-03 | 新增 `pasly doctor` 只读系统诊断（7 段：System / Install / Core / Config / Network / Cert / Firewall）和菜单 23；新增 dry-run 计划模式：`lib/utils.sh` 加 `isDryRun` / `planAction` 两个 helper，`unInstall` / `selectCoreInstall` / `selectRealityCoreInstall` / `setupChain*` 共 8 处用户菜单可触发的 mutator 顶层入口插桩，`pasly --dry-run` / `pasly -n` / `DRY_RUN=1 pasly` 均可触发，菜单顶部黄字 banner 标识；`create_release.yml` 同时上传 `install.sh` 资产，让 README 可钉到 `releases/latest/download/install.sh`；新增 49 个双语 MSG 键（dry-run + doctor），对齐通过；新增 5 个 dry-run helper 单元测试（`test_modules.sh` 64 → 69）；doctor 的 sing-box 进程探测对齐 `pgrep -x sing-box`（与 `handleSingBox` + chain 函数一致）；本指南新增 §12 章节、修复 §6.5 重复编号、刷新 install.sh / lib/ 函数计数。 |
| 2.1 | 2026-05-01 | `singBoxMergeConfig` 改为 mktemp + sing-box check + 原子 mv（保留旧 config 不破坏）；19 处 chain/multi-chain 调用点接入失败检查；`parseChainCode` 加 IPv6 / Alpine grep / URL-safe base64 / SS2022 method+key 严格校验；`removeChainProxy` 不删 `01_direct_outbound.json`，剥离 deprecated `domain_strategy` 字段；订阅 hysteria2 obfs 走 jq -Rs / @uri 双层编码；`updateV2RayAgent` 改 `.new + bash -n + 原子 mv`；chain info 文件加 `schema_version`；`initXrayClients` / `initSingBoxClients` 全分支改 `--arg` 并修两个隐藏 bug（`${uuid}` → `${newUUID}`、`grep -q "0"` → `,0,` glob）；删除 `handleHysteria` / `coreInstallType` 死代码；dokodemo dead routing 加源码交叉引用；release/tag 不再自动清理。 |
| 2.0 | 2026-04-19 | 结构大调：lib/ 精简至 6 模块 57 函数（config-reader / service-control 删除）；P0 代码面全部落地（SHA256 自更新、jq 注入防御、eval 移除、原子写入、checkRoot exit）；P1 主体落地（输入校验 helper、配置快照回滚、coreKind 改名）。 |
| 1.0 | 2025-12-26 | 初始版本 |
