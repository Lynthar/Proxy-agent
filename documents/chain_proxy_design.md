# 链式代理功能设计方案

## 一、需求分析

### 1.1 使用场景
```
客户端 → 入口VPS(线路优化) → 出口VPS(IP优化) → 互联网
         [Entry Node]         [Exit Node]
```

- **入口VPS**: 线路优化（如 CN2 GIA、AS9929 等优质线路）
- **出口VPS**: IP优化（如美国原生IP、解锁流媒体等）
- **两者特点**: 都在境外，无需考虑 GFW 审查

### 1.2 现有 SOCKS5 分流问题

| 问题 | 描述 |
|------|------|
| 配置复杂 | 需要在两台VPS分别配置，容易出错 |
| 流量明文 | SOCKS5 无加密，存在安全风险 |
| 缺乏测试 | 无内置连通性测试 |
| 路由遗漏 | 常忘记配置 `route.final` |
| 状态不明 | 难以判断链路是否正常工作 |

### 1.3 设计目标

1. **安全**: 链路加密，防止中间人攻击
2. **快速**: 低延迟，高吞吐量
3. **简单**: 一键配置，自动匹配
4. **健壮**: 内置测试，错误提示清晰
5. **灵活**: 支持多种协议选择

---

## 二、协议选择

### 2.1 候选协议对比

| 协议 | 加密 | 性能 | 复杂度 | 适用场景 |
|------|------|------|--------|----------|
| SOCKS5 | ❌ | ★★★★ | 低 | 内网信任环境 |
| Shadowsocks 2022 | ✅ | ★★★★★ | 低 | **推荐** |
| VLESS/TCP | ❌ | ★★★★★ | 中 | 极致性能 |
| WireGuard | ✅ | ★★★★★ | 高 | 大流量隧道 |
| Hysteria2 | ✅ | ★★★★ | 中 | 丢包环境 |

### 2.2 推荐方案

**主推: Shadowsocks 2022 (sing-box)**
- 原因: 加密、快速、配置简单、sing-box 原生支持
- 加密方式: `2022-blake3-aes-128-gcm` 或 `2022-blake3-aes-256-gcm`

**备选: VLESS over TCP (无TLS)**
- 原因: 更轻量，适合完全信任的内网环境

---

## 三、功能设计

### 3.1 菜单结构

```
链式代理管理
├── 1. 快速配置向导 [推荐]
│   ├── 配置为入口节点 (Entry)
│   └── 配置为出口节点 (Exit)
├── 2. 查看链路状态
├── 3. 测试链路连通性
├── 4. 导出/导入配置
│   ├── 导出配置 (生成配置码)
│   └── 导入配置 (粘贴配置码)
├── 5. 高级设置
│   ├── 切换协议
│   ├── 修改端口
│   └── 更新密钥
└── 6. 卸载链式代理
```

### 3.2 配置流程

#### 方案A: 配置码模式 (推荐)

```
[出口VPS]                              [入口VPS]
    │                                      │
    ▼                                      │
1. 选择"配置为出口节点"                      │
    │                                      │
    ▼                                      │
2. 自动生成配置                             │
   - 随机端口                               │
   - 随机密钥                               │
   - 创建入站                               │
    │                                      │
    ▼                                      │
3. 生成配置码 ─────────────────────────────→ 4. 选择"配置为入口节点"
   chain://ss2022@IP:PORT#KEY                  │
                                              ▼
                                          5. 粘贴配置码
                                              │
                                              ▼
                                          6. 自动解析并配置出站
                                              │
                                              ▼
                                          7. 自动测试连通性
```

#### 方案B: 手动模式

适合已有出口节点信息的情况，手动输入 IP、端口、密钥。

### 3.3 配置码格式

```
chain://[protocol]@[ip]:[port]?key=[base64_key]&method=[cipher]#[name]

示例:
chain://ss2022@1.2.3.4:54321?key=YWJjZGVmZ2hpamtsbW5vcA==&method=2022-blake3-aes-128-gcm#MyExitNode
```

### 3.4 核心函数设计

```bash
# 主入口
chainProxyMenu()

# 快速配置向导
chainProxyWizard()
  ├── setupChainExit()      # 配置出口节点
  └── setupChainEntry()     # 配置入口节点

# 出口节点配置
setupChainExit()
  ├── generateChainKey()    # 生成密钥
  ├── createChainInbound()  # 创建入站配置
  └── generateChainCode()   # 生成配置码

# 入口节点配置
setupChainEntry()
  ├── parseChainCode()      # 解析配置码
  ├── createChainOutbound() # 创建出站配置
  ├── createChainRoute()    # 创建路由规则
  └── testChainConnection() # 测试连通性

# 辅助函数
showChainStatus()           # 显示链路状态
testChainConnection()       # 测试连通性
exportChainConfig()         # 导出配置
importChainConfig()         # 导入配置
removeChainProxy()          # 卸载
```

