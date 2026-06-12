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

## v2.2 DONE (2026-06-12): ALL THREE Barrett moduli verified, mod-q conditional-subtract live
`proof/reduce/reduce.saw` now proves `reduce(x) == x mod M` for **all u32 x** for every modulus the
crate instantiates — M = q = 8380417, M = 2*gamma2 = 190464 (ML-DSA-44), M = 2^d = 8192. `saw` exits
0; non-vacuity checked per-instance (mutated moduli 8380416 / 190465 / 8191 each yield a
counterexample).
- **Harness extension that forced the instances:** `sign44` (via `Signer`, deterministic — no RNG
  plumbing needed) and `verify44` (via `Verifier`) in `harness/src/lib.rs`. The mod-q instance comes
  from the final `z.mod_plus_minus::<SpecQ>()` in `signing.rs:362`; 2*gamma2 from `decompose`. MIR
  grew 2016 → 2836 fns.
- **Instance identification** (by MULTIPLIER constant in the MIR body): `_inst3390e630c0020d00` has
  8396807 = floor(2^46/q) ⇒ M = q; `_inst805f6f80791ad6a1` has 360800 = floor(2^36/190464) ⇒
  M = 2*gamma2; `_inst7d46f3ac9454f524` has 32768 ⇒ M = 2^d (the v2.1 one).
- **Stronger than planned: NO precondition.** The plan expected `x < M^2`. But q and 2*gamma2 both
  exceed 2^16, so M^2 > 2^32 and the Barrett condition holds for every u32 — the proof quantifies
  over the full domain, conditional subtract live. (For 2^d = 8192, M^2 = 2^26 < 2^32 does NOT cover
  u32, but power-of-two exactness does — the v2.1 argument.)
- **Trust base unchanged.** sign/verify monomorphize one new asm leaf (`<u32 as CmovEq>::cmoveq`,
  used by `ct_eq` in decompose) but it is NOT on the reduce path, so the proofs still need only the
  two v2.1 assumed specs (`black_box` identity + `<u32 as Cmov>::cmovnz`). `cmoveq`'s spec
  (`*output = (self == rhs) ? input : *output`, from cmov-0.5.4's eor/cmp/csel-EQ) will be needed for
  the decompose/hint surface later — documented in ASSUMPTIONS.md.
- **Parameter-set scope:** harness is MlDsa44; ML-DSA-65/87's 2*gamma2 = 523776 is a different
  monomorphization, not in this MIR, not claimed. q and 2^d are parameter-set-independent.
- This closes NOTES smell #5 (Barrett reduce) for ML-DSA-44's moduli. Smells #1 (ct_div), #2 (zetas
  vs FIPS 204 App B), #3 (hint logic) remain the focused-audit queue.

## How to rebuild the MIR (now repo-local and reboot-proof)
The build lives in the gitignored **`implementations/rustcrypto-ml-dsa/build/`** (no more `/tmp`),
and the build step refreshes a **stable symlink** `build/mldsa_harness.linked-mir.json` that
`proof/reduce/reduce.saw` loads via a relative path — so rebuilds (which change the hash in the real
filename) and reboots no longer break the script. To regenerate from scratch:
```
# 1. toolchain (installs pinned nightly-2025-09-14 + mir-json @7e12cece, schema v8; rlibs -> .tools/rlibs)
./scripts/setup_rust.sh
export SAW_RUST_LIBRARY_PATH=$PWD/.tools/rlibs
# 2. build the harness crate to MIR (dev-deps non-transitive => no `der`)
cd implementations/rustcrypto-ml-dsa/harness
CARGO_TARGET_DIR=$PWD/../build cargo +nightly-2025-09-14 saw-build
# 3. refresh the stable symlink (the hash can change when deps/toolchain change)
cd ../build && ln -sf aarch64-apple-darwin/debug/deps/mldsa_harness-*.linked-mir.json mldsa_harness.linked-mir.json
# 4. from the repo root:  .tools/bin/saw implementations/rustcrypto-ml-dsa/proof/reduce/reduce.saw
#    (expect: three "Proof succeeded!" + exit 0)
```

## TODO — remaining plan
- **(a) Commit v2.1 milestone.** DONE (5b9eb74).
- **(b) v2.2 mod-q reduce.** DONE (this section).
- **(c) `rust.yml` CI: WIRED (2026-06-12), pending first green run on a clean runner.** Mirrors
  `saw.yml` on macos-15 arm64: setup.sh (SAW) + setup_rust.sh (skipped when the mir-json/nightly/rlibs
  caches hit), builds the harness MIR repo-locally, refreshes the symlink, runs `saw reduce.saw`, and
  a non-vacuity guard (mutated moduli must FAIL). Do NOT treat it as a gate (branch protection) until
  it has proven reproducible on a clean runner — the first cache-miss run builds mir-json + translates
  stdlibs and will be slow (~tens of minutes).
