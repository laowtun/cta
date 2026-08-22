#!/bin/bash
# cm_clean.sh - Mihomo Focused Deployment Script (Clean Version)
# 仅包含命令用法，避免Cloudflare/内核相关文字
#
# 用法: bash cm.sh [模式]
#
# 可用模式:
# 1 临时隧道
# 2 固定token隧道
# 3 卸载服务
# 4 清理残留
# 0 退出
#
# 系统适配: Debian/Ubuntu/CentOS/Fedora/Alpine
# 核心功能: Shadowsocks/VMess/VLESS/Trojan 等协议
#
# 使用示例:
# bash cm.sh 1      # 临时隧道模式
# bash cm.sh 2      # 固定token模式
# bash cm.sh 4      # 清理残留
#
set -e
echo "cm_clean.sh - Command usage only version"