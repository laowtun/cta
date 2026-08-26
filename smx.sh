#!/bin/bash
# =============================================================================
# smx.sh - 统一代理节点部署脚本
# 自选内核: 1=Xray 2=sing-box 3=mihomo
# 自选协议: VLESS / VMess (WebSocket)
# 部署模式: 临时隧道 / Token固定隧道 / 网页授权
# 由 laowtun 独立开发
# =============================================================================

# ---------- 全局变量 ----------
DIR="/opt/smx"
CMD="/usr/bin/smx"
CORE=""
CORE_BIN=""
CORE_NAME=""
CORE_UNIT=""
RADAR_JSON=""

IPv4_API="https://ipv4-check-perf.radar.cloudflare.com/"
IPv6_API="https://ipv6-check-perf.radar.cloudflare.com/"

# ---------- 颜色/输出 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
if [ ! -t 1 ] || [ "$(tput colors 2>/dev/null)" -lt 8 ]; then RED=''; GREEN=''; YELLOW=''; NC=''; fi
info()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------- 系统检测 ----------
is_alpine() { [ "$(grep -iE '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')" = "alpine" ]; }

install_deps() {
    if is_alpine; then
        [ -z "$(command -v curl)" ] && apk add -f curl >/dev/null 2>&1
        [ -z "$(command -v gzip)" ] && apk add -f gzip >/dev/null 2>&1
        [ -z "$(command -v unzip)" ] && apk add -f unzip >/dev/null 2>&1
    elif command -v apt-get >/dev/null 2>&1; then
        [ -z "$(command -v curl)" ] && { apt-get update >/dev/null 2>&1; apt-get -y install curl >/dev/null 2>&1; }
        [ -z "$(command -v gzip)" ] && { apt-get update >/dev/null 2>&1; apt-get -y install gzip >/dev/null 2>&1; }
        [ -z "$(command -v unzip)" ] && { apt-get update >/dev/null 2>&1; apt-get -y install unzip >/dev/null 2>&1; }
    elif command -v yum >/dev/null 2>&1; then
        [ -z "$(command -v curl)" ] && yum -y install curl >/dev/null 2>&1
        [ -z "$(command -v gzip)" ] && yum -y install gzip >/dev/null 2>&1
        [ -z "$(command -v unzip)" ] && yum -y install unzip >/dev/null 2>&1
    fi
}

# ---------- 安全输入（支持重试） ----------
ask_input() {
    local prompt="$1" default="${2:-}" allow_empty="${3:-}" val=""
    while true; do
        read -r -p "$prompt" val
        [ -z "$val" ] && [ -n "$default" ] && val="$default"
        if [ -n "$val" ] || [ "$allow_empty" = "1" ]; then
            echo "$val"
            return 0
        fi
        warn "输入不能为空，请重新输入 (Ctrl+C 退出)"
    done
}

ask_confirm() {
    local prompt="$1" val="$2"
    echo -e "  ${GREEN}你输入的是:${NC} $val"
    read -r -p "  确认正确？(Y/n, 默认Y): " yn
    [ "$yn" = "n" ] || [ "$yn" = "N" ] && return 1
    return 0
}

# ---------- Radar 节点名 ----------
get_radar_info() {
    local ipv="${1:-4}" api
    [ "$ipv" = "6" ] && api="$IPv6_API" || api="$IPv4_API"
    RADAR_JSON=$(curl --max-time 8 -sS "$api" 2>/dev/null)
    echo "$RADAR_JSON" > "$DIR/radar.json" 2>/dev/null
}
radar_field() {
    local key="$1"
    echo "$RADAR_JSON" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -1
}
gen_node_name() {
    local c=$(radar_field country) a=$(radar_field asn) ci=$(radar_field city)
    [ -z "$c" ] && c=XX; [ -z "$a" ] && a=XX; [ -z "$ci" ] && ci=XX
    echo "${c}-asn${a}-${ci}"
}

