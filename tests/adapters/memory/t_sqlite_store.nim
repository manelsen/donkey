## Tests for SqliteStoreAdapter — contract tests following t_contract.nim pattern.
##
## Compile with -d:withSqlite to activate.

import std/[os, strutils, unittest, times]
import donkey/core/types
import donkey/core/pipeops
import donkey/domain/message

when defined(withSqlite):
  import donkey/adapters/memory/sqlite_store
  import donkey/domain/personality

  proc runContractTests(adapter: SqliteStoreAdapter) =
    let uid = UserId("test-user-uuid")

    suite "SqliteStoreAdapter contract [" & adapter.dbPath & "]":

      setup:
        # Clean slate before each test: delete the db file and recreate
        if fileExists(adapter.dbPath):
          removeFile(adapter.dbPath)
        discard adapter.ensureDatabase

      test "hasProfile: false when user absent":
        let r = adapter.hasProfile(uid)
        check r.isOk
        check not r.get

      test "hasProfile: true after saveUserMd":
        let r = adapter.saveUserMd(uid, "# Alice\n")
        check r.isOk
        let hr = adapter.hasProfile(uid)
        check hr.isOk
        check hr.get

      test "loadContext: returns empty strings when user absent":
        let r = adapter.loadContext(uid)
        check r.isOk
        let ctx = r.get
        check ctx.userId == uid
        check ctx.userMd == ""
        check ctx.memoryMd == ""
        check ctx.preferencesMd == ""

      test "loadContext: reads all three fields":
        discard adapter.saveUserMd(uid, "user content")
        discard adapter.appendMemory(uid, "memory content")
        discard adapter.savePreferences(uid, "prefs content")
        let r = adapter.loadContext(uid)
        check r.isOk
        let ctx = r.get
        check ctx.userMd == "user content"
        check ctx.memoryMd == "memory content"
        check ctx.preferencesMd == "prefs content"

      test "saveUserMd: stores content for later retrieval":
        discard adapter.saveUserMd(uid, "# Bob\n")
        let r = adapter.loadContext(uid)
        check r.isOk
        check r.get.userMd == "# Bob\n"

      test "saveUserMd: overwrites on second call":
        discard adapter.saveUserMd(uid, "v1")
        discard adapter.saveUserMd(uid, "v2")
        let r = adapter.loadContext(uid)
        check r.isOk
        check r.get.userMd == "v2"

      test "appendMemory: creates memory on first call":
        let r = adapter.appendMemory(uid, "first note")
        check r.isOk
        let mr = adapter.loadContext(uid)
        check mr.isOk
        check mr.get.memoryMd == "first note"

      test "appendMemory: accumulates entries separated by newline":
        discard adapter.appendMemory(uid, "note A")
        discard adapter.appendMemory(uid, "note B")
        let r = adapter.loadContext(uid)
        check r.isOk
        let content = r.get.memoryMd
        check content.contains("note A")
        check content.contains("note B")

      test "savePreferences: round-trips content":
        discard adapter.savePreferences(uid, "provider: zai-coding\n")
        let r = adapter.loadContext(uid)
        check r.isOk
        check r.get.preferencesMd == "provider: zai-coding\n"

      test "clearMemory: empties memory field":
        discard adapter.appendMemory(uid, "some memory")
        let r = adapter.clearMemory(uid)
        check r.isOk
        let mr = adapter.loadContext(uid)
        check mr.isOk
        check mr.get.memoryMd == ""

      test "saveSession: stores JSONL history":
        let hist = @[
          ChatMessage(role: "user", text: "hello", imageUrl: ""),
          ChatMessage(role: "assistant", text: "hi there", imageUrl: ""),
        ]
        let sid = $SessionId("session-123")
        let r = adapter.saveSession(uid, sid, hist)
        check r.isOk

      test "listSessions: returns session ids":
        let hist = @[
          ChatMessage(role: "user", text: "hello", imageUrl: ""),
          ChatMessage(role: "assistant", text: "hi", imageUrl: ""),
        ]
        discard adapter.saveSession(uid, $SessionId("s1"), hist)
        discard adapter.saveSession(uid, $SessionId("s2"), hist)
        let r = adapter.listSessions(uid)
        check r.isOk
        let sessions = r.get
        check sessions.contains("s1")
        check sessions.contains("s2")

      test "listUsers: returns all users":
        let uid2 = UserId("other-user")
        discard adapter.saveUserMd(uid, "# User 1\n")
        discard adapter.saveUserMd(uid2, "# User 2\n")
        let r = adapter.listUsers
        check r.isOk
        let users = r.get
        check users.len >= 2

      test "updateUserField: updates access field":
        let r = adapter.updateUserField(uid, "access", "revoked")
        check r.isOk
        let rr = adapter.isRevoked(uid)
        check rr.isOk
        check rr.get

      test "isRevoked: false when access is active":
        discard adapter.saveUserMd(uid, "# Alice\n")
        let r = adapter.isRevoked(uid)
        check r.isOk
        check not r.get

      test "hasIdentity: false when no agent_name":
        discard adapter.savePreferences(uid, "provider: zai\n")
        let r = adapter.hasIdentity(uid)
        check r.isOk
        check not r.get

      test "hasIdentity: true when agent_name present":
        discard adapter.savePreferences(uid, "agent_name = \"Donkey\"\n")
        let r = adapter.hasIdentity(uid)
        check r.isOk
        check r.get

      test "saveIdentity and loadIdentity round-trip":
        let traits = PersonalityTraits(
          energy: "high",
          tone: "friendly",
          length: "medium",
          initiative: "proactive",
        )
        let r = adapter.saveIdentity(uid, traits, "Donkey")
        check r.isOk
        let lr = adapter.loadIdentity(uid)
        check lr.isOk
        let (name, loaded) = lr.get
        check name == "Donkey"
        check loaded.energy == "high"
        check loaded.tone == "friendly"

      test "scheduleReminder: returns reminder id":
        let past = getTime().toUnix() - 100
        let r = adapter.scheduleReminder(uid, "telegram", past, "Hello")
        check r.isOk
        check r.get.len > 0

      test "loadDueReminders: returns due reminders":
        let past = getTime().toUnix() - 200
        discard adapter.scheduleReminder(uid, "telegram", past, "past reminder")
        let r = adapter.loadDueReminders
        check r.isOk
        let due = r.get
        check due.len > 0

      test "deleteReminder: removes reminder":
        let past = getTime().toUnix() - 300
        let ridResult = adapter.scheduleReminder(uid, "telegram", past, "to delete")
        check ridResult.isOk
        let rid = ridResult.get
        let r = adapter.deleteReminder(uid, rid)
        check r.isOk

  # ── implementations under test ────────────────────────────────────────────────

  block sqliteStore:
    let dbPath = getTempDir() / "donkey_test_sqlite.db"
    if fileExists(dbPath):
      removeFile(dbPath)
    defer:
      if fileExists(dbPath):
        removeFile(dbPath)
    runContractTests(SqliteStoreAdapter(dbPath: dbPath))

  block ensureDatabase:
    test "ensureDatabase: creates schema without error":
      let dbPath = getTempDir() / "donkey_test_init.db"
      if fileExists(dbPath):
        removeFile(dbPath)
      defer:
        if fileExists(dbPath):
          removeFile(dbPath)
      let adapter = SqliteStoreAdapter(dbPath: dbPath)
      let r = adapter.ensureDatabase
      check r.isOk
