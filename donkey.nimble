# Package
version = "0.2.0"
author = "Manelsen"
description = "AI agent system"
license = "MIT"
srcDir      = "src"
binDir      = "."
bin         = @["donkey"]

# Dependencies
# CI pins Nim 2.2.12: 2.2.14/2.4.x SIGSEGV under --mm:orc when a built-in
# Channel carries GC-managed values (provider executor); the dependency set is
# not the cause. Keep >= 2.0.0 so the Alpine Docker image still resolves.
requires "nim >= 2.0.0"
requires "chronos >= 4.4.1"
requires "nimcrypto >= 0.7.3"
requires "parsetoml >= 0.7.2"
requires "results >= 0.5.1"
requires "ws >= 0.6.0"
requires "db_connector >= 0.1.0" ## PostgreSQL + pgvector + AGE (-d:withPostgres)
requires "illwill >= 0.4.1" ## TUI dashboard (donkey tui)
requires "wasm3 >= 0.1.6"
requires "checksums >= 0.2.2" ## SHA1 for WeChat webhook signature (replaces deprecated std/sha1)

# Tasks
task test, "Compile and run all tests (execution mode)":
  ## Uses nim -r instead of testament bare 'all' (which defaults to compile-only
  ## for files without a `discard """action: "run""""` spec block).
  exec "bash scripts/run_tests.sh"
