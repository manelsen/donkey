## Skill processes on the event loop (PRD-roadmap E5 follow-up): one client
## per skill, shared by every session; its tools are listed in the background
## the first time a session asks, and come into sessions built after that.

import std/[json, os, unittest]
import chronos
import donkey/adapters/tool/mcp_client
import donkey/adapters/tool/runtime_builder
import donkey/core/pipeops
import donkey/ports/tool

const FakeSkill = """
import json, sys
for line in sys.stdin:
    msg = json.loads(line)
    mid, method = msg.get("id"), msg.get("method")
    if mid is None or method is None:
        continue
    if method == "initialize":
        r = {"protocolVersion": "2024-11-05", "capabilities": {}}
    elif method == "tools/list":
        r = {"tools": [{"name": "greet", "description": "Greets", "inputSchema": {"type": "object"}}]}
    else:
        r = {"content": [{"type": "text", "text": "hello " + msg["params"]["arguments"].get("name", "")}]}
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": r}) + "\n"); sys.stdout.flush()
"""

proc fakeScript(): string =
  result = getTempDir() / "donkey_fake_skill.py"
  writeFile(result, FakeSkill)

proc runTests*() =
  suite "skill clients":

    test "a skill is listed in the background, then reused by later sessions":
      var made = 0
      let skills = newSkillClients(proc(script: string; perms: seq[string]): McpClient =
        inc made
        newMcpClient("python3", @["-u", fakeScript()], timeoutMs = 5_000))
      let build = skills.builder()
      let first = build("greet.ts", @[], SkillRuntimePolicy())
      check first.isOk
      check first.get.schemas.len == 0          ## not listed yet: no wait
      for _ in 0 ..< 100:
        if skills.listedCount() == 1: break
        waitFor sleepAsync(chronos.milliseconds(20))
      let second = build("greet.ts", @[], SkillRuntimePolicy())
      check second.get.schemas.len == 1 and second.get.schemas[0].name == "greet"
      check made == 1                            ## one process for every session
      let r = waitFor second.get.port.invokeAsync(
        ToolCall(id: "c1", name: "greet", input: %* {"name": "Belle"}))
      check r.isOk and r.get.output == "hello Belle"
      waitFor skills.closeAll()

    test "permissions the policy refuses are refused before anything starts":
      var made = 0
      let skills = newSkillClients(proc(script: string; perms: seq[string]): McpClient =
        inc made
        newMcpClient("python3", @["-u", fakeScript()]))
      let r = skills.builder()("x.ts", @["--allow-all"], SkillRuntimePolicy())
      check r.isErr
      check made == 0

    test "a skill whose listing fails is tried again by a later session":
      var made = 0
      let skills = newSkillClients(proc(script: string; perms: seq[string]): McpClient =
        inc made
        newMcpClient("/nonexistent/skill-runner", timeoutMs = 1_000))
      discard skills.builder()("x.ts", @[], SkillRuntimePolicy())
      for _ in 0 ..< 100:
        if skills.failedCount() == 1: break
        waitFor sleepAsync(chronos.milliseconds(20))
      check skills.failedCount() == 1
      discard skills.builder()("x.ts", @[], SkillRuntimePolicy())
      check made == 1   ## the same client, asked to list again

when isMainModule:
  runTests()
