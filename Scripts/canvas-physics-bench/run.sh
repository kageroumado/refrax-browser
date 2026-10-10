#!/bin/bash
# Builds CanvasPhysics.swift with the bench driver and runs it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${TMPDIR:-/tmp}/canvas-physics-bench"
swiftc -O -o "$out" "$here/Shim.swift" "$here/../../Refrax/Features/Canvas/CanvasPhysics.swift" "$here/main.swift"
"$out"
