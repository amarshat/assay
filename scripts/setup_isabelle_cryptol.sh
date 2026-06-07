#!/usr/bin/env bash
# Prerequisite for the Isabelle leg (pipeline steps 3-4): install the AFP and build the SAW
# `Cryptol` Isabelle support session that cryptol-to-isabelle output depends on.
#
# This is SEPARATE from scripts/setup.sh because it is heavy (AFP build incl. Berlekamp_Zassenhaus)
# and only needed once the Isabelle leg is in play. Idempotent: skips work already done.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TOOLS_DIR="${TOOLS_DIR:-$ROOT/.tools}"
DL_DIR="$TOOLS_DIR/downloads"
BIN="$TOOLS_DIR/bin"
mkdir -p "$DL_DIR"
export PATH="$BIN:$PATH"

AFP_ASSET="afp-current.tar.gz"
AFP_URL="https://www.isa-afp.org/release/${AFP_ASSET}"
SAW_ISA_COMPONENT="$TOOLS_DIR/saw-1.5.1/lib/isabelle"   # ships session Cryptol_Base/Cryptol

# --- 1. download + extract AFP ---
if [[ -f "$DL_DIR/$AFP_ASSET" ]]; then echo ">> cached AFP"; else
  echo ">> downloading AFP ($AFP_URL)"
  curl -fL --retry 3 -o "$DL_DIR/$AFP_ASSET.partial" "$AFP_URL"
  mv "$DL_DIR/$AFP_ASSET.partial" "$DL_DIR/$AFP_ASSET"
fi
AFP_DIR="$(find "$TOOLS_DIR" -maxdepth 1 -type d -name 'afp-*' | head -1 || true)"
if [[ -z "$AFP_DIR" ]]; then
  echo ">> extracting AFP"
  tar -xzf "$DL_DIR/$AFP_ASSET" -C "$TOOLS_DIR"
  AFP_DIR="$(find "$TOOLS_DIR" -maxdepth 1 -type d -name 'afp-*' | head -1)"
fi
echo ">> AFP at: $AFP_DIR"

# --- 2. register components (idempotent; -u appends only if absent) ---
echo ">> registering AFP + SAW Cryptol components with Isabelle"
isabelle components -u "$AFP_DIR/thys"
isabelle components -u "$SAW_ISA_COMPONENT"

# --- 3. build the Cryptol support image (the long part) ---
echo ">> building Isabelle session 'Cryptol' (this is the heavy step: Berlekamp_Zassenhaus, Word_Lib, Cryptol)"
# timeout_scale multiplies AFP sessions' declared per-session timeouts. Slow/loaded machines (e.g.
# CI runners) otherwise hit '*** Timeout' on heavy AFP entries like Jordan_Normal_Form. Override
# with ISABELLE_TIMEOUT_SCALE; 10 is generous headroom.
isabelle build -o timeout_scale="${ISABELLE_TIMEOUT_SCALE:-10}" -bv Cryptol

echo ">> DONE: Cryptol Isabelle session built. cryptol-to-isabelle output can now be checked."
