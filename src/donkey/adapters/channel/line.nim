## LineAdapter — outbound ChannelPort for the LINE Messaging API.
##
## Inbound is webhook-driven: the HTTP layer parses the raw body (US-003/US-005)
## and calls `pushEvent(payload)`, which enqueues the already-parsed
## `LineParseResult` values. The daemon drains the queue with `tryRecvEvent`.
## There is no LINE SDK and no parallel `LineEvent` type.
##
## Outbound:
##   push   POST {apiBase}/v2/bot/message/push   {"to": target, "messages":[…]}
##   reply  POST {apiBase}/v2/bot/message/reply  {"replyToken": token, "messages":[…]}
##
## Protocol facts (PRD §1, §9; Hermes is read-only at
## `/home/micelio/git/hermes-agent`, `plugins/platforms/line/adapter.py`):
##   - `to` is the raw `U…`/`C…`/`R…` id; internal `group:`/`room:`/`user:`
##     prefixes are stripped by `lineTarget` (FR-5, `adapter.py:247-248`).
##   - one text bubble holds 5000 chars; chunks are capped at 4500 and at most
##     5 bubbles are sent per call. Overflow is ellipsised
##     (`adapter.py:58-60,117-135`).
##   - a reply token is single-use and short-lived; a refused reply never
##     falls back to push, which would churn the metered API
##     (`adapter.py:247-248`).
##   - the access token is a static Bearer secret; only `api.line.me` (or the
##     configured test base) is on the egress allowlist.
##
## The adapter remembers the last conversation each speaker wrote from
## (`chatIds`), the same way the Telegram adapter does: `OutboundMessage.replyTo`
## always wins, the remembered chat is the fallback, and the identity's raw id
## is the last resort (DMs).

import std/[net, json, os, strutils, tables, unicode]
import ../../core/pipeops
import ../../core/types
import ../../core/utf8
import ../../core/channels/flood_gate
import ../../domain/message
import ../../domain/channels/line_pure
import ../../ports/channel
import ../../ports/http
import ../../ports/link_codes
import ../http/std_http
import ../identity/identity_resolver
import ../../infra/event_queue

export line_pure
export identity_resolver
export channel.FileDownload
export link_codes

const
  LineApiBase*       = "https://api.line.me"
  LineApiHost*       = "api.line.me"
  LinePushPath*      = "/v2/bot/message/push"
  LineReplyPath*     = "/v2/bot/message/reply"
  LineMaxChars*      = 5_000  ## per-bubble hard limit (characters)
  LineChunkChars*    = 4_500  ## conservative chunking limit (characters)
  LineMaxBubbles*    = 5      ## one API call carries at most five bubbles
  LineEllipsis*      = "…"
  LineTimeoutSec     = 30
  LineDefaultRetryMs = 5_000'i64
    ## Applied only when a 429 carries no usable retry hint. The window is
    ## recorded so the next send does not hammer the API immediately.

# ── Adapter type ──────────────────────────────────────────────────────────────

type
  LineAdapter* = object
    channelAccessToken*: string
    apiBase*:            string        ## override for tests/proxies
    resolver*:           IdentityResolver
    linkCodes*:          LinkCodePort
      ## Cross-channel `/continue` seam: the table is shared per identity file,
      ## so a code minted on another channel resolves here.
    http*:               HttpRuntimePort
    flood*:              FloodGate     ## channel-wide 429 window
    configError*:        string        ## invalid base/credentials; sends fail closed
    chatIds*:            Table[string, string]
      ## senderId (raw `U…`) → last conversation it wrote from (`C…`/`R…`/`U…`)

# ── Webhook queue ─────────────────────────────────────────────────────────────

## Thread-safe: an `EventQueue` (shared memory, events moved, not copied),
## created with the module; the receiving thread pushes, the daemon loop polls.
const LineQueueCapacity* = 256
  ## Bounded: an unbuffered queue makes the webhook worker block until the
  ## daemon drains, and a burst would stall every connection on that worker.

var gLineEvents* = initEventQueue[LineParseResult]("line", capacity = LineQueueCapacity)

proc pushEvent*(payload: JsonNode): bool {.discardable.} =
  ## Parses a LINE webhook payload (already signature-verified upstream) and
  ## enqueues every event. Policy decisions belong to `line_policy`/the
  ## runtime, so standby, non-text and unknown events are queued too; the
  ## runtime consumes and logs the ones they drop.
  ##
  ## Returns false when the queue is full: the route then answers 503 so LINE
  ## redelivers, instead of blocking the worker or silently dropping events.
  result = true
  for ev in parseWebhook(payload):
    if not gLineEvents.push(ev):
      result = false

