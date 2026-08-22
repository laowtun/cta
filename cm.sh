#!/bin/bash
# ---------------------------------------------------------------
# cm.sh - Cloudflare mihomo 综合部署脚本
#
# 模式:
#   1. 临时隧道    - trycloudflare.com, 重启失效
#   2. 安装服务    - 网页授权绑定域名 (named tunnel + systemd/Alpine 自启)
#   3. Token+域名  - 输入 Cloudflare Tunnel Token + 域名 (固定隧道)
#   4. 卸载服务
#   5. 清空缓存
#   0. 退出
#
# 内核: mihomo (Clash Meta)
# 节点名称: Cloudflare Radar API ({国家}-asn{ASN}-{城市})
# ---------------------------------------------------------------

# 云flare Radar IP 检测 API
IPv4_API="https://ipv4-check-perf.radar.cloudflare.com/"
IPv6_API="https://ipv6-check-perf.radar.cloudflare.com/"

# 目录/服务标识
DIR="/opt/cm"
SVC="mihomo"
CMD="/usr/bin/cm"

# =============== 系统检测与依赖安装 (多包管理器) ===============
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")

detect_system_index() {
    n=0
    local os_name=$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d \" -f2 | awk '{print $1}')
    for i in ${linux_os[@]}; do
        if [ "$i" == "$os_name" ]; then
            return
        else
            n=$((n+1))
        fi
    done
    if [ $n == ${#linux_os[@]} ]; then
        echo "当前系统 $os_name 没有 100% 适配，默认使用 APT 包管理器"
        n=0
    fi
}

install_deps() {
    detect_system_index
    [ -z "$(type -P curl)" ] && { ${linux_update[$n]} >/dev/null 2>&1; ${linux_install[$n]} curl >/dev/null 2>&1; }
    [ -z "$(type -P gzip)" ] && { ${linux_update[$n]} >/dev/null 2>&1; ${linux_install[$n]} gzip >/dev/null 2>&1; }
    if [ "$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d \" -f2 | awk '{print $1}')" != "Alpine" ]; then
        [ -z "$(type -P systemctl)" ] && { ${linux_update[$n]} >/dev/null 2>&1; ${linux_install[$n]} systemctl >/dev/null 2>&1; }
    fi
}

is_alpine() {
    [ "$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
}

# =============== Cloudflare Radar 节点名称生成 ===============
get_radar_info() {
    local ipv="$1"
    local api
    [ "$ipv" == "6" ] && api="$IPv6_API" || api="$IPv4_API"
    RADAR_JSON=$(curl --max-time 8 -sS "$api" 2>/dev/null)
    echo "采集完成: $api"
}

radar_field() {
    local key="$1"
    local json="${RADAR_JSON}"
    local val
    val=$(echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -1)
    [ -z "$val" ] && val="XX"
    echo "$val"
}

generate_node_name() {
    local country=$(radar_field country)
    local asn=$(radar_field asn)
    local city=$(radar_field city)
    echo "${country}-asn${asn}-${city}"
}

# =============== 按架构下载 mihomo + cloudflared ===============
# 获取 mihomo 最新版本号
get_mihomo_version() {
    local v
    v=$(curl -fsSL --retry 2 "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+')
    echo "${v#v}"
}

# $1 = 目标目录
download_binaries() {
    local dest="${1:-$DIR}"
    mkdir -p "$dest"
    cd "$dest"
    rm -rf mihomo mihomo.gz cloudflared-linux
    echo "[INFO] 正在获取 mihomo 最新版本..."
    local ver=$(get_mihomo_version)
    [ -z "$ver" ] && ver="1.19.30"
    echo "[INFO] mihomo 版本: $ver"

    local arch="$(uname -m)"
    echo "[INFO] 正在下载 mihomo + cloudflared (架构: $arch)..."
    case "$arch" in
        x86_64 | x64 | amd64)
            MIH_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-v1-v${ver}.gz"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        armv8 | arm64 | aarch64)
            echo "[INFO] 检测到 arm64"
            MIH_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-arm64-v1-v${ver}.gz"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        armv7l | armv71)
            MIH_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-armv7-v1-v${ver}.gz"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
            ;;
        *)
            echo "[ERROR] 当前架构 $arch 没有适配"
            exit 1
            ;;
    esac

    if ! curl -fsSL --retry 2 --retry-delay 2 -o mihomo.gz "$MIH_URL"; then
        echo "[ERROR] mihomo 下载失败: $MIH_URL"
        exit 1
    fi
    if ! curl -fsSL --retry 2 --retry-delay 2 -o cloudflared-linux "$CLOUD_URL"; then
        echo "[ERROR] cloudflared 下载失败: $CLOUD_URL"
        exit 1
    fi
    if ! gzip -d mihomo.gz 2>/dev/null && [ -f mihomo.gz ]; then
        # 若解压失败但文件在, 尝试直接改名
        mv mihomo.gz mihomo 2>/dev/null
    fi
    chmod +x mihomo cloudflared-linux 2>/dev/null
    echo "[OK] mihomo 与 cloudflared 下载完成 (位于 $dest)"
}

# =============== 生成 mihomo config.yaml ===============
# $1 = protocol (1 vmess / 2 vless)  $2 = port  $3 = uuid  $4 = path  $5 = 配置文件路径
gen_config() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" == "1" ]; then
        cat > "$conf" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: true

listeners:
  - name: vmess-ws-in
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
    else
        cat > "$conf" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: true

listeners:
  - name: vless-ws-in
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
    fi
}

# =============== 生成 vmess/vless 链接 ===============
# $1 = protocol  $2 = uuid  $3 = host   $4 = path  $5 = node_name  $6 = 地址  $7 = 输出文件
gen_links() {
    local protocol="$1" uuid="$2" host="$3" path="$4" isp="$5" add="${6:-speed.cloudflare.com}" out="$7"
    local ps_tls="$(echo "$isp" | sed -e 's/_/ /g')_tls"
    local ps_plain="$(echo "$isp" | sed -e 's/_/ /g')"
    local ps_url="$(echo "$isp" | sed -e 's/_/%20/g' -e 's/,/%2C/g')"
    if [ "$protocol" == "1" ]; then
        echo -e "vmess链接已经生成, $add 可替换为CF优选IP\n" > "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$path\",\"port\":\"443\",\"ps\":\"$ps_tls\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\n端口 443 可改为 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$path\",\"port\":\"80\",\"ps\":\"$ps_plain\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\n端口 80 可改为 8080 8880 2052 2082 2086 2095\n" >> "$out"
    else
        echo -e "vless链接已经生成, $add 可替换为CF优选IP\n" > "$out"
        echo "vless://$uuid@$add:443?encryption=none&security=tls&type=ws&host=$host&path=$path#${ps_url}_tls" >> "$out"
        echo -e "\n端口 443 可改为 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vless://$uuid@$add:80?encryption=none&security=none&type=ws&host=$host&path=$path#$ps_url" >> "$out"
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
    # 同步副本到当前工作目录, 让用户直接 cat v2ray.txt 也能看到
    if [ -f "$file" ]; then
        cp -f "$file" ./v2ray.txt 2>/dev/null
        cp -f "$file" /root/v2ray.txt 2>/dev/null
    fi
    echo -e "\n信息已经保存在 $file"
    echo -e "也可以运行: cat v2ray.txt (当前目录) 查看"
}

# 校验 mihomo 配置 (mihomo 无独立 check, 用 -t 测试)
validate_config() {
    local mh="$1" dir="$2" conf="$3"
    if [ -x "$mh" ]; then
        "$mh" -d "$dir" -t -f "$conf" >/dev/null 2>&1
        return $?
    fi
    return 0
}

# =============== 模式1: 临时隧道模式 ===============
quicktunnel() {
    echo -e "-------------------------------"
    echo "临时隧道模式: 生成 trycloudflare 快速链接"
    echo "注意: 重启或再次运行后失效"
    read -p "请选择协议(1.vmess,2.vless):" protocol
    [ -z "$protocol" ] && protocol=1
    if [ "$protocol" != 1 ] && [ "$protocol" != 2 ]; then echo "请输入正确的协议"; exit; fi

    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    [ -z "$ips" ] && ips=4
    if [ "$ips" != 4 ] && [ "$ips" != 6 ]; then echo "请输入正确的argo连接模式"; exit; fi

    kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $2}') >/dev/null 2>&1

    echo "[INFO] 正在通过 Cloudflare Radar 获取节点信息..."
    get_radar_info "$ips"
    isp=$(generate_node_name)
    echo "[OK] 节点名称: $isp"

    download_binaries "$DIR"

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')
    port=$((RANDOM % 50000 + 10000))

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$DIR/config.yaml"

    "$DIR/mihomo" -d "$DIR" -f "$DIR/config.yaml" >/dev/null 2>&1 &
    "$DIR/cloudflared-linux" tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >"$DIR/argo.log" 2>&1 &

    echo "等待 cloudflare argo 生成地址..."
    sleep 3
    n=0
    while true; do
        n=$((n+1))
        argo=$(grep trycloudflare.com "$DIR/argo.log" | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
        if [ $n == 15 ]; then
            n=0
            kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
            rm -rf "$DIR/argo.log"
            echo "获取超时, 重试中..."
            "$DIR/cloudflared-linux" tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >"$DIR/argo.log" 2>&1 &
        elif [ -z "$argo" ]; then
            sleep 1
        else
            rm -rf "$DIR/argo.log"
            break
        fi
    done
    clear
    echo "临时域名: $argo"
    gen_links "$protocol" "$uuid" "$argo" "$urlpath" "$isp" "speed.cloudflare.com" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
}

# =============== 模式3: Token + 域名固定隧道 ===============
token_tunnel() {
    echo -e "-------------------------------"
    echo "Token+域名模式: 输入 Cloudflare Tunnel Token + 绑定域名"
    read -p "请选择协议(1.vmess,2.vless):" protocol
    [ -z "$protocol" ] && protocol=1
    if [ "$protocol" != 1 ] && [ "$protocol" != 2 ]; then echo "请输入正确的协议"; exit; fi

    read -p "请输入 Cloudflare Tunnel Token: " token
    [ -z "$token" ] && { echo "Token 不能为空"; exit; }

    read -p "请输入绑定域名(如: node.example.com): " tdomain
    [ -z "$tdomain" ] && { echo "域名不能为空"; exit; }

    read -p "请输入 Cloudflare 面板中填写的本地服务端口 (默认 8001): " port
    [ -z "$port" ] && port=8001
    if ! echo "$port" | grep -qE '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "端口格式不正确"; exit
    fi

    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    [ -z "$ips" ] && ips=4
    if [ "$ips" != 4 ] && [ "$ips" != 6 ]; then echo "请输入正确的argo连接模式"; exit; fi

    kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $2}') >/dev/null 2>&1

    echo "[INFO] 正在通过 Cloudflare Radar 获取节点信息..."
    get_radar_info "$ips"
    isp=$(generate_node_name)
    echo "[OK] 节点名称: $isp"

    download_binaries "$DIR"

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$DIR/config.yaml"

    echo "$token" > "$DIR/tunnel.token"
    chmod 600 "$DIR/tunnel.token"

    if is_alpine; then
        cat > /etc/local.d/mihomo.start <<EOF
$DIR/mihomo -d $DIR -f $DIR/config.yaml &
EOF
        cat > /etc/local.d/cloudflared.start <<EOF
$DIR/cloudflared-linux tunnel --no-autoupdate --edge-ip-version $ips --protocol http2 run --token "\$(cat $DIR/tunnel.token)" &
EOF
        chmod +x /etc/local.d/mihomo.start /etc/local.d/cloudflared.start
        rc-update add local >/dev/null 2>&1
        pkill -9 -f 'mihomo -d' >/dev/null 2>&1
        pkill -9 -f 'cloudflared-linux tunnel' >/dev/null 2>&1
        /etc/local.d/mihomo.start >/dev/null 2>&1
        /etc/local.d/cloudflared.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/mihomo.service <<EOF
[Unit]
Description=mihomo
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=$DIR/mihomo -d $DIR -f $DIR/config.yaml
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        cat > /lib/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel (Token)
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/bin/bash -c '$DIR/cloudflared-linux tunnel --no-autoupdate --edge-ip-version $ips --protocol http2 run --token \$(cat $DIR/tunnel.token)'
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl stop cloudflared.service >/dev/null 2>&1
        systemctl stop mihomo.service >/dev/null 2>&1
        systemctl enable cloudflared.service >/dev/null 2>&1
        systemctl enable mihomo.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start mihomo.service
        systemctl start cloudflared.service
        sleep 5
    fi

    gen_links "$protocol" "$uuid" "$tdomain" "$urlpath" "$isp" "$tdomain" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
    echo -e "\n服务已安装, 开机自启已启用. 查看主服务: systemctl status mihomo cloudflared"
}

