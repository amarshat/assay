<p align="center">
  <img src="assay-logo.png" alt="PQC-Assay — C = spec" width="260">
</p>

<h1 align="center">PQC-Assay</h1>
<p align="center"><em>(formerly "Assay")</em></p>

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
> - **SAW (C ≡ Cryptol): the whole `reduce.c` layer.** All four primitives are proven bit-for-bit
>   equal to the Cryptol model: `montgomery_reduce` (inputs `−2³¹·Q ≤ a ≤ Q·2³¹`), `reduce32`
>   (`a ≤ 2³¹−2²²−1`), `caddq` (unconditional), `freeze` (compositional). Verified non-vacuous.
> - **Isabelle (model ≡ spec): `montgomery_reduce`.** The cryptol-to-isabelle-lifted model satisfies
>   the independently-written spec `is_montgomery_reduction` — `2³²·r ≡ a (mod Q)` and strict
>   `−Q < r < Q` — for the half-open domain `−2³¹·Q ≤ a < 2³¹·Q`. No `sorry`, no `oops`.
>   (The other three have SAW proofs but not yet the Isabelle spec leg.)
>
> Chaining the two for `montgomery_reduce`: **the C computes a correct Montgomery residue mod Q** on
> that half-open domain. **Not in scope:** the forward NTT, optimized/native code, any constant-time /
> side-channel property. We also found a minor off-by-one in PQClean's
> `montgomery_reduce` doc-comment bound at the inclusive endpoint (see `docs/ASSUMPTIONS.md`, OF-1).
> Every claim is only as strong as the assumptions in [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md).

## Honest scope (please read before citing this)

This is a **methodology demonstration and an honest end-to-end pipeline shakedown — not an ML-DSA
assurance milestone.** Reviewed by two external senior engineers (formal-methods and applied-PQC);
their verdict was, in short, *"rigorous, honest, correctly built — and pointed at the easy thing."*
Specifically:

- **`montgomery_reduce` is the least bug-prone function in the stack.** It's a branch-free
  two-multiply/one-shift device that has been correct in pq-crystals for years. Where ML-DSA bugs
  actually live is **inter-procedural reduction-bound composition across the NTT/InvNTT** (e.g.
  ePrint [2026/1032](https://eprint.iacr.org/2026/1032), which found a real overflow in an optimized
  ML-DSA path that survived test vectors; and the missing-reduction bug Apple's SAW work caught in
  ML-DSA InvNTT). A single-primitive equivalence proof cannot, by construction, touch that — and the
  forward NTT with coefficient-bound tracking is the next rung (see Roadmap).
- **The verified contract is ~256× wider than anything ML-DSA exercises.** Real call sites
  (pointwise-multiply, NTT butterflies) feed products `≲ Q² ≈ 2⁴⁶`; the proven precondition goes to
  `2³¹·Q ≈ 2⁵⁴`. So OF-1's problematic endpoint is unreachable in practice — the reference is
  mathematically correct; only the upstream doc bound is off by one at an out-of-reach point.
- **`montgomery_reduce` is parameter-set-independent** (identical across ML-DSA-44/65/87 — same `Q`,
  `QINV`, `reduce.c`), so the "-44" pin is cosmetic and the result holds for all three for free.
- **This is reference C, not deployed code.** The hot paths that actually ship (AVX2/aarch64;
  OpenSSL 3.5 / BoringSSL / AWS-LC; PQ Code Package `mldsa-native`) are different code, verified by
  different toolchains (CBMC, HOL-Light/s2n-bignum). Pointing this pipeline at `mldsa-native` is v2.

In one line: **we proved the safe, easy thing correctly and stopped right before the interesting
part — on purpose, as a v1.** The value is the *reproducible methodology on third-party reference C*
plus a real (cosmetic) upstream doc finding, not the theorem itself.

## Background: what Apple shipped in May 2026 (for newcomers)

New to this? In May 2026 Apple open-sourced the [formal verification of its `corecrypto` library](https://github.com/apple/corecrypto/tree/2026-05) — the cryptography that runs on Apple devices — covering the new post-quantum algorithms ML-KEM and ML-DSA (NIST FIPS 203/204). *Formal verification* means proving, with machine-checked mathematics, that the actual shipping code (C, and even ARM64 assembly) computes **exactly** what the official specification says — for *every* possible input, not just the cases a test happens to try. Apple did this using open tools from [Galois](https://github.com/GaloisInc/saw-script) (SAW + Cryptol) plus the [Isabelle](https://isabelle.in.tum.de/) theorem prover, and the effort even caught real bugs that ordinary testing missed. **Assay applies that same public approach to _third-party_ reference C** (here, PQClean's ML-DSA), starting with one small arithmetic primitive — see below. We reuse the *approach and tools*, not Apple's code or proofs.

## Why this is different

Most formally verified PQC (libcrux, HACL\*, formosa-mlkem) is written in a research language
(F\*, Jasmin) and *extracts* C, or verifies generated assembly. Assay instead verifies
**existing hand-written C** (PQClean's reference implementation, the basis many libraries derive
from) directly against a spec. The longer-term aim (Roadmap v2) is to point the same pipeline at the
**optimized/assembly** code that is actually deployed — that is where a real bug is most likely and
where this approach earns its keep. Today's scope is deliberately one small primitive, done honestly
end-to-end, rather than broad claims.

It also deliberately targets **ML-DSA**, where *functional verification of the optimized code is less
mature* than ML-KEM's and the **reduction-bound composition is an active 2026 research target** (cf.
ePrint 2026/1032; PQ Code Package `mldsa-native`'s HOL-Light proofs are still in progress). That's the
interesting frontier; v1 is the warm-up that gets the pipeline working on third-party reference C.

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
