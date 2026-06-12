# Assay: RustCrypto `ml-dsa`

Verification target: the [RustCrypto `ml-dsa`](https://crates.io/crates/ml-dsa) crate, **pinned to
`0.1.1`**. The de-facto pure-Rust ML-DSA (FIPS 204) implementation.

## Why this target
- **Used:** the canonical Rust ML-DSA crate; broad supply-chain reach.
- **Unverified:** its own docs state it has *never been independently audited*, and no RustCrypto
  post-quantum package has.
- **Defect history (bugs are still being found):**
  - `decompose` timing side-channel — [RUSTSEC-2025-0144](https://rustsec.org/advisories/RUSTSEC-2025-0144.html).
  - Verification accepted **duplicate hint indices** because a `<` became `<=`, violating FIPS 204 —
    [GHSA-5x2r-hc65-25f9](https://github.com/RustCrypto/signatures/security/advisories/GHSA-5x2r-hc65-25f9).
    Exactly the spec-conformance class a verify-against-FIPS-204 pipeline catches.
- **Reachable:** SAW analyzes Rust via `mir-json` + `crucible-mir` (schema v11, matches our SAW 1.5.1).

## Source layout → verification targets (bug-richest first)
| File | What | Target phase |
|---|---|---|
| `hint.rs` | hint encode/decode, `MakeHint`/`UseHint` (home of the duplicate-index bug) | v2.1 |
| `verifying.rs` | signature verification: norm + hint checks | v2.1 |
| `algebra.rs` | field/ring arithmetic (reduce, Montgomery) | v2.2 |
| `ntt.rs` | the NTT | v2.2 |
| `signing.rs` | signing, `decompose` (home of the timing bug) | later |
| `sampling.rs`, `encode.rs`, `param.rs` | sampling / encoding / params | later |

## Plan
- **v2.0 — toolchain spike (in progress).** Stand up SAW-Rust (`scripts/setup_rust.sh`), vendor
  `ml-dsa 0.1.1`, get `algebra.rs`/`ntt.rs` to MIR, land a first trivial `mir_verify`. Gating unknown.
- **v2.1 — spec-conformance of hint/verify.** Model FIPS 204's hint rules (strictly increasing
  indices, `MakeHint`/`UseHint`) and prove `hint.rs`/`verifying.rs` conform. Where a GHSA-class defect
  would surface.
- **v2.2 — arithmetic.** `algebra.rs`/`ntt.rs` functional correctness vs a Cryptol model + the
  overflow/coefficient-bound reasoning (reuse the v1.5 Isabelle machinery; Rust release arithmetic
  wraps, so overflow defects are possible).

## Outcomes (honestly)
A finding routes to RUSTSEC/GHSA (recorded here first, human-routed, never auto-filed) and anchors a
paper. A clean result is the *first formal verification of the de-facto Rust ML-DSA crate*. Either is
publishable and noticeable. Risk: SAW-Rust is more experimental than SAW-C; RustCrypto's
generics/traits can be awkward for MIR.

## Status
- **v2.0 (toolchain spike): DONE (2026-06-11).** SAW-Rust pipeline proven end to end — a smoke
  `mir_verify` against a Cryptol spec succeeds (`proof/smoke/`). Toolchain pinned in
  `scripts/setup_rust.sh`: nightly-2025-09-14 + mir-json `7e12cece` (schema v8, the commit SAW 1.5.1
  bundles). Note: SAW 1.5.1 wants schema **v8**, not the v11 of mir-json HEAD — the smoke test caught
  this.
- Target pinned and vendored: `ml-dsa 0.1.1` + `module-lattice 0.2.3` (see `target/`).
- **v2.1 first real verify: DONE (2026-06-12).** `proof/reduce/reduce.saw` closes (`saw` exits 0):
  the crate's Barrett `reduce` ≡ `x mod 8192` (the 2^d / Power2Round modulus, the instance the keygen
  harness reaches) for **all** `u32`. This clears the cmov inline-asm blocker via two sound
  `mir_unsafe_assume_spec` overrides for the CT layer (`<u32 as Cmov>::cmovnz` + `black_box`); see
  `NOTES.md` and `docs/ASSUMPTIONS.md`. Non-vacuity checked (a mutated spec fails). This is the first
  tool-verified statement about the real RustCrypto crate's arithmetic.
- **v2.2 Barrett reduce, ALL moduli: DONE (2026-06-12).** Harness extended with sign/verify entry
  points (`sign44`/`verify44`), which force the remaining `BarrettReduce` monomorphizations into the
  MIR. `proof/reduce/reduce.saw` now proves `reduce(x) == x mod M` for **all** `u32 x`, no
  precondition, for all three moduli the crate uses: **q = 8380417** (final z reduction in signing),
  **2·γ₂ = 190464** (Decompose, ML-DSA-44), and **2^d = 8192** (Power2Round). For q and 2·γ₂ the
  conditional-subtract branch is live — the Barrett-precision case where bugs hide — and Z3 checks
  exactness over the full u32 domain. Non-vacuity checked per instance (mutated moduli fail). Trust
  base unchanged (same two CT-layer assumed specs). The MIR build is now repo-local (`build/`,
  gitignored) behind a stable symlink, so rebuilds/reboots no longer break the proof script. Scope:
  ML-DSA-65/87's 2·γ₂ = 523776 is a different monomorphization, not in this MIR, not claimed.
- **Focused audit of the bug-prone surface** (not the whole crate). Three targets, chosen because
  they are exactly where defects have historically appeared:
  1. `ct_div` Barrett precision (`algebra.rs`) — **DONE 2026-06-12, CLEAN.** SAW-verified
     `ct_div(x) == floor(x/190464)` for all `x < Q` (the documented contract; `proof/ctdiv/`).
     The `x < Q` precondition is load-bearing — precision genuinely breaks ~283× above Q — but all
     callers stay in-contract. No finding.
  2. const-computed zetas (`ntt.rs`) — **DONE 2026-06-12, CLEAN.** All 16 copies of the table baked
     into the compiled artifact match `zeta^bitrev8(i) mod q` (FIPS 204 Appendix B) on all 255 live
     entries; index 0 is a never-read dummy (`proof/zetas/check_zetas.py`, in CI). No finding.
  3. hint conformance (`hint.rs`) — **scalar layer DONE 2026-06-12, CLEAN.** SAW-verified against
     FIPS 204: `decompose` ≡ Algorithm 36, `high_bits` ≡ Algorithm 37, `make_hint` ≡ Algorithm 39,
     `use_hint` ≡ Algorithm 40, for **all** field elements (ML-DSA-44; `proof/hint/`, spec transcribed
     from the standard, four mutations all rejected). No finding. **Remaining:** `bit_pack`/
     `bit_unpack` — the literal GHSA-5x2r-hc65-25f9 site (strictly-increasing hint-index validation).

## Open findings
_(none yet — this section is the private ledger; do not open public issues from here)_
