#!/usr/bin/env python3
"""Prove that five behaviours are actually pinned by the test suite.

Each mutation makes one deliberate, compiling change to a runtime invariant,
runs the full wasm-gc test suite, records which tests turn red, and restores
the original bytes. A mutation that leaves every test green means the suite no
longer protects that invariant, and is itself a failure.

The invariants are the ten-octet varint limit, unknown-field preservation,
64-bit integers as JSON strings, a zero without presence staying off the wire,
and negative zero keeping its sign.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass
class Mutation:
    name: str
    path: str
    edits: list[tuple[str, str]]
    expect: list[str] = field(default_factory=list)


MUTATIONS = [
    Mutation(
        name="varint ten-octet limit",
        path="src/wire/wire.mbt",
        edits=[
            ("if shift == 63 && byte > 1UL {", "if shift == 70 && byte > 1UL {"),
            ("if shift > 63 {", "if shift > 70 {"),
        ],
        expect=[
            "protowire: the largest varint takes ten octets, an eleventh overflows",
        ],
    ),
    Mutation(
        name="unknown-field preservation",
        path="src/proto/proto.mbt",
        edits=[
            ("if !opts.discard_unknown {", "if opts.discard_unknown {"),
        ],
        expect=[
            "proto: Marshal and Unmarshal keep a scalar alongside an unknown field",
            "unknown fields survive a round-trip",
        ],
    ),
    Mutation(
        name="int64 as a JSON string",
        path="src/json/json.mbt",
        edits=[
            (
                "@reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>\n"
                "      @cjson.Json::string(value.int().to_string())",
                "@reflect.Int64 | @reflect.Sint64 | @reflect.Sfixed64 =>\n"
                "      number_json(value.int())",
            ),
            (
                "@reflect.Uint64 | @reflect.Fixed64 =>\n"
                "      @cjson.Json::string(value.uint().to_string())",
                "@reflect.Uint64 | @reflect.Fixed64 =>\n"
                "      number_json(value.uint().reinterpret_as_int64())",
            ),
        ],
        expect=[
            "protojson: 64-bit integers are strings on the wire",
        ],
    ),
    Mutation(
        name="a zero without presence stays off the wire",
        path="src/reflect/message.mbt",
        edits=[
            (
                "  } else {\n    !message.get(field).is_zero()\n  }",
                "  } else {\n    true\n  }",
            ),
        ],
        expect=[
            "binary: a zero without presence writes no bytes",
            "binary: a zero read from the wire does not come back",
            "binary and JSON leave the same zeros out",
            "a zero-valued field without presence is left out",
        ],
    ),
    Mutation(
        name="negative zero keeps its sign",
        path="src/reflect/value.mbt",
        edits=[
            (
                "  value == 0.0 && value.reinterpret_as_uint64() == 0UL",
                "  value == 0.0",
            ),
        ],
        expect=[
            "binary: negative zero keeps its sign on the wire",
            "a negative zero is written by both encodings",
        ],
    ),
]

FAILED_NAME = re.compile(r'\btest \S+:?\d* \("([^"]+)"\) failed')


def apply(mutation: Mutation, target: Path, original: str) -> None:
    text = original
    for old, new in mutation.edits:
        hits = text.count(old)
        if hits != 1:
            raise RuntimeError(
                f"{mutation.name}: expected one occurrence of {old!r}, found {hits}"
            )
        text = text.replace(old, new, 1)
    target.write_text(text, encoding="utf-8", newline="\n")


def run_suite() -> tuple[int, list[str]]:
    proc = subprocess.run(
        ["moon", "test", "--target", "wasm-gc"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    names = sorted(set(FAILED_NAME.findall(proc.stdout)))
    return proc.returncode, names


def main() -> int:
    ok = True
    for mutation in MUTATIONS:
        target = ROOT / mutation.path
        original = target.read_text(encoding="utf-8")
        try:
            apply(mutation, target, original)
            code, red = run_suite()
        finally:
            target.write_text(original, encoding="utf-8", newline="\n")
        restored = target.read_text(encoding="utf-8") == original
        missing = [name for name in mutation.expect if name not in red]
        passed = code != 0 and not missing and restored
        ok = ok and passed
        print(f"\n=== {mutation.name}")
        print(f"  suite exit code : {code} (non-zero expected)")
        print(f"  source restored : {restored}")
        print(f"  tests turned red: {len(red)}")
        for name in red:
            print(f"    - {name}")
        for name in missing:
            print(f"    ! expected but stayed green: {name}")
        print(f"  verdict: {'PASS' if passed else 'FAIL'}")
    print("\nmutation check: " + ("all five invariants are pinned" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
