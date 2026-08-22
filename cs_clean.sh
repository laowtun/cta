#!/bin/bash
# cs_clean.sh - Sing-box Focused Deployment Script (Clean Version)
# 仅包含命令用法，避免Cloudflare/内核相关文字
#
# 用法: bash cs.sh [模式]
#
# 可用模式:
# 1 临时隧道    - trycloudflare, 重启失效
# 2 固定token隧道 - 输入域名，固定不变
# 3 卸载服务      - 卸载代理
# 4 清理残留    - 清理残留文件
# 0 退出
#
# 系统适配: Debian/Ubuntu/CentOS/Fedora/Alpine
# 核心功能: VLESS/VMess/Trojan/SS 等协议
# 传输支持: ws/grpc/mixed/QUIC
#
# 使用示例:
# bash cs.sh 1      # 临时隧道模式
# bash cs.sh 2      # 固定token模式
# bash cs.sh 4      # 清理残留
#
# 该脚本继承 suoha.sh 的系统适配能力
#
set -e
echo "cs_clean.sh - Command usage only version"