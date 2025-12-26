# Proxy-agent 使用指南

> 适用范围：已安装或准备使用 Proxy-agent 的管理员。本指南按“架构与原理→功能模块→故障排查”展开，尽量用通俗语言解释脚本行为，并结合代码中的默认值与路径，帮助对网络知识只有基础认知的读者正确部署与维护。

## 第一部分：脚本架构与原理

### 1.1 项目概述
- **项目定位**：一键安装、配置并管理 Xray-core 与 sing-box 的多协议代理脚本。入口命令为 `pasly`，菜单覆盖安装、更新、用户、证书、分流、链式代理等运维操作。脚本自带中英文语言包（21 号菜单切换）。
- **核心功能**：通过模块化 Bash 组件管理协议安装、配置文件生成、服务控制、订阅导出、Nginx 伪装站与诊断工具，避免手工修改 JSON 或 systemd 配置导致的错误。
- **支持协议矩阵**：VLESS（TCP/Vision、Reality+Vision、Reality+XHTTP、WS）、VMess（WS、HTTPUpgrade）、Trojan（TCP/gRPC, gRPC 已废弃）、Hysteria2、TUIC、NaiveProxy、AnyTLS、Shadowsocks 2022，以及内部 SOCKS5。协议属性（是否需 TLS/Reality/UDP/CDN）由注册表函数统一判断，避免配置不一致。
- **系统要求**：Debian 9+/Ubuntu 16+/CentOS 7+/Alpine 3+；amd64/arm64；需 root 权限，默认监听 80/443，如已占用需提前释放或调整端口。

### 1.2 目录结构
- **安装根目录**：`/etc/Proxy-agent`（向后兼容 `/etc/v2ray-agent`）。脚本运行会自动创建目录与必要文件。
- **配置文件布局**：
  - `xray/conf/`、`sing-box/conf/config/`：按协议 ID 映射的入站 JSON（如 `02_VLESS_TCP_inbounds.json`、`14_ss2022_inbounds.json`）。
  - `tls/`：自动申请或自备证书与私钥，文件名为域名加后缀 `.crt/.key`。
  - `subscribe/`、`subscribe_local/`：远程/本地订阅输出目录，可由 Nginx 暴露下载。
  - `lib/` 与 `shell/lang/`：脚本模块与语言文件。
- **日志与临时文件**：Xray 访问/错误日志保存在 `xray/access.log` 与 `xray/error.log`；脚本运行产生的 `/tmp/Proxy-agent-*.tmp` 在退出时清理。

### 1.3 代码架构
- **主脚本 (`install.sh`)**：负责错误处理、版本检测（读取 `VERSION` 或远程 release）、模块加载顺序（i18n → constants → utils → json-utils → system-detect → service-control → protocol-registry → config-reader），以及菜单与安装/更新入口。
- **核心模块 (`lib/`)**：
  - `constants.sh`：协议 ID、配置/日志/服务路径、默认端口与带宽、TLS/Nginx 默认值集中定义。
  - `protocol-registry.sh`：协议文件名与显示名映射、TLS/Reality/UDP/CDN 属性判断、安装扫描与菜单标记（推荐/不推荐）。
  - `config-reader.sh`：根据检测到的核心类型返回配置路径，读取端口、用户、域名、Reality 密钥、Hysteria2/TUIC 参数、Nginx 订阅端口等。
  - `utils.sh`、`json-utils.sh`：通用函数与原子化 JSON 读写，防止并发或格式破坏。
  - `system-detect.sh`、`service-control.sh`：系统/架构检测，选择 systemd 或 Alpine init，生成并重载核心服务文件，判定 Nginx 配置路径。
  - `i18n.sh`：加载语言资源，若模块缺失则由 `install.sh` 提供后备文案。
- **函数调用关系**：主脚本加载模块后初始化版本与环境，再根据菜单调用安装、用户、证书、分流等子流程。协议相关查询统一走注册表，配置路径与客户端列表读取由 `config-reader.sh` 封装，服务启停交由 `service-control.sh`。

### 1.4 运行原理
- **流量处理架构**：每个协议在 Xray/sing-box 生成入站监听（`*_inbounds.json`），按协议属性决定是否附加 TLS/Reality/UDP。若启用 Nginx 伪装或订阅站点，前端监听 80/443，将 HTTPS/HTTP 回源到核心端口以隔离证书与业务流量。
- **Nginx 与核心协作**：脚本依据系统自动选择 `/etc/nginx/conf.d/` 或 `/etc/nginx/http.d/` 写入站点配置，静态伪装页与订阅文件放在 Nginx 根目录（`/usr/share/nginx/html/`），核心监听端口通常设为内网高位端口，由 Nginx 反代。
- **配置加载流程**：
  1. 用户在菜单选择协议或组合，脚本通过注册表解析为配置文件名。
  2. 生成/更新对应 JSON 至当前核心配置目录（自动区分 Xray 与 sing-box），写入端口、证书/Reality 参数、传输路径等。
  3. 写入完成后调用服务控制模块重载核心，必要时同时重载 Nginx。

