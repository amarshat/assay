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

set -x
"$CLANG" -c -emit-llvm -O0 -g -I "$TARGET_DIR" "$COMBINED" -o "$OUT"
set +x

echo ">> built bitcode: $OUT"
