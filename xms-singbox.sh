#!/bin/bash
# xms-singbox.sh - Sing-box VLESS+Cloudflare Tunnel (互动版)
# 功能：支持零食隧道 和 固定token隧道
# 不再写死域名，由用户在运行时决定

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==================== 1. 系统检测 ====================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s | tr '[:upper:' '[:lower:])'
    fi
    case $OS in
        debian|ubuntu) PKG_MGR="apt" ;;
        centos|fedora) PKG_MGR="yum" ;;
        alpine) PKG_MGR="apk" ;;
        *) PKG_MGR="unknown" ;;
    esac
}

# ==================== 2. 选择部署模式 ====================
select_mode() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  xms-singbox.sh - Sing-box Deployment${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Please select deployment mode:${NC}"
    echo "  1) Temporary Tunnel (trycloudflare) "
    echo "       → Domain auto-generates each run"
    echo "       → No domain setup needed"
    echo ""
    echo "  2) Fixed Token Tunnel "
    echo "       → Domain stays fixed (binds to your domain)"
    echo "       → You input your domain or subdomain"
    echo "       → Uses token authentication"
    echo ""
    echo "  3) Exit"
    echo ""
    read -r -p "Enter choice [1-3]: " mode_choice
    
    case $mode_choice in
        1) DEPLOY_MODE="temp" ;;
        2) DEPLOY_MODE="fixed" ;;
        3) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice!${NC}"; select_mode ;;
    esac
}

# ==================== 3. 域名/模式处理 ====================
handle_domain() {
    if [ "$DEPLOY_MODE" = "temp" ]; then
        CF_DOMAIN="auto-generated-by-trycloudflare"
        echo -e "${GREEN}Mode: Temporary Tunnel${NC}"
        echo -e "${GREEN}→ Domain will be auto-generated${NC}"
        echo -e "${YELLOW}⚠️  Each run may give you a new domain${NC}"
    else
        echo -e "${GREEN}Mode: Fixed Token Tunnel${NC}"
        read -r -p "Enter your domain (or subdomain, e.g. node.bbk.qzz.io): " CF_DOMAIN
        CF_DOMAIN=${CF_DOMAIN:-bbk.qzz.io}
        echo -e "${YELLOW}→ Using domain: $CF_DOMAIN${NC}"
    fi
}

# ==================== 4. VLESS+WS 配置 ====================
config_vless_ws() {
    echo -e "${GREEN}Configuring VLESS+WebSocket...${NC}"
    
    UUID=$(cat /proc/sys/kernel/random/uuid | head -c 32)
    
    cat > /etc/sing-box/config.json << EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen": ":8080",
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vless",
        "host": "$CF_DOMAIN"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
    
    echo -e "${GREEN}✓ Configuration generated${NC}"
}

# ==================== 5. 内置 cloudflared ====================
enable_cloudflared_internal() {
    echo -e "${GREEN}Enabling built-in cloudflared...${NC}"
    
    if [ "$DEPLOY_MODE" = "temp" ]; then
        CLOUDFLARED_MODE="auto"
        echo -e "${GREEN}→ Internal cloudflared: auto mode (temporary)${NC}"
    else
        CLOUDFLARED_MODE="explicit"
        echo -e "${GREEN}→ Internal cloudflared: explicit mode (fixed domain)${NC}"
    fi
}

# ==================== 6. 生成节点链接 ====================
generate_link() {
    UUID=$(cat /etc/sing-box/config.json | python3 -c "import sys,json; print(json.load(sys.stdin)['inbounds'][0]['users'][0]['uuid'])")
    
    echo -e "${GREEN}VLESS Node Link:${NC}"
    if [ "$DEPLOY_MODE" = "temp" ]; then
        echo -e "vless://$UUID@$CF_DOMAIN:8080?encryption=none&security=tls&type=ws&host=$CF_DOMAIN&path=/vless#Sing-box-Temp-Tunnel"
        echo -e "${YELLOW}⚠️  Note: Domain may change on next run${NC}"
    else
        echo -e "vless://$UUID@$CF_DOMAIN:8080?encryption=none&security=tls&type=ws&host=$CF_DOMAIN&path=/vless#Sing-box-Fixed-Tunnel"
    fi
}

# ==================== 主流程 ====================
main() {
    detect_os
    select_mode
    handle_domain
    config_vless_ws
    enable_cloudflared_internal
    generate_link
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}Mode: $DEPLOY_MODE${NC}"
    echo -e "${GREEN}Domain: $CF_DOMAIN${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

main "$@"