#!/bin/zsh
# Builds libshields.a (Engines/Shared/shields, adblock-rust behind a C ABI) for Refrax.app.
#
# Runs as the "Shields" aggregate target's script phase, which Refrax depends on. Cargo decides
# what is stale, so the phase runs on every build and a no-op build takes a fraction of a second.
# The library is always built optimized: the debug build of adblock-rust is too slow to browse
# with. Outside Xcode it builds into /Volumes/Ugreen/Build/refrax-shields (or ./build/shields
# where that disk is absent) and copies the library next to it.
#
# SHIELDS_OFFLINE=1 builds from the local cargo cache only (after `cargo fetch --locked`).

set -euo pipefail

repository="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
manifest="$repository/Engines/Shared/shields/Cargo.toml"

if [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
    target_directory="$DERIVED_FILE_DIR/shields"
    products="$BUILT_PRODUCTS_DIR"
elif [[ -d /Volumes/Ugreen ]]; then
    target_directory=/Volumes/Ugreen/Build/refrax-shields/xcode
    products=/Volumes/Ugreen/Build/refrax-shields
else
    target_directory="$repository/build/shields"
    products="$repository/build"
fi

cargo_binary="${CARGO:-}"
if [[ -z "$cargo_binary" ]]; then
    for candidate in "$(command -v cargo 2>/dev/null || true)" "$HOME/.cargo/bin/cargo" /opt/homebrew/bin/cargo; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            cargo_binary="$candidate"
            break
        fi
    done
fi
if [[ -z "$cargo_binary" ]]; then
    echo "error: cargo not found. Install Rust (https://rustup.rs), then build again." >&2
    exit 1
fi

arguments=(build --release --locked --target aarch64-apple-darwin
           --manifest-path "$manifest" --target-dir "$target_directory")
if [[ "${SHIELDS_OFFLINE:-0}" == 1 ]]; then
    arguments+=(--offline)
fi

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.1}"

"$cargo_binary" "${arguments[@]}"

mkdir -p "$products"
library="$target_directory/aarch64-apple-darwin/release/libshields.a"
if ! cmp -s "$library" "$products/libshields.a"; then
    cp "$library" "$products/libshields.a"
fi
