## signal_pure.nim — pure parsing of signal-cli JSON-RPC message envelopes.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (item |> parseEnvelope)
##   |>->  — last-arg pipe         (data |>-> extractStr("message"))
##
## Contract:
##   1. parseEnvelope(JsonNode)     → SigParseResult   (single result-array item)
##   2. parseEnvelopes(JsonNode)    → seq[SigParseResult]  (full result array)
##   3. toInbound(r, userId)        → InboundMessage
##   4. hasAttachment(r)            → bool

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  SigMsgKind* = enum
    smkText        ## dataMessage with non-empty message text
    smkAttachment  ## dataMessage with one or more attachments
    smkUnknown     ## receipts, typing indicators, sync messages, calls — ignored

  SigParseResult* = object
    kind*:         SigMsgKind
    rawId*:        string   ## sender E.164 phone number, e.g. "+1234567890"
    text*:         string   ## message body (may be empty for pure attachment)
    timestamp*:    int64    ## envelope timestamp (epoch milliseconds)
    attachmentId*: string   ## first attachment id (non-empty for smkAttachment)

# ── Internal helpers ──────────────────────────────────────────────────────────

func extractStr(name: string; node: JsonNode): string =
  ## Returns a string field from node by name.
  ## Designed for  node |>-> extractStr(name)  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func senderNumber(env: JsonNode): string =
  ## Extracts the sender phone number from an envelope.
  ## Prefers sourceNumber (always E.164); falls back to source.
  if env == nil: return ""
  let num = env.getOrDefault("sourceNumber").getStr("")
  if num.len > 0: return num
  env.getOrDefault("source").getStr("")

func firstAttachmentId(atts: JsonNode): string =
  ## Extracts the id of the first attachment in the attachments array.
  if atts == nil or atts.kind != JArray or atts.len == 0: return ""
  let first = atts[0]
  if first.kind != JObject: return ""
  let id = first.getOrDefault("id").getStr("")
  if id.len > 0: return id
  first.getOrDefault("filename").getStr("")

func parseDataMessage(source: string; ts: int64; data: JsonNode): SigParseResult =
  ## Parses a dataMessage sub-object into a SigParseResult.
  ## Designed for  data |>-> parseDataMessage(source, ts)  (piped value is last arg).
  if data == nil or data.kind != JObject:
    return SigParseResult(kind: smkUnknown)
  let msg     = data |>-> extractStr("message")
  let atts    = data.getOrDefault("attachments")
  let hasAtts = atts != nil and atts.kind == JArray and atts.len > 0
  if hasAtts:
    SigParseResult(
      kind:         smkAttachment,
      rawId:        source,
      text:         msg,
      timestamp:    ts,
      attachmentId: firstAttachmentId(atts),
    )
  elif msg.len > 0:
    SigParseResult(kind: smkText, rawId: source, text: msg, timestamp: ts)
  else:
    SigParseResult(kind: smkUnknown)

# ── Public API ────────────────────────────────────────────────────────────────

func parseEnvelope*(item: JsonNode): SigParseResult =
  ## Parses a single item from the signal-cli receive result array.
  ## Returns smkUnknown for non-data-message envelopes (receipts, typing, sync).
  if item == nil or item.kind != JObject:
    return SigParseResult(kind: smkUnknown)
  let env = item.getOrDefault("envelope")
  if env == nil or env.kind != JObject:
    return SigParseResult(kind: smkUnknown)
  let source = env |> senderNumber
  if source.len == 0:
    return SigParseResult(kind: smkUnknown)
  let ts   = env.getOrDefault("timestamp").getBiggestInt(0)
  let data = env.getOrDefault("dataMessage")
  if data == nil or data.kind != JObject:
    return SigParseResult(kind: smkUnknown)
  data |>-> parseDataMessage(source, ts)

func parseEnvelopes*(items: JsonNode): seq[SigParseResult] =
  ## Parses the result array from a signal-cli receive JSON-RPC response.
  ## Filters out smkUnknown entries. Designed for  resultArray |> parseEnvelopes.
  if items == nil or items.kind != JArray: return @[]
  for item in items:
    let r = item |> parseEnvelope
    if r.kind != smkUnknown:
      result.add(r)

func toInbound*(r: SigParseResult; userId: UserId): InboundMessage =
  ## Converts a SigParseResult to an InboundMessage.
  ## attachmentId goes to mediaUrl field; adapter handles local path resolution.
  InboundMessage(
    userId:    userId,
    channelId: $r.timestamp,
    text:      r.text,
    mediaUrl:  r.attachmentId,
    channel:   ckSignal,
  )

func hasAttachment*(r: SigParseResult): bool =
  ## Returns true when the result carries one or more attachments.
  r.kind == smkAttachment
