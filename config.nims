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

# PostgreSQL + pgvector + Apache AGE backend (opt-in).
# Build with: nimble build -d:withPostgres
# Requires libpq installed: apt install libpq-dev  (Debian/Ubuntu)
#                            apk add postgresql-dev  (Alpine)
when defined(withPostgres):
  switch("passL", "-lpq")

# SQLite fast-cache backend (opt-in).
# Build with: nimble build -d:withSqlite
# Requires libsqlite3 installed: apt install libsqlite3-dev  (Debian/Ubuntu)
when defined(withSqlite):
  switch("passL", "-lsqlite3")

# Nimble package paths (chronos, parsetoml, results, nimcrypto).
import std/os
let nimblePkgs = getHomeDir() / ".nimble" / "pkgs2"
if dirExists(nimblePkgs):
  for kind, path in walkDir(nimblePkgs):
    if kind == pcDir:
      switch("path", path)
