## DiscordAdapter — ChannelPort for Discord.
##
## Receiving: Discord gateway WebSocket runs in a dedicated OS thread.
##   The thread pushes DiscordRawEvent values to a module-level Channel.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## Sending: HTTP REST API (POST /channels/{id}/messages).
##   DM channel IDs are fetched on first send and cached.
##
## Slash commands:
##   /continue <code>  — link Discord identity to an existing session
##   Registered at startup via registerSlashCommands().
##
## Blocking model: the gateway thread blocks on WebSocket recv (1 s timeout).
##   Provider LLM calls (max ~10 s) block the event loop but not this thread.
##   Discord heartbeat interval is ~41 s; occasional missed beats are tolerated.

import std/[json, net, os, random, strutils, sysrand, tables, times, uri]
import ../../core/log
import ../../core/app_meta
import ../../core/commands/command_catalog
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/discord_pure
import ../../domain/channels/telegram_policy  # mentionRequiredFromEnv
import ../../config/environment
import ../../core/security/dm_policy  # parseChatIdList
import ../../ports/http
import ../../core/media_download
import ../http/std_http
import ../identity/identity_resolver
import ./ws_client
import ../network/persistent_socket
import ../network/gateway_family
import ../../infra/event_queue
import ../../infra/thread_handle
import ../../core/channels/recent_ids

const DiscordMaxChars* = 2000

# ── Public event type (thread → main) ─────────────────────────────────────────

type
  DiscordEventKind* = enum
    deMessage       ## regular DM or guild message
    deInteraction   ## slash command interaction (code already extracted)
    deModalRequest  ## /continue slash cmd without code → need to show modal
    deButtonClick   ## component button click — content = custom_id
    deResync        ## a new gateway session replaced a lost one: the events
                    ## of the gap were not replayed, recover them by REST

  DiscordRawEvent* = object
    kind*:             DiscordEventKind
    discordUserId*:    string
    content*:          string   ## message text OR interaction option value
    channelId*:        string   ## Discord channel ID (for messages)
    messageId*:        string
    interactionId*:    string
    interactionToken*: string
    guildId*:          string   ## server id; empty for a DM
    originChannelId*:  string   ## channel the event came from (allowlist only)
    attachmentUrl*:    string   ## first attachment (the turn downloads one)
    attachmentName*:   string
    attachmentMime*:   string
    extraAttachments*: seq[string]  ## names of the attachments after the first
    referencedAuthorId*: string ## author of the message this one replies to

# ── Gateway thread ─────────────────────────────────────────────────────────────

## Module-level channel — opened once, valid for daemon lifetime.
## Thread-safe: an `EventQueue` (shared memory, events moved, not copied),
## created with the module; the receiving thread pushes, the daemon loop polls.
var gDiscordEvents* = initEventQueue[DiscordRawEvent]("discord")

## Messages received before the gateway is ready (READY dispatch) wait here
## and are flushed to gDiscordEvents when READY arrives. All of it runs on
## the gateway thread (handleDispatch and the READY flush), so the buffer
## and the flag are thread-local to it: no lock, no cast.
var gDiscordPending {.threadvar.}: seq[DiscordRawEvent]
var gDiscordReady {.threadvar.}: bool
var gDiscordEverReady {.threadvar.}: bool  ## a READY was seen before in this process

func readyNeedsResync*(readyBefore: bool): bool =
  ## A READY answers an IDENTIFY. The first one is the startup, recovered by
  ## the startup backfill; a later one means the session was lost (RESUME
  ## refused or impossible) and the gateway did not replay the gap.
  readyBefore

proc bufferOrPush(event: DiscordRawEvent) =
  ## Before READY the event waits; afterwards it goes to the daemon loop.
  if gDiscordReady:
    gDiscordEvents.push(event)
  else:
    gDiscordPending.add(event)

const
  DiscordApiBase*   = "https://discord.com/api/v10"
  DiscordGatewayUrl = "wss://gateway.discord.gg"
  DiscordIntents    = 37376  ## GUILD_MESSAGES(512) + DIRECT_MESSAGES(4096) + MESSAGE_CONTENT(32768)

proc epochMs(): int64 =
  let t = getTime()
  t.toUnix() * 1000 + (t.nanosecond div 1_000_000)

