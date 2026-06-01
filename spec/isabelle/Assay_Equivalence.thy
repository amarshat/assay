(* The payoff: the model lifted from Cryptol (via cryptol-to-isabelle) equals the FIPS spec.
   STATUS: SCAFFOLD / UNVERIFIED. `sorry` is a HOLE, not a proof — every `sorry` must be gone
   before any correctness claim is made. CI should reject `sorry`. *)

theory Assay_Equivalence
  imports MLDSA_NTT_Spec
  (* TODO: import the generated model produced by cryptol-to-isabelle, and Apple lemma
     libraries where licensed. *)
begin

theorem ntt_model_matches_spec:
  "True"   (* TODO: state equivalence between the lifted Cryptol model and spec_ntt. *)
  sorry    (* TODO: discharge. Remove sorry. *)

end
