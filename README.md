# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![GitHub Release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent?label=Release)](https://github.com/Lynthar/Proxy-agent/releases)
[![Tests](https://img.shields.io/badge/Tests-passing-brightgreen)]()
[![English](https://img.shields.io/badge/English-README-blue)](documents/en/README_EN.md)

Xray-core / sing-box 多协议代理一键安装脚本。基于 [v2ray-agent](https://github.com/mack-a/v2ray-agent) 修改而来，感谢 @mack-a 的贡献。

## 快速安装

```bash
wget -P /root -N https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

> **Alpine 用户请先执行 `apk add bash wget`**（脚本依赖 bash）。

安装完成后使用 `pasly` 命令打开管理菜单。

## 支持协议

| 协议 | 传输 | 说明 |
|---|---|---|
| VLESS | TCP/Vision · WS · XHTTP · Reality | 推荐 |
| VMess | WS · HTTPUpgrade | CDN 友好 |
| Trojan | TCP | HTTPS 伪装 |
| Hysteria2 | QUIC | 高速 UDP |
| TUIC | QUIC | 低延迟 UDP |
| NaiveProxy | HTTP/2 | 抗检测 |
| AnyTLS · Shadowsocks 2022 | — | 通用 |

## 主要特性

- 双核心支持（Xray-core / sing-box），自动识别与切换
- 链式代理：支持出口/中继/入口多跳，多链路分流，Xray + sing-box 混合出站
- 外部节点：可将第三方 SS/Trojan/SOCKS5 节点接入链式代理作为出口
- 原子化 JSON 写入 + 配置快照式备份与回滚
- 自更新 SHA256 校验 + 失败自动回滚
- 中英双语，支持菜单切换与环境变量覆盖

## 系统要求

- **系统**：Debian 9+、Ubuntu 16+、CentOS 7+、Alpine 3+
- **架构**：amd64、arm64
- **权限**：root
- **sing-box**：≥ 1.11（脚本默认拉最新版自动满足；本脚本配置使用 1.11 引入的路由级 sniff/resolve action）

## 语言切换

```bash
pasly                     # 菜单内选择 21
V2RAY_LANG=en pasly       # 环境变量临时覆盖
```

## 文档

- [使用指南](documents/user-guide.md)
- [开发指南](documents/developer-guide.md)
- [English README](documents/en/README_EN.md)

## 致谢

- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)

## 许可证

[AGPL-3.0](LICENSE)
