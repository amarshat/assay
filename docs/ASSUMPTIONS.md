# Trust base & assumptions

A proof is only meaningful relative to what it assumes. This file is the honest ledger.
**Update it the moment any assumption is introduced.** Reviewers will read this first.

## Standing assumptions
- **Compiler correctness.** We verify C (via its LLVM bitcode) and the FIPS spec; we assume the
  compiler faithfully lowers verified C. (Same assumption Apple states for corecrypto.)
- **Tool soundness.** We trust SAW, Cryptol, the cryptol-to-isabelle translator, and Isabelle.
- **Spec faithfulness.** We assume our (independently written, no Apple artifacts) Isabelle
  specification faithfully captures the intended Montgomery-reduction behavior / FIPS 204.
  Provenance noted in spec/README.md.

## Scope limits (v1)
- **Scope is the reduce.c layer; nothing about the forward NTT is proven.** SAW proves all four
  reduce.c primitives ≡ Cryptol model: `montgomery_reduce` (under its precondition), and `reduce32`
  (under `a <= 2^31-2^22-1`), `caddq`, `freeze` (`caddq` unconditional; `freeze` inherits reduce32's
  precondition). The Isabelle model≡spec leg currently covers `montgomery_reduce` only. The forward
  NTT is NOT modeled or proven.
- Input range: the C documents the precondition `-2^31 * Q <= a <= Q * 2^31`. The SAW proof IS
  discharged under exactly this precondition (`mont_in_range` in the model); equivalence outside it
  is NOT claimed by the proof. (Empirically the Cryptol model is a bit-exact transcription that also
  matches the C outside the range, but that is not what SAW asserts.)
- **Call-site reachability (practical-safety context).** The *verified contract* (`|a| <= 2^31*Q
  ~= 2^54`) is ~256x wider than what ML-DSA actually feeds this function: pointwise-multiply and NTT
  butterflies produce products `<~ Q^2 ~= 2^46`. So OF-1's problematic endpoint (`a = 2^31*Q`) is
  unreachable in any real ML-DSA execution; the reference is mathematically correct in practice.
- **Parameter-set independence.** `montgomery_reduce` is byte-identical across ML-DSA-44/65/87 (same
  `Q`, `QINV`, `reduce.c`); the proof holds for all three. The "-44" pin is cosmetic for this function.
