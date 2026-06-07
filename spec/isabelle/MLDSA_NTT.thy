theory "MLDSA_NTT"
imports "Cryptol.Cryptol"
begin

context includes cryptol_translation_syntax begin
type_synonym N = "256"

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

cryptol_definition ntt :: "([N]Integer) \<Rightarrow> ([N]Integer)" where
"ntt coeffs \<equiv> error`{[N]Integer,48} (list_to_seq [0x6f :: [8],0x75 :: [8],0x74 :: [8],0x20 :: [8],0x6f :: [8],0x66 :: [8],0x20 :: [8],0x73 :: [8],0x63 :: [8],0x6f :: [8],0x70 :: [8],0x65 :: [8],0x20 :: [8],0x66 :: [8],0x6f :: [8],0x72 :: [8],0x20 :: [8],0x76 :: [8],0x31 :: [8],0x3a :: [8],0x20 :: [8],0x66 :: [8],0x6f :: [8],0x72 :: [8],0x77 :: [8],0x61 :: [8],0x72 :: [8],0x64 :: [8],0x20 :: [8],0x4e :: [8],0x54 :: [8],0x54 :: [8],0x20 :: [8],0x6e :: [8],0x6f :: [8],0x74 :: [8],0x20 :: [8],0x6d :: [8],0x6f :: [8],0x64 :: [8],0x65 :: [8],0x6c :: [8],0x65 :: [8],0x64 :: [8],0x20 :: [8],0x79 :: [8],0x65 :: [8],0x74 :: [8]] :: [48][8])"

cryptol_definition q :: "Integer" where
"q  \<equiv> 8380417 :: Integer"

end
end
