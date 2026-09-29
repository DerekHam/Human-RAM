#!/usr/bin/env bash
# Renders the app's windows to PNGs in docs/images/ using the app's own
# snapshot mode (no Screen Recording permission required). Seeds sample data
# into an isolated database so your real data is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIR="$ROOT/docs/images"
APP="$ROOT/build/Human RAM (Shareable).app"
rm -rf "$DIR"
mkdir -p "$DIR"

echo "==> building app bundle (debug)"
HRAM_UNIVERSAL=0 ./Scripts/build_share.sh debug >/dev/null

TMPDB="$(mktemp -t hram-shots).sqlite3"
trap 'rm -f "$TMPDB" "$TMPDB"-wal "$TMPDB"-shm' EXIT

echo "==> capturing into $DIR"
HRAM_DB_PATH="$TMPDB" HRAM_DEBUG_SEED=1 HRAM_SNAPSHOT_DIR="$DIR" \
    "$APP/Contents/MacOS/HumanRAM"

echo "==> done"
ls -la "$DIR"
