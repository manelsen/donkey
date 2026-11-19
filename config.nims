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

# SQLite backend enabled by default on the sqlite branch.
# Opt out with: nim c -u:withSqlite ...
switch("define", "withSqlite")

# PostgreSQL backend disabled by default on the sqlite branch.
# Re-enable explicitly with: nim c -d:withPostgres ...

when defined(withPostgres):
  switch("passL", "-lpq")

# SQLite backend and embedded runtime.
# Build with: nimble build
# Uses embedded SQLite amalgamation in self-contained builds.
when defined(withSqlite):
  switch("define", "staticSqlite")

# Nimble package paths (chronos, parsetoml, results, nimcrypto).
# A cache can hold several versions of the same package; adding all of them
# leaves resolution to filesystem order. Keep only the newest version.
import std/[os, strutils, tables]

proc pkgParts(dirName: string): tuple[name, version: string] =
  ## "chronos-4.4.1-<40 hex>" -> ("chronos", "4.4.1")
  let hashDash = dirName.rfind('-')
  if hashDash < 0 or dirName.len - hashDash - 1 != 40:
    return ("", "")
  let rest = dirName[0 ..< hashDash]
  let verDash = rest.rfind('-')
  if verDash < 0:
    return ("", "")
  let ver = rest[verDash + 1 .. ^1]
  if ver.len == 0 or ver[0] notin {'0'..'9'} or '.' notin ver:
    return ("", "")
  (rest[0 ..< verDash], ver)

proc versionTuple(v: string): seq[int] =
  for part in v.split('.'):
    var n = 0
    for ch in part:
      if ch in {'0'..'9'}:
        n = n * 10 + ord(ch) - ord('0')
    result.add n

proc isNewer(a, b: string): bool =
  let x = versionTuple(a)
  let y = versionTuple(b)
  for i in 0 ..< max(x.len, y.len):
    let xi = if i < x.len: x[i] else: 0
    let yi = if i < y.len: y[i] else: 0
    if xi != yi:
      return xi > yi
  false

let nimblePkgs = getHomeDir() / ".nimble" / "pkgs2"
if dirExists(nimblePkgs):
  var selected = initTable[string, tuple[path, version: string]]()
  var loose: seq[string] = @[]
  for kind, path in walkDir(nimblePkgs):
    if kind == pcDir:
      let (name, ver) = pkgParts(path.extractFilename)
      if name.len == 0:
        loose.add(path)
      elif not selected.hasKey(name) or isNewer(ver, selected[name].version):
        selected[name] = (path, ver)
  for path in loose:
    switch("path", path)
  for name, entry in selected:
    switch("path", entry.path)
