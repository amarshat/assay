# Verifying third-party post-quantum C against its spec, with SAW + Cryptol + Isabelle

> **DRAFT / outline — not finished content yet.** Skeleton for the project writeup.
> It applies the *approach* Apple open-sourced for `corecrypto` in May 2026 (SAW + Cryptol + Isabelle;
> see the README "Background" section) to *third-party* reference code — **using none of Apple's code,
> proofs, or theories**. The Isabelle specification here is written independently from FIPS 204.
> Write the *journey*, not just the result — the rough edges are the value.

## 1. Why I did this
- Apple's May 2026 corecrypto verification release: what it open-sourced, and the gap it leaves —
  almost nobody has driven these tools on code *outside* Apple yet.
- Why third-party reference C, and why ML-DSA specifically.

## 2. The toolchain, briefly
- SAW, Cryptol, cryptol-to-isabelle, Isabelle (+ AFP) — what each does and how they connect. All from
  Galois / the open ecosystem; no Apple artifacts.

## 3. Setting it up (the parts the docs don't tell you)
- Install/pin friction, exact versions, gotchas: arm64 macOS code-signing/quarantine `Killed: 9`;
  the AFP + SAW `Cryptol` Isabelle session build; GNU Make 3.81 PATH quirks. Be concrete — this
  section is what gets shared.

## 4. The subroutine under test
- v1 scope: **`montgomery_reduce` only** — the modular-reduction primitive the forward NTT relies on,
  NOT the NTT itself (yet). Why it's bug-prone; what Montgomery reduction must compute (`a·2⁻³² mod Q`).

## 5. C → Cryptol → SAW
- Modeling decisions (bit-exact widths; arithmetic vs logical shift), what SAW proves, the
  non-vacuity control run, where it struggled.

## 6. Lifting to Isabelle and proving equivalence
- The cryptol-to-isabelle translator in practice; the `seq`/`word` coercion library; the proof
  structure (integer core + seq→word bridge + sint-of-word-computation + the `T ≡ a·QINV (mod 2³²)`
  congruence). The spec was written independently — **no Apple lemmas were used.**

## 7. Result, and honest limitations
- What is proven, under exactly which assumptions (link `docs/ASSUMPTIONS.md`), plus the OF-1 finding
  (PQClean's documented bound is off by one at the inclusive endpoint).
- What is NOT proven: the other reduction primitives, the forward NTT, optimized/native code, any
  constant-time / side-channel property. Credibility lives here.

## 8. What I'd want from the tools next
- Concrete asks, filed as issues/PRs against the relevant repos — link them.

## Appendix: how to reproduce
- `./scripts/setup.sh && ./scripts/setup_isabelle_cryptol.sh && make verify`
