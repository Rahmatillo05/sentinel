#!/bin/bash
# ============================================
# Sentinel — Nginx Reload Timer
# Joylashuv: /usr/local/bin/sentinel-reload-timer.sh
# ============================================
# Har 10 sekundda tekshiradi: agar yangi ban/unban bo'lgan bo'lsa
# Nginx'ni bir marta reload qiladi.
# Bu ko'p ban bo'lganda ham ortiqcha reload'dan himoya qiladi.
# ============================================

RELOAD_FLAG="/tmp/sentinel-needs-reload"
PID_FILE="/tmp/sentinel-reload-timer.pid"
LOG_FILE="/var/log/sentinel/sentinel.log"
INTERVAL=10

log() {
    echo "[SENTINEL] $(date '+%Y-%m-%d %H:%M:%S') reload-timer: $1" >> "$LOG_FILE" 2>/dev/null
}

case "$1" in
    start)
        # Agar allaqachon ishlayotgan bo'lsa — to'xtatish
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            log "Timer allaqachon ishlayapti (PID: $(cat "$PID_FILE"))"
            exit 0
        fi

        log "Timer ishga tushdi (interval: ${INTERVAL}s)"
        echo $$ > "$PID_FILE"

        while true; do
            sleep "$INTERVAL"

            if [ -f "$RELOAD_FLAG" ]; then
                rm -f "$RELOAD_FLAG"
                if nginx -t -q 2>/dev/null; then
                    nginx -s reload 2>/dev/null
                    log "Nginx reload qilindi"
                else
                    log "XATO: Nginx config test muvaffaqiyatsiz — reload bekor"
                fi
            fi
        done
        ;;

    stop)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID" 2>/dev/null
                log "Timer to'xtatildi (PID: $PID)"
            fi
            rm -f "$PID_FILE" "$RELOAD_FLAG"
        fi
        ;;

    *)
        echo "Ishlatish: $0 {start|stop}"
        exit 1
        ;;
esac
