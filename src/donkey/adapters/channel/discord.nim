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

import std/[json, locks, net, os, random, strutils, tables, times, uri]
import ../../core/log
import ../../core/app_meta
import ../../core/commands/command_catalog
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/discord_pure
import ../../ports/http
import ../../core/media_download
import ../http/std_http
import ../identity/identity_resolver
import ./ws_client

const DiscordMaxChars* = 2000

# ── Public event type (thread → main) ─────────────────────────────────────────

type
  DiscordEventKind* = enum
    deMessage       ## regular DM or guild message
    deInteraction   ## slash command interaction (code already extracted)
    deModalRequest  ## /continue slash cmd without code → need to show modal
    deButtonClick   ## component button click — content = custom_id

  DiscordRawEvent* = object
    kind*:             DiscordEventKind
    discordUserId*:    string
    content*:          string   ## message text OR interaction option value
    channelId*:        string   ## Discord channel ID (for messages)
    messageId*:        string
    interactionId*:    string
    interactionToken*: string

# ── Gateway thread ─────────────────────────────────────────────────────────────

## Module-level channel — opened once, valid for daemon lifetime.
## Thread-safe: chronos Channel uses internal synchronization.
var gDiscordEvents* {.global.}: Channel[DiscordRawEvent]

## Buffer for messages received before gateway is ready (READY dispatch).
## Protected by gDiscordBufLock — written from gateway OS thread in
## handleDispatch/runGatewaySession, read in the same thread AND flushed
## to gDiscordEvents when READY arrives. The lock prevents corruption if
## handleDispatch is called concurrently with the flush loop.
var gDiscordPending* {.global.}: seq[DiscordRawEvent] = @[]

## Set to true once the gateway receives the READY dispatch.
## Protected by gDiscordBufLock — written from gateway thread, read in
## handleDispatch to decide whether to buffer or send directly.
var gDiscordReady* {.global.}: bool = false

## Lock protecting gDiscordPending and gDiscordReady.
## Initialized by initDiscordGlobals() called at daemon startup.
var gDiscordBufLock {.global.}: Lock

proc initDiscordGlobals*() =
  ## Call once at daemon startup before any Discord gateway activity.
  initLock(gDiscordBufLock)

const
  DiscordApiBase*   = "https://discord.com/api/v10"
  DiscordGatewayUrl = "wss://gateway.discord.gg"
  DiscordIntents    = 37376  ## GUILD_MESSAGES(512) + DIRECT_MESSAGES(4096) + MESSAGE_CONTENT(32768)

type
  GatewayState = object
    ws:           WsClient
    heartbeatMs:  int
    lastBeatMs:   int64   ## epoch ms of last heartbeat sent
    lastSeq:      int     ## last dispatch sequence number
    sessionId:    string
    resumeUrl:    string  ## provided in READY for resume
  DiscordReconnect = object of IOError  ## OP=7 is normal, not an error

proc epochMs(): int64 =
  let t = getTime()
  t.toUnix() * 1000 + (t.nanosecond div 1_000_000)

