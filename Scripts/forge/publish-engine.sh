#!/bin/bash
# Publishes a forge engine artifact as a release of kageroumado/refrax-engines and names it in
# the engine catalog Refrax installs from (Refrax/Core/Engines/Distribution/EngineCatalog.swift).
#
#   publish-engine.sh <version> --key <ed25519.pem> [--channel stable|beta] [--dry-run]
#                     [--notes-file FILE] [--engine DIR] [--security-floor <version>]
#   publish-engine.sh --security-floor <version> --key <ed25519.pem> [--dry-run]
#
# Run a release through `kagerou publish refrax-chromium -v 152.0.7977.82-r1`, which passes the
# plan's key. The artifact is $FORGE/artifacts/<version>, packaged, signed and notarized by forge
# (package → sign → notarize). Nothing uploads until every check passes; the catalog goes up
# last, only after GitHub reports the digest of the zip it now serves. Only the two newest
# releases keep their engine zip, the latest and one to go back to; every release keeps its
# dSYMs, for crash reports from Macs still running it.
#
# The security floor is the oldest release Refrax may run: an installed engine below it doesn't
# start, and its pages render with WebKit until it updates. The second form raises it without
# a release, when a release turns out to be unsafe; a release keeps the floor the catalog has.
set -euo pipefail

REPO=kageroumado/refrax-engines
ENGINE_ID=website.refrax.engine.chromium
ENGINE_NAME="Refrax Chromium.engine"
HOST_NAME="Refrax Chromium Host"
CATALOG_TAG=catalog
RETAINED_RELEASES=2
FORGE="${FORGE:-$HOME/Forge/chromium}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_PATTERN='^[0-9]+(\.[0-9]+)+-r[0-9]+$'

die() { echo "publish-engine: $*" >&2; exit 1; }
log() { echo "[publish-engine $(date +%H:%M:%S)] $*"; }

version="" key="" channel=stable dry_run=false notes_file="" artifact="" floor=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --key) key="$2"; shift 2 ;;
        --channel) channel="$2"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --notes-file) notes_file="$2"; shift 2 ;;
        --engine) artifact="$2"; shift 2 ;;
        --security-floor) floor="$2"; shift 2 ;;
        --identity | --min-app-version) shift 2 ;; # forge signs; the contract gates compatibility
        -*) die "unknown option $1" ;;
        *) [[ -z "$version" ]] || die "one version only"; version="$1"; shift ;;
    esac
done
[[ -n "$version" || -n "$floor" ]] || die "name a version to release, or --security-floor"
[[ -z "$version" || "$version" =~ $VERSION_PATTERN ]] || die "version must be <chromium version>-r<revision>, e.g. 152.0.7977.82-r1"
[[ -z "$floor" || "$floor" =~ $VERSION_PATTERN ]] || die "the security floor must be <chromium version>-r<revision>"
[[ -f "$key" ]] || die "no signing key (--key)"
[[ "$channel" == stable || "$channel" == beta ]] || die "channel must be stable or beta"
$dry_run || gh repo view "$REPO" >/dev/null 2>&1 || die "$REPO does not exist"

sign() { openssl pkeyutl -sign -rawin -inkey "$key" -in "$1" | base64 >"$1.sig"; }

# Checks each signature with the key's public half, as Refrax will.
verify_signatures() {
    local public="$out/key.pub" signed
    openssl pkey -in "$key" -pubout -out "$public"
    for signed in "$@"; do
        base64 -d -i "$signed.sig" -o "$out/sig.bin"
        openssl pkeyutl -verify -pubin -inkey "$public" -rawin -in "$signed" -sigfile "$out/sig.bin" >/dev/null ||
            die "the signature of ${signed##*/} does not verify"
    done
    trash "$public" "$out/sig.bin"
}

# The published catalog (a dry run reads it too), or an empty one before the first release.
fetch_catalog() {
    catalog="$out/engines.json"
    if ! gh release download "$CATALOG_TAG" -R "$REPO" -p engines.json -D "$out" --clobber 2>/dev/null; then
        echo '{"schema": 1, "engines": {}}' >"$catalog"
    fi
}

