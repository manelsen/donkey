## Several Discord bots in one instance (PRD-roadmap E3.4): each bot is its
## own adapter and gateway connection, tagging what it queues with its name;
## a person is the same user on all of them, and everything sent to them goes
## through the bot they wrote to last.

import std/[os, strutils, unittest]
import donkey/adapters/channel/discord
import donkey/adapters/channel/discord_bots
import donkey/adapters/channel/outbound_builder
import donkey/adapters/identity/identity_resolver
import donkey/config/environment
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/bots_pure
import donkey/domain/message

proc tempIds(tag: string): string =
  result = getTempDir() / ("donkey_dc_bots_" & tag & ".tsv")
  removeFile(result)

proc specs(): seq[BotSpec] =
  validateBots(@[
    BotSpec(name: "time", channel: "discord", tokenEnv: "DC_TIME"),
    BotSpec(name: "ops", channel: "discord", tokenEnv: "DC_OPS"),
    BotSpec(name: "suporte", channel: "telegram", tokenEnv: "TG_SUPORTE")])[0]

proc runTests*() =
  suite "discord bots":

    test "one adapter per Discord bot whose token is set; the others are reported":
      let primary = newDiscordAdapter("primary", tempIds("build"))
      let (bots, problems) = buildDiscordBots(specs(), environmentOf({"DC_TIME": "t-tok"}), primary)
      check bots.slots.len == 1
      check bots.slots[0].name == "time" and bots.slots[0].adapter.token == "t-tok"
      check problems.len == 1 and "DC_OPS" in problems[0]

    test "every bot shares the primary's identities and settings, not its DM cursor":
      var primary = newDiscordAdapter("primary", tempIds("ids"), requireMention = true,
                                      allowedChannels = @["g1"])
      let (bots, _) = buildDiscordBots(specs(),
        environmentOf({"DC_TIME": "t", "DC_OPS": "o"}), primary)
      let uid = primary.resolver.resolve(ckDiscord, "42")
      check bots.slots[1].adapter.resolver.resolve(ckDiscord, "42") == uid
      check bots.slots[0].adapter.requireMention
      check bots.slots[0].adapter.allowedChannels == @["g1"]
      check bots.slots[0].adapter.cursor.isNil
      check not primary.cursor.isNil

    test "an event through a bot makes it that person's bot; the default bot takes back":
      var primary = newDiscordAdapter("primary", tempIds("aff"))
      var (bots, _) = buildDiscordBots(specs(),
        environmentOf({"DC_TIME": "t", "DC_OPS": "o"}), primary)
      bots.noteInbound(UserId("u-1"), "ops")
      check adapterFor(addr bots, addr primary, UserId("u-1"))[].token == "o"
      bots.noteInbound(UserId("u-1"), "")
      check adapterFor(addr bots, addr primary, UserId("u-1"))[].token == "primary"

    test "an event's bot is found by name; an unknown one is nil":
      var primary = newDiscordAdapter("primary", tempIds("named"))
      var (bots, _) = buildDiscordBots(specs(), environmentOf({"DC_TIME": "t"}), primary)
      check slotAdapter(addr bots, addr primary, "")[].token == "primary"
      check slotAdapter(addr bots, addr primary, "time")[].token == "t"
      check slotAdapter(addr bots, addr primary, "gone").isNil

    test "more bots than gateways are reported, not left silent":
      let primary = newDiscordAdapter("primary", tempIds("max"))
      var many: seq[BotSpec]
      var vars: seq[(string, string)]
      for i in 0 ..< MaxDiscordGateways + 2:
        many.add BotSpec(name: "b" & $i, channel: "discord", tokenEnv: "DC_B" & $i)
        vars.add ("DC_B" & $i, "tok" & $i)
      let (bots, problems) = buildDiscordBots(validateBots(many)[0],
                                              environmentOf(vars), primary)
      check bots.slots.len == MaxDiscordGateways - 1
      check problems.len == 3
      check "at most" in problems[0]

  suite "discord bots — the outbound port":

    test "each operation for a person goes through that person's adapter":
      var a = newDiscordAdapter("a", tempIds("port"), apiBase = "http://127.0.0.1:9")
      var b = newDiscordAdapter("b", tempIds("port"), apiBase = "http://127.0.0.1:9")
      let pa = addr a
      let pb = addr b
      var asked: seq[string]
      let pick: DiscordPick = proc(userId: UserId): ptr DiscordAdapter {.gcsafe.} =
        {.cast(gcsafe).}:
          asked.add $userId
        if $userId == "u-b": pb else: pa
      let port = discordOutboundPort(pa, pick)
      discard port.send(OutboundMessage(userId: UserId("u-b"), channel: ckDiscord, text: "x"))
      discard port.sendReturnId(OutboundMessage(userId: UserId("u-a"), channel: ckDiscord, text: "x"))
      discard port.editMessage(UserId("u-b"), "1", "x", false)
      discard port.sendKeyboard(UserId("u-b"), "x", @[@[("ok", "ok")]])
      discard port.editKeyboard(UserId("u-b"), "1", "x", @[@[("ok", "ok")]])
      discard port.setMessageReaction(UserId("u-b"), "c", "1", "👍")
      check asked == @["u-b", "u-a", "u-b", "u-b", "u-b", "u-b"]

  suite "discord bots — the gateway tag":

    test "what a gateway thread queues carries its bot":
      setGatewayBot("ops")
      check taggedEvent(DiscordRawEvent(kind: deMessage, content: "oi")).bot == "ops"
      setGatewayBot("")
      check taggedEvent(DiscordRawEvent(kind: deMessage)).bot == ""

when isMainModule:
  runTests()
