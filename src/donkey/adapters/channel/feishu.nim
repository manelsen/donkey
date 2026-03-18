## FeishuAdapter — ChannelPort for Feishu (飞书) / Lark (international).
##
## Receiving: WebSocket persistent connection — no public HTTPS endpoint needed.
##   Protocol: pbbp2 (proprietary protobuf binary framing over WebSocket).
##   The WebSocket URL is obtained via REST, then connected from inside-out.
##
## Sending: REST API — POST /im/v1/messages with tenant_access_token.
##
## REST endpoints:
##   Token:  POST {base}/open-apis/auth/v3/app_access_token/internal
##   WS URL: POST {base}/callback/ws/endpoint
##
## Frame proto schema (pbbp2):
##   message Header  { string key = 1; string value = 2; }
##   message Frame   { uint64 SeqID=1; uint64 LogID=2; uint32 service=3;
##                     uint32 method=4; repeated Header headers=5;
##                     string payloadEncoding=6; string payloadType=7;
##                     bytes payload=8; string LogIDNew=9; }
##
## method values: 0=control (ping/pong/handshake), 1=data (event/card)
## header "type" values: "ping", "pong", "event", "card"

import std/[json, net, options, os, strutils, times]
import nimcrypto/sha2
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../http/std_http
import ../identity/identity_resolver
import ./ws_client

const
  LarkApiBase*   = "https://open.larksuite.com"
  FeishuApiBase* = "https://open.feishu.cn"
  FeishuHeartbeatMs = 120_000

# ── Public event type ─────────────────────────────────────────────────────────

type
  FeishuRawEvent* = object
    eventType*: string
    openId*:    string
    msgType*:   string
    content*:   string
    msgId*:     string
    chatId*:    string
    challenge*: string

var gFeishuEvents* {.global.}: Channel[FeishuRawEvent]

# ── Pure functions — signature & event parsing ─────────────────────────────────

func feishuSignature*(timestamp, nonce, appSecret, body: string): string =
  let plain = timestamp & nonce & appSecret & body
  toLowerAscii($sha256.digest(plain))

func verifyFeishuSig*(timestamp, nonce, appSecret, body, sig: string): bool =
  feishuSignature(timestamp, nonce, appSecret, body) == sig

proc parseFeishuEvent*(body: string): Option[FeishuRawEvent] =
  var j: JsonNode
  try: j = parseJson(body)
  except: return none(FeishuRawEvent)

  if j.getOrDefault("type").getStr("") == "url_verification":
    return some(FeishuRawEvent(
      eventType: "url_verification",
      challenge: j.getOrDefault("challenge").getStr(""),
    ))

  let header = j.getOrDefault("header")
  if header == nil: return none(FeishuRawEvent)
  let headerType = header.getOrDefault("event_type").getStr("")
  if headerType.len == 0: return none(FeishuRawEvent)

  let event  = j.getOrDefault("event")
  if event == nil:
    return some(FeishuRawEvent(eventType: headerType))

  let sender = event.getOrDefault("sender")
  let openId = if sender != nil:
                 sender.getOrDefault("sender_id").getOrDefault("open_id").getStr("")
               else: ""

  let msgNode = event.getOrDefault("message")
  if msgNode == nil:
    return some(FeishuRawEvent(eventType: headerType, openId: openId))

  let msgType = msgNode.getOrDefault("message_type").getStr("")
  let msgId   = msgNode.getOrDefault("message_id").getStr("")
  let chatId  = msgNode.getOrDefault("chat_id").getStr("")

  var content = ""
  if msgType == "text":
    let raw = msgNode.getOrDefault("content").getStr("")
    try: content = parseJson(raw).getOrDefault("text").getStr("")
    except: discard

  some(FeishuRawEvent(
    eventType: headerType,
    openId:    openId,
    msgType:   msgType,
    content:   content,
    msgId:     msgId,
    chatId:    chatId,
  ))

func buildSendBody*(receiveId, receiveIdType, text: string): JsonNode =
  let contentJson = $(%* {"text": text})
  %* {"receive_id": receiveId, "msg_type": "text", "content": contentJson}

func challengeResponse*(challenge: string): JsonNode =
  %* {"challenge": challenge}

