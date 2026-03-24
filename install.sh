#!/bin/bash
# ============================================
# Sentinel — Server Security Monitor
# Avtomatik O'rnatish Scripti
# ============================================
#
# Ishlatish:
#   sudo bash install.sh
#
# Qo'llab-quvvatlanadi:
#   - Debian 12/13, Ubuntu 22.04+
#   - CentOS Stream 9, AlmaLinux 9, Rocky Linux 9
#   - Nginx (to'g'ridan-to'g'ri yoki HAProxy/LB ortida)
#
# ============================================

set -e

# --- Ranglar ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Yo'llar ---
SENTINEL_DIR="/etc/sentinel"
SENTINEL_LOG_DIR="/var/log/sentinel"
SENTINEL_BIN="/usr/local/bin"
NGINX_CONF_DIR="/etc/nginx"
F2B_FILTER_DIR="/etc/fail2ban/filter.d"
F2B_JAIL_DIR="/etc/fail2ban/jail.d"
F2B_ACTION_DIR="/etc/fail2ban/action.d"

# --- Script joylashuvi (install.sh turgan papka) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "============================================"
echo "  SENTINEL — Server Security Monitor"
echo "  O'rnatish boshlandi"
echo "============================================"
echo ""

# Mavjud o'rnatmani tekshirish
if [ -f "${SENTINEL_DIR}/sentinel.conf" ]; then
    echo -e "${YELLOW}Sentinel allaqachon o'rnatilgan!${NC}"
    echo "  Qayta o'rnatish eski konfiguratsiyani yangilaydi."
    echo "  Mavjud ban'lar saqlanadi."
    echo ""
    read -p "  Davom etasizmi? [y/N]: " REINSTALL
    if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
        echo "Bekor qilindi."
        exit 0
    fi
    echo ""
fi

# ============================================
# Root tekshirish
# ============================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Xato: root huquqi kerak. sudo bilan ishga tushiring.${NC}"
    exit 1
fi

# ============================================
# [1/8] OS va Firewall aniqlash (AVTOMATIK)
# ============================================
echo -e "${YELLOW}[1/8] OS va firewall aniqlanmoqda${NC}"

# OS aniqlash
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
    OS_NAME="$PRETTY_NAME"
else
    echo -e "${RED}Xato: OS aniqlab bo'lmadi (/etc/os-release topilmadi)${NC}"
    exit 1
fi

# Paket manager aniqlash
if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
else
    echo -e "${RED}Xato: apt, dnf yoki yum topilmadi.${NC}"
    exit 1
fi

# Firewall aniqlash
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    FIREWALL_BACKEND="firewalld"
    BANACTION="firewallcmd-rich-rules"
    BANACTION_ALL="firewallcmd-rich-rules[actiontype=<allports>]"
elif command -v nft &>/dev/null; then
    FIREWALL_BACKEND="nftables"
    BANACTION="nftables-multiport"
    BANACTION_ALL="nftables-allports"
elif command -v iptables &>/dev/null; then
    FIREWALL_BACKEND="iptables"
    BANACTION="iptables-multiport"
    BANACTION_ALL="iptables-allports"
else
    FIREWALL_BACKEND="none"
    BANACTION=""
    BANACTION_ALL=""
fi

# Nginx tekshirish
if ! command -v nginx &>/dev/null; then
    echo -e "${RED}Xato: Nginx topilmadi. Avval Nginx o'rnating.${NC}"
    exit 1
fi

echo -e "  OS:       ${CYAN}${OS_NAME}${NC}"
echo -e "  Paketlar: ${CYAN}${PKG_MANAGER}${NC}"
echo -e "  Nginx:    ${CYAN}$(nginx -v 2>&1 | cut -d/ -f2)${NC}"

if [ "$FIREWALL_BACKEND" = "none" ]; then
    echo -e "  Firewall: ${YELLOW}topilmadi${NC}"
    echo ""
    echo -e "  ${YELLOW}OGOHLANTIRISH: Firewall (nftables/firewalld/iptables) topilmadi.${NC}"
    echo "  Web hujumlar Nginx darajasida bloklanadi (ishlaydi)."
    echo "  Lekin SSH brute force bloklash ISHLAMAYDI."
    echo ""
    echo "  Tavsiya: nftables yoki firewalld o'rnating."
    echo ""
    read -p "  Davom etasizmi? [y/N]: " FW_CONFIRM
    if [ "$FW_CONFIRM" != "y" ] && [ "$FW_CONFIRM" != "Y" ]; then
        echo "Bekor qilindi."
        exit 0
    fi
