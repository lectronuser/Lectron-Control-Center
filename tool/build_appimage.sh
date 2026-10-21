#!/usr/bin/env bash
# Packs the Linux release build into a single AppImage file.
#
#   tool/build_appimage.sh            build the app, then pack it
#   tool/build_appimage.sh --no-build pack the existing build/linux/x64/release/bundle
#
# Result: build/BoardTest-<version>-x86_64.AppImage
set -euo pipefail

cd "$(dirname "$0")/.."
APP_ID="com.lectron.lectron_control"   # APPLICATION_ID in linux/CMakeLists.txt, also the window class
BINARY="lectron_control"
BUNDLE="build/linux/x64/release/bundle"
APPDIR="build/AppDir"
VERSION="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
OUTPUT="build/BoardTest-${VERSION}-x86_64.AppImage"

if [[ "${1:-}" != "--no-build" ]]; then
  flutter build linux --release
fi
[[ -x "$BUNDLE/$BINARY" ]] || { echo "No release bundle in $BUNDLE" >&2; exit 1; }

# The Flutter bundle must stay together: the executable looks for lib/ and data/ next to itself.
rm -rf "$APPDIR"
mkdir -p "$APPDIR"
cp -r "$BUNDLE"/. "$APPDIR/"
cp assets/icon/app_icon.png "$APPDIR/$APP_ID.png"
ln -s "$APP_ID.png" "$APPDIR/.DirIcon"

cat > "$APPDIR/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Board Test
GenericName=Lectron Pi5-H7 board test
Comment=Board test, configuration and PDF test report for the Lectron Pi5-H7
Exec=$BINARY
Icon=$APP_ID
StartupWMClass=$APP_ID
Categories=Development;Electronics;
Terminal=false
DESKTOP

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/lectron_control" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# appimagetool from PATH, or a copy kept in build/
TOOL="$(command -v appimagetool || true)"
if [[ -z "$TOOL" ]]; then
  TOOL="build/appimagetool-x86_64.AppImage"
  if [[ ! -x "$TOOL" ]]; then
    echo "Downloading appimagetool..."
    curl -fL -o "$TOOL" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$TOOL"
  fi
fi

# --appimage-extract-and-run: works without FUSE (containers, CI)
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUTPUT"
echo "Created $OUTPUT"
