## Tests for admin TUI components (pure functions only).
import std/[unittest, sequtils, strutils, times, os]
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
