---
name: Bug 反馈 / Bug report
about: 提交脚本或安装过程中遇到的错误
title: '[bug] '
labels: bug
assignees: ''
---

> 提交前请先查看 [README](../../README.md) 与 [使用指南](../../docs/user-guide.md)。

## 1. 问题描述

请清晰描述遇到的问题与复现步骤。例：
> 在 `pasly` 主菜单选 1 → 选择 sing-box → 输入域名 example.com → 在"申请 TLS 证书"步骤报错。

## 2. 重现步骤

```
1. ...
2. ...
3. ...
```

## 3. 错误日志

> 粘贴 install.sh 输出的红字部分，或对应核心日志：
> - Xray: `tail -100 /etc/Proxy-agent/xray/error.log`
> - sing-box: `tail -100 /etc/Proxy-agent/sing-box/box.log`（或 `journalctl -u sing-box -n 100`）

```
请粘贴日志
```

## 4. 环境信息

- 脚本版本（运行 `pasly` 后顶部显示，或 `cat /etc/Proxy-agent/VERSION`）：
- 系统：（例 Ubuntu 22.04 / Debian 12 / Alpine 3.19 / CentOS 9）
- 架构：（amd64 / arm64）
- 核心：（Xray-core / sing-box，附版本号）
- 协议：（VLESS+Reality / Hysteria2 / 链式代理 / ...）

## 5. 已尝试的处理

- [ ] 已查看错误日志
- [ ] 已尝试重启服务（菜单 16）
- [ ] 已尝试更新脚本（菜单 17）
- [ ] 已尝试备份回滚（菜单 22）
