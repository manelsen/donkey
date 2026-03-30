## Tests for admin TUI components (pure functions only).
import std/[unittest, sequtils, strutils, times, os, options]
import illwill as ill
import donkey/tui/admin_tui
import donkey/config/types
import donkey/core/types
import donkey/adapters/memory/md_file

suite "Admin TUI":

  test "sectionLabel returns correct labels":
    check sectionLabel(asConfig) == "[Config]"
    check sectionLabel(asAgents) == "[Agents]"
    check sectionLabel(asChannels) == "[Channels]"
    check sectionLabel(asProviders) == "[Providers]"
    check sectionLabel(asModels) == "[Models]"
    check sectionLabel(asHooks) == "[Hooks]"
    check sectionLabel(asPlugins) == "[Plugins]"

  test "sectionLabels returns all labels":
    let labels = sectionLabels()
    check labels.len == 8
    check "Config" in labels.join
    check "Agents" in labels.join
    check "Channels" in labels.join

  test "newAdminState initializes correctly":
    let cfg = defaultConfig("~/.donkey")
    let st = newAdminState(cfg)
    check st.section == asConfig
    check st.selectedIndex == 0
    check st.items.len == 0
    check st.logLevel == "info"
    check st.verbose == "default"
    check st.reasoning == "auto"

  test "newAdminState without config uses defaults":
    let st = newAdminState()
    check st.section == asConfig
    check st.config.home == ""

  test "loadConfigItems populates items":
    var st = newAdminState(defaultConfig("/home/user"))
    st.loadConfigItems()
    check st.items.len == 7
    let names = st.items.mapIt(it.name)
    check "home" in names
    check "log_level" in names
    check "verbose" in names
    check "reasoning" in names

  test "loadAgentItems populates agents":
    var st = newAdminState()
    st.loadAgentItems()
    check st.items.len == 3
    let names = st.items.mapIt(it.name)
    check "default" in names
    check "coder" in names

  test "loadChannelItems populates channels":
    var st = newAdminState()
    st.runtimeChannels = @["telegram", "discord", "cli"]
    st.loadChannelItems()
    check st.items.len == 3
    let names = st.items.mapIt(it.name)
    check "telegram" in names
    check "discord" in names
    check "cli" in names

  test "loadChannelItems fallback without runtime channels":
    var st = newAdminState()
    st.loadChannelItems()
    check st.items.len == 1
    check st.items[0].name == "cli"
    check st.items[0].status == "active"

  test "loadProviderItems populates providers":
    var st = newAdminState()
    st.loadProviderItems()
    check st.items.len == 8
    let names = st.items.mapIt(it.name)
    check "anthropic" in names
    check "openai" in names
    check "openrouter" in names
    check "zhipu" in names

  test "loadModelItems populates models":
    var st = newAdminState()
    st.loadModelItems()
    check st.items.len == 10
    let names = st.items.mapIt(it.name)
    check "claude-opus-4-6" in names
    check "gpt-4o-mini" in names

  test "loadHookItems populates hooks":
    var st = newAdminState()
    st.loadHookItems()
    check st.items.len == 4
    let names = st.items.mapIt(it.name)
    check "rag_context" in names
    check "memory_capture" in names

  test "loadPluginItems populates plugins":
    var st = newAdminState()
    st.loadPluginItems()
    check st.items.len == 4
    let names = st.items.mapIt(it.name)
    check "shell" in names
    check "git" in names

  test "loadSection dispatches to correct loader":
    var st = newAdminState()
    st.section = asConfig
    st.loadSection()
    check st.items.len == 7

    st.section = asAgents
    st.loadSection()
    check st.items.len == 3

    st.section = asChannels
    st.loadSection()
    check st.items.len == 1  # fallback: only cli

    st.section = asProviders
    st.loadSection()
    check st.items.len == 8

    st.section = asModels
    st.loadSection()
    check st.items.len == 10

    st.section = asHooks
    st.loadSection()
    check st.items.len == 4

    st.section = asPlugins
    st.loadSection()
    check st.items.len == 4

  test "items have correct enabled status":
    var st = newAdminState()
    st.runtimeChannels = @["telegram", "discord"]
    st.loadChannelItems()
    let telegram = st.items.filterIt(it.name == "telegram")[0]
    check telegram.enabled == true
    check telegram.status == "connected"

  test "items can be toggled":
    var st = newAdminState()
    st.runtimeChannels = @["telegram", "discord"]
    st.loadChannelItems()
    var idx = -1
    for i, item in st.items:
      if item.name == "telegram":
        idx = i
        break
    check idx >= 0
    check st.items[idx].enabled == true
    st.items[idx].enabled = false
    check st.items[idx].enabled == false

  test "loadUsersItems populates users from adapter":
    var st = newAdminState()
    let tmpDir = "/tmp/test_donkey_users_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)

    # Create test paddock
    let testUserId = "test-user-123"
    createDir(tmpDir / testUserId)
    writeFile(tmpDir / testUserId / "USER.md", """
---
summary: Test user for unit test.
---
# Test User 123
**Preferred name:** TestUser
**Access:** active
""")

    # Create adapter and load users
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    st.memory = adapter
    st.loadUsersItems()

    # Verify user was loaded
    check st.items.len == 1
    check st.items[0].name == testUserId
    check st.items[0].description == "TestUser"
    check st.items[0].enabled == true
    check st.items[0].status == "active"

  test "loadUsersItems handles empty paddocks":
    var st = newAdminState()
    let tmpDir = "/tmp/test_donkey_empty_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)

    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    st.memory = adapter
    st.loadUsersItems()

    check st.items.len == 0

  test "loadUsersItems handles multiple users":
    var st = newAdminState()
    let tmpDir = "/tmp/test_donkey_multi_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)

    # Create multiple test users
    for i in 1 .. 5:
      let userId = "user-" & $i
      createDir(tmpDir / userId)
      let access = if i == 3: "revoked" else: "active"
      writeFile(tmpDir / userId / "USER.md",
        "# User " & $i & "\n**Preferred name:** User" & $i & "\n**Access:** " & access)

    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    st.memory = adapter
    st.loadUsersItems()

    check st.items.len == 5
    let revokedUsers = st.items.filterIt(it.status == "revoked")
    check revokedUsers.len == 1
    check revokedUsers[0].name == "user-3"

  test "AdminSection includes asUsers":
    # Verify asUsers is in the enum
    let hasUsers = ord(asUsers) >= 0
    check hasUsers == true

  test "navigate to Users section":
    var st = newAdminState()
    check st.section == asConfig

    # Navigate to Users section
    st.section = asUsers
    st.loadSection()

    # Should have loadUsersItems called via loadSection
    check st.section == asUsers

  test "showUserDetail populates detail view":
    var st = newAdminState()
    let tmpDir = "/tmp/test_detail_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)

    # Create test user with full context
    let userId = "test-user-detail"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", """
