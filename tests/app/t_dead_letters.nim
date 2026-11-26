## The dead letter box (second round, front 4): kept on disk, private,
## across restarts; retried when due through the send it is given; a retry
## that goes through takes the letter out, one that fails waits longer.

import std/[os, strutils, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/app/dead_letters
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/domain/dead_letters_pure

const Min = 60_000'i64

proc reply(text = "resposta"): OutboundMessage =
  OutboundMessage(userId: UserId("u-1"), channel: ckTelegram, text: text, replyTo: "42")

var n = 0
proc freshPath(): string =
  inc n
  let dir = getTempDir() / ("donkey_dlq_" & $n)
  removeDir(dir)
  dir / "state" / "dead_letters.json"

proc runTests*() =
  suite "dead letter box":

    test "a failed reply is kept on disk, readable only by the daemon's user":
      let path = freshPath()
      let box = newDeadLetterBox(newFsAdapter(), path)
      box.keep(reply(), "HTTP 502", 0)
      check fileExists(path)
      check getFilePermissions(path) == {fpUserRead, fpUserWrite}
      check newDeadLetterBox(newFsAdapter(), path).letters.len == 1

    test "what does not qualify is not kept":
      let box = newDeadLetterBox(newFsAdapter(), freshPath())
      var m = reply(); m.mediaUrl = "/x.png"
      box.keep(m, "e", 0)
      check box.letters.len == 0

    test "due letters are sent again; success removes, failure reschedules":
      let box = newDeadLetterBox(newFsAdapter(), freshPath())
      box.keep(reply("a"), "e", 0)
      box.keep(reply("b"), "e", 0)
      var sent: seq[string]
      let send = proc(m: OutboundMessage): Result[void, string] {.gcsafe.} =
        {.cast(gcsafe).}: sent.add m.text
        if m.text == "a": ok() else: err("still down")
      check box.retryDue(Min - 1, send) == 0
      check box.retryDue(Min, send) == 2
      check sent == @["a", "b"]
      check box.letters.len == 1 and box.letters[0].text == "b"
      check box.letters[0].attempts == 2 and box.letters[0].lastError == "still down"
      check newDeadLetterBox(newFsAdapter(), box.path).letters.len == 1   ## saved

    test "an unreadable file is kept aside, not overwritten with an empty list":
      let path = freshPath()
      createDir(parentDir(path))
      writeFile(path, "{broken")
      let box = newDeadLetterBox(newFsAdapter(), path)
      check box.problem.len > 0
      box.keep(reply(), "e", 0)
      check readFile(path) == "{broken"

  suite "dead letter box — what goes wrong":

    test "a file that exists but cannot be read is not overwritten":
      let path = freshPath()
      createDir(parentDir(path))
      writeFile(path, "[]")
      setFilePermissions(path, {})
      let box = newDeadLetterBox(newFsAdapter(), path)
      setFilePermissions(path, {fpUserRead, fpUserWrite})
      check box.problem.len > 0
      box.keep(reply(), "e", 0)
      check readFile(path) == "[]"

    test "a send that raises is a failed retry, and the box is still saved":
      let box = newDeadLetterBox(newFsAdapter(), freshPath())
      box.keep(reply("a"), "e", 0)
      box.keep(reply("b"), "e", 0)
      let send = proc(m: OutboundMessage): Result[void, string] {.gcsafe.} =
        if m.text == "a": raise newException(ValueError, "boom")
        ok()
      check box.retryDue(Min, send) == 2
      check box.letters.len == 1 and box.letters[0].text == "a" and "boom" in box.letters[0].lastError

when isMainModule:
  runTests()
