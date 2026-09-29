#!/usr/bin/env bash
# Builds a universal, ad-hoc-signed shareable app and packages it as a DMG and
# a zip for a GitHub release. Prints the sha256 needed by the Homebrew cask.
#
#   ./Scripts/release.sh            # release config, universal
#   HRAM_UNIVERSAL=0 ./Scripts/release.sh   # native arch only (faster local test)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP_NAME="Human RAM (Shareable)"
APP_DIR="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/Human-RAM-v$VERSION-macOS.dmg"
ZIP="$ROOT/build/Human-RAM-v$VERSION-macOS.zip"
STAGE="$ROOT/build/dmg-stage"

if [ -f "$ROOT/Casks/human-ram.rb" ]; then
    echo "==> syncing Homebrew cask to $VERSION"
    sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$ROOT/Casks/human-ram.rb"
fi

echo "==> building $APP_NAME $VERSION"
HRAM_UNIVERSAL="${HRAM_UNIVERSAL:-1}" "$ROOT/Scripts/build_share.sh" "$CONFIG"

if [ ! -d "$APP_DIR" ]; then
    echo "error: expected $APP_DIR after build" >&2
    exit 1
fi

if command -v lipo >/dev/null && [ "${HRAM_UNIVERSAL:-1}" = "1" ]; then
    echo "==> architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/HumanRAM")"
fi

echo "==> assembling DMG"
rm -rf "$STAGE" "$DMG" "$ZIP"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/INSTALL.txt" "$STAGE/READ ME FIRST.txt"
cp "$ROOT/Resources/Fix Gatekeeper.command" "$STAGE/Fix Gatekeeper.command"
chmod +x "$STAGE/Fix Gatekeeper.command"

hdiutil create \
    -volname "Human RAM" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo "==> zipping app"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP"

echo "==> checksums"
shasum -a 256 "$DMG" "$ZIP" | tee "$ROOT/build/checksums.txt"

echo ""
echo "Done. Upload these to the GitHub release:"
echo "  $DMG"
echo "  $ZIP"
echo ""
echo "Homebrew cask snippet:"
echo "  version \"$VERSION\""
echo "  sha256 \"$(shasum -a 256 "$DMG" | awk '{print $1}')\""
