#!/bin/bash
# smxc.sh - Proxy deploy script (speed.cloudflare.com/meta)
# Node name: country-AS-asn-org-city_tls
# Modes: quick tunnel / token tunnel / web auth tunnel

DIR="/opt/smx"
CORE="" CORE_BIN="" CORE_NAME="" CORE_UNIT="" RADAR_JSON=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
[ ! -t 1 ] || [ "$(tput colors 2>/dev/null)" -lt 8 ] && RED='' GREEN='' YELLOW='' NC=''
info()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

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

# --- speed.cloudflare.com/meta ---
get_radar_info() {
    RADAR_JSON=$(curl --max-time 8 -sS "https://speed.cloudflare.com/meta" \
        -H "Referer: https://speed.cloudflare.com/" \
        -H "Origin: https://speed.cloudflare.com" 2>/dev/null)
    echo "$RADAR_JSON" > "$DIR/radar.json" 2>/dev/null
}
radar_field() {
    echo "$RADAR_JSON" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -1
}
gen_node_name() {
    local c=$(radar_field country) a=$(radar_field asn) org=$(radar_field asOrganization) ci=$(radar_field city)
    [ -z "$c" ] && c=XX; [ -z "$a" ] && a=0; [ -z "$org" ] && org=Unknown; [ -z "$ci" ] && ci=XX
    echo "${c}-AS${a}-${org}-${ci}"
}

# --- links ---
gen_links() {
    local protocol="$1" uuid="$2" host="$3" path="$4" isp="$5" add="${6:-speed.cloudflare.com}" out="$7"
    if [ "$protocol" = "1" ]; then
        echo -e "vmess links generated, $add can be replaced with CF optimized IP\n" > "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"/$path\",\"port\":\"443\",\"ps\":\"$(echo "$isp" | sed 's/_/ /g')_tls\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\nPort 443 can be changed to 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"/$path\",\"port\":\"80\",\"ps\":\"$(echo "$isp" | sed 's/_/ /g')\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\nPort 80 can be changed to 8080 8880 2052 2082 2086 2095\n" >> "$out"
    else
        local ps_url="$(echo "$isp" | sed -e 's/_/%20/g' -e 's/,/%2C/g')"
        echo -e "vless links generated, $add can be replaced with CF optimized IP\n" > "$out"
        echo "vless://$uuid@$add:443?encryption=none&security=tls&type=ws&host=$host&path=/$path#${ps_url}_tls" >> "$out"
        echo -e "\nPort 443 can be changed to 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vless://$uuid@$add:80?encryption=none&security=none&type=ws&host=$host&path=/$path#$ps_url" >> "$out"
        echo -e "\nPort 80 can be changed to 8080 8880 2052 2082 2086 2095\n" >> "$out"
    fi
}
show_links() {
    local file="$1"
    if [ -f "$file" ] && [ -s "$file" ]; then
        echo ""; echo -e "${GREEN}========== Node Info ==========${NC}"
        cat "$file"
        echo -e "${GREEN}==============================${NC}"; echo ""
    fi
    cp -f "$file" "$DIR/v2ray.txt" 2>/dev/null
    cp -f "$file" /root/v2ray.txt 2>/dev/null
    cp -f "$file" ./v2ray.txt 2>/dev/null
}

# --- choose core ---
choose_core() {
    clear
    echo "===================================="
    echo "  smxc.sh - Proxy Deploy"
    echo "  speed.cloudflare.com/meta"
    echo "===================================="
    echo "  1. Xray"
    echo "  2. sing-box"
    echo "  3. mihomo (Clash Meta)"
    echo "  0. Exit"
    read -p "Choose [default 1]: " core
    [ -z "$core" ] && core=1
    case "$core" in
        1) CORE=xray;     CORE_NAME="Xray";     CORE_UNIT="smx-xray" ;;
        2) CORE=singbox;  CORE_NAME="sing-box"; CORE_UNIT="smx-singbox" ;;
        3) CORE=mihomo;   CORE_NAME="mihomo";   CORE_UNIT="smx-mihomo" ;;
        *) echo "Exit"; exit 0 ;;
    esac
    DIR="/opt/${CORE}"
    echo "  Selected: $CORE_NAME ($DIR)"
    sleep 1
}

