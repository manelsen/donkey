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
      check seen[0].tools.len == 0
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

    test "subagents cannot call or convene the user's agents":
      check "ask_agent" in SubagentHardDeniedTools
      check "convene_agents" in SubagentHardDeniedTools

when isMainModule:
  runTests()
