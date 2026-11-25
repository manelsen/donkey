## The turn journal: what a turn in flight leaves behind if the daemon dies,
## and what the next start does with it (PRD-roadmap E1).

import std/[strutils, unicode, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/turn_journal_pure

const Hour = 3_600_000'i64

proc sample(): TurnRecord =
  TurnRecord(id: newTurnId(1_800_000_000_000, "u-1", "u-1-7"), userId: "u-1",
             channel: ckTelegram, replyTo: "123:456", payload: """{"text":"oi"}""",
             preview: "resume o relatório", startedMs: 1_800_000_000_000)

proc runTests*() =
  suite "turn journal":

    test "a tool is an effect unless it only reads":
      for name in ["session_search", "web_search", "fs_read", "read_file",
                   "grep", "calc", "current_time", "inspect_image"]:
        check not isEffectfulTool(name)
      for name in ["fs_write", "bash", "edit_file", "schedule_reminder",
                   "manage_schedules", "spawn_subagent", "execute_code"]:
        check isEffectfulTool(name)

    test "a tool nobody knows counts as an effect":
      check isEffectfulTool("mcp_server__send_email")
      check isEffectfulTool("")

    test "each effect is kept once, in order":
      let r = sample().withEffect("fs_write").withEffect("bash").withEffect("fs_write")
      check r.effects == @["fs_write", "bash"]

    test "a record survives the file round trip":
      let r = sample().withEffect("bash")
      let back = parseTurnRecord(recordJson(r))
      check back.isOk
      check back.get == r

    test "a damaged file is refused, not guessed":
      check parseTurnRecord("").isErr
      check parseTurnRecord("{not json").isErr
      check parseTurnRecord("""{"id":"x"}""").isErr
      check parseTurnRecord("""{"id":"x","user":"u","channel":"pigeon","started_ms":1}""").isErr

    test "turn ids make safe file names":
      let id = newTurnId(1_800_000_000_000, "../etc/passwd", "a b/c")
      for c in id:
        check c in {'a'..'z', 'A'..'Z', '0'..'9', '-'}
      check journalFileName(id) == id & ".json"
      check turnIdOfFile(journalFileName(id)) == id
      check turnIdOfFile("notes.txt") == ""
      check turnIdOfFile(".json") == ""

    test "two turns of one user in the same millisecond get different ids":
      check newTurnId(5, "u-1", "u-1-1") != newTurnId(5, "u-1", "u-1-2")

    test "a turn that did nothing yet is replayed":
      check decideRecovery(sample(), nowMs = sample().startedMs + Hour) == rcReplay

    test "a turn that had an effect is never replayed":
      let r = sample().withEffect("fs_write")
      check decideRecovery(r, nowMs = r.startedMs + 1) == rcNotify

    test "a turn already replayed once is not replayed again":
      var r = sample()
      r.resumes = 1
      check decideRecovery(r, nowMs = r.startedMs + 1) == rcNotify

    test "a turn older than a day only gets the notice":
      let r = sample()
      check decideRecovery(r, nowMs = r.startedMs + 24 * Hour + 1) == rcNotify
      check decideRecovery(r, nowMs = r.startedMs + 24 * Hour) == rcReplay

    test "the notice names the message and what was already done":
      let text = interruptedNotice(sample().withEffect("fs_write").withEffect("bash"))
      check "resume o relatório" in text
      check "fs_write" in text and "bash" in text
      check "continue" in text

    test "the notice without effects asks for the message again":
      var r = sample()
      r.resumes = 1
      let text = interruptedNotice(r)
      check "resume o relatório" in text
      check "fs_write" notin text

    test "the preview is clipped on a character boundary":
      let p = turnPreview("ação ".repeat(40))
      check p.len <= PreviewMaxBytes + "…".len
      check p.endsWith("…")
      check p.validateUtf8 == -1
      check turnPreview("  curto  ") == "curto"
      check turnPreview("linha um\nlinha dois") == "linha um linha dois"

when isMainModule:
  runTests()
