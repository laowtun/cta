#!/bin/bash
# =============================================================================
# smxc.sh - 代理节点部署脚本
# 数据源: speed.cloudflare.com/meta
# 节点名格式: 国家-AS编号-运营商-城市_tls
# 部署模式: 临时隧道 / Token固定隧道 / 网页授权
# =============================================================================

# ---------- 全局变量 ----------
DIR="/opt/smx"
CMD="/usr/bin/smxc"
CORE=""
CORE_BIN=""
CORE_NAME=""
CORE_UNIT=""
RADAR_JSON=""

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

# ---------- IP信息获取 ----------
# speed.cloudflare.com/meta 获取完整信息（含 asOrganization）
get_radar_info() {
    RADAR_JSON=$(curl --max-time 8 -sS "https://speed.cloudflare.com/meta" \
        -H "Referer: https://speed.cloudflare.com/" \
        -H "Origin: https://speed.cloudflare.com" 2>/dev/null)
    echo "$RADAR_JSON" > "$DIR/radar.json" 2>/dev/null
}
radar_field() {
    local key="$1"
    echo "$RADAR_JSON" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -1
}
gen_node_name() {
    local c=$(radar_field country) a=$(radar_field asn) org=$(radar_field asOrganization) ci=$(radar_field city)
    [ -z "$c" ] && c=XX; [ -z "$a" ] && a=0; [ -z "$org" ] && org=Unknown; [ -z "$ci" ] && ci=XX
    # 城市名连字符改下划线，避免和分隔符混淆
    ci=$(echo "$ci" | tr '-' '_')
    echo "${c}-AS${a}-${org}-${ci}"
}

# ---------- 链接生成 ----------
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
    if [ -f "$file" ] && [ -s "$file" ]; then
        echo ""
        echo -e "${GREEN}========== 节点信息 ==========${NC}"
        cat "$file"
        echo -e "${GREEN}==============================${NC}"
        echo ""
    fi
    cp -f "$file" "$DIR/v2ray.txt" 2>/dev/null
    cp -f "$file" /root/v2ray.txt 2>/dev/null
    cp -f "$file" ./v2ray.txt 2>/dev/null
}

# ---------- 选择内核 ----------
choose_core() {
    clear
    echo "===================================="
    echo "  smxc.sh - 代理节点部署"
    echo "  数据源: speed.cloudflare.com/meta"
    echo "===================================="
    echo "  1. Xray"
    echo "  2. sing-box"
    echo "  3. mihomo (Clash Meta)"
    echo "  0. 退出"
    read -p "请选择(默认1): " core
    [ -z "$core" ] && core=1
    case "$core" in
        1) CORE=xray;     CORE_NAME="Xray";     CORE_UNIT="smx-xray" ;;
        2) CORE=singbox;  CORE_NAME="sing-box"; CORE_UNIT="smx-singbox" ;;
        3) CORE=mihomo;   CORE_NAME="mihomo";   CORE_UNIT="smx-mihomo" ;;
        *) echo "退出"; exit 0 ;;
    esac
    DIR="/opt/${CORE}"
    echo "  已选择: $CORE_NAME ($DIR)"
    sleep 1
}

# ---------- 下载 ----------
get_arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo amd64 ;;
        armv8|arm64|aarch64) echo arm64 ;;
        armv7l|armv71) echo armv7 ;;
        arm|armv6l) echo arm6 ;;
        *) echo unsupported ;;
    esac
}
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
    curl -fsSL --retry 2 -o xray.zip "$url" || { err "Xray 下载失败"; return 1; }
    unzip -o xray.zip -d xray >/dev/null 2>&1 || { err "Xray 解压失败"; return 1; }
    chmod +x "$dst/xray/xray"; CORE_BIN="$dst/xray/xray"; rm -rf "$dst/xray.zip"
    echo "  Xray 就绪: $CORE_BIN"
}
download_singbox() {
    local dst="$DIR" arch=$(get_arch) ver url
    mkdir -p "$dst"
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
    curl -fsSL --retry 2 -o singbox.tar.gz "$url" || { err "sing-box 下载失败"; return 1; }
    tar xzf singbox.tar.gz -C "$dst" 2>/tmp/sb_err || { err "sing-box 解压失败"; return 1; }
    mv "$dst"/sing-box-*/* "$dst"/ 2>/dev/null; rm -rf "$dst"/sing-box-*/
    chmod +x "$dst/sing-box" 2>/dev/null; CORE_BIN="$dst/sing-box"; rm -rf "$dst/singbox.tar.gz"
    echo "  sing-box 就绪: $CORE_BIN"
}
download_mihomo() {
    local dst="$DIR" arch=$(get_arch) ver url
    mkdir -p "$dst"
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
    curl -fsSL --retry 2 -o mihomo.gz "$url" || { err "mihomo 下载失败"; return 1; }
    gzip -d mihomo.gz 2>/dev/null || { [ -f mihomo.gz ] && mv mihomo.gz mihomo 2>/dev/null; }
    [ ! -f "$dst/mihomo" ] && { err "mihomo 解压失败"; return 1; }
    chmod +x "$dst/mihomo"; CORE_BIN="$dst/mihomo"
    echo "  mihomo 就绪: $CORE_BIN"
}
download_cloudflared() {
    local dst="$DIR" arch=$(get_arch) url
    case "$arch" in
        amd64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
        arm64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
        armv7|arm6) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
        *) warn "cloudflared 不支持架构 $arch"; return 1 ;;
    esac
    echo "  下载 cloudflared ($arch)..."
    cd "$dst" && rm -rf cloudflared
    curl -fsSL --retry 2 -o cloudflared "$url" || { err "cloudflared 下载失败"; return 1; }
    chmod +x "$dst/cloudflared"; echo "  cloudflared 就绪"
}
download_all() {
    download_cloudflared || return 1
    case "$CORE" in
        xray)    download_xray || return 1 ;;
        singbox) download_singbox || return 1 ;;
        mihomo)  download_mihomo || return 1 ;;
    esac
}

