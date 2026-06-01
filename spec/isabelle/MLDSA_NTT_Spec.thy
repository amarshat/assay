(* FIPS-204 forward NTT specification.
   STATUS: SCAFFOLD / UNVERIFIED skeleton. Either reuse Apple's formalization (check license,
   see spec/README.md) or define independently from FIPS 204. Nothing here is a result until
   the session builds and Assay_Equivalence checks. *)

theory MLDSA_NTT_Spec
  imports Main "HOL-Library.Word"
begin

(* TODO: fix parameters against FIPS 204. *)
definition q :: nat where "q = 8380417"   (* TODO confirm *)
definition n :: nat where "n = 256"        (* TODO confirm *)

(* Specification-level reduction: abstract, range-correct. *)
definition spec_reduce :: "int \<Rightarrow> int" where
  "spec_reduce x = x mod (int q)"          (* TODO: align with FIPS-defined reduction *)

(* Specification-level forward NTT. Define abstractly (e.g. via the evaluation/zeta formulation),
   independent of the C's loop structure. *)
definition spec_ntt :: "int list \<Rightarrow> int list" where
  "spec_ntt xs = xs"                        (* TODO: real FIPS-204 NTT definition *)

end
