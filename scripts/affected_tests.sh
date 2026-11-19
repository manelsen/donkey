#!/usr/bin/env bash
# Print the test targets affected by the changes against a git ref.
#
# Usage: scripts/affected_tests.sh [base-ref]   (default: origin/master)
#
# The output is newline-separated and can be passed straight to run_tests.sh.
# Unknown or cross-cutting changes print "tests", which selects the full suite.
# This is deliberately conservative: an unrecognized path never narrows the run.

set -euo pipefail

BASE="${1:-origin/master}"
cd "$(dirname "$0")/.."

if [ -n "${AFFECTED_FILES:-}" ]; then
  # Debugging/testing hook: newline-separated paths instead of a git diff.
  changed="$AFFECTED_FILES"
elif ! changed="$(git diff --name-only "$BASE" HEAD 2>/dev/null)"; then
  echo "tests"
  exit 0
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
    # A test edit runs that test; helper/fixture changes fall back to the suite.
    tests/t_*.nim|tests/*/t_*.nim)
      add "$f"
      ;;
    tests/*)
      full=1
      ;;
    # Cross-cutting: contracts, entrypoint, build config, tooling.
    src/donkey.nim|src/donkey/core/*|src/donkey/ports/*|config.nims|donkey.nimble|scripts/*|.github/*)
      full=1
      ;;
    src/donkey/adapters/channel/*)
      add tests/adapters/channel tests/channel tests/app tests/architecture
      ;;
    src/donkey/adapters/provider/*)
      add tests/adapters/provider tests/provider tests/domain/providers \
          tests/app/t_provider_executor.nim tests/app/t_provider_breadth_surface.nim \
          tests/app/t_orchestrator.nim
      ;;
    src/donkey/adapters/*)
      add tests/adapters tests/app tests/architecture
      ;;
    src/donkey/domain/*)
      add tests/domain tests/app tests/core
      ;;
    src/donkey/app/*)
      add tests/app tests/architecture
      ;;
    src/donkey/config/*)
      add tests/config tests/app tests/architecture
      ;;
    src/donkey/infra/*)
      add tests/infra tests/app
      ;;
    src/donkey/tui/*)
      add tests/tui
      ;;
    *.md|docs/*)
      add tests/t_version.nim tests/architecture
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

# Drop duplicates while keeping a stable order; every target must exist.
mapfile -t unique < <(printf '%s\n' "${targets[@]}" | sort -u)
for target in "${unique[@]}"; do
  if [ ! -e "$target" ]; then
    echo tests
    exit 0
  fi
done
printf '%s\n' "${unique[@]}"
