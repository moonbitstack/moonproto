#!/usr/bin/env bash
# Run the protobuf conformance suite against cmd/conformance-mbt.
#
# The official runner is built from the protobuf C++ sources and is not vendored
# here. Put `conformance_test_runner` on PATH (or set CONFORMANCE_RUNNER) to run
# the official suite; otherwise this falls back to the framing self-check, which
# drives the same testee over the same 4-byte framing.
#
# The runner takes the testee as a positional argument. The two checked-in
# failure lists are the known deviations; every entry carries a reason.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$root" && moon build --target native src/cmd/conformance-mbt >/dev/null)
exe="$root/_build/native/debug/build/cmd/conformance-mbt/conformance-mbt"
if [ -f "$exe.exe" ]; then
  exe="$exe.exe"
fi

runner="${CONFORMANCE_RUNNER:-$(command -v conformance_test_runner || true)}"
if [ -n "$runner" ] && [ -x "$runner" ]; then
  echo "running $runner"
  exec "$runner" \
    --failure_list "$root/tests/conformance/failure_list.txt" \
    --text_format_failure_list "$root/tests/conformance/text_format_failure_list.txt" \
    "$exe"
fi

echo "no conformance_test_runner found; running the framing self-check"
python3 "$root/scripts/conformance_selftest.py" "$exe"
