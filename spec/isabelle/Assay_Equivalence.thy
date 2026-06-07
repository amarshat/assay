(* The payoff: the model lifted from Cryptol (via cryptol-to-isabelle, see MLDSA_NTT.thy) satisfies
   the FIPS/mathematical specification of Montgomery reduction (MLDSA_NTT_Spec.thy).

   STATUS: IN PROGRESS / UNVERIFIED. No equivalence theorem is asserted yet. There is deliberately
   NO `sorry` in this file: a `sorry` would register an unproven claim as a theorem, which the
   project forbids (and CI rejects). The real theorem
       mont_input_ok (sint a) \<Longrightarrow> is_montgomery_reduction (sint a) (sint (montgomery_reduce a))
   (modulo the exact seq->int coercions from the Cryptol library) will be added and discharged here.
   Until `isabelle build Assay` checks it with no holes, montgomery_reduce is NOT proven correct
   against the spec. *)

theory Assay_Equivalence
  imports MLDSA_NTT MLDSA_NTT_Spec
begin

(* equivalence theorem to be developed once the Cryptol support library is built and its
   seq/word coercion constants are confirmed via find_consts/find_theorems. *)

end
