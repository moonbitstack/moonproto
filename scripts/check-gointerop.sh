#!/usr/bin/env bash
# Verify tests/gointerop/interop.pb.go is exactly what protoc 36.2 and
# protoc-gen-go v1.36.12 emit from the shared schema. This keeps the Go side of
# the bidirectional interop test honest: the checked-in file cannot drift.
#
#   PROTOC=/path/to/protoc scripts/check-gointerop.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
protoc="${PROTOC:-protoc}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" 2>/dev/null || true' EXIT
if command -v cygpath >/dev/null 2>&1; then
  tmp="$(cygpath -u "$tmp")"
  proto_tmp="$(cygpath -m "$tmp")"
else
  proto_tmp="$tmp"
fi
mkdir -p "$tmp/bin" "$tmp/out"

GOBIN="$proto_tmp/bin" go install \
  google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.12
plugin="$tmp/bin/protoc-gen-go"
if [ -f "$plugin.exe" ]; then
  plugin="$plugin.exe"
fi
if command -v cygpath >/dev/null 2>&1; then
  plugin="$(cygpath -m "$plugin")"
fi

"$protoc" -I "$root/tests/interop" \
  --plugin="protoc-gen-go=$plugin" \
  --go_out="$proto_tmp/out" \
  --go_opt=paths=source_relative \
  --go_opt='Minterop.proto=moonbitstack/moonproto/tests/gointerop;main' \
  interop.proto

if ! diff -u "$root/tests/gointerop/interop.pb.go" "$tmp/out/interop.pb.go"; then
  echo "tests/gointerop/interop.pb.go is stale" >&2
  exit 1
fi
echo "protoc-gen-go output matches the checked-in schema"
