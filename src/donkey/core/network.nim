## network.nim — pure IP address validator, SSRF guard.
##
## Detects private, bogon, loopback, and link-local addresses to prevent
## internal network scanning (SSRF).
##
## Usage:
##   let r = "192.168.1.1" |> isPrivateIp     # Result[bool, string] — Ok(true)
##   let r = "8.8.8.8"     |> isPrivateIp     # Ok(false)
##   let r = "not-an-ip"   |> isPrivateIp     # Err("expected 4 octets…")
##
##   # Railway-oriented validation:
##   rawIp |> isPrivateIp >>= rejectIfPrivate

import std/[strutils]
import ./pipeops

# ── IPv4 ──────────────────────────────────────────────────────────────────────

func parseIpv4*(s: string): Result[array[4, uint8], string] =
  ## Parses an IPv4 dotted-quad string into four octets.
  ## Returns Err on malformed input (wrong segment count, non-digits, out of range).
  let parts = s.split('.')
  if parts.len != 4:
    return err("expected 4 octets, got " & $parts.len)
  var octets: array[4, uint8]
  for i, p in parts:
    if p.len == 0 or p.len > 3:
      return err("invalid octet '" & p & "'")
    if not p.allCharsInSet({'0'..'9'}):
      return err("non-digit character in octet '" & p & "'")
    let n = parseInt(p)   # safe: digits-only, len ≤ 3 → max value 999
    if n > 255:
      return err("octet out of range: " & p)
    octets[i] = uint8(n)
  ok(octets)

func isPrivateOctets*(o: array[4, uint8]): bool =
  ## Returns true when the IPv4 address belongs to a private, bogon,
  ## loopback, or otherwise non-public range.
  ##
  ## Ranges covered:
  ##   0.0.0.0/8        — "this" network (RFC 1122)
  ##   10.0.0.0/8       — private (RFC 1918)
  ##   100.64.0.0/10    — CGNAT (RFC 6598)
  ##   127.0.0.0/8      — loopback (RFC 1122)
  ##   169.254.0.0/16   — link-local / APIPA / cloud metadata (RFC 3927)
  ##   172.16.0.0/12    — private (RFC 1918)
  ##   192.168.0.0/16   — private (RFC 1918)
  ##   198.18.0.0/15    — network benchmarking (RFC 2544)
  ##   198.51.100.0/24  — documentation TEST-NET-2 (RFC 5737)
  ##   203.0.113.0/24   — documentation TEST-NET-3 (RFC 5737)
  ##   233.252.0.0/24   — documentation multicast (RFC 5771)
  ##   240.0.0.0/4      — reserved (includes 255.255.255.255) (RFC 1112)
  let a = int(o[0])
  let b = int(o[1])
  let c = int(o[2])
  if a == 0:                              return true   # 0.0.0.0/8
  if a == 10:                             return true   # 10.0.0.0/8
  if a == 100 and b >= 64 and b <= 127:   return true   # 100.64.0.0/10 CGNAT
  if a == 127:                            return true   # 127.0.0.0/8 loopback
  if a == 169 and b == 254:              return true   # 169.254.0.0/16 link-local
  if a == 172 and b >= 16 and b <= 31:   return true   # 172.16.0.0/12
  if a == 192 and b == 168:              return true   # 192.168.0.0/16
  if a == 198 and b >= 18 and b <= 19:   return true   # 198.18.0.0/15 benchmarking
  if a == 198 and b == 51 and c == 100:  return true   # 198.51.100.0/24 doc
  if a == 203 and b == 0 and c == 113:   return true   # 203.0.113.0/24 doc
  if a == 233 and b == 252 and c == 0:   return true   # 233.252.0.0/24 doc mcast
  if a >= 240:                           return true   # 240.0.0.0/4 reserved + bcast
  false

# ── IPv6 ──────────────────────────────────────────────────────────────────────

func isPrivateIpv6*(s: string): bool =
  ## Returns true when s is a private, loopback, or link-local IPv6 address.
  ## Performs textual prefix matching — not a full RFC-compliant parser.
  ##
  ## Ranges covered:
  ##   ::1              — loopback (RFC 4291)
  ##   ::               — unspecified (RFC 4291)
  ##   fe80::/10        — link-local (RFC 4291)
  ##   fc00::/7         — unique local (fc00:: and fd00::) (RFC 4193)
  ##   ::ffff:0:0/96    — IPv4-mapped (RFC 4291)
  let lower = s.toLowerAscii()
  if lower == "::1":                     return true   # loopback
  if lower == "::":                      return true   # unspecified
  if lower.startsWith("fe80"):           return true   # link-local fe80::/10
  if lower.startsWith("fc"):             return true   # unique local fc00::/7
  if lower.startsWith("fd"):             return true   # unique local fd00::/8
  if lower.startsWith("::ffff:"):        return true   # IPv4-mapped
  false

# ── unified entry point ───────────────────────────────────────────────────────

func isPrivateIp*(ip: string): Result[bool, string] =
  ## Returns Ok(true) when ip is a private, bogon, loopback, or link-local
  ## address. Returns Ok(false) for public addresses. Returns Err when ip
  ## cannot be parsed as a valid IPv4 or IPv6 address.
  ##
  ## Designed as a unary function for |> piping and >>= chaining:
  ##   "10.0.0.1"    |> isPrivateIp   → Ok(true)
  ##   "8.8.8.8"     |> isPrivateIp   → Ok(false)
  ##   "::1"         |> isPrivateIp   → Ok(true)
  ##   "not-an-ip"   |> isPrivateIp   → Err("expected 4 octets…")
  if ':' in ip:
    return ok(ip |> isPrivateIpv6)
  let octets = ? parseIpv4(ip)
  ok(octets |> isPrivateOctets)
