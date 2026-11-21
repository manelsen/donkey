## `{.cast(gcsafe).}` tells the compiler to stop checking thread safety for a
## block. Each one is a promise nobody verifies, and a broken one shows up as
## a crash far away (closures crossing threads crashed the provider executor
## under Nim 2.4). So the casts are on a diet:
##
## - A cast that stays must say why it is safe, with `## gcsafe: <reason>`
##   on the same line or the line above.
## - Casts without a reason have a budget that only goes down. Removing one
##   means lowering `UnexplainedBudget` in the same change; adding one fails.

import std/[os, strutils, unittest]
import ./t_nim_source

const
  CastPragma = "{.cast(gcsafe).}"
  ReasonMarker = "## gcsafe:"
  UnexplainedBudget = 130
    ## Casts in src/ without a reason. Lower it as casts are removed or
    ## explained; it must never go up.

type CastSite = object
  path: string
  line: int        ## 1-based
  explained: bool

func hasReason(line: string): bool =
  let at = line.find(ReasonMarker)
  at >= 0 and line[at + ReasonMarker.len .. ^1].strip.len > 0

func castSites(path, src: string): seq[CastSite] =
  ## Casts in code (not in comments or strings), each with whether a reason
  ## sits on its line or the line above.
  let lines = src.splitLines()
  let code = codeOnly(src).splitLines()
  for i, line in code:
    var at = line.find(CastPragma)
    while at >= 0:
      let explained = lines[i].hasReason or (i > 0 and lines[i - 1].hasReason)
      result.add CastSite(path: path, line: i + 1, explained: explained)
      at = line.find(CastPragma, at + CastPragma.len)

proc runTests*() =
  suite "gcsafe casts":
    test "casts are found in code and their reasons are read":
      check castSites("x", "{.cast(gcsafe).}:\n  discard").len == 1
      check not castSites("x", "{.cast(gcsafe).}:\n  discard")[0].explained
      check castSites("x", "## gcsafe: read-only after init\n{.cast(gcsafe).}:")[0].explained
      check castSites("x", "{.cast(gcsafe).}:  ## gcsafe: guarded by gLock")[0].explained
      check not castSites("x", "## gcsafe:\n{.cast(gcsafe).}:")[0].explained
      check castSites("x", "## avoid {.cast(gcsafe).} here").len == 0
      check castSites("x", "let s = \"{.cast(gcsafe).}\"").len == 0

    test "unexplained casts stay within a budget that only goes down":
      var unexplained: seq[string]
      var total = 0
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        for site in castSites(path, readFile(path)):
          inc total
          if not site.explained:
            unexplained.add site.path & ":" & $site.line
      checkpoint($total & " casts, " & $unexplained.len & " without a reason")
      if unexplained.len > UnexplainedBudget:
        for site in unexplained: checkpoint("no reason: " & site)
        checkpoint("a new cast needs `## gcsafe: <reason>`, or a design without it")
      check unexplained.len <= UnexplainedBudget
      if unexplained.len < UnexplainedBudget:
        checkpoint("lower UnexplainedBudget to " & $unexplained.len)
      check unexplained.len == UnexplainedBudget

when isMainModule:
  runTests()
