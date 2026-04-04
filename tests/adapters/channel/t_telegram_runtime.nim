import std/[os, sequtils, strutils, tables, unittest]
import results
import donkey/core/commands/command_routing
import donkey/core/log
import donkey/adapters/channel/telegram
import donkey/adapters/channel/telegram_runtime
import donkey/app/session_manager
import donkey/adapters/memory/md_file
import donkey/domain/agent_message
import donkey/domain/message
import donkey/ports/provider

suite "telegram_runtime":

  test "parseTelegramPrefs returns defaults when empty":
    let prefs = parseTelegramPrefs("")
    check prefs.provider == "zai-coding"
    check prefs.model == ""
    check prefs.thinking == "off"

  test "parseTelegramPrefs reads provider model and thinking":
    let prefs = parseTelegramPrefs("""
provider = "gemini"
model = "gemini-2.5-pro"
thinking = "high"
""")
    check prefs.provider == "gemini"
    check prefs.model == "gemini-2.5-pro"
    check prefs.thinking == "high"

  test "parseCallbackData parses model set":
    let callback = parseCallbackData("models:set:openrouter:openai/gpt-4o")
    check callback.kind == cbkModelsSet
    check callback.provider == "openrouter"
    check callback.model == "openai/gpt-4o"

  test "parseCallbackData parses thinking set":
    let callback = parseCallbackData("think:set:medium")
    check callback.kind == cbkThinkSet
    check callback.value == "medium"

  test "parseCallbackData parses core callbacks":
    check parseCallbackData("personality:tone:warm").kind == cbkPersonality
    check parseCallbackData("name:Ada").kind == cbkName

  test "parseCommandText parses continue":
    let cmd = parseCommandText("/continue abc123")
    check cmd.kind == cmdContinue
    check cmd.value == "abc123"

  test "parseCommandText parses reset":
    check parseCommandText("/reset").kind == cmdReset

  test "parseCommandText parses skill":
    let cmd = parseCommandText("/skill search browser")
    check cmd.kind == cmdSkill
    check cmd.value == "search browser"

  test "handleTelegramTaskCommand delegates to ensure callback when provided":
    var sm: SessionManager
    sm.init()
    var tgAdapter = TelegramAdapter(
      resolver: newIdentityResolver(getTempDir() / "donkey_tg_runtime_resolver_test"),
    )
    let covered = [
      (cmdDebug, tkDebugToggle, "/debug"),
      (cmdReset, tkReset, "/reset"),
      (cmdNew, tkNew, "/new"),
      (cmdCompact, tkCompact, "/compact"),
      (cmdStop, tkStop, "/stop"),
      (cmdRestart, tkRestart, "/restart"),
      (cmdBind, tkBind, "/bind"),
    ]
    for (kind, expectedTask, text) in covered:
      var msgSeq = 0
      var called = false
      var seenTask = tkUserMsg
      var seenUserId = ""
      var seenPayload = ""
      let msg = InboundMessage(
        userId: UserId("u-tg-" & $kind),
        channel: ckTelegram,
        channelId: "42",
        text: text,
      )
      let ensureTaskSession =
        proc(seenMsg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} =
          {.cast(gcsafe).}:
            called = true
            seenTask = taskKind
            seenUserId = $seenMsg.userId
            seenPayload = payload
      check handleTelegramTaskCommand(
        sm, msg, newCommandDecision(kind), tgAdapter, msgSeq, ensureTaskSession)
      check called
      check seenTask == expectedTask
      check seenUserId == $msg.userId
      check seenPayload == ""
      check msgSeq == 0

  test "handleTelegramUiCallback delegates reset callback to ensure callback when provided":
    var sm: SessionManager
    sm.init()
    var tgAdapter = TelegramAdapter(
      resolver: newIdentityResolver(getTempDir() / "donkey_tg_runtime_resolver_reset_callback_test"),
    )
    var kbdMsgIds = initTable[string, string]()
    let tmpDir = getTempDir() / "donkey_tg_runtime_reset_callback"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    var msgSeq = 0
    var called = false
    var seenTask = tkUserMsg
    let msg = InboundMessage(
      userId: UserId("u-tg-reset-callback"),
      channel: ckTelegram,
      channelId: "42",
      callbackId: "cb-reset",
      text: "/callback reset",
    )
    let completeBuilder =
      proc(preferencesMd: string): CompleteFn {.gcsafe.} = nil
    let modelCatalogLoader: ModelCatalogLoader =
      proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.} =
        ok(ModelCatalogResult())
    let logger = newLogger("test.telegram")
    let ensureTaskSession =
      proc(seenMsg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} =
        {.cast(gcsafe).}:
          called = true
          seenTask = taskKind
          check $seenMsg.userId == $msg.userId
          check payload == ""
    check handleTelegramUiCallback(
      msg, parseCallbackData("reset"), sm, tgAdapter, kbdMsgIds, memory,
      completeBuilder, modelCatalogLoader, 0, 0, msgSeq, 0, logger, ensureTaskSession)
    check called
    check seenTask == tkReset
    check msgSeq == 0

  test "handleTelegramUiCallback routes reasoning callback through local toggle":
    var sm: SessionManager
    sm.init()
    var tgAdapter = TelegramAdapter(
      resolver: newIdentityResolver(getTempDir() / "donkey_tg_runtime_resolver_reasoning_callback_test"),
    )
    var kbdMsgIds = initTable[string, string]()
    let tmpDir = getTempDir() / "donkey_tg_runtime_reasoning_callback"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-tg-reasoning-callback")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, "reasoning = \"off\"")
    var msgSeq = 0
    let msg = InboundMessage(
      userId: userId,
      channel: ckTelegram,
      channelId: "42",
      callbackId: "cb-reasoning",
      text: "/callback reasoning",
    )
    let completeBuilder =
      proc(preferencesMd: string): CompleteFn {.gcsafe.} = nil
    let modelCatalogLoader: ModelCatalogLoader =
      proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.} =
        ok(ModelCatalogResult())
    let logger = newLogger("test.telegram")
    check handleTelegramUiCallback(
      msg, parseCallbackData("reasoning"), sm, tgAdapter, kbdMsgIds, memory,
      completeBuilder, modelCatalogLoader, 0, 0, msgSeq, 0, logger)
    check memory.loadContext(userId).preferencesMd.contains("reasoning = \"on\"")

  test "handleTelegramUiCommand handles deferred config commands without falling back":
    var tgAdapter = TelegramAdapter(
      resolver: newIdentityResolver(getTempDir() / "donkey_tg_runtime_resolver_deferred_ui_test"),
    )
    var kbdMsgIds = initTable[string, string]()
    let tmpDir = getTempDir() / "donkey_tg_runtime_deferred_ui"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let logger = newLogger("test.telegram")
    let modelCatalogLoader: ModelCatalogLoader =
      proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.} =
        ok(ModelCatalogResult())
    let commands = [cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts]
    for kind in commands:
      let msg = InboundMessage(
        userId: UserId("u-tg-deferred-" & $kind),
        channel: ckTelegram,
        channelId: "42",
        text: "/" & $kind,
      )
      check handleTelegramUiCommand(
        msg, newCommandDecision(kind), tgAdapter, kbdMsgIds, memory,
        modelCatalogLoader, 0, 0, logger)

  test "buildProviderButtons marks current provider":
    let tmpDir = getTempDir() / "donkey_tg_runtime_provider"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-tg-provider")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, "provider = \"gemini\"")
    let buttons = buildProviderButtons(memory, userId)
    check buttons.len > 0
    check buttons.anyIt(it.anyIt(it[0].startsWith("✓ gemini")))

  test "buildThinkButtons marks current thinking level":
    let tmpDir = getTempDir() / "donkey_tg_runtime_think"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-tg-think")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, "thinking = \"medium\"")
    let buttons = buildThinkButtons(memory, userId)
    check buttons.len == 1
    check buttons[0].anyIt(it[0] == "✓ medium")

  test "handleTelegramCoreCommand handles /skill locally":
    var sm: SessionManager
    sm.init()
    var tgAdapter = TelegramAdapter(
      resolver: newIdentityResolver(getTempDir() / "donkey_tg_runtime_resolver_skill_test"),
    )
    var kbdMsgIds = initTable[string, string]()
    let tmpDir = getTempDir() / "donkey_tg_runtime_skill"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    let msg = InboundMessage(
      userId: UserId("u-tg-skill"),
      channel: ckTelegram,
      channelId: "42",
      text: "/skill",
    )
    let completeBuilder =
      proc(preferencesMd: string): CompleteFn {.gcsafe.} = nil
    var msgSeq = 0
    check handleTelegramCoreCommand(
      sm, msg, newCommandDecision(cmdSkill), tgAdapter, kbdMsgIds, memory,
      completeBuilder, 0, 0, msgSeq)

  test "buildTelegramStatusText includes provider and thinking":
    let tmpDir = getTempDir() / "donkey_tg_runtime_status"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-tg-status")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, """
provider = "anthropic"
model = "claude-opus"
thinking = "low"
""")
    let text = buildTelegramStatusText(memory, userId, 7, 2, 0)
    check text.contains("anthropic / claude-opus")
    check text.contains("Thinking: low")

  test "saveTelegramPreference upserts key":
    let tmpDir = getTempDir() / "donkey_tg_runtime_save"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-tg-save")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, "provider = \"zai-coding\"")
    saveTelegramPreference(memory, userId, "provider", "gemini")
    let prefs = memory.loadContext(userId).preferencesMd
    check prefs.contains("provider = \"gemini\"")
