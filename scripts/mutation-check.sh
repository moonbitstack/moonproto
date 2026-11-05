#!/usr/bin/env bash
# Break three invariants one at a time and confirm the suite sees each break.
# The driver restores every source file before it exits, including on failure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$root/scripts/mutation-check.py"
