#!/usr/bin/env bash
# Verify src/conformance/test_types.mbt is exactly what the checked-in descriptor
# set produces. The generator emits compact records and `moon fmt` expands them,
# so formatting is part of the comparison.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target="$root/src/conformance/test_types.mbt"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" 2>/dev/null || true' EXIT
cp "$target" "$tmp/before.mbt"
python3 "$root/scripts/gen_conformance_types.py" >/dev/null
(cd "$root" && moon fmt >/dev/null)
if ! diff -q "$tmp/before.mbt" "$target" >/dev/null; then
  cp "$tmp/before.mbt" "$target"
  echo "src/conformance/test_types.mbt is stale; run scripts/gen_conformance_types.py" >&2
  exit 1
fi
echo "conformance descriptors are up to date"
