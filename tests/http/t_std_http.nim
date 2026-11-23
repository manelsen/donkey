## StdHttpAdapter — HttpPort concept satisfaction test.
## No live HTTP calls: concept check is compile-time; the suite just confirms it runs.

import std/[options, unittest]
import donkey/ports/http
import donkey/adapters/http/std_http

proc verifyHttpPort(h: HttpPort) {.used.} = discard

proc runTests*() =
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

  suite "StdHttpAdapter — 429 wait":
    proc resp(body: string; headers: seq[HttpHeader] = @[]): HttpResponse =
      HttpResponse(status: 429, body: body, headers: headers)

    test "Telegram: parameters.retry_after in seconds":
      check rateLimitWaitMs(resp("""{"ok":false,"parameters":{"retry_after":3}}""")) ==
        some(3000)

    test "Discord: a top-level fractional retry_after":
      check rateLimitWaitMs(resp("""{"message":"You are being rate limited.",
        "retry_after":0.64,"global":false}""")) == some(640)

    test "the Retry-After header wins over the body":
      check rateLimitWaitMs(resp("""{"retry_after":9}""",
        @[("Retry-After", "2")])) == some(2000)
      check rateLimitWaitMs(resp("", @[("retry-after", "1.5")])) == some(1500)

    test "no hint waits the default":
      check rateLimitWaitMs(resp("not json")) == some(5000)
      check rateLimitWaitMs(resp("""{"retry_after":"soon"}""")) == some(5000)

    test "a wait beyond the cap is not slept; the call fails instead":
      ## A global ban can ask for hours: blocking the caller that long is
      ## worse than reporting the 429.
      check rateLimitWaitMs(resp("""{"retry_after":3600}""")).isNone

    test "a zero or negative hint still waits a little":
      check rateLimitWaitMs(resp("""{"retry_after":0}""")) == some(100)

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

when isMainModule:
  runTests()
