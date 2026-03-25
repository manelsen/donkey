## pg_helpers.nim — Shared PostgreSQL adapter boilerplate templates.
##
## Compile with -d:withPostgres to activate.
##
## Provides withDb: opens a DB connection via a.openDb(), injects `db`
## into the body, closes it via defer, and wraps body in try/except.
## Analogous to withHttpClient in adapters/http/helpers.nim.

when defined(withPostgres):
  template withDb*(a: untyped; body: untyped): untyped =
    ## Opens a DB connection via a.openDb(), injects `db` into body, closes
    ## it via defer. Returns err on openDb failure or CatchableError in body.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db {.inject.} = openResult.get
    defer: db.close()
    try:
      body
    except CatchableError as e:
      err(e.msg)
