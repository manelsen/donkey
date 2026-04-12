## SlackAdapter — ChannelPort for Slack Events API (webhook / Socket Mode).
##
## Receiving: Events arrive via HTTP POST from Slack to a webhook endpoint.
##   The HTTP layer calls pushEvent() with the parsed JSON payload.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## URL verification: Slack sends a url_verification challenge on first setup.
##   Call parseChallenge(payload) — non-empty result means echo it back as-is.
##
## Sending: Slack Web API POST /api/chat.postMessage using bot token.
##   DM channel IDs are fetched on first send via conversations.open and cached.
##
## Slash commands arrive form-encoded; the HTTP layer must JSON-encode them and
## set "type": "slash_command" before calling pushEvent().

import std/[json, tables]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/slack_pure
import ../../ports/http
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver

const
  SlackApiBase*  = "https://slack.com/api"
  SlackMaxChars* = 3000   ## practical per-message limit (avoids block API)

# ── Public event type ─────────────────────────────────────────────────────────

type
  SlackRawEventKind* = enum
    srMessage      ## regular message or app_mention → feed to session
    srSlashCommand ## slash command (text = "/command args")
    srBlockAction  ## block action (text = "actionId:value")

  SlackRawEvent* = object
    kind*:        SlackRawEventKind
    slackUserId*: string
    text*:        string
    channelId*:   string
    teamId*:      string
    responseUrl*: string  ## non-empty for slash commands and block actions
    triggerId*:   string

# ── Module-level event queue ──────────────────────────────────────────────────

## Thread-safe: chronos Channel uses internal synchronization.
## Opened once at daemon startup via openQueue().
var gSlackEvents* {.global.}: Channel[SlackRawEvent]

# ── Inbound helpers (called by HTTP layer) ────────────────────────────────────

proc parseChallenge*(payload: JsonNode): string =
  ## Returns the challenge string if this is a url_verification payload.
  ## Empty string otherwise. HTTP layer must respond with this value verbatim.
  let r = payload |> parseEvent
  if r |> isVerification: r.challenge else: ""

proc pushEvent*(payload: JsonNode) =
  ## Parses an incoming Slack Events API webhook payload and enqueues it.
  ## Ignores unknown, filtered (bot), and verification payloads.
  let r = payload |> parseEvent
  case r.kind
  of sekVerification, sekUnknown: discard
  of sekMessage:
    gSlackEvents.send(SlackRawEvent(
      kind:        srMessage,
      slackUserId: r.rawId,
      text:        r.text,
      channelId:   r.channelId,
      teamId:      r.teamId,
    ))
  of sekSlashCommand:
    gSlackEvents.send(SlackRawEvent(
      kind:        srSlashCommand,
      slackUserId: r.rawId,
      text:        r.text,
      channelId:   r.channelId,
      teamId:      r.teamId,
      responseUrl: r.responseUrl,
      triggerId:   r.triggerId,
    ))
  of sekBlockAction:
    gSlackEvents.send(SlackRawEvent(
      kind:        srBlockAction,
      slackUserId: r.rawId,
      text:        r.text,
      channelId:   r.channelId,
      teamId:      r.teamId,
      responseUrl: r.responseUrl,
      triggerId:   r.triggerId,
    ))

# ── SlackAdapter ──────────────────────────────────────────────────────────────

type
  SlackAdapter* = object
    botToken*:  string
    apiBase*:   string                     ## override for testing
    resolver*:  IdentityResolver
    dmChannels: ref Table[string, string]  ## slackUserId → dm_channel_id (ref = value receiver ok)
    http*:      StdHttpAdapter

func authHeader(a: SlackAdapter): (string, string) =
  ("Authorization", "Bearer " & a.botToken)

