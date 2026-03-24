#!/bin/bash
# ============================================
# Sentinel — Tezkor O'rnatish (Remote)
# ============================================
#
# Ishlatish (ikkala variant bir xil):
#
#   curl -sSL https://raw.githubusercontent.com/Rahmatillo05/sentinel/main/install-remote.sh -o /tmp/sentinel-setup.sh && sudo bash /tmp/sentinel-setup.sh
#
#   wget -qO /tmp/sentinel-setup.sh https://raw.githubusercontent.com/Rahmatillo05/sentinel/main/install-remote.sh && sudo bash /tmp/sentinel-setup.sh
#
# MUHIM: "curl ... | sudo bash" ISHLAMAYDI — chunki install
# interaktiv savol so'raydi. Avval yuklab, keyin ishga tushiring.
#
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="Rahmatillo05/sentinel"
INSTALL_DIR="/tmp/sentinel-install"
TARBALL_URL="https://github.com/${REPO}/archive/main.tar.gz"
REPO_URL="https://github.com/${REPO}.git"

# Root tekshirish
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Xato: root huquqi kerak. sudo bilan ishga tushiring.${NC}"
    exit 1
fi

# Eski install papkani tozalash
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

echo ""
echo "Sentinel yuklanmoqda..."

# Yuklash: git → curl → wget (qaysi biri bor bo'lsa)
if command -v git &>/dev/null; then
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null
elif command -v curl &>/dev/null; then
    curl -sSL "$TARBALL_URL" | tar xz -C "$INSTALL_DIR" --strip-components=1
elif command -v wget &>/dev/null; then
    wget -qO- "$TARBALL_URL" | tar xz -C "$INSTALL_DIR" --strip-components=1
else
    echo -e "${RED}Xato: git, curl yoki wget kerak. Hech biri topilmadi.${NC}"
    exit 1
fi

if [ ! -f "${INSTALL_DIR}/install.sh" ]; then
    echo -e "${RED}Xato: yuklab olib bo'lmadi.${NC}"
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
