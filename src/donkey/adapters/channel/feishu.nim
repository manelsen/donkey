## FeishuAdapter — ChannelPort for Feishu/Lark webhook (HTTP callback).
##
## Receiving: Feishu POSTs events to your webhook endpoint.
##   The HTTP layer calls pushEvent() with the parsed JSON payload.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## URL verification: Feishu sends {"type":"url_verification","challenge":"xxx"}.
##   Call parseChallenge(payload) — non-empty result means echo it back verbatim.
##
## Sending: Feishu Open API POST /open-apis/im/v1/messages with Bearer token.
##   Requires a valid tenant_access_token (passed in as accessToken).
##
## Topology (pipeops):
##   |>    — payload |> parseEvent
##   >>=   — http.post(...) >>= parseFsBody >>= extractMsgId

import std/[json, strutils]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/feishu_pure
import ../../ports/http
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver

const
  FsApiBase*    = "https://open.feishu.cn"
  FsMaxChars*   = 4000  ## practical per-message limit for Feishu text messages

# ── Public event type ─────────────────────────────────────────────────────────

type
  FeishuEvent* = object
    msgType*:  string  ## "text", "image", "audio", "file", "sticker", "interactive"
    openId*:   string  ## sender open_id
    msgId*:    string  ## Feishu message_id (om_xxx) — for dedup / ack
    chatId*:   string  ## chat_id the message was sent to
    chatType*: string  ## "p2p" or "group"
    content*:  string  ## message text (msgType="text") or "" otherwise

# ── Module-level event queue ──────────────────────────────────────────────────

## Thread-safe: chronos Channel uses internal synchronization.
## Opened once at daemon startup via openQueue().
var gFsEvents* {.global.}: Channel[FeishuEvent]

# ── Inbound helpers (called by HTTP layer) ────────────────────────────────────

proc parseChallenge*(payload: JsonNode): string =
  ## Returns the challenge string if this is a url_verification payload.
  ## Empty string otherwise. HTTP layer must respond with {"challenge":"..."}.
  let r = payload |> parseEvent
  if r |> isVerification: r.challenge else: ""

proc pushEvent*(payload: JsonNode) =
  ## Parses an incoming Feishu webhook payload and enqueues actionable events.
  ## Ignores unknown, verification, and non-message event types.
  let r = payload |> parseEvent
  case r.kind
  of fmkUnknown, fmkEvent, fmkInteractive: discard
  of fmkText:
    gFsEvents.send(FeishuEvent(
      msgType:  "text",
      openId:   r.rawId,
      msgId:    r.messageId,
      chatId:   r.chatId,
      chatType: r.chatType,
      content:  r.text,
    ))
  of fmkImage:
    gFsEvents.send(FeishuEvent(
      msgType:  "image",
      openId:   r.rawId,
      msgId:    r.messageId,
      chatId:   r.chatId,
      chatType: r.chatType,
    ))
  of fmkAudio:
    gFsEvents.send(FeishuEvent(
      msgType:  "audio",
      openId:   r.rawId,
      msgId:    r.messageId,
      chatId:   r.chatId,
      chatType: r.chatType,
    ))
  of fmkFile:
    gFsEvents.send(FeishuEvent(
      msgType:  "file",
      openId:   r.rawId,
      msgId:    r.messageId,
      chatId:   r.chatId,
      chatType: r.chatType,
    ))
  of fmkSticker:
    gFsEvents.send(FeishuEvent(
      msgType:  "sticker",
      openId:   r.rawId,
      msgId:    r.messageId,
      chatId:   r.chatId,
      chatType: r.chatType,
    ))

# ── FeishuAdapter ─────────────────────────────────────────────────────────────

type
  FeishuAdapter* = object
    appId*:       string
    appSecret*:   string
    accessToken*: string   ## tenant_access_token for Feishu Open API
    apiBase*:     string   ## override for testing
    resolver*:    IdentityResolver
    http*:        StdHttpAdapter

func authHeader(a: FeishuAdapter): (string, string) =
  ("Authorization", "Bearer " & a.accessToken)

