## Config loader — reads donkey.toml, applies env overrides, returns defaults
## gracefully when the file is missing or unparseable.
##
## Priority (highest to lowest):
##   1. DONKEY_HOME env var (for home dir only)
##   2. Values in donkey.toml
##   3. Built-in defaults (see config/types.nim)

import std/[os, strutils]
import parsetoml
import ./types
import ../core/types

export types

const EnvHome* = "DONKEY_HOME"

proc resolveHome*(): string =
  result = getEnv(EnvHome)
  if result.len == 0:
    result = expandTilde("~/.donkey")

proc loadConfig*(path: string): DonkeyConfig =
  let home = resolveHome()
  result = defaultConfig(home)

  if not fileExists(path): return

  try:
    let t = parseFile(path)

    if not t.hasKey("donkey"): return
    let d = t["donkey"]

    if d.hasKey("log_level"):
      result.logLevel = parseLogLevel(d["log_level"].getStr())

    if d.hasKey("log_file"):
      let lf = d["log_file"].getStr().strip()
      if lf.len > 0:
        result.logFile = expandTilde(lf)

    if d.hasKey("paddocks"):
      let p = d["paddocks"].getStr().strip()
      if p.len > 0:
        result.paddocks = expandTilde(p)

  except:
    discard  # Bad TOML → silently fall back to defaults (caller should log)
