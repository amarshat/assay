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
- `module_lattice 0.2.3` (the arithmetic), alongside `ml-dsa 0.1.1`.
