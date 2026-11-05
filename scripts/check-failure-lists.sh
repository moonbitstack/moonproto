#!/usr/bin/env bash
# The official runner reads two checked-in failure lists. Keep them honest:
# the binary/JSON list must stay empty, and every text-format entry must name a
# case and carry the observed runner message as its reason.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$root/tests/conformance/failure_list.txt"
text="$root/tests/conformance/text_format_failure_list.txt"

if grep -Eq '^[[:space:]]*[^#[:space:]]' "$binary"; then
  echo "binary/JSON failure_list.txt must be empty; every case in those suites passes" >&2
  exit 1
fi

total=0
while IFS= read -r line || [ -n "$line" ]; do
  stripped="${line#"${line%%[![:space:]]*}"}"
  case "$stripped" in
    "" | \#*) continue ;;
  esac
  total=$((total + 1))
  case "$line" in
    *"#"*) ;;
    *) echo "text-format entry has no reason: $stripped" >&2; exit 1 ;;
  esac
  name="${line%%#*}"
  name="${name//[[:space:]]/}"
  if [ -z "$name" ]; then
    echo "text-format entry has no test name: $line" >&2
    exit 1
  fi
done < "$text"

if [ "$total" -eq 0 ]; then
  echo "text_format_failure_list.txt declares no subset" >&2
  exit 1
fi

dups="$(grep -E '^[[:space:]]*[^#[:space:]]' "$text" | sed 's/#.*//' | tr -d '[:space:]' | sort | uniq -d)"
if [ -n "$dups" ]; then
  echo "duplicate text-format entries: $dups" >&2
  exit 1
fi

echo "failure lists: binary/JSON empty; text format declares $total cases with reasons"
