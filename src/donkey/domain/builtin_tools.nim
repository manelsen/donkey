## Built-in native tools — tool metadata and pure helpers.
## Side-effectful execution (HTTP calls, clock) lives in app/native_tools.nim.

import std/[strutils, times]
import ../config/types

# ── web_fetch ─────────────────────────────────────────────────────────────────

const
  WebFetchToolName* = "web_fetch"
  WebAllowlistEnvVar* = "DONKEY_WEB_ALLOWLIST"

  WebFetchToolDescription* =
    "Fetch the text content of a public URL. " &
    "Use when the user asks you to read a web page, check documentation, " &
    "or access any public HTTP endpoint. " &
    "Do NOT use for private/internal network addresses. " &
    "When a web allowlist is configured, only allowlisted hosts may be accessed."

  WebFetchToolSchema* =
    "{\"type\":\"object\",\"properties\":{" &
    "\"url\":{\"type\":\"string\",\"description\":\"Public URL to fetch\"}," &
    "\"max_chars\":{\"type\":\"integer\"," &
    "\"description\":\"Max characters to return (default: 3000, hard cap: 8000)\"}" &
    "},\"required\":[\"url\"]}"

  DefaultMaxChars* = 3_000
  HardMaxChars*    = 8_000

# ── current_time ──────────────────────────────────────────────────────────────

const
  CurrentTimeToolName* = "current_time"

  CurrentTimeToolDescription* =
    "Returns the current UTC date and time. " &
    "Use when the user asks what time or day it is, or when you need to " &
    "compute deadlines, schedules, or relative time expressions."

  CurrentTimeToolSchema* =
    "{\"type\":\"object\",\"properties\":{}}"

# ── pure helpers ──────────────────────────────────────────────────────────────

func truncateBody*(body: string; maxChars: int): string =
  ## Truncates body to min(maxChars, HardMaxChars), appending a marker.
  let cap = min(maxChars, HardMaxChars)
  if body.len <= cap: body
  else: body[0 ..< cap] & "\n[...truncated]"

func isPrivateUrl*(rawUrl: string): bool =
  ## Returns true when rawUrl points to a private/internal host.
  ## Guards against SSRF — checks localhost, 127.x, 10.x, 192.168.x,
  ## 169.254.x (link-local/cloud metadata), and 172.16-31.x.
  let lower = rawUrl.toLowerAscii()

  # Strip scheme.
  let afterScheme =
    if "://" in lower: lower[lower.find("://") + 3 .. ^1] else: lower

  # Strip credentials (user:pass@host).
  let afterAt =
    if "@" in afterScheme:
      afterScheme[afterScheme.rfind('@') + 1 .. ^1]
    else:
      afterScheme

  # Isolate host (stop at first '/', '?', '#').
  var hostPort = afterAt
  for i, c in afterAt:
    if c in {'/', '?', '#'}:
      hostPort = afterAt[0 ..< i]
      break

  # Strip port (last ':NNN' where NNN is all digits).
  let colon = hostPort.rfind(':')
  var host  = hostPort
  if colon > 0:
    let afterColon = hostPort[colon + 1 .. ^1]
    if afterColon.len > 0 and afterColon.allCharsInSet({'0'..'9'}):
      host = hostPort[0 ..< colon]

  # Match known private patterns.
  if host in ["localhost", "0.0.0.0", "[::1]", "::1"]: return true
  if host.startsWith("127.")    : return true
  if host.startsWith("169.254."): return true
  if host.startsWith("192.168."): return true

  # 10.x.x.x — only when host looks like a dotted-quad.
  if host.startsWith("10."):
    let parts = host.split('.')
    if parts.len == 4: return true

  # 172.16.0.0 – 172.31.255.255.
  if host.startsWith("172."):
    let parts = host.split('.')
    if parts.len >= 2 and parts[1].len > 0 and parts[1].allCharsInSet({'0'..'9'}):
      let second = parseInt(parts[1])
      if second in 16 .. 31: return true

  false

