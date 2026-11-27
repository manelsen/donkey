## gateway_drainer.nim — Channel gateway event draining and dispatch coordinator.
##
## Application layer coordinator for draining inbound events across chat gateways
## (Telegram, Discord, WeChat, WeCom, QQ, Feishu, DingTalk, Matrix, WhatsApp).
##
## Strict hexagonal architecture: no direct imports from adapters/.
## Coordination occurs via functional ports and callbacks.

import std/[strutils, tables, times]
import ../core/types
import ../core/log
import ../domain/message
import ../infra/supervisor

type
  GatewayDrainProc* = proc(): bool {.gcsafe.}

  GatewayFallbackHandler* = proc(msg: InboundMessage) {.gcsafe.}

  DrainGuard = object
    sup: Supervised
    pausedUntil: int64
    failing: bool

  DrainGuards* = ref object
    ## E12.2: each channel's drain under the supervisor: one that raises is
    ## paused for the supervisor's wait, and the other channels go on.
    guards: Table[ChannelKind, DrainGuard]
    log: Logger

  GatewayDrainer* = object
    guards*:         DrainGuards
    drainDiscord*:   GatewayDrainProc
    drainWeCom*:     GatewayDrainProc
    drainWeChat*:    GatewayDrainProc
    drainQQ*:        GatewayDrainProc
    drainFeishu*:    GatewayDrainProc
    drainSlack*:     GatewayDrainProc
    drainDingTalk*:  GatewayDrainProc
    drainLine*:      GatewayDrainProc
    drainMatrix*:    GatewayDrainProc
    drainTelegram*:  GatewayDrainProc
    drainWhatsApp*:  GatewayDrainProc
    drainEmail*:     GatewayDrainProc
    drainSignal*:    GatewayDrainProc
    drainTeams*:     GatewayDrainProc
    drainMattermost*: GatewayDrainProc
    drainSms*:       GatewayDrainProc
    drainIrc*:       GatewayDrainProc
    drainGoogleChat*: GatewayDrainProc
    drainNtfy*:      GatewayDrainProc
    drainSimplex*:   GatewayDrainProc
    drainBlueBubbles*: GatewayDrainProc

func initGatewayDrainer*(
  drainDiscord:   GatewayDrainProc = nil,
  drainWeCom:     GatewayDrainProc = nil,
  drainWeChat:    GatewayDrainProc = nil,
  drainQQ:        GatewayDrainProc = nil,
  drainFeishu:    GatewayDrainProc = nil,
  drainSlack:     GatewayDrainProc = nil,
  drainDingTalk:  GatewayDrainProc = nil,
  drainLine:      GatewayDrainProc = nil,
  drainMatrix:    GatewayDrainProc = nil,
  drainTelegram:  GatewayDrainProc = nil,
  drainWhatsApp:  GatewayDrainProc = nil,
  drainEmail:     GatewayDrainProc = nil,
  drainSignal:    GatewayDrainProc = nil,
  drainTeams:     GatewayDrainProc = nil,
  drainMattermost: GatewayDrainProc = nil,
  drainSms:       GatewayDrainProc = nil,
  drainIrc:       GatewayDrainProc = nil,
  drainGoogleChat: GatewayDrainProc = nil,
  drainNtfy: GatewayDrainProc = nil,
  drainSimplex: GatewayDrainProc = nil,
  drainBlueBubbles: GatewayDrainProc = nil,
): GatewayDrainer =
  ## Initializes a GatewayDrainer with channel drain callbacks.
  GatewayDrainer(
    guards:         DrainGuards(log: newLogger("gateway.drain")),
    drainDiscord:   drainDiscord,
    drainWeCom:     drainWeCom,
    drainWeChat:    drainWeChat,
    drainQQ:        drainQQ,
    drainFeishu:    drainFeishu,
    drainSlack:     drainSlack,
    drainDingTalk:  drainDingTalk,
    drainLine:      drainLine,
    drainMatrix:    drainMatrix,
    drainTelegram:  drainTelegram,
    drainWhatsApp:  drainWhatsApp,
    drainEmail:     drainEmail,
    drainSignal:    drainSignal,
    drainTeams:     drainTeams,
    drainMattermost: drainMattermost,
    drainSms:       drainSms,
    drainIrc:       drainIrc,
    drainGoogleChat: drainGoogleChat,
    drainNtfy: drainNtfy,
    drainSimplex: drainSimplex,
    drainBlueBubbles: drainBlueBubbles,
  )

# ── Polling & Batch Draining Helpers ──────────────────────────────────────────

