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
import ../../core/app_meta
import ../../core/types
import ../../core/pipeops
import ../../domain/message
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

proc handleDispatch(t: string; d: JsonNode) =
  ## Parses a Discord dispatch event and pushes to gDiscordEvents.
  case t

  of "MESSAGE_CREATE":
    let author = d.getOrDefault("author")
    if author == nil: return
    if author.getOrDefault("bot").getBool(false): return  ## ignore bot messages
    let content = d.getOrDefault("content").getStr("")
    if content.len == 0: return
    gDiscordEvents.send(DiscordRawEvent(
      kind:          deMessage,
      discordUserId: author["id"].getStr(),
      content:       content,
      channelId:     d["channel_id"].getStr(),
      messageId:     d["id"].getStr(),
    ))

  of "INTERACTION_CREATE":
    let interactionType = d.getOrDefault("type").getInt(0)
    let interactionId    = d["id"].getStr()
    let interactionToken = d["token"].getStr()
    let userNode = if d.hasKey("user"): d["user"]
                   elif d.hasKey("member"): d["member"]["user"]
                   else: nil
    if userNode == nil: return
    let userId = userNode["id"].getStr()

    ## Type 2: APPLICATION_COMMAND
    if interactionType == 2:
      let iData = d.getOrDefault("data")
      if iData == nil: return
      let cmdName = iData["name"].getStr()
      proc optionValue(name: string): string =
        let opts = iData.getOrDefault("options")
        if opts != nil and opts.kind == JArray:
          for opt in opts:
            if opt["name"].getStr() == name:
              return opt["value"].getStr()
        ""

      if cmdName in ["start", "help", "memory", "forget", "doctor",
                     "reset", "debug", "mycode", "ping", "status"]:
        gDiscordEvents.send(DiscordRawEvent(
          kind:          deMessage,
          discordUserId: userId,
          content:       "/" & cmdName,
          interactionId: interactionId,
          interactionToken: interactionToken,
        ))
        return
      if cmdName == "models":
        let provider = optionValue("provider")
        let model = optionValue("model")
        let suffix = if provider.len > 0 and model.len > 0: " " & provider & " " & model
                     elif provider.len > 0: " " & provider
                     else: ""
        gDiscordEvents.send(DiscordRawEvent(
          kind:             deMessage,
          discordUserId:    userId,
          content:          "/models" & suffix,
          interactionId:    interactionId,
          interactionToken: interactionToken,
        ))
        return
      if cmdName == "think":
        let level = optionValue("level")
        gDiscordEvents.send(DiscordRawEvent(
          kind:             deMessage,
          discordUserId:    userId,
          content:          if level.len > 0: "/think " & level else: "/think",
          interactionId:    interactionId,
          interactionToken: interactionToken,
        ))
        return
      if cmdName != "continue": return
      var code = ""
      code = optionValue("code")
      if code.len > 0:
        ## Has inline code — process directly (legacy slash command style).
        gDiscordEvents.send(DiscordRawEvent(
          kind:             deInteraction,
          discordUserId:    userId,
          content:          code,
          interactionId:    interactionId,
          interactionToken: interactionToken,
        ))
      else:
        ## No code — request a modal from the daemon (needs HTTP response).
        gDiscordEvents.send(DiscordRawEvent(
          kind:             deModalRequest,
          discordUserId:    userId,
          interactionId:    interactionId,
          interactionToken: interactionToken,
        ))

    ## Type 3: MESSAGE_COMPONENT (button click)
    if interactionType == 3:
      let customId = d.getOrDefault("data").getOrDefault("custom_id").getStr("")
      gDiscordEvents.send(DiscordRawEvent(
        kind:             deButtonClick,
        discordUserId:    userId,
        content:          customId,
        interactionId:    interactionId,
        interactionToken: interactionToken,
      ))
      return

    ## Type 5: MODAL_SUBMIT
    if interactionType == 5:
      ## Extract code from modal component rows.
      var code = ""
      let components = d.getOrDefault("data").getOrDefault("components")
      if components != nil and components.kind == JArray:
        for row in components:
          let rowComps = row.getOrDefault("components")
          if rowComps != nil and rowComps.kind == JArray:
            for comp in rowComps:
              if comp.getOrDefault("custom_id").getStr("") == "link_code":
                code = comp.getOrDefault("value").getStr("")
      gDiscordEvents.send(DiscordRawEvent(
        kind:             deInteraction,
        discordUserId:    userId,
        content:          code,
        interactionId:    interactionId,
        interactionToken: interactionToken,
      ))

  else: discard