# ---------- 链接生成 (对齐 suoha 格式) ----------
gen_links() {
    local protocol="$1" uuid="$2" host="$3" path="$4" isp="$5" add="${6:-speed.cloudflare.com}" out="$7"
    if [ "$protocol" = "1" ]; then
        echo -e "vmess链接已经生成, $add 可替换为CF优选IP\n" > "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"/$path\",\"port\":\"443\",\"ps\":\"$(echo "$isp" | sed 's/_/ /g')_tls\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\n端口 443 可改为 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"/$path\",\"port\":\"80\",\"ps\":\"$(echo "$isp" | sed 's/_/ /g')\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\n端口 80 可改为 8080 8880 2052 2082 2086 2095\n" >> "$out"
    else
        local ps_url="$(echo "$isp" | sed -e 's/_/%20/g' -e 's/,/%2C/g')"
        echo -e "vless链接已经生成, $add 可替换为CF优选IP\n" > "$out"
        echo "vless://$uuid@$add:443?encryption=none&security=tls&type=ws&host=$host&path=/$path#${ps_url}_tls" >> "$out"
        echo -e "\n端口 443 可改为 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vless://$uuid@$add:80?encryption=none&security=none&type=ws&host=$host&path=/$path#$ps_url" >> "$out"
        echo -e "\n端口 80 可改为 8080 8880 2052 2082 2086 2095\n" >> "$out"
    fi
    if [ "$add" != "speed.cloudflare.com" ] && echo "$add" | grep -q '\.'; then
        echo "注意:如果 80 8080 8880 2052 2082 2086 2095 端口无法正常使用" >> "$out"
        echo "请前往 https://dash.cloudflare.com/" >> "$out"
        echo "检查管理面板 SSL/TLS - 边缘证书 - 始终使用HTTPS 是否处于关闭状态" >> "$out"
    fi
}

show_links() {
    local file="$1"
    cat "$file"
    cp -f "$file" "$DIR/v2ray.txt" 2>/dev/null
    cp -f "$file" /root/v2ray.txt 2>/dev/null
    cp -f "$file" ./v2ray.txt 2>/dev/null
    echo -e "\n信息已经保存在 $file"
    echo -e "也可以运行: cat v2ray.txt 查看"
}

# ---------- 交互: 选择内核 ----------
choose_core() {
    clear
    echo "===================================="
    echo "  统一代理节点部署脚本"
    echo "===================================="
    echo "选择内核:"
    echo "  1. Xray"
    echo "  2. sing-box"
    echo "  3. mihomo (Clash Meta)"
    echo "  0. 退出"
    read -p "请输入选择(默认1): " core
    [ -z "$core" ] && core=1
    case "$core" in
        1) CORE=xray;     CORE_NAME="Xray";     CORE_UNIT="smx-xray" ;;
        2) CORE=singbox;  CORE_NAME="sing-box"; CORE_UNIT="smx-singbox" ;;
        3) CORE=mihomo;   CORE_NAME="mihomo";   CORE_UNIT="smx-mihomo" ;;
        *) echo "退出"; exit 0 ;;
    esac
    DIR="/opt/${CORE}"
    echo "  已选择内核: $CORE_NAME (安装目录: $DIR)"
    sleep 1
}
# ---------- 下载函数 (按架构) ----------
get_arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo amd64 ;;
        armv8|arm64|aarch64) echo arm64 ;;
        armv7l|armv71) echo armv7 ;;
        arm|armv6l) echo arm6 ;;
        *) echo unsupported ;;
    esac
}
is_bad_arch() { [ "$(get_arch)" = "unsupported" ]; }

download_xray() {
    local dst="$DIR" arch=$(get_arch) url
    mkdir -p "$dst"
    case "$arch" in
        amd64) url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" ;;
        arm64) url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip" ;;
        armv7) url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip" ;;
        *) warn "Xray 不支持架构 $arch"; return 1 ;;
    esac
    echo "  下载 Xray ($arch)..."
    cd "$dst" && rm -rf xray xray.zip
    if ! curl -fsSL --retry 2 -o xray.zip "$url"; then err "Xray 下载失败"; return 1; fi
    if ! unzip -o xray.zip -d xray >/dev/null 2>&1; then err "Xray 解压失败"; return 1; fi
    chmod +x "$dst/xray/xray"
    CORE_BIN="$dst/xray/xray"
    rm -rf "$dst/xray.zip"
    echo "  Xray 就绪: $CORE_BIN"
}

