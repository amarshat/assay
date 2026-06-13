# Draft question for Galois (SAW Zulip #saw, or saw-script#3298 thread)

**Title:** Idiomatic SAW tactic for `mir_verify` of Barrett reduction over a wide
(2^46) input domain — z3/abc time out

---

Verifying a Barrett reduction in RustCrypto's `module_lattice` (the field core
shared by `ml-dsa` / `ml-kem`) with `mir_verify`. The function (q = 8380417):

```rust
fn barrett_reduce(x: Self::Long) -> Self::Int {   // Long = u64, Int = u32
    let x: Self::LongLong = x.into();              // LongLong = u128
    let product  = x * Self::BARRETT_MULTIPLIER;   // MULTIPLIER = (1<<46)/q = 8396807
    let quotient = product >> Self::BARRETT_SHIFT;  // SHIFT = 46
    let remainder = x - quotient * Self::QLL;
    Self::small_reduce(Truncate::truncate(remainder))
}
```

Spec / goal:

```
let barrett_spec = do {
    x <- mir_fresh_var "x" mir_u64;
    mir_precond {{ x < (1 << 46) }};           // a*b domain: a,b < q < 2^23
    mir_execute_func [mir_term x];
    mir_return (mir_term {{ drop`{32} (x % 8380417) : [32] }});
};
mir_verify m ".../barrett_reduce" [] false barrett_spec z3;
```

**Symptom:** scales fine on a narrow domain, dies on the real one.
- `x < 2^28`  → z3 proves in ~4 s.
- `x < 2^36`, `x < 2^44`, `x < 2^46` → no result.
- Timed out (≥5–9 min each, killed): `z3`, `abc`,
  `do { goal_eval_unint []; z3; }`, and a carry-fold-reformulated spec (still
  compares against the impl). cvc4/cvc5/yices on hand; no bitwuzla/boolector.

Reading it as: bitblasting `(x * 8396807) >> 46` — a ~92-bit product, divided by
2^46 — over a 2^46-wide symbolic input is just too big for SAT/BV.

**Question:** what's the idiomatic SAW way to discharge a Barrett-style
`(x*M) >> k` reduction over a wide domain? Specifically:
1. A tactic that avoids bitblasting the wide multiply/shift — e.g. abstracting
   the quotient as a witness with a multiply-only side condition, or
   `unint`-ing the shift and supplying the Euclidean identity as a rewrite?
2. Is the intended route to drop to unbounded-`Integer` reasoning (nlsat) for
   the arithmetic and bridge BV↔Integer, rather than proving it at BV width?
   (We did exactly this for the analogous `montgomery_reduce` in our C/Cryptol
   pipeline via a lift to Isabelle — wondering if there's a SAW-native idiom
   that avoids the second tool.)

Minimal repro: `repro_barrett_2p46.saw` (single `mir_verify`, the timeout above).

**Related, same disease:** verifying one NTT layer (`ntt_layer<128,1>` ==
a FIPS 204 Alg 41 spec) with ALL field ops (neg/add/sub/mul == mod q) assumed
via `mir_unsafe_assume_spec` — overrides apply, simulation completes, but the
layer goal times out at "Checking proof obligations". The spec computes
`(...) % q` per output coefficient (256 of them, `[64]` urem-by-constant), and
those don't term-match the impl's reduce-after-each-op, so z3 bitblasts all 256.
Is the right move to write the spec compositionally from the same override terms
so it discharges by rewriting, or is there a SAW idiom for "many independent
modular-reduction obligations" (a urem-by-constant rewrite / simp set)?

Context: open formal-verification project on RustCrypto ML-DSA; scalar layer
(Barrett over u32, ct_div, zetas, hint layer) already SAW-verified. This wider
Barrett is the gate for the NTT-layer (FIPS 204 Alg 41/42) proofs.
