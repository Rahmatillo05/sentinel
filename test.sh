#!/bin/bash
# ============================================
# Sentinel — Test Script
# Sentinel o'rnatilganidan keyin ishlashini tekshirish
# ============================================
#
# Ishlatish:
#   sudo bash test.sh
#
# Bu script:
#   1. Fail2ban ishlayaptimi tekshiradi
#   2. Barcha jaillar faollashtirilganmi tekshiradi
#   3. Nginx sentinel log formatida yozayaptimi tekshiradi
#   4. Filterlar haqiqiy logni o'qiy olishini tekshiradi
#   5. Ban/unban ishlashini tekshiradi (xavfsiz test IP bilan)
#   6. Telegram xabar ishlashini tekshiradi
#   7. Whitelist to'g'ri sozlanganmi tekshiradi
#
# ============================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[OK]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }

echo ""
echo "============================================"
echo "  SENTINEL — Test"
echo "============================================"
echo ""

# Root tekshirish
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Xato: root huquqi kerak.${NC}"
    exit 1
fi

# ============================================
echo -e "${CYAN}[1/7] Fail2ban holati${NC}"
# ============================================

if systemctl is-active --quiet fail2ban 2>/dev/null; then
    pass "Fail2ban ishlayapti"
else
    fail "Fail2ban ISHLAMAYAPTI"
fi

if [ -f /etc/fail2ban/jail.d/sentinel-jails.conf ]; then
    pass "sentinel-jails.conf mavjud"
else
    fail "sentinel-jails.conf TOPILMADI"
fi

# ============================================
echo ""
echo -e "${CYAN}[2/7] Jaillar holati${NC}"
# ============================================

EXPECTED_JAILS="sentinel-scanner sentinel-exploit sentinel-botnet sentinel-ratelimit sentinel-bruteforce sentinel-recidive sshd"

for jail in $EXPECTED_JAILS; do
    STATUS=$(fail2ban-client status "$jail" 2>&1)
    if echo "$STATUS" | grep -q "Status for the jail"; then
        CURRENT=$(echo "$STATUS" | grep "Currently banned" | awk '{print $NF}')
        TOTAL=$(echo "$STATUS" | grep "Total banned" | awk '{print $NF}')
        pass "${jail} — faol (hozir: ${CURRENT}, jami: ${TOTAL} ban)"
    else
        fail "${jail} — ISHLAMAYAPTI"
    fi
done

# ============================================
echo ""
echo -e "${CYAN}[3/7] Nginx log format${NC}"
# ============================================

# sentinel log format mavjudmi?
if grep -rq "log_format sentinel" /etc/nginx/ 2>/dev/null; then
    pass "Nginx'da sentinel log_format topildi"
else
    if grep -rq "sentinel-log-format.conf" /etc/nginx/ 2>/dev/null; then
        pass "sentinel-log-format.conf include qilingan"
    else
        fail "Nginx'da sentinel log format TOPILMADI — filterlar ishlamaydi!"
    fi
fi

# sentinel-security.conf (map + deny)
if grep -rq "sentinel_blocked\|sentinel-security.conf\|sentinel-deny.map" /etc/nginx/ 2>/dev/null; then
    pass "Nginx IP bloklash konfiguratsiyasi topildi"
else
    fail "Nginx IP bloklash SOZLANMAGAN — ban ishlaydi lekin so'rovlar bloklanmaydi"
fi

# deny map fayl
if [ -f /etc/nginx/sentinel-deny.map ]; then
    pass "sentinel-deny.map mavjud"
else
    fail "sentinel-deny.map TOPILMADI"
fi