proc drainPolledGateway*(
  channel: ChannelKind;
  pollEvent: proc(): (bool, InboundMessage) {.gcsafe.};
  fallbackHandler: GatewayFallbackHandler;
  log: Logger = Logger();
  authorize: proc(userId: UserId): bool {.gcsafe.} = nil
): int {.gcsafe.} =
  ## Drains an event queue channel (e.g. DingTalk, Matrix, or test mocks).
  ## Loops until pollEvent returns hasEvent=false.
  ## Dispatches valid messages (non-empty text or mediaUrl) to fallbackHandler.
  ## Events rejected by `authorize` are consumed (queue advances) but never
  ## dispatched, so an unauthorized sender cannot reach the application layer.
  ## Returns number of dispatched messages.
  if pollEvent == nil:
    return 0

  var (hasEvent, msg) = pollEvent()
  while hasEvent:
    if msg.text.strip.len > 0 or msg.mediaUrl.len > 0:
      if authorize != nil and not authorize(msg.userId):
        log.warn("gateway drainer: unauthorized message on " & $channel &
                 " from " & $msg.userId)
      else:
        if fallbackHandler != nil:
          fallbackHandler(msg)
        result.inc
    (hasEvent, msg) = pollEvent()

proc drainBatchGateway*(
  channel: ChannelKind;
  pollBatch: proc(): seq[InboundMessage] {.gcsafe.};
  dispatchHandler: proc(msg: InboundMessage): bool {.gcsafe.};
  fallbackHandler: GatewayFallbackHandler;
  log: Logger = Logger()
): int {.gcsafe.} =
  ## Drains a batch channel (e.g. Telegram or test mocks).
  ## Polls batch of messages, tries primary dispatchHandler, falls back to fallbackHandler.
  ## Returns number of processed messages.
  if pollBatch == nil:
    return 0

  let msgs = pollBatch()
  for msg in msgs:
    result.inc
    if dispatchHandler != nil and dispatchHandler(msg):
      discard
    elif fallbackHandler != nil:
      fallbackHandler(msg)

# ── Parameterized Channel Procs ───────────────────────────────────────────────

proc drainDingTalkGateway*(
  configured: bool;
  pollEvent: proc(): (bool, InboundMessage) {.gcsafe.};
  fallbackHandler: GatewayFallbackHandler;
  log: Logger = Logger();
  authorize: proc(userId: UserId): bool {.gcsafe.} = nil
): int {.discardable, gcsafe.} =
  ## Drains DingTalk event queue if configured.
  if not configured or pollEvent == nil:
    return 0
  drainPolledGateway(ckDingTalk, pollEvent, fallbackHandler, log, authorize)

proc drainMatrixGateway*(
  configured: bool;
  pollEvent: proc(): (bool, InboundMessage) {.gcsafe.};
  fallbackHandler: GatewayFallbackHandler;
  log: Logger = Logger();
  authorize: proc(userId: UserId): bool {.gcsafe.} = nil
): int {.discardable, gcsafe.} =
  ## Drains Matrix event queue if configured.
  if not configured or pollEvent == nil:
    return 0
  drainPolledGateway(ckMatrix, pollEvent, fallbackHandler, log, authorize)

proc drainTelegramGateway*(
  configured: bool;
  pollBatch: proc(): seq[InboundMessage] {.gcsafe.};
  dispatchHandler: proc(msg: InboundMessage): bool {.gcsafe.};
  fallbackHandler: GatewayFallbackHandler;
  log: Logger = Logger()
): int {.discardable, gcsafe.} =
  ## Drains Telegram message batch if configured.
  if not configured or pollBatch == nil:
    return 0
  drainBatchGateway(ckTelegram, pollBatch, dispatchHandler, fallbackHandler, log)

proc guarded(drainer: GatewayDrainer; kind: ChannelKind; fn: GatewayDrainProc): bool {.raises: [].} =
  ## One channel's drain under the supervisor (E12.2): an exception pauses
  ## that channel for the supervisor's wait instead of leaving the daemon's
  ## loop and taking every channel down with it.
  if fn == nil: return false
  if drainer.guards == nil:
    ## A drainer built without guards (a test's literal): still never let a
    ## channel's exception out.
    try: return fn()
    except Exception: return false  ## effect boundary: callee raises are unannotated
  let now = int64(epochTime() * 1000)
  var g = drainer.guards.guards.getOrDefault(kind,
            DrainGuard(sup: newSupervised(kind, $kind & " drain")))
  if now < g.pausedUntil:
    return false
  try:
    result = fn()
    if g.failing:
      g.failing = false
      g.sup.started(now)
  except CatchableError as e:
    drainer.guards.log.warn($kind & ": its drain failed: " & e.msg)
    g.failing = true
    g.pausedUntil = now + g.sup.ended(e.msg, ranMs = 0, drainer.guards.log, now = now)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    drainer.guards.log.warn($kind & ": its drain failed: " & e.msg)
    g.failing = true
    g.pausedUntil = now + g.sup.ended(e.msg, ranMs = 0, drainer.guards.log, now = now)
  drainer.guards.guards[kind] = g

proc drainDiscordGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains Discord gateway if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

proc drainWeComGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains WeCom gateway if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

proc drainWeChatGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains WeChat gateway if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

proc drainQQGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains QQ gateway if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

proc drainFeishuGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains Feishu gateway if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

proc drainSlackGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains the Slack webhook event queue if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

proc drainWhatsAppGateway*(
  configured: bool;
  drainFn: proc(): bool {.gcsafe.}
): bool {.discardable, gcsafe.} =
  ## Drains WhatsApp gateway if configured.
  if not configured or drainFn == nil:
    return false
  drainFn()

