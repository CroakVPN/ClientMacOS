#!/bin/bash
# ============================================================
# CroakVPN FIX — Настройка разрешений для macOS
# Запустите этот скрипт ОДИН РАЗ после установки CroakVPN
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       CroakVPN — Настройка macOS         ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. Найти CroakVPN.app
APP_PATH=""
for candidate in \
    "/Applications/CroakVPN.app" \
    "$HOME/Applications/CroakVPN.app" \
    "$HOME/Downloads/CroakVPN.app" \
    "$HOME/Desktop/CroakVPN.app"; do
    if [ -d "$candidate" ]; then
        APP_PATH="$candidate"
        break
    fi
done

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}[!] CroakVPN.app не найден.${NC}"
    echo "    Перетащите CroakVPN.app в /Applications и запустите скрипт снова."
    exit 1
fi

echo -e "${GREEN}[✓]${NC} Найден: $APP_PATH"

# 2. Снять карантин (Gatekeeper)
echo -e "${YELLOW}[…]${NC} Снимаем карантин Gatekeeper..."
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
echo -e "${GREEN}[✓]${NC} Карантин снят"

# 3. Найти sing-box внутри .app
SINGBOX=""
for sb in \
    "$APP_PATH/Contents/Resources/sing-box" \
    "$APP_PATH/Contents/MacOS/sing-box"; do
    if [ -f "$sb" ]; then
        SINGBOX="$sb"
        break
    fi
done

if [ -z "$SINGBOX" ]; then
    echo -e "${RED}[!] sing-box не найден внутри $APP_PATH${NC}"
    echo "    Приложение повреждено. Скачайте заново."
    exit 1
fi

echo -e "${GREEN}[✓]${NC} sing-box: $SINGBOX"

# 4. Сделать sing-box исполняемым
chmod +x "$SINGBOX"
xattr -dr com.apple.quarantine "$SINGBOX" 2>/dev/null || true
echo -e "${GREEN}[✓]${NC} sing-box исполняемый, карантин снят"

# 5. Настроить sudoers (sing-box требует root для TUN)
echo ""
echo -e "${YELLOW}[…]${NC} Настройка sudo для sing-box (потребуется пароль)..."
echo "    Это нужно один раз — после этого VPN будет работать без пароля."
echo ""

SUDOERS_FILE="/etc/sudoers.d/croakvpn"
USER_NAME=$(whoami)
SUDOERS_CONTENT="Defaults:${USER_NAME} !requiretty
${USER_NAME} ALL=(ALL) NOPASSWD: ${SINGBOX}, /usr/bin/pkill"

# Записать во временный файл
TMP_SUDOERS=$(mktemp)
echo "$SUDOERS_CONTENT" > "$TMP_SUDOERS"

# Проверить синтаксис через visudo
if ! sudo visudo -c -f "$TMP_SUDOERS" 2>/dev/null; then
    echo -e "${RED}[!] Ошибка синтаксиса sudoers. Пропускаем.${NC}"
    rm -f "$TMP_SUDOERS"
else
    sudo cp "$TMP_SUDOERS" "$SUDOERS_FILE"
    sudo chmod 440 "$SUDOERS_FILE"
    sudo chown root:wheel "$SUDOERS_FILE"
    rm -f "$TMP_SUDOERS"
    echo -e "${GREEN}[✓]${NC} sudo настроен для sing-box"
fi

# 6. Проверка
echo ""
echo -e "${YELLOW}[…]${NC} Проверяем..."
if sudo -n "$SINGBOX" version 2>/dev/null | grep -q "sing-box"; then
    SB_VERSION=$(sudo -n "$SINGBOX" version 2>/dev/null | head -1)
    echo -e "${GREEN}[✓]${NC} sing-box работает: $SB_VERSION"
else
    echo -e "${YELLOW}[!]${NC} sing-box не отвечает — возможно потребуется перезапуск терминала"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           Готово! Запустите CroakVPN      ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Если CroakVPN уже открыт — закройте и откройте заново,"
echo "затем обновите подписку в настройках."
echo ""
