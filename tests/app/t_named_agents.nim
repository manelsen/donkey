## manage_agents: the user's named agents created, listed, changed and removed
## from the chat, and an agent's own notes. Real files in a temp paddock.

import std/[json, os, strutils, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/app/named_agents
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

    test "an empty list says how to create one":
      let r = run(%* {"action": "list"})
      check r.isOk and "manage_agents" in r.get

    test "a subagent can never manage the user's agents":
      check "manage_agents" in SubagentHardDeniedTools

when isMainModule:
  runTests()