else
    echo -e "  Firewall: ${CYAN}${FIREWALL_BACKEND}${NC}"
fi

# ============================================
# [2/8] Arxitektura so'rash
# ============================================
echo ""
echo -e "${YELLOW}[2/8] Arxitektura sozlamalari${NC}"
echo ""
echo "  Rejim tanlang:"
echo "    1) To'g'ridan-to'g'ri (Internet → Nginx)"
echo "    2) Proxy ortida (Internet → HAProxy/LB → Nginx)"
echo "    3) Faqat monitoring (bloklash yo'q, faqat Telegram xabar)"
echo ""
read -p "  Tanlovingiz [1/2/3] (default: 1): " ARCH_CHOICE
ARCH_CHOICE=${ARCH_CHOICE:-1}

if [ "$ARCH_CHOICE" = "2" ]; then
    ARCHITECTURE="proxy"
    echo ""
    read -p "  Proxy IP yoki subnet (masalan: 10.0.0.0/8): " PROXY_SUBNET
    if [ -z "$PROXY_SUBNET" ]; then
        echo -e "${RED}Xato: Proxy subnet kiritilishi kerak.${NC}"
        exit 1
    fi
    # Faqat IP/CIDR formatini qabul qilish
    if ! echo "$PROXY_SUBNET" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$'; then
        echo -e "${RED}Xato: Noto'g'ri format. Masalan: 10.0.0.5 yoki 10.0.0.0/8${NC}"
        exit 1
    fi
    echo -e "  Rejim: ${CYAN}Proxy ortida (${PROXY_SUBNET})${NC}"
elif [ "$ARCH_CHOICE" = "3" ]; then
    ARCHITECTURE="monitor"
    PROXY_SUBNET=""
    echo -e "  Rejim: ${CYAN}Faqat monitoring (bloklash o'chirilgan)${NC}"
else
    ARCHITECTURE="direct"
    PROXY_SUBNET=""
    echo -e "  Rejim: ${CYAN}To'g'ridan-to'g'ri${NC}"
fi

# ============================================
# [3/8] Telegram sozlash
# ============================================
echo ""
echo -e "${YELLOW}[3/8] Telegram sozlamalari${NC}"
echo ""
read -p "  Telegram BOT_TOKEN: " BOT_TOKEN
read -p "  Telegram CHAT_ID:   " CHAT_ID

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo -e "${RED}Xato: BOT_TOKEN va CHAT_ID bo'sh bo'lmasligi kerak.${NC}"
    exit 1
fi
# Token format tekshirish (faqat raqam, harf, :, -)
if ! echo "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$'; then
    echo -e "${RED}Xato: BOT_TOKEN formati noto'g'ri.${NC}"
    exit 1
fi
# Chat ID format (raqam, manfiy bo'lishi mumkin)
if ! echo "$CHAT_ID" | grep -qE '^-?[0-9]+$'; then
    echo -e "${RED}Xato: CHAT_ID faqat raqam bo'lishi kerak.${NC}"
    exit 1
fi

# Qo'shimcha whitelist IP'lar
echo ""
echo "  Doim ruxsat beriladigan IP'lar (sizning IP, monitoring, boshqa serverlar)"
echo "  Bo'sh joy bilan ajrating. Bo'sh qoldirsangiz ham bo'ladi."
read -p "  IP'lar: " EXTRA_WHITELIST_IPS
# IP formatini tekshirish (agar kiritilgan bo'lsa)
if [ -n "$EXTRA_WHITELIST_IPS" ]; then
    for check_ip in $EXTRA_WHITELIST_IPS; do
        if ! echo "$check_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$'; then
            echo -e "${RED}Xato: '${check_ip}' noto'g'ri IP format.${NC}"
            exit 1
        fi
    done
fi
echo ""

echo -n "  Telegram ulanish tekshirilmoqda... "
RESPONSE=$(curl -s --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}XATO — token noto'g'ri${NC}"
    exit 1
fi

# ============================================
# [4/8] Fail2ban o'rnatish
# ============================================
echo ""
echo -e "${YELLOW}[4/8] Fail2ban o'rnatilmoqda${NC}"