proc openQueue*() =
  ## Opens the module-level event queue. Call once at daemon startup, before
  ## the `/webhook/line` route starts accepting payloads.
  discard  ## the queue is created with the module

proc openQueue*(a: LineAdapter) =
  ## Adapter-shaped overload used by the shared channel startup convention.
  discard a
  openQueue()

# ── Configuration and API base ────────────────────────────────────────────────

func lineApiHost*(apiBase: string): string =
  ## Host exactly as the HTTP transport derives it (includes a port).
  let base = apiBase.strip
  let marker = base.find("://")
  if marker < 0:
    return ""
  var host = base[marker + 3 .. ^1]
  let slash = host.find('/')
  if slash >= 0: host = host[0 ..< slash]
  let query = host.find('?')
  if query >= 0: host = host[0 ..< query]
  let fragment = host.find('#')
  if fragment >= 0: host = host[0 ..< fragment]
  let at = host.rfind('@')
  if at >= 0: host = host[at + 1 .. ^1]
  host.strip

func bareLineHost(host: string): string =
  ## Host without brackets or port, used only for the loopback decision.
  if host.startsWith("["):
    let close = host.find(']')
    if close > 0:
      return host[1 ..< close]
  let colon = host.rfind(':')
  if colon >= 0: host[0 ..< colon] else: host

func isLoopbackLineHost(host: string): bool =
  ## Literal loopback only: a DNS name like `127.evil.com` is not local, even
  ## though it starts with the same bytes.
  let bare = bareLineHost(host).toLowerAscii()
  if bare == "localhost" or bare == "::1":
    return true
  try:
    let ip = parseIpAddress(bare)
    if ip.family == IPv4:
      return ip.address_v4[0] == 127'u8
    $ip == "::1"
  except ValueError:
    false

func lineApiBaseError*(apiBase: string): string =
  ## Reason a custom base is refused; empty means acceptable. The production
  ## base is https; plain http is allowed only on loopback for tests.
  let base = apiBase.strip
  if base.len == 0:
    return ""
  let marker = base.find("://")
  if marker <= 0:
    return "apiBase must be an absolute https URL"
  let scheme = base[0 ..< marker].toLowerAscii()
  let host = lineApiHost(base)
  if host.len == 0:
    return "apiBase has no host"
  if scheme == "https":
    return ""
  if scheme == "http" and isLoopbackLineHost(host):
    return ""
  "apiBase must use https outside loopback"

func lineApiAllowlist*(apiBase: string): seq[string] =
  ## Egress stays restricted to the API host. An empty override keeps the
  ## official endpoint; a custom base contributes its own host instead of
  ## disabling the allowlist.
  let base = apiBase.strip
  if base.len == 0:
    return @[LineApiHost]
  let host = lineApiHost(base)
  if host.len == 0: @[] else: @[host]

func resolvedApiBase*(a: LineAdapter): string =
  ## Base used for API calls. Empty keeps the official endpoint.
  let base = a.apiBase.strip
  if base.len > 0: base.strip(chars = {'/'}) else: LineApiBase

func buildPushUrl*(apiBase: string): string =
  ## `POST {apiBase}/v2/bot/message/push`. An empty base keeps the official
  ## endpoint.
  let base = if apiBase.strip.len > 0: apiBase.strip else: LineApiBase
  base.strip(chars = {'/'}) & LinePushPath

func buildReplyUrl*(apiBase: string): string =
  ## `POST {apiBase}/v2/bot/message/reply`.
  let base = if apiBase.strip.len > 0: apiBase.strip else: LineApiBase
  base.strip(chars = {'/'}) & LineReplyPath

# ── Text chunking (Hermes-compatible) ────────────────────────────────────────

func clipRunes(s: string; maxRunes: int): string =
  ## Byte-safe prefix of at most `maxRunes` Unicode characters.
  if maxRunes <= 0:
    return ""
  var count = 0
  var pos = 0
  while pos < s.len and count < maxRunes:
    let step = runeLenAt(s, pos)
    if step <= 0:
      break
    pos += step
    inc count
  if pos >= s.len: s else: s[0 ..< pos]

func isLineWhitespace(r: Rune): bool =
  r.int in [9, 10, 13, 32]

func clipToLineUnits*(text: string; maxUnits: int): string =
  ## Cuts `text` so it fits in `maxUnits` UTF-16 code units, never splitting a
  ## code point.
  if maxUnits <= 0:
    return ""
  var units = 0
  var pos = 0
  while pos < text.len:
    let step = runeLenAt(text, pos)
    if step <= 0:
      break
    let width = utf16Width(runeAt(text, pos))
    if units + width > maxUnits:
      break
    units += width
    pos += step
  text[0 ..< pos]