# ── GatewayDrainer Dispatchers ────────────────────────────────────────────────

proc drainDiscordGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Discord gateway from drainer callback.
  if drainer.drainDiscord != nil:
    result = guarded(drainer, ckDiscord, drainer.drainDiscord)

proc drainWeComGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains WeCom gateway from drainer callback.
  if drainer.drainWeCom != nil:
    result = guarded(drainer, ckWeCom, drainer.drainWeCom)

proc drainWeChatGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains WeChat gateway from drainer callback.
  if drainer.drainWeChat != nil:
    result = guarded(drainer, ckWeChat, drainer.drainWeChat)

proc drainQQGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains QQ gateway from drainer callback.
  if drainer.drainQQ != nil:
    result = guarded(drainer, ckQQ, drainer.drainQQ)

proc drainFeishuGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Feishu gateway from drainer callback.
  if drainer.drainFeishu != nil:
    result = guarded(drainer, ckFeishu, drainer.drainFeishu)

proc drainSlackGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the Slack gateway from the drainer callback.
  if drainer.drainSlack != nil:
    result = guarded(drainer, ckSlack, drainer.drainSlack)

proc drainDingTalkGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains DingTalk gateway from drainer callback.
  if drainer.drainDingTalk != nil:
    result = guarded(drainer, ckDingTalk, drainer.drainDingTalk)

proc drainLineGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the LINE webhook event queue if configured.
  if drainer.drainLine != nil:
    result = guarded(drainer, ckLine, drainer.drainLine)

proc drainMatrixGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Matrix gateway from drainer callback.
  if drainer.drainMatrix != nil:
    result = guarded(drainer, ckMatrix, drainer.drainMatrix)

proc drainTelegramGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Telegram gateway from drainer callback.
  if drainer.drainTelegram != nil:
    result = guarded(drainer, ckTelegram, drainer.drainTelegram)

proc drainWhatsAppGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains WhatsApp gateway from drainer callback.
  if drainer.drainWhatsApp != nil:
    result = guarded(drainer, ckWhatsApp, drainer.drainWhatsApp)

proc drainEmailGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  if drainer.drainEmail != nil:
    result = guarded(drainer, ckEmail, drainer.drainEmail)

proc drainSignalGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  if drainer.drainSignal != nil:
    result = guarded(drainer, ckSignal, drainer.drainSignal)

proc drainMattermostGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the Mattermost socket queue if configured.
  if drainer.drainMattermost != nil:
    result = guarded(drainer, ckMattermost, drainer.drainMattermost)

proc drainSmsGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the SMS webhook queue if configured.
  if drainer.drainSms != nil:
    result = guarded(drainer, ckSms, drainer.drainSms)

proc drainIrcGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the IRC connection's queue if configured.
  if drainer.drainIrc != nil:
    result = guarded(drainer, ckIrc, drainer.drainIrc)

proc drainNtfyGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the ntfy poller's queue if configured (E13.1).
  if drainer.drainNtfy != nil:
    result = guarded(drainer, ckNtfy, drainer.drainNtfy)

proc drainSimplexGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the SimpleX connection's queue if configured (E13.2).
  if drainer.drainSimplex != nil:
    result = guarded(drainer, ckSimplex, drainer.drainSimplex)

proc drainBlueBubblesGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the BlueBubbles poller's queue if configured (E13.3).
  if drainer.drainBlueBubbles != nil:
    result = guarded(drainer, ckBlueBubbles, drainer.drainBlueBubbles)

proc drainGoogleChatGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the Google Chat webhook queue if configured.
  if drainer.drainGoogleChat != nil:
    result = guarded(drainer, ckGoogleChat, drainer.drainGoogleChat)

proc drainTeamsGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the Teams webhook queue if configured.
  if drainer.drainTeams != nil:
    result = guarded(drainer, ckTeams, drainer.drainTeams)

proc drainGatewayEvents*(drainer: GatewayDrainer): int {.discardable, gcsafe.} =
  ## Drains all configured channel gateways in sequence.
  ## Returns the count of active gateways that executed.
  if drainDiscordGateway(drainer): result.inc
  if drainWeComGateway(drainer): result.inc
  if drainWeChatGateway(drainer): result.inc
  if drainFeishuGateway(drainer): result.inc
  if drainSlackGateway(drainer): result.inc
  if drainQQGateway(drainer): result.inc
  if drainDingTalkGateway(drainer): result.inc
  if drainLineGateway(drainer): result.inc
  if drainMatrixGateway(drainer): result.inc
  if drainTelegramGateway(drainer): result.inc
  if drainWhatsAppGateway(drainer): result.inc
  if drainEmailGateway(drainer): result.inc
  if drainSignalGateway(drainer): result.inc
  if drainTeamsGateway(drainer): result.inc
  if drainMattermostGateway(drainer): result.inc
  if drainSmsGateway(drainer): result.inc
  if drainIrcGateway(drainer): result.inc
  if drainGoogleChatGateway(drainer): result.inc
  if drainNtfyGateway(drainer): result.inc
  if drainSimplexGateway(drainer): result.inc
  if drainBlueBubblesGateway(drainer): result.inc
