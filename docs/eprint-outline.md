# ePrint outline (draft)

Working title: *Machine-Checking the ML-DSA Reference Reduction Layer and Forward-NTT
Overflow-Freedom: A Reproducible SAW→Cryptol→Isabelle Pipeline*

Target venue: **IACR Cryptology ePrint Archive** (citable, indexed; not peer-reviewed). This is a
methodology / experience report, NOT a novelty claim — the outline says so explicitly.

## Contribution statement (what we honestly claim)
1. An **independent, reproducible, end-to-end** verification of PQClean's ML-DSA reference `reduce.c`
   (`montgomery_reduce`, `reduce32`, `caddq`, `freeze`): C ≡ Cryptol (SAW) **composed with**
   Cryptol-model ≡ FIPS-204-derived spec (Isabelle), via the new `cryptol-to-isabelle` bridge — using
   **none** of Apple's corecrypto artifacts.
2. A **machine-checked coefficient-bound / overflow-freedom** result for the forward NTT
   (`ntt_overflow_free`), by induction over the 8 levels — the cryptographically meaningful invariant
   the functional-equivalence proof sidesteps.
3. Two upstream **documentation/contract fixes** (OF-1, OF-2; pq-crystals/dilithium#114).
4. A **methodological lesson + proof-engineering technique**: brute-force SAW overflow-proof on the
   unrolled 256-point NTT is computationally impractical (~3000 obligations, did not complete); an
   Isabelle induction with a *total* coefficient invariant (OOB-index-as-last) is the tractable route
   and avoids all modular index reasoning.

## What we explicitly do NOT claim (the honesty section — load-bearing)
- Not a *novel* verification result: Apple verified analogous corecrypto ML-DSA primitives with the
  same pipeline; this is **reference C, independently reproduced**.
- Not deployed/optimized code (AVX2/aarch64, `mldsa-native`) — future work, where real bugs live.
- Not NTT *transform* correctness (negacyclic / model ≡ FIPS-spec) — we have C≡model + overflow-freedom,
  not transform correctness.
- The **C-side overflow-freedom bridge (nsw)** is an argued meta-step (wrapv≡model + model-no-wrap ⇒
  nsw no-UB), **not** separately mechanized.
- Not constant-time.

## Section skeleton
1. **Introduction** — PQC/ML-DSA context; why reference C; the gap we fill (independent + reproducible
   + cross-tool, honestly scoped).
2. **Background** — SAW/Cryptol/Isabelle, `cryptol-to-isabelle`, Montgomery & Barrett reduction, the
   negacyclic NTT.
3. **The pipeline** — the SAW→Cryptol→Isabelle chain; the **cross-tool composition** (strongest angle);
   `make lift-check` guarding the model↔theory link.
4. **The `reduce.c` layer** — C≡Cryptol (bit-exact, no-UB-in-range); Cryptol≡FIPS-spec; the four
   functions and their proven output windows.
5. **Forward-NTT overflow-freedom** — the coefficient-bound composition; the **total-invariant
   technique**; the SAW impracticality vs the 8-level induction; the wrapv→nsw bridge stated honestly.
6. **Findings** — OF-1, OF-2; responsible disclosure.
7. **Scope, limitations, non-claims** — the section above, expanded.
8. **Reproducibility** — pinned toolchain, CI (incl. the heap-cache content-addressable lesson),
   one-command `make verify`.
9. **Related work** — Apple corecrypto; CBMC/HOL-Light for deployed; ePrint 2026/1032; pq-crystals.
10. **Conclusion / future work** — v2 (deployed code), NTT transform spec.

## The three things that carry the paper's credibility
- **Cross-tool composition** via the brand-new `cryptol-to-isabelle` (saw-script 1.5.1) — a worked,
  reproducible example others can follow.
- **The total-invariant overflow proof** — a small but genuine proof-engineering contribution (and a
  documented negative result on the SAW route).
- **Independence + reproducibility + scrupulous scoping** — what makes it read as serious, not hobbyist.

## Honest verdict
A legitimate, defensible **ePrint** (not a top-tier peer-reviewed paper — the novelty bar isn't met,
and the paper says so). Worth posting once written; the cross-tool composition + mechanized
overflow-freedom + honesty are the load-bearing parts. A real peer-reviewed paper needs v2.
