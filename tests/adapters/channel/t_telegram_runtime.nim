import std/[os, sequtils, strutils, unittest]
import donkey/core/commands/command_routing
import donkey/adapters/channel/telegram_runtime
import donkey/adapters/memory/md_file
import donkey/domain/message

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