# Loglar sentinel formatida yozilayaptimi tekshirish
SAMPLE_LOG=""
for logfile in /var/log/nginx/*_access.log /var/log/nginx/access.log; do
    if [ -f "$logfile" ] && [ -s "$logfile" ]; then
        SAMPLE_LOG=$(tail -1 "$logfile" 2>/dev/null)
        break
    fi
done

if [ -n "$SAMPLE_LOG" ]; then
    if echo "$SAMPLE_LOG" | grep -q '\[Client '; then
        pass "Log format to'g'ri: sentinel formatida yozilayapti"
    else
        fail "Log format NOTO'G'RI — sentinel formatida emas!"
        echo -e "    Hozirgi: ${SAMPLE_LOG:0:100}..."
        echo "    Kutilgan: [vaqt] status method \"uri\" [Client IP] \"user-agent\""
    fi
else
    warn "Log fayllar bo'sh — hali hech qanday trafik yo'q"
fi

# ============================================
echo ""
echo -e "${CYAN}[4/7] Filter regex testi${NC}"
# ============================================

# Test log yaratish
TEST_LOG=$(mktemp)
cat > "$TEST_LOG" << 'TESTDATA'
[24/Mar/2026:10:15:30 +0500] 404 GET "/.git/config" [Client 198.51.100.1] "Mozilla/5.0"
[24/Mar/2026:10:15:31 +0500] 404 GET "/.env" [Client 198.51.100.2] "Mozilla/5.0"
[24/Mar/2026:10:15:32 +0500] 404 GET "/?id=1 UNION SELECT 1,2,3" [Client 198.51.100.3] "sqlmap/1.5"
[24/Mar/2026:10:15:33 +0500] 404 GET "/../../etc/passwd" [Client 198.51.100.4] "Mozilla/5.0"
[24/Mar/2026:10:15:34 +0500] 200 GET "/" [Client 198.51.100.5] "Googlebot/2.1"
[24/Mar/2026:10:15:35 +0500] 404 POST "/login" [Client 198.51.100.6] "Mozilla/5.0"
[24/Mar/2026:10:15:36 +0500] 405 PROPFIND "/" [Client 198.51.100.7] "-"
[24/Mar/2026:10:15:37 +0500] 404 GET "/actuator/env" [Client 198.51.100.8] "python-httpx/0.27.0"
TESTDATA

# Har bir filtrni test qilish
for filter in sentinel-scanner sentinel-exploit sentinel-botnet sentinel-ratelimit sentinel-bruteforce; do
    if [ -f "/etc/fail2ban/filter.d/${filter}.conf" ]; then
        RESULT=$(fail2ban-regex "$TEST_LOG" "/etc/fail2ban/filter.d/${filter}.conf" 2>&1)
        MATCHED=$(echo "$RESULT" | grep "^Lines: " | head -1)
        MATCH_COUNT=$(echo "$RESULT" | grep -oP 'matched:\s+\K[0-9]+' 2>/dev/null || echo "$RESULT" | grep "matched:" | awk '{print $NF}')

        if [ -n "$MATCH_COUNT" ] && [ "$MATCH_COUNT" -gt 0 ] 2>/dev/null; then
            pass "${filter} — ${MATCH_COUNT} ta mos keldi"
        else
            # Ba'zi filterlar test dataga mos kelmasligi mumkin
            case "$filter" in
                sentinel-bruteforce)
                    # Faqat 1 ta POST /login bor — bu normal
                    warn "${filter} — kam match (bu test data uchun normal bo'lishi mumkin)"
                    ;;
                *)
                    fail "${filter} — HECH NARSA MOS KELMADI (regex xato bo'lishi mumkin)"
                    ;;
            esac
        fi
    else
        fail "${filter} — filter fayl TOPILMADI"
    fi
done

rm -f "$TEST_LOG"

# ============================================
echo ""
echo -e "${CYAN}[5/7] Ban/Unban testi${NC}"
# ============================================

# Test IP (RFC 5737 — documentation uchun ajratilgan, real emas)
TEST_IP="198.51.100.254"

# Ban test
echo -n "  Ban test ($TEST_IP)... "
fail2ban-client set sentinel-scanner banip "$TEST_IP" 2>/dev/null
sleep 1

if fail2ban-client status sentinel-scanner 2>/dev/null | grep -q "$TEST_IP"; then
    echo -e "${GREEN}OK${NC}"
    PASS=$((PASS+1))

    # Nginx deny map tekshirish
    if grep -q "$TEST_IP" /etc/nginx/sentinel-deny.map 2>/dev/null; then
        pass "IP deny map'ga yozildi"
    else
        warn "IP deny map'ga yozilMADI (reload timer kutayotgan bo'lishi mumkin)"
    fi
else
    echo -e "${RED}FAIL${NC}"
    FAIL=$((FAIL+1))
fi

# Unban test
echo -n "  Unban test ($TEST_IP)... "
fail2ban-client set sentinel-scanner unbanip "$TEST_IP" 2>/dev/null
sleep 1

if ! fail2ban-client status sentinel-scanner 2>/dev/null | grep -q "$TEST_IP"; then
    echo -e "${GREEN}OK${NC}"
    PASS=$((PASS+1))
else
    echo -e "${RED}FAIL${NC}"
    FAIL=$((FAIL+1))
fi

# ============================================
echo ""
echo -e "${CYAN}[6/7] Telegram testi${NC}"
# ============================================

if [ -f /etc/sentinel/sentinel.conf ]; then
    source /etc/sentinel/sentinel.conf
    RESPONSE=$(curl -s --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        pass "Telegram bot ulanish ishlayapti"

        # Test xabar
        TEST_RESULT=$(curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            --data-urlencode "text=SENTINEL TEST — bu test xabar, e'tibor bermang." 2>/dev/null)
        HTTP_CODE=$(echo "$TEST_RESULT" | tail -1)
        if [ "$HTTP_CODE" = "200" ]; then
            pass "Telegram test xabar yuborildi"
        else
            fail "Telegram xabar yuborib bo'lmadi (HTTP $HTTP_CODE)"
        fi
    else
        fail "Telegram bot ULANMADI — token tekshiring"
    fi
else
    fail "sentinel.conf TOPILMADI"
fi

# ============================================
echo ""
echo -e "${CYAN}[7/7] Whitelist va xavfsizlik${NC}"
# ============================================

# Config huquqlari
CONF_PERMS=$(stat -c "%a" /etc/sentinel/sentinel.conf 2>/dev/null || stat -f "%Lp" /etc/sentinel/sentinel.conf 2>/dev/null)
if [ "$CONF_PERMS" = "600" ]; then
    pass "sentinel.conf huquqlari to'g'ri (600)"
else
    fail "sentinel.conf huquqlari NOTO'G'RI ($CONF_PERMS) — 600 bo'lishi kerak"
fi

# Whitelist fayllar
if [ -f /etc/sentinel/whitelist.conf ]; then
    WL_COUNT=$(grep -v '^#' /etc/sentinel/whitelist.conf | grep -v '^$' | wc -l | tr -d ' ')
    pass "whitelist.conf mavjud (${WL_COUNT} ta yozuv)"
else
    warn "whitelist.conf topilmadi"
fi

# Cron joblar
if crontab -l 2>/dev/null | grep -q "SENTINEL_CRON"; then
    CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "SENTINEL_CRON")
    pass "Cron joblar mavjud (${CRON_COUNT} ta)"
else
    warn "Cron joblar topilmadi"
fi

# Logrotate
if [ -f /etc/logrotate.d/sentinel ]; then
    pass "Logrotate konfiguratsiya mavjud"
else
    warn "Logrotate konfiguratsiya topilmadi"
fi

# Reload timer
if [ -f /usr/local/bin/sentinel-reload-timer.sh ]; then
    pass "Reload timer script mavjud"
else
    warn "Reload timer script topilmadi"
fi

# ============================================
# NATIJA
# ============================================
echo ""
echo "============================================"
TOTAL=$((PASS+FAIL+WARN))
echo -e "  NATIJA: ${GREEN}${PASS} OK${NC} / ${RED}${FAIL} FAIL${NC} / ${YELLOW}${WARN} WARN${NC} (jami: ${TOTAL})"

if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}Sentinel to'liq ishlayapti!${NC}"
elif [ "$FAIL" -le 2 ]; then
    echo -e "  ${YELLOW}Sentinel ishlayapti, lekin ba'zi muammolar bor.${NC}"
else
    echo -e "  ${RED}Sentinel to'liq ishlamayapti. Yuqoridagi xatolarni tuzating.${NC}"
fi
echo "============================================"
echo ""

# ============================================
# QOIDA: Haqiqiy hujumni simulyatsiya qilish
# ============================================
echo -e "${CYAN}Haqiqiy hujumni simulyatsiya qilish uchun:${NC}"
echo ""
echo "  # Boshqa kompyuter yoki telefondan (o'z IP'ingizdan EMAS):"
echo ""
echo "  # Scanner test (3 ta so'rov kerak → ban):"
echo "  curl -k https://YOUR_DOMAIN/.env"
echo "  curl -k https://YOUR_DOMAIN/.git/config"
echo "  curl -k https://YOUR_DOMAIN/wp-admin/"
echo ""
echo "  # Exploit test (1 ta so'rov yetarli → ban):"
echo "  curl -k 'https://YOUR_DOMAIN/?id=1+UNION+SELECT+1,2,3'"
echo ""
echo "  # Botnet test (1 ta so'rov yetarli → ban):"
echo "  curl -k -A 'sqlmap/1.5' https://YOUR_DOMAIN/"
echo ""
echo "  # Keyin tekshiring:"
echo "  fail2ban-client status sentinel-scanner"
echo "  fail2ban-client status sentinel-exploit"
echo "  cat /etc/nginx/sentinel-deny.map"
echo ""
echo -e "  ${RED}DIQQAT: O'z IP'ingizdan test QILMANG — whitelistda bo'lmasa bloklanasiz!${NC}"
echo ""
echo "============================================"
