#!/bin/bash
# Builds NaturalScrollingAuto and assembles a runnable .app bundle.
#
#   ./build-app.sh            # build into ./build/NaturalScrollingAuto.app
#   ./build-app.sh --install  # also copy to /Applications and launch
#
# Requires only the Xcode Command Line Tools (Swift toolchain) — no full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NaturalScrollingAuto"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# App icon: if a source image exists (Resources/AppIcon.png or .jpg, ideally
# 1024x1024), generate a multi-resolution AppIcon.icns and bundle it.
# Otherwise the app uses the generic macOS app icon.
ICON_SRC=""
for candidate in Resources/AppIcon.png Resources/AppIcon.jpg Resources/AppIcon.jpeg; do
    if [[ -f "$candidate" ]]; then ICON_SRC="$candidate"; break; fi
done
if [[ -n "$ICON_SRC" ]]; then
    echo "==> Generating app icon from $ICON_SRC"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -s format png -z $size $size             "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png"      >/dev/null
        sips -s format png -z $((size*2)) $((size*2)) "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc code signing (needed for the login-item API)"
codesign --force --sign - "$APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo "==> Launching"
    open "/Applications/$APP_NAME.app"
    echo "Done. Look for the menu-bar icon. Enable 'Open at Login' from its menu."
else
    echo "Done: $APP_BUNDLE"
    echo "Run it with:  open \"$APP_BUNDLE\""
    echo "Or install + launch with:  ./build-app.sh --install"
fi
