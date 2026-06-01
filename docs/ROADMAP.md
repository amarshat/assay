# Roadmap

The whole strategy is **depth, scoped tight**. One finished proof beats three half-built ones.

## v1 — prove one subroutine (the finishable win)
- Target: forward **NTT** + the modular reduction it relies on, in **pqclean's reference ML-DSA C**.
- Why this target: clean, readable C (SAW reasons about it well), upstream of liboqs →
  OpenSSL/BoringSSL adjacency (real-world relevance), and a self-contained, deterministic,
  FIPS-204-numbered sub-algorithm with no message-size dependence (sidesteps the SAW
  message-size limitation Apple flagged).
- Done = `make verify` checks green in CI, ASSUMPTIONS.md complete, writeup drafted.

## v2 — optimized ≡ reference (the credibility + bug-hunt step)
- Re-point the proof at **mldsa-native's optimized C**; prove optimized ≡ reference.
- This is where Apple-style "verify hand-optimized deployed code" credibility lives, and where
  a real bug is most likely to surface.

## v3 — the frontier (graduate here once v1/v2 land)
- Constant-time / secret-independence verification of the same subroutines.
- This is the higher-glory research direction; attempt it only after the toolchain mastery from
  v1/v2 is established and public.

## Non-goals (for now)
- Full end-to-end ML-DSA. Whole-algorithm correctness. Multiple implementations at once.
