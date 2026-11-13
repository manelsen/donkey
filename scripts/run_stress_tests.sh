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
JOBS="${JOBS:-1}"
exec bash scripts/run_tests.sh tests/stress
