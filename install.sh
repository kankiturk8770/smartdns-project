#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}لطفاً با دسترسی root اجرا کنید: sudo bash install.sh${NC}"
  exit 1
fi

clear
echo "=========================================="
echo "    اسکریپت نصب و پیکربندی Smart DNS    "
echo "=========================================="
echo "1) نصب سرور خارج (Exit Server + Web Panel)"
echo "2) نصب سرور ایران (Relay Server + CoreDNS)"
read -p "لطفاً گزینه‌ای را انتخاب کنید [1 یا 2]: " mode

mkdir -p /etc/smartdns/core /etc/smartdns/templates /etc/coredns /etc/haproxy

# 1. نصب پیش‌نیازهای عمومی
apt-get update -y
apt-get install -y haproxy python3 python3-pip sqlite3 curl wget
pip3 install fastapi uvicorn sqlite3 > /dev/null 2>&1 || true

# 2. نصب CoreDNS مستقیم
if [ ! -f /usr/local/bin/coredns ]; then
    echo -e "${GREEN}[+] در حال دانلود CoreDNS...${NC}"
    COREDNS_VER="1.11.1"
    wget -q https://github.com/coredns/coredns/releases/download/v${COREDNS_VER}/coredns_${COREDNS_VER}_linux_amd64.tgz
    tar -zxf coredns_${COREDNS_VER}_linux_amd64.tgz -C /usr/local/bin/
    rm -f coredns_${COREDNS_VER}_linux_amd64.tgz
    chmod +x /usr/local/bin/coredns
fi

# ساخت سرویس CoreDNS Systemd
cat << 'EOS' > /etc/systemd/system/coredns.service
[Unit]
Description=CoreDNS DNS Server
After=network.target

[Service]
PermissionsStartOnly=true
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOS

systemctl daemon-reload

if [ "$mode" == "1" ]; then
    echo -e "${GREEN}[+] در حال پیکربندی سرور خارج و پنل مدیریت...${NC}"

    # کانفیگ HAProxy سرور خارج
    cat << 'EOS' > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 50000
    user haproxy
    group haproxy

defaults
    log global
    mode tcp
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend dns_sni_passthrough
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    default_backend default_out

backend default_out
    mode tcp
    server internet 0.0.0.0:443
EOS

    # ساخت فایل وب پنل پایتون (Backend)
    cat << 'EOS' > /etc/smartdns/core/app.py
import sqlite3
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import uvicorn

app = FastAPI()

def init_db():
    conn = sqlite3.connect('/etc/smartdns/database.db')
    cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS domains (id INTEGER PRIMARY KEY AUTOINCREMENT, domain TEXT UNIQUE)''')
    conn.commit()
    conn.close()

init_db()

@app.get("/panel", response_class=HTMLResponse)
def read_root():
    with open('/etc/smartdns/templates/index.html', 'r', encoding='utf-8') as f:
        return f.read()

@app.get("/api/domains")
def get_domains():
    conn = sqlite3.connect('/etc/smartdns/database.db')
    cursor = conn.cursor()
    cursor.execute("SELECT domain FROM domains")
    domains = [row[0] for row in cursor.fetchall()]
    conn.close()
    return {"domains": domains}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9443)
EOS

    # ساخت فایل ظاهر پنل (HTML/CSS Frontend)
    cat << 'EOS' > /etc/smartdns/templates/index.html
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>مدیریت Smart DNS</title>
    <style>
        body { font-family: Tahoma, sans-serif; background: #0f172a; color: #f8fafc; padding: 20px; text-align: center; }
        .card { background: #1e293b; max-width: 600px; margin: 30px auto; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.3); }
        h1 { color: #38bdf8; margin-bottom: 20px; }
        ul { list-style: none; padding: 0; text-align: right; }
        li { background: #334155; padding: 10px 15px; margin: 8px 0; border-radius: 6px; display: flex; justify-content: space-between; }
        .status { color: #4ade80; font-weight: bold; }
    </style>
</head>
<body>
    <div class="card">
        <h1>داشبورد مدیریت Smart DNS</h1>
        <p>وضعیت سرویس: <span class="status">فعال (Running)</span></p>
        <hr style="border-color: #334155;">
        <h3>دامنه‌های فعال برای Bypass:</h3>
        <ul id="domain-list">
            <li>در حال بارگذاری دامنه‌ها...</li>
        </ul>
    </div>
    <script>
        fetch('/api/domains')
            .then(res => res.json())
            .then(data => {
                const list = document.getElementById('domain-list');
                list.innerHTML = '';
                if(data.domains.length === 0) {
                    list.innerHTML = '<li>هیچ دامنه‌ای ثبت نشده است (پیش‌فرض تمام دامنه‌های گیمینگ)</li>';
                } else {
                    data.domains.forEach(d => {
                        list.innerHTML += `<li>${d}</li>`;
                    });
                }
            });
    </script>
</body>
</html>
EOS

    # ساخت سرویس پنل
    cat << 'EOS' > /etc/systemd/system/smartdns-panel.service
[Unit]
Description=SmartDNS Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 /etc/smartdns/core/app.py
WorkingDirectory=/etc/smartdns
Restart=always

[Install]
WantedBy=multi-user.target
EOS

    systemctl daemon-reload
    systemctl enable --now smartdns-panel
    systemctl restart haproxy

    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN} سرور خارج با موفقیت و پنل کامل نصب شد! ${NC}"
    echo -e "${GREEN} آدرس پنل وب: http://YOUR_EXIT_IP:9443/panel ${NC}"
    echo -e "${GREEN}==========================================${NC}"

elif [ "$mode" == "2" ]; then
    echo -e "${GREEN}[+] در حال پیکربندی سرور ایران...${NC}"
    read -p "لطفاً IP سرور خارج را وارد کنید: " exit_ip

    if [ -z "$exit_ip" ]; then
        echo -e "${RED}خطا: IP سرور خارج نمی‌تواند خالی باشد!${NC}"
        exit 1
    fi

    # تنظیم Corefile سرور ایران
    cat << EOS > /etc/coredns/Corefile
. {
    hosts {
        $exit_ip pubgmobile.com
        $exit_ip latency-opt.pubgmobile.com
        fallthrough
    }
    forward . 8.8.8.8 1.1.1.1
    log
    errors
}
EOS

    # تنظیم HAProxy سرور ایران برای ریلای
    cat << EOS > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 50000
    user haproxy
    group haproxy

defaults
    log global
    mode tcp
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend sni_in
    bind *:443
    mode tcp
    default_backend exit_server

backend exit_server
    mode tcp
    server exit_node $exit_ip:443
EOS

    systemctl enable --now coredns
    systemctl restart coredns
    systemctl restart haproxy

    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN} سرور ایران با موفقیت نصب و به خارج متصل شد! ${NC}"
    echo -e "${GREEN} DNS سرور ایران شما: IP این سرور ${NC}"
    echo -e "${GREEN}==========================================${NC}"
fi