func base(a: FeishuAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: FsApiBase

# ── REST response helpers ─────────────────────────────────────────────────────

proc parseFsBody(resp: HttpResponse): Result[JsonNode, string]
                {.gcsafe, raises: [].} =
  ## Validates HTTP status and Feishu "code" field. Designed for >>= chaining.
  if resp.status < 200 or resp.status >= 300:
    return err("Feishu HTTP " & $resp.status & ": " & resp.body)
  try:
    let j = parseJson(resp.body)
    let code = j.getOrDefault("code").getInt(-1)
    if code != 0:
      let msg = j.getOrDefault("msg").getStr("unknown")
      return err("Feishu API error code=" & $code & ": " & msg)
    ok(j)
  except CatchableError as e:
    err(e.msg)

proc postJson(a: FeishuAdapter; path: string;
              body: JsonNode): Result[JsonNode, string] =
  ## POSTs JSON to a Feishu Open API endpoint; validates "code" field.
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  a.http.post(a.base() & path, $body, headers) >>= parseFsBody

# ── ChannelPort procs ─────────────────────────────────────────────────────────

proc sendChunk(a: FeishuAdapter; openId, text: string): Result[void, string] =
  ## Sends a single text chunk to a Feishu user by open_id.
  let content = "{\"text\":\"" & text.replace("\\", "\\\\").replace("\"", "\\\"") & "\"}"
  discard ? a.postJson("/open-apis/im/v1/messages?receive_id_type=open_id", %* {
    "receive_id": openId,
    "msg_type":   "text",
    "content":    content,
  })
  ok()

proc send*(a: FeishuAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user's Feishu open_id.
  ## Splits messages longer than FsMaxChars into multiple sends.
  let fsId = a.resolver.reverseChannel(msg.userId, ckFeishu)
  if fsId.len == 0:
    return err("FeishuAdapter.send: no Feishu ID for user " & $msg.userId)
  for chunk in splitChunks(msg.text, FsMaxChars):
    ? a.sendChunk(fsId, chunk)
  ok()

proc extractMsgId(j: JsonNode): Result[string, string]
                 {.gcsafe, raises: [].} =
  ## Extracts the message_id from a Feishu send response. Designed for >>= chaining.
  try:
    let msgId = j.getOrDefault("data").getOrDefault("message_id").getStr("")
    if msgId.len == 0:
      return err("Feishu send response: missing data.message_id")
    ok(msgId)
  except CatchableError as e:
    err(e.msg)

proc sendReturnId*(a: FeishuAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends a single chunk and returns the Feishu message_id (om_xxx).
  ## Used by the streaming machinery for subsequent edit calls.
  let fsId = a.resolver.reverseChannel(msg.userId, ckFeishu)
  if fsId.len == 0:
    return err("FeishuAdapter.sendReturnId: no Feishu ID for " & $msg.userId)
  let chunk = splitChunks(msg.text, FsMaxChars)[0]
  let content = "{\"text\":\"" & chunk.replace("\\", "\\\\").replace("\"", "\\\"") & "\"}"
  a.postJson("/open-apis/im/v1/messages?receive_id_type=open_id", %* {
    "receive_id": fsId,
    "msg_type":   "text",
    "content":    content,
  }) >>= extractMsgId

proc editMessage*(a: FeishuAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Updates an existing Feishu message via PATCH /im/v1/messages/{message_id}.
  let txt = if text.len > FsMaxChars: text[0 ..< FsMaxChars] else: text
  let content = "{\"text\":\"" & txt.replace("\\", "\\\\").replace("\"", "\\\"") & "\"}"
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  let body    = %* {"content": content}
  let resp    = a.http.patch(a.base() & "/open-apis/im/v1/messages/" & msgId,
                             $body, headers)
  discard ? (resp >>= parseFsBody)
  ok()

proc ack*(a: FeishuAdapter; msgId: string) =
  ## No-op — Feishu webhook does not require explicit ack (HTTP 200 suffices).
  discard

# ── Queue management ──────────────────────────────────────────────────────────

proc openQueue*(a: FeishuAdapter) =
  ## Opens the module-level event queue. Call once at daemon startup.
  {.cast(gcsafe).}:
    gFsEvents.open()

proc startGateway*(a: var FeishuAdapter) =
  ## Opens the webhook event queue. For HTTP callback mode this is equivalent
  ## to openQueue(). Named startGateway to match the ChannelPort convention used
  ## by WebSocket-based adapters (Discord, QQ).
  a.openQueue()

proc tryRecvEvent*(a: FeishuAdapter): (bool, FeishuEvent) =
  ## Non-blocking poll for webhook events. Returns (false, default) when empty.
  gFsEvents.tryRecv()

# ── Constructor ───────────────────────────────────────────────────────────────

proc newFeishuAdapter*(appId, appSecret: string;
                       identityPath:  string;
                       accessToken    = "";
                       apiBase        = ""): FeishuAdapter =
  FeishuAdapter(
    appId:       appId,
    appSecret:   appSecret,
    accessToken: accessToken,
    apiBase:     apiBase,
    resolver:    newIdentityResolver(identityPath),
    http:        newStdHttpAdapter(),
  )
