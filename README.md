# Assay

**Formally verifying deployed post-quantum cryptographic code against its FIPS specification.**

Assay applies the SAW → Cryptol → Isabelle verification pipeline — the same approach Apple
open-sourced for `corecrypto` in May 2026 — to *third-party, deployed* C implementations of
ML-DSA (FIPS 204). The goal is to prove that the arithmetic subroutines most prone to subtle
bugs are mathematically equivalent to the standard.

> Status: **early / work in progress.** v1 targets a single subroutine (see Roadmap). Nothing
> here should be treated as a verified result until the proofs in `spec/` and `proof/` actually
> check end-to-end in CI. Claims of correctness are only as strong as the assumptions in
> [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md).

## Why this is different

Most formally verified PQC (libcrux, HACL\*, formosa-mlkem) is written in a research language
(F\*, Jasmin) and *extracts* C, or verifies generated assembly. Assay instead verifies
**hand-written C that is already shipping** — directly against the spec — which is the
least-covered, highest-value surface in the verified-crypto landscape, and exactly what Apple's
newly released toolchain is built to attack.

It also deliberately targets **ML-DSA**, which is less completely verified than ML-KEM.

## The pipeline

```
   target C subroutine
          │  (1) hand-translate
          ▼
   Cryptol model  ──(2) SAW: prove C ≡ Cryptol──►  ✔
          │  (3) cryptol-to-isabelle
          ▼
   Isabelle model ──(4) prove model ≡ FIPS spec──►  ✔
                                  ▲
                FIPS 204 spec in Isabelle (reused from Apple's
                release where licensing permits; see spec/README.md)
```

Full detail in [`docs/PIPELINE.md`](docs/PIPELINE.md).

## Reproduce

```bash
./scripts/setup.sh        # pin & install SAW, Cryptol, Isabelle, cryptol-to-isabelle
make verify               # run the whole pipeline; non-zero exit = proof did not check
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

Built on open tools from Galois and Apple:
[SAW + Cryptol](https://github.com/GaloisInc/saw-script),
the `cryptol-to-isabelle` translator (saw-script v1.5.1),
[Isabelle](https://isabelle.in.tum.de/), and Apple's published
[corecrypto verification libraries](https://github.com/apple/corecrypto/tree/2026-05).

## Licensing

This project's own code is under [MIT](LICENSE). **The C under `target/` and any reused Apple
Isabelle theories carry their own licenses** — some of Apple's theories are under a restricted
evaluation license. See [`target/README.md`](target/README.md) and [`spec/README.md`](spec/README.md);
verify provenance before redistributing.
