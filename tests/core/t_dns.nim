## t_dns.nim — unit tests for core/dns.nim
##
## Covers blockIfPrivate and labelledBlock including all three
## pipeline-operator forms: |>, |>->, >>=.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/dns

# ── blockIfPrivate ─────────────────────────────────────────────────────────────

suite "dns — blockIfPrivate":

  test "public IPv4 passes through":
    let r = blockIfPrivate("8.8.8.8")
    check r.isOk
    check r.get() == "8.8.8.8"

  test "another public IPv4 passes through":
    let r = blockIfPrivate("1.1.1.1")
    check r.isOk
    check r.get() == "1.1.1.1"

  test "loopback 127.0.0.1 is blocked":
    let r = blockIfPrivate("127.0.0.1")
    check r.isErr
    check "SSRF blocked" in r.error

  test "private RFC1918 10.x is blocked":
    check blockIfPrivate("10.0.0.1").isErr

  test "private RFC1918 192.168.x is blocked":
    check blockIfPrivate("192.168.1.1").isErr

  test "private RFC1918 172.16.x is blocked":
    check blockIfPrivate("172.16.0.1").isErr

  test "link-local 169.254.x is blocked (cloud metadata endpoint)":
    let r = blockIfPrivate("169.254.169.254")
    check r.isErr
    check "private" in r.error

  test "IPv6 loopback ::1 is blocked":
    check blockIfPrivate("::1").isErr

  test "IPv6 link-local fe80:: is blocked":
    check blockIfPrivate("fe80::1").isErr

  test "public IPv6 passes through":
    let r = blockIfPrivate("2606:4700::1111")
    check r.isOk
    check r.get() == "2606:4700::1111"

  test "malformed IP propagates parse error":
    let r = blockIfPrivate("not.an.ip")
    check r.isErr

  test "empty string returns Err":
    check blockIfPrivate("").isErr

# ── blockIfPrivate via |> ──────────────────────────────────────────────────────

suite "dns — blockIfPrivate via |>":

  test "|> pipeline — public IP ok":
    let r = "1.1.1.1" |> blockIfPrivate
    check r.isOk
    check r.get() == "1.1.1.1"

  test "|> pipeline — private IP blocked":
    let r = "192.168.0.1" |> blockIfPrivate
    check r.isErr

  test "|> pipeline — loopback blocked":
    let r = "127.0.0.1" |> blockIfPrivate
    check r.isErr

  test "|> pipeline — malformed returns Err":
    let r = "bad-input" |> blockIfPrivate
    check r.isErr

# ── labelledBlock via |>-> ──────────────────────────────────────────────────────

suite "dns — labelledBlock via |>->":

  test "|>-> public IP passes through":
    let r = "8.8.4.4" |>-> labelledBlock("resolver")
    check r.isOk
    check r.get() == "8.8.4.4"

  test "|>-> private IP blocked with label prefix":
    let r = "10.0.0.1" |>-> labelledBlock("resolver")
    check r.isErr
    check "resolver" in r.error

  test "|>-> loopback blocked":
    let r = "127.0.0.1" |>-> labelledBlock("outbound")
    check r.isErr
    check "outbound" in r.error

  test "|>-> link-local blocked":
    let r = "169.254.169.254" |>-> labelledBlock("http-client")
    check r.isErr
    check "http-client" in r.error

  test "|>-> label appears in error message":
    let r = "172.16.5.5" |>-> labelledBlock("my-context")
    check r.isErr
    check "my-context" in r.error
    check "172.16.5.5" in r.error

  test "|>-> public IPv6 passes through":
    let r = "2001:db8::1" |>-> labelledBlock("check")
    check r.isOk

# ── >>= chaining ───────────────────────────────────────────────────────────────

suite "dns — >>= chaining":

  test ">>= public IP chains to next step":
    proc wrapOk(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("safe: " & ip)
    let r = "8.8.8.8" |> blockIfPrivate >>= wrapOk
    check r.isOk
    check r.get() == "safe: 8.8.8.8"

  test ">>= private IP short-circuits chain":
    proc wrapOk(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("safe: " & ip)
    let r = "10.0.0.1" |> blockIfPrivate >>= wrapOk
    check r.isErr
    check "SSRF blocked" in r.error

  test ">>= parse error short-circuits chain":
    proc wrapOk(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("safe: " & ip)
    let r = "not-an-ip" |> blockIfPrivate >>= wrapOk
    check r.isErr

  test ">>= chaining with labelledBlock":
    proc accept(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("accepted: " & ip)
    let r = ("1.2.3.4" |>-> labelledBlock("test")) >>= accept
    check r.isOk
    check "accepted: 1.2.3.4" == r.get()

  test ">>= multi-step chain — public IP flows through all steps":
    proc addScheme(ip: string): Result[string, string] {.gcsafe, raises: [].} =
      ok("https://" & ip)
    proc addPort(url: string): Result[string, string] {.gcsafe, raises: [].} =
      ok(url & ":443")
    let r = "9.9.9.9" |> blockIfPrivate >>= addScheme >>= addPort
    check r.isOk
    check r.get() == "https://9.9.9.9:443"