func splitForLine*(text: string; maxChars = LineChunkChars): seq[string] =
  ## Splits text into at most `LineMaxBubbles` bubbles of at most `maxChars`
  ## **UTF-16 code units** (what LINE counts; an emoji is two). Breaks are
  ## preferred at a paragraph, then a line, then a word boundary past the
  ## halfway point; otherwise the cut is hard.
  ## When the bubble budget is exhausted the last bubble is ellipsised, so a
  ## long answer never silently loses its tail marker.
  if text.len == 0:
    return @[]
  if maxChars <= 0:
    return @[text]

  var runes: seq[Rune]
  var starts: seq[int]
  var pos = 0
  while pos < text.len:
    starts.add pos
    let step = runeLenAt(text, pos)
    if step <= 0:
      break
    runes.add runeAt(text, pos)
    pos += step
  starts.add text.len

  let total = runes.len
  ## LINE measures a message in UTF-16 code units, not code points: counting
  ## runes lets a string of emoji exceed the API limit by up to 2x.
  var units = newSeq[int](total + 1)
  for i in 0 ..< total:
    units[i + 1] = units[i] + utf16Width(runes[i])
  let totalUnits = units[^1]
  if totalUnits <= maxChars:
    return @[text]

  var cur = 0
  while cur < total and result.len < LineMaxBubbles and
        (totalUnits - units[cur]) > maxChars:
    var limit = cur
    while limit < total and units[limit + 1] - units[cur] <= maxChars:
      inc limit
    var minCut = cur
    while minCut < total and units[minCut + 1] - units[cur] <= maxChars div 2:
      inc minCut
    var cut = -1

    var i = limit - 1
    while i >= minCut:
      if runes[i] == Rune('\n') and i + 1 < total and
         runes[i + 1] == Rune('\n'):
        cut = i
        break
      dec i

    if cut < 0:
      i = limit - 1
      while i >= minCut:
        if runes[i] == Rune('\n'):
          cut = i
          break
        dec i

    if cut < 0:
      i = limit - 1
      while i >= minCut:
        if runes[i] == Rune(' '):
          cut = i
          break
        dec i

    if cut <= cur:
      cut = limit

    let piece = text[starts[cur] ..< starts[cut]].strip(
      leading = false, trailing = true)
    ## Whitespace-only slices must not become empty bubbles: LINE rejects them
    ## and the whole POST with it.
    if piece.len > 0:
      result.add piece
    cur = cut
    while cur < total and isLineWhitespace(runes[cur]):
      inc cur

  if cur < total:
    if result.len < LineMaxBubbles:
      result.add text[starts[cur] .. ^1]
    elif result.len > 0:
      ## Budget exhausted: mark the truncation on the last bubble.
      let last = result[^1]
      ## `maxChars` is UTF-16 units; clipping by runes could leave the bubble
      ## at the limit and the ellipsis would push it over.
      result[^1] = clipToLineUnits(last, maxChars - 1).strip(
        leading = false, trailing = true) & LineEllipsis
  result

# ── Request bodies ────────────────────────────────────────────────────────────

func messagesJson(chunks: seq[string]): JsonNode =
  result = newJArray()
  for chunk in chunks:
    result.add(%* {"type": "text", "text": chunk})

func buildPushBody*(target, text: string): JsonNode =
  ## Push payload: the raw LINE id in `to`, text split into LINE bubbles.
  %* {
    "to":       lineTarget(target),
    "messages": messagesJson(splitForLine(text)),
  }

func buildReplyBody*(replyToken, text: string): JsonNode =
  ## Reply payload: the token replaces `to`; no push fallback exists here.
  %* {
    "replyToken": replyToken,
    "messages":   messagesJson(splitForLine(text)),
  }

# ── Error hygiene ─────────────────────────────────────────────────────────────

func redactSecret(text, secret: string): string =
  ## Never let the channel access token reach a log or a caller error.
  if secret.len == 0: text else: text.replace(secret, "[redacted]")

func shortenBody(text: string; limit = 200): string =
  let trimmed = text.strip
  if trimmed.len <= limit:
    trimmed
  else:
    clipRunes(trimmed, limit) & LineEllipsis

