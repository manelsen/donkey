import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/pipeops
import ../../app/session_manager
import ../../domain/message
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../app/approval_runtime
import ./common_runtime
import ./wecom
import ../../app/command_dispatch
import ../../ports/channel_capability

# ── Markdown builders for WeCom rich replies ──────────────────────────────────
#
# WeCom markdown subset: ## heading, **bold**,
# <font color="info|comment|warning">text</font>, [link](url), > quote, - list.

func buildWeComHelpMd*(): string =
  let pages = buildHelpPages(commandCaps(ckWeCom))
  result = "## 📖 Donkey — Ajuda\n"
  for (title, body) in pages:
    result.add("\n**" & title & "**\n")
    for line in body.splitLines():
      result.add(line & "\n")

func buildWeComStatusMd*(statusText: string): string =
  ## Wraps the plain-text status in a WeCom markdown card.
  "## 📊 Status\n" & statusText

func buildWeComDoctorMd*(reportText: string): string =
  "## 🩺 Doctor\n" & reportText

func buildWeComPingMd*(pingText: string): string =
  let color = if "error" in pingText: "warning" else: "info"
  "## 🏓 Ping\n<font color=\"" & color & "\">" & pingText & "</font>"

func buildWeComMycodeM*(codeText: string): string =
  "## 🔗 Link Code\n" & codeText

func buildWeComMemoryMd*(memText: string): string =
  "## 🧠 Memórias\n" & memText

# ── Reply helpers ─────────────────────────────────────────────────────────────

proc wcReply(wcAdapter: var WeComAdapter; userId: UserId; text: string; logger: Logger) =
  wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: text)).isOkOr:
    logger.error("wc send failed for user=" & $userId & " reason=" & error)

proc wcMd(wcAdapter: var WeComAdapter; userId: UserId; md: string; logger: Logger) =
  wcAdapter.sendMarkdown(userId, md).isOkOr:
    logger.warn("wc sendMarkdown failed for user=" & $userId & " reason=" & error & " — falling back to text")
    ## Fallback to plain text if markdown fails
    wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: md)).isOkOr:
      logger.error("wc send text fallback failed for user=" & $userId & " reason=" & error)

proc presentWeComReply(wcAdapter: var WeComAdapter; userId: UserId;
                       reply: CommandReply; logger: Logger) =
  ## WeCom renders diagnostic topics as markdown cards; the rest as text.
  if not reply.shouldSend:
    return
  case reply.topic
  of rtAbout, rtDoctor:
    wcMd(wcAdapter, userId, buildWeComDoctorMd(reply.text), logger)
  of rtLinkCode:
    wcMd(wcAdapter, userId, buildWeComMycodeM(reply.text), logger)
  of rtHelp:
    wcMd(wcAdapter, userId, buildWeComHelpMd(), logger)
  of rtMemory:
    wcMd(wcAdapter, userId, buildWeComMemoryMd(reply.text), logger)
  of rtPing:
    wcMd(wcAdapter, userId, buildWeComPingMd(reply.text), logger)
  of rtStatus:
    wcMd(wcAdapter, userId, buildWeComStatusMd(reply.text), logger)
  else:
    wcReply(wcAdapter, userId, reply.text, logger)

# ── Main drain ────────────────────────────────────────────────────────────────

proc drainWeComEvents*(wcAdapter: var WeComAdapter;
                       wecomCorpId: string;
                       sm: var SessionManager;
                       env: ChannelRuntimeEnv;
                       msgSeq: var int;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                       logger: Logger) =
  if wecomCorpId.len == 0:
    return

  var (hasEvent, event) = wcAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and (event.content |> strip).len > 0:
      let auth = authorizeInbound(sm, wcAdapter.resolver.identityGate(), ckWeCom,
                                  event.fromUser, event.content)
      if not auth.allowed:
        logger.warn("wecom: unauthorized message from " &
                    (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = wcAdapter.tryRecvEvent()
        continue
      let userId = auth.userId
      let approvalReply = tryHandleApprovalInput(userId, event.content)
      if approvalReply.isSome:
        wcMd(wcAdapter, userId, approvalReply.get, logger)
        (hasEvent, event) = wcAdapter.tryRecvEvent()
        continue
      let inbound = InboundMessage(
        userId:    userId,
        channel:   ckWeCom,
        channelId: event.msgId,
        text:      event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckWeCom, text: event.content))
      let outcome = dispatchCommand(env.commands, sm, msgSeq,
          commandRequest(command, userId, ckWeCom, event.msgId, event.fromUser,
                         wcAdapter.resolver))
      case outcome.kind
      of cokFallback:
        handleSessionFallback(inbound)
      of cokAccepted:
        discard
      of cokReply:
        presentWeComReply(wcAdapter, userId, outcome.reply, logger)
    (hasEvent, event) = wcAdapter.tryRecvEvent()
