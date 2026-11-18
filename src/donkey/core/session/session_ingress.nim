## Pure session ingress decisions.
## This module knows nothing about queues, adapters or runtime wiring.

import ../types

type
  SessionRuntimeSignature* = distinct string

  SessionIngressState* = object
    hasSession*:       bool
    awaitingAsk*:      bool
    lastInboundAtMs*:  int64
    currentSignature*: SessionRuntimeSignature

  SessionIngressRequest* = object
    userId*:         UserId
    state*:          SessionIngressState
    nextSignature*:  SessionRuntimeSignature

  SessionIngressActionKind* = enum
    siaStartNewSession
    siaReuseSessionRuntime
    siaRebuildSessionRuntime

  SessionIngressTarget* = enum
    sitActorInbox
    sitAskInbox

  SessionIngressDecision* = object
    actionKind*:          SessionIngressActionKind
    target*:              SessionIngressTarget
    shouldRecordChannel*: bool
    cancelsAsk*:          bool ## abandon the open ask before enqueueing

func `$`*(signature: SessionRuntimeSignature): string {.borrow.}
func `==`*(a, b: SessionRuntimeSignature): bool {.borrow.}

func decideSessionIngress*(request: SessionIngressRequest;
                           answerableAsk = true): SessionIngressDecision =
  result.shouldRecordChannel = true
  if not request.state.hasSession:
    result.actionKind = siaStartNewSession
    result.target = sitActorInbox
    return

  if request.state.currentSignature != request.nextSignature:
    result.actionKind = siaRebuildSessionRuntime
    result.target = sitActorInbox
    return

  result.actionKind = siaReuseSessionRuntime
  if not request.state.awaitingAsk:
    result.target = sitActorInbox
  elif answerableAsk:
    result.target = sitAskInbox
  else:
    ## A request that cannot answer (an API turn carries no conversational
    ## text for the question) must not be delivered as the answer. Cancelling
    ## the ask lets its waiting turn end instead of swallowing this one.
    result.target = sitActorInbox
    result.cancelsAsk = true

func startsSessionRuntime*(decision: SessionIngressDecision): bool =
  decision.actionKind in {siaStartNewSession, siaRebuildSessionRuntime}

func rebuildsSessionRuntime*(decision: SessionIngressDecision): bool =
  decision.actionKind == siaRebuildSessionRuntime

func startsNewSession*(decision: SessionIngressDecision): bool =
  decision.actionKind == siaStartNewSession
