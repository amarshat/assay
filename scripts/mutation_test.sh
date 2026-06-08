#!/usr/bin/env bash
# Non-vacuity regression guard: deliberately break the Cryptol model (add 1 to montgomery_reduce's
# result) and assert that SAW *rejects* it. If SAW ever accepts a wrong model, the real proof has
# gone vacuous (e.g. an accidentally-unsatisfiable precondition) — this catches that in CI.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
export PATH="$ROOT/.tools/bin:$PATH"

[ -f build/mldsa_ntt.bc ] || { mkdir -p build; CLANG="${CLANG:-clang}" ./scripts/build_bitcode.sh target/pqclean build/mldsa_ntt.bc; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Mutate: append "+ 1" to the montgomery_reduce result line.
sed 's/^montgomery_reduce a = drop`{32} (\(.*\))$/montgomery_reduce a = drop`{32} (\1) + 1/' \
  model/cryptol/MLDSA_NTT.cry > "$TMP/M.cry"
grep -q '+ 1$' "$TMP/M.cry" || { echo "!! mutation-test: failed to inject the mutation" >&2; exit 1; }

cat > "$TMP/neg.saw" <<EOF
enable_experimental;
m <- llvm_load_module "$ROOT/build/mldsa_ntt.bc";
import "$TMP/M.cry";
let spec = do {
    a <- llvm_fresh_var "a" (llvm_int 64);
    llvm_precond {{ mont_in_range a }};
    llvm_execute_func [llvm_term a];
    llvm_return (llvm_term {{ montgomery_reduce a }});
};
llvm_verify m "PQCLEAN_MLDSA44_CLEAN_montgomery_reduce" [] true spec z3;
EOF

if saw "$TMP/neg.saw" >/dev/null 2>&1; then
  echo "!! MUTATION TEST FAILED: SAW ACCEPTED a deliberately-wrong (result+1) model — proof is VACUOUS." >&2
  exit 1
else
  echo ">> mutation-test OK: SAW correctly REJECTS the result+1 mutant (the proof is non-vacuous)."
fi
