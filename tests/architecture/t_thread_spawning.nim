## Threads start through `infra/thread_handle.spawnThread`, which refuses at
## compile time an argument holding a ref or a closure (ORC counts references
## without atomics, so such a value would be counted by two threads at once).
## `createThread` skips that check, so it is allowed only where listed below,
## each with the reason its argument shares nothing the GC counts.

import std/[os, sets, strutils, unittest]
import ./t_nim_source

const DirectCreateThread = [
  "src/donkey/infra/thread_handle.nim",
    # spawnThread itself, behind the compile-time check.
  "src/donkey/app/provider_executor.nim",
    # `Thread[void]` workers: no argument; jobs travel through a Channel.
  "src/donkey/adapters/tools/browser_executor.nim",
    # The argument is a `ptr` to a shared block of Channels.
]

func nimIdent(name: string): string =
  ## The identity Nim gives an identifier: the first letter as written, the
  ## rest without `_` and in lower case.
  if name.len == 0: return
  result.add name[0]
  for c in name[1 .. ^1]:
    if c != '_': result.add c.toLowerAscii

func callsCreateThread(code: string): bool =
  ## True when an identifier Nim reads as `createThread` appears in `code`.
  var i = 0
  while i < code.len:
    if isIdentChar(code[i]) and (i == 0 or not isIdentChar(code[i - 1])):
      var j = i
      while j < code.len and isIdentChar(code[j]): inc j
      if nimIdent(code[i ..< j]) == "createthread": return true
      i = j
    else:
      inc i
  false

proc runTests*() =
  suite "thread spawning":
    test "createThread is found in code, not in comments or strings":
      check callsCreateThread(codeOnly("createThread(t, fn, arg)"))
      check not callsCreateThread(codeOnly("## createThread(t, fn, arg)"))
      check not callsCreateThread(codeOnly("let s = \"createThread\""))
      check not callsCreateThread(codeOnly("myCreateThreadHelper()"))

    test "every spelling Nim treats as createThread is found":
      ## Nim ignores `_` and case after the first letter of an identifier.
      check callsCreateThread(codeOnly("create_thread(t, fn, arg)"))
      check callsCreateThread(codeOnly("createTHREAD(t, fn, arg)"))
      check callsCreateThread(codeOnly("create_Thread(t, fn, arg)"))
      check not callsCreateThread(codeOnly("CreateThread(t, fn, arg)"))

    test "threads start through spawnThread outside the listed places":
      let allowed = toHashSet(DirectCreateThread)
      var offenders: seq[string]
      for path in walkDirRec("src"):
        if not path.endsWith(".nim"): continue
        let rel = path.replace('\\', '/')
        if rel in allowed: continue
        if callsCreateThread(codeOnly(readFile(path))):
          offenders.add rel
      if offenders.len > 0:
        echo "createThread outside the allowed list (use spawnThread): ",
             offenders.join(", ")
      check offenders.len == 0

    test "every allowed place still exists":
      for path in DirectCreateThread:
        check fileExists(path)

when isMainModule:
  runTests()
