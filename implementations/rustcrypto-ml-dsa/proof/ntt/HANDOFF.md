# NTT layer proof — handoff (2026-06-12)

> **Verification status: UNVERIFIED.** The three files in this directory were
> *written* this session but **not yet run to a `saw` exit-0 in this session**.
> Per the repo prime directive (CLAUDE.md): a `.saw`/`.cry` that "looks
> complete" is **not a proof**. The first job below is to actually run them.

## What this task is

v2 (RustCrypto ml-dsa 0.1.1, SAW-Rust via mir-json) currently has the scalar
layer done: Barrett reduce, ct_div, zetas table, hint layer — all tool-verified
and in CI (`.github/workflows/rust.yml`). See
`../../../../memory` status note for the full v2 ledger.

**This directory is the NEXT step: the NTT transform itself** —
RustCrypto's `ntt_layer` / `ntt_inverse_layer` vs **FIPS 204 Algorithm 41/42**
(forward / inverse NTT). The zetas table these layers use is already
artifact-checked (`../zetas/`); what's unproven is that the butterfly *layers*
compute the Alg 41/42 maps.

## Files here

1. **`field_ops.saw`** — the butterfly *leaves*: `module_lattice::algebra::Elem`
   `neg/add/sub/mul == arithmetic mod q` (q = 8380417). `mul` is split into a
   `barrett_reduce(x) == x mod q for x < 2^46` lemma used as an override (same
   trick v1 used). These are `module_lattice 0.2.3` functions **shared with
   ml-kem**, so verifying them covers both crates' field cores.
   Status: written, **not run this session**.

2. **`fips204_ntt.cry`** — Cryptol spec of ONE generic NTT layer, forward
   (`nttLayerFwd`) and inverse (`nttLayerInv`), transcribed from FIPS 204
   Alg 41/42. Parameterized by `(len, iterations=128/len, m0)`. Each butterfly
   is a disjoint (j, j+len) pair, so a layer is expressed as a parallel map over
   all 256 positions. Encoding discipline matches the other spec files (signed/
   unsigned `[64]`, exact for these magnitudes).

3. **`layer_feasibility_test.saw`** — a **feasibility probe**: proves ONE
   forward layer `ntt_layer<128,1>` (m: 0→1) against `nttLayerFwd`. Tests the
   whole machinery at once: indexwise `Elem` array `points_to` over a symbolic
   `[256][32]`, the `&mut m: usize` postcondition, and **solver tractability of
   128 inlined butterflies** (mul-by-concrete-zeta keeps the Barrett multiplies
   linear). If this one layer proves in reasonable wall-clock, the rest are the
   same shape at smaller LEN.

## How to run (exact, from repo root)

These need the v2 Rust toolchain + the harness MIR artifact. Mirror
`.github/workflows/rust.yml`:

```sh
# 1. toolchain + solvers on PATH (SAW shells out to z3 in .tools/bin)
export PATH="$PWD/.tools/bin:$PATH"
export SAW_RUST_LIBRARY_PATH="$PWD/.tools/rlibs"

# 2. (re)build the harness MIR if build/mldsa_harness.linked-mir.json is stale
CARGO_TARGET_DIR="$PWD/build" cargo +nightly-2025-09-14 saw-build
#   (run inside implementations/rustcrypto-ml-dsa/harness; see setup_rust.sh)

# 3. run the proofs — .saw paths load the MIR relative to the SCRIPT dir
.tools/bin/saw implementations/rustcrypto-ml-dsa/proof/ntt/field_ops.saw
.tools/bin/saw implementations/rustcrypto-ml-dsa/proof/ntt/layer_feasibility_test.saw
```

`field_ops.saw` should be quick. `layer_feasibility_test.saw` is the risk — it
may be slow or the `_inst` name may not match (see below).

## Known risks / likely blockers

- **`_inst` monomorphization hash.** `layer_feasibility_test.saw` hard-codes
  `ml_dsa::ntt::ntt_layer::_inst4c08bb177e505583`. The `_inst` hash is
  machine-stable but **monomorphization-dependent** — if the harness doesn't
  instantiate `ntt_layer<128,1>` (or instantiates a different set), this name
  won't resolve. If SAW errors "no such function", grep the MIR for the real
  name: `grep -o 'ntt_layer[^"]*' build/...linked-mir.json | sort -u`, and make
  sure the harness actually calls `.ntt()` so the const-generic instances get
  monomorphized. Crate disambiguators ([0]-style suffixes) are machine-dependent
  and broke CI before — keep disambiguator-free names, keep `_inst` hashes.
