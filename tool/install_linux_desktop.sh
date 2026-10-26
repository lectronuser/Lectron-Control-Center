#!/usr/bin/env bash
# Installs the launcher and the icons for the current user, so GNOME / KDE show the Lectron "L" in the dock and
# the app grid. Under Wayland the shell takes the icon from the .desktop file named after the application ID,
# not from the window, so this is needed for development builds too.
#
#   tool/install_linux_desktop.sh                    point the launcher at the release build if there is one, else debug
#   tool/install_linux_desktop.sh --exec FILE        point it at FILE, e.g. ~/App/LectronControlCenter.AppImage
#   tool/install_linux_desktop.sh --remove           take the launcher and the icons away again
set -euo pipefail

cd "$(dirname "$0")/.."
APP_ID="com.lectron.lectron_control"   # APPLICATION_ID in linux/CMakeLists.txt
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

if [[ "${1:-}" == "--remove" ]]; then
  rm -f "$DATA/applications/$APP_ID.desktop"
  find "$DATA/icons/hicolor" -name "$APP_ID.png" -delete 2>/dev/null || true
  echo "Removed the launcher and the icons"
  exit 0
fi

EXEC=""
if [[ "${1:-}" == "--exec" ]]; then
  EXEC="$(readlink -f "${2:?--exec needs a file}")"
  [[ -x "$EXEC" ]] || { echo "$EXEC is not an executable file" >&2; exit 1; }
fi
for mode in release debug; do
  [[ -n "$EXEC" ]] && break
  candidate="$PWD/build/linux/x64/$mode/bundle/lectron_control_center"
  if [[ -x "$candidate" ]]; then EXEC="$candidate"; break; fi
done
if [[ -z "$EXEC" ]]; then
  echo "No build found: run 'flutter build linux' first (the icon still shows for 'flutter run')" >&2
  EXEC="lectron_control_center"
fi

for dir in linux/packaging/icons/hicolor/*/apps; do
  size="$(basename "$(dirname "$dir")")"
  install -Dm644 "$dir/$APP_ID.png" "$DATA/icons/hicolor/$size/apps/$APP_ID.png"
done
mkdir -p "$DATA/applications"
sed "s|@EXEC@|$EXEC|" "linux/packaging/$APP_ID.desktop" > "$DATA/applications/$APP_ID.desktop"

gtk-update-icon-cache -q -t "$DATA/icons/hicolor" 2>/dev/null || true
update-desktop-database -q "$DATA/applications" 2>/dev/null || true
echo "Installed $APP_ID.desktop (Exec=$EXEC) and the icons in $DATA"
