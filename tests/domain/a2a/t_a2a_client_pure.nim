## E13.4: A2A's client side — the agents Donkey may delegate to, and the wire.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/a2a/a2a_client_pure

proc runTests*() =
  suite "a2a client — the allowed agents":
    test "[[a2a.agents]]: name, url, token_env":
      let cfg = %*{"agents": [
        {"name": "planner", "url": "https://p.example/a2a/", "token_env": "A2A_PLANNER_TOKEN",
         "description": "Planeja viagens"},
        {"name": "local", "url": "http://127.0.0.1:9000/a2a", "token_env": "A2A_LOCAL"}]}
      let agents = parseA2aAgents(cfg)
      check agents.isOk and agents.get.len == 2
      check agents.get[0].url == "https://p.example/a2a"
      check agents.get[0].description == "Planeja viagens"
      check agents.get[1].host == "127.0.0.1"

    test "what is refused: plain http away from loopback, no token, a bad or repeated name":
      check parseA2aAgents(%*{"agents": [{"name": "x", "url": "http://p.example/a2a", "token_env": "T"}]}).isErr
      check parseA2aAgents(%*{"agents": [{"name": "x", "url": "https://p.example/a2a"}]}).isErr
      check parseA2aAgents(%*{"agents": [{"name": "Com Espaço", "url": "https://p/a2a", "token_env": "T"}]}).isErr
      let twice = %*{"agents": [{"name": "x", "url": "https://a/a2a", "token_env": "T"},
                                {"name": "x", "url": "https://b/a2a", "token_env": "U"}]}
      check parseA2aAgents(twice).isErr
      check parseA2aAgents(%*{}).get.len == 0

  suite "a2a client — the wire":
    test "SendMessage in v1.0, message/send in v0.3":
      let v1 = parseJson(sendRequest("oi", "m1", legacy = false))
      check v1["method"].getStr == "SendMessage"
      check v1["params"]["message"]["role"].getStr == "ROLE_USER"
      check v1["params"]["message"]["parts"][0]["text"].getStr == "oi"
      let v03 = parseJson(sendRequest("oi", "m1", legacy = true))
      check v03["method"].getStr == "message/send"
      check v03["params"]["message"]["role"].getStr == "user"
      check v03["params"]["message"]["parts"][0]["kind"].getStr == "text"
      check parseJson(getTaskRequest("t1", legacy = false))["method"].getStr == "GetTask"
      check parseJson(getTaskRequest("t1", legacy = true))["method"].getStr == "tasks/get"

    test "a finished v1.0 task: its artifacts' text":
      let body = $(%*{"jsonrpc": "2.0", "id": 1, "result": {"task": {"id": "t1",
        "status": {"state": "TASK_STATE_COMPLETED"},
        "artifacts": [{"parts": [{"text": "plano pronto"}]}]}}})
      let o = parseOutcome(body)
      check o.isOk and o.get.done and not o.get.failed and o.get.text == "plano pronto"

    test "a v0.3 task, a direct message, a task still working":
      let old = $(%*{"jsonrpc": "2.0", "id": 1, "result": {"kind": "task", "id": "t2",
        "status": {"state": "completed", "message": {"parts": [{"kind": "text", "text": "ok"}]}}}})
      check parseOutcome(old).get.text == "ok"
      let msg = $(%*{"jsonrpc": "2.0", "id": 1, "result": {"message": {"role": "ROLE_AGENT",
        "parts": [{"text": "direto"}]}}})
      check parseOutcome(msg).get.done and parseOutcome(msg).get.text == "direto"
      let working = $(%*{"jsonrpc": "2.0", "id": 1, "result": {"task": {"id": "t3",
        "status": {"state": "TASK_STATE_WORKING"}}}})
      let w = parseOutcome(working).get
      check not w.done and w.taskId == "t3"

    test "failed or rejected tasks, input-required, and JSON-RPC errors":
      let failed = $(%*{"jsonrpc": "2.0", "id": 1, "result": {"task": {"id": "t",
        "status": {"state": "TASK_STATE_FAILED", "message": {"parts": [{"text": "sem acesso"}]}}}}})
      let f = parseOutcome(failed).get
      check f.done and f.failed and "sem acesso" in f.text
      let asks = $(%*{"jsonrpc": "2.0", "id": 1, "result": {"task": {"id": "t",
        "status": {"state": "TASK_STATE_INPUT_REQUIRED", "message": {"parts": [{"text": "qual data?"}]}}}}})
      let a = parseOutcome(asks).get
      check a.done and not a.failed and "qual data?" in a.text   ## the question comes back as the answer
      let unknown = $(%*{"jsonrpc": "2.0", "id": 1, "error": {"code": -32601, "message": "Method not found"}})
      check parseOutcome(unknown).isErr and isMethodNotFound(unknown)
      check parseOutcome("<html>").isErr

  suite "a2a client — the tool":
    test "its schema offers only the configured agents; its description says what each does":
      let agents = @[A2aAgent(name: "planner", description: "Planeja viagens"),
                     A2aAgent(name: "local")]
      let schema = parseJson(delegateToolSchema(agents))
      check schema["properties"]["agent"]["enum"] == %["planner", "local"]
      check schema["required"] == %["agent", "task"]
      let d = delegateToolDescription(agents)
      check "planner: Planeja viagens" in d and "local" in d
      check DelegateToolName == "delegate_to_agent"

    test "the approval shows the agent and the whole task":
      let s = delegateSummary(A2aAgent(name: "planner", url: "https://p.example/a2a"), "reserve um hotel")
      check "planner" in s and "https://p.example/a2a" in s and "reserve um hotel" in s

when isMainModule:
  runTests()
