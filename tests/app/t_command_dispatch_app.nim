## The application command dispatcher, run against fake ports: no adapter,
## no file on disk.
##
## Contract: the dispatcher decides *what* to answer (topic, text, visibility)
## and performs session-task side effects; each channel only decides *how* to
## present the outcome.

import std/[strutils, unittest]
import chronos/asyncsync
import donkey/core/pipeops
import donkey/core/commands/command_routing
import donkey/core/commands/command_outcome
import donkey/core/commands/command_text
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/channel_capability
import donkey/ports/command_services
import donkey/ports/link_codes
import donkey/app/session_manager
import donkey/app/command_dispatch

type Probe = ref object
  saved: seq[(string, string)]
  linked: seq[(string, string)]
  stoppedAtEnsure: bool
  ensured: seq[TaskKind]

proc fakeServices(p: Probe; memoryFails = false): CommandServicesPort =
  CommandServicesPort(
    about: proc(u: UserId; n: int): Result[string, string] {.gcsafe.} =
      ok("about " & $n),
    doctor: proc(u: UserId; n: int): Result[string, string] {.gcsafe.} =
      ok("doctor"),
    status: proc(u: UserId; n: int): Result[string, string] {.gcsafe.} =
      ok("status"),
    ping: proc(u: UserId): Result[string, string] {.gcsafe.} =
      ok("pong"),
    memoryView: proc(u: UserId): Result[string, string] {.gcsafe.} =
      if memoryFails: err("permission denied") else: ok("memories"),
    clearMemory: proc(u: UserId): Result[void, string] {.gcsafe.} = ok(),
    skill: proc(u: UserId; v: string): Result[string, string] {.gcsafe.} =
      ok("skill " & v),
    models: proc(u: UserId; v: string): Result[string, string] {.gcsafe.} =
      if v == "bad": err("Provider inválido: `bad`.") else: ok("models"),
    think: proc(u: UserId; v: string): Result[string, string] {.gcsafe.} =
      ok("think"),
    budget: proc(u: UserId; v: string): Result[string, string] {.gcsafe.} =
      ok("budget"),
    channelPrefs: proc(u: UserId): Result[ChannelPrefs, string] {.gcsafe.} =
      ok(defaultChannelPrefs()),
    savePreference: proc(u: UserId; k, v: string): Result[void, string] {.gcsafe.} =
      {.cast(gcsafe).}: p.saved.add((k, v))
      ok(),
    toolCounts: proc(): ToolCounts {.gcsafe.} =
      ToolCounts(tools: 3, clients: 1),
  )

proc fakeLinks(p: Probe): IdentityLinkPort =
  IdentityLinkPort(
    mint: proc(u: UserId): string {.gcsafe.} = "ABC123",
    link: proc(code: string; ch: ChannelKind; raw: string): bool {.gcsafe.} =
      {.cast(gcsafe).}: p.linked.add((code, raw))
      code == "ABC123",
  )

proc request(p: Probe; kind: CommandKind; value = "";
             channel = ckFeishu): CommandDispatchRequest =
  CommandDispatchRequest(
    command: newCommandDecision(kind, value), userId: UserId("u-1"),
    channel: channel, messageId: "m-1", rawId: "raw-1", links: fakeLinks(p))

