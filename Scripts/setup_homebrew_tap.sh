#!/usr/bin/env bash
# Creates (or refreshes) the Homebrew tap that serves `brew install --cask human-ram`.
# Needs the GitHub CLI, authenticated: `gh auth login`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP="${HRAM_TAP:-DerekHam/homebrew-human-ram}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

if ! gh repo view "$TAP" >/dev/null 2>&1; then
    echo "==> creating $TAP"
    gh repo create "$TAP" --public \
        --description "Homebrew tap for Human RAM"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
echo "==> cloning $TAP"
gh repo clone "$TAP" "$WORKDIR" -- --depth 1 >/dev/null

mkdir -p "$WORKDIR/Casks"
cp "$ROOT/Casks/human-ram.rb" "$WORKDIR/Casks/human-ram.rb"

USER="$(gh api user --jq .login)"
cd "$WORKDIR"
git add Casks/human-ram.rb
if git diff --cached --quiet; then
    echo "==> tap already up to date"
else
    git -c user.name="$USER" -c user.email="$USER@users.noreply.github.com" \
        commit -m "human-ram $VERSION" >/dev/null
    git push
    echo "==> pushed human-ram $VERSION to $TAP"
fi

echo "Users can now run:"
echo "  brew tap ${TAP%/*}/human-ram"
echo "  brew install --cask human-ram"
