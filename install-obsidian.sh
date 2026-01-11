#!/usr/bin/env bash

APP_NAME="Obsidian"
USER_HOME="/home/eberth"

APPIMAGE_PATH="$USER_HOME/AppImages/Obsidian-1.10.6.AppImage"
ICON_SOURCE="$USER_HOME/AppImages/obsidian"
ICON_TARGET="$USER_HOME/.local/share/icons/hicolor/512x512/apps/obsidian.png"
DESKTOP_FILE="$USER_HOME/.local/share/applications/obsidian.desktop"

chmod +x "$APPIMAGE_PATH"

mkdir -p "$USER_HOME/.local/share/icons/hicolor/512x512/apps"
cp "$ICON_SOURCE" "$ICON_TARGET"

mkdir -p "$USER_HOME/.local/share/applications"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Obsidian
Comment=Knowledge base and Markdown editor
Exec=env ELECTRON_OZONE_PLATFORM_HINT=auto "$APPIMAGE_PATH"
Icon=obsidian
Terminal=false
Categories=Office;Utility;
EOF

update-desktop-database "$USER_HOME/.local/share/applications" 2>/dev/null
gtk-update-icon-cache "$USER_HOME/.local/share/icons" 2>/dev/null
