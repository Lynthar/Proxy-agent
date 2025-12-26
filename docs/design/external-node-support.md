# 外部节点支持设计文档

## 1. 概述

### 1.1 背景
用户可能"拼车"使用他人的代理节点（如 SS、Trojan），只有节点连接信息，没有服务器 root 权限。
本功能允许用户将这类外部节点作为链式代理的**出口节点**使用。

### 1.2 使用场景
```
用户流量 → 入口机(有root，安装脚本) → 外部节点(拼车SS/Trojan) → 互联网
                    ↓                           ↓
              配置入口协议                  只需连接信息
              (Hysteria2/VLESS等)           无需root权限
```

### 1.3 支持的协议
| 协议 | 链接格式 | 备注 |
|------|---------|------|
| Shadowsocks | `ss://method:password@host:port#name` | 传统SS |
| Shadowsocks 2022 | `ss://2022-blake3-*:password@host:port#name` | SS2022 |
| SOCKS5 | `socks5://[user:pass@]host:port#name` | 可选认证 |
| Trojan | `trojan://password@host:port?sni=xxx#name` | 支持TLS参数 |

---

## 2. 数据结构设计

### 2.1 外部节点信息 (`external_node_info.json`)

```json
{
    "nodes": [
        {
            "id": "ext_1",
            "name": "US-SS-Node",
            "type": "shadowsocks",
            "server": "us.example.com",
            "server_port": 8388,
            "method": "aes-256-gcm",
            "password": "password123",
            "enabled": true,
            "created_at": "2025-12-26T12:00:00Z",
            "last_test": "2025-12-26T12:30:00Z",
            "latency": 150
        },
        {
            "id": "ext_2",
            "name": "HK-Trojan-Node",
            "type": "trojan",
            "server": "hk.example.com",
            "server_port": 443,
            "password": "trojan-password",
            "tls": {
                "enabled": true,
                "server_name": "hk.example.com",
                "insecure": false
            },
            "enabled": true
        },
        {
            "id": "ext_3",
            "name": "JP-SOCKS5",
            "type": "socks",
            "server": "jp.example.com",
            "server_port": 1080,
            "username": "user",
            "password": "pass",
            "enabled": true
        }
    ]
}
```

存储位置: `/etc/Proxy-agent/sing-box/conf/external_node_info.json`

### 2.2 各协议配置字段

#### Shadowsocks / SS2022
```json
{
    "type": "shadowsocks",
    "server": "string (必填)",
    "server_port": "number (必填)",
    "method": "string (必填, 如 aes-256-gcm, 2022-blake3-aes-128-gcm)",
    "password": "string (必填)",
    "plugin": "string (可选, obfs-local/v2ray-plugin)",
    "plugin_opts": "string (可选)"
}
```

#### SOCKS5
```json
{
    "type": "socks",
    "server": "string (必填)",
    "server_port": "number (必填)",
    "version": "5 (默认)",
    "username": "string (可选)",
    "password": "string (可选)"
}
```

#### Trojan
```json
{
    "type": "trojan",
    "server": "string (必填)",
    "server_port": "number (必填)",
    "password": "string (必填)",
    "tls": {
        "enabled": true,
        "server_name": "string (可选, 默认使用server)",
        "insecure": false,
        "alpn": ["h2", "http/1.1"]
    }
}
```

---

## 3. 用户界面设计

### 3.1 菜单结构

在链式代理菜单中添加入口:
```
链式代理菜单
├── 1. 配置出口节点
├── 2. 配置入口节点（单链路）
├── 3. 配置中继节点
├── 4. 配置入口节点（多链路分流）
├── 5. 配置入口节点（外部节点）  ← 新增
├── ...
```

### 3.2 外部节点管理菜单

```
外部节点管理
==============================================================
已配置的外部节点:
  1. [SS] US-SS-Node (us.example.com:8388) - 150ms
  2. [Trojan] HK-Trojan (hk.example.com:443) - 89ms
  3. [SOCKS5] JP-SOCKS5 (jp.example.com:1080) - 未测试

操作选项:
  a. 添加外部节点
  b. 删除外部节点
  c. 测试节点连通性
  d. 将节点设为链式代理出口
  0. 返回
==============================================================
```

### 3.3 添加节点流程

#### 方式一：解析链接
```
添加外部节点
==============================================================
选择添加方式:
  1. 粘贴节点链接 (ss://, trojan://, socks5://)
  2. 手动输入配置
  0. 返回

请选择: 1

请粘贴节点链接:
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@us.example.com:8388#US-Node

解析结果:
  协议: Shadowsocks
  服务器: us.example.com
  端口: 8388
  加密方式: aes-256-gcm
  名称: US-Node

确认添加? [y/n]: y
---> 节点已添加
```

#### 方式二：手动输入
```
手动添加节点
==============================================================
选择协议类型:
  1. Shadowsocks
  2. Shadowsocks 2022
  3. SOCKS5
  4. Trojan

请选择: 1

请输入服务器地址: us.example.com
请输入端口: 8388
请选择加密方式:
  1. aes-256-gcm
  2. aes-128-gcm
  3. chacha20-ietf-poly1305
请选择: 1
请输入密码: ********
请输入节点名称 (可选): US-Node

---> 节点已添加
```

### 3.4 设为链式代理出口

```
将外部节点设为链式代理出口
==============================================================
当前入口协议: Hysteria2 (:443)

选择出口节点:
  1. [SS] US-SS-Node (us.example.com:8388)
  2. [Trojan] HK-Trojan (hk.example.com:443)

请选择: 1

配置模式:
  1. 单出口 (所有流量走此节点)
  2. 多出口分流 (配合规则分流)

请选择: 1

---> 正在配置...
---> 生成 sing-box 出站配置...
---> 更新路由规则...
---> 重启 sing-box 服务...
---> 配置完成!

当前链路: 用户 → Hysteria2 → SS(US-Node) → 互联网
```

