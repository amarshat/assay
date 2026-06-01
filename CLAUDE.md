# Working in this repo (read me first)

This is a **formal verification** project. The output is a machine-checked proof, not just code.
That changes the rules you usually operate under.

## Prime directive
**Never state or imply that a proof passes unless a tool actually verified it in this session.**
A `.thy` file that "looks complete" is not a proof. A SAW script that you wrote is not a result
until `saw` exits 0. If you cannot run the tool, say so and mark the step UNVERIFIED. Fabricated
or assumed proof results are worse than useless here — they destroy the entire point of the project.

## What we are doing (v1)
Prove that the **forward NTT** (and the modular-reduction primitives it depends on) in a deployed
C implementation of **ML-DSA** is equivalent to the **FIPS 204** sub-algorithm, via:
1. C → Cryptol model (`model/cryptol/`)
2. SAW proves C ≡ Cryptol (`proof/saw/`)
3. `cryptol-to-isabelle` lifts the Cryptol model into Isabelle
4. Isabelle proves the lifted model ≡ FIPS-204 spec (`spec/isabelle/`)

Scope is intentionally ONE subroutine. Do not expand scope without updating `docs/ROADMAP.md`.

## Conventions
- Pin every tool version in `scripts/setup.sh`. Reproducibility is the product.
- Every assumption (compiler correctness, checked input ranges, anything out of scope) goes in
  `docs/ASSUMPTIONS.md` the moment it is introduced. Be loud about limitations.
- The target C in `target/` is **vendored and pinned** (commit hash recorded in `target/README.md`).
  Never silently edit it — if a transformation is needed for SAW, document it.
- Before reusing any Apple Isabelle theory, confirm its license in `spec/README.md`.

## If you find a discrepancy / bug
Stop. Do not open any public issue or PR automatically. Record it in `docs/ASSUMPTIONS.md` under
"Open findings" and surface it to the human — disclosure must be deliberate and go through
maintainers first (see `CONTRIBUTING.md`).

## Useful commands
- `make verify`   run the full pipeline (fails loudly if any step doesn't check)
- `make saw`      just the C ≡ Cryptol step
- `make isabelle` just the Isabelle session
- `make clean`    remove build artifacts