if command -v fail2ban-client &>/dev/null; then
    echo -e "  Fail2ban allaqachon o'rnatilgan: ${CYAN}$(fail2ban-client --version 2>&1 | head -1)${NC}"
else
    if [ "$PKG_MANAGER" = "apt" ]; then
        apt update -qq 2>/dev/null
        if ! apt install -y -qq fail2ban curl jq 2>/dev/null; then
            echo -e "${RED}Xato: Fail2ban o'rnatib bo'lmadi${NC}"
            exit 1
        fi
    elif [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]; then
        $PKG_MANAGER install -y -q epel-release 2>/dev/null || true
        if ! $PKG_MANAGER install -y -q fail2ban curl jq 2>/dev/null; then
            echo -e "${RED}Xato: Fail2ban o'rnatib bo'lmadi${NC}"
            exit 1
        fi
        # CentOS/RHEL uchun firewalld integratsiya
        if [ "$FIREWALL_BACKEND" = "firewalld" ]; then
            $PKG_MANAGER install -y -q fail2ban-firewalld 2>/dev/null || true
        fi
    fi
    echo -e "  ${GREEN}Fail2ban o'rnatildi${NC}"
fi

systemctl enable fail2ban > /dev/null 2>&1

# ============================================
# [5/8] Sentinel fayllarni joylashtirish
# ============================================
echo ""
echo -e "${YELLOW}[5/8] Sentinel fayllar joylashtirilmoqda${NC}"

# --- Papkalar yaratish ---
mkdir -p "$SENTINEL_DIR" "$SENTINEL_LOG_DIR"
chown root:root "$SENTINEL_DIR"
chmod 700 "$SENTINEL_DIR"

# --- Logrotate ---
if [ -f "${SCRIPT_DIR}/config/sentinel-logrotate.conf" ]; then
    cp "${SCRIPT_DIR}/config/sentinel-logrotate.conf" /etc/logrotate.d/sentinel
fi

# --- Config yaratish ---
cat > "${SENTINEL_DIR}/sentinel.conf" << CONF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
LOG_FILE="${SENTINEL_LOG_DIR}/sentinel.log"
DENY_MAP="${NGINX_CONF_DIR}/sentinel-deny.map"
ARCHITECTURE="${ARCHITECTURE}"
PROXY_SUBNET="${PROXY_SUBNET}"
FIREWALL_BACKEND="${FIREWALL_BACKEND}"
WHITELIST_AUTO_UPDATE="yes"
WHITELIST_CRON_SCHEDULE="0 3 * * 1"
DAILY_REPORT_ENABLED="yes"
DAILY_REPORT_CRON="0 8 * * *"
HEALTH_CHECK_ENABLED="yes"
HEALTH_CHECK_CRON="*/30 * * * *"
CONF
chmod 600 "${SENTINEL_DIR}/sentinel.conf"
echo "  sentinel.conf — OK (chmod 600)"

# --- Whitelist ---
if [ -f "${SCRIPT_DIR}/config/whitelist.conf" ]; then
    cp "${SCRIPT_DIR}/config/whitelist.conf" "${SENTINEL_DIR}/whitelist.conf"
else
    cat > "${SENTINEL_DIR}/whitelist.conf" << 'WL'
127.0.0.1/8
::1
10.0.0.0/8
192.168.0.0/16
172.16.0.0/12
WL
fi
echo "  whitelist.conf — OK"

# --- Nginx config fayllar ---
touch "${NGINX_CONF_DIR}/sentinel-deny.map"

# Log format
if [ -f "${SCRIPT_DIR}/nginx/sentinel-log-format.conf" ]; then
    cp "${SCRIPT_DIR}/nginx/sentinel-log-format.conf" "${NGINX_CONF_DIR}/sentinel-log-format.conf"
fi

# Security (map + block)
if [ -f "${SCRIPT_DIR}/nginx/sentinel-security.conf" ]; then
    cp "${SCRIPT_DIR}/nginx/sentinel-security.conf" "${NGINX_CONF_DIR}/sentinel-security.conf"
fi

# Real IP (proxy holat uchun)
if [ "$ARCHITECTURE" = "proxy" ]; then
    cat > "${NGINX_CONF_DIR}/sentinel-realip.conf" << REALIP
