# Proxy-agent
- v2ray-agent的分支，感谢原作者mack-a的贡献

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
*   **双语支持:** 提供中文和英文两个版本.
*   **可在本仓库文档中查看使用说明**

## 快速开始

### 中文版安装

```bash
wget -P /root -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

### English Version Installation

```bash
wget -P /root -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/shell/install_en.sh" && chmod 700 /root/install_en.sh && /root/install_en.sh
```

### 使用

安装后，运行以下命令可再次打开管理菜单:

```bash
pasly
```

## 语言选择 / Language Selection

| 语言 / Language | 安装脚本 / Script |
|----------------|------------------|
| 中文           | `install.sh`     |
| English        | `install_en.sh`  |

两个版本功能完全相同，仅界面语言不同。

## 文档和指南

*   请参考本仓库的 documents 目录，了解脚本功能、风险提示与使用示例。
*   For English documentation, see [English README](documents/en/README_EN.md)

## 支持

*   **反馈:** [提交 issue](https://github.com/Lynthar/Proxy-agent/issues)

## 许可证

本项根据 [AGPL-3.0 许可证](LICENSE) 授权.
