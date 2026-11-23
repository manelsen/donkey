## named_agents.nim — the user's named agents on disk, through the fs port.
##
## `{paddock}/agents/<name>.toml` holds the agent (`domain/agents/
## named_agent_pure` reads and writes it); `<name>.notes.md` next to it holds
## the agent's own notes. Everything else an agent knows is the user's shared
## memory.

import std/[algorithm, os, strutils]
import ../core/pipeops
import ../core/tooling/native_tool_args
import ../domain/agents/named_agent_pure
import ../ports/fs

const AgentsDirName* = "agents"

type LoadedAgent* = object
  agent*: NamedAgent
  notes*: string

func agentsDir*(paddockDir: string): string =
  paddockDir & "/" & AgentsDirName

proc loadNamedAgent*(fs: FsRuntimePort; paddockDir, name: string): Result[LoadedAgent, string] =
  if not validAgentName(name):
    return err("not an agent name: " & name)
  let dir = agentsDir(paddockDir)
  let text = ? fs.readFile(dir & "/" & agentFileName(name))
  let agent = ? parseAgentFile(text)
  if agent.name != name:
    return err("agents/" & agentFileName(name) & " names another agent: " & agent.name)
  let notes = fs.readFile(dir & "/" & agentNotesFileName(name)).get("")
  ok(LoadedAgent(agent: agent, notes: notes))

proc listNamedAgents*(fs: FsRuntimePort; paddockDir: string): seq[NamedAgent] =
  ## Every readable agent file, by name; a broken file is skipped.
  let entries = fs.listDir(agentsDir(paddockDir)).get(@[])
  var names: seq[string]
  for entry in entries:
    let file = extractFilename(entry.path)
    if file.endsWith(".toml"):
      names.add(file[0 ..< file.len - ".toml".len])
  names.sort()
  for name in names:
    let loaded = loadNamedAgent(fs, paddockDir, name)
    if loaded.isOk:
      result.add(loaded.get.agent)

proc writeAgent(fs: FsRuntimePort; paddockDir: string; a: NamedAgent): Result[void, string] =
  let dir = agentsDir(paddockDir)
  ? fs.createDir(dir)
  fs.writeFile(dir & "/" & agentFileName(a.name), renderAgentFile(a))

proc performManageAgents*(fs: FsRuntimePort; paddockDir: string;
                          ctx: ManageAgentsContext): Result[string, string] =
  ## The `manage_agents` tool: one action on the user's named agents.
  case ctx.action
  of "list":
    let agents = listNamedAgents(fs, paddockDir)
    if agents.len == 0:
      return ok("No named agents yet. Create one with manage_agents " &
                "(action=create, name, description); the user then calls it " &
                "by starting a message with @name.")
    var lines = @["Named agents (call with @name):"]
    for a in agents:
      var line = "- @" & a.name & ": " & a.description
      if a.provider.len > 0:
        line.add(" [" & a.provider & (if a.model.len > 0: "/" & a.model else: "") & "]")
      lines.add(line)
    return ok(lines.join("\n"))
  of "create":
    if not validAgentName(ctx.name):
      return err("Error: agent name must be 1-32 of a-z, 0-9 and '-'")
    if loadNamedAgent(fs, paddockDir, ctx.name).isOk:
      return err("Error: @" & ctx.name & " already exists; use action=update")
    let agent = NamedAgent(name: ctx.name, description: ctx.description,
                           provider: ctx.provider, model: ctx.model)
    ? writeAgent(fs, paddockDir, agent)
    return ok("Created @" & ctx.name & ". The user calls it by starting a message with @" &
              ctx.name & ".")
  of "update":
    var loaded = ? loadNamedAgent(fs, paddockDir, ctx.name)
    if ctx.description.len > 0: loaded.agent.description = ctx.description
    if ctx.provider.len > 0: loaded.agent.provider = ctx.provider
    if ctx.model.len > 0: loaded.agent.model = ctx.model
    ? writeAgent(fs, paddockDir, loaded.agent)
    return ok("Updated @" & ctx.name & ".")
  of "delete":
    discard ? loadNamedAgent(fs, paddockDir, ctx.name)
    let dir = agentsDir(paddockDir)
    ? fs.remove(dir & "/" & agentFileName(ctx.name), false)
    discard fs.remove(dir & "/" & agentNotesFileName(ctx.name), false)
    return ok("Deleted @" & ctx.name & ".")
  of "note":
    if ctx.text.strip.len == 0:
      return err("Error: an empty note")
    discard ? loadNamedAgent(fs, paddockDir, ctx.name)
    ? fs.appendFile(agentsDir(paddockDir) & "/" & agentNotesFileName(ctx.name),
                    "- " & ctx.text.strip.replace("\n", " ") & "\n")
    return ok("Noted for @" & ctx.name & ".")
  else:
    err("Error: unknown action " & ctx.action)
