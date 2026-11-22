## Native tool arguments: what the parsers accept, refuse and default, with
## no file system involved (paths come back as the model wrote them).

import std/[json, options, unittest]
import donkey/core/pipeops
import donkey/core/tooling/native_tool_args

proc runTests*() =
  suite "native tool args — field readers":
    test "a required string must be present and non-empty":
      check parseJson("""{"k": "v"}""").requireStringField("k").get == "v"
      check parseJson("""{"k": ""}""").requireStringField("k").isErr
      check parseJson("{}").requireStringField("k").error == "Error: 'k' is required."

    test "optional fields default when absent and refuse other types":
      let j = parseJson("""{"i": 3, "b": false, "s": "x", "bad": "3"}""")
      check optionalIntField(j, "i").get == 3
      check optionalIntField(j, "missing").get == 0
      check optionalIntField(j, "bad").isErr
      check optionalBoolField(j, "b", true).get == false
      check optionalBoolField(j, "missing", true).get == true
      check optionalStringField(j, "s").get == "x"
      check optionalStringField(j, "i").isErr

    test "string arrays are trimmed and deduplicated":
      let j = parseJson("""{"a": [" x ", "y", "x", ""], "n": [1]}""")
      check stringArrayField(j, "a").get == @["x", "y"]
      check stringArrayField(j, "n").isErr
      check stringArrayField(j, "missing").get.len == 0

  suite "native tool args — a missing array field is an error, not a crash":
    ## `getOrDefault` returns nil for a missing field, and reading `.kind` of
    ## nil is a SIGSEGV that no `except` catches: a model that left out
    ## `edits`, `job_ids` or `ops` used to take the whole daemon down.
    test "edit_file without edits":
      check parseEditFileArgs(parseJson("""{"path": "a.md"}""")).error ==
        "Error: 'edits' must be an array."

    test "edit with no lines field":
      let res = parseEditFileArgs(parseJson(
        """{"path": "a.md", "edits": [{"op": "append"}]}"""))
      check res.isOk
      check res.get.edits[0].lines.len == 0

    test "await without job_ids":
      check parseAwaitContext(parseJson("{}")).error ==
        "Error: 'job_ids' must be an array."

    test "todo without ops":
      check parseTodoOps(parseJson("{}")).error == "Error: 'ops' must be an array."

  suite "native tool args — file tools keep the raw path":
    test "read_file defaults and clamps its window":
      let ctx = parseReadFileArgs(parseJson(
        """{"path": "../x", "start_line": -4}""")).get
      check ctx.path == "../x"
      check ctx.startLine == 1
      check ctx.maxLines == 200

    test "grep needs a pattern and a path":
      check parseGrepArgs(parseJson("""{"path": "."}""")).error ==
        "Error: 'pattern' is required."
      let ctx = parseGrepArgs(parseJson("""{"pattern": "a", "path": "."}""")).get
      check ctx.recursive
      check ctx.max == 50

    test "cp/mv needs both ends":
      check parseCpMvArgs(parseJson("""{"source": "a"}""")).isErr
      check parseCpMvArgs(parseJson("""{"source": "a", "dest": "b"}""")).get.dest == "b"

  suite "native tool args — edit_file anchors":
    test "anchors parse with their aliases and reject bad lines":
      check parseHashlineAnchor("12#ABC: text").get == HashlineAnchor(line: 12, hash: "abc")
      check parseHashlineAnchor("0#abc").isErr
      check parseHashlineAnchor("x#abc").isErr
      check parseHashlineAnchor("12").isErr
      let ctx = parseEditFileArgs(parseJson("""{"path": "a", "edits": [
        {"op": "replace", "anchor": "1#aa", "to": "2#bb", "lines": ["x"]}]}""")).get
      check ctx.edits[0].pos.get.line == 1
      check ctx.edits[0].stop.get.hash == "bb"

    test "replace needs a position; unknown ops and non-string lines are refused":
      check parseEditFileArgs(parseJson(
        """{"path": "a", "edits": [{"op": "replace"}]}""")).isErr
      check parseEditFileArgs(parseJson(
        """{"path": "a", "edits": [{"op": "delete"}]}""")).isErr
      check parseEditFileArgs(parseJson(
        """{"path": "a", "edits": [{"op": "append", "lines": [1]}]}""")).isErr

  suite "native tool args — the rest":
    test "session search trims, bounds and defaults":
      check parseSessionSearchContext(parseJson("""{"query": "  "}""")).isErr
      let ctx = parseSessionSearchContext(parseJson("""{"query": " hi "}""")).get
      check ctx.query == "hi"
      check ctx.includeMemory

    test "memory ingest takes a path or a text, not both":
      check parseMemoryIngestContext(parseJson("""{"path": "a", "text": "b"}""")).isErr
      check parseMemoryIngestContext(parseJson("{}")).isErr
      check parseMemoryIngestContext(parseJson("""{"text": "b"}""")).isOk

    test "spawn_subagent needs a task and types its limits":
      check parseSpawnSubagentContext(parseJson("{}")).isErr
      check parseSpawnSubagentContext(parseJson(
        """{"task": "t", "max_tokens": "many"}""")).isErr
      let ctx = parseSpawnSubagentContext(parseJson(
        """{"task": "t", "tools": ["fs_read"], "wait": false}""")).get
      check ctx.request.tools == @["fs_read"]
      check not ctx.wait

    test "speech defaults to a file, not a voice note":
      let ctx = parseSpeechContext(parseJson("""{"text": "oi"}""")).get
      check not ctx.asVoice
      check parseSpeechContext(parseJson("""{"text": "oi", "as_voice": "yes"}""")).isErr

    test "manage_skills maps actions to the /skill text":
      check parseManageSkillsContext(parseJson("{}")).get.action == "help"
      let removal = parseManageSkillsContext(parseJson(
        """{"action": "remove", "name": "x"}""")).get
      check removal.action == "disable"
      check buildManageSkillsValue(removal) == "disable x"
      check buildManageSkillsValue(parseManageSkillsContext(parseJson(
        """{"action": "install", "slug": "s"}""")).get) == "install s"
      check parseManageSkillsContext(parseJson("""{"action": "search"}""")).isErr
      check parseManageSkillsContext(parseJson("""{"action": "nuke"}""")).isErr

    test "rewind defaults to the last checkpoint and checks the range":
      check parseRewindIndex(parseJson("{}"), 0).isErr
      check parseRewindIndex(parseJson("{}"), 3).get == 2
      check parseRewindIndex(parseJson("""{"index": 3}"""), 3).isErr

when isMainModule:
  runTests()