func base(a: SlackAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: SlackApiBase

# ── REST response helpers ─────────────────────────────────────────────────────

proc parseSlackBody(resp: HttpResponse): Result[JsonNode, string]
                   {.gcsafe, raises: [].} =
  ## Validates HTTP status and Slack "ok" field. Designed for >>= chaining.
  if resp.status < 200 or resp.status >= 300:
    return err("Slack HTTP " & $resp.status & ": " & resp.body)
  try:
    let j = parseJson(resp.body)
    if not j.getOrDefault("ok").getBool(false):
      return err("Slack API error: " & j.getOrDefault("error").getStr("unknown"))
    ok(j)
  except CatchableError as e:
    err(e.msg)

proc postJson(a: SlackAdapter; endpoint: string;
              body: JsonNode): Result[JsonNode, string] =
  ## POSTs JSON to a Slack Web API endpoint; validates "ok" field.
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  a.http.post(a.base() & "/" & endpoint, $body, headers) >>= parseSlackBody

# ── DM channel resolution (conversations.open) ────────────────────────────────

proc dmChannelFor(a: SlackAdapter; slackUserId: string): Result[string, string] =
  ## Returns (or creates) the DM channel ID for the given Slack user.
  ## Uses conversations.open; caches the result.
  if slackUserId in a.dmChannels[]:
    return ok(a.dmChannels[][slackUserId])
  let j = ? a.postJson("conversations.open", %* {"users": slackUserId})
  try:
    let chId = j["channel"]["id"].getStr("")
    if chId.len == 0:
      return err("Slack conversations.open: missing channel.id")
    a.dmChannels[][slackUserId] = chId
    ok(chId)
  except CatchableError as e:
    err(e.msg)

# ── ChannelPort procs ─────────────────────────────────────────────────────────

proc sendChunk(a: SlackAdapter; channelId, text: string): Result[void, string] =
  discard ? a.postJson("chat.postMessage",
                       %* {"channel": channelId, "text": text})
  ok()

proc send*(a: SlackAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user's Slack DM channel.
  ## Opens the DM channel on first send (conversations.open); caches the id.
  ## Splits messages longer than SlackMaxChars into multiple sends.
  let slackId = a.resolver.reverseChannel(msg.userId, ckSlack)
  if slackId.len == 0:
    return err("SlackAdapter.send: no Slack ID for user " & $msg.userId)
  let chId = ? a.dmChannelFor(slackId)
  for chunk in splitChunks(msg.text, SlackMaxChars):
    ? a.sendChunk(chId, chunk)
  ok()

proc sendToChannel*(a: SlackAdapter;
                    channelId, text: string): Result[void, string] =
  ## Sends a message directly to a Slack channel id.
  ## Used by the runtime for event-context replies (slash commands, block actions).
  for chunk in splitChunks(text, SlackMaxChars):
    ? a.sendChunk(channelId, chunk)
  ok()

proc sendReturnId*(a: SlackAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends a single chunk and returns the Slack message ts (used as message id).
  ## Used by the streaming machinery for subsequent chat.update calls.
  let slackId = a.resolver.reverseChannel(msg.userId, ckSlack)
  if slackId.len == 0:
    return err("SlackAdapter.sendReturnId: no Slack ID for " & $msg.userId)
  let chId  = ? a.dmChannelFor(slackId)
  let chunk = splitChunks(msg.text, SlackMaxChars)[0]
  let j = ? a.postJson("chat.postMessage",
                       %* {"channel": chId, "text": chunk})
  try:
    ok(j["message"]["ts"].getStr(""))
  except CatchableError as e:
    err(e.msg)

proc editMessage*(a: SlackAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Updates an existing message via chat.update (streaming partial update).
  let slackId = a.resolver.reverseChannel(userId, ckSlack)
  if slackId.len == 0:
    return err("SlackAdapter.editMessage: no Slack ID for " & $userId)
  let chId = ? a.dmChannelFor(slackId)
  let txt  = if text.len > SlackMaxChars: text[0 ..< SlackMaxChars] else: text
  discard ? a.postJson("chat.update",
                       %* {"channel": chId, "ts": msgId, "text": txt})
  ok()

proc buildSlackBlocks(text: string; buttons: seq[seq[(string, string)]]): JsonNode =
  ## Internal helper to build Slack Block Kit payload.
  result = newJArray()
  result.add(%* {
    "type": "section",
    "text": { "type": "mrkdwn", "text": text }
  })
  if buttons.len > 0:
    var elements = newJArray()
    for row in buttons:
      for (label, data) in row:
        elements.add(%* {
          "type":      "button",
          "text":      { "type": "plain_text", "text": label },
          "value":     data,
          "action_id": data,
        })
    if elements.len > 0:
      result.add(%* {
        "type": "actions",
        "elements": elements
      })

proc sendKeyboard*(a: SlackAdapter; userId: UserId;
                   text: string;
                   buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Sends a message with Block Kit buttons to the user's Slack DM.
  let slackId = a.resolver.reverseChannel(userId, ckSlack)
  if slackId.len == 0:
    return err("SlackAdapter.sendKeyboard: no Slack ID for user " & $userId)
  let chId = ? a.dmChannelFor(slackId)
  let blocks = buildSlackBlocks(text, buttons)
  discard ? a.postJson("chat.postMessage",
                       %* {"channel": chId, "text": text, "blocks": blocks})
  ok()

proc editKeyboard*(a: SlackAdapter; userId: UserId;
                   msgId, text: string;
                   buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Replaces the content and blocks of an existing message.
  let slackId = a.resolver.reverseChannel(userId, ckSlack)
  if slackId.len == 0:
    return err("SlackAdapter.editKeyboard: no Slack ID for user " & $userId)
  let chId = ? a.dmChannelFor(slackId)
  let blocks = buildSlackBlocks(text, buttons)
  discard ? a.postJson("chat.update",
                       %* {"channel": chId, "ts": msgId, "text": text, "blocks": blocks})
  ok()

proc ack*(a: SlackAdapter; channelId: string) =
  ## No-op — Slack webhook ack is the HTTP 200 response, handled by the HTTP layer.
  discard

# ── Queue management ──────────────────────────────────────────────────────────

proc openQueue*(a: SlackAdapter) =
  ## Opens the module-level event queue. Call once at daemon startup.
  {.cast(gcsafe).}:
    gSlackEvents.open()

proc tryRecvEvent*(a: SlackAdapter): (bool, SlackRawEvent) =
  ## Non-blocking poll for webhook events. Returns (false, default) when empty.
  gSlackEvents.tryRecv()

# ── Constructor ───────────────────────────────────────────────────────────────

proc newSlackAdapter*(botToken:     string;
                      identityPath: string;
                      apiBase       = ""): SlackAdapter =
  var t = new(Table[string, string])
  t[] = initTable[string, string]()
  SlackAdapter(
    botToken:   botToken,
    apiBase:    apiBase,
    resolver:   newIdentityResolver(identityPath),
    dmChannels: t,
    http:       newStdHttpAdapter(),
  )
