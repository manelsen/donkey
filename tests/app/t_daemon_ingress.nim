import std/[os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/app/session_ingress
import donkey/adapters/memory/md_file
import donkey/app/session_manager
import donkey/app/sandbox
import donkey/config/types
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/dm_policy
import donkey/core/session/session_ingress
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/http
import donkey/ports/provider
import donkey/ports/runtime_state
import donkey/ports/tool

var gRegistryUpserts: seq[SessionRegistryRecord] = @[]

proc countingRegistry(): SessionRegistryPort =
  SessionRegistryPort(
    loadAll: proc(): Result[seq[SessionRegistryRecord], string] {.gcsafe.} =
      ok(newSeq[SessionRegistryRecord]()),
    upsert: proc(record: SessionRegistryRecord): Result[void, string] {.gcsafe.} =
      {.cast(gcsafe).}:
        gRegistryUpserts.add(record)
      ok(),
  )

proc makeTestServices(memory: MdFileAdapter;
                      outbox: AsyncQueue[OutboundMessage];
                      isRevoked: proc(u: UserId): bool {.gcsafe.} = nil;
                      isDmAllowed: proc(u: UserId): bool {.gcsafe.} = nil;
                      dmPolicy: DmPolicy = DmPolicyOpen): SessionIngressServices =
  let stubComplete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    ok(CompletionResponse(text: "ok"))
  let emptyClients: seq[ToolRuntimePort] = @[]
  let emptyTools: seq[ToolDescription] = @[]
  buildSessionIngressServices(
    memory = memory.toRuntimePort(),
    cfg = DonkeyConfig(defaultProvider: "openai", defaultModel: "gpt-4o"),
    completeFn = stubComplete,
    streamFn = nil,
    toolClients = emptyClients,
    tools = emptyTools,
    globalOutbox = outbox,
    log = newLogger("test-ingress"),
    sandboxMode = smNone,
    sandboxRuntimeCmd = "",
    sandboxImage = "",
    typingFn = nil,
    searchFn = nil,
    isRevoked = isRevoked,
    isDmAllowed = isDmAllowed,
    dmPolicy = dmPolicy,
    http = HttpRuntimePort(),
  )

suite "daemon session ingress":

  test "toolCatalogSignature changes with provider and tools":
    let baseTools = @[
      ToolDescription(name: "a", description: "desc-a", schemaJson: """{"type":"object"}"""),
      ToolDescription(name: "b", description: "desc-b", schemaJson: """{"type":"object","x":1}"""),
    ]
    let same = toolCatalogSignature(baseTools, "zai-coding/glm-4.7", "/tmp/p1")
    let changedProvider = toolCatalogSignature(baseTools, "gemini/flash", "/tmp/p1")
    let changedTool = toolCatalogSignature(
      @[ToolDescription(name: "a", description: "desc-a2", schemaJson: """{"type":"object"}""")],
      "zai-coding/glm-4.7",
      "/tmp/p1",
    )
    check same != changedProvider
    check same != changedTool

  test "buildSessionIngressContext increments msg id and reuses existing entry":
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let msg = InboundMessage(
      userId: UserId("u-ingress"),
      channel: ckTelegram,
      channelId: "42",
      text: "hello",
    )
    let first = sm.buildSessionIngressContext(msg, SessionRuntimeSignature("sig-a"), msgSeq)
    let second = sm.buildSessionIngressContext(msg, SessionRuntimeSignature("sig-a"), msgSeq)
    check first.plan.decision.actionKind == siaStartNewSession
    check not first.plan.decision.rebuildsSessionRuntime
    check second.plan.decision.actionKind == siaReuseSessionRuntime
    check first.msgId == "u-ingress-1"
    check second.msgId == "u-ingress-2"
    check first.plan.entry == second.plan.entry

  test "buildSessionIngressContext persists exactly one registry write per message":
    gRegistryUpserts.setLen(0)
    var sm: SessionManager
    sm.init()
    sm.setRegistryStore(countingRegistry())
    var msgSeq = 0
    let msg = InboundMessage(
      userId: UserId("u-persist"),
      channel: ckTelegram,
      channelId: "900",
      text: "hello",
    )
    discard sm.buildSessionIngressContext(msg, SessionRuntimeSignature("sig-p"), msgSeq)
    check gRegistryUpserts.len == 1
    ## The single write must include the channel recorded on this message.
    check gRegistryUpserts[0].channels == @[(ckTelegram, "900")]
    check gRegistryUpserts[0].lastInboundAtMs > 0

    ## The reuse path is also a single write, still carrying the channel.
    discard sm.buildSessionIngressContext(msg, SessionRuntimeSignature("sig-p"), msgSeq)
    check gRegistryUpserts.len == 2
    check gRegistryUpserts[1].channels == @[(ckTelegram, "900")]

  test "SessionManager channel-level authorization follows the DM policy":
    var sm: SessionManager
    sm.init()
    let uid = UserId("u-auth")
    check sm.allows(uid)
    sm.dmPolicy = DmPolicyAllowlist
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} = u == UserId("u-auth")
    check sm.allows(uid)
    check not sm.allows(UserId("other"))

  test "allowlist policy rejects an unknown user":
    let tmpDir = getTempDir() / "donkey_test_ingress_allowlist"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)
    let memory = MdFileAdapter(paddocksDir: tmpDir / "paddocks")
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeTestServices(
      memory, outbox,
      isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false,
      dmPolicy = DmPolicyAllowlist,
    )
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let msg = InboundMessage(
      userId: UserId("u-denied"),
      channel: ckTelegram,
      channelId: "42",
      text: "hello",
    )
    discard startSessionIngress(sm, msg, services, msgSeq)
    check outbox.len == 1
    let reply = waitFor outbox.get()
    check "não autorizado" in reply.text

  test "enqueueSessionMessage diverts next reply to askInbox":
    var entry = SessionEntry(
      inbox: newAsyncQueue[AgentMessage](),
      askInbox: newAsyncQueue[string](),
      awaitingAsk: true,
      channels: @[],
      toolCatalogSignature: "sig-a",
    )
    let msg = InboundMessage(
      userId: UserId("u-ask"),
      channel: ckTelegram,
      channelId: "77",
      text: "my answer",
    )
    enqueueSessionMessage(entry, msg, "u-ask-1", sitAskInbox)
    check not entry.awaitingAsk
    check entry.askInbox.popFirstNoWait() == "my answer"
    check entry.inbox.len == 0

  test "enqueueSessionMessage sends normal inbound text to actor inbox":
    var entry = SessionEntry(
      inbox: newAsyncQueue[AgentMessage](),
      askInbox: newAsyncQueue[string](),
      awaitingAsk: false,
      channels: @[],
      toolCatalogSignature: "sig-a",
    )
    let msg = InboundMessage(
      userId: UserId("u-normal"),
      channel: ckTelegram,
      channelId: "88",
      text: "hello world",
    )
    enqueueSessionMessage(entry, msg, "u-normal-3", sitActorInbox)
    let queued = entry.inbox.popFirstNoWait()
    check queued.id == "u-normal-3"
    check queued.replyTo == "88"
    check queued.payload == "hello world"

  test "revoked user is detected from USER.md":
    let memory = MdFileAdapter(paddocksDir: "/tmp/donkey_revoked_ingress")
    let uid = UserId("u-revoked")
    memory.saveUserMd(uid, "# User\n\n**Access:** revoked\n")
    check memory.isRevoked(uid)

  test "handleSessionFallback rejects revoked user into global outbox":
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = SessionIngressServices(
      globalOutbox: outbox,
      isRevoked: proc(u: UserId): bool = u == UserId("u-revoked-user"),
    )
    let msg = InboundMessage(
      userId: UserId("u-revoked-user"),
      channel: ckTelegram,
      channelId: "123",
      text: "hello",
    )
    handleSessionFallback(sm, msgSeq, msg, services)
    check outbox.len == 1
    let rejected = outbox.popFirstNoWait()
    check rejected.userId == UserId("u-revoked-user")
    check "revogado" in rejected.text
    check msgSeq == 0
    check not sm.hasSession(UserId("u-revoked-user"))

  test "handleSessionFallback creates session and leaves outbox clear for non-revoked user":
    let dir = getTempDir() / "donkey_ingress_non_revoked_" & $nowMs()
    createDir(dir)
    defer: removeDir(dir)
    let memory = MdFileAdapter(paddocksDir: dir)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeTestServices(memory, outbox, proc(u: UserId): bool = false)
    let msg = InboundMessage(
      userId: UserId("u-allowed-user"),
      channel: ckTelegram,
      channelId: "123",
      text: "hello allowed user",
    )
    handleSessionFallback(sm, msgSeq, msg, services)
    check sm.hasSession(UserId("u-allowed-user"))
    check msgSeq == 1
    check outbox.len == 0

  test "handleSessionFallback proceeds with session creation when isRevoked is nil":
    let dir = getTempDir() / "donkey_ingress_nil_revoked_" & $nowMs()
    createDir(dir)
    defer: removeDir(dir)
    let memory = MdFileAdapter(paddocksDir: dir)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let outbox = newAsyncQueue[OutboundMessage]()
    let services = makeTestServices(memory, outbox, nil)
    let msg = InboundMessage(
      userId: UserId("u-nil-revoked-user"),
      channel: ckTelegram,
      channelId: "123",
      text: "hello unverified user",
    )
    handleSessionFallback(sm, msgSeq, msg, services)
    check sm.hasSession(UserId("u-nil-revoked-user"))
    check msgSeq == 1
    check outbox.len == 0

  test "handleSessionFallback rejects user revoked in real MdFileAdapter":
    let dir = getTempDir() / "donkey_ingress_md_revoked_" & $nowMs()
    createDir(dir)
    defer: removeDir(dir)
    let memory = MdFileAdapter(paddocksDir: dir)
    let revokedUid = UserId("u-real-revoked")
    memory.saveUserMd(revokedUid, "# User\n\n**Access:** revoked\n")
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let outbox = newAsyncQueue[OutboundMessage]()
    let isRevokedHook: proc(u: UserId): bool {.gcsafe.} =
      proc(u: UserId): bool {.gcsafe.} =
        {.gcsafe.}:
          memory.isRevoked(u)
    let services = makeTestServices(memory, outbox, isRevokedHook)
    let msg = InboundMessage(
      userId: revokedUid,
      channel: ckTelegram,
      channelId: "123",
      text: "hello from revoked",
    )
    handleSessionFallback(sm, msgSeq, msg, services)
    check outbox.len == 1
    let rejected = outbox.popFirstNoWait()
    check rejected.userId == revokedUid
    check "revogado" in rejected.text
    check msgSeq == 0
    check not sm.hasSession(revokedUid)
