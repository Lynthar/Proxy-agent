# Proxy-agent vs v2ray-agent 全面对比分析报告

**分析日期**: 2025-12-18
**比较对象**:
- Proxy-agent (Lynthar/Proxy-agent)
- v2ray-agent (mack-a/v2ray-agent)

---

## 一、基本概况对比

| 特性 | Proxy-agent (Lynthar) | v2ray-agent (mack-a) |
|------|----------------------|---------------------|
| **代码行数** | 12,988 行 | 9,641 行 |
| **函数数量** | 228 个 | 187 个 |
| **架构模式** | **模块化** (install.sh + lib/*.sh) | **单文件** (install.sh) |
| **配置目录** | `/etc/Proxy-agent/` | `/etc/v2ray-agent/` |
| **管理命令** | `pasly` | `vasma` |
| **许可证** | AGPL-3.0 | AGPL-3.0 |
| **社区规模** | Fork 项目 | 18k+ stars, 5.2k+ forks |

---

## 二、架构差异分析

### 1. Proxy-agent 模块化架构

```
Proxy-agent/
├── install.sh           # 主脚本 (12,988行)
├── lib/                 # 模块库 (8个模块)
│   ├── constants.sh     # 协议ID、路径常量、辅助函数
│   ├── utils.sh         # 通用工具函数 (字符串、UUID、网络)
│   ├── i18n.sh          # 国际化加载器
│   ├── json-utils.sh    # JSON操作封装 (70+函数)
│   ├── system-detect.sh # 系统检测模块
│   ├── service-control.sh # 服务控制模块
│   ├── protocol-registry.sh # 协议注册表
│   └── config-reader.sh # 配置读取接口
├── shell/lang/          # 语言文件
│   ├── zh_CN.sh         # 中文 (30,646行，600+翻译)
│   └── en_US.sh         # 英文 (30,407行)
├── tests/               # 测试框架
│   ├── test_modules.sh  # 模块单元测试 (68个用例)
│   └── test_integration.sh # 集成测试 (32个用例)
└── documents/           # 文档资料
```

**模块加载机制**:
```bash
# install.sh 开头
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="${_SCRIPT_DIR}/lib"

if [[ -d "${_LIB_DIR}" ]]; then
    for _module in i18n constants utils json-utils ...; do
        source "${_LIB_DIR}/${_module}.sh"
    done
fi
```

**关键特点**:
- 渐进式模块化重构
- 模块通过 `source` 动态加载
- 防重复加载机制 (`[[ -n "${_MODULE_LOADED}" ]] && return 0`)
- 支持独立运行 install.sh (模块为增强功能)

### 2. v2ray-agent 单文件架构

```
v2ray-agent/
├── install.sh           # 主脚本 (9,641行，包含所有功能)
├── shell/               # 辅助脚本
│   ├── empty_login_history.sh
│   ├── init_tls.sh
│   ├── send_email.sh
│   └── ufw_remove.sh
├── fodder/              # 资源文件
└── documents/           # 文档资料
```

**关键特点**:
- 所有功能集中在单一文件
- 无模块化组织
- 依赖外部 shell 脚本为辅助功能
- 代码紧凑，部署简单

---

## 三、功能差异对比

### 1. Proxy-agent 独有功能

| 功能 | 描述 |
|------|------|
| **国际化 (i18n)** | 中/英双语支持，600+ 翻译键 |
| **链式代理管理** | 多节点代理链 (Entry → Relay → Exit)，使用 SS2022 |
| **测试框架** | 100 个自动化测试用例 |
| **语言切换菜单** | 菜单选项 21 - 动态切换语言 |
| **自动更新检测** | 启动时检查 GitHub Release 新版本 |
| **JSON工具库** | 70+ JSON操作函数，原子写入，类型安全 |
| **常量管理** | 协议ID映射、配置路径、显示名称等集中管理 |
| **安全增强** | 域名/URL验证、SHA256校验、命令注入防护 |
| **错误处理** | 全局 `set -o pipefail`、错误处理函数、清理函数 |

### 2. v2ray-agent 独有/差异功能

| 功能 | 描述 |
|------|------|
| **推广信息** | 菜单显示 VPS 推荐链接 |
| **博客整合** | 链接到 v2ray-agent.com 教程 |
| **成熟稳定** | 260+ Release 版本，更成熟稳定 |
| **活跃社区** | 大量用户反馈和问题修复 |

### 3. 共同支持的协议

| 协议 | Proxy-agent | v2ray-agent |
|------|:-----------:|:-----------:|
| VLESS+Vision | ✅ | ✅ |
| VLESS+WS | ✅ | ✅ |
| VMess+WS | ✅ | ✅ |
| Trojan+TCP | ✅ | ✅ |
| Trojan+gRPC | ✅ | ✅ |
| VLESS+gRPC | ✅ | ✅ |
| VLESS+Reality+Vision | ✅ | ✅ |
| VLESS+Reality+gRPC | ✅ | ✅ |
| VLESS+Reality+XHTTP | ✅ | ✅ |
| Hysteria2 | ✅ | ✅ |
| TUIC | ✅ | ✅ |
| NaiveProxy | ✅ | ✅ |
| Shadowsocks 2022 | ✅ | ✅ |
| AnyTLS | ✅ | ✅ |
| VMess+HTTPUpgrade | ✅ | ✅ |

---

## 四、代码质量对比

### 1. Proxy-agent 代码改进

#### 全局错误处理 (install.sh:12-34)
```bash
set -o pipefail

_error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    if [[ ${exit_code} -ne 0 ]]; then
        echo -e "\033[31m[错误] 脚本在第 ${line_number} 行发生错误\033[0m" >&2
        echo -e "\033[31m[错误] 命令: ${command}\033[0m" >&2
        echo -e "\033[31m[错误] 退出码: ${exit_code}\033[0m" >&2
    fi
}

_cleanup() {
    rm -f /tmp/Proxy-agent-*.tmp 2>/dev/null
}
trap '_cleanup' EXIT
```

#### 域名验证防注入 (install.sh:227-248)
```bash
isValidDomain() {
    local domain="$1"
    [[ -z "${domain}" ]] && return 1
    # 检查危险字符（命令注入防护）
    if [[ "${domain}" =~ [\;\|\&\$\`\(\)\{\}\[\]\<\>\!\#\*\?\~\'\"] ]]; then
        return 1
    fi
    # 检查空格或换行
    if [[ "${domain}" =~ [[:space:]] ]]; then
        return 1
    fi
    # 基本域名格式验证
    if [[ ! "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    return 0
}
```

#### SHA256 校验 (install.sh:269-296)
```bash
verifySHA256() {
    local file="$1"
    local expectedHash="$2"

    local actualHash
    if command -v sha256sum &>/dev/null; then
        actualHash=$(sha256sum "${file}" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actualHash=$(shasum -a 256 "${file}" | awk '{print $1}')
    fi

    if [[ "${actualHash,,}" == "${expectedHash,,}" ]]; then
        return 0
    else
        echoContent red " ---> 校验失败: SHA256不匹配"
        return 1
    fi
}
```

### 2. v2ray-agent 原始代码风格

```bash
# 直接内联所有逻辑，无模块化
echoContent() {
    case $1 in
    "red") ${echoType} "\033[31m${printN}$2 \033[0m" ;;
    "green") ${echoType} "\033[32m${printN}$2 \033[0m" ;;
    esac
}

# 硬编码消息（纯中文）
echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
echoContent yellow "检测到SELinux已开启，请手动关闭"

# 无输入验证
read -r -p "请输入域名:" domain
# 直接使用 domain 变量
```

---

## 五、国际化系统详解

### Proxy-agent i18n 实现

**1. 语言检测优先级**:
```
V2RAY_LANG环境变量 > /etc/Proxy-agent/lang_pref文件 > LANGUAGE > LANG > 默认中文
```

**2. 翻译函数 (lib/i18n.sh)**:
```bash
t() {
    local key="MSG_$1"
    local text="${!key:-$1}"  # 找不到则显示key本身
    shift
    if [[ $# -gt 0 ]]; then
        printf "${text}" "$@"  # 支持 %s 格式化
    else
        echo "${text}"
    fi
}
```

**3. 使用示例**:
```bash
# 简单消息
echoContent yellow "1.$(t MENU_REINSTALL)"

# 带参数消息
echoContent red "$(t PORT_OCCUPIED "${port}")"

# shell/lang/zh_CN.sh
MSG_PORT_OCCUPIED="端口 %s 被占用，请手动关闭后安装"
```

**4. 语言切换**:
```bash
# 方式1: 菜单选项 21
# 方式2: 环境变量
V2RAY_LANG=en pasly
# 方式3: 安装时指定
V2RAY_LANG=en bash install.sh
```

---

## 六、链式代理功能 (Proxy-agent 独有)

### 设计架构

```
                                 ┌─────────────────┐
Client ──► Entry节点 ──► Relay节点(可选) ──► Exit节点 ──► Internet
           (入口)        (中继，可多层)      (出口)
```

### 配置向导

```bash
chainProxyMenu() {
    # 1.快速配置向导 [推荐]
    # 2.查看链路状态
    # 3.测试链路连通性
    # 4.高级设置
    # 5.卸载链式代理
}

chainProxyWizard() {
    # 1.出口节点 (Exit) - 生成配置码
    # 2.中继节点 (Relay) - 导入下游，生成上游配置码
    # 3.入口节点 (Entry) - 导入配置码
    # 4.手动配置入口节点
}
```

### 技术实现

- 使用 Shadowsocks 2022 协议 (加密安全、性能优秀)
- 基于 sing-box 核心
- 支持配置码自动生成/导入
- 链路连通性测试功能
- 支持多层中继: 入口→中继1→中继2→...→出口

---

## 七、JSON工具库对比

### Proxy-agent json-utils.sh (70+ 函数)

| 类别 | 函数 | 描述 |
|------|------|------|
| **验证** | `jsonValidateFile()` | 验证JSON文件语法 |
| | `jsonValidateString()` | 验证JSON字符串语法 |
| **读取** | `jsonGetValue()` | 从文件读取值 |
| | `jsonGetArray()` | 读取数组 |
| | `jsonGetArrayLength()` | 获取数组长度 |
| | `jsonGetFromString()` | 从字符串读取值 |
| **修改** | `jsonSetValue()` | 设置JSON值 |
| | `jsonSetString()` | 设置字符串值 |
| | `jsonArrayAppend()` | 向数组添加元素 |
| | `jsonArrayDeleteByIndex()` | 删除数组元素 |
| **安全写入** | `jsonWriteFile()` | 原子写入+备份 |
| | `jsonModifyFile()` | 安全修改文件 |
| **Xray专用** | `xrayGetInboundPort()` | 读取入站端口 |
| | `xrayGetRealityConfig()` | 读取Reality配置 |
| | `xrayGetTLSDomain()` | 读取TLS域名 |
| **sing-box专用** | `singboxGetInboundPort()` | 读取入站端口 |
| | `singboxGetHysteria2Config()` | 读取Hysteria2配置 |
| | `singboxGetTuicConfig()` | 读取TUIC配置 |

### 原子写入示例

```bash
jsonWriteFile() {
    local file="$1"
    local content="$2"
    local backup="${3:-true}"

    # 验证JSON语法
    if ! echo "${content}" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    # 创建备份
    if [[ "${backup}" == "true" && -f "${file}" ]]; then
        cp "${file}" "${file}.bak.$(date +%s)" 2>/dev/null
    fi

    # 写入临时文件
    local tmpFile="${JSON_TMP_PREFIX}_$$_$(date +%s)"
    echo "${content}" | jq . > "${tmpFile}" 2>/dev/null

    # 原子移动
    mv "${tmpFile}" "${file}" 2>/dev/null
}
```

### v2ray-agent

- 直接使用 jq 命令，无封装
- 无原子写入保护
- 无统一错误处理

---

## 八、菜单结构对比

### Proxy-agent 菜单

```
==============================================================
作者: Lynthar
当前版本: v3.6.0
Github: https://github.com/Lynthar/Proxy-agent
描述: 八合一共存脚本
==============================================================
1.安装/重新安装
2.任意组合安装
3.链式代理管理           ← 独有
4.Hysteria2 管理
5.REALITY 管理
6.Tuic 管理
-------------------------工具管理-----------------------------
7.用户管理
8.伪装站管理
9.证书管理
10.CDN 节点管理
11.分流工具
12.添加新端口
13.BT 下载管理
15.域名黑名单
-------------------------版本管理-----------------------------
16.Core 管理
17.更新脚本
18.安装 BBR、DD 脚本
-------------------------脚本管理-----------------------------
20.卸载脚本
21.切换语言 / Switch Language   ← 独有
==============================================================
```

### v2ray-agent 菜单

```
==============================================================
作者：mack-a
当前版本：v3.5.3
Github：https://github.com/mack-a/v2ray-agent
描述：八合一共存脚本
=========================== 推广区============================   ← 独有区域
VPS选购攻略
https://www.v2ray-agent.com/archives/...
年付10美金低价VPS AS4837
...
==============================================================
1.安装/重新安装
2.任意组合安装
(无选项3)
4.Hysteria2管理
...
20.卸载脚本
==============================================================
```

---

## 九、测试框架 (Proxy-agent 独有)

### test_modules.sh (68 用例)

```bash
# 工具函数测试
test_utils_randomNum()
test_utils_isValidPort()
test_utils_stripAnsi()
test_utils_urlEncode()
test_utils_isValidUUID()

# JSON工具测试
test_json_validate()
test_json_get_value()
test_json_modify()
test_json_atomic_write()

# 协议注册表测试
test_protocol_registry_lookup()
test_protocol_config_path()
```

### test_integration.sh (32 用例)

```bash
# 集成测试
test_full_installation_flow()
test_config_generation()
test_service_control()
test_user_management()
test_certificate_renewal()
```

---

## 十、配置目录结构对比

### Proxy-agent (/etc/Proxy-agent/)

```
/etc/Proxy-agent/
├── install.sh          # 主脚本
├── VERSION             # 版本号
├── lang_pref           # 语言设置
├── xray/               # Xray-core 配置和二进制
│   ├── xray
│   └── conf/
├── sing-box/           # sing-box 配置和二进制
│   ├── sing-box
│   └── conf/
├── tls/                # TLS 证书
├── subscribe/          # 订阅文件
├── lib/                # 模块库
└── shell/lang/         # 语言文件
```

### v2ray-agent (/etc/v2ray-agent/)

```
/etc/v2ray-agent/
├── xray/
│   ├── xray
│   └── conf/
├── sing-box/
│   ├── sing-box
│   └── conf/
├── tls/
└── subscribe/
```

---

## 十一、总结与建议

### Proxy-agent 优势

1. **模块化架构** - 代码可维护性高，易于扩展
2. **国际化支持** - 中英双语，用户友好
3. **链式代理** - 独有的多节点代理链功能
4. **代码质量** - 安全验证、错误处理、测试覆盖
5. **JSON工具库** - 类型安全、原子写入
6. **自动更新检测** - 启动时检查新版本

### v2ray-agent 优势

1. **成熟稳定** - 260+ 版本迭代，社区验证
2. **部署简单** - 单文件，无依赖
3. **社区支持** - 18k+ 星标，活跃维护
4. **文档完善** - 配套博客和教程

### 适用场景推荐

| 场景 | 推荐 |
|------|------|
| 需要中英文切换 | **Proxy-agent** |
| 需要链式代理 | **Proxy-agent** |
| 追求代码质量 | **Proxy-agent** |
| 开发/二次开发 | **Proxy-agent** |
| 追求稳定性 | **v2ray-agent** |
| 初学者使用 | **v2ray-agent** |
| 需要社区支持 | **v2ray-agent** |

---

## 附录：代码量统计

### Proxy-agent

| 文件 | 行数 |
|------|------|
| install.sh | 12,988 |
| lib/constants.sh | 242 |
| lib/utils.sh | 362 |
| lib/i18n.sh | 93 |
| lib/json-utils.sh | 767 |
| lib/service-control.sh | 395 |
| shell/lang/zh_CN.sh | 30,646 |
| shell/lang/en_US.sh | 30,407 |
| tests/test_modules.sh | 14,255 |
| tests/test_integration.sh | 18,436 |
| **总计** | **~108,591** |

### v2ray-agent

| 文件 | 行数 |
|------|------|
| install.sh | 9,641 |
| shell/*.sh | ~500 |
| **总计** | **~10,141** |
