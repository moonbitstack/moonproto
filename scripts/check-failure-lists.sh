#!/usr/bin/env bash
# The official runner reads two checked-in failure lists. Both must stay empty:
# every required case in the binary, JSON and text format suites passes, so any
# entry here would be a waiver without a reason.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

status=0
for list in "$root/tests/conformance/failure_list.txt" \
            "$root/tests/conformance/text_format_failure_list.txt"; do
  if grep -Eq '^[[:space:]]*[^#[:space:]]' "$list"; then
    echo "$(basename "$list") must be empty; every case in its suite passes:" >&2
    grep -En '^[[:space:]]*[^#[:space:]]' "$list" >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  exit 1
fi
echo "failure lists: binary/JSON and text format are both empty"
