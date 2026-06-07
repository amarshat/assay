# Target: the C under verification

The implementation being verified is **vendored and pinned** here so the proof is reproducible
against an exact, unmodifiable snapshot.

## Note on PQClean's deprecation (2026-06)
PQClean announced it will be archived read-only in **July 2026** (recommending the
[PQ Code Package](https://github.com/pq-code-package) for maintained PQC). **This does not affect
Assay:** the target files are vendored into this directory (committed, SHA-256 recorded) and built
locally, so nothing here fetches PQClean at build/CI time; and the pinned commit `202a8f9` remains
readable even after the repo is archived. More importantly, this `reduce.c` is **verbatim
`pq-crystals/dilithium` reference code** (PQClean only adds the `PQCLEAN_MLDSA44_CLEAN_` symbol
prefix) — `montgomery_reduce` and its doc comment are byte-identical to
`pq-crystals/dilithium/ref/reduce.c`. So the verification targets the canonical Dilithium reference
shared by PQClean, PQ Code Package's `mldsa-native`, and liboqs — not a single dying distribution.
The natural v2 target (optimized ≡ reference) is **PQ Code Package `mldsa-native`**.

## v1 target (this session: modular reduction only — NOT the NTT yet)
- Source: **PQClean** reference ML-DSA (ML-DSA-44), the `clean` C implementation.
- Subsystem: the **modular-reduction primitives** in `reduce.c`. The forward NTT (`ntt.c`) is
  explicitly out of scope for now; we prove the smaller piece it depends on first.
- The `reduce.c` translation unit defines four functions:
  | Function | Signature | What it does |
  |---|---|---|
  | `..._montgomery_reduce` | `int32_t(int64_t a)` | Montgomery reduction: `r ≡ a·2⁻³² (mod Q)`, `−Q<r<Q`, for `−2³¹·Q ≤ a ≤ Q·2³¹` |
  | `..._reduce32` | `int32_t(int32_t a)` | Barrett-style reduction: `r ≡ a (mod Q)`, `−6283008 ≤ r ≤ 6283008`, for `a ≤ 2³¹−2²²−1` |
  | `..._caddq` | `int32_t(int32_t a)` | Conditional add: `a + (a>>31 & Q)` (adds Q iff `a` negative) |
  | `..._freeze` | `int32_t(int32_t a)` | `caddq(reduce32(a))` → canonical representative in `[0, Q)` |
  (symbol prefix: `PQCLEAN_MLDSA44_CLEAN_`)
- **First proof target (recommended):** `montgomery_reduce` — it is the reduction the forward NTT
  actually calls in its butterflies, so it is "the modular reduction the NTT relies on" per
  docs/ROADMAP.md, and it is fully self-contained (single `int64_t → int32_t`, no memory, no loops).
  *Pending the human's confirmation of which function to target (see checkpoint 2 in the session).*

## RECORD BEFORE PROVING (do not skip)
- Upstream repo URL: https://github.com/PQClean/PQClean
- Commit hash: `202a8f96315f9ed219387a50f7e40d04af037ea8` (committed 2026-05-14)
- Path within repo: `crypto_sign/ml-dsa-44/clean/`
- Date identified: 2026-06-01
- Date vendored: 2026-06-01 (into `target/pqclean/`, verbatim from the pinned commit)
- Files vendored (the exact compile closure for `reduce.c`), with SHA-256 for integrity:
  - `reduce.c`  (the primitives) — `8f57fd817a50d4e9d0e6f719da352ad503ac0bacf76ea492a7f3885520857af9`
  - `reduce.h`  (prototypes + `MONT = -4186625`, `QINV = 58728449`) — `c56a083ce9ea4da55a17e9c2f2da74e7277cdede5b2f8e758e441ff9e0813863`
  - `params.h`  (defines `Q = 8380417`, `N = 256`; self-contained, no further includes) — `0210251cea61d26e49b2dad16c4ed86d65474fbffa54c61af7a22c677ddd3cd2`
  - `LICENSE`   (CC0 dedication, kept alongside) — `5d7798eec4d8c8ef0a72dfe805ec54dfd7b212d3928bf9695fda4095d22829ab`
- License of vendored code: **Public Domain (CC0)** — per the per-directory `LICENSE`:
  > Public Domain (https://creativecommons.org/share-your-work/public-domain/cc0/)
  `reduce.c`/`reduce.h`/`params.h` carry no per-file copyright header. The LICENSE's Keccak/AES
  public-domain attribution note does **not** apply to these files. CC0 imposes no attribution or
  header-retention obligation; we keep the `LICENSE` file alongside the vendored code regardless.
- Upstream provenance (per `crypto_sign/ml-dsa-44/META.yml`): the `clean` implementation tracks
  pq-crystals/dilithium commit `cbcd8753a43402885c90343cd6335fb54712cda1`, imported via
  mkannwischer/package-pqclean tree `69049406ed50d83a792f2fa67f6c088dbd0e335e`.

## Rules
- Never edit vendored C silently. If SAW needs a transformation (e.g. isolating a function),
  document exactly what and why here, and prefer a wrapper over an edit.
- When vendored, the files go under `target/pqclean/` and are treated as read-only.
