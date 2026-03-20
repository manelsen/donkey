import std/strutils
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../domain/message
import ../identity/identity_resolver
import ./feishu

proc drainFeishuEvents*(fsAdapter: var FeishuAdapter;
                        feishuAppId: string;
                        memory: MdFileAdapter;
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if feishuAppId.len == 0:
    return

  var (hasEvent, event) = fsAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and (event.content |> strip).len > 0:
      let userId = fsAdapter.resolver.resolve(ckFeishu, event.openId)
      handleSessionFallback(InboundMessage(
        userId:    userId,
        channel:   ckFeishu,
        channelId: event.msgId,
        text:      event.content,
      ))
    (hasEvent, event) = fsAdapter.tryRecvEvent()
