## Discord presentation of dispatcher outcomes, through a recording sink:
##   - every interaction gets exactly one initial response, whatever the outcome;
##   - requester-only replies are ephemeral on interactions and go by DM on
##     text events, and are never posted in the channel, even when the DM fails.

import std/[json, unittest]
import donkey/core/log
import donkey/core/pipeops
import donkey/core/commands/command_routing
import donkey/domain/message
import donkey/app/command_dispatch
import donkey/adapters/channel/discord
import donkey/adapters/channel/discord_runtime

type
  Call = object
    interaction: bool
    private:     bool
    ephemeral:   bool
    text:        string
  Recorder = ref object
    calls: seq[Call]
    dmFails: bool

proc sink(r: Recorder): DiscordReplySink =
  DiscordReplySink(
    respond: proc(event: DiscordRawEvent; title, text: string; color: int;
                  ephemeral: bool): Result[void, string] {.gcsafe.} =
      {.cast(gcsafe).}:
        r.calls.add(Call(interaction: true, ephemeral: ephemeral, text: text))
      ok(),
    post: proc(event: DiscordRawEvent; userId: UserId; text: string;
               private: bool): Result[void, string] {.gcsafe.} =
      {.cast(gcsafe).}:
        if private and r.dmFails:
          return err("cannot DM this user")
        r.calls.add(Call(private: private, text: text))
      ok(),
  )

let slash = DiscordRawEvent(kind: deMessage, discordUserId: "42",
                            content: "/mycode", channelId: "guild-chan",
                            interactionId: "i-1", interactionToken: "tok")
let textEvent = DiscordRawEvent(kind: deMessage, discordUserId: "42",
                                content: "/mycode", channelId: "guild-chan")
let logger = newLogger("t.discord")
let uid = UserId("u-1")

proc outcomes(): seq[CommandOutcome] =
  @[fallback(), accepted(cmdStop),
    replied(rtLinkCode, "code ABC123"), replied(rtAbout, "about"),
    replied(rtUnsupported, UnsupportedCommandText),
    replied(rtNoSession, noSessionText(cmdCompact))]

proc runTests*() =
  suite "discord command replies: interaction acknowledgement":
    test "every outcome kind produces exactly one interaction response":
      for o in outcomes():
        let r = Recorder()
        presentDiscordOutcome(sink(r), slash, uid, o, logger)
        check r.calls.len == 1
        check r.calls[0].interaction

    test "an accepted task is acknowledged ephemerally":
      let r = Recorder()
      presentDiscordOutcome(sink(r), slash, uid, accepted(cmdCompact), logger)
      check r.calls[0].ephemeral
      check r.calls[0].text == acceptedText(cmdCompact)

  suite "discord command replies: requester-only visibility":
    test "a link code on an interaction is ephemeral":
      let r = Recorder()
      presentDiscordOutcome(sink(r), slash, uid, replied(rtLinkCode, "code"), logger)
      check r.calls.len == 1
      check r.calls[0].ephemeral

    test "a public reply on an interaction is not ephemeral":
      let r = Recorder()
      presentDiscordOutcome(sink(r), slash, uid, replied(rtAbout, "about"), logger)
      check not r.calls[0].ephemeral

    test "requester-only replies to a text command go by DM, never the channel":
      for topic in [rtLinkCode, rtContinue, rtDoctor, rtMemory, rtWhoami]:
        let r = Recorder()
        presentDiscordOutcome(sink(r), textEvent, uid, replied(topic, "secret"), logger)
        check r.calls.len == 1
        check r.calls[0].private
        check not r.calls[0].interaction

    test "a failed DM is not posted publicly as a fallback":
      let r = Recorder(dmFails: true)
      presentDiscordOutcome(sink(r), textEvent, uid, replied(rtLinkCode, "secret"), logger)
      check r.calls.len == 0

    test "public replies to a text command stay in the channel":
      let r = Recorder()
      presentDiscordOutcome(sink(r), textEvent, uid, replied(rtStatus, "status"), logger)
      check r.calls.len == 1
      check not r.calls[0].private

    test "unsupported text commands stay silent":
      let r = Recorder()
      presentDiscordOutcome(sink(r), textEvent, uid,
                            replied(rtUnsupported, UnsupportedCommandText), logger)
      check r.calls.len == 0

    test "the ephemeral flag is part of the interaction payload":
      check interactionMessageData("x", ephemeral = true)["flags"].getInt ==
        DiscordEphemeralFlag
      check not interactionMessageData("x", ephemeral = false).hasKey("flags")

when isMainModule:
  runTests()
