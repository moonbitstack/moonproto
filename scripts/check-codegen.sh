#!/usr/bin/env bash
# Compile what the plugin generates: run protoc over a fixture with the oneof,
# map and nested message the tests use, put the result in a throwaway package,
# and check it with warnings denied. Needs protoc (or PROTOC=...).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
protoc="${PROTOC:-protoc}"
include="${PROTOC_INCLUDE:-}"
pkg="$root/src/zz_codegen_check"

(cd "$root" && moon build --target native >/dev/null)
plugin="$root/_build/native/debug/build/cmd/protoc-gen-mbt/protoc-gen-mbt"
if [ -f "$plugin.exe" ]; then
  plugin="$plugin.exe"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" "$pkg" 2>/dev/null || true' EXIT
if command -v cygpath >/dev/null 2>&1; then
  proto_tmp="$(cygpath -m "$tmp")"
else
  proto_tmp="$tmp"
fi

args=(-I "$root/tests/interop")
if [ -n "$include" ]; then
  args+=(-I "$include")
fi
"$protoc" "${args[@]}" \
  --plugin="protoc-gen-mbt=$plugin" \
  --mbt_out="$proto_tmp" \
  "$root/tests/interop/interop.proto"

rm -rf "$pkg"
mkdir -p "$pkg"
cp "$tmp"/*.mbt "$pkg"/
cat > "$pkg/moon.pkg" <<'PKG'
import {
  "moonbitstack/moonproto/desc",
  "moonbitstack/moonproto/dynamic",
  "moonbitstack/moonproto/json",
  "moonbitstack/moonproto/reflect",
}
PKG

(cd "$root" && moon check --target wasm-gc --deny-warn)
echo "generated package compiles cleanly"