# Sentinel — Real IP (proxy ortida)
# Avtomatik yaratilgan: $(date '+%Y-%m-%d %H:%M:%S')

set_real_ip_from ${PROXY_SUBNET};
real_ip_header X-Forwarded-For;
real_ip_recursive on;
REALIP
    echo "  sentinel-realip.conf — OK (proxy: ${PROXY_SUBNET})"
fi

echo "  Nginx config fayllar — OK"

# --- Filterlar ---
for filter in sentinel-scanner sentinel-exploit sentinel-botnet sentinel-ratelimit sentinel-bruteforce; do
    if [ -f "${SCRIPT_DIR}/filters/${filter}.conf" ]; then
        cp "${SCRIPT_DIR}/filters/${filter}.conf" "${F2B_FILTER_DIR}/${filter}.conf"
    fi
    echo "  ${filter}.conf — OK"
done

# --- Action: nginx-block ---
if [ -f "${SCRIPT_DIR}/actions/sentinel-nginx-block.conf" ]; then
    cp "${SCRIPT_DIR}/actions/sentinel-nginx-block.conf" "${F2B_ACTION_DIR}/sentinel-nginx-block.conf"
fi
echo "  sentinel-nginx-block.conf — OK"

# --- Action: telegram ---
if [ -f "${SCRIPT_DIR}/actions/sentinel-telegram.conf" ]; then
    cp "${SCRIPT_DIR}/actions/sentinel-telegram.conf" "${F2B_ACTION_DIR}/sentinel-telegram.conf"
fi
echo "  sentinel-telegram.conf — OK"

# --- Scriptlar ---
for script in notify.sh sender.sh whitelist-update.sh daily-report.sh health-check.sh reload-timer.sh; do
    if [ -f "${SCRIPT_DIR}/scripts/${script}" ]; then
        cp "${SCRIPT_DIR}/scripts/${script}" "${SENTINEL_BIN}/sentinel-${script}"
        chmod +x "${SENTINEL_BIN}/sentinel-${script}"
    fi
done

# --- Test va Uninstall scriptlar ---
if [ -f "${SCRIPT_DIR}/test.sh" ]; then
    cp "${SCRIPT_DIR}/test.sh" "${SENTINEL_BIN}/sentinel-test.sh"
    chmod +x "${SENTINEL_BIN}/sentinel-test.sh"
fi
if [ -f "${SCRIPT_DIR}/uninstall.sh" ]; then
    cp "${SCRIPT_DIR}/uninstall.sh" "${SENTINEL_BIN}/sentinel-uninstall.sh"
    chmod +x "${SENTINEL_BIN}/sentinel-uninstall.sh"
fi
echo "  Scriptlar — OK"

# ============================================
# [6/8] Jail konfiguratsiya yaratish
# ============================================
echo ""
echo -e "${YELLOW}[6/8] Jail konfiguratsiya yaratilmoqda${NC}"

# Action strategiyasini aniqlash
if [ "$ARCHITECTURE" = "monitor" ]; then
    # Faqat monitoring — bloklash yo'q, faqat Telegram
    WEB_ACTION="action   = sentinel-telegram[name=%(__name__)s]"
    SSH_ACTION="action   = sentinel-telegram[name=sshd]"
    RECIDIVE_ACTION="banaction = sentinel-telegram"
elif [ "$ARCHITECTURE" = "proxy" ]; then
    # Proxy ortida — faqat nginx-block-map
    WEB_ACTION="action   = sentinel-nginx-block[deny_map=${NGINX_CONF_DIR}/sentinel-deny.map]
           sentinel-telegram[name=%(__name__)s]"
    SSH_ACTION="action   = sentinel-telegram[name=sshd]"
    RECIDIVE_ACTION="banaction = sentinel-nginx-block"