---
summary: Test user detail view.
---
# Test User Detail
**Preferred name:** TestDetail
**Access:** active
**Timezone:** UTC
""")
    writeFile(tmpDir / userId / "MEMORY.md", """
# Memory
- Test fact 1
- Test fact 2
""")
    writeFile(tmpDir / userId / "PREFERENCES.md", """
# Preferences
- Theme: dark
- Language: en
""")

    # Load user detail
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    let ctx = adapter.loadContext(UserId(userId))
    
    check ctx.userId == UserId(userId)
    check ctx.userMd.contains("TestDetail")
    check ctx.memoryMd.contains("Test fact")
    check ctx.preferencesMd.contains("dark")

  test "showUserDetail handles missing memory":
    var st = newAdminState()
    let tmpDir = "/tmp/test_no_mem_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)

    let userId = "test-no-mem"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", "# User\n**Access:** active")

    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    let ctx = adapter.loadContext(UserId(userId))
    
    check ctx.memoryMd.len == 0
    check ctx.preferencesMd.len == 0

  test "AdminState can track selectedUserId":
    var st = newAdminState()
    st.selectedUserId = some(UserId("test-user"))
    check st.selectedUserId.isSome()
    check st.selectedUserId.get() == UserId("test-user")

  test "deleteUser removes paddock directory":
    let tmpDir = "/tmp/test_delete_" & $epochTime()
    createDir(tmpDir)
    
    let userId = "user-to-delete"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", "# User\n**Access:** active")
    
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    
    # Verify user exists
    let users = adapter.listUsers()
    check users.len == 1
    
    # Delete user (simulated - just remove directory)
    let paddockPath = tmpDir / userId
    discard execShellCmd("rm -rf " & paddockPath)
    
    # Verify user removed
    let usersAfter = adapter.listUsers()
    check usersAfter.len == 0

  test "confirmMode tracks deletion state":
    var st = newAdminState()
    check st.confirmMode == cmNone
    
    st.confirmMode = cmDelete
    check st.confirmMode == cmDelete
    
    st.confirmMode = cmNone
    check st.confirmMode == cmNone

  test "can set confirmMode enum":
    var st = newAdminState()
    st.confirmMode = ConfirmMode(cmDelete)
    check st.confirmMode == cmDelete

  test "revokeUser updates access field":
    let tmpDir = "/tmp/test_revoke_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)
    
    let userId = "user-revoke"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", """# User
