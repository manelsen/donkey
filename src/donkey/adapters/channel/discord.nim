## DiscordAdapter — ChannelPort via Discord WebSocket gateway + REST API.
##
## Architecture:
##   - Gateway WebSocket loop runs in a background OS thread (asyncdispatch).
##   - Events are passed to the main thread via a Nim Channel[DiscordEvent].
##   - REST calls (send, edit, register commands) use std/httpclient directly.
##
## Gateway connection sequence (Discord API v10):
##   1. GET /gateway/bot → get WSS URL
##   2. WS connect → receive op=10 HELLO → start heartbeat
##   3. Send op=2 IDENTIFY
##   4. Receive op=0 t=READY → connected
##   5. Receive op=0 t=MESSAGE_CREATE → push DiscordEvent to channel
##
## Intents used: GUILD_MESSAGES (512) + DIRECT_MESSAGES (4096) +
##               MESSAGE_CONTENT (32768) = 37376
##
## All I/O is fallible → Result[T, string]. try/except stays inside the adapter.

import std/[httpclient, json, strutils, tables, times]
import asyncdispatch
import ws
import ../../core/pipeops
import ../../domain/message
import ../identity/identity_resolver

export identity_resolver

const
  DiscordApiBase* = "https://discord.com/api/v10"
  GatewayIntents  = 37376  ## GUILD_MESSAGES + DIRECT_MESSAGES + MESSAGE_CONTENT

type
  DiscordEventKind* = enum
    deMessage      ## Regular message in a channel/DM
    deInteraction  ## Slash command interaction (/continue <code>)

  DiscordEvent* = object
    kind*:             DiscordEventKind
    messageId*:        string
    discordUserId*:    string   ## Discord snowflake user ID (as string)
    discordChannelId*: string   ## Discord snowflake channel ID
    content*:          string
    interactionId*:    string
    interactionToken*: string

  ## Thread-shared state: main thread reads, gateway thread writes.
  ## All access to evChan is thread-safe (built-in Channel).
  GatewayArgs = object
    token:         string
    evChanPtr:     ptr Channel[DiscordEvent]

  DiscordAdapter* = object
    token*:      string
    resolver*:   IdentityResolver
    ## Nim Channel for cross-thread event delivery.
    evChan:      Channel[DiscordEvent]
    ## Maps UserId → last known Discord channel snowflake.
    ## Populated from incoming events; used for routing replies.
    chanMap:     Table[string, string]   ## UserId string → discord channel_id
    threadRunning: bool

# ── REST helpers ────────────────────────────────────────────────────────────────

proc authHeader(token: string): seq[(string, string)] =
  @[("Authorization", "Bot " & token),
    ("Content-Type", "application/json")]

