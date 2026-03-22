## t_network.nim — unit tests for core/network.nim
##
## Covers parseIpv4, isPrivateOctets, isPrivateIpv6, and isPrivateIp
## including pipeline-operator usage (|>, >>=).

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/network

# ── parseIpv4 ─────────────────────────────────────────────────────────────────

suite "network — parseIpv4":

  test "valid dotted-quad parses correctly":
    let r = parseIpv4("10.20.30.40")
    check r.isOk
    check r.get() == [10u8, 20u8, 30u8, 40u8]

  test "all-zeros":
    check parseIpv4("0.0.0.0").isOk

  test "max valid address":
    let r = parseIpv4("255.255.255.255")
    check r.isOk
    check r.get() == [255u8, 255u8, 255u8, 255u8]

  test "loopback":
    let r = parseIpv4("127.0.0.1")
    check r.isOk
    check r.get() == [127u8, 0u8, 0u8, 1u8]

  test "octet out of range returns Err":
    check parseIpv4("256.0.0.0").isErr
    check parseIpv4("0.0.0.256").isErr
    check parseIpv4("0.999.0.0").isErr

  test "too few segments returns Err":
    check parseIpv4("1.2.3").isErr

  test "too many segments returns Err":
    check parseIpv4("1.2.3.4.5").isErr

  test "non-digit octet returns Err":
    check parseIpv4("a.b.c.d").isErr
    check parseIpv4("192.168.1.x").isErr

  test "empty octet returns Err":
    check parseIpv4("1..2.3").isErr
    check parseIpv4(".1.2.3").isErr

  test "octet string too long returns Err":
    check parseIpv4("1234.0.0.0").isErr

# ── isPrivateOctets ───────────────────────────────────────────────────────────

suite "network — isPrivateOctets":

  test "10.x.x.x is private (RFC 1918)":
    check isPrivateOctets([10u8, 0u8, 0u8, 1u8])
    check isPrivateOctets([10u8, 255u8, 255u8, 255u8])

  test "172.16–31.x.x is private (RFC 1918)":
    check isPrivateOctets([172u8, 16u8, 0u8, 1u8])
    check isPrivateOctets([172u8, 31u8, 255u8, 255u8])

  test "172.15.x.x is NOT private":
    check not isPrivateOctets([172u8, 15u8, 0u8, 1u8])

  test "172.32.x.x is NOT private":
    check not isPrivateOctets([172u8, 32u8, 0u8, 1u8])

  test "192.168.x.x is private (RFC 1918)":
    check isPrivateOctets([192u8, 168u8, 0u8, 1u8])
    check isPrivateOctets([192u8, 168u8, 255u8, 255u8])

  test "127.x.x.x is loopback":
    check isPrivateOctets([127u8, 0u8, 0u8, 1u8])
    check isPrivateOctets([127u8, 255u8, 255u8, 255u8])

  test "169.254.x.x is link-local / cloud metadata":
    check isPrivateOctets([169u8, 254u8, 0u8, 1u8])
    check isPrivateOctets([169u8, 254u8, 169u8, 254u8])

  test "0.x.x.x is bogon":
    check isPrivateOctets([0u8, 0u8, 0u8, 0u8])
    check isPrivateOctets([0u8, 255u8, 255u8, 255u8])

  test "100.64–127.x.x is CGNAT (RFC 6598)":
    check isPrivateOctets([100u8, 64u8, 0u8, 1u8])
    check isPrivateOctets([100u8, 127u8, 255u8, 255u8])

  test "100.63.x.x is NOT CGNAT":
    check not isPrivateOctets([100u8, 63u8, 0u8, 1u8])

  test "100.128.x.x is NOT CGNAT":
    check not isPrivateOctets([100u8, 128u8, 0u8, 1u8])

  test "198.18–19.x.x is benchmarking range":
    check isPrivateOctets([198u8, 18u8, 0u8, 1u8])
    check isPrivateOctets([198u8, 19u8, 255u8, 255u8])

  test "198.51.100.x is documentation (TEST-NET-2)":
    check isPrivateOctets([198u8, 51u8, 100u8, 1u8])

  test "203.0.113.x is documentation (TEST-NET-3)":
    check isPrivateOctets([203u8, 0u8, 113u8, 1u8])

  test "240.x.x.x is reserved":
    check isPrivateOctets([240u8, 0u8, 0u8, 1u8])

  test "255.255.255.255 is broadcast":
    check isPrivateOctets([255u8, 255u8, 255u8, 255u8])

  test "well-known public addresses are not private":
    check not isPrivateOctets([8u8, 8u8, 8u8, 8u8])     # Google DNS
    check not isPrivateOctets([1u8, 1u8, 1u8, 1u8])     # Cloudflare
    check not isPrivateOctets([9u8, 9u8, 9u8, 9u8])     # Quad9

  test "203.0.114.x is NOT documentation":
    check not isPrivateOctets([203u8, 0u8, 114u8, 1u8])