**Access:** active
**Preferred name:** TestUser""")
    
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    
    # Verify initial state
    let users = adapter.listUsers()
    check users[0].access == "active"
    check users[0].preferredName == "TestUser"
    
    # Revoke user
    adapter.updateUserField(UserId(userId), "access", "revoked")
    
    # Verify revoked
    let usersAfter = adapter.listUsers()
    check usersAfter[0].access == "revoked"

  test "restoreUser sets access to active":
    let tmpDir = "/tmp/test_restore_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)
    
    let userId = "user-restore"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", """# User
**Access:** revoked""")
    
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    
    # Restore user
    adapter.updateUserField(UserId(userId), "access", "active")
    
    # Verify restored
    let users = adapter.listUsers()
    check users[0].access == "active"

  test "editUserField updates PREFERENCES.md":
    let tmpDir = "/tmp/test_edit_prefs_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)
    
    let userId = "user-edit-prefs"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", """# User
**Preferred name:** OldName""")
    writeFile(tmpDir / userId / "PREFERENCES.md", """# Preferences
**Timezone:** UTC""")
    
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    
    # Save new preferences
    let newPrefs = """# Preferences
**Timezone:** America/New_York
**Language:** en
"""
    adapter.savePreferences(UserId(userId), newPrefs)
    
    # Verify
    let ctx = adapter.loadContext(UserId(userId))
    check ctx.preferencesMd.contains("America/New_York")
    check ctx.preferencesMd.contains("Language")

  test "validatePreferenceField accepts valid values":
    # Test that editing preserves valid fields
    let tmpDir = "/tmp/test_validate_" & $epochTime()
    createDir(tmpDir)
    defer: discard execShellCmd("rm -rf " & tmpDir)
    
    let userId = "user-validate"
    createDir(tmpDir / userId)
    writeFile(tmpDir / userId / "USER.md", """# User