# ---------- 配置生成 ----------
gen_config_xray() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" = "2" ]; then
        cat > "$conf" <<XEOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":$port,"protocol":"vless","settings":{"clients":[{"id":"$uuid","flow":""}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/$path"}}}],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
XEOF
    else
        cat > "$conf" <<XEOF
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":$port,"protocol":"vmess","settings":{"clients":[{"id":"$uuid","alterId":0}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/$path"}}}],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
XEOF
    fi
}
gen_config_singbox() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" = "2" ]; then
        cat > "$conf" <<XEOF
{"log":{"level":"warning","timestamp":true},"inbounds":[{"type":"vless","listen":"127.0.0.1","listen_port":$port,"users":[{"uuid":"$uuid","flow":""}],"transport":{"type":"ws","path":"/$path"}}],"outbounds":[{"type":"direct"}]}
XEOF
    else
        cat > "$conf" <<XEOF
{"log":{"level":"warning","timestamp":true},"inbounds":[{"type":"vmess","listen":"127.0.0.1","listen_port":$port,"users":[{"uuid":"$uuid","alterId":0}],"transport":{"type":"ws","path":"/$path"}}],"outbounds":[{"type":"direct"}]}
XEOF
    fi
}
gen_config_mihomo() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" = "2" ]; then
        cat > "$conf" <<XEOF
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
XEOF
    else
        cat > "$conf" <<XEOF
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
XEOF
    fi
}
gen_config() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    case "$CORE" in
        xray)    gen_config_xray "$protocol" "$port" "$uuid" "$path" "$conf" ;;
        singbox) gen_config_singbox "$protocol" "$port" "$uuid" "$path" "$conf" ;;
        mihomo)  gen_config_mihomo "$protocol" "$port" "$uuid" "$path" "$conf" ;;
    esac
}

# ---------- systemd ----------
get_run_cmd() {
    case "$CORE" in
        xray)    echo "$CORE_BIN run -c $DIR/config.json" ;;
        singbox) echo "$CORE_BIN run -c $DIR/config.json" ;;
        mihomo)  echo "$CORE_BIN -d $DIR -f $DIR/config.yaml" ;;
    esac
}
config_file() {
    case "$CORE" in mihomo) echo "$DIR/config.yaml" ;; *) echo "$DIR/config.json" ;; esac
}
install_systemd() {
    local unit="$1" exec="$2" desc="$3"
    if is_alpine; then
        cat > /etc/local.d/${unit}.start <<SEOF
$exec &
SEOF
        chmod +x /etc/local.d/${unit}.start
        rc-update add local >/dev/null 2>&1
    else
        cat > /lib/systemd/system/${unit}.service <<SEOF
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
SEOF
        systemctl stop ${unit}.service >/dev/null 2>&1
        systemctl enable ${unit}.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start ${unit}.service
    fi
}
stop_services() {
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

# ---------- 模式1: 临时隧道 ----------
quicktunnel() {
    mkdir -p "$DIR"
    read -p "请选择协议(1.vmess,2.vless,默认1): " protocol
    [ -z "$protocol" ] && protocol=1
    stop_services >/dev/null 2>&1
    echo "[INFO] 获取节点信息..."
    get_radar_info
    isp=$(gen_node_name)
    echo "[OK] 节点名称: $isp"
    download_all || { err "下载失败"; exit 1; }
    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo "$uuid" | cut -d- -f1)
    port=$((RANDOM % 40000 + 10000))
    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"
    case "$CORE" in
        mihomo) "$CORE_BIN" -d "$DIR" -f "$DIR/config.yaml" >/dev/null 2>&1 & ;;
        *)      "$CORE_BIN" run -c "$DIR/config.json" >/dev/null 2>&1 & ;;
    esac
    sleep 1
    "$DIR/cloudflared" tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version 4 --protocol http2 >"$DIR/argo.log" 2>&1 &
    echo "等待 cloudflare argo 生成地址..."
    sleep 4; n=0
    while true; do
        n=$((n+1))
        argo=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/argo.log" | head -1 | sed 's#https://##')
        [ $n -gt 30 ] && { echo "获取地址超时, 检查日志"; cat "$DIR/argo.log"; break; }
        [ -z "$argo" ] && sleep 1 || break
    done
    [ -z "$argo" ] && { err "未能获取临时域名"; exit 1; }
    echo "临时域名: $argo"
    gen_links "$protocol" "$uuid" "$argo" "$urlpath" "$isp" "speed.cloudflare.com" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
}

