#!/usr/bin/env bash
# Fetch protoc 36.2 and print two `NAME=value` lines for `eval`:
#
#   eval "$(scripts/setup-protoc.sh)"
#
# Editions and the conformance schemas need exactly this version, so CI and
# local runs share one pinned binary instead of whatever protoc is on PATH.
# PROTOC362_DIR overrides the cache location.
set -euo pipefail
version="36.2"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="${PROTOC362_DIR:-$root/.cache/protoc-$version}"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux)
    case "$arch" in
      x86_64 | amd64) asset="linux-x86_64" ;;
      aarch64 | arm64) asset="linux-aarch_64" ;;
      *) echo "unsupported Linux architecture $arch" >&2; exit 1 ;;
    esac
    ;;
  Darwin)
    case "$arch" in
      arm64) asset="osx-aarch_64" ;;
      x86_64) asset="osx-x86_64" ;;
      *) echo "unsupported macOS architecture $arch" >&2; exit 1 ;;
    esac
    ;;
  MINGW* | MSYS* | CYGWIN* | Windows_NT) asset="win64" ;;
  *) echo "unsupported OS $os" >&2; exit 1 ;;
esac

protoc="$dest/bin/protoc"
if [ -f "$protoc.exe" ]; then
  protoc="$protoc.exe"
fi
if [ ! -x "$protoc" ]; then
  mkdir -p "$dest"
  zip="$dest/protoc.zip"
  url="https://github.com/protocolbuffers/protobuf/releases/download/v${version}/protoc-${version}-${asset}.zip"
  # the release host answers 5xx now and then; a retry is cheaper than a red build
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "$url" -o "$zip"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$zip" -d "$dest"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$dest"
  else
    python -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$dest"
  fi
  rm -f "$zip"
  chmod +x "$dest/bin/protoc" 2>/dev/null || true
  if [ -f "$dest/bin/protoc.exe" ]; then
    protoc="$dest/bin/protoc.exe"
  fi
fi

printf 'PROTOC=%s\nPROTOC_INCLUDE=%s\n' "$protoc" "$dest/include"
"$protoc" --version >&2
