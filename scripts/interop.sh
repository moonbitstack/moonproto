#!/usr/bin/env bash
# Re-derive the reference bytes with protoc and compare them to the fixture the
# test suite embeds. Needs protoc on PATH (or PROTOC=...).
#
# The MoonBit side of this check lives in src/proto/interop_wbtest.mbt.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
protoc="${PROTOC:-protoc}"
dir="$root/tests/interop"

actual="$("$protoc" --encode=interop.All -I "$dir" "$dir/interop.proto" < "$dir/fixture.txt" | od -An -v -tx1 | tr -d ' \n')"
expected="$(tr -d '\n' < "$dir/expected.hex")"

if [ "$actual" != "$expected" ]; then
  echo "protoc's encoding no longer matches tests/interop/expected.hex" >&2
  echo "  expected: $expected" >&2
  echo "  actual:   $actual" >&2
  exit 1
fi
echo "protoc and tests/interop/expected.hex agree ($((${#expected} / 2)) bytes)"