- **Solver tractability.** 128 butterflies inlined is the whole bet. v1's *SAW*
  full-NTT unroll (~3000 obligations) was computationally impractical and was
  abandoned for an Isabelle induction. Here each *layer* is a separate, bounded
  `mir_verify` (mul-by-concrete-zeta ⇒ linear), which should be far more
  tractable — but confirm the LEN=128 probe actually completes before writing
  the other 7 forward + 8 inverse layers.
- **Cryptol/SAW encoding.** Keep arithmetic in signed/unsigned `[64]` — mixing
  Cryptol `Integer` with bitvectors makes z3 stall forever on `mir_verify`
  goals (documented v2 gotcha).

## BLOCKER (2026-06-13): 2^46 Barrett NOT directly SMT-provable

The `mul` override needs `barrett_reduce(x) == x mod q` over **x < 2^46** (the
a*b product domain, a,b < q < 2^23). Tested this session, all TIMED OUT:
- z3 on direct `x % q`: fast for x < 2^28 (~4s), STALLS at 2^36, 2^44 (killed).
- abc on full 2^46: timeout 124 at 9 min.
- `_barrett_bref.saw` (carry-fold spec, no wide urem): timeout 124 at 8 min —
  doesn't help, because `mir_verify` still compares against the IMPL, which does
  `(x * M) >> 46` on a ~92-bit u128 product (M = 8396807, SHIFT = 46). The `>>46`
  of a wide product is the bitblast bomb; reformulating the SPEC can't remove it.
- Only solvers bundled in `.tools/bin`: abc cvc4 cvc5 yices z3. No bitwuzla.

Conclusion: structural, not solver choice. Direct bitvector proof over 2^46 is
out. **Next route (real work, not a probe):** prove the Barrett identity
`x - ((x*M)>>46)*q ≡ x (mod q)  /\  ∈ [0,2q)` in UNBOUNDED Integer arithmetic
(z3 nonlinear, no bitblast) + a BV<->Integer bridge — same shape as v1
montgomery_reduce. Either SAW with an explicit quotient witness, or lift to
Isabelle as v1 did. Everything downstream (field_ops mul, layers) waits on this.

Note: the EXISTING verified barrett (commit d9414f9, proof/reduce/) is over u32
(x < 2^32) — tractable. The NTT need is the WIDER u64/2^46 domain. Different goal.

## Definition of done for this task

1. `field_ops.saw` exits 0 (field core conforms).
2. `layer_feasibility_test.saw` exits 0 (one forward layer ≡ Alg 41).
3. Generalize to all 8 forward layers (LEN = 128,64,…,1; m0 = 0,1,3,7,15,31,63,
   127) and 8 inverse layers (Alg 42, `nttLayerInv`, m0 = 256,128,…,2).
4. **Non-vacuity / mutation check** for each (mirror the mutated-moduli guard in
   `rust.yml` — mutate a zeta or a sign and confirm the proof FAILS).
5. Wire into `.github/workflows/rust.yml` as new steps; confirm CI green.
6. Update `docs/ASSUMPTIONS.md` with any new trust-base entries, and the memory
   status note. **Do NOT claim it's proven until saw exits 0 here.**

## Hard rules (CLAUDE.md — non-negotiable)

- Never state/imply a proof passes unless a tool verified it **this session**.
  If you can't run `saw`, mark it UNVERIFIED and say so.
- Found a discrepancy/bug? **Stop.** Record in `docs/ASSUMPTIONS.md` under "Open
  findings", surface to the human. **Do not** open any public issue/PR — there
  are already two findings (OF-1, OF-2) disclosed deliberately as
  pq-crystals/dilithium#114; disclosure is human-routed only.
- Target crate in `target/` is vendored + pinned. Never silently edit it.
- Commits: **no `Co-Authored-By` trailer** (user preference).
