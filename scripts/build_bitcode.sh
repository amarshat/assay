#!/usr/bin/env bash
# Compile the vendored target C to LLVM bitcode for SAW.
# Usage: ./scripts/build_bitcode.sh <target_dir> <out.bc>
#
# ntt() (in ntt.c) calls montgomery_reduce (in reduce.c), so both must end up in one module. There's
# no llvm-link in the toolchain, so we compile a single translation unit that #includes both vendored
# .c files. The wrapper lives in the build dir — the vendored files are not edited. -O0 -g keeps the
# source structure SAW reasons about.
set -euo pipefail

TARGET_DIR="${1:?need target dir}"
OUT="${2:?need output .bc path}"
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"

CLANG="${CLANG:-clang}"

COMBINED="$OUT_DIR/_combined.c"
printf '#include "reduce.c"\n#include "ntt.c"\n' > "$COMBINED"

WRAPV="${OUT%.bc}_wrapv.bc"

set -x
# Default (nsw): used for the reduce.c proofs, which assert no signed-overflow UB in range.
"$CLANG" -c -emit-llvm -O0 -g -I "$TARGET_DIR" "$COMBINED" -o "$OUT"
# -fwrapv (two's-complement wrapping, no nsw): used for the forward-NTT functional-equivalence
# proof. The NTT does unreduced int32 add/sub that overflow for unbounded inputs; proving
# overflow-freedom needs coefficient-bound composition (future work). Under wrapping the C computes
# exactly the mod-2^n Cryptol model, so functional equivalence holds for all inputs.
"$CLANG" -c -emit-llvm -O0 -g -fwrapv -I "$TARGET_DIR" "$COMBINED" -o "$WRAPV"
set +x

echo ">> built bitcode: $OUT and $WRAPV"
