## MatrixAdapter — ChannelPort for Matrix Synapse (Client-Server API).
##
## Receiving: the Application Service (AS) or HTTP layer POSTs events to your
##   callback endpoint. The HTTP layer calls pushEvent() with the parsed JSON.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## Sending: Matrix Client-Server API PUT event endpoint.
##   PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message/{txnId}
##   Body:    {"msgtype":"m.text","body":"..."}
##   Headers: Authorization: Bearer <access_token>
##   Returns: {"event_id":"$..."}
##
## Routing convention:
##   rawId = room_id for all events (identity key is the room, not the user MXID)
##   This lets reverseChannel(userId, ckMatrix) → room_id for outbound sends.
##
## Token: long-lived access token issued to the bot account.
##   No refresh needed — Matrix access tokens do not expire by default.
##
## Topology (pipeops):
##   |>    — payload |> parseEvent
##   >>=   — http.put(...) >>= parseMxBody >>= extractEventId

import std/[json, locks, strutils]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/matrix_pure
import ../../ports/http
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver

const
  MxDefaultApiBase* = ""  ## Must be provided; no sensible global default.
  MxApiPath         = "/_matrix/client/v3"
  MxMaxChars*       = 40000  ## Conservative per-message character limit.

# ── Public event type ─────────────────────────────────────────────────────────

type
  MatrixEvent* = object
    msgType*:  string  ## "text" | "image" | "audio" | "video" | "file"
    roomId*:   string  ## room_id (routing key, used as rawId)
    senderId*: string  ## @user:server (sender MXID)
    eventId*:  string  ## $event:server (unique event id)
    content*:  string  ## message text (msgType="text"); "" otherwise
    mediaUrl*: string  ## mxc:// URL (media types); "" otherwise

# ── Module-level event queue ──────────────────────────────────────────────────

## Thread-safe: chronos Channel uses internal synchronization.
var gMxEvents* {.global.}: Channel[MatrixEvent]

# ── Transaction ID counter ────────────────────────────────────────────────────

## Monotonic counter used to generate unique transaction IDs for Matrix send
## events. Protected by gMxTxnLock — incremented from async context in
## nextTxnId() which is called by sendChunk, sendReturnId, and editMessage.
var gMxTxnSeq {.global.}: int
var gMxTxnLock {.global.}: Lock

proc nextTxnId(): string =
  acquire(gMxTxnLock)
  inc gMxTxnSeq
  let seq = gMxTxnSeq
  release(gMxTxnLock)
  $nowMs() & $seq

# ── Inbound helpers (called by HTTP layer) ────────────────────────────────────

proc pushEvent*(payload: JsonNode) =
  ## Parses an incoming Matrix event payload and enqueues actionable events.
  ## Ignores mxkUnknown events (non-message types or unsupported msgtypes).
  let r = payload |> parseEvent
  case r.kind
  of mxkUnknown: discard
  of mxkText:
    {.cast(gcsafe).}:
      gMxEvents.send(MatrixEvent(
        msgType:  "text",
        roomId:   r.roomId,
        senderId: r.senderId,
        eventId:  r.eventId,
        content:  r.text,
      ))
  of mxkImage:
    {.cast(gcsafe).}:
      gMxEvents.send(MatrixEvent(
        msgType:  "image",
        roomId:   r.roomId,
        senderId: r.senderId,
        eventId:  r.eventId,
        mediaUrl: r.mediaUrl,
      ))
  of mxkAudio:
    {.cast(gcsafe).}:
      gMxEvents.send(MatrixEvent(
        msgType:  "audio",
        roomId:   r.roomId,
        senderId: r.senderId,
        eventId:  r.eventId,
        mediaUrl: r.mediaUrl,
      ))
  of mxkVideo:
    {.cast(gcsafe).}:
      gMxEvents.send(MatrixEvent(
        msgType:  "video",
        roomId:   r.roomId,
        senderId: r.senderId,
        eventId:  r.eventId,
        mediaUrl: r.mediaUrl,
      ))
  of mxkFile:
    {.cast(gcsafe).}:
      gMxEvents.send(MatrixEvent(
        msgType:  "file",
        roomId:   r.roomId,
        senderId: r.senderId,
        eventId:  r.eventId,
        mediaUrl: r.mediaUrl,
      ))

# ── MatrixAdapter ─────────────────────────────────────────────────────────────

type
  MatrixAdapter* = object
    homeserver*:   string  ## e.g. "https://matrix.example.com"
    botUserId*:    string  ## bot MXID, e.g. "@bot:example.com"
    accessToken*:  string  ## long-lived access token for the bot account
    apiBase*:      string  ## override for testing (replaces homeserver)
    resolver*:     IdentityResolver
    http*:         StdHttpAdapter