# --- download ---
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
        *) warn "Xray unsupported arch $arch"; return 1 ;;
    esac
    echo "  Downloading Xray ($arch)..."
    cd "$dst" && rm -rf xray xray.zip
    curl -fsSL --retry 2 -o xray.zip "$url" || { err "Xray download failed"; return 1; }
    unzip -o xray.zip -d xray >/dev/null 2>&1 || { err "Xray unzip failed"; return 1; }
    chmod +x "$dst/xray/xray"; CORE_BIN="$dst/xray/xray"; rm -rf "$dst/xray.zip"
    echo "  Xray ready: $CORE_BIN"
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
        *) warn "sing-box unsupported arch $arch"; return 1 ;;
    esac
    echo "  Downloading sing-box $ver ($arch)..."
    cd "$dst" && rm -rf singbox.tar.gz singbox
    curl -fsSL --retry 2 -o singbox.tar.gz "$url" || { err "sing-box download failed"; return 1; }
    tar xzf singbox.tar.gz -C "$dst" 2>/tmp/sb_err || { err "sing-box unzip failed"; return 1; }
    mv "$dst"/sing-box-*/* "$dst"/ 2>/dev/null; rm -rf "$dst"/sing-box-*/
    chmod +x "$dst/sing-box" 2>/dev/null; CORE_BIN="$dst/sing-box"; rm -rf "$dst/singbox.tar.gz"
    echo "  sing-box ready: $CORE_BIN"
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
        *) warn "mihomo unsupported arch $arch"; return 1 ;;
    esac
    echo "  Downloading mihomo $ver ($arch)..."
    cd "$dst" && rm -rf mihomo.gz mihomo
    curl -fsSL --retry 2 -o mihomo.gz "$url" || { err "mihomo download failed"; return 1; }
    gzip -d mihomo.gz 2>/dev/null || { [ -f mihomo.gz ] && mv mihomo.gz mihomo 2>/dev/null; }
    [ ! -f "$dst/mihomo" ] && { err "mihomo unzip failed"; return 1; }
    chmod +x "$dst/mihomo"; CORE_BIN="$dst/mihomo"
    echo "  mihomo ready: $CORE_BIN"
}
download_cloudflared() {
    local dst="$DIR" arch=$(get_arch) url
    case "$arch" in
        amd64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
        arm64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
        armv7|arm6) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
        *) warn "cloudflared unsupported arch $arch"; return 1 ;;
    esac
    echo "  Downloading cloudflared ($arch)..."
    cd "$dst" && rm -rf cloudflared
    curl -fsSL --retry 2 -o cloudflared "$url" || { err "cloudflared download failed"; return 1; }
    chmod +x "$dst/cloudflared"; echo "  cloudflared ready"
}
download_all() {
    download_cloudflared || return 1
    case "$CORE" in
        xray)    download_xray || return 1 ;;
        singbox) download_singbox || return 1 ;;
        mihomo)  download_mihomo || return 1 ;;
    esac
}

# --- config ---
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

# --- systemd ---
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

# --- Mode 1: Quick Tunnel ---
quicktunnel() {
    mkdir -p "$DIR"
    read -p "Protocol [1.vmess,2.vless, default 1]: " protocol
    [ -z "$protocol" ] && protocol=1
    stop_services >/dev/null 2>&1
    echo "[INFO] Getting node info..."
    get_radar_info
    isp=$(gen_node_name)
    echo "[OK] Node name: $isp"
    download_all || { err "Download failed"; exit 1; }
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
    echo "Waiting for cloudflare argo address..."
    sleep 4; n=0
    while true; do
        n=$((n+1))
        argo=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/argo.log" | head -1 | sed 's#https://##')
        [ $n -gt 30 ] && { echo "Timeout, check log"; cat "$DIR/argo.log"; break; }
        [ -z "$argo" ] && sleep 1 || break
    done
    [ -z "$argo" ] && { err "Failed to get temp domain"; exit 1; }
    echo "Temp domain: $argo"
    gen_links "$protocol" "$uuid" "$argo" "$urlpath" "$isp" "speed.cloudflare.com" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
}

