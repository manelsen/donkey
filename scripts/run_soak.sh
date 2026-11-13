#!/usr/bin/env bash
# run_soak.sh — repeat the stress suite for a bounded wall-clock window.
#
# Usage:
#   SOAK_DURATION_SEC=600 bash scripts/run_soak.sh
#   SOAK_MAX_RUNS=20 bash scripts/run_soak.sh
#
# Exit code 0 only when every iteration passes. Each iteration invokes
# scripts/run_stress_tests.sh, which itself has a timeout.

set -uo pipefail
cd "$(dirname "$0")/.."

DURATION="${SOAK_DURATION_SEC:-600}"
MAX_RUNS="${SOAK_MAX_RUNS:-0}"
END=$((SECONDS + DURATION))
runs=0
failures=0

while [ "$SECONDS" -lt "$END" ]; do
  if [ "$MAX_RUNS" -gt 0 ] && [ "$runs" -ge "$MAX_RUNS" ]; then
    break
  fi
  runs=$((runs + 1))
  printf '\n=== soak run %d @ %s ===\n' "$runs" "$(date -Is)"
  if ! bash scripts/run_stress_tests.sh; then
    failures=$((failures + 1))
    printf 'SOAK: run %d FAILED\n' "$runs" >&2
  fi
  sleep 2
done

printf '\nSOAK RESULT: runs=%d failures=%d duration=%ds\n' \
  "$runs" "$failures" "$DURATION"
[ "$failures" -eq 0 ]
