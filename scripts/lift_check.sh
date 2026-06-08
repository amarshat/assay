#!/usr/bin/env bash
# Mechanized composition-soundness check (closes the reviewers' gap #1):
# verify that the COMMITTED Isabelle model `spec/isabelle/MLDSA_NTT.thy` is byte-for-byte what
# `cryptol-to-isabelle` produces from `model/cryptol/MLDSA_NTT.cry` — i.e. the lifted theory the
# Isabelle proof reasons about is exactly the lift of the Cryptol model that SAW checks against the C.
#
# Without this, the end-to-end chain  C ≡ Cryptol (SAW)  ∘  model ≡ spec (Isabelle)  relies on the
# UNCHECKED premise `thy = lift(cry)`, maintained by eyeball. This makes it a tool-enforced gate.
#
# Needs only the SAW bundle (cryptol-to-isabelle + z3) on PATH — NOT a full Isabelle build.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
export PATH="$ROOT/.tools/bin:$PATH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ">> regenerating Isabelle model from model/cryptol/MLDSA_NTT.cry"
cryptol-to-isabelle -s model/cryptol/MLDSA_NTT.cry -d "$TMP" --all-modules >/dev/null

if diff -u spec/isabelle/MLDSA_NTT.thy "$TMP/MLDSA_NTT.thy"; then
  echo ">> lift-check OK: spec/isabelle/MLDSA_NTT.thy == cryptol-to-isabelle(model/cryptol/MLDSA_NTT.cry)"
else
  echo "!! lift-check FAILED: the committed Isabelle model is OUT OF SYNC with the Cryptol model." >&2
  echo "!! The end-to-end chain is only sound if they match. Regenerate with:" >&2
  echo "!!   cryptol-to-isabelle -s model/cryptol/MLDSA_NTT.cry -d spec/isabelle --all-modules" >&2
  exit 1
fi