proc restGet(token, url: string): Result[JsonNode, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    client.headers = newHttpHeaders(authHeader(token))
    let resp = client.get(url)
    if resp.code.int >= 400:
      return err("HTTP " & $resp.code.int & ": " & resp.body)
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc restPost(token, url, body: string): Result[JsonNode, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    client.headers = newHttpHeaders(authHeader(token))
    let resp = client.post(url, body)
    if resp.code.int >= 400:
      return err("HTTP " & $resp.code.int & ": " & resp.body)
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc restPatch(token, url, body: string): Result[JsonNode, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    client.headers = newHttpHeaders(authHeader(token))
    client.headers["X-HTTP-Method-Override"] = "PATCH"
    ## std/httpclient doesn't have a PATCH method directly; use request().
    let req = client.request(url, httpMethod = HttpPatch, body = body)
    if req.code.int >= 400:
      return err("HTTP " & $req.code.int & ": " & req.body)
    ok(parseJson(req.body))
  except CatchableError as e:
    err(e.msg)

proc restPut(token, url, body: string): Result[JsonNode, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    client.headers = newHttpHeaders(authHeader(token))
    let req = client.request(url, httpMethod = HttpPut, body = body)
    if req.code.int >= 400:
      return err("HTTP " & $req.code.int & ": " & req.body)
    ok(parseJson(req.body))
  except CatchableError as e:
    err(e.msg)

# ── Gateway thread ───────────────────────────────────────────────────────────────

proc gatewayLoop(token: string; evChan: ptr Channel[DiscordEvent]) {.async.} =
  ## Runs inside the gateway OS thread. Uses asyncdispatch (ws lib).
  ## Connects to Discord gateway and loops, pushing events to evChan.

  # 1. Get gateway URL.
  let gwUrl =
    try:
      let client = newAsyncHttpClient()
      client.headers = newHttpHeaders(@[("Authorization", "Bot " & token)])
      let resp = await client.get(DiscordApiBase & "/gateway/bot")
      let body = await resp.body
      let j = parseJson(body)
      j["url"].getStr() & "?v=10&encoding=json"
    except CatchableError as e:
      echo "[discord] failed to get gateway URL: " & e.msg
      return

  # 2. Connect WebSocket.
  var conn: WebSocket
  try:
    conn = await newWebSocket(gwUrl)
  except CatchableError as e:
    echo "[discord] WebSocket connect failed: " & e.msg
    return

  var heartbeatInterval = 41250   ## ms, updated from HELLO
  var identified         = false
  var sessionId          = ""

  ## Heartbeat loop runs in parallel via asyncCheck so it fires on schedule
  ## regardless of how long receiveStrPacket blocks.
  proc heartbeatLoop(c: WebSocket; intervalMs: int) {.async.} =
    while c.readyState == Open:
      await sleepAsync(intervalMs)
      try: await c.send($ %*{"op": 1, "d": nil})
      except CatchableError: break

  # 3. Main receive loop.
  while conn.readyState == Open:
    var data: string
    try:
      data = await conn.receiveStrPacket()
    except CatchableError as e:
      echo "[discord] receive error: " & e.msg
      break

    if data.len == 0:
      continue

    let msg =
      try: parseJson(data)
      except: continue

    let op = msg["op"].getInt(-1)

    case op
    of 10: ## HELLO
      heartbeatInterval = msg["d"]["heartbeat_interval"].getInt(41250)
      asyncCheck heartbeatLoop(conn, heartbeatInterval)
      # Send IDENTIFY
      let identify = %* {
        "op": 2,
        "d": {
          "token":   token,
          "intents": GatewayIntents,
          "properties": {
            "os":      "linux",
            "browser": "donkey",
            "device":  "donkey"
          }
        }
      }
      try:
        await conn.send($identify)
        identified = true
      except CatchableError as e:
        echo "[discord] identify failed: " & e.msg
        break

    of 11: ## HEARTBEAT ACK
      discard

    of 1: ## HEARTBEAT request from server — server-initiated heartbeat
      try: await conn.send($ %*{"op": 1, "d": nil})
      except CatchableError: break

    of 0: ## DISPATCH
      let t = msg["t"].getStr("")
      let d = msg["d"]

      case t
      of "READY":
        sessionId = d["session_id"].getStr("")
        echo "[discord] gateway ready, session=" & sessionId

      of "MESSAGE_CREATE":
        # Skip bot messages.
        let author = d["author"]
        if author{"bot"}.getBool(false):
          continue

        let ev = DiscordEvent(
          kind:             deMessage,
          messageId:        d["id"].getStr(""),
          discordUserId:    author["id"].getStr(""),
          discordChannelId: d["channel_id"].getStr(""),
          content:          d["content"].getStr(""),
          interactionId:    "",
          interactionToken: "",
        )
        evChan[].send(ev)

      of "INTERACTION_CREATE":
        ## Slash command interaction — extract the `code` option value.
        var code = ""
        let opts = d{"data"}{"options"}
        if opts != nil and opts.kind == JArray:
          for opt in opts:
            if opt{"name"}.getStr("") == "code":
              code = opt{"value"}.getStr("")
        let ev = DiscordEvent(
          kind:             deInteraction,
          messageId:        d["id"].getStr(""),
          discordUserId:    d{"member"}{"user"}{"id"}.getStr(
                              d{"user"}{"id"}.getStr("")),
          discordChannelId: d["channel_id"].getStr(""),
          content:          code,
          interactionId:    d["id"].getStr(""),
          interactionToken: d["token"].getStr(""),
        )
        evChan[].send(ev)

      else:
        discard ## Unknown dispatch type

    of 9: ## INVALID SESSION — reconnect
      echo "[discord] invalid session, reconnecting..."
      break

    of 7: ## RECONNECT
      echo "[discord] server requested reconnect"
      break

    else:
      discard

  try: conn.close()
  except: discard

proc gatewayThreadProc(args: GatewayArgs) {.thread.} =
  ## OS thread entry point. Runs its own asyncdispatch event loop.
  waitFor gatewayLoop(args.token, args.evChanPtr)

# ── Public API ───────────────────────────────────────────────────────────────────

proc newDiscordAdapter*(token: string; identityPath: string): DiscordAdapter =
  result = DiscordAdapter(
    token:    token,
    resolver: newIdentityResolver(identityPath),
    chanMap:  initTable[string, string](),
    threadRunning: false,
  )
  result.evChan.open()

var gatewayThread {.global.}: Thread[GatewayArgs]

proc startGateway*(a: var DiscordAdapter) {.gcsafe.} =
  ## Spawns the gateway background thread.
  ## Safe to call once; subsequent calls are no-ops.
  ## {.gcsafe.}: the global gatewayThread is written once before the thread
  ## is started and never read/written concurrently with the main thread
  ## after that point. The token copy lives in the thread's stack.
  if a.threadRunning:
    return
  {.cast(gcsafe).}:
    let args = GatewayArgs(token: a.token, evChanPtr: addr a.evChan)
    createThread(gatewayThread, gatewayThreadProc, args)
  a.threadRunning = true

proc tryRecvEvent*(a: var DiscordAdapter): (bool, DiscordEvent) =
  ## Non-blocking dequeue of the next gateway event.
  ## Also updates the internal UserId→channelId mapping.
  let (ok2, ev) = a.evChan.tryRecv()
  if not ok2:
    return (false, DiscordEvent())
  ## Record which Discord channel this user last spoke in.
  a.chanMap[ev.discordUserId] = ev.discordChannelId
  (true, ev)

proc discordChannelFor*(a: DiscordAdapter; userId: UserId): string =
  ## Returns the Discord channel snowflake last associated with this UserId.
  ## Looks up via the resolver's Discord user ID, then into chanMap.
  ## Returns "" if unknown.
  for discordUid, chanId in a.chanMap:
    let resolved = a.resolver.resolve(ckDiscord, discordUid)
    if resolved == userId:
      return chanId
  ""

# ── ChannelPort — send / edit ────────────────────────────────────────────────────

proc sendToChannel*(a: DiscordAdapter;
                    discordChannelId, text: string): Result[string, string] =
  ## POSTs a message to a Discord channel. Returns the message snowflake ID.
  let url  = DiscordApiBase & "/channels/" & discordChannelId & "/messages"
  let body = $ %*{"content": text}
  let resp = ? restPost(a.token, url, body)
  ok(resp["id"].getStr(""))

proc send*(a: DiscordAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the Discord channel last seen for this user.
  let chanId = a.discordChannelFor(msg.userId)
  if chanId.len == 0:
    return err("discord: no known channel for user " & $msg.userId)
  let _ = ? a.sendToChannel(chanId, msg.text)
  ok()

proc sendReturnId*(a: DiscordAdapter;
                   msg: OutboundMessage): Result[string, string] =
  ## Sends a message and returns its Discord snowflake ID.
  let chanId = a.discordChannelFor(msg.userId)
  if chanId.len == 0:
    return err("discord: no known channel for user " & $msg.userId)
  a.sendToChannel(chanId, msg.text)

proc editMessage*(a: DiscordAdapter; userId: UserId;
                  messageId, text: string): Result[void, string] =
  ## Edits an existing Discord message in place (for streaming updates).
  let chanId = a.discordChannelFor(userId)
  if chanId.len == 0:
    return err("discord: no known channel for user " & $userId)
  let url  = DiscordApiBase & "/channels/" & chanId & "/messages/" & messageId
  let body = $ %*{"content": text}
  let _ = ? restPatch(a.token, url, body)
  ok()

proc sendInteractionResponse*(a: DiscordAdapter;
                               interactionId, interactionToken,
                               text: string): Result[void, string] =
  ## Responds to a slash command interaction (type 4 = CHANNEL_MESSAGE_WITH_SOURCE).
  let url  = DiscordApiBase & "/interactions/" & interactionId &
             "/" & interactionToken & "/callback"
  let body = $ %*{
    "type": 4,
    "data": {"content": text}
  }
  let _ = ? restPost(a.token, url, body)
  ok()

# ── Application registration ─────────────────────────────────────────────────────

proc getAppId*(a: var DiscordAdapter): Result[string, string] =
  ## Fetches the bot application ID via GET /users/@me.
  let resp = ? restGet(a.token, DiscordApiBase & "/users/@me")
  ok(resp["id"].getStr(""))

proc registerSlashCommands*(a: var DiscordAdapter;
                             appId: string): Result[void, string] =
  ## Registers the /continue slash command globally.
  let url  = DiscordApiBase & "/applications/" & appId & "/commands"
  let body = $ %*[
    {
      "name":        "continue",
      "type":        1,
      "description": "Resume your session from another channel",
      "options":     [{
        "name":        "code",
        "description": "6-digit pairing code",
        "type":        3,    ## STRING
        "required":    false
      }]
    }
  ]
  let _ = ? restPut(a.token, url, body)
  ok()
