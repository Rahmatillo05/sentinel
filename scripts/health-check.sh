#!/bin/bash
# ============================================
# Sentinel — Health Check
# Joylashuv: /usr/local/bin/sentinel-health-check.sh
# Cron: har 30 daqiqada (*/30 * * * *)
# ============================================
# Fail2ban ishlayaptimi tekshiradi.
# Agar to'xtagan bo'lsa — qayta ishga tushiradi va Telegram xabar yuboradi.
# ============================================

CONF_FILE="/etc/sentinel/sentinel.conf"
if [ ! -f "$CONF_FILE" ]; then
    exit 1
fi

# Xavfsiz config o'qish
get_conf() { grep "^${1}=" "$CONF_FILE" | head -1 | cut -d'"' -f2; }

BOT_TOKEN=$(get_conf BOT_TOKEN)
CHAT_ID=$(get_conf CHAT_ID)
DENY_MAP=$(get_conf DENY_MAP)
LOG_FILE=$(get_conf LOG_FILE)

API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
HOSTNAME=$(hostname)
LOG_FILE="${LOG_FILE:-/var/log/sentinel/sentinel.log}"

log() {
    echo "[SENTINEL] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# --- Fail2ban holati tekshirish ---
if ! systemctl is-active --quiet fail2ban 2>/dev/null; then

    log "OGOHLANTIRISH: Fail2ban ishlamayapti! Qayta ishga tushirilmoqda..."

    systemctl restart fail2ban 2>/dev/null

    sleep 3

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        STATUS="qayta ishga tushirildi"
        log "Fail2ban muvaffaqiyatli qayta ishga tushdi"
    else
        STATUS="QAYTA ISHGA TUSHMADI!"
        log "KRITIK: Fail2ban qayta ishga tushmadi!"
    fi

    MESSAGE="SENTINEL HEALTH CHECK
Server: ${HOSTNAME}
Vaqt:   $(date '+%Y-%m-%d %H:%M:%S')

Fail2ban to'xtagan edi!
Holat: ${STATUS}

Tekshiring: systemctl status fail2ban"

    curl -s -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${MESSAGE}" \
        > /dev/null 2>&1
fi

# --- Nginx holati tekshirish ---
if ! systemctl is-active --quiet nginx 2>/dev/null; then

    log "OGOHLANTIRISH: Nginx ishlamayapti!"

    MESSAGE="SENTINEL HEALTH CHECK
Server: ${HOSTNAME}
Vaqt:   $(date '+%Y-%m-%d %H:%M:%S')

Nginx ishlamayapti!

Tekshiring: systemctl status nginx"

    curl -s -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${MESSAGE}" \
        > /dev/null 2>&1
fi

# --- Deny map hajmi tekshirish ---
if [ -f "$DENY_MAP" ]; then
    DENY_COUNT=$(wc -l < "$DENY_MAP" | tr -d ' ')
    if [ "$DENY_COUNT" -gt 10000 ]; then
        log "OGOHLANTIRISH: sentinel-deny.map da ${DENY_COUNT} ta yozuv — juda ko'p"

        MESSAGE="SENTINEL HEALTH CHECK
Server: ${HOSTNAME}

sentinel-deny.map da ${DENY_COUNT} ta bloklangan IP.
Bu Nginx reload tezligiga ta'sir qilishi mumkin.

Eski yozuvlarni tozalang yoki Fail2ban bantime'ni tekshiring."

        curl -s -X POST "${API_URL}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "disable_web_page_preview=true" \
            --data-urlencode "text=${MESSAGE}" \
            > /dev/null 2>&1
    fi
fi
