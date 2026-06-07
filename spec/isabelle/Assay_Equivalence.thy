(* The payoff (pipeline step 4): the model lifted from Cryptol (MLDSA_NTT.thy) satisfies the
   FIPS/mathematical specification of Montgomery reduction (MLDSA_NTT_Spec.thy).

   STATUS: PARTIAL.  The integer-level mathematical core (`mont_core` below) IS PROVEN: given
   T \<equiv> A*QINV (mod 2^32) and the ranges, r = (A - T*Q) div 2^32 satisfies the congruence and the
   strict bounds -Q<r<Q. What remains OPEN is the word-level BRIDGE: showing the lifted
   `montgomery_reduce` computes exactly that r with that T (relating seq/word casts, sshiftr, and
   the low-32 truncation to the integer expression). The final theorem `montgomery_reduce_correct`
   is therefore still abandoned with `oops` (NOT proven end-to-end).

   IMPORTANT — do not be misled: this theory BUILDS GREEN, but `oops` means NO theorem is
   produced. The C-vs-spec correctness of montgomery_reduce is therefore UNVERIFIED. Only the
   SAW step (C == Cryptol model, make saw) is verified so far. This file deliberately contains
   no proof-hole command (the one CI forbids), which would falsely register a theorem. *)

theory Assay_Equivalence
  imports MLDSA_NTT MLDSA_NTT_Spec
begin

(* ----------------------------------------------------------------------------------------------
   Integer-level core of Montgomery reduction correctness (no words yet).
   If T ≡ A*QINV (mod 2^32) and the ranges hold, then r = (A - T*Q) div 2^32 satisfies the spec.
   QINV*Q = 1 + 114592*2^32, i.e. QINV*Q ≡ 1 (mod 2^32). Q = 8380417, 2^32 = 4294967296. *)
lemma qinv_q: "(58728449::int) * 8380417 = 1 + 114592 * 4294967296" by simp

lemma mont_core:
  fixes A T :: int
  assumes Tc:  "(T - A * 58728449) mod 4294967296 = 0"
      and Tlo: "- 2147483648 \<le> T" and Thi: "T < 2147483648"
      and Alo: "- (2147483648 * 8380417) \<le> A" and Ahi: "A < 2147483648 * 8380417"
  shows "(4294967296 * ((A - T * 8380417) div 4294967296)) mod 8380417 = A mod 8380417
       \<and> - 8380417 < (A - T * 8380417) div 4294967296
       \<and> (A - T * 8380417) div 4294967296 < 8380417"
proof -
  from Tc have "(4294967296::int) dvd (T - A * 58728449)" by (simp add: mod_eq_0_iff_dvd)
  then obtain k where k: "T - A * 58728449 = 4294967296 * k" by (auto elim: dvdE)
  hence T_eq: "T = A * 58728449 + 4294967296 * k" by simp
  define r where "r = - (A * 114592 + k * 8380417)"
  have D_eq: "A - T * 8380417 = 4294967296 * r"
    unfolding r_def T_eq by (simp add: algebra_simps)
  hence r_is: "(A - T * 8380417) div 4294967296 = r" by simp
  \<comment> \<open>congruence: 2^32*r = A - T*Q \<equiv> A (mod Q), since Q dvd T*Q (NO presburger: huge modulus)\<close>
  have cong: "(4294967296 * r) mod 8380417 = A mod 8380417"
  proof -
    have eq: "4294967296 * r = A - T * 8380417" using D_eq by simp
    have "(A - T * 8380417) mod (8380417::int) = A mod 8380417"
      using mod_mult_self1[of A "- T" 8380417] by (simp add: algebra_simps)
    thus ?thesis using eq by simp
  qed
  \<comment> \<open>bounds: multiply the range hyps by Q, then divide the 2^32*r relation. Evaluate the big
      numeral products up front so linarith only sees plain integers.\<close>
  have e1: "(2147483648::int) * 8380417 = 17996808470921216" by simp
  have e2: "(4294967296::int) * 8380417 = 35993616941842432" by simp
  have Tq_lo: "T * 8380417 \<ge> - 17996808470921216" using Tlo by (simp add: mult_right_mono)
  have Tq_hi: "T * 8380417 \<le> 17996808462540799" using Thi by (simp add: mult_right_mono)
  have Ahi': "A < 17996808470921216" using Ahi e1 by simp
  have Alo': "- 17996808470921216 \<le> A" using Alo e1 by simp
  have ub: "4294967296 * r < 35993616941842432" using D_eq Ahi' Tq_lo by linarith
  have lb: "- 35993616941842432 < 4294967296 * r" using D_eq Alo' Tq_hi by linarith
  from ub have rub: "r < 8380417" by simp
  from lb have rlb: "- 8380417 < r" by simp
  from cong rub rlb r_is show ?thesis by simp
qed

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

\<comment> \<open>PROBE bridge lemmas (per-operation seq->word). Confirm whether sext64 is a sign-extend.\<close>
lemma probe_sint_seq: "sint_seq (w :: ('n::len, bool) seq) = sint (seq_to_word w)"
  by (simp add: word_seq_convs)

lemma probe_sext64: "seq_to_word (sext64 x) = (scast (seq_to_word x) :: 64 word)"
  unfolding sext64_def
  apply (simp add: word_seq_convs seq_to_word)
  apply (intro conjI impI; word_bitwise; simp)
  done

\<comment> \<open>collapse the seq-library's 32+32 length-type cast bookkeeping back to a plain low-32 ucast\<close>
lemma ucast_collapse:
  "LENGTH('m::len) = 64 \<Longrightarrow>
   (ucast (take_bit 32 (ucast (y::64 word) :: 'm word)) :: 32 word) = ucast y"
  by (rule bit_word_eqI) (auto simp: bit_simps)

lemma probe_bridge:
  "seq_to_word (montgomery_reduce a) =
   (ucast (sshiftr (seq_to_word a - scast (ucast (seq_to_word a * 58728449) :: 32 word) * 8380417) 32)
    :: 32 word)"
  unfolding montgomery_reduce_def Q64_def QINV_def
  by (simp add: word_seq_convs seq_to_word probe_sext64 ucast_collapse)

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
