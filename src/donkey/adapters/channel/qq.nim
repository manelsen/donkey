## QQAdapter — OneBot v11 style channel adapter.
##
## Receiving:
##   startWebhook(port) launches an embedded HTTP server on a dedicated OS
##   thread. It accepts POST requests from the OneBot bridge and pushes parsed
##   events into a thread-safe Channel drained by tryRecvEvent().
##
##   For testing or external forwarding, enqueueEventJson() accepts raw JSON
##   directly without going through the HTTP path.
##
## Sending:
##   Uses OneBot HTTP APIs with Bearer token authentication.

import std/[json, net, strutils]
import ../../core/pipeops
import ../../domain/message
import ../http/std_http
import ../identity/identity_resolver

const
  OneBotDefaultBase* = "http://127.0.0.1:5700"

type
  QQEvent* = object
    messageType*: string
    userId*:      string
    groupId*:     string
    messageId*:   string
    content*:     string

  QQAdapter* = object
    apiBase*:     string
    accessToken*: string
    resolver*:    IdentityResolver
    http*:        StdHttpAdapter
    events:       seq[QQEvent]   ## direct-injection queue (tests / external)

  QQOneBotWebhookArgs = object
    port: int

var gQQOneBotEvents: Channel[QQEvent]
var gQQOneBotEventsOpen    = false
var gQQOneBotWebhookStarted = false
var gQQOneBotWebhookThread: Thread[QQOneBotWebhookArgs]

func base(a: QQAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: OneBotDefaultBase

proc newQQAdapter*(apiBase, accessToken, identityPath: string): QQAdapter =
  QQAdapter(
    apiBase: apiBase,
    accessToken: accessToken,
    resolver: newIdentityResolver(identityPath),
    http: newStdHttpAdapter(),
    events: @[],
  )

proc authHeaders(a: QQAdapter): seq[(string, string)] =
  if a.accessToken.len == 0: @[]
  else: @[("Authorization", "Bearer " & a.accessToken),
          ("Content-Type", "application/json")]

proc parseEventJson*(payload: string): Result[QQEvent, string] =
  try:
    let parsed = parseJson(payload)
    if parsed.getOrDefault("post_type").getStr("") != "message":
      return err("unsupported post_type")
    let messageType = parsed.getOrDefault("message_type").getStr("")
    let userId = $parsed.getOrDefault("user_id").getBiggestInt()
    if messageType.len == 0 or userId == "0":
      return err("missing message_type/user_id")
    ok(QQEvent(
      messageType: messageType,
      userId: userId,
      groupId: $parsed.getOrDefault("group_id").getBiggestInt(),
      messageId: $parsed.getOrDefault("message_id").getBiggestInt(),
      content: parsed.getOrDefault("raw_message").getStr(""),
    ))
  except CatchableError as e:
    err(e.msg)

proc qqOneBotWebhookThread(args: QQOneBotWebhookArgs) {.thread.} =
  ## Minimal HTTP/1.1 server for OneBot v11 event delivery.
  ## Accepts POST requests with a JSON body and enqueues parsed QQEvents.

  proc readLine(s: Socket): string =
    var buf = ""
    var c: char
    while true:
      if s.recv(c.addr, 1) != 1:
        return buf
      if c == '\r':
        discard s.recv(c.addr, 1)
        break
      buf.add(c)
    buf

  proc respond(s: Socket; status: string) =
    let resp = "HTTP/1.1 " & status & "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    try: s.send(resp) except CatchableError:
      stderr.writeLine("[WRN] [qq.respond] failed to send response: " & getCurrentExceptionMsg())

  var server = newSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(args.port))
  server.listen()

  while true:
    var client: Socket
    try:
      server.accept(client)
    except CatchableError:
      continue
    try:
      let requestLine = client.readLine()
      let parts = requestLine.split(' ')
      let meth = if parts.len >= 1: parts[0] else: ""
      var contentLength = 0
      while true:
        let h = client.readLine()
        if h.len == 0:
          break
        let lower = h.toLowerAscii()
        if lower.startsWith("content-length:"):
          try: contentLength = parseInt(h[15 .. ^1].strip())
          except ValueError: discard
      var body = ""
      if contentLength > 0:
        body = newString(contentLength)
        var received = 0
        while received < contentLength:
          let n = client.recv(body[received].addr, contentLength - received)
          if n <= 0: break
          received += n

      if meth == "POST" and body.len > 0:
        let evRes = parseEventJson(body)
        if evRes.isOk:
          gQQOneBotEvents.send(evRes.value)
        client.respond("200 OK")
      else:
        client.respond("405 Method Not Allowed")
    except CatchableError:
      stderr.writeLine("[WRN] [qq webhook] connection handler error: " & getCurrentExceptionMsg())
    try: client.close() except CatchableError: discard

proc startWebhook*(a: QQAdapter; port: Port) =
  ## Starts the embedded OneBot webhook HTTP server on the given port.
  ## Safe to call multiple times — only the first call has effect.
  if gQQOneBotWebhookStarted:
    return
  gQQOneBotEvents.open()
  gQQOneBotEventsOpen     = true
  gQQOneBotWebhookStarted = true
  createThread(gQQOneBotWebhookThread, qqOneBotWebhookThread,
               QQOneBotWebhookArgs(port: port.int))

proc enqueueEventJson*(a: var QQAdapter; payload: string): Result[void, string] =
  let event = ? parseEventJson(payload)
  if gQQOneBotEventsOpen:
    gQQOneBotEvents.send(event)
  else:
    a.events.add(event)
  ok()

proc tryRecvEvent*(a: var QQAdapter): (bool, QQEvent) =
  if gQQOneBotEventsOpen:
    let (ok, ev) = gQQOneBotEvents.tryRecv()
    if ok:
      return (true, ev)
  if a.events.len == 0:
    return (false, QQEvent())
  let event = a.events[0]
  a.events.delete(0)
  (true, event)

proc targetFor*(a: QQAdapter; userId: UserId): Result[(string, string), string] =
  let rawId = a.resolver.reverseChannel(userId, ckQQ)
  if rawId.len == 0:
    return err("QQAdapter.send: no QQ id for user " & $userId)
  if rawId.startsWith("group:"):
    return ok(("send_group_msg", rawId["group:".len .. ^1]))
  ok(("send_private_msg", rawId))

proc sendToRawId*(a: var QQAdapter;
                  rawId: string;
                  msg: OutboundMessage): Result[void, string] =
  let (apiMethod, targetId) =
    if rawId.len == 0:
      return err("QQAdapter.send: missing raw QQ id")
    elif rawId.startsWith("group:"):
      ("send_group_msg", rawId["group:".len .. ^1])
    else:
      ("send_private_msg", rawId)
  let key = if apiMethod == "send_group_msg": "group_id" else: "user_id"
  let body = %* {key: targetId, "message": msg.text}
  let resp = ? a.http.post(a.base() & "/" & apiMethod, $body, a.authHeaders())
  if resp.status < 200 or resp.status >= 300:
    return err("qq send error " & $resp.status & ": " & resp.body)
  ok()

proc send*(a: var QQAdapter; msg: OutboundMessage): Result[void, string] =
  let (_, rawId) = ? a.targetFor(msg.userId)
  let fullRawId =
    if a.resolver.reverseChannel(msg.userId, ckQQ).startsWith("group:"):
      "group:" & rawId
    else:
      rawId
  a.sendToRawId(fullRawId, msg)
