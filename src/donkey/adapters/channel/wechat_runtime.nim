import std/strutils
import ../../domain/message
import ../identity/identity_resolver
import ./wechat

proc drainWeChatEvents*(wchAdapter: var WeChatAdapter;
                        wechatAppId: string;
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if wechatAppId.len == 0:
    return

  var (hasEvent, event) = wchAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and event.content.strip.len > 0:
      let userId = resolve(wchAdapter.resolver, ckWeChat, event.fromUser)
      handleSessionFallback(InboundMessage(
        userId: userId,
        channel: ckWeChat,
        channelId: event.msgId,
        text: event.content,
      ))
    (hasEvent, event) = wchAdapter.tryRecvEvent()
