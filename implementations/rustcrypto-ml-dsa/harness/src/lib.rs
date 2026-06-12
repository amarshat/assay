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

// Forces the byte encode/decode layer (encode.rs + hint.rs bit_pack/bit_unpack —
// the latter is the GHSA-5x2r-hc65-25f9 hint-index-validation site).
pub fn sig_roundtrip44(sig: &Signature<MlDsa44>) -> Option<Signature<MlDsa44>> {
    let enc = sig.encode();
    Signature::<MlDsa44>::decode(&enc)
}

// Adversarial regression TESTS (not proofs) for the hint-index validation in
// bit_unpack, exercised through the public Signature::decode. Direct symbolic
// verification of bit_unpack is blocked: hybrid-array's slice access is
// ptr-cast + from_raw_parts, which crucible-mir (SAW 1.5.1) cannot simulate
// (see NOTES.md). FIPS 204 Algorithm 21 HintBitUnpack must reject: hint indices
// not strictly increasing within a polynomial (the GHSA bug class), cut
// positions that decrease, cuts above omega, and nonzero padding after the last
// cut. ML-DSA-44 hint encoding = the trailing omega + k = 80 + 4 = 84 bytes.
#[cfg(test)]
mod hint_validation_tests {
    use super::*;
    use ml_dsa::signature::SignatureEncoding;

    const SIG_LEN: usize = 2420; // ML-DSA-44 signature size
    const HINT_OFF: usize = SIG_LEN - 84; // hint region: indices[80] ++ cuts[4]

    fn base_sig_bytes() -> Vec<u8> {
        let seed = Seed::default();
        let sk = keygen44(&seed);
        let sig = sign44(&sk, b"hint validation test");
        sig.to_bytes().to_vec()
    }

    fn decode(bytes: &[u8]) -> Option<Signature<MlDsa44>> {
        Signature::<MlDsa44>::decode(bytes.try_into().expect("signature length"))
    }

    /// Overwrite the hint region with `indices` (padded with zeros) and `cuts`.
    fn with_hint(mut bytes: Vec<u8>, indices: &[u8], cuts: [u8; 4]) -> Vec<u8> {
        for b in &mut bytes[HINT_OFF..] {
            *b = 0;
        }
        bytes[HINT_OFF..HINT_OFF + indices.len()].copy_from_slice(indices);
        bytes[HINT_OFF + 80..].copy_from_slice(&cuts);
        bytes
    }

    #[test]
    fn well_formed_hint_accepted() {
        // control: strictly increasing indices [5, 9] in poly 0 — must decode
        let b = with_hint(base_sig_bytes(), &[5, 9], [2, 2, 2, 2]);
        assert!(decode(&b).is_some());
    }

    #[test]
    fn duplicate_index_rejected() {
        // THE GHSA-5x2r-hc65-25f9 case: duplicate index within one polynomial
        let b = with_hint(base_sig_bytes(), &[5, 5], [2, 2, 2, 2]);
        assert!(decode(&b).is_none());
    }

    #[test]
    fn decreasing_index_rejected() {
        let b = with_hint(base_sig_bytes(), &[9, 5], [2, 2, 2, 2]);
        assert!(decode(&b).is_none());
    }

    #[test]
    fn decreasing_cuts_rejected() {
        let b = with_hint(base_sig_bytes(), &[5], [1, 0, 1, 1]);
        assert!(decode(&b).is_none());
    }

    #[test]
    fn cut_above_omega_rejected() {
        let b = with_hint(base_sig_bytes(), &[], [0, 0, 0, 81]);
        assert!(decode(&b).is_none());
    }

    #[test]
    fn nonzero_padding_after_last_cut_rejected() {
        // one used index, but junk later in the index area (FIPS: y[Index..omega-1] must be 0)
        let mut b = with_hint(base_sig_bytes(), &[5], [1, 1, 1, 1]);
        b[HINT_OFF + 79] = 7;
        assert!(decode(&b).is_none());
    }

    #[test]
    fn duplicate_index_across_polys_accepted() {
        // same index value in DIFFERENT polynomials is legal (strictness is per-poly)
        let b = with_hint(base_sig_bytes(), &[5, 5], [1, 2, 2, 2]);
        assert!(decode(&b).is_some());
    }
}
