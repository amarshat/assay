# RustCrypto ml-dsa — structural notes and candidate smells

Working notes from reading the vendored source (`target/ml-dsa-0.1.1`). These ground the v2.1/v2.2
plan. Nothing here is a finding yet; "smells" are places a bug could plausibly hide, to check.

## Structure
- The scheme logic lives in `ml-dsa` (`signing.rs`, `verifying.rs`, `hint.rs`, `sampling.rs`,
  `encode.rs`, `param.rs`).
- **The field/polynomial/NTT arithmetic lives in `module_lattice` `0.2.3`** (a separate RustCrypto
  crate: `define_field!`, `Elem`, `Polynomial`, `NttPolynomial`, `MultiplyNtt`). `ml-dsa/algebra.rs`
  only defines the `BaseField` (q = 8 380 417) and the Barrett `reduce` trait; `ntt.rs` only builds
  the zetas table and calls `module_lattice`'s NTT. **So a full assay must also vendor and model
  `module_lattice` — and that crate is shared with RustCrypto `ml-kem`, so verifying it covers both
  ML-DSA and ML-KEM arithmetic (double impact).**
- Reduction here is **Barrett**, generic over the modulus (q, 2^d, 2*gamma2), and constant-time
  (`ct_select`, `CtLt`), not Montgomery as in the PQClean reference. Different proof obligations.

## Candidate smells (to verify, not yet findings)
1. **`ct_div` precision (`algebra.rs`).** Constant-time division by a compile-time constant via
   Barrett, with `SHIFT = 48` and the documented precondition "requires x < Q (~2^23)". Claim to
   check: does it return exactly `floor(x / M)` for *all* `x < Q` and every divisor M used? Barrett
   precision off-by-one at some x is the classic failure mode.
