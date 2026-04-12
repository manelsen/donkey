#!/usr/bin/env bash
# run_tests.sh — compile and execute every test file under tests/.
#
# Unlike `testament all`, this script actually runs each test binary
# so that unittest assertions are evaluated (not just compiled).
#
# Exit code: 0 if all tests pass, non-zero otherwise.

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
FAILED_FILES=()

while IFS= read -r f; do
  # Skip files that require special build flags (opt-in backends)
  case "$f" in
    *t_sqlite_store*) continue ;;   # requires -d:withSqlite
    *t_postgres*|*t_pgvector*|*t_age_store*) continue ;; # requires -d:withPostgres + live DB
    *t_wasm.nim) continue ;;        # requires wasm3 nimble package (not installed by default)
  esac

  if nim c --mm:orc -u:withPostgres -r "$f" > /tmp/donkey_test_out.txt 2>&1; then
    PASS=$((PASS + 1))
    # Print brief summary from unittest output
    summary=$(grep -E "\[Summary\]|\[OK\]" /tmp/donkey_test_out.txt | tail -1 || true)
    printf "PASS  %-65s %s\n" "$f" "$summary"
  else
    FAIL=$((FAIL + 1))
    FAILED_FILES+=("$f")
    echo "FAIL  $f"
    grep -E "Error:|FAILED|\[FAILED\]" /tmp/donkey_test_out.txt | head -5 >&2 || true
  fi
done < <(find tests -name "*.nim" | sort)

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "${#FAILED_FILES[@]}" -gt 0 ]; then
  echo ""
  echo "Failed files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  $f"
  done
  exit 1
fi
