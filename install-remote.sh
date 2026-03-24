#!/bin/bash
# ============================================
# Sentinel — Tezkor O'rnatish (Remote)
# ============================================
#
# Ishlatish:
#   curl -sSL https://raw.githubusercontent.com/OksSecurity/sentinel/main/install-remote.sh | sudo bash
#
# yoki:
#   wget -qO- https://raw.githubusercontent.com/OksSecurity/sentinel/main/install-remote.sh | sudo bash
#
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Root tekshirish
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Xato: root huquqi kerak. sudo bilan ishga tushiring.${NC}"
    exit 1
fi

# git yoki curl tekshirish
if ! command -v git &>/dev/null && ! command -v curl &>/dev/null; then
    echo -e "${RED}Xato: git yoki curl kerak.${NC}"
    exit 1
fi

INSTALL_DIR="/tmp/sentinel-install"
REPO_URL="https://github.com/OksSecurity/sentinel.git"

# Eski install papkani tozalash
rm -rf "$INSTALL_DIR"

echo ""
echo "Sentinel yuklanmoqda..."

if command -v git &>/dev/null; then
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null
else
    # git yo'q bo'lsa — tarball yuklab olish
    mkdir -p "$INSTALL_DIR"
    curl -sSL "https://github.com/OksSecurity/sentinel/archive/main.tar.gz" \
        | tar xz -C "$INSTALL_DIR" --strip-components=1
fi

if [ ! -f "${INSTALL_DIR}/install.sh" ]; then
    echo -e "${RED}Xato: install.sh topilmadi.${NC}"
    rm -rf "$INSTALL_DIR"
    exit 1
fi

echo -e "${GREEN}Yuklandi.${NC}"
echo ""

# Install ishga tushirish
cd "$INSTALL_DIR"
bash install.sh

# Tozalash
rm -rf "$INSTALL_DIR"