else
    if [ -n "$BANACTION" ]; then
        # To'g'ridan-to'g'ri — firewall + nginx-block-map
        WEB_ACTION="action   = ${BANACTION}[name=%(__name__)s, port=\"http,https\", protocol=tcp]
           sentinel-nginx-block[deny_map=${NGINX_CONF_DIR}/sentinel-deny.map]
           sentinel-telegram[name=%(__name__)s]"
        SSH_ACTION="action   = ${BANACTION}[name=sshd, port=\"ssh\", protocol=tcp]
           sentinel-telegram[name=sshd]"
        RECIDIVE_ACTION="banaction = ${BANACTION_ALL}"
    else
        # Firewall yo'q — faqat nginx-block-map
        WEB_ACTION="action   = sentinel-nginx-block[deny_map=${NGINX_CONF_DIR}/sentinel-deny.map]
           sentinel-telegram[name=%(__name__)s]"
        SSH_ACTION="action   = sentinel-telegram[name=sshd]"
        RECIDIVE_ACTION="banaction = sentinel-nginx-block"
    fi
fi

# Whitelist tayyorlash
IGNORE_IPS="127.0.0.1/8 ::1 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12"
if [ -n "$PROXY_SUBNET" ]; then
    IGNORE_IPS="${IGNORE_IPS} ${PROXY_SUBNET}"
fi
if [ -n "$EXTRA_WHITELIST_IPS" ]; then
    IGNORE_IPS="${IGNORE_IPS} ${EXTRA_WHITELIST_IPS}"
fi

# SSH backend aniqlash
if [ -f /var/log/auth.log ]; then
    SSHD_BACKEND="auto"
else
    SSHD_BACKEND="systemd"
fi

cat > "${F2B_JAIL_DIR}/sentinel-jails.conf" << JAILCONF
# Sentinel — Jail Konfiguratsiya
# Avtomatik yaratilgan: $(date '+%Y-%m-%d %H:%M:%S')
# ESLATMA: [DEFAULT] ishlatilmaydi — mavjud jaillarni buzmaslik uchun

[sentinel-scanner]
enabled  = true
port     = http,https
filter   = sentinel-scanner
logpath  = /var/log/nginx/*_access.log
           /var/log/nginx/access.log
maxretry = 3
findtime = 600
bantime  = 86400
ignoreip = ${IGNORE_IPS}
${WEB_ACTION}

[sentinel-exploit]
enabled  = true
port     = http,https
filter   = sentinel-exploit
logpath  = /var/log/nginx/*_access.log
           /var/log/nginx/access.log
maxretry = 1
findtime = 600
bantime  = 604800
ignoreip = ${IGNORE_IPS}
${WEB_ACTION}

[sentinel-botnet]
enabled  = true
port     = http,https
filter   = sentinel-botnet
logpath  = /var/log/nginx/*_access.log
           /var/log/nginx/access.log
maxretry = 1
findtime = 600
bantime  = 604800
ignoreip = ${IGNORE_IPS}
${WEB_ACTION}

[sentinel-ratelimit]
enabled  = true
port     = http,https
filter   = sentinel-ratelimit
logpath  = /var/log/nginx/*_access.log
           /var/log/nginx/access.log
maxretry = 100
findtime = 60
bantime  = 3600
ignoreip = ${IGNORE_IPS}
${WEB_ACTION}

[sentinel-bruteforce]
enabled  = true
port     = http,https
filter   = sentinel-bruteforce
logpath  = /var/log/nginx/*_access.log
           /var/log/nginx/access.log
maxretry = 15
findtime = 300
bantime  = 3600
ignoreip = ${IGNORE_IPS}
${WEB_ACTION}

[sentinel-recidive]
enabled  = true
filter   = recidive
logpath  = /var/log/fail2ban.log
maxretry = 3
findtime = 86400
bantime  = 604800
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 2592000
ignoreip = ${IGNORE_IPS}
${RECIDIVE_ACTION}

[sshd]
enabled  = true
port     = ssh
filter   = sshd
backend  = ${SSHD_BACKEND}
maxretry = 5
findtime = 600
bantime  = 86400
ignoreip = ${IGNORE_IPS}
${SSH_ACTION}
JAILCONF
echo "  sentinel-jails.conf — OK"

# ============================================
# [7/8] Cron va Whitelist sozlash
# ============================================
echo ""
echo -e "${YELLOW}[7/8] Cron joblar sozlanmoqda${NC}"

# Whitelist boshlang'ich yuklash
"${SENTINEL_BIN}/sentinel-whitelist-update.sh" 2>/dev/null || true
echo "  Whitelist yuklandi"

# Cron joblar
CRON_TAG="# SENTINEL_CRON"
(crontab -l 2>/dev/null | grep -v "$CRON_TAG") | {
    cat
    echo "0 3 * * 1 ${SENTINEL_BIN}/sentinel-whitelist-update.sh ${CRON_TAG}"
    echo "0 8 * * * ${SENTINEL_BIN}/sentinel-daily-report.sh ${CRON_TAG}"
    echo "*/30 * * * * ${SENTINEL_BIN}/sentinel-health-check.sh ${CRON_TAG}"
} | crontab -
echo "  Cron joblar — OK"

