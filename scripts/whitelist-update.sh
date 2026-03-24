#!/bin/bash
# ============================================
# Sentinel — Whitelist Avtomatik Yangilash
# Joylashuv: /usr/local/bin/sentinel-whitelist-update.sh
# Cron: haftalik (0 3 * * 1)
# ============================================
# Google, Bing, Yandex botlarning rasmiy IP diapazonlarini
# yuklab olib, Fail2ban whitelist'ga qo'shadi.
# ============================================

CONF_FILE="/etc/sentinel/sentinel.conf"
WHITELIST_DIR="/etc/sentinel"
LOG_FILE="/var/log/sentinel/sentinel.log"

log() {
    echo "[SENTINEL] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "Whitelist yangilash boshlandi"

# --- Google IP diapazonlari ---
GOOGLE_IPS=$(curl -s --max-time 30 "https://developers.google.com/static/search/apis/ipranges/googlebot.json" 2>/dev/null)
if echo "$GOOGLE_IPS" | grep -q "prefixes"; then
    echo "$GOOGLE_IPS" | grep -o '"ipv4Prefix":"[^"]*"' | cut -d'"' -f4 > "${WHITELIST_DIR}/whitelist-google.conf"
    GOOGLE_COUNT=$(wc -l < "${WHITELIST_DIR}/whitelist-google.conf" | tr -d ' ')
    log "Google IP: ${GOOGLE_COUNT} ta diapazon yuklandi"
else
    log "XATO: Google IP yuklab bo'lmadi"
fi

# --- Bing IP diapazonlari ---
# Bing rasmiy JSON endpoint'i yo'q, asosiy diapazonlar
cat > "${WHITELIST_DIR}/whitelist-bing.conf" << 'BING'
40.77.167.0/24
199.30.24.0/23
157.55.39.0/24
207.46.13.0/24
40.77.188.0/22
65.52.104.0/24
207.46.0.0/16
BING
log "Bing IP: statik ro'yxat yozildi"

# --- Yandex IP diapazonlari ---
cat > "${WHITELIST_DIR}/whitelist-yandex.conf" << 'YANDEX'
5.255.253.0/24
37.140.165.0/24
77.88.22.0/23
77.88.44.0/24
87.250.224.0/19
93.158.147.0/24
95.108.128.0/17
100.43.80.0/24
141.8.153.0/24
178.154.128.0/17
199.21.99.0/24
213.180.192.0/19
YANDEX
log "Yandex IP: statik ro'yxat yozildi"

# --- Barcha whitelist'larni birlashtirish ---
{
    echo "# Sentinel Auto-Generated Whitelist"
    echo "# Yangilangan: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Qo'lda o'zgartirmang — bu fayl avtomatik qayta yoziladi"
    echo ""
    echo "# Google"
    cat "${WHITELIST_DIR}/whitelist-google.conf" 2>/dev/null
    echo ""
    echo "# Bing"
    cat "${WHITELIST_DIR}/whitelist-bing.conf" 2>/dev/null
    echo ""
    echo "# Yandex"
    cat "${WHITELIST_DIR}/whitelist-yandex.conf" 2>/dev/null
} > "${WHITELIST_DIR}/whitelist-searchengines.conf"

# --- Fail2ban ignoreip yangilash ---
# Qo'lda yozilgan whitelist + avtomatik whitelist = birlashtirilgan
IGNORE_IPS="127.0.0.1/8 ::1"

# Qo'lda yozilgan whitelist
if [ -f "${WHITELIST_DIR}/whitelist.conf" ]; then
    MANUAL_IPS=$(grep -v '^#' "${WHITELIST_DIR}/whitelist.conf" | grep -v '^$' | tr '\n' ' ')
    IGNORE_IPS="${IGNORE_IPS} ${MANUAL_IPS}"
fi

# Search engine IP'lari
if [ -f "${WHITELIST_DIR}/whitelist-searchengines.conf" ]; then
    SE_IPS=$(grep -v '^#' "${WHITELIST_DIR}/whitelist-searchengines.conf" | grep -v '^$' | tr '\n' ' ')
    IGNORE_IPS="${IGNORE_IPS} ${SE_IPS}"
fi

# Jail config'dagi ignoreip ni yangilash
# sed multiline ishlamaydi, shuning uchun to'liq faylni qayta yozamiz
JAIL_CONF="/etc/fail2ban/jail.d/sentinel-jails.conf"
if [ -f "$JAIL_CONF" ]; then
    # Faqat ignoreip qatorini yangilash (bitta qatorda, bo'sh joy bilan ajratilgan)
    sed -i "s|^ignoreip = .*|ignoreip = ${IGNORE_IPS}|" "$JAIL_CONF" 2>/dev/null
    log "Fail2ban ignoreip yangilandi"
fi

# Fail2ban reload
if command -v fail2ban-client &>/dev/null; then
    fail2ban-client reload 2>/dev/null
    log "Fail2ban reload qilindi"
fi

log "Whitelist yangilash tugadi"
