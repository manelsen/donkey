## SessionManager unit tests.
## Verifies session creation, channel tracking, and listing.

import std/unittest
import donkey/app/session_manager
import donkey/domain/message
import donkey/core/types

suite "SessionManager":

  test "hasSession returns false for unknown user":
    var sm: SessionManager
    sm.init()
    check not sm.hasSession(UserId("unknown-uuid"))

  test "getOrCreate creates a session":
    var sm: SessionManager
    sm.init()
    let uid = UserId("test-uuid-1")
    let isNew = not sm.hasSession(uid)
    let entry = sm.getOrCreate(uid)
    check isNew
    check sm.hasSession(uid)
    check entry != nil

  test "getOrCreate returns same entry on repeated calls":
    var sm: SessionManager
    sm.init()
    let uid = UserId("test-uuid-2")
    let e1 = sm.getOrCreate(uid)
    let e2 = sm.getOrCreate(uid)
    ## Both point to the same session entry.
    check e1.inbox == e2.inbox

  test "recordChannel adds channels":
    var sm: SessionManager
    sm.init()
    let uid = UserId("test-uuid-3")
    discard sm.getOrCreate(uid)
    sm.recordChannel(uid, ckTelegram, "12345")
    sm.recordChannel(uid, ckDiscord,  "67890")
    let entry = sm.get(uid)
    check entry.channels.len == 2
    check (ckTelegram, "12345") in entry.channels
    check (ckDiscord, "67890")  in entry.channels

  test "recordChannel is idempotent":
    var sm: SessionManager
    sm.init()
    let uid = UserId("test-uuid-4")
    discard sm.getOrCreate(uid)
    sm.recordChannel(uid, ckTelegram, "42")
    sm.recordChannel(uid, ckTelegram, "42")
    check sm.get(uid).channels.len == 1

  test "listSessions returns all sessions":
    var sm: SessionManager
    sm.init()
    let u1 = UserId("list-uuid-1")
    let u2 = UserId("list-uuid-2")
    discard sm.getOrCreate(u1)
    discard sm.getOrCreate(u2)
    sm.recordChannel(u1, ckTelegram, "1")
    sm.recordChannel(u2, ckDiscord,  "2")
    let sessions = sm.listSessions()
    check sessions.len == 2
    var foundU1, foundU2 = false
    for (uid, _) in sessions:
      if uid == u1: foundU1 = true
      if uid == u2: foundU2 = true
    check foundU1 and foundU2

  test "prepareEntry creates new session lease with signature":
    var sm: SessionManager
    sm.init()
    let lease = sm.prepareEntry(UserId("sig-uuid-1"), "sig-a")
    check lease.isNew
    check not lease.rebuilt
    check lease.entry != nil
    check lease.entry[].toolCatalogSignature == "sig-a"

  test "prepareEntry rebuilds runtime when signature changes":
    var sm: SessionManager
    sm.init()
    let uid = UserId("sig-uuid-2")
    let first = sm.prepareEntry(uid, "sig-a")
    first.entry[].awaitingAsk = true
    let oldInbox = first.entry[].inbox
    let oldAskInbox = first.entry[].askInbox
    let rebuilt = sm.prepareEntry(uid, "sig-b")
    check not rebuilt.isNew
    check rebuilt.rebuilt
    check rebuilt.oldInbox == oldInbox
    check rebuilt.oldAskInbox == oldAskInbox
    check rebuilt.entry[].inbox != oldInbox
    check rebuilt.entry[].askInbox != oldAskInbox
    check not rebuilt.entry[].awaitingAsk
