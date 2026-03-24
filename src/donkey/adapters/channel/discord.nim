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

import std/[json, net, os, random, strutils, tables, times]
import ../../core/log
import ../../core/app_meta
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/discord_pure
import ../../ports/http
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
var gDiscordEvents* {.global.}: Channel[DiscordRawEvent]

## Buffer for messages received before gateway is ready.
var gDiscordPending* {.global.}: seq[DiscordRawEvent] = @[]
var gDiscordReady* {.global.}: bool = false

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
    if gDiscordReady:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        gDiscordPending.add(event)
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
    if gDiscordReady:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        gDiscordPending.add(event)
  of dekButtonClick:
    logger.debug("discord: button click from " & r.rawId)
    let event = DiscordRawEvent(
      kind:             deButtonClick,
      discordUserId:    r.rawId,
      content:          r.content,
      interactionId:    r.interactionId,
      interactionToken: r.interactionToken,
    )
    if gDiscordReady:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        gDiscordPending.add(event)
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
    if gDiscordReady:
      gDiscordEvents.send(event)
    else:
      {.cast(gcsafe).}:
        gDiscordPending.add(event)

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
    let helloFrame = state.ws.recvFrame()
    let hello = parseJson(helloFrame.data)
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
        let frame = state.ws.recvFrame()
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
              ## Gateway is now ready — flush buffered messages
              gDiscordReady = true
              if gDiscordPending.len > 0:
                logger.info("discord: flushing " & $gDiscordPending.len & " buffered message(s)")
                for event in gDiscordPending:
                  gDiscordEvents.send(event)
                gDiscordPending = @[]
            else:
              handleDispatch(t, d, logger)

          of 7:  ## Reconnect
            logger.info("discord: reconnect requested (op=7)")
            raise newException(IOError, "Discord requested reconnect (op=7)")

          of 9:  ## Invalid Session
            logger.warn("discord: invalid session (op=9)")
            if not j["d"].getBool(false):
              state.sessionId = ""; state.resumeUrl = ""
            raise newException(IOError, "Invalid session (op=9)")

          of 11: discard  ## Heartbeat ACK
          else:  discard

        of WsOpcodePing:
          state.ws.sendFrame(frame.data, WsOpcodePong)

        of WsOpcodeClose:
          logger.warn("discord: websocket closed")
          raise newException(IOError, "Discord gateway closed (op=close)")

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
    except Exception as e:
      arg.logger.error("discord: gateway error: " & e.msg & " — reconnecting in " & $backoffMs & " ms")
      sleep(backoffMs)
      backoffMs = min(backoffMs * 2, 60_000)

var gGatewayThread {.global.}: Thread[GatewayArgs]

# ── DiscordAdapter ─────────────────────────────────────────────────────────────

type
  DiscordAdapter* = object
    token*:     string
    apiBase*:   string       ## override for testing
    appId*:     ref string   ## cached application ID
    resolver*:  IdentityResolver
    dmChannels: ref Table[string, string]  ## discord_user_id → dm_channel_id (ref allows value receiver)
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

proc sendChunk(a: DiscordAdapter; chId, text: string): Result[void, string] =
  let body    = %* {"content": text}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/channels/" & chId & "/messages", $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord send error " & $resp.status & ": " & resp.body)
  ok()

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
  var rows: seq[JsonNode]
  for row in buttons:
    var comps: seq[JsonNode]
    for (label, data) in row:
      comps.add(%* {
        "type":      2,   ## BUTTON
        "style":     1,   ## PRIMARY (blurple)
        "label":     label,
        "custom_id": data,
      })
    if comps.len > 0:
      rows.add(%* {"type": 1, "components": comps})  ## ACTION_ROW
  let body    = %* {"content": text, "components": rows}
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
  var rows: seq[JsonNode]
  for row in buttons:
    var comps: seq[JsonNode]
    for (label, data) in row:
      comps.add(%* {
        "type": 2,
        "style": 1,
        "label": label,
        "custom_id": data,
      })
    if comps.len > 0:
      rows.add(%* {"type": 1, "components": comps})
  let body = %* {"content": text, "components": rows}
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
  var rows: seq[JsonNode]
  for row in buttons:
    var comps: seq[JsonNode]
    for (label, data) in row:
      comps.add(%* {
        "type": 2,
        "style": 1,
        "label": label,
        "custom_id": data,
      })
    if comps.len > 0:
      rows.add(%* {"type": 1, "components": comps})
  let body = %* {"content": text, "components": rows}
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
  if resp.status < 200 or resp.status >= 300:
    return err("Discord deferred update error " & $resp.status)
  ok()

