import std/unittest
import donkey/core/session_ingress
import donkey/core/types

suite "session ingress decisions":

  test "new session starts runtime and targets actor inbox":
    let decision = decideSessionIngress(SessionIngressRequest(
      userId: UserId("u-new"),
      state: SessionIngressState(
        hasSession: false,
        awaitingAsk: false,
        currentSignature: SessionRuntimeSignature(""),
      ),
      nextSignature: SessionRuntimeSignature("sig-a"),
    ))
    check decision.actionKind == siaStartNewSession
    check decision.target == sitActorInbox
    check decision.shouldRecordChannel
    check decision.startsSessionRuntime
    check decision.startsNewSession

  test "unchanged runtime with pending ask targets ask inbox":
    let decision = decideSessionIngress(SessionIngressRequest(
      userId: UserId("u-ask"),
      state: SessionIngressState(
        hasSession: true,
        awaitingAsk: true,
        currentSignature: SessionRuntimeSignature("sig-a"),
      ),
      nextSignature: SessionRuntimeSignature("sig-a"),
    ))
    check decision.actionKind == siaReuseSessionRuntime
    check decision.target == sitAskInbox
    check not decision.startsSessionRuntime

  test "signature drift rebuilds runtime and clears ask redirect":
    let decision = decideSessionIngress(SessionIngressRequest(
      userId: UserId("u-rebuild"),
      state: SessionIngressState(
        hasSession: true,
        awaitingAsk: true,
        currentSignature: SessionRuntimeSignature("sig-a"),
      ),
      nextSignature: SessionRuntimeSignature("sig-b"),
    ))
    check decision.actionKind == siaRebuildSessionRuntime
    check decision.target == sitActorInbox
    check decision.startsSessionRuntime
    check decision.rebuildsSessionRuntime

