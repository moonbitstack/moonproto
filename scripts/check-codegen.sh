#!/usr/bin/env bash
# Compile what the plugin generates for all four schema shapes: proto2, proto3,
# editions 2023 and editions 2024. The generated files land in one throwaway
# package inside the module so `moon check --deny-warn` sees them with the same
# toolchain and the same warnings as the rest of the source tree.
#
#   PROTOC=/path/to/protoc PROTOC_INCLUDE=/path/to/include scripts/check-codegen.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
protoc="${PROTOC:-protoc}"
include="${PROTOC_INCLUDE:-}"
pkg="$root/src/zz_codegen_check"
shapes=(proto2 proto3 edition2023 edition2024)

(cd "$root" && moon build --target native src/cmd/protoc-gen-mbt >/dev/null)
plugin="$root/_build/native/debug/build/cmd/protoc-gen-mbt/protoc-gen-mbt"
if [ -f "$plugin.exe" ]; then
  plugin="$plugin.exe"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" "$pkg" 2>/dev/null || true' EXIT
if command -v cygpath >/dev/null 2>&1; then
  tmp="$(cygpath -u "$tmp")"
  proto_tmp="$(cygpath -m "$tmp")"
else
  proto_tmp="$tmp"
fi

args=(-I "$root/tests/shapes")
if [ -n "$include" ]; then
  args+=(-I "$include")
fi
inputs=()
for shape in "${shapes[@]}"; do
  inputs+=("$root/tests/shapes/$shape.proto")
done
"$protoc" "${args[@]}" \
  --plugin="protoc-gen-mbt=$plugin" \
  --mbt_out="$proto_tmp" \
  "${inputs[@]}"

rm -rf "$pkg"
mkdir -p "$pkg"
for shape in "${shapes[@]}"; do
  if [ ! -f "$tmp/$shape.mbt" ]; then
    echo "plugin did not emit $shape.mbt" >&2
    exit 1
  fi
  cp "$tmp/$shape.mbt" "$pkg/"
done
cat > "$pkg/moon.pkg" <<'PKG'
import {
  "moonbitstack/moonproto/desc",
  "moonbitstack/moonproto/json",
  "moonbitstack/moonproto/proto",
  "moonbitstack/moonproto/reflect",
}
PKG

(cd "$root" && moon check --target all --deny-warn)
echo "generated packages compile cleanly: ${shapes[*]}"
