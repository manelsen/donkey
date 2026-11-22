## QQAdapter — OneBot v11 style channel adapter.
##
## Receiving:
##   startWebhook(port) launches an embedded HTTP server on a dedicated OS
##   thread. It accepts POST requests from the OneBot bridge and pushes parsed
##   events into a thread-safe Channel drained by tryRecvEvent().
##
##   Authentication: with QQ_ONEBOT_SECRET set, every POST must carry the
##   OneBot v11 `X-Signature: sha1=<HMAC-SHA1(secret, body)>` header (403
##   otherwise). Without a secret the listener only binds to loopback.
##
##   For testing or external forwarding, enqueueEventJson() accepts raw JSON
##   directly without going through the HTTP path.
##
## Sending:
##   Uses OneBot HTTP APIs with Bearer token authentication.

import std/[json, nativesockets, net, strutils, tables]
import ../../core/log
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/qq_pure
import ../http/std_http
import ../identity/identity_resolver
import ../webhook/http_request_reader
import ../../app/metrics
import ../../infra/event_queue
import ../../infra/thread_handle

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
    listenFd: SocketHandle   ## bound + listening, owned by the thread
    domain:   Domain
    secret:   string
    logger:   Logger

var gQQOneBotEvents = initEventQueue[QQEvent]("qq_onebot")
var gQQOneBotEventsOpen    = false
var gQQOneBotWebhookStarted = false
var gQQOneBotWebhookThread: ThreadHandle[QQOneBotWebhookArgs]  ## shared memory: a global pointer is gcsafe

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

proc respond(s: Socket; status: string) =
  let resp = "HTTP/1.1 " & status & "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  try: s.send(resp) except CatchableError: discard

proc handleQQOneBotConn*(client: Socket; logger: Logger; secret = "";
                         timeoutSec = WebhookClientTimeoutSec) =
  ## Serves one OneBot v11 event delivery and closes the socket. The request
  ## is read through http_request_reader: bounded headers, capped body,
  ## socket timeouts — a hostile peer gets 4xx instead of OOM or a hung thread.
  defer: closeWebhookClient(client)
  applyWebhookClientTimeouts(client, timeoutSec).isOkOr:
    logger.warn("qq webhook: " & error)
    recordWebhookFailure("qq", error)
    return
  let req = readWebhookRequest(client).valueOr:
    logger.warn("qq webhook: rejected request: " & error)
    recordWebhookFailure("qq", error)
    client.respond(statusLine(readErrorStatus(error)))
    return
  if req.httpMethod == "POST" and req.body.len > 0:
    if not oneBotSignatureValid(secret, req.body,
                                req.headers.getOrDefault("x-signature")):
      logger.warn("qq webhook: rejected event with missing/invalid X-Signature")
      recordWebhookFailure("qq", "invalid signature")
      client.respond(statusLine(403))
      return
    let evRes = parseEventJson(req.body)
    if evRes.isOk and gQQOneBotEventsOpen:
      gQQOneBotEvents.push(evRes.value)
    client.respond("200 OK")
  else:
    client.respond("405 Method Not Allowed")

func listenDomain(host: string): Domain =
  ## `::1` and other IPv6 literals need an AF_INET6 socket; names and IPv4
  ## literals bind on AF_INET.
  try:
    if parseIpAddress(host).family == IpAddressFamily.IPv6: AF_INET6
    else: AF_INET
  except ValueError: AF_INET

proc bindOneBotListener*(host: string; port: Port): Result[Socket, string] =
  ## Binds synchronously so a bad host/port is reported to the caller
  ## instead of killing the listener thread after "started" was logged.
  ## The socket family follows the host: `::1` needs an AF_INET6 socket.
  let domain = listenDomain(host)
  var server: Socket
  try:
    server = newSocket(domain, buffered = false)  ## see http_request_reader
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(port, host)
    server.listen()
    ok(server)
  except CatchableError as e:
    if server != nil:
      try: server.close() except CatchableError: discard
    err("bind " & host & ":" & $port & ": " & e.msg)

proc qqOneBotWebhookThread(args: QQOneBotWebhookArgs) {.thread.} =
  ## Minimal HTTP/1.1 server for OneBot v11 event delivery.
  let server = newSocket(args.listenFd, args.domain, buffered = false)

  while true:
    var client: Socket
    try:
      server.accept(client)
    except CatchableError:
      continue
    try:
      handleQQOneBotConn(client, args.logger, args.secret)
    except CatchableError:
      let errMsg = getCurrentExceptionMsg()
      args.logger.warn("qq webhook: connection handler error: " & errMsg)
      recordWebhookFailure("qq", errMsg)

proc startWebhook*(a: QQAdapter; host: string; port: Port; secret: string;
                   logger: Logger): Result[void, string] =
  ## Starts the embedded OneBot webhook HTTP server on host:port.
  ## Refuses a non-loopback bind without a secret (see oneBotListenerCheck).
  ## Safe to call multiple times — only the first call has effect.
  ? oneBotListenerCheck(host, secret)
  if gQQOneBotWebhookStarted:
    return ok()
  let server = ? bindOneBotListener(host, port)
  let domain = listenDomain(host)
  gQQOneBotEventsOpen = true
  try:
    gQQOneBotWebhookThread = spawnThread(qqOneBotWebhookThread,
                 QQOneBotWebhookArgs(listenFd: server.getFd, domain: domain,
                                     secret: secret, logger: logger))
  except CatchableError as e:
    ## Undo so a later call can retry instead of seeing "already started".
    gQQOneBotEventsOpen = false
    try: server.close() except CatchableError: discard
    return err("qq webhook thread: " & e.msg)
  gQQOneBotWebhookStarted = true
  ok()

proc enqueueEventJson*(a: var QQAdapter; payload: string): Result[void, string] =
  let event = ? parseEventJson(payload)
  if gQQOneBotEventsOpen:
    if not gQQOneBotEvents.push(event):
      return err("qq event queue full: event dropped")
  else:
    a.events.add(event)
  ok()

proc tryRecvEvent*(a: var QQAdapter): (bool, QQEvent) =
  if gQQOneBotEventsOpen:
    let (ok, ev) = gQQOneBotEvents.tryTake()
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
