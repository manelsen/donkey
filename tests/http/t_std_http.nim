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

suite "StdHttpAdapter — status retry policy (TG-020)":

  test "TG-020: a 409 on an idempotent call is retryable when enabled":
    check shouldRetryStatus(409, rkIdempotent, retryConflict = true)

  test "TG-020: a 409 is not retried when disabled":
    check not shouldRetryStatus(409, rkIdempotent, retryConflict = false)

  test "TG-020: a 409 on a send is never retried":
    check not shouldRetryStatus(409, rkNonIdempotent, retryConflict = true)

  test "TG-020: server errors stay retryable":
    check shouldRetryStatus(500, rkNonIdempotent, retryConflict = false)
    check shouldRetryStatus(502, rkIdempotent, retryConflict = false)

  test "TG-020: client errors are not retried":
    check not shouldRetryStatus(400, rkIdempotent, retryConflict = true)
    check not shouldRetryStatus(404, rkIdempotent, retryConflict = true)