- **(d) The focused audit:** #1, #2, and the scalar half of #3 DONE 2026-06-12 (below); remaining:
  `bit_pack`/`bit_unpack` (the literal GHSA site) + polynomial/vector hint wrappers.

## Focused audit results (2026-06-12): smells #1 and #2 — both CLEAN, no findings
- **#1 ct_div Barrett precision: VERIFIED.** `proof/ctdiv/ct_div.saw` (saw exits 0):
  `ct_div(x) == floor(x / 190464)` (the only monomorphized divisor, TwoGamma2 for MlDsa44; same
  `_inst805f6f80791ad6a1` generic hash as the 2*gamma2 reduce) for **all x < Q = 8380417** — exactly
  the documented contract. No overrides needed (straight-line u64 mul/shift). Non-vacuity: divisor
  mutated to 190465 fails. The documented `x < Q` precondition is genuinely load-bearing: dropping it
  yields a counterexample at x = 4144496639 (ct_div returns 21760, true floor 21759 — the ceiling
  multiplier `div_ceil(2^48, M)` over-estimates); first failure of form kM-1 is at x = 2369753087,
  ~283x above Q, confirmed by direct computation. Callers (decompose, diff < q) stay in-contract.
- **#2 const zetas table: VERIFIED (artifact-level).** `proof/zetas/check_zetas.py` (exit 0, wired
  into rust.yml): all 16 embedded copies of `ZETA_POW_BITREV` in the linked MIR (one per
  ntt_layer/ntt_inverse_layer monomorphization — rustc const-eval bakes the table into each) are
  identical, and all 255 live entries equal `zeta^bitrev8(i) mod q` (zeta=1753, the definition FIPS
  204 Appendix B tabulates). Entry 0 is a deliberate never-read dummy: both directions perform
  exactly 255 = 1+2+...+128 reads (forward pre-increments from m=0 → indices 1..=255; inverse
  pre-decrements from m=256 → 255..=1). Checker is self-tested: a corrupted table makes it exit 1.
  Note this checks the COMPILED artifact (post-const-eval), which is strictly stronger than auditing
  the const-fn source.
- **#3 (scalar half) hint layer == FIPS 204: VERIFIED.** `proof/hint/hint.saw` (saw exits 0, 4
  proofs): `decompose` == Alg 36, `high_bits` == Alg 37, `make_hint` == Alg 39, `use_hint` == Alg 40,
  for ALL field elements (ML-DSA-44 instances). Spec `fips204_hint44.cry` transcribed from FIPS 204
  over signed [64] (exact integer semantics: every quantity < 2^24 in magnitude — first attempt used
  Cryptol Integer and z3 ground to a halt on the mixed int/bv goals; same-width signed BV is the
  tractable faithful encoding). Plumbing learned: `mir_find_adt` for `module_lattice::Elem<BaseField>`
  + `mir_struct_value`/`mir_tuple_value` for the (Elem, Elem) return; make_hint/use_hint verified
  compositionally with the proven decompose/high_bits as overrides. NEW assumed CT spec needed:
  `<u32 as CmovEq>::cmoveq` (via ctutils ct_eq in decompose) — justified against its asm in
  ASSUMPTIONS.md; trust base is now exactly {black_box, cmovnz u32, cmoveq u32}. Non-vacuity: 4
  mutations (r0+1, r1+1, ~make_hint, use_hint+1) all yield counterexamples.
  Still open for #3: `bit_pack`/`bit_unpack` — the GHSA-5x2r-hc65-25f9 strictly-increasing-index
  validation lives in bit_unpack, array-level with data-dependent loops (omega=80, K=4 for MlDsa44).

## PORTABILITY: SAW names must NOT carry crate disambiguators (CI lesson, 2026-06-12)
The first clean-runner CI run failed on `Couldn't find MIR function named:
cmov/7f670710::backends::...` — the crate disambiguator hashes (`cmov/7f670710`, `ml_dsa/b7ee2aad`,
...) are rustc metadata hashes that DIFFER between machines. SAW resolves disambiguator-free names
fine (`cmov::backends::aarch64::{impl#1}::cmovnz`, `ml_dsa::algebra::BarrettReduce::reduce::_inst...`,
no `[0]` suffix needed). All proof scripts now use the portable form. The `_inst` monomorphization
hashes are kept — whether THEY are machine-stable is confirmed by the rust.yml run on a clean runner
(if one ever changes, regenerate from the MIR: python3 scan of fns by name/MULTIPLIER constant).
