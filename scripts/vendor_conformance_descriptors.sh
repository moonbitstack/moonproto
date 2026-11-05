#!/usr/bin/env bash
# Regenerate tests/conformance/descriptor_set.bin from a pinned protobuf
# checkout, then re-derive src/conformance/test_types.mbt from it. Both are
# checked in, so neither protoc nor a protobuf checkout is needed at test time.
#
#   PROTOBUF_SOURCE=~/pb362 PROTOC=/path/to/protoc \
#     scripts/vendor_conformance_descriptors.sh
#
# protobuf 36.2 is the pinned version. PROTOBUF_SOURCE points at the root of
# that checkout. The six schemas live in three different directories upstream.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
protoc="${PROTOC:-protoc}"
source_dir="${PROTOBUF_SOURCE:?set PROTOBUF_SOURCE to a protobuf 36.2 checkout}"
out="$root/tests/conformance/descriptor_set.bin"

src="$source_dir/src"
golden="$source_dir/editions/golden"
conf="$source_dir/conformance/test_protos"
schema=(
  google/protobuf/test_messages_proto2.proto
  google/protobuf/test_messages_proto3.proto
  test_messages_proto2_editions.proto
  test_messages_proto3_editions.proto
  test_messages_edition2023.proto
  test_messages_edition_unstable.proto
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" 2>/dev/null || true' EXIT
if command -v cygpath >/dev/null 2>&1; then
  tmp="$(cygpath -u "$tmp")"
  proto_tmp="$(cygpath -m "$tmp")"
else
  proto_tmp="$tmp"
fi

# The order here is the order in the checked-in descriptor set. `--include_imports`
# is deliberately absent: the generator only needs the six schemas themselves.
"$protoc" -I "$src" -I "$golden" -I "$conf" \
  --descriptor_set_out="$proto_tmp/descriptor_set.bin" \
  "${schema[@]}"

cp "$tmp/descriptor_set.bin" "$out"
python3 "$root/scripts/gen_conformance_types.py"
(cd "$root" && moon fmt >/dev/null)
echo "vendored $out and regenerated src/conformance/test_types.mbt"
