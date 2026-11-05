#!/usr/bin/env bash
# Regenerate src/known/google/protobuf from the .proto files protobuf ships,
# through this repository's own plugin. Requires protoc (>= 27 for editions)
# and its include directory.
#
#   PROTOC=/path/to/protoc PROTOC_INCLUDE=/path/to/include scripts/generate-known.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
protoc="${PROTOC:-protoc}"
include="${PROTOC_INCLUDE:-$(dirname "$(dirname "$(command -v "$protoc")")")/include}"
out="$root/src/known/google/protobuf"

if [ ! -d "$include/google/protobuf" ]; then
  echo "no protobuf includes at $include; set PROTOC_INCLUDE" >&2
  exit 1
fi

(cd "$root" && moon build --target native src/cmd/protoc-gen-mbt >/dev/null)
plugin="$root/_build/native/debug/build/cmd/protoc-gen-mbt/protoc-gen-mbt"
if [ -f "$plugin.exe" ]; then
  plugin="$plugin.exe"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" 2>/dev/null || true' EXIT

# protoc is a native binary on Windows, so hand it a Windows path.
if command -v cygpath >/dev/null 2>&1; then
  proto_tmp="$(cygpath -m "$tmp")"
else
  proto_tmp="$tmp"
fi
"$protoc" -I "$include" \
  --plugin="protoc-gen-mbt=$plugin" \
  --mbt_out="$proto_tmp" \
  google/protobuf/any.proto \
  google/protobuf/api.proto \
  google/protobuf/duration.proto \
  google/protobuf/empty.proto \
  google/protobuf/field_mask.proto \
  google/protobuf/source_context.proto \
  google/protobuf/struct.proto \
  google/protobuf/timestamp.proto \
  google/protobuf/type.proto \
  google/protobuf/wrappers.proto \
  google/protobuf/descriptor.proto

rm -f "$out"/*.mbt
cp "$tmp"/google/protobuf/*.mbt "$out"/
(cd "$root" && moon fmt >/dev/null)
echo "wrote $(ls "$out"/*.mbt | wc -l) files to $out"
