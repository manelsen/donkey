# Testing
Running the suite, comparing runs and checking boundaries.

## Running Tests

```bash
# Run the default test suite (grouped compilation, one process per file)
bash scripts/run_tests.sh

# Fall back to one compiler invocation per file
TEST_RUNNER=legacy bash scripts/run_tests.sh

# Target a specific module or test file
bash scripts/run_tests.sh tests/ports
bash scripts/run_tests.sh tests/app/t_orchestrator.nim

# Execute via Nimble
nimble test
```

`tests/test_groups.tsv` maps each grouped test file to a group. Files that
cannot share a binary (profile-gated backends, stress, executable-location
dependencies) stay in the per-file fallback and are documented in
`tests/test_group_exceptions.tsv`.

To compare two runs case by case, point the runner at empty report directories
and use the comparator:

```bash
TEST_REPORT_DIR=/tmp/tests-before bash scripts/run_tests.sh tests/core
TEST_REPORT_DIR=/tmp/tests-after  bash scripts/run_tests.sh tests/core
python3 scripts/compare_test_reports.py /tmp/tests-before /tmp/tests-after
```

> [!NOTE]
> PostgreSQL tests are excluded by default in `scripts/run_tests.sh`. WASM applet and shell composer suites run automatically when `~/.donkey/busybox` and `wasmtime` are present on the host.

## Test runner performance

Measured with Nim 2.2.12, `JOBS=4`, the same checkout and the same test
fixtures. Cold runs used separate empty `XDG_CACHE_HOME` trees; warm runs
reused them.

| Mode | Cold | Warm | Compilations (cold) |
|---|---:|---:|---:|
| `TEST_RUNNER=legacy` | 730.76 s | 92.04 s | 294 |
| `grouped` (4 groups, default) | 233.31 s | 48.68 s | 20 |

The original target was **3×** in both scenarios. The default grouped mode
reaches **3.13× cold** and **1.89× warm**. The warm ceiling is the remaining
test runtime after the orchestrator debounce fixture, not scheduling; this
delivery accepts a 4-minute cold and 1-minute warm ceiling.

The gcov audit compiled both modes with
`--lineDir:on --passC:--coverage --passL:--coverage`. It recorded zero gcov
errors. The 447 line and 344 branch differences are instrumentation
attribution changes (inlining and dead-code elimination between translation
units), not lost tests: both modes run the same 5,528 cases, and
function-level counts confirm that the affected functions execute in grouped
mode.

## Verifying Architectural Boundaries

Core and Domain modules must never import Adapters. Run the automated boundary checker:

```bash
# Requires ripgrep (rg)
bash scripts/check_boundaries.sh
```

## Build locks

Each grouped build takes a lock, a directory beside the group's cache with
its owner (`PID HOST`) inside (`scripts/lib/group_lock.sh`). A run that dies
without releasing it (killed for memory, a closed terminal) leaves the lock
behind; the next run sees the owner is gone and takes it over
(`Reclaiming stale group build lock: …`) instead of waiting two minutes and
failing every test of the group. A lock without an owner, left by an older
runner, is taken over once it is a minute old.
