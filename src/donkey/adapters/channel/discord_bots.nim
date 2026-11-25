## discord_bots — the `[[bots]]` entries on Discord (PRD-roadmap E3.4).
##
## Each bot is a DiscordAdapter of its own with its own gateway connection,
## built like the default one (mention rule, allowed channels) and sharing its
## identities: one person is one user on every bot. The gateway thread tags
## what it queues with its bot (discord.taggedEvent); the drain picks the
## event's adapter with `slotAdapter` and records the person's bot with
## `noteInbound`, and every outbound path asks `adapterFor`.
##
## A bot's adapter has no DM recovery cursor: the cursor is one per person
## and DM channels differ per bot, so only the default bot recovers DMs
## missed while the daemon was down.

import std/strutils
import ../../config/environment
import ../../core/types
import ../../domain/bots_pure
import ./discord

type
  DiscordBotSlot* = object
    name*:    string
    adapter*: DiscordAdapter

  DiscordBots* = object
    slots*:    seq[DiscordBotSlot]
      ## Built once at startup and never resized: `adapterFor` and
      ## `slotAdapter` hand out pointers into it.
    affinity*: BotAffinity

proc buildDiscordBots*(specs: openArray[BotSpec]; env: Environment;
                       primary: DiscordAdapter): (DiscordBots, seq[string]) =
  var bots = DiscordBots()
  var problems: seq[string]
  for spec in botsOf(specs, ckDiscord):
    let token = env.get(spec.tokenEnv).strip
    if token.len == 0:
      problems.add "bot " & spec.name & ": " & spec.tokenEnv & " is not set"
      continue
    var adapter = newDiscordAdapter(token, "", apiBase = primary.apiBase,
                                    requireMention = primary.requireMention,
                                    allowedChannels = primary.allowedChannels)
    adapter.resolver = primary.resolver
    adapter.cursor = nil
    bots.slots.add DiscordBotSlot(name: spec.name, adapter: adapter)
  (bots, problems)

proc noteInbound*(bots: var DiscordBots; userId: UserId; botName: string) =
  ## The person wrote through `botName` ("" = the default bot): it answers them.
  bots.affinity.record($userId, botName)

proc slotAdapter*(bots: ptr DiscordBots; primary: ptr DiscordAdapter;
                  botName: string): ptr DiscordAdapter =
  ## The adapter an event came through; nil for a bot no longer configured.
  if botName.len == 0:
    return primary
  for slot in bots[].slots.mitems:
    if slot.name == botName:
      return addr slot.adapter
  nil

proc adapterFor*(bots: ptr DiscordBots; primary: ptr DiscordAdapter;
                 userId: UserId): ptr DiscordAdapter =
  ## The adapter of the bot this person wrote to last; the default bot when
  ## that is the default, unknown or no longer configured.
  let found = slotAdapter(bots, primary, bots[].affinity.botFor($userId))
  if found.isNil: primary else: found
