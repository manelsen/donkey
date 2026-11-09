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
import donkey/core/session/session_ingress
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/http
import donkey/ports/provider
import donkey/ports/tool

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
    let stubComplete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(text: "ok"))
    let emptyClients: seq[ToolRuntimePort] = @[]
    let emptyTools: seq[ToolDescription] = @[]
    let services = buildSessionIngressServices(
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
      isRevoked = proc(u: UserId): bool = false,
      http = HttpRuntimePort(),
    )
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
    let entry = sm.get(UserId("u-allowed-user"))
    check entry != nil
    entry[].inbox.addLastNoWait(newCancelMsg())

  test "handleSessionFallback proceeds with session creation when isRevoked is nil":
    let dir = getTempDir() / "donkey_ingress_nil_revoked_" & $nowMs()
    createDir(dir)
    defer: removeDir(dir)
    let memory = MdFileAdapter(paddocksDir: dir)
    var sm: SessionManager
    sm.init()
    var msgSeq = 0
    let outbox = newAsyncQueue[OutboundMessage]()
    let stubComplete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(text: "ok"))
    let emptyClients: seq[ToolRuntimePort] = @[]
    let emptyTools: seq[ToolDescription] = @[]
    let services = buildSessionIngressServices(
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
      isRevoked = nil,
      http = HttpRuntimePort(),
    )
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
    let entry = sm.get(UserId("u-nil-revoked-user"))
    check entry != nil
    entry[].inbox.addLastNoWait(newCancelMsg())
