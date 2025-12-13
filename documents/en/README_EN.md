# v2ray-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![English Version](https://img.shields.io/badge/English-Version-blue)](documents/en/README_EN.md)

Xray-core/sing-box One-click Quick Install Script

## Features

*   **Multi-core Support:** Supports Xray-core and sing-box.
*   **Multi-protocol Support:** Supports various protocols like VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy.
*   **Automatic TLS:** Automatically applies for and renews SSL certificates.
*   **Easy Management:** Provides a simple menu to manage users, ports, and configurations.
*   **Subscription Support:** Generates and manages subscription links.
*   **Traffic Splitting Management:** Provides wireguard, IPv6, Socks5, DNS, VMess(ws), SNI reverse proxy, which can be used to unlock streaming media, evade IP verification, etc.
*   **Target Domain Management:** Provides domain name blacklist management, which can be used to prohibit access to specified websites.
*   **BT Download Management:** Can be used to prohibit the download of P2P-related content.
*   **You can find usage notes in the documents directory of this repository.**

## Quick Start

### Installation

```
bash wget -P /root -N "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

### Usage

After installation, run the following command to open the management menu again:

```
vasma
```

## Documentation and Guides

*   Please refer to the documents directory for usage notes, risk reminders, and examples.

## Support

*   **Feedback:** [Submit an issue](https://github.com/mack-a/v2ray-agent/issues)

## License

This project is licensed under the [AGPL-3.0 License](LICENSE).
