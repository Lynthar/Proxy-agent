# Proxy-agent 全面代码审计报告

**审计日期**: 2025-12-13
**对比项目**: [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)
**参考文档**: [Xray-core](https://github.com/XTLS/Xray-core), [REALITY](https://github.com/XTLS/REALITY), [sing-box](https://github.com/SagerNet/sing-box)

---

## 问题汇总表

| 编号 | 严重性 | 类别 | 问题描述 | 状态 |
|------|--------|------|----------|------|
| 1 | 🔴 高 | 配置错误 | sing-box SOCKS5 入站添加了不存在的 `aead` 字段 | ✅ 已修复 |
| 2 | 🔴 高 | 路由缺失 | 全局 SOCKS5 出站转发缺少 `route.final` 配置 | ✅ 已修复 |
| 3 | 🟠 中 | 逻辑错误 | Hysteria2 带宽配置 `up_mbps`/`down_mbps` 反向 | ✅ 已修复 |
| 4 | 🟠 中 | 配置错误 | Xray 入站配置包含无效的 `add` 字段 | ✅ 已修复 |
| 5 | 🟠 中 | 死代码 | `initRealityClientServersName` 中 elif 条件永不执行 | ✅ 已修复 |
| 6 | 🟡 低 | 死代码 | 被注释的 `initTuicConfig` 函数 | ✅ 已修复 |
| 7 | 🟡 低 | 死代码 | 被注释的 `initXrayFrontingConfig` 函数 | ✅ 已修复 |
| 8 | 🟡 低 | 安全建议 | Reality shortIds 使用空字符串 `""` | ✅ 已修复 |
| 9 | 🟡 低 | 安全建议 | Reality shortIds 硬编码固定值 | ✅ 已修复 |
| 10 | 🟡 低 | 配置建议 | Reality maxTimeDiff 设置过大 (70000ms) | ✅ 已修复 |
| 11 | 🟡 低 | 代码冗余 | SOCKS5 入站的 AEAD 选项误导性菜单文本 | ✅ 已修复 |
| 12 | ⚪ 信息 | 版本兼容 | Xray x25519 输出格式变化需注意 | ✅ 已修复 |

---

## 详细问题说明

### 1. 🔴 [已修复] sing-box SOCKS5 入站 aead 字段错误

**位置**: `install.sh:7863`

**原代码**:
```bash
| (if $enableAead then .inbounds[0].users[0].aead = true else . end)
```

**问题**: 根据 [sing-box SOCKS 文档](https://sing-box.sagernet.org/configuration/inbound/socks/)，SOCKS 入站的 users 配置只支持 `username` 和 `password` 字段，不支持 `aead` 字段。

**错误信息**:
```
FATAL[0000] inbounds[0].users[0].aead: json: unknown field "aead"
```

**状态**: ✅ 已在本次审计中修复

---

### 2. 🔴 [已修复] 全局 SOCKS5 出站转发缺少路由配置

**位置**: `install.sh:7620-7666` (`setSocks5OutboundRoutingAll` 函数)

**问题**: 函数只删除了其他路由规则，但没有创建让所有流量走 `socks5_outbound` 的路由配置。

**影响**: 使用 Reality 协议时，流量无法正确通过 SOCKS 出站转发。

**状态**: ✅ 已在本次审计中修复（添加了 `route.final: "socks5_outbound"` 配置）

---

### 3. 🟠 Hysteria2 带宽配置反向

**位置**: `install.sh:4726-4727`, `install.sh:3831-3832`

**当前代码**:
```json
"up_mbps":${hysteria2ClientUploadSpeed},
"down_mbps":${hysteria2ClientDownloadSpeed},
```

**用户输入** (`install.sh:3082-3094`):
```bash
echoContent yellow "请输入本地带宽峰值的下行速度..."
read -r -p "下行速度:" hysteria2ClientDownloadSpeed

echoContent yellow "请输入本地带宽峰值的上行速度..."
read -r -p "上行速度:" hysteria2ClientUploadSpeed
```

**问题**: 根据 [Hysteria2 官方文档](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)：
> "Note that the server's upload speed is the client's download speed, and vice versa."

服务器的 `up_mbps` 对应客户端的**下载**速度，`down_mbps` 对应客户端的**上传**速度。

**正确配置**:
```json
"up_mbps":${hysteria2ClientDownloadSpeed},   // 服务器上传 = 客户端下载
"down_mbps":${hysteria2ClientUploadSpeed},   // 服务器下载 = 客户端上传
```

**建议**: 交换 `up_mbps` 和 `down_mbps` 的值。

---

### 4. 🟠 Xray 入站配置包含无效的 `add` 字段

**位置**: `install.sh:4273`

**当前代码**:
```json
{
  "inbounds": [{
    "settings": {...},
    "add": "${add}",    // ❌ 无效字段
    "streamSettings": {...}
  }]
}
```

**问题**: `add` 是**客户端**配置字段（用于指定服务器地址），不是 Xray 入站配置的有效字段。这个字段会被 Xray 忽略，但可能导致配置文件验证工具报错。

**建议**: 删除入站配置中的 `"add": "${add}"` 行。

---

### 5. 🟠 initRealityClientServersName 中 elif 条件永不执行

**位置**: `install.sh:9970-9984`

**当前代码**:
```bash
if [[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]; then
    # ... 处理逻辑 (9971-9980)
elif [[ -n "${realityServerName}" && -z "${lastInstallationConfig}" ]]; then  # 9981 ❌
    realityServerName=
    realityDomainPort=
fi
```

**问题**: 第 9981 行的 `elif` 条件与第 9970 行的 `if` 条件**完全相同**，导致 `elif` 分支永远不会执行。

**建议**: 检查原始意图，可能应该是：
```bash
elif [[ -n "${realityServerName}" && -n "${lastInstallationConfig}" ]]; then
```
或直接删除这个无用的 elif 分支。

---

### 6. 🟡 被注释的 initTuicConfig 函数

**位置**: `install.sh:3345-3361`

**代码**:
```bash
# 初始化tuic配置
#initTuicConfig() {
#    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Tuic配置"
#    ...
#EOF
#}
```

**问题**: 整个函数被注释掉，是死代码。

**建议**: 如果不再需要，应该删除；如果计划将来使用，应该添加 TODO 注释说明。

---

### 7. 🟡 被注释的 initXrayFrontingConfig 函数

**位置**: `install.sh:3887-3984` (约 100 行)

**问题**: 整个函数被注释掉，是死代码。

**建议**: 删除这段被注释的代码，或者如果有保留意图，移到单独的文档或存档文件中。

---

### 8. 🟡 Reality shortIds 使用空字符串

**位置**: `install.sh:4182-4185`, `4354-4357`, `4652-4655`, `4693-4696`

**当前代码**:
```json
"shortIds": [
    "",                    // ❌ 空字符串
    "6ba85179e30d4fc2"
]
```

**问题**: 根据 REALITY 协议设计，空的 shortId (`""`) 允许无 shortId 的连接，这可能降低安全性。

**建议**: 移除空字符串，使用随机生成的 shortId：
```json
"shortIds": [
    "$(openssl rand -hex 8)",
    "$(openssl rand -hex 8)"
]
```

---

### 9. 🟡 Reality shortIds 硬编码固定值

**位置**: 多处，包括 `4184`, `4356`, `4654`, `4695`, `5201`, `5205` 等

**当前代码**:
```json
"shortIds": ["", "6ba85179e30d4fc2"]
```

**问题**: 使用硬编码的固定 shortId 值 `6ba85179e30d4fc2`，这意味着所有使用此脚本安装的服务器都使用相同的 shortId，可能被用于指纹识别。

**建议**: 每次安装时随机生成 shortIds。

---

### 10. 🟡 Reality maxTimeDiff 设置过大

**位置**: `install.sh:4181`, `4353`

**当前代码**:
```json
"maxTimeDiff": 70000
```

**问题**: 70000ms (70秒) 的时间差容忍值较大。默认值通常更小。

**建议**: 考虑使用默认值或更小的值（如 60000ms）。

---

### 11. 🟡 SOCKS5 入站的 AEAD 选项无实际作用

**位置**: `install.sh:7786-7800`

**当前代码**:
```bash
echoContent yellow "1.用户名/密码[回车默认，兼容性高]"
echoContent yellow "2.预共享密钥(AEAD)[安全性更高，默认使用下方UUID生成]"
read -r -p "请选择:" socks5InboundAuthType

if [[ "${socks5InboundAuthType}" == "2" ]]; then
    socks5InboundAuthType="aead"
    socks5InboundEnableAEAD=true  // 这个变量在修复后已无实际作用
```

**问题**:
1. sing-box SOCKS 协议不支持 AEAD 认证（AEAD 是 Shadowsocks 的特性）
2. 在修复问题 #1 后，`socks5InboundEnableAEAD` 变量已经不再使用
3. 菜单选项误导用户认为有 AEAD 选项

**建议**:
- 移除 AEAD 认证选项的菜单提示
- 或者改为使用 Shadowsocks 协议来支持 AEAD

---

### 12. ⚪ Xray x25519 输出格式版本差异

**位置**: `install.sh:9903-9904`

**当前代码**:
```bash
realityPrivateKey=$(echo "${realityX25519Key}" | grep "PrivateKey" | awk '{print $2}')
realityPublicKey=$(echo "${realityX25519Key}" | grep "Password" | awk '{print $2}')
```

**说明**: 根据 [Xray 讨论](https://github.com/XTLS/Xray-core/discussions/5219)，Xray x25519 命令的输出格式在某个版本后发生了变化：

**旧版本输出**:
```
Private key: xxx
Public key: xxx
```

**新版本输出**:
```
PrivateKey: xxx
Password: xxx       // "Password" 就是公钥
Hash32: xxx
```

**当前状态**: 当前代码使用 `grep "PrivateKey"` 和 `grep "Password"` 匹配**新版本**格式，这是正确的。

**风险**: 如果用户使用旧版本 Xray，可能无法正确提取密钥。

**建议**: 添加兼容性处理，同时支持两种格式：
```bash
realityPrivateKey=$(echo "${realityX25519Key}" | grep -E "Private|PrivateKey" | awk '{print $NF}')
realityPublicKey=$(echo "${realityX25519Key}" | grep -E "Public|Password" | awk '{print $NF}')
```

---

## 与源项目 (mack-a/v2ray-agent) 的主要差异

| 功能区域 | 当前项目 | 源项目 | 差异说明 |
|----------|----------|--------|----------|
| SOCKS5 入站 | 支持监听范围选择、AEAD 选项 | 简单实现，用户名=密码=UUID | 当前项目功能更多但 AEAD 选项无效 |
| SOCKS5 出站 | 支持 TLS、健康检查、故障转移 | 基础实现 | 当前项目功能更强 |
| 代码行数 | 10,405 行 | 9,646 行 | 当前项目多约 760 行 |
| Reality 密钥提取 | 使用 grep "Password" | 使用 grep "Password" | 两者相同（针对新版 Xray） |

---

## 修复状态汇总

**所有问题均已修复** (2025-12-13):

1. ✅ sing-box SOCKS5 aead 字段 - 已移除
2. ✅ 全局 SOCKS5 路由配置 - 已添加 route.final
3. ✅ Hysteria2 up_mbps/down_mbps - 已交换
4. ✅ Xray 入站 add 字段 - 已移除
5. ✅ elif 条件逻辑 - 已移除死代码
6. ✅ initTuicConfig 死代码 - 已删除
7. ✅ initXrayFrontingConfig 死代码 - 已删除
8. ✅ Reality shortIds 空字符串 - 已改为随机生成
9. ✅ Reality shortIds 硬编码 - 已改为动态生成
10. ✅ maxTimeDiff - 已从 70000 调整为 60000
11. ✅ SOCKS5 AEAD 菜单 - 已更新为准确描述
12. ✅ x25519 版本兼容 - 已添加新旧版本支持

---

## 参考资料

- [Xray-core GitHub](https://github.com/XTLS/Xray-core)
- [Xray-examples](https://github.com/XTLS/Xray-examples)
- [REALITY Protocol](https://github.com/XTLS/REALITY)
- [sing-box GitHub](https://github.com/SagerNet/sing-box)
- [sing-box SOCKS Inbound](https://sing-box.sagernet.org/configuration/inbound/socks/)
- [Hysteria2 Server Config](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)
- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)

---

*报告生成日期: 2025-12-13*
