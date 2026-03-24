#!/bin/bash
# ============================================
# Sentinel — Kunlik Hisobot
# Joylashuv: /usr/local/bin/sentinel-daily-report.sh
# Cron: har kuni soat 08:00 (0 8 * * *)
# ============================================

CONF_FILE="/etc/sentinel/sentinel.conf"
if [ ! -f "$CONF_FILE" ]; then
    exit 1
fi
source "$CONF_FILE"

API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d')
YESTERDAY=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d')

# --- Statistika yig'ish ---

# Jami ban soni (kechagi fail2ban logdan)
TOTAL_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep -c "Ban" || echo "0")

# Jail bo'yicha taqsimot
SCANNER_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "sentinel-scanner" | grep -c "Ban" 2>/dev/null || echo "0")
EXPLOIT_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "sentinel-exploit" | grep -c "Ban" 2>/dev/null || echo "0")
BOTNET_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "sentinel-botnet" | grep -c "Ban" 2>/dev/null || echo "0")
RATE_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "sentinel-ratelimit" | grep -c "Ban" 2>/dev/null || echo "0")
BRUTE_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "sentinel-bruteforce" | grep -c "Ban" 2>/dev/null || echo "0")
SSH_BANS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "sshd" | grep -c "Ban" 2>/dev/null || echo "0")

# Hozir aktiv banlar
ACTIVE_BANS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//' | tr ',' '\n' | while read jail; do
    fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}'
done | awk '{sum+=$1}END{print sum+0}')

# Top 5 IP
TOP_IPS=$(grep "$YESTERDAY" /var/log/fail2ban.log 2>/dev/null | grep "Ban" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -5 | awk '{printf "  %s (%s ban)\n", $2, $1}')

# --- Xabar yuborish ---
MESSAGE="SENTINEL KUNLIK HISOBOT
${DATE}

Server: ${HOSTNAME}

Jami ban: ${TOTAL_BANS}
  Scanner:     ${SCANNER_BANS}
  Exploit:     ${EXPLOIT_BANS}
  Botnet:      ${BOTNET_BANS}
  Rate limit:  ${RATE_BANS}
  Brute force: ${BRUTE_BANS}
  SSH:         ${SSH_BANS}

Hozir aktiv: ${ACTIVE_BANS} ta ban

Top IP'lar:
${TOP_IPS:-  hech kim banlanmagan}"

curl -s -X POST "${API_URL}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "disable_web_page_preview=true" \
    --data-urlencode "text=${MESSAGE}" \
    > /dev/null 2>&1

echo "[SENTINEL] $(date) Kunlik hisobot yuborildi" >> /var/log/sentinel/sentinel.log
