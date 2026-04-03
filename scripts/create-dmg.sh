#!/bin/bash
# create-dmg.sh — Creates a styled DMG installer for CroakVPN
# Used in GitHub Actions after building the .app
set -euo pipefail

APP_PATH="$1"          # Path to CroakVPN.app
FIX_PATH="$2"          # Path to FIX.command
BG_PATH="$3"           # Path to background.png
OUTPUT_DMG="$4"        # Output DMG path

VOLUME_NAME="CroakVPN"
DMG_TEMP="pack.temp.dmg"
DMG_SIZE="150m"

echo "[INFO] Creating DMG..."

# Create temporary directory with DMG contents
STAGING=$(mktemp -d)
cp -a "$APP_PATH" "$STAGING/CroakVPN.app"
cp "$FIX_PATH" "$STAGING/FIX.command"
chmod +x "$STAGING/FIX.command"
ln -s /Applications "$STAGING/Applications"

# Create temporary DMG (writable)
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size "$DMG_SIZE" "$DMG_TEMP"

# Mount it
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" | \
    grep -E '^\S+\s+Apple_HFS' | sed 's/^.*\t//' | head -1)

# Wait for mount
sleep 2

# Copy background
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_PATH" "$MOUNT_DIR/.background/background.png"

# Use AppleScript to set DMG window appearance
echo "[INFO] Styling DMG window..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set background picture of viewOptions to file ".background:background.png"
        
        -- Position: CroakVPN.app on the left
        set position of item "CroakVPN.app" of container window to {150, 180}
        -- Position: Applications symlink on the right
        set position of item "Applications" of container window to {450, 180}
        -- Position: FIX.command at the bottom center
        set position of item "FIX.command" of container window to {300, 340}
        
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

# Set permissions
chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true

# Unmount
sync
hdiutil detach "$MOUNT_DIR" -force

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"

# Cleanup
rm -f "$DMG_TEMP"
rm -rf "$STAGING"

echo "[OK] DMG created: $OUTPUT_DMG"
