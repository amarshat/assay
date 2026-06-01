#!/usr/bin/env bash
# Install & PIN the toolchain. Reproducibility is the product, so pin exact versions.
#
# Verified working on: macOS 26.3.1 (Darwin 25.x), Apple Silicon (arm64), 2026-06-01.
# Re-running is idempotent: it skips a tool if the pinned version is already extracted.
#
# After running, these must succeed (checkpoint 1 of docs/ROADMAP.md):
#   "$TOOLS_DIR"/bin/saw --version
#   "$TOOLS_DIR"/bin/isabelle version
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TOOLS_DIR="${TOOLS_DIR:-$ROOT/.tools}"          # gitignored; see /.tools/ in .gitignore
BIN_DIR="$TOOLS_DIR/bin"
DL_DIR="$TOOLS_DIR/downloads"
mkdir -p "$BIN_DIR" "$DL_DIR"

# ---------------------------------------------------------------------------
# PINNED VERSIONS  (mirror any change here into docs/ASSUMPTIONS.md)
# ---------------------------------------------------------------------------
SAW_VERSION="1.5.1"                              # first release shipping cryptol-to-isabelle
SAW_ASSET="saw-${SAW_VERSION}-macos-15-ARM64-with-solvers.tar.gz"
SAW_URL="https://github.com/GaloisInc/saw-script/releases/download/v${SAW_VERSION}/${SAW_ASSET}"

ISABELLE_VERSION="2025-2"                        # Isabelle2025-2 (Jan 2026)
ISA_ASSET="Isabelle${ISABELLE_VERSION}_macos.tar.gz"
ISA_URL="https://isabelle.in.tum.de/dist/${ISA_ASSET}"

# clang: we deliberately use the system Apple clang (recorded in ASSUMPTIONS.md), NOT a vendored one.
EXPECTED_CLANG="Apple clang version 17.0.0 (clang-1700.0.13.5)"

# ---------------------------------------------------------------------------
fetch() {  # fetch <url> <dest-file>
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then echo ">> cached: $dest"; return; fi
  echo ">> downloading $url"
  curl -fL --retry 3 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

link() {   # symlink <target> into BIN_DIR
  local target="$1" name="$2"
  ln -sf "$target" "$BIN_DIR/$name"
}

# --- SAW + Cryptol + cryptol-to-isabelle (Galois) ---------------------------
SAW_HOME="$TOOLS_DIR/saw-${SAW_VERSION}"
if [[ ! -x "$SAW_HOME/bin/saw" ]]; then
  fetch "$SAW_URL" "$DL_DIR/$SAW_ASSET"
  echo ">> extracting SAW ${SAW_VERSION}"
  rm -rf "$SAW_HOME" && mkdir -p "$SAW_HOME"
  tar -xzf "$DL_DIR/$SAW_ASSET" -C "$SAW_HOME" --strip-components=1
fi
for b in saw cryptol cryptol-to-isabelle abc z3 yices yices-smt2 cvc4 cvc5; do
  [[ -e "$SAW_HOME/bin/$b" ]] && link "$SAW_HOME/bin/$b" "$b"
done

# macOS arm64 gotchas, both of which cause a silent "Killed: 9" on exec:
#   (1) downloaded files carry com.apple.quarantine; an ad-hoc-signed (non-notarized)
#       binary that is quarantined is SIGKILLed by Gatekeeper. Strip it.
#   (2) every arm64 binary must carry at least an ad-hoc signature. Galois tarballs are
#       signed ad-hoc already, but re-sign defensively in case extraction altered them.
xattr -dr com.apple.quarantine "$SAW_HOME" 2>/dev/null || true
if command -v codesign >/dev/null; then
  find "$SAW_HOME/bin" -type f -exec sh -c 'file "$1" | grep -q Mach-O' _ {} \; \
    -exec codesign --force --sign - {} \; 2>/dev/null || true
fi

# --- Isabelle ---------------------------------------------------------------
ISA_HOME="$TOOLS_DIR/Isabelle${ISABELLE_VERSION}"
if [[ ! -x "$ISA_HOME/bin/isabelle" ]] && [[ -z "$(find "$ISA_HOME" -name isabelle -path '*/bin/*' 2>/dev/null | head -1)" ]]; then
  fetch "$ISA_URL" "$DL_DIR/$ISA_ASSET"
  echo ">> extracting Isabelle ${ISABELLE_VERSION}"
  rm -rf "$ISA_HOME" && mkdir -p "$ISA_HOME"
  # macOS tarball unpacks to an .app bundle; --strip-components flattens it to ISA_HOME.
  tar -xzf "$DL_DIR/$ISA_ASSET" -C "$ISA_HOME" --strip-components=1
fi
xattr -dr com.apple.quarantine "$ISA_HOME" 2>/dev/null || true
# The CLI launcher lives at <app>/bin/isabelle (or Contents/Resources/.../bin/isabelle).
ISA_BIN="$(find "$ISA_HOME" -type f -name isabelle -path '*/bin/*' | head -1 || true)"
[[ -n "$ISA_BIN" ]] && link "$ISA_BIN" "isabelle"

# --- clang (system) ---------------------------------------------------------
if ! clang --version | grep -qF "$EXPECTED_CLANG"; then
  echo "!! WARNING: system clang != pinned '$EXPECTED_CLANG' — record the delta in ASSUMPTIONS.md" >&2
fi

# ---------------------------------------------------------------------------
echo
echo ">> toolchain installed under $TOOLS_DIR"
echo ">> add to PATH for this shell:   export PATH=\"$BIN_DIR:\$PATH\""
echo ">> verifying versions:"
"$BIN_DIR/saw" --version || { echo "!! saw failed to run" >&2; exit 1; }
"$BIN_DIR/isabelle" version || { echo "!! isabelle failed to run" >&2; exit 1; }
clang --version | head -1
echo ">> setup complete."
