# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![中文版](https://img.shields.io/badge/中文-版本-blue)](../../README.md)

Xray-core/sing-box One-click Quick Install Script

A fork of v2ray-agent by mack-a with additional features and improvements.

## Features

*   **Multi-core Support:** Supports Xray-core and sing-box.
*   **Multi-protocol Support:** Supports various protocols like VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy.
*   **Automatic TLS:** Automatically applies for and renews SSL certificates.
*   **Easy Management:** Provides a simple menu to manage users, ports, and configurations.
*   **Subscription Support:** Generates and manages subscription links.
*   **Traffic Splitting Management:** Provides wireguard, IPv6, Socks5, DNS, VMess(ws), SNI reverse proxy for streaming unlock, IP verification bypass, etc.
*   **Target Domain Management:** Domain name blacklist management to prohibit access to specified websites.
*   **BT Download Management:** Can be used to prohibit P2P-related content download.
*   **Bilingual Support:** Available in both Chinese and English.

## Quick Start

### Installation (English Version)

```bash
wget -P /root -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/shell/install_en.sh" && chmod 700 /root/install_en.sh && /root/install_en.sh
```

### Installation (Chinese Version)

```bash
wget -P /root -N "https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

### Usage

After installation, run the following command to open the management menu again:

```bash
pasly
```

## Language Selection

This script supports two languages:

| Language | Installation Command |
|----------|---------------------|
| English  | Use `install_en.sh` |
| 中文     | Use `install.sh`    |

Both versions have identical functionality, only the interface language differs.

## Documentation and Guides

*   Please refer to the `documents` directory for usage notes, risk reminders, and examples.

## Support

*   **Feedback:** [Submit an issue](https://github.com/Lynthar/Proxy-agent/issues)

## License

This project is licensed under the [AGPL-3.0 License](../../LICENSE).
