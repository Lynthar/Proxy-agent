# Proxy-agent

[![license](https://img.shields.io/github/license/Lynthar/Proxy-agent)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/Lynthar/Proxy-agent/ci.yml?branch=master&label=CI)](https://github.com/Lynthar/Proxy-agent/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent)](https://github.com/Lynthar/Proxy-agent/releases)

Xray-core / sing-box 多协议一键安装与管理脚本；链式代理支持入口/中继/出口多跳与多链路分流

简体中文 | [English](README.en.md)

装完输入 `pasly` 进菜单，然后根据提示进行下一步。该脚本同时带 Xray-core 和 sing-box 两个内核。

我专门加强了**链式代理**：可以用入口机、中继机、出口机连成多跳；一台机器上可以挂多条链路
分流；也能把手上现成的第三方 SS / Trojan / SOCKS5 节点直接当出口接进来。其余的包括伪装站、
证书申请、订阅生成、WARP 分流、脚本自更新和版本回滚。中英双语。

## 安装

需要 root，bash ≥ 4.3，amd64 或 arm64。

```bash
wget -P /root -N https://github.com/Lynthar/Proxy-agent/releases/latest/download/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

Alpine 需要先 `apk add bash wget`。

首次运行时脚本会自己去 release 拉 `lib_bundle.tar.gz`，校验 SHA256 后原子落位；
校验不过就什么都不动。想读完代码再运行，也可以直接 clone，`lib/` 和 `install.sh` 同级时
不触发这段自举：

```bash
git clone https://github.com/Lynthar/Proxy-agent.git
cd Proxy-agent && sudo ./install.sh
```

## 用法

输入 `pasly` 回车后看到的是这个菜单：

```
==============================================================
作者: Lynthar
当前版本: v1.3.7
Github: https://github.com/Lynthar/Proxy-agent
描述: 八合一共存脚本
1.安装
2.任意组合安装
3.链式代理管理
4.Hysteria2 管理
5.REALITY 管理
6.Tuic 管理
-------------------------工具管理-----------------------------
7.用户管理
8.伪装站管理
9.证书管理
11.分流工具
12.添加新端口
-------------------------版本管理-----------------------------
16.Core 管理
17.更新脚本
18.安装 BBR、DD 脚本
19.一键无域名 Reality 安装
-------------------------脚本管理-----------------------------
20.卸载脚本
21.切换语言 / Switch Language
22.脚本版本管理
23.系统诊断（只读）
==============================================================
```

由于历史原因，10 / 13 / 14 / 15 是移除或隐藏的菜单留下的空号。

三条不进菜单、执行完就退出的子命令：

```bash
pasly doctor       # 只读诊断，这条不需要 root
pasly --dry-run    # 计划模式：安装 / 卸载 / 链式代理只打印不执行（等价 -n）
V2RAY_LANG=en pasly
```

## 协议

13 个在用协议：

| 类别 | 协议 |
|---|---|
| VLESS | TCP/Vision · WS · Reality Vision · XHTTP |
| VMess | WS · HTTPUpgrade |
| 其它 | Trojan TCP · Hysteria2 · TUIC · NaiveProxy · AnyTLS · Shadowsocks 2022 · SOCKS5 |

链式代理里，Xray 与 sing-box 可以混合出站，第三方节点也能接进来当出口。链式的每一跳是
sing-box 的 shadowsocks 出站，还开了 sing-box 特有的 h2mux 多路复用；所以入站走 Xray 时，
流量会在本机转交给 sing-box 再出站。

## 配置

没有单一配置文件——配置由菜单交互生成，落在 `/etc/Proxy-agent/` 下（`xray/conf/`、
`sing-box/conf/config/`、`tls/`、`subscribe/`、`backup/`）。

七个环境变量：

| 变量 | 作用 |
|---|---|
| `V2RAY_LANG` | 临时切语言（`en` / `zh`），优先于持久化的 `lang_pref` |
| `DRY_RUN=1` | 计划模式，等价 `--dry-run` |
| `PROXY_AGENT_DIR` | 安装根目录，默认 `/etc/Proxy-agent` |
| `PROXY_AGENT_NO_BOOTSTRAP` | 禁用 `lib/` 自举下载 |
| `PROXY_AGENT_BOOTSTRAP_REF` / `_MODE` | 自举拉取的 ref 与模式 |
| `PROXY_AGENT_SELINUX_NONFATAL` | SELinux enforcing 下不退出 |

## 能力边界

- **它不是面板。** 纯 TTY 菜单，没有 Web UI、没有 API，也不统计流量、到期或多用户配额。
- **三个 gRPC 变体已废弃**：Trojan gRPC、VLESS gRPC、VLESS vision gRPC 仍在注册表里
  但标了废弃，别在新部署上用。
- **CentOS 7 装不了。** 它的 bash 是 4.2.46，达不到脚本开头要求的 4.3——脚本用了
  nameref 和负数组下标，在 4.2 上会静默出错，所以直接拒绝运行。
- **卸载不回收防火墙规则。** 端口的 allow 规则会留着，虽然那时已经没有东西在监听。
- **批量导入几百个用户会明显变慢。** 二十来个用户感觉不到；实测 400 用户约 4.7 秒、
  800 用户约 10 秒。
- **英文界面可能不完整。** 双语键是对齐的，但有些交互路径（比如自定义内核安装那几段）
  仍会出现中文。

## 与上游的区别

上游是 [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)。这个 fork 在它
基础上加的是：链式代理与第三方节点接入、`doctor` 只读诊断、`--dry-run` 计划模式、
脚本版本快照与回滚、自更新与自举的 SHA256 校验、双语界面，以及 CI 门禁。

## 文档

- [用户指南](docs/user-guide.md) —— 快捷命令、功能速查、故障排查、常见问题。
- [SELinux 说明](docs/selinux.md) —— enforcing 模式下脚本会退出并指到这里。

## 安全

这是个以 root 运行、改 systemd 和防火墙、还会自己更新自己的脚本。

**自更新和自举都校验 SHA256**，失配就从 `backup/` 恢复旧脚本，或者干脆不动目标位置。

**它会替你装几样第三方组件**：acme.sh 走官方安装方式，BBR 走第三方脚本，Xray 和
sing-box 的二进制从各自 GitHub release 拉。这些都没有钉版本。伪装站素材是从 GitHub
archive 取的 zip，没有校验——它是纯静态文件、不进执行链。

**SELinux enforcing 下脚本会直接退出**并指向 `docs/selinux.md`，这是有意的。

目前没有私密的漏洞报告渠道，敏感问题请不要发公开 issue。

## 许可证

GNU Affero 通用公共许可证 v3.0 —— 见 [LICENSE](LICENSE)。上游 mack-a/v2ray-agent 同为 AGPL-3.0。