# Rewrites the catalog: the release (when given) on its channel, the floor (when given), then
# the checks EngineCatalog.problems() makes in Refrax. Signs it.
update_catalog() {
    python3 - "$catalog" "$ENGINE_ID" "$channel" "$floor" "$@" <<'PY'
import json, re, sys
path, engine, channel, floor = sys.argv[1:5]
release = sys.argv[5:]
version_pattern = r"\d+(\.\d+)+-r\d+"

def key(version):
    upstream, revision = version.rsplit("-r", 1)
    return [int(part) for part in upstream.split(".")], int(revision)

catalog = json.load(open(path))
entry = catalog.setdefault("engines", {}).setdefault(engine, {"displayName": "Chromium", "channels": {}})
entry["displayName"] = "Chromium"
if release:
    version, url, sha, size, contract, minimum, upstream = release
    entry["channels"][channel] = {
        "version": version, "url": url, "sha256": sha, "sizeBytes": int(size), "contract": contract,
        "minimumSystemVersion": minimum, "notes": f"Chromium {upstream}",
    }
if floor:
    entry["securityFloor"] = floor

problems = []
if catalog.get("schema") != 1:
    problems.append("schema is not 1")
for engine_id, engine_entry in catalog["engines"].items():
    stable = engine_entry["channels"].get("stable")
    if stable is None:
        problems.append(f"{engine_id}: no stable channel")
    engine_floor = engine_entry.get("securityFloor")
    if engine_floor is not None:
        if not re.fullmatch(version_pattern, engine_floor):
            problems.append(f"{engine_id}.securityFloor {engine_floor}")
        elif stable and re.fullmatch(version_pattern, stable["version"]) and key(stable["version"]) < key(engine_floor):
            problems.append(f"{engine_id}.securityFloor {engine_floor} is newer than the stable release: nothing could run")
    for name, entry_release in engine_entry["channels"].items():
        label = f"{engine_id}.channels.{name}"
        if not re.fullmatch(version_pattern, entry_release["version"]):
            problems.append(f"{label}.version")
        if not entry_release["url"].startswith("https://github.com/kageroumado/refrax-engines/releases/download/"):
            problems.append(f"{label}.url")
        if entry_release["version"] not in entry_release["url"].rsplit("/", 1)[-1]:
            problems.append(f"{label}.url does not carry the version")
        if not re.fullmatch(r"[0-9a-f]{64}", entry_release["sha256"]):
            problems.append(f"{label}.sha256")
        if entry_release["sizeBytes"] <= 0:
            problems.append(f"{label}.sizeBytes")
        if not re.fullmatch(r"\d+\.\d+", entry_release["contract"]):
            problems.append(f"{label}.contract")
if problems:
    sys.exit("catalog problems: " + "; ".join(problems))
json.dump(catalog, open(path, "w"), indent=2, sort_keys=True)
PY
    sign "$catalog"
}

upload_catalog() {
    if ! gh release view "$CATALOG_TAG" -R "$REPO" >/dev/null 2>&1; then
        gh release create "$CATALOG_TAG" -R "$REPO" --title "Engine catalog" --latest=false \
            --notes "engines.json lists the engine releases Refrax installs; engines.json.sig is its Ed25519 signature."
    fi
    gh release upload "$CATALOG_TAG" -R "$REPO" --clobber "$catalog" "$catalog.sig"
}

# Removes the engine zip from every release but the newest $RETAINED_RELEASES and those the
# catalog names; their dSYMs stay.
trim_releases() {
    local tags tag old_version name
    tags=$(gh api "repos/$REPO/releases" --paginate --jq '.[].tag_name | select(startswith("chromium/"))')
    python3 - "$catalog" "$RETAINED_RELEASES" $tags <<'PY' | while read -r tag; do
import json, sys
catalog = json.load(open(sys.argv[1]))
retained = int(sys.argv[2])
named = {release["version"] for engine in catalog["engines"].values() for release in engine["channels"].values()}

def key(version):
    upstream, revision = version.rsplit("-r", 1)
    return [int(part) for part in upstream.split(".")], int(revision)

versions = sorted((tag.split("/", 1)[1] for tag in sys.argv[3:]), key=key, reverse=True)
for version in versions[retained:]:
    if version not in named:
        print(f"chromium/{version}")
PY
        old_version="${tag#chromium/}"
        for name in "Refrax-Chromium-$old_version.zip" "Refrax-Chromium-$old_version.zip.sig" "Refrax-Chromium-$old_version.zip.sha256"; do
            gh release delete-asset "$tag" "$name" -R "$REPO" -y >/dev/null 2>&1 || true
        done
        log "trimmed $tag to its dSYMs"
    done
}

# MARK: Floor only

if [[ -z "$version" ]]; then
    out="$(mktemp -d -t refrax-engine-floor)"
    fetch_catalog
    update_catalog
    verify_signatures "$catalog"
    if $dry_run; then
        log "dry run: the catalog would set the floor to $floor; nothing uploaded"
        exit 0
    fi
    upload_catalog
    log "the catalog's security floor for $ENGINE_ID is $floor"
    exit 0
fi

# MARK: The artifact

