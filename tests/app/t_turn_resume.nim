## Resuming turns after a crash (PRD-roadmap E1.3): at startup each turn a
## previous process left in the journal is replayed into the user's session
## or answered with a notice.
##
## Same harness as t_schedule_enqueue: no event loop runs, so a replayed task
## stays queued in a session primed beforehand.

import std/[os, strutils, tables, unittest]
import chronos
import chronos/asyncsync
import donkey/adapters/memory/md_file
import donkey/adapters/state/turn_journal_store
import donkey/app/session_ingress
import donkey/app/session_manager
import donkey/config/types
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/access
import donkey/ports/http
import donkey/ports/provider
import donkey/ports/turn_journal

const Now = 1_800_000_000_000'i64

proc stubBundle(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  ProviderBundle(completeFn: proc(req: CompletionRequest): Result[CompletionResponse, string] =
    ok(CompletionResponse(text: "retomado")))

proc makeServices(base: string; outbox: AsyncQueue[OutboundMessage];
                  journal: TurnJournalPort;
                  isRevoked: ProfileCheck = nil): SessionIngressServices =
  let memory = MdFileAdapter(paddocksDir: base / "paddocks")
  let stubComplete: CompleteFn =
    proc(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(text: "ok"))
  result = buildSessionIngressServices(
    memory = memory.toRuntimePort(),
    cfg = DonkeyConfig(defaultProvider: "openai", defaultModel: "gpt-4o"),
    completeFn = stubComplete, streamFactory = StreamFactory(),
    toolClients = @[], tools = @[], globalOutbox = outbox,
    log = newLogger("test-turn-resume"), sandboxMode = smNone,
    sandboxRuntimeCmd = "", sandboxImage = "", typingFn = nil, searchFn = nil,
    access = AccessPort(isRevoked: isRevoked), http = HttpRuntimePort(),
    providerRuntimeBuilder = stubBundle)
  result.journal = journal

proc prime(sm: var SessionManager; services: SessionIngressServices;
           msgSeq: var int; uid: string) =
  discard startSessionIngress(sm, InboundMessage(
    userId: UserId(uid), channel: ckTelegram, channelId: "42", text: "prime"),
    services, msgSeq)
  ## The actor it spawns takes the prime's own task at once: only the task
  ## under test is left queued.

proc leftBehind(dir: string; r: TurnRecord) =
  ## A turn a previous process was running when it died.
  let journal = turnJournalPort(newTurnJournalStore(dir))
  doAssert journal.begin(r).isOk

proc rec(id, uid: string; effects: seq[string] = @[]; resumes = 0;
         startedMs = Now - 60_000): TurnRecord =
  TurnRecord(id: id, userId: uid, channel: ckTelegram, replyTo: "42:7",
             payload: "resume o relatório", preview: "resume o relatório",
             startedMs: startedMs, effects: effects, resumes: resumes)

proc tempBase(tag: string): string =
  result = getTempDir() / ("donkey_turn_resume_" & tag)
  removeDir(result)

proc runTests*() =
  suite "turn resume at startup":

    test "a turn with no effect goes back to the user's session":
      let base = tempBase("replay")
      defer: removeDir(base)
      let dir = base / "state" / "turns"
      leftBehind(dir, rec("1-a", "u-r1"))
      let outbox = newAsyncQueue[OutboundMessage]()
      let journal = turnJournalPort(newTurnJournalStore(dir))
      let services = makeServices(base, outbox, journal)
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      prime(sm, services, msgSeq, "u-r1")
      let summary = resumeInterruptedTurns(sm, services, msgSeq, Now)
      check summary.replayed == 1 and summary.notified == 0
      var entry = sm.entries["u-r1"]
      check entry.inbox.len == 1
      let task = entry.inbox.popFirstNoWait()
      check task.taskKind == tkUserMsg
      check task.resumeOf == "1-a"
      check task.payload == "resume o relatório"
      check task.replyTo == "42:7"
      check task.channel == ckTelegram
      check outbox.len == 0

    test "the replay is counted before the turn runs, so a second crash only notifies":
      let base = tempBase("counted")
      defer: removeDir(base)
      let dir = base / "state" / "turns"
      leftBehind(dir, rec("1-a", "u-r2"))
      let outbox = newAsyncQueue[OutboundMessage]()
      let services = makeServices(base, outbox, turnJournalPort(newTurnJournalStore(dir)))
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      prime(sm, services, msgSeq, "u-r2")
      discard resumeInterruptedTurns(sm, services, msgSeq, Now)
      ## The daemon dies again before the replayed turn starts.
      let again = turnJournalPort(newTurnJournalStore(dir)).pending()
      check again.isOk and again.get.len == 1
      check again.get[0].resumes == 1

    test "a turn that had an effect gets a notice and leaves the journal":
      let base = tempBase("notice")
      defer: removeDir(base)
      let dir = base / "state" / "turns"
      leftBehind(dir, rec("1-a", "u-r3", effects = @["fs_write"]))
      let outbox = newAsyncQueue[OutboundMessage]()
      let services = makeServices(base, outbox, turnJournalPort(newTurnJournalStore(dir)))
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let summary = resumeInterruptedTurns(sm, services, msgSeq, Now)
      check summary.replayed == 0 and summary.notified == 1
      check outbox.len == 1
      let notice = outbox.popFirstNoWait()
      check notice.userId == UserId("u-r3")
      check notice.channel == ckTelegram and notice.replyTo == "42:7"
      check "fs_write" in notice.text and "resume o relatório" in notice.text
      check not sm.hasSession(UserId("u-r3"))
      check turnJournalPort(newTurnJournalStore(dir)).pending().get.len == 0

    test "a revoked user's turn is dropped, neither replayed nor answered":
      let base = tempBase("revoked")
      defer: removeDir(base)
      let dir = base / "state" / "turns"
      leftBehind(dir, rec("1-a", "u-r4"))
      leftBehind(dir, rec("2-b", "u-r4", effects = @["bash"]))
      let outbox = newAsyncQueue[OutboundMessage]()
      let revoked: ProfileCheck = proc(u: UserId): Result[bool, string] {.gcsafe, raises: [].} = ok(true)
      let services = makeServices(base, outbox,
        turnJournalPort(newTurnJournalStore(dir)), isRevoked = revoked)
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let summary = resumeInterruptedTurns(sm, services, msgSeq, Now)
      check summary.replayed == 0 and summary.notified == 0 and summary.dropped == 2
      check outbox.len == 0
      check not sm.hasSession(UserId("u-r4"))
      check turnJournalPort(newTurnJournalStore(dir)).pending().get.len == 0

    test "a replayed turn is answered and leaves the journal, as a new process sees it":
      let base = tempBase("end-to-end")
      defer: removeDir(base)
      let dir = base / "state" / "turns"
      let userDir = base / "paddocks" / "u-r5"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Test")
      leftBehind(dir, rec("1-a", "u-r5"))
      let outbox = newAsyncQueue[OutboundMessage]()
      let services = makeServices(base, outbox, turnJournalPort(newTurnJournalStore(dir)))
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      check resumeInterruptedTurns(sm, services, msgSeq, Now).replayed == 1
      let reply = waitFor outbox.get().wait(chronos.seconds(20))
      check reply.userId == UserId("u-r5")
      check reply.replyTo == "42:7"
      check reply.text == "retomado"
      ## The turn ends after its reply is queued: give the actor the moment.
      for _ in 0 ..< 50:
        if turnJournalPort(newTurnJournalStore(dir)).pending().get.len == 0:
          break
        waitFor sleepAsync(chronos.milliseconds(20))
      check turnJournalPort(newTurnJournalStore(dir)).pending().get.len == 0

    test "without a journal there is nothing to resume":
      let base = tempBase("none")
      defer: removeDir(base)
      let outbox = newAsyncQueue[OutboundMessage]()
      let services = makeServices(base, outbox, TurnJournalPort())
      var sm: SessionManager
      sm.init()
      var msgSeq = 0
      let summary = resumeInterruptedTurns(sm, services, msgSeq, Now)
      check summary.replayed == 0 and summary.notified == 0 and summary.dropped == 0

when isMainModule:
  runTests()
