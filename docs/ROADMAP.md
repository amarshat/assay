# Roadmap

The whole strategy is **depth, scoped tight**. One finished proof beats three half-built ones.

## v1 — the Montgomery-reduction primitive (DONE) + the reduce.c layer
- Delivered: `montgomery_reduce` in **PQClean's reference ML-DSA C**, proven end-to-end
  (C ≡ Cryptol via SAW; model ≡ independent FIPS-derived spec via Isabelle). `make verify` green.
- NB: `montgomery_reduce` is an *implementation device* the FIPS-204 NTT relies on (Montgomery
  reduction is not itself specified in FIPS 204) — not a "FIPS-numbered sub-algorithm". It is also
  parameter-set-independent (valid for ML-DSA-44/65/87) and the least bug-prone function in the stack.
  **This is a pipeline warm-up on third-party reference C, not an ML-DSA assurance milestone.**
- Rounding out the layer (DONE): both legs for `reduce32`, `caddq`, `freeze` (same translation unit) —
  SAW C ≡ Cryptol AND Isabelle model ≡ spec, no holes. `caddq`'s `(a>>31)&Q` is the branch-free
  signedness exercise `montgomery_reduce` isn't; `reduce32`'s Barrett output bound is a floor-division
  interval proof (and surfaced OF-2, a doc-comment off-by-one on its low end). `freeze` is compositional.
- Hard gate (composition soundness): `make lift-check` mechanizes the `cryptol-to-isabelle` step —
  regenerate the Isabelle model from the `.cry` SAW checks and diff against the committed theory, so
  the end-to-end chain has no eyeball-maintained link.
- Forward NTT functional equivalence (DONE): SAW proves `ntt(a[256])` ≡ Cryptol `ntt` under
  two's-complement wrapping (`-fwrapv` bitcode), montgomery_reduce as an uninterpreted override.
  This shows the pipeline scales to the full 256-point transform. It does NOT prove overflow-freedom.

## v1.5 — forward NTT overflow-freedom + an Isabelle NTT spec
- The remaining, *cryptographically meaningful* part: prove every `montgomery_reduce` input stays in
  range and no intermediate overflows `int32` across all 256 coefficients / 8 levels — i.e. the
  **coefficient-bound composition** invariant (this is what the `-fwrapv` functional-equivalence proof
  deliberately sidesteps). Needs a montgomery_reduce output-bound (|t| < Q) carried through the
  butterflies under an input bound.
- This is the actual historical ML-DSA bug class (cf. ePrint 2026/1032's optimized-path overflow that
  survived KATs; Apple's missing-reduction InvNTT bug). It also needs an Isabelle FIPS-204 NTT spec
  (negacyclic, 8-level) validated against FIPS 204 Algorithms 41–42 — itself a substantial formalization.
- **Overflow-freedom: DONE in Isabelle (2026-06-11).** Theorem `ntt_overflow_free`
  (`spec/isabelle/Assay_Equivalence.thy`, no holes, `make verify` exits 0): for inputs within
  `+/-(2^31 - 2^27)`, the lifted model NTT keeps every coefficient within `+/-2080309256 < 2^31 - 1`
  through all 8 levels. The per-butterfly bounds (`sint_add/sub_inrange`, `butterfly_node_*_bound`)
  establish that **every int32 add/sub stays in range (no overflow)** and that every
  `montgomery_reduce` input stays in its (half-open) precondition — the **coefficient-bound
  composition** invariant the `-fwrapv` proof sidesteps. Done by induction over the 8 levels (one
  lemma `nttLevel_bounded`: a level grows `|coeff|` by `<= Q`, the montgomery output bound), NOT by
  SAW unrolling. Key device: a *total* invariant over all indices (OOB falls back to the last
  element, so we never reason about modular index bounds). The brute-force SAW attempt
  (~3000 obligations, did not complete) is preserved on branch `v1.5-saw-overflow-wip`.
- **C-side bridge (argued, not separately mechanized):** the SAW `-fwrapv` proof gives C ≡ model for
  all inputs; the Isabelle result shows the model does not wrap under the bound; the two bitcodes
  differ only in nsw poison, absent when no overflow occurs — so the reference C NTT is overflow-free
  (no signed-overflow UB) and equals the spec under the bound. Mechanizing this last bridge in SAW is
  what proved impractical; it is a standard, sound meta-level argument.
- **Still open for v1.5:** an Isabelle FIPS-204 NTT *spec* (negacyclic, 8-level, Algorithms 41-42) and
  a model ≡ spec proof for the NTT itself (we have functional equivalence to the Cryptol model and now
  overflow-freedom, but not yet model ≡ FIPS-spec for the transform as we have for `reduce.c`).

## v2 — optimized ≡ reference (the credibility + bug-hunt step)
Re-point the pipeline at **PQ Code Package's `mldsa-native`** (the maintained successor PQClean points
to, and closer to deployed code). This is **multi-month**, not "re-point the proof" — break it down:
- **v2.0** — Isabelle NTT spec + reference NTT equivalence (depends on v1.5).
- **v2.1** — optimized scalar primitives (AVX2/aarch64 lane-packed `montgomery_reduce`/`reduce32`).
- **v2.2** — optimized NTT ≡ reference with the **lazy/deferred-reduction bound invariants** (the
  genre that produced the wolfSSL overflow). Expect SAW loop/induction friction and the message-size
  limitation Apple flagged for ML-DSA.
- Note: the *deployed* hot paths (OpenSSL 3.5 / BoringSSL / AWS-LC; `mldsa-native` asm) are verified
  by other toolchains (CBMC; HOL-Light/s2n-bignum); reference C has anchor value, not deployment value.

## v3 — constant-time / secret-independence (frontier)
- **Different tool, not this pipeline.** SAW≡Cryptol functional equivalence is not the CT tool; use
  ct-verif / SideTrail-style product programs, Binsec/Rel, or the Jasmin constant-time type system.
- **Different targets.** `montgomery_reduce` is already trivially CT (branch/division/table-free). The
  real CT risk is rejection sampling (`rej_eta`, `poly_uniform*`, challenge gen) and
  `decompose`/`make_hint`/`use_hint` — data-dependent control flow on secret-adjacent values.

## Non-goals (for now)
- Full end-to-end ML-DSA. Whole-algorithm correctness. Multiple implementations at once.

## Disclosure
- OF-1 (`montgomery_reduce` doc-comment strict-bound off-by-one at an endpoint) and OF-2 (`reduce32`
  doc-comment low-end bound `-6283008` reachably `-6283009` under its one-sided precondition) were
  **disclosed 2026-06-09 as pq-crystals/dilithium#114** (origin; PQClean is archiving; mldsa-native /
  liboqs are downstream). The AVX2 path has no `reduce.c`, so the comments don't repeat there. Both are
  doc/contract issues, not miscomputations. Next: await maintainer response, then offer a PR for their
  preferred phrasing.
