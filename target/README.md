# Target: the C under verification

The implementation being verified is **vendored and pinned** here so the proof is reproducible
against an exact, unmodifiable snapshot.

## v1 target
- Source: PQClean reference ML-DSA (Dilithium) C.
- Files under verification: `ntt.c` / `reduce.c` (or equivalent) — the forward NTT and modular
  reduction primitives.

## RECORD BEFORE PROVING (do not skip)
- Upstream repo URL: <FILL IN>
- Commit hash: <FILL IN>
- Date vendored: <FILL IN>
- License of vendored code: <FILL IN — verify; PQClean is permissively licensed but confirm the
  exact terms for the files you include, and keep their license headers intact>

## Rules
- Never edit vendored C silently. If SAW needs a transformation (e.g. isolating a function),
  document exactly what and why here, and prefer a wrapper over an edit.
