## ChannelPort contract + pure helpers — pipeops pipeline tests.
## Demonstrates |> (countInbound), |>-> (filterInbound), >>= (validateOutbound).

import std/[strutils, unittest]
import donkey/domain/message
import donkey/ports/channel
import donkey/core/pipeops

# ── mock adapter satisfying ChannelPort concept ───────────────────────────────

type MockChannel = object
  sent: seq[OutboundMessage]

proc send(c: MockChannel; msg: OutboundMessage): Result[void, string] =
  ok()

proc receive(vc: var MockChannel): Result[seq[InboundMessage], string] =
  ok(@[InboundMessage(userId: UserId("u1"), text: "hello", channel: ckTelegram)])

proc ack(c: MockChannel; id: string) = discard

# ── concept satisfaction ───────────────────────────────────────────────────────

suite "channel port — concept":

  test "MockChannel satisfies ChannelPort concept":
    ## Compile-time proof: MockChannel implements ChannelPort.
    ## If this test file compiles, the concept is satisfied.
    var ch = MockChannel()
    let r = ch.receive()
    check r.isOk
    let s = ch.send(OutboundMessage(userId: UserId("u1"), text: "hi",
                                    channel: ckTelegram))
    check s.isOk

  test "send returns ok on success":
    let ch = MockChannel()
    let r = ch.send(OutboundMessage(userId: UserId("u2"), text: "ping",
                                    channel: ckTelegram))
    check r.isOk

  test "receive returns ok with inbound messages":
    var ch = MockChannel()
    let r = ch.receive()
    check r.isOk
    check r.get().len == 1
    check r.get()[0].text == "hello"

# ── filterInbound — |>-> ──────────────────────────────────────────────────────

suite "channel port — filterInbound (|>->)":

  let msgs = @[
    InboundMessage(userId: UserId("alice"), text: "a1", channel: ckTelegram),
    InboundMessage(userId: UserId("bob"),   text: "b1", channel: ckTelegram),
    InboundMessage(userId: UserId("alice"), text: "a2", channel: ckTelegram),
  ]

  test "filters messages for alice via |>->":
    let got = msgs |>-> filterInbound(UserId("alice"))
    check got.len == 2
    check got[0].text == "a1"
    check got[1].text == "a2"

  test "filters messages for bob via |>->":
    let got = msgs |>-> filterInbound(UserId("bob"))
    check got.len == 1
    check got[0].text == "b1"

  test "returns empty seq for unknown user":
    let got = msgs |>-> filterInbound(UserId("carol"))
    check got.len == 0

  test "filterInbound on empty seq returns empty":
    let empty: seq[InboundMessage] = @[]
    let got = empty |>-> filterInbound(UserId("alice"))
    check got.len == 0

  test "filter then count chains |>-> and |>":
    let count = (msgs |>-> filterInbound(UserId("alice"))) |> countInbound
    check count == 2

# ── countInbound — |> ─────────────────────────────────────────────────────────

suite "channel port — countInbound (|>)":

  test "counts all inbound messages via |>":
    let msgs = @[
      InboundMessage(userId: UserId("u1"), text: "x", channel: ckTelegram),
      InboundMessage(userId: UserId("u2"), text: "y", channel: ckTelegram),
    ]
    check msgs |> countInbound == 2

  test "counts zero for empty seq":
    let empty: seq[InboundMessage] = @[]
    check empty |> countInbound == 0

  test "counts single message":
    let msgs = @[InboundMessage(userId: UserId("u1"), text: "solo",
                                channel: ckTelegram)]
    check msgs |> countInbound == 1

# ── validateOutbound — >>= ────────────────────────────────────────────────────

suite "channel port — validateOutbound (>>=)":

  proc secondValidation(msg: OutboundMessage): Result[OutboundMessage, string]
      {.gcsafe, raises: [].} =
    ## Stub second step in a >>= chain — checks userId non-empty.
    if $msg.userId == "":
      err("userId is empty")
    else:
      ok(msg)

  test "ok message passes >>= chain":
    let msg = OutboundMessage(userId: UserId("u1"), text: "hello",
                              channel: ckTelegram)
    let r = Result[OutboundMessage, string].ok(msg) >>= validateOutbound
    check r.isOk
    check r.get().text == "hello"

  test "empty text message fails validateOutbound via >>=":
    let msg = OutboundMessage(userId: UserId("u1"), text: "",
                              channel: ckTelegram)
    let r = Result[OutboundMessage, string].ok(msg) >>= validateOutbound
    check r.isErr
    check r.error.contains("empty text")

  test "two-step >>= chain: validateOutbound >>= secondValidation":
    let msg = OutboundMessage(userId: UserId("u1"), text: "hi",
                              channel: ckTelegram)
    let r = Result[OutboundMessage, string].ok(msg) >>=
            validateOutbound >>= secondValidation
    check r.isOk

  test "chain short-circuits on first error":
    let msg = OutboundMessage(userId: UserId("u1"), text: "",
                              channel: ckTelegram)
    let r = Result[OutboundMessage, string].ok(msg) >>=
            validateOutbound >>= secondValidation
    check r.isErr
    check r.error.contains("empty text")
