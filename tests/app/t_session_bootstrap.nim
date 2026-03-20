import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/app/session_bootstrap
import donkey/domain/more_tools
import donkey/domain/message

suite "session_bootstrap":

  test "parseProviderPrefs returns defaults when empty":
    let prefs = parseProviderPrefs("")
    check prefs.providerName == "zhipu"
    check prefs.modelName == ""

  test "parseProviderPrefs reads provider and model from toml":
    let prefs = parseProviderPrefs("""
provider = "gemini"
model = "gemini-2.5-pro"
""")
    check prefs.providerName == "gemini"
    check prefs.modelName == "gemini-2.5-pro"

  test "buildProviderSpec applies openrouter defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "openrouter", modelName: ""))
    check spec.providerName == "openrouter"
    check spec.modelName == "openai/gpt-4o-mini"

  test "buildProviderSpec falls back to zhipu defaults":
    let spec = buildProviderSpec(ProviderPrefs(providerName: "weird", modelName: ""))
    check spec.providerName == "zhipu"
    check spec.modelName == "glm-4.7"

  test "providerLabelFromPrefs returns provider/model label":
    let label = providerLabelFromPrefs("""
provider = "anthropic"
model = "claude-opus"
""")
    check label == "anthropic/claude-opus"

  test "encodeSessionPayload keeps plain text when no media":
    let msg = InboundMessage(userId: UserId("u1"), text: "hello")
    check encodeSessionPayload(msg) == "hello"

  test "encodeSessionPayload encodes media payload as json":
    let msg = InboundMessage(userId: UserId("u1"), text: "hello", mediaUrl: "https://x/y.png")
    let payload = parseJson(encodeSessionPayload(msg))
    check payload["text"].getStr() == "hello"
    check payload["mediaUrl"].getStr() == "https://x/y.png"

  test "sessionReplyTo only returns telegram channel id":
    let tgMsg = InboundMessage(userId: UserId("u1"), channel: ckTelegram, channelId: "123")
    let dcMsg = InboundMessage(userId: UserId("u1"), channel: ckDiscord, channelId: "abc")
    check sessionReplyTo(tgMsg) == "123"
    check sessionReplyTo(dcMsg) == ""

  test "buildSessionTaskMsg preserves encoded payload":
    let msg = InboundMessage(userId: UserId("u1"), channel: ckTelegram, channelId: "42",
                             text: "hi", mediaUrl: "https://x/z.png")
    let task = buildSessionTaskMsg(msg, "m1")
    let payload = parseJson(task.payload)
    check task.id == "m1"
    check payload["text"].getStr() == "hi"
    check payload["mediaUrl"].getStr() == "https://x/z.png"
    check task.replyTo == "42"

  test "loadSessionContext reads prefs and paddock":
    let tmpDir = getTempDir() / "donkey_session_bootstrap_ctx"
    let memory = MdFileAdapter(paddocksDir: tmpDir)
    let userId = UserId("u-session-bootstrap")
    defer:
      if dirExists(tmpDir):
        removeDir(tmpDir)
    memory.savePreferences(userId, """
provider = "gemini"
model = "gemini-2.5-flash"
""")
    let ctx = loadSessionContext(memory, userId)
    check ctx.preferencesMd.contains("provider = \"gemini\"")
    check ctx.paddockDir == memory.paddockDir(userId)
    check ctx.providerLabel == "gemini/gemini-2.5-flash"

  test "withNativeTools appends native tool descriptions":
    let base = startSessionToolBundle(@[], @[])
    let bundled = withNativeTools(base)
    check bundled.tools.len >= nativeSessionTools().len
    check bundled.tools.anyIt(it.name == BashToolName)

  test "loadSessionBootstrapPlan maps context fields":
    let plan = loadSessionBootstrapPlan(SessionContext(
      preferencesMd: "provider = \"zhipu\"",
      paddockDir: "/tmp/paddock-x",
      providerLabel: "zhipu",
    ))
    check plan.preferencesMd.contains("provider")
    check plan.paddockDir == "/tmp/paddock-x"
    check plan.providerLabel == "zhipu"

  test "buildProviderBundle exposes streamFn only for providers that implement it":
    let openrouter = buildProviderBundle("provider = \"openrouter\"")
    let anthropic = buildProviderBundle("provider = \"anthropic\"")
    let gemini = buildProviderBundle("provider = \"gemini\"")
    let minimax = buildProviderBundle("provider = \"minimax\"")
    let zhipu = buildProviderBundle("provider = \"zhipu\"")
    check openrouter.streamFn != nil
    check anthropic.streamFn != nil
    check gemini.streamFn == nil
    check minimax.streamFn == nil
    check zhipu.streamFn == nil
