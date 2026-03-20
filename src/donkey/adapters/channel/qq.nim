## QQAdapter — OneBot v11 style channel adapter.
##
## Receiving:
##   An external HTTP/WebSocket bridge is expected to forward OneBot events via
##   enqueueEventJson(). The daemon drains tryRecvEvent().
##
## Sending:
##   Uses OneBot HTTP APIs with Bearer token authentication.

import std/[json, strutils]
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
    events:       seq[QQEvent]

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

proc enqueueEventJson*(a: var QQAdapter; payload: string): Result[void, string] =
  let event = ? parseEventJson(payload)
  a.events.add(event)
  ok()

proc tryRecvEvent*(a: var QQAdapter): (bool, QQEvent) =
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

proc send*(a: var QQAdapter; msg: OutboundMessage): Result[void, string] =
  let (apiMethod, targetId) = ? a.targetFor(msg.userId)
  let key = if apiMethod == "send_group_msg": "group_id" else: "user_id"
  let body = %* {key: targetId, "message": msg.text}
  let resp = ? a.http.post(a.base() & "/" & apiMethod, $body, a.authHeaders())
  if resp.status < 200 or resp.status >= 300:
    return err("qq send error " & $resp.status & ": " & resp.body)
  ok()
