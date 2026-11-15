#!/bin/zsh
# Writes Scripts/abi/<os>/<Framework>.exports from a macOS dyld shared cache: every symbol
# the framework's export trie holds, plus those of the dylibs it re-exports.
#
#   Scripts/abi/make-baseline.sh <dyld_shared_cache_arm64e> <os> <Framework>
#
# Fetch a release's cache onto the SSD first (~5 GB, a few minutes):
#   ipsw download ipsw --macos --version 26.1 --device Mac13,1 --dyld --dyld-arch arm64e \
#     -o /Volumes/Ugreen/Scratch/macos-26.1
#
# The list comes from `ipsw dyld tbd`, which reads the export trie and inlines re-exported
# images. An extracted dylib's symbol table is the wrong source: ipsw rebuilds it without
# the Swift overlay's symbols.
set -euo pipefail
export LC_ALL=C

cache=${1:?usage: make-baseline.sh <cache> <os> <Framework>}
os=${2:?usage: make-baseline.sh <cache> <os> <Framework>}
framework=${3:?usage: make-baseline.sh <cache> <os> <Framework>}

work=$(mktemp -d /Volumes/Ugreen/Scratch/abi-baseline.XXXXXX)
output=${0:A:h}/$os/$framework.exports
mkdir -p "${output:h}"

ipsw dyld tbd "$cache" "/System/Library/Frameworks/$framework.framework/Versions/A/$framework" \
  -o "$work" >/dev/null 2>&1
python3 - "$work/$framework.tbd" <<'PYTHON' | sort -u > "$output"
import re, sys

# Flow lists in a tapi .tbd: `key: [ a, b, 'c' ]`, possibly spanning lines.
prefixes = {
    "symbols": [""],
    "weak-symbols": [""],
    "thread-local-symbols": [""],
    "objc-classes": ["_OBJC_CLASS_$_", "_OBJC_METACLASS_$_"],
    "objc-eh-types": ["_OBJC_EHTYPE_$_"],
    "objc-ivars": ["_OBJC_IVAR_$_"],
}
text = open(sys.argv[1]).read()
for key, items in re.findall(r"([a-z-]+):\s*\[([^\]]*)\]", text):
    for name in re.split(r"[,\s]+", items):
        name = name.strip("'\"")
        for prefix in prefixes.get(key, []) if name else []:
            print(prefix + name)
PYTHON
images=$(grep -c '^install-name:' "$work/$framework.tbd")
trash "$work"
echo "$output: $(wc -l < "$output" | tr -d ' ') symbols from $images images"
