#!/bin/bash
# ---------------------------------------------------------------
# cx.sh - Cloudflare Xray 综合部署脚本
# 
# 模式:
#   1. 临时隧道    - trycloudflare.com (trycloudflare.com), 重启失效
#   2. 安装服务    - 网页授权绑定域名 (named tunnel + systemd/Alpine 自启)
#   3. Token+域名  - 输入 Cloudflare Tunnel Token + 域名 (固定隧道)
#   4. 卸载服务
#   5. 清空缓存
#   0. 退出
#
# 节点名称: 通过 Cloudflare Radar API 生成 {国家}-asn{ASN}-{城市}
#   IPv4: https://ipv4-check-perf.radar.cloudflare.com/
#   IPv6: https://ipv6-check-perf.radar.cloudflare.com/
# ---------------------------------------------------------------

# 云flare Radar IP 检测 API
IPv4_API="https://ipv4-check-perf.radar.cloudflare.com/"
IPv6_API="https://ipv6-check-perf.radar.cloudflare.com/"

# =============== 系统检测与依赖安装 (多包管理器) ===============
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")

# 判断系统索引 n
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

# 检查并安装依赖
install_deps() {
    detect_system_index
    [ -z "$(type -P unzip)" ] && { ${linux_update[$n]} >/dev/null 2>&1; ${linux_install[$n]} unzip >/dev/null 2>&1; }
    [ -z "$(type -P curl)" ] && { ${linux_update[$n]} >/dev/null 2>&1; ${linux_install[$n]} curl >/dev/null 2>&1; }
    # Alpine 不需要 systemctl，其他系统安装
    if [ "$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d \" -f2 | awk '{print $1}')" != "Alpine" ]; then
        [ -z "$(type -P systemctl)" ] && { ${linux_update[$n]} >/dev/null 2>&1; ${linux_install[$n]} systemctl >/dev/null 2>&1; }
    fi
}

is_alpine() {
    [ "$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
}

# =============== Cloudflare Radar 节点名称生成 ===============
# 根据 IP 版本($ips: 4/6) 用对应 Radar API 获取 国家/ASN/城市
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

# 节点名称: {国家}-asn{ASN}-{城市}
generate_node_name() {
    local country=$(radar_field country)
    local asn=$(radar_field asn)
    local city=$(radar_field city)
    echo "${country}-asn${asn}-${city}"
}

# =============== 按架构下载 Xray + cloudflared ===============
# $1 = 目标目录 (可选，默认当前目录)
download_binaries() {
    local dest="${1:-.}"
    mkdir -p "$dest"
    cd "$dest"
    rm -rf xray cloudflared-linux xray.zip
    echo "[INFO] 正在下载 Xray 和 cloudflared (架构: $(uname -m))..."
    case "$(uname -m)" in
        x86_64 | x64 | amd64)
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        i386 | i686)
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386"
            ;;
        armv8 | arm64 | aarch64)
            echo "[INFO] 检测到 arm64"
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        armv7l | armv71)
            XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip"
            CLOUD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
            ;;
        *)
            echo "[ERROR] 当前架构 $(uname -m) 没有适配"
            exit 1
            ;;
    esac
    # 下载 Xray (失败则重试, 仍失败则报错退出)
    if ! curl -fsSL --retry 2 --retry-delay 2 -o xray.zip "$XRAY_URL"; then
        echo "[ERROR] Xray 下载失败: $XRAY_URL"
        echo "请检查网络后重新运行"
        exit 1
    fi
    # 下载 cloudflared (失败则重试, 仍失败则报错退出)
    if ! curl -fsSL --retry 2 --retry-delay 2 -o cloudflared-linux "$CLOUD_URL"; then
        echo "[ERROR] cloudflared 下载失败: $CLOUD_URL"
        echo "请检查网络后重新运行"
        exit 1
    fi
    # 下载成功后解压
    if ! unzip -o xray.zip -d xray >/dev/null 2>&1; then
        echo "[ERROR] Xray 解压失败 (xray.zip 可能损坏)"
        exit 1
    fi
    chmod +x cloudflared-linux xray/xray
    rm -rf xray.zip
    echo "[OK] Xray 与 cloudflared 下载完成"
}

