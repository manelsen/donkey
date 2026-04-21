## MarkdownMemoryAdapter contract tests — Result-based memory adapter.
## runContractTests/1 is called against every implementation.

import std/[os, strutils, unittest]
import donkey/adapters/memory/markdown
import donkey/core/types
import donkey/core/pipeops

# ── contract ─────────────────────────────────────────────────────────────────

proc runContractTests(adapter: MarkdownMemoryAdapter) =
  let uid = UserId("test-user-uuid")

  suite "MarkdownMemoryAdapter contract [" & adapter.paddocksDir & "]":

    setup:
      # Clean slate before each test.
      let pd = adapter.paddockDir(uid)
      if dirExists(pd):
        removeDir(pd)

    test "hasProfile: false when paddock absent":
      let result = adapter.hasProfile(uid)
      check result.isOk
      check result.get() == false

    test "hasProfile: false when USER.md absent but dir exists":
      discard adapter.ensurePaddock(uid)
      let result = adapter.hasProfile(uid)
      check result.isOk
      check result.get() == false

    test "hasProfile: true after saveUserMd":
      let saveResult = adapter.saveUserMd(uid, "# Alice\n")
      check saveResult.isOk
      let profileResult = adapter.hasProfile(uid)
      check profileResult.isOk
      check profileResult.get() == true

    test "loadContext: returns empty strings when no files":
      let ensureResult = adapter.ensurePaddock(uid)
      check ensureResult.isOk
      let ctx = adapter.loadContext(uid)
      check ctx.isOk
      check ctx.get().userId  == uid
      check ctx.get().userMd        == ""
      check ctx.get().memoryMd      == ""
      check ctx.get().preferencesMd == ""

    test "loadContext: reads all three files":
      discard adapter.saveUserMd(uid, "user content")
      discard adapter.appendMemory(uid, "memory content")
      discard adapter.savePreferences(uid, "prefs content")
      let ctx = adapter.loadContext(uid)
      check ctx.isOk
      check ctx.get().userMd        == "user content"
      check ctx.get().memoryMd      == "memory content"
      check ctx.get().preferencesMd == "prefs content"

    test "loadContext: ensures paddock and HEARTBEAT.md exist":
      let ctx = adapter.loadContext(uid)
      check ctx.isOk
      check dirExists(adapter.paddockDir(uid))
      check fileExists(adapter.heartbeatMdPath(uid))
      check readFile(adapter.heartbeatMdPath(uid)) == ""

    test "saveUserMd: creates paddock automatically":
      let result = adapter.saveUserMd(uid, "# Bob\n")
      check result.isOk
      check fileExists(adapter.userMdPath(uid))

    test "saveUserMd: overwrites on second call":
      discard adapter.saveUserMd(uid, "v1")
      discard adapter.saveUserMd(uid, "v2")
      let content = readFile(adapter.userMdPath(uid))
      check content == "v2"

    test "appendMemory: creates file on first call":
      let result = adapter.appendMemory(uid, "first note")
      check result.isOk
      let content = readFile(adapter.memoryMdPath(uid))
      check content == "first note"

    test "appendMemory: accumulates entries separated by newline":
      discard adapter.appendMemory(uid, "note A")
      discard adapter.appendMemory(uid, "note B")
      let content = readFile(adapter.memoryMdPath(uid))
      check content.contains("note A")
      check content.contains("note B")

    test "savePreferences: round-trips content":
      let result = adapter.savePreferences(uid, "provider: zai-coding\n")
      check result.isOk
      let content = readFile(adapter.preferencesMdPath(uid))
      check content == "provider: zai-coding\n"

    test "ensurePaddock: creates sessions/ subdirectory":
      let result = adapter.ensurePaddock(uid)
      check result.isOk
      check dirExists(adapter.paddockDir(uid) / "sessions")

    test "ensurePaddock: creates HEARTBEAT.md":
      let result = adapter.ensurePaddock(uid)
      check result.isOk
      check fileExists(adapter.heartbeatMdPath(uid))
      check readFile(adapter.heartbeatMdPath(uid)) == ""

    test "updateUserField: stores preferred name and access":
      discard adapter.updateUserField(uid, "Preferred name", "Ada")
      discard adapter.updateUserField(uid, "Access", "revoked")
      let ctx = adapter.loadContext(uid)
      check ctx.isOk
      check parseUserField(ctx.get().userMd, "Preferred name") == "Ada"
      let revoked = adapter.isRevoked(uid)
      check revoked.isOk
      check revoked.get() == true

# ── bootstrapUserMd helper ───────────────────────────────────────────────────

suite "bootstrapUserMd":

  test "includes name and preferred name":
    let md = bootstrapUserMd("Alice Wonderland", "Alice", "UTC-3", "pt-BR")
    check md.contains("Alice Wonderland")
    check md.contains("Alice")

  test "includes timezone and language":
    let md = bootstrapUserMd("Bob", "Bob", "UTC+8", "zh-CN")
    check md.contains("UTC+8")
    check md.contains("zh-CN")

  test "has YAML frontmatter":
    let md = bootstrapUserMd("X", "X", "UTC", "en")
    check md.startsWith("---\n")

# ── implementations under test ────────────────────────────────────────────────

block mdFile:
  let base = getTempDir() / "donkey_test_markdown_paddocks"
  createDir(base)
  defer: removeDir(base)
  runContractTests(MarkdownMemoryAdapter(paddocksDir: base))
