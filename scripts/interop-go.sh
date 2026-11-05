#!/usr/bin/env bash
# Bidirectional interop with protoc-gen-go over tests/interop/interop.proto.
#
# Both programs read the same text fixture and the same generated schema. Each
# encodes it, each decodes the other's bytes, and each asserts every field
# value before answering. Requires Go and the MoonBit toolchain.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
# On Windows, mktemp may answer with a drive-letter path. Shell redirections
# and cleanup want a POSIX path; the native Go linker wants the original one.
go_out="$tmp/gointerop"
if command -v cygpath >/dev/null 2>&1; then
  tmp="$(cygpath -u "$tmp")"
fi
trap 'rm -rf "$tmp"' EXIT

(cd "$root/tests/gointerop" && go build -o "$go_out" .)
(cd "$root" && moon build --target native src/cmd/interop-mbt >/dev/null)
mbt="$root/_build/native/debug/build/cmd/interop-mbt/interop-mbt"
if [ -f "$mbt.exe" ]; then
  mbt="$mbt.exe"
fi

fixture="$root/tests/interop/fixture.txt"
"$tmp/gointerop" encode <"$fixture" >"$tmp/go.hex"
"$mbt" encode <"$fixture" >"$tmp/mbt.hex"
cmp "$tmp/go.hex" "$tmp/mbt.hex"

"$mbt" decode <"$tmp/go.hex" >"$tmp/mbt-from-go.hex"
cmp "$tmp/go.hex" "$tmp/mbt-from-go.hex"

"$tmp/gointerop" decode <"$tmp/mbt.hex" >"$tmp/go-from-mbt.hex"
cmp "$tmp/mbt.hex" "$tmp/go-from-mbt.hex"

go_hex="$(cat "$tmp/go.hex")"
bytes=$(( ${#go_hex} / 2 ))
echo "protoc-gen-go interop passed: both encodings agree, both decoders recover every field ($bytes bytes)"
