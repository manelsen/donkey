## The environment is read once (audit item 9). `config/environment` takes a
## snapshot after `donkey.env` and the vault have filled the process
## environment, and the daemon and `ctl` pass it down. Everything else gets
## its settings from that snapshot, so a test sets them without `putEnv` and
## nothing changes under a running daemon.
##
## - Only `config/environment` reads the environment.
## - `config/dotenv` and `adapters/secrets/vault` fill it before the snapshot
##   (children such as MCP servers inherit what they set), so they may read it
##   to keep the variables already there.
## - Reads elsewhere have a budget that only goes down while the migration
##   runs. Removing some means lowering `ReadBudget` in the same change.

import std/[os, strutils, unittest]
import ./t_nim_source

const
  EnvCalls = ["getEnv", "existsEnv", "envPairs"]
  Owners = [
    "src/donkey/config/environment.nim",  ## the one reader
    "src/donkey/config/dotenv.nim",       ## fills the environment from donkey.env
    "src/donkey/adapters/secrets/vault.nim",  ## fills it from the vault
  ]
  ReadBudget = 133
    ## Reads outside the owners. Only goes down.

func readLines(code: string): seq[int] =
  ## 0-based lines with a call to one of `EnvCalls` (`getEnv(` or `getEnv (`),
  ## not the tail of a longer name.
  let lines = code.splitLines()
  for i, line in lines:
    for name in EnvCalls:
      var at = line.find(name)
      while at >= 0:
        let before = if at > 0: line[at - 1] else: ' '
        var after = at + name.len
        while after < line.len and line[after] == ' ': inc after
        if not isIdentChar(before) and before != '.' and
           after < line.len and line[after] in {'(', '"'}:
          result.add i
        at = line.find(name, at + 1)

proc runTests*() =
  suite "environment reads":
    test "calls are found in code, not in comments or text":
      check readLines(codeOnly("let x = getEnv(\"A\")")).len == 1
      check readLines(codeOnly("let x = getEnv (\"A\")")).len == 1
      check readLines(codeOnly("for k, v in envPairs(): discard")).len == 1
      check readLines(codeOnly("if existsEnv(\"A\"): discard")).len == 1
      check readLines(codeOnly("## never call getEnv(\"A\") here")).len == 0
      check readLines(codeOnly("let s = \"getEnv(A)\"")).len == 0
      check readLines(codeOnly("let x = myGetEnv(\"A\")")).len == 0
      check readLines(codeOnly("let x = env.getEnv(\"A\")")).len == 0
      check readLines(codeOnly("let x = getEnvironment()")).len == 0

    test "reads outside the owners stay within a budget that only goes down":
      var sites: seq[string]
      for path in walkDirRec("src"):
        if not path.endsWith(".nim") or path in Owners: continue
        let src = readFile(path)
        let lines = src.splitLines()
        for i in readLines(codeOnly(src)):
          sites.add path & ":" & $(i + 1) & "  " & lines[i].strip
      checkpoint($sites.len & " environment reads outside config/environment")
      if sites.len > ReadBudget:
        for site in sites: checkpoint(site)
        checkpoint("take the value from the Environment snapshot instead")
      check sites.len <= ReadBudget
      if sites.len < ReadBudget:
        checkpoint("lower ReadBudget to " & $sites.len)
      check sites.len == ReadBudget

when isMainModule:
  runTests()
