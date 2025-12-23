# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![GitHub Release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent?label=Release)](https://github.com/Lynthar/Proxy-agent/releases)
[![中文](https://img.shields.io/badge/中文-README-blue)](../../README.md)

A fork of [v2ray-agent](https://github.com/mack-a/v2ray-agent), providing one-click installation and management for Xray-core / sing-box.

## Features

### Multi-Core Support
- **Xray-core** - High-performance proxy core
- **sing-box** - Next-generation universal proxy platform

### Supported Protocols
| Protocol | Transport | Description |
|----------|-----------|-------------|
| VLESS | TCP/Vision, WebSocket, XHTTP | Lightweight protocol |
| VMess | WebSocket, HTTPUpgrade | V2Ray native protocol |
| Trojan | TCP | HTTPS traffic disguise |
| Hysteria2 | QUIC | High-speed UDP protocol |
| TUIC | QUIC | Low-latency UDP protocol |
| Reality | Vision, XHTTP | No domain/certificate required |
| NaiveProxy | - | Anti-detection protocol |
| Shadowsocks 2022 | - | Next-gen SS protocol |
| AnyTLS | - | Universal TLS protocol |

### Core Features
- **Auto TLS** - Automatic SSL certificate application and renewal (Let's Encrypt / Buypass)
- **User Management** - Add, remove, view user configurations
- **Subscription Generation** - Support for Universal, Clash Meta, sing-box formats
- **Camouflage Site** - One-click Nginx camouflage website deployment

### Advanced Features
- **Traffic Routing** - WARP, IPv6, Socks5, DNS routing for streaming unlock
- **CDN Nodes** - Custom CDN node addresses
- **Chain Proxy** - Multi-level proxy chain configuration
- **Domain Blacklist** - Block access to specified domains
- **BT Management** - Enable/disable P2P downloads

### System Features
- **Bilingual UI** - Switch between Chinese/English anytime
- **Auto Update** - Detect and update from GitHub Releases

## Requirements

- **OS**: Debian 9+, Ubuntu 16+, CentOS 7+, Alpine 3+
- **Architecture**: amd64, arm64
- **Memory**: 512MB+
- **Requires**: root privileges

## Quick Start

### Installation

```bash
wget -P /root -N https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

### Management

After installation, run the following command to open the management menu:

```bash
pasly
```

## Language Selection

The script supports both Chinese and English with three switching methods:

### Method 1: Menu Switch (Recommended)
```bash
pasly
# Select 21.切换语言 / Switch Language
```

### Method 2: Specify at Installation
```bash
V2RAY_LANG=en bash install.sh   # English
V2RAY_LANG=zh bash install.sh   # Chinese (default)
```

### Method 3: Temporary Override
```bash
V2RAY_LANG=en pasly   # English interface
V2RAY_LANG=zh pasly   # Chinese interface
```

Language settings are saved to `/etc/Proxy-agent/lang_pref` and auto-loaded on subsequent runs.

## Directory Structure

```
/etc/Proxy-agent/
├── install.sh          # Main script
├── VERSION             # Version number
├── lang_pref           # Language setting
├── xray/               # Xray-core config and binary
│   ├── xray
│   └── conf/
├── sing-box/           # sing-box config and binary
│   ├── sing-box
│   └── conf/
├── tls/                # TLS certificates
├── subscribe/          # Subscription files
├── lib/                # Module library
└── shell/lang/         # Language files
```

## Menu Functions

```
==============================================================
1.Install/Reinstall       # One-click proxy core installation
2.Custom Installation     # Choose protocol combination freely
3.Chain Proxy Management  # Configure proxy chains
4.Hysteria2 Management    # Hysteria2 protocol management
5.REALITY Management      # Reality protocol management
6.TUIC Management         # TUIC protocol management
-------------------------Tool Management----------------------
7.User Management         # Add/remove users
8.Camouflage Site         # Deploy/change camouflage website
9.Certificate Management  # TLS certificate operations
10.CDN Node Management    # Configure CDN addresses
11.Routing Tools          # WARP/DNS/IPv6 routing
12.Add New Port           # Multi-port configuration
13.BT Download Management # P2P traffic control
15.Domain Blacklist       # Block domain access
-------------------------Version Management-------------------
16.Core Management        # Upgrade/switch core
17.Update Script          # Check and update script
18.Install BBR            # TCP optimization
-------------------------Script Management--------------------
20.Uninstall              # Complete uninstall
21.Switch Language        # Chinese/English toggle
==============================================================
```

## Documentation

- [Nginx Proxy Configuration](../nginx_proxy.md)
- [Performance Optimization](../optimize_V2Ray.md)
- [Installation Tools](../install_tools.md)

## Contributing

Issues and Pull Requests are welcome.

- **Feedback**: [GitHub Issues](https://github.com/Lynthar/Proxy-agent/issues)

## Credits

- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) - Original project
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)

## License

[AGPL-3.0](../../LICENSE)
