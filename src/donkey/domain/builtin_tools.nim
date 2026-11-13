## Built-in native tools — tool metadata and pure helpers.
## Side-effectful execution (HTTP calls, clock) lives in app/native_tools.nim.

import std/[strutils, times]
import ../config/types
import ./url_policy
export url_policy

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

func parseWebAllowlist*(raw: string): seq[string] =
  for item in raw.split(','):
    let host = normalizeHost(item.strip())
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
