## Several Telegram bots in one instance (PRD-roadmap E3.3): each bot is its
## own adapter and long poll; a person is the same user on all of them, and
## everything sent to them goes through the bot they wrote to last.

import std/[os, strutils, unittest]
import donkey/adapters/channel/telegram
import donkey/adapters/channel/telegram_bots
import donkey/adapters/identity/identity_resolver
import donkey/config/environment
import donkey/core/types
import donkey/domain/bots_pure
import donkey/domain/message

proc tempIds(tag: string): string =
  result = getTempDir() / ("donkey_tg_bots_" & tag & ".tsv")
  removeFile(result)

proc specs(): seq[BotSpec] =
  validateBots(@[
    BotSpec(name: "suporte", channel: "telegram", tokenEnv: "TG_SUPORTE"),
    BotSpec(name: "vendas", channel: "telegram", tokenEnv: "TG_VENDAS"),
    BotSpec(name: "time", channel: "discord", tokenEnv: "DC_TIME")])[0]

proc runTests*() =
  suite "telegram bots":

    test "one adapter per Telegram bot whose token is set; the others are reported":
      let ids = tempIds("build")
      var primary = newTelegramAdapter("primary-token", ids)
      let (bots, problems) = buildTelegramBots(specs(),
        environmentOf({"TG_SUPORTE": "111:aaa"}), primary)
      check bots.slots.len == 1
      check bots.slots[0].name == "suporte"
      check bots.slots[0].adapter.token == "111:aaa"
      check problems.len == 1 and "TG_VENDAS" in problems[0]

    test "every bot shares the primary's identities":
      let ids = tempIds("ids")
      var primary = newTelegramAdapter("primary-token", ids)
      let (bots, _) = buildTelegramBots(specs(),
        environmentOf({"TG_SUPORTE": "111:aaa", "TG_VENDAS": "222:bbb"}), primary)
      let uid = primary.resolver.resolve(ckTelegram, "42")
      check bots.slots[0].adapter.resolver.resolve(ckTelegram, "42") == uid
      check bots.slots[1].adapter.resolver.resolve(ckTelegram, "42") == uid

    test "a message through a bot is tagged with it and makes it that person's bot":
      let ids = tempIds("tag")
      var primary = newTelegramAdapter("primary-token", ids)
      var (bots, _) = buildTelegramBots(specs(),
        environmentOf({"TG_SUPORTE": "111:aaa", "TG_VENDAS": "222:bbb"}), primary)
      var msg = InboundMessage(userId: UserId("u-1"), text: "oi")
      bots.noteInbound(msg, "vendas")
      check msg.bot == "vendas"
      check adapterFor(addr bots, addr primary, UserId("u-1"))[].token == "222:bbb"

    test "a person who wrote to the default bot is answered by it":
      let ids = tempIds("default")
      var primary = newTelegramAdapter("primary-token", ids)
      var (bots, _) = buildTelegramBots(specs(),
        environmentOf({"TG_SUPORTE": "111:aaa"}), primary)
      check adapterFor(addr bots, addr primary, UserId("u-2"))[].token == "primary-token"
      var a = InboundMessage(userId: UserId("u-2"))
      bots.noteInbound(a, "suporte")
      var b = InboundMessage(userId: UserId("u-2"))
      bots.noteInbound(b, "")
      check b.bot == ""
      check adapterFor(addr bots, addr primary, UserId("u-2"))[].token == "primary-token"

    test "an affinity to a bot that is gone falls back to the default":
      let ids = tempIds("gone")
      var primary = newTelegramAdapter("primary-token", ids)
      var bots = TelegramBots()
      bots.affinity.record("u-3", "removido")
      check adapterFor(addr bots, addr primary, UserId("u-3"))[].token == "primary-token"

when isMainModule:
  runTests()
