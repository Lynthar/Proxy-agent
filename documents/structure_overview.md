# Proxy-agent 文件与目录结构概览

本项目提供 Xray-core/sing-box 的一键安装与运维脚本。下文按目录梳理主要文件及其职责，便于快速理解代码布局与功能特点。

## 根目录
- `install.sh`：中文版主安装脚本，负责系统/CPU 检测、依赖安装、核心选择、协议配置、证书与订阅管理等完整生命周期的菜单化操作。
- `README.md`：项目简介与快速开始说明，概述多核心、多协议、TLS 自动化与分流等特性，并给出安装命令与文档链接。
- `LICENSE`：AGPL-3.0 许可协议文本。

## shell/
- `install_en.sh`：英文版安装脚本，逻辑与 `install.sh` 相似，涵盖系统检测、CPU 架构适配、核心版本与多协议部署等流程，便于英文环境使用。
- `init_tls.sh`：辅助 TLS 证书初始化脚本，自动安装 acme.sh、nginx、socat，备份/恢复 nginx 配置并引导输入域名签发证书。
- `ufw_remove.sh`：快捷关闭 UFW、防火墙放行的脚本，停止并禁用 ufw，清空规则后添加基本 ACCEPT 策略。
- `empty_login_history.sh`：清理服务器登录/历史日志的脚本，重置 wtmp、btmp、lastlog 与 bash_history。
- `send_email.sh`：公网 IP 变更通知脚本，比较当前 IP 与历史记录，变化时通过 mail 命令发送邮件提醒。

## documents/
- `README_EN.md`：英文版项目说明，内容与根目录 README 对应。
- `install_tools.md`：安装所需工具与环境注意事项的文档。
- `nginx_proxy.md`：Nginx 反向代理示例与配置指引。
- `optimize_V2Ray.md`：V2Ray 性能优化建议与调优参数汇总。
- `sing-box.json`：示例 sing-box 配置文件。
- `donation.md`、`donation_aff.md`：项目捐赠与联盟推广说明。
- `en/`：英文文档子目录，包含与中文主文档对应的英文版本。

## fodder/
- `blog/`、`donation/`、`install/`：素材文件目录，存放博客、捐赠与安装相关的配图资源（如 `install.jpg`）。

## 技术特点与组织方式
- **脚本为核心**：安装/管理逻辑主要集中在 Bash 脚本中，以函数化方式封装系统检测、依赖安装、核心下载与配置生成等步骤，减少外部依赖。
- **多协议/多核心支持**：脚本中根据 CPU 架构选择对应的 Xray-core、sing-box 等发行版，涵盖 VLESS、VMess、Trojan、Hysteria2、Tuic、NaiveProxy 等协议的端口与配置管理。
- **自动化与安全辅助**：提供 TLS 申请、Nginx 代理初始化、订阅生成、日志清理、防火墙重置、IP 变更通知等配套脚本，便于无人值守与安全加固。
- **文档与素材分层**：安装与优化文档集中于 `documents/`，示例配置与图像资源存放在 `fodder/`，便于与脚本逻辑解耦。
