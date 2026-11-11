## gateway_drainer.nim — Channel gateway event draining and dispatch coordinator.
##
## Application layer coordinator for draining inbound events across chat gateways
## (Telegram, Discord, WeChat, WeCom, QQ, Feishu, DingTalk, Matrix, WhatsApp).
##
## Strict hexagonal architecture: no direct imports from adapters/.
## Coordination occurs via functional ports and callbacks.

import std/strutils
import ../core/types
import ../core/log
import ../domain/message

type
  GatewayDrainProc* = proc(): bool {.gcsafe.}

  GatewayFallbackHandler* = proc(msg: InboundMessage) {.gcsafe.}

  GatewayDrainer* = object
    drainDiscord*:   GatewayDrainProc
    drainWeCom*:     GatewayDrainProc
    drainWeChat*:    GatewayDrainProc
    drainQQ*:        GatewayDrainProc
    drainFeishu*:    GatewayDrainProc
    drainSlack*:     GatewayDrainProc
    drainDingTalk*:  GatewayDrainProc
    drainMatrix*:    GatewayDrainProc
    drainTelegram*:  GatewayDrainProc
    drainWhatsApp*:  GatewayDrainProc
    drainEmail*:     GatewayDrainProc
    drainSignal*:    GatewayDrainProc

func initGatewayDrainer*(
  drainDiscord:   GatewayDrainProc = nil,
  drainWeCom:     GatewayDrainProc = nil,
  drainWeChat:    GatewayDrainProc = nil,
  drainQQ:        GatewayDrainProc = nil,
  drainFeishu:    GatewayDrainProc = nil,
  drainSlack:     GatewayDrainProc = nil,
  drainDingTalk:  GatewayDrainProc = nil,
  drainMatrix:    GatewayDrainProc = nil,
  drainTelegram:  GatewayDrainProc = nil,
  drainWhatsApp:  GatewayDrainProc = nil,
  drainEmail:     GatewayDrainProc = nil,
  drainSignal:    GatewayDrainProc = nil,
): GatewayDrainer =
  ## Initializes a GatewayDrainer with channel drain callbacks.
  GatewayDrainer(
    drainDiscord:   drainDiscord,
    drainWeCom:     drainWeCom,
    drainWeChat:    drainWeChat,
    drainQQ:        drainQQ,
    drainFeishu:    drainFeishu,
    drainSlack:     drainSlack,
    drainDingTalk:  drainDingTalk,
    drainMatrix:    drainMatrix,
    drainTelegram:  drainTelegram,
    drainWhatsApp:  drainWhatsApp,
    drainEmail:     drainEmail,
    drainSignal:    drainSignal,
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
    result = drainer.drainDiscord()

proc drainWeComGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains WeCom gateway from drainer callback.
  if drainer.drainWeCom != nil:
    result = drainer.drainWeCom()

proc drainWeChatGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains WeChat gateway from drainer callback.
  if drainer.drainWeChat != nil:
    result = drainer.drainWeChat()

proc drainQQGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains QQ gateway from drainer callback.
  if drainer.drainQQ != nil:
    result = drainer.drainQQ()

proc drainFeishuGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Feishu gateway from drainer callback.
  if drainer.drainFeishu != nil:
    result = drainer.drainFeishu()

proc drainSlackGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains the Slack gateway from the drainer callback.
  if drainer.drainSlack != nil:
    result = drainer.drainSlack()

proc drainDingTalkGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains DingTalk gateway from drainer callback.
  if drainer.drainDingTalk != nil:
    result = drainer.drainDingTalk()

proc drainMatrixGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Matrix gateway from drainer callback.
  if drainer.drainMatrix != nil:
    result = drainer.drainMatrix()

proc drainTelegramGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains Telegram gateway from drainer callback.
  if drainer.drainTelegram != nil:
    result = drainer.drainTelegram()

proc drainWhatsAppGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  ## Drains WhatsApp gateway from drainer callback.
  if drainer.drainWhatsApp != nil:
    result = drainer.drainWhatsApp()

proc drainEmailGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  if drainer.drainEmail != nil:
    result = drainer.drainEmail()

proc drainSignalGateway*(drainer: GatewayDrainer): bool {.discardable, gcsafe.} =
  if drainer.drainSignal != nil:
    result = drainer.drainSignal()

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
  if drainMatrixGateway(drainer): result.inc
  if drainTelegramGateway(drainer): result.inc
  if drainWhatsAppGateway(drainer): result.inc
  if drainEmailGateway(drainer): result.inc
  if drainSignalGateway(drainer): result.inc
