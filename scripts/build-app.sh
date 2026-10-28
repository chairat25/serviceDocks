#!/usr/bin/env bash
# Builds build/ServiceDock.app (ad-hoc signed).
# Usage: scripts/build-app.sh [--universal] [--dmg] [--install]
#   --universal  build for Apple Silicon and Intel (slower)
#   --dmg        also create build/ServiceDock-<version>.dmg and .zip for distribution
#   --install    copy the app to /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
APP_NAME="ServiceDock"
APP="$ROOT/build/$APP_NAME.app"

UNIVERSAL=false
DMG=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=true ;;
        --dmg) DMG=true ;;
        --install) INSTALL=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

cd "$ROOT"
ARCH_FLAGS=()
if $UNIVERSAL; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "→ Building release binary ${ARCH_FLAGS[*]:-(native)}"
swift build -c release --product ServiceDock ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "→ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ServiceDock" "$APP/Contents/MacOS/ServiceDock"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" scripts/Info.plist > "$APP/Contents/Info.plist"

echo "→ Rendering icon"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "→ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if $DMG; then
    echo "→ Packaging DMG and ZIP"
    STAGE="$ROOT/build/dmg-stage"
    DMG_PATH="$ROOT/build/ServiceDock-$VERSION.dmg"
    ZIP_PATH="$ROOT/build/ServiceDock-$VERSION.zip"
    rm -rf "$STAGE" "$DMG_PATH" "$ZIP_PATH"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
    rm -rf "$STAGE"
    (cd "$ROOT/build" && ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH")
    (cd "$ROOT/build" && shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "ServiceDock-$VERSION.sha256")
    echo "  $DMG_PATH"
    echo "  $ZIP_PATH"
fi

if $INSTALL; then
    echo "→ Installing to /Applications"
    pkill -x ServiceDock 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    APP="/Applications/$APP_NAME.app"
fi

echo "✓ Built: $APP"
echo "  Open with: open \"$APP\""
