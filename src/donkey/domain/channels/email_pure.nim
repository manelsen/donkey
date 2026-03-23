## email_pure.nim — pure parsing of RFC 2822 email messages.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## An email message has this structure:
##   Header-Name: Header-Value\r\n
##   ...
##   \r\n
##   Body text
##
## Relevant headers extracted:
##   From        — sender address (used as routing rawId)
##   Subject     — email subject line
##   Message-ID  — unique message identifier
##   Date        — send date
##   Content-Type — body content type (text/plain, text/html, etc.)
##
## Routing convention:
##   rawId = From header value (sender email address)
##   The adapter identity key is the sender's email address.
##
## Topology (pipeops):
##   |>    — unary pure transform  (raw |> parseEmail)
##   |>->  — last-arg pipe         (raw |>-> findHeader("From"))
##   >>=   — Result chain          (not used here; parsers return value types)
##
## Contract:
##   1. parseEmail(raw)      → EmailParseResult
##   2. toInbound(r, userId) → InboundMessage
##   3. hasAttachment(r)     → bool

import std/strutils
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  EmailMsgKind* = enum
    emkText        ## text/plain body (default)
    emkHtml        ## text/html body
    emkUnknown     ## parse failure or unsupported content type

  EmailParseResult* = object
    kind*:        EmailMsgKind
    fromAddr*:    string  ## From header — routing key used as rawId
    subject*:     string  ## Subject header
    messageId*:   string  ## Message-ID header (dedup / ack key)
    date*:        string  ## Date header
    body*:        string  ## decoded plain-text body
    contentType*: string  ## raw Content-Type value

# ── Internal pure helpers ─────────────────────────────────────────────────────

func headersBody(raw: string): (string, string) =
  ## Splits a raw RFC 2822 email into (headers, body) at the first blank line.
  ## Supports both CRLF (\r\n\r\n) and LF-only (\n\n) line endings.
  let crlfSep = raw.find("\r\n\r\n")
  if crlfSep >= 0:
    return (raw[0 ..< crlfSep], raw[crlfSep + 4 .. ^1])
  let lfSep = raw.find("\n\n")
  if lfSep >= 0:
    return (raw[0 ..< lfSep], raw[lfSep + 2 .. ^1])
  (raw, "")

func findHeader*(name: string; headers: string): string =
  ## Returns the value of the first header named `name` (case-insensitive).
  ## Returns "" when the header is absent.
  ## Designed for  headers |>-> findHeader("From")  (piped value is last arg).
  ##
  ## Handles folded headers (continuation lines starting with whitespace)
  ## by appending them to the previous value.
  let needle = name.toLowerAscii() & ":"
  var i = 0
  var found = ""
  while i < headers.len:
    # Find end of line
    var j = i
    while j < headers.len and headers[j] != '\n':
      inc j
    let line =
      if j > i and headers[j - 1] == '\r': headers[i ..< j - 1]
      else: headers[i ..< j]
    let lineLen = line.len
    if lineLen > needle.len:
      let key = line[0 ..< needle.len].toLowerAscii()
      if key == needle:
        found = line[needle.len ..< lineLen].strip()
        # Collect folded continuation lines
        var k = j + 1
        while k < headers.len and headers[k] in {' ', '\t'}:
          var m = k
          while m < headers.len and headers[m] != '\n':
            inc m
          let cont =
            if m > k and headers[m - 1] == '\r': headers[k ..< m - 1]
            else: headers[k ..< m]
          found.add(' ')
          found.add(cont.strip())
          k = m + 1
        return found
    i = j + 1
  ""

func parseMsgKind(contentType: string): EmailMsgKind =
  let ct = contentType.toLowerAscii()
  if "text/html" in ct:        emkHtml
  elif "text/plain" in ct:     emkText
  elif ct.len == 0:             emkText  ## default when Content-Type absent
  else:                         emkUnknown

# ── Public pure API ───────────────────────────────────────────────────────────

func parseEmail*(raw: string): EmailParseResult =
  ## Parses a raw RFC 2822 email message.
  ## Returns kind=emkUnknown on empty input.
  ##
  ## Usage:  let r = raw |> parseEmail
  if raw.len == 0: return EmailParseResult(kind: emkUnknown)
  let (headers, body) = raw |> headersBody
  let contentType = headers |>-> findHeader("Content-Type")
  let kind = parseMsgKind(contentType)
  EmailParseResult(
    kind:        kind,
    fromAddr:    headers |>-> findHeader("From"),
    subject:     headers |>-> findHeader("Subject"),
    messageId:   headers |>-> findHeader("Message-ID"),
    date:        headers |>-> findHeader("Date"),
    body:        body,
    contentType: contentType,
  )

func toInbound*(r: EmailParseResult; userId: UserId): InboundMessage =
  ## Converts an EmailParseResult + resolved UserId into an InboundMessage.
  ## channelId carries the Message-ID for dedup and ack.
  InboundMessage(
    userId:    userId,
    channel:   ckEmail,
    channelId: r.messageId,
    text:      r.body,
    mediaUrl:  "",
  )

func hasAttachment*(r: EmailParseResult): bool =
  ## True when the email carries a MIME attachment (not currently parsed).
  ## Reserved for future multipart/mixed support.
  r.kind == emkUnknown