# =============== 生成 xray config.json ===============
# $1 = protocol (1 vmess / 2 vless)  $2 = port  $3 = uuid  $4 = path  $5 = 配置文件路径
gen_config() {
    local protocol="$1" port="$2" uuid="$3" path="$4" conf="$5"
    if [ "$protocol" == "1" ]; then
        cat > "$conf" <<EOF
{
    "inbounds": [
        {
            "port": $port,
            "listen": "localhost",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$path"
                }
            }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "settings": {} }
    ]
}
EOF
    else
        cat > "$conf" <<EOF
{
    "inbounds": [
        {
            "port": $port,
            "listen": "localhost",
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    { "id": "$uuid" }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$path"
                }
            }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "settings": {} }
    ]
}
EOF
    fi
}

# =============== 生成 vmess/vless 链接 ===============
# $1 = protocol  $2 = uuid  $3 = host(argo域名)  $4 = path  $5 = node_name  $6 = xray地址(IP/域名)  $7 = 输出文件
gen_links() {
    local protocol="$1" uuid="$2" host="$3" path="$4" isp="$5" add="${6:-speed.cloudflare.com}" out="$7"
    local ps_tls="$(echo "$isp" | sed -e 's/_/ /g')_tls"
    local ps_plain="$(echo "$isp" | sed -e 's/_/ /g')"
    if [ "$protocol" == "1" ]; then
        echo -e "vmess链接已经生成, $add 可替换为CF优选IP\n" > "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$path\",\"port\":\"443\",\"ps\":\"$ps_tls\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\n端口 443 可改为 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vmess://$(echo "{\"add\":\"$add\",\"aid\":\"0\",\"host\":\"$host\",\"id\":\"$uuid\",\"net\":\"ws\",\"path\":\"$path\",\"port\":\"80\",\"ps\":\"$ps_plain\",\"tls\":\"\",\"type\":\"none\",\"v\":\"2\"}" | base64 -w 0)" >> "$out"
        echo -e "\n端口 80 可改为 8080 8880 2052 2082 2086 2095\n" >> "$out"
    else
        local ps_url="$(echo "$isp" | sed -e 's/_/%20/g' -e 's/,/%2C/g')"
        echo -e "vless链接已经生成, $add 可替换为CF优选IP\n" > "$out"
        echo "vless://$uuid@$add:443?encryption=none&security=tls&type=ws&host=$host&path=$path#${ps_url}_tls" >> "$out"
        echo -e "\n端口 443 可改为 2053 2083 2087 2096 8443\n" >> "$out"
        echo "vless://$uuid@$add:80?encryption=none&security=none&type=ws&host=$host&path=$path#$ps_url" >> "$out"
        echo -e "\n端口 80 可改为 8080 8880 2052 2082 2086 2095\n" >> "$out"
    fi
    # 如果用了 CF 域名，提示 SSL 设置
    if [ "$add" != "speed.cloudflare.com" ] && echo "$add" | grep -q '\.'; then
        echo "注意:如果 80 8080 8880 2052 2082 2086 2095 端口无法正常使用" >> "$out"
        echo "请前往 https://dash.cloudflare.com/" >> "$out"
        echo "检查管理面板 SSL/TLS - 边缘证书 - 始终使用HTTPS 是否处于关闭状态" >> "$out"
    fi
}

# 打印节点链接文件
show_links() {
    local file="$1"
    cat "$file"
    if [ -f "$file" ]; then
        cp -f "$file" ./v2ray.txt 2>/dev/null
        cp -f "$file" /root/v2ray.txt 2>/dev/null
    fi
    echo -e "\n信息已经保存在 $file"
    echo -e "也可以运行: cat v2ray.txt (当前目录) 查看"
}

