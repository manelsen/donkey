# Package
version     = "0.1.0"
author      = "donkey contributors"
description = "AI agent system"
license     = "MIT"
srcDir      = "src"
bin         = @["donkey"]

# Dependencies
requires "nim >= 2.0.0"
requires "chronos >= 4.0.0"
requires "nimcrypto >= 0.6.0"
requires "parsetoml >= 0.6.0"
requires "results >= 0.5.0"
requires "ws >= 0.5.0"
requires "db_connector >= 0.1.0"  ## PostgreSQL + pgvector + AGE (-d:withPostgres)
requires "illwill >= 0.4.0"       ## TUI dashboard (donkey tui)
requires "checksums >= 0.2.0"     ## SHA1 for WeChat webhook signature (replaces deprecated std/sha1)

# Tasks
task test, "Compile and run all tests (execution mode)":
  ## Uses nim -r instead of testament bare 'all' (which defaults to compile-only
  ## for files without a `discard """action: "run""""` spec block).
  exec "bash scripts/run_tests.sh"
