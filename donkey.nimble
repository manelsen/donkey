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

# Tasks
task test, "Run all tests":
  exec "testament --megatest:off all"
