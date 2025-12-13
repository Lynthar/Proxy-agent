# Proxy-agent 代码审查报告

## 概述

本报告对 Proxy-agent 脚本进行了全面的代码审查，重点分析了 Xray-core 和 sing-box 的配置生成逻辑，对比官方文档和最佳实践，发现了以下问题和改进建议。

---

## 1. 安全问题

### 1.1 sing-box SOCKS5 认证漏洞 (CVE-2023-43644)

**严重性**: 高

**问题**: sing-box 1.4.4 及更早版本存在 SOCKS5 入站认证绕过漏洞。攻击者可以构造特殊请求绕过用户认证。

**当前代码位置**: `install.sh:7849-7863`

```bash
# 当前 SOCKS5 入站配置
{
  type: "socks",
  listen: $listen,
  listen_port: $listenPort,
  tag: $tag,
  users: [
    {
      username: $user,
      password: $pass
    }
  ],
  domain_strategy: $domainStrategy
}
```

**建议**:
1. 在脚本中添加 sing-box 版本检查，确保版本 >= 1.4.5
2. 不要将 SOCKS5 入站暴露在不安全的网络环境中
3. 考虑启用 AEAD 认证模式以增强安全性

---

### 1.2 SOCKS5 默认用户名为 "admin"

**严重性**: 中

**问题位置**: `install.sh:8132-8133`

```bash
if [[ -z "${socks5RoutingOutboundUserName}" ]]; then
    socks5RoutingOutboundUserName="admin"
fi
```

**问题**: 使用可预测的默认用户名 "admin" 可能导致安全风险。

**建议**: 使用随机生成的用户名或强制用户输入。

---

### 1.3 TLS 证书验证可被跳过

**严重性**: 中

**问题位置**: `install.sh:8028-8030`

```bash
read -r -p "跳过证书校验:" socks5OutboundSkipVerify
if [[ "${socks5OutboundSkipVerify}" == "y" ]]; then
    socks5OutboundTLSInsecure=true
fi
```

**问题**: 允许跳过 TLS 证书验证可能导致中间人攻击。

**建议**: 添加警告信息，明确告知用户风险。

---

## 2. 配置错误

### 2.1 sing-box Reality 配置缺少 flow 字段

**严重性**: 中

**问题位置**: `install.sh:4674-4705` (VLESS Reality gRPC)

```json
{
  "type": "vless",
  "users": [{"uuid": "xxx", "name": "xxx-VLESS_Reality_gPRC"}]
}
```

**问题**: VLESS Reality gRPC 用户配置中缺少 `flow` 字段，但在 `initSingBoxClients` 函数中 type 8 确实没有设置 flow（正确，gRPC 不需要 flow）。

**状态**: 这是正确的配置，gRPC 传输不使用 flow。

---

### 2.2 Xray Reality gRPC 配置中的 flow 字段

**严重性**: 低

**问题位置**: `install.sh:2945`

```bash
currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_grpc\",\"flow\":\"\"}"
```

**问题**: 对于 gRPC 传输，`flow` 应该完全省略或留空。当前设置为空字符串 `"flow":""`。

**建议**: 对于 gRPC 协议，完全移除 `flow` 字段而不是设为空字符串。

---

### 2.3 sing-box VLESS Vision TLS 配置缺少关键字段

**严重性**: 中

**问题位置**: `install.sh:4519-4537`

```json
{
  "type": "vless",
  "tls": {
    "server_name": "${sslDomain}",
    "enabled": true,
    "certificate_path": "...",
    "key_path": "..."
  }
}
```

**建议添加**:
```json
{
  "tls": {
    "alpn": ["h2", "http/1.1"],
    "min_version": "1.2"
  }
}
```

**建议**: 为 VLESS Vision TLS 入站添加 `alpn` 和 `min_version` 配置以增强安全性和兼容性。

---

### 2.4 Xray VLESS TCP 配置中的 "add" 字段

**严重性**: 低

**问题位置**: `install.sh:4273`

```json
{
  "inbounds": [{
    "add": "${add}"
  }]
}
```

**问题**: `add` 不是 Xray 入站配置的有效字段。这是客户端配置字段，不应该出现在服务端入站配置中。

**建议**: 移除入站配置中的 `add` 字段。

---

### 2.5 sing-box Hysteria2/TUIC 缺少 UDP 配置

**严重性**: 低

**问题位置**: `install.sh:4718-4739` (Hysteria2), `install.sh:4780-4802` (TUIC)

**建议**: 考虑添加以下配置优化 UDP 性能:
```json
{
  "sniff": true,
  "sniff_override_destination": false
}
```

---

## 3. 代码逻辑问题

### 3.1 Reality PublicKey 解析错误

**严重性**: 高

**问题位置**: `install.sh:9895`

```bash
realityPublicKey=$(echo "${realityX25519Key}" | grep "Password" | awk '{print $2}')
```

