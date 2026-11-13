## QQOfficialAdapter — official QQ Bot API adapter.
##
## Receiving:
##   Expects webhook/WebSocket payloads from the official QQ Bot API to be
##   forwarded into enqueueEventJson(). The daemon drains tryRecvEvent().
##
## Sending:
##   Uses QQ Bot OpenAPI with app credentials:
##     POST https://bots.qq.com/app/getAppAccessToken
##     Authorization: QQBot <access_token>
##     POST https://api.sgroup.qq.com/v2/users/{openid}/messages
##     POST https://api.sgroup.qq.com/v2/groups/{group_openid}/messages

import std/[json, net, os, strutils, tables, times]
import ../../core/pipeops
import ../../domain/message
import ../../ports/http
import ../http/std_http
import ./ws_client

const
  QQOfficialDefaultApiBase* = "https://api.sgroup.qq.com"
  QQOfficialDefaultTokenBase* = "https://bots.qq.com"
  QQOfficialTokenSkewSec = 60'i64
  QQOfficialDefaultIntents* = (1 shl 25) or (1 shl 26)

type
  QQOfficialEvent* = object
    messageType*: string
    userId*:      string
    groupId*:     string
    messageId*:   string
    content*:     string

  QQOfficialToken* = object
    accessToken*: string
    expiresInSec*: int64

  QQOfficialAdapter* = object
    appId*:         string
    clientSecret*:  string
    apiBase*:       string
    tokenBase*:     string
    http*:          HttpRuntimePort
    events:         seq[QQOfficialEvent]
    accessToken:    string
    tokenExpirySec: int64
    passiveMsgSeq:  Table[string, int]

  QQOfficialGatewayInfo* = object
    url*:    string
    shards*: int

  QQOfficialGatewayState = object
    ws:          WsClient
    heartbeatMs: int
    lastBeatMs:  int64
    lastSeq:     int
    sessionId:   string

  QQOfficialGatewayArgs = object
    appId:        string
    clientSecret: string
    apiBase:      string
    tokenBase:    string
    intents:      int

## Thread-safe: chronos Channel uses internal synchronization.
## Opened once at daemon startup via startGateway().
var gQQOfficialEvents* {.global.}: Channel[QQOfficialEvent]

## Thread handle for the QQ official gateway OS thread.
## Safe: only assigned once via createThread in startGateway.
var gQQOfficialGatewayThread {.global.}: Thread[QQOfficialGatewayArgs]

## Startup guard — set to true once in startGateway.
## Safe: only written from main thread before any gateway activity begins.
var gQQOfficialGatewayStarted {.global.}: bool