proc sendHeartbeat(state: var GatewayState) =
  let payload = if state.lastSeq > 0: $state.lastSeq else: "null"
  state.ws.sendFrame("{\"op\":1,\"d\":" & payload & "}")
  state.lastBeatMs = epochMs()

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
  ## All gDiscordReady/gDiscordPending accesses protected by gDiscordBufLock.
  let r = parseDispatch(t, d)
  case r.kind
  of dekUnknown: return
  of dekMessage:
    logger.debug("discord: message from " & r.rawId)
    let event = DiscordRawEvent(
      kind:          deMessage,
      discordUserId: r.rawId,
      content:       r.content,
      channelId:     r.channelId,
      messageId:     r.messageId,
    )
    acquire(gDiscordBufLock)
    let ready = gDiscordReady
    release(gDiscordBufLock)
    if ready:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        acquire(gDiscordBufLock)
        gDiscordPending.add(event)
        release(gDiscordBufLock)
  of dekSlashCommand:
    logger.debug("discord: slash command from " & r.rawId)
    let event =
      if r.needsModal:
        DiscordRawEvent(
          kind:             deModalRequest,
          discordUserId:    r.rawId,
          interactionId:    r.interactionId,
          interactionToken: r.interactionToken,
        )
      elif r.content.len > 0 and not r.content.startsWith("/"):
        DiscordRawEvent(
          kind:             deInteraction,
          discordUserId:    r.rawId,
          content:          r.content,
          interactionId:    r.interactionId,
          interactionToken: r.interactionToken,
        )
      else:
        DiscordRawEvent(
          kind:             deMessage,
          discordUserId:    r.rawId,
          content:          r.content,
          interactionId:    r.interactionId,
          interactionToken: r.interactionToken,
        )
    acquire(gDiscordBufLock)
    let ready = gDiscordReady
    release(gDiscordBufLock)
    if ready:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        acquire(gDiscordBufLock)
        gDiscordPending.add(event)
        release(gDiscordBufLock)
  of dekButtonClick:
    logger.debug("discord: button click from " & r.rawId)
    let event = DiscordRawEvent(
      kind:             deButtonClick,
      discordUserId:    r.rawId,
      content:          r.content,
      messageId:        r.messageId,
      interactionId:    r.interactionId,
      interactionToken: r.interactionToken,
    )
    acquire(gDiscordBufLock)
    let ready = gDiscordReady
    release(gDiscordBufLock)
    if ready:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        acquire(gDiscordBufLock)
        gDiscordPending.add(event)
        release(gDiscordBufLock)
  of dekModalSubmit:
    ## Modal submit always carries a code from the link_code text input.
    logger.debug("discord: modal submit from " & r.rawId)
    let event = DiscordRawEvent(
      kind:             deInteraction,
      discordUserId:    r.rawId,
      content:          r.content,
      interactionId:    r.interactionId,
      interactionToken: r.interactionToken,
    )
    acquire(gDiscordBufLock)
    let ready = gDiscordReady
    release(gDiscordBufLock)
    if ready:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        acquire(gDiscordBufLock)
        gDiscordPending.add(event)
        release(gDiscordBufLock)

