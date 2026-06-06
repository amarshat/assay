# Trust base & assumptions

A proof is only meaningful relative to what it assumes. This file is the honest ledger.
**Update it the moment any assumption is introduced.** Reviewers will read this first.

## Standing assumptions
- **Compiler correctness.** We verify C (via its LLVM bitcode) and the FIPS spec; we assume the
  compiler faithfully lowers verified C. (Same assumption Apple states for corecrypto.)
- **Tool soundness.** We trust SAW, Cryptol, the cryptol-to-isabelle translator, and Isabelle.
- **Spec faithfulness.** We assume our Isabelle formalization of FIPS 204 (or the reused Apple
  formalization) faithfully captures the standard. Provenance noted in spec/README.md.

## Scope limits (v1)
- **This session proves nothing about the forward NTT.** Scope is the single primitive
  `PQCLEAN_MLDSA44_CLEAN_montgomery_reduce` (`int32_t(int64_t)`) from target/pqclean/reduce.c —
  the reduction the NTT relies on. The other reduce.c functions (reduce32, caddq, freeze) and the
  NTT itself are NOT modeled or proven yet.
- Input range: the C documents the precondition `-2^31 * Q <= a <= Q * 2^31`. The SAW proof IS
  discharged under exactly this precondition (`mont_in_range` in the model); equivalence outside it
  is NOT claimed by the proof. (Empirically the Cryptol model is a bit-exact transcription that also
  matches the C outside the range, but that is not what SAW asserts.)
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
- The earlier 16-vector C-vs-Cryptol concrete cross-check (2026-06-01) remains as a secondary
  sanity check; the SAW proof above supersedes it for all in-range inputs.
- **NOT yet proven:** model ≡ FIPS-204 spec (Isabelle leg), reduce32/caddq/freeze, the forward NTT.

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
- (none yet)
