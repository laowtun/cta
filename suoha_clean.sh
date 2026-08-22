#!/bin/bash
# suoha_clean.sh - Base System Adaptation (Clean Version)
# 仅包含命令用法，避免不相关文字
#
# 支持的系统: Debian/Ubuntu/CentOS/Fedora/Alpine
# 包管理器: apt/yum/apk
#
# 用法: bash suoha.sh [选项]
#
# 选项:
# --检测          检测系统并显示信息
# --更新          更新系统包
# --安装          安装必需的包
# --协议          显示支持的协议列表
# --卸载          卸载 suoha 相关组件
# --帮助          显示帮助信息
#
# 使用示例:
# bash suoha.sh --检测
# bash suoha.sh --更新
# bash suoha.sh --安装
#
# 该脚本提供跨发行版的系统适配能力
#
set -e
echo "suoha_clean.sh - Command usage only version"