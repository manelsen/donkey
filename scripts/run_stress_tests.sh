#!/usr/bin/env bash
# run_stress_tests.sh — opt-in concurrency/fault suite.
#
# Usage:
#   bash scripts/run_stress_tests.sh          # serial (default)
#   JOBS=4 bash scripts/run_stress_tests.sh   # parallel
#
# These tests use threads, real locks and local TLS certificates; they are
# intentionally excluded from the default suite. The CI runs them on every PR.

set -uo pipefail
cd "$(dirname "$0")/.."

export DONKEY_STRESS=1
export JOBS="${JOBS:-1}"
STRESS_TIMEOUT_SEC="${STRESS_TIMEOUT_SEC:-300}"
exec timeout --signal=TERM --kill-after=10 "$STRESS_TIMEOUT_SEC" \
  bash scripts/run_tests.sh tests/stress
