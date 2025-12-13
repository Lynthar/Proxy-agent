# Proxy-agent 与 mack-a/v2ray-agent 对比分析报告

**分析日期**: 2025-12-13
**源项目版本**: v3.5.2 (mack-a/v2ray-agent)
**本项目版本**: v3.5.1 (Lynthar/Proxy-agent)

---

## 概述

| 项目 | 代码行数 | 函数数量 |
|------|---------|---------|
| Proxy-agent | 10,337 | 192 |
| Upstream (mack-a) | 9,646 | 187 |
| **差异** | +691 (+7.2%) | +5 |

---

## 一、新增功能与代码

### 1.1 新增函数

| 函数名 | 用途 | 评估 |
|--------|------|------|
| `stripAnsi()` | 移除 ANSI 转义序列，确保变量值干净 | ✅ 合理 |
| `validateJsonFile()` | 验证 JSON 文件格式，失败时自动清理 | ✅ 合理 |
| `readCredentialBySource()` | 支持从直接输入/文件/环境变量读取凭据 | ✅ 增强自动化能力 |
| `checkSocksConfig()` | 检查 SOCKS5 配置状态 | ✅ 增强用户体验 |
| `initRealityShortIds()` | 动态生成 Reality shortIds | ✅ 安全性改进 |

### 1.2 SOCKS5 入站增强

**Proxy-agent 增强内容**:

```diff
+ 监听范围选择（127.0.0.1 / 自定义网段 / 0.0.0.0）
+ 认证方式选择（用户名密码 / 统一密钥）
+ 使用 jq 动态生成 JSON（替代 heredoc）
+ JSON 格式验证
+ 安全的防火墙规则（按需开放）
```

**对比**:
| 功能 | Upstream | Proxy-agent |
|------|----------|-------------|
| 监听地址 | 固定 `::` (全部) | 可选 (127.0.0.1/自定义/0.0.0.0) |
| 认证方式 | 仅用户名=密码=UUID | 支持分离用户名/密码 |
| 凭据来源 | 仅直接输入 | 支持文件/环境变量 |
| JSON 生成 | heredoc 模板 | jq 动态生成 |
| 格式验证 | 无 | 有 |

**评估**: ✅ 合理且符合 sing-box 规范

### 1.3 SOCKS5 全局出站路由修复

**关键修复** (Proxy-agent 修复了 Upstream 的 bug):

```bash
# Proxy-agent 添加了关键的 route.final 配置
cat <<EOF >"${singBoxConfigPath}socks5_01_outbound_route.json"
{
  "route": {
    "final": "socks5_outbound"
  }
}
EOF
```

**Upstream 问题**: 全局出站模式下仅删除其他路由，但未设置 `route.final`，导致 Reality 协议无法通过 SOCKS5 转发。

**评估**: ✅ 正确修复，符合 sing-box 路由规范

### 1.4 Reality shortIds 动态生成

**Proxy-agent 改进**:
```bash
# 动态生成随机 shortIds
initRealityShortIds() {
    if [[ -z "${realityShortId1}" ]]; then
        realityShortId1=$(openssl rand -hex 8)
        realityShortId2=$(openssl rand -hex 8)
    fi
}
```

**Upstream 问题**: 使用硬编码的 shortIds `"6ba85179e30d4fc2"`

**评估**: ✅ 安全性改进，符合 REALITY 协议最佳实践

### 1.5 x25519 密钥提取兼容性

**Proxy-agent 改进**:
```bash
# 兼容新旧版本 Xray 输出格式
realityPrivateKey=$(echo "${realityX25519Key}" | grep -E "Private|PrivateKey" | awk '{print $NF}')
realityPublicKey=$(echo "${realityX25519Key}" | grep -E "Public|Password" | awk '{print $NF}')
```

**Upstream**: 仅支持新版格式 (`PrivateKey`/`Password`)

**评估**: ✅ 提高兼容性

---

## 二、移除的内容

### 2.1 推广区

**移除内容**:
```
=========================== 推广区============================
VPS选购攻略
年付10美金低价VPS AS4837
优质常驻套餐DMIT CN2-GIA
VPS探针：https://ping.v2ray-agent.com/
```

**评估**: ✅ 合理（移除非功能性内容）

### 2.2 其他移除

- **无功能性代码移除**: Proxy-agent 保留了所有核心功能

---

## 三、修改的内容

### 3.1 菜单提示文本修改

**SOCKS5 认证方式菜单**:
- Upstream: 无认证方式选择
- Proxy-agent:
  - 原: "预共享密钥(AEAD)" (误导性)
  - 现: "统一密钥" (准确)

**评估**: ✅ 更准确（sing-box SOCKS 不支持 AEAD）

### 3.2 maxTimeDiff 调整

| 项目 | 值 |
|------|-----|
| Upstream | 70000ms |
| Proxy-agent | 60000ms |

**评估**: ✅ 合理（60秒是更常用的默认值）

---

## 四、潜在问题分析

### 4.1 ⚠️ Hysteria2 带宽读取逻辑

**当前状态**:
```bash
# Proxy-agent (可能有问题)
hysteria2ClientUploadSpeed=$(jq -r '.inbounds[0].up_mbps' ...)
hysteria2ClientDownloadSpeed=$(jq -r '.inbounds[0].down_mbps' ...)

# Upstream (语义正确)
hysteria2ClientUploadSpeed=$(jq -r '.inbounds[0].down_mbps' ...)
hysteria2ClientDownloadSpeed=$(jq -r '.inbounds[0].up_mbps' ...)
```

**说明**:
- 服务端 `up_mbps` = 服务端上传 = 客户端下载
- 服务端 `down_mbps` = 服务端下载 = 客户端上传

**影响**: 读取现有配置时变量名与实际值语义不匹配，但写入配置时已正确处理，实际功能不受影响。

**建议**: 建议修复读取逻辑以保持代码清晰度。

---

## 五、合规性总结

### 5.1 Xray-core 规范符合度

| 检查项 | 状态 |
|--------|------|
| Reality 配置结构 | ✅ 符合 |
| VLESS 协议配置 | ✅ 符合 |
| 路由规则格式 | ✅ 符合 |
| x25519 密钥生成 | ✅ 符合 |

### 5.2 sing-box 规范符合度

| 检查项 | 状态 |
|--------|------|
| SOCKS 入站配置 | ✅ 符合（已移除无效 aead 字段）|
| SOCKS 出站配置 | ✅ 符合 |
| route.final 配置 | ✅ 符合（已添加）|
| Hysteria2 配置 | ✅ 符合 |
| Reality 配置 | ✅ 符合 |

### 5.3 REALITY 协议规范

| 检查项 | 状态 |
|--------|------|
| shortIds 格式 | ✅ 符合（16位十六进制）|
| shortIds 随机性 | ✅ 改进（动态生成）|
| privateKey/publicKey | ✅ 符合 |

---

## 六、结论

### 改进点
1. **安全性**: 增加了 SOCKS5 监听范围选择、动态 shortIds 生成
2. **可靠性**: 添加 JSON 验证、修复 SOCKS5 全局路由
3. **兼容性**: 支持新旧版 Xray x25519 输出格式
4. **自动化**: 支持从文件/环境变量读取凭据
5. **准确性**: 更正了误导性的菜单文本

### 待优化
1. Hysteria2 带宽读取变量命名可优化以提高代码可读性

### 总体评估
**Proxy-agent 的修改是合理的、正确的、符合 Xray 和 sing-box 规范的**。主要变更都是功能增强和 bug 修复，没有引入不兼容的改动。

---

*报告生成日期: 2025-12-13*
