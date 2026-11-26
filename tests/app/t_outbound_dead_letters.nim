## The outbound runtime and the dead letter box (second round, front 4): a
## send the channel refuses is kept; a channel that is not configured is not
## (retrying cannot help); the same ports send the retries.

import std/[os, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/app/dead_letters
import donkey/app/outbound_runtime
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/channel

let quiet = newLogger("test.outbound_dlq", lvlError)

proc portsWith(sendFn: proc(m: OutboundMessage): Result[void, string] {.gcsafe.}): OutboundChannelPorts =
  result.telegram = OutboundChannelPort(send: sendFn)

var n = 0
proc box(): DeadLetterBox =
  inc n
  let dir = getTempDir() / ("donkey_out_dlq_" & $n)
  removeDir(dir)
  newDeadLetterBox(newFsAdapter(), dir / "dead_letters.json")

proc reply(): OutboundMessage =
  OutboundMessage(userId: UserId("u-1"), channel: ckTelegram, text: "oi", replyTo: "1")

proc runTests*() =
  suite "outbound dead letters":

    test "a refused send is kept":
      let b = box()
      let ports = portsWith(proc(m: OutboundMessage): Result[void, string] {.gcsafe.} = err("HTTP 502"))
      sendImmediateOutbound(reply(), ports, quiet, deadLetters = b)
      check b.letters.len == 1 and b.letters[0].lastError == "HTTP 502"

    test "a channel that is not configured is not kept":
      let b = box()
      sendImmediateOutbound(reply(), OutboundChannelPorts(), quiet, deadLetters = b)
      check b.letters.len == 0

    test "a send that goes through keeps nothing; retries use the same ports":
      let b = box()
      var sent = 0
      let ports = portsWith(proc(m: OutboundMessage): Result[void, string] {.gcsafe.} =
        {.cast(gcsafe).}: inc sent
        ok())
      sendImmediateOutbound(reply(), ports, quiet, deadLetters = b)
      check b.letters.len == 0 and sent == 1
      check sendThroughPorts(reply(), ports).isOk and sent == 2
      check sendThroughPorts(reply(), OutboundChannelPorts()).isErr

when isMainModule:
  runTests()
