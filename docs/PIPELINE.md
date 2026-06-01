# The verification pipeline

Mirrors Apple's published corecrypto approach, applied to third-party C.

```
 ┌─────────────────────┐
 │  target C subroutine│  target/pqclean/...   (vendored, pinned)
 └──────────┬──────────┘
            │ (1) hand-translate  → model/cryptol/MLDSA_NTT.cry
            ▼
 ┌─────────────────────┐
 │   Cryptol model     │
 └──────────┬──────────┘
            │ (2) SAW: llvm_verify  C bitcode ≡ Cryptol   → proof/saw/mldsa_ntt.saw
            ▼   (must exit 0)
 ┌─────────────────────┐
 │  C ≡ Cryptol  ✔      │
 └──────────┬──────────┘
            │ (3) cryptol-to-isabelle  → spec/isabelle/ (generated model)
            ▼
 ┌─────────────────────┐        ┌──────────────────────────────┐
 │  Isabelle model     │        │ FIPS-204 NTT spec in Isabelle │
 └──────────┬──────────┘        │ spec/isabelle/MLDSA_NTT_Spec  │
            │                    └───────────────┬──────────────┘
            │ (4) prove equivalence (Assay_Equivalence.thy)
            ▼                                    │
 ┌─────────────────────────────────────────────────────────────┐
 │  model ≡ FIPS-204 spec  ✔   ⇒  C subroutine is correct        │
 └─────────────────────────────────────────────────────────────┘
```

## Step notes
1. **C → Cryptol** is manual and is itself a source of error; SAW (step 2) is what makes it
   trustworthy by checking the model against the actual C.
2. **SAW** loads the LLVM bitcode and proves the function computes the Cryptol term for all
   inputs in scope.
3. **cryptol-to-isabelle** (Galois, shipped in saw-script v1.5.1) lifts the Cryptol model into
   Isabelle, eliminating hand-translation error between the two.
4. **Isabelle equivalence** is the hard mathematical step; lean on Apple's released lemma
   libraries (where licensed) to keep proofs tractable.