proc runGatewaySession(token: string; state: var GatewayState) =
  ## Single gateway session: connect, identify/resume, loop until error.
  let host =
    if state.resumeUrl.startsWith("wss://"):
      let noScheme = state.resumeUrl[6 .. ^1]
      if '/' in noScheme: noScheme[0 ..< noScheme.find('/')] else: noScheme
    else: "gateway.discord.gg"

  state.ws = wsConnect(host, Port(443), "/?v=10&encoding=json", useTls = true)

  ## 1. Hello → get heartbeat interval.
  let helloFrame = state.ws.recvFrame()
  let hello = parseJson(helloFrame.data)
  state.heartbeatMs = hello["d"]["heartbeat_interval"].getInt(41250)

  ## 2. Send first heartbeat with random jitter (Discord requirement).
  randomize()
  let jitter = rand(state.heartbeatMs)
  let startMs = epochMs()
  while epochMs() - startMs < jitter:
    sleep(100)
  state.sendHeartbeat()

  ## 3. Identify or Resume.
  if state.sessionId.len > 0:
    state.ws.sendFrame($ %* {
      "op": 6,
      "d": {"token": token, "session_id": state.sessionId, "seq": state.lastSeq},
    })
  else:
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
          else:
            handleDispatch(t, d)

        of 7:  ## Reconnect
          raise newException(IOError, "Discord requested reconnect (op=7)")

        of 9:  ## Invalid Session
          if not j["d"].getBool(false):
            state.sessionId = ""; state.resumeUrl = ""
          raise newException(IOError, "Invalid session (op=9)")

        of 11: discard  ## Heartbeat ACK
        else:  discard

      of WsOpcodePing:
        state.ws.sendFrame(frame.data, WsOpcodePong)

      of WsOpcodeClose:
        raise newException(IOError, "Discord gateway closed (op=close)")

      else: discard

    except TimeoutError:
      discard  ## no data — loop back to heartbeat check

type GatewayArgs = object
  token: string

proc discordGatewayThread(arg: GatewayArgs) {.thread.} =
  ## Entry point for the dedicated gateway OS thread.
  ## Reconnects automatically with exponential backoff (capped at 60 s).
  var state = GatewayState()
  var backoffMs = 1000
  while true:
    try:
      runGatewaySession(arg.token, state)
    except Exception as e:
      echo "[discord] gateway error: " & e.msg & " — reconnecting in " &
           $backoffMs & " ms"
      sleep(backoffMs)
      backoffMs = min(backoffMs * 2, 60_000)

var gGatewayThread {.global.}: Thread[GatewayArgs]

# ── DiscordAdapter ─────────────────────────────────────────────────────────────

type
  DiscordAdapter* = object
    token*:     string
    apiBase*:   string       ## override for testing
    resolver*:  IdentityResolver
    dmChannels: ref Table[string, string]  ## discord_user_id → dm_channel_id (ref allows value receiver)
    http*:      StdHttpAdapter

func authHeader(a: DiscordAdapter): (string, string) =
  ("Authorization", "Bot " & a.token)

