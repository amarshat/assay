(* The payoff (pipeline step 4): the model lifted from Cryptol (MLDSA_NTT.thy) satisfies the
   FIPS/mathematical specification of Montgomery reduction (MLDSA_NTT_Spec.thy).

   STATUS: PROVEN end-to-end (no proof holes). `isabelle build -D spec/isabelle Assay` exits 0.
   The final theorem `montgomery_reduce_correct` establishes that the lifted Cryptol
   `montgomery_reduce` satisfies `is_montgomery_reduction` (2^32*r == a (mod Q) and strict
   -Q<r<Q) for every 64-bit input in the half-open documented range. Structure:
     - mont_core      : integer-level correctness (congruence + strict bounds), given
                        T == A*QINV (mod 2^32) and the ranges.
     - probe_bridge   : the lifted montgomery_reduce equals a clean word computation
                        (seq -> word, via word_seq_convs + sext64=scast + ucast_collapse).
     - red_value      : sint of that word computation = (A - T*Q) div 2^32 (no overflow / fits).
     - tcong          : T == A*QINV (mod 2^32), via the low-32 truncation.
   Combined with the SAW leg (C == Cryptol model, make saw), this completes C == FIPS-spec for
   montgomery_reduce over the half-open domain. Contains NO proof-hole command. *)

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