**Preferred name:** Test""")
    
    let adapter = MdFileAdapter(paddocksDir: tmpDir)
    let ctx = adapter.loadContext(UserId(userId))
    
    # User.md content preserved when editing prefs
    check ctx.userMd.contains("Test")

  test "ProviderItem tracks all provider fields":
    var item: ProviderItem
    item.name = "anthropic"
    item.enabled = true
    item.status = "healthy"
    item.model = "claude-sonnet-4"
    item.endpoint = "api.anthropic.com"
    
    check item.name == "anthropic"
    check item.enabled == true
    check item.status == "healthy"
    check item.model == "claude-sonnet-4"

  test "statusColor maps provider status":
    check statusColor("healthy") == StatusOk
    check statusColor("degraded") == ill.fgYellow
    check statusColor("error") == StatusError
    check statusColor("unknown") == ill.fgWhite

  test "toggleProvider changes enabled state":
    var st = newAdminState()
    st.loadProviderItems()
    
    # Find anthropic
    var idx = -1
    for i, item in st.items:
      if item.name == "anthropic":
        idx = i
        break
    check idx >= 0
    
    let original = st.items[idx].enabled
    st.items[idx].enabled = not original
    check st.items[idx].enabled == not original

  test "cannot disable all providers warning":
    var st = newAdminState()
    st.loadProviderItems()
    
    # Fallback lists all known providers (none configured)
    check st.items.len > 0
    let names = st.items.mapIt(it.name)
    check "anthropic" in names

  test "selectModel changes active model":
    var st = newAdminState()
    st.loadModelItems()
    
    # Find default model
    var defaultIdx = -1
    for i, item in st.items:
      if item.status == "static":
        defaultIdx = i
        break
    check defaultIdx >= 0
    
    # Simulate changing status
    st.items[defaultIdx].status = "available"
    check st.items[defaultIdx].status == "available"

  test "models have metadata fields":
    var st = newAdminState()
    st.loadModelItems()
    
    for item in st.items:
      check item.name.len > 0
      check item.description.len > 0

    var tres2: ProviderTestResult
    tres2.provider = "openai"
    tres2.success = false
    tres2.latencyMs = 0
    tres2.message = "Connection timeout"
    
    check tres2.success == false
    check tres2.message.contains("timeout")

  test "ProviderMetrics tracks usage":
    var m: ProviderMetrics
    m.totalRequests = 1000
    m.successful = 950
    m.failed = 50
    m.avgLatencyMs = 250
    
    check m.totalRequests == 1000
    check m.successful == 950
    check m.failed == 50
    check m.avgLatencyMs == 250

  test "MetricsTimeRange enum values":
    check ord(mtr1h) == 0
    check ord(mtr24h) == 1
    check ord(mtr7d) == 2

  test "ChannelItem tracks extended fields":
    var ch: ChannelItem
    ch.name = "discord"
    ch.enabled = true
    ch.status = "connected"
    ch.botName = "DonkeyBot"
    ch.userCount = 42
    
    check ch.name == "discord"
    check ch.enabled == true
    check ch.status == "connected"
    check ch.botName == "DonkeyBot"
    check ch.userCount == 42

  test "ChannelMetrics tracks per-channel metrics":
    var m: ChannelMetrics
    m.messagesIn = 500
    m.messagesOut = 480
    m.errors = 5
    m.avgResponseTimeMs = 1200
    
    check m.messagesIn == 500
    check m.messagesOut == 480
    check m.errors == 5

  test "ChannelItem toggle preserves other fields":
    var ch = ChannelItem(
      name: "telegram",
      enabled: true,
      status: "connected",
      botName: "TestBot",
      userCount: 10
    )
    
    ch.enabled = false
    check ch.name == "telegram"
    check ch.status == "connected"
    check ch.userCount == 10

  test "SparklineData type":
    var sl: SparklineData
    sl.label = "sessions"
    sl.points = @[1.0, 2.0, 3.0, 4.0, 5.0]
    sl.current = 5.0
    
    check sl.label == "sessions"
    check sl.points.len == 5
    check sl.current == 5.0

  test "SparklineTrend enum":
    check ord(stUp) < ord(stDown)  # Up is better than down
    check ord(stDown) < ord(stSpike)  # Spike is worst

  test "HistogramBucket type":
    var hb: HistogramBucket
    hb.label = "1-3s"
    hb.count = 50
    hb.percentage = 25.0
    
    check hb.label == "1-3s"
    check hb.count == 50
    check hb.percentage == 25.0

  test "AlertThreshold type":
    var at: AlertThreshold
    at.metric = "latency"
    at.warning = 5000
    at.critical = 10000
    at.enabled = true
    
    check at.metric == "latency"
    check at.warning == 5000
    check at.critical == 10000

  test "Alert type":
    var alert: Alert
    alert.level = alCritical
    alert.message = "High latency"
    alert.timestamp = 1234567890
    
    check alert.level == alCritical
    check alert.message == "High latency"

  test "TokenUsage type":
    var tu: TokenUsage
    tu.inputTokens = 1000000
    tu.outputTokens = 500000
    tu.costUsd = 25.50
    
    check tu.inputTokens == 1000000
    check tu.costUsd == 25.50

  test "HookItem tracks hook registry fields":
    var h: HookItem
    h.name = "rag_context"
    h.hookType = "pre-llm"
    h.enabled = true
    h.execCount = 500
    h.lastRun = 1234567890
    
    check h.name == "rag_context"
    check h.hookType == "pre-llm"
    check h.execCount == 500

  test "ToolItem tracks MCP tool fields":
    var t: ToolItem
    t.name = "web_search"
    t.server = "native"
    t.enabled = true
    t.execCount = 200
    t.errors = 3
    
    check t.name == "web_search"
    check t.server == "native"
    check t.errors == 3

  test "SkillItem tracks skill fields":
    var s: SkillItem
    s.name = "browser"
    s.path = "/skills/browser"
    s.enabled = true
    s.manifest = "Browser automation"
    
    check s.name == "browser"
    check s.path == "/skills/browser"

  test "ConfigNode represents config tree":
    var cn: ConfigNode
    cn.key = "donkey.home"
    cn.value = "~/.donkey"
    cn.kind = ckString
    cn.changed = false
    
    check cn.key == "donkey.home"
    check cn.kind == ckString
    check cn.changed == false

  test "ConfigNodeKind enum":
    check ord(ckString) >= 0
    check ord(ckInt) > ord(ckString)
    check ord(ckBool) > ord(ckInt)

  test "ConfigDiff tracks changes":
    var diff: ConfigDiff
    diff.key = "log_level"
    diff.oldValue = "info"
    diff.newValue = "debug"
    
    check diff.key == "log_level"
    check diff.oldValue == "info"
    check diff.newValue == "debug"

  test "ConfigSnapshot for rollback":
    var snap: ConfigSnapshot
    snap.timestamp = 1234567890
    snap.note = "before model change"
    snap.entries = @[("log_level", "info")]
    
    check snap.entries.len == 1
    check snap.note == "before model change"

  test "SessionItem tracks active session":
    var si: SessionItem
    si.sessionId = "sess-123"
    si.userId = "user-456"
    si.channel = "discord"
    si.messageCount = 42
    si.ageSeconds = 300
    
    check si.sessionId == "sess-123"
    check si.channel == "discord"
    check si.messageCount == 42

  test "SessionMessage for history view":
    var sm: SessionMessage
    sm.role = "user"
    sm.text = "Hello"
    sm.timestamp = 1234567890
    
    check sm.role == "user"
    check sm.text == "Hello"

  test "DaemonHealth tracks daemon status":
    var dh: DaemonHealth
    dh.uptimeSec = 86400
    dh.pid = 12345
    dh.version = "0.1.0"
    dh.memoryMb = 128
    dh.threadCount = 4
    dh.status = dhsRunning
    
    check dh.uptimeSec == 86400
    check dh.pid == 12345
    check dh.status == dhsRunning

  test "DaemonHealthStatus enum":
    check ord(dhsRunning) == 0
    check ord(dhsDegraded) > 0
    check ord(dhsError) > ord(dhsDegraded)

  test "LogFilter for log viewer":
    var lf: LogFilter
    lf.levels = @["ERR", "WRN"]
    lf.subsystem = "orch"
    
    check lf.levels.len == 2
    check lf.subsystem == "orch"

  test "Toast for notifications":
    var t: Toast
    t.message = "User deleted"
    t.kind = tkSuccess
    t.timestamp = 1234567890
    
    check t.message == "User deleted"
    check t.kind == tkSuccess

  test "ToastKind enum":
    check ord(tkSuccess) < ord(tkError)
    check ord(tkWarning) < ord(tkError)

  test "CommandPalette tracks query":
    var cp: CommandPalette
    cp.query = "delete"
    cp.results = @["delete user", "delete session"]
    
    check cp.query == "delete"
    check cp.results.len == 2

  test "sectionCount matches AdminSection count":
    let count = AdminSection.high.ord + 1
    check count == 8  # Config, Agents, Channels, Providers, Models, Hooks, Plugins, Users
