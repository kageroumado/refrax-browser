#!/bin/bash
# Packages Ladybird.engine as Refrax installs it: the engine-neutral client, and beside it a
# host app holding the Refrax host, Ladybird's helper processes, their libraries and
# resources, all signed by one identity.
#
#   package.sh [--ladybird-build DIR] [--ladybird-source DIR] [--output DIR] [--identity ID]
#              [--install APPLICATION-SUPPORT-DIR]
#
# The first three options default to $LADYBIRD_BUILD, $LADYBIRD_SOURCE and $FORGE_ENGINES/packaged,
# as in build.sh.
#
# --install copies the bundle into <dir>/Engines/website.refrax.engine.ladybird/, where a
# Refrax whose data lives in <dir> finds it at its next launch.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

ladybird_build="${LADYBIRD_BUILD:-$HOME/Forge/ladybird/Build/release}"
ladybird_source="${LADYBIRD_SOURCE:-$HOME/Forge/ladybird}"
output="${FORGE_ENGINES:-$HOME/Forge/engines}/packaged"
identity=""
install_into=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ladybird-build) ladybird_build="$2"; shift 2 ;;
        --ladybird-source) ladybird_source="$2"; shift 2 ;;
        --output) output="$2"; shift 2 ;;
        --identity) identity="$2"; shift 2 ;;
        --install) install_into="$2"; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')"
fi
[[ -n "$identity" ]] || { echo "no signing identity: Refrax loads only engines its own team signed" >&2; exit 1; }

# Ladybird's own install step gives its programs library paths relative to themselves.
prefix="$(dirname "$ladybird_build")/refrax-install"
# The install step refuses a prefix that holds an earlier install.
[[ -e "$prefix" ]] && trash "$prefix"
cmake --install "$ladybird_build" --prefix "$prefix" --component ladybird_Runtime >"$prefix.log" 2>&1 \
    || { echo "cmake --install failed, see $prefix.log" >&2; exit 1; }
installed="$prefix/bundle/Ladybird.app/Contents"
[[ -x "$installed/MacOS/RefraxLadybirdHost" ]] || { echo "the installed bundle has no RefraxLadybirdHost" >&2; exit 1; }

engine="$output/Ladybird.engine"
staging="$output/Ladybird.engine.staging"
mkdir -p "$output"
[[ -e "$staging" ]] && trash "$staging"
host="$staging/Contents/Helpers/Refrax Ladybird Host.app/Contents"
mkdir -p "$staging/Contents/MacOS" "$host/MacOS" "$host/lib"

# The browser's own window and its WebDriver stay behind: Refrax is the window.
for program in "$installed"/MacOS/*; do
    case "$(basename "$program")" in
        Ladybird|WebDriver) ;;
        *) cp "$program" "$host/MacOS/" ;;
    esac
done
cp -R "$installed/Resources" "$host/Resources"

# Every library a program names, and every library those name, under the name it is asked for.
python3 - "$host" "$prefix/lib" "$ladybird_build/vcpkg_installed/arm64-osx-dynamic/lib" <<'PY'
import os, shutil, subprocess, sys
host, *library_directories = sys.argv[1:]
pending = [os.path.join(host, "MacOS", name) for name in os.listdir(os.path.join(host, "MacOS"))]
copied = set()
while pending:
    binary = pending.pop()
    for line in subprocess.run(["otool", "-L", binary], capture_output=True, text=True).stdout.splitlines()[1:]:
        dependency = line.strip().split(" ")[0]
        if not dependency.startswith("@rpath/"):
            continue
        name = dependency[len("@rpath/"):]
        if name in copied:
            continue
        for directory in library_directories:
            source = os.path.join(directory, name)
            if os.path.exists(source):
                destination = os.path.join(host, "lib", name)
                shutil.copyfile(os.path.realpath(source), destination)
                os.chmod(destination, 0o755)
                copied.add(name)
                pending.append(destination)
                break
        else:
            sys.exit(f"{os.path.basename(binary)} needs {name}, which is in none of {library_directories}")
print(f"{len(copied)} libraries")
PY

version="$("$ladybird_build/bin/Ladybird.app/Contents/MacOS/Ladybird" --version 2>/dev/null | awk '/^Version/ {print $2}')"
revision="$(git -C "$ladybird_source" rev-parse --short HEAD 2>/dev/null || echo unknown)"
cat >"$host/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RefraxLadybirdHost</string>
    <key>CFBundleIdentifier</key><string>website.refrax.engine.ladybird.host</string>
    <key>CFBundleName</key><string>Refrax Ladybird Host</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version:-0}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.4</string>
</dict>
</plist>
PLIST

clang -fobjc-arc -fmodules -O2 -g -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=26.0 -arch arm64 \
    -bundle -o "$staging/Contents/MacOS/RefraxLadybird" \
    "$REPO_ROOT"/Engines/Remote/Sources/*.m \
    -framework AppKit -framework QuartzCore
sed -e "s/@LADYBIRD_VERSION@/${version:-0}/g" -e "s/@LADYBIRD_REVISION@/$revision/g" -e "s/@BUNDLE_VERSION@/1/g" \
    -e "s|Helpers/Ladybird.app/Contents/MacOS/RefraxLadybirdHost|Helpers/Refrax Ladybird Host.app/Contents/MacOS/RefraxLadybirdHost|" \
    "$HERE/Info.plist" > "$staging/Contents/Info.plist"

# Inside out, with the hardened runtime: libraries, helpers (each with the entitlements Ladybird
# gave it, less the one that lets a debugger attach), the host app, the client, the bundle.
sign() { codesign --force --options runtime --timestamp=none --sign "$identity" "$@" >/dev/null 2>&1 || { echo "codesign failed: $*" >&2; exit 1; }; }
for library in "$host"/lib/*.dylib; do sign "$library"; done
entitlements="$output/entitlements"
mkdir -p "$entitlements"
for program in "$host"/MacOS/*; do
    name="$(basename "$program")"
    [[ "$name" == RefraxLadybirdHost ]] && continue
    plist="$entitlements/$name.plist"
    codesign -d --entitlements - --xml "$ladybird_build/bin/Ladybird.app/Contents/MacOS/$name" 2>/dev/null >"$plist" || true
    if [[ -s "$plist" ]]; then
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$plist" >/dev/null 2>&1 || true
        sign --entitlements "$plist" "$program"
    else
        sign "$program"
    fi
done
sign "$staging/Contents/Helpers/Refrax Ladybird Host.app"
sign "$staging/Contents/MacOS/RefraxLadybird"
sign "$staging"
codesign --verify --strict --deep "$staging" || { echo "the packaged bundle does not verify" >&2; exit 1; }

# A bundle that a process has loaded is replaced whole, never rewritten in place.
[[ -e "$engine" ]] && trash "$engine"
mv "$staging" "$engine"
echo "$engine ($(du -sh "$engine" | cut -f1))"

if [[ -n "$install_into" ]]; then
    destination="$install_into/Engines/website.refrax.engine.ladybird"
    mkdir -p "$destination"
    [[ -e "$destination/Ladybird.engine" ]] && trash "$destination/Ladybird.engine"
    cp -R "$engine" "$destination/Ladybird.engine"
    echo "installed in $destination"
fi
