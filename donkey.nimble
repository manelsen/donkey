# Package
version = "0.2.0"
author = "Manelsen"
description = "AI agent system"
license = "MIT"
srcDir      = "src"
binDir      = "."
bin         = @["donkey"]

# Dependencies
# Nim 2.4.2 (CI and the Docker build pin it). Every package is pinned to an
# exact version (by commit for the three that publish no tags, where a version
# names no revision), the transitive ones too (they come with chronos), so a fresh
# install resolves the same tree. There is no nimble.lock: with a lock file
# present the compiler stops using the default nimble path, and the grouped
# test builds (entries outside the repo, without config.nims) cannot find
# their packages. Bump a pin deliberately and run the suite.
#
# 2.2.14 and 2.4.x crashed the provider executor while it moved provider
# closures built on the event loop to its workers: ORC's cycle collector keeps
# roots per thread. Workers now build their own closures, and spawnThread
# refuses any thread argument holding a ref or a closure.
requires "nim >= 2.4.2"
requires "chronos == 4.4.1"
requires "nimcrypto == 0.7.3"
requires "results == 0.5.1"
requires "ws#c9c0c7b51e2e83cc9305a895a0b144a297b4bea8" ## 0.6.0; untagged upstream, so pinned by commit
requires "db_connector#29450a2063970712422e1ab857695c12d80112a6" ## 0.1.0, untagged upstream: pinned by commit. PostgreSQL + pgvector + AGE (-d:withPostgres)
requires "illwill == 0.4.1" ## TUI dashboard (donkey tui)
requires "checksums == 0.2.2" ## SHA1 for WeChat webhook signature (replaces deprecated std/sha1)
requires "threading#653c8eb013ab1b0486c1ebf06e14d8b79843c385" ## 0.2.1, untagged upstream: pinned by commit. Shared-memory channels for event queues
# Transitive, through chronos; pinned for a reproducible tree.
requires "stew == 0.6.5"
requires "httputils == 0.6.0"
requires "bearssl == 0.3.1"
requires "unittest2 == 0.3.0"

# Tasks
task test, "Compile and run all tests (execution mode)":
  ## Uses nim -r instead of testament bare 'all' (which defaults to compile-only
  ## for files without a `discard """action: "run""""` spec block).
  exec "bash scripts/run_tests.sh"