# =============== 模式2: 安装服务 (网页授权 named tunnel) ===============
installtunnel() {
    echo -e "-------------------------------"
    echo "安装服务模式: 网页授权绑定域名"
    read -p "请选择协议(1.vmess,2.vless):" protocol
    [ -z "$protocol" ] && protocol=1
    if [ "$protocol" != 1 ] && [ "$protocol" != 2 ]; then echo "请输入正确的协议"; exit; fi

    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    [ -z "$ips" ] && ips=4
    if [ "$ips" != 4 ] && [ "$ips" != 6 ]; then echo "请输入正确的argo连接模式"; exit; fi

    echo "[INFO] 正在获取节点信息..."
    get_radar_info "$ips"
    isp=$(generate_node_name)
    echo "[OK] 节点名称: $isp"

    # 清理旧的安装服务
    if is_alpine; then
        kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        rm -rf $DIR /etc/local.d/cloudflared.start /etc/local.d/mihomo.start $CMD
    else
        systemctl stop cloudflared.service >/dev/null 2>&1
        systemctl stop mihomo.service >/dev/null 2>&1
        systemctl disable cloudflared.service >/dev/null 2>&1
        systemctl disable mihomo.service >/dev/null 2>&1
        kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf $DIR /lib/systemd/system/cloudflared.service /lib/systemd/system/mihomo.service $CMD
        systemctl --system daemon-reload
    fi

    download_binaries "$DIR"

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')
    port=$((RANDOM % 50000 + 10000))

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "$DIR/config.yaml"

    clear
    echo "复制下面的链接, 用浏览器打开并授权需要绑定的域名"
    echo "在网页授权完毕后会继续进行下一步设置"
    "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel login

    clear
    "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel list >"$DIR/argo.log" 2>&1
    echo -e "ARGO TUNNEL 当前已经绑定的服务如下\n"
    sed 1,2d "$DIR/argo.log" | awk '{print $2}'
    echo -e "\n自定义一个完整二级域名, 例如 xxx.example.com"
    echo "必须是网页里面绑定授权的域名才生效, 不能乱输入"
    read -p "输入绑定域名的完整二级域名: " domain
    if [ -z "$domain" ]; then
        echo "没有设置域名"; exit
    elif [ $(echo "$domain" | grep "\." | wc -l) == 0 ]; then
        echo "域名格式不正确"; exit
    fi
    name=$(echo "$domain" | awk -F\. '{print $1}')
    if [ $(sed 1,2d "$DIR/argo.log" | awk '{print $2}' | grep -w $name | wc -l) == 0 ]; then
        echo "创建 TUNNEL $name"
        "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel create $name >"$DIR/argo.log" 2>&1
        echo "TUNNEL $name 创建成功"
    else
        echo "TUNNEL $name 已经存在"
        if [ ! -f "/root/.cloudflared/$(sed 1,2d "$DIR/argo.log" | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json" ]; then
            echo "/root/.cloudflared/... 文件不存在, 重建 TUNNEL $name"
            "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel cleanup $name >"$DIR/argo.log" 2>&1
            "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel delete $name >"$DIR/argo.log" 2>&1
            "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel create $name >"$DIR/argo.log" 2>&1
        else
            echo "清理 TUNNEL $name"
            "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel cleanup $name >"$DIR/argo.log" 2>&1
        fi
    fi
    echo "绑定 TUNNEL $name 到域名 $domain"
    "$DIR/cloudflared-linux" --edge-ip-version $ips --protocol http2 tunnel route dns --overwrite-dns $name $domain >"$DIR/argo.log" 2>&1
    echo "$domain 绑定成功"
    tunneluuid=$(cut -d= -f2 "$DIR/argo.log")

    gen_links "$protocol" "$uuid" "$domain" "$urlpath" "$isp" "$domain" "$DIR/v2ray.txt"
    rm -rf "$DIR/argo.log"

    cat > "$DIR/config.yaml" <<EOF
tunnel: $tunneluuid
credentials-file: /root/.cloudflared/$tunneluuid.json
ingress:
  - hostname: $domain
    service: http://localhost:$port
  - service: http_status:404
EOF

    if is_alpine; then
        cat > /etc/local.d/cloudflared.start <<EOF
$DIR/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config $DIR/config.yaml run $name &
EOF
        cat > /etc/local.d/mihomo.start <<EOF
$DIR/mihomo -d $DIR -f $DIR/config.yaml &
EOF
        chmod +x /etc/local.d/cloudflared.start /etc/local.d/mihomo.start
        rc-update add local >/dev/null 2>&1
        /etc/local.d/cloudflared.start >/dev/null 2>&1
        /etc/local.d/mihomo.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=$DIR/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config $DIR/config.yaml run $name
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        cat > /lib/systemd/system/mihomo.service <<EOF
[Unit]
Description=mihomo
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=$DIR/mihomo -d $DIR -f $DIR/config.yaml
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl enable cloudflared.service >/dev/null 2>&1
        systemctl enable mihomo.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start cloudflared.service
        systemctl start mihomo.service
    fi

    # 生成管理命令 cm
    cat > "$DIR/cm.sh" <<'INNER'
#!/bin/bash
clear
while true; do
    if is_alpine 2>/dev/null; then
        echo argo $(ps -ef | grep cloudflared | grep -v grep | wc -l)
    else
        echo argo $(systemctl status cloudflared.service 2>/dev/null | sed -n '3p')
    fi
    echo mihomo $(systemctl status mihomo.service 2>/dev/null | sed -n '3p')
    echo "1.管理TUNNEL"
    echo "2.启动服务"
    echo "3.停止服务"
    echo "4.重启服务"
    echo "5.卸载服务"
    echo "6.查看当前v2ray链接"
    echo "0.退出"
    read -p "请选择菜单(默认0): " menu
    [ -z "$menu" ] && menu=0
    if [ $menu == 1 ]; then
        clear
        while true; do
            echo "ARGO TUNNEL 当前已经绑定的服务如下"
            /opt/cm/cloudflared-linux tunnel list
            echo "1.删除TUNNEL"
            echo "0.退出"
            read -p "请选择菜单(默认0): " tunneladmin
            [ -z "$tunneladmin" ] && tunneladmin=0
            if [ $tunneladmin == 1 ]; then
                read -p "请输入要删除的TUNNEL NAME: " tunnelname
                echo "断开TUNNEL $tunnelname"
                /opt/cm/cloudflared-linux tunnel cleanup $tunnelname
                echo "删除TUNNEL $tunnelname"
                /opt/cm/cloudflared-linux tunnel delete $tunnelname
            else
                break
            fi
        done
    elif [ $menu == 2 ]; then
        systemctl start cloudflared.service 2>/dev/null
        systemctl start mihomo.service 2>/dev/null
        clear
    elif [ $menu == 3 ]; then
        systemctl stop cloudflared.service 2>/dev/null
        systemctl stop mihomo.service 2>/dev/null
        clear
    elif [ $menu == 4 ]; then
        systemctl restart cloudflared.service 2>/dev/null
        systemctl restart mihomo.service 2>/dev/null
        clear
    elif [ $menu == 5 ]; then
        systemctl stop cloudflared.service 2>/dev/null
        systemctl stop mihomo.service 2>/dev/null
        systemctl disable cloudflared.service 2>/dev/null
        systemctl disable mihomo.service 2>/dev/null
        kill -9 $(ps -ef | grep -E 'mihomo|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf /opt/cm /lib/systemd/system/cloudflared.service /lib/systemd/system/mihomo.service /usr/bin/cm
        systemctl --system daemon-reload
        echo "所有服务都卸载完成"
        exit
    elif [ $menu == 6 ]; then
        clear
        cat /opt/cm/v2ray.txt
    elif [ $menu == 0 ]; then
        echo "退出成功"
        exit
    fi
done
INNER
    chmod +x "$DIR/cm.sh"
    ln -sf "$DIR/cm.sh" "$CMD"

    clear
    gen_links "$protocol" "$uuid" "$domain" "$urlpath" "$isp" "$domain" "$DIR/v2ray.txt"
    show_links "$DIR/v2ray.txt"
    echo -e "\n服务安装完成, 管理服务请运行命令: cm"
}

# =============== 卸载 / 清空缓存 ===============
uninstall_all() {
    if is_alpine; then
        kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        rm -rf $DIR /etc/local.d/cloudflared.start /etc/local.d/mihomo.start $CMD
    else
        systemctl stop cloudflared.service >/dev/null 2>&1
        systemctl stop mihomo.service >/dev/null 2>&1
        systemctl disable cloudflared.service >/dev/null 2>&1
        systemctl disable mihomo.service >/dev/null 2>&1
        kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf $DIR /lib/systemd/system/cloudflared.service /lib/systemd/system/mihomo.service $CMD
        systemctl --system daemon-reload
    fi
    clear
    rm -f /root/v2ray.txt ./v2ray.txt 2>/dev/null
    echo "所有服务都卸载完成"
    echo "彻底删除授权记录: 请访问 https://dash.cloudflare.com/profile/api-tokens"
}

clear_cache() {
    if is_alpine; then
        kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $1}') >/dev/null 2>&1
    else
        kill -9 $(ps -ef | grep -E "mihomo|cloudflared" | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    fi
    cd /
    rm -rf $DIR/*.log $DIR/v2ray.txt $DIR/cache.db 2>/dev/null
    echo "缓存已清理"
}

# =============== 主程序 ===============
detect_system_index
install_deps

clear
echo "===================================="
echo "  CM - Cloudflare mihomo 一键脚本"
echo "  Cloudflare mihomo 综合部署 + Radar 节点名"
echo "===================================="
echo "1. 临时隧道 (trycloudflare, 重启失效)"
echo "2. 安装服务 (网页授权绑定域名, 开机自启)"
echo "3. Token+域名 (固定隧道, 输入Token+域名)"
echo "4. 卸载服务"
echo "5. 清空缓存"
echo "0. 退出脚本"
echo ""
read -p "请选择模式(默认1): " mode
[ -z "$mode" ] && mode=1

case "$mode" in
    1) quicktunnel ;;
    2) installtunnel ;;
    3) token_tunnel ;;
    4) uninstall_all ;;
    5) clear_cache ;;
    *) echo "退出成功"; exit ;;
esac