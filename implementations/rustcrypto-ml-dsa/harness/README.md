# Verification harness

Thin crate that depends on `ml-dsa` (default-features off, `alloc` on) and calls the public
deterministic entry `SigningKey::<MlDsa44>::from_seed`, so the crate's internal arithmetic is
monomorphized into the MIR. Because dev-dependencies are not transitive, this avoids the `der` crate
(which mir-json cannot translate). Build:

    export SAW_RUST_LIBRARY_PATH=<repo>/.tools/rlibs
    cargo +nightly-2025-09-14 saw-build      # -> target/.../mldsa_harness-*.linked-mir.json
