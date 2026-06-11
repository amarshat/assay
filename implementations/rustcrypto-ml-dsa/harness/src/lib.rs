// Harness: calls the public deterministic key-gen so the crate's internal arithmetic
// (NTT, Barrett reduce, sampling) is monomorphized and lands in the linked MIR.
use ml_dsa::{MlDsa44, SigningKey, Seed};

pub fn keygen44(seed: &Seed) -> SigningKey<MlDsa44> {
    SigningKey::<MlDsa44>::from_seed(seed)
}