## 第二部分：功能模块详解

### 2.1 协议安装
- **安装入口**：菜单项“安装/重新安装”或“任意组合安装”。后者允许一次选择多个协议，脚本会生成 `,ID,` 形式的状态串保存到变量 `currentInstallProtocolType`，并按选择创建对应入站文件。
- **内核选择**：同一脚本可安装 Xray 或 sing-box。协议与核心兼容性已在注册表区分（如 Hysteria2/TUIC 仅写入 sing-box 目录），无需手动挑选。
- **TLS/Reality 处理**：脚本使用 `protocolRequiresTLS` 与 `protocolUsesReality` 判断是否申请/跳过证书：传统 TLS 协议自动申请并写入 `tls/`；Reality 协议直接生成公私钥与 shortIds，不依赖 ACME。
- **安装注意事项**：
  - 确保域名已解析到服务器且 80/443 未被占用；若已有 Nginx/Apache，请先停用或调整端口。
  - 组合安装时避免选择“已废弃”标记的 gRPC 方案（2/5/8），优先使用 Vision、XHTTP 等推荐项。
  - 升级或重装会覆盖同名配置文件，建议提前备份 `/etc/Proxy-agent`。

### 2.2 用户管理
- **数据结构**：用户信息存放在各协议入站 JSON 的 `clients`（Xray）或 `users`（sing-box）数组中。脚本读取/写入时使用 jq 保证格式正确，不需人工编辑。
- **新增/删除用户**：在菜单“用户管理”选择目标协议，脚本会自动定位对应配置文件并写入 UUID/密码、流量限制等字段，保存后重载核心。
- **多协议同步**：组合安装场景下，可为多协议同时添加同一用户，订阅生成时会输出全部可用节点。确保不同协议的端口、传输路径在客户端分别匹配。
- **客户端查看**：可通过菜单查看用户列表；如需手动确认，使用 `jq '.inbounds[0].settings.clients'` 或 `jq '.inbounds[0].users'` 检查对应 JSON。

### 2.3 证书管理
- **申请流程**：对需要 TLS 的协议，脚本会在安装时自动申请证书并写入 `tls/<域名>.crt/.key`，并在配置中引用。Reality 协议因无需传统证书而跳过。
- **自动续期**：默认续期周期 90 天；可在“证书管理”菜单手动触发续签或重新申请，失败时检查域名解析与防火墙放行 80 端口。
- **自定义证书**：将自备证书文件放入 `tls/` 并命名为 `<域名>.crt/.key`，重新运行证书菜单选择自定义路径即可覆盖自动申请的证书。

### 2.4 分流配置
- **WARP/IPv6 分流**：若启用 WARP，脚本会读取 `/etc/Proxy-agent/warp/config` 中的密钥与 IPv6 地址，为特定路由设置 WARP 出口；同时可选择 IPv6 优先的路由策略。
- **DNS 分流**：在分流工具中为不同协议或域名设置 DNS 服务器，降低污染或劫持风险；调整后需重载核心生效。
- **SNI 反向代理与伪装**：通过 Nginx 在 80/443 提供静态伪装页或 302 跳转，并将实际代理端口隐藏在内网，兼容 CDN 回源。

### 2.5 链式代理
- **工作原理**：出口节点创建 Shadowsocks 2022 或 VLESS(TCP) 入站（推荐 SS2022），入口节点创建对应出站，链路可多路复用并自动加密。
- **配置流程**：
  1. 在出口节点菜单生成链式配置码（包含端口、加密方式、密钥），支持随机端口与密钥。
  2. 在入口节点导入配置码，脚本解析后写入出站与路由，并执行连通性测试。
  3. 可在菜单查看链路状态、修改端口或密钥，或一键卸载链式代理。
- **注意事项**：入口/出口需保持时间同步；如使用防火墙，请放行出口端口和入口到出口的传输端口。

### 2.6 伪装站点
- **内置模板**：脚本提供静态模板，可直接部署到 Nginx 根目录，用于掩饰代理站点。
- **302 重定向/反代**：在伪装站菜单可设置 302 跳转或自定义反代路径，将访问者引导到目标站点，同时为代理端口提供回源入口。
- **自定义伪装**：将自建静态站点文件复制到 Nginx 静态目录即可生效；如需多站点并存，可在 Nginx 配置中新增 server 块。

### 2.7 端口管理
- **默认规则**：HTTPS/HTTP 默认端口 443/80；随机端口范围 10000–30000。Hysteria2 默认带宽下行 100 Mbps、上行 50 Mbps，TUIC 默认拥塞算法 BBR。
- **添加新端口**：在“添加新端口”菜单为已安装协议生成额外入站，脚本会写入新的 JSON 并重载核心，适合多入口或多租户场景。
- **端口跳跃（Hysteria2）**：可调整 Hysteria2 监听端口配合客户端端口跳跃策略；如走 UDP 需确保防火墙放行对应端口范围。

