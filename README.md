# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![GitHub Release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent?label=Release)](https://github.com/Lynthar/Proxy-agent/releases)
[![Tests](https://img.shields.io/badge/Tests-68%20passed-brightgreen)]()
[![English](https://img.shields.io/badge/English-README-blue)](documents/en/README_EN.md)

Xray-core / sing-box 多协议代理一键安装脚本，基于 [v2ray-agent](https://github.com/mack-a/v2ray-agent) 修改而来，感谢mack-a的贡献。

## 快速安装

```bash
wget -P /root -N https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

安装后使用 `pasly` 命令打开管理菜单。

## 支持协议

| 协议 | 传输方式 | TLS | 说明 |
|------|----------|-----|------|
| VLESS | TCP/Vision, WS, XHTTP | TLS/Reality | 推荐 |
| VMess | WebSocket, HTTPUpgrade | TLS | CDN 友好 |
| Trojan | TCP | TLS | 伪装 HTTPS |
| Hysteria2 | QUIC | 自签名 | 高速 UDP |
| TUIC | QUIC | TLS | 低延迟 UDP |
| NaiveProxy | HTTP/2 | TLS | 抗检测 |
| Shadowsocks 2022 | - | - | 链式代理 |

### 主要改进

- 模块化设计：constants, utils, json-utils, system-detect, service-control, protocol-registry, config-reader, i18n
- 统一的协议注册表和配置读取接口
- 原子化 JSON 操作，防止配置损坏
- 添加i18n，中英双语
- Reality shortIds 改为随机生成，移除空值
- 移除部分冗余文件并精简部分代码
- 添加完整的单元测试和集成测试
- 统一错误处理和日志输出

## 功能列表

```
1.安装/重新安装        2.任意组合安装        3.链式代理管理
4.Hysteria2 管理       5.REALITY 管理        6.TUIC 管理
7.用户管理             8.伪装站管理          9.证书管理
10.CDN 节点管理        11.分流工具           12.添加新端口
13.BT 下载管理         15.域名黑名单         16.Core 管理
17.更新脚本            18.安装 BBR           20.卸载脚本
21.切换语言
```

## 系统要求

- **系统**: Debian 9+, Ubuntu 16+, CentOS 7+, Alpine 3+
- **架构**: amd64, arm64
- **权限**: root

## 目录结构

```
/etc/Proxy-agent/
├── xray/conf/      # Xray 配置
├── sing-box/conf/  # sing-box 配置
├── tls/            # 证书
├── subscribe/      # 订阅
├── lib/            # 模块库
└── shell/lang/     # 语言文件
```

## 语言切换

```bash
# 菜单切换 (推荐)
pasly  # 选择 21

# 环境变量
V2RAY_LANG=en pasly
```

## 致谢

- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)

## 许可证

[AGPL-3.0](LICENSE)
