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

---

## 1. 项目概述

### 1.1 技术栈

- **语言**：Bash 4+
- **依赖**：`jq` · `curl` · `wget` · `openssl`
- **支持核心**：Xray-core · sing-box
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

用户执行 `pasly` 或 `bash /etc/Proxy-agent/install.sh`，流程：

```
trap 设置 → source lib/*.sh → _load_version → initVar → checkSystem →
checkCPUVendor → readInstallType → readInstallProtocolType → ... → menu()
```

---

## 2. 目录结构

### 2.1 源码目录

```
Proxy-agent/
├── install.sh                  # 主脚本（~16k 行，279 函数）
├── VERSION                     # 版本号文件
│
├── lib/                        # 共享工具模块（57 函数，6 个文件）
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
│   └── loader.sh
│
├── documents/                  # 使用与开发文档（本文件所在）
├── tests/
│   ├── test_modules.sh         # 单元测试（64 用例）
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

install.sh 按下列顺序 `source` 模块（install.sh L46-57）：

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
| `utils.sh` | 通用工具 | `echoContent` · `randomNum` · `randomPort` · `timestamp` · `isValidPort` · `isValidUUID` · `trim` · `stripAnsi` · `base64Encode/Decode` · `versionGreaterThan` · `validateJsonFile` |
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
versionGreaterThan "1.2.3" "1.2.0"   # 0 = v1 > v2

# 时间戳
ts=$(timestamp)         # date +%s
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
readonly PROTOCOL_VLESS_XHTTP=12
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
| `MSG_MENU_` | 菜单项 | `MSG_MENU_INSTALL` |
| `MSG_ERR_` | 错误消息 | `MSG_ERR_PORT_RANGE` |
| `MSG_UPDATE_` | 更新流程 | `MSG_UPDATE_SHA256_OK` |
| `MSG_CHAIN_` | 链式代理 | `MSG_CHAIN_MENU_WIZARD` |
| `MSG_EXT_` | 外部节点 | `MSG_EXT_ADD_SS` |
| `MSG_SCRIPT_` | 脚本版本管理 | `MSG_SCRIPT_ROLLBACK_CONFIG_PROMPT` |

### 5.5 语言检测优先级

`V2RAY_LANG` > `/etc/Proxy-agent/lang_pref` > `$LANGUAGE` > `$LANG` > `zh_CN`。

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
# install.sh L4729+
singBoxMergeConfig        # 调 sing-box merge，合并 conf/config/*.json 到 conf/config.json
                          # 失败时打印 sing-box 实际报错前 20 行，返回 1
```

**sing-box 服务启动前必须合并**：`handleSingBox start` 已自动先调 `singBoxMergeConfig` 再启动。

### 6.5 链式代理状态文件

`chain_*_info.json` 和 `external_node_info.json` 在 `sing-box/conf/` 根目录（**不在 `conf/config/` 片段目录**），不参与 sing-box merge。它们是**链式代理模块自己的状态存储**，被 chain 代码读取后再派生出 `conf/config/chain_*.json` 片段。

---

## 7. 服务管理系统

### 7.1 服务控制总览

服务控制代码在 `install.sh` 内直接定义，按 `${release}`（Alpine / Debian / Ubuntu / CentOS）分派到 `systemctl` 或 `rc-service`。

| 函数 | 位置 | 职责 |
|------|------|------|
| `handleXray start\|stop` | install.sh | Xray 启停 + pgrep 验证 + 失败时打印 systemctl status / journalctl 诊断 |
| `handleSingBox start\|stop` | install.sh | sing-box 启停 + **自动合并配置** + 10×0.5s 等待退出循环 |
| `handleHysteria start\|stop` | install.sh | Hysteria 独立服务（老版本兼容层） |
| `handleNginx start\|stop` | install.sh | Nginx 启停 + Reality-only 场景跳过 + CentOS SELinux 自动修复 |
| `reloadCore` | install.sh | 根据 `${coreKind}` 和 `currentInstallProtocolType` 决定重启 xray / sing-box |

### 7.2 行为约定

- **失败处理**：服务启停失败时，服务函数会打印红字错误 + 诊断信息（如 `systemctl status` 前 20 行、`journalctl` 前 15 行），然后 `exit 1` 终止整个脚本。调用方**不需要**自己加 `|| exit 1`。
- **启动前检查**：`handleSingBox start` 会先调 `singBoxMergeConfig`；合并失败直接退出，不会带着旧 `config.json` 启动。
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

所有链式状态文件通过 `writeChainInfoAtomic`（install.sh L4715）写入：JSON 语法校验 → mktemp → rename。失败保留旧文件不变。外部节点 add/remove 用 `addExternalNodeToFile` / `removeExternalNodeFromFile`，同样走原子写入 + jq 返回码检查。

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
# .github/workflows/create_release.yml 生成 install.sh.sha256 并挂到 Release 资产
# install.sh::verifyInstallSHA256 下载时核对
# 校验失败 → 删坏文件 + 从 /etc/Proxy-agent/backup/v<ver>_<ts>/install.sh 恢复 + exit 1
# 软降级：无 tag（master 分支）/ 无资产（老 Release）/ 格式异常 → 警告但不阻断升级
```

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
2. **注册元数据**：`protocol-registry.sh` 5 个 `case` 分支加上 15：
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
# 老变量名保留一版作为 mirror alias
coreKind=1
coreInstallType=1   # 计划下一个主版本移除

# 老代码路径保护
if [[ -f "/old/path/config.json" ]]; then
    mv "/old/path/config.json" "/new/path/config.json"
fi
```

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
| `allowPort PORT [PROTO] [IP]` | 开放防火墙端口（ufw / firewalld / iptables / nftables） |

### 工具函数（lib/utils.sh）

| 函数 | 用途 |
|------|------|
| `echoContent COLOR TEXT` | 彩色输出（red / green / yellow / skyBlue 等） |
| `randomNum MIN MAX` · `randomPort` | 随机数 |
| `isValidPort` · `isValidUUID` | 校验谓词 |
| `base64Encode` · `base64Decode` | Base64 跨平台兼容 |
| `versionGreaterThan V1 V2` | 版本比较 |
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

## 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|---------|
| 2.0 | 2026-04-19 | 结构大调：lib/ 精简至 6 模块 57 函数（config-reader / service-control 删除）；P0 代码面全部落地（SHA256 自更新、jq 注入防御、eval 移除、原子写入、checkRoot exit）；P1 主体落地（输入校验 helper、配置快照回滚、coreKind 改名）。 |
| 1.0 | 2025-12-26 | 初始版本 |
