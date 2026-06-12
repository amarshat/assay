// Harness: calls the public API so the crate's internal arithmetic is monomorphized
// and lands in the linked MIR. Each entry point forces a different slice of the crate:
//  - keygen: NTT, Power2Round (BarrettReduce with M = 2^d = 8192), sampling
//  - sign:   decompose (M = 2*gamma2), the final z reduction (M = q, via
//            mod_plus_minus::<SpecQ> in signing.rs), hint generation
//  - verify: use-hint / hint decode, norm checks
use ml_dsa::{MlDsa44, Seed, Signature, SigningKey, VerifyingKey};
use ml_dsa::signature::{Signer, Verifier};

pub fn keygen44(seed: &Seed) -> SigningKey<MlDsa44> {
    SigningKey::<MlDsa44>::from_seed(seed)
}

pub fn sign44(sk: &SigningKey<MlDsa44>, msg: &[u8]) -> Signature<MlDsa44> {
    // Signer for SigningKey uses the deterministic ML-DSA variant (empty context).
    sk.sign(msg)
}

pub fn verify44(vk: &VerifyingKey<MlDsa44>, msg: &[u8], sig: &Signature<MlDsa44>) -> bool {
    vk.verify(msg, sig).is_ok()
}