func messageEventOf*(r: DsParseResult): DiscordRawEvent =
  ## The event of a parsed MESSAGE_CREATE: live (gateway) and recovered
  ## (REST backfill) messages take the same shape, attachments included.
  DiscordRawEvent(
    kind:          deMessage,
    discordUserId: r.rawId,
    content:       r.content,
    channelId:     r.channelId,
    messageId:     r.messageId,
    guildId:       r.guildId,
    originChannelId: r.originChannelId,
    referencedAuthorId: r.referencedAuthorId,
    attachmentUrl:  (if r.attachmentUrls.len > 0: r.attachmentUrls[0] else: ""),
    attachmentName: (if r.attachmentNames.len > 0: r.attachmentNames[0] else: ""),
    attachmentMime: (if r.attachmentMimes.len > 0: r.attachmentMimes[0] else: ""),
    extraAttachments: (if r.attachmentNames.len > 1: r.attachmentNames[1 .. ^1]
                       else: @[]),
  )

proc handleDispatch(t: string; d: JsonNode; logger: Logger) =
  ## Routes op=0 dispatch events to gDiscordEvents via discord_pure parser.
  ## Messages received before gateway is ready are buffered.
  ## Mapping: DsEventKind → DiscordEventKind:
  ##   dekMessage     → deMessage
  ##   dekButtonClick → deButtonClick
  ##   dekModalSubmit → deInteraction  (code extracted by pure parser)
  ##   dekSlashCommand with needsModal → deModalRequest
  ##   dekSlashCommand with "/" content → deMessage  (regular slash cmd)
  ##   dekSlashCommand without "/" → deInteraction  (/continue code)
  let r = parseDispatch(t, d)
  case r.kind
  of dekUnknown: return
  of dekMessage:
    logger.debug("discord: message from " & r.rawId)
    bufferOrPush(messageEventOf(r))
  of dekSlashCommand:
    logger.debug("discord: slash command from " & r.rawId)
    let event =
      if r.needsModal:
        DiscordRawEvent(
          kind:             deModalRequest,
          discordUserId:    r.rawId,
          interactionId:    r.interactionId,
          interactionToken: r.interactionToken,
          guildId:          r.guildId,
          originChannelId:  r.originChannelId,
        )
      elif r.content.len > 0 and not r.content.startsWith("/"):
        DiscordRawEvent(
          kind:             deInteraction,
          discordUserId:    r.rawId,
          content:          r.content,
          interactionId:    r.interactionId,
          interactionToken: r.interactionToken,
          guildId:          r.guildId,
          originChannelId:  r.originChannelId,
        )
      else:
        DiscordRawEvent(
          kind:             deMessage,
          discordUserId:    r.rawId,
          content:          r.content,
          interactionId:    r.interactionId,
          interactionToken: r.interactionToken,
          guildId:          r.guildId,
          originChannelId:  r.originChannelId,
        )
    bufferOrPush(event)
  of dekButtonClick:
    logger.debug("discord: button click from " & r.rawId)
    let event = DiscordRawEvent(
      kind:             deButtonClick,
      discordUserId:    r.rawId,
      content:          r.content,
      messageId:        r.messageId,
      interactionId:    r.interactionId,
      interactionToken: r.interactionToken,
      guildId:          r.guildId,
      originChannelId:  r.originChannelId,
    )
    bufferOrPush(event)
  of dekModalSubmit:
    ## Modal submit always carries a code from the link_code text input.
    logger.debug("discord: modal submit from " & r.rawId)
    let event = DiscordRawEvent(
      kind:             deInteraction,
      discordUserId:    r.rawId,
      content:          r.content,
      interactionId:    r.interactionId,
      interactionToken: r.interactionToken,
      guildId:          r.guildId,
      originChannelId:  r.originChannelId,
    )
    bufferOrPush(event)

## The gateway connection: adapters/network/persistent_socket keeps it
## (thread, backoff, idle timeout, stop) and gateway_family speaks the
## protocol Discord shares with QQ official. What is Discord's own is here:
## the URL, the identify payload, READY and the dispatches.

type
  DiscordGatewayConfig = object
    ## Plain data, copied to the connection thread.
    token: string

  DiscordGatewayState = object
    ## Lives on the connection thread, across reconnections.
    family: FamilyState

proc discordLocate(cfg: DiscordGatewayConfig; state: var DiscordGatewayState;
                   log: Logger): Result[SocketTarget, string]
                  {.nimcall, gcsafe, raises: [CatchableError].} =
  ## A session is resumed on the URL READY gave; a new one on the default.
  let url = if state.family.resumeUrl.startsWith("wss://"): state.family.resumeUrl
            else: DiscordGatewayUrl
  var host = url[6 .. ^1]
  if '/' in host: host = host[0 ..< host.find('/')]
  log.info("discord: connecting to " & host)
  ok(SocketTarget(host: host, port: Port(443), path: "/?v=10&encoding=json",
                  useTls: true))

