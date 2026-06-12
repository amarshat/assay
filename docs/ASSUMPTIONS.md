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
- **Scope is the reduce.c layer plus forward-NTT functional equivalence.** SAW proves all four
  reduce.c primitives ≡ Cryptol model (`montgomery_reduce` under its precondition; `reduce32` under
  `a <= 2^31-2^22-1`; `caddq` unconditional; `freeze` compositional), AND the forward NTT
  `ntt(a[256])` ≡ Cryptol `ntt` under two's-complement wrapping (see overflow note below). The
  Isabelle model≡spec leg covers the **whole `reduce.c` layer** (`montgomery_reduce`, `caddq`,
  `reduce32`, `freeze`). The forward NTT is proven equal to the model under wrapping AND its
  **overflow-freedom / coefficient-bound composition is now proven in Isabelle** (`ntt_overflow_free`,
  v1.5; see proof results below). There is still no Isabelle model≡FIPS-spec for the NTT transform.
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
- **C undefined-behavior / overflow setting.** Two bitcodes are built (`scripts/build_bitcode.sh`):
  - *default (`nsw`)* — used for the **reduce.c** proofs, which therefore DO assert absence of
    signed-overflow UB in their documented input ranges (`montgomery_reduce` under `mont_in_range`,
    `reduce32` under `a <= 2^31-2^22-1`).
  - *`-fwrapv`* — used for the **forward NTT** proof. The NTT does unreduced int32 add/sub (`a[j] ± t`)
    that overflow for unbounded inputs, so we prove functional equivalence under two's-complement
    wrapping (what the code computes; matches the mod-2^n model). Overflow-freedom is established
    separately (Isabelle `ntt_overflow_free`, v1.5; see proof results) and bridged to the C by the
    argument noted there — the `-fwrapv` proof itself asserts no overflow bound.
- Anything not listed as proven is, explicitly, NOT proven.

## v2 (Rust / RustCrypto `ml-dsa`) assumptions
- **Assumed specs for the constant-time primitive layer (inline asm SAW cannot read).** The crate's
  arithmetic bottoms out in CT primitives that SAW (MIR/LLVM) cannot translate, so the v2.1 proof
  (`implementations/rustcrypto-ml-dsa/proof/reduce/reduce.saw`) replaces them with `mir_unsafe_assume_spec`
  *assumed* specs. These are sound iff each spec reproduces the primitive's true input/output relation;
  they are NOT verified against the asm (SAW cannot see it). This is the standard SAW handling of
  inline-asm/intrinsic leaves, but it IS part of the trust base:
  - `<u32 as cmov::Cmov>::cmovnz` (`cmov-0.5.4 backends::aarch64::{impl#1}`): assumed
    `*self = (condition != 0) ? *value : *self`. Justified by reading the asm (`tst {cond},0xff;
    csel {self},{value},{self},NE`) — `csel ...,NE` selects `value` when the `tst` cleared Z, i.e.
    when `condition != 0`. This is exactly the crate's documented `cmovnz` ("move if non-zero")
    contract. It is the ONLY cmov instance reachable from the keygen harness (`cmovz`, `CmovEq`, and
    the u16/u64 widths are not monomorphized on this surface).
  - `core::hint::black_box`: assumed identity (it is an optimizer barrier with no semantic effect).
- **Which `reduce` instance is covered.** Only the M = 2^d = 8192 (Power2Round) monomorphization is
  reached by `SigningKey::<MlDsa44>::from_seed`; the mod-q and 2*gamma2 instances are out of scope
  until a harness exercises the NTT-multiply / sign / verify paths (v2.2). For the power-of-two
  modulus the Barrett shift is exact, so the result holds for all `u32` with no input precondition —
  unlike the q / 2*gamma2 cases, which will carry an `x < M^2` precondition and a live
  conditional-subtract branch (the actually bug-prone Barrett case).
- **Pinned, vendored target.** `ml-dsa 0.1.1` + `module-lattice 0.2.3` (provenance in
  `implementations/rustcrypto-ml-dsa/target/`). mir-json schema v8 = the commit SAW 1.5.1 bundles.

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
  precondition.
- **C ≡ Cryptol for the forward NTT `ntt(a[256])`: VERIFIED under two's-complement wrapping**
  (`make saw`, exit 0). Proven on the `-fwrapv` bitcode (so all inputs, no bound precondition), with
  `montgomery_reduce` passed as an override and kept uninterpreted (`w4_unint_z3`) so the 1024
  butterfly calls reduce to a structural array equality. The Cryptol `ntt` model was also concretely
  cross-checked against the C on two input vectors.