func resolvedBase(a: MatrixAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: a.homeserver

func authHeader(a: MatrixAdapter): (string, string) =
  ("Authorization", "Bearer " & a.accessToken)

# ── REST response helpers ─────────────────────────────────────────────────────

proc parseMxBody(resp: HttpResponse): Result[JsonNode, string]
               {.gcsafe, raises: [].} =
  ## Validates HTTP status and parses JSON body. Designed for >>= chaining.
  if resp.status < 200 or resp.status >= 300:
    return err("Matrix HTTP " & $resp.status & ": " & resp.body)
  try:
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc extractEventId(j: JsonNode): Result[string, string]
                   {.gcsafe, raises: [].} =
  ## Extracts event_id from a Matrix send response. Designed for >>= chaining.
  try:
    let evId = j.getOrDefault("event_id").getStr("")
    if evId.len == 0:
      return err("Matrix send response: missing event_id")
    ok(evId)
  except CatchableError as e:
    err(e.msg)

# ── Send helpers ──────────────────────────────────────────────────────────────

func buildSendUrl(base, roomId, txnId: string): string =
  ## Builds the Matrix send event URL for a given room and transaction ID.
  base.strip(chars = {'/'}) & MxApiPath &
    "/rooms/" & roomId & "/send/m.room.message/" & txnId

func buildSendBody(text: string): string =
  ## Builds the JSON body for a Matrix m.text message send.
  let safe = text.replace("\\", "\\\\").replace("\"", "\\\"")
  "{\"msgtype\":\"m.text\",\"body\":\"" & safe & "\"}"

proc sendChunk(a: MatrixAdapter; roomId, text: string): Result[void, string] =
  ## Sends a single text chunk to the given room.
  let url  = buildSendUrl(a.resolvedBase(), roomId, nextTxnId())
  let hdrs = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.put(url, buildSendBody(text), hdrs)
  if resp.status < 200 or resp.status >= 300:
    return err("Matrix send error " & $resp.status & ": " & resp.body)
  ok()

proc sendToRoom*(a: MatrixAdapter; roomId: string;
                 msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the given room, splitting if over MxMaxChars.
  if roomId.len == 0:
    return err("MatrixAdapter.sendToRoom: empty roomId")
  for chunk in splitChunks(msg.text, MxMaxChars):
    ? a.sendChunk(roomId, chunk)
  ok()

proc send*(a: MatrixAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the room resolved from the identity store.
  let roomId = a.resolver.reverseChannel(msg.userId, ckMatrix)
  if roomId.len == 0:
    return err("MatrixAdapter.send: no Matrix room for user " & $msg.userId)
  a.sendToRoom(roomId, msg)

proc sendReturnId*(a: MatrixAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends a single chunk and returns the Matrix event_id ($...).
  let roomId = a.resolver.reverseChannel(msg.userId, ckMatrix)
  if roomId.len == 0:
    return err("MatrixAdapter.sendReturnId: no Matrix room for user " & $msg.userId)
  let chunk = splitChunks(msg.text, MxMaxChars)[0]
  let url   = buildSendUrl(a.resolvedBase(), roomId, nextTxnId())
  let hdrs  = @[a.authHeader(), ("Content-Type", "application/json")]
  a.http.put(url, buildSendBody(chunk), hdrs) >>= parseMxBody >>= extractEventId

proc editMessage*(a: MatrixAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Sends a Matrix replacement event (m.replace) for the given event_id.
  ## msgId must be the original event_id ($...).
  let roomId = a.resolver.reverseChannel(userId, ckMatrix)
  if roomId.len == 0:
    return err("MatrixAdapter.editMessage: no Matrix room for user " & $userId)
  let safe = text.replace("\\", "\\\\").replace("\"", "\\\"")
  let body = "{\"msgtype\":\"m.text\",\"body\":\"* " & safe &
    "\",\"m.new_content\":{\"msgtype\":\"m.text\",\"body\":\"" & safe &
    "\"},\"m.relates_to\":{\"rel_type\":\"m.replace\",\"event_id\":\"" &
    msgId & "\"}}"
  let url  = buildSendUrl(a.resolvedBase(), roomId, nextTxnId())
  let hdrs = @[a.authHeader(), ("Content-Type", "application/json")]
  let resp = ? a.http.put(url, body, hdrs)
  if resp.status < 200 or resp.status >= 300:
    return err("Matrix edit error " & $resp.status & ": " & resp.body)
  ok()

proc ack*(a: MatrixAdapter; msgId: string) =
  ## No-op — Matrix Application Service does not require explicit ack.
  discard

# ── Queue management ──────────────────────────────────────────────────────────

proc openQueue*(a: MatrixAdapter) =
  ## Opens the module-level event queue. Call once at daemon startup.
  initLock(gMxTxnLock)
  {.cast(gcsafe).}:
    gMxEvents.open()

proc startGateway*(a: var MatrixAdapter) =
  ## Opens the event queue. Named startGateway to match the ChannelPort
  ## convention used by WebSocket-based adapters.
  a.openQueue()

proc tryRecvEvent*(a: MatrixAdapter): (bool, MatrixEvent) =
  ## Non-blocking poll for queued events. Returns (false, default) when empty.
  {.cast(gcsafe).}:
    gMxEvents.tryRecv()

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMatrixAdapter*(homeserver, botUserId, accessToken: string;
                       identityPath: string;
                       apiBase = ""): MatrixAdapter =
  MatrixAdapter(
    homeserver:  homeserver,
    botUserId:   botUserId,
    accessToken: accessToken,
    apiBase:     apiBase,
    resolver:    newIdentityResolver(identityPath),
    http:        newStdHttpAdapter(),
  )
