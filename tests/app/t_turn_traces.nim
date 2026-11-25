## Writing per-turn traces: opt-in, one private file per UTC day, old days
## removed when a new day starts.

import std/[os, posix, strutils, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/app/turn_traces
import donkey/config/environment
import donkey/core/pipeops
import donkey/domain/turn_trace_pure

const Home = "/tmp/donkey_t_turn_traces"
const Now = 1_800_000_000_000'i64   ## 2027-01-15, UTC

proc runTests*() =
  suite "turn traces on disk":
    setup:
      removeDir(Home)
      createDir(Home)

    test "off unless DONKEY_TRACES is on; retention from DONKEY_TRACES_DAYS":
      check not tracesEnabled(environmentOf({"X": "1"}))
      check tracesEnabled(environmentOf({"DONKEY_TRACES": "on"}))
      check tracesEnabled(environmentOf({"DONKEY_TRACES": "1"}))
      check traceRetentionDays(environmentOf({"X": "1"})) == 14
      check traceRetentionDays(environmentOf({"DONKEY_TRACES_DAYS": "3"})) == 3
      check traceRetentionDays(environmentOf({"DONKEY_TRACES_DAYS": "x"})) == 14

    test "lines of one day go to one private file":
      let fs = newFsAdapter()
      check appendTurnTrace(fs, Home, TurnTrace(startedMs: Now, userId: "u", outcome: "ok"),
                            Now, days = 14).isOk
      check appendTurnTrace(fs, Home, TurnTrace(startedMs: Now + 1, userId: "u", outcome: "ok"),
                            Now + 1, days = 14).isOk
      let path = Home / "state" / "traces" / "2027-01-15.jsonl"
      check readFile(path).strip.splitLines.len == 2
      var st: Stat
      check stat(path.cstring, st) == 0
      check (st.st_mode.int and 0o777) == 0o600

    test "a new day removes the days past the retention":
      let fs = newFsAdapter()
      createDir(Home / "state" / "traces")
      writeFile(Home / "state" / "traces" / "2026-12-01.jsonl", "{}\n")
      writeFile(Home / "state" / "traces" / "2027-01-10.jsonl", "{}\n")
      check appendTurnTrace(fs, Home, TurnTrace(startedMs: Now, outcome: "ok"), Now, days = 14).isOk
      check not fileExists(Home / "state" / "traces" / "2026-12-01.jsonl")
      check fileExists(Home / "state" / "traces" / "2027-01-10.jsonl")

when isMainModule:
  runTests()