proc discordOpened(cfg: DiscordGatewayConfig; state: var DiscordGatewayState;
                   ws: WsClient; log: Logger): SessionStep
                  {.nimcall, gcsafe, raises: [CatchableError].} =
  let now = epochMs()
  ## The first heartbeat waits a random 0-5 s (Discord asks for jitter; the
  ## full 0-41 s would delay startup), sent by the tick.
  familyHello(ws, state.family, now, jitterCapMs = 5_000).isOkOr:
    log.warn("discord: " & error)
    return ssReconnect
  if state.family.sessionId.len > 0:
    log.info("discord: resuming session " & state.family.sessionId)
  else:
    log.info("discord: identifying")
  familyIdentify(ws, state.family, %* {
    "token":      cfg.token,
    "intents":    DiscordIntents,
    "properties": {"os": "linux", "browser": AppSlug, "device": AppSlug},
  }, resumeToken = cfg.token)
  ssKeep

proc discordReady(data: JsonNode; logger: Logger) =
  ## A new session: messages that arrived before it wait in the buffer, and
  ## a session after a lost one asks the daemon to recover the gap.
  logger.info("discord: ready, session=" & data{"session_id"}.getStr(""))
  gDiscordReady = true
  if readyNeedsResync(gDiscordEverReady):
    logger.info("discord: new session after a lost one; recovering the gap")
    gDiscordEvents.push(DiscordRawEvent(kind: deResync))
  gDiscordEverReady = true
  let pendingCount = gDiscordPending.len
  if pendingCount > 0:
    logger.info("discord: flushing " & $pendingCount & " buffered message(s)")
    for event in gDiscordPending:
      gDiscordEvents.push(event)
    gDiscordPending = @[]

proc discordFrame(cfg: DiscordGatewayConfig; state: var DiscordGatewayState;
                  ws: WsClient; frame: WsFrame; log: Logger): SessionStep
                 {.nimcall, gcsafe, raises: [CatchableError].} =
  let event = familyFrame(ws, state.family, frame, closeAction, log, "discord")
  case event.kind
  of fkReady, fkDispatch:
    try:
      if event.kind == fkReady: discordReady(event.data, log)
      else: handleDispatch(event.name, event.data, log)
    except Exception as e:  ## effect boundary: callee raises are unannotated
      log.warn("discord: dispatch " & event.name & " failed: " & e.msg)
  of fkStep:
    return event.step
  of fkNone, fkResumed:
    discard
  ssKeep

proc discordTick(cfg: DiscordGatewayConfig; state: var DiscordGatewayState;
                 ws: WsClient; nowMs: int64; log: Logger): SessionStep
                {.nimcall, gcsafe, raises: [CatchableError].} =
  familyTick(ws, state.family, nowMs, log, "discord")

const DiscordGatewayProtocol = SocketProtocol[DiscordGatewayConfig, DiscordGatewayState](
  locate: discordLocate, opened: discordOpened, frame: discordFrame, tick: discordTick)

var gDiscordGateway: PersistentSocket[DiscordGatewayConfig, DiscordGatewayState]
  ## Pointers only: gcsafe to touch from the daemon.

# ── DiscordAdapter ─────────────────────────────────────────────────────────────

type
  DiscordCursorState* = ref object
    ## The DM recovery cursor (`discord_last_msg_id`) moves only after the
    ## turn that handled a message has delivered its final reply: a crash in
    ## between leaves the message to the startup backfill (at-least-once; the
    ## message dedup keeps a live replay from answering twice).
    pending*: Table[string, string]   ## userId → latest DM id not yet settled
    save*: proc(userId: UserId; msgId: string) {.gcsafe.}
      ## Set by the daemon wiring (it owns the memory); nil saves nothing.

  DiscordAdapter* = object
    token*:     string
    apiBase*:   string       ## override for testing
    appId*:     ref string   ## cached application ID
    resolver*:  IdentityResolver
    dmChannels: ref Table[string, string]  ## discord_user_id → dm_channel_id (ref allows value receiver)
    statusReactions: ref Table[string, string] ## channel_id:message_id -> emoji
    seenMessages: ref RecentIds  ## message ids already handled (RESUME replay, backfill overlap)
    requireMention*: bool  ## in a server, answer only when mentioned or replied to
    cursor*: DiscordCursorState  ## DM recovery cursor, moved after delivery
    allowedChannels*: seq[string]  ## servers/channels served; empty = all
    http*:      StdHttpAdapter

