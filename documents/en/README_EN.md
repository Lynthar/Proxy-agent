# Proxy-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![GitHub Release](https://img.shields.io/github/v/release/Lynthar/Proxy-agent?label=Release)](https://github.com/Lynthar/Proxy-agent/releases)
[![中文](https://img.shields.io/badge/中文-README-blue)](../../README.md)

One-click installer and management menu for Xray-core / sing-box multi-protocol proxy stacks. Fork of [v2ray-agent](https://github.com/mack-a/v2ray-agent) by @mack-a.

## Quick Install

```bash
wget -P /root -N https://raw.githubusercontent.com/Lynthar/Proxy-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

> **Alpine users: run `apk add bash wget` first** (the script requires bash).

After install, launch the management menu with `pasly`.

## Supported Protocols

| Protocol | Transport | Notes |
|---|---|---|
| VLESS | TCP/Vision · WS · XHTTP · Reality | Recommended |
| VMess | WS · HTTPUpgrade | CDN-friendly |
| Trojan | TCP | HTTPS disguise |
| Hysteria2 | QUIC | High-speed UDP |
| TUIC | QUIC | Low-latency UDP |
| NaiveProxy | HTTP/2 | Anti-detection |
| AnyTLS · Shadowsocks 2022 | — | General purpose |

## Core Features

- **Dual-core** — Xray-core and sing-box, auto-detected and switchable
- **Chain proxy** — exit / relay / entry multi-hop, multi-chain split routing, Xray+sing-box hybrid outbounds
- **External nodes** — plug third-party SS / Trojan / SOCKS5 nodes into the chain as exits
- **Atomic JSON writes** + snapshot-based config backup and rollback
- **Signed self-update** — SHA256 verification of the downloaded `install.sh`, auto-restore from backup on mismatch
- **Bilingual UI** — Chinese / English, switch via menu or `V2RAY_LANG` env variable

## Requirements

- **OS**: Debian 9+, Ubuntu 16+, CentOS 7+, Alpine 3+
- **Arch**: amd64, arm64
- **Memory**: 512 MB+
- **Privilege**: root

## Language Selection

```bash
pasly                     # Menu option 21
V2RAY_LANG=en pasly       # Temporary override via env var
```

The selection is persisted to `/etc/Proxy-agent/lang_pref` and auto-loaded on subsequent runs.

## Directory Layout

```
/etc/Proxy-agent/
├── install.sh          # Main script
├── VERSION
├── lang_pref           # Language preference
├── backup/             # Versioned backups (script + config snapshots)
├── xray/               # Xray-core binary and conf/
├── sing-box/           # sing-box binary and conf/
├── tls/                # TLS certificates
├── subscribe/          # Subscription files
├── lib/                # Shared shell modules
└── shell/lang/         # Language files
```

## Menu Map

```
==============================================================
1. Install / Reinstall       Core selection + full install
2. Custom Install            Pick protocol combination
3. Chain Proxy               Entry / relay / exit / multi-chain
4. Hysteria2 Management
5. REALITY Management
6. TUIC Management
7. User Management           Add / remove / view / subscribe
8. Camouflage Site           Nginx decoy deployment
9. Certificate Management    Let's Encrypt / Buypass
10. CDN Nodes
11. Routing Tools            WARP / IPv6 / SOCKS5 / DNS
12. Add Port
13. BT Management
15. Domain Blacklist
16. Core Management          Upgrade / switch
17. Update Script            Checked against SHA256, auto-rollback on failure
18. BBR
20. Uninstall
21. Switch Language
==============================================================
```

## Documentation

- [User Guide](../user-guide.md)
- [Developer Guide](../developer-guide.md)
- [Nginx Proxy](../nginx_proxy.md)
- [SELinux Notes](../selinux.md)

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/Lynthar/Proxy-agent).

## Credits

- [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent) — original project
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)

## License

[AGPL-3.0](../../LICENSE)
