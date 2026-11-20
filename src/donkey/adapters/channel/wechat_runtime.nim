import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../core/pipeops
import ../../app/session_manager
import ../../domain/message
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../app/approval_runtime
import ./wechat
import ./text_command_dispatch

proc sendWeChatReply(wchAdapter: var WeChatAdapter;
                     userId: UserId;
                     text: string) =
  wchAdapter.send(OutboundMessage(
    userId: userId,
    channel: ckWeChat,
    text: text,
  )).isOkOr:
    discard

proc drainWeChatEvents*(wchAdapter: var WeChatAdapter;
                        wechatAppId: string;
                        sm: var SessionManager;
                        env: CommandEnv;
                        msgSeq: var int;
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                        log: Logger = newLogger("wch.outbound")) =
  if wechatAppId.len == 0:
    return

  var (hasEvent, event) = wchAdapter.tryRecvEvent()
  while hasEvent:
    if (event.msgType == "text" and event.content.strip.len > 0) or
       event.mediaId.len > 0:
      ## Only a text event runs the command dispatcher; a media-only event
      ## must not mint an identity just because its caption contains
      ## `/continue <code>` (the code would never be consumed).
      let gateText = if event.msgType == "text": event.content else: ""
      let auth = authorizeInbound(sm, wchAdapter.resolver.identityGate(), ckWeChat,
                                  event.fromUser, gateText)
      if not auth.allowed:
        log.warn("wechat: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = wchAdapter.tryRecvEvent()
        continue
      let userId = auth.userId
      let approvalReply = tryHandleApprovalInput(userId, event.content)
      if approvalReply.isSome:
        sendWeChatReply(wchAdapter, userId, approvalReply.get)
        (hasEvent, event) = wchAdapter.tryRecvEvent()
        continue
      let msg = InboundMessage(
        userId: userId,
        channel: ckWeChat,
        channelId: event.msgId,
        text: event.content,
        mediaUrl: event.mediaId,
      )
      if event.msgType == "text" and event.content.strip.len > 0:
        let command = decideCommandRequest(CommandRequest(channel: ckWeChat, text: event.content))
        let outcome = dispatchTextCommand(env, sm, msgSeq, command, userId, ckWeChat,
                                          event.msgId, wchAdapter.resolver, event.fromUser)
        case outcome.kind
        of cokFallback:
          handleSessionFallback(msg)
        of cokSilent:
          discard
        of cokReply:
          if outcome.reply.shouldSend:
            wchAdapter.sendWeChatReply(userId, outcome.reply.text)
      else:
        handleSessionFallback(msg)
    (hasEvent, event) = wchAdapter.tryRecvEvent()
