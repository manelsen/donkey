## Tests for domain/channels/line_policy.nim — pure LINE replay cache and
## inbound policy. Signature/MAC verification belongs to
## `core/security/webhook_auth` (US-003) and is not tested here.
##
## Protocol facts:
##   - there is no signed timestamp, so the only replay defence is
##     `webhookEventId` dedupe bounded to 1000 entries; we keep entries for 24 h
##     as a conservative margin over LINE redelivery (PRD §1, §9);
##   - groups/rooms are default-deny through `LINE_ALLOWED_GROUPS`: unlike the
##     generic `GroupGate` (empty = allow every group), LINE denies when the
##     list is empty (PRD §9, US-006);
##   - identity is the speaker (`source.userId`); the outbound destination is
##     the conversation (`chatId`), never the speaker in a group.
##
## No I/O, no clock: `nowSec` is always supplied by the caller.

import std/unittest
import donkey/domain/channels/line_policy
import donkey/domain/channels/line_pure
import donkey/domain/message

proc event(eventId = "evt-1"; senderId = "U1"; chatId = "U1";
           sourceKind = lskUser; contentKind = lckText;
           mode = lmActive; text = "hi"): LineParseResult =
  LineParseResult(
    senderId: senderId,
    chatId: chatId,
    sourceKind: sourceKind,
    contentKind: contentKind,
    mode: mode,
    text: text,
    eventId: eventId,
  )

