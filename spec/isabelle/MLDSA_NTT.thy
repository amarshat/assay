theory "MLDSA_NTT"
imports "Cryptol.Cryptol"
begin

context includes cryptol_translation_syntax begin
cryptol_definition Q64 :: "[64]" where
"Q64  \<equiv> 0x7fe001 :: [64]"

cryptol_definition QINV :: "[64]" where
"QINV  \<equiv> 0x3802001 :: [64]"

cryptol_definition mont_in_range :: "([64]) \<Rightarrow> Bit" where
"mont_in_range a \<equiv> 
  let
    hi = ((((0x2 :: [64]) ^^`{[64],Integer} (31 :: Integer)) *`{[64]} Q64) : ([64]));
    lo = ((negate`{[64]} hi) : ([64]))
  in ((a >=$`{[64]} lo) &&`{Bit} (a <=$`{[64]} hi))"

cryptol_definition sext64 :: "([32]) \<Rightarrow> ([64])" where
"sext64 x \<equiv> (if x @`{32,Bit,Integer} (0 :: Integer) then (complement`{[32]} (zero`{[32]})) else coerce (zero`{[32]})) #`{32,32,Bit} x"

cryptol_definition montgomery_reduce :: "([64]) \<Rightarrow> ([32])" where
"montgomery_reduce a \<equiv> 
  let
    t = ((drop`{32,32,Bit} (a *`{[64]} QINV)) : ([32]))
  in (drop`{32,32,Bit} ((a -`{[64]} ((sext64`{} t) *`{[64]} Q64)) >>$`{64,Integer} (32 :: Integer)))"

cryptol_definition q :: "Integer" where
"q  \<equiv> 8380417 :: Integer"

end
end
