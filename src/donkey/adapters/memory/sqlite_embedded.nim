## sqlite_embedded — embedded SQLite/sqlite-vec runtime registration.

when defined(withSqlite):
  when defined(staticSqlite):
    import db_connector/sqlite3
    import std/locks

    {.compile("sqlite-vec.c", "-O3").}

    var gEmbeddedVecLock {.global.}: Lock
    var gEmbeddedVecRegistered {.global.}: bool

    initLock(gEmbeddedVecLock)

    proc sqlite3_auto_extension(xEntryPoint: pointer): cint {.cdecl, importc.}
    proc sqlite3_vec_init(db: PSqlite3; pzErrMsg: ptr cstring; pApi: pointer): cint {.cdecl, importc.}

    proc hasEmbeddedSqliteVec*(): bool =
      true

    proc ensureEmbeddedSqliteVecRegistered*() =
      acquire(gEmbeddedVecLock)
      defer: release(gEmbeddedVecLock)
      if gEmbeddedVecRegistered:
        return
      discard sqlite3_auto_extension(cast[pointer](sqlite3_vec_init))
      gEmbeddedVecRegistered = true
  else:
    proc hasEmbeddedSqliteVec*(): bool =
      false

    proc ensureEmbeddedSqliteVecRegistered*() =
      discard
