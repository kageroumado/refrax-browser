#!/bin/bash
# Builds Ladybird.engine: the engine-neutral client (Engines/Remote/Sources) as the bundle's
# executable, around a Ladybird build that has the Refrax host (UI/Refrax in the fork).
#
#   build.sh [--ladybird-build DIR] [--ladybird-source DIR] [--output DIR]
#
# The bundle links to the Ladybird build in place, so it runs on this Mac only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

ladybird_build="/Volumes/Ugreen/Build/ladybird/Build/release"
ladybird_source="$HOME/Developer/clones/ladybird"
output="/Volumes/Ugreen/Build/refrax/Engines"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ladybird-build) ladybird_build="$2"; shift 2 ;;
        --ladybird-source) ladybird_source="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done

app="$ladybird_build/bin/Ladybird.app"
[[ -x "$app/Contents/MacOS/RefraxLadybirdHost" ]] || { echo "no RefraxLadybirdHost in $app: build the fork's RefraxLadybirdHost target" >&2; exit 1; }

engine="$output/Ladybird.engine"
staging="$output/Ladybird.engine.staging"
[[ -e "$staging" ]] && trash "$staging"
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Helpers"

clang -fobjc-arc -fmodules -O2 -g -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=26.0 -arch arm64 \
    -bundle -o "$staging/Contents/MacOS/RefraxLadybird" \
    "$REPO_ROOT"/Engines/Remote/Sources/*.m \
    -framework AppKit -framework QuartzCore

version="$("$app/Contents/MacOS/Ladybird" --version 2>/dev/null | awk '/^Version/ {print $2}')"
revision="$(git -C "$ladybird_source" rev-parse --short HEAD 2>/dev/null || echo unknown)"
sed -e "s/@LADYBIRD_VERSION@/${version:-0}/g" -e "s/@LADYBIRD_REVISION@/$revision/g" -e "s/@BUNDLE_VERSION@/1/g" \
    "$HERE/Info.plist" > "$staging/Contents/Info.plist"

ln -s "$app" "$staging/Contents/Helpers/Ladybird.app"
codesign --force --sign - "$staging/Contents/MacOS/RefraxLadybird" >/dev/null

# A bundle that a process has loaded is replaced whole, never rewritten in place.
[[ -e "$engine.old" ]] && trash "$engine.old"
[[ -d "$engine" ]] && mv "$engine" "$engine.old"
mv "$staging" "$engine"
[[ -e "$engine.old" ]] && trash "$engine.old"
echo "$engine"
