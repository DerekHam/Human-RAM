#!/usr/bin/env bash
# Builds the shareable, app-only variant of Human RAM.
# It compiles with -DHRAM_SHAREABLE, uses its own bundle id and data folder,
# ships no widget extension, and is ad-hoc signed for easy hand-off.
# Set HRAM_UNIVERSAL=1 to build a universal (arm64 + x86_64) binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="Human RAM (Shareable)"
APP_DIR="$ROOT/build/$APP_NAME.app"
BUNDLE_ID="${HRAM_BUNDLE_ID:-com.example.humanram.shared}"
STORAGE="HumanRAM Shared"

BUILD_ARGS=(-c "$CONFIG" -Xswiftc -DHRAM_SHAREABLE)
if [ "${HRAM_UNIVERSAL:-0}" = "1" ]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    echo "==> swift build ($CONFIG, shareable, universal)"
else
    echo "==> swift build ($CONFIG, shareable)"
fi
swift build "${BUILD_ARGS[@]}"

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BIN="$BIN_PATH/HumanRAM"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/HumanRAM"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"

if [ -f "$ROOT/Resources/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Resources/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR"

echo "==> done: $APP_DIR"
echo "    bundle id:   $BUNDLE_ID"
echo "    data folder: ~/Library/Application Support/$STORAGE"
echo "    run with: open \"$APP_DIR\""
