## SQLite durability pragmas.
##
## The runtime relies on WAL for concurrent reads, NORMAL synchronous for a
## durable-enough commit without an fsync per write, and a busy timeout so a
## concurrent writer waits instead of failing with SQLITE_BUSY.

import std/[os, strutils, unittest]

when defined(withSqlite):
  import db_connector/db_sqlite
  import donkey/adapters/memory/sqlite_magma_store

  proc freshDir(tag: string): string =
    result = getTempDir() / ("donkey_sqlite_" & tag & "_" & $getCurrentProcessId())
    removeDir(result)
    createDir(result)

  suite "sqlite durability pragmas":

    test "magma store opens in WAL with a busy timeout":
      let dir = freshDir("magma")
      defer: removeDir(dir)
      let adapter = newSqliteMagmaStoreAdapter(dir / "magma.db")
      let db = adapter.openDb()
      check $db.getValue(sql"PRAGMA journal_mode") == "wal"
      check $db.getValue(sql"PRAGMA synchronous") == "1"
      check $db.getValue(sql"PRAGMA busy_timeout") == "5000"
      db.close()

    test "WAL survives a reopen":
      let dir = freshDir("reopen")
      defer: removeDir(dir)
      let path = dir / "magma.db"
      block:
        let db = newSqliteMagmaStoreAdapter(path).openDb()
        check $db.getValue(sql"PRAGMA journal_mode") == "wal"
        db.close()
      let db = newSqliteMagmaStoreAdapter(path).openDb()
      check $db.getValue(sql"PRAGMA journal_mode") == "wal"
      check $db.getValue(sql"PRAGMA busy_timeout") == "5000"
      db.close()
