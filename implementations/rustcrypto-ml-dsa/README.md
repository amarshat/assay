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
- **Next (v2.1):** model FIPS 204's hint rules and verify `hint.rs`/`verifying.rs` (the GHSA-class
  spec-conformance target), and the `module_lattice` Barrett `reduce` / NTT arithmetic.

## Open findings
_(none yet — this section is the private ledger; do not open public issues from here)_