proc runTests*() =
  suite "dispatchCommand":
    setup:
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let p = Probe()
      let env = CommandEnv(services: fakeServices(p))

    test "plain text and callbacks fall back to the session":
      check dispatchCommand(env, sm, msgSeq, request(p, cmdNone)).kind == cokFallback
      check dispatchCommand(env, sm, msgSeq, request(p, cmdCallback, "x")).kind == cokFallback

    test "about/start/help/status/ping produce replies with their topic":
      for (kind, topic) in [(cmdAbout, rtAbout), (cmdStart, rtStartIntro),
                            (cmdHelp, rtHelp), (cmdStatus, rtStatus),
                            (cmdPing, rtPing)]:
        let o = dispatchCommand(env, sm, msgSeq, request(p, kind))
        check o.kind == cokReply
        check o.reply.topic == topic
        check o.reply.text.len > 0

    test "/agents asks the port for the tool counts":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdAgents))
      check o.reply.topic == rtUi
      check "3 carregadas" in o.reply.text
      check "1 conectados" in o.reply.text

    test "/mycode mints through the link port and is requester-only":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdMyCode))
      check o.reply.topic == rtLinkCode
      check "ABC123" in o.reply.text
      check o.reply.visibility == rvRequesterOnly

    test "/continue links the speaker's raw id":
      let good = dispatchCommand(env, sm, msgSeq, request(p, cmdContinue, "ABC123"))
      check not good.reply.failed
      check p.linked == @[("ABC123", "raw-1")]
      let bad = dispatchCommand(env, sm, msgSeq, request(p, cmdContinue, "NOPE42"))
      check bad.reply.failed
      check bad.reply.visibility == rvRequesterOnly

    test "doctor, memory and whoami are requester-only":
      for kind in [cmdDoctor, cmdMemory, cmdWhoami]:
        check dispatchCommand(env, sm, msgSeq, request(p, kind)).reply.visibility ==
          rvRequesterOnly

    test "an unreadable memory yields an error reply, not an exception":
      let failing = CommandEnv(services: fakeServices(p, memoryFails = true))
      let o = dispatchCommand(failing, sm, msgSeq, request(p, cmdMemory))
      check o.kind == cokReply
      check o.reply.failed
      check "permission denied" in o.reply.text

    test "a UI command error is told to the user":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdModels, "bad"))
      check o.reply.topic == rtUi
      check o.reply.failed
      check "Provider inválido" in o.reply.text

    test "/reasoning toggles the preference on every channel":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdReasoning))
      check o.reply.topic == rtReasoning
      check p.saved == @[("reasoning", "off")]

    test "/whoami answers on every channel with the speaker's raw id":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdWhoami))
      check o.reply.topic == rtWhoami
      check "raw-1" in o.reply.text

    test "/allowlist stays with the session instead of answering with /status":
      check dispatchCommand(env, sm, msgSeq, request(p, cmdAllowlist)).kind == cokFallback

    test "/whoami shows the real session id":
      let entry = sm.getOrCreate(UserId("u-1"))
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdWhoami))
      check entry.sessionId.len > 0
      check entry.sessionId in o.reply.text
      check "`active`" notin o.reply.text

  suite "dispatchCommand: session tasks":
    setup:
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let p = Probe()
      let env = CommandEnv(services: fakeServices(p))

    test "without a live session the no-session text is per command":
      let compact = dispatchCommand(env, sm, msgSeq, request(p, cmdCompact))
      check compact.reply.topic == rtNoSession
      check compact.reply.text == noSessionText(cmdCompact)
      check "reiniciar" notin compact.reply.text
      check msgSeq == 0

    test "with a live session the task is enqueued and accepted":
      discard sm.getOrCreate(UserId("u-1"))
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdReset))
      check o.kind == cokAccepted
      check o.task == cmdReset
      check msgSeq == 1
      check sm.getOrCreate(UserId("u-1")).inbox.len == 1

    test "/stop on a busy non-Telegram session interrupts the turn":
      discard sm.getOrCreate(UserId("u-1"))
      let before = currentUserInterrupt("u-1")
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdStop, channel = ckSlack))
      check o.kind == cokAccepted
      check isUserStoppedSince("u-1", before)
      check sm.getOrCreate(UserId("u-1")).inbox.len == 1

    test "the stop flag is set before the task is enqueued":
      var req = request(p, cmdStop, channel = ckDiscord)
      req.sessionMode = smCreate
      let before = currentUserInterrupt("u-1")
      req.ensureSession = proc(kind: TaskKind; payload: string) {.gcsafe.} =
        {.cast(gcsafe).}:
          p.stoppedAtEnsure = isUserStoppedSince("u-1", before)
          p.ensured.add(kind)
      check dispatchCommand(env, sm, msgSeq, req).kind == cokAccepted
      check p.stoppedAtEnsure
      check p.ensured == @[tkStop]

    test "non-interrupting tasks leave the running turn alone":
      discard sm.getOrCreate(UserId("u-1"))
      let before = currentUserInterrupt("u-1")
      discard dispatchCommand(env, sm, msgSeq, request(p, cmdCompact))
      check not isUserStoppedSince("u-1", before)

    test "create mode starts a session when there is none":
      var req = request(p, cmdDebug, channel = ckTelegram)
      req.sessionMode = smCreate
      let o = dispatchCommand(env, sm, msgSeq, req)
      check o.kind == cokAccepted
      check sm.hasLiveSession(UserId("u-1"))
      check msgSeq == 1

  suite "dispatchCommand: channel capabilities":
    setup:
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let p = Probe()
      let env = CommandEnv(services: fakeServices(p))

    test "every command listed in help is answered on every channel":
      for channel in ChannelKind:
        for kind in helpCommandKinds(commandCaps(channel)):
          let o = dispatchCommand(env, sm, msgSeq, request(p, kind, channel = channel))
          check o.kind != cokFallback
          if o.kind == cokReply:
            check o.reply.topic != rtUnsupported
            if o.reply.topic == rtUnsupported:
              checkpoint($channel & " lists " & $kind)

    test "/config is unsupported where there is no config view":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdConfig, channel = ckFeishu))
      check o.reply.topic == rtUnsupported
      check "/config" notin helpTextFor(ckFeishu, interactiveUi = false)

    test "the /config text fallback names commands, not buttons":
      let o = dispatchCommand(env, sm, msgSeq, request(p, cmdConfig, channel = ckSlack))
      check o.reply.topic == rtConfig
      check "botões" notin o.reply.text
      check "/models" in o.reply.text
      check "/think" in o.reply.text
      check "/budget" in o.reply.text

    test "help keeps /config on channels with a config view":
      check "/config" in helpTextFor(ckDiscord, interactiveUi = true)

when isMainModule:
  runTests()
