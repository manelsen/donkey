# Makes `src/` visible to all nim compilations in this project,
# including testament test files in tests/.
switch("path", "src")

# Strict Compilation & Panics
switch("styleCheck", "error")
switch("warningAsError", "on")
switch("panics", "on")

# Required for httpclient HTTPS (Telegram API, Zhipu API).
switch("define", "ssl")
switch("define", "wasm3HasWasi")

# Required for Discord gateway thread (Channel[T] cross-thread communication).
switch("threads", "on")

# PostgreSQL backend disabled by default on the sqlite branch.
# Re-enable explicitly with: nim c -d:withPostgres ...

when defined(withPostgres):
  switch("passL", "-lpq")

# SQLite fast-cache backend (opt-in).
# Build with: nimble build -d:withSqlite
# Uses embedded SQLite amalgamation in self-contained builds.
when defined(withSqlite):
  switch("define", "staticSqlite")

# Nimble package paths (chronos, parsetoml, results, nimcrypto).
import std/os
let nimblePkgs = getHomeDir() / ".nimble" / "pkgs2"
if dirExists(nimblePkgs):
  for kind, path in walkDir(nimblePkgs):
    if kind == pcDir:
      switch("path", path)