artifact="${artifact:-$FORGE/artifacts/$version}"
engine="$artifact/$ENGINE_NAME"
tag="chromium/$version"
upstream="${version%-r*}"
revision="${version##*-r}"

[[ -d "$engine" ]] || die "no engine at $engine (forge package release $version)"
[[ -f "$artifact/.signed" && -f "$artifact/.notarized" ]] || die "$version is not signed and notarized (forge sign, forge notarize)"
build=$(plutil -extract RFXEngineBuild raw -o - "$engine/Contents/Info.plist")
[[ "$build" == "$version" ]] || die "the engine is build $build, not $version"
contract=$(plutil -extract RFXEngineContractVersion raw -o - "$engine/Contents/Info.plist")
minimum_system=$(plutil -extract LSMinimumSystemVersion raw -o - "$engine/Contents/Info.plist" 2>/dev/null || echo 26.0)
codesign --verify --deep --strict "$engine" || die "the engine's code signature does not verify"
spctl --assess --type exec "$engine/Contents/Helpers/$HOST_NAME.app" 2>/dev/null ||
    die "Gatekeeper rejects the host app (is the notarization ticket stapled?)"

# The source the engine was built from is Refrax at this commit, public on origin/main.
git -C "$REPO_ROOT" fetch -q origin main
[[ -z "$(git -C "$REPO_ROOT" status --porcelain -- Engines Scripts/forge)" ]] || die "Engines/ or Scripts/forge has uncommitted changes"
commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
git -C "$REPO_ROOT" merge-base --is-ancestor "$commit" origin/main || die "HEAD ($commit) is not on origin/main; push it first"
$dry_run || ! gh release view "$tag" -R "$REPO" >/dev/null 2>&1 || die "$tag is already released"

# MARK: Assets

out="$artifact/publish"
[[ -e "$out" ]] && trash "$out"
mkdir -p "$out"
zip_name="Refrax-Chromium-$version.zip"
zip="$out/$zip_name"
log "zipping the engine"
ditto -c -k --keepParent "$engine" "$zip"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
echo "$sha  $zip_name" >"$zip.sha256"
sign "$zip"
size=$(stat -f %z "$zip")
assets=("$zip" "$zip.sig" "$zip.sha256")
signed=("$zip")
if [[ -d "$artifact/dSYMs" ]]; then
    log "zipping the dSYMs"
    dsyms="$out/Refrax-Chromium-$version-dSYMs.zip"
    ditto -c -k --keepParent "$artifact/dSYMs" "$dsyms"
    sign "$dsyms"
    assets+=("$dsyms" "$dsyms.sig")
    signed+=("$dsyms")
fi

# MARK: Catalog

fetch_catalog
url="https://github.com/$REPO/releases/download/chromium%2F$version/$zip_name"
update_catalog "$version" "$url" "$sha" "$size" "$contract" "$minimum_system" "$upstream"
verify_signatures "${signed[@]}" "$catalog"
log "assets ready in $out ($(du -sh "$zip" | cut -f1) engine zip, sha256 $sha)"

if $dry_run; then
    log "dry run: nothing uploaded"
    exit 0
fi

# MARK: Publish

notes="$out/notes.md"
if [[ -n "$notes_file" ]]; then
    cp "$notes_file" "$notes"
else
    cat >"$notes" <<EOF
The Chromium engine for [Refrax](https://github.com/kageroumado/refrax-browser): Chromium $upstream, engine contract $contract, revision $revision.

Refrax installs it from **Settings → Engines → Available Engines**, checking this release's Ed25519 signature, its checksum and its Developer ID signature. To install by hand, unzip \`$zip_name\` into \`~/Library/Application Support/website.refrax.browser/Engines/$ENGINE_ID/\`.

Built from [kageroumado/refrax-browser@${commit:0:10}](https://github.com/kageroumado/refrax-browser/tree/$commit/Engines/Chromium): ungoogled-chromium with Refrax's patches and host. Signed and notarized; arm64, macOS $minimum_system or later.
EOF
fi
prerelease=()
[[ "$channel" == beta ]] && prerelease=(--prerelease)
log "creating release $tag"
gh release create "$tag" -R "$REPO" --title "Chromium $upstream (r$revision)" --notes-file "$notes" \
    --latest=false ${prerelease[@]+"${prerelease[@]}"} "${assets[@]}"

served=$(gh api "repos/$REPO/releases/tags/chromium%2F$version" --jq ".assets[] | select(.name == \"$zip_name\") | .digest")
[[ "$served" == "sha256:$sha" ]] || die "GitHub serves $zip_name with digest $served, not sha256:$sha; the catalog was not updated"

upload_catalog
log "published $tag; the catalog's $channel channel names it"
trim_releases
