# Isabelle spec & equivalence proof

Contains the FIPS-204 NTT specification in Isabelle and the proof that the (translated) Cryptol
model is equivalent to it.

## Reusing Apple's formalization
Apple released FIPS formalizations and lemma libraries with corecrypto (2026-05 branch).
**Before importing any of it**, confirm the license on the specific theory file:
some pieces are under a *restricted evaluation license*, others are permissive. Record what you
reused and under which license here:

- Reused theory: <FILL IN> — license: <FILL IN> — source commit: <FILL IN>

If licensing is unclear or restrictive, write the spec independently from FIPS 204 and say so —
an independent spec is itself a stronger, more defensible artifact.
