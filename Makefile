# Assay — one-command reproduction.
# Each target fails loudly; `make verify` is the whole pipeline.

TARGET_C    := target/pqclean
BITCODE     := build/mldsa_ntt.bc
SAW_SCRIPT  := proof/saw/mldsa_ntt.saw
ISA_SESSION := Assay

.PHONY: all verify bitcode saw isabelle writeup clean

all: verify

## Full pipeline: C ≡ Cryptol (SAW) then model ≡ FIPS spec (Isabelle)
verify: saw isabelle
	@echo "✔ pipeline complete — all checked steps passed"

## Compile the target C subroutine to LLVM bitcode for SAW
bitcode:
	@mkdir -p build
	./scripts/build_bitcode.sh $(TARGET_C) $(BITCODE)

## Prove the C implementation matches the Cryptol model
saw: bitcode
	@echo ">> SAW: proving C ≡ Cryptol"
	saw $(SAW_SCRIPT)

## Run the Isabelle session: model ≡ FIPS-204 spec
isabelle:
	@echo ">> Isabelle: proving model ≡ FIPS-204 spec"
	isabelle build -D spec/isabelle -v $(ISA_SESSION)

## Build the technical writeup (placeholder — wire up your renderer of choice)
writeup:
	@echo "See docs/writeup/using-apple-corecrypto-toolchain.md"

clean:
	rm -rf build output heaps browser_info *.saw-cache saw-out