# ── isPrivateIpv6 ─────────────────────────────────────────────────────────────

suite "network — isPrivateIpv6":

  test "::1 is loopback":
    check isPrivateIpv6("::1")

  test ":: is unspecified":
    check isPrivateIpv6("::")

  test "fe80:: is link-local":
    check isPrivateIpv6("fe80::1")
    check isPrivateIpv6("fe80::dead:beef")

  test "fc00:: is unique local":
    check isPrivateIpv6("fc00::1")

  test "fd00:: is unique local":
    check isPrivateIpv6("fd00::1")
    check isPrivateIpv6("fd12:3456:789a::1")

  test "::ffff: is IPv4-mapped":
    check isPrivateIpv6("::ffff:192.168.1.1")
    check isPrivateIpv6("::ffff:10.0.0.1")

  test "public IPv6 addresses are not private":
    check not isPrivateIpv6("2001:db8::1")
    check not isPrivateIpv6("2606:4700::1111")
    check not isPrivateIpv6("2001:4860:4860::8888")

# ── isPrivateIp (unified, |> pipeline) ───────────────────────────────────────

suite "network — isPrivateIp via |>":

  test "private IPv4 returns Ok(true)":
    let r = "192.168.1.1" |> isPrivateIp
    check r.isOk
    check r.get()

  test "10.x.x.x returns Ok(true)":
    let r = "10.0.0.1" |> isPrivateIp
    check r.isOk
    check r.get()

  test "loopback 127.0.0.1 returns Ok(true)":
    let r = "127.0.0.1" |> isPrivateIp
    check r.isOk
    check r.get()

  test "link-local 169.254.x.x returns Ok(true)":
    let r = "169.254.169.254" |> isPrivateIp
    check r.isOk
    check r.get()

  test "public IPv4 returns Ok(false)":
    let r = "8.8.8.8" |> isPrivateIp
    check r.isOk
    check not r.get()

  test "another public IPv4 returns Ok(false)":
    let r = "1.1.1.1" |> isPrivateIp
    check r.isOk
    check not r.get()

  test "private IPv6 ::1 returns Ok(true)":
    let r = "::1" |> isPrivateIp
    check r.isOk
    check r.get()

  test "private IPv6 fe80:: returns Ok(true)":
    let r = "fe80::1" |> isPrivateIp
    check r.isOk
    check r.get()

  test "public IPv6 returns Ok(false)":
    let r = "2001:db8::1" |> isPrivateIp
    check r.isOk
    check not r.get()

  test "malformed string returns Err":
    check ("not-an-ip" |> isPrivateIp).isErr

  test "octet out of range returns Err":
    check ("999.0.0.1" |> isPrivateIp).isErr

  test "too few segments returns Err":
    check ("1.2.3" |> isPrivateIp).isErr

# ── >>= chaining ──────────────────────────────────────────────────────────────

suite "network — isPrivateIp >>= chaining":

  test ">>= rejects private addresses":
    proc rejectPrivate(priv: bool): Result[string, string] {.gcsafe, raises: [].} =
      if priv: err("blocked: private address")
      else: ok("allowed")

    let r = "10.0.0.1" |> isPrivateIp >>= rejectPrivate
    check r.isErr
    check "blocked" in r.error

  test ">>= passes public addresses through":
    proc rejectPrivate(priv: bool): Result[string, string] {.gcsafe, raises: [].} =
      if priv: err("blocked: private address")
      else: ok("allowed")

    let r = "8.8.8.8" |> isPrivateIp >>= rejectPrivate
    check r.isOk
    check r.get() == "allowed"

  test ">>= short-circuits on parse error":
    proc rejectPrivate(priv: bool): Result[string, string] {.gcsafe, raises: [].} =
      if priv: err("blocked")
      else: ok("allowed")

    let r = "not-an-ip" |> isPrivateIp >>= rejectPrivate
    check r.isErr