func authHeader(a: DiscordAdapter): (string, string) =
  ("Authorization", "Bot " & a.token)

func base(a: DiscordAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: DiscordApiBase

# ── REST response helpers (for >>= chains) ────────────────────────────────────

func extractJsonId(j: JsonNode): string =
  ## Extracts the "id" string field from a JSON object. Designed for |> piping.
  j.getOrDefault("id").getStr("")

proc parseJsonBody(resp: HttpResponse): Result[JsonNode, string]
                  {.gcsafe, raises: [].} =
  ## Parses a 2xx HTTP response body as JSON; propagates status errors.
  if resp.status < 200 or resp.status >= 300:
    return err("Discord API error " & $resp.status & ": " & resp.body)
  try: ok(parseJson(resp.body))
  except CatchableError as e: err(e.msg)

proc extractId(resp: HttpResponse): Result[string, string]
               {.gcsafe, raises: [].} =
  ## Validates status, parses JSON, and returns the top-level "id" field.
  ## Used with >>= for procs that return a Discord resource id.
  resp |> parseJsonBody >>= proc(j: JsonNode): Result[string, string]
                                {.gcsafe, raises: [].} =
    let id = j |> extractJsonId
    if id.len == 0: err("Discord response missing 'id' field")
    else: ok(id)

# ── REST helpers ───────────────────────────────────────────────────────────────

proc dmChannelFor*(a: DiscordAdapter; discordUserId: string): Result[string, string] =
  ## Returns (or creates) the DM channel ID for the given Discord user.
  if discordUserId in a.dmChannels[]:
    return ok(a.dmChannels[][discordUserId])
  let body    = %* {"recipient_id": discordUserId}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/users/@me/channels", $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord create-DM error " & $resp.status & ": " & resp.body)
  try:
    let chId = parseJson(resp.body) |> extractJsonId
    if chId.len == 0: return err("Discord create-DM: response missing 'id'")
    a.dmChannels[][discordUserId] = chId
    ok(chId)
  except CatchableError as e:
    err(e.msg)

proc fetchUnreadMessages*(a: DiscordAdapter; chId: string; limit = 10): Result[seq[JsonNode], string] =
  ## Fetches recent messages from a channel via REST API.
  ## Used to process messages received while bot was offline.
  let headers = @[a.authHeader()]
  let url = a.base() & "/channels/" & chId & "/messages?limit=" & $limit
  let resp = ? a.http.get(url, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord fetch messages error " & $resp.status)
  try:
    let msgs = parseJson(resp.body)
    if msgs.kind != JArray:
      return err("Discord messages response is not an array")
    var filtered: seq[JsonNode] = @[]
    for msg in msgs:
      # Skip bots (including our own messages) and webhook posts; a message
      # with neither text nor attachment is dropped by the parser.
      if isBotAuthored(msg):
        continue
      filtered.add(msg)
    ok(filtered)
  except CatchableError as e:
    err(e.msg)

# ── ChannelPort procs ──────────────────────────────────────────────────────────

proc makeComponentRows(buttons: seq[seq[(string, string)]]): seq[JsonNode] =
  ## Converts a seq-of-rows of (label, custom_id) pairs to Discord ACTION_ROW components.
  for row in buttons:
    var comps: seq[JsonNode]
    for (label, data) in row:
      comps.add(%* {"type": 2, "style": 1, "label": label, "custom_id": data})
    if comps.len > 0:
      result.add(%* {"type": 1, "components": comps})

var gNonceCounter {.threadvar.}: uint32

proc messageNonce(): string =
  ## Unique per message create; reused by the HTTP layer's retries of the
  ## same request, which is the point. Discord allows up to 25 characters.
  ## A repeated nonce would make Discord answer with another message, so
  ## the fallback (no OS randomness) is millisecond + counter + random,
  ## which cannot repeat within this thread.
  var bytes: array[10, byte]
  if urandom(bytes):
    for b in bytes: result.add(toHex(b, 2))
  else:
    inc gNonceCounter
    result = toHex(epochMs(), 11) & toHex(gNonceCounter, 8) &
             toHex(rand(int32.high), 6)
  result = result[0 ..< min(result.len, 25)]

func withNonce(body: JsonNode; nonce: string): JsonNode =
  ## `enforce_nonce`: a create whose nonce Discord saw in the last minutes
  ## returns that message instead of posting a duplicate. A POST retried
  ## after a timeout may already have gone through.
  result = body.copy()
  result["nonce"] = %nonce
  result["enforce_nonce"] = %true

proc sendChunk(a: DiscordAdapter; chId, text: string): Result[void, string] =
  let body    = withNonce(%* {"content": text}, messageNonce())
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/channels/" & chId & "/messages", $withSafeMentions(body), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord send error " & $resp.status & ": " & resp.body)
  ok()