# ── Minimal protobuf encoder ───────────────────────────────────────────────────
## Implements only what is needed for pbbp2 Frame encoding.

func pbVarint(n: uint64): string =
  ## Encodes n as a protobuf varint (LEB128).
  var n = n
  while true:
    let b = uint8(n and 0x7F)
    n = n shr 7
    if n == 0:
      result.add(char(b))
      break
    else:
      result.add(char(b or 0x80))

func pbTag(fieldNum: int; wireType: int): string =
  pbVarint(uint64((fieldNum shl 3) or wireType))

func pbLen(fieldNum: int; data: string): string =
  ## Encodes a length-delimited field (wire type 2).
  result.add(pbTag(fieldNum, 2))
  result.add(pbVarint(uint64(data.len)))
  result.add(data)

func pbUint(fieldNum: int; value: uint64): string =
  ## Encodes a varint field (wire type 0).
  result.add(pbTag(fieldNum, 0))
  result.add(pbVarint(value))

func encodeHeader(key, value: string): string =
  result.add(pbLen(1, key))    ## field 1: key
  result.add(pbLen(2, value))  ## field 2: value

func encodePingFrame*(seqId: uint64): string =
  ## Encodes a control/ping Frame to send as a WebSocket binary frame.
  let hdr = encodeHeader("type", "ping")
  result.add(pbUint(1, seqId))  ## SeqID
  result.add(pbUint(4, 0))      ## method=0 (control)
  result.add(pbLen(5, hdr))     ## headers[0]

# ── Minimal protobuf decoder ───────────────────────────────────────────────────

type
  PbHeader* = object
    key*:   string
    value*: string

  PbFrame* = object
    seqId*:   uint64
    mthod*:   uint32   ## "method" is a Nim keyword; field 4 in pbbp2 Frame
    headers*: seq[PbHeader]
    payload*: string

proc pbDecodeVarint(data: string; pos: var int): uint64 =
  var shift = 0
  while pos < data.len:
    let b = uint8(data[pos])
    inc pos
    result = result or (uint64(b and 0x7F) shl shift)
    if (b and 0x80) == 0: break
    shift += 7

proc pbDecodeHeader(data: string): PbHeader =
  var pos = 0
  while pos < data.len:
    let tag    = pbDecodeVarint(data, pos)
    let field  = int(tag shr 3)
    let wire   = int(tag and 0x7)
    if wire != 2: break           ## only length-delimited fields expected
    let length = int(pbDecodeVarint(data, pos))
    if pos + length > data.len: break
    let v = data[pos ..< pos + length]
    pos += length
    case field
    of 1: result.key   = v
    of 2: result.value = v
    else: discard

proc pbDecodeFrame*(data: string): PbFrame =
  ## Decodes a pbbp2 Frame from raw bytes. Ignores unknown fields safely.
  var pos = 0
  while pos < data.len:
    let tag   = pbDecodeVarint(data, pos)
    let field = int(tag shr 3)
    let wire  = int(tag and 0x7)
    case wire
    of 0:  ## varint
      let v = pbDecodeVarint(data, pos)
      case field
      of 1: result.seqId  = v
      of 4: result.mthod = uint32(v)
      else: discard
    of 2:  ## length-delimited
      let length = int(pbDecodeVarint(data, pos))
      if pos + length > data.len: break
      let bytes = data[pos ..< pos + length]
      pos += length
      case field
      of 5: result.headers.add(pbDecodeHeader(bytes))
      of 8: result.payload = bytes
      else: discard
    of 1:  ## 64-bit (skip 8 bytes)
      pos += 8
    of 5:  ## 32-bit (skip 4 bytes)
      pos += 4
    else: break

func frameHeader(f: PbFrame; key: string): string =
  for h in f.headers:
    if h.key == key: return h.value
  ""

# ── FeishuAdapter ──────────────────────────────────────────────────────────────

type
  FeishuAdapter* = object
    appId*:        string
    appSecret*:    string
    apiBase*:      string
    resolver*:     IdentityResolver
    http*:         StdHttpAdapter
    appToken:      string
    appExpiry:     int64
    tenantToken:   string
    tenantExpiry:  int64