func lineRetryAfterMs(body: string;
                      headers: seq[HttpHeader] = @[]): int64 =
  ## Reads the standard `Retry-After` header (seconds) or the
  ## `retry_after`/`retryAfter` body fields. Returns 0 when the API gave no
  ## usable hint.
  for (key, value) in headers:
    if key.toLowerAscii() == "retry-after":
      var valueMs = 0'i64
      var digits = 0
      for ch in value.strip:
        if ch notin {'0' .. '9'} or digits >= 9:
          break
        valueMs = valueMs * 10 + int64(ord(ch) - ord('0'))
        inc digits
      if valueMs > 0:
        return valueMs * 1000

  for marker in ["\"retry_after\":", "\"retryAfter\":"]:
    let at = body.find(marker)
    if at < 0:
      continue
    var i = at + marker.len
    while i < body.len and body[i] in {' ', '\t'}:
      inc i
    var value = 0'i64
    var digits = 0
    while i < body.len and body[i] in {'0' .. '9'} and digits < 9:
      value = value * 10 + int64(ord(body[i]) - ord('0'))
      inc i
      inc digits
    if value > 0:
      return value * 1000
  0

# ── HTTP ──────────────────────────────────────────────────────────────────────

proc postJson(a: LineAdapter; url, label: string;
              body: JsonNode): Result[void, string] =
  ## One non-idempotent POST. A transport failure or a 4xx/5xx is returned as
  ## `err` without a retry: LINE has no request idempotency key, so resending
  ## a push could duplicate the message. The body is truncated and the access
  ## token is redacted; the URL (and any query) is never echoed.
  if a.channelAccessToken.len == 0:
    return err("LINE: missing channel access token")
  if a.http.post.isNil:
    return err("LINE: no HTTP transport")

  let waitMs = a.flood.remainingMs(0, epochMs())
  if waitMs > 0:
    return err("LINE " & label & ": flood window active (" & $waitMs & " ms)")

  let headers = @[("Authorization", "Bearer " & a.channelAccessToken),
                  ("Content-Type", "application/json")]
  var sent: Result[HttpResponse, string]
  try:
    sent =
      if not a.http.postNoRedirect.isNil:
        ## A redirect would forward the Bearer to another host.
        a.http.postNoRedirect(url, $body, headers)
      else:
        a.http.post(url, $body, headers)
  except CatchableError:
    return err("LINE " & label & " transport error")

  if sent.isErr:
    ## Transport messages may embed the request URL; keep them out of the
    ## caller-visible error.
    return err("LINE " & label & " transport error")

  let resp = sent.value
  if resp.status == 429:
    let retryMs = lineRetryAfterMs(resp.body, resp.headers)
    a.flood.noteRetryAfter(0, (if retryMs > 0: retryMs else: LineDefaultRetryMs),
                           epochMs())
    return err("LINE " & label & ": HTTP 429 (flood window recorded)")

  if resp.status < 200 or resp.status >= 300:
    let detail = shortenBody(redactSecret(resp.body, a.channelAccessToken))
    if detail.len > 0:
      return err("LINE " & label & " HTTP " & $resp.status & ": " & detail)
    return err("LINE " & label & " HTTP " & $resp.status)
  ok()

# ── ChannelPort implementation ────────────────────────────────────────────────

proc rememberChat*(a: var LineAdapter; senderId, chatId: string) =
  ## Remembers the conversation a speaker last wrote from. In a group the
  ## chat id is not the sender id, and a proactive send must answer in the
  ## group instead of the speaker's DM.
  if senderId.len > 0 and chatId.len > 0:
    a.chatIds[senderId] = chatId

proc targetFor(a: LineAdapter; msg: OutboundMessage): string =
  ## Precedence: explicit reply target, then the remembered conversation,
  ## then the identity's raw id (a DM). Internal prefixes never leak.
  if msg.replyTo.strip.len > 0:
    return lineTarget(msg.replyTo.strip)
  let rawId = a.resolver.reverseChannel(msg.userId, ckLine)
  if rawId.len == 0:
    return ""
  let remembered = a.chatIds.getOrDefault(rawId, "")
  if remembered.len > 0:
    lineTarget(remembered)
  else:
    lineTarget(rawId)

# ── Link codes (cross-channel `/continue`) ────────────────────────────────────

proc confirmLinkCode*(resolver: IdentityResolver; code: string;
                      kind: ChannelKind; rawId: string): bool {.gcsafe.} =
  ## Redeems `code` and maps (kind, rawId) to its target. A code from another
  ## channel must resolve here: the pending table is keyed by the identity file,
  ## not by the adapter that minted it.
  resolver.consumeLinkCode(code.strip, kind, rawId)

proc linkCodePort*(a: LineAdapter): LinkCodePort {.gcsafe.} =
  ## Cross-channel seam used by the LINE runtime. The semantics of a code (TTL,
  ## single use) stay in the shared table; minting and redeeming just reach it.
  a.resolver.linkCodePort()