\<comment> \<open>generic: take_bit at the full word length is the identity (per Galois #3298;
    the library's take_bit_length_eq is over-specialized)\<close>
lemma take_bit_length_eq'[simp]: "LENGTH('n) = n \<Longrightarrow> take_bit n (w :: 'n :: len word) = w"
  by fastforce

\<comment> \<open>sint of a down-cast (64->32) when the signed value fits in 32 bits\<close>
lemma sint_ucast_fit:
  fixes V :: "64 word"
  assumes "- 2147483648 \<le> sint V" and "sint V < 2147483648"
  shows "sint (ucast V :: 32 word) = sint V"
proof -
  have "sint (ucast V :: 32 word) = sint (scast V :: 32 word)"
    by (simp add: scast_ucast_down_same)
  also have "\<dots> = signed_take_bit 31 (sint V)"
    by (simp add: signed_scast_eq)
  also have "\<dots> = sint V" using assms by (simp add: signed_take_bit_int_eq_self)
  finally show ?thesis .
qed

\<comment> \<open>sint of the clean word computation equals the integer expression mont_core reasons about\<close>
lemma red_value:
  fixes aw :: "64 word" and t32 :: "32 word"
  assumes Alo: "- (2147483648 * 8380417) \<le> sint aw" and Ahi: "sint aw < 2147483648 * 8380417"
  shows "sint (ucast (sshiftr (aw - scast t32 * 8380417) 32) :: 32 word)
       = (sint aw - sint t32 * 8380417) div 4294967296"
proof -
  have e1: "(2147483648::int) * 8380417 = 17996808470921216" by simp
  have t_lo: "(- 2147483648::int) \<le> sint t32" using sint_greater_eq[of t32] by simp
  have t_hi: "sint t32 \<le> 2147483647" using sint_lt[of t32] by simp
  have tq_lo: "- 17996808470921216 \<le> sint t32 * 8380417"
    using mult_right_mono[OF t_lo, of 8380417] by simp
  have tq_hi: "sint t32 * 8380417 \<le> 17996808462540799"
    using mult_right_mono[OF t_hi, of 8380417] by simp
  have hom: "aw - scast t32 * 8380417 = (of_int (sint aw - sint t32 * 8380417) :: 64 word)"
    by (simp add: of_int_sint_scast)
  have fitX: "- 9223372036854775808 \<le> sint aw - sint t32 * 8380417
            \<and> sint aw - sint t32 * 8380417 < 9223372036854775808"
    using Alo Ahi tq_lo tq_hi e1 by linarith
  have sintX: "sint (aw - scast t32 * 8380417) = sint aw - sint t32 * 8380417"
    unfolding hom by (rule sint_of_int_eq; (use fitX in simp))
  have sh: "sint (sshiftr (aw - scast t32 * 8380417) 32) = (sint aw - sint t32 * 8380417) div 4294967296"
    using sintX by (simp add: sshiftr_div_2n)
  have ub: "sint aw - sint t32 * 8380417 < 35993616941842432" using Ahi tq_lo e1 by linarith
  have lb: "- 35993616941842432 \<le> sint aw - sint t32 * 8380417" using Alo tq_hi e1 by linarith
  have v_hi: "(sint aw - sint t32 * 8380417) div 4294967296 < 2147483648"
  proof -
    have "(sint aw - sint t32 * 8380417) div 4294967296 \<le> 35993616941842431 div 4294967296"
      using ub by (auto intro: zdiv_mono1)
    thus ?thesis by simp
  qed
  have v_lo: "- 2147483648 \<le> (sint aw - sint t32 * 8380417) div 4294967296"
  proof -
    have "(- 35993616941842432) div (4294967296::int) \<le> (sint aw - sint t32 * 8380417) div 4294967296"
      using lb by (auto intro: zdiv_mono1)
    thus ?thesis by simp
  qed
  have Vfit: "- 2147483648 \<le> sint (sshiftr (aw - scast t32 * 8380417) 32)
            \<and> sint (sshiftr (aw - scast t32 * 8380417) 32) < 2147483648"
    using v_lo v_hi unfolding sh by simp
  show ?thesis
    using sint_ucast_fit[OF conjunct1[OF Vfit] conjunct2[OF Vfit]] sh by simp
qed

\<comment> \<open>the low-32-bits t satisfy t \<equiv> a*QINV (mod 2^32)\<close>
lemma tcong:
  fixes aw :: "64 word"
  shows "(sint (ucast (aw * 58728449) :: 32 word) - sint aw * 58728449) mod 4294967296 = 0"
proof -
  have stb: "sint (ucast (aw * 58728449) :: 32 word) = signed_take_bit 31 (sint (aw * 58728449))"
  proof -
    have "sint (ucast (aw * 58728449) :: 32 word) = sint (scast (aw * 58728449) :: 32 word)"
      by (simp add: scast_ucast_down_same)
    thus ?thesis by (simp add: signed_scast_eq)
  qed
  have m1: "signed_take_bit 31 (sint (aw * 58728449)) mod 4294967296
          = sint (aw * 58728449) mod 4294967296"
    by (simp add: signed_take_bit_eq_take_bit_shift take_bit_eq_mod mod_diff_left_eq)
  have su: "\<And>y::64 word. sint y mod 4294967296 = uint y mod 4294967296"
  proof -
    fix y :: "64 word"
    have key: "(uint y - 18446744073709551616) mod 4294967296 = uint y mod 4294967296"
      using mod_mult_self1[of "uint y" "- 4294967296" 4294967296] by simp
    show "sint y mod 4294967296 = uint y mod 4294967296"
      using key by (simp add: word_sint_msb_eq size_word.rep_eq)
  qed
  have m2: "sint (aw * 58728449) mod 4294967296 = (sint aw * 58728449) mod 4294967296"
  proof -
    have "sint (aw * 58728449) mod 4294967296 = uint (aw * 58728449) mod 4294967296" by (rule su)
    also have "\<dots> = (uint aw * 58728449) mod 4294967296"
      by (simp add: uint_word_ariths(3) take_bit_eq_mod mod_mod_cancel)
    also have "\<dots> = (sint aw * 58728449) mod 4294967296"
      by (rule mod_mult_cong[OF su[of aw, symmetric] refl])
    finally show ?thesis .
  qed
  have "sint (ucast (aw * 58728449) :: 32 word) mod 4294967296 = (sint aw * 58728449) mod 4294967296"
    using stb m1 m2 by simp
  thus ?thesis by (simp add: mod_eq_dvd_iff)
qed

\<comment> \<open>per Galois (saw-script #3298): use the cryptol_syntax bundle for hand-written proofs;
    cryptol_translation_syntax is meant only for translator output and removes notations like \<open>^\<close>.\<close>
context includes cryptol_syntax begin

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

theorem montgomery_reduce_correct:
  fixes a :: "(64, bool) seq"
  assumes "mont_input_ok (sint_seq a)"
  shows "is_montgomery_reduction (sint_seq a) (sint_seq (montgomery_reduce a))"
proof -
  define aw  :: "64 word" where "aw  = seq_to_word a"
  define t32 :: "32 word" where "t32 = ucast (aw * 58728449)"
  have A_eq: "sint_seq a = sint aw" unfolding aw_def by (rule probe_sint_seq)
  have Arng: "- (2147483648 * 8380417) \<le> sint aw \<and> sint aw < 2147483648 * 8380417"
    using assms unfolding mont_input_ok_def MLDSA_NTT_Spec.q_def A_eq by simp
  \<comment> \<open>bridge to the clean word value (Galois #3298: the no-op 64->32+32 ucasts discharge via
      is_up / ucast_up_ucast / take_bit_length_eq'), then to its integer meaning\<close>
  have bval: "sint_seq (montgomery_reduce a)
            = sint (ucast (sshiftr (aw - scast t32 * 8380417) 32) :: 32 word)"
    unfolding aw_def t32_def montgomery_reduce_def
    by (simp add: unsigned_take_bit_eq is_up QINV_def Q64_def
                  probe_sext64 seq_to_word ucast_up_ucast take_bit_length_eq')
  have rval: "sint_seq (montgomery_reduce a) = (sint aw - sint t32 * 8380417) div 4294967296"
    unfolding bval using red_value[OF conjunct1[OF Arng] conjunct2[OF Arng]] .
  \<comment> \<open>premises for mont_core\<close>
  have Tcong: "(sint t32 - sint aw * 58728449) mod 4294967296 = 0"
    unfolding t32_def by (rule tcong)
  have Trng: "- 2147483648 \<le> sint t32 \<and> sint t32 < 2147483648"
    using sint_greater_eq[of t32] sint_lt[of t32] by simp
  show ?thesis
    unfolding is_montgomery_reduction_def MLDSA_NTT_Spec.q_def A_eq rval
    using mont_core[OF Tcong conjunct1[OF Trng] conjunct2[OF Trng]
                       conjunct1[OF Arng] conjunct2[OF Arng]]
    by simp
qed

\<comment> \<open>--- the rest of the reduce.c layer: caddq / reduce32 / freeze vs spec ---\<close>

lemma caddq_correct:
  fixes a :: "(32, bool) seq"
  shows "is_caddq (sint_seq a) (sint_seq (caddq a))"
proof -
  define aw :: "32 word" where "aw = seq_to_word a"
  have A: "sint_seq a = sint aw" unfolding aw_def by (rule probe_sint_seq)
  have br: "sint_seq (caddq a) = sint (aw + (sshiftr aw 31 AND 0x7FE001))"
    unfolding caddq_def Q32_def aw_def by (simp add: probe_sint_seq word_seq_convs seq_to_word)
  have lo: "- 2147483648 \<le> sint aw" and hi: "sint aw < 2147483648"
    using sint_greater_eq[of aw] sint_lt[of aw] by simp_all
  \<comment> \<open>the shift-AND selects q iff aw is negative\<close>
  have sel: "(sshiftr aw 31 AND (0x7FE001 :: 32 word)) = (if sint aw < 0 then 0x7FE001 else 0)"
    by (intro bit_word_eqI)
       (auto simp: bit_simps word_msb_sint[symmetric] msb_word_iff_bit not_le less_Suc0)
  \<comment> \<open>sint of the sum: no int32 overflow either way\<close>
  have val: "sint (aw + (sshiftr aw 31 AND 0x7FE001)) = sint aw + (if sint aw < 0 then 8380417 else 0)"
  proof (cases "sint aw < 0")
    case True
    have b1: "- 2147483648 \<le> sint aw + 8380417" using lo by simp
    have b2: "sint aw + 8380417 < 2147483648" using True by simp
    have "sint (aw + 0x7FE001) = sint (word_of_int (sint aw + 8380417) :: 32 word)"
      by (metis of_int_add of_int_numeral of_int_sint)
    also have "\<dots> = sint aw + 8380417"
      by (rule sint_of_int_eq) (use b1 b2 in simp)+
    finally show ?thesis using sel True by simp
  next
    case False thus ?thesis using sel by simp
  qed
  show ?thesis
    unfolding is_caddq_def MLDSA_NTT_Spec.q_def A br val
    using lo hi by (auto simp: mod_add_self2)
qed

\<comment> \<open>in this context \<open><<\<close> is the cryptol/word \<open>left_shift\<close> (Rotate_Shift), not Word's \<open>shiftl\<close>;
    for a word it unfolds to \<open>shiftl\<close>, which on 1 by 22 is 0x400000\<close>
lemma shl22: "left_shift (1 :: 32 word) 22 = 0x400000"
proof -
  have "left_shift (1 :: 32 word) 22 = shiftl 1 22"
    by (simp add: left_shift_def right_shift_def)
  also have "\<dots> = 0x400000"
    by (rule bit_word_eqI) (auto simp: bit_simps shiftl_def)
  finally show ?thesis .
qed

\<comment> \<open>reduce32 (Barrett-style): residue-preserving, output in the TRUE window [-6283009, 6283008].
    The output bound (OF-2: the C doc says -6283008) is the substantive part: a careful
    floor-division interval argument with a case split at the extreme quotient t = -256.\<close>
lemma reduce32_correct:
  fixes a :: "(32, bool) seq"
  assumes dom: "reduce32_input_ok (sint_seq a)"
  shows "is_reduce32 (sint_seq a) (sint_seq (reduce32 a))"
proof -
  define aw :: "32 word" where "aw = seq_to_word a"
  define a' :: int where "a' = sint aw"
  have A: "sint_seq a = a'" unfolding aw_def a'_def by (rule probe_sint_seq)
  have lo31: "- 2147483648 \<le> a'" and hi31: "a' < 2147483648"
    unfolding a'_def using sint_greater_eq[of aw] sint_lt[of aw] by simp_all
  have dom': "a' \<le> 2143289343" using dom A unfolding reduce32_input_ok_def by simp
  \<comment> \<open>the shifted addend does not overflow int32, so its signed value is exactly a' + 2^22\<close>
  have add_eq: "aw + 0x400000 = word_of_int (a' + 4194304)"
    unfolding a'_def by (metis of_int_add of_int_numeral of_int_sint)
  have sint_add: "sint (aw + 0x400000) = a' + 4194304"
    unfolding add_eq by (rule sint_of_int_eq) (use lo31 dom' in simp)+
  \<comment> \<open>the arithmetic shift is exactly floor-division by 2^23\<close>
  define t :: int where "t = (a' + 4194304) div 8388608"
  have sint_t: "sint (sshiftr (aw + 0x400000) 23) = t"
    unfolding t_def using sint_add by (simp add: sshiftr_div_2n)
  \<comment> \<open>quotient bounds from the input range\<close>
  have aplo: "- 2143289344 \<le> a' + 4194304" using lo31 by simp
  have aphi: "a' + 4194304 \<le> 2147483647" using dom' by simp
  have thi: "t \<le> 255"
  proof -
    have "(a' + 4194304) div 8388608 \<le> 2147483647 div 8388608"
      using aphi by (auto intro: zdiv_mono1)
    thus ?thesis unfolding t_def by simp
  qed
  have tlo: "- 256 \<le> t"
  proof -
    have "(- 2143289344 :: int) div 8388608 \<le> (a' + 4194304) div 8388608"
      using aplo by (auto intro: zdiv_mono1)
    thus ?thesis unfolding t_def by simp
  qed
  \<comment> \<open>the integer output bound (the hard interval fact)\<close>
  define s :: int where "s = (a' + 4194304) mod 8388608"
  have eqn: "a' + 4194304 = 8388608 * t + s"
    unfolding t_def s_def by simp
  have s0: "0 \<le> s" and s1: "s < 8388608" unfolding s_def by simp_all
  have rfix: "a' - t * 8380417 = 8191 * t + s - 4194304" using eqn by (simp add: algebra_simps)
  have BND: "- 6283009 \<le> a' - t * 8380417 \<and> a' - t * 8380417 \<le> 6283008"
  proof -
    have up: "8191 * t + s - 4194304 \<le> 6283008" using thi s1 by linarith
    have low: "- 6283009 \<le> 8191 * t + s - 4194304"
    proof (cases "t \<le> - 256")
      case True
      hence te: "t = - 256" using tlo by linarith
      show ?thesis using te eqn s0 lo31 by linarith
    next
      case False
      hence "- 255 \<le> t" by simp
      thus ?thesis using s0 by linarith
    qed
    show ?thesis using up low rfix by simp
  qed
  \<comment> \<open>collapse the word arithmetic to the integer value, using BND for the no-overflow fit\<close>
  have tw_eq: "sshiftr (aw + 0x400000) 23 = word_of_int t"
    using sint_t by (metis of_int_sint)
  have hom: "aw - sshiftr (aw + 0x400000) 23 * 0x7FE001 = word_of_int (a' - t * 8380417)"
    unfolding tw_eq a'_def
    by (metis of_int_diff of_int_mult of_int_numeral of_int_sint)
  have R: "sint_seq (reduce32 a) = a' - t * 8380417"
  proof -
    have "sint_seq (reduce32 a) = sint (aw - sshiftr (aw + 0x400000) 23 * 0x7FE001)"
      unfolding reduce32_def Q32_def aw_def
      by (simp add: probe_sint_seq word_seq_convs seq_to_word shl22)
    also have "\<dots> = sint (word_of_int (a' - t * 8380417) :: 32 word)"
      using hom by simp
    also have "\<dots> = a' - t * 8380417"
      by (rule sint_of_int_eq) (use BND in simp)+
    finally show ?thesis .
  qed
  \<comment> \<open>residue preservation: a' - t*Q \<equiv> a' (mod Q)\<close>
  have cong: "(a' - t * 8380417) mod 8380417 = a' mod 8380417"
    using mod_mult_self1[of a' "- t" 8380417] by (simp add: algebra_simps)
  show ?thesis
    unfolding is_reduce32_def MLDSA_NTT_Spec.q_def A R
    using BND cong by simp
qed

\<comment> \<open>freeze = caddq \<circ> reduce32, the canonical representative in [0, q). Compositional: reduce32's
    output window [-6283009, 6283008] sits inside [-q, q), so caddq's precondition is met.\<close>
lemma freeze_correct:
  fixes a :: "(32, bool) seq"
  assumes dom: "reduce32_input_ok (sint_seq a)"
  shows "is_freeze (sint_seq a) (sint_seq (freeze a))"
proof -
  have r32: "is_reduce32 (sint_seq a) (sint_seq (reduce32 a))"
    using dom by (rule reduce32_correct)
  have cad: "is_caddq (sint_seq (reduce32 a)) (sint_seq (caddq (reduce32 a)))"
    by (rule caddq_correct)
  have c1: "sint_seq (reduce32 a) mod 8380417 = sint_seq a mod 8380417"
   and b1: "- 6283009 \<le> sint_seq (reduce32 a)" and b2: "sint_seq (reduce32 a) \<le> 6283008"
    using r32 unfolding is_reduce32_def MLDSA_NTT_Spec.q_def by simp_all
  have c2: "sint_seq (caddq (reduce32 a)) mod 8380417 = sint_seq (reduce32 a) mod 8380417"
    using cad unfolding is_caddq_def MLDSA_NTT_Spec.q_def by simp
  have ante: "- 8380417 \<le> sint_seq (reduce32 a) \<and> sint_seq (reduce32 a) < 8380417"
    using b1 b2 by linarith
  have pos: "0 \<le> sint_seq (caddq (reduce32 a)) \<and> sint_seq (caddq (reduce32 a)) < 8380417"
    using cad ante unfolding is_caddq_def MLDSA_NTT_Spec.q_def by simp
  have fdef: "sint_seq (freeze a) = sint_seq (caddq (reduce32 a))"
    by (simp add: freeze_def)
  show ?thesis
    unfolding is_freeze_def MLDSA_NTT_Spec.q_def fdef
    using c1 c2 pos by simp
qed

end

end