func openApiBase(a: FeishuAdapter): string =
  let b = if a.apiBase.len > 0: a.apiBase else: LarkApiBase
  b & "/open-apis"

func callbackBase(a: FeishuAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: LarkApiBase

# ── Access tokens ──────────────────────────────────────────────────────────────

proc getAppToken*(a: var FeishuAdapter): Result[string, string] =
  let now = getTime().toUnix()
  if a.appToken.len > 0 and now < a.appExpiry - 60:
    return ok(a.appToken)
  let body = %* {"app_id": a.appId, "app_secret": a.appSecret}
  let resp = ? a.http.post(a.openApiBase() & "/auth/v3/app_access_token/internal",
                           $body, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("Feishu app token error " & $resp.status)
  try:
    let j = parseJson(resp.body)
    if j.getOrDefault("code").getInt(-1) != 0:
      return err("Feishu app token API: " & $j)
    a.appToken = j["app_access_token"].getStr()
    a.appExpiry = now + j["expire"].getInt(7200)
    ok(a.appToken)
  except CatchableError as e: err(e.msg)

proc getAccessToken*(a: var FeishuAdapter): Result[string, string] =
  let now = getTime().toUnix()
  if a.tenantToken.len > 0 and now < a.tenantExpiry - 60:
    return ok(a.tenantToken)
  let body = %* {"app_id": a.appId, "app_secret": a.appSecret}
  let resp = ? a.http.post(a.openApiBase() & "/auth/v3/tenant_access_token/internal",
                           $body, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("Feishu tenant token error " & $resp.status)
  try:
    let j = parseJson(resp.body)
    if j.getOrDefault("code").getInt(-1) != 0:
      return err("Feishu tenant token API: " & $j)
    a.tenantToken = j["tenant_access_token"].getStr()
    a.tenantExpiry = now + j["expire"].getInt(7200)
    ok(a.tenantToken)
  except CatchableError as e: err(e.msg)

# ── Sending ────────────────────────────────────────────────────────────────────

proc send*(a: var FeishuAdapter; msg: OutboundMessage): Result[void, string] =
  let feishuId = a.resolver.reverseChannel(msg.userId, ckFeishu)
  if feishuId.len == 0:
    return err("FeishuAdapter.send: no Feishu ID for user " & $msg.userId)
  let tok  = ? a.getAccessToken()
  let url  = a.openApiBase() & "/im/v1/messages?receive_id_type=open_id"
  let body = buildSendBody(feishuId, "open_id", msg.text)
  let hdrs = @[("Content-Type",  "application/json"),
               ("Authorization", "Bearer " & tok)]
  let resp = ? a.http.post(url, $body, hdrs)
  if resp.status < 200 or resp.status >= 300:
    return err("Feishu send error " & $resp.status & ": " & resp.body)
  try:
    let j = parseJson(resp.body)
    if j.getOrDefault("code").getInt(-1) != 0:
      return err("Feishu send API error: " & j.getOrDefault("msg").getStr(""))
    ok()
  except CatchableError as e: err(e.msg)

# ── WebSocket gateway thread ───────────────────────────────────────────────────

type GatewayArgs = object
  appId:     string
  appSecret: string
  apiBase:   string

func parseWsUrl(url: string): tuple[host, path: string] =
  let noScheme = if url.startsWith("wss://"): url[6..^1]
                 elif url.startsWith("ws://"): url[5..^1]
                 else: url
  let si = noScheme.find('/')
  if si < 0: (noScheme, "/")
  else: (noScheme[0..<si], noScheme[si..^1])

type WsEndpointResult = object
  url:          string
  pingInterval: int   ## milliseconds

proc acquireWsEndpoint(arg: GatewayArgs): WsEndpointResult =
  ## POST /callback/ws/endpoint with AppID+AppSecret directly (no token needed).
  ## SDK sends credentials directly + locale header. No Authorization header.
  let http = newStdHttpAdapter()
  let body = $(%* {"AppID": arg.appId, "AppSecret": arg.appSecret})
  let hdrs = @[("Content-Type", "application/json"), ("locale", "zh")]
  let resp = http.post(arg.apiBase & "/callback/ws/endpoint", body, hdrs)
  if resp.isErr: raise newException(IOError, "ws endpoint HTTP: " & resp.error)
  echo "[feishu] ws_endpoint status=" & $resp.value.status &
       " body=" & resp.value.body
  let j = parseJson(resp.value.body)
  let code = j.getOrDefault("code").getInt(-1)
  if code != 0:
    raise newException(IOError, "ws endpoint API code=" & $code & ": " & $j)
  let data = j["data"]
  let pingMs = data.getOrDefault("ClientConfig")
                   .getOrDefault("PingInterval").getInt(120) * 1000
  WsEndpointResult(url: data["URL"].getStr(), pingInterval: pingMs)

proc handleEventFrame(frame: PbFrame) =
  let frameType = frameHeader(frame, "type")
  case frameType
  of "event":
    let evtOpt = parseFeishuEvent(frame.payload)
    if evtOpt.isSome:
      gFeishuEvents.send(evtOpt.get)
    else:
      echo "[feishu] unparsed event payload: " &
           frame.payload[0..min(200, frame.payload.high)]
  of "pong":
    discard  ## heartbeat ack
  of "":
    ## Unknown — log raw for protocol diagnosis
    echo "[feishu] frame method=" & $frame.mthod &
         " headers=" & $frame.headers.len &
         " payload=" & $frame.payload.len & "B"
  else:
    echo "[feishu] unhandled frame type=" & frameType

proc runGatewaySession(arg: GatewayArgs) =
  let ep           = acquireWsEndpoint(arg)
  let (host, path) = parseWsUrl(ep.url)
  echo "[feishu] connecting to " & host & path
  let ws           = wsConnect(host, Port(443), path, useTls = true)
  echo "[feishu] WebSocket connected"

  var seqId: uint64 = 0
  var lastBeatMs = nowMs()
  let pingIntervalMs = if ep.pingInterval > 0: ep.pingInterval
                       else: FeishuHeartbeatMs

  while true:
    if nowMs() - lastBeatMs >= pingIntervalMs:
      inc seqId
      ws.sendFrame(encodePingFrame(seqId), WsOpcodeBin)
      lastBeatMs = nowMs()

    try:
      let frame = ws.recvFrame(timeoutMs = 1000)
      case frame.opcode
      of WsOpcodeText:
        echo "[feishu] text frame (unexpected): " & frame.data[0..min(200, frame.data.high)]
      of WsOpcodeBin:
        let f = pbDecodeFrame(frame.data)
        handleEventFrame(f)
      of WsOpcodePing:
        ws.sendFrame(frame.data, WsOpcodePong)
      of WsOpcodeClose:
        raise newException(IOError, "gateway closed (WS close frame)")
      else: discard
    except TimeoutError:
      discard

proc feishuGatewayThread(arg: GatewayArgs) {.thread.} =
  var backoffMs = 1_000
  while true:
    try:
      runGatewaySession(arg)
      backoffMs = 1_000
    except Exception as e:
      echo "[feishu] gateway error: " & e.msg & " — reconnecting in " &
           $backoffMs & " ms"
      sleep(backoffMs)
      backoffMs = min(backoffMs * 2, 60_000)

var gGatewayThread {.global.}: Thread[GatewayArgs]

# ── Lifecycle ──────────────────────────────────────────────────────────────────

proc startGateway*(a: FeishuAdapter) {.gcsafe.} =
  {.cast(gcsafe).}:
    gFeishuEvents.open()
    createThread(gGatewayThread, feishuGatewayThread,
                 GatewayArgs(appId: a.appId, appSecret: a.appSecret,
                             apiBase: a.callbackBase()))

proc tryRecvEvent*(a: FeishuAdapter): (bool, FeishuRawEvent) =
  gFeishuEvents.tryRecv()

# ── Constructor ────────────────────────────────────────────────────────────────

proc newFeishuAdapter*(appId, appSecret: string;
                       identityPath: string;
                       apiBase       = ""): FeishuAdapter =
  FeishuAdapter(
    appId:      appId,
    appSecret:  appSecret,
    apiBase:    apiBase,
    resolver:   newIdentityResolver(identityPath),
    http:       newStdHttpAdapter(),
  )
