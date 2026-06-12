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
- **Next (v2.1/2.2): a FOCUSED audit of the bug-prone surface** (not the whole crate). Three targets,
  chosen because they are exactly where defects have historically appeared:
  1. `ct_div` Barrett precision (`algebra.rs`) — does it return `floor(x/M)` for all `x < Q`?
  2. const-computed zetas (`ntt.rs`) — do all 256 entries match FIPS 204 Appendix B?
  3. hint encode/decode conformance (`hint.rs`/`verifying.rs`) — the GHSA-class spec target.
  Bounded (weeks), maximizes finding odds, shareable either way (a tight audit note, or a finding).

## Open findings
_(none yet — this section is the private ledger; do not open public issues from here)_
