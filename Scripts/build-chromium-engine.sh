#!/bin/zsh
# Builds the Chromium engine plug-in and installs it where Refrax looks for it.
#
#   Scripts/build-chromium-engine.sh [--release]
#
# Environment:
#   CEF_ROOT   CEF binary distribution (minimal is enough). Default: ~/Developer/.cef/sdk-154
#   IDENTITY   codesign identity; must share the app's Team ID or library validation
#              rejects the framework. Default: the identity that signed the last debug build.
#
# Output (debug): ~/Library/Application Support/website.refrax.browser.debug/Engines/Chromium/
#   Chromium Embedded Framework.framework   cloned from CEF_ROOT, re-signed
#   RefraxChromium.dylib                    the Objective-C engine plug-in
#   Refrax Chromium Helper[ (GPU|Renderer|Alerts)].app
#   engine.json                             versions, read by the app
set -euo pipefail

REPO=${0:A:h:h}
CEF_ROOT=${CEF_ROOT:-$HOME/Developer/.cef/sdk-154}
BUILD_DIR=${BUILD_DIR:-$HOME/Developer/.cef/build}
BUNDLE_ID=website.refrax.browser.debug
[[ "${1:-}" == "--release" ]] && BUNDLE_ID=website.refrax.browser
DEST="$HOME/Library/Application Support/$BUNDLE_ID/Engines/Chromium"
HELPER_NAME="Refrax Chromium Helper"

if [[ -z "${IDENTITY:-}" ]]; then
  APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Refrax-*/Build/Products/Debug/Refrax.app 2>/dev/null | head -1)
  # The leaf certificate's SHA-1 names the identity unambiguously (names can hold non-ASCII).
  CERTS=$(mktemp -d)
  (cd "$CERTS" && codesign -d --extract-certificates "$APP" 2>/dev/null)
  IDENTITY=$(shasum -a 1 "$CERTS/codesign0" | cut -d' ' -f1 | tr a-f A-F)
fi
[[ -n "$IDENTITY" ]] || { echo "No signing identity; set IDENTITY" >&2; exit 1; }

echo "==> Building plug-in against $CEF_ROOT"
mkdir -p "$BUILD_DIR"
cmake -S "$REPO/Engines/Chromium" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DCEF_ROOT="$CEF_ROOT" > /dev/null
ninja -C "$BUILD_DIR" RefraxChromium RefraxChromiumHelper | tail -1

echo "==> Installing into $DEST"
mkdir -p "$DEST"
FRAMEWORK="$DEST/Chromium Embedded Framework.framework"
if [[ ! -d "$FRAMEWORK" ]]; then
  # APFS clone: no extra disk space until either copy changes.
  cp -cR "$CEF_ROOT/Release/Chromium Embedded Framework.framework" "$FRAMEWORK"
fi
# Every binary is replaced by rename, never rewritten in place: a running Refrax
# has these files mapped, and rewriting a mapped signed binary gets the process
# killed with "Code Signature Invalid". A rename leaves it the old inode.
install_atomically() {  # source, destination [--sign]
  local staging="$2.staging"
  cp -f "$1" "$staging"
  if [[ "${3:-}" == "--sign" ]]; then
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$staging" 2>&1 | grep -v "replacing existing" || true
  fi
  mv -f "$staging" "$2"
}

ENTITLEMENTS_DIR=$(mktemp -d)
write_entitlements() {  # name, keys...
  local file="$ENTITLEMENTS_DIR/$1.plist"; shift
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    for key in "$@"; do echo "<key>$key</key><true/>"; done
    echo '</dict></plist>'
  } > "$file"
  echo "$file"
}

make_helper() {  # suffix (e.g. " (GPU)"), bundle-id suffix, entitlement keys...
  local suffix=$1 idsuffix=$2; shift 2
  local name="$HELPER_NAME$suffix"
  local app="$DEST/$name.app"
  mkdir -p "$app/Contents/MacOS"
  install_atomically "$BUILD_DIR/RefraxChromiumHelper" "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.chromium.helper$idsuffix</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST
  local ent; ent=$(write_entitlements "helper$idsuffix" "$@")
  codesign --force --options runtime --timestamp=none --entitlements "$ent" --sign "$IDENTITY" "$app" 2>&1 | grep -v "replacing existing signature" || true
}

echo "==> Signing with: $IDENTITY"
for lib in "$FRAMEWORK"/Libraries/*.dylib; do
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$lib" 2>&1 | grep -v "replacing existing" || true
done
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$FRAMEWORK" 2>&1 | grep -v "replacing existing" || true
install_atomically "$BUILD_DIR/libRefraxChromium.dylib" "$DEST/RefraxChromium.dylib" --sign

# Entitlements follow Chrome's (and Arc's) helpers. The base helper hosts utility
# processes, which load code signed by other teams (the Widevine CDM).
JIT=com.apple.security.cs.allow-jit
make_helper "" "" com.apple.security.cs.disable-library-validation
make_helper " (GPU)" ".gpu" $JIT
make_helper " (Renderer)" ".renderer" $JIT
make_helper " (Alerts)" ".alerts"

CEF_VERSION=$(sed -n 's/^#define CEF_VERSION "\(.*\)"/\1/p' "$CEF_ROOT/include/cef_version.h")
CHROMIUM_VERSION=$(grep -E '^#define CHROME_VERSION_(MAJOR|MINOR|BUILD|PATCH) ' "$CEF_ROOT/include/cef_version.h" | awk '{print $3}' | paste -sd. -)
cat > "$DEST/engine.json" <<JSON
{
  "cefVersion": "$CEF_VERSION",
  "chromiumVersion": "$CHROMIUM_VERSION",
  "plugin": "RefraxChromium.dylib",
  "helper": "$HELPER_NAME.app/Contents/MacOS/$HELPER_NAME"
}
JSON
echo "==> Installed Chromium $CHROMIUM_VERSION (CEF $CEF_VERSION)"
