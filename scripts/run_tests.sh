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
#   SHARD_INDEX=2 SHARD_TOTAL=4 bash scripts/run_tests.sh
#                                           # Run only shard 2 of 4 (sorted paths)
#
# Exit code: 0 if all tests pass, non-zero otherwise.

set -uo pipefail
cd "$(dirname "$0")/.."

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/donkey_tests_XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
export TMP_DIR

# Optional machine-readable report: one TSV line per discovered file plus the
# log for each run. The caller owns the directory and must start it empty.
REPORT_DIR="${TEST_REPORT_DIR:-}"
if [ -n "$REPORT_DIR" ]; then
  if [ -e "$REPORT_DIR" ] && [ ! -d "$REPORT_DIR" ]; then
    echo "TEST_REPORT_DIR is not a directory: $REPORT_DIR" >&2
    exit 2
  fi
  if [ -d "$REPORT_DIR" ] && [ -n "$(ls -A "$REPORT_DIR" 2>/dev/null)" ]; then
    echo "TEST_REPORT_DIR must be empty: $REPORT_DIR" >&2
    exit 2
  fi
  mkdir -p "$REPORT_DIR/logs"
  export REPORT_DIR
fi

# Test execution mode. `legacy` compiles one binary per file; `grouped`
# compiles one binary per manifest group and runs each file in a subprocess.
TEST_RUNNER="${TEST_RUNNER:-grouped}"
EXTRA_NIM_FLAGS="${EXTRA_NIM_FLAGS:-}"
export EXTRA_NIM_FLAGS
case "$TEST_RUNNER" in
  legacy|grouped) ;;
  *)
    echo "TEST_RUNNER must be 'legacy' or 'grouped': $TEST_RUNNER" >&2
    exit 2
    ;;
esac

REPO_ROOT="$(pwd)"
export REPO_ROOT
GROUP_MANIFEST="${TEST_GROUP_MANIFEST:-$REPO_ROOT/tests/test_groups.tsv}"
export GROUP_MANIFEST

# Persistent per-path nimcache root. Falls back to the run's temp dir when
# HOME is unusable (unset, or a literal "~", which would create "./~").
TEST_NIMCACHE_ROOT=""
if [ -n "${XDG_CACHE_HOME:-}" ]; then
  cache_base="$XDG_CACHE_HOME"
elif [ -n "${HOME:-}" ]; then
  cache_base="$HOME/.cache"
else
  # Neither is set: `/.cache` is absolute but not writable, and creating it
  # would fail every test in a container. Use the per-run temp dir.
  cache_base=""
