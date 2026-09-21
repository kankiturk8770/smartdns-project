#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}لطفاً با دسترسی root اجرا کنید: sudo bash install.sh${NC}"
  exit 1
fi

echo "=========================================="
echo "    اسکریپت نصب هوشمند Smart DNS    "
echo "=========================================="
echo "1) نصب و تنظیم سرور خارج (Exit Server)"
echo "2) نصب و تنظیم سرور ایران (Relay Server)"
read -p "انتخاب کنید [1-2]: " mode

mkdir -p /etc/smartdns/core /etc/coredns /etc/haproxy

apt-get update -y
apt-get install -y haproxy python3 python3-pip sqlite3 curl wget
pip3 install fastapi uvicorn > /dev/null 2>&1

# نصب مستقیم CoreDNS با دانلود نسخه آماده
if [ ! -f /usr/local/bin/coredns ]; then
    echo -e "${GREEN}در حال دانلود و نصب CoreDNS...${NC}"
    COREDNS_VER="1.11.1"
    wget -q https://github.com/coredns/coredns/releases/download/v${COREDNS_VER}/coredns_${COREDNS_VER}_linux_amd64.tgz
    tar -zxf coredns_${COREDNS_VER}_linux_amd64.tgz -C /usr/local/bin/
    rm -f coredns_${COREDNS_VER}_linux_amd64.tgz
    chmod +x /usr/local/bin/coredns
fi

# ساخت سرویس systemd برای CoreDNS
cat << 'EOF_SERVICE' > /etc/systemd/system/coredns.service
[Unit]
Description=CoreDNS DNS server
After=network.target

[Service]
PermissionsStartOnly=true
LimitNOFILE=1048576
LimitNPROC=512
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload

if [ "$mode" == "1" ]; then
    cp config/exit/haproxy.cfg /etc/haproxy/haproxy.cfg
    cp panel/app.py /etc/smartdns/core/app.py
    cp panel/smartdns-panel.service /etc/systemd/system/smartdns-panel.service
    systemctl daemon-reload
    systemctl enable --now smartdns-panel
    systemctl restart haproxy
    echo -e "${GREEN}سرور خارج با موفقیت نصب شد!${NC}"
elif [ "$mode" == "2" ]; then
    read -p "آدرس IP سرور خارج را وارد کنید: " exit_ip
    sed -i "s/EXIT_IP_HERE/$exit_ip/g" config/relay/Corefile
    sed -i "s/EXIT_IP_HERE/$exit_ip/g" config/relay/haproxy.cfg
    cp config/relay/Corefile /etc/coredns/Corefile
    cp config/relay/haproxy.cfg /etc/haproxy/haproxy.cfg
    systemctl enable --now coredns
    systemctl restart coredns
    systemctl restart haproxy
    echo -e "${GREEN}سرور ایران با موفقیت نصب شد!${NC}"
fi
