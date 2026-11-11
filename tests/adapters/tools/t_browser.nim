## Tests for BrowserTools adapter — ToolPort implementation via Lightpanda CDP.
##
## Tests cover:
##   - ToolPort concept conformance (listTools, invoke)
##   - browser_navigate, browser_content, browser_screenshot schema validation
##   - Input validation for required parameters
##   - SSRF blocking on private URLs
##   - Error handling when Lightpanda is not installed
##   - Error handling when browser is not running (call content/screenshot first)

import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/tools/browser
import donkey/domain/tools/browser_pure
import donkey/ports/tool
import donkey/core/pipeops

# ── Test fixtures ──────────────────────────────────────────────────────────────

# ── Concept conformance ───────────────────────────────────────────────────────

suite "ToolPort conformance":

  test "BrowserTools satisfies ToolPort concept":
    ## Compile-time proof: BrowserTools implements ToolPort.
    ## If this test file compiles, the concept is satisfied.
    var bt = BrowserTools()
    let tools = bt.listTools()
    check tools.isOk
    # invoke returns Result - even errors are isOk=false, not exceptions
    let call = ToolCall(id: "test", name: "unknown_tool", input: %* {})
    let res = bt.invoke(call)
    check res.isOk  # Result type is ok, even if the tool is unknown

  test "listTools returns exactly three schemas":
    let bt = BrowserTools()
    let result = bt.listTools()
    check result.isOk
    let tools = result.get()
    check tools.len == 3

  test "browser_navigate schema":
    let bt = BrowserTools()
    let tools = bt.listTools().get()
    let schema = tools.filterIt(it.name == "browser_navigate")[0]
    check schema.name == "browser_navigate"
    check schema.description.len > 0
    check schema.inputSchema.kind == JObject
    # url is required
    let required = schema.inputSchema.getOrDefault("required")
    check required.kind == JArray
    check schema.inputSchema{"properties"}.hasKey("url")

  test "browser_content schema":
    let bt = BrowserTools()
    let tools = bt.listTools().get()
    let schema = tools.filterIt(it.name == "browser_content")[0]
    check schema.name == "browser_content"
    check schema.description.len > 0
    check schema.inputSchema.kind == JObject
    check schema.inputSchema{"properties"}.hasKey("max_chars")
    check schema.inputSchema{"properties"}.hasKey("as_html")

  test "browser_screenshot schema":
    let bt = BrowserTools()
    let tools = bt.listTools().get()
    let schema = tools.filterIt(it.name == "browser_screenshot")[0]
    check schema.name == "browser_screenshot"
    check schema.description.len > 0
    check schema.inputSchema.kind == JObject
    check schema.inputSchema{"properties"}.hasKey("fullPage")

suite "Input validation":

  test "browser_navigate rejects missing url":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.callId == "test"
    check tr.output.contains("missing required field")

  test "browser_navigate rejects empty url":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": ""})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError

  test "browser_navigate rejects private/internal URLs (SSRF block)":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "http://127.0.0.1:8080/admin"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.output.contains("private") or tr.output.contains("not allowed")

  test "browser_navigate rejects non-HTTP schemes":
    var bt = BrowserTools(backend: bbOff)
    for url in ["file:///etc/passwd", "data:text/html,hello", "chrome://settings"]:
      let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": url})
      let tr = bt.invoke(call).get()
      check tr.isError
      check tr.output.contains("http/https") or tr.output.contains("not allowed")

  test "browser_navigate rejects localhost":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "http://localhost:8080/"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError

  test "browser_navigate rejects 10.x private range":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "http://10.0.0.1:8080/"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError

  test "browser_navigate rejects 192.168.x range":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "http://192.168.1.1/"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError

  test "browser_navigate rejects 172.16-31.x range":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "http://172.16.0.1/"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError

  test "browser_content errors when browser not running":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_content", input: %* {})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.output.contains("browser not running") or tr.output.contains("navigate first")

  test "browser_screenshot errors when browser not running":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "browser_screenshot", input: %* {})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.output.contains("browser not running") or tr.output.contains("navigate first")

  test "browser_navigate returns error when lightpanda not installed":
    var bt = BrowserTools(lightpandaPath: "/nonexistent/lightpanda")
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "https://example.com"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.output.contains("not found") or tr.output.contains("Install")

  test "unknown tool returns error":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "nonexistent_tool", input: %* {})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.output.contains("unknown tool")

suite "Constructor":
  test "newBrowserTools with default args":
    let bt = newBrowserTools()
    check bt.lightpandaPath == ""
    check bt.host == "127.0.0.1"
    check bt.port == 9222

  test "newBrowserTools with custom path":
    let bt = newBrowserTools(lightpandaPath = "/usr/local/bin/lightpanda")
    check bt.lightpandaPath == "/usr/local/bin/lightpanda"

  test "newBrowserTools with custom host/port":
    let bt = newBrowserTools(host = "0.0.0.0", port = 9333)
    check bt.host == "0.0.0.0"
    check bt.port == 9333

suite "Browser backends":

  test "newBrowserTools selects Edge and stores its executable":
    let bt = newBrowserTools(backend = bbEdge,
                             executablePath = "/opt/microsoft-edge")
    check bt.backend == bbEdge
    check bt.executablePath == "/opt/microsoft-edge"
    check bt.lightpandaPath == ""

  test "navigate reports a disabled backend":
    var bt = BrowserTools(backend: bbOff)
    let call = ToolCall(id: "test", name: "browser_navigate",
                        input: %* {"url": "https://example.com"})
    let tr = bt.invoke(call).get()
    check tr.isError
    check tr.output.contains("disabled")

  test "navigate reports a missing Edge executable":
    var bt = BrowserTools(backend: bbEdge,
                          executablePath: "/nonexistent/microsoft-edge")
    let call = ToolCall(id: "test", name: "browser_navigate",
                        input: %* {"url": "https://example.com"})
    let tr = bt.invoke(call).get()
    check tr.isError
    check tr.output.contains("not found")

  test "toRuntimePort exposes the browser tools":
    let port = newBrowserTools(backend = bbOff).toRuntimePort()
    let tools = port.listTools().get()
    check tools.len == 3
    port.close()