---

## 四、配置模板

### 4.1 出口节点 - 入站配置 (sing-box)

```json
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "chain_inbound",
      "listen": "::",
      "listen_port": ${CHAIN_PORT},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${CHAIN_KEY}",
      "multiplex": {
        "enabled": true
      }
    }
  ]
}
```

### 4.2 入口节点 - 出站配置 (sing-box)

```json
{
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "chain_outbound",
      "server": "${EXIT_IP}",
      "server_port": ${EXIT_PORT},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${CHAIN_KEY}",
      "multiplex": {
        "enabled": true,
        "protocol": "h2mux",
        "max_connections": 4,
        "min_streams": 4
      }
    }
  ]
}
```

### 4.3 入口节点 - 路由配置 (sing-box)

```json
{
  "route": {
    "final": "chain_outbound"
  }
}
```

---

## 五、安全设计

### 5.1 密钥生成

```bash
# Shadowsocks 2022 需要 Base64 编码的密钥
# AES-128-GCM: 16字节 = 128位
openssl rand -base64 16

# AES-256-GCM: 32字节 = 256位
openssl rand -base64 32
```

### 5.2 防火墙规则

```bash
# 出口节点: 仅允许入口节点IP访问链式端口
ufw allow from ${ENTRY_IP} to any port ${CHAIN_PORT} proto tcp

# 或使用 iptables
iptables -A INPUT -p tcp --dport ${CHAIN_PORT} -s ${ENTRY_IP} -j ACCEPT
iptables -A INPUT -p tcp --dport ${CHAIN_PORT} -j DROP
```

### 5.3 配置码安全

- 配置码包含敏感信息，应通过安全渠道传输
- 建议: 复制后立即清除剪贴板
- 可选: 添加一次性使用或过期机制

---

## 六、连通性测试

### 6.1 测试流程

```bash
testChainConnection() {
    # 1. 检查出站配置存在
    # 2. 获取出口节点IP和端口
    # 3. TCP连接测试
    # 4. 通过链路请求测试URL
    # 5. 返回测试结果和延迟
}
```

### 6.2 测试命令

```bash
# TCP 端口测试
nc -zv ${EXIT_IP} ${EXIT_PORT} -w 5

# 通过 sing-box 测试 (如果已运行)
curl -x socks5://127.0.0.1:${LOCAL_SOCKS_PORT} https://api.ipify.org --connect-timeout 10
```

---

## 七、状态显示

### 7.1 链路状态面板

```
╔══════════════════════════════════════════════════════════════╗
║                      链式代理状态                              ║
╠══════════════════════════════════════════════════════════════╣
║  当前角色: 入口节点 (Entry)                                    ║
║  链路协议: Shadowsocks 2022                                   ║
║  出口地址: 1.2.3.4:54321                                      ║
║  连接状态: ✅ 正常                                             ║
║  最近延迟: 45ms                                               ║
║  运行时间: 2天 5小时                                           ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 八、实现优先级

### Phase 1: 核心功能
- [x] 菜单框架
- [x] 出口节点配置 (Shadowsocks 2022)
- [x] 入口节点配置
- [x] 配置码生成/解析
- [x] 基本连通性测试

### Phase 2: 增强功能
- [ ] 状态面板
- [ ] 防火墙自动配置
- [ ] 多出口节点支持
- [ ] 负载均衡

### Phase 3: 高级功能
- [ ] WireGuard 协议支持
- [ ] 自动故障转移
- [ ] 流量统计
- [ ] Web 管理界面

---

## 九、与现有功能的关系

### 9.1 与 SOCKS5 分流的区别

| 特性 | SOCKS5 分流 | 链式代理 |
|------|------------|----------|
| 加密 | ❌ | ✅ |
| 配置方式 | 手动两端 | 配置码自动 |
| 连通测试 | ❌ | ✅ |
| 状态显示 | 基本 | 详细 |
| 适用场景 | 内网/调试 | 生产环境 |

### 9.2 菜单位置建议

```
主菜单
├── ...
├── 11.分流工具
│   ├── 1.WARP分流
│   ├── 2.WARP分流 IPv6
│   ├── 3.IPv6分流
│   ├── 4.Socks5分流 (保留，用于调试)
│   ├── 5.DNS分流
│   ├── 6.链式代理 [新增，推荐]  ← 新功能
│   └── 7.SNI反向代理
├── ...
```

---

*设计文档版本: v1.0*
*创建日期: 2025-12-13*
