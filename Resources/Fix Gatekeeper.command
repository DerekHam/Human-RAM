#!/bin/bash
# Removes macOS's download quarantine flag from Human RAM so it opens without
# the "unidentified developer" warning. Safe to run more than once.
set -euo pipefail

APP=""
for candidate in \
    "/Applications/Human RAM (Shareable).app" \
    "$HOME/Applications/Human RAM (Shareable).app" \
    "/Applications/Human RAM.app" \
    "$HOME/Applications/Human RAM.app" \
    "$(cd "$(dirname "$0")" && pwd)/Human RAM (Shareable).app"; do
    if [ -d "$candidate" ]; then
        APP="$candidate"
        break
    fi
done

if [ -z "$APP" ]; then
    echo "Could not find Human RAM in Applications."
    echo "First drag \"Human RAM (Shareable).app\" into Applications, then run this again."
    read -r -p "Press Return to close."
    exit 1
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Done. $APP is ready to open."
read -r -p "Press Return to close."
