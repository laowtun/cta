#!/bin/bash
# cx_clean.sh - Xray Focused Deployment Script (Clean Version)
# 仅包含命令用法，避免Cloudflare/内核相关文字
#
# 用法: bash cx.sh [模式]
#
# 可用模式:
# 1 临时隧道
# 2 固定token隧道
# 3 卸载服务
# 4 清理残留
# 0 退出
#
# 核心功能: VLESS/VMess/Trojan/SS 等协议
# 传输支持: ws/grpc/mixed/QUIC
#
# 使用示例:
# bash cx.sh 1      # 临时隧道模式
# bash cx.sh 2      # 固定token模式
# bash cx.sh 4      # 清理残留
#
set -e
echo "cx_clean.sh - Command usage only version"