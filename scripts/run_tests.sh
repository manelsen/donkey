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

# Persistent per-path nimcache root. Falls back to the run's temp dir when
# HOME is unusable (unset, or a literal "~", which would create "./~").
TEST_NIMCACHE_ROOT=""
cache_base="${XDG_CACHE_HOME:-${HOME:-}/.cache}"
case "$cache_base" in
  /*) TEST_NIMCACHE_ROOT="$cache_base/nim/donkey-tests" ;;
esac
export TEST_NIMCACHE_ROOT

HAVE_GNU_REALPATH=0
if command -v realpath >/dev/null 2>&1 &&    [ -n "$(realpath -m --relative-to=. . 2>/dev/null)" ]; then
  HAVE_GNU_REALPATH=1
fi
export HAVE_GNU_REALPATH

run_one() {
  local f="$1"
  if [ "$HAVE_GNU_REALPATH" = "1" ]; then
    local normalized_f
    normalized_f="$(realpath -m --relative-to=. "$f" 2>/dev/null || true)"
    if [ -n "$normalized_f" ]; then
      f="$normalized_f"
    fi
  else
    while [[ "$f" == ./* ]]; do
      f="${f#./}"
    done
  fi
  local tmp_dir="$2"
  local id="$3"

  # Stress tests are opt-in; the normal suite stays fast and deterministic.
  case "$f" in
    tests/stress/*)
      if [ "${DONKEY_STRESS:-0}" != "1" ]; then
        return 0
      fi
      ;;
  esac

  # Skip files that require special build flags (opt-in backends)
  case "$f" in
    *t_sqlite_store*) return 0 ;;   # requires -d:withSqlite
    *t_postgres*|*t_pgvector*|*t_age_store*) return 0 ;; # requires -d:withPostgres + live DB
    *t_wasm.nim) return 0 ;;        # requires wasm3 nimble package (not installed by default)
    *t_wasm*|*t_shell_composer*)
      if [ ! -f "$HOME/.donkey/busybox" ] || ! command -v wasmtime >/dev/null 2>&1; then
        return 0
      fi
      ;;
  esac

  local log="$tmp_dir/test_${id}.log"
  printf "RUN   %s\n" "$f"

  # Nim keys its default nimcache on the file basename only
  # (~/.cache/nim/<basename>_d), so two tests with the same name in different
  # directories clobber each other's main-module object when compiled in
  # parallel (e.g. t_openai_compat under app/ and domain/providers/).
  # Derive a unique, persistent cache from the test path so parallel runs can
  # never share a directory while warm-cache reuse between runs is preserved.
  # Key on the *absolute* path: two checkouts/worktrees of the same repo share
  # the relative path (and therefore the cache) otherwise, which is the same
  # collision this exists to prevent.
  local abs_f
  abs_f="$(realpath -m "$f" 2>/dev/null || true)"
  if [ -z "$abs_f" ]; then abs_f="$PWD/$f"; fi
  local cache_key="${abs_f%.nim}"
  cache_key="${cache_key#/}"
  cache_key="${cache_key//\//_}"
  # Two different paths can flatten to the same key (`a/b_c` vs `a_b/c`), so
  # append a checksum of the absolute path: deterministic across runs, and a
  # collision would need the same path.
  local path_hash
  path_hash="$(printf '%s' "$abs_f" | cksum | cut -d' ' -f1)"
  cache_key="${cache_key}_${path_hash}"
  local cache_dir
  if [ -n "$TEST_NIMCACHE_ROOT" ]; then
    cache_dir="$TEST_NIMCACHE_ROOT/${cache_key}_d"
  else
    # No usable HOME (unset or a literal "~"): keep the cache inside the
    # per-run temp dir instead of creating a "./~" directory in the repo.
    cache_dir="$tmp_dir/nimcache_${id}_d"
  fi

  if nim c --hints:off --mm:orc -u:withPostgres \
       --nimcache:"$cache_dir" \
       -r "$f" > "$log" 2>&1; then
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

normalize_target() {
  local target="$1"
  if [ "$HAVE_GNU_REALPATH" = "1" ]; then
    local normalized_target
    normalized_target="$(realpath -m --relative-to=. "$target" 2>/dev/null || true)"
    if [ -n "$normalized_target" ]; then
      target="$normalized_target"
    fi
  else
    while [[ "$target" == ./* ]]; do
      target="${target#./}"
    done
    if [[ -z "$target" ]]; then
      target="."
    fi
  fi
  while [[ "$target" == */ ]] || [[ "$target" == */. ]]; do
    target="${target%/}"
    target="${target%/.}"
  done
  if [[ "$target" == /* ]]; then
    local root
    root="$(pwd)"
    if [[ "$target" == "$root" ]]; then
      target="."
    elif [[ "$target" == "$root/"* ]]; then
      target="${target#"$root"/}"
    fi
  fi
  printf '%s' "$target"
}

# Normalize targets once so filters, find and stress detection agree.
TARGETS=("$@")
if [ "${#TARGETS[@]}" -eq 0 ]; then
  TARGETS=("tests")
fi
normalized_targets=()
for target in "${TARGETS[@]}"; do
  normalized="$(normalize_target "$target")"
  normalized_targets+=("$normalized")
  case "$normalized" in
    tests/stress|tests/stress/*) export DONKEY_STRESS=1 ;;
  esac
done
TARGETS=("${normalized_targets[@]}")

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
