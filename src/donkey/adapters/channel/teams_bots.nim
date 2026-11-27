## teams_bots — the `[[bots]]` entries on Teams (PRD-roadmap E3.6).
##
## Each bot is an Azure Bot of its own: its App ID (the audience of the
## tokens the connector sends it) and its password (`secret_env`). The apps
## share the route (`routeApps` tells the webhook which audience is which
## bot), the identities and the tenant of the default bot; each keeps its own
## conversations file, since a conversation belongs to the app it was held
## with. The activity's bot picks the adapter on the daemon loop, and the
## person's last bot answers every outbound path.

import std/[os, strutils]
import ../../config/environment
import ../../core/types
import ../../domain/bots_pure
import ../webhook/webhook_receiver
import ./teams

type
  TeamsBotSlot* = object
    name*:    string
    adapter*: TeamsAdapter

  TeamsBots* = object
    slots*:    seq[TeamsBotSlot]
      ## Built once at startup and never resized: pointers into it are kept.
    affinity*: BotAffinity

proc buildTeamsBots*(specs: openArray[BotSpec]; env: Environment;
                     primary: TeamsAdapter; stateDir: string): (TeamsBots, seq[string]) =
  var bots = TeamsBots()
  var problems: seq[string]
  for spec in botsOf(specs, ckTeams):
    let password = env.get(spec.secretEnv).strip
    if password.len == 0:
      problems.add "bot " & spec.name & ": " & spec.secretEnv & " is not set"
      continue
    if spec.appId == primary.appId:
      problems.add "bot " & spec.name & ": " & spec.appId & " is already the default app"
      continue
    var adapter = newTeamsAdapter(spec.appId, password, primary.tenantId, "",
      stateDir / ("teams_conversations_" & spec.name & ".json"),
      serviceHosts = primary.serviceHosts,
      certPath = (if spec.certEnv.len > 0: env.get(spec.certEnv).strip else: ""))
    adapter.resolver = primary.resolver
    adapter.linkCodes = primary.linkCodes
    bots.slots.add TeamsBotSlot(name: spec.name, adapter: adapter)
  (bots, problems)

func routeApps*(bots: TeamsBots): seq[TeamsApp] =
  for slot in bots.slots:
    result.add TeamsApp(appId: slot.adapter.appId, bot: slot.name)

proc noteInbound*(bots: var TeamsBots; userId: UserId; botName: string) =
  bots.affinity.record($userId, botName)

proc slotAdapter*(bots: ptr TeamsBots; primary: ptr TeamsAdapter;
                  botName: string): ptr TeamsAdapter =
  if botName.len == 0:
    return primary
  for slot in bots[].slots.mitems:
    if slot.name == botName:
      return addr slot.adapter
  nil

proc adapterFor*(bots: ptr TeamsBots; primary: ptr TeamsAdapter;
                 userId: UserId): ptr TeamsAdapter =
  let found = slotAdapter(bots, primary, bots[].affinity.botFor($userId))
  if found.isNil: primary else: found