# =============== 模式1: 临时隧道模式 ===============
quicktunnel() {
    echo -e "-------------------------------"
    echo "临时隧道模式: 生成 trycloudflare 快速链接"
    echo "注意: 重启或再次运行后失效"
    read -p "请选择xray协议(1.vmess,2.vless):" protocol
    [ -z "$protocol" ] && protocol=1
    if [ "$protocol" != 1 ] && [ "$protocol" != 2 ]; then echo "请输入正确的xray协议"; exit; fi

    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    [ -z "$ips" ] && ips=4
    if [ "$ips" != 4 ] && [ "$ips" != 6 ]; then echo "请输入正确的argo连接模式"; exit; fi

    # 清理旧进程
    kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    rm -rf xray cloudflared-linux v2ray.txt

    # 用 Cloudflare Radar 采集节点名 (替代 speed.cloudflare.com/meta)
    echo "[INFO] 正在通过 Cloudflare Radar 获取节点信息..."
    get_radar_info "$ips"
    isp=$(generate_node_name)
    echo "[OK] 节点名称: $isp"

    # 下载二进制
    download_binaries "/opt/cx"

    # 生成 UUID / path / port
    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')
    port=$((RANDOM % 50000 + 10000))

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "/opt/cx/xray/config.json"

    # 启动 Xray
    /opt/cx/xray/xray run -c /opt/cx/xray/config.json >/dev/null 2>&1 &

    # 启动临时隧道
    /opt/cx/cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >/opt/cx/argo.log 2>&1 &

    # 等待临时域名生成
    echo "等待 cloudflare argo 生成地址..."
    sleep 3
    n=0
    while true; do
        n=$((n+1))
        argo=$(grep trycloudflare.com /opt/cx/argo.log | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
        if [ $n == 15 ]; then
            n=0
            kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
            rm -rf /opt/cx/argo.log
            echo "获取超时, 重试中..."
            /opt/cx/cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >/opt/cx/argo.log 2>&1 &
        elif [ -z "$argo" ]; then
            sleep 1
        else
            rm -rf /opt/cx/argo.log
            break
        fi
    done
    clear
    echo "临时域名: $argo"
    gen_links "$protocol" "$uuid" "$argo" "$urlpath" "$isp" "speed.cloudflare.com" "/opt/cx/v2ray.txt"
    show_links "/opt/cx/v2ray.txt"
}

# =============== 模式3: Token + 域名固定隧道 ===============
token_tunnel() {
    echo -e "-------------------------------"
    echo "Token+域名模式: 输入 Cloudflare Tunnel Token + 绑定域名"
    read -p "请选择xray协议(1.vmess,2.vless):" protocol
    [ -z "$protocol" ] && protocol=1
    if [ "$protocol" != 1 ] && [ "$protocol" != 2 ]; then echo "请输入正确的xray协议"; exit; fi

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

    # 清理旧进程
    kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    rm -rf /opt/cx/v2ray.txt

    echo "[INFO] 正在通过 Cloudflare Radar 获取节点信息..."
    get_radar_info "$ips"
    isp=$(generate_node_name)
    echo "[OK] 节点名称: $isp"

    download_binaries "/opt/cx"

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')
    # Token 模式: 使用用户填写的端口 (须与 Cloudflare 面板配置一致)
    # 面板端口示例: http://localhost:8001 → 填写 8001

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "/opt/cx/xray/config.json"

    # 保存 Token (600 权限) - Token 由 systemd 服务引用
    echo "$token" > /opt/cx/tunnel.token
    chmod 600 /opt/cx/tunnel.token

    # 创建服务 (systemd 持久化, 开机自启, 进程退出不影响)
    if is_alpine; then
        # Alpine 用 local.d
        cat > /etc/local.d/xray.start <<EOF
/opt/cx/xray/xray run -c /opt/cx/xray/config.json &
EOF
        cat > /etc/local.d/cloudflared.start <<EOF
/opt/cx/cloudflared-linux tunnel --no-autoupdate --edge-ip-version $ips --protocol http2 run --token "\$(cat /opt/cx/tunnel.token)" &
EOF
        chmod +x /etc/local.d/xray.start /etc/local.d/cloudflared.start
        rc-update add local >/dev/null 2>&1
        pkill -9 -f 'xray/xray run' >/dev/null 2>&1
        pkill -9 -f 'cloudflared-linux tunnel' >/dev/null 2>&1
        /etc/local.d/xray.start >/dev/null 2>&1
        /etc/local.d/cloudflared.start >/dev/null 2>&1
    else
        # systemd
        cat > /lib/systemd/system/xray.service <<EOF
[Unit]
Description=Xray
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/cx/xray/xray run -c /opt/cx/xray/config.json
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
ExecStart=/bin/bash -c '/opt/cx/cloudflared-linux tunnel --no-autoupdate --edge-ip-version $ips --protocol http2 run --token \$(cat /opt/cx/tunnel.token)'
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl stop cloudflared.service >/dev/null 2>&1
        systemctl stop xray.service >/dev/null 2>&1
        systemctl enable cloudflared.service >/dev/null 2>&1
        systemctl enable xray.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start xray.service
        systemctl start cloudflared.service
        sleep 5
    fi

    gen_links "$protocol" "$uuid" "$tdomain" "$urlpath" "$isp" "$tdomain" "/opt/cx/v2ray.txt"
    show_links "/opt/cx/v2ray.txt"
    echo -e "\n服务已安装, 开机自启已启用. 查看主服务: systemctl status xray cloudflared"
}

# =============== 模式2: 安装服务 (网页授权 named tunnel) ===============
installtunnel() {
    echo -e "-------------------------------"
    echo "安装服务模式: 网页授权绑定域名"
    read -p "请选择xray协议(1.vmess,2.vless):" protocol
    [ -z "$protocol" ] && protocol=1
    if [ "$protocol" != 1 ] && [ "$protocol" != 2 ]; then echo "请输入正确的xray协议"; exit; fi

    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    [ -z "$ips" ] && ips=4
    if [ "$ips" != 4 ] && [ "$ips" != 6 ]; then echo "请输入正确的argo连接模式"; exit; fi

    echo "[INFO] 正在获取节点信息..."
    get_radar_info "$ips"
    isp=$(generate_node_name)
    echo "[OK] 节点名称: $isp"

    # 清理旧的安装服务
    if is_alpine; then
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        rm -rf /opt/cx /etc/local.d/cloudflared.start /etc/local.d/xray.start /usr/bin/cx
    else
        systemctl stop cloudflared.service >/dev/null 2>&1
        systemctl stop xray.service >/dev/null 2>&1
        systemctl disable cloudflared.service >/dev/null 2>&1
        systemctl disable xray.service >/dev/null 2>&1
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf /opt/cx /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/cx
        systemctl --system daemon-reload
    fi

    download_binaries "/opt/cx"

    uuid=$(cat /proc/sys/kernel/random/uuid)
    urlpath=$(echo $uuid | awk -F- '{print $1}')
    port=$((RANDOM % 50000 + 10000))

    gen_config "$protocol" "$port" "$uuid" "$urlpath" "/opt/cx/config.json"

    clear
    echo "复制下面的链接, 用浏览器打开并授权需要绑定的域名"
    echo "在网页授权完毕后会继续进行下一步设置"
    /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel login

    clear
    /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel list >/opt/cx/argo.log 2>&1
    echo -e "ARGO TUNNEL 当前已经绑定的服务如下\n"
    sed 1,2d /opt/cx/argo.log | awk '{print $2}'
    echo -e "\n自定义一个完整二级域名, 例如 xxx.example.com"
    echo "必须是网页里面绑定授权的域名才生效, 不能乱输入"
    read -p "输入绑定域名的完整二级域名: " domain
    if [ -z "$domain" ]; then
        echo "没有设置域名"; exit
    elif [ $(echo "$domain" | grep "\." | wc -l) == 0 ]; then
        echo "域名格式不正确"; exit
    fi
    name=$(echo "$domain" | awk -F\. '{print $1}')
    if [ $(sed 1,2d /opt/cx/argo.log | awk '{print $2}' | grep -w $name | wc -l) == 0 ]; then
        echo "创建 TUNNEL $name"
        /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel create $name >/opt/cx/argo.log 2>&1
        echo "TUNNEL $name 创建成功"
    else
        echo "TUNNEL $name 已经存在"
        if [ ! -f "/root/.cloudflared/$(sed 1,2d /opt/cx/argo.log | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json" ]; then
            echo "/root/.cloudflared/... 文件不存在, 重建 TUNNEL $name"
            /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel cleanup $name >/opt/cx/argo.log 2>&1
            /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel delete $name >/opt/cx/argo.log 2>&1
            /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel create $name >/opt/cx/argo.log 2>&1
        else
            echo "清理 TUNNEL $name"
            /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel cleanup $name >/opt/cx/argo.log 2>&1
        fi
    fi
    echo "绑定 TUNNEL $name 到域名 $domain"
    /opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel route dns --overwrite-dns $name $domain >/opt/cx/argo.log 2>&1
    echo "$domain 绑定成功"
    tunneluuid=$(cut -d= -f2 /opt/cx/argo.log)

    gen_links "$protocol" "$uuid" "$domain" "$urlpath" "$isp" "$domain" "/opt/cx/v2ray.txt"
    rm -rf /opt/cx/argo.log

    # 生成 cloudflared config
    cat > /opt/cx/config.yaml <<EOF
tunnel: $tunneluuid
credentials-file: /root/.cloudflared/$tunneluuid.json
ingress:
  - hostname: $domain
    service: http://localhost:$port
  - service: http_status:404
EOF

    # 生成服务 / 启动
    if is_alpine; then
        cat > /etc/local.d/cloudflared.start <<EOF
/opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/cx/config.yaml run $name &
EOF
        cat > /etc/local.d/xray.start <<EOF
/opt/cx/xray/xray run -config /opt/cx/config.json &
EOF
        chmod +x /etc/local.d/cloudflared.start /etc/local.d/xray.start
        rc-update add local >/dev/null 2>&1
        /etc/local.d/cloudflared.start >/dev/null 2>&1
        /etc/local.d/xray.start >/dev/null 2>&1
    else
        cat > /lib/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/cx/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/cx/config.yaml run $name
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        cat > /lib/systemd/system/xray.service <<EOF
[Unit]
Description=Xray
After=network.target
[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/cx/xray/xray run -config /opt/cx/config.json
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl enable cloudflared.service >/dev/null 2>&1
        systemctl enable xray.service >/dev/null 2>&1
        systemctl --system daemon-reload
        systemctl start cloudflared.service
        systemctl start xray.service
    fi

    # 生成管理命令 cx
    cat > /opt/cx/cx.sh <<'INNER'
#!/bin/bash
clear
while true; do
    echo argo $(systemctl status cloudflared.service 2>/dev/null | sed -n '3p')
    echo xray $(systemctl status xray.service 2>/dev/null | sed -n '3p')
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
            /opt/cx/cloudflared-linux tunnel list
            echo "1.删除TUNNEL"
            echo "0.退出"
            read -p "请选择菜单(默认0): " tunneladmin
            [ -z "$tunneladmin" ] && tunneladmin=0
            if [ $tunneladmin == 1 ]; then
                read -p "请输入要删除的TUNNEL NAME: " tunnelname
                echo "断开TUNNEL $tunnelname"
                /opt/cx/cloudflared-linux tunnel cleanup $tunnelname
                echo "删除TUNNEL $tunnelname"
                /opt/cx/cloudflared-linux tunnel delete $tunnelname
            else
                break
            fi
        done
    elif [ $menu == 2 ]; then
        systemctl start cloudflared.service
        systemctl start xray.service
        clear
    elif [ $menu == 3 ]; then
        systemctl stop cloudflared.service
        systemctl stop xray.service
        clear
    elif [ $menu == 4 ]; then
        systemctl restart cloudflared.service
        systemctl restart xray.service
        clear
    elif [ $menu == 5 ]; then
        systemctl stop cloudflared.service
        systemctl stop xray.service
        systemctl disable cloudflared.service
        systemctl disable xray.service
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf /opt/cx /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/cx
        systemctl --system daemon-reload
        echo "所有服务都卸载完成"
        echo "彻底删除授权记录: 请访问 https://dash.cloudflare.com/profile/api-tokens"
        exit
    elif [ $menu == 6 ]; then
        clear
        cat /opt/cx/v2ray.txt
    elif [ $menu == 0 ]; then
        echo "退出成功"
        exit
    fi
done
INNER
    chmod +x /opt/cx/cx.sh
    ln -sf /opt/cx/cx.sh /usr/bin/cx

    clear
    gen_links "$protocol" "$uuid" "$domain" "$urlpath" "$isp" "$domain" "/opt/cx/v2ray.txt"
    show_links "/opt/cx/v2ray.txt"
    echo -e "\n服务安装完成, 管理服务请运行命令: cx"
}

# =============== 卸载 / 清空缓存 ===============
uninstall_all() {
    if is_alpine; then
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        rm -rf /opt/cx /etc/local.d/cloudflared.start /etc/local.d/xray.start /usr/bin/cx
    else
        systemctl stop cloudflared.service >/dev/null 2>&1
        systemctl stop xray.service >/dev/null 2>&1
        systemctl disable cloudflared.service >/dev/null 2>&1
        systemctl disable xray.service >/dev/null 2>&1
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf /opt/cx /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/cx
        systemctl --system daemon-reload
    fi
    clear
    rm -f /root/v2ray.txt ./v2ray.txt 2>/dev/null
    echo "所有服务都卸载完成"
    echo "彻底删除授权记录: 请访问 https://dash.cloudflare.com/profile/api-tokens"
}

clear_cache() {
    if is_alpine; then
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $1}') >/dev/null 2>&1
    else
        kill -9 $(ps -ef | grep -E 'xray|cloudflared' | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    fi
    cd /
    rm -rf /opt/cx/xray /opt/cx/cloudflared-linux /opt/cx/v2ray.txt /opt/cx/argo.log /root/quicktunnel-temp 2>/dev/null
    echo "缓存已清理"
}

# =============== 主程序 ===============
# 先检测系统
detect_system_index
install_deps

clear
echo "===================================="
echo "  CX - Cloudflare Xray 一键脚本"
echo "  Cloudflare Xray 综合部署 + Radar 节点名"
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