# ---------- 模式3: Token+域名固定隧道 ----------
token_tunnel() {
    mkdir -p "$DIR"
    while true; do
        read -r -p "请选择协议(1.vmess,2.vless,默认1): " protocol
        [ -z "$protocol" ] && protocol=1
        { [ "$protocol" = "1" ] || [ "$protocol" = "2" ]; } && break
        warn "请输入 1 或 2"
    done
    while true; do
        echo -e "\n${GREEN}请粘贴 Cloudflare Tunnel Token${NC}"
        read -r -p "Token: " token
        [ -z "$token" ] && { warn "Token 不能为空，请重新粘贴"; continue; }
        echo -e "  ${GREEN}Token (前30字符):${NC} ${token:0:30}..."
        read -r -p "  确认正确？(Y/n, 默认Y): " yn
        { [ "$yn" = "n" ] || [ "$yn" = "N" ]; } && { warn "请重新粘贴"; continue; }
        break
    done
    while true; do
        read -r -p "请输入绑定域名(如: node.example.com): " tdomain
        [ -z "$tdomain" ] && { warn "域名不能为空"; continue; }
        echo "$tdomain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' || { warn "域名格式不正确"; continue; }
        echo -e "  ${GREEN}你输入的是:${NC} $tdomain"
        read -r -p "  确认正确？(Y/n, 默认Y): " yn
        { [ "$yn" = "n" ] || [ "$yn" = "N" ]; } && { warn "请重新输入"; continue; }
        break
    done
    while true; do
        read -r -p "请输入本地服务端口(默认8001): " port
        [ -z "$port" ] && port=8001
        { [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; } 2>/dev/null && break
        warn "端口必须是 1-65535 的数字"
    done
    stop_services >/dev/null 2>&1
    echo "[INFO] 获取节点信息..."
    get_radar_info; isp=$(gen_node_name)
    echo "[OK] 节点名称: $isp"
    download_all || { err "下载失败"; exit 1; }
    uuid=$(cat /proc/sys/kernel/random/uuid); urlpath=$(echo "$uuid" | cut -d- -f1)
    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"
    echo "$token" > "$DIR/tunnel.token"; chmod 600 "$DIR/tunnel.token"
    local runcmd=$(get_run_cmd)
    install_systemd "${CORE_UNIT}" "$runcmd" "$CORE_NAME"
    if is_alpine; then
        cat > /etc/local.d/cloudflared.start <<'CEOF'
$DIR/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 run --token "$(cat $DIR/tunnel.token)" &
CEOF
        chmod +x /etc/local.d/cloudflared.start
        /etc/local.d/cloudflared.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/smx-cf.service <<CEOF
[Unit]
Description=Cloudflare Tunnel (Token)
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/bin/bash -c "\$DIR/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 run --token \\\$(cat \$DIR/tunnel.token)"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
CEOF
        systemctl stop smx-cf.service >/dev/null 2>&1
        systemctl enable smx-cf.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start smx-cf.service
    fi
    gen_links "$protocol" "$uuid" "$tdomain" "$urlpath" "$isp" "$tdomain" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
    echo -e "\n服务已安装, 开机自启已启用"
}

# ---------- 模式2: 网页授权绑定域名 ----------
installtunnel() {
    mkdir -p "$DIR"
    while true; do
        read -r -p "请选择协议(1.vmess,2.vless,默认1): " protocol
        [ -z "$protocol" ] && protocol=1
        { [ "$protocol" = "1" ] || [ "$protocol" = "2" ]; } && break
        warn "请输入 1 或 2"
    done
    stop_services >/dev/null 2>&1
    echo "[INFO] 获取节点信息..."
    get_radar_info; isp=$(gen_node_name)
    echo "[OK] 节点名称: $isp"
    download_all || { err "下载失败"; exit 1; }
    uuid=$(cat /proc/sys/kernel/random/uuid); urlpath=$(echo "$uuid" | cut -d- -f1)
    port=$((RANDOM % 40000 + 10000))
    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"
    clear
    echo "复制下面的链接, 用浏览器打开并授权需要绑定的域名"
    echo "在网页授权完毕后会继续进行下一步设置"
    "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel login
    clear
    "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel list >"$DIR/argo.log" 2>&1
    echo -e "ARGO TUNNEL 当前已经绑定的服务如下\n"
    sed 1,2d "$DIR/argo.log" | awk '{print $2}'
    echo -e "\n自定义一个完整二级域名, 例如 xxx.example.com"
    echo "必须是网页里面绑定授权的域名才生效, 不能乱输入"
    while true; do
        read -r -p "输入绑定域名的完整二级域名: " domain
        [ -z "$domain" ] && { warn "域名不能为空"; continue; }
        echo "$domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' || { warn "域名格式不正确"; continue; }
        echo -e "  ${GREEN}你输入的是:${NC} $domain"
        read -r -p "  确认正确？(Y/n, 默认Y): " yn
        { [ "$yn" = "n" ] || [ "$yn" = "N" ]; } && { warn "请重新输入"; continue; }
        break
    done
    name=$(echo "$domain" | awk -F\. '{print $1}')
    if [ $(sed 1,2d "$DIR/argo.log" | awk '{print $2}' | grep -w $name | wc -l) = 0 ]; then
        echo "创建 TUNNEL $name"
        "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel create $name >"$DIR/argo.log" 2>&1
    else
        echo "TUNNEL $name 已经存在"
        "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel cleanup $name >"$DIR/argo.log" 2>&1
    fi
    echo "绑定 TUNNEL $name 到域名 $domain"
    "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel route dns --overwrite-dns $name $domain >"$DIR/argo.log" 2>&1
    tunneluuid=$(grep -oE '[0-9a-f-]{36}' "$DIR/argo.log" | head -1)
    cat > "$DIR/cloudflared.yaml" <<YEOF
tunnel: $tunneluuid
credentials-file: /root/.cloudflared/$tunneluuid.json
ingress:
  - hostname: $domain
    service: http://localhost:$port
  - service: http_status:404
YEOF
    local runcmd=$(get_run_cmd)
    install_systemd "${CORE_UNIT}" "$runcmd" "$CORE_NAME"
    if is_alpine; then
        cat > /etc/local.d/cloudflared.start <<CEOF
$DIR/cloudflared --edge-ip-version 4 --protocol http2 tunnel --config $DIR/cloudflared.yaml run $name &
CEOF
        chmod +x /etc/local.d/cloudflared.start
        /etc/local.d/cloudflared.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/smx-cf.service <<CEOF
[Unit]
Description=Cloudflare Tunnel
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=$DIR/cloudflared --edge-ip-version 4 --protocol http2 tunnel --config $DIR/cloudflared.yaml run $name
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
CEOF
        systemctl stop smx-cf.service >/dev/null 2>&1
        systemctl enable smx-cf.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start smx-cf.service
    fi
    gen_links "$protocol" "$uuid" "$domain" "$urlpath" "$isp" "$domain" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
    echo -e "\n服务安装完成, 开机自启已启用"
}

# ---------- 卸载 ----------
uninstall_all() {
    for u in smx-xray smx-singbox smx-mihomo smx-cf; do
        systemctl stop ${u}.service >/dev/null 2>&1
        systemctl disable ${u}.service >/dev/null 2>&1
        rm -f /lib/systemd/system/${u}.service /etc/local.d/${u}.start
    done
    kill -9 $(ps -ef | grep -E 'xray run|sing-box run|mihomo -d|cloudflared.*tunnel' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    rm -rf /opt/xray /opt/singbox /opt/mihomo /opt/smx
    rm -f /root/v2ray.txt ./v2ray.txt "/usr/bin/smxc" 2>/dev/null
    rm -rf /root/.cloudflared 2>/dev/null
    systemctl --system daemon-reload >/dev/null 2>&1
    clear; echo "所有服务都卸载完成"
}

# ---------- 清空缓存 ----------
clear_cache() {
    kill -9 $(ps -ef | grep -E "xray run|sing-box run|mihomo -d|cloudflared.*tunnel" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    rm -rf "$DIR"/*.log "$DIR"/v2ray.txt 2>/dev/null; echo "缓存已清理"
}

# ---------- 主菜单 ----------
main_menu() {
    while true; do
        clear
        echo "===================================="
        echo "  smxc.sh - 代理节点部署"
        echo "  数据源: speed.cloudflare.com/meta"
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
        echo "  如需继续操作请重新运行: bash smxc.sh"
        echo "===================================="
        exit 0
    done
}

# ---------- 入口 ----------
[ "$(id -u)" -ne 0 ] && { echo "请用 root 运行"; exit 1; }
install_deps
choose_core
main_menu