func extractUrlHost*(rawUrl: string): string =
  let lower = rawUrl.toLowerAscii()
  let afterScheme =
    if "://" in lower: lower[lower.find("://") + 3 .. ^1] else: lower
  let afterAt =
    if "@" in afterScheme:
      afterScheme[afterScheme.rfind('@') + 1 .. ^1]
    else:
      afterScheme
  var hostPort = afterAt
  for i, c in afterAt:
    if c in {'/', '?', '#'}:
      hostPort = afterAt[0 ..< i]
      break
  let colon = hostPort.rfind(':')
  result = hostPort
  if colon > 0:
    let afterColon = hostPort[colon + 1 .. ^1]
    if afterColon.len > 0 and afterColon.allCharsInSet({'0'..'9'}):
      result = hostPort[0 ..< colon]

func extractUrlPath*(rawUrl: string): string =
  let lower = rawUrl.toLowerAscii()
  let afterScheme =
    if "://" in lower: lower[lower.find("://") + 3 .. ^1] else: lower
  let afterAt =
    if "@" in afterScheme:
      afterScheme[afterScheme.rfind('@') + 1 .. ^1]
    else:
      afterScheme
  var start = afterAt.find('/')
  if start < 0:
    return "/"
  result = afterAt[start .. ^1]
  for i, c in result:
    if c in {'?', '#'}:
      result = result[0 ..< i]
      break
  if result.len == 0:
    result = "/"

func parseWebAllowlist*(raw: string): seq[string] =
  for item in raw.split(','):
    let host = item.strip().toLowerAscii()
    if host.len > 0:
      result.add(host)

func hostMatchesAllowlist*(host, allowedHost: string): bool =
  host == allowedHost or host.endsWith("." & allowedHost)

func normalizePolicyPathPrefix*(raw: string): string =
  if raw.len == 0 or raw == "/":
    return ""
  if raw[0] == '/':
    return raw
  "/" & raw

func matchesWebAccessRule*(rawUrl: string; rule: WebAccessRule): bool =
  let host = extractUrlHost(rawUrl)
  if host.len == 0 or not hostMatchesAllowlist(host, rule.host):
    return false
  let requiredPrefix = normalizePolicyPathPrefix(rule.pathPrefix)
  if requiredPrefix.len == 0:
    return true
  let path = extractUrlPath(rawUrl)
  path == requiredPrefix or path.startsWith(requiredPrefix)

func isAllowedPublicUrl*(rawUrl: string;
                         allowlist: seq[string]): bool =
  if isPrivateUrl(rawUrl):
    return false
  if allowlist.len == 0:
    return true
  let host = extractUrlHost(rawUrl)
  if host.len == 0:
    return false
  for allowedHost in allowlist:
    if hostMatchesAllowlist(host, allowedHost):
      return true
  false

func isAllowedPublicUrl*(rawUrl: string;
                         rules: seq[WebAccessRule];
                         fallbackAllowlist: seq[string]): bool =
  if isPrivateUrl(rawUrl):
    return false
  if rules.len > 0:
    for rule in rules:
      if matchesWebAccessRule(rawUrl, rule):
        return true
    return false
  isAllowedPublicUrl(rawUrl, fallbackAllowlist)

func buildUrlAccessError*(rawUrl: string;
                          allowlist: seq[string]): string =
  if isPrivateUrl(rawUrl):
    return "Error: private/internal addresses not allowed."
  let host = extractUrlHost(rawUrl)
  if allowlist.len == 0:
    return "Error: invalid or blocked URL."
  "Error: host '" & host & "' is not in " & WebAllowlistEnvVar & "."

func buildUrlAccessError*(rawUrl: string;
                          rules: seq[WebAccessRule];
                          fallbackAllowlist: seq[string];
                          policyLabel: string): string =
  if isPrivateUrl(rawUrl):
    return "Error: private/internal addresses not allowed."
  let host = extractUrlHost(rawUrl)
  let path = extractUrlPath(rawUrl)
  if rules.len > 0:
    return "Error: URL '" & host & path & "' is outside the configured " &
      policyLabel & " policy."
  buildUrlAccessError(rawUrl, fallbackAllowlist)

func currentTimeResult*(t: DateTime): string =
  ## Returns a formatted UTC timestamp string for the current_time tool result.
  "Current UTC time: " & t.format("yyyy-MM-dd HH:mm:ss") &
  " (day: " & $t.weekday & ")"