proc send*(a: LineAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends text only. Media and keyboards are refused explicitly instead of
  ## being dropped silently: LINE's capability descriptor is send-only and a
  ## caller that ignores it must see the reason.
  if a.configError.len > 0:
    return err("LINE: " & a.configError)
  if msg.mediaUrl.len > 0:
    return err("LINE: media unsupported (text only)")
  if msg.keyboard.len > 0:
    return err("LINE: keyboards unsupported (text only)")
  if msg.text.strip.len == 0:
    return ok()   ## the API refuses empty text; nothing to deliver

  let target = a.targetFor(msg)
  if target.len == 0:
    return err("LINE: no target id for user " & $msg.userId)

  let base = a.resolvedApiBase()
  ## One push carries up to five text bubbles; splitting the text into
  ## separate calls would risk partial delivery (and duplicated messages on a
  ## retry), while LINE accepts them together.
  ? a.postJson(buildPushUrl(base), "push", buildPushBody(target, msg.text))
  ok()

proc sendReply*(a: LineAdapter; replyToken, text: string): Result[void, string] =
  ## Answers with a single-use reply token. A refused reply (expired token,
  ## 400) is returned as `err` and never retried as a push: that would bill
  ## the metered API and could duplicate the answer.
  if a.configError.len > 0:
    return err("LINE: " & a.configError)
  let token = replyToken.strip
  if token.len == 0:
    return err("LINE: missing reply token")
  if text.strip.len == 0:
    return ok()

  let base = a.resolvedApiBase()
  ? a.postJson(buildReplyUrl(base), "reply", buildReplyBody(token, text))
  ok()

proc tryRecvEvent*(a: var LineAdapter): (bool, LineParseResult) =
  ## Non-blocking poll for webhook events. It deliberately does **not** remember
  ## the conversation: a group event that policy will deny must not become the
  ## sender's remembered target. The runtime records it after acceptance.
  var has = false
  var ev: LineParseResult
  (has, ev) = gLineEvents.tryTake()
  (has, ev)

proc receive*(a: var LineAdapter): Result[seq[InboundMessage], string] =
  ## LINE is webhook-driven, not polled: the daemon drains through
  ## `tryRecvEvent`. This stub keeps the adapter compatible with ChannelPort
  ## without inventing a second receive path.
  discard a
  ok(newSeq[InboundMessage]())

proc ack*(a: LineAdapter; msgId: string) =
  ## No-op — the LINE webhook requires only a 2xx HTTP response.
  discard a
  discard msgId

proc downloadFile*(a: LineAdapter; fileId: string): Result[FileDownload, string] =
  ## Inbound media is out of scope for LINE in this PRD; fail loudly.
  discard a
  discard fileId
  err("LINE: media unsupported")

# ── Constructor ───────────────────────────────────────────────────────────────

proc newLineAdapter*(channelAccessToken, identityPath: string;
                     apiBase = "";
                     http: HttpRuntimePort = HttpRuntimePort()): LineAdapter =
  ## The daemon passes `LINE_CHANNEL_ACCESS_TOKEN` (a static Bearer secret,
  ## never logged) and `LINE_API_BASE` from the environment snapshot; an empty
  ## base is the official endpoint. An injected `http` is used verbatim, so
  ## tests never open a socket. The default transport disables retries for
  ## non-idempotent sends and allows egress only to the configured LINE host.
  let token = channelAccessToken.strip
  let base = apiBase.strip

  ## Do not raise: an invalid base would abort daemon startup and take every
  ## other channel with it. The adapter records the reason and fails sends.
  ## The plain-http loopback allowance exists for an injected test transport;
  ## a real one must never send the Bearer in clear text.
  let baseError =
    if http.post.isNil: lineApiBaseError(base)
    else: ""
  let effectiveBase = if baseError.len > 0: "https://api.line.me" else: base

  var runtimeHttp = http
  if runtimeHttp.post.isNil:
    runtimeHttp = newStdHttpAdapter(
      timeout = LineTimeoutSec,
      allowlist = lineApiAllowlist(effectiveBase),
      retryNonIdempotent = false,
      retryConflict = false).toRuntimePort()

  var adapter = LineAdapter(
    configError: baseError,
    channelAccessToken: token,
    apiBase:            base,
    resolver:           newIdentityResolver(identityPath),
    http:               runtimeHttp,
    flood:              newFloodGate(),
    chatIds:            initTable[string, string](),
  )
  adapter.linkCodes = adapter.resolver.linkCodePort()
  adapter