func apiBase(a: QQOfficialAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: QQOfficialDefaultApiBase

func tokenBase(a: QQOfficialAdapter): string =
  if a.tokenBase.len > 0: a.tokenBase else: QQOfficialDefaultTokenBase

proc nowUnixSec(): int64 =
  getTime().toUnix()

proc sendHeartbeat(state: var QQOfficialGatewayState) =
  let payload = if state.lastSeq > 0: $state.lastSeq else: "null"
  state.ws.sendFrame("{\"op\":1,\"d\":" & payload & "}")
  state.lastBeatMs = nowUnixSec() * 1000

func qqBotHeaders*(token: string): seq[HttpHeader] =
  @[
    ("Authorization", "QQBot " & token),
    ("Content-Type", "application/json"),
  ]

func authRequestHeaders*(): seq[HttpHeader] =
  @[("Content-Type", "application/json")]

func detectOfficialEventType*(parsed: JsonNode): string =
  let payloadType = parsed.getOrDefault("t").getStr("")
  if payloadType.len > 0:
    return payloadType
  if parsed.getOrDefault("group_openid").getStr("").len > 0:
    return "GROUP_AT_MESSAGE_CREATE"
  if parsed.getOrDefault("author").getOrDefault("user_openid").getStr("").len > 0:
    return "C2C_MESSAGE_CREATE"
  ""

func parseOfficialEventNode*(eventType: string;
                             data: JsonNode): Result[QQOfficialEvent, string] =
  case eventType
  of "C2C_MESSAGE_CREATE":
    let userId = data.getOrDefault("author").getOrDefault("user_openid").getStr("")
    let messageId = data.getOrDefault("id").getStr("")
    if userId.len == 0 or messageId.len == 0:
      return err("missing user_openid/id")
    ok(QQOfficialEvent(
      messageType: "private",
      userId: userId,
      messageId: "msg:" & messageId,
      content: data.getOrDefault("content").getStr(""),
    ))
  of "GROUP_AT_MESSAGE_CREATE", "GROUP_MSG_RECEIVE":
    let groupId = data.getOrDefault("group_openid").getStr("")
    let author = data.getOrDefault("author")
    let memberId = author.getOrDefault("member_openid").getStr("")
    let userId =
      if memberId.len > 0: memberId
      else: author.getOrDefault("user_openid").getStr("")
    let messageId = data.getOrDefault("id").getStr("")
    if groupId.len == 0 or userId.len == 0 or messageId.len == 0:
      return err("missing group_openid/member_openid/id")
    ok(QQOfficialEvent(
      messageType: "group",
      userId: userId,
      groupId: groupId,
      messageId: "msg:" & messageId,
      content: data.getOrDefault("content").getStr(""),
    ))
  else:
    err("unsupported event type: " & eventType)

func parseInteractionEventNode*(data: JsonNode): Result[QQOfficialEvent, string] =
  let buttonData = data.getOrDefault("data").getOrDefault("resolved").getOrDefault("button_data").getStr("")
  let scene = data.getOrDefault("scene").getStr("")
  let eventId = data.getOrDefault("id").getStr("")
  let userId =
    if scene == "group":
      data.getOrDefault("group_member_openid").getStr("")
    else:
      data.getOrDefault("user_openid").getStr("")
  if eventId.len == 0 or userId.len == 0 or buttonData.len == 0:
    return err("missing interaction id/user/button_data")
  ok(QQOfficialEvent(
    messageType: if scene == "group": "group" else: "private",
    userId: userId,
    groupId: data.getOrDefault("group_openid").getStr(""),
    messageId: "event:" & eventId,
    content: "/callback " & buttonData,
  ))

proc parseOfficialEventJson*(payload: string): Result[QQOfficialEvent, string] =
  try:
    let parsed = parseJson(payload)
    let eventType = detectOfficialEventType(parsed)
    if eventType.len == 0:
      return err("unable to detect QQ official event type")
    let data =
      if parsed.hasKey("d"): parsed["d"]
      else: parsed
    parseOfficialEventNode(eventType, data)
  except CatchableError as e:
    err(e.msg)

func buildAccessTokenUrl*(tokenBase: string): string =
  tokenBase.strip(chars = {'/'}) & "/app/getAppAccessToken"

proc parseAccessTokenResponse*(body: string): Result[QQOfficialToken, string] =
  try:
    let parsed = parseJson(body)
    let accessToken = parsed.getOrDefault("access_token").getStr("")
    let expiresInRaw = parsed.getOrDefault("expires_in")
    let expiresIn =
      if expiresInRaw.kind == JString:
        parseInt(expiresInRaw.getStr(""))
      else:
        expiresInRaw.getInt(0)
    if accessToken.len == 0 or expiresIn <= 0:
      return err("missing access_token/expires_in")
    ok(QQOfficialToken(
      accessToken: accessToken,
      expiresInSec: int64(expiresIn),
    ))
  except CatchableError as e:
    err(e.msg)

proc parseGatewayInfoResponse*(body: string): Result[QQOfficialGatewayInfo, string] =
  try:
    let parsed = parseJson(body)
    let url = parsed.getOrDefault("url").getStr("")
    let shards = parsed.getOrDefault("shards").getInt(1)
    if url.len == 0:
      return err("missing gateway url")
    ok(QQOfficialGatewayInfo(url: url, shards: shards))
  except CatchableError as e:
    err(e.msg)

func buildSendUrl*(apiBase, rawId: string): Result[string, string] =
  let root = apiBase.strip(chars = {'/'})
  if rawId.len == 0:
    return err("missing QQ target id")
  if rawId.startsWith("group:"):
    let groupId = rawId["group:".len .. ^1]
    if groupId.len == 0:
      return err("missing QQ group_openid")
    return ok(root & "/v2/groups/" & groupId & "/messages")
  ok(root & "/v2/users/" & rawId & "/messages")

func parseReplyToken(replyTo: string): (string, string) =
  if replyTo.startsWith("event:"):
    return ("event", replyTo["event:".len .. ^1])
  if replyTo.startsWith("msg:"):
    return ("msg", replyTo["msg:".len .. ^1])
  ("msg", replyTo)

func qqKeyboardButtonStyle*(label, data: string): int =
  if label.startsWith("✓ "):
    return 1
  if data == "models:back" or label.startsWith("←") or label.endsWith("→"):
    return 0
  0

func qqKeyboardVisitedLabel*(label: string): string =
  if label.startsWith("✓ "): label else: "✓ " & label

func buildSendBody*(msg: OutboundMessage; msgSeq = 1): Result[JsonNode, string] =
  if msg.mediaUrl.len > 0:
    return err("qq official media send not implemented")
  var body = %* {
    "content": msg.text,
    "msg_type": 0,
  }
  if msg.replyTo.len > 0:
    let (replyKind, replyId) = parseReplyToken(msg.replyTo)
    if replyKind == "event":
      body["event_id"] = % replyId
    else:
      body["msg_id"] = % replyId
      body["msg_seq"] = % msgSeq
  ok(body)

func buildKeyboardBody*(text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo: string;
                        allowedUserIds: seq[string] = @[];
                        msgSeq = 1): JsonNode =
  var rows: seq[JsonNode]
  var idx = 0
  for row in buttons:
    var built: seq[JsonNode]
    for (label, data) in row:
      inc idx
      built.add(%* {
        "id": "btn-" & $idx,
        "render_data": {
          "label": label,
          "visited_label": qqKeyboardVisitedLabel(label),
          "style": qqKeyboardButtonStyle(label, data),
        },
        "action": {
          "type": 1,
          "permission":
            if allowedUserIds.len > 0:
              %* {"type": 0, "specify_user_ids": allowedUserIds}
            else:
              %* {"type": 2},
          "data": data,
          "unsupport_tips": "Atualize o QQ para usar este botão.",
        },
      })
    rows.add(%* {"buttons": built})

  result = %* {
    "msg_type": 2,
    "markdown": {"content": if text.len > 0: text else: "Escolha uma opção:"},
    "keyboard": {"content": {"rows": rows}},
  }
  if replyTo.len > 0:
    let (replyKind, replyId) = parseReplyToken(replyTo)
    if replyKind == "event":
      result["event_id"] = % replyId
    else:
      result["msg_id"] = % replyId
      result["msg_seq"] = % msgSeq

func buildGatewayBotUrl*(apiBase: string): string =
  apiBase.strip(chars = {'/'}) & "/gateway/bot"

proc newQQOfficialAdapter*(appId, clientSecret, identityPath: string): QQOfficialAdapter =
  discard identityPath
  QQOfficialAdapter(
    appId: appId,
    clientSecret: clientSecret,
    apiBase: QQOfficialDefaultApiBase,
    tokenBase: QQOfficialDefaultTokenBase,
    http: newStdHttpAdapter().toRuntimePort(),
    events: @[],
    passiveMsgSeq: initTable[string, int](),
  )

proc newQQOfficialAdapter*(appId, clientSecret, identityPath, apiBase,
                           tokenBase: string;
                           http: HttpRuntimePort): QQOfficialAdapter =
  discard identityPath
  QQOfficialAdapter(
    appId: appId,
    clientSecret: clientSecret,
    apiBase: apiBase,
    tokenBase: tokenBase,
    http: http,
    events: @[],
    passiveMsgSeq: initTable[string, int](),
  )

proc nextPassiveMsgSeq(a: var QQOfficialAdapter; rawId, replyTo: string): int =
  let (replyKind, replyId) = parseReplyToken(replyTo)
  if replyKind != "msg" or replyId.len == 0:
    return 0
  let key = rawId & "|" & replyId
  let next = a.passiveMsgSeq.getOrDefault(key, 0) + 1
  a.passiveMsgSeq[key] = next
  next

proc enqueueEventJson*(a: var QQOfficialAdapter; payload: string): Result[void, string] =
  let event = ? parseOfficialEventJson(payload)
  a.events.add(event)
  ok()

proc tryRecvEvent*(a: var QQOfficialAdapter): (bool, QQOfficialEvent) =
  if a.events.len == 0:
    return gQQOfficialEvents.tryRecv()
  let localEvent = a.events[0]
  a.events.delete(0)
  (true, localEvent)

proc ensureAccessToken*(a: var QQOfficialAdapter): Result[string, string] =
  if a.accessToken.len > 0 and (a.tokenExpirySec - QQOfficialTokenSkewSec) > nowUnixSec():
    return ok(a.accessToken)

  let body = %* {
    "appId": a.appId,
    "clientSecret": a.clientSecret,
  }
  let resp = ? a.http.post(buildAccessTokenUrl(a.tokenBase()), $body, authRequestHeaders())
  if resp.status < 200 or resp.status >= 300:
    return err("qq official token error " & $resp.status & ": " & resp.body)
  let token = ? parseAccessTokenResponse(resp.body)
  a.accessToken = token.accessToken
  a.tokenExpirySec = nowUnixSec() + token.expiresInSec
  ok(a.accessToken)

proc fetchGatewayInfo*(a: var QQOfficialAdapter): Result[QQOfficialGatewayInfo, string] =
  let token = ? a.ensureAccessToken()
  let resp = ? a.http.get(buildGatewayBotUrl(a.apiBase()), qqBotHeaders(token))
  if resp.status < 200 or resp.status >= 300:
    return err("qq official gateway error " & $resp.status & ": " & resp.body)
  parseGatewayInfoResponse(resp.body)

proc sendToRawId*(a: var QQOfficialAdapter;
                  rawId: string;
                  msg: OutboundMessage): Result[void, string] =
  let token = ? a.ensureAccessToken()
  let url = ? buildSendUrl(a.apiBase(), rawId)
  let msgSeq =
    if msg.replyTo.len > 0: a.nextPassiveMsgSeq(rawId, msg.replyTo)
    else: 0
  let body =
    if msg.keyboard.len > 0: buildKeyboardBody(msg.text, msg.keyboard, msg.replyTo, @[], msgSeq)
    else: ? buildSendBody(msg, msgSeq)
  let resp = ? a.http.post(url, $body, qqBotHeaders(token))
  if resp.status < 200 or resp.status >= 300:
    return err("qq official send error " & $resp.status & ": " & resp.body)
  ok()

proc sendKeyboardToRawId*(a: var QQOfficialAdapter;
                          rawId: string;
                          text: string;
                          buttons: seq[seq[(string, string)]];
                          replyTo = "";
                          allowedUserId = ""): Result[void, string] =
  let token = ? a.ensureAccessToken()
  let url = ? buildSendUrl(a.apiBase(), rawId)
  let msgSeq =
    if replyTo.len > 0: a.nextPassiveMsgSeq(rawId, replyTo)
    else: 0
  let allowIds = if allowedUserId.len > 0: @[allowedUserId] else: @[]
  let body = buildKeyboardBody(text, buttons, replyTo, allowIds, msgSeq)
  let resp = ? a.http.post(url, $body, qqBotHeaders(token))
  if resp.status < 200 or resp.status >= 300:
    return err("qq official send error " & $resp.status & ": " & resp.body)
  ok()

proc acknowledgeInteraction*(a: var QQOfficialAdapter; interactionId: string): Result[void, string] =
  let token = ? a.ensureAccessToken()
  let url = a.apiBase().strip(chars = {'/'}) & "/interactions/" & interactionId
  let body = %* {"code": 0}
  let resp = ? a.http.put(url, $body, qqBotHeaders(token))
  if resp.status < 200 or resp.status >= 300:
    return err("qq official interaction ack error " & $resp.status & ": " & resp.body)
  ok()

proc handleGatewayDispatch(adapter: var QQOfficialAdapter;
                           eventType: string;
                           data: JsonNode) =
  if eventType == "INTERACTION_CREATE":
    let event = parseInteractionEventNode(data).valueOr:
      return
    gQQOfficialEvents.send(event)
    discard adapter.acknowledgeInteraction(data.getOrDefault("id").getStr(""))
    return

  let eventRes = parseOfficialEventNode(eventType, data)
  if eventRes.isOk:
    gQQOfficialEvents.send(eventRes.value)

proc runGatewaySession(adapter: var QQOfficialAdapter;
                       intents: int;
                       state: var QQOfficialGatewayState) =
  let gateway = adapter.fetchGatewayInfo().valueOr:
    raise newException(IOError, "QQ official gateway lookup failed: " & error)
  var wsUrl = gateway.url
  if not wsUrl.startsWith("wss://"):
    wsUrl = "wss://" & wsUrl
  let noScheme = wsUrl[6 .. ^1]
  let slashIdx = noScheme.find('/')
  let host = if slashIdx >= 0: noScheme[0 ..< slashIdx] else: noScheme
  let path = if slashIdx >= 0: noScheme[slashIdx .. ^1] else: "/"
  state.ws = wsConnect(host, Port(443), path, useTls = true)

  let helloRes = state.ws.recvFrame()
  if helloRes.isErr:
    raise newException(IOError, "QQ official hello failed: " & helloRes.error)
  let hello = parseJson(helloRes.get().data)
  state.heartbeatMs = hello["d"]["heartbeat_interval"].getInt(45000)
  state.sendHeartbeat()

  let token = adapter.ensureAccessToken().valueOr:
    raise newException(IOError, "QQ official token refresh failed: " & error)
  if state.sessionId.len > 0:
    state.ws.sendFrame($ %* {
      "op": 6,
      "d": {
        "token": "QQBot " & token,
        "session_id": state.sessionId,
        "seq": state.lastSeq,
      },
    })
  else:
    state.ws.sendFrame($ %* {
      "op": 2,
      "d": {
        "token": "QQBot " & token,
        "intents": intents,
        "shard": [0, 1],
        "properties": {"app": "donkey"},
      },
    })

  while true:
    if nowUnixSec() * 1000 - state.lastBeatMs >= int64(state.heartbeatMs):
      state.sendHeartbeat()
    try:
      let frameRes = state.ws.recvFrame()
      if frameRes.isErr:
        if frameRes.error == "timeout":
          continue
        raise newException(IOError, "QQ official receive failed: " & frameRes.error)
      let frame = frameRes.get()
      case frame.opcode
      of WsOpcodeText:
        let j = parseJson(frame.data)
        let op = j.getOrDefault("op").getInt(-1)
        case op
        of 0:
          let s = j.getOrDefault("s").getInt(0)
          if s > 0: state.lastSeq = s
          let t = j.getOrDefault("t").getStr("")
          let d = j.getOrDefault("d")
          if t == "READY":
            state.sessionId = d.getOrDefault("session_id").getStr("")
          elif t == "RESUMED":
            discard
          else:
            handleGatewayDispatch(adapter, t, d)
        of 7:
          raise newException(IOError, "QQ official requested reconnect (op=7)")
        of 9:
          state.sessionId = ""
          raise newException(IOError, "QQ official invalid session (op=9)")
        of 10:
          discard
        of 11:
          discard
        else:
          discard
      of WsOpcodePing:
        state.ws.sendFrame(frame.data, WsOpcodePong)
      of WsOpcodeClose:
        raise newException(IOError, "QQ official gateway closed")
      else:
        discard
    except TimeoutError:
      discard

proc qqOfficialGatewayThread(arg: QQOfficialGatewayArgs) {.thread.} =
  var adapter = newQQOfficialAdapter(arg.appId, arg.clientSecret, "",
                                     arg.apiBase, arg.tokenBase,
                                     newStdHttpAdapter().toRuntimePort())
  var state = QQOfficialGatewayState()
  var backoffMs = 1000
  while true:
    try:
      runGatewaySession(adapter, arg.intents, state)
    except Exception as e:
      echo "[qq-official] gateway error: " & e.msg & " — reconnecting in " &
           $backoffMs & " ms"
      sleep(backoffMs)
      backoffMs = min(backoffMs * 2, 60_000)

proc startGateway*(a: QQOfficialAdapter; intents = QQOfficialDefaultIntents) {.gcsafe.} =
  {.cast(gcsafe).}:
    if gQQOfficialGatewayStarted:
      return
    gQQOfficialEvents.open()
    gQQOfficialGatewayStarted = true
    createThread(gQQOfficialGatewayThread, qqOfficialGatewayThread, QQOfficialGatewayArgs(
      appId: a.appId,
      clientSecret: a.clientSecret,
      apiBase: a.apiBase(),
      tokenBase: a.tokenBase(),
      intents: intents,
    ))
