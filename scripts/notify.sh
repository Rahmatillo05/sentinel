#!/bin/bash
# ============================================
# Sentinel — Telegram Notification Script
# Joylashuv: /usr/local/bin/sentinel-notify.sh
# ============================================

# Config yuklash
CONF_FILE="/etc/sentinel/sentinel.conf"
if [ ! -f "$CONF_FILE" ]; then
    exit 1
fi
source "$CONF_FILE"

# Log papka mavjudligi
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Parametrlar
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
HOSTNAME=$(hostname)
ACTION=$1
JAIL=$2
IP=$3
FAILURES=$4
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Jail nomi → o'zbek tavsif
case "$JAIL" in
    sentinel-scanner)    ALERT_TYPE="Scanner aniqlandi"     ; BAN_DUR="24 soat" ;;
    sentinel-exploit)    ALERT_TYPE="Exploit/Hujum urinishi"; BAN_DUR="7 kun" ;;
    sentinel-botnet)     ALERT_TYPE="Zararli bot"           ; BAN_DUR="7 kun" ;;
    sentinel-ratelimit)  ALERT_TYPE="Rate limit oshdi"      ; BAN_DUR="1 soat" ;;
    sentinel-bruteforce) ALERT_TYPE="Brute force hujum"     ; BAN_DUR="1 soat" ;;
    sentinel-recidive)   ALERT_TYPE="Qayta offender"        ; BAN_DUR="progressiv" ;;
    sshd)                ALERT_TYPE="SSH brute force"       ; BAN_DUR="24 soat" ;;
    test)                ALERT_TYPE="Test xabar"            ; BAN_DUR="-" ;;
    *)                   ALERT_TYPE="$JAIL"                 ; BAN_DUR="noaniq" ;;
esac

# GeoIP ma'lumot olish (ip-api.com — bepul, sekundiga 45 so'rov)
get_geoip() {
    local ip=$1
    local geo_data
    geo_data=$(curl -s --max-time 5 "http://ip-api.com/json/${ip}?fields=status,country,city,isp,org" 2>/dev/null)

    if echo "$geo_data" | grep -q '"status":"success"'; then
        local country city isp
        country=$(echo "$geo_data" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
        city=$(echo "$geo_data" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
        isp=$(echo "$geo_data" | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
        echo "${country}, ${city} (${isp})"
    else
        echo "noaniq"
    fi
}

# Oxirgi so'rovlarni olish
get_last_requests() {
    local ip=$1
    # IP dagi nuqtalarni escape qilish (grep regex uchun)
    local ip_escaped="${ip//./\\.}"
    local requests=""
    requests=$(grep -F "$ip" /var/log/nginx/*_access.log /var/log/nginx/access.log 2>/dev/null \
        | tail -5 \
        | sed 's/.*"\(\/[^"]*\)".*/  \1/' 2>/dev/null)
    echo "${requests:-  ma'lumot yo'q}"
}

# --- BAN xabari ---
if [ "$ACTION" = "ban" ]; then

    GEO=$(get_geoip "$IP")
    REQUESTS=$(get_last_requests "$IP")

    MESSAGE="SENTINEL ALERT
${ALERT_TYPE}

Server:      ${HOSTNAME}
IP:          ${IP}
Joylashuv:   ${GEO}
Urinishlar:  ${FAILURES} ta
Ban muddati: ${BAN_DUR}
Jail:        ${JAIL}
Vaqt:        ${TIMESTAMP}

Oxirgi so'rovlar:
${REQUESTS}"

    RESULT=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${MESSAGE}" 2>&1)

    HTTP_CODE=$(echo "$RESULT" | tail -1)
    if [ "$HTTP_CODE" != "200" ]; then
        echo "[SENTINEL] $(date) Telegram xabar yuborishda xato (HTTP $HTTP_CODE): ban $IP" >> /var/log/sentinel/sentinel.log
    fi

# --- UNBAN xabari ---
elif [ "$ACTION" = "unban" ]; then

    MESSAGE="SENTINEL AUTO-UNBAN
Server: ${HOSTNAME}
IP:     ${IP}
Jail:   ${JAIL}
Vaqt:   ${TIMESTAMP}
Ban muddati tugadi, IP ochildi."

    RESULT=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${MESSAGE}" 2>&1)

    HTTP_CODE=$(echo "$RESULT" | tail -1)
    if [ "$HTTP_CODE" != "200" ]; then
        echo "[SENTINEL] $(date) Telegram xabar yuborishda xato (HTTP $HTTP_CODE): unban $IP" >> /var/log/sentinel/sentinel.log
    fi

fi
