#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

check_absent() {
  local description="$1"
  local pattern="$2"
  shift 2
  if rg -n "$pattern" "$@" > /tmp/donkey_boundary_check.txt; then
    echo "Boundary check failed: $description" >&2
    cat /tmp/donkey_boundary_check.txt >&2
    rm -f /tmp/donkey_boundary_check.txt
    exit 1
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

