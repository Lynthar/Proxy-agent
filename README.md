# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![GitHub Release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent?label=Release)](https://github.com/Lynthar/Proxy-agent/releases)
[![Tests](https://img.shields.io/badge/Tests-passing-brightgreen)]()
[![English](https://img.shields.io/badge/English-README-blue)](README.en.md)

Xray-core / sing-box 多协议代理一键安装脚本。基于 [v2ray-agent](https://github.com/mack-a/v2ray-agent) 修改而来，感谢 @mack-a 的贡献。

## 快速安装

```bash
wget -P /root -N https://github.com/Lynthar/Proxy-agent/releases/latest/download/install.sh && chmod 700 /root/install.sh && /root/install.sh
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
- 系统诊断（`pasly doctor`）+ dry-run 计划模式（`pasly --dry-run`）
- 中英双语，支持菜单切换与环境变量覆盖

## 系统要求

- **系统**：Debian 9+、Ubuntu 18+、CentOS/RHEL 8+、Alpine 3+（Ubuntu 16 已被脚本明确拒绝）
- **架构**：amd64、arm64
- **内存**：512 MB+
- **权限**：root
- **Bash**：≥ 4.3（脚本用到 nameref 与负数组下标 `${arr[-1]}`；CentOS 7 自带的 bash 4.2 不受支持）
- **sing-box**：≥ 1.11（脚本默认拉最新版自动满足；本脚本配置使用 1.11 引入的路由级 sniff/resolve action）

## 语言切换

```bash
pasly                     # 菜单内选择 21
V2RAY_LANG=en pasly       # 环境变量临时覆盖
```

选择会持久化到 `/etc/Proxy-agent/lang_pref`，之后每次运行自动加载。

## 目录结构

```
/etc/Proxy-agent/
├── install.sh          # 主脚本
├── VERSION
├── lang_pref           # 语言偏好
├── backup/             # 版本化备份（脚本 + 配置快照）
├── xray/               # Xray-core 二进制与 conf/
├── sing-box/           # sing-box 二进制与 conf/
├── tls/                # TLS 证书
├── subscribe/          # 订阅文件
├── lib/                # 共用 shell 模块
└── shell/lang/         # 语言文件
```

## 菜单地图

```
==============================================================
1. 安装 / 重新安装            选核心 + 完整安装
2. 任意组合安装               自选协议组合
3. 链式代理管理               入口 / 中继 / 出口 / 多链路
4. Hysteria2 管理
5. REALITY 管理
6. Tuic 管理
7. 用户管理                   增删 / 查看 / 订阅
8. 伪装站管理                 Nginx 伪装站部署
9. 证书管理                   Let's Encrypt / Buypass
11. 分流工具                  WARP / IPv6 / SOCKS5 / DNS
12. 添加新端口
16. Core 管理                 升级 / 切换
17. 更新脚本                  SHA256 校验，失败自动回滚
18. 安装 BBR、DD 脚本
19. 一键无域名 Reality 安装
20. 卸载脚本
21. 切换语言
22. 脚本版本管理              备份 / 回滚 / 列出快照
23. 系统诊断（只读）
==============================================================
```

10 / 13 / 14 / 15 是移除或隐藏菜单留下的空号，有意保留。

子命令也可直接用（不进菜单，跑完即退出）：

```bash
pasly doctor          # 等同菜单 23
pasly --dry-run       # 计划模式：安装 / 卸载 / 链式代理只打印不执行
DRY_RUN=1 pasly       # 同 --dry-run
```

## 文档

- [使用指南](docs/user-guide.md)
- [SELinux 说明](docs/selinux.md)
- [English README](README.en.md)

## 参与贡献

欢迎在 [GitHub](https://github.com/Lynthar/Proxy-agent) 提 issue 与 pull request。

## 致谢

- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)

## 许可证

[AGPL-3.0](LICENSE)
