import std/unittest
import chronos/asyncsync
import donkey
import donkey/adapters/memory/md_file
import donkey/app/session_manager
import donkey/domain/agent_message
import donkey/domain/message

suite "daemon session ingress":

  test "toolCatalogSignature changes with provider and tools":
    let baseTools = @[
      ToolDescription(name: "a", description: "desc-a", schemaJson: """{"type":"object"}"""),
      ToolDescription(name: "b", description: "desc-b", schemaJson: """{"type":"object","x":1}"""),
    ]
    let same = toolCatalogSignature(baseTools, "zhipu/glm-4.7", "/tmp/p1")
    let changedProvider = toolCatalogSignature(baseTools, "gemini/flash", "/tmp/p1")
    let changedTool = toolCatalogSignature(
      @[ToolDescription(name: "a", description: "desc-a2", schemaJson: """{"type":"object"}""")],
      "zhipu/glm-4.7",
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
    let first = sm.buildSessionIngressContext(msg, "sig-a", msgSeq)
    let second = sm.buildSessionIngressContext(msg, "sig-a", msgSeq)
    check first.plan.isNew
    check not first.plan.rebuilt
    check not second.plan.isNew
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
    enqueueSessionMessage(entry, msg, "u-ask-1")
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
    enqueueSessionMessage(entry, msg, "u-normal-3")
    let queued = entry.inbox.popFirstNoWait()
    check queued.id == "u-normal-3"
    check queued.replyTo == "88"
    check queued.payload == "hello world"

  test "revoked user is detected from USER.md":
    let memory = MdFileAdapter(paddocksDir: "/tmp/donkey_revoked_ingress")
    let uid = UserId("u-revoked")
    memory.saveUserMd(uid, "# User\n\n**Access:** revoked\n")
    check memory.isRevoked(uid)
