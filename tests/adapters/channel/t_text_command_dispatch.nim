## Shared text-command dispatch used by every non-Telegram channel runtime.
##
## Contract: the dispatcher decides *what* to answer (topic + text + flags) and
## performs session-task side effects; each channel only decides *how* to
## present a reply (plain text, markdown, embed, ephemeral).

import std/[os, strutils, unittest]
import chronos/asyncsync
import donkey/core/pipeops
import donkey/core/commands/command_routing
import donkey/domain/message
import donkey/ports/provider
import donkey/adapters/memory/md_file
import donkey/adapters/identity/identity_resolver
import donkey/adapters/channel/common_runtime
import donkey/adapters/channel/text_command_dispatch
import donkey/app/session_manager

let tmpRoot = getTempDir() / ("donkey_text_command_dispatch_" & $getCurrentProcessId())

proc env(): CommandEnv =
  CommandEnv(
    memory: MdFileAdapter(paddocksDir: tmpRoot / "paddocks"),
    completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        ok(CompletionResponse(text: "pong")),
    modelCatalogLoader: proc(p: string): Result[ModelCatalogResult, string] {.gcsafe.} =
      ok(emptyCatalogResult()),
    toolsCount: 3,
    toolClientsCount: 1,
    daemonStartMs: 0,
  )

proc run(kind: CommandKind; value = ""; sm: var SessionManager;
         msgSeq: var int; resolver: IdentityResolver): CommandOutcome =
  dispatchTextCommand(env(), sm, msgSeq, newCommandDecision(kind, value),
                      UserId("u-1"), ckFeishu, "m-1", resolver, "raw-1")

proc runTests*() =
  suite "dispatchTextCommand":
    setup:
      removeDir(tmpRoot)
      createDir(tmpRoot)
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let resolver = newIdentityResolver(tmpRoot / "ids.tsv")

    test "plain text is not a command: caller falls back to the session":
      check run(cmdNone, "", sm, msgSeq, resolver).kind == cokFallback

    test "callbacks fall back too (channels with buttons route them first)":
      check run(cmdCallback, "x", sm, msgSeq, resolver).kind == cokFallback

    test "about/start/help/status/ping produce replies with their topic":
      for (kind, topic) in [(cmdAbout, rtAbout), (cmdStart, rtStartIntro),
                            (cmdHelp, rtHelp), (cmdStatus, rtStatus),
                            (cmdPing, rtPing)]:
        let o = run(kind, "", sm, msgSeq, resolver)
        check o.kind == cokReply
        check o.reply.topic == topic
        check o.reply.text.len > 0

    test "link code is generated through the resolver and marked sensitive":
      let o = run(cmdMyCode, "", sm, msgSeq, resolver)
      check o.reply.topic == rtLinkCode
      check o.reply.sensitive

    test "continue with an unknown code reports failure":
      let o = run(cmdContinue, "NOPE42", sm, msgSeq, resolver)
      check o.reply.topic == rtContinue
      check o.reply.failed
      check o.reply.sensitive

    test "doctor and memory views are sensitive":
      check run(cmdDoctor, "", sm, msgSeq, resolver).reply.sensitive
      check run(cmdMemory, "", sm, msgSeq, resolver).reply.sensitive

    test "channel-specific local actions are reported as unsupported":
      for kind in [cmdMenu, cmdWhoami, cmdReasoning]:
        let o = run(kind, "", sm, msgSeq, resolver)
        check o.kind == cokReply
        check o.reply.topic == rtUnsupported

    test "session task without a live session explains why":
      let o = run(cmdReset, "", sm, msgSeq, resolver)
      check o.reply.topic == rtNoSession
      check "reiniciar" in o.reply.text
      check "Nenhuma sessão ativa" in run(cmdDebug, "", sm, msgSeq, resolver).reply.text
      check msgSeq == 0

    test "session task with a live session is enqueued silently":
      discard sm.getOrCreate(UserId("u-1"))
      check sm.hasLiveSession(UserId("u-1"))
      let o = run(cmdReset, "", sm, msgSeq, resolver)
      check o.kind == cokSilent
      check msgSeq == 1
      check sm.getOrCreate(UserId("u-1")).inbox.len == 1

    test "ui commands reply with topic rtUi":
      let o = run(cmdVerbose, "", sm, msgSeq, resolver)
      check o.reply.topic == rtUi
      check o.reply.text.len > 0

    test "ui commands without a text form are unsupported":
      check run(cmdConfig, "", sm, msgSeq, resolver).reply.topic == rtUnsupported

when isMainModule:
  runTests()
