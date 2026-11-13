## url_policy — shared URL authority and private-address checks for SSRF gates.
##
## All callers must interpret the authority the same way the HTTP transport
## does. `parseUri` is also what `std/httpclient` uses, so policy checks cannot
## be tricked by userinfo or a path/query that looks like a host.

import std/[strutils, uri]

func fallbackHost(rawUrl: string): string =
  ## Scheme-less inputs: parseUri leaves hostname empty. Bound the authority
  ## before the first path/query/fragment, then drop credentials and port.
  let lower = rawUrl.toLowerAscii()
  let afterScheme =
    if "://" in lower: lower[lower.find("://") + 3 .. ^1] else: lower
  var hostPort = afterScheme
  for i, c in afterScheme:
    if c in {'/', '?', '#'}:
      hostPort = afterScheme[0 ..< i]
      break
  let at = hostPort.rfind('@')
  if at >= 0:
    hostPort = hostPort[at + 1 .. ^1]
  let colon = hostPort.rfind(':')
  result = hostPort
  if colon > 0:
    let afterColon = hostPort[colon + 1 .. ^1]
    if afterColon.len > 0 and afterColon.allCharsInSet({'0'..'9'}):
      result = hostPort[0 ..< colon]
  result = result.strip(chars = {'[', ']'})

func normalizeHost(host: string): string =
  result = host.toLowerAscii()
  while result.len > 0 and result[^1] == '.':
    result.setLen(result.len - 1)

func extractUrlHost*(rawUrl: string): string =
  ## Returns the authority hostname, lowercased and without a trailing dot,
  ## or "" when there is none.
  let parsed = parseUri(rawUrl)
  if parsed.hostname.len > 0:
    return normalizeHost(parsed.hostname)
  normalizeHost(fallbackHost(rawUrl))

func extractUrlPath*(rawUrl: string): string =
  ## Returns the path portion (without query/fragment), defaulting to "/".
  let parsed = parseUri(rawUrl)
  if parsed.hostname.len > 0:
    result = parsed.path
  else:
    let lower = rawUrl.toLowerAscii()
    let slash = lower.find('/')
    if slash < 0:
      return "/"
    result = lower[slash .. ^1]
    for i, c in result:
      if c in {'?', '#'}:
        result = result[0 ..< i]
        break
  if result.len == 0:
    result = "/"

func isPrivateIpv4(host: string): bool =
  if host.startsWith("127.") or host.startsWith("169.254.") or
     host.startsWith("192.168."):
    return true

  if host.startsWith("10."):
    let parts = host.split('.')
    if parts.len == 4:
      return true

  if host.startsWith("172."):
    let parts = host.split('.')
    if parts.len >= 2 and parts[1].len > 0 and
       parts[1].allCharsInSet({'0'..'9'}):
      try:
        let second = parseInt(parts[1])
        if second in 16 .. 31:
          return true
      except ValueError:
        discard  # overflow/non-numeric label: not an IPv4 literal

  false

func isPrivateUrl*(rawUrl: string): bool =
  ## Returns true when rawUrl points to a private/internal host.
  let host = extractUrlHost(rawUrl)
  if host.len == 0:
    return false

  if host in ["localhost", "localhost.localdomain", "0.0.0.0", "::", "::1"]:
    return true

  # IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1).
  if host.startsWith("::ffff:"):
    return isPrivateIpv4(host[7 .. ^1])

  if ':' in host:
    # IPv6 link-local (fe80::/10) and unique-local (fc00::/7).
    if host.startsWith("fe80:") or host.startsWith("fc") or host.startsWith("fd"):
      return true

  isPrivateIpv4(host)
