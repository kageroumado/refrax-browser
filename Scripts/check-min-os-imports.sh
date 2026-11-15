#!/bin/zsh
# Fails when a Mach-O in the app strongly imports a symbol that the oldest supported macOS
# does not export. dyld kills an app at launch over one such import (refrax-browser#13:
# six text-extraction classes missing from macOS 26.1's WebKit).
#
#   Scripts/check-min-os-imports.sh <Refrax.app>
#
# Rilmazafone runs it as the pre-sign hook of plans/refrax.releaseplan, after archive.
# Each Scripts/abi/<os>/<Framework>.exports file is one baseline: every symbol that
# framework exports on that macOS, re-exports included. A framework without a baseline is
# not checked. Regenerate a baseline with Scripts/abi/make-baseline.sh.
set -euo pipefail
export LC_ALL=C

app=${1:?usage: check-min-os-imports.sh <app>}
baselines=${0:A:h}/abi

missing=0
for baseline in "$baselines"/*/*.exports(N); do
  os=${baseline:h:t}
  framework=${baseline:t:r}
  for binary in ${(f)"$(find "$app/Contents" -type f -perm +111)"}; do
    file -b "$binary" | grep -q Mach-O || continue
    absent=$(
      dyld_info -imports "$binary" \
        | awk -v from="(from $framework)" 'index($0, from) && !index($0, "[weak-import]") {print $2}' \
        | sort -u \
        | comm -23 - "$baseline"
    )
    [[ -z $absent ]] && continue
    echo "${binary#$app/} strongly imports from $framework what macOS $os lacks:" >&2
    print -r -- "$absent" | sed 's/^/  /' >&2
    missing=1
  done
done

if (( missing )); then
  echo "Weak-import these (__attribute__((weak_import)) on the declaration) and check for them at runtime." >&2
  exit 1
fi
echo "Strong imports resolve on every baseline in $baselines."
