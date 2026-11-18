## line_runtime.nim — inbound LINE event drain for the daemon.
##
## The HTTP layer (US-005) only verifies the MAC and enqueues the parsed
## events. This module owns the event loop: `line_policy` decides standby,
## content, source and group/user gates *before* any identity, session or
## pairing work; the replay cache deduplicates `webhookEventId`; only the
## accepted events are routed to the session fallback.
##
## No policy is reimplemented here: group default-deny, exact matching and the
## user allowlist all come from `decideLineEvent`.
##
## The replay cache is a value type whose `recordEvent` rebuilds `entries`, so
## the caller must pass the daemon's single `var lineReplay` — a by-value copy
## would make dedupe a no-op.

import ../../app/inbound_gate
import ../../app/session_manager
import ../../core/commands/command_routing
import ../../core/log
import ../../core/pipeops
import ../../domain/channels/line_policy
import ../../domain/channels/line_pure
import ../../domain/message
import ./common_runtime
import ./line

proc drainLineEvents*(lnAdapter: var LineAdapter;
                      sm: var SessionManager;
                      lineReplay: var LineReplayCache;
                      policy: LinePolicy;
                      nowSec: int64;
                      handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                      log: Logger = newLogger("line.runtime")): int {.gcsafe.} =
  ## Drains the webhook queue until it is empty and returns the number of
  ## events that produced a turn (session fallback or local `/continue`).
  ## Every event is consumed: denied and duplicate events are logged and
  ## dropped, so the drain loop cannot spin on them.
  var (hasEvent, event) = lnAdapter.tryRecvEvent()
  while hasEvent:
    let decision = decideLineEvent(policy, event)
    if decision != ledAccept:
      log.debug("line: dropped event=" & event.eventId & " reason=" & $decision)
      (hasEvent, event) = lnAdapter.tryRecvEvent()
      continue

    if not replayDecision(lineReplay, event.eventId, nowSec):
      log.debug("line: duplicate event=" & event.eventId &
                " cache=" & $replayCacheLen(lineReplay))
      (hasEvent, event) = lnAdapter.tryRecvEvent()
      continue
    recordEvent(lineReplay, event.eventId, nowSec)

    let routing = lineRouting(event)
    let auth = authorizeInbound(
      sm, lnAdapter.resolver.identityGate(), ckLine,
      routing.identityId, event.text, isGroup = false)
    if not auth.allowed:
      log.warn("line: unauthorized message from " &
               (if auth.identified: $auth.userId else: "unidentified sender"))
      (hasEvent, event) = lnAdapter.tryRecvEvent()
      continue

    ## The identity is the speaker; the recorded conversation is the reply
    ## target, so a proactive send answers the group instead of the DM.
    sm.recordChannel(auth.userId, ckLine, routing.replyTarget, persist = false)
    let msg = toInbound(event, auth.userId)

    let command = decideCommandRequest(
      CommandRequest(channel: ckLine, text: msg.text))
    if command.route == crLocal and
       decideLocalCommandAction(command) == lcaContinueLink:
      ## Only `/continue` is local; every other command/text is a session turn.
      let reply = buildContinueResultText(
        lnAdapter.resolver.consumeLinkCode(command.value, ckLine,
                                           routing.identityId))
      lnAdapter.send(OutboundMessage(
        userId:  auth.userId,
        channel: ckLine,
        text:    reply,
        replyTo: routing.replyTarget,
      )).isOkOr:
        log.error("line: send /continue reply failed for user=" &
                  $auth.userId & " reason=" & error)
      inc result
      (hasEvent, event) = lnAdapter.tryRecvEvent()
      continue

    if handleSessionFallback != nil:
      handleSessionFallback(msg)
      inc result
    (hasEvent, event) = lnAdapter.tryRecvEvent()
