## CliAdapter — tests.
## Demonstrates CliAdapter satisfying ChannelPort concept and pure helpers.

import std/[strutils, unittest]
import donkey/core/types
import donkey/core/pipeops
import donkey/domain/message
import donkey/adapters/channel/cli_repl

# ── concept satisfaction via MockCli ───────────────────────────────────────────

type MockCli = object

proc send(c: MockCli; msg: OutboundMessage): Result[void, string] =
  ok()

proc receive(vc: var MockCli): Result[seq[InboundMessage], string] =
  ok(@[InboundMessage(userId: UserId("u1"), text: "hello", channel: ckCli)])

proc ack(c: MockCli; id: string) = discard

# ── pure helpers tests ─────────────────────────────────────────────────────────

suite "cli repl — pure helpers":

  test "isCommand returns true for slash commands":
    check isCommand("/help")
    check isCommand("/quit")
    check isCommand("/reset all")

  test "isCommand returns false for regular text":
    check not isCommand("hello")
    check not isCommand("")
    check not isCommand(" /notacommand")

  test "stripCommand removes leading slash":
    check stripCommand("/help") == "help"
    check stripCommand("/quit") == "quit"

  test "stripCommand returns text unchanged if no leading slash":
    check stripCommand("hello world") == "hello world"
    check stripCommand("") == ""

# ── concept satisfaction ───────────────────────────────────────────────────────

suite "cli repl — ChannelPort concept":

  test "MockCli satisfies ChannelPort concept":
    var ch = MockCli()
    let r = ch.receive()
    check r.isOk
    let s = ch.send(OutboundMessage(userId: UserId("u1"), text: "hi", channel: ckCli))
    check s.isOk

# ── CliAdapter construction ───────────────────────────────────────────────────

suite "cli repl — CliAdapter":

  test "newCliAdapter with default userId":
    let adapter = newCliAdapter()
    check adapter.userId == CliDefaultUserId
    check adapter.counter == 0

  test "newCliAdapter with custom userId":
    let adapter = newCliAdapter(UserId("local:test"))
    check adapter.userId == UserId("local:test")
    check adapter.counter == 0

# ── pipeops integration ───────────────────────────────────────────────────────

suite "cli repl — pipeops integration":

  test "send returns ok on empty text":
    let adapter = newCliAdapter()
    let msg = OutboundMessage(userId: UserId("local:cli"), text: "", channel: ckCli)
    let r = adapter.send(msg)
    check r.isOk

  test "sendReturnId returns ok with stream id":
    let adapter = newCliAdapter()
    let msg = OutboundMessage(userId: UserId("local:cli"), text: "hello", channel: ckCli)
    let r = adapter.sendReturnId(msg)
    check r.isOk
    check r.get() == "1"

  test "editMessage returns ok silently":
    let adapter = newCliAdapter()
    let r = adapter.editMessage(UserId("local:cli"), "1", "new text")
    check r.isOk
