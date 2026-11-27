## E12.3: a channel run as its own process, under the supervisor.

import std/[os, strutils, unittest]
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/supervision_pure
import donkey/domain/channels/channel_wire
import donkey/infra/connection_state
import donkey/infra/event_queue
import donkey/infra/channel_process

var gGot = initEventQueue[string]("test.got", capacity = 64)
var gOut = initEventQueue[string]("test.out", capacity = 64)

proc sink(payload: string) {.nimcall, gcsafe, raises: [].} = gGot.push(payload)
proc source(): (bool, string) {.nimcall, gcsafe, raises: [].} = gOut.tryTake()

const Fast = RestartPolicy(kind: rkPermanent, maxRestarts: 3, withinMs: 60_000,
                           baseBackoffMs: 50, maxBackoffMs: 200, coolOffMs: 60_000)

proc shSpec(script: string): ChannelProcessSpec =
  ChannelProcessSpec(name: "irc", channel: ckIrc, command: "/bin/sh", args: @["-c", script])

proc waitUntil(cond: proc(): bool; ms = 5_000): bool =
  var waited = 0
  while waited < ms:
    if cond(): return true
    sleep(20); waited += 20
  cond()

proc frame(k: WireKind; p = ""): string = quoteShell(encodeFrame(WireFrame(kind: k, payload: p)))

proc runTests*() =
  suite "channel process (E12.3)":
    setup:
      resetConnections()

    test "the child's events reach the daemon; its connection is counted here":
      var p = startChannelProcess(shSpec("printf '%s\\n%s\\n' " & frame(wfUp) & " " &
                                         frame(wfEvent, """{"text":"oi"}""") & "; sleep 30"),
                                  sink, source, newLogger("t", lvlError), Fast).get
      var got = ""
      check waitUntil(proc(): bool =
        let (ok, v) = gGot.tryTake()
        if ok: got = v
        ok)
      check got == """{"text":"oi"}"""
      check waitUntil(proc(): bool = connectionCounts(ckIrc).connected == 1)
      p.stop()
      check connectionCounts(ckIrc) == (running: 0, connected: 0)

    test "an outbound line reaches the child as a frame on its stdin":
      let path = getTempDir() / "donkey_t_channel_process.out"
      removeFile(path)
      gOut.push("PRIVMSG #a :olá")
      var p = startChannelProcess(shSpec("read l; printf '%s' \"$l\" > " & quoteShell(path) &
                                         "; sleep 30"),
                                  sink, source, newLogger("t", lvlError), Fast).get
      check waitUntil(proc(): bool = fileExists(path) and readFile(path).len > 0)
      let back = decodeFrame(readFile(path))
      check back.isOk and back.get == WireFrame(kind: wfOut, payload: "PRIVMSG #a :olá")
      p.stop()

    test "a child that dies (a Defect, say) is restarted, then down past the intensity":
      let path = getTempDir() / "donkey_t_channel_process.count"
      removeFile(path)
      var p = startChannelProcess(shSpec("echo x >> " & quoteShell(path) & "; exit 1"),
                                  sink, source, newLogger("t", lvlError), Fast).get
      check waitUntil(proc(): bool = supervisionOf(ckIrc) == csDown)
      check readFile(path).countLines >= 4   ## the first run and three restarts
      p.stop()

when isMainModule:
  runTests()
