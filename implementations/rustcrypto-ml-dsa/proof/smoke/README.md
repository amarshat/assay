# SAW-Rust pipeline sanity check

Five-line Rust function + a Cryptol spec, used to confirm the toolchain end to end before tackling
the real crate. Confirmed passing 2026-06-11 (mir-json schema v8 -> SAW 1.5.1 -> `mir_verify` ->
`Proof succeeded!`). Caught the schema v11-vs-v8 mismatch that an install-only check would have missed.
