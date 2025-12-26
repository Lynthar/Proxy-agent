# Proxy-agent 开发者技术指南

本文档面向希望对 Proxy-agent 脚本进行定制化开发和修改的开发者。

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
9. [开发指南](#9-开发指南)
10. [最佳实践](#10-最佳实践)

---

## 1. 项目概述

### 1.1 技术栈

- **语言**: Bash 4.0+
- **依赖**: jq, curl, wget, openssl
- **支持的核心**: Xray-core, sing-box
- **支持的系统**: Debian/Ubuntu, CentOS/RHEL, Alpine Linux

### 1.2 架构设计原则

| 原则 | 说明 |
|------|------|
| 模块化 | 功能拆分到 lib/ 目录下的独立模块 |
| 双核心支持 | 同时支持 Xray 和 sing-box，通过抽象层统一 |
| 协议 ID 系统 | 每个协议有不可变的唯一 ID |
| 原子操作 | JSON 写入通过临时文件 + 重命名，防止损坏 |
| 优雅降级 | 多级回退机制，提高容错性 |
| 国际化优先 | 所有用户界面文本通过 i18n 系统 |

---

## 2. 目录结构

### 2.1 源码目录

```
Proxy-agent/
├── install.sh                  # 主脚本 (~15,000行)
├── VERSION                     # 版本号文件
│
├── lib/                        # 模块库
│   ├── constants.sh            # 常量定义
│   ├── utils.sh                # 通用工具函数
│   ├── json-utils.sh           # JSON 操作
│   ├── system-detect.sh        # 系统检测
│   ├── service-control.sh      # 服务管理
│   ├── protocol-registry.sh    # 协议注册
│   ├── config-reader.sh        # 配置读取
│   └── i18n.sh                 # 国际化
│
├── shell/lang/                 # 语言文件
│   ├── zh_CN.sh                # 中文
│   ├── en_US.sh                # 英文
│   └── loader.sh               # 语言加载器
│
├── docs/                       # 开发文档
│   └── design/                 # 设计文档
│
└── tests/                      # 测试
    ├── test_modules.sh
    └── test_integration.sh
```

### 2.2 运行时目录

```
/etc/Proxy-agent/
├── xray/
│   ├── xray                    # 二进制
│   └── conf/                   # 配置目录
│       ├── 00_log.json
│       ├── 02_VLESS_TCP_inbounds.json
│       └── ...
│
├── sing-box/
│   ├── sing-box                # 二进制
│   └── conf/
│       ├── config/             # 分片配置
│       │   ├── 00_log.json
│       │   └── ...
│       ├── config.json         # 合并后的配置
│       └── external_node_info.json  # 外部节点
│
├── tls/                        # 证书目录
├── subscribe/                  # 订阅文件
└── lang_pref                   # 语言偏好
```

---

## 3. 模块系统

### 3.1 模块加载顺序

模块按以下顺序加载，确保依赖关系正确：

```
1. i18n.sh          ─┐
2. constants.sh      │ 无依赖
3. utils.sh         ─┘
4. system-detect.sh ─── 依赖 utils, constants
5. service-control.sh ── 依赖 utils, system-detect
6. json-utils.sh    ─── 纯 JSON 工具
7. protocol-registry.sh ── 依赖 constants
8. config-reader.sh ─── 依赖 json-utils, protocol-registry
```

### 3.2 模块职责

| 模块 | 职责 | 核心函数 |
|------|------|---------|
| `constants.sh` | 常量定义 | 协议 ID、路径、映射表 |
| `utils.sh` | 通用工具 | `echoContent`, `randomNum`, `generateUUID` |
| `json-utils.sh` | JSON 操作 | `jsonGetValue`, `validateJsonFile` |
| `system-detect.sh` | 系统检测 | `checkSystem`, `checkCPUVendor`, `getPublicIP` |
| `service-control.sh` | 服务管理 | `handleXrayService`, `handleSingBoxService` |
| `protocol-registry.sh` | 协议管理 | `getProtocolDisplayName`, `isProtocolInstalled` |
| `config-reader.sh` | 配置读取 | `detectCoreType`, `getConfigPath` |
| `i18n.sh` | 国际化 | `t` (翻译函数) |

### 3.3 utils.sh 常用函数

```bash
# 彩色输出
echoContent red "错误信息"
echoContent green "成功信息"
echoContent yellow "警告信息"
echoContent skyBlue "标题信息"

# 随机数
randomNum 10000 30000  # 生成 10000-30000 之间的随机数
randomPort             # 生成随机端口

# UUID
generateUUID           # 生成 v4 UUID
isValidUUID "xxx"      # 验证 UUID 格式

# 版本比较
versionGreaterThan "1.2.0" "1.1.0"  # 返回 0 表示 true

# 文件操作
fileExistsAndNotEmpty "/path/to/file"
ensureDir "/path/to/dir"

# 网络
isPortInUse 443 tcp
```

---

## 4. 协议注册系统

### 4.1 协议 ID 定义

每个协议有一个**不可变的唯一 ID**：

```bash
# constants.sh
readonly PROTOCOL_VLESS_TCP_VISION=0
readonly PROTOCOL_VLESS_WS=1
readonly PROTOCOL_TROJAN_GRPC=2
readonly PROTOCOL_VMESS_WS=3
readonly PROTOCOL_TROJAN_TCP=4
readonly PROTOCOL_VLESS_GRPC=5
readonly PROTOCOL_HYSTERIA2=6
readonly PROTOCOL_VLESS_REALITY_VISION=7
readonly PROTOCOL_VLESS_REALITY_GRPC=8
readonly PROTOCOL_TUIC=9
readonly PROTOCOL_NAIVE=10
readonly PROTOCOL_VMESS_HTTPUPGRADE=11
readonly PROTOCOL_VLESS_XHTTP=12
readonly PROTOCOL_ANYTLS=13
readonly PROTOCOL_SS2022=14
readonly PROTOCOL_SOCKS5=20
```

### 4.2 协议映射

```bash
# 配置文件映射
PROTOCOL_CONFIG_FILES[0]="02_VLESS_TCP_inbounds.json"
PROTOCOL_CONFIG_FILES[1]="03_VLESS_WS_inbounds.json"
# ...

# 显示名称映射
PROTOCOL_DISPLAY_NAMES[0]="VLESS+TCP/TLS_Vision"
PROTOCOL_DISPLAY_NAMES[1]="VLESS+WS+TLS"
# ...

# TLS 要求映射
PROTOCOL_REQUIRES_TLS[0]=true
PROTOCOL_REQUIRES_TLS[7]=false  # Reality 不需要 TLS
```

### 4.3 协议查询函数

```bash
# 获取协议配置文件名
getProtocolConfigFileName 0
# 输出: 02_VLESS_TCP_inbounds.json

# 获取协议显示名称
getProtocolDisplayName 0
# 输出: VLESS+TCP/TLS_Vision

# 检查协议是否需要 TLS
protocolRequiresTLS 0
# 返回 0 表示需要

# 检查协议是否使用 Reality
protocolUsesReality 7
# 返回 0 表示使用

# 检查协议是否已安装
isProtocolInstalled 0
# 返回 0 表示已安装

# 获取所有 TLS 协议
getAllTLSProtocols
# 输出: 0 1 2 3 4 5 10 11 13

# 获取所有 UDP 协议
getAllUDPProtocols
# 输出: 6 9
```

### 4.4 协议状态跟踪

安装的协议以逗号分隔字符串存储：

```bash
# 全局变量
currentInstallProtocolType=",0,1,7,"

# 检查协议是否在选择中
isProtocolSelected ",0,1,7," 0  # 返回 0

# 添加协议到选择
addProtocolToSelection ",0,1," 7  # 输出 ",0,1,7,"
```

---

## 5. i18n 国际化系统

### 5.1 使用方法

```bash
# 在代码中使用
echoContent yellow "$(t MENU_INSTALL)"

# 带参数
echoContent green "$(t PROGRESS_STEP "$current" "$total")"
```

### 5.2 添加新翻译

1. 在 `shell/lang/zh_CN.sh` 添加：
```bash
MSG_NEW_MESSAGE="新消息内容"
```

2. 在 `shell/lang/en_US.sh` 添加：
```bash
MSG_NEW_MESSAGE="New message content"
```

3. 在代码中使用：
```bash
echoContent yellow "$(t NEW_MESSAGE)"
```

### 5.3 语言文件结构

```bash
# shell/lang/zh_CN.sh

# 系统消息
MSG_SYS_CHECKING="正在检查..."
MSG_SYS_COMPLETE="完成"

# 菜单项
MSG_MENU_INSTALL="安装"
MSG_MENU_UNINSTALL="卸载"

# 进度
MSG_PROGRESS_STEP="进度 %s/%s"

# 错误
MSG_ERR_ROOT_REQUIRED="需要 root 权限"

# 链式代理
MSG_CHAIN_MENU_WIZARD="快速配置向导"

# 外部节点
MSG_EXT_MENU_TITLE="外部节点管理"
```

### 5.4 翻译键命名规范

| 前缀 | 用途 | 示例 |
|------|------|------|
| `MSG_SYS_` | 系统消息 | `MSG_SYS_CHECKING` |
| `MSG_MENU_` | 菜单项 | `MSG_MENU_INSTALL` |
| `MSG_ERR_` | 错误消息 | `MSG_ERR_PORT_INVALID` |
| `MSG_CHAIN_` | 链式代理 | `MSG_CHAIN_MENU_WIZARD` |
| `MSG_EXT_` | 外部节点 | `MSG_EXT_ADD_SS` |
| `MSG_SCRIPT_` | 脚本版本 | `MSG_SCRIPT_BACKUP_SUCCESS` |

---

## 6. 配置文件系统

### 6.1 配置文件命名规范

```
XX_PROTOCOL_inbounds.json
│  │
│  └── 协议/功能名称
└── 序号 (决定加载顺序)
```

常用序号分配：
- `00`: 日志配置
- `01`: API 配置
- `02-14`: 协议入站配置
- `20+`: 特殊功能 (SOCKS5等)

### 6.2 Xray 配置结构

Xray 使用 `-confdir` 自动合并多个 JSON 文件：

```json
// 02_VLESS_TCP_inbounds.json
{
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {"id": "uuid-here", "flow": "xtls-rprx-vision"}
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {...}
            }
        }
    ]
}
```

### 6.3 sing-box 配置结构

sing-box 需要合并为单一配置文件：

```json
// 合并前: conf/config/06_hysteria2_inbounds.json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "tag": "hysteria2-in",
            "listen": "::",
            "listen_port": 443,
            "users": [
                {"password": "xxx"}
            ],
            "tls": {...}
        }
    ]
}

// 合并后: conf/config.json
{
    "log": {...},
    "inbounds": [...],  // 所有入站合并
    "outbounds": [...], // 所有出站合并
    "route": {...}      // 路由规则合并
}
```

### 6.4 配置合并函数

```bash
# sing-box 配置合并
singBoxMergeConfig() {
    # 1. 读取所有 conf/config/*.json
    # 2. 使用 jq 合并
    # 3. 验证语法
    # 4. 写入 conf/config.json
}

# 在服务启动前自动调用
handleSingBoxService start
  → singBoxMergeConfig
  → sing-box run -c conf/config.json
```

---

## 7. 服务管理系统

### 7.1 服务控制抽象

```bash
# 统一接口
serviceControl "serviceName" "action"

# 自动检测 init 系统
# systemd (Debian/Ubuntu/CentOS):
#   systemctl start xray.service
# OpenRC (Alpine):
#   rc-service xray start
```

### 7.2 Xray 服务管理

```bash
handleXrayService start    # 启动
handleXrayService stop     # 停止
handleXrayService restart  # 重启
handleXrayService status   # 状态
```

### 7.3 sing-box 服务管理

```bash
handleSingBoxService start    # 合并配置 + 启动
handleSingBoxService stop     # 停止
handleSingBoxService restart  # 合并配置 + 重启
handleSingBoxService status   # 状态
```

### 7.4 防火墙管理

```bash
# 开放端口
allowPort 443 tcp

# 自动检测防火墙类型
# UFW: ufw allow 443/tcp
# Firewalld: firewall-cmd --permanent --add-port=443/tcp
# iptables: iptables -I INPUT -p tcp --dport 443 -j ACCEPT
```

---

## 8. 链式代理系统

### 8.1 架构概述

```
用户 → 入口节点 → [中继节点...] → 出口节点 → 互联网
         │              │              │
     可控 (root)    可控 (root)    可控或外部
```

### 8.2 节点角色

| 角色 | 职责 | 配置文件 |
|------|------|---------|
| 出口节点 | 接收流量，直连互联网 | `chain_exit_info.json` |
| 中继节点 | 转发流量到下游 | `chain_relay_info.json` |
| 入口节点 | 接收用户流量，转发到链路 | `chain_entry_info.json` |

### 8.3 配置码格式

```bash
# V1 格式 (单跳)
chain://ss2022@IP:PORT?key=BASE64_KEY&method=2022-blake3-aes-128-gcm#NAME

# V2 格式 (多跳)
chain://v2@BASE64_ENCODED_JSON_ARRAY
```

### 8.4 多链路分流

```bash
# chain_multi_info.json
{
    "role": "entry",
    "mode": "multi_chain",
    "chains": [
        {
            "name": "chain_us",
            "ip": "us.example.com",
            "port": 5000,
            "method": "2022-blake3-aes-128-gcm",
            "password": "xxx",
            "is_default": true
        },
        {
            "name": "chain_hk",
            "ip": "hk.example.com",
            "port": 5001,
            ...
        }
    ],
    "rules": [
        {"type": "preset", "value": "streaming", "chain": "chain_us"},
        {"type": "preset", "value": "ai", "chain": "chain_hk"}
    ]
}
```

### 8.5 外部节点系统

外部节点允许使用无 root 权限的拼车节点：

```bash
# external_node_info.json
{
    "nodes": [
        {
            "id": "ext_xxx",
            "name": "US-SS-Node",
            "type": "shadowsocks",
            "server": "us.example.com",
            "server_port": 8388,
            "method": "aes-256-gcm",
            "password": "xxx"
        },
        {
            "id": "ext_yyy",
            "name": "HK-Trojan",
            "type": "trojan",
            "server": "hk.example.com",
            "server_port": 443,
            "password": "xxx",
            "tls": {
                "enabled": true,
                "server_name": "hk.example.com"
            }
        }
    ]
}
```

支持的协议：
- Shadowsocks (包括 SS2022)
- SOCKS5
- Trojan

---

## 9. 开发指南

### 9.1 添加新协议

**步骤 1: 定义协议 ID**

```bash
# constants.sh
readonly PROTOCOL_NEW_PROTO=15
```

**步骤 2: 添加映射**

```bash
# constants.sh
PROTOCOL_CONFIG_FILES[15]="15_NEW_PROTO_inbounds.json"
PROTOCOL_DISPLAY_NAMES[15]="New Protocol"
PROTOCOL_REQUIRES_TLS[15]=true
```

**步骤 3: 添加到 protocol-registry.sh**

```bash
getProtocolConfigFileName() {
    case "$1" in
        15) echo "15_NEW_PROTO_inbounds.json" ;;
        ...
    esac
}

getProtocolDisplayName() {
    case "$1" in
        15) echo "New Protocol" ;;
        ...
    esac
}
```

**步骤 4: 创建协议处理函数**

```bash
# install.sh
handleNewProto() {
    local port=$1
    local uuid=$2

    # 创建入站配置
    cat > /etc/Proxy-agent/xray/conf/15_NEW_PROTO_inbounds.json <<EOF
{
    "inbounds": [...]
}
EOF

    # 重启服务
    handleXrayService restart
}
```

**步骤 5: 添加到安装流程**

```bash
# 在协议选择菜单中添加
echoContent yellow "15. New Protocol"

# 在处理逻辑中添加
case "$protocol" in
    15) handleNewProto "$port" "$uuid" ;;
esac
```

### 9.2 添加新菜单功能

```bash
# 命名规范: [action][feature]Menu
newFeatureMenu() {
    echoContent skyBlue "\n$(t NEW_FEATURE_TITLE)"
    echoContent red "=============================================================="

    # 显示选项
    echoContent yellow "1. $(t OPTION_1)"
    echoContent yellow "2. $(t OPTION_2)"
    echoContent yellow "0. $(t BACK)"

    # 读取输入
    read -r -p "$(t PROMPT_SELECT): " choice

    # 处理选择
    case "$choice" in
        1) handleOption1 ;;
        2) handleOption2 ;;
        0) parentMenu ;;
        *) newFeatureMenu ;;  # 无效输入，重新显示
    esac
}
```

### 9.3 添加新语言支持

**步骤 1: 创建语言文件**

```bash
# shell/lang/ja_JP.sh
#!/usr/bin/env bash
MSG_SYS_CHECKING="確認中..."
MSG_MENU_INSTALL="インストール"
# ...
```

**步骤 2: 修改 i18n.sh**

```bash
_detect_language() {
    # 添加日语检测
    case "${LANG:-}" in
        ja_JP*) echo "ja_JP" ;;
        zh_CN*) echo "zh_CN" ;;
        *) echo "en_US" ;;
    esac
}
```

### 9.4 测试

```bash
# 语法检查
bash -n install.sh

# 运行单元测试
bash tests/test_modules.sh

# 运行集成测试
bash tests/test_integration.sh
```

---

## 10. 最佳实践

### 10.1 编码规范

```bash
# 函数命名: 动词 + 名词，驼峰式
handleXrayService()
parseChainCode()
generateExternalOutbound()

# 变量命名: 驼峰式
currentInstallProtocolType
chainExitIP

# 常量命名: 大写下划线
PROTOCOL_VLESS_TCP_VISION
PROXY_AGENT_DIR

# 局部变量声明
local variableName="value"
```

### 10.2 错误处理

```bash
# 检查命令执行结果
if ! someCommand; then
    echoContent red " ---> 操作失败"
    return 1
fi

# 检查文件存在
if [[ ! -f "${configFile}" ]]; then
    echoContent red " ---> 配置文件不存在"
    return 1
fi

# 验证用户输入
if [[ -z "${userInput}" ]]; then
    echoContent red " ---> 输入不能为空"
    return 1
fi
```

### 10.3 JSON 安全操作

```bash
# 使用临时文件 + 原子替换
local tempFile="${configFile}.tmp"

jq '.key = "value"' "${configFile}" > "${tempFile}"

# 验证语法
if jq . "${tempFile}" > /dev/null 2>&1; then
    mv "${tempFile}" "${configFile}"
else
    rm -f "${tempFile}"
    echoContent red " ---> JSON 语法错误"
    return 1
fi
```

### 10.4 用户交互

```bash
# 提供默认值
read -r -p "请输入端口 [443]: " port
port="${port:-443}"

# 确认危险操作
read -r -p "确认删除? [y/N]: " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    return 0
fi

# 使用 i18n
read -r -p "$(t PROMPT_SELECT): " choice
```

### 10.5 服务操作

```bash
# 修改配置后重启
modifyConfig() {
    # ... 修改配置 ...

    # 重启对应服务
    local coreType
    coreType=$(detectCoreType)

    if [[ "${coreType}" == "1" ]]; then
        handleXrayService restart
    elif [[ "${coreType}" == "2" ]]; then
        handleSingBoxService restart
    fi
}
```

### 10.6 向后兼容

```bash
# 检查旧版本配置
if [[ -f "/old/path/config.json" ]]; then
    # 迁移到新位置
    mv "/old/path/config.json" "/new/path/config.json"
fi

# 保留旧函数名作为别名
oldFunctionName() {
    newFunctionName "$@"
}
```

---

## 附录 A: 函数速查表

### 系统检测

| 函数 | 用途 |
|------|------|
| `checkSystem` | 检测操作系统 |
| `checkCPUVendor` | 检测 CPU 架构 |
| `checkRoot` | 检查 root 权限 |
| `getPublicIP` | 获取公网 IP |
| `detectCoreType` | 检测已安装的核心 |

### 协议管理

| 函数 | 用途 |
|------|------|
| `getProtocolDisplayName ID` | 获取协议显示名称 |
| `isProtocolInstalled ID` | 检查协议是否已安装 |
| `protocolRequiresTLS ID` | 检查协议是否需要 TLS |
| `getAllTLSProtocols` | 获取所有 TLS 协议 |

### 服务管理

| 函数 | 用途 |
|------|------|
| `handleXrayService ACTION` | Xray 服务控制 |
| `handleSingBoxService ACTION` | sing-box 服务控制 |
| `reloadAllCores` | 重启所有运行中的服务 |
| `allowPort PORT PROTO` | 开放防火墙端口 |

### 工具函数

| 函数 | 用途 |
|------|------|
| `echoContent COLOR TEXT` | 彩色输出 |
| `randomNum MIN MAX` | 生成随机数 |
| `generateUUID` | 生成 UUID |
| `t KEY` | 获取翻译文本 |

---

## 附录 B: 配置文件模板

### Xray VLESS 入站

```json
{
    "inbounds": [
        {
            "port": 443,
            "listen": "0.0.0.0",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/etc/Proxy-agent/tls/xxx.crt",
                            "keyFile": "/etc/Proxy-agent/tls/xxx.key"
                        }
                    ]
                }
            }
        }
    ]
}
```

### sing-box Hysteria2 入站

```json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "tag": "hysteria2-in",
            "listen": "::",
            "listen_port": 443,
            "users": [
                {
                    "password": "PASSWORD"
                }
            ],
            "tls": {
                "enabled": true,
                "certificate_path": "/etc/Proxy-agent/tls/xxx.crt",
                "key_path": "/etc/Proxy-agent/tls/xxx.key"
            }
        }
    ]
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

## 附录 C: 常见问题

### Q: 如何调试脚本?

```bash
# 启用调试模式
bash -x install.sh

# 仅检查语法
bash -n install.sh
```

### Q: 如何查看服务日志?

```bash
# Xray
tail -f /etc/Proxy-agent/xray/error.log

# sing-box
tail -f /etc/Proxy-agent/sing-box/box.log

# systemd 日志
journalctl -u xray -f
journalctl -u sing-box -f
```

### Q: 配置修改后不生效?

```bash
# 确保重启服务
handleXrayService restart
# 或
handleSingBoxService restart

# 对于 sing-box，确保配置已合并
singBoxMergeConfig
```

---

## 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|---------|
| 1.0 | 2025-12-26 | 初始版本 |
