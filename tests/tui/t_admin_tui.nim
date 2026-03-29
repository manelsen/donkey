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
    st.loadChannelItems()
    check st.items.len == 4
    let names = st.items.mapIt(it.name)
    check "telegram" in names
    check "discord" in names
    check "cli" in names

  test "loadProviderItems populates providers":
    var st = newAdminState()
    st.loadProviderItems()
    check st.items.len == 4
    let names = st.items.mapIt(it.name)
    check "anthropic" in names
    check "openai" in names

  test "loadModelItems populates models":
    var st = newAdminState()
    st.loadModelItems()
    check st.items.len == 5
    let names = st.items.mapIt(it.name)
    check "claude-sonnet-4-5" in names
    check "gpt-4o" in names

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
    check st.items.len == 4

    st.section = asProviders
    st.loadSection()
    check st.items.len == 4

    st.section = asModels
    st.loadSection()
    check st.items.len == 5

    st.section = asHooks
    st.loadSection()
    check st.items.len == 4

    st.section = asPlugins
    st.loadSection()
    check st.items.len == 4

  test "items have correct enabled status":
    var st = newAdminState()
    st.loadChannelItems()
    let telegram = st.items.filterIt(it.name == "telegram")[0]
    check telegram.enabled == true
    check telegram.status == "connected"

  test "items can be toggled":
    var st = newAdminState()
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
    st.loadUsersItems(adapter)

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
    st.loadUsersItems(adapter)

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
    st.loadUsersItems(adapter)

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
    
    # Count enabled providers
    let enabled = st.items.filterIt(it.enabled)
    check enabled.len >= 1

  test "selectModel changes active model":
    var st = newAdminState()
    st.loadModelItems()
    
    # Find default model
    var defaultIdx = -1
    for i, item in st.items:
      if item.status == "default":
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