fi
case "$cache_base" in
  /*) TEST_NIMCACHE_ROOT="$cache_base/nim/donkey-tests" ;;
esac
export TEST_NIMCACHE_ROOT

# CI stores grouped artifacts separately from the per-file caches.
if [ -n "${TEST_GROUP_CACHE_DIR:-}" ]; then
  GROUP_CACHE_ROOT="$TEST_GROUP_CACHE_DIR"
elif [ -n "$TEST_NIMCACHE_ROOT" ]; then
  GROUP_CACHE_ROOT="$TEST_NIMCACHE_ROOT/grouped"
else
  GROUP_CACHE_ROOT="$TMP_DIR/grouped"
fi

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
  local skip_reason=""
  case "$f" in
    tests/stress/*)
      if [ "${DONKEY_STRESS:-0}" != "1" ]; then
        skip_reason="stress suite disabled (DONKEY_STRESS!=1)"
      fi
      ;;
  esac

  # Skip files that require special build flags (opt-in backends)
  if [ -z "$skip_reason" ]; then
    case "$f" in
      *t_postgres*|*t_pgvector*)
        skip_reason="requires live PostgreSQL backend" ;;
      *t_magma_memory_adapter_sqlite*) ;;
      *t_magma_graph*|*t_magma_integration*|*t_magma_memory_adapter*)
        skip_reason="requires -d:withPostgres and a live database" ;;
      *t_wasm*|*t_shell_composer*)
        if [ ! -f "$HOME/.donkey/busybox" ] || ! command -v wasmtime >/dev/null 2>&1; then
          skip_reason="requires ~/.donkey/busybox and wasmtime"
        fi
        ;;
    esac
  fi

  if [ -n "$skip_reason" ]; then
    printf "SKIP  %-65s %s\n" "$f" "$skip_reason"
    if [ -n "${REPORT_DIR:-}" ]; then
      local skip_log="$REPORT_DIR/logs/${f}.log"
      mkdir -p "$(dirname "$skip_log")"
      printf "SKIPPED: %s\n" "$skip_reason" > "$skip_log"
      printf '%s\t%s\t%s\n' "$f" skipped "$skip_reason" >> "$tmp_dir/meta_${id}.tsv"
    fi
    return 0
  fi

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
  if [ -n "$EXTRA_NIM_FLAGS" ]; then
    local flags_hash
    flags_hash="$(printf '%s' "$EXTRA_NIM_FLAGS" | cksum | cut -d' ' -f1)"
    cache_key="${cache_key}_${flags_hash}"
  fi
  local cache_dir
  if [ -n "$TEST_NIMCACHE_ROOT" ]; then
    cache_dir="$TEST_NIMCACHE_ROOT/${cache_key}_d"
  else
    # No usable HOME (unset or a literal "~"): keep the cache inside the
    # per-run temp dir instead of creating a "./~" directory in the repo.
    cache_dir="$tmp_dir/nimcache_${id}_d"
  fi

  local run_status=0
  if [ -n "${REPORT_DIR:-}" ]; then
    # unittest2 only prints individual case names in verbose mode; its
    # compact output is enough for CI but not for report comparison.
    UNITTEST2_OUTPUT_LVL=VERBOSE nim c --hints:off --mm:orc -u:withPostgres $EXTRA_NIM_FLAGS \
      --nimcache:"$cache_dir" \
      -r "$f" > "$log" 2>&1 || run_status=$?
  else
    nim c --hints:off --mm:orc -u:withPostgres $EXTRA_NIM_FLAGS \
      --nimcache:"$cache_dir" \
      -r "$f" > "$log" 2>&1 || run_status=$?
  fi

  if [ "$run_status" -eq 0 ]; then
    touch "$tmp_dir/pass_${id}"
    local summary
    summary=$(grep -E "\[Summary\]|\[OK\]" "$log" | tail -1 || true)
    printf "PASS  %-65s %s\n" "$f" "$summary"
  else
    echo "$f" > "$tmp_dir/fail_${id}"
    echo "FAIL  $f"
    grep -E "Error:|FAILED|\[FAILED\]" "$log" | head -10 >&2 || true
  fi

  if [ -n "${REPORT_DIR:-}" ]; then
    local report_log="$REPORT_DIR/logs/${f}.log"
    mkdir -p "$(dirname "$report_log")"
    cp "$log" "$report_log"
    local file_status="executed"
    if [ "$run_status" -ne 0 ]; then
      file_status="failed"
    fi
    printf '%s\t%s\t%s\n' "$f" "$file_status" "" >> "$tmp_dir/meta_${id}.tsv"
  fi
}
export -f run_one

# Append one inventory line and copy the log. Shared by grouped runs.
record_report() {
  local f="$1" status="$2" log="$3" id="$4"
  [ -n "${REPORT_DIR:-}" ] || return 0
  local report_log="$REPORT_DIR/logs/${f}.log"
  mkdir -p "$(dirname "$report_log")"
  if [ -n "$log" ] && [ -f "$log" ]; then
    cp "$log" "$report_log"
  else
    printf '%s\n' "$status" > "$report_log"
  fi
  printf '%s\t%s\t%s\n' "$f" "$status" "" >> "$TMP_DIR/meta_${id}.tsv"
}
export -f record_report

group_cache_dir() {
  printf '%s' "$GROUP_CACHE_ROOT/${1}_${GROUP_CACHE_PROFILE}"
}
export -f group_cache_dir

# The build lock knows its owner, so a lock left by a killed run is taken
# over instead of waited on (scripts/lib/group_lock.sh).
source "$REPO_ROOT/scripts/lib/group_lock.sh"
export GROUP_LOCK_LEGACY_AGE_SEC
export -f group_lock_is_stale reclaim_group_lock acquire_group_lock release_group_lock

# Compile one manifest group. Files are executed later, in parallel, so a slow
# test cannot serialize the rest of its group.
build_group() {
  local group="$1"
  local cache_dir lock entry binary build_log stamp
  cache_dir="$(group_cache_dir "$group")"
  lock="${cache_dir}.lock"
  entry="$cache_dir/entry.nim"
  binary="$cache_dir/entry"
  build_log="$cache_dir/build.log"
  stamp="$cache_dir/input.sha256"

  mkdir -p "$GROUP_CACHE_ROOT"
  acquire_group_lock "$lock" 600 || return 1
  mkdir -p "$cache_dir"

  local imports="$cache_dir/imports.tmp"
  : > "$imports"
  echo 'import std/envvars' >> "$imports"
  local idx=0 paths=() aliases=()
  while IFS=$'\t' read -r g p; do
    [ "$g" = "$group" ] || continue
    echo "import ${p%.nim} as g$idx" >> "$imports"
    paths+=("$p")
    aliases+=("g$idx")
    idx=$((idx + 1))
  done < "$GROUP_MANIFEST"

  {
    cat "$imports"
    echo ""
    echo 'let target = getEnv("TEST_FILE")'
    echo 'delEnv("TEST_FILE")'
    echo 'case target'
    local i
    for i in "${!paths[@]}"; do
      echo "of \"${paths[$i]}\":"
      echo "  ${aliases[$i]}.runTests()"
    done
    echo 'else:'
    echo '  stderr.writeLine("unknown grouped test: " & target)'
    echo '  quit(2)'
  } > "$entry.tmp"
  if cmp -s "$entry.tmp" "$entry"; then
    rm -f "$entry.tmp"
  else
    mv "$entry.tmp" "$entry"
  fi

  local run_status=0
  if [ -x "$binary" ] && [ -n "$GROUP_CACHE_INPUTS" ] && [ -r "$stamp" ] &&
     [ "$(cat "$stamp")" = "$GROUP_CACHE_INPUTS" ]; then
    printf 'REUSE group %s\n' "$group"
  else
    printf 'BUILD group %s\n' "$group"
    if ! rm -f "$stamp"; then
      run_status=1
    elif [ -n "${REPORT_DIR:-}" ]; then
      UNITTEST2_OUTPUT_LVL=VERBOSE nim c --hints:off --mm:orc -u:withPostgres $EXTRA_NIM_FLAGS \
        --panics:on -d:ssl --threads:on \
        -d:withSqlite -d:staticSqlite \
        --path:"$REPO_ROOT" --path:"$REPO_ROOT/src" \
        --nimcache:"$cache_dir/nimcache" -o:"$binary" "$entry" \
        > "$build_log" 2>&1 || run_status=$?
    else
      nim c --hints:off --mm:orc -u:withPostgres $EXTRA_NIM_FLAGS \
        --panics:on -d:ssl --threads:on \
        -d:withSqlite -d:staticSqlite \
        --path:"$REPO_ROOT" --path:"$REPO_ROOT/src" \
        --nimcache:"$cache_dir/nimcache" -o:"$binary" "$entry" \
        > "$build_log" 2>&1 || run_status=$?
    fi
    if [ "$run_status" -eq 0 ] && [ -x "$binary" ] && [ -n "$GROUP_CACHE_INPUTS" ]; then
      printf '%s\n' "$GROUP_CACHE_INPUTS" > "$stamp.tmp" &&
        mv "$stamp.tmp" "$stamp" || run_status=$?
    fi
  fi
  release_group_lock "$lock"

  if [ "$run_status" -ne 0 ] || [ ! -x "$binary" ]; then
    echo "FAIL  group $group (compile)"
    grep -E "Error:|error:" "$build_log" | head -10 >&2 || true
    printf '%s\n' "$build_log" > "$TMP_DIR/groupfail_${group}"
    return 1
  fi
  touch "$TMP_DIR/groupok_${group}"
  return 0
}
export -f build_group

# Run one selected file from an already-compiled group.
run_group_file() {
  local group="$1"
  local f="$2"
  local cache_dir binary build_log
  cache_dir="$(group_cache_dir "$group")"
  binary="$cache_dir/entry"
  build_log="$cache_dir/build.log"
  local id
  id="g$(printf '%s' "$f" | cksum | cut -d' ' -f1)"

  if [ ! -f "$TMP_DIR/groupok_${group}" ]; then
    printf "RUN   %s\n" "$f"
    echo "FAIL  $f"
    echo "$f" > "$TMP_DIR/fail_${id}"
    if [ -n "${REPORT_DIR:-}" ]; then
      record_report "$f" failed "$build_log" "$id"
    fi
    return 1
  fi

  local log="$TMP_DIR/test_${id}.log"
  printf "RUN   %s\n" "$f"
  local file_status=0
  if [ -n "${REPORT_DIR:-}" ]; then
    TEST_FILE="$f" UNITTEST2_OUTPUT_LVL=VERBOSE "$binary" > "$log" 2>&1 || file_status=$?
  else
    TEST_FILE="$f" "$binary" > "$log" 2>&1 || file_status=$?
  fi
  if [ "$file_status" -eq 0 ]; then
    touch "$TMP_DIR/pass_${id}"
    local summary
    summary=$(grep -E "\[Summary\]|\[OK\]" "$log" | tail -1 || true)
    printf "PASS  %-65s %s\n" "$f" "$summary"
  else
    echo "$f" > "$TMP_DIR/fail_${id}"
    echo "FAIL  $f"
    grep -E "Error:|FAILED|\[FAILED\]" "$log" | head -10 >&2 || true
  fi
  if [ -n "${REPORT_DIR:-}" ]; then
    local file_status_name="executed"
    [ "$file_status" -ne 0 ] && file_status_name="failed"
    record_report "$f" "$file_status_name" "$log" "$id"
  fi
  return "$file_status"
}
export -f run_group_file

run_job() {
  local job="$1"
  local kind="${job%%$'\t'*}"
  local rest="${job#*$'\t'}"
  case "$kind" in
    file)
      local id
      id="$(printf '%s' "$rest" | cksum | cut -d' ' -f1)"
      run_one "$rest" "$TMP_DIR" "$id"
      ;;
    group)
      build_group "$rest"
      ;;
    gfile)
      local group="${rest%%$'\t'*}"
      local f="${rest#*$'\t'}"
      run_group_file "$group" "$f"
      ;;
    *)
      echo "Unknown test job: $job" >&2
      return 2
      ;;
  esac
}
export -f run_job

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

SHARD_TOTAL="${SHARD_TOTAL:-1}"
SHARD_INDEX="${SHARD_INDEX:-1}"
if ! [[ "$SHARD_TOTAL" =~ ^[1-9][0-9]*$ ]] || ! [[ "$SHARD_INDEX" =~ ^[1-9][0-9]*$ ]]; then
  echo "SHARD_TOTAL/SHARD_INDEX must be positive integers" >&2
  exit 2
fi
if [ "$SHARD_INDEX" -gt "$SHARD_TOTAL" ]; then
  echo "SHARD_INDEX ($SHARD_INDEX) exceeds SHARD_TOTAL ($SHARD_TOTAL)" >&2
  exit 2
fi

# Every target must exist: `find` would otherwise report an error, contribute
# no files, and let a mistyped target look like a successful empty run.
for target in "${TARGETS[@]}"; do
  if [ ! -e "$target" ]; then
    echo "No such test target: $target" >&2
    exit 2
  fi
done

# Bash 3.2 (stock macOS) has no mapfile; collect with a while-read loop.
# sort -u drops files listed twice when a target overlaps a file target.
files=()
file_count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  files+=("$f")
  file_count=$((file_count + 1))
done < <(find "${TARGETS[@]}" -name "*.nim" | sort -u)

if [ "$file_count" -eq 0 ]; then
  echo "No test files found for targets: ${TARGETS[*]}" >&2
  exit 2
fi

# Collect the selected files first. Legacy mode filters them round-robin;
# grouped mode assigns whole units below, using the full checkout inventory.
idx=0
items=()
selected_files=("${files[@]}")
if [ "$TEST_RUNNER" = "legacy" ]; then
  shard_nr=0
  for f in "${files[@]}"; do
    shard_nr=$((shard_nr + 1))
    if [ "$SHARD_TOTAL" -gt 1 ] &&
       [ $(( (shard_nr - 1) % SHARD_TOTAL + 1 )) -ne "$SHARD_INDEX" ]; then
      continue
    fi
    idx=$((idx + 1))
    items+=("$f" "$TMP_DIR" "$idx")
  done
  if [ "$idx" -eq 0 ]; then
    echo "Shard $SHARD_INDEX/$SHARD_TOTAL has no test files for targets: ${TARGETS[*]}"
    exit 0
  fi
fi

if [ "$TEST_RUNNER" = "grouped" ]; then
  if [ ! -f "$GROUP_MANIFEST" ]; then
    echo "Grouped runner needs a manifest: $GROUP_MANIFEST" >&2
    exit 2
  fi

  # Validate the whole manifest before running anything: a duplicate path or a
  # file that moved would silently change what a group executes.
  normalized_manifest="$TMP_DIR/manifest.tsv"
  seen_paths="$TMP_DIR/manifest_paths.txt"
  : > "$normalized_manifest"
  : > "$seen_paths"
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    group="${line%%$'\t'*}"
    path="${line#*$'\t'}"
    if [ "$group" = "$line" ] || [ -z "$path" ] || [ -z "$group" ]; then
      echo "$GROUP_MANIFEST:$lineno: expected group<TAB>path" >&2
      exit 2
    fi
    if ! [[ "$group" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      echo "$GROUP_MANIFEST:$lineno: invalid group name: $group" >&2
      exit 2
    fi
    path="${path#./}"
    case "$path" in
      *.nim) ;;
      *)
        echo "$GROUP_MANIFEST:$lineno: not a Nim test: $path" >&2
        exit 2
        ;;
    esac
    if [ ! -f "$path" ]; then
      echo "$GROUP_MANIFEST:$lineno: missing test file: $path" >&2
      exit 2
    fi
    if grep -Fqx "$path" "$seen_paths"; then
      echo "$GROUP_MANIFEST:$lineno: duplicate path: $path" >&2
      exit 2
    fi
    printf '%s\n' "$path" >> "$seen_paths"
    printf '%s\t%s\n' "$group" "$path" >> "$normalized_manifest"
  done < "$GROUP_MANIFEST"
  GROUP_MANIFEST="$normalized_manifest"
  export GROUP_MANIFEST

  # Shard assignment uses the complete checkout inventory: every manifest
  # group is one unit, and every non-manifest test file is one unit. Path
  # filtering happens after assignment, so a group never splits across shards
  # and adding a new file cannot move a group to another shard.
  group_units="$TMP_DIR/unit_groups.txt"
  cut -f1 "$GROUP_MANIFEST" | sort -u > "$group_units"
  all_tests="$TMP_DIR/all_tests.txt"
  find tests -name '*.nim' | sort -u > "$all_tests"

  units=()
  while IFS= read -r group; do
    [ -n "$group" ] && units+=("group:$group")
  done < "$group_units"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! grep -Fqx "$path" "$seen_paths"; then
      units+=("file:$path")
    fi
  done < "$all_tests"

  unit_shards="$TMP_DIR/unit_shards.tsv"
  : > "$unit_shards"
  unit_nr=0
  for unit in "${units[@]}"; do
    unit_nr=$((unit_nr + 1))
    unit_shard=$(( (unit_nr - 1) % SHARD_TOTAL + 1 ))
    printf '%s\t%s\n' "$unit" "$unit_shard" >> "$unit_shards"
  done

  build_jobs=()
  run_jobs=()
  group_names="$TMP_DIR/groups.txt"
  : > "$group_names"
  for f in "${selected_files[@]}"; do
    group="$(awk -F'\t' -v p="$f" '$2 == p { print $1; exit }' "$GROUP_MANIFEST")"
    if [ -n "$group" ]; then
      group_shard="$(awk -F'\t' -v k="group:$group" '$1 == k { print $2; exit }' "$unit_shards")"
      if [ "$group_shard" = "$SHARD_INDEX" ]; then
        printf '%s\n' "$f" >> "$TMP_DIR/group_${group}.files"
        printf '%s\n' "$group" >> "$group_names"
      fi
    else
      file_shard="$(awk -F'\t' -v k="file:$f" '$1 == k { print $2; exit }' "$unit_shards")"
      if [ "$file_shard" = "$SHARD_INDEX" ]; then
        run_jobs+=("file"$'\t'"$f")
      fi
    fi
  done
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    build_jobs+=("group"$'\t'"$group")
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      run_jobs+=("gfile"$'\t'"$group"$'\t'"$f")
    done < "$TMP_DIR/group_${group}.files"
  done < <(sort -u "$group_names")

  if [ "${#run_jobs[@]}" -eq 0 ]; then
    echo "Shard $SHARD_INDEX/$SHARD_TOTAL has no test units for targets: ${TARGETS[*]}"
    exit 0
  fi

  build_status=0
  if [ -n "${build_jobs[0]:-}" ]; then
    fingerprints=""
    if [ -r "${TEST_GROUP_FINGERPRINT_FILE:-}" ]; then
      fingerprints="$(cat "$TEST_GROUP_FINGERPRINT_FILE")"
    elif command -v python3 >/dev/null 2>&1; then
      fingerprints="$(python3 scripts/test_build_fingerprint.py)" || fingerprints=""
    fi
    read -r GROUP_CACHE_PROFILE GROUP_CACHE_INPUTS <<< "$fingerprints"
    if ! [[ "$GROUP_CACHE_PROFILE" =~ ^[0-9a-f]{64}$ &&
            "$GROUP_CACHE_INPUTS" =~ ^[0-9a-f]{64}$ ]]; then
      # Environments without a fingerprint tool can still compile and run tests.
      GROUP_CACHE_ROOT="$TMP_DIR/grouped"
      GROUP_CACHE_PROFILE=uncached
      GROUP_CACHE_INPUTS=""
    fi
    export GROUP_CACHE_ROOT GROUP_CACHE_PROFILE GROUP_CACHE_INPUTS
    printf "%s\0" "${build_jobs[@]}" |
      xargs -0 -P "$JOBS" -n 1 bash -c 'run_job "$1"' _ || build_status=$?
  fi
  run_status=0
  printf "%s\0" "${run_jobs[@]}" |
    xargs -0 -P "$JOBS" -n 1 bash -c 'run_job "$1"' _ || run_status=$?
  runner_status=0
  if [ "$build_status" -ne 0 ] || [ "$run_status" -ne 0 ]; then
    runner_status=1
  fi
else
  runner_status=0
  printf "%s\0" "${items[@]}" |
    xargs -0 -P "$JOBS" -n 3 bash -c 'run_one "$@"' _ || runner_status=$?
fi

PASS=$(find "$TMP_DIR" -name "pass_*" | wc -l)
FAIL=$(find "$TMP_DIR" -name "fail_*" | wc -l)

if [ -n "${REPORT_DIR:-}" ]; then
  printf 'path\tstatus\treason\n' > "$REPORT_DIR/index.tsv"
  find "$TMP_DIR" -name 'meta_*.tsv' -exec cat {} + 2>/dev/null | sort >> "$REPORT_DIR/index.tsv"
fi

# A worker killed before it could write a marker (OOM, xargs failing to spawn)
# must not look like a green run: no fail_* file will exist in that case.
if [ "$runner_status" -ne 0 ] && [ "$FAIL" -eq 0 ]; then
  echo "Test runner failed (xargs status $runner_status) without recording a failure" >&2
  exit 1
fi

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