download_singbox() {
    local dst="$DIR" arch=$(get_arch) ver url
    mkdir -p "$dst"
    echo "  获取 sing-box 版本..."
    ver=$(curl -fsSL --max-time 10 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')
    [ -z "$ver" ] && ver="1.13.19"
    case "$arch" in
        amd64) url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-amd64.tar.gz" ;;
        arm64) url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-arm64.tar.gz" ;;
        armv7) url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-armv7.tar.gz" ;;
        *) warn "sing-box 不支持架构 $arch"; return 1 ;;
    esac
    echo "  下载 sing-box $ver ($arch)..."
    cd "$dst" && rm -rf singbox.tar.gz singbox
    if ! curl -fsSL --retry 2 -o singbox.tar.gz "$url"; then err "sing-box 下载失败"; return 1; fi
    if ! tar xzf singbox.tar.gz -C "$dst" 2>/tmp/sb_err; then err "sing-box 解压失败: $(cat /tmp/sb_err)"; return 1; fi
    mv "$dst"/sing-box-*/* "$dst"/ 2>/dev/null
    rm -rf "$dst"/sing-box-*/
    chmod +x "$dst/sing-box" 2>/dev/null
    CORE_BIN="$dst/sing-box"
    rm -rf "$dst/singbox.tar.gz"
    echo "  sing-box 就绪: $CORE_BIN"
}

download_mihomo() {
    local dst="$DIR" arch=$(get_arch) ver url
    mkdir -p "$dst"
    echo "  获取 mihomo 版本..."
    ver=$(curl -fsSL --max-time 10 "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')
    [ -z "$ver" ] && ver="1.19.30"
    case "$arch" in
        amd64) url="https://github.com/MetaCubeX/mihomo/releases/download/v${ver}/mihomo-linux-amd64-v1-v${ver}.gz" ;;
        arm64) url="https://github.com/MetaCubeX/mihomo/releases/download/v${ver}/mihomo-linux-arm64-v1-v${ver}.gz" ;;
        armv7) url="https://github.com/MetaCubeX/mihomo/releases/download/v${ver}/mihomo-linux-armv7-v1-v${ver}.gz" ;;
        *) warn "mihomo 不支持架构 $arch"; return 1 ;;
    esac
    echo "  下载 mihomo $ver ($arch)..."
    cd "$dst" && rm -rf mihomo.gz mihomo
    if ! curl -fsSL --retry 2 -o mihomo.gz "$url"; then err "mihomo 下载失败"; return 1; fi
    if ! gzip -d mihomo.gz 2>/dev/null; then
        [ -f mihomo.gz ] && mv mihomo.gz mihomo 2>/dev/null
    fi
    [ ! -f "$dst/mihomo" ] && { err "mihomo 解压失败"; return 1; }
    chmod +x "$dst/mihomo"
    CORE_BIN="$dst/mihomo"
    echo "  mihomo 就绪: $CORE_BIN"
}

download_cloudflared() {
    local dst="$DIR" arch=$(get_arch) url
    case "$arch" in
        amd64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
        arm64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
        armv7) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
        arm6)  url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
        *) warn "cloudflared 不支持架构 $arch"; return 1 ;;
    esac
    echo "  下载 cloudflared ($arch)..."
    cd "$dst" && rm -rf cloudflared
    if ! curl -fsSL --retry 2 -o cloudflared "$url"; then err "cloudflared 下载失败"; return 1; fi
    chmod +x "$dst/cloudflared"
    echo "  cloudflared 就绪"
}

download_all() {
    download_cloudflared || return 1
    case "$CORE" in
        xray)    download_xray || return 1 ;;
        singbox) download_singbox || return 1 ;;
        mihomo)  download_mihomo || return 1 ;;
    esac
}

# ---------- 各内核配置生成 ----------
# $1=protocol  $2=port  $3=uuid  $4=path  $5=配置文件路径
gen_config_xray() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" = "2" ]; then
        cat > "$conf" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid", "flow": ""}], "decryption": "none"},
    "streamSettings": {"network": "ws", "wsSettings": {"path": "/$path"}}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
    else
        cat > "$conf" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "127.0.0.1",
    "port": $port,
    "protocol": "vmess",
    "settings": {"clients": [{"id": "$uuid", "alterId": 0}]},
    "streamSettings": {"network": "ws", "wsSettings": {"path": "/$path"}}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
    fi
}

