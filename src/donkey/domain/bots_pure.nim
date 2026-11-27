## bots_pure — several bots in one instance (PRD-roadmap E3).
##
## A bot is a facade: its own token (or number, or app) and persona, over the
## instance's users, memory and sessions. `validateBots` keeps the
## well-formed `[[bots]]` entries and says what is wrong with the others;
## `BotAffinity` remembers which bot each person wrote to last, which is the
## bot that answers them on that channel.

import std/[strutils, tables]
import ../core/types
import ./agents/agent_name_pure

const MultiBotChannels* = {ckTelegram, ckDiscord, ckWhatsApp, ckTeams}

type
  BotSpec* = object
    name*:          string
    channel*:       string       ## as written in the config
    kind*:          ChannelKind  ## set by `validateBots`
    agent*:         string       ## {home}/agents/<agent>.md; "" = default persona
    tokenEnv*:      string       ## Telegram, Discord: the variable with the token
    phoneNumberId*: string       ## WhatsApp: the number in the shared account
    appId*:         string       ## Teams: the bot's App ID
    secretEnv*:     string       ## Teams: the variable with its password
    certEnv*:       string       ## Teams: the variable with the path of its certificate PEM

  BotAffinity* = object
    last: Table[string, string]   ## user id → bot name ("" = the default bot)

func validBotName*(name: string): bool =
  name.len in 1 .. 32 and name[0] in {'a'..'z'} and
    name.allCharsInSet({'a'..'z', '0'..'9', '-', '_'})

func kindOf(channel: string; kind: var ChannelKind): bool =
  for k in ChannelKind:
    if $k == channel.strip.toLowerAscii:
      kind = k
      return true
  false

func credentialOf(b: BotSpec): string =
  ## What tells two bots of one channel apart.
  case b.kind
  of ckWhatsApp: b.phoneNumberId
  of ckTeams: b.appId
  else: b.tokenEnv

func problemOf(b: BotSpec): string =
  ## "" when the entry is well formed; `b.kind` must be set.
  if b.kind notin MultiBotChannels:
    return "bot " & b.name & ": channel " & b.channel & " has no multi-bot support"
  if b.agent.len > 0 and not validAgentName(b.agent):
    return "bot " & b.name & ": agent " & b.agent & " is not an agent name"
  case b.kind
  of ckTelegram, ckDiscord:
    if b.tokenEnv.strip.len == 0:
      return "bot " & b.name & ": token_env is missing"
  of ckWhatsApp:
    if b.phoneNumberId.strip.len == 0:
      return "bot " & b.name & ": phone_number_id is missing"
  of ckTeams:
    if b.appId.strip.len == 0 or b.secretEnv.strip.len == 0:
      return "bot " & b.name & ": app_id and secret_env are both needed"
  else:
    discard
  ""

func validateBots*(specs: openArray[BotSpec]): (seq[BotSpec], seq[string]) =
  ## The entries to run, in order, and one line per entry left out.
  var bots: seq[BotSpec]
  var problems: seq[string]
  var names, credentials: seq[string]
  for spec in specs:
    var b = spec
    if not validBotName(b.name):
      problems.add "bot name '" & b.name & "' must be lower case letters, digits, - or _"
      continue
    if b.name in names:
      problems.add "bot " & b.name & ": the name is already used"
      continue
    if not kindOf(b.channel, b.kind):
      problems.add "bot " & b.name & ": unknown channel " & b.channel
      continue
    let problem = problemOf(b)
    if problem.len > 0:
      problems.add problem
      continue
    let credential = $b.kind & ":" & credentialOf(b).strip
    if credential in credentials:
      problems.add "bot " & b.name & ": another bot already uses the same " &
                   (if b.kind == ckWhatsApp: "number" else: "credential")
      continue
    names.add b.name
    credentials.add credential
    bots.add b
  (bots, problems)

func botsOf*(bots: openArray[BotSpec]; kind: ChannelKind): seq[BotSpec] =
  for b in bots:
    if b.kind == kind:
      result.add b

func record*(a: var BotAffinity; userId, bot: string) =
  a.last[userId] = bot

func botFor*(a: BotAffinity; userId: string): string =
  a.last.getOrDefault(userId, "")
