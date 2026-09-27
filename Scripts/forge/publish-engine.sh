#!/bin/bash
# Publishes a forge engine artifact as a release of kageroumado/refrax-engines and names it in
# the engine catalog Refrax installs from (Refrax/Core/Engines/Distribution/EngineCatalog.swift).
#
#   publish-engine.sh <version> --key <ed25519.pem> [--channel stable|beta] [--dry-run]
#                     [--notes-file FILE] [--engine DIR]
#
# Run through `kagerou publish refrax-chromium -v 152.0.7977.82-r1`, which passes the plan's key.
# The artifact is $FORGE/artifacts/<version>, packaged, signed and notarized by forge
# (package → sign → notarize). Nothing uploads until every check passes; the catalog goes up
# last, only after GitHub reports the digest of the zip it now serves.
set -euo pipefail

REPO=kageroumado/refrax-engines
ENGINE_ID=website.refrax.engine.chromium
ENGINE_NAME="Refrax Chromium.engine"
HOST_NAME="Refrax Chromium Host"
CATALOG_TAG=catalog
FORGE="${FORGE:-/Volumes/Ugreen/Projects/refrax/engines/chromium}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "publish-engine: $*" >&2; exit 1; }
log() { echo "[publish-engine $(date +%H:%M:%S)] $*"; }

version="" key="" channel=stable dry_run=false notes_file="" artifact=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --key) key="$2"; shift 2 ;;
        --channel) channel="$2"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --notes-file) notes_file="$2"; shift 2 ;;
        --engine) artifact="$2"; shift 2 ;;
        --identity | --min-app-version) shift 2 ;; # forge signs; the contract gates compatibility
        -*) die "unknown option $1" ;;
        *) [[ -z "$version" ]] || die "one version only"; version="$1"; shift ;;
    esac
done
[[ "$version" =~ ^[0-9]+(\.[0-9]+)+-r[0-9]+$ ]] || die "version must be <chromium version>-r<revision>, e.g. 152.0.7977.82-r1"
[[ -f "$key" ]] || die "no signing key (--key)"
[[ "$channel" == stable || "$channel" == beta ]] || die "channel must be stable or beta"
artifact="${artifact:-$FORGE/artifacts/$version}"
engine="$artifact/$ENGINE_NAME"
tag="chromium/$version"
upstream="${version%-r*}"
revision="${version##*-r}"

# MARK: The artifact

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

if ! $dry_run; then
    gh repo view "$REPO" >/dev/null 2>&1 || die "$REPO does not exist"
    gh release view "$tag" -R "$REPO" >/dev/null 2>&1 && die "$tag is already released"
fi

# MARK: Assets

out="$artifact/publish"
[[ -e "$out" ]] && trash "$out"
mkdir -p "$out"
zip_name="Refrax-Chromium-$version.zip"
zip="$out/$zip_name"
log "zipping the engine"
ditto -c -k --keepParent "$engine" "$zip"
sign() { openssl pkeyutl -sign -rawin -inkey "$key" -in "$1" | base64 >"$1.sig"; }
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
echo "$sha  $zip_name" >"$zip.sha256"
sign "$zip"
size=$(stat -f %z "$zip")
assets=("$zip" "$zip.sig" "$zip.sha256")
if [[ -d "$artifact/dSYMs" ]]; then
    log "zipping the dSYMs"
    dsyms="$out/Refrax-Chromium-$version-dSYMs.zip"
    ditto -c -k --keepParent "$artifact/dSYMs" "$dsyms"
    sign "$dsyms"
    assets+=("$dsyms" "$dsyms.sig")
fi

# MARK: Catalog

catalog="$out/engines.json"
if $dry_run || ! gh release download "$CATALOG_TAG" -R "$REPO" -p engines.json -D "$out" --clobber 2>/dev/null; then
    echo '{"schema": 1, "engines": {}}' >"$catalog"
fi
url="https://github.com/$REPO/releases/download/chromium%2F$version/$zip_name"
python3 - "$catalog" "$ENGINE_ID" "$channel" "$version" "$url" "$sha" "$size" "$contract" "$minimum_system" "$upstream" <<'PY'
import json, re, sys
path, engine, channel, version, url, sha, size, contract, minimum, upstream = sys.argv[1:]
catalog = json.load(open(path))
entry = catalog.setdefault("engines", {}).setdefault(engine, {"displayName": "Chromium", "channels": {}})
entry["displayName"] = "Chromium"
entry["channels"][channel] = {
    "version": version, "url": url, "sha256": sha, "sizeBytes": int(size), "contract": contract,
    "minimumSystemVersion": minimum, "notes": f"Chromium {upstream}",
}
# The checks EngineCatalog.problems() makes in Refrax.
problems = []
if catalog.get("schema") != 1:
    problems.append("schema is not 1")
for engine_id, engine_entry in catalog["engines"].items():
    if "stable" not in engine_entry["channels"]:
        problems.append(f"{engine_id}: no stable channel")
    for name, release in engine_entry["channels"].items():
        label = f"{engine_id}.channels.{name}"
        if not re.fullmatch(r"\d+(\.\d+)+-r\d+", release["version"]):
            problems.append(f"{label}.version")
        if not release["url"].startswith("https://github.com/kageroumado/refrax-engines/releases/download/"):
            problems.append(f"{label}.url")
        if release["version"] not in release["url"].rsplit("/", 1)[-1]:
            problems.append(f"{label}.url does not carry the version")
        if not re.fullmatch(r"[0-9a-f]{64}", release["sha256"]):
            problems.append(f"{label}.sha256")
        if release["sizeBytes"] <= 0:
            problems.append(f"{label}.sizeBytes")
        if not re.fullmatch(r"\d+\.\d+", release["contract"]):
            problems.append(f"{label}.contract")
if problems:
    sys.exit("catalog problems: " + "; ".join(problems))
json.dump(catalog, open(path, "w"), indent=2, sort_keys=True)
PY
sign "$catalog"
# Verify every signature with the public half, as Refrax will.
public="$out/key.pub"
openssl pkey -in "$key" -pubout -out "$public"
for signed in "$zip" "$catalog" ${dsyms:+"$dsyms"}; do
    base64 -d -i "$signed.sig" -o "$out/sig.bin"
    openssl pkeyutl -verify -pubin -inkey "$public" -rawin -in "$signed" -sigfile "$out/sig.bin" >/dev/null ||
        die "the signature of ${signed##*/} does not verify"
done
trash "$public" "$out/sig.bin"
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
    --latest=false "${prerelease[@]}" "${assets[@]}"

served=$(gh api "repos/$REPO/releases/tags/chromium%2F$version" --jq ".assets[] | select(.name == \"$zip_name\") | .digest")
[[ "$served" == "sha256:$sha" ]] || die "GitHub serves $zip_name with digest $served, not sha256:$sha; the catalog was not updated"

if ! gh release view "$CATALOG_TAG" -R "$REPO" >/dev/null 2>&1; then
    gh release create "$CATALOG_TAG" -R "$REPO" --title "Engine catalog" --latest=false \
        --notes "engines.json lists the engine releases Refrax installs; engines.json.sig is its Ed25519 signature."
fi
gh release upload "$CATALOG_TAG" -R "$REPO" --clobber "$catalog" "$catalog.sig"
log "published $tag; the catalog's $channel channel names it"
