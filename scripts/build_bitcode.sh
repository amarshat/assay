#!/usr/bin/env bash
# Compile the vendored target C subroutine to LLVM bitcode for SAW.
# Usage: ./scripts/build_bitcode.sh <target_dir> <out.bc>
#
# v1 scope: only reduce.c is needed (it contains montgomery_reduce). Its compile closure is
# reduce.c + reduce.h + params.h, all in <target_dir>. We compile at -O0 with debug info so the
# source structure SAW reasons about is preserved.
set -euo pipefail

TARGET_DIR="${1:?need target dir}"
OUT="${2:?need output .bc path}"
mkdir -p "$(dirname "$OUT")"

CLANG="${CLANG:-clang}"

set -x
"$CLANG" -c -emit-llvm -O0 -g \
  -I "$TARGET_DIR" \
  "$TARGET_DIR/reduce.c" \
  -o "$OUT"
set +x

echo ">> built bitcode: $OUT"
