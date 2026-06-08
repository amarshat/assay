# Roadmap

The whole strategy is **depth, scoped tight**. One finished proof beats three half-built ones.

## v1 — the Montgomery-reduction primitive (DONE) + the reduce.c layer
- Delivered: `montgomery_reduce` in **PQClean's reference ML-DSA C**, proven end-to-end
  (C ≡ Cryptol via SAW; model ≡ independent FIPS-derived spec via Isabelle). `make verify` green.
- NB: `montgomery_reduce` is an *implementation device* the FIPS-204 NTT relies on (Montgomery
  reduction is not itself specified in FIPS 204) — not a "FIPS-numbered sub-algorithm". It is also
  parameter-set-independent (valid for ML-DSA-44/65/87) and the least bug-prone function in the stack.
  **This is a pipeline warm-up on third-party reference C, not an ML-DSA assurance milestone.**
- Rounding out the layer: SAW proofs for `reduce32`, `caddq`, `freeze` (the same translation unit).
  `caddq`'s `(a>>31)&Q` is the real branch-free-signedness exercise `montgomery_reduce` isn't.
- Hard gate (composition soundness): `make lift-check` mechanizes the `cryptol-to-isabelle` step —
  regenerate the Isabelle model from the `.cry` SAW checks and diff against the committed theory, so
  the end-to-end chain has no eyeball-maintained link.

## v1.5 — the forward NTT butterfly with coefficient-bound tracking
- The first *cryptographically meaningful* claim: model one butterfly (and then `ntt()`/
  `invntt_tomont()`), proving every `montgomery_reduce` input stays in range and no intermediate
  overflows `int32` across all 256 coefficients / 8 levels.
- This **bound-composition** property is the actual historical ML-DSA bug class (cf. ePrint
  2026/1032's optimized-path overflow that survived KATs; Apple's missing-reduction InvNTT bug). It
  is where verification first earns its keep, and it requires an Isabelle FIPS-204 NTT spec
  (negacyclic, 8-level) validated against FIPS 204 Algorithms 41–42 — itself a substantial formalization.

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
- OF-1 (the upstream `montgomery_reduce` doc-comment off-by-one) routes to **pq-crystals/dilithium**
  (origin; PQClean is archiving), and should also check the optimized AVX2/aarch64 variants' comment.
  Handle per CLAUDE.md (deliberate, human-routed; not auto-filed).
