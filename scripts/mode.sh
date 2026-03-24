#!/bin/bash
# ============================================
# Sentinel — Rejim almashtirish
# Joylashuv: /usr/local/bin/sentinel-mode.sh
# ============================================
# Ishlatish:
#   sentinel-mode.sh              — hozirgi rejim
#   sentinel-mode.sh direct       — to'g'ridan-to'g'ri
#   sentinel-mode.sh monitor      — faqat monitoring
# ============================================

CONF_FILE="/etc/sentinel/sentinel.conf"

if [ "$EUID" -ne 0 ]; then
    echo "Xato: root huquqi kerak."
    exit 1
fi

if [ ! -f "$CONF_FILE" ]; then
    echo "Xato: Sentinel o'rnatilmagan."
    exit 1
fi

get_conf() { grep "^${1}=" "$CONF_FILE" | head -1 | cut -d'"' -f2; }

CURRENT=$(get_conf ARCHITECTURE)

if [ -z "$1" ]; then
    echo "Rejim: ${CURRENT}"
    exit 0
fi

if [ "$1" = "$CURRENT" ]; then
    echo "Allaqachon ${1} rejimida."
    exit 0
fi

case "$1" in
    direct|proxy|monitor)
        sed -i "s|^ARCHITECTURE=.*|ARCHITECTURE=\"${1}\"|" "$CONF_FILE"
        echo "Rejim: ${CURRENT} → ${1}"
        echo ""
        echo "Qo'llash uchun qayta install kerak:"
        echo "  curl -sSL https://raw.githubusercontent.com/Rahmatillo05/sentinel/main/install-remote.sh -o /tmp/sentinel-setup.sh"
        echo "  sudo bash /tmp/sentinel-setup.sh"
        echo ""
        echo "Install oldingi sozlamalarni (token, chat_id) saqlab qoladi."
        ;;
    *)
        echo "Ishlatish: $0 {direct|proxy|monitor}"
        ;;
esac
