# Assay — one-command reproduction.
# Each target fails loudly; `make verify` is the whole pipeline.

# Use the pinned toolchain installed by scripts/setup.sh into .tools/ (gitignored).
# We both (a) export it on PATH so saw/isabelle find their bundled helpers (z3, etc.) at
# runtime, and (b) call the tools by EXPLICIT path below — GNU Make 3.81 exec's single-command
# recipes directly and resolves them against Make's own PATH, not the exported one.
TOOLS_BIN   := $(CURDIR)/.tools/bin
export PATH := $(TOOLS_BIN):$(PATH)

SAW         := $(TOOLS_BIN)/saw
ISABELLE    := $(TOOLS_BIN)/isabelle
CLANG       ?= clang

TARGET_C    := target/pqclean
BITCODE     := build/mldsa_ntt.bc
SAW_SCRIPT  := proof/saw/mldsa_ntt.saw
ISA_SESSION := Assay

.PHONY: all verify bitcode saw isabelle lift-check mutation-test writeup clean

all: verify

## Full pipeline: lift in sync (lift-check) → C ≡ Cryptol (SAW) → model ≡ FIPS spec (Isabelle)
verify: lift-check saw isabelle
	@echo "✔ pipeline complete — all checked steps passed"

## Composition gate: committed Isabelle model == cryptol-to-isabelle(Cryptol model). Fast; SAW bundle only.
lift-check:
	./scripts/lift_check.sh

## Non-vacuity guard: assert SAW REJECTS a deliberately-wrong model.
mutation-test:
	CLANG=$(CLANG) ./scripts/mutation_test.sh

## Compile the target C subroutine to LLVM bitcode for SAW
bitcode:
	@mkdir -p build
	CLANG=$(CLANG) ./scripts/build_bitcode.sh $(TARGET_C) $(BITCODE)

## Prove the C implementation matches the Cryptol model
saw: bitcode
	@echo ">> SAW: proving C ≡ Cryptol"
	$(SAW) $(SAW_SCRIPT)

## Run the Isabelle session: model ≡ FIPS-204 spec
isabelle:
	@echo ">> Isabelle: proving model ≡ FIPS-204 spec"
	$(ISABELLE) build -D spec/isabelle -v $(ISA_SESSION)

## Build the technical writeup (placeholder — wire up your renderer of choice)
writeup:
	@echo "See docs/writeup/verifying-third-party-pqc-with-saw-and-isabelle.md"

clean:
	rm -rf build output heaps browser_info *.saw-cache saw-out
