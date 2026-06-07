# Assay

**Machine-checking a post-quantum reference-C arithmetic primitive against its specification, with an Apple-style SAW → Cryptol → Isabelle pipeline.**

Assay applies an Apple-style SAW → Cryptol → Isabelle verification pipeline (the structure Apple
used for its 2026 `corecrypto` work — **no Apple code or theories are used here; our spec is written
independently from FIPS 204**) to the **PQClean reference C** for ML-DSA (FIPS 204). Scope today is
**one scalar arithmetic primitive**, `montgomery_reduce` — an implementation device the FIPS-204 NTT
relies on (Montgomery reduction is not itself defined in FIPS 204). **This is not the optimized /
assembly code shipped in most products** (AVX2, aarch64-asm, mldsa-native); that is a later goal
(see Roadmap v2). **The NTT itself is not yet modeled.**

> Status: **v1 proof complete for one primitive.** Scope = the single function `montgomery_reduce`
> (NOT the NTT, NOT the other reduction primitives, NOT a full algorithm).
>
> **What is proven today (tool-checked, `make verify` exits 0):**
> - **SAW (C ≡ Cryptol): DONE.** The C function `PQCLEAN_MLDSA44_CLEAN_montgomery_reduce`
>   (PQClean ML-DSA-44, pinned in `target/`) is bit-for-bit equal to the Cryptol model in `model/`,
>   for all inputs in `−2³¹·Q ≤ a ≤ Q·2³¹` (verified non-vacuous).
> - **Isabelle (model ≡ spec): DONE.** The cryptol-to-isabelle-lifted model satisfies the
>   independently-written spec `is_montgomery_reduction` — `2³²·r ≡ a (mod Q)` and strict `−Q < r < Q`
>   — for every input in the half-open domain `−2³¹·Q ≤ a < 2³¹·Q`. No `sorry`, no `oops`.
>
> Chaining the two: **the deployed C `montgomery_reduce` computes a correct Montgomery residue mod Q**
> (for that input range). **Not in scope:** the other reduction primitives, the forward NTT, optimized
> code, any constant-time / side-channel property. We also found a minor off-by-one in PQClean's
> `montgomery_reduce` doc-comment bound at the inclusive endpoint (see `docs/ASSUMPTIONS.md`, OF-1).
> Every claim is only as strong as the assumptions in [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md).

## Why this is different

Most formally verified PQC (libcrux, HACL\*, formosa-mlkem) is written in a research language
(F\*, Jasmin) and *extracts* C, or verifies generated assembly. Assay instead verifies
**existing hand-written C** (PQClean's reference implementation, the basis many libraries derive
from) directly against a spec. The longer-term aim (Roadmap v2) is to point the same pipeline at the
**optimized/assembly** code that is actually deployed — that is where a real bug is most likely and
where this approach earns its keep. Today's scope is deliberately one small primitive, done honestly
end-to-end, rather than broad claims.

It also deliberately targets **ML-DSA**, which is less completely verified than ML-KEM.

## The pipeline

```
   target C subroutine
          │  (1) hand-translate
          ▼
   Cryptol model  ──(2) SAW: prove C ≡ Cryptol──►  ✔ (montgomery_reduce)
          │  (3) cryptol-to-isabelle
          ▼
   Isabelle model ──(4) prove model ≡ FIPS spec──►  ✔ (montgomery_reduce)
                                  ▲
                Spec in Isabelle (written independently; NO Apple
                artifacts used; see spec/README.md)
```

Full detail in [`docs/PIPELINE.md`](docs/PIPELINE.md).

## Reproduce

Requires macOS on Apple Silicon (the pinned toolchain; see `docs/ASSUMPTIONS.md`).

```bash
./scripts/setup.sh                  # pin & install SAW, Cryptol, Isabelle, cryptol-to-isabelle
./scripts/setup_isabelle_cryptol.sh # AFP + build the SAW 'Cryptol' Isabelle session (heavy, ~20min, once)
make verify                         # whole pipeline: SAW (C≡Cryptol) + Isabelle (model≡spec); non-zero = a proof failed
# make saw                          # just the SAW leg (fast; no Isabelle needed)
```

## Layout

| Path | What |
|------|------|
| `target/`  | The exact C under verification, with pinned provenance |
| `model/`   | Cryptol model of the target subroutine |
| `proof/`   | SAW scripts proving C ≡ Cryptol |
| `spec/`    | Isabelle FIPS-204 spec + the equivalence proof |
| `docs/`    | Roadmap, assumptions, pipeline, and the writeup-in-progress |
| `scripts/` | Toolchain setup & pipeline orchestration |

## Tools

Built on open tools from Galois:
[SAW + Cryptol](https://github.com/GaloisInc/saw-script),
the `cryptol-to-isabelle` translator (saw-script v1.5.1), and
[Isabelle](https://isabelle.in.tum.de/) (+ AFP). The pipeline *structure* mirrors Apple's published
[corecrypto verification approach](https://github.com/apple/corecrypto/tree/2026-05), but **no Apple
code or theory files are used** — the Isabelle spec is written independently from FIPS 204.

## Licensing

This project's own code is under [MIT](LICENSE). **The C under `target/` and any reused Apple
Isabelle theories carry their own licenses** — some of Apple's theories are under a restricted
evaluation license. See [`target/README.md`](target/README.md) and [`spec/README.md`](spec/README.md);
verify provenance before redistributing.