gen_config_singbox() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" = "2" ]; then
        cat > "$conf" <<EOF
{
  "log": {"level": "warning", "timestamp": true},
  "inbounds": [{
    "type": "vless",
    "listen": "127.0.0.1",
    "listen_port": $port,
    "users": [{"uuid": "$uuid", "flow": ""}],
    "transport": {"type": "ws", "path": "/$path"}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
    else
        cat > "$conf" <<EOF
{
  "log": {"level": "warning", "timestamp": true},
  "inbounds": [{
    "type": "vmess",
    "listen": "127.0.0.1",
    "listen_port": $port,
    "users": [{"uuid": "$uuid", "alterId": 0}],
    "transport": {"type": "ws", "path": "/$path"}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
    fi
}

gen_config_mihomo() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" = "2" ]; then
        cat > "$conf" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: true

listeners:
  - name: vless-in
    type: vless
    port: $port
    address: "127.0.0.1"
    users:
      - uuid: $uuid
    allow-insecure: true
    network: ws
    ws-path: /$path

proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
    else
        cat > "$conf" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: true

listeners:
  - name: vmess-in
    type: vmess
    port: $port
    address: "127.0.0.1"
    users:
      - uuid: $uuid
    allow-insecure: true
    network: ws
    ws-path: /$path

proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
    fi
}

# 统一配置生成入口
gen_config() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    case "$CORE" in
        xray)    gen_config_xray "$protocol" "$port" "$uuid" "$path" "$conf" ;;
        singbox) gen_config_singbox "$protocol" "$port" "$uuid" "$path" "$conf" ;;
        mihomo)  gen_config_mihomo "$protocol" "$port" "$uuid" "$path" "$conf" ;;
    esac
}

# ---------- systemd 服务管理 ----------
# 统一启动命令 (按内核)
get_run_cmd() {
    case "$CORE" in
        xray)    echo "$CORE_BIN run -c $DIR/config.json" ;;
        singbox) echo "$CORE_BIN run -c $DIR/config.json" ;;
        mihomo)  echo "$CORE_BIN -d $DIR -f $DIR/config.yaml" ;;
    esac
}
config_file() {
    case "$CORE" in
        mihomo) echo "$DIR/config.yaml" ;;
        *)      echo "$DIR/config.json" ;;
    esac
}

install_systemd() {
    local unit="$1" exec="$2" desc="$3"
    if is_alpine; then
        cat > /etc/local.d/${unit}.start <<EOF
$exec &
EOF
        chmod +x /etc/local.d/${unit}.start
        rc-update add local >/dev/null 2>&1
    else
        cat > /lib/systemd/system/${unit}.service <<EOF
[Unit]
Description=$desc
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=$exec
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl stop ${unit}.service >/dev/null 2>&1
        systemctl enable ${unit}.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start ${unit}.service
    fi
}

stop_services() {
    # 停掉所有历史服务 (三内核 + cloudflared)
    for u in smx-xray smx-singbox smx-mihomo smx-cf; do
        systemctl stop ${u}.service >/dev/null 2>&1
        systemctl disable ${u}.service >/dev/null 2>&1
    done
    if is_alpine; then
        for u in smx-xray smx-singbox smx-mihomo smx-cf; do rm -f /etc/local.d/${u}.start; done
    else
        for u in smx-xray smx-singbox smx-mihomo smx-cf; do rm -f /lib/systemd/system/${u}.service; done
    fi
    kill -9 $(ps -ef | grep -E "xray run|sing-box run|mihomo -d|cloudflared.*tunnel" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    systemctl --system daemon-reload 2>/dev/null
}

# ---------- 部署模式 ----------
# 模式1: 临时隧道
quicktunnel() {
    mkdir -p "$DIR"
    read -p "请选择协议(1.vmess,2.vless,默认1): " protocol
    [ -z "$protocol" ] && protocol=1
    read -p "请选择argo连接IPV4或IPV6(输入4或6,默认4): " ips
    [ -z "$ips" ] && ips=4

    stop_services >/dev/null 2>&1

    echo "[INFO] 获取节点信息..."
    get_radar_info "$ips"
    isp=$(gen_node_name)
    echo "[OK] 节点名称: $isp"

    if ! download_all; then err "下载失败"; exit 1; fi

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo "$uuid" | cut -d- -f1)
    port=$((RANDOM % 40000 + 10000))

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"

    # 启动内核
    case "$CORE" in
        mihomo) "$CORE_BIN" -d "$DIR" -f "$DIR/config.yaml" >/dev/null 2>&1 & ;;
        *)      "$CORE_BIN" run -c "$DIR/config.json" >/dev/null 2>&1 & ;;
    esac
    sleep 1
    "$DIR/cloudflared" tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >"$DIR/argo.log" 2>&1 &

    echo "等待 cloudflare argo 生成地址..."
    sleep 4
    n=0
    while true; do
        n=$((n+1))
        argo=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/argo.log" | head -1 | sed 's#https://##')
        if [ $n -gt 30 ]; then
            echo "获取地址超时, 检查日志"; cat "$DIR/argo.log"; break
        elif [ -z "$argo" ]; then
            sleep 1
        else
            break
        fi
    done
    [ -z "$argo" ] && { err "未能获取临时域名"; exit 1; }
    echo "临时域名: $argo"
    gen_links "$protocol" "$uuid" "$argo" "$urlpath" "$isp" "speed.cloudflare.com" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
}

