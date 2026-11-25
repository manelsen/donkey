## telegram_bots — the `[[bots]]` entries on Telegram (PRD-roadmap E3.3).
##
## Each bot is a TelegramAdapter of its own, with its own long poll, built
## like the default one but sharing its identities (one person is one user on
## every bot). The bot a person wrote to last answers them: `noteInbound`
## records it when a message arrives, and `adapterFor` is what every outbound
## path (send, edits, keyboards, typing) asks for that person's adapter.

import std/strutils
import chronos
import ../../config/environment
import ../../core/pipeops
import ../../core/types
import ../../domain/bots_pure
import ../../domain/message
import ../../ports/http
import ./telegram

type
  TelegramBotSlot* = object
    name*:    string
    adapter*: TelegramAdapter
    poll*:    Future[Result[HttpResponse, string]]   ## its long poll in flight

  TelegramBots* = object
    slots*:    seq[TelegramBotSlot]
      ## Built once at startup and never resized: `adapterFor` hands out
      ## pointers into it that the outbound ports and typing keep.
    affinity*: BotAffinity

proc buildTelegramBots*(specs: openArray[BotSpec]; env: Environment;
                        primary: TelegramAdapter): (TelegramBots, seq[string]) =
  ## An adapter per Telegram entry whose token variable is set, configured
  ## like the default bot (API base, poll timeout, settings) and sharing its
  ## identity resolver. Entries without a token are reported, not run.
  var bots = TelegramBots()
  var problems: seq[string]
  for spec in botsOf(specs, ckTelegram):
    let token = env.get(spec.tokenEnv).strip
    if token.len == 0:
      problems.add "bot " & spec.name & ": " & spec.tokenEnv & " is not set"
      continue
    var adapter = newTelegramAdapter(token, "", apiBase = primary.apiBase,
                                     pollTimeout = primary.pollTimeout,
                                     settings = primary.settings)
    adapter.resolver = primary.resolver
    bots.slots.add TelegramBotSlot(name: spec.name, adapter: adapter)
  (bots, problems)

proc noteInbound*(bots: var TelegramBots; msg: var InboundMessage; botName: string) =
  ## The message came through `botName` ("" = the default bot): tag it, and
  ## make that bot the one that answers this person.
  msg.bot = botName
  bots.affinity.record($msg.userId, botName)

proc adapterFor*(bots: ptr TelegramBots; primary: ptr TelegramAdapter;
                 userId: UserId): ptr TelegramAdapter =
  ## The adapter of the bot this person wrote to last; the default bot when
  ## that is the default, unknown or no longer configured.
  let name = bots[].affinity.botFor($userId)
  if name.len > 0:
    for slot in bots[].slots.mitems:
      if slot.name == name:
        return addr slot.adapter
  primary
