# xms-singbox - 脚本下载安装文档

## 📥 一键下载安装命令

### 1. cm.sh (Mihomo 综合部署)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/cm.sh)
```
**模式**: 1-临时隧道, 2-固定token隧道, 3-卸载服务, 4-清理残留, 0-退出

### 2. cs.sh (Sing-box 综合部署)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/cs.sh)
```
**模式**: 1-临时隧道, 2-固定token隧道, 3-卸载服务, 4-清理残留, 0-退出

### 3. cx.sh (Xray 综合部署)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/cx.sh)
```
**模式**: 1-临时隧道, 2-固定token隧道, 3-卸载服务, 4-清理残留, 0-退出

### 4. smx.sh (统一代理节点部署脚本)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/smx.sh)
```
**功能**: 自选内核(1=Xray 2=sing-box 3=mihomo), 自选协议, 5种模式(临时/固定隧道/网页授权/卸载/清缓存)

### 5. suoha.sh (原始基础脚本)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/suoha.sh)
```
**说明**: 已被xms.sh等新脚本继承了系统适配能力,支持Debian/Ubuntu/CentOS/Fedora/Alpine

## 🚀 快速使用

### 推荐方案
```bash
# 使用 smx.sh (综合管理器，功能最全)
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/smx.sh)

# 或使用单核脚本
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/cs.sh)  # sing-box
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/cm.sh)  # mihomo
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/cx.sh)  # xray
```

### 系统适配
这些脚本已适配以下系统:
- Debian/Ubuntu/CentOS/Fedora/Alpine
- 包管理器自动适配: apt/yum/apk

## 📋 使用说明

### 安装任意脚本
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/laowtun/cta/main/脚本文件名.sh)
```

### 常用操作
- **临时隧道**: 域名随重启变化，无需绑定
- **固定token隧道**: 输入域名后重启不变
- **卸载服务**: 卸载代理相关配置
- **清理残留**: 清理无用的配置文件和缓存

## 📬 联系方式
- GitHub: https://github.com/laowtun/cta
- 问题反馈: GitHub Issues

---
*这些脚本由 laowtun 独立开发和维护*