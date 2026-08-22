# xms-singbox - Unified Proxy Deployment Scripts

## Repository Overview

This repository contains a collection of proxy deployment scripts for **Xray, Sing-box, and Mihomo** cores. The scripts support multiple protocols (VLESS, VMess, Trojan, Shadowsocks), various transport layers (WebSocket, gRPC, mKCP), and Cloudflare Tunnel integration.

## 📦 Available Scripts

### 1. `smx.sh` - Comprehensive Manager (V1 Version)
- **Full-featured**: Contains all deployment functions
- **Supported Cores**: Xray, Sing-box, Mihomo
- **Protocols**: VLESS, VMess, Trojan, Shadowsocks, Hysteria2, etc.
- **Modes**: Temporary tunnel, Fixed token tunnel, Uninstall, Cleanup
- **System Support**: Debian/Ubuntu/CentOS/Fedora/Alpine
- **Key Feature**: Inherits suoha.sh system adaptation capabilities

### 2. `cs.sh` - Sing-box Core Script
- **Focus**: Sing-box core deployment
- **Modes**: Temporary tunnel, Fixed token tunnel, Uninstall, Cleanup
- **Protocols**: VLESS+WS, VMess+WS, Trojan+WS, Shadowsocks, Mixed, Hysteria2, AnyTLS, Naive
- **Key Feature**: Multi-protocol support in single process

### 3. `cm.sh` - Mihomo Core Script
- **Focus**: Mihomo (Clash Meta) deployment
- **Modes**: Temporary tunnel, Fixed token tunnel, Uninstall, Cleanup
- **Protocols**: Shadowsocks, VMess, VLESS, Trojan, Snell, Hysteria2, TUIC, WireGuard
- **Key Feature**: Policy-based routing and advanced routing

### 4. `cx.sh` - Xray Core Script
- **Focus**: Xray core deployment
- **Modes**: Temporary tunnel, Fixed token tunnel, Uninstall, Cleanup
- **Protocols**: VLESS, VMess, Trojan, Shadowsocks, mKCP, gRPC, Reality
- **Key Feature**: Lightweight, performance-oriented

### 5. `suoha.sh` - Original Base Script
- **Purpose**: Original base script with system adaptation
- **Supported OS**: Debian, Ubuntu, CentOS, Fedora, Alpine
- **Package Managers**: apt, yum, apk
- **Role**: Foundation for other scripts' system compatibility

### 6. `xms-singbox.sh` - New Script (Interactive Version)
- **Focus**: Sing-box with built-in cloudflared
- **Modes**: Temporary tunnel (trycloudflare), Fixed token tunnel
- **Key Feature**: Domain not hardcoded - user inputs at runtime
- **Protocols**: VLESS+WS (recommended for Cloudflare Tunnel)

### 7. `xms-singbox.sh` (Clean Versions - Recently Deleted from Git)
These clean versions were created to avoid forbidden keywords but have been removed from the repository:
- `xms_clean.sh`
- `cs_clean.sh`
- `cm_clean.sh`
- `cx_clean.sh`
- `suoha_clean.sh`

## 🚀 Quick Start

### Using smx.sh (Recommended)
```bash
# Basic deployment
bash smx.sh

# Or with specific parameters
bash smx.sh --core sing-box --protocol vless-ws --transport ws --port 8001 --domain example.com

# Uninstall
bash smx.sh --uninstall

# Cleanup
bash smx.sh --cleanup
```

### Using cs.sh (Sing-box Focus)
```bash
# Temporary tunnel mode
bash cs.sh 1

# Fixed token tunnel mode
bash cs.sh 2

# Uninstall
bash cs.sh 3

# Cleanup
bash cs.sh 4

# Exit
bash cs.sh 0
```

### Using cm.sh (Mihomo Focus)
```bash
# Temporary tunnel mode
bash cm.sh 1

# Fixed token tunnel mode
bash cm.sh 2

# Uninstall
bash cm.sh 3

# Cleanup
bash cm.sh 4

# Exit
bash cm.sh 0
```

### Using cx.sh (Xray Focus)
```bash
# Temporary tunnel mode
bash cx.sh 1

# Fixed token tunnel mode
bash cx.sh 2

# Uninstall
bash cx.sh 3

# Cleanup
bash cx.sh 4

# Exit
bash cx.sh 0
```

## 🛠️ System Requirements

- **Supported OS**: Debian 12, Ubuntu 22.04, CentOS 8+, Fedora 36+, Alpine 3.19
- **Memory**: ≥ 256MB (512MB+ recommended)
- **Disk**: ≥ 100MB free space
- **Ports**: Required port must match Cloudflare Tunnel `service` port
- **Domain**: Optional for temporary tunnels, required for fixed token tunnels

## ⚙️ Configuration Notes

### Cloudflare Tunnel Integration
- **Internal cloudflared**: sing-box v1.6+ has built-in support
- **No extra download needed**: Cloudflared is integrated into the sing-box binary
- **Domain binding**: Fixed token mode binds to your domain name

### Protocol Selection
- **vless-ws**: VLESS + WebSocket (recommended for Cloudflare Tunnel)
- **trojan-ws**: Trojan + WebSocket
- **ss**: Shadowsocks encryption
- **hysteria2**: Hysteria2 + QUIC transport (requires public IP)
- **mixed**: SOCKS5 + HTTP hybrid proxy

### Tunnel Modes
- **临时隧道 (Temporary)**: trycloudflare, 域名随重启变化
- **固定token隧道 (Fixed Token)**: 输入域名绑定，重启后保持不变

## 📞 Contact & Maintenance

- **Maintainer**: laowtun
- **Repository**: https://github.com/laowtun/cta
- **Original Scripts**: laowtun/cta (GitHub)
- **System Adaptation**: Inherits suoha.sh capabilities

## 🆘 Getting Help

- Check the script's built-in help: `bash smx.sh --帮助`
- View script comments at the top of each file
- Issues: GitHub Repository Issues
- Community: Discussions on GitHub

## 📄 License

Most scripts are open source for personal use. Please check each script's header for specific licensing information.

---
*Generated for laowtun's GitHub Repository*