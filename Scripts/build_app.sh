#!/usr/bin/env bash
# Builds Human RAM + its WidgetKit extension and assembles a signed .app bundle.
# For the original widget-free, ad-hoc build use ./Scripts/build_app_adhoc.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
APP_NAME="Human RAM"
APP_DIR="$ROOT/build/$APP_NAME.app"
WIDGET_NAME="HumanRAMWidget"
SIGN_ID="${HRAM_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
    echo "error: set HRAM_SIGN_ID to your codesigning identity, e.g." >&2
    echo "  export HRAM_SIGN_ID='Apple Development: you@example.com (XXXXXXXXXX)'" >&2
    echo "list identities with: security find-identity -v -p codesigning" >&2
    exit 1
fi

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_PATH/HumanRAM"
WIDGET_BIN="$BIN_PATH/HumanRAMWidget"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/HumanRAM"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [ -f "$ROOT/Resources/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Resources/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> assembling widget extension"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/$WIDGET_NAME.appex"
mkdir -p "$WIDGET_DIR/Contents/MacOS"
cp "$WIDGET_BIN" "$WIDGET_DIR/Contents/MacOS/$WIDGET_NAME"
cp "$ROOT/Resources/WidgetInfo.plist" "$WIDGET_DIR/Contents/Info.plist"
printf 'XPC!' > "$WIDGET_DIR/Contents/PkgInfo"

echo "==> signing widget extension ($SIGN_ID)"
codesign --force --sign "$SIGN_ID" \
    --entitlements "$ROOT/Resources/HumanRAMWidget.entitlements" \
    "$WIDGET_DIR"

echo "==> signing app ($SIGN_ID)"
codesign --force --sign "$SIGN_ID" \
    --entitlements "$ROOT/Resources/HumanRAM.entitlements" \
    "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "==> done: $APP_DIR"
echo "    run with: open \"$APP_DIR\""
echo "    fallback (no widget): ./Scripts/build_app_adhoc.sh"