# --- Mode 3: Token Tunnel ---
token_tunnel() {
    mkdir -p "$DIR"
    while true; do
        read -r -p "Protocol [1.vmess,2.vless, default 1]: " protocol
        [ -z "$protocol" ] && protocol=1
        { [ "$protocol" = "1" ] || [ "$protocol" = "2" ]; } && break
        warn "Enter 1 or 2"
    done
    while true; do
        echo -e "\n${GREEN}Paste Cloudflare Tunnel Token${NC}"
        read -r -p "Token: " token
        [ -z "$token" ] && { warn "Token empty, retry"; continue; }
        echo -e "  ${GREEN}Token (first 30):${NC} ${token:0:30}..."
        read -r -p "  Confirm? [Y/n, default Y]: " yn
        { [ "$yn" = "n" ] || [ "$yn" = "N" ]; } && { warn "Retry"; continue; }
        break
    done
    while true; do
        read -r -p "Domain (e.g. node.example.com): " tdomain
        [ -z "$tdomain" ] && { warn "Domain required"; continue; }
        echo "$tdomain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' || { warn "Invalid domain"; continue; }
        echo -e "  ${GREEN}Domain:${NC} $tdomain"
        read -r -p "  Confirm? [Y/n, default Y]: " yn
        { [ "$yn" = "n" ] || [ "$yn" = "N" ]; } && { warn "Retry"; continue; }
        break
    done
    while true; do
        read -r -p "Local port [default 8001]: " port
        [ -z "$port" ] && port=8001
        { [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; } 2>/dev/null && break
        warn "Port must be 1-65535"
    done
    stop_services >/dev/null 2>&1
    echo "[INFO] Getting node info..."
    get_radar_info; isp=$(gen_node_name)
    echo "[OK] Node name: $isp"
    download_all || { err "Download failed"; exit 1; }
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
    echo -e "\nService installed, auto-start enabled"
}

# --- Mode 2: Web Auth ---
installtunnel() {
    mkdir -p "$DIR"
    while true; do
        read -r -p "Protocol [1.vmess,2.vless, default 1]: " protocol
        [ -z "$protocol" ] && protocol=1
        { [ "$protocol" = "1" ] || [ "$protocol" = "2" ]; } && break
        warn "Enter 1 or 2"
    done
    stop_services >/dev/null 2>&1
    echo "[INFO] Getting node info..."
    get_radar_info; isp=$(gen_node_name)
    echo "[OK] Node name: $isp"
    download_all || { err "Download failed"; exit 1; }
    uuid=$(cat /proc/sys/kernel/random/uuid); urlpath=$(echo "$uuid" | cut -d- -f1)
    port=$((RANDOM % 40000 + 10000))
    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$(config_file)"
    clear
    echo "Copy the link below, open in browser to authorize domain"
    "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel login
    clear
    "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel list >"$DIR/argo.log" 2>&1
    echo -e "Current ARGO TUNNEL bindings:\n"
    sed 1,2d "$DIR/argo.log" | awk '{print $2}'
    echo -e "\nEnter full subdomain, e.g. xxx.example.com"
    while true; do
        read -r -p "Domain: " domain
        [ -z "$domain" ] && { warn "Domain required"; continue; }
        echo "$domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' || { warn "Invalid"; continue; }
        echo -e "  ${GREEN}Domain:${NC} $domain"
        read -r -p "  Confirm? [Y/n, default Y]: " yn
        { [ "$yn" = "n" ] || [ "$yn" = "N" ]; } && continue
        break
    done
    name=$(echo "$domain" | awk -F\. '{print $1}')
    if [ $(sed 1,2d "$DIR/argo.log" | awk '{print $2}' | grep -w $name | wc -l) = 0 ]; then
        echo "Creating TUNNEL $name"
        "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel create $name >"$DIR/argo.log" 2>&1
    else
        echo "TUNNEL $name exists"
        "$DIR/cloudflared" --edge-ip-version 4 --protocol http2 tunnel cleanup $name >"$DIR/argo.log" 2>&1
    fi
    echo "Binding TUNNEL $name to $domain"
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
    echo -e "\nService installed, auto-start enabled"
}

# --- uninstall ---
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
    clear; echo "All services uninstalled"
}
clear_cache() {
    kill -9 $(ps -ef | grep -E "xray run|sing-box run|mihomo -d|cloudflared.*tunnel" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    rm -rf "$DIR"/*.log "$DIR"/v2ray.txt 2>/dev/null; echo "Cache cleared"
}

# --- main menu ---
main_menu() {
    while true; do
        clear
        echo "===================================="
        echo "  smxc.sh - Proxy Deploy"
        echo "  speed.cloudflare.com/meta"
        echo ""
        echo "  Core: $CORE_NAME"
        echo "  Dir:  $DIR"
        echo "===================================="
        echo "  1. Choose core"
        echo "  2. Quick tunnel (trycloudflare, no persist)"
        echo "  3. Web auth tunnel (domain binding, auto-start)"
        echo "  4. Token tunnel (fixed, auto-start)"
        echo "  5. Uninstall"
        echo "  6. Clear cache"
        echo "  0. Exit"
        read -p "Choose [default 2]: " m
        [ -z "$m" ] && m=2
        case "$m" in
            1) choose_core ;;
            2) quicktunnel ;;
            3) installtunnel ;;
            4) token_tunnel ;;
            5) uninstall_all ;;
            6) clear_cache ;;
            *) echo "Exit"; exit 0 ;;
        esac
        echo ""
        echo "===================================="
        echo "  Done. Run again: bash smxc.sh"
        echo "===================================="
        exit 0
    done
}

[ "$(id -u)" -ne 0 ] && { echo "Run as root"; exit 1; }
install_deps
choose_core
main_menu
