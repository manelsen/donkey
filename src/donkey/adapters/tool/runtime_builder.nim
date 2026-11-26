## runtime_builder — skill processes on the event loop (PRD-roadmap E5
## follow-up).
##
## A skill is an MCP server in a Deno subprocess, driven by the asynchronous
## stdio client like any MCP server. One client per skill (script and
## permissions), kept for the whole process and shared by every session:
## sessions used to start their own process for each skill and list its
## tools while being built, holding the loop. The builder a session calls
## returns at once with the tools already listed; the first time, the
## listing runs in the background, and the sessions built after it (the next
## message: a changed catalog rebuilds the session) carry the skill's tools.
## Skills from skills.toml are listed at startup with the MCP servers.

import std/[strutils, tables]
import chronos
import ../../core/pipeops
import ../../ports/tool
import ../../config/skills_registry
import ./deno_skill
import ./mcp_client

type
  SkillClientFactory* = proc(script: string; permissions: seq[string]): McpClient {.gcsafe.}

  SkillState = enum
    ssNew, ssListing, ssListed, ssFailed

  SkillEntry = ref object
    client: McpClient
    state:  SkillState

  SkillClients* = ref object
    factory: SkillClientFactory
    entries: Table[string, SkillEntry]

proc denoClientFactory*(): SkillClientFactory =
  result = proc(script: string; permissions: seq[string]): McpClient {.gcsafe.} =
    newDenoSkillAdapter(script, permissions)

proc newSkillClients*(factory: SkillClientFactory = denoClientFactory()): SkillClients =
  SkillClients(factory: factory, entries: initTable[string, SkillEntry]())

proc listInBackground(entry: SkillEntry) {.async: (raises: []).} =
  entry.state = ssListing
  let listed = await entry.client.listToolsAsync()
  entry.state = if listed.isOk: ssListed else: ssFailed

proc entryFor(s: SkillClients; script: string; permissions: seq[string]): SkillEntry =
  let key = script & "\x1f" & permissions.join("\x1f")
  result = s.entries.getOrDefault(key)
  if result.isNil:
    result = SkillEntry(client: s.factory(script, permissions))
    s.entries[key] = result

proc clientFor*(s: SkillClients; script: string; permissions: seq[string];
                policy: SkillRuntimePolicy): Result[McpClient, string] =
  ## The client of a skill whose permissions the policy allows (skills.toml
  ## at startup: the daemon lists it with the MCP servers).
  let allowed = ? validateSkillPermissions(permissions, policy.allowNetHosts)
  ok(s.entryFor(script, allowed).client)

proc builder*(s: SkillClients): SkillRuntimeBuilder =
  ## For session bootstrap: never waits for a process.
  result = proc(script: string; permissions: seq[string];
                policy: SkillRuntimePolicy): Result[LoadedToolRuntime, string] {.gcsafe.} =
    let allowed = ? validateSkillPermissions(permissions, policy.allowNetHosts)
    let e = s.entryFor(script, allowed)
    if e.state in {ssNew, ssFailed}:
      asyncSpawn listInBackground(e)
    let port = e.client.toRuntimePort()
    ok(LoadedToolRuntime(port: port, schemas: port.listTools().get(@[])))

func listedCount*(s: SkillClients): int =
  for e in s.entries.values:
    if e.state == ssListed: inc result

func failedCount*(s: SkillClients): int =
  for e in s.entries.values:
    if e.state == ssFailed: inc result

proc closeAll*(s: SkillClients) {.async: (raises: []).} =
  for entry in s.entries.values:
    await entry.client.closeAsync()
