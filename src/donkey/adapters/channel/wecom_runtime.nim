import std/strutils
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../domain/message
import ../identity/identity_resolver
import ./wecom

proc drainWeComEvents*(wcAdapter: var WeComAdapter;
                       wecomCorpId: string;
                       memory: MdFileAdapter;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if wecomCorpId.len == 0:
    return

  var (hasEvent, event) = wcAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and (event.content |> strip).len > 0:
      let userId = wcAdapter.resolver.resolve(ckWeCom, event.fromUser)
      handleSessionFallback(InboundMessage(
        userId:    userId,
        channel:   ckWeCom,
        channelId: event.msgId,
        text:      event.content,
      ))
    (hasEvent, event) = wcAdapter.tryRecvEvent()
