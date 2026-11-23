#!/usr/bin/env bash
# Instala SINTONÍA para tu usuario (sin permisos de administrador):
#   bash instalar-linux.sh [Sintonia-x86_64.AppImage]
# Queda en ~/.local/bin/Sintonia y aparece en el menú de aplicaciones.
set -e
SRC="${1:-$(dirname "$0")/Sintonia-x86_64.AppImage}"
mkdir -p ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/512x512/apps
install -m 755 "$SRC" ~/.local/bin/Sintonia
cd /tmp && ~/.local/bin/Sintonia --appimage-extract sintonia.png >/dev/null 2>&1 || true
[ -f /tmp/squashfs-root/sintonia.png ] && cp /tmp/squashfs-root/sintonia.png ~/.local/share/icons/hicolor/512x512/apps/sintonia.png
rm -rf /tmp/squashfs-root
cat > ~/.local/share/applications/sintonia.desktop <<DESK
[Desktop Entry]
Type=Application
Name=Sintonía
GenericName=Películas y series
Comment=Películas y series en una sola pantalla
Exec=$HOME/.local/bin/Sintonia
Icon=sintonia
Categories=AudioVideo;Video;Player;TV;
StartupWMClass=sintonia
Terminal=false
DESK
update-desktop-database ~/.local/share/applications >/dev/null 2>&1 || true
echo "Listo: SINTONÍA está en el menú de aplicaciones."
