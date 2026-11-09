#!/usr/bin/env bash
# run_tests.sh — compile and execute test files under tests/ in parallel.
#
# Unlike `testament all`, this script actually runs each test binary
# so that unittest assertions are evaluated (not just compiled).
#
# Usage:
#   bash scripts/run_tests.sh               # Run all tests in parallel
#   bash scripts/run_tests.sh tests/ports   # Run only tests under tests/ports
#   bash scripts/run_tests.sh tests/ports/t_channel.nim # Run single test
#   JOBS=1 bash scripts/run_tests.sh        # Serial execution (for debugging)
#
# Exit code: 0 if all tests pass, non-zero otherwise.

set -uo pipefail
cd "$(dirname "$0")/.."

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/donkey_tests_XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

run_one() {
  local f="$1"
  local tmp_dir="$2"
  local id="$3"

  # Skip files that require special build flags (opt-in backends)
  case "$f" in
    *t_sqlite_store*) return 0 ;;   # requires -d:withSqlite
    *t_postgres*|*t_pgvector*|*t_age_store*) return 0 ;; # requires -d:withPostgres + live DB
    *t_wasm.nim) return 0 ;;        # requires wasm3 nimble package (not installed by default)
  esac

  local log="$tmp_dir/test_${id}.log"
  if nim c --hints:off --mm:orc -u:withPostgres -r "$f" > "$log" 2>&1; then
    touch "$tmp_dir/pass_${id}"
    local summary
    summary=$(grep -E "\[Summary\]|\[OK\]" "$log" | tail -1 || true)
    printf "PASS  %-65s %s\n" "$f" "$summary"
  else
    echo "$f" > "$tmp_dir/fail_${id}"
    echo "FAIL  $f"
    grep -E "Error:|FAILED|\[FAILED\]" "$log" | head -10 >&2 || true
  fi
}
export -f run_one

# Determine targets
TARGETS=("$@")
if [ "${#TARGETS[@]}" -eq 0 ]; then
  TARGETS=("tests")
fi

idx=0
items=()
while IFS= read -r f; do
  idx=$((idx + 1))
  items+=("$f" "$TMP_DIR" "$idx")
done < <(find "${TARGETS[@]}" -name "*.nim" | sort)

if [ "$idx" -eq 0 ]; then
  echo "No test files found for targets: ${TARGETS[*]}"
  exit 0
fi

printf "%s\0" "${items[@]}" | xargs -0 -P "$JOBS" -n 3 bash -c 'run_one "$@"' _

PASS=$(find "$TMP_DIR" -name "pass_*" | wc -l)
FAIL=$(find "$TMP_DIR" -name "fail_*" | wc -l)

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failed files:"
  for f in "$TMP_DIR"/fail_*; do
    [ -f "$f" ] && cat "$f"
  done
  exit 1
fi
