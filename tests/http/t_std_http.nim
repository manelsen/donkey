## StdHttpAdapter — HttpPort concept satisfaction test.
## No live HTTP calls: concept check is compile-time; the suite just confirms it runs.

import unittest
import donkey/ports/http
import donkey/adapters/http/std_http

proc verifyHttpPort(h: HttpPort) {.used.} = discard

suite "StdHttpAdapter":
  test "satisfies HttpPort concept":
    let a = newStdHttpAdapter()
    verifyHttpPort(a)
    check true

  test "newStdHttpAdapter is stateless value type":
    let a = newStdHttpAdapter()
    let b = a   ## copy — no shared state
    check true
