#!/bin/bash
# ============================================
# Sentinel — Uninstall (O'chirib Tashlash)
# ============================================
#
# Ishlatish:
#   sudo bash uninstall.sh
#
# Bu script:
#   - Sentinel jail'larni to'xtatadi
#   - Fail2ban config fayllarni o'chiradi
#   - Sentinel scriptlarni o'chiradi
#   - Cron joblarni o'chiradi
#   - /etc/sentinel papkani o'chiradi
#   - Fail2ban'ni qayta ishga tushiradi
#
# O'CHIRMAYDI:
#   - Fail2ban o'zini (boshqa jaillar uchun kerak bo'lishi mumkin)
#   - Nginx konfiguratsiyasini (qo'lda olib tashlang)
#
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "============================================"
echo "  SENTINEL — O'chirib Tashlash"
echo "============================================"
echo ""

# Root tekshirish
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Xato: root huquqi kerak.${NC}"
    exit 1
fi

# Tasdiqlash
echo -e "${YELLOW}Sentinel to'liq o'chiriladi. Davom etasizmi?${NC}"
read -p "[y/N]: " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Bekor qilindi."
    exit 0
fi

echo ""

# --- Fail2ban jaillarni to'xtatish ---
echo -n "Jaillar to'xtatilmoqda... "
for jail in sentinel-scanner sentinel-exploit sentinel-botnet sentinel-ratelimit sentinel-bruteforce sentinel-recidive; do
    fail2ban-client stop "$jail" 2>/dev/null || true
done
echo -e "${GREEN}OK${NC}"

# --- Fail2ban config fayllar ---
echo -n "Fail2ban config fayllar o'chirilmoqda... "
rm -f /etc/fail2ban/filter.d/sentinel-*.conf
rm -f /etc/fail2ban/jail.d/sentinel-*.conf
rm -f /etc/fail2ban/action.d/sentinel-*.conf
echo -e "${GREEN}OK${NC}"

# --- Sentinel scriptlar ---
echo -n "Sentinel scriptlar o'chirilmoqda... "
rm -f /usr/local/bin/sentinel-*.sh
echo -e "${GREEN}OK${NC}"

# --- Sentinel config papka ---
echo -n "Sentinel config o'chirilmoqda... "
rm -rf /etc/sentinel
echo -e "${GREEN}OK${NC}"

# --- Sentinel loglar ---
echo -n "Sentinel loglar o'chirilmoqda... "
rm -rf /var/log/sentinel
echo -e "${GREEN}OK${NC}"

# --- Reload timer to'xtatish ---
echo -n "Reload timer to'xtatilmoqda... "
if [ -f /var/log/sentinel/sentinel-reload-timer.pid ]; then
    kill "$(cat /var/log/sentinel/sentinel-reload-timer.pid)" 2>/dev/null || true
fi
if [ -f /var/log/sentinel/sentinel-sender.pid ]; then
    kill "$(cat /var/log/sentinel/sentinel-sender.pid)" 2>/dev/null || true
fi
echo -e "${GREEN}OK${NC}"

# --- Nginx deny map va config fayllar ---
echo -n "Nginx sentinel fayllar tozalanmoqda... "
if [ -f /etc/nginx/sentinel-deny.map ]; then
    > /etc/nginx/sentinel-deny.map
fi
rm -f /etc/nginx/sentinel-log-format.conf
rm -f /etc/nginx/sentinel-security.conf
rm -f /etc/nginx/sentinel-realip.conf
echo -e "${GREEN}OK${NC}"

# --- Cron joblar ---
echo -n "Cron joblar o'chirilmoqda... "
CRON_TAG="# SENTINEL_CRON"
(crontab -l 2>/dev/null | grep -v "$CRON_TAG") | crontab - 2>/dev/null || true
echo -e "${GREEN}OK${NC}"

# --- Fail2ban restart ---
echo -n "Fail2ban qayta ishga tushirilmoqda... "
systemctl restart fail2ban 2>/dev/null || true
echo -e "${GREEN}OK${NC}"

echo ""
echo "============================================"
echo -e "${GREEN}  Sentinel muvaffaqiyatli o'chirildi!${NC}"
echo "============================================"
echo ""
echo -e "${YELLOW}ESLATMA: Nginx konfiguratsiyasidan quyidagilarni qo'lda olib tashlang:${NC}"
echo ""
echo "  1. nginx.conf dan include qatorlarni o'chiring:"
echo "     include /etc/nginx/sentinel-log-format.conf;"
echo "     include /etc/nginx/sentinel-security.conf;"
echo "     include /etc/nginx/sentinel-realip.conf;"
echo ""
echo "  2. server {} bloklardan:"
echo "     access_log ... sentinel;  →  standart formatga qaytaring"
echo "     if (\$sentinel_blocked) { return 403; }  →  o'chiring"
echo ""
echo "  3. nginx -t && nginx -s reload"
echo ""
echo "============================================"
