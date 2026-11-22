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
  UnexplainedBudget = 115
    ## Casts in src/ without a reason. Lower it as casts are removed or
    ## explained; it must never go up.

type CastSite = object
  path: string
  line: int        ## 1-based
  explained: bool

func hasReason(line, comments: string): bool =
  ## The marker counts only inside a comment: `comments` is the line with
  ## comments blanked and literals kept, so a marker there is not blank.
  var at = line.find(ReasonMarker)
  while at >= 0:
    if at < comments.len and comments[at] == ' ' and
       line[at + ReasonMarker.len .. ^1].strip.len > 0:
      return true
    at = line.find(ReasonMarker, at + 1)
  false

func castCount(code: string): int =
  ## Casts in a line of code: `cast(gcsafe)` as a pragma item, alone or among
  ## others (`{.cast(gcsafe), cast(noSideEffect).}`), however it is spaced.
  ## In code it can only be a pragma; a type cast is `cast[T](x)`.
  let squeezed = code.multiReplace((" ", ""), ("\t", ""))
  var at = squeezed.find("cast(gcsafe)")
  while at >= 0:
    if at == 0 or not isIdentChar(squeezed[at - 1]):  ## not `broadcast(...)`
      inc result
    at = squeezed.find("cast(gcsafe)", at + 1)

func castSites(path, src: string): seq[CastSite] =
  ## Casts in code (not in comments or strings), each with whether a reason
  ## sits in a comment on its line or the line above.
  let lines = src.splitLines()
  let code = codeOnly(src).splitLines()
  let comments = withoutComments(src).splitLines()
  for i, line in code:
    for _ in 1 .. castCount(line):
      let explained = lines[i].hasReason(comments[i]) or
        (i > 0 and lines[i - 1].hasReason(comments[i - 1]))
      result.add CastSite(path: path, line: i + 1, explained: explained)

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
      check castSites("x", "{. cast(gcsafe) .}:\n  discard").len == 1
      check castSites("x", "{.cast( gcsafe ).}: discard").len == 1
      check castSites("x", "{.cast(gcsafe), cast(noSideEffect).}: discard").len == 1
      check castSites("x", "{.cast(noSideEffect), cast( gcsafe ).}: discard").len == 1
      check castSites("x", "let p = cast[pointer](x)").len == 0
      check castSites("x", "broadcast(gcsafe)").len == 0
      check castSites("x", "{.raises: [], cast(gcsafe).}: discard").len == 1
      check not castSites("x", "let l = \"## gcsafe: not a comment\"\n{.cast(gcsafe).}:")[0].explained
      check castSites("x", "let l = 1  ## gcsafe: a real comment\n{.cast(gcsafe).}:")[0].explained

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
