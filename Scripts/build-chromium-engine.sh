#!/bin/zsh
# Builds the in-process Chromium (CEF) engine bundle and installs it where Refrax
# discovers engines.
#
#   Scripts/build-chromium-engine.sh [--release]
#
# Environment:
#   CEF_ROOT   CEF binary distribution (minimal is enough). Default: ~/Developer/.cef/sdk-154
#   IDENTITY   codesign identity; must share the app's Team ID, which Refrax checks
#              before loading an engine. Default: the identity that signed the last debug build.
#
# Output (debug): ~/Library/Application Support/website.refrax.browser.debug/Engines/
#   website.refrax.engine.chromium/Chromium.engine/Contents/
#     Info.plist                     engine descriptor (Engines/CONTRACT.md)
#     MacOS/RefraxChromium           principal class RFXChromiumEngineHost
#     Frameworks/Chromium Embedded Framework.framework
#     Frameworks/Refrax Chromium Helper[ (GPU|Renderer|Alerts)].app
set -euo pipefail

REPO=${0:A:h:h}
CEF_ROOT=${CEF_ROOT:-$HOME/Developer/.cef/sdk-154}
BUILD_DIR=${BUILD_DIR:-$HOME/Developer/.cef/build}
APP_BUNDLE_ID=website.refrax.browser.debug
[[ "${1:-}" == "--release" ]] && APP_BUNDLE_ID=website.refrax.browser
ENGINE_ID=website.refrax.engine.chromium
ENGINES="$HOME/Library/Application Support/$APP_BUNDLE_ID/Engines"
DEST="$ENGINES/$ENGINE_ID/Chromium.engine"
HELPER_NAME="Refrax Chromium Helper"

if [[ -z "${IDENTITY:-}" ]]; then
  APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Refrax-*/Build/Products/Debug/Refrax.app 2>/dev/null | head -1)
  # The leaf certificate's SHA-1 names the identity unambiguously (names can hold non-ASCII).
  CERTS=$(mktemp -d)
  (cd "$CERTS" && codesign -d --extract-certificates "$APP" 2>/dev/null)
  IDENTITY=$(shasum -a 1 "$CERTS/codesign0" | cut -d' ' -f1 | tr a-f A-F)
fi
[[ -n "$IDENTITY" ]] || { echo "No signing identity; set IDENTITY" >&2; exit 1; }

sign() {  # path [entitlements plist]
  local args=(--force --options runtime --timestamp=none --sign "$IDENTITY")
  [[ -n "${2:-}" ]] && args+=(--entitlements "$2")
  codesign "${args[@]}" "$1" 2>&1 | grep -v "replacing existing signature" || true
}

echo "==> Building against $CEF_ROOT"
mkdir -p "$BUILD_DIR"
cmake -S "$REPO/Engines/Chromium" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DCEF_ROOT="$CEF_ROOT" > /dev/null
ninja -C "$BUILD_DIR" RefraxChromium RefraxChromiumHelper | tail -1

CEF_VERSION=$(sed -n 's/^#define CEF_VERSION "\(.*\)"/\1/p' "$CEF_ROOT/include/cef_version.h")
CHROMIUM_VERSION=$(grep -E '^#define CHROME_VERSION_(MAJOR|MINOR|BUILD|PATCH) ' "$CEF_ROOT/include/cef_version.h" | awk '{print $3}' | paste -sd. -)

# Assemble in a staging bundle, then swap it in by rename: a running Refrax has
# the installed binaries mapped, and rewriting a mapped signed binary gets the
# process killed with "Code Signature Invalid". A rename leaves it the old inode.
STAGING="$DEST.staging"
[[ -e "$STAGING" ]] && trash "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Frameworks"
echo "==> Assembling $STAGING"

cp -cR "$CEF_ROOT/Release/Chromium Embedded Framework.framework" "$STAGING/Contents/Frameworks/"
cp "$BUILD_DIR/libRefraxChromium.dylib" "$STAGING/Contents/MacOS/RefraxChromium"

cat > "$STAGING/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$ENGINE_ID</string>
  <key>CFBundleName</key><string>Chromium</string>
  <key>CFBundleExecutable</key><string>RefraxChromium</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>$CEF_VERSION</string>
  <key>NSPrincipalClass</key><string>RFXChromiumEngineHost</string>
  <key>RFXEngineContractVersion</key><string>1.0</string>
  <key>RFXEngineDisplayName</key><string>Chromium</string>
  <key>RFXEngineVersion</key><string>Chromium $CHROMIUM_VERSION</string>
  <key>RFXEngineVendor</key><string>Refrax (CEF)</string>
  <key>RFXEngineOutOfProcess</key><false/>
  <key>RFXEngineCapabilities</key><array>
    <string>javaScriptEvaluation</string><string>findInPage</string><string>zoom</string>
    <string>devTools</string><string>downloads</string>
  </array>
</dict></plist>
PLIST

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
  local app="$STAGING/Contents/Frameworks/$name.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$BUILD_DIR/RefraxChromiumHelper" "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$ENGINE_ID.helper$idsuffix</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST
  local ent; ent=$(write_entitlements "helper$idsuffix" "$@")
  sign "$app" "$ent"
}

echo "==> Signing with: $IDENTITY"
FRAMEWORK="$STAGING/Contents/Frameworks/Chromium Embedded Framework.framework"
for lib in "$FRAMEWORK"/Libraries/*.dylib; do sign "$lib"; done
sign "$FRAMEWORK"

# Entitlements follow Chrome's (and Arc's) helpers. The base helper hosts utility
# processes, which load code signed by other teams (the Widevine CDM).
JIT=com.apple.security.cs.allow-jit
make_helper "" "" com.apple.security.cs.disable-library-validation
make_helper " (GPU)" ".gpu" $JIT
make_helper " (Renderer)" ".renderer" $JIT
make_helper " (Alerts)" ".alerts"

sign "$STAGING/Contents/MacOS/RefraxChromium"
sign "$STAGING"
codesign --verify --strict --deep "$STAGING"

echo "==> Installing $DEST"
mkdir -p "${DEST:h}"
if [[ -d "$DEST" ]]; then
  mv "$DEST" "$DEST.previous.$$"
  mv "$STAGING" "$DEST"
  trash "$DEST.previous.$$"
else
  mv "$STAGING" "$DEST"
fi
echo "==> Installed Chromium $CHROMIUM_VERSION (CEF $CEF_VERSION)"