- **C undefined-behavior / overflow setting.** The SAW proof is over the LLVM bitcode emitted by
  clang `-O0`; we reason about two's-complement word arithmetic as crucible-llvm models it. In the
  documented input range no signed overflow occurs (|a|, |t*Q| < 2^54, the difference < 2^63), so the
  result is unaffected either way; we do not currently make an explicit "no signed-overflow UB" claim
  (a hardening item — Apple's corecrypto contracts assert absence of UB explicitly).
- Anything not listed as proven is, explicitly, NOT proven.

## Modeling choices for `montgomery_reduce` (model/cryptol/MLDSA_NTT.cry)
- Modeled at the **exact C bit widths** (`[64] -> [32]`), not over idealized `Integer`, because SAW
  checks bit-for-bit equivalence and the algorithm depends on two's-complement truncation/shift.
- `*` on `[n]` = multiply mod 2^n → matches C's wrapping `(uint64_t)` product and low bits of
  `(int64_t)t * Q`. `drop`{32}` = keep low 32 bits → matches the `(int32_t)` casts and the final
  int64→int32 assignment. `>>$` = ARITHMETIC right shift → matches `>> 32` on a signed `int64_t`
  (plain logical `>>` would be wrong here).
## Proof results (what a tool actually checked, and when)
- **C ≡ Cryptol for `montgomery_reduce`: VERIFIED.** `make saw` exits 0 on 2026-06-06.
  - Tool: SAW v1.5.1, solver Z3 (bundled). Bitcode: Apple clang 17 `-O0 -g`, `build/mldsa_ntt.bc`.
  - Claim discharged: `∀ a:[64]. mont_in_range a ⇒ C(a) == montgomery_reduce(a)`, i.e. the C function
    `PQCLEAN_MLDSA44_CLEAN_montgomery_reduce` returns exactly the model's value for every input in
    `-2^31*Q ≤ a ≤ Q*2^31`. Nothing outside that range is claimed.
  - SAW output: `Proof succeeded! PQCLEAN_MLDSA44_CLEAN_montgomery_reduce`.
  - **Non-vacuity checked.** A control run with a deliberately wrong model (`result + 1`) made SAW
    fail with counterexample `a = 0`, confirming the precondition is satisfiable and the equality
    postcondition is really being asserted. (An earlier control swapping `>>$`→`>>` correctly still
    passed — for this function the shift-by-32-then-truncate makes arithmetic/logical shift
    equivalent, so it is not a behavioral change.)
- **C ≡ Cryptol for reduce32 / caddq / freeze: VERIFIED** (`make saw`, exit 0). `reduce32` under
  `a <= 2^31-2^22-1` (bounds the `a+(1<<22)` add against int32 overflow); `caddq` unconditional;
  `freeze` proven compositionally using the `reduce32`/`caddq` overrides, inheriting reduce32's
  precondition. These have SAW (C≡model) proofs but NOT yet Isabelle (model≡spec) proofs.
- The earlier 16-vector C-vs-Cryptol concrete cross-check (2026-06-01) remains as a secondary
  sanity check; the SAW proof above supersedes it for all in-range inputs.

- **model ≡ FIPS/math spec (Isabelle leg): VERIFIED (2026-06-07).** `make verify` (SAW + Isabelle)
  exits 0; `isabelle build -D spec/isabelle Assay` checks `montgomery_reduce_correct` with NO `sorry`
  / NO `oops`. Theorem: the cryptol-to-isabelle-lifted `montgomery_reduce` satisfies
  `is_montgomery_reduction (sint_seq a) (sint_seq (montgomery_reduce a))`, i.e. `2^32*r ≡ a (mod Q)`
  and strict `-Q < r < Q`, for every `a` with `-2^31*Q ≤ sint a < 2^31*Q` (half-open; see OF-1).
  Proof structure: `mont_core` (integer core) + `probe_bridge` (seq→word) + `red_value`
  (sint of the word computation = `(A - T*Q) div 2^32`, no overflow) + `tcong` (`T ≡ A*QINV mod 2^32`).
  - Trust base note: relies on `cryptol-to-isabelle` translating the Cryptol model faithfully (tool
    soundness assumption) and on the SAW Cryptol support library + AFP (`Word_Lib`,
    `Berlekamp_Zassenhaus`). Prerequisite built by `scripts/setup_isabelle_cryptol.sh` (AFP
    `afp-2026-06-05`; heavy).
  - **Chaining:** with the SAW leg (C ≡ Cryptol model) this gives end-to-end: the deployed C
    `montgomery_reduce` computes a correct Montgomery residue mod Q. Note the two legs use slightly
    different input predicates — SAW proves C ≡ model over the INCLUSIVE range `-2^31*Q ≤ a ≤ Q*2^31`
    (`mont_in_range`), while the Isabelle correctness spec uses the HALF-OPEN `-2^31*Q ≤ a < 2^31*Q`
    (`mont_input_ok`, where the strict `-Q<r<Q` actually holds; OF-1). The composed end-to-end
    correctness claim therefore holds on the half-open intersection (which is the honest, maximal
    domain for the strict-bound spec).
- **NOT proven:** reduce32/caddq/freeze, the forward NTT, optimized/native code, constant-time.

## Tool/version pins
Pinned and installed by `scripts/setup.sh` into `.tools/` (gitignored). Platform of record:
**macOS 26.3.1, Apple Silicon (arm64)**, set up 2026-06-01.

- SAW: **v1.5.1** (2026-05-22), asset `saw-1.5.1-macos-15-ARM64-with-solvers.tar.gz`.
- Cryptol: **3.5.0** (git 6173b60), bundled inside the SAW 1.5.1 tarball (used in-place to avoid skew).
- cryptol-to-isabelle: bundled standalone in the SAW 1.5.1 tarball (first release to ship it).
- Isabelle: **Isabelle2025-2** (Jan 2026), asset `Isabelle2025-2_macos.tar.gz` (universal bundle,
  upstream lists macOS 26 / Apple Silicon support).
- clang: **Apple clang 17.0.0 (clang-1700.0.13.5)**, system `/usr/bin/clang` (NOT vendored — see below).
- z3: 4.15.4 present on system, but the SAW "with-solvers" bundle ships its own solver set; the
  pipeline prefers the bundled solvers for reproducibility.

### Platform / toolchain caveats (introduced 2026-06-01)
- **SAW binary built for macOS 15, run on macOS 26.** No arm64 macOS-26-specific SAW build exists
  upstream; the macOS-15 arm64 build is what we run. Flagged here for honesty; gated on `saw --version`
  actually running before we depend on it.
- **Apple Silicon Gatekeeper.** On macOS arm64 a downloaded binary that is only ad-hoc signed and
  still carries the `com.apple.quarantine` xattr is SIGKILLed on exec ("Killed: 9"). `setup.sh`
  strips quarantine (`xattr -dr com.apple.quarantine`) and ad-hoc re-signs the Mach-O binaries
  (`codesign --force --sign -`). Neither alters behavior; they only satisfy the loader. Verified:
  `saw --version` → `1.5.1`, `cryptol --version` → `3.5.0` after this step.
- **Apple clang, not mainline LLVM/clang.** We emit LLVM bitcode for SAW with the system Apple clang
  (17.0.0). Apple's clang can emit a bitcode/IR version that differs from mainline; if SAW's LLVM
  parser rejects it, the documented fallback is a pinned mainline `clang`. Part of the trust base
  (see "Compiler correctness").

## Open findings (handle per CONTRIBUTING.md → Responsible disclosure)
- **OF-1 (2026-06-07): PQClean `montgomery_reduce` doc-comment postcondition is off by one at the
  upper input endpoint.** The comment in `target/pqclean/reduce.c` states, for input domain
  `-2^31*Q <= a <= Q*2^31` (inclusive), that it returns `r` with **`-Q < r < Q`** (strict). But at
  `a = 2^31*Q` the function returns `r = Q` (= 8380417), which violates the strict upper bound.
  Verified directly against the vendored C: `montgomery_reduce(17996808470921216) = 8380417`; the
  lower endpoint `a = -2^31*Q` returns `0` (fine). The congruence `2^32*r ≡ a (mod Q)` still holds.
  - Severity: **documentation/contract only, not a security or functional bug.** Real callers (NTT
    butterflies) feed products bounded well below `2^31*Q`, so the endpoint is not exercised in
    practice. The reference is mathematically correct; only the stated strict bound at the inclusive
    endpoint is wrong (the true guarantee over the inclusive domain is `-Q <= r <= Q`).
  - Origin & disclosure routing: the identical `montgomery_reduce` comment is in
    **`pq-crystals/dilithium/ref/reduce.c`** (verified 2026-06-07) — PQClean only re-namespaces it.
    So the finding originates upstream and also affects PQ Code Package `mldsa-native` and liboqs.
    PQClean is being archived (July 2026), so the right disclosure home is **pq-crystals/dilithium**,
    not PQClean. **Do NOT auto-file upstream** (CLAUDE.md); surfaced to the maintainer (human) on
    2026-06-07 to decide deliberately.
  - Impact on Assay: the SAW leg (C ≡ Cryptol model) is unaffected — it asserts no bound. The
    Isabelle correctness spec is stated over the **half-open** domain `-2^31*Q <= a < 2^31*Q`, where
    the strict `-Q < r < Q` is actually true; see `spec/isabelle/MLDSA_NTT_Spec.thy` (`mont_input_ok`).