# ============================================
# [8/8] Ishga tushirish
# ============================================
echo ""
echo -e "${YELLOW}[8/8] Fail2ban ishga tushirilmoqda${NC}"

# Config test
if fail2ban-client --test > /dev/null 2>&1; then
    echo "  Config test — OK"
else
    echo -e "${RED}  Config test — XATO:${NC}"
    fail2ban-client --test 2>&1 | tail -5
    echo ""
    echo -e "${RED}  Xatoni tuzating va qayta ishga tushiring.${NC}"
    exit 1
fi

systemctl restart fail2ban

# Jaillar tekshirish
sleep 2
JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//')
echo -e "  Jaillar: ${CYAN}${JAILS}${NC}"

# Telegram test xabar
"${SENTINEL_BIN}/sentinel-notify.sh" ban test 0.0.0.0 0 "install-test"

# ============================================
# Yakuniy ko'rsatmalar
# ============================================
echo ""
echo "============================================"
echo -e "${GREEN}  Sentinel muvaffaqiyatli o'rnatildi!${NC}"
echo "============================================"
echo ""
# Nginx log format tekshirish
NGINX_CONFIGURED=false
if grep -rq "sentinel-log-format" /etc/nginx/nginx.conf 2>/dev/null; then
    echo -e "${GREEN}  Nginx sentinel konfiguratsiya topildi.${NC}"
    NGINX_CONFIGURED=true
fi

echo ""
echo -e "${CYAN}KEYINGI QADAM: Nginx konfiguratsiya${NC}"
echo ""
echo "  Tayyor config fayllar serverga joylashtirildi."
echo "  Siz faqat nginx.conf ga include qo'shishingiz kerak."
echo ""
echo -e "  ${YELLOW}1-QADAM: nginx.conf ning http {} blokiga qo'shing:${NC}"
echo ""
echo "     http {"
echo "         # Sentinel"
echo "         include /etc/nginx/sentinel-log-format.conf;"
echo "         include /etc/nginx/sentinel-security.conf;"
if [ "$ARCHITECTURE" = "proxy" ]; then
echo "         include /etc/nginx/sentinel-realip.conf;"
fi
echo ""
echo "         # ... mavjud konfiguratsiya ..."
echo "     }"
echo ""
echo -e "  ${YELLOW}2-QADAM: Har bir server {} blokiga qo'shing:${NC}"
echo ""
echo "     server {"
echo "         # Sentinel log format ishlatish"
echo "         access_log /var/log/nginx/DOMAIN_access.log sentinel;"
echo ""
echo "         # Bloklangan IP'larni taqiqlash"
echo "         if (\$sentinel_blocked) {"
echo "             return 403;"
echo "         }"
echo ""
echo "         # ... mavjud konfiguratsiya ..."
echo "     }"
echo ""
echo -e "  ${YELLOW}3-QADAM: Tekshirish va reload:${NC}"
echo ""
echo "     nginx -t && nginx -s reload"
echo ""
echo -e "  ${RED}ESLATMA: 1-2-3 qadamlarni bajarmaguncha Sentinel ISHLAMAYDI!${NC}"
echo ""
echo "============================================"
echo ""
echo "Foydali buyruqlar:"
echo "  sentinel-test.sh                          — Sentinel test"
echo "  sentinel-uninstall.sh                     — Sentinel o'chirish"
echo "  fail2ban-client status                    — umumiy holat"
echo "  fail2ban-client status sentinel-scanner   — scanner jail"
echo "  fail2ban-client banned                    — barcha blocked IP'lar"
echo "  fail2ban-client set JAIL unbanip IP       — IP ni ochish"
echo "  fail2ban-client unban --all               — hammasini ochish"
echo "  cat /etc/nginx/sentinel-deny.map          — bloklangan IP'lar"
echo "  cat /var/log/sentinel/sentinel.log        — Sentinel loglari"
echo ""
echo "============================================"
