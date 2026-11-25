## manage_agents: the user's named agents created, listed, changed and removed
## from the chat, and an agent's own notes. Real files in a temp paddock.

import std/[json, os, sequtils, strutils, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/named_agents
import donkey/app/native_tools
import donkey/app/provider_executor
import donkey/app/session_state
import donkey/core/types
import donkey/domain/message
import donkey/core/pipeops
import donkey/core/tooling/native_tool_args
import donkey/domain/agents/named_agent_pure
import donkey/domain/subagent_pure

const Paddock = "/tmp/donkey_t_named_agents"

proc run(args: JsonNode): Result[string, string] =
  let ctx = ? parseManageAgentsContext(args)
  performManageAgents(newFsAdapter(), Paddock, ctx)

proc runTests*() =
  suite "manage_agents":
    setup:
      removeDir(Paddock)
      createDir(Paddock)

    test "create, then the agent is on disk and in the list":
      let r = run(%* {"action": "create", "name": "revisor",
                      "description": "Revisa código com rigor.", "provider": "anthropic"})
      check r.isOk and "revisor" in r.get
      let loaded = loadNamedAgent(newFsAdapter(), Paddock, "revisor")
      check loaded.isOk and loaded.get.agent.provider == "anthropic"
      let listed = run(%* {"action": "list"})
      check listed.isOk and "revisor" in listed.get and "Revisa código" in listed.get

    test "an existing name is not overwritten by create":
      discard run(%* {"action": "create", "name": "a", "description": "um"})
      check run(%* {"action": "create", "name": "a", "description": "dois"}).isErr
      check loadNamedAgent(newFsAdapter(), Paddock, "a").get.agent.description == "um"

    test "update changes only what it is given":
      discard run(%* {"action": "create", "name": "a", "description": "um", "model": "m1"})
      check run(%* {"action": "update", "name": "a", "model": "m2"}).isOk
      let a = loadNamedAgent(newFsAdapter(), Paddock, "a").get.agent
      check a.description == "um" and a.model == "m2"

    test "delete removes the agent and its notes":
      discard run(%* {"action": "create", "name": "a", "description": "um"})
      discard run(%* {"action": "note", "name": "a", "text": "lembrar X"})
      check run(%* {"action": "delete", "name": "a"}).isOk
      check loadNamedAgent(newFsAdapter(), Paddock, "a").isErr
      check not fileExists(Paddock / "agents" / "a.notes.md")

    test "notes are appended and reach the agent's turn":
      discard run(%* {"action": "create", "name": "a", "description": "um"})
      check run(%* {"action": "note", "name": "a", "text": "prefere PRs pequenos"}).isOk
      check run(%* {"action": "note", "name": "a", "text": "usa Nim"}).isOk
      let notes = loadNamedAgent(newFsAdapter(), Paddock, "a").get.notes
      check "prefere PRs pequenos" in notes and "usa Nim" in notes

    test "bad names and unknown agents are refused":
      check run(%* {"action": "create", "name": "../x", "description": "d"}).isErr
      check run(%* {"action": "create", "name": "Upper", "description": "d"}).isErr
      check run(%* {"action": "delete", "name": "ghost"}).isErr
      check run(%* {"action": "note", "name": "ghost", "text": "x"}).isErr
      check run(%* {"action": "create", "name": "a"}).isErr   ## no description
      discard run(%* {"action": "create", "name": "b", "description": "d"})
      check run(%* {"action": "note", "name": "b", "text": "   "}).isErr

    test "an empty list says how to create one":
      let r = run(%* {"action": "list"})
      check r.isOk and "manage_agents" in r.get

    test "a subagent can never manage the user's agents":
      check "manage_agents" in SubagentHardDeniedTools

  suite "agents talking to each other":
    setup:
      removeDir(Paddock)
      createDir(Paddock / "agents")
      writeFile(Paddock / "agents" / "revisor.toml",
        "name = \"revisor\"\ndescription = \"Revisa com rigor.\"\nprovider = \"anthropic\"\n")
      writeFile(Paddock / "agents" / "revisor.notes.md", "- prefere testes")
      writeFile(Paddock / "agents" / "otimista.toml",
        "name = \"otimista\"\ndescription = \"Vê o lado bom.\"\n")

    var seen {.threadvar.}: seq[CompletionRequest]
    proc fakeAsync(): AsyncCompleteFn =
      result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        {.cast(gcsafe).}: seen.add(req)
        let who = if "revisor" in req.system: "revisor" else: "otimista"
        return ok(CompletionResponse(text: who & " responde (" & $req.messages.len & ")"))

    proc ctxFor(): NativeCtx =
      NativeCtx(uid: UserId("u"), channel: ckCli, paddockDir: Paddock,
                fs: newFsAdapter(), asyncCompleteFn: fakeAsync())

    test "ask_agent: one call with that agent's persona, notes and model":
      seen = @[]
      let r = waitFor askNamedAgent(newFsAdapter(), Paddock, fakeAsync(), "revisor", "o diff está bom?", "PR #9")
      check r.isOk and r.get.startsWith("revisor responde")
      check seen.len == 1
      check "Revisa com rigor." in seen[0].system and "prefere testes" in seen[0].system
      check seen[0].providerOverride == "anthropic"
      check seen[0].tools.len == 0   ## no tools wired in this call
      check "PR #9" in seen[0].messages[0].text and "o diff está bom?" in seen[0].messages[0].text

    test "ask_agent: an unknown agent is an error and no call":
      seen = @[]
      check (waitFor askNamedAgent(newFsAdapter(), Paddock, fakeAsync(), "ghost", "q", "")).isErr
      check seen.len == 0

    test "convene: every agent answers, then sees the others and revises":
      seen = @[]
      let r = waitFor conveneNamedAgents(newFsAdapter(), Paddock, fakeAsync(), @["revisor", "otimista"],
                                         "vale migrar?", "", rounds = 2)
      check r.isOk
      check seen.len == 4
      let transcript = r.get
      check "Round 1" in transcript and "Round 2" in transcript
      check "@revisor" in transcript and "@otimista" in transcript
      ## in round 2 each one sees the other's round-1 answer
      let second = seen[2 .. 3]
      check second.anyIt("otimista responde" in it.messages[^1].text)
      check second.anyIt("revisor responde" in it.messages[^1].text)

    test "convene: limits and unknown names":
      check (waitFor conveneNamedAgents(newFsAdapter(), Paddock, fakeAsync(), @["revisor"], "q", "", 1)).isErr
      check (waitFor conveneNamedAgents(newFsAdapter(), Paddock, fakeAsync(), @["revisor", "ghost"], "q", "", 1)).isErr
      check (waitFor conveneNamedAgents(newFsAdapter(), Paddock, fakeAsync(), @["revisor", "otimista"], "q", "", 9)).isOk

    test "the tools are dispatched for real (manage_agents, ask_agent, convene_agents)":
      seen = @[]
      let state = newSessionState()
      let listed = waitFor executeNativeTool(ToolCallRequest(id: "1", name: "manage_agents",
        inputJson: """{"action":"list"}"""), ctxFor(), state, @[])
      check listed.handled and "@revisor" in listed.text
      let asked = waitFor executeNativeTool(ToolCallRequest(id: "2", name: "ask_agent",
        inputJson: """{"name":"revisor","question":"ok?"}"""), ctxFor(), state, @[])
      check asked.handled and "revisor responde" in asked.text
      let room = waitFor executeNativeTool(ToolCallRequest(id: "3", name: "convene_agents",
        inputJson: """{"agents":["revisor","otimista"],"question":"q","rounds":1}"""),
        ctxFor(), state, @[])
      check room.handled and "@otimista" in room.text

    proc lookupModel(): AsyncCompleteFn =
      ## Looks something up first, then answers with what it found.
      result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        {.cast(gcsafe).}: seen.add(req)
        for m in req.messages:
          if m.role == roleTool:
            return ok(CompletionResponse(text: "segundo o histórico: " & m.text))
        return ok(CompletionResponse(toolCalls: @[ToolCallRequest(
          id: "c1", name: "session_search", inputJson: """{"phrase":"senha"}""")]))

    proc fakeTools(): ConsultTools =
      ConsultTools(
        tools: consultedAgentToolDescriptions(webSearch = false),
        run: proc(call: ToolCallRequest): Future[ConsultToolResult] {.async.} =
          return ConsultToolResult(text: "achei '" & call.name & "'"))

    test "a consulted agent may look things up, then answers from it":
      seen = @[]
      let r = waitFor askNamedAgent(newFsAdapter(), Paddock, lookupModel(), "revisor",
                                    "qual era a senha?", "", consult = fakeTools())
      check r.isOk
      check r.get.startsWith("segundo o histórico:")
      check "achei 'session_search'" in r.get   ## the tool's output reached it
      check seen.len == 2
      check seen[0].tools.anyIt(it.name == "session_search")

    test "consulted agents get read-only tools, and web search only with a key":
      let names = consultedAgentToolDescriptions(webSearch = false).mapIt(it.name)
      check names == @["session_search", "current_time", "calc", "fetch", "web_fetch"]
      check "web_search" in consultedAgentToolDescriptions(webSearch = true).mapIt(it.name)
      for denied in ["ask_agent", "convene_agents", "manage_agents", "bash", "fs_write"]:
        check denied notin names
        check denied notin ConsultedAgentToolNames

    test "the last round offers no tools, so the agent has to answer":
      seen = @[]
      let stubborn: AsyncCompleteFn = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        {.cast(gcsafe).}: seen.add(req)
        if req.tools.len > 0:
          return ok(CompletionResponse(toolCalls: @[ToolCallRequest(
            id: "c" & $req.messages.len, name: "calc", inputJson: """{"expression":"1+1"}""")]))
        return ok(CompletionResponse(text: "respondo sem mais buscas"))
      let r = waitFor askNamedAgent(newFsAdapter(), Paddock, stubborn, "revisor", "q", "",
                                    consult = fakeTools())
      check r.get == "respondo sem mais buscas"
      check seen.len == MaxConsultedToolRounds + 1
      check seen[^1].tools.len == 0

    test "a blank final answer is an error, not an empty reply":
      let mute: AsyncCompleteFn = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        return ok(CompletionResponse(text: "  "))
      let r = waitFor askNamedAgent(newFsAdapter(), Paddock, mute, "revisor", "q", "")
      check r.isErr and "no answer" in r.error

    test "an agent that takes too long is an error, and a room still finishes":
      let slow: AsyncCompleteFn = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
        if "revisor" in req.system:
          await sleepAsync(chronos.milliseconds(2000))
        return ok(CompletionResponse(text: "pronto"))
      let one = waitFor askNamedAgent(newFsAdapter(), Paddock, slow, "revisor", "q", "",
                                      deadlineMs = 200)
      check one.isErr and "too long" in one.error
      let room = waitFor conveneNamedAgents(newFsAdapter(), Paddock, slow,
        @["revisor", "otimista"], "q", "", 1, deadlineMs = 200)
      check room.isOk
      check "too long" in room.get and "pronto" in room.get

    test "through the real tools, a consulted agent cannot call agents or write":
      let ctx = consultedAgentCtx(ctxFor(), "revisor")
      let state = newSessionState()
      for denied in ["ask_agent", "convene_agents", "manage_agents", "fs_write", "bash"]:
        let r = waitFor executeNativeTool(ToolCallRequest(id: "x", name: denied,
          inputJson: "{}"), ctx, state, @[])
        check r.handled and "not allowed" in r.text
      let time = waitFor executeNativeTool(ToolCallRequest(id: "t", name: "current_time",
        inputJson: "{}"), ctx, state, @[])
      check time.handled and "not allowed" notin time.text

    test "subagents cannot call or convene the user's agents":
      check "ask_agent" in SubagentHardDeniedTools
      check "convene_agents" in SubagentHardDeniedTools

when isMainModule:
  runTests()