# 模式3: Token+域名固定隧道
token_tunnel() {
    mkdir -p "$DIR"

    # 协议选择（可重试）
    while true; do
        read -r -p "请选择协议(1.vmess,2.vless,默认1): " protocol
        [ -z "$protocol" ] && protocol=1
        if [ "$protocol" = "1" ] || [ "$protocol" = "2" ]; then break; fi
        warn "请输入 1 或 2"
    done

    # Token 输入（可重试 + 确认）
    while true; do
        echo -e "\n${GREEN}请粘贴 Cloudflare Tunnel Token${NC}"
        echo "提示: Token 很长(200+字符)，粘贴后按回车"
        echo "      如果粘贴有误，输入 n 重新粘贴"
        read -r -p "Token: " token
        if [ -z "$token" ]; then
            warn "Token 不能为空，请重新粘贴 (Ctrl+C 退出)"
            continue
        fi
        echo -e "  ${GREEN}你输入的 Token (前30字符):${NC} ${token:0:30}..."
        echo -e "  ${GREEN}Token 长度:${NC} ${#token} 字符"
        read -r -p "  确认正确？(Y/n, 默认Y): " yn
        [ "$yn" = "n" ] || [ "$yn" = "N" ] && { warn "请重新粘贴 Token"; continue; }
        break
    done

    # 域名输入（可重试）
    while true; do
        read -r -p "请输入绑定域名(如: node.example.com): " tdomain
        if [ -z "$tdomain" ]; then
            warn "域名不能为空，请重新输入 (Ctrl+C 退出)"
            continue
        fi
        if ! echo "$tdomain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            warn "域名格式不正确，请重新输入"
            continue
        fi
        echo -e "  ${GREEN}你输入的是:${NC} $tdomain"
        read -r -p "  确认正确？(Y/n, 默认Y): " yn
        [ "$yn" = "n" ] || [ "$yn" = "N" ] && { warn "请重新输入域名"; continue; }
        break
    done

    # 端口输入（可重试）
    while true; do
        read -r -p "请输入本地服务端口(默认8001): " port
        [ -z "$port" ] && port=8001
        if [ "$port" -ge 1 ] && [ "$port" -le 65535 ] 2>/dev/null; then break; fi
        warn "端口必须是 1-65535 的数字"
    done

    # IPv4/6 选择
    while true; do
        read -r -p "请选择argo连接IPV4或IPV6(输入4或6,默认4): " ips
        [ -z "$ips" ] && ips=4
        if [ "$ips" = "4" ] || [ "$ips" = "6" ]; then break; fi
        warn "请输入 4 或 6"
    done

    stop_services >/dev/null 2>&1

    echo "[INFO] 获取节点信息..."
    get_radar_info "$ips"
    isp=$(gen_node_name)
    echo "[OK] 节点名称: $isp"

    if ! download_all; then err "下载失败"; exit 1; fi

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo "$uuid" | cut -d- -f1)

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"

    echo "$token" > "$DIR/tunnel.token"
    chmod 600 "$DIR/tunnel.token"

    # 安装内核服务
    local runcmd=$(get_run_cmd)
    install_systemd "${CORE_UNIT}" "$runcmd" "$CORE_NAME"

    # 安装 cloudflared 服务 (token 模式)
    if is_alpine; then
        cat > /etc/local.d/cloudflared.start <<EOF
