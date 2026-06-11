#!/usr/bin/env bash
# SAW-Rust toolchain for the `implementations/` Rust assays (e.g. RustCrypto ml-dsa).
#
# Confirmed compatible with the pinned SAW 1.5.1: this mir-json commit emits MIR JSON SCHEMA v11,
# which SAW 1.5.1 expects. (Verified 2026-06-11.) Everything is pinned, per the project's
# reproducibility-is-the-product rule.
#
# After running, export:   export SAW_RUST_LIBRARY_PATH="<repo>/.tools/rlibs"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"                                   # gitignored, same as setup.sh
NIGHTLY="nightly-2025-09-14"                           # pinned by mir-json's rust-toolchain.toml
MIRJSON_COMMIT="13232df733daf3346463d82b13b846ffd21aafe9"  # GaloisInc/mir-json, schema v11
MIRJSON_DIR="$TOOLS/mir-json"
RLIBS="$TOOLS/rlibs"

mkdir -p "$TOOLS"

# 1. Rust (rustup) -- install if absent
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"

# 2. the pinned nightly, with the compiler internals mir-json links against
rustup toolchain install "$NIGHTLY" --force --component rustc-dev,rust-src

# 3. build + install mir-json at the pinned commit (schema v11)
if [ ! -d "$MIRJSON_DIR/.git" ]; then
  git clone https://github.com/GaloisInc/mir-json.git "$MIRJSON_DIR"
fi
( cd "$MIRJSON_DIR" && git fetch --depth 1 origin "$MIRJSON_COMMIT" 2>/dev/null || git fetch origin
  git checkout -q "$MIRJSON_COMMIT"
  cargo "+$NIGHTLY" install --path . --locked --force )
mir-json --version

# 4. translate the mir-json-specific Rust stdlibs -> rlibs/  (needed for SAW to resolve std)
( cd "$MIRJSON_DIR" && mir-json-translate-libs )
ln -sfn "$MIRJSON_DIR/rlibs" "$RLIBS"

echo
echo "SAW-Rust toolchain ready (mir-json @ ${MIRJSON_COMMIT:0:12}, schema v11; SAW 1.5.1 compatible)."
echo "Add to your environment so SAW finds the translated stdlibs:"
echo "  export SAW_RUST_LIBRARY_PATH=\"$RLIBS\""