proc runGatewaySession(token: string; state: var GatewayState; logger: Logger) =
  ## Single gateway session: connect, identify/resume, loop until error.
  {.cast(gcsafe).}:
    let host =
      if state.resumeUrl.startsWith("wss://"):
        let noScheme = state.resumeUrl[6 .. ^1]
        if '/' in noScheme: noScheme[0 ..< noScheme.find('/')] else: noScheme
      else: DiscordGatewayUrl[6 .. ^1]  ## strip "wss://" from the constant

    logger.info("discord: connecting to " & host)
    state.ws = wsConnect(host, Port(443), "/?v=10&encoding=json", useTls = true)

    ## 1. Hello → get heartbeat interval.
    let helloRes = state.ws.recvFrame()
    if helloRes.isErr:
      raise newException(IOError, "Discord hello failed: " & helloRes.error)
    let hello = parseJson(helloRes.get().data)
    state.heartbeatMs = hello["d"]["heartbeat_interval"].getInt(41250)
    logger.debug("discord: hello, heartbeat=" & $state.heartbeatMs)

    ## 2. Send first heartbeat with random jitter (Discord requirement).
    ## Use smaller jitter at startup (max 5s) for faster initial response.
    randomize()
    let jitter = rand(min(state.heartbeatMs, 5000))  # 0-5s instead of 0-41s
    let startMs = epochMs()
    while epochMs() - startMs < jitter:
      sleep(100)
    state.sendHeartbeat()

    ## 3. Identify or Resume.
    if state.sessionId.len > 0:
      logger.info("discord: resuming session " & state.sessionId)
      state.ws.sendFrame($ %* {
        "op": 6,
        "d": {"token": token, "session_id": state.sessionId, "seq": state.lastSeq},
      })
    else:
      logger.info("discord: identifying")
      state.ws.sendFrame($ %* {
        "op": 2,
        "d": {
          "token":      token,
          "intents":    DiscordIntents,
          "properties": {"os": "linux", "browser": AppSlug, "device": AppSlug},
        },
      })

    ## 4. Main receive loop.
    while true:
      if epochMs() - state.lastBeatMs >= state.heartbeatMs:
        state.sendHeartbeat()

      try:
        let frameRes = state.ws.recvFrame()
        if frameRes.isErr:
          if frameRes.error == "timeout":
            continue
          logger.warn("discord: receive failed: " & frameRes.error)
          break
        let frame = frameRes.get()
        case frame.opcode

        of WsOpcodeText:
          let j = parseJson(frame.data)
          let op = j["op"].getInt()

          case op
          of 0:  ## Dispatch
            let s = j["s"].getInt(0)
            if s > 0: state.lastSeq = s
            let t = j["t"].getStr("")
            let d = j["d"]
            if t == "READY":
              state.sessionId = d["session_id"].getStr()
              let rgu = d.getOrDefault("resume_gateway_url")
              if rgu != nil: state.resumeUrl = rgu.getStr()
              logger.info("discord: ready, session=" & state.sessionId)
              ## Gateway is now ready — flush buffered messages.
              ## Protected by gDiscordBufLock.
              acquire(gDiscordBufLock)
              gDiscordReady = true
              let pendingCount = gDiscordPending.len
              if pendingCount > 0:
                logger.info("discord: flushing " & $pendingCount & " buffered message(s)")
                for event in gDiscordPending:
                  gDiscordEvents.send(event)
                gDiscordPending = @[]
              release(gDiscordBufLock)
            else:
              handleDispatch(t, d, logger)

          of 7:  ## Reconnect
            logger.info("discord: reconnect requested (op=7)")
            break

          of 9:  ## Invalid Session
            logger.warn("discord: invalid session (op=9)")
            if not j["d"].getBool(false):
              state.sessionId = ""; state.resumeUrl = ""
            break

          of 11: discard  ## Heartbeat ACK
          else:  discard

        of WsOpcodePing:
          state.ws.sendFrame(frame.data, WsOpcodePong)

        of WsOpcodeClose:
          logger.warn("discord: websocket closed")
          break

        else: discard

      except TimeoutError:
        discard  ## no data — loop back to heartbeat check

type GatewayArgs = object
  token:  string
  logger: Logger

proc discordGatewayThread(arg: GatewayArgs) {.thread.} =
  ## Entry point for the dedicated gateway OS thread.
  ## Reconnects automatically with exponential backoff (capped at 60 s).
  var state = GatewayState()
  var backoffMs = 1000
  while true:
    try:
      runGatewaySession(arg.token, state, arg.logger)
      backoffMs = 1000 # Reset backoff on successful session
    except DiscordReconnect:
      # OP=7 is normal - Discord requests reconnect for load balancing
      arg.logger.info("discord: reconnecting…")
      sleep(1000) # Brief pause before reconnect
    except Exception as e:
      arg.logger.error("discord: gateway error: " & e.msg & " — reconnecting in " & $backoffMs & " ms")
      sleep(backoffMs)
      backoffMs = min(backoffMs * 2, 60_000)

## Thread handle for the Discord gateway OS thread.
## Safe: only assigned once via createThread, never mutated concurrently.
var gGatewayThread {.global.}: Thread[GatewayArgs]

# ── DiscordAdapter ─────────────────────────────────────────────────────────────

type
  DiscordAdapter* = object
    token*:     string
    apiBase*:   string       ## override for testing
    appId*:     ref string   ## cached application ID
    resolver*:  IdentityResolver
    dmChannels: ref Table[string, string]  ## discord_user_id → dm_channel_id (ref allows value receiver)
    statusReactions: ref Table[string, string] ## channel_id:message_id -> emoji
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
      # Skip bot's own messages
      let author = msg.getOrDefault("author")
      if author.getOrDefault("bot").getBool(false):
        continue
      # Skip messages without content
      let content = msg.getOrDefault("content").getStr("")
      if content.len == 0:
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