func outboundChannelId(msg: OutboundMessage): string =
  if msg.replyTo.startsWith("channel:"):
    msg.replyTo["channel:".len .. ^1]
  else:
    ""

proc resolveOutboundChannelId(a: DiscordAdapter; msg: OutboundMessage): Result[string, string] =
  let explicit = outboundChannelId(msg)
  if explicit.len > 0:
    return ok(explicit)
  let discordId = a.resolver.reverseChannel(msg.userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter: no Discord ID for user " & $msg.userId)
  a.dmChannelFor(discordId)

proc sendKeyboard*(a: DiscordAdapter; userId: UserId;
                   text: string;
                   buttons: seq[seq[(string, string)]]): Result[string, string] =
  ## Sends a message with Discord component buttons.
  ## Each inner seq becomes an ACTION_ROW (max 5 buttons per row).
  ## Returns the message_id of the sent message.
  let discordId = a.resolver.reverseChannel(userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.sendKeyboard: no Discord ID for " & $userId)
  let chId = ? a.dmChannelFor(discordId)
  let body = withNonce(%* {"content": text, "components": makeComponentRows(buttons)},
                       messageNonce())
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/channels/" & chId & "/messages", $withSafeMentions(body), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord sendKeyboard error " & $resp.status & ": " & resp.body)
  let msgId = resp.body.parseJson().getOrDefault("id").getStr("")
  ok(msgId)

proc editKeyboard*(a: DiscordAdapter; userId: UserId;
                   msgId: string;
                   text: string;
                   buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Edits an existing DM message with new content and component buttons.
  let discordId = a.resolver.reverseChannel(userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.editKeyboard: no Discord ID for " & $userId)
  let chId = ? a.dmChannelFor(discordId)
  let body = %* {"content": text, "components": makeComponentRows(buttons)}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/channels/" & chId & "/messages/" & msgId
  let resp = ? a.http.patch(url, $withSafeMentions(body), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord editKeyboard error " & $resp.status & ": " & resp.body)
  ok()

proc editInteractionKeyboard*(a: DiscordAdapter;
                              interactionToken, text: string;
                              buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Edits the original interaction message with new text and components.
  let body = %* {"content": text, "components": makeComponentRows(buttons)}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  ## Use PATCH /webhooks/{application_id}/{interaction_token}/messages/@original
  let appId = if a.appId != nil: a.appId[] else: "unknown"
  let url = a.base() & "/webhooks/" & appId & "/" & interactionToken & "/messages/@original"
  let resp = ? a.http.patch(url, $withSafeMentions(body), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord edit interaction keyboard error " & $resp.status & ": " & resp.body)
  ok()

proc sendDeferredUpdate*(a: DiscordAdapter;
                         interactionId, interactionToken: string): Result[void, string] =
  ## Acknowledges a button interaction with type 6 (DEFERRED_UPDATE_MESSAGE).
  ## This suppresses the loading spinner and allows updating the message via webhook later.
  let body    = %* {"type": 6}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status == 404:
    return ok() ## benign: interaction already acknowledged/expired
  if resp.status < 200 or resp.status >= 300:
    return err("Discord deferred update error " & $resp.status)
  ok()

proc send*(a: DiscordAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message either to an explicit Discord channel target or to the
  ## user's DM channel when no channel target is provided.
  ## If msg.keyboard is non-empty, sends with component buttons.
  ## Splits messages longer than 2000 characters into multiple sends.
  if msg.keyboard.len > 0:
    discard a.sendKeyboard(msg.userId, discordText(msg.text), msg.keyboard)
    return ok()
  let chId = ? a.resolveOutboundChannelId(msg)
  for chunk in splitChunks(discordText(msg.text), DiscordMaxChars):
    ? a.sendChunk(chId, chunk)
  ok()

const DiscordEphemeralFlag* = 64  ## message visible only to the invoking user

func interactionMessageData*(content: string; ephemeral: bool): JsonNode =
  result = withSafeMentions(%* {"content": content})
  if ephemeral:
    result["flags"] = %DiscordEphemeralFlag

proc sendInteractionResponse*(a: DiscordAdapter;
                              interactionId, interactionToken, text: string;
                              ephemeral = false): Result[void, string] =
  ## Responds to a slash command interaction (must be within 3 seconds).
  ## An ephemeral response is shown only to the user who ran the command.
  let body    = %* {"type": 4, "data": interactionMessageData(text, ephemeral)}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord interaction response error " & $resp.status)
  ok()

proc sendInteractionKeyboard*(a: DiscordAdapter;
                              interactionId, interactionToken, text: string;
                              buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Responds to a slash command interaction with text and buttons.
  let body = %* {
    "type": 4,
    "data": withSafeMentions(%* {"content": text,
                                 "components": makeComponentRows(buttons)}),
  }
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord interaction keyboard error " & $resp.status & ": " & resp.body)
  ok()

proc sendInteractionEmbedPage*(a: DiscordAdapter;
                               interactionId, interactionToken: string;
                               title, description: string;
                               color: int;
                               buttons: seq[seq[(string, string)]];
                               ephemeral = false): Result[void, string] =
  ## Responds to a slash command with a rich embed + navigation buttons (type 4).
  var data = %* {
    "embeds": [{"title": title, "description": description, "color": color}],
    "components": makeComponentRows(buttons),
  }
  if ephemeral:
    data["flags"] = %DiscordEphemeralFlag
  let body = %* {"type": 4, "data": withSafeMentions(data)}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord interaction embed error " & $resp.status & ": " & resp.body)
  ok()

proc editInteractionEmbedPage*(a: DiscordAdapter;
                               interactionToken: string;
                               title, description: string;
                               color: int;
                               buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Edits the original interaction embed + buttons via webhook PATCH.
  let body = %* {
    "embeds": [{"title": title, "description": description, "color": color}],
    "components": makeComponentRows(buttons),
  }
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let appId = if a.appId != nil: a.appId[] else: "unknown"
  let url = a.base() & "/webhooks/" & appId & "/" & interactionToken & "/messages/@original"
  let resp = ? a.http.patch(url, $withSafeMentions(body), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord edit embed error " & $resp.status & ": " & resp.body)
  ok()

proc sendInteractionModal*(a: DiscordAdapter;
                           interactionId, interactionToken: string): Result[void, string] =
  ## Responds to a slash command with a modal dialog (type 9).
  ## The modal has a single text input with custom_id "link_code".
  let body = %* {
    "type": 9,   ## MODAL
    "data": {
      "custom_id": "continue_modal",
      "title":     "Continue Session",
      "components": [{
        "type": 1,   ## ACTION_ROW
        "components": [{
          "type":        4,   ## TEXT_INPUT
          "custom_id":   "link_code",
          "label":       "Link code (from /mycode on another channel)",
          "style":       1,   ## SHORT
          "min_length":  6,
          "max_length":  8,
          "placeholder": "e.g. AB3X7Q",
          "required":    true,
        }],
      }],
    },
  }
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord modal error " & $resp.status & ": " & resp.body)
  ok()

proc sendReturnId*(a: DiscordAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends a single chunk (first DiscordMaxChars) and returns the Discord message id.
  ## Used by the streaming machinery to obtain the id for subsequent editMessage calls.
  ## Uses >>= to chain HTTP response → JSON parse → id extraction.
  let chId = ? a.resolveOutboundChannelId(msg)
  let shown = discordText(msg.text)
  let txt  = if shown.len > DiscordMaxChars: shown[0 ..< DiscordMaxChars]
             else: shown
  var body    = withNonce(%* {"content": txt}, messageNonce())
  if msg.keyboard.len > 0:
    body.add("components", %makeComponentRows(msg.keyboard))
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  a.http.post(a.base() & "/channels/" & chId & "/messages", $withSafeMentions(body), headers) >>= extractId

proc editMessage*(a: DiscordAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## PATCHes an existing DM message with new text (streaming partial update).
  let discordId = a.resolver.reverseChannel(userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.editMessage: no Discord ID for " & $userId)
  let chId = ? a.dmChannelFor(discordId)
  let shown = discordText(text)
  let txt  = if shown.len > DiscordMaxChars: shown[0 ..< DiscordMaxChars] else: shown
  let body    = %* {"content": txt}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url  = a.base() & "/channels/" & chId & "/messages/" & msgId
  let resp = ? a.http.patch(url, $withSafeMentions(body), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord editMessage error " & $resp.status)
  ok()

proc setMessageReaction*(a: DiscordAdapter; userId: UserId;
                         channelId, msgId, emoji: string): Result[void, string] =
  ## Adds or removes a status reaction on an existing message.
  ## channelId is the Discord channel where the target message lives (DM or guild).
  if channelId.len == 0 or msgId.len == 0:
    return ok()
  let cacheKey = channelId & ":" & msgId
  let previous = a.statusReactions[].getOrDefault(cacheKey)
  if previous == emoji:
    return ok()
  let headers = @[a.authHeader()]
  if previous.len > 0:
    let encoded = encodeUrl(previous, usePlus = false)
    let removeUrl = a.base() & "/channels/" & channelId &
      "/messages/" & msgId & "/reactions/" & encoded & "/@me"
    let resp = ? a.http.delete(removeUrl, headers)
    if resp.status == 429:
      return ok() ## cosmetic only; avoid noisy logs and extra pressure
    if resp.status != 204 and resp.status != 404:
      return err("Discord remove reaction error " & $resp.status & ": " & resp.body)

  if emoji.len == 0:
    a.statusReactions[][cacheKey] = ""
    return ok()

  let addUrl = a.base() & "/channels/" & channelId &
    "/messages/" & msgId & "/reactions/" & encodeUrl(emoji, usePlus = false) & "/@me"
  let addResp = ? a.http.put(addUrl, "", headers)
  if addResp.status == 429:
    return ok() ## cosmetic only; avoid noisy logs and extra pressure
  if addResp.status != 204 and addResp.status != 200:
    return err("Discord add reaction error " & $addResp.status & ": " & addResp.body)
  a.statusReactions[][cacheKey] = emoji
  ok()

proc downloadFile*(a: DiscordAdapter; fileId: string): Result[FileDownload, string] =
  ## Downloads an attachment from Discord CDN.
  ## fileId is the attachment URL (proxy_url or url from gateway event).
  if fileId.len == 0:
    return err("Discord downloadFile: empty fileId")
  if not isDiscordCdnUrl(fileId):
    return err("Discord downloadFile: not a Discord CDN URL")
  try:
    let headers: seq[(string, string)] = @[]
    let resp = ? a.http.get(fileId, headers)
    if resp.status != 200:
      return err("Discord downloadFile error " & $resp.status & ": " & resp.body)
    var data = newSeq[byte](resp.body.len)
    for i in 0 ..< resp.body.len:
      data[i] = cast[byte](resp.body[i])
    let fileName = fileId.split("/")[^1].split("?")[0]
    ok(FileDownload(
      fileName: fileName,
      fileSize: data.len.int64,
      mimeType: extractMimeType(fileId),
      localPath: "",
      data: data,
    ))
  except CatchableError as e:
    err(e.msg)

proc notePendingCursor*(a: DiscordAdapter; userId: UserId; msgId: string) =
  ## A DM handed to a turn: the cursor may move to it once the turn is done.
  if a.cursor.isNil or msgId.len == 0: return
  let key = $userId
  a.cursor.pending[key] = laterSnowflake(a.cursor.pending.getOrDefault(key, ""), msgId)

func hasPendingCursor*(a: DiscordAdapter; userId: UserId): bool =
  not a.cursor.isNil and a.cursor.pending.getOrDefault($userId, "").len > 0

proc settleCursor*(a: DiscordAdapter; userId: UserId) =
  ## Saves the pending cursor of `userId`, once.
  if a.cursor.isNil: return
  let key = $userId
  let msgId = a.cursor.pending.getOrDefault(key, "")
  if msgId.len == 0: return
  a.cursor.pending.del(key)
  if a.cursor.save != nil:
    a.cursor.save(userId, msgId)

proc ack*(a: DiscordAdapter; channelId: string) =
  ## No-op — Discord has no explicit acknowledgement step.
  discard

# ── Gateway management ─────────────────────────────────────────────────────────

proc startGateway*(a: DiscordAdapter; logger: Logger) {.gcsafe.} =
  ## Starts the Discord gateway connection. Call once at daemon startup.
  if gDiscordGateway.running:
    return
  let started = startPersistentSocket("discord", DiscordGatewayProtocol,
    DiscordGatewayConfig(token: a.token), defaultSocketPolicy(), logger)
  if started.isErr:
    logger.error("discord: " & started.error)
    return
  gDiscordGateway = started.get

proc stopGateway*() =
  ## Closes the gateway connection at shutdown. Safe when it never started.
  gDiscordGateway.stop()

proc tryRecvEvent*(a: DiscordAdapter): (bool, DiscordRawEvent) =
  ## Non-blocking poll for gateway events. Returns (false, default) when empty.
  gDiscordEvents.tryTake()

# ── Slash command registration ─────────────────────────────────────────────────

proc getAppId*(a: DiscordAdapter): Result[string, string] =
  ## Fetches the bot's application ID via GET /users/@me.
  try:
    let resp = ? a.http.get(a.base() & "/users/@me", @[a.authHeader()])
    if resp.status == 401:
      return err("Discord getAppId error 401: Unauthorized. Check if DISCORD_BOT_TOKEN is correct.")
    if resp.status < 200 or resp.status >= 300:
      return err("Discord getAppId error " & $resp.status & ": " & resp.body)
    let id = ? extractId(resp)
    if a.appId != nil: a.appId[] = id
    ok(id)
  except CatchableError as e:
    err(e.msg)

proc botUserId*(a: DiscordAdapter): string =
  ## The bot's own user id (`/users/@me`), cached after the first lookup.
  ## Empty when the lookup fails; a server message then addresses nobody.
  if a.appId != nil and a.appId[].len > 0:
    return a.appId[]
  a.getAppId().get("")

proc registerSlashCommands*(a: DiscordAdapter; appId: string; guildId = ""): Result[void, string] =
  ## Registers the operational command surface as global or guild application commands.
  let commands = newCommandCatalog().toDiscordSlashCommandsJson()
  ## Add DM support: integration_types [GUILD_INSTALL, USER_INSTALL] + contexts [GUILD, BOT_DM, PRIVATE_CHANNEL]
  for i in 0 ..< commands.len:
    commands[i]["integration_types"] = %* [0, 1]
    commands[i]["contexts"]          = %* [0, 1, 2]
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url =
    if guildId.len > 0:
      a.base() & "/applications/" & appId & "/guilds/" & guildId & "/commands"
    else:
      a.base() & "/applications/" & appId & "/commands"
  ## Bulk overwrite — replaces all existing global or guild commands.
  try:
    let resp = ? a.http.put(url, $commands, headers)
    if resp.status == 403:
      return err("Discord register commands error 403: Forbidden. Check if application.commands scope is granted.")
    if resp.status < 200 or resp.status >= 300:
      return err("Discord register commands error " & $resp.status & ": " & resp.body)
    ok()
  except CatchableError as e:
    err("Discord register commands failed: " & e.msg)

# ── Constructor ────────────────────────────────────────────────────────────────

const
  DiscordDedupeTtlSec* = 600.0
    ## A gateway RESUME replays the events missed while disconnected, and the
    ## startup backfill can overlap the first live events: minutes, not hours.
  DiscordDedupeMaxMessages* = 2048

proc isDuplicateMessage*(a: DiscordAdapter; messageId: string;
                         now = epochTime()): bool =
  ## True when this message id was already handled: the turn or command must
  ## not run twice. An adapter built without the cache never reports one.
  if a.seenMessages == nil: return false
  a.seenMessages[].seenBefore(messageId, now)

func discordAllowedChannels*(env: Environment): seq[string] =
  ## `DONKEY_DISCORD_ALLOWED_CHANNELS`: comma-separated server or channel ids.
  parseChatIdList(env.get("DONKEY_DISCORD_ALLOWED_CHANNELS"))

func discordRequireMention*(env: Environment): bool =
  ## `DONKEY_DISCORD_REQUIRE_MENTION`: opt-in, like the Telegram switch.
  mentionRequiredFromEnv(env.get("DONKEY_DISCORD_REQUIRE_MENTION"))

proc newDiscordAdapter*(token:        string;
                        identityPath: string;
                        apiBase       = "";
                        requireMention = false;
                        allowedChannels: seq[string] = @[]): DiscordAdapter =
  var t = new(Table[string, string])
  t[] = initTable[string, string]()
  var sr = new(Table[string, string])
  sr[] = initTable[string, string]()
  var appId = new(string)
  appId[] = ""
  var seen = new(RecentIds)
  seen[] = initRecentIds(DiscordDedupeTtlSec, DiscordDedupeMaxMessages)
  let cursor = DiscordCursorState(pending: initTable[string, string]())
  DiscordAdapter(
    token:      token,
    apiBase:    apiBase,
    appId:      appId,
    resolver:   newIdentityResolver(identityPath),
    dmChannels: t,
    statusReactions: sr,
    seenMessages: seen,
    requireMention: requireMention,
    allowedChannels: allowedChannels,
    cursor: cursor,
    http:       newStdHttpAdapter(),
  )