### 2.8 CDN 配置
- **兼容协议**：WS/gRPC/HTTPUpgrade/XHTTP 等协议可结合 CDN；Reality、Hysteria2、TUIC 等 UDP/Reality 协议通常绕过 CDN。
- **优选 IP 管理**：在订阅或客户端配置填入优选回源 IP，结合 CDN 提升延迟与稳定性；变更后需与实际证书域名保持一致或使用自定义回源头。
- **回源与证书**：Nginx 监听 80/443，转发到核心内网端口，证书保存在 `tls/`；如使用自定义端口，请同步更新 Nginx 监听与客户端 SNI。

### 2.9 订阅管理
- **生成位置**：远程订阅输出到 `subscribe/`，本地订阅输出到 `subscribe_local/`，可由 Nginx 暴露或直接下载。
- **格式与命名**：订阅链接名取自协议短名称（如 `vless_reality_xhttp`、`vmess_httpupgrade`、`ss2022`），包含对应端口、传输路径、证书/Reality 参数。
- **使用建议**：配置变更后重新生成订阅并在客户端导入；若使用 CDN，请确认订阅中的域名、端口与回源 IP 匹配。

## 第三部分：故障排查与维护

### 3.1 日志系统
- **日志位置**：Xray 的访问/错误日志位于安装目录的 `xray/access.log` 与 `xray/error.log`；sing-box 使用相同目录结构。Nginx 访问/错误日志遵循系统默认路径（如 `/var/log/nginx/`）。
- **日志级别与格式**：遵循核心默认格式，必要时可在对应入站 JSON 调整 loglevel；遇到连接失败时重点查看握手错误、SNI/证书错误、路由匹配等字段。
- **快速查看**：`tail -f /etc/Proxy-agent/xray/error.log` 或 `journalctl -u xray -f`（sing-box 同理）实时观察报错。

### 3.2 诊断方法
- **服务状态**：使用 `systemctl status xray` / `systemctl status sing-box` 查看运行与重启记录，Alpine 使用 `/etc/init.d/xray status`。
- **端口与连接**：`ss -lntup | grep -E "(443|10000)"` 检查监听，确认无端口被占用；如走 CDN，请用 `curl -I https://域名` 确认 443 可达。
- **配置验证**：核对入站 JSON 是否存在、端口与证书路径匹配，Reality 协议检查 public/private key 与 server_name；客户端导入最新订阅后再测试。

### 3.3 常见问题
- **安装失败**：多因依赖或端口占用。请确认系统版本满足要求、80/443 未被占用且能访问 GitHub Release；必要时手动下载脚本并离线执行。
- **连接失败**：常见于证书未签发、域名解析错误、CDN 回源异常或时间不同步。请先用浏览器/`curl` 验证 HTTPS，再检查核心日志与 Nginx 配置。
- **性能异常**：Hysteria2/TUIC 可调整带宽、拥塞算法或多路复用；链式代理建议优先 SS2022；CPU/内存不足时减少并发或禁用不需要的协议。

### 3.4 维护与更新
- **脚本更新**：启动时比对本地 `VERSION` 与 GitHub 最新版本，检测到更新会提示；在菜单选择“更新脚本”自动下载覆盖。
- **核心更新**：通过“Core 管理”更新 Xray/sing-box 二进制，路径分别为 `/etc/Proxy-agent/xray/xray` 与 `/etc/Proxy-agent/sing-box/sing-box`。
- **备份/恢复**：备份 `/etc/Proxy-agent` 整个目录（含配置、订阅、证书）；恢复后确保 systemd 服务文件与权限正确，再重启核心与 Nginx。
- **完全卸载**：菜单“卸载脚本”会删除安装目录、systemd/Alpine 服务与相关配置；如曾启用 Nginx 站点或防火墙放行，请手动清理残留。

## 附录
- **A. 端口分配表**：默认 HTTP/HTTPS 端口 80/443；随机端口 10000–30000；Hysteria2 默认 50/100 Mbps 上下行；TUIC 默认拥塞算法 BBR。
- **B. 配置文件命名规则**：入站文件以协议 ID 前缀命名，例如 `02_VLESS_TCP_inbounds.json`（VLESS TCP+Vision）、`14_ss2022_inbounds.json`（Shadowsocks 2022），由注册表自动映射，无需手写。
- **C. 命令速查**：
  - 打开菜单：`pasly`
  - 切换语言：`V2RAY_LANG=en pasly`
  - 查看版本：`cat /etc/Proxy-agent/VERSION`
  - 核心状态：`systemctl status xray` / `systemctl status sing-box`
