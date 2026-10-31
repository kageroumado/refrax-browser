#!/bin/zsh
# Refreshes the filter list snapshots the app ships (Refrax/Resources/Shields/Lists), which a
# fresh install builds Shields from before its first download.
#
# Usage: Scripts/shields-list-snapshots.sh
#
# The lists are FilterListSource.bundledListIDs; keep the two in step. Each snapshot is the
# list's text, LZMA-compressed (about 1.3 MB for all seven), and every refresh adds that much to
# the repository's history, so run it once per release rather than per commit.

set -euo pipefail

root=${0:A:h:h}
out="$root/Refrax/Resources/Shields/Lists"
mkdir -p "$out"
scratch=$(mktemp -d)
trap 'trash "$scratch" 2>/dev/null || true' EXIT

typeset -A lists=(
    easylist https://easylist.to/easylist/easylist.txt
    easyprivacy https://easylist.to/easylist/easyprivacy.txt
    ublock-filters https://ublockorigin.github.io/uAssets/filters/filters.txt
    ublock-privacy https://ublockorigin.github.io/uAssets/filters/privacy.txt
    ublock-badware https://ublockorigin.github.io/uAssets/filters/badware.txt
    ublock-unbreak https://ublockorigin.github.io/uAssets/filters/unbreak.txt
    ublock-quick-fixes https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt
)

for id url in ${(kv)lists}; do
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --max-filesize 33554432 --output "$scratch/$id.txt" "$url"
    if head -c 512 "$scratch/$id.txt" | grep -q '^[[:space:]]*<'; then
        print -u2 "$id: $url served HTML, not a filter list"
        exit 1
    fi
    compression_tool -encode -a lzma -i "$scratch/$id.txt" -o "$out/shields-list-$id.lzma"
    print "$id: $(wc -c < "$scratch/$id.txt" | tr -d ' ') bytes -> $(wc -c < "$out/shields-list-$id.lzma" | tr -d ' ')"
done
