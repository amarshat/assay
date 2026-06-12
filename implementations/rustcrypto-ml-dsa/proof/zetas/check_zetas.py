#!/usr/bin/env python3
"""Focused-audit target #2 (NOTES.md smell #2): the const-computed zetas table.

ml-dsa 0.1.1 builds ZETA_POW_BITREV: [Elem; 256] in a const fn (ntt.rs) with manual
`% QL` reductions (operator overloading isn't const), commented "match ... Appendix B
of FIPS 204". A const-eval mistake there would be a real, KAT-surviving defect class.

This script checks the table IN THE COMPILED ARTIFACT — the linked MIR that SAW also
consumes — not the source: rustc's const evaluator already baked the table into every
ntt_layer / ntt_inverse_layer monomorphization, so we extract every embedded copy and
compare entry-wise against the definition FIPS 204 Appendix B tabulates:

    ZETA_POW_BITREV[i] = zeta^{BitRev_8(i)} mod q   (zeta = 1753, q = 8380417),  i in 1..=255

Entry 0 is a deliberate, documented dummy (0): both ntt_layer (pre-increment from m=0)
and ntt_inverse_layer (pre-decrement from m=256) perform exactly 255 = 1+2+...+128 table
reads, covering indices 1..=255 and never index 0.

Exit 0 iff every embedded copy is identical and every live entry matches; loud otherwise.
"""
import json
import sys

MIR = sys.argv[1] if len(sys.argv) > 1 else "build/mldsa_harness.linked-mir.json"
Q, ZETA = 8380417, 1753


def bitrev8(x: int) -> int:
    return int(format(x, "08b")[::-1], 2)


expected = [0] + [pow(ZETA, bitrev8(i), Q) for i in range(1, 256)]


def find_tables(obj, out):
    """Collect every rendered 256-element array of single-uint-field structs."""
    if isinstance(obj, dict):
        els = obj.get("elements")
        if isinstance(els, list) and len(els) == 256:
            try:
                out.append([int(e["fields"][0]["val"]) for e in els])
            except (KeyError, TypeError, IndexError):
                pass
        for v in obj.values():
            find_tables(v, out)
    elif isinstance(obj, list):
        for v in obj:
            find_tables(v, out)


d = json.load(open(MIR))
tables = []
layer_fns = 0
for f in d["fns"]:
    if "::ntt::ntt_layer" in f["name"] or "::ntt::ntt_inverse_layer" in f["name"]:
        layer_fns += 1
        find_tables(f, tables)

if layer_fns == 0 or not tables:
    print(f"FAIL: no ntt layer fns ({layer_fns}) or no embedded tables ({len(tables)}) "
          f"found in {MIR} — extraction broke or the MIR changed shape")
    sys.exit(1)

ref = tables[0]
if not all(t == ref for t in tables):
    print(f"FAIL: the {len(tables)} embedded table copies are NOT identical")
    sys.exit(1)

diffs = [(i, ref[i], expected[i]) for i in range(256) if ref[i] != expected[i]]
if diffs:
    print(f"FAIL: {len(diffs)} entries differ from zeta^bitrev8(i) mod q:")
    for i, got, exp in diffs[:10]:
        print(f"  idx {i}: artifact={got} expected={exp}")
    sys.exit(1)

print(f"OK: {len(tables)} embedded copies across {layer_fns} ntt layer monomorphizations are "
      f"identical, and all 255 live entries equal zeta^bitrev8(i) mod q (FIPS 204 App B); "
      f"entry 0 is the documented never-read dummy.")
