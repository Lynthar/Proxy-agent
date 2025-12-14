# Proxy-agent

基于 v2ray-agent 的分支，感谢原作者 mack-a 的贡献

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![English Version](https://img.shields.io/badge/English-Version-blue)](documents/en/README_EN.md)

Xray-core/sing-box 一键脚本快速安装

## 功能

*   **多核心支持:** 支持 Xray-core 和 sing-box.
*   **多协议支持:** 支持 VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy 等多种协议.
*   **自动TLS:** 自动申请和续订 SSL 证书.
*   **易于管理:** 提供简单的菜单来管理用户、端口和配置.
*   **订阅支持:** 生成和管理订阅链接.
*   **分流管理:** 提供wireguard、IPv6、Socks5、DNS、VMess(ws)、SNI反向代理，可用于解锁流媒体、规避IP验证等作用.
*   **目标域名管理:** 提供域名黑名单管理，可用于禁止访问指定网站.
*   **BT下载管理:** 可用于禁止下载P2P相关内容.
*   **双语支持:** 支持中文和英文界面，可随时切换.

## 快速开始

### 安装

```bash
wget -P /root -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

### 使用

安装后，运行以下命令可再次打开管理菜单:

```bash
pasly
```

## 语言选择 / Language Selection

脚本支持中文和英文两种语言，有以下几种切换方式：

### 方式1：在管理菜单中切换（推荐）

```bash
pasly
# 选择菜单项 21.切换语言 / Switch Language
```

### 方式2：首次安装时指定语言

```bash
# 安装英文版
V2RAY_LANG=en bash install.sh

# 安装中文版（默认）
V2RAY_LANG=zh bash install.sh
```

### 方式3：临时使用指定语言

```bash
V2RAY_LANG=en pasly   # 英文界面
V2RAY_LANG=zh pasly   # 中文界面
```

语言设置会被持久保存到 `/etc/Proxy-agent/lang_pref`，后续使用 `pasly` 时会自动加载。

## 安装目录

脚本安装后的配置目录：`/etc/Proxy-agent/`

## 从旧版本迁移

如果你之前使用的是 `/etc/v2ray-agent/` 目录，脚本会在首次运行时自动迁移到 `/etc/Proxy-agent/`，无需手动操作。

## 文档和指南

*   请参考本仓库的 documents 目录，了解脚本功能、风险提示与使用示例。
*   For English documentation, see [English README](documents/en/README_EN.md)

## 支持

*   **反馈:** [提交 issue](https://github.com/Lynthar/Proxy-agent/issues)

## 许可证

本项根据 [AGPL-3.0 许可证](LICENSE) 授权.
