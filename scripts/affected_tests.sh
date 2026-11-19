#!/usr/bin/env bash
# Print the test targets affected by the changes against a git ref.
#
# Usage: scripts/affected_tests.sh [base-ref]   (default: origin/master)
#        BASE_REF=origin/master scripts/affected_tests.sh
#
# The output is newline-separated and can be passed straight to run_tests.sh.
# Shared layers under src/ (core, ports, domain, app, config, infra, the
# entrypoint and every adapter except channel/provider) are imported across the
# test tree, so a change there always runs the full suite. Unknown paths do too.
# This is deliberately conservative: an unrecognized path never narrows the run.

set -euo pipefail

BASE="${BASE_REF:-${1:-origin/master}}"
cd "$(dirname "$0")/.."

if [ -n "${AFFECTED_FILES:-}" ]; then
  # Debugging/testing hook: newline-separated paths instead of a git diff.
  changed="$AFFECTED_FILES"
elif git merge-base "$BASE" HEAD >/dev/null 2>&1; then
  # Compare against the merge base so commits that landed on the base branch
  # after this branch point are not mistaken for part of the diff.
  changed="$(git diff --name-only "$BASE"...HEAD -- 2>/dev/null || true)"
else
  # Shallow or unrelated histories: fall back to a direct tree diff.
  changed="$(git diff --name-only "$BASE" HEAD -- 2>/dev/null || true)"
fi

if [ -z "$changed" ]; then
  echo "tests"
  exit 0
fi

full=0
targets=()

add() {
  local target
  for target in "$@"; do
    targets+=("$target")
  done
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    # A test edit runs that test; other files under tests/ (fixtures, helpers)
    # are cross-cutting and fall back to the full suite.
    tests/t_*.nim|tests/*/t_*.nim)
      add "$f"
      ;;
    tests/*)
      full=1
      ;;
    # Leaf layer: only tests/tui consumes it.
    src/donkey/tui/*)
      add tests/tui
      ;;
    # Provider adapters are exercised by suites outside tests/adapters as well.
    src/donkey/adapters/provider/*)
      add tests/adapters tests/provider tests/domain/providers tests/core \
          tests/app tests/architecture tests/reranking tests/embedding
      ;;
    # Channel adapters are shared with the port/config/app suites.
    src/donkey/adapters/channel/*)
      add tests/adapters tests/adapters/channel tests/channel tests/app \
          tests/architecture tests/ports tests/config
      ;;
    # Every other src/ path is a shared layer (core, ports, domain, app,
    # config, infra, other adapters, entrypoint): run the full suite.
    src/*)
      full=1
      ;;
    *.md|docs/*)
      add tests/architecture
      ;;
    *)
      full=1
      ;;
  esac
done <<< "$changed"

if [ "$full" -eq 1 ]; then
  echo tests
  exit 0
fi

if [ "${#targets[@]}" -eq 0 ]; then
  echo tests
  exit 0
fi

# Drop duplicates while keeping a stable order; every target must exist.
unique=()
while IFS= read -r target; do
  [ -n "$target" ] && unique+=("$target")
done < <(printf '%s\n' "${targets[@]}" | sort -u)

if [ "${#unique[@]}" -eq 0 ]; then
  echo tests
  exit 0
fi
for target in "${unique[@]}"; do
  if [ ! -e "$target" ]; then
    echo tests
    exit 0
  fi
done
printf '%s\n' "${unique[@]}"
