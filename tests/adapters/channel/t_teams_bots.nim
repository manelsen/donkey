## Several Teams bots in one instance (PRD-roadmap E3.6): each app has its
## own App ID and password, sharing the route, the identities and the tenant
## of the default bot; a person is answered by the app they wrote to last.

import std/[os, strutils, unittest]
import donkey/adapters/channel/teams
import donkey/adapters/channel/teams_bots
import ./teams_cert_vectors
import donkey/adapters/channel/outbound_builder
import donkey/adapters/identity/identity_resolver
import donkey/config/environment
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/bots_pure
import donkey/domain/message

proc tempDir(tag: string): string =
  result = getTempDir() / ("donkey_teams_bots_" & tag)
  removeDir(result)
  createDir(result)

proc specs(): seq[BotSpec] =
  validateBots(@[
    BotSpec(name: "vendas", channel: "teams", appId: "app-999", secretEnv: "TEAMS_VENDAS"),
    BotSpec(name: "rh", channel: "teams", appId: "app-777", secretEnv: "TEAMS_RH"),
    BotSpec(name: "time", channel: "discord", tokenEnv: "DC")])[0]

proc runTests*() =
  suite "teams bots":

    test "one adapter per app whose password is set; the others are reported":
      let dir = tempDir("build")
      let primary = newTeamsAdapter("app-123", "pw", "tenant-1", dir / "ids.tsv",
                                    dir / "teams_conversations.json")
      let (bots, problems) = buildTeamsBots(specs(),
        environmentOf({"TEAMS_VENDAS": "pw-v"}), primary, dir)
      check bots.slots.len == 1
      check bots.slots[0].name == "vendas"
      check bots.slots[0].adapter.appId == "app-999"
      check bots.slots[0].adapter.tenantId == "tenant-1"
      check bots.slots[0].adapter.configError == ""
      check problems.len == 1 and "TEAMS_RH" in problems[0]

    test "the apps the route accepts, with their bots":
      let dir = tempDir("apps")
      let primary = newTeamsAdapter("app-123", "pw", "t", dir / "ids.tsv",
                                    dir / "c.json")
      let (bots, _) = buildTeamsBots(specs(),
        environmentOf({"TEAMS_VENDAS": "a", "TEAMS_RH": "b"}), primary, dir)
      let apps = bots.routeApps()
      check apps.len == 2
      check apps[0].appId == "app-999" and apps[0].bot == "vendas"

    test "every app shares the default bot's identities, keeps its own conversations":
      let dir = tempDir("ids")
      var primary = newTeamsAdapter("app-123", "pw", "t", dir / "ids.tsv",
                                    dir / "teams_conversations.json")
      var (bots, _) = buildTeamsBots(specs(),
        environmentOf({"TEAMS_VENDAS": "a", "TEAMS_RH": "b"}), primary, dir)
      let uid = primary.resolver.resolve(ckTeams, "aad-belle")
      check bots.slots[0].adapter.resolver.resolve(ckTeams, "aad-belle") == uid
      check bots.slots[0].adapter.rememberConversation("aad-belle",
        "https://smba.trafficmanager.net/amer/", "a:1").isOk
      check fileExists(dir / "teams_conversations_vendas.json")
      check not fileExists(dir / "teams_conversations.json")

    test "an activity's bot picks its adapter; the affinity answers the person":
      let dir = tempDir("pick")
      var primary = newTeamsAdapter("app-123", "pw", "t", dir / "ids.tsv", dir / "c.json")
      var (bots, _) = buildTeamsBots(specs(),
        environmentOf({"TEAMS_VENDAS": "a", "TEAMS_RH": "b"}), primary, dir)
      check slotAdapter(addr bots, addr primary, "")[].appId == "app-123"
      check slotAdapter(addr bots, addr primary, "rh")[].appId == "app-777"
      check slotAdapter(addr bots, addr primary, "gone").isNil
      bots.noteInbound(UserId("u-1"), "rh")
      check adapterFor(addr bots, addr primary, UserId("u-1"))[].appId == "app-777"

  suite "teams bots — the outbound port":

    test "a message for a person goes through their app":
      let dir = tempDir("port")
      var a = newTeamsAdapter("", "", "", dir / "ids.tsv", dir / "a.json")
      var b = newTeamsAdapter("", "", "", dir / "ids.tsv", dir / "b.json")
      a.configError = "app A"
      b.configError = "app B"
      let pa = addr a
      let pb = addr b
      let pick: TeamsPick = proc(userId: UserId): ptr TeamsAdapter {.gcsafe.} =
        if $userId == "u-b": pb else: pa
      let port = teamsOutboundPort(pa, pick)
      let r = port.send(OutboundMessage(userId: UserId("u-b"), channel: ckTeams, text: "x"))
      check r.isErr and "app B" in r.error
      let r2 = port.send(OutboundMessage(userId: UserId("u-a"), channel: ckTeams, text: "x"))
      check r2.isErr and "app A" in r2.error

proc runCertTests*() =
  suite "teams bots — a certificate per app (E9)":
    test "cert_env names the variable with the app's PEM; its token is that app's":
      let dir = getTempDir() / "donkey_teams_bots_cert"
      removeDir(dir); createDir(dir)
      writeFile(dir / "vendas.pem", TestCombinedPem)
      let spec = @[BotSpec(name: "vendas", channel: "teams", appId: "app-999",
                           secretEnv: "TEAMS_VENDAS", certEnv: "TEAMS_VENDAS_CERT")]
      let primary = newTeamsAdapter("app-123", "pw", "tenant-1", dir / "ids.tsv", dir / "c.json")
      let (bots, problems) = buildTeamsBots(validateBots(spec)[0],
        environmentOf({"TEAMS_VENDAS": "pw2", "TEAMS_VENDAS_CERT": dir / "vendas.pem"}),
        primary, dir)
      check problems.len == 0
      check bots.slots[0].adapter.certThumbprintOf == TestCertX5t

when isMainModule:
  runTests()
  runCertTests()
