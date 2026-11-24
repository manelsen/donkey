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
##   donkey_bench magma-seed <paddock> <sqlite> <corpus.jsonl>
##                                   fills a MAGMA SQLite graph the way
##                                   Donkey's automatic capture would have:
##                                   one memory per substantive turn
##   donkey_bench capture-check <corpus.jsonl>
##                                   prints {"skipped": [line index, …]}: the
##                                   user turns automatic capture would not
##                                   keep, by their position in the corpus
##   donkey_bench magma-rank <paddock> <sqlite> <k>
##                                   reads one question per line and prints
##                                   {"hits": [content, …]}: recall's top k,
##                                   in rank order, as the memory agent asks
##                                   for 8
##   donkey_bench magma-rank-policy <paddock> <sqlite> <k>
##                                   like magma-rank, but each line is
##                                   "policy<TAB>question": `temporal` or
##                                   `default`, the policy a router chose
##   donkey_bench magma-prompt <paddock> <sqlite>
##                                   reads one question per line and prints
##                                   {"system": …, "tools": […]} with the
##                                   memory agent's recall for that question
##
## MAGMA reads the embedding key (OPENROUTER_API_KEY) and the
## DONKEY_MEMORY_* knobs from the process environment.
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
import donkey/config/environment
import donkey/ports/memory
import donkey/domain/memory/capture_pure
import donkey/domain/memory/provenance_pure
import donkey/domain/memory/recall_pure
import donkey/adapters/memory/magma_memory_adapter
import donkey/adapters/memory/multigraph_runtime
import donkey/ports/multigraph_store
import donkey/domain/memory/query_policy_pure

const AgentName = "Donkey"

proc readOrEmpty(path: string): string =
  if fileExists(path): readFile(path) else: ""

proc promptJson(context: string): string =
  let tools = nativeSessionTools()
  let system = buildSystemBase(PersonalityTraits(), AgentName, orchToolsSuffix(tools))
  let req = buildPrompt(system, newHistory(), context, tools)
  var arr = newJArray()
  for t in tools:
    arr.add(%*{"type": "function", "function": {
      "name": t.name, "description": t.description,
      "parameters": parseJson(t.schemaJson)}})
  $(%*{"system": req.system, "tools": arr})

proc promptCmd(paddock: string) =
  ## The memory agent's context without a graph: USER.md, MEMORY.md and
  ## PREFERENCES.md joined.
  echo promptJson(@[readOrEmpty(paddock / "USER.md"), readOrEmpty(paddock / "MEMORY.md"),
                    readOrEmpty(paddock / "PREFERENCES.md")].join("\n"))

proc magmaMemory(paddock, sqlite: string): MdFileAdapter =
  MdFileAdapter(paddocksDir: paddock.parentDir, magmaSqlitePath: sqlite,
                magmaEnv: magmaEnvironment(readEnvironment()))

proc magmaSeedCmd(paddock, sqlite, corpus: string) =
  ## One memory per turn that Donkey's capture keeps (`shouldSkipAutoMemoryCapture`,
  ## `formatAutoMemoryEntry`, `turnOrigin`), written as `appendMemory` writes
  ## it except for the time: the turn's own, not the moment of seeding, so
  ## recall by time sees four months, not one minute.
  let memory = magmaMemory(paddock, sqlite)
  let uid = UserId(paddock.extractFilename)
  let magma = memory.newMagmaAdapter()
  if magma == nil: quit("MAGMA unavailable", 1)
  discard magma.saveUserMd(uid, readOrEmpty(paddock / "USER.md"))
  discard magma.savePreferences(uid, readOrEmpty(paddock / "PREFERENCES.md"))
  var records: seq[JsonNode]
  for line in lines(corpus):
    if line.strip.len > 0: records.add(parseJson(line))
  var stored, skipped = 0
  ## The temporal chain follows insertion order. `appendMemory` links to the
  ## node with the latest time, which in live use is the previous one (time
  ## only moves forward); a corpus whose sessions are not in date order
  ## (LongMemEval) would link many memories to the same one and make a hub.
  var prevId = ""
  proc put(text: string; ts: int64; session: string) =
    let nid = magma.memId(uid)
    let ok = magma.graph.insertNode(MagmaNode(
      id: nid, userId: $uid, nodeType: NtMemory, content: text,
      embedding: magma.embedFn(text), timestamp: ts,
      meta: originToMeta(turnOrigin(session))))
    if not ok: quit("graph refused " & nid, 1)
    if prevId.len > 0:
      magma.graph.linkTemporal(prevId, nid)
    prevId = nid
  ## The two profile notes of MEMORY.md, as memories from before the history.
  let first = if records.len > 0: records[0]["ts"].getBiggestInt div 1000 - 86400 else: 0
  for note in readOrEmpty(paddock / "MEMORY.md").splitLines:
    if note.startsWith("- "):
      put(note, first, "profile")
  var i = 0
  while i < records.len:
    let m = records[i]
    if m["role"].getStr == "user":
      let reply = if i + 1 < records.len and records[i + 1]["role"].getStr == "assistant":
                    records[i + 1]["text"].getStr else: ""
      if shouldSkipAutoMemoryCapture(m["text"].getStr, reply):
        inc skipped
      else:
        let at = if reply.len > 0: records[i + 1] else: m
        put(formatAutoMemoryEntry(m["text"].getStr, reply),
            at["ts"].getBiggestInt div 1000, at["session"].getStr)
        inc stored
        if stored mod 100 == 0:
          stderr.writeLine("seeded " & $stored)
    inc i
  echo $(%*{"stored": stored, "skipped": skipped})

