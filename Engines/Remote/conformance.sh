#!/bin/bash
# Checks an engine bundle against the engine contract (Engines/Conformance).
#
#   conformance.sh [--active] <path/to/X.engine> [test-name-substring …]
#
# --active launches the runner through LaunchServices, which makes it the active app and takes
# the keyboard: the input tests need that, and are skipped without it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
build="/Volumes/Ugreen/Build/refrax/Engines"

active=0
if [[ "${1:-}" == "--active" ]]; then active=1; shift; fi
engine="${1:?usage: conformance.sh [--active] <engine bundle> [tests…]}"
shift

app="$build/Engine Conformance.app"
mkdir -p "$app/Contents/MacOS"
binary="$app/Contents/MacOS/engine-conformance"
newest_source="$(ls -t "$REPO_ROOT"/Engines/Conformance/Sources/*.swift "$REPO_ROOT/Engines/SDK/RFXEngine.h" | head -1)"
if [[ ! -x "$binary" || "$newest_source" -nt "$binary" ]]; then
    swiftc -swift-version 6 -O -import-objc-header "$REPO_ROOT/Engines/Conformance/Bridging.h" \
        "$REPO_ROOT"/Engines/Conformance/Sources/*.swift -o "$binary"
    cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>engine-conformance</string>
    <key>CFBundleIdentifier</key><string>website.refrax.engine-conformance</string>
    <key>CFBundleName</key><string>Engine Conformance</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
    # A real identity where there is one: macOS keys privacy grants (removable-volume access to
    # an engine on the SSD) to the signature, so an ad hoc one asks again after every rebuild.
    identity="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')"
    codesign --force --sign "${identity:--}" "$app" >/dev/null 2>&1
fi

storage="/Volumes/Ugreen/Scratch/engine-conformance/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$storage"
status="$storage.status"
if [[ $active -eq 1 ]]; then
    log="$storage.log"
    : >"$log"
    tail -f "$log" &
    tail_pid=$!
    open -W -n -a "$app" --stdout "$log" --stderr "$storage.engine.log" --args "$engine" --storage "$storage" --status "$status" "$@"
    sleep 1
    kill "$tail_pid" 2>/dev/null || true
else
    "$binary" "$engine" --storage "$storage" --status "$status" "$@" 2>"$storage.engine.log" || true
fi
echo "storage: $storage   engine log: $storage.engine.log"
[[ -f "$status" ]] && exit "$(cat "$status")"
echo "the runner exited without a result" >&2
exit 3
