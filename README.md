# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![GitHub Release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent?label=Release)](https://github.com/Lynthar/Proxy-agent/releases)
[![English](https://img.shields.io/badge/English-README-blue)](documents/en/README_EN.md)

基于 [v2ray-agent](https://github.com/mack-a/v2ray-agent) 的分支，提供 Xray-core / sing-box 一键安装与管理。

## 功能特性

### 多核心支持
- **Xray-core** - 高性能代理核心
- **sing-box** - 新一代通用代理平台

### 支持协议
| 协议 | 传输方式 | 说明 |
|------|----------|------|
| VLESS | TCP/Vision, WebSocket, gRPC, XHTTP | 轻量级协议 |
| VMess | WebSocket, HTTPUpgrade | V2Ray 原生协议 |
| Trojan | TCP, gRPC | 伪装 HTTPS 流量 |
| Hysteria2 | QUIC | 高速 UDP 协议 |
| TUIC | QUIC | 低延迟 UDP 协议 |
| Reality | Vision, gRPC | 无需域名和证书 |
| NaiveProxy | - | 抗检测协议 |
| Shadowsocks 2022 | - | 新一代 SS 协议 |
| AnyTLS | - | 通用 TLS 协议 |

### 核心功能
- **自动 TLS** - 自动申请、续期 SSL 证书（Let's Encrypt / Buypass）
- **用户管理** - 添加、删除、查看用户配置
- **订阅生成** - 支持通用、Clash Meta、sing-box 格式
- **伪装站点** - 一键部署 Nginx 伪装网站

### 高级功能
- **分流管理** - WARP、IPv6、Socks5、DNS 分流解锁流媒体
- **CDN 节点** - 自定义 CDN 节点地址
- **链式代理** - 多级代理链路配置
- **域名黑名单** - 禁止访问指定域名
- **BT 管理** - 禁止/允许 P2P 下载

### 系统功能
- **双语界面** - 中文/英文可随时切换
- **自动更新** - 从 GitHub Releases 检测并更新
- **平滑迁移** - 自动从旧版 v2ray-agent 迁移

## 系统要求

- **操作系统**: Debian 9+, Ubuntu 16+, CentOS 7+, Alpine 3+
- **CPU 架构**: amd64, arm64
- **内存**: 512MB+
- **需要**: root 权限

## 快速开始

### 安装

```bash
wget -P /root -N https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

### 管理

安装完成后，使用以下命令打开管理菜单：

```bash
pasly
```

## 语言切换

脚本支持中英文双语，三种切换方式：

### 方式 1：菜单切换（推荐）
```bash
pasly
# 选择 21.切换语言 / Switch Language
```

### 方式 2：安装时指定
```bash
V2RAY_LANG=en bash install.sh   # 英文
V2RAY_LANG=zh bash install.sh   # 中文（默认）
```

### 方式 3：临时指定
```bash
V2RAY_LANG=en pasly   # 英文界面
V2RAY_LANG=zh pasly   # 中文界面
```

语言设置保存在 `/etc/Proxy-agent/lang_pref`，后续自动加载。

## 目录结构

```
/etc/Proxy-agent/
├── install.sh          # 主脚本
├── VERSION             # 版本号
├── lang_pref           # 语言设置
├── xray/               # Xray-core 配置和二进制
│   ├── xray
│   └── conf/
├── sing-box/           # sing-box 配置和二进制
│   ├── sing-box
│   └── conf/
├── tls/                # TLS 证书
├── subscribe/          # 订阅文件
├── lib/                # 模块库
└── shell/lang/         # 语言文件
```

## 菜单功能

```
==============================================================
1.安装/重新安装          # 一键安装代理核心
2.任意组合安装           # 自由选择协议组合
3.链式代理管理           # 配置代理链路
4.Hysteria2 管理         # Hysteria2 协议管理
5.REALITY 管理           # Reality 协议管理
6.Tuic 管理              # TUIC 协议管理
-------------------------工具管理-----------------------------
7.用户管理               # 添加/删除用户
8.伪装站管理             # 部署/更换伪装网站
9.证书管理               # TLS 证书操作
10.CDN 节点管理          # 配置 CDN 地址
11.分流工具              # WARP/DNS/IPv6 分流
12.添加新端口            # 多端口配置
13.BT 下载管理           # P2P 流量控制
15.域名黑名单            # 禁止访问域名
-------------------------版本管理-----------------------------
16.Core 管理             # 升级/切换核心
17.更新脚本              # 检查并更新脚本
18.安装 BBR              # TCP 优化
-------------------------脚本管理-----------------------------
20.卸载脚本              # 完全卸载
21.切换语言              # 中英文切换
==============================================================
```

## 迁移说明

从旧版 v2ray-agent 迁移：
- 脚本首次运行时自动检测 `/etc/v2ray-agent/`
- 自动迁移配置到 `/etc/Proxy-agent/`
- 自动更新服务文件和 crontab
- 无需手动操作

## 相关文档

- [Nginx 代理配置](documents/nginx_proxy.md)
- [性能优化指南](documents/optimize_V2Ray.md)
- [安装工具说明](documents/install_tools.md)

## 贡献

欢迎提交 Issue 和 Pull Request。

- **问题反馈**: [GitHub Issues](https://github.com/Lynthar/Proxy-agent/issues)

## 致谢

- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) - 原项目
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)

## 许可证

[AGPL-3.0](LICENSE)