2. **Const-computed zetas (`ntt.rs`).** `ZETA_POW_BITREV` is built in a `const fn` (ZETA = 1753,
   `bitrev8`, manual `% BaseField::QL` reductions because operator overloading isn't const), with the
   comment that the values "match FIPS 204 Appendix B." Checkable: do all 256 entries actually equal
   the FIPS 204 Appendix B zetas? A const-eval mistake would be a real defect.
3. **Hint indices (`hint.rs`, `verifying.rs`).** The known GHSA bug was here (`<=` vs `<` letting
   duplicate hint indices pass, violating FIPS 204's strictly-increasing rule). Verify the *current*
   hint encode/decode/use logic conforms to the spec; this is the highest-value spec-conformance
   target.
4. **`decompose` (`signing.rs`/`algebra.rs`).** Home of the RUSTSEC-2025-0144 timing side-channel.
   Functional correctness vs FIPS 204 `Decompose`/`HighBits`/`LowBits`; we are a functional tool, not
   a CT tool, but functional bugs here are in scope.
5. **Barrett `reduce` bound.** Prove `reduce(x) == x mod m` and the tight output bound for the moduli
   used, analogous to the v1 reduce32 work but Barrett-generic.

## To vendor next
- `module_lattice 0.2.3` (the arithmetic), alongside `ml-dsa 0.1.1`. (Done.)

## Build bring-up (v2.1 spike, 2026-06-11)
`cargo saw-build` compiles the whole dependency graph to MIR **except `der 0.8.0`**, where mir-json
panics: `internal error: entered unreachable code: slice type should not occur here`
(`src/analyz/ty_json.rs:1346`). `der` is a known limitation of this mir-json (schema v8); it is pulled
in only by the crate's **dev-dependencies** (the `tests/pkcs8.rs` test) and the `pkcs8` default
feature, neither of which is the arithmetic/hint logic we audit.
- `cargo tree -e normal --no-default-features --features alloc` shows **no `der`** in the normal
  graph, so the lib itself is clean; `cargo saw-build` drags `der` in because it also builds the
  test/dev targets.
- **Next step (the fix):** a separate *harness* crate that depends on
  `ml-dsa = { default-features = false, features = ["alloc"] }` and calls the public API
  (`MlDsa44` key_gen/sign/verify) to force monomorphization of the internal `reduce`/NTT/hint
  functions. Dev-dependencies are not transitive, so the harness pulls no `der`. Then `cargo saw-build`
  the harness, and `mir_verify` the specific internal functions by name from the linked MIR.
- Status: toolchain + pipeline proven (smoke); real-crate MIR blocked only on the der dev-dep, fix
  identified (harness). This is API-plumbing, not a fundamental unknown.

## v2.1 real-crate MIR + first verify attempt (2026-06-11) — REACHED THE ARITHMETIC
The harness crate works: `SigningKey::<MlDsa44>::from_seed` forces monomorphization, and
`cargo saw-build` of the harness links **36 MIR files** including the real `ml_dsa`, `module_lattice`,
`typenum`, `keccak` — **no der**. The crate is 2016 monomorphized functions. The Barrett reduce is
`ml_dsa::algebra::BarrettReduce::reduce::_inst7d46f3ac9454f524` (takes `u32`, returns `u32`).
SAW loads and *simulates* it; the proof `reduce(x) == x % q` is set up.

Blockers reached (this is the shape of verifying CT crypto with SAW), in order:
1. `core::hint::black_box` (optimizer barrier) — SAW can't translate it. **Fixed:** sound identity
   override (`mir_unsafe_assume_spec`, one `u8` instance). Applies cleanly.
2. `cmov` crate (`ct_select`/`ct_lt`) uses **inline aarch64 assembly** — SAW does MIR/LLVM, not asm.
   `cmov` has a portable `soft.rs` backend but it's cfg-gated to non-asm arches, so the host build
   picks the asm path. **Path forward (not yet done):** override the constant-time primitives
   (`ct_select`, `ct_lt`, `ct_gt`, `ct_eq`) with functional specs — a small, fixed, sound set that
   unblocks all the arithmetic at once. Alternative: build for a target whose cmov picks `soft`
   (needs stdlibs re-translated for that target — heavier).

Takeaway for the writeup: unlike the PQClean reference C (plain arithmetic), this crate is built on a
constant-time primitive layer (`cmov` asm, `black_box`). Functionally verifying it with SAW requires
modeling that CT layer with overrides first. That is the v2.1 next task, and it is bounded.

## v2.1 FIRST REAL VERIFY — DONE (2026-06-12): Barrett `reduce` ≡ mod 2^d, all u32
`proof/reduce/reduce.saw` now closes (`saw` exits 0; `Proof succeeded!`). The cmov blocker is cleared.
- **The CT-layer override that unblocked it.** Only ONE asm primitive is actually reachable from the
  keygen harness: `<u32 as cmov::Cmov>::cmovnz` (`backends::aarch64::{impl#1}::cmovnz`). I overrode it
  with `mir_unsafe_assume_spec` carrying its exact functional contract
  `*self = (cond != 0) ? *value : *self` — which is precisely what the `tst/csel NE` asm computes
  (verified by reading cmov-0.5.4 `src/backends/aarch64.rs`). Plus the pre-existing `black_box`
  identity override. That's the whole CT layer for this surface — `cmovz`, `CmovEq`, and the u16/u64
  instances are NOT reached here, so two overrides suffice. (`ct_select`/`ct_lt` are plain MIR that
  bottoms out in `cmovnz`; overriding the leaf composes them automatically.)
- **Soundness of the override.** It is an *assumed* spec (not proven against the asm — SAW can't see
  the asm). It is sound iff it matches the asm's input/output relation, which it does by construction.
  This is the standard, documented way SAW handles inline-asm/intrinsic leaves. Recorded as an
  assumption in `docs/ASSUMPTIONS.md`.
- **WHICH instance — important correction to the earlier guess.** The previous note assumed the
  monomorphized `reduce` (`_inst7d46f3ac9454f524`) was the mod-q one. It is NOT. The symbolic term
  shows `MULTIPLIER = 32768 = 2^15`, `SHIFT = 28`, `M = 8192 = 2^d` — the **Power2Round** modulus.
  That's the only `reduce` instance `from_seed` keygen forces into the MIR. For this power-of-two M
  the Barrett quotient `(x*2^15)>>28 = x>>13 = floor(x/8192)` is **exact for every u32**, so
  `reduce(x) = x mod 8192` unconditionally (no `x < M^2` precondition needed — that bound only bites
  for the non-power-of-two moduli q and 2*gamma2).
- **Verified claim:** `reduce(x) == x % 8192` for all `u32 x`. Non-vacuity checked: mutating the spec
  to `x % 8191` makes SAW fail (counterexample), so the proof has real content.
- **To reach mod q (v2.2):** need a harness that exercises NTT multiply / the sign or verify path so
  the M=q monomorphization lands in the MIR; then the proof carries a real `x < M^2` precondition and
  the conditional-subtract branch becomes live (the genuinely bug-prone case — Barrett precision).

## RESTART CAVEAT + how to rebuild the MIR (read first after reboot)
The linked MIR `reduce.saw` loads lives in **`/tmp/mldsa-harness/.../mldsa_harness-*.linked-mir.json`**.
`/tmp` is volatile — **it is gone after a reboot**, and the hash in the filename can change on rebuild,
so `proof/reduce/reduce.saw`'s `mir_load_module` path will need updating. To regenerate:
```
# 1. toolchain (installs pinned nightly-2025-09-14 + mir-json @7e12cece, schema v8; rlibs -> .tools/rlibs)
./scripts/setup_rust.sh
export SAW_RUST_LIBRARY_PATH=$PWD/.tools/rlibs
# 2. build the harness crate to MIR (dev-deps non-transitive => no `der`)
cd implementations/rustcrypto-ml-dsa/harness
mkdir -p /tmp/mldsa-harness
CARGO_TARGET_DIR=/tmp/mldsa-harness cargo +nightly-2025-09-14 saw-build
# 3. point reduce.saw at the new path, then:  saw proof/reduce/reduce.saw   (expect: Proof succeeded!, exit 0)
ls /tmp/mldsa-harness/target/aarch64-apple-darwin/debug/deps/*.linked-mir.json
```
Note: a better fix (part of TODO-c below) is to build into a repo-local, gitignored dir
(`implementations/rustcrypto-ml-dsa/build/`) instead of `/tmp`, and have `reduce.saw` take the path as
an arg / env var so CI and reboots don't break it.

## TODO after restart — agreed plan a / b / c
- **(a) Commit this milestone.** DONE in the same commit that saved this note (the first real verify +
  cmov overrides + ASSUMPTIONS/NOTES/README updates).
- **(b) v2.2 harness to reach mod-q `reduce`.** Extend `harness/src/lib.rs` to also call sign and/or
  verify (`SigningKey::sign` / `VerifyingKey::verify`) so the NTT-multiply path monomorphizes the
  M = q (and 2*gamma2) `reduce` instances. Then write the mod-q proof: spec `reduce(x) == x % q` under
  the **`x < M^2`** precondition (the conditional-subtract branch is now LIVE — this is the
  Barrett-precision case where a real bug could hide). Expect possibly more cmov widths (u64) and more
  CT leaves to override — enumerate with the `python3 ... 'cmov' in name` scan and add specs as needed.
- **(c) Wire `rust.yml` CI** once (a) lands and the build path is repo-local (not `/tmp`): a workflow
  mirroring `saw.yml` that runs `setup_rust.sh`, builds the harness MIR, and runs `saw reduce.saw`,
  gated to exit 0. Cache `.tools/rlibs` + the nightly toolchain. Do NOT gate on it until the path is
  deterministic (see RESTART CAVEAT) and the build is reproducible on a clean runner.
