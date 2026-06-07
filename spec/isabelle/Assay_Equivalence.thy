(* The payoff (pipeline step 4): the model lifted from Cryptol (MLDSA_NTT.thy) satisfies the
   FIPS/mathematical specification of Montgomery reduction (MLDSA_NTT_Spec.thy).

   STATUS: OPEN / NOT PROVEN.  This is the hard mathematical step and it is NOT yet discharged.
   The theorem below is stated and *mechanically reduced* to a concrete word-arithmetic goal
   (see the reduction proof + the recorded remaining goal), but the final arithmetic is left
   open and the proof is abandoned with `oops`.

   IMPORTANT — do not be misled: this theory BUILDS GREEN, but `oops` means NO theorem is
   produced. The C-vs-spec correctness of montgomery_reduce is therefore UNVERIFIED. Only the
   SAW step (C == Cryptol model, make saw) is verified so far. This file deliberately contains
   no proof-hole command (the one CI forbids), which would falsely register a theorem. *)

theory Assay_Equivalence
  imports MLDSA_NTT MLDSA_NTT_Spec
begin

context includes cryptol_translation_syntax begin

text \<open>
  Goal: for a 64-bit input \<open>a\<close> within the documented range, the lifted \<open>montgomery_reduce\<close>
  returns a correct Montgomery reduction of \<open>sint_seq a\<close>, i.e.
  \<open>2^32 * r \<equiv> a (mod q)\<close> and \<open>-q < r < q\<close>, where \<open>r = sint_seq (montgomery_reduce a)\<close>.

  PROOF PLAN for the remaining word-arithmetic goal (the `simp` below reduces to it):
    Let A = sint(seq_to_word a), t' = signed value of the low 32 bits of (a * QINV).
    1. QINV * q \<equiv> 1 (mod 2^32)  [QINV = 0x3802001, q = 0x7FE001], hence t' * q \<equiv> A (mod 2^32),
       so 2^32 dvd (A - t'*q).
    2. The body computes (A - t'*q) >>$ 32 = (A - t'*q) div 2^32 EXACTLY (arithmetic shift on a
       value divisible by 2^32); the final drop`{32} keeps the low 32 bits, which fits since
       |A - t'*q| < 2^32 * q (from |A| <= 2^31*q, |t'| < 2^31). So r = (A - t'*q) div 2^32.
    3. Then 2^32 * r = A - t'*q \<equiv> A (mod q), giving the congruence; and the bound on |A - t'*q|
       gives -q < r < q.
  Mechanizing step 2 over the seq/word coercions (UCAST between 32 and 32+32 length types,
  sshiftr, take_bit) is the bulk of the remaining work.
\<close>

theorem montgomery_reduce_correct:
  fixes a :: "(64, bool) seq"
  assumes "mont_input_ok (sint_seq a)"
  shows "is_montgomery_reduction (sint_seq a) (sint_seq (montgomery_reduce a))"
  unfolding is_montgomery_reduction_def mont_input_ok_def MLDSA_NTT_Spec.q_def
            montgomery_reduce_def sext64_def Q64_def QINV_def
  apply (simp add: word_seq_convs seq_to_word)
  (* Remaining goal is a pure 64/32-bit word + (mod 8380417) arithmetic obligation;
     see PROOF PLAN above. NOT discharged yet. *)
  oops

end

end
