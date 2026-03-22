## QQChannelAdapter — unified QQ channel facade for OneBot and official QQ Bot API.

import std/net
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../identity/identity_resolver
import ../http/std_http
import qq
import qq_official

type
  QQBackendKind* = enum
    qbkNone
    qbkOneBot
    qbkOfficial

  QQInboundEvent* = object
    messageType*: string
    userId*:      string
    groupId*:     string
    messageId*:   string
    content*:     string

  QQChannelAdapter* = object
    resolver*: IdentityResolver
    case kind*: QQBackendKind
    of qbkOneBot:
      onebot*: QQAdapter
    of qbkOfficial:
      official*: QQOfficialAdapter
    of qbkNone:
      discard

func qqRawIdentity*(event: QQInboundEvent): string =
  if event.messageType == "group" and event.groupId.len > 0 and event.groupId != "0":
    "group:" & event.groupId
  else:
    event.userId

func enabled*(a: QQChannelAdapter): bool =
  a.kind != qbkNone

func backendLabel*(a: QQChannelAdapter): string =
  case a.kind
  of qbkOneBot: "onebot"
  of qbkOfficial: "official"
  of qbkNone: "disabled"

proc newQQDisabledChannelAdapter*(identityPath: string): QQChannelAdapter =
  QQChannelAdapter(
    kind: qbkNone,
    resolver: newIdentityResolver(identityPath),
  )

proc newQQOneBotChannelAdapter*(apiBase, accessToken, identityPath: string): QQChannelAdapter =
  QQChannelAdapter(
    kind: qbkOneBot,
    resolver: newIdentityResolver(identityPath),
    onebot: newQQAdapter(apiBase, accessToken, identityPath),
  )

proc newQQOfficialChannelAdapter*(appId, clientSecret, identityPath: string;
                                  apiBase = QQOfficialDefaultApiBase;
                                  tokenBase = QQOfficialDefaultTokenBase): QQChannelAdapter =
  QQChannelAdapter(
    kind: qbkOfficial,
    resolver: newIdentityResolver(identityPath),
    official: newQQOfficialAdapter(appId, clientSecret, identityPath, apiBase, tokenBase,
                                   newStdHttpAdapter().toRuntimePort()),
  )

proc resolveUser*(a: var QQChannelAdapter; event: QQInboundEvent): UserId =
  resolve(a.resolver, ckQQ, qqRawIdentity(event))

proc generateLinkCode*(a: var QQChannelAdapter; userId: UserId): string =
  a.resolver.generateLinkCode(userId)

proc consumeLinkCode*(a: var QQChannelAdapter; code: string; rawIdentity: string): bool =
  a.resolver.consumeLinkCode(code, ckQQ, rawIdentity)

proc enqueueEventJson*(a: var QQChannelAdapter; payload: string): Result[void, string] =
  case a.kind
  of qbkOneBot:
    a.onebot.enqueueEventJson(payload)
  of qbkOfficial:
    a.official.enqueueEventJson(payload)
  of qbkNone:
    err("qq channel disabled")

proc tryRecvEvent*(a: var QQChannelAdapter): (bool, QQInboundEvent) =
  case a.kind
  of qbkOneBot:
    let (hasEvent, event) = a.onebot.tryRecvEvent()
    (hasEvent, QQInboundEvent(
      messageType: event.messageType,
      userId: event.userId,
      groupId: event.groupId,
      messageId: event.messageId,
      content: event.content,
    ))
  of qbkOfficial:
    let (hasEvent, event) = a.official.tryRecvEvent()
    (hasEvent, QQInboundEvent(
      messageType: event.messageType,
      userId: event.userId,
      groupId: event.groupId,
      messageId: event.messageId,
      content: event.content,
    ))
  of qbkNone:
    (false, QQInboundEvent())

proc send*(a: var QQChannelAdapter; msg: OutboundMessage): Result[void, string] =
  let rawId = a.resolver.reverseChannel(msg.userId, ckQQ)
  if rawId.len == 0:
    return err("QQChannelAdapter.send: no QQ id for user " & $msg.userId)
  case a.kind
  of qbkOneBot:
    a.onebot.sendToRawId(rawId, msg)
  of qbkOfficial:
    a.official.sendToRawId(rawId, msg)
  of qbkNone:
    err("qq channel disabled")

proc sendKeyboard*(a: var QQChannelAdapter;
                   userId: UserId;
                   text: string;
                   buttons: seq[seq[(string, string)]];
                   replyTo = "";
                   allowedRawUserId = ""): Result[void, string] =
  let rawId = a.resolver.reverseChannel(userId, ckQQ)
  if rawId.len == 0:
    return err("QQChannelAdapter.sendKeyboard: no QQ id for user " & $userId)
  case a.kind
  of qbkOfficial:
    a.official.sendKeyboardToRawId(rawId, text, buttons, replyTo, allowedRawUserId)
  of qbkOneBot:
    err("QQ OneBot does not support rich keyboard")
  of qbkNone:
    err("qq channel disabled")

proc startGateway*(a: var QQChannelAdapter) =
  case a.kind
  of qbkOfficial:
    a.official.startGateway()
  else:
    discard

proc startWebhook*(a: QQChannelAdapter; port: Port) =
  case a.kind
  of qbkOneBot:
    a.onebot.startWebhook(port)
  else:
    discard
