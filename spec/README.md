# Isabelle spec & equivalence proof

Contains an independent Isabelle specification of the ML-DSA **Montgomery-reduction** primitive
(`MLDSA_NTT_Spec.thy`) and the in-progress proof that the cryptol-to-isabelle-lifted model
(`MLDSA_NTT.thy`) satisfies it (`Assay_Equivalence.thy`). NOTE: this is the reduction primitive, not
the full NTT (the NTT spec is future work despite the file naming).

## Reusing Apple's formalization
**Decision (2026-06-07): we reuse NOTHING from Apple.** The spec is written **independently** from
FIPS 204 / the Dilithium definition of Montgomery reduction. No Apple corecrypto theory files or
lemma libraries are imported. (An independent spec is the stronger, more defensible artifact, and
sidesteps Apple's restricted evaluation-license pieces entirely.)

- Reused Apple theories: **none.**

The only external Isabelle dependency is the Archive of Formal Proofs (AFP `Word_Lib`,
`Berlekamp_Zassenhaus`), pulled in transitively by the SAW-provided `Cryptol` support session that
the `cryptol-to-isabelle` output imports (installed by `scripts/setup_isabelle_cryptol.sh`).