proc magmaPromptCmd(paddock, sqlite: string) =
  ## What the memory agent builds for each question (`tkLoadCtx`): the
  ## graph's context, with the memory part replaced by the recall of 8
  ## memories for the question when there is any.
  let memory = magmaMemory(paddock, sqlite)
  let uid = UserId(paddock.extractFilename)
  let searchFn = buildGlobalMagmaSearchFn(memory)
  if searchFn == nil: quit("MAGMA search unavailable", 1)
  var question = ""
  while stdin.readLine(question):
    let ctx = memory.loadContext(uid)
    var memSection = ctx.memoryMd
    let recalled = renderRecall(searchFn(uid, question, 8))
    if recalled.len > 0:
      memSection = recalled
    stdout.writeLine(promptJson(@[ctx.userMd, memSection, ctx.preferencesMd].join("\n")))
    stdout.flushFile()

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

proc captureCheckCmd(corpus: string) =
  ## The same pairing and rule as `magma-seed`: a user turn with the reply
  ## right after it, kept unless `shouldSkipAutoMemoryCapture` says no.
  var records: seq[JsonNode]
  for line in lines(corpus):
    if line.strip.len > 0: records.add(parseJson(line))
  var skipped = newJArray()
  for i, m in records:
    if m["role"].getStr != "user": continue
    let reply = if i + 1 < records.len and records[i + 1]["role"].getStr == "assistant":
                  records[i + 1]["text"].getStr else: ""
    if shouldSkipAutoMemoryCapture(m["text"].getStr, reply):
      skipped.add(%i)
  echo $(%*{"skipped": skipped})
proc magmaRankCmd(paddock, sqlite: string; k: int) =
  let memory = magmaMemory(paddock, sqlite)
  let uid = UserId(paddock.extractFilename)
  let searchFn = buildGlobalMagmaSearchFn(memory)
  if searchFn == nil: quit("MAGMA search unavailable", 1)
  var question = ""
  while stdin.readLine(question):
    var arr = newJArray()
    for hit in searchFn(uid, question, k):
      arr.add(%hit.content)
    stdout.writeLine($(%*{"hits": arr}))
    stdout.flushFile()

proc magmaRankPolicyCmd(paddock, sqlite: string; k: int) =
  let memory = magmaMemory(paddock, sqlite)
  let uid = UserId(paddock.extractFilename)
  let magma = memory.newMagmaAdapter()
  if magma == nil: quit("MAGMA unavailable", 1)
  var line = ""
  while stdin.readLine(line):
    let tab = line.find('\t')
    let (route, question) = if tab < 0: ("default", line) else: (line[0 ..< tab], line[tab + 1 .. ^1])
    let policy = if route == "temporal": temporalPolicy() else: defaultPolicy()
    var arr = newJArray()
    for hit in magma.searchWithRerank(uid, question, k, nil, some(policy)):
      arr.add(%hit.content)
    stdout.writeLine($(%*{"hits": arr}))
    stdout.flushFile()

when isMainModule:
  let args = commandLineParams()
  if args.len >= 2 and args[0] == "prompt": promptCmd(args[1])
  elif args.len >= 1 and args[0] == "serve": serveCmd()
  elif args.len >= 4 and args[0] == "magma-seed": magmaSeedCmd(args[1], args[2], args[3])
  elif args.len >= 3 and args[0] == "magma-prompt": magmaPromptCmd(args[1], args[2])
  elif args.len >= 2 and args[0] == "capture-check": captureCheckCmd(args[1])
  elif args.len >= 4 and args[0] == "magma-rank": magmaRankCmd(args[1], args[2], parseInt(args[3]))
  elif args.len >= 4 and args[0] == "magma-rank-policy": magmaRankPolicyCmd(args[1], args[2], parseInt(args[3]))
  else: quit("usage: donkey_bench prompt <paddock> | serve | magma-seed <paddock> <sqlite> <corpus> | magma-prompt <paddock> <sqlite>", 2)
