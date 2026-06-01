# Using Apple's open corecrypto verification toolchain on third-party code

> Draft skeleton for the flagship writeup. This is the highest-leverage artifact in the project:
> almost nobody has used these tools on code outside Apple yet. Write the *journey*, not just the
> result — the rough edges are the value.

## 1. Why I did this
- The May 2026 corecrypto release; what Apple open-sourced; the gap it opens.
- Why third-party deployed C, and why ML-DSA specifically.

## 2. The toolchain, briefly
- SAW, Cryptol, cryptol-to-isabelle, Isabelle — what each does, how they connect.

## 3. Setting it up (the parts the docs don't tell you)
- Install/pin friction, versions, gotchas. Be concrete; this section is what gets shared.

## 4. The subroutine under test
- The NTT + modular reduction; why it's bug-prone; the FIPS-204 definition.

## 5. C → Cryptol → SAW
- Modeling decisions, what SAW caught, where it struggled.

## 6. Lifting to Isabelle and proving equivalence
- The translator in practice; which Apple lemmas helped; the proof structure.

## 7. Result, and honest limitations
- What is proven, under exactly which assumptions (link ASSUMPTIONS.md).
- What is NOT proven. (Credibility lives here.)

## 8. What I'd want from the tools next
- Concrete, filed as issues/PRs against the relevant repos — link them.

## Appendix: how to reproduce
- `./scripts/setup.sh && make verify`