proc sendChunk(a: DiscordAdapter; chId, text: string): Result[void, string] =
  let body    = %* {"content": text}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/channels/" & chId & "/messages", $body, headers)
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
  let body = %* {"content": text, "components": makeComponentRows(buttons)}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/channels/" & chId & "/messages", $body, headers)
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
  let resp = ? a.http.patch(url, $body, headers)
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
  let resp = ? a.http.patch(url, $body, headers)
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
    discard a.sendKeyboard(msg.userId, msg.text, msg.keyboard)
    return ok()
  let chId = ? a.resolveOutboundChannelId(msg)
  for chunk in splitChunks(msg.text, DiscordMaxChars):
    ? a.sendChunk(chId, chunk)
  ok()

proc sendInteractionResponse*(a: DiscordAdapter;
                              interactionId, interactionToken, text: string): Result[void, string] =
  ## Responds to a slash command interaction (must be within 3 seconds).
  let body    = %* {"type": 4, "data": {"content": text}}
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
    "data": {"content": text, "components": makeComponentRows(buttons)},
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
                               buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Responds to a slash command with a rich embed + navigation buttons (type 4).
  let body = %* {
    "type": 4,
    "data": {
      "embeds": [{"title": title, "description": description, "color": color}],
      "components": makeComponentRows(buttons),
    },
  }
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
  let resp = ? a.http.patch(url, $body, headers)
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
  let txt  = if msg.text.len > DiscordMaxChars: msg.text[0 ..< DiscordMaxChars]
             else: msg.text
  var body    = %* {"content": txt}
  if msg.keyboard.len > 0:
    body.add("components", %makeComponentRows(msg.keyboard))
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  a.http.post(a.base() & "/channels/" & chId & "/messages", $body, headers) >>= extractId

proc editMessage*(a: DiscordAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## PATCHes an existing DM message with new text (streaming partial update).
  let discordId = a.resolver.reverseChannel(userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.editMessage: no Discord ID for " & $userId)
  let chId = ? a.dmChannelFor(discordId)
  let txt  = if text.len > DiscordMaxChars: text[0 ..< DiscordMaxChars] else: text
  let body    = %* {"content": txt}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url  = a.base() & "/channels/" & chId & "/messages/" & msgId
  let resp = ? a.http.patch(url, $body, headers)
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

proc ack*(a: DiscordAdapter; channelId: string) =
  ## No-op — Discord has no explicit acknowledgement step.
  discard

# ── Gateway management ─────────────────────────────────────────────────────────

proc startGateway*(a: DiscordAdapter; logger: Logger) {.gcsafe.} =
  ## Starts the Discord gateway thread. Call once at daemon startup.
  {.cast(gcsafe).}:
    gDiscordEvents.open()
    createThread(gGatewayThread, discordGatewayThread, GatewayArgs(token: a.token, logger: logger))

proc tryRecvEvent*(a: DiscordAdapter): (bool, DiscordRawEvent) =
  ## Non-blocking poll for gateway events. Returns (false, default) when empty.
  gDiscordEvents.tryRecv()

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
  except Exception as e:
    err(e.msg)

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
  except Exception as e:
    err("Discord register commands failed: " & e.msg)

# ── Constructor ────────────────────────────────────────────────────────────────

proc newDiscordAdapter*(token:        string;
                        identityPath: string;
                        apiBase       = ""): DiscordAdapter =
  var t = new(Table[string, string])
  t[] = initTable[string, string]()
  var sr = new(Table[string, string])
  sr[] = initTable[string, string]()
  var appId = new(string)
  appId[] = ""
  DiscordAdapter(
    token:      token,
    apiBase:    apiBase,
    appId:      appId,
    resolver:   newIdentityResolver(identityPath),
    dmChannels: t,
    statusReactions: sr,
    http:       newStdHttpAdapter(),
  )
