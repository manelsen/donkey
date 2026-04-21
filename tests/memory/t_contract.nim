## MemoryPort contract tests — nullclaw pattern.
## runContractTests/1 is called against every implementation.

import std/[os, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/ports/memory
import donkey/core/types

proc verifyMemoryPort(m: MemoryPort) {.used.} = discard

# ── contract ──────────────────────────────────────────────────────────────────

proc runContractTests(adapter: MdFileAdapter) =
  let uid = UserId("test-user-uuid")

  suite "MemoryPort contract [" & adapter.paddocksDir & "]":

    setup:
      # Clean slate before each test.
      let pd = adapter.paddockDir(uid)
      if dirExists(pd):
        removeDir(pd)

    test "hasProfile: false when paddock absent":
      check not adapter.hasProfile(uid)

    test "hasProfile: false when USER.md absent but dir exists":
      createDir(adapter.paddockDir(uid))
      check not adapter.hasProfile(uid)

    test "hasProfile: true after saveUserMd":
      adapter.saveUserMd(uid, "# Alice\n")
      check adapter.hasProfile(uid)

    test "loadContext: returns empty strings when no files":
      adapter.ensurePaddock(uid)
      let ctx = adapter.loadContext(uid)
      check ctx.userId  == uid
      check ctx.userMd        == ""
      check ctx.memoryMd      == ""
      check ctx.preferencesMd == ""

    test "loadContext: reads all three files":
      adapter.saveUserMd(uid, "user content")
      adapter.appendMemory(uid, "memory content")
      adapter.savePreferences(uid, "prefs content")
      let ctx = adapter.loadContext(uid)
      check ctx.userMd        == "user content"
      check ctx.memoryMd      == "memory content"
      check ctx.preferencesMd == "prefs content"

    test "loadContext: ensures paddock and HEARTBEAT.md exist":
      let ctx = adapter.loadContext(uid)
      discard ctx
      check dirExists(adapter.paddockDir(uid))
      check fileExists(adapter.heartbeatMdPath(uid))
      check readFile(adapter.heartbeatMdPath(uid)) == ""

    test "saveUserMd: creates paddock automatically":
      adapter.saveUserMd(uid, "# Bob\n")
      check fileExists(adapter.userMdPath(uid))

    test "saveUserMd: overwrites on second call":
      adapter.saveUserMd(uid, "v1")
      adapter.saveUserMd(uid, "v2")
      check readFile(adapter.userMdPath(uid)) == "v2"

    test "appendMemory: creates file on first call":
      adapter.appendMemory(uid, "first note")
      check readFile(adapter.memoryMdPath(uid)) == "first note"

    test "appendMemory: accumulates entries separated by newline":
      adapter.appendMemory(uid, "note A")
      adapter.appendMemory(uid, "note B")
      let content = readFile(adapter.memoryMdPath(uid))
      check content.contains("note A")
      check content.contains("note B")

    test "savePreferences: round-trips content":
      adapter.savePreferences(uid, "provider: zai-coding\n")
      check readFile(adapter.preferencesMdPath(uid)) == "provider: zai-coding\n"

    test "resetBootstrap removes profile and preferences but keeps episodic memory":
      adapter.saveUserMd(uid, "# Alice\n")
      adapter.savePreferences(uid, "language = \"pt-BR\"\n")
      adapter.appendMemory(uid, "memory content")
      adapter.resetBootstrap(uid)
      check not fileExists(adapter.userMdPath(uid))
      check not fileExists(adapter.preferencesMdPath(uid))
      check fileExists(adapter.memoryMdPath(uid))
      check readFile(adapter.memoryMdPath(uid)) == "memory content"
      check not adapter.hasProfile(uid)

    test "ensurePaddock: creates sessions/ subdirectory":
      adapter.ensurePaddock(uid)
      check dirExists(adapter.paddockDir(uid) / "sessions")

    test "ensurePaddock: creates HEARTBEAT.md":
      adapter.ensurePaddock(uid)
      check fileExists(adapter.heartbeatMdPath(uid))
      check readFile(adapter.heartbeatMdPath(uid)) == ""

    test "updateUserField: stores preferred name and access":
      adapter.updateUserField(uid, "Preferred name", "Ada")
      adapter.updateUserField(uid, "Access", "revoked")
      let ctx = adapter.loadContext(uid)
      check parseUserField(ctx.userMd, "Preferred name") == "Ada"
      check adapter.isRevoked(uid)

# ── bootstrapUserMd helper ────────────────────────────────────────────────────

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
  let base = getTempDir() / "donkey_test_paddocks"
  createDir(base)
  defer: removeDir(base)
  runContractTests(MdFileAdapter(paddocksDir: base))

suite "MdFileAdapter satisfies MemoryPort concept":

  test "compile-time concept check passes":
    let a = MdFileAdapter(paddocksDir: getTempDir())
    verifyMemoryPort(a)
    check true
