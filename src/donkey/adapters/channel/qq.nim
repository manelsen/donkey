## QQAdapter — OneBot v11 style channel adapter.
##
## Receiving:
##   The OneBot bridge POSTs events to the shared webhook receiver at
##   /webhook/qq (DONKEY_WEBHOOK_PORT), which hands them to acceptOneBotEvent.
##   Events wait in a thread-safe queue drained by tryRecvEvent().
##
##   Authentication: with QQ_ONEBOT_SECRET set, every POST must carry the
##   OneBot v11 `X-Signature: sha1=<HMAC-SHA1(secret, body)>` header (403
##   otherwise). Without a secret the route is mounted only when the receiver
##   binds to loopback (oneBotListenerCheck).
##
##   For testing or external forwarding, enqueueEventJson() accepts raw JSON
##   directly without going through the HTTP path.
##
## Sending:
##   Uses OneBot HTTP APIs with Bearer token authentication.

import std/[json, strutils, tables]
import ../../core/log
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/qq_pure
import ../http/std_http
import ../identity/identity_resolver
import ../../app/metrics
import ../../infra/event_queue

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

var gQQOneBotEvents = initEventQueue[QQEvent]("qq_onebot")
  ## Valid for the daemon's lifetime: the receiver's workers push, the loop polls.

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

proc acceptOneBotEvent*(payload: string): Result[void, string] {.gcsafe.} =
  ## Queues a OneBot event for the daemon loop; the receiver has already
  ## checked its signature.
  let event = ? parseEventJson(payload)
  if not gQQOneBotEvents.push(event):
    return err("qq event queue full: event dropped")
  ok()

proc enqueueEventJson*(a: var QQAdapter; payload: string): Result[void, string] =
  ## Direct injection into this adapter (tests, external forwarding).
  let event = ? parseEventJson(payload)
  a.events.add(event)
  ok()

proc tryRecvEvent*(a: var QQAdapter): (bool, QQEvent) =
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
