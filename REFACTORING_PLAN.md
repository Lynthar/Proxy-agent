# Proxy-agent 重构计划

## 概述

本计划旨在将 `install.sh` 从单一大型脚本重构为模块化结构，提高代码可维护性和可读性。

## 当前状态分析

- **总行数**: 12,308
- **函数数量**: 216
- **全局变量**: 62+
- **最大函数**: initSingBoxConfig (~500行)

## 重构原则

1. **渐进式重构** - 每次只改动一小部分，确保不破坏现有功能
2. **向后兼容** - 模块化后仍能独立运行完整脚本
3. **测试优先** - 每次改动后进行语法检查和功能验证
4. **保守策略** - 对紧耦合代码采取观察策略，不急于拆分

## 模块划分

### Phase 1: 安全提取（低风险）

```
lib/
├── constants.sh      # 常量定义（协议ID、文件路径、默认值）
├── utils.sh          # 纯工具函数（无副作用）
├── system-detect.sh  # 系统检测函数
└── service-control.sh # 服务控制函数
```

### Phase 2: 配置抽象（中等风险）

```
lib/
├── config-reader.sh  # 配置读取接口
├── protocol-registry.sh # 协议注册表
└── json-utils.sh     # JSON操作封装
```

### Phase 3: 高级模块（高风险，需要Phase 1-2完成）

```
lib/
├── tls-manager.sh    # TLS证书管理
├── subscription.sh   # 订阅生成
├── user-manager.sh   # 用户管理
└── menu-framework.sh # 菜单框架
```

## Phase 1 详细计划

### 1.1 constants.sh

定义所有硬编码常量：

```bash
# 协议ID映射
readonly PROTOCOL_VLESS_TCP=0
readonly PROTOCOL_VLESS_WS=1
readonly PROTOCOL_TROJAN_GRPC=2
readonly PROTOCOL_VMESS_WS=3
readonly PROTOCOL_TROJAN_TCP=4
readonly PROTOCOL_VLESS_GRPC=5
readonly PROTOCOL_HYSTERIA2=6
readonly PROTOCOL_VLESS_REALITY_VISION=7
readonly PROTOCOL_VLESS_REALITY_GRPC=8
readonly PROTOCOL_TUIC=9
readonly PROTOCOL_NAIVE=10
readonly PROTOCOL_VMESS_HTTPUPGRADE=11
readonly PROTOCOL_XHTTP=12
readonly PROTOCOL_ANYTLS=13
readonly PROTOCOL_SS2022=14

# 配置文件路径
readonly XRAY_CONFIG_DIR="/etc/v2ray-agent/xray/conf"
readonly SINGBOX_CONFIG_DIR="/etc/v2ray-agent/sing-box/conf/config"
readonly TLS_DIR="/etc/v2ray-agent/tls"
```

### 1.2 utils.sh

提取纯函数：

- `stripAnsi()` - 移除ANSI控制字符
- `randomNum()` - 生成随机数
- `validateJsonFile()` - 验证JSON文件
- `echoContent()` - 彩色输出（已存在，保持原样）

### 1.3 system-detect.sh

提取系统检测：

- `checkSystem()` - 检测操作系统
- `checkCPUVendor()` - 检测CPU架构
- `checkRoot()` - 检查root权限

### 1.4 service-control.sh

提取服务控制：

- `handleXray()` - Xray服务控制
- `handleSingBox()` - sing-box服务控制
- `handleNginx()` - Nginx服务控制
- `handleFirewall()` - 防火墙控制

## 实施策略

### 步骤1: 创建模块文件

在 `lib/` 目录下创建模块文件，先只包含函数定义，不修改主脚本。

### 步骤2: 添加条件加载

在主脚本开头添加条件加载逻辑：

```bash
# 加载模块（如果存在）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

if [[ -d "${LIB_DIR}" ]]; then
    for module in constants utils system-detect service-control; do
        if [[ -f "${LIB_DIR}/${module}.sh" ]]; then
            source "${LIB_DIR}/${module}.sh"
        fi
    done
fi
```

### 步骤3: 渐进替换

逐步将主脚本中的函数替换为模块调用，每次替换后进行测试。

### 步骤4: 清理

当所有函数都从模块加载后，从主脚本中移除重复代码。

## 风险评估

| 模块 | 风险等级 | 依赖复杂度 | 预计工作量 |
|------|----------|------------|------------|
| constants.sh | 低 | 无依赖 | 1小时 |
| utils.sh | 低 | 无依赖 | 1小时 |
| system-detect.sh | 低 | 写入release等变量 | 2小时 |
| service-control.sh | 中 | 依赖coreInstallType | 2小时 |
| config-reader.sh | 中 | 依赖多个路径变量 | 4小时 |
| protocol-registry.sh | 高 | 影响40+函数 | 8小时 |

## 变量命名规范

### 统一使用 camelCase

```bash
# 正确
currentInstallProtocolType
singBoxConfigPath
hysteria2ClientDownloadSpeed

# 避免
current_install_protocol_type  # snake_case
SINGBOX_CONFIG_PATH           # 除常量外避免全大写
```

### 布尔变量命名

```bash
# 使用 is/has/should 前缀或 Enabled 后缀
isRealityEnabled      # 替代 realityStatus
hasValidCertificate   # 替代 sslStatus
shouldInstallTLS      # 替代 installTLSFlag
```

### 集合变量命名

```bash
# 复数形式表示数组
clients        # 替代 currentClients（如果仅表示当前）
protocols      # 表示协议数组
outbounds      # 表示出站配置数组
```

## 完成状态

### Phase 1: 已完成 ✅

- [x] `lib/constants.sh` - 协议ID、配置路径、默认值、辅助函数
- [x] `lib/utils.sh` - 字符串处理、JSON验证、UUID、网络工具
- [x] `lib/system-detect.sh` - 系统检测、CPU检测、容器检测
- [x] `lib/service-control.sh` - Xray/sing-box/Nginx服务控制

### Phase 2: 已完成 ✅

- [x] `lib/json-utils.sh` - JSON安全读写、验证、修改、原子操作
- [x] `lib/protocol-registry.sh` - 协议注册表、检测、属性查询
- [x] `lib/config-reader.sh` - 配置读取接口、Reality/Hysteria2/TUIC配置

### Phase 3: 待实施 ⏳

- [ ] `lib/tls-manager.sh` - TLS证书管理（ACME、SSL续期）
- [ ] `lib/subscription.sh` - 订阅生成（各格式支持）
- [ ] `lib/user-manager.sh` - 用户CRUD操作
- [ ] `lib/menu-framework.sh` - 菜单渲染框架

## 下一步行动

Phase 3 为高风险模块，建议：
1. 在生产环境验证 Phase 1-2 稳定性
2. 收集用户反馈
3. 逐步实施 Phase 3 模块

## 注意事项

- 每次更改后运行 `bash -n install.sh` 检查语法
- 保留所有原始函数直到确认模块工作正常
- 使用 `readonly` 声明常量
- 使用 `local` 声明函数内部变量
- 添加详细注释说明模块用途
