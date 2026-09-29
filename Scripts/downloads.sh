#!/usr/bin/env bash
# Reports Human RAM release download counts, plus 14-day repo views/clones.
# GitHub only exposes current totals and the last 14 days of traffic, so run
# this periodically (and save the output) if you want a history to show.
set -euo pipefail

REPO="${HRAM_REPO:-DerekHam/Human-RAM}"

if ! command -v gh >/dev/null 2>&1; then
    echo "gh (GitHub CLI) is required: https://cli.github.com" >&2
    exit 1
fi

echo "Human RAM — download report"
echo "Repo: https://github.com/$REPO"
echo "=================================================="

echo ""
echo "Per release:"
gh api "repos/$REPO/releases" --paginate \
    --jq '.[] | select(.assets | length > 0) |
          "  \(.tag_name)\t\(.published_at[0:10])\t" +
          ([.assets[] | select(.name | test("\\.(dmg|zip)$")) |
            "\(.name)=\(.download_count)"] | join("  "))'

echo ""
dmg=$(gh api "repos/$REPO/releases" --paginate \
    --jq '[.[].assets[] | select(.name | endswith(".dmg")) | .download_count] | add // 0')
zip=$(gh api "repos/$REPO/releases" --paginate \
    --jq '[.[].assets[] | select(.name | endswith(".zip")) | .download_count] | add // 0')
echo "  DMG downloads: $dmg"
echo "  ZIP downloads: $zip"
echo "  TOTAL app downloads: $((dmg + zip))"

echo ""
echo "Traffic (last 14 days; GitHub keeps only 14 days):"
if views=$(gh api "repos/$REPO/traffic/views" --jq '"  page views: \(.count)  (\(.uniques) unique visitors)"' 2>/dev/null); then
    echo "$views"
else
    echo "  page views: unavailable (needs push access to the repo)"
fi
if clones=$(gh api "repos/$REPO/traffic/clones" --jq '"  git clones: \(.count)  (\(.uniques) unique)"' 2>/dev/null); then
    echo "$clones"
else
    echo "  git clones: unavailable (needs push access to the repo)"
fi

echo ""
echo "Notes:"
echo "  - Counts include your own test/Homebrew fetches and any mirrors."
echo "  - Homebrew installs count as DMG downloads (same GitHub asset)."
echo "  - Re-uploading an asset (--clobber) resets that asset's counter."