proc send*(a: DiscordAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user's DM channel on Discord.
  ## If msg.keyboard is non-empty, sends with component buttons.
  ## Splits messages longer than 2000 characters into multiple sends.
  if msg.keyboard.len > 0:
    discard a.sendKeyboard(msg.userId, msg.text, msg.keyboard)
    return ok()
  let discordId = a.resolver.reverseChannel(msg.userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.send: no Discord ID for user " & $msg.userId)
  let chId = ? a.dmChannelFor(discordId)
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
  var rows: seq[JsonNode]
  for row in buttons:
    var comps: seq[JsonNode]
    for (label, data) in row:
      comps.add(%* {
        "type":      2,
        "style":     1,
        "label":     label,
        "custom_id": data,
      })
    if comps.len > 0:
      rows.add(%* {"type": 1, "components": comps})
  let body = %* {
    "type": 4,
    "data": {
      "content": text,
      "components": rows,
    }
  }
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord interaction keyboard error " & $resp.status & ": " & resp.body)
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
  let discordId = a.resolver.reverseChannel(msg.userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.sendReturnId: no Discord ID for " & $msg.userId)
  let chId = ? a.dmChannelFor(discordId)
  let txt  = if msg.text.len > DiscordMaxChars: msg.text[0 ..< DiscordMaxChars]
             else: msg.text
  let body    = %* {"content": txt}
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
  let commands = %* [
    {"name": "start",   "type": 1, "description": "Show the intro text"},
    {"name": "help",    "type": 1, "description": "Show available commands"},
    {"name": "memory",  "type": 1, "description": "Show saved memories"},
    {"name": "forget",  "type": 1, "description": "Clear saved memories"},
    {"name": "doctor",  "type": 1, "description": "Run a runtime diagnostic"},
    {"name": "reset",   "type": 1, "description": "Reset the active session"},
    {"name": "debug",   "type": 1, "description": "Toggle verbose tool/debug mode"},
    {
      "name":        "continue",
      "type":        1,
      "description": "Continue your session from another channel (opens dialog)",
      "options": [
        {
          "name": "code",
          "description": "Link code from /mycode on another channel",
          "type": 3,
          "required": false,
        }
      ],
    },
    {
      "name":        "mycode",
      "type":        1,
      "description": "Generate a link code to reconnect from another channel",
    },
    {
      "name":        "models",
      "type":        1,
      "description": "Show or change the active provider/model",
      "options": [
        {
          "name": "provider",
          "description": "Provider name",
          "type": 3,
          "required": false,
        },
        {
          "name": "model",
          "description": "Model name",
          "type": 3,
          "required": false,
        }
      ],
    },
    {
      "name":        "think",
      "type":        1,
      "description": "Show or change the reasoning level",
      "options": [
        {
          "name": "level",
          "description": "off, low, medium, or high",
          "type": 3,
          "required": false,
        }
      ],
    },
    {
      "name":        "budget",
      "type":        1,
      "description": "Show or change the cost/quality policy",
      "options": [
        {
          "name": "policy",
          "description": "cheap-first, balanced, or quality-first",
          "type": 3,
          "required": false,
        }
      ],
    },
    {"name": "ping",   "type": 1, "description": "Measure provider latency"},
    {"name": "status", "type": 1, "description": "Show session/runtime status"},
  ]
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
  var appId = new(string)
  appId[] = ""
  DiscordAdapter(
    token:      token,
    apiBase:    apiBase,
    appId:      appId,
    resolver:   newIdentityResolver(identityPath),
    dmChannels: t,
    http:       newStdHttpAdapter(),
  )