proc runTests*() =
  suite "LineSignatureHeader":
    test "the header name is the LINE one":
      check LineSignatureHeader == "X-Line-Signature"

  # ── Replay cache ──────────────────────────────────────────────────────────────

  suite "LineReplayCache — decision and mutation are separate":
    test "a fresh cache accepts and replayDecision does not mutate":
      var cache = LineReplayCache()
      check replayDecision(cache, "evt-1", 1_000'i64)
      ## The decision alone must not record: a second call is still a first sight.
      check replayDecision(cache, "evt-1", 1_000'i64)
      check replayCacheLen(cache) == 0

    test "recording an event makes its duplicate a replay":
      var cache = LineReplayCache()
      check replayDecision(cache, "evt-1", 1_000'i64)
      recordEvent(cache, "evt-1", 1_000'i64)
      check replayCacheLen(cache) == 1
      check not replayDecision(cache, "evt-1", 1_001'i64)
      check replayDecision(cache, "evt-2", 1_001'i64)

    test "recording the same event twice keeps a single entry":
      var cache = LineReplayCache()
      recordEvent(cache, "evt-1", 1_000'i64)
      recordEvent(cache, "evt-1", 1_001'i64)
      check replayCacheLen(cache) == 1
      check not replayDecision(cache, "evt-1", 1_002'i64)

  suite "LineReplayCache — TTL":
    test "the TTL is 24 hours":
      check LineReplayTtlSec == 86_400

    test "an event is a duplicate for 24 h and accepted afterwards":
      var cache = LineReplayCache()
      recordEvent(cache, "evt-1", 10_000'i64)
      check not replayDecision(cache, "evt-1", 10_000'i64 + 86_399)
      check replayDecision(cache, "evt-1", 10_000'i64 + 86_400)

    test "an expired entry is pruned when a new event is recorded":
      var cache = LineReplayCache()
      recordEvent(cache, "evt-1", 0'i64)
      recordEvent(cache, "evt-2", 86_400'i64)
      check replayCacheLen(cache) == 1
      check replayDecision(cache, "evt-1", 86_400'i64)

    test "re-recording a duplicate does not extend its TTL":
      var cache = LineReplayCache()
      recordEvent(cache, "evt-1", 0'i64)
      recordEvent(cache, "evt-1", 80_000'i64)
      check replayDecision(cache, "evt-1", 86_400'i64)

  suite "LineReplayCache — bound and empty ids":
    test "the bound is 1000 events":
      check LineReplayMaxEvents == 1_000

    test "the oldest entry is evicted at the bound":
      var cache = LineReplayCache()
      for i in 0 ..< LineReplayMaxEvents:
        recordEvent(cache, "evt-" & $i, 0'i64)
      check replayCacheLen(cache) == LineReplayMaxEvents
      check not replayDecision(cache, "evt-0", 0'i64)
      recordEvent(cache, "evt-new", 0'i64)
      check replayCacheLen(cache) == LineReplayMaxEvents
      ## evt-0 was the oldest; it is gone and therefore a first sight again.
      check replayDecision(cache, "evt-0", 0'i64)
      check not replayDecision(cache, "evt-new", 0'i64)

    test "an empty event id is never a duplicate and never cached":
      var cache = LineReplayCache()
      check replayDecision(cache, "", 0'i64)
      recordEvent(cache, "", 0'i64)
      recordEvent(cache, "", 1'i64)
      check replayCacheLen(cache) == 0
      check replayDecision(cache, "", 2'i64)

    test "a duplicate at the eviction bound does not evict a legitimate entry":
      var cache = LineReplayCache()
      for i in 0 ..< LineReplayMaxEvents:
        recordEvent(cache, "evt-" & $i, 0'i64)
      check replayCacheLen(cache) == LineReplayMaxEvents
      ## Re-recording an id that is already present must be a no-op: if eviction
      ## ran before the duplicate check, the oldest entry would be lost.
      recordEvent(cache, "evt-500", 0'i64)
      check replayCacheLen(cache) == LineReplayMaxEvents
      check not replayDecision(cache, "evt-500", 0'i64)
      check not replayDecision(cache, "evt-0", 0'i64)

    test "a clock rollback does not resurrect a recorded event":
      var cache = LineReplayCache()
      recordEvent(cache, "evt-1", 10_000'i64)
      ## A timestamp earlier than the recorded one is clock skew, not expiry: a
      ## future-dated record stays valid and is still a duplicate.
      check not replayDecision(cache, "evt-1", 9_999'i64)
      check not replayDecision(cache, "evt-1", 0'i64)

  # ── Inbound policy ────────────────────────────────────────────────────────────

  suite "LINE group policy — default deny":
    test "an empty allowed-groups list denies groups and rooms":
      ## Deliberate deviation from GroupGate, whose empty list allows every chat.
      check not lineGroupAllowed(@[], lskGroup, "C1")
      check not lineGroupAllowed(@[], lskRoom, "R1")

    test "a listed group/room is allowed, another is not":
      check lineGroupAllowed(@["C1"], lskGroup, "C1")
      check not lineGroupAllowed(@["C1"], lskGroup, "C2")
      check lineGroupAllowed(@["R1"], lskRoom, "R1")
      check not lineGroupAllowed(@["C1"], lskGroup, "")

    test "group ids are matched exactly, not by prefix":
      check not lineGroupAllowed(@["C1"], lskGroup, "C1x")
      check not lineGroupAllowed(@["C1"], lskRoom, "C1x")

    test "DMs are not gated by the group list":
      check lineGroupAllowed(@[], lskUser, "U1")

    test "an unknown source has no allowed conversation":
      check not lineGroupAllowed(@["C1"], lskUnknown, "")

  suite "LINE user policy":
    test "an empty allowed-users list allows every speaker":
      check lineUserAllowed(@[], "U1")
      check lineUserAllowed(@[], "")

    test "a non-empty list requires an exact match":
      check lineUserAllowed(@["U1"], "U1")
      check not lineUserAllowed(@["U1"], "U2")
      check not lineUserAllowed(@["U1"], "")

    test "user ids are matched exactly, not by prefix":
      check not lineUserAllowed(@["U1"], "U10")

  suite "decideLineEvent — discards":
    test "a standby event is discarded even when everything else is fine":
      check decideLineEvent(LinePolicy(), event(mode = lmStandby)) == ledDropStandby
      check decideLineEvent(LinePolicy(allowedGroups: @["C1"]),
                            event(mode = lmStandby, sourceKind = lskGroup,
                                  senderId = "U1", chatId = "C1")) ==
        ledDropStandby

    test "non-text content is discarded":
      check decideLineEvent(LinePolicy(), event(contentKind = lckNonText)) ==
        ledDropNonText

    test "unknown content is discarded":
      check decideLineEvent(LinePolicy(), event(contentKind = lckUnknown)) ==
        ledDropUnknownContent

    test "standby wins over non-text so the runtime never answers it":
      check decideLineEvent(LinePolicy(),
                            event(mode = lmStandby, contentKind = lckNonText)) ==
        ledDropStandby

    test "an unknown source or missing speaker is discarded":
      check decideLineEvent(LinePolicy(), event(sourceKind = lskUnknown)) ==
        ledDropUnknownSource
      check decideLineEvent(LinePolicy(), event(senderId = "")) ==
        ledDropUnknownSource

    test "a group outside the allowlist is discarded, an empty list denies all":
      let group = event(sourceKind = lskGroup, senderId = "U1", chatId = "C1")
      check decideLineEvent(LinePolicy(), group) == ledDropGroupNotAllowed
      check decideLineEvent(LinePolicy(allowedGroups: @["C2"]), group) ==
        ledDropGroupNotAllowed
      check decideLineEvent(LinePolicy(allowedGroups: @["C1"]), group) ==
        ledAccept

    test "a speaker outside the user allowlist is discarded":
      check decideLineEvent(LinePolicy(allowedUsers: @["U2"]),
                            event(senderId = "U1")) == ledDropUserNotAllowed
      check decideLineEvent(LinePolicy(allowedUsers: @["U1"]),
                            event(senderId = "U1")) == ledAccept

    test "when both gates fail, the group gate is reported first":
      let both = event(sourceKind = lskGroup, senderId = "U10", chatId = "C1x")
      let policy = LinePolicy(allowedGroups: @["C1"], allowedUsers: @["U1"])
      check decideLineEvent(policy, both) == ledDropGroupNotAllowed

    test "allowlist matching is exact rather than prefix-based":
      check decideLineEvent(LinePolicy(allowedGroups: @["C1"]),
                            event(sourceKind = lskGroup, senderId = "U1",
                                  chatId = "C1x")) == ledDropGroupNotAllowed
      check decideLineEvent(LinePolicy(allowedUsers: @["U1"]),
                            event(senderId = "U10")) == ledDropUserNotAllowed

  suite "decideLineEvent — accepts":
    test "a DM text event is accepted with an empty policy":
      check decideLineEvent(LinePolicy(), event()) == ledAccept

    test "a group text event from an allowed group and user is accepted":
      let policy = LinePolicy(allowedGroups: @["C1"], allowedUsers: @["U1"])
      check decideLineEvent(policy, event(sourceKind = lskGroup,
                                          senderId = "U1",
                                          chatId = "C1")) == ledAccept

  # ── Identity / destination mapping (toInbound contract, US-001) ──────────────

  suite "lineRouting keeps identity and destination separate":
    test "a DM identifies and replies to the speaker":
      let route = lineRouting(event())
      check route.identityId == "U1"    ## identity: the speaker
      check route.replyTarget == "U1"   ## outbound destination: the conversation

    test "a group identifies the speaker and replies to the group":
      let route = lineRouting(event(sourceKind = lskGroup,
                                    senderId = "U-speaker",
                                    chatId = "C-group"))
      check route.identityId == "U-speaker"  ## identity: the speaker
      check route.replyTarget == "C-group"   ## outbound destination: the group

  suite "toInbound uses line_pure's mapping":
    test "a DM keeps the speaker as raw identity and channel target":
      let inbound = toInbound(event(), UserId("resolved-user"))
      check inbound.channel == ckLine
      check inbound.userId == UserId("resolved-user")
      check inbound.rawChannelId == "U1"   ## identity: the speaker
      check inbound.channelId == "U1"      ## reply target: the conversation

    test "a group keeps the speaker as identity and the group as target":
      let r = event(sourceKind = lskGroup, senderId = "U-speaker", chatId = "C-group")
      let inbound = toInbound(r, UserId("resolved-user"))
      check inbound.channel == ckLine
      check inbound.rawChannelId == "U-speaker"  ## identity: the speaker
      check inbound.channelId == "C-group"       ## outbound destination: the group

when isMainModule:
  runTests()
