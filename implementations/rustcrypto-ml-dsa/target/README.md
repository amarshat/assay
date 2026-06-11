# Vendored target: RustCrypto `ml-dsa`

Pinned, vendored copy of the verification target. Never edit it silently; if a transformation is
needed for SAW/MIR, document it here.

- **Crate:** `ml-dsa`
- **Version:** `0.1.1`
- **Source:** crates.io published artifact, `https://static.crates.io/crates/ml-dsa/ml-dsa-0.1.1.crate`
- **`.crate` SHA-256:** `add6b9d92e496f16f4526d68ff29da1483aba4b119baeab8bed3b9e3544a6f3d`
- **Vendored:** 2026-06-11
- **Upstream:** [RustCrypto/signatures](https://github.com/RustCrypto/signatures), crate dir `ml-dsa/`

We vendor the **crates.io** artifact (not a git checkout) because that is exactly what downstream
users pull, i.e. the supply-chain object under assay.

Source files of interest (see `../README.md` for the per-file verification plan): `algebra.rs`,
`ntt.rs`, `hint.rs`, `verifying.rs`, `signing.rs`.

## Companion crate: `module-lattice`

The field/polynomial/NTT arithmetic that `ml-dsa` builds on lives in `module-lattice` (also used by
RustCrypto `ml-kem`), so it is vendored alongside.

- **Crate:** `module-lattice`
- **Version:** `0.2.3`
- **`.crate` SHA-256:** `0c61b87c9683ab7cb1c6871d261ad5479b6b10ceb52c4352aaca3b5d35a8febe`
- **Source:** `https://static.crates.io/crates/module-lattice/module-lattice-0.2.3.crate`
- Arithmetic + NTT live in `module-lattice-0.2.3/src/algebra.rs` and `lib.rs`.
