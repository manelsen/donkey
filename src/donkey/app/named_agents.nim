## named_agents.nim — the user's named agents on disk, through the fs port.
##
## `{paddock}/agents/<name>.toml` holds the agent (`domain/agents/
## named_agent_pure` reads and writes it); `<name>.notes.md` next to it holds
## the agent's own notes. Everything else an agent knows is the user's shared
## memory.

import std/[algorithm, os, strutils]
import chronos
import ../core/pipeops
import ../core/tooling/native_tool_args
import ../domain/message
import ./provider_executor
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

# ── Agents talking to each other ──────────────────────────────────────────────

const
  MinRoomAgents* = 2
  MaxRoomAgents* = 5
  MaxRoomRounds* = 3

proc agentRequest(loaded: LoadedAgent; text: string): CompletionRequest =
  ## One reply from the agent, without tools: no recursion through a room.
  var h = newHistory()
  h.addUser(text)
  result = CompletionRequest(
    system: namedAgentSystem(loaded.agent, loaded.notes, ""),
    messages: h,
    providerOverride: loaded.agent.provider,
    modelOverride: loaded.agent.model)

proc askOnce(callModel: AsyncCompleteFn; loaded: LoadedAgent;
             text: string): Future[Result[string, string]] {.async.} =
  if callModel == nil:
    return err(Result[string, string], "no model available for agent calls")
  var resp: Result[CompletionResponse, string]
  try:
    resp = await callModel(agentRequest(loaded, text))
  except CancelledError as e:
    raise e
  except Exception as e:  ## effect boundary: callee raises are unannotated
    return err(Result[string, string], "@" & loaded.agent.name & ": " & e.msg)
  if resp.isErr:
    return err(Result[string, string], "@" & loaded.agent.name & ": " & resp.error)
  return ok(Result[string, string], resp.get.text)

proc askNamedAgent*(fs: FsRuntimePort; paddockDir: string; callModel: AsyncCompleteFn;
                    name, question, context: string): Future[Result[string, string]] {.async.} =
  ## `ask_agent`: one question to one named agent, answered in its persona.
  let loaded = loadNamedAgent(fs, paddockDir, name)
  if loaded.isErr:
    return err(Result[string, string], "Error: no agent @" & name & " (" & loaded.error & ")")
  let text = (if context.strip.len > 0: "Context from the user's main assistant:\n" &
                context.strip & "\n\n" else: "") & question
  return await askOnce(callModel, loaded.get, text)

proc conveneNamedAgents*(fs: FsRuntimePort; paddockDir: string; callModel: AsyncCompleteFn;
                         names: seq[string]; question, context: string;
                         rounds: int): Future[Result[string, string]] {.async.} =
  ## `convene_agents`: each agent answers alone; in each further round each
  ## reads the others' latest answers and revises. The caller is the lead and
  ## writes the synthesis from the returned transcript.
  if names.len < MinRoomAgents or names.len > MaxRoomAgents:
    return err(Result[string, string], "Error: a room takes " & $MinRoomAgents & "-" & $MaxRoomAgents & " agents")
  var agents: seq[LoadedAgent]
  for name in names:
    let loaded = loadNamedAgent(fs, paddockDir, name)
    if loaded.isErr:
      return err(Result[string, string], "Error: no agent @" & name)
    agents.add(loaded.get)
  let roundCount = max(1, min(rounds, MaxRoomRounds))
  let opening = (if context.strip.len > 0: "Context:\n" & context.strip & "\n\n" else: "") &
                "Question for the group: " & question
  var latest = newSeq[string](agents.len)
  var transcript = "# Room: " & question & "\n"
  for round in 1 .. roundCount:
    var futures: seq[Future[Result[string, string]]]
    for i, agent in agents:
      var prompt = opening
      if round > 1:
        prompt.add("\n\nThe other agents answered:\n")
        for j, other in agents:
          if j != i:
            prompt.add("\n@" & other.agent.name & ":\n" & latest[j] & "\n")
        prompt.add("\nReply briefly: where you agree, where you disagree, and " &
                   "your revised answer.")
      futures.add(askOnce(callModel, agent, prompt))
    ## Every call of the round has started (an async proc runs up to its first
    ## await, where the provider job goes to a worker); wait for all of them
    ## before reading any, so none is left pending if one fails.
    await allFutures(futures)
    transcript.add("\n## Round " & $round & "\n")
    for i, fut in futures:
      let answer = fut.read()
      latest[i] = if answer.isOk: answer.get else: "(no answer: " & answer.error & ")"
      transcript.add("\n### @" & agents[i].agent.name & "\n" & latest[i] & "\n")
  return ok(Result[string, string], transcript)
