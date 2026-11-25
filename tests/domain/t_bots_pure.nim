## Several bots in one instance (PRD-roadmap E3.1): what a `[[bots]]` entry
## must hold for its channel, and which bot answers a person (affinity).

import std/[strutils, unittest]
import donkey/core/types
import donkey/domain/bots_pure

proc tg(name: string; tokenEnv = "TELEGRAM_TOKEN_X"; agent = ""): BotSpec =
  BotSpec(name: name, channel: "telegram", tokenEnv: tokenEnv, agent: agent)

proc runTests*() =
  suite "bots — the entries":

    test "a well-formed entry per channel is kept":
      let (bots, problems) = validateBots(@[
        tg("suporte", agent = "suporte"),
        BotSpec(name: "comunidade", channel: "discord", tokenEnv: "DISCORD_TOKEN_C"),
        BotSpec(name: "vendas", channel: "whatsapp", phoneNumberId: "1234567890"),
        BotSpec(name: "time", channel: "teams", appId: "app-2", secretEnv: "TEAMS_SECRET_2")])
      check problems.len == 0
      check bots.len == 4
      check bots[0].kind == ckTelegram and bots[3].kind == ckTeams

    test "each channel's own field is required":
      let (bots, problems) = validateBots(@[
        tg("a", tokenEnv = ""),
        BotSpec(name: "b", channel: "whatsapp"),
        BotSpec(name: "c", channel: "teams", appId: "app"),
        BotSpec(name: "d", channel: "discord")])
      check bots.len == 0
      check problems.len == 4
      check "token_env" in problems[0]
      check "phone_number_id" in problems[1]
      check "secret_env" in problems[2]

    test "a channel without multi-bot support is refused by name":
      let (bots, problems) = validateBots(@[BotSpec(name: "x", channel: "line", tokenEnv: "T")])
      check bots.len == 0
      check "line" in problems[0]
      check validateBots(@[BotSpec(name: "x", channel: "pigeon")])[1].len == 1

    test "names are simple and unique; the second of two is refused":
      let (bots, problems) = validateBots(@[tg("suporte"), tg("suporte", "OTHER"),
                                            tg("Bad Name"), tg("")])
      check bots.len == 1
      check problems.len == 3
      check "suporte" in problems[0]

    test "an agent name must be a valid agent name":
      let (bots, problems) = validateBots(@[tg("a", agent = "../etc")])
      check bots.len == 0 and problems.len == 1

    test "two bots cannot share a token or a number":
      let (bots, problems) = validateBots(@[tg("a", "SAME"), tg("b", "SAME"),
        BotSpec(name: "c", channel: "whatsapp", phoneNumberId: "1"),
        BotSpec(name: "d", channel: "whatsapp", phoneNumberId: "1")])
      check bots.len == 2
      check problems.len == 2

  suite "bots — affinity":

    test "the last bot a person wrote to answers them":
      var aff: BotAffinity
      check aff.botFor("u-1") == ""
      aff.record("u-1", "suporte")
      check aff.botFor("u-1") == "suporte"
      aff.record("u-1", "")
      check aff.botFor("u-1") == ""
      check aff.botFor("u-2") == ""

    test "the bots of one channel, by name":
      let (bots, _) = validateBots(@[tg("a", "T1"), tg("b", "T2"),
        BotSpec(name: "c", channel: "discord", tokenEnv: "D")])
      check botsOf(bots, ckTelegram).len == 2
      check botsOf(bots, ckDiscord).len == 1
      check botsOf(bots, ckWhatsApp).len == 0

when isMainModule:
  runTests()
