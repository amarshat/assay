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