func base(a: DiscordAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: DiscordApiBase

# ── REST helpers ───────────────────────────────────────────────────────────────

proc dmChannelFor(a: DiscordAdapter; discordUserId: string): Result[string, string] =
  ## Returns (or creates) the DM channel ID for the given Discord user.
  if discordUserId in a.dmChannels[]:
    return ok(a.dmChannels[][discordUserId])
  let body    = %* {"recipient_id": discordUserId}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/users/@me/channels", $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord create-DM error " & $resp.status & ": " & resp.body)
  try:
    let j = parseJson(resp.body)
    let chId = j["id"].getStr()
    a.dmChannels[][discordUserId] = chId
    ok(chId)
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
  ## Sends a message with Discord component buttons. Returns the message id.
  ## Each inner seq becomes an ACTION_ROW (max 5 buttons per row).
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
  try:
    ok(parseJson(resp.body)["id"].getStr())
  except CatchableError as e:
    err(e.msg)

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

proc sendButtonAck*(a: DiscordAdapter;
                    interactionId, interactionToken: string): Result[void, string] =
  ## Acknowledges a button interaction with type 6 (DEFERRED_UPDATE_MESSAGE).
  ## Must be called within 3 s of the button click to suppress the loading spinner.
  let body    = %* {"type": 6}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/interactions/" & interactionId & "/" & interactionToken & "/callback"
  let resp = ? a.http.post(url, $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord button ack error " & $resp.status)
  ok()

proc send*(a: DiscordAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user's DM channel on Discord.
  ## If msg.keyboard is non-empty, sends with component buttons.
  ## Splits messages longer than 2000 characters into multiple sends.
  if msg.keyboard.len > 0:
    discard ? a.sendKeyboard(msg.userId, msg.text, msg.keyboard)
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
  let discordId = a.resolver.reverseChannel(msg.userId, ckDiscord)
  if discordId.len == 0:
    return err("DiscordAdapter.sendReturnId: no Discord ID for " & $msg.userId)
  let chId = ? a.dmChannelFor(discordId)
  let txt  = if msg.text.len > DiscordMaxChars: msg.text[0 ..< DiscordMaxChars]
             else: msg.text
  let body    = %* {"content": txt}
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.post(a.base() & "/channels/" & chId & "/messages", $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord sendReturnId error " & $resp.status & ": " & resp.body)
  try:
    ok(parseJson(resp.body)["id"].getStr())
  except CatchableError as e:
    err(e.msg)

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

proc startGateway*(a: DiscordAdapter) {.gcsafe.} =
  ## Starts the Discord gateway thread. Call once at daemon startup.
  {.cast(gcsafe).}:
    gDiscordEvents.open()
    createThread(gGatewayThread, discordGatewayThread, GatewayArgs(token: a.token))

proc tryRecvEvent*(a: DiscordAdapter): (bool, DiscordRawEvent) =
  ## Non-blocking poll for gateway events. Returns (false, default) when empty.
  gDiscordEvents.tryRecv()

# ── Slash command registration ─────────────────────────────────────────────────

proc getAppId*(a: DiscordAdapter): Result[string, string] =
  ## Fetches the bot's application ID via GET /users/@me.
  let headers = @[a.authHeader()]
  let resp = ? a.http.get(a.base() & "/users/@me", headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord /users/@me error " & $resp.status)
  try:
    ok(parseJson(resp.body)["id"].getStr())
  except CatchableError as e:
    err(e.msg)

proc registerSlashCommands*(a: DiscordAdapter; appId: string): Result[void, string] =
  ## Registers the operational command surface as global application commands.
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
    {"name": "ping",   "type": 1, "description": "Measure provider latency"},
    {"name": "status", "type": 1, "description": "Show session/runtime status"},
  ]
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let url = a.base() & "/applications/" & appId & "/commands"
  ## Bulk overwrite — replaces all existing global commands.
  let resp = ? a.http.put(url, $commands, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Discord register commands error " & $resp.status & ": " & resp.body)
  ok()

# ── Constructor ────────────────────────────────────────────────────────────────

proc newDiscordAdapter*(token:        string;
                        identityPath: string;
                        apiBase       = ""): DiscordAdapter =
  var t = new(Table[string, string])
  t[] = initTable[string, string]()
  DiscordAdapter(
    token:      token,
    apiBase:    apiBase,
    resolver:   newIdentityResolver(identityPath),
    dmChannels: t,
    http:       newStdHttpAdapter(),
  )