- **Forward NTT overflow-freedom (model level, Isabelle): VERIFIED (2026-06-11).** `make verify`
  exits 0, no `sorry`/`oops`. Theorem `ntt_overflow_free` (`spec/isabelle/Assay_Equivalence.thy`):
  for inputs with every coefficient in `+/-(2^31 - 2^27)`, the lifted model NTT keeps every
  coefficient in `+/-2080309256 < 2^31 - 1` through all 8 levels. The per-butterfly lemmas
  (`sint_add/sub_inrange`, `butterfly_node_*_bound`) establish that **every int32 add/sub stays in
  `[-2^31, 2^31)` — no overflow** — and that every `montgomery_reduce` input stays in its half-open
  precondition (so the OF-1 endpoint is never hit). Proof = induction over 8 levels (`nttLevel_bounded`:
  one level grows `|coeff|` by `<= Q`, the montgomery output bound `|t| < Q` from
  `montgomery_reduce_correct`), with a *total* coefficient invariant that sidesteps modular index
  reasoning (OOB index = last element). This is the coefficient-bound composition that the `-fwrapv`
  functional-equivalence proof deliberately sidesteps.
  - **C-side claim (argued, not separately mechanized):** SAW gives C ≡ model for all inputs under
    `-fwrapv`; Isabelle shows the model does not wrap under the bound; the nsw and `-fwrapv` bitcodes
    differ only in signed-overflow poison, absent when no overflow occurs. Hence the reference C NTT
    is overflow-free (no signed-overflow UB) and equals the spec under the bound. The brute-force SAW
    mechanization of this bridge was computationally impractical (~3000 obligations; see ROADMAP /
    branch `v1.5-saw-overflow-wip`); the meta-level argument is standard and sound.
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
- **model ≡ spec for reduce32 / caddq / freeze (Isabelle leg): VERIFIED (2026-06-08).**
  `isabelle build -D spec/isabelle Assay` exits 0, no `sorry`/`oops`. The lifted Cryptol models satisfy:
  - `caddq_correct`: `is_caddq` (residue-preserving; maps `[-Q,Q)` into `[0,Q)`) — unconditional.
  - `reduce32_correct`: `is_reduce32` (residue-preserving; output in the TRUE window
    `[-6283009, 6283008]`, see OF-2) over the SAW domain `a <= 2^31-2^22-1`. The output-bound proof
    is a floor-division interval argument with a case split at the extreme quotient `t = -256`.
  - `freeze_correct`: `is_freeze` (residue-preserving; output in `[0,Q)`) over the same domain,
    proven compositionally — reduce32's window `[-6283009, 6283008]` lies in `[-Q, Q)`, satisfying
    caddq's precondition. Chained with the SAW leg this gives C ≡ spec for the full `reduce.c` layer.
- **NOT proven:** an Isabelle model≡FIPS-spec for the NTT *transform* (we have C≡model + model-level
  overflow-freedom, not the negacyclic-transform correctness); the full SAW mechanization of the
  nsw/`-fwrapv` overflow bridge; optimized/native code; constant-time.

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
- **DISCLOSED 2026-06-09:** OF-1 and OF-2 were filed together (deliberate, human-routed) as a single
  upstream issue: **pq-crystals/dilithium#114** ("ref/reduce.c: doc-comment output bounds for
  montgomery_reduce and reduce32 are off by one at endpoints"). Both are documentation/contract fixes,
  not security or functional bugs; PQClean (re-namespaced copy, archiving) and mldsa-native/liboqs are
  downstream of this origin. Awaiting maintainer response on preferred phrasing before any PR.
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
- **OF-2 (2026-06-08): PQClean `reduce32` doc-comment output bound is off by one on the low end
  under its own (one-sided) precondition.** The comment in `target/pqclean/reduce.c` states, for
  `a <= 2^31 - 2^22 - 1`, that it returns `r` with **`-6283008 <= r <= 6283008`**. But the stated
  precondition is one-sided (no lower bound), so `a = -2143289344` is admissible (it is a valid
  `int32`, `>= -2^31`, and satisfies `a <= 2^31-2^22-1`), and there `reduce32(a) = -6283009`,
  which violates the stated lower bound by one. Verified by direct computation against the formula
  (`scripts`-level check, 2026-06-08): min over `a in [-2^31, 2^31-2^22-1]` is `-6283009` at
  `a=-2143289344`; max is `6283008` at `a=2143289343`. The congruence `r ≡ a (mod Q)` still holds.
  - Root cause: the documented bound `[-6283008, 6283008]` is correct only under the **symmetric**
    precondition `|a| <= 2^31-2^22-1` (which excludes `a=-2143289344`, since
    `2143289344 > 2143289343`). The doc's one-sided precondition is too weak for its postcondition —
    either the precondition should be symmetric or the postcondition low end should be `-6283009`.
  - Severity: **documentation/contract only, not a security or functional bug** (same class as OF-1).
    The reduced value is always a correct residue; only the stated tightness is off, and ML-DSA call
    sites feed `reduce32` magnitudes far below this endpoint.
  - Origin & disclosure routing: same as OF-1 — identical comment in `pq-crystals/dilithium/ref`;
    route to **pq-crystals/dilithium**, not PQClean (archiving). **Do NOT auto-file** (CLAUDE.md);
    surfaced to the human 2026-06-08.
  - Impact on Assay: the SAW leg asserts no output bound, so it is unaffected. The Isabelle
    `is_reduce32` spec uses the **true reachable** window `-6283009 <= r <= 6283008` (not the doc's
    `-6283008`), proven over the SAW domain `a <= 2^31-2^22-1`; see `spec/isabelle/MLDSA_NTT_Spec.thy`.
