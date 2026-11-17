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

  test "runtime port exposes a no-redirect POST":
    let port = newStdHttpAdapter().toRuntimePort()
    check port.postNoRedirect != nil

  test "newStdHttpAdapter is stateless value type":
    let a = newStdHttpAdapter()
    let b = a   ## copy — no shared state
    check true

suite "StdHttpAdapter — retry policy (TG-021)":

  test "TG-021: idempotent methods keep the retry budget":
    let a = newStdHttpAdapter(maxRetries = 3, retryNonIdempotent = false)
    check a.maxAttempts(rkIdempotent) == 3
    check a.maxAttempts(rkIdempotent) == 3

  test "TG-021: non-idempotent methods make a single attempt":
    let a = newStdHttpAdapter(maxRetries = 3, retryNonIdempotent = false)
    check a.maxAttempts(rkNonIdempotent) == 1
    check a.maxAttempts(rkNonIdempotent) == 1

  test "TG-021: the default keeps the previous behaviour":
    let a = newStdHttpAdapter(maxRetries = 3)
    check a.maxAttempts(rkNonIdempotent) == 3
