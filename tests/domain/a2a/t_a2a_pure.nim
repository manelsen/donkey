## E13.4: A2A (v1.0, JSON-RPC binding) — the server's pure core.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/a2a/a2a_pure

proc runTests*() =
  suite "a2a — agent card":
    test "the card has the v1.0 required fields and one JSON-RPC interface":
      let card = agentCard(CardInfo(name: "Donkey", description: "Assistente da equipe",
                                    url: "https://d.example/a2a", version: "1.2.3"))
      for key in ["name", "description", "supportedInterfaces", "version", "capabilities",
                  "defaultInputModes", "defaultOutputModes", "skills"]:
        check card.hasKey(key)
      let iface = card["supportedInterfaces"][0]
      check iface["url"].getStr == "https://d.example/a2a"
      check iface["protocolBinding"].getStr == "JSONRPC"
      check iface["protocolVersion"].getStr == "1.0"
      check card["capabilities"]["streaming"].getBool == false
      check card["skills"].len == 1
      ## a bearer token, as the requirement every request must meet
      check card["securitySchemes"].hasKey("bearer")
      check card["securityRequirements"][0]["schemes"].hasKey("bearer")

  suite "a2a — the public URL":
    test "https, or http on loopback only; it must end at /a2a":
      check publicA2aUrl("https://d.example/a2a").get == "https://d.example/a2a"
      check publicA2aUrl(" https://d.example/a2a/ ").get == "https://d.example/a2a"
      check publicA2aUrl("http://127.0.0.1:8080/a2a").isOk
      check publicA2aUrl("http://localhost:8080/a2a").isOk
      check publicA2aUrl("http://d.example/a2a").isErr
      check publicA2aUrl("https://d.example/").isErr
      check publicA2aUrl("ftp://d.example/a2a").isErr
      ## the host is compared whole, not as a prefix; no credentials in the card
      check publicA2aUrl("http://127.0.0.1.evil.com/a2a").isErr
      check publicA2aUrl("http://localhostfoo/a2a").isErr
      check publicA2aUrl("https://user:pass@d.example/a2a").isErr

  suite "a2a — reading a request":
    test "a JSON-RPC call: method, id and params":
      let c = parseRpc("""{"jsonrpc":"2.0","id":7,"method":"SendMessage","params":{"a":1}}""")
      check c.isOk and c.get.meth == "SendMessage" and c.get.id == %7
      check c.get.params["a"].getInt == 1

    test "not JSON, not 2.0, no method: the JSON-RPC errors":
      check parseRpc("{oops").error.code == -32700
      check parseRpc("""{"jsonrpc":"1.0","id":1,"method":"X"}""").error.code == -32600
      check parseRpc("""{"jsonrpc":"2.0","id":1}""").error.code == -32600
      check parseRpc("[]").error.code == -32600

    test "the message's text, v1.0 parts and the 0.3 ones; ids kept":
      let v1 = %*{"message": {"messageId": "m1", "role": "ROLE_USER", "contextId": "c1",
                              "parts": [{"text": "oi"}, {"text": "tudo bem?"}]}}
      let m = incomingMessage(v1)
      check m.isOk and m.get.text == "oi\ntudo bem?" and m.get.contextId == "c1"
      let v03 = %*{"message": {"messageId": "m2", "role": "user",
                               "parts": [{"kind": "text", "text": "olá"}, {"kind": "file"}]}}
      check incomingMessage(v03).get.text == "olá"

    test "a message without text is invalid params":
      check incomingMessage(%*{"message": {"parts": [{"url": "x"}]}}).isErr
      check incomingMessage(%*{}).isErr

  suite "a2a — answering":
    test "a completed task carries the reply as an artifact and in its status":
      let t = A2aTask(id: "t1", contextId: "c1", state: tsCompleted, reply: "pronto",
                      timestamp: "2026-11-27T22:00:00Z")
      let j = taskJson(t)
      check j["id"].getStr == "t1" and j["contextId"].getStr == "c1"
      check j["status"]["state"].getStr == "TASK_STATE_COMPLETED"
      check j["status"]["message"]["role"].getStr == "ROLE_AGENT"
      check j["status"]["message"]["parts"][0]["text"].getStr == "pronto"
      check j["artifacts"][0]["parts"][0]["text"].getStr == "pronto"

    test "SendMessage answers {task}; errors keep the id":
      let t = A2aTask(id: "t1", contextId: "c1", state: tsFailed, reply: "erro")
      let ok = rpcResult(%7, %*{"task": taskJson(t)})
      check ok["jsonrpc"].getStr == "2.0" and ok["id"] == %7
      check ok["result"]["task"]["status"]["state"].getStr == "TASK_STATE_FAILED"
      let e = rpcError(%"x", RpcError(code: -32001, message: "Task not found"))
      check e["error"]["code"].getInt == -32001 and e["id"] == %"x"

when isMainModule:
  runTests()
