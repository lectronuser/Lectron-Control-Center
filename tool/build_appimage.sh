#!/usr/bin/env bash
# Packs the Linux release build into a single AppImage file.
#
#   tool/build_appimage.sh            build the app, then pack it
#   tool/build_appimage.sh --no-build pack the existing build/linux/x64/release/bundle
#
# Result: build/LectronControlCenter-<version>-x86_64.AppImage
set -euo pipefail

cd "$(dirname "$0")/.."
APP_ID="com.lectron.lectron_control"   # APPLICATION_ID in linux/CMakeLists.txt, also the window class
BINARY="lectron_control_center"
BUNDLE="build/linux/x64/release/bundle"
APPDIR="build/AppDir"
VERSION="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
OUTPUT="build/LectronControlCenter-${VERSION}-x86_64.AppImage"

if [[ "${1:-}" != "--no-build" ]]; then
  # the whole icon font: the icon tree shaker kept a stale subset between builds and new icons came out blank
  flutter build linux --release --no-tree-shake-icons
fi
[[ -x "$BUNDLE/$BINARY" ]] || { echo "No release bundle in $BUNDLE" >&2; exit 1; }

# The Flutter bundle must stay together: the executable looks for lib/ and data/ next to itself.
rm -rf "$APPDIR"
mkdir -p "$APPDIR"
cp -r "$BUNDLE"/. "$APPDIR/"
cp "linux/packaging/icons/hicolor/256x256/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
ln -s "$APP_ID.png" "$APPDIR/.DirIcon"

# the same launcher as tool/install_linux_desktop.sh installs; inside the AppImage it runs the bundled binary
sed "s|@EXEC@|$BINARY|" "linux/packaging/$APP_ID.desktop" > "$APPDIR/$APP_ID.desktop"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
# started from a snap (e.g. the VS Code terminal) the snap's GTK settings leak in and crash GTK at start
case "${GTK_PATH:-}${GTK_EXE_PREFIX:-}${GIO_MODULE_DIR:-}${GSETTINGS_SCHEMA_DIR:-}" in
  *snap*)
    unset GTK_PATH GTK_EXE_PREFIX GTK_IM_MODULE_FILE GIO_MODULE_DIR GSETTINGS_SCHEMA_DIR
    XDG_DATA_DIRS=/usr/local/share:/usr/share
    export XDG_DATA_DIRS
    ;;
esac
exec "$HERE/lectron_control_center" "$@"
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
