# SELinux 配置指南 / SELinux Configuration Guide

## 问题说明 / Problem Description

SELinux (Security-Enhanced Linux) 在 CentOS/RHEL/Fedora 等系统上默认启用，可能会阻止代理服务正常运行。

SELinux is enabled by default on CentOS/RHEL/Fedora systems and may prevent proxy services from running properly.

## 检查 SELinux 状态 / Check SELinux Status

```bash
# 查看当前状态 / Check current status
getenforce

# 或者 / Or
sestatus
```

输出说明 / Output explanation:
- `Enforcing` - SELinux 正在强制执行策略（会阻止服务）
- `Permissive` - SELinux 仅记录违规但不阻止
- `Disabled` - SELinux 已禁用

## 解决方案 / Solutions

### 方案 1: 临时切到宽容模式 (推荐) / Option 1: Switch to Permissive Temporarily (Recommended)

```bash
# 临时切换到宽容模式，重启后恢复
# Temporarily switch to permissive mode, reverts after reboot
sudo setenforce 0
```

重启后 SELinux 回到 Enforcing。脚本在 SELinux 没禁用时会把 Xray / sing-box 两个二进制登记成 `bin_t`（需要 `semanage`，没有时自动装 `policycoreutils-python-utils`，装不上就退回 `chcon`），并把 nginx 监听的端口（订阅口、伪装站与回落用的本机端口等）登记成 `http_port_t`（装了 VLESS+XHTTP+TLS 或 VMess+HTTPUpgrade 时还有它们转发到的本机端口，并开启 `httpd_can_network_relay`），所以重启后代理本身照常工作，定时任务（证书续期、geo 更新、拼车统计）也照常跑，证书不会到期续不上。`pasly` 菜单在 Enforcing 下仍然会退出，要改配置时先执行一次 `setenforce 0`，或者选方案 2。

After a reboot SELinux is back to Enforcing. While SELinux is not disabled the script registers the Xray / sing-box binaries as `bin_t` (via `semanage`, installing `policycoreutils-python-utils` if missing, falling back to `chcon`) and the ports nginx listens on (the subscription port, the fake site and the local fallback ports) as `http_port_t` (with VLESS+XHTTP+TLS or VMess+HTTPUpgrade also the local port they forward to, plus enabling `httpd_can_network_relay`), so the proxies themselves keep working after a reboot, and so do the cron jobs (certificate renewal, geo updates, carpool metering): certificates do not expire unrenewed. The `pasly` menu still exits under Enforcing: run `setenforce 0` once before changing the configuration, or pick Option 2.

### 方案 2: 永久禁用 / Option 2: Permanent Disable

编辑 SELinux 配置文件 / Edit SELinux configuration:

```bash
sudo vi /etc/selinux/config
```

将 `SELINUX=enforcing` 改为 / Change `SELINUX=enforcing` to:

```
SELINUX=disabled
```

然后重启系统 / Then reboot:

```bash
sudo reboot
```

### 方案 3: 配置 SELinux 策略 (高级) / Option 3: Configure SELinux Policy (Advanced)

如果需要保持 SELinux 启用，可以为代理服务配置策略：

If you need to keep SELinux enabled, configure policies for proxy services:

```bash
# 允许 Nginx 网络连接 / Allow Nginx network connections
sudo setsebool -P httpd_can_network_connect 1

# 允许 Nginx 连接到任意端口 / Allow Nginx to connect to any port
sudo setsebool -P httpd_can_network_relay 1

# 查看 SELinux 拒绝日志 / View SELinux denial logs
sudo ausearch -m avc -ts recent

# 生成并应用自定义策略 / Generate and apply custom policy
sudo ausearch -c 'xray' --raw | audit2allow -M xray_policy
sudo semodule -i xray_policy.pp
```

## 验证服务状态 / Verify Service Status

禁用 SELinux 后，重新运行安装脚本或启动服务：

After disabling SELinux, re-run the installation script or start services:

```bash
# 重新运行安装脚本 / Re-run installation script
pasly

# 或手动重启服务 / Or manually restart services
systemctl restart xray
systemctl restart nginx
```

## 安全建议 / Security Recommendations

- 生产环境建议使用方案 3（配置策略）而非完全禁用 SELinux
- 如果不熟悉 SELinux，可以使用方案 2 永久禁用
- 在云服务器上，通常可以安全地禁用 SELinux，因为有其他安全层

- For production, Option 3 (configuring policies) is recommended over completely disabling SELinux
- If unfamiliar with SELinux, Option 2 (permanent disable) is acceptable
- On cloud servers, it's usually safe to disable SELinux as other security layers exist

## 相关链接 / Related Links

- [SELinux Project Wiki](https://selinuxproject.org/page/Main_Page)
- [Red Hat SELinux Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/using_selinux/index)
