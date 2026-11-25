## The turn journal on disk: one private file per turn in flight under
## `state/turns/`, gone when the turn ends (PRD-roadmap E1).

import std/[os, unittest]
when defined(posix):
  import std/posix
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/turn_journal_pure
import donkey/ports/turn_journal
import donkey/adapters/state/turn_journal_store

proc rec(id: string; startedMs = 1_000'i64): TurnRecord =
  TurnRecord(id: id, userId: "u-1", channel: ckTelegram, replyTo: "1:2",
             payload: "p", preview: "oi", startedMs: startedMs)

proc freshDir(name: string): string =
  result = getTempDir() / "donkey-turn-journal" / name
  removeDir(result)

proc runTests*() =
  suite "turn journal store":

    test "a turn that ends leaves nothing behind":
      let dir = freshDir("ends")
      defer: removeDir(dir)
      let journal = turnJournalPort(newTurnJournalStore(dir))
      check journal.hasTurnJournal
      check journal.begin(rec("1-a")).isOk
      check fileExists(dir / journalFileName("1-a"))
      check journal.finish("1-a").isOk
      check turnJournalPort(newTurnJournalStore(dir)).pending().get.len == 0
      check not fileExists(dir / journalFileName("1-a"))

    test "a turn in flight is what the next process finds, effects included":
      let dir = freshDir("crash")
      defer: removeDir(dir)
      block:
        let journal = turnJournalPort(newTurnJournalStore(dir))
        check journal.begin(rec("1-a")).isOk
        check journal.markEffect("1-a", "fs_write").isOk
        check journal.markEffect("1-a", "bash").isOk
        check journal.begin(rec("2-b", 2_000)).isOk
        check journal.finish("2-b").isOk
      ## A new store: nothing of the old one in memory.
      let found = turnJournalPort(newTurnJournalStore(dir)).pending()
      check found.isOk
      check found.get.len == 1
      check found.get[0].id == "1-a"
      check found.get[0].effects == @["fs_write", "bash"]

    test "the file is readable only by the daemon's user":
      when defined(posix):
        let dir = freshDir("mode")
        defer: removeDir(dir)
        let journal = turnJournalPort(newTurnJournalStore(dir))
        check journal.begin(rec("1-a")).isOk
        var st: Stat
        check stat((dir / journalFileName("1-a")).cstring, st) == 0
        check (st.st_mode.int and 0o777) == 0o600
        check stat(dir.cstring, st) == 0
        check (st.st_mode.int and 0o777) == 0o700

    test "an effect on a turn the store does not know is an error":
      let dir = freshDir("unknown")
      defer: removeDir(dir)
      let journal = turnJournalPort(newTurnJournalStore(dir))
      check journal.markEffect("nope", "bash").isErr

    test "an effect already written is not written again":
      let dir = freshDir("once")
      defer: removeDir(dir)
      let store = newTurnJournalStore(dir)
      let journal = turnJournalPort(store)
      check journal.begin(rec("1-a")).isOk
      check journal.markEffect("1-a", "bash").isOk
      let before = store.writes
      check journal.markEffect("1-a", "bash").isOk
      check store.writes == before

    test "a damaged file is set aside, and the others still come back":
      let dir = freshDir("damaged")
      defer: removeDir(dir)
      let journal = turnJournalPort(newTurnJournalStore(dir))
      check journal.begin(rec("1-a")).isOk
      writeFile(dir / "2-b.json", "{broken")
      writeFile(dir / "notes.txt", "not a turn")
      let found = turnJournalPort(newTurnJournalStore(dir)).pending()
      check found.isOk
      check found.get.len == 1 and found.get[0].id == "1-a"
      check fileExists(dir / "2-b.json.bad")
      check not fileExists(dir / "2-b.json")
      check fileExists(dir / "notes.txt")

    test "an unreadable file is set aside without hiding the others":
      when defined(posix):
        if getuid() != 0:   ## root reads a 000 file anyway
          let dir = freshDir("unreadable")
          defer: removeDir(dir)
          let journal = turnJournalPort(newTurnJournalStore(dir))
          check journal.begin(rec("1-a")).isOk
          check journal.begin(rec("2-b")).isOk
          check chmod((dir / "2-b.json").cstring, 0) == 0
          let found = turnJournalPort(newTurnJournalStore(dir)).pending()
          check found.isOk
          check found.get.len == 1 and found.get[0].id == "1-a"
          check fileExists(dir / "2-b.json.bad")

    test "this process's own turns in flight are not interrupted ones":
      let dir = freshDir("own")
      defer: removeDir(dir)
      let journal = turnJournalPort(newTurnJournalStore(dir))
      check journal.begin(rec("1-a")).isOk
      check journal.pending().get.len == 0

    test "no directory yet means no turn in flight":
      let dir = freshDir("none")
      let found = turnJournalPort(newTurnJournalStore(dir)).pending()
      check found.isOk and found.get.len == 0

    test "an empty port says so":
      check not TurnJournalPort().hasTurnJournal

when isMainModule:
  runTests()
