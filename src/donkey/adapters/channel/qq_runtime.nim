import std/strutils
import ../../domain/message
import ../identity/identity_resolver
import ./qq

func qqRawIdentity*(event: QQEvent): string =
  if event.messageType == "group" and event.groupId.len > 0 and event.groupId != "0":
    "group:" & event.groupId
  else:
    event.userId

proc drainQQEvents*(qqAdapter: var QQAdapter;
                    qqApiBase: string;
                    handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if qqApiBase.len == 0:
    return

  var (hasEvent, event) = qqAdapter.tryRecvEvent()
  while hasEvent:
    if event.content.strip.len > 0:
      let userId = resolve(qqAdapter.resolver, ckQQ, qqRawIdentity(event))
      handleSessionFallback(InboundMessage(
        userId: userId,
        channel: ckQQ,
        channelId: event.messageId,
        text: event.content,
      ))
    (hasEvent, event) = qqAdapter.tryRecvEvent()
