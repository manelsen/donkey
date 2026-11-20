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
import ./feishu
import ./text_command_dispatch

proc drainFeishuEvents*(fsAdapter: var FeishuAdapter;
                        feishuAppId: string;
                        sm: var SessionManager;
                        env: CommandEnv;
                        msgSeq: var int;
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                        log: Logger = newLogger("fs.outbound")) =
  if feishuAppId.len == 0:
    return

  var (hasEvent, event) = fsAdapter.tryRecvEvent()
  while hasEvent:
    if (event.msgType == "text" and (event.content |> strip).len > 0) or
       event.fileKey.len > 0:
      ## Only a text event runs the command dispatcher; a media-only event
      ## must not mint an identity just because its caption contains
      ## `/continue <code>` (the code would never be consumed).
      let gateText = if event.msgType == "text": event.content else: ""
      let auth = authorizeInbound(sm, fsAdapter.resolver.identityGate(), ckFeishu,
                                  event.openId, gateText)
      if not auth.allowed:
        log.warn("feishu: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = fsAdapter.tryRecvEvent()
        continue
      let userId = auth.userId
      let approvalReply = tryHandleApprovalInput(userId, event.content)
      if approvalReply.isSome:
        fsAdapter.send(OutboundMessage(
          userId: userId, channel: ckFeishu, text: approvalReply.get)).isOkOr:
          log.error("fs send approval reply failed: " & error)
        (hasEvent, event) = fsAdapter.tryRecvEvent()
        continue
      let msg = InboundMessage(
        userId:    userId,
        channel:   ckFeishu,
        channelId: event.msgId,
        text:      event.content,
        mediaUrl:  event.fileKey,
      )
      if event.msgType == "text" and (event.content |> strip).len > 0:
        let command = decideCommandRequest(CommandRequest(channel: ckFeishu, text: event.content))
        let outcome = dispatchTextCommand(env, sm, msgSeq, command, userId, ckFeishu,
                                          event.msgId, fsAdapter.resolver, event.openId)
        case outcome.kind
        of cokFallback:
          handleSessionFallback(msg)
        of cokSilent:
          discard
        of cokReply:
          if outcome.reply.shouldSend:
            fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu,
                                           text: outcome.reply.text)).isOkOr:
              log.error("fs send " & $outcome.reply.topic & " failed for user=" &
                        $userId & " reason=" & error)
      else:
        handleSessionFallback(msg)
    (hasEvent, event) = fsAdapter.tryRecvEvent()
