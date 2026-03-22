## t_dns_resolver.nim — integration tests for adapters/network/dns_resolver.nim
##
## Tests use only system-local hostnames (localhost) and guaranteed-invalid
## domains to avoid external network dependencies.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/dns
import donkey/adapters/network/dns_resolver

# ── safeResolve — SSRF blocking ────────────────────────────────────────────────

suite "dns_resolver — safeResolve SSRF protection":

  test "localhost resolves to loopback and is blocked":
    let r = safeResolve("localhost")
    check r.isErr

  test "127.0.0.1 literal is blocked":
    let r = safeResolve("127.0.0.1")
    check r.isErr

  test "nonexistent domain returns DNS error":
    let r = safeResolve("this.domain.absolutely.does.not.exist.invalid")
    check r.isErr

  test "empty host returns Err":
    let r = safeResolve("")
    check r.isErr

# ── safeResolve via |> ─────────────────────────────────────────────────────────

suite "dns_resolver — safeResolve via |>":

  test "|> pipeline — localhost blocked":
    let r = "localhost" |> safeResolve
    check r.isErr

  test "|> pipeline — nonexistent domain blocked":
    let r = "this.host.does.not.exist.invalid" |> safeResolve
    check r.isErr

# ── safeResolve via >>= ────────────────────────────────────────────────────────

suite "dns_resolver — safeResolve >>= chaining":

  test ">>= chain stops at blocked host":
    proc openConn(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("connected: " & ip)
    let r = safeResolve("localhost") >>= openConn
    check r.isErr

  test ">>= chain stops at DNS error":
    proc openConn(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("connected: " & ip)
    let r = safeResolve("no.such.host.invalid") >>= openConn
    check r.isErr

# ── |>-> with labelledBlock (core/dns) ────────────────────────────────────────

suite "dns_resolver — labelledBlock |>-> integration":

  test "|>-> loopback IP blocked with request context":
    let r = "127.0.0.1" |>-> labelledBlock("webhook-fetch")
    check r.isErr
    check "webhook-fetch" in r.error

  test "|>-> private IP blocked with request context":
    let r = "10.0.0.1" |>-> labelledBlock("outbound-http")
    check r.isErr
    check "outbound-http" in r.error
