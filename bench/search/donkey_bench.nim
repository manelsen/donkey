## donkey_bench — Donkey's side of the conversation-search benchmark.
##
##   donkey_bench prompt <paddock>   prints {"system": …, "tools": […]}: the
##                                   system prompt and tool list a turn sends,
##                                   built by the same functions the
##                                   orchestrator uses, with the paddock's
##                                   USER.md / MEMORY.md / PREFERENCES.md as
##                                   the "relevant memory" block
##   donkey_bench serve              reads {"paddock": …, "args": {…}} per line,
##                                   runs the real `session_search` through
##                                   `executeNativeTool`, prints {"out": …}
##
## Not part of the build; compiled by bench/search/bancada.py.

import std/[json, os, strutils]
import chronos
import chronos/asyncsync
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/memory/md_file
import donkey/app/native_tools
import donkey/app/prompt_building
import donkey/app/session_bootstrap
import donkey/app/session_state
import donkey/core/log
import donkey/core/types
import donkey/domain/message
import donkey/domain/personality

const AgentName = "Donkey"

proc readOrEmpty(path: string): string =
  if fileExists(path): readFile(path) else: ""

proc promptCmd(paddock: string) =
  let tools = nativeSessionTools()
  let system = buildSystemBase(PersonalityTraits(), AgentName, orchToolsSuffix(tools))
  ## The memory agent's context: USER.md, MEMORY.md, PREFERENCES.md joined.
  let context = @[readOrEmpty(paddock / "USER.md"), readOrEmpty(paddock / "MEMORY.md"),
                  readOrEmpty(paddock / "PREFERENCES.md")].join("\n")
  let req = buildPrompt(system, newHistory(), context, tools)
  var arr = newJArray()
  for t in tools:
    arr.add(%*{"type": "function", "function": {
      "name": t.name, "description": t.description,
      "parameters": parseJson(t.schemaJson)}})
  echo $(%*{"system": req.system, "tools": arr})

proc serveCmd() =
  let log = newLogger("bench", lvlError)
  let outbox = newAsyncQueue[OutboundMessage]()
  var line = ""
  while stdin.readLine(line):
    var outText = ""
    try:
      let j = parseJson(line)
      let paddock = j["paddock"].getStr
      let adapter = MdFileAdapter(paddocksDir: paddock.parentDir)
      let ctx = NativeCtx(uid: UserId(paddock.extractFilename), channel: ckTelegram,
                          outbox: outbox, memory: adapter.toRuntimePort(),
                          fs: newFsAdapter(), log: log, paddockDir: paddock)
      let res = waitFor executeNativeTool(ToolCallRequest(id: "b", name: "session_search",
        inputJson: $j["args"]), ctx, newSessionState(), @[])
      outText = res.text
    except CatchableError as e:
      outText = "Error: " & e.msg
    stdout.writeLine($(%*{"out": outText}))
    stdout.flushFile()

when isMainModule:
  let args = commandLineParams()
  if args.len >= 2 and args[0] == "prompt": promptCmd(args[1])
  elif args.len >= 1 and args[0] == "serve": serveCmd()
  else: quit("usage: donkey_bench prompt <paddock> | serve", 2)
