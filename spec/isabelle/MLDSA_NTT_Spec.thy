(* Mathematical specification for the ML-DSA modular-reduction primitive.

   SCOPE (v1): montgomery_reduce only. The forward NTT spec is future work.

   FIPS 204 fixes the prime modulus q = 8380417 for ML-DSA. Montgomery reduction is an
   implementation device (not spelled out in FIPS 204 text): for input a it must return a value
   congruent to a * 2^-32 modulo q, in the range (-q, q). This theory states exactly that
   correctness property at the integer level; Assay_Equivalence.thy proves the lifted Cryptol
   model satisfies it.

   STATUS: this file defines specifications only (no proof obligations); it builds under plain HOL. *)

theory MLDSA_NTT_Spec
  imports Main
begin

definition q :: int where "q = 8380417"

(* Input domain for the strict-bound correctness claim: HALF-OPEN  -2^31*q <= a < 2^31*q.
   NB: PQClean's reduce.c comment documents the INCLUSIVE domain -2^31*q <= a <= q*2^31 together
   with the strict postcondition -q < r < q, but those are inconsistent at the upper endpoint:
   montgomery_reduce(2^31*q) = q, violating r < q (see docs/ASSUMPTIONS.md, finding OF-1). The
   strict postcondition holds exactly on the half-open domain below, which is what we specify. *)
definition mont_input_ok :: "int \<Rightarrow> bool" where
  "mont_input_ok a \<longleftrightarrow> -(2^31 * q) \<le> a \<and> a < 2^31 * q"

(* r is a correct Montgomery reduction of a iff  2^32 * r \<equiv> a  (mod q)  and  -q < r < q.
   (Equivalently r \<equiv> a * 2^-32 (mod q), since gcd(2,q)=1.) *)
definition is_montgomery_reduction :: "int \<Rightarrow> int \<Rightarrow> bool" where
  "is_montgomery_reduction a r \<longleftrightarrow> (2^32 * r) mod q = a mod q \<and> -q < r \<and> r < q"

end
