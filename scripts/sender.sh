#!/bin/bash
# ============================================
# Sentinel — Queue Sender
# Joylashuv: /usr/local/bin/sentinel-sender.sh
# ============================================
# Queue papkadagi xabarlarni ketma-ket Telegram'ga yuboradi.
# Bir vaqtda faqat 1 ta sender ishlaydi.
# DDoS paytida xabarlarni guruhlab (batch) yuboradi.
# ============================================

CONF_FILE="/etc/sentinel/sentinel.conf"
if [ ! -f "$CONF_FILE" ]; then
    exit 1
fi
source "$CONF_FILE"

QUEUE_DIR="/var/log/sentinel/queue"
PID_FILE="/tmp/sentinel-sender.pid"
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
BATCH_WAIT=5       # sekund — yangi xabarlar uchun kutish
MAX_IDLE=60         # sekund — queue bo'sh bo'lsa o'chish
BATCH_SIZE=10       # shu sondan ko'p bo'lsa guruhlab yuborish

# Allaqachon ishlayaptimi?
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PID_FILE"

# Tozalash (exit paytida)
cleanup() {
    rm -f "$PID_FILE"
}
trap cleanup EXIT

# GeoIP link (API chaqirmasdan, faqat link berish)
get_geoip_link() {
    echo "https://ip-api.com/#${1}"
}

# Xabar yuborish
send_telegram() {
    local text="$1"
    curl -s --max-time 10 -X POST "${API_URL}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${text}" \
        > /dev/null 2>&1
}

# Asosiy loop
idle_count=0

while true; do
    # Queue'dagi xabarlarni olish
    MESSAGES=("${QUEUE_DIR}"/*.msg)

    # Queue bo'shmi?
    if [ ! -f "${MESSAGES[0]}" ]; then
        idle_count=$((idle_count + 1))
        if [ "$idle_count" -ge $((MAX_IDLE / BATCH_WAIT)) ]; then
            # MAX_IDLE sekund bo'sh — o'chish
            break
        fi
        sleep "$BATCH_WAIT"
        continue
    fi

    idle_count=0
    MSG_COUNT=${#MESSAGES[@]}

    if [ "$MSG_COUNT" -le "$BATCH_SIZE" ]; then
        # Kam xabar — har birini alohida yuborish
        for msg_file in "${MESSAGES[@]}"; do
            [ ! -f "$msg_file" ] && continue

            TEXT=$(cat "$msg_file")
            rm -f "$msg_file"

            send_telegram "$TEXT"
            sleep 0.1
        done
    else
        # Ko'p xabar — guruhlab bitta xabar qilish
        BATCH_TEXT="SENTINEL — ${MSG_COUNT} ta hodisa

Server: $(hostname)
Vaqt:   $(date '+%Y-%m-%d %H:%M:%S')
"
        for msg_file in "${MESSAGES[@]}"; do
            [ ! -f "$msg_file" ] && continue

            MSG_IP=$(grep "^IP:" "$msg_file" | awk '{print $2}')
            TYPE_LINE=$(head -2 "$msg_file" | tail -1)
            JAIL_SHORT=$(grep "^Jail:" "$msg_file" | awk '{print $2}' | sed 's/sentinel-//')

            if [ -n "$MSG_IP" ]; then
                BATCH_TEXT="${BATCH_TEXT}
${JAIL_SHORT} | ${MSG_IP} | https://ip-api.com/#${MSG_IP}"
            fi

            rm -f "$msg_file"
        done

        send_telegram "$BATCH_TEXT"
    fi

    sleep "$BATCH_WAIT"
done