**问题**: Xray x25519 命令输出的字段名是 "Public key" 而不是 "Password"。当前代码使用 `grep "Password"` 将无法正确提取 PublicKey，导致 Reality 配置生成失败。

**Xray x25519 实际输出格式**:
```
Private key: xxx
Public key: xxx
```

**建议修改为**:
```bash
realityPublicKey=$(echo "${realityX25519Key}" | grep "Public" | awk '{print $3}')
```

**注意**: 同时需要检查 `PrivateKey` 的提取逻辑，当前使用 `grep "PrivateKey"` 可能也需要改为 `grep "Private"`。

---

### 3.2 initRealityClientServersName 逻辑重复

**严重性**: 低

**问题位置**: `install.sh:9972-9974`

```bash
elif [[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]; then
    realityServerName=
    realityDomainPort=
fi
```

**问题**: 条件 `[[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]` 与上面的条件完全相同（9961行），导致这个分支永远不会执行。

**建议**: 检查并修正条件逻辑。

---

### 3.3 SOCKS5 入站 domain_strategy 选项有限

**严重性**: 低

**问题位置**: `install.sh:7824-7827`

```bash
if [[ -z "${socks5InboundDomainStrategyStatus}" || "${socks5InboundDomainStrategyStatus}" == "1" ]]; then
    domainStrategy="ipv4_only"
elif [[ "${socks5InboundDomainStrategyStatus}" == "2" ]]; then
    domainStrategy="ipv6_only"
```

**建议**: 添加更多选项:
- `prefer_ipv4`
- `prefer_ipv6`
- 空值（使用系统默认）

---

## 4. 最佳实践建议

### 4.1 Reality 配置优化

**当前配置** (`install.sh:4342-4358`):
```json
{
  "realitySettings": {
    "shortIds": ["", "6ba85179e30d4fc2"],
    "maxTimeDiff": 70000
  }
}
```

**建议**:
1. 不建议使用空的 shortId (`""`)，应该生成随机值
2. `maxTimeDiff: 70000` (70秒) 可能过大，建议使用默认值或更小的值

**改进建议**:
```json
{
  "shortIds": ["$(openssl rand -hex 8)", "$(openssl rand -hex 8)"]
}
```

---

### 4.2 TLS 配置增强

**当前配置** (`install.sh:4276-4287`):
```json
{
  "tlsSettings": {
    "rejectUnknownSni": true,
    "minVersion": "1.2",
    "certificates": [...]
  }
}
```

**建议添加**:
```json
{
  "tlsSettings": {
    "alpn": ["h2", "http/1.1"],
    "cipherSuites": "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256"
  }
}
```

---

### 4.3 sing-box 配置合并机制

**当前方式**: 使用 `sing-box merge` 命令合并配置

**建议**: 确保正确设置 `log`、`dns`、`route` 和 `experimental` 顶层配置，避免配置冲突。

---

### 4.4 Hysteria2 带宽配置

**当前配置** (`install.sh:4726-4727`):
```json
{
  "up_mbps": ${hysteria2ClientUploadSpeed},
  "down_mbps": ${hysteria2ClientDownloadSpeed}
}
```

**注意**: sing-box 1.8+ 版本中 `up_mbps` 和 `down_mbps` 已被弃用，应使用 `up` 和 `down` 并指定单位。

**建议修改为**:
```json
{
  "up": "${hysteria2ClientUploadSpeed} Mbps",
  "down": "${hysteria2ClientDownloadSpeed} Mbps"
}
```

---

## 5. 缺失功能建议

### 5.1 版本兼容性检查

建议添加对 Xray-core 和 sing-box 版本的检查，确保使用的配置与核心版本兼容。

### 5.2 配置验证

建议在生成配置后使用 `xray test -c` 或 `sing-box check` 进行配置验证。

### 5.3 日志轮转配置

建议为 Xray 和 sing-box 配置日志轮转，避免日志文件无限增长。

---

## 6. 总结

| 类别 | 问题数量 |
|------|---------|
| 高严重性安全问题 | 2 |
| 中严重性问题 | 4 |
| 低严重性问题 | 5 |
| 最佳实践建议 | 4 |

### 优先修复建议

1. **立即修复**: Reality PublicKey 解析逻辑错误 (3.1)
2. **尽快修复**: sing-box SOCKS5 认证漏洞提醒 (1.1)
3. **建议修复**: SOCKS5 默认用户名问题 (1.2)
4. **建议优化**: Reality shortIds 配置 (4.1)
5. **建议优化**: TLS 配置增强 (4.2)

---

## 参考资源

- [Xray-core GitHub](https://github.com/XTLS/Xray-core)
- [Xray-examples](https://github.com/XTLS/Xray-examples)
- [REALITY Protocol](https://github.com/XTLS/REALITY)
- [sing-box GitHub](https://github.com/SagerNet/sing-box)
- [CVE-2023-43644](https://github.com/advisories/GHSA-r5hm-mp3j-285g)

---

*报告生成日期: 2025-12-13*
