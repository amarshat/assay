#!/usr/bin/env bash
# Compile the vendored target C subroutine to LLVM bitcode for SAW.
# Usage: ./scripts/build_bitcode.sh <target_dir> <out.bc>
set -euo pipefail

TARGET_DIR="${1:?need target dir}"
OUT="${2:?need output .bc path}"
mkdir -p "$(dirname "$OUT")"

# Emit bitcode without optimizations that would obscure the source structure SAW reasons about.
# Adjust the file list to the exact subroutine files you vendored.
# Example shape (edit symbol/files):
#   clang -c -emit-llvm -O0 -g \
#     "$TARGET_DIR"/ntt.c "$TARGET_DIR"/reduce.c \
#     -o "$OUT"

echo "TODO: set the clang invocation for your vendored files, then remove this line."
echo "would build bitcode from $TARGET_DIR into $OUT"
