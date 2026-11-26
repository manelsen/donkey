## /insights in the chat (open item of E7.8): the insights tool gives a
## person their own report, from the traces, only their turns.

import std/[os, strutils, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/app/insights_tool
import donkey/app/learned_skills
import donkey/core/pipeops

proc line(user: string; tool = "web_search"): string =
  """{"ts":1,"duration_ms":10,"user":"""" & user & """","channel":"cli","kind":"user","session":"s","provider":"openrouter","streamed":false,"tools":[{"name":"""" & tool & """","outcome":"output"}],"tokens":{"input":100,"output":10},"outcome":"ok"}"""

proc runTests*() =
  suite "insights tool":

    test "a person's report counts only their own turns":
      let h = getTempDir() / "donkey_insights_tool"
      removeDir(h)
      createDir(h / "paddocks" / "u1")
      createDir(h / "state" / "traces")
      writeFile(h / "state" / "traces" / "2026-11-26.jsonl",
                line("u1") & "\n" & line("u2", "bash") & "\n" & line("u1") & "\n")
      discard newLearnedSkills(newFsAdapter(), h / "paddocks" / "u1").create(
        "---\nname: deploy\ndescription: d\n---\nsteps\n", by = "review", nowMs = 1)
      let r = performInsights(newFsAdapter(), h / "paddocks" / "u1", "u1", sinceMs = 0)
      check r.isOk
      check "2 turns" in r.get and "web_search" in r.get
      check "bash" notin r.get
      check "deploy" in r.get

    test "no traces: says how to get them":
      let h = getTempDir() / "donkey_insights_tool_empty"
      removeDir(h)
      createDir(h / "paddocks" / "u1")
      check "DONKEY_TRACES" in performInsights(newFsAdapter(), h / "paddocks" / "u1", "u1", 0).get

when isMainModule:
  runTests()
