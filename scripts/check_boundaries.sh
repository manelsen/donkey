#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rg >/dev/null 2>&1; then
  echo "Error: ripgrep (rg) is required for boundary checks but was not found in PATH." >&2
  exit 127
fi

check_absent() {
  local description="$1"
  local pattern="$2"
  shift 2
  local status=0
  rg -n "$pattern" "$@" > /tmp/donkey_boundary_check.txt || status=$?
  if [ "$status" -eq 0 ]; then
    echo "Boundary check failed: $description" >&2
    cat /tmp/donkey_boundary_check.txt >&2
    rm -f /tmp/donkey_boundary_check.txt
    exit 1
  elif [ "$status" -ne 1 ]; then
    echo "Boundary check error running ripgrep (exit code $status): $description" >&2
    rm -f /tmp/donkey_boundary_check.txt
    exit "$status"
  fi
  rm -f /tmp/donkey_boundary_check.txt
}

check_absent \
  "app/core/ports must not import adapters directly" \
  '^\s*(import|from)\s+.*adapters/' \
  src/donkey/app src/donkey/core src/donkey/ports

check_absent \
  "core must stay free of runtime-only deps" \
  '^\s*(import|from)\s+.*(chronos|asyncsync|osproc|httpclient|parsetoml|adapters/)' \
  src/donkey/core

check_absent \
  "ports must not depend on adapters or app" \
  '^\s*(import|from)\s+.*(adapters/|app/)' \
  src/donkey/ports

echo "Boundary checks passed."

