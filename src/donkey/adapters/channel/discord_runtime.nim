import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ./discord

proc handleDiscordEvent*(sm: var SessionManager;
                         event: DiscordRawEvent;
                         dcAdapter: DiscordAdapter;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         toolsCount: int;
                         toolClientsCount: int;
                         msgSeq: var int;
                         log: Logger;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  case event.kind
  of deMessage:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    let command = decideCommandRequest(CommandRequest(channel: ckDiscord, text: event.content))
    if decideLocalCommandAction(command) == lcaGenerateLinkCode:
      let code = dcAdapter.resolver.generateLinkCode(userId)
      let codeText = "Your link code: **" & code & "** (valid 10 min)\n" &
                     "Type `/continue` on another channel to reconnect."
      if event.interactionId.len > 0:
        dcAdapter.sendInteractionResponse(
          event.interactionId, event.interactionToken, codeText).isOkOr:
            log.error("dc /mycode interaction resp: " & error)
      else:
        dcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckDiscord,
          text: codeText,
        )).isOkOr:
          log.error("dc /mycode reply: " & error)
    else:
      handleSessionFallback(InboundMessage(
        userId:    userId,
        channel:   ckDiscord,
        channelId: event.messageId,
        text:      event.content,
      ))

  of deInteraction:
    let code = event.content |> strip
    let linked = dcAdapter.resolver.consumeLinkCode(
      code, ckDiscord, event.discordUserId)
    let replyText =
      if linked: "✅ Session reconnected! Your conversation history carries over."
      else:      "❌ Invalid or expired code. Generate a fresh one with `/mycode`."
    dcAdapter.sendInteractionResponse(
      event.interactionId, event.interactionToken, replyText).isOkOr:
        log.error("dc interaction response: " & error)

  of deModalRequest:
    dcAdapter.sendInteractionModal(
      event.interactionId, event.interactionToken).isOkOr:
        log.error("dc send modal: " & error)

  of deButtonClick:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    dcAdapter.sendButtonAck(
      event.interactionId, event.interactionToken).isOkOr:
        log.error("dc button ack: " & error)
    let callback = decideCallbackRequest(
      CallbackRequest(channel: ckDiscord, data: event.content))
    if callback.route != cbrSessionTask:
      return
    let entry = sm.getOrCreate(userId)
    inc msgSeq
    entry.inbox.addLastNoWait(
      newTaskMsg($msgSeq, callbackTaskKind(callback), $userId, callback.value, ckDiscord, ""))

proc drainDiscordEvents*(sm: var SessionManager;
                         dcAdapter: DiscordAdapter;
                         discordToken: string;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         toolsCount: int;
                         toolClientsCount: int;
                         msgSeq: var int;
                         log: Logger;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if discordToken.len == 0:
    return

  var (hasEvent, event) = dcAdapter.tryRecvEvent()
  while hasEvent:
    handleDiscordEvent(sm, event, dcAdapter, memory, completeBuilder,
                       toolsCount, toolClientsCount, msgSeq, log, handleSessionFallback)
    (hasEvent, event) = dcAdapter.tryRecvEvent()
