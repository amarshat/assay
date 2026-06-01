# Target: the C under verification

The implementation being verified is **vendored and pinned** here so the proof is reproducible
against an exact, unmodifiable snapshot.

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
- Date vendored: **NOT YET — no source has been copied into this repo pending human confirmation.**
- Files in the compile closure for `reduce.c` (the exact set we will vendor):
  - `reduce.c`  (the primitives)
  - `reduce.h`  (prototypes + `MONT = -4186625`, `QINV = 58728449`)
  - `params.h`  (defines `Q = 8380417`, `N = 256`; self-contained, no further includes)
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
