# Verifying third-party post-quantum C against its spec, with SAW + Cryptol + Isabelle

> Draft outline, not finished prose. This applies the SAW + Cryptol + Isabelle approach Apple
> open-sourced for `corecrypto` (May 2026) to third-party reference code. No Apple code, proofs, or
> theories are used; the Isabelle spec is written from FIPS 204.

## 1. Why

- What Apple's May 2026 corecrypto release open-sourced, and the gap: these tools have mostly been
  driven on Apple's own code, not on third-party C.
- Why reference C, and why ML-DSA.

## 2. The toolchain

- SAW, Cryptol, cryptol-to-isabelle, Isabelle (+ AFP): what each does and how they connect. All from
  Galois / the open ecosystem.

## 3. Setup (the parts the docs skip)

- Version pins and the gotchas hit along the way: arm64 macOS code-signing/quarantine `Killed: 9`;
  building the AFP + SAW `Cryptol` Isabelle session; GNU Make 3.81 resolving single-command recipes
  against its own PATH.

## 4. The target

- `reduce.c`: `montgomery_reduce`, `reduce32`, `caddq`, `freeze`. Montgomery reduction computes
  `a·2⁻³² mod Q`; it's an implementation device, not a FIPS-204 object. SAW covers all four; the
  Isabelle leg covers `montgomery_reduce` so far. The NTT is not modeled.

## 5. C → Cryptol → SAW

- Modeling at bit-exact widths; arithmetic vs logical shift; the documented preconditions (and the
  int32 overflow that forces `reduce32`'s). The mutation test that checks the proof isn't vacuous.

## 6. Lifting to Isabelle and proving equivalence

- cryptol-to-isabelle in practice; the `seq`/`word` coercion library; the proof structure (integer
  core, `seq`→`word` bridge, `sint` of the word computation, the `T ≡ a·QINV (mod 2³²)` congruence).
  Mechanizing the lift so the committed theory is diffed against the `.cry` SAW checks.

## 7. Results and limits

- What's proven, under which assumptions (link `docs/ASSUMPTIONS.md`). The OF-1 doc off-by-one in the
  upstream `montgomery_reduce` comment.
- What's not proven: the forward NTT, optimized/native code, constant-time. Why `montgomery_reduce` is
  the easy target, and where the real risk is — reduction-bound composition across the NTT
  (ePrint 2026/1032; Apple's InvNTT bug).

## 8. What I'd want from the tools next

- Concrete asks, filed against the relevant repos.

## Appendix: reproduce

- `./scripts/setup.sh && ./scripts/setup_isabelle_cryptol.sh && make verify`
