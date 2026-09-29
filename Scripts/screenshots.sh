#!/usr/bin/env bash
# Renders the app's windows to docs/images/ using the app's own snapshot mode
# (no Screen Recording permission required). Produces light and dark variants
# so the README can theme-match. Seeds sample data into an isolated database so
# your real data is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIR="$ROOT/docs/images"
APP="$ROOT/build/Human RAM (Shareable).app"
rm -rf "$DIR"
mkdir -p "$DIR"

echo "==> building app bundle (debug)"
HRAM_UNIVERSAL=0 ./Scripts/build_share.sh debug >/dev/null

BIN="$APP/Contents/MacOS/HumanRAM"

for theme in light dark; do
    echo "==> capturing $theme into $DIR"
    TMPDB="$(mktemp -t hram-shots).sqlite3"
    HRAM_DB_PATH="$TMPDB" \
    HRAM_DEBUG_SEED=1 \
    HRAM_SNAPSHOT_DIR="$DIR" \
    HRAM_SNAPSHOT_APPEARANCE="$theme" \
    HRAM_SNAPSHOT_SUFFIX="-$theme" \
        "$BIN"
    rm -f "$TMPDB" "$TMPDB"-wal "$TMPDB"-shm
done

echo "==> done"
ls -la "$DIR"
