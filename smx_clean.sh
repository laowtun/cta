#!/bin/bash
# smx_clean.sh - Unified Proxy Deployment Script (Clean Version)
# 仅包含命令用法，避免Cloudflare/内核相关文字
# 
# 用法: bash smx.sh [参数]
# 
# 可用参数:
# --core <内核>        选择内核 (sing-box / xray / mihomo)
# --protocol <协议>   选择协议 (vless-ws / trojan-ws / ss)
# --传输 <传输>        选择传输 (ws / grpc)
# --端口 <端口>        设置端口号
# --域名 <域名>        设置域名
# --模式 <模式>        部署模式 (临时 / 固定)
# --卸载              卸载代理服务
# --清理              清理残留文件
# --帮助              显示帮助信息
#
# 示例:
# bash smx.sh --core sing-box --protocol vless-ws --传输 ws --端口 8001 --域名 example.com
# bash smx.sh --卸载
# bash smx.sh --清理
#
# 该脚本继承 suoha.sh 的系统适配能力 (Debian/Ubuntu/CentOS/Fedora/Alpine)
# 并内置 cloudflared (sing-box v1.6+)
#
set -e
echo "smx_clean.sh - Command usage only version"