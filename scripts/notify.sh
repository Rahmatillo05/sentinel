#!/bin/bash
# ============================================
# Sentinel — Telegram Notification Script
# Joylashuv: /usr/local/bin/sentinel-notify.sh
# ============================================
# Bu script xabarni to'g'ridan-to'g'ri yubormaydi.
# Queue faylga yozadi → sender process navbatdan yuboradi.
# DDoS paytida 100 ta ban = 100 ta curl emas, 1 ta sender.
# ============================================

CONF_FILE="/etc/sentinel/sentinel.conf"
if [ ! -f "$CONF_FILE" ]; then
    exit 1
fi

QUEUE_DIR="/var/log/sentinel/queue"
mkdir -p "$QUEUE_DIR" 2>/dev/null || true

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

if [ "$ACTION" = "ban" ]; then

    # Qaysi domenlarga so'rov yuborilgan (log fayl nomidan)
    DOMAINS=$(grep -l "\[Client ${IP}\]" /var/log/nginx/*_access.log 2>/dev/null \
        | sed 's|.*/||; s|_access\.log||' \
        | sort -u \
        | tr '\n' ', ' \
        | sed 's/,$//')

    # Oxirgi so'rovlarni olish
    REQUESTS=$(grep "\[Client ${IP}\]" /var/log/nginx/*_access.log /var/log/nginx/access.log 2>/dev/null \
        | tail -5 \
        | sed 's/.*"\(\/[^"]*\)".*/  \1/' 2>/dev/null)

    MESSAGE="SENTINEL BAN
${ALERT_TYPE}

Server:  ${HOSTNAME}
IP:      ${IP}
Geo:     https://ip-api.com/#${IP}
Domen:   ${DOMAINS:-noaniq}
Jail:    ${JAIL}
Ban:     ${BAN_DUR}
Vaqt:    ${TIMESTAMP}

So'rovlar:
${REQUESTS:-  -}"

elif [ "$ACTION" = "unban" ]; then

    MESSAGE="SENTINEL UNBAN
${HOSTNAME} | ${IP} | ${JAIL}
${TIMESTAMP}"

else
    exit 0
fi

# Queue ga yozish (atomik — mv orqali)
TEMP=$(mktemp "${QUEUE_DIR}/.tmp.XXXXXX")
echo "$MESSAGE" > "$TEMP"
mv "$TEMP" "${QUEUE_DIR}/$(date +%s%N).msg"

# Sender ishlayaptimi tekshirish, yo'q bo'lsa ishga tushirish
if [ ! -f /var/log/sentinel/sentinel-sender.pid ] || ! kill -0 "$(cat /var/log/sentinel/sentinel-sender.pid 2>/dev/null)" 2>/dev/null; then
    /usr/local/bin/sentinel-sender.sh &
fi
