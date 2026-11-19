import std/unittest
import donkey/core/session/session_ingress
import donkey/core/types

proc runTests*() =
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

    test "an api request cancels the pending ask instead of answering it":
      ## A7: an orphaned ask reservation expires, then an API request from the
      ## same user arrives. Answering it with the previous turn's text hands the
      ## wrong correlation to both turns: the old one replies with a stale token
      ## and the new one never runs.
      let decision = decideSessionIngress(SessionIngressRequest(
        userId: UserId("u-api-ask"),
        state: SessionIngressState(
          hasSession: true,
          awaitingAsk: true,
          currentSignature: SessionRuntimeSignature("sig-a"),
        ),
        nextSignature: SessionRuntimeSignature("sig-a"),
        ),
        answerableAsk = false)
      check decision.actionKind == siaReuseSessionRuntime
      check decision.target == sitActorInbox
      check decision.cancelsAsk

    test "a channel reply to an open ask keeps answering it":
      let decision = decideSessionIngress(SessionIngressRequest(
        userId: UserId("u-chan-ask"),
        state: SessionIngressState(
          hasSession: true,
          awaitingAsk: true,
          currentSignature: SessionRuntimeSignature("sig-a"),
        ),
        nextSignature: SessionRuntimeSignature("sig-a"),
        ))
      check decision.target == sitAskInbox
      check not decision.cancelsAsk

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

when isMainModule:
  runTests()