---

## 4. sing-box 配置生成

### 4.1 Shadowsocks 出站

```json
{
    "type": "shadowsocks",
    "tag": "external_ss_us",
    "server": "us.example.com",
    "server_port": 8388,
    "method": "aes-256-gcm",
    "password": "password123"
}
```

### 4.2 Shadowsocks 2022 出站

```json
{
    "type": "shadowsocks",
    "tag": "external_ss2022_hk",
    "server": "hk.example.com",
    "server_port": 8388,
    "method": "2022-blake3-aes-128-gcm",
    "password": "base64_encoded_key"
}
```

### 4.3 SOCKS5 出站

```json
{
    "type": "socks",
    "tag": "external_socks_jp",
    "server": "jp.example.com",
    "server_port": 1080,
    "version": "5",
    "username": "user",
    "password": "pass"
}
```

### 4.4 Trojan 出站

```json
{
    "type": "trojan",
    "tag": "external_trojan_hk",
    "server": "hk.example.com",
    "server_port": 443,
    "password": "trojan-password",
    "tls": {
        "enabled": true,
        "server_name": "hk.example.com",
        "insecure": false,
        "alpn": ["h2", "http/1.1"]
    }
}
```

### 4.5 路由规则配置

单出口模式:
```json
{
    "route": {
        "rules": [],
        "final": "external_ss_us"
    }
}
```

多出口分流模式 (复用现有 multi-chain 机制):
```json
{
    "route": {
        "rules": [
            {
                "rule_set": ["geosite-netflix", "geosite-disney"],
                "outbound": "external_ss_us"
            },
            {
                "rule_set": ["geosite-openai", "geosite-anthropic"],
                "outbound": "external_trojan_hk"
            }
        ],
        "final": "external_ss_us"
    }
}
```

---

## 5. 链接解析规则

### 5.1 Shadowsocks 链接

**标准格式:**
```
ss://BASE64(method:password)@host:port#name
ss://BASE64(method:password)@host:port/?plugin=xxx#name
```

**SIP002 格式:**
```
ss://BASE64(method:password)@host:port#name
```

**解析示例:**
```
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@us.example.com:8388#US-Node
↓ Base64解码
aes-256-gcm:password
```

### 5.2 Trojan 链接

**格式:**
```
trojan://password@host:port?sni=xxx&alpn=h2,http/1.1&allowInsecure=0#name
```

**参数:**
- `sni`: TLS SNI
- `alpn`: ALPN 协议
- `allowInsecure`: 是否允许不安全证书 (0/1)
- `type`: 传输类型 (tcp/ws/grpc)

### 5.3 SOCKS5 链接

**格式:**
```
socks5://host:port#name
socks5://username:password@host:port#name
```

---

## 6. 与现有功能的集成

### 6.1 集成点

1. **链式代理菜单** (`chainProxyMenu`)
   - 添加选项 "5. 配置外部节点作为出口"

2. **多链路分流** (`setupMultiChainEntry`)
   - 在链路选择时，支持选择外部节点
   - 复用现有的规则配置机制

3. **配置合并** (`mergeSingBoxConfig`)
   - 将外部节点出站配置合并到最终配置

### 6.2 新增函数

```bash
# 外部节点管理
externalNodeMenu()           # 外部节点管理菜单
addExternalNode()            # 添加外部节点
removeExternalNode()         # 删除外部节点
listExternalNodes()          # 列出外部节点
testExternalNode()           # 测试节点连通性

# 链接解析
parseSSLink()                # 解析 ss:// 链接
parseTrojanLink()            # 解析 trojan:// 链接
parseSOCKS5Link()            # 解析 socks5:// 链接
parseExternalLink()          # 统一解析入口

# 配置生成
generateExternalOutbound()   # 生成外部节点出站配置
setupExternalAsChainExit()   # 将外部节点设为链式代理出口
```

### 6.3 文件结构

```
/etc/Proxy-agent/sing-box/conf/
├── external_node_info.json           # 外部节点信息存储
├── config/
│   ├── external_outbound.json        # 外部节点出站配置
│   └── external_route.json           # 外部节点路由配置 (如有)
```

---

## 7. 安全考虑

### 7.1 密码存储
- 密码明文存储在本地 JSON 文件中
- 文件权限设置为 600 (仅 root 可读写)

### 7.2 连接测试
- 测试连通性时使用 TCP 探测
- 可选进行代理功能测试 (通过代理访问测试URL)

### 7.3 证书验证
- Trojan 默认启用证书验证
- 提供 `insecure` 选项供用户选择 (不推荐)

---

## 8. 实现优先级

### Phase 1: 基础功能
- [ ] 外部节点数据结构和存储
- [ ] 手动添加节点 (SS, SOCKS5)
- [ ] 单出口模式配置

### Phase 2: 链接解析
- [ ] SS 链接解析
- [ ] Trojan 链接解析
- [ ] SOCKS5 链接解析

### Phase 3: 高级功能
- [ ] SS2022 支持
- [ ] 多出口分流 (与 multi-chain 集成)
- [ ] 节点连通性测试
- [ ] 批量导入

---

## 9. 用户文档

### 快速开始

1. 进入链式代理菜单，选择 "外部节点管理"
2. 选择 "添加外部节点"
3. 粘贴拼车获得的节点链接 (如 `ss://...`)
4. 确认添加后，选择 "将节点设为链式代理出口"
5. 完成配置，流量将通过外部节点出口

### 注意事项

- 确保入口机器已配置入口协议 (如 Hysteria2, VLESS)
- 外部节点的稳定性取决于拼车方的服务质量
- 建议定期测试节点连通性
