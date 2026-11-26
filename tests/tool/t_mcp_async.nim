## The MCP stdio client, asynchronous (PRD-roadmap E5.0): a real subprocess
## (a fake server in Python), driven on the event loop without blocking it.
## The server writes log lines on stderr, notifications between messages,
## and a request of its own in the middle of a call, as real servers do.

import std/[json, os, strutils, unittest]
import chronos
import donkey/adapters/tool/mcp_client
import donkey/core/pipeops
import donkey/ports/tool

const FakeServer = """
import json, sys, time
def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    msg = json.loads(line)
    sys.stderr.write("log: got " + str(msg.get("method")) + "\n"); sys.stderr.flush()
    if "method" not in msg:
        continue                      # a response to our own request, handled inline
    mid, method = msg.get("id"), msg["method"]
    if mid is None:
        continue                      # a notification
    send({"jsonrpc": "2.0", "method": "notifications/message", "params": {"level": "info"}})
    if method == "initialize":
        caps = msg["params"]["capabilities"]
        send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": "2024-11-05",
              "capabilities": {"tools": {}}, "serverInfo": {"name": "fake"},
              "echoCaps": caps}})
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": [
            {"name": "echo", "description": "Echo", "inputSchema": {"type": "object"}}]}})
    elif method == "tools/call":
        name = msg["params"]["name"]
        args = msg["params"]["arguments"]
        if name == "slow":
            time.sleep(float(args.get("seconds", 1)))
            text = "slept"
        elif name == "ask":
            send({"jsonrpc": "2.0", "id": "s-1", "method": "sampling/createMessage",
                  "params": {"messages": [{"role": "user",
                             "content": {"type": "text", "text": "2+2?"}}], "maxTokens": 10}})
            reply = json.loads(sys.stdin.readline())
            if "result" in reply:
                text = "model said: " + reply["result"]["content"]["text"]
            else:
                text = "refused: " + reply["error"]["message"]
        elif name == "odd":
            send({"jsonrpc": "2.0", "id": mid, "method": "odd",
                  "result": {"content": [{"type": "text", "text": "odd but mine"}]}})
            continue
        else:
            text = "echo:" + json.dumps(args, sort_keys=True)
        send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": text}]}})
    else:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no " + method}})
"""

proc serverScript(): string =
  result = getTempDir() / "donkey_fake_mcp.py"
  writeFile(result, FakeServer)

proc client(handler: ServerRequestHandler = nil; timeoutMs = 10_000): McpClient =
  newMcpClient("python3", @["-u", serverScript()], timeoutMs = timeoutMs,
               onServerRequest = handler)

proc runTests*() =
  suite "mcp stdio client — asynchronous":

    test "tools are listed and called, through stderr logs and notifications":
      let c = client()
      defer: waitFor c.closeAsync()
      let tools = waitFor c.listToolsAsync()
      check tools.isOk
      check tools.get.len == 1 and tools.get[0].name == "echo"
      let r = waitFor c.invokeAsync(ToolCall(id: "c1", name: "echo", input: %* {"a": 1}))
      check r.isOk
      check r.get.output == """echo:{"a": 1}"""

    test "the loop keeps running while a call is in flight":
      let c = client()
      defer: waitFor c.closeAsync()
      discard waitFor c.listToolsAsync()
      var ticks = 0
      proc ticker() {.async.} =
        for _ in 0 ..< 20:
          await sleepAsync(chronos.milliseconds(25))
          inc ticks
      let ticking = ticker()
      let r = waitFor c.invokeAsync(ToolCall(id: "c2", name: "slow", input: %* {"seconds": 0.6}))
      waitFor ticking
      check r.isOk and r.get.output == "slept"
      check ticks == 20

    test "a call that takes too long is an error, not a hang":
      let c = client(timeoutMs = 300)
      defer: waitFor c.closeAsync()
      discard waitFor c.listToolsAsync()
      let r = waitFor c.invokeAsync(ToolCall(id: "c3", name: "slow", input: %* {"seconds": 3}))
      check r.isErr and "timed out" in r.error

    test "calls from two sessions on one client do not mix their answers":
      let c = client()
      defer: waitFor c.closeAsync()
      discard waitFor c.listToolsAsync()
      let a = c.invokeAsync(ToolCall(id: "a", name: "echo", input: %* {"who": "a"}))
      let b = c.invokeAsync(ToolCall(id: "b", name: "echo", input: %* {"who": "b"}))
      check (waitFor a).get.output == """echo:{"who": "a"}"""
      check (waitFor b).get.output == """echo:{"who": "b"}"""

    test "without a handler the client offers no sampling, and refuses a request":
      let c = client()
      defer: waitFor c.closeAsync()
      discard waitFor c.listToolsAsync()
      check not c.offeredCapabilities.hasKey("sampling")
      let r = waitFor c.invokeAsync(ToolCall(id: "c4", name: "ask", input: %* {}))
      check r.isOk and r.get.output.startsWith("refused:")

    test "with a handler the client offers sampling and answers the server's request":
      let handler: ServerRequestHandler = proc(meth: string; params: JsonNode; call: ToolCall):
          Future[Result[JsonNode, string]] {.async: (raises: []), gcsafe.} =
        if meth != "sampling/createMessage":
          return err("unsupported")
        try: await sleepAsync(chronos.milliseconds(50))   ## e.g. waiting for the person
        except CancelledError: return err("cancelled")
        return ok(%* {"role": "assistant", "model": "fake",
                      "content": {"type": "text", "text": "4"}})
      let c = client(handler)
      defer: waitFor c.closeAsync()
      discard waitFor c.listToolsAsync()
      check c.offeredCapabilities.hasKey("sampling")
      let r = waitFor c.invokeAsync(ToolCall(id: "c5", name: "ask", input: %* {}))
      check r.isOk and r.get.output == "model said: 4"

    test "a response is recognised by its id, even with a stray method field":
      let c = client(timeoutMs = 3_000)
      defer: waitFor c.closeAsync()
      discard waitFor c.listToolsAsync()
      let r = waitFor c.invokeAsync(ToolCall(id: "c6", name: "odd", input: %* {}))
      check r.isOk and r.get.output == "odd but mine"

    test "the port's tool list is an error until a listing has worked":
      let c = client()
      defer: waitFor c.closeAsync()
      check c.toRuntimePort().listTools().isErr
      discard waitFor c.listToolsAsync()
      check c.toRuntimePort().listTools().get.len == 1

    test "a server that is not there is an error":
      let c = newMcpClient("/nonexistent/mcp-server", timeoutMs = 2_000)
      check (waitFor c.listToolsAsync()).isErr

when isMainModule:
  runTests()
