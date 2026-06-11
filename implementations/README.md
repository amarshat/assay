# Implementations under assay

This monorepo applies the SAW → Cryptol → Isabelle pipeline to ML-DSA (FIPS 204) implementations.

- The **repository root** (`target/`, `model/`, `proof/`, `spec/`) is the original assay of the
  **PQClean reference C** (`reduce.c` layer proven both legs; forward-NTT functional equivalence +
  model-level overflow-freedom). That is the v1/v1.5 work described in `paper/` and the ePrint; it
  stays at the root because it is the published, DOI-pinned artifact (Zenodo `10.5281/zenodo.20641411`).
- This **`implementations/` folder** holds assays of **additional, third-party implementations** —
  the v2 program of pointing the pipeline at *used-but-unverified* code where defects can actually
  survive (see `docs/ROADMAP.md`).

| Implementation | Language | Status | Why |
|---|---|---|---|
| [`rustcrypto-ml-dsa/`](rustcrypto-ml-dsa/) | Rust | scoping (v2.0 toolchain spike) | de-facto Rust ML-DSA crate; explicitly unaudited; real defect history (RUSTSEC-2025-0144, GHSA-5x2r-hc65-25f9) |
| _(planned)_ wolfSSL `dilithium.c` | C | fallback | own implementation, deployed in wolfBoot; unverified |

Each subdirectory is self-contained (vendored target, model, SAW/Isabelle artifacts, its own README and
findings ledger). Tooling is shared from `scripts/` (`setup_rust.sh` for the SAW-Rust toolchain).

**Disclosure discipline (per `CLAUDE.md`):** any finding in third-party code is recorded privately in
the relevant subdirectory's notes, surfaced to the maintainer (human) first, and routed deliberately
through the project's responsible-disclosure channel. Never auto-filed.
