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
apt-get install -y haproxy coredns python3 python3-pip sqlite3
pip3 install fastapi uvicorn > /dev/null 2>&1

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
    systemctl restart coredns
    systemctl restart haproxy
    echo -e "${GREEN}سرور ایران با موفقیت نصب شد!${NC}"
fi
