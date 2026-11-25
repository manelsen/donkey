## Several WhatsApp numbers in one instance (PRD-roadmap E3.5): numbers of
## the same Meta account share its access token, so each bot is an adapter
## with the default bot's token and its own number. The number an event was
## sent to picks the bot; everything sent to a person goes from the number
## they wrote to last.

import std/[os, strutils, unittest]
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/whatsapp_bots
import donkey/adapters/channel/outbound_builder
import donkey/adapters/identity/identity_resolver
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/bots_pure
import donkey/domain/message

proc tempIds(tag: string): string =
  result = getTempDir() / ("donkey_wa_bots_" & tag & ".tsv")
  removeFile(result)

proc specs(): seq[BotSpec] =
  validateBots(@[
    BotSpec(name: "vendas", channel: "whatsapp", phoneNumberId: "222"),
    BotSpec(name: "suporte", channel: "whatsapp", phoneNumberId: "333"),
    BotSpec(name: "time", channel: "discord", tokenEnv: "DC")])[0]

proc runTests*() =
  suite "whatsapp bots":

    test "each number is an adapter with the account's token":
      let primary = newWhatsAppAdapter("acct-token", "111", tempIds("build"))
      let (bots, problems) = buildWhatsAppBots(specs(), primary)
      check problems.len == 0
      check bots.slots.len == 2
      check bots.slots[0].name == "vendas"
      check bots.slots[0].adapter.phoneNumberId == "222"
      check bots.slots[0].adapter.accessToken == "acct-token"

    test "without the default number configured the bots are reported, not run":
      let primary = newWhatsAppAdapter("", "", tempIds("none"))
      let (bots, problems) = buildWhatsAppBots(specs(), primary)
      check bots.slots.len == 0
      check problems.len == 2 and "WHATSAPP_ACCESS_TOKEN" in problems[0]

    test "a bot cannot reuse the default number":
      let primary = newWhatsAppAdapter("acct-token", "222", tempIds("dup"))
      let (bots, problems) = buildWhatsAppBots(specs(), primary)
      check bots.slots.len == 1 and bots.slots[0].name == "suporte"
      check problems.len == 1 and "vendas" in problems[0]

    test "the number an event was sent to picks the bot":
      var primary = newWhatsAppAdapter("acct-token", "111", tempIds("pick"))
      var (bots, _) = buildWhatsAppBots(specs(), primary)
      let (pa, na) = botForNumber(addr bots, addr primary, "111")
      check pa == (addr primary) and na == ""
      let (pb, nb) = botForNumber(addr bots, addr primary, "333")
      check pb[].phoneNumberId == "333" and nb == "suporte"
      let (pc, _) = botForNumber(addr bots, addr primary, "999")
      check pc.isNil
      check botForNumber(addr bots, addr primary, "")[0].isNil

    test "every bot shares the default bot's identities":
      var primary = newWhatsAppAdapter("acct-token", "111", tempIds("ids"))
      let (bots, _) = buildWhatsAppBots(specs(), primary)
      let uid = primary.resolver.resolve(ckWhatsApp, "5511999")
      check bots.slots[1].adapter.resolver.resolve(ckWhatsApp, "5511999") == uid

    test "a person is answered from the number they wrote to last":
      var primary = newWhatsAppAdapter("acct-token", "111", tempIds("aff"))
      var (bots, _) = buildWhatsAppBots(specs(), primary)
      bots.noteInbound(UserId("u-1"), "vendas")
      check adapterFor(addr bots, addr primary, UserId("u-1"))[].phoneNumberId == "222"
      bots.noteInbound(UserId("u-1"), "")
      check adapterFor(addr bots, addr primary, UserId("u-1"))[].phoneNumberId == "111"

  suite "whatsapp bots — the outbound port":

    test "a message for a person goes from their number":
      var a = newWhatsAppAdapter("tok", "111", tempIds("port"), apiBase = "http://127.0.0.1:9")
      var b = newWhatsAppAdapter("tok", "222", tempIds("port"), apiBase = "http://127.0.0.1:9")
      let pa = addr a
      let pb = addr b
      var asked: seq[string]
      let pick: WhatsAppPick = proc(userId: UserId): ptr WhatsAppAdapter {.gcsafe.} =
        {.cast(gcsafe).}:
          asked.add $userId
        if $userId == "u-b": pb else: pa
      let port = whatsappOutboundPort(pa, pick)
      discard port.send(OutboundMessage(userId: UserId("u-b"), channel: ckWhatsApp, text: "x"))
      discard port.sendReturnId(OutboundMessage(userId: UserId("u-a"), channel: ckWhatsApp, text: "x"))
      check asked == @["u-b", "u-a"]

when isMainModule:
  runTests()
