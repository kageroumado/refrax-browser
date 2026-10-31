#!/bin/zsh
# Downloads popular extensions and runs RefraxTests/ExtensionCompatibilityHarness against them.
#
#   Scripts/extension-compat.sh [--download] [--build] [directory]
#
# --download  fetches the extensions below into the directory (Firefox add-ons as .xpi,
#             Chrome Web Store items as .crx); existing files are replaced.
# --build     runs build-for-testing first.
# directory   defaults to /Volumes/Ugreen/Scratch/extensions.
#
# The harness writes report.json and report.md into the directory. Every xcodebuild run
# takes /tmp/refrax-build.lock, which other build scripts share.
set -euo pipefail

download=false
build=false
directory=/Volumes/Ugreen/Scratch/extensions
for argument in "$@"; do
  case "$argument" in
    --download) download=true ;;
    --build) build=true ;;
    *) directory="$argument" ;;
  esac
done

repository=${0:A:h:h}
derived=/Volumes/Ugreen/Build/refrax-extensions
log=/Volumes/Ugreen/Build/refrax-extensions.log

# Firefox add-on slugs and Chrome Web Store IDs.
firefox_addons=(darkreader bitwarden-password-manager sponsorblock return-youtube-dislikes violentmonkey
  vimium-c privacy-badger17 refined-github- styl-us)
chrome_items=(nngceckbapebfimnlniiiahkandclblb ddkjiahejlhfcafbddmgiahcphecmpfh)

mkdir -p "$directory"
if $download; then
  for slug in $firefox_addons; do
    curl -fsSL -o "$directory/$slug.xpi" "https://addons.mozilla.org/firefox/downloads/latest/$slug/latest.xpi"
    echo "downloaded $slug.xpi"
  done
  for id in $chrome_items; do
    curl -fsSL -o "$directory/$id.crx" \
      "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=135.0&acceptformat=crx2,crx3&x=id%3D$id%26uc"
    echo "downloaded $id.crx"
  done
  cp "$repository/Refrax/Resources/BundledExtensions/ublock_origin-1.68.0.xpi" "$directory/ublock-origin.xpi"
fi

xcodebuild_locked() {
  until mkdir /tmp/refrax-build.lock 2>/dev/null; do sleep 10; done
  echo $$ > /tmp/refrax-build.lock/pid
  local status=0
  xcodebuild "$@" -project "$repository/Refrax.xcodeproj" -scheme Refrax -destination 'platform=macOS' \
    -derivedDataPath "$derived" > "$log" 2>&1 || status=$?
  rm -rf /tmp/refrax-build.lock
  return $status
}

if $build; then
  xcodebuild_locked build-for-testing
fi
TEST_RUNNER_REFRAX_EXTENSION_COMPAT_DIR="$directory" \
  xcodebuild_locked test-without-building -only-testing:RefraxTests/ExtensionCompatibilityHarness || true
echo "log: $log"
echo "report: $directory/report.md"