$DIR/cloudflared tunnel --no-autoupdate --edge-ip-version $ips --protocol http2 run --token "\$(cat $DIR/tunnel.token)" &
EOF
        chmod +x /etc/local.d/cloudflared.start
        /etc/local.d/cloudflared.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/smx-cf.service <<EOF
[Unit]
Description=Cloudflare Tunnel (Token)
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/bin/bash -c '$DIR/cloudflared tunnel --no-autoupdate --edge-ip-version $ips --protocol http2 run --token \$(cat $DIR/tunnel.token)'
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl stop smx-cf.service >/dev/null 2>&1
        systemctl enable smx-cf.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start smx-cf.service
    fi

    gen_links "$protocol" "$uuid" "$tdomain" "$urlpath" "$isp" "$tdomain" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
    echo -e "\n服务已安装, 开机自启已启用"
}

# ---------- 卸载 ----------
uninstall_all() {
    # 清理所有三内核的服务
    for u in smx-xray smx-singbox smx-mihomo smx-cf; do
        systemctl stop ${u}.service >/dev/null 2>&1
        systemctl disable ${u}.service >/dev/null 2>&1
        rm -f /lib/systemd/system/${u}.service /etc/local.d/${u}.start
    done
    kill -9 $(ps -ef | grep -E 'xray run|sing-box run|mihomo -d|cloudflared.*tunnel' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    # 清理所有内核目录与缓存
    rm -rf /opt/xray /opt/singbox /opt/mihomo /opt/smx
    rm -f /root/v2ray.txt ./v2ray.txt "/usr/bin/smx" 2>/dev/null
    # 清理网页授权模式产生的云凭证 (cert.pem + tunnel json)
    rm -rf /root/.cloudflared 2>/dev/null
    systemctl --system daemon-reload >/dev/null 2>&1
    clear
    echo "所有服务都卸载完成"
}

# ---------- 清空缓存 ----------
clear_cache() {
    kill -9 $(ps -ef | grep -E "xray run|sing-box run|mihomo -d|cloudflared.*tunnel" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    rm -rf "$DIR"/*.log "$DIR"/v2ray.txt 2>/dev/null
    echo "缓存已清理"
}

# ---------- 主菜单 ----------

installtunnel() {
    mkdir -p "$DIR"

    # 协议选择（可重试）
    while true; do
        read -r -p "请选择协议(1.vmess,2.vless,默认1): " protocol
        [ -z "$protocol" ] && protocol=1
        if [ "$protocol" = "1" ] || [ "$protocol" = "2" ]; then break; fi
        warn "请输入 1 或 2"
    done

    # IPv4/6 选择
    while true; do
        read -r -p "请选择argo连接IPV4或IPV6(输入4或6,默认4): " ips
        [ -z "$ips" ] && ips=4
        if [ "$ips" = "4" ] || [ "$ips" = "6" ]; then break; fi
        warn "请输入 4 或 6"
    done

    stop_services >/dev/null 2>&1

    echo "[INFO] 获取节点信息..."
    get_radar_info "$ips"
    isp=$(gen_node_name)
    echo "[OK] 节点名称: $isp"

    mkdir -p "$DIR"
    if ! download_all; then err "下载失败"; exit 1; fi

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo "$uuid" | cut -d- -f1)
    port=$((RANDOM % 40000 + 10000))

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"

    clear
    echo "复制下面的链接, 用浏览器打开并授权需要绑定的域名"
    echo "在网页授权完毕后会继续进行下一步设置"
    "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel login

    clear
    "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel list >"$DIR/argo.log" 2>&1
    echo -e "ARGO TUNNEL 当前已经绑定的服务如下\n"
    sed 1,2d "$DIR/argo.log" | awk '{print $2}'
    echo -e "\n自定义一个完整二级域名, 例如 xxx.example.com"
    echo "必须是网页里面绑定授权的域名才生效, 不能乱输入"

    # 域名输入（可重试 + 确认）
    while true; do
        read -r -p "输入绑定域名的完整二级域名: " domain
        if [ -z "$domain" ]; then
            warn "域名不能为空，请重新输入 (Ctrl+C 退出)"
            continue
        fi
        if ! echo "$domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            warn "域名格式不正确，请重新输入"
            continue
        fi
        echo -e "  ${GREEN}你输入的是:${NC} $domain"
        read -r -p "  确认正确？(Y/n, 默认Y): " yn
        [ "$yn" = "n" ] || [ "$yn" = "N" ] && { warn "请重新输入域名"; continue; }
        break
    done
    name=$(echo "$domain" | awk -F\. '{print $1}')
    if [ $(sed 1,2d "$DIR/argo.log" | awk '{print $2}' | grep -w $name | wc -l) == 0 ]; then
        echo "创建 TUNNEL $name"
        "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel create $name >"$DIR/argo.log" 2>&1
        echo "TUNNEL $name 创建成功"
    else
        echo "TUNNEL $name 已经存在"
        if [ ! -f "/root/.cloudflared/$(sed 1,2d "$DIR/argo.log" | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json" ]; then
            echo "证书文件不存在, 重建 TUNNEL $name"
            "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel cleanup $name >"$DIR/argo.log" 2>&1
            "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel delete $name >"$DIR/argo.log" 2>&1
            "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel create $name >"$DIR/argo.log" 2>&1
        else
            echo "清理 TUNNEL $name"
            "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel cleanup $name >"$DIR/argo.log" 2>&1
        fi
    fi
    echo "绑定 TUNNEL $name 到域名 $domain"
    "$DIR/cloudflared" --edge-ip-version $ips --protocol http2 tunnel route dns --overwrite-dns $name $domain >"$DIR/argo.log" 2>&1
    echo "$domain 绑定成功"
    tunneluuid=$(grep -oE '[0-9a-f-]{36}' "$DIR/argo.log" | head -1)

    # 生成 cloudflared config
    cat > "$DIR/cloudflared.yaml" <<EOF
tunnel: $tunneluuid
credentials-file: /root/.cloudflared/$tunneluuid.json
ingress:
  - hostname: $domain
    service: http://localhost:$port
  - service: http_status:404
EOF

    # 安装内核服务
    local runcmd=$(get_run_cmd)
    install_systemd "${CORE_UNIT}" "$runcmd" "$CORE_NAME"

    # 安装 cloudflared 服务 (config 模式)
    if is_alpine; then
        cat > /etc/local.d/cloudflared.start <<EOF
$DIR/cloudflared --edge-ip-version $ips --protocol http2 tunnel --config $DIR/cloudflared.yaml run $name &
EOF
        chmod +x /etc/local.d/cloudflared.start
        /etc/local.d/cloudflared.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/smx-cf.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=$DIR/cloudflared --edge-ip-version $ips --protocol http2 tunnel --config $DIR/cloudflared.yaml run $name
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl stop smx-cf.service >/dev/null 2>&1
        systemctl enable smx-cf.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start smx-cf.service
    fi

    gen_links "$protocol" "$uuid" "$domain" "$urlpath" "$isp" "$domain" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
    echo -e "\n服务安装完成, 开机自启已启用"
}

main_menu() {
    while true; do
        clear
        echo "===================================="
        echo "  统一代理节点部署脚本"
        echo ""
        echo "  当前内核: $CORE_NAME"
        echo "  安装目录: $DIR"
        echo "===================================="
        echo "  1. 重新选择内核"
        echo "  2. 临时隧道 (trycloudflare, 重启失效)"
        echo "  3. 安装服务 (网页授权绑定域名, 开机自启)"
        echo "  4. Token+域名 (固定隧道, 开机自启)"
        echo "  5. 卸载服务"
        echo "  6. 清空缓存"
        echo "  0. 退出"
        read -p "请输入选择(默认2): " m
        [ -z "$m" ] && m=2
        case "$m" in
            1) choose_core ;;
            2) quicktunnel ;;
            3) installtunnel ;;
            4) token_tunnel ;;
            5) uninstall_all ;;
            6) clear_cache ;;
            *) echo "退出"; exit 0 ;;
        esac
        echo ""
        echo "===================================="
        echo "  部署/操作已完成"
        echo "  如需继续操作请重新运行: bash smx.sh"
        echo "===================================="
        exit 0
    done
}




# 模式2: 安装服务 (网页授权绑定域名)

# ---------- 入口 ----------
[ "$(id -u)" -ne 0 ] && { echo "请用 root 运行"; exit 1; }
install_deps
choose_core
main_menu
