## Tests for BrowserTools adapter — ToolPort implementation via Lightpanda CDP.
##
## Tests cover:
##   - ToolPort concept conformance (listTools, invoke)
##   - browser_navigate, browser_content, browser_screenshot schema validation
##   - Input validation for required parameters
##   - SSRF blocking on private URLs
##   - Error handling when Lightpanda is not installed
##   - Error handling when browser is not running (call content/screenshot first)

import std/[json, os, sequtils, strtabs, strutils, tables, times, unittest]
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
    check res.isErr  # lets the tool dispatcher try the next client

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
    let call = ToolCall(id: "test", name: "browser_navigate", input: %* {"url": "https://8.8.8.8"})
    let res = bt.invoke(call)
    check res.isOk
    let tr = res.get()
    check tr.isError
    check tr.output.contains("not found") or tr.output.contains("Install")

  test "unknown tool returns an Err for dispatcher fallback":
    var bt = BrowserTools()
    let call = ToolCall(id: "test", name: "nonexistent_tool", input: %* {})
    let res = bt.invoke(call)
    check res.isErr
    check res.error.contains("unknown tool")

suite "Browser request policy":
  test "allows inline schemes used by pages":
    check isAllowedBrowserRequest("data:text/html,hello")
    check isAllowedBrowserRequest("blob:https://example.com/abc")
    check isAllowedBrowserRequest("about:blank")

  test "blocks local schemes and private destinations":
    check not isAllowedBrowserRequest("file:///etc/passwd")
    check not isAllowedBrowserRequest("chrome://settings")
    check not isAllowedBrowserRequest("http://127.0.0.1:8080/")
    check not isAllowedBrowserRequest("http://[::1]/")
    check not isAllowedBrowserRequest("http://169.254.169.254/latest/meta-data/")

  test "blocks private hosts disguised by IPv6, userinfo or port":
    check not isAllowedBrowserRequest("http://[::ffff:127.0.0.1]/")
    check not isAllowedBrowserRequest("http://user:pass@127.0.0.1:8080/")
    check not isAllowedBrowserRequest("http://localhost.:8080/")
    check not isAllowedBrowserRequest("http://0.0.0.0:8080/")

  test "documents cannot use inline content even when subresources can":
    check isAllowedBrowserRequest("data:text/html,hello", brkSubresource)
    check isAllowedBrowserRequest("blob:https://example.com/x", brkSubresource)
    check not isAllowedBrowserRequest("data:text/html,hello", brkDocument)
    check not isAllowedBrowserRequest("blob:https://example.com/x", brkDocument)

  test "WebSocket and service worker requests are denied":
    check not isAllowedBrowserRequest("wss://example.com/socket", brkWebSocket)
    check not isAllowedBrowserRequest("ws://example.com/socket", brkWebSocket)
    check not isAllowedBrowserRequest("https://example.com/sw.js", brkServiceWorker)
    check not isAllowedBrowserRequest("ftp://example.com/x", brkSubresource)

  test "the redirect second layer avoids blocking DNS":
    check isAllowedBrowserRequest("https://example.invalid/x", brkSubresource,
                                  resolveDns = false)
    check not isAllowedBrowserRequest("http://127.0.0.1/x", brkSubresource,
                                      resolveDns = false)

  test "handles non-numeric 172 labels without raising":
    check not isAllowedBrowserRequest("http://172.example.com/")

  test "allows public literal addresses":
    check isAllowedBrowserRequest("http://8.8.8.8/")

suite "CDP event policy":

  test "blocked document request aborts the browser session":
    var bt = BrowserTools(fetchEnabled: true)
    bt.handleCdpEvent(%*{
      "method": "Fetch.requestPaused",
      "params": {
        "requestId": "r1",
        "resourceType": "Document",
        "request": {"url": "http://127.0.0.1/admin"},
      },
    })
    check bt.blockedRequests == 1
    check bt.lastBlockedUrl == "http://127.0.0.1/admin"
    check "document blocked" in bt.policyViolation

  test "blocked subresource is denied without aborting the page":
    var bt = BrowserTools(fetchEnabled: true)
    bt.handleCdpEvent(%*{
      "method": "Fetch.requestPaused",
      "params": {
        "requestId": "r2",
        "resourceType": "Script",
        "request": {"url": "http://127.0.0.1/secret.js"},
      },
    })
    check bt.blockedRequests == 1
    check bt.policyViolation.len == 0

  test "paused requests are ignored when interception is disabled":
    var bt = BrowserTools(fetchEnabled: false)
    bt.handleCdpEvent(%*{
      "method": "Fetch.requestPaused",
      "params": {
        "requestId": "r3",
        "resourceType": "Document",
        "request": {"url": "http://127.0.0.1/"},
      },
    })
    check bt.blockedRequests == 0
    check bt.policyViolation.len == 0

  test "WebSocket creation is a fail-closed violation":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "Network.webSocketCreated",
      "params": {"url": "wss://example.com/socket"},
    })
    check bt.blockedWebSockets == 1
    check bt.lastBlockedUrl == "wss://example.com/socket"
    check "websocket blocked" in bt.policyViolation

  test "WebTransport creation is a fail-closed violation":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "Network.webTransportCreated",
      "params": {"url": "https://example.com/transport"},
    })
    check bt.blockedWebSockets == 1
    check "webtransport blocked" in bt.policyViolation

  test "service worker activity is a fail-closed violation":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "ServiceWorker.workerVersionUpdated",
      "params": {"versions": [{"versionId": "v1", "runningStatus": "running"}]},
    })
    check bt.blockedServiceWorkers == 1
    check "service worker" in bt.policyViolation

  test "empty service worker inventory does not abort navigation":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "ServiceWorker.workerVersionUpdated",
      "params": {"versions": []},
    })
    check bt.blockedServiceWorkers == 0
    check bt.policyViolation.len == 0

  test "service worker registration inventory is checked for entries":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "ServiceWorker.workerRegistrationUpdated",
      "params": {"registrations": []},
    })
    check bt.blockedServiceWorkers == 0
    check bt.policyViolation.len == 0
    bt.handleCdpEvent(%*{
      "method": "ServiceWorker.workerRegistrationUpdated",
      "params": {"registrations": [{"registrationId": "r1"}]},
    })
    check bt.blockedServiceWorkers == 1
    check "service worker" in bt.policyViolation

  test "service worker error report is always a violation":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "ServiceWorker.workerErrorReported",
      "params": {"errorMessage": "boom"},
    })
    check bt.blockedServiceWorkers == 1
    check "service worker" in bt.policyViolation

  test "redirect to a private document is recorded and denied":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "Network.requestWillBeSent",
      "params": {
        "requestId": "r4",
        "type": "Document",
        "redirectResponse": {"url": "https://example.com/start"},
        "request": {"url": "http://10.0.0.1/internal"},
      },
    })
    check bt.blockedRequests == 1
    check "redirect blocked" in bt.policyViolation

  test "redirect to a private subresource does not abort the page":
    var bt = BrowserTools()
    bt.handleCdpEvent(%*{
      "method": "Network.requestWillBeSent",
      "params": {
        "requestId": "r5",
        "type": "Script",
        "redirectResponse": {"url": "https://example.com/start.js"},
        "request": {"url": "http://10.0.0.1/secret.js"},
      },
    })
    check bt.blockedRequests == 1
    check bt.policyViolation.len == 0

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

  test "newBrowserTools clamps the CDP timeout":
    check newBrowserTools().cdpTimeoutMs() == BrowserDefaultTimeoutMs
    check newBrowserTools(timeoutMs = 0).cdpTimeoutMs() == BrowserDefaultTimeoutMs
    check newBrowserTools(timeoutMs = 1).cdpTimeoutMs() == BrowserMinTimeoutMs
    check newBrowserTools(timeoutMs = 45_000).cdpTimeoutMs() == 45_000
    check newBrowserTools(timeoutMs = 999_999).cdpTimeoutMs() == BrowserMaxTimeoutMs

  test "browser process env excludes daemon secrets":
    putEnv("DONKEY_TEST_PROVIDER_KEY", "super-secret")
    defer: delEnv("DONKEY_TEST_PROVIDER_KEY")
    let env = browserProcessEnv("/tmp/donkey-profile")
    check env.hasKey("PATH")
    check env["HOME"] == "/tmp/donkey-profile"
    check not env.hasKey("DONKEY_TEST_PROVIDER_KEY")

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
                        input: %* {"url": "https://8.8.8.8"})
    let tr = bt.invoke(call).get()
    check tr.isError
    check tr.output.contains("disabled")

  test "navigate reports a missing Edge executable":
    var bt = BrowserTools(backend: bbEdge,
                          executablePath: "/nonexistent/microsoft-edge")
    let call = ToolCall(id: "test", name: "browser_navigate",
                        input: %* {"url": "https://8.8.8.8"})
    let tr = bt.invoke(call).get()
    check tr.isError
    check tr.output.contains("not found")

  test "explicit Lightpanda is rejected when a proxy is configured":
    var bt = BrowserTools(backend: bbLightpanda,
                          proxyServer: "http://127.0.0.1:3128")
    let call = ToolCall(id: "test", name: "browser_navigate",
                        input: %* {"url": "https://8.8.8.8"})
    let tr = bt.invoke(call).get()
    check tr.isError
    check tr.output.contains("DONKEY_BROWSER_PROXY")

  test "auto skips Lightpanda when a proxy is configured":
    var bt = BrowserTools(backend: bbAuto, lightpandaPath: "/nonexistent/lightpanda",
                          proxyServer: "http://127.0.0.1:3128")
    let call = ToolCall(id: "test", name: "browser_navigate",
                        input: %* {"url": "https://8.8.8.8"})
    let tr = bt.invoke(call).get()
    check tr.isError
    check tr.output.contains("Lightpanda does not support")

  test "runtime port routes tool calls with a per-user key":
    let runtime = newBrowserToolRuntime(backend = bbOff)
    check runtime.listTools().get().len == 3
    let port = runtime.toRuntimePort()
    let recognized = ToolCall(id: "x", name: "browser_content",
                              input: %* {}, userId: "user-a")
    check port.invoke(recognized).isOk
    let unknown = ToolCall(id: "y", name: "not_a_browser_tool",
                           input: %* {}, userId: "user-a")
    check port.invoke(unknown).isErr
    port.close()

  test "runtime allocates a distinct CDP port per user":
    let runtime = newBrowserToolRuntime(backend = bbOff, port = 19400)
    for user in ["user-a", "user-b"]:
      discard runtime.invoke(ToolCall(id: user, name: "browser_content",
                                      input: %* {}, userId: user))
    check runtime.byUser.hasKey("user-a")
    check runtime.byUser.hasKey("user-b")
    check runtime.byUser["user-a"][].port >= 19400
    check runtime.byUser["user-b"][].port >= 19400
    check runtime.byUser["user-a"][].port != runtime.byUser["user-b"][].port
    discard runtime.close()

  test "configured profile directories are not adapter-owned":
    let base = getTempDir() / ("donkey-test-profiles-" & $getCurrentProcessId())
    defer: removeDir(base)
    let runtime = newBrowserToolRuntime(
      backend = bbOff, profileBaseDir = base)
    discard runtime.invoke(ToolCall(id: "x", name: "browser_content",
                                    input: %* {}, userId: "user-a"))
    check runtime.byUser["user-a"][].profileDir == base / "user-a"
    check not runtime.byUser["user-a"][].ownsProfileDir
    when not defined(windows):
      let perms = getFilePermissions(base / "user-a")
      check fpGroupRead notin perms
      check fpGroupWrite notin perms
      check fpOthersRead notin perms
      check fpOthersWrite notin perms
    discard runtime.close()

  test "user keys are collision-free":
    check browserUserKey("") == "__default__"
    check browserUserKey("user-a") == "user-a"
    check browserUserKey("alice:a") == "alice_3Aa"
    check browserUserKey("alice:a") != browserUserKey("alice_a")
    check browserUserKey("_default_") != "__default__"

  test "runtime passes the filtering proxy to each browser":
    let runtime = newBrowserToolRuntime(
      backend = bbOff, proxyServer = "http://127.0.0.1:3128")
    discard runtime.invoke(ToolCall(id: "x", name: "browser_content",
                                    input: %* {}, userId: "user-a"))
    check runtime.byUser["user-a"][].proxyServer == "http://127.0.0.1:3128"
    discard runtime.close()

  test "runtime evicts idle users":
    let runtime = newBrowserToolRuntime(
      backend = bbOff, port = 19500, idleTimeoutSeconds = 60)
    discard runtime.invoke(ToolCall(id: "a", name: "browser_content",
                                    input: %* {}, userId: "user-a"))
    check runtime.byUser.hasKey("user-a")
    runtime.byUser["user-a"][].lastUsed = epochTime() - 120
    discard runtime.invoke(ToolCall(id: "b", name: "browser_content",
                                    input: %* {}, userId: "user-b"))
    check not runtime.byUser.hasKey("user-a")
    check runtime.byUser.hasKey("user-b")
    discard runtime.close()

  test "idle eviction works without a new invocation":
    let runtime = newBrowserToolRuntime(
      backend = bbOff, port = 19550, idleTimeoutSeconds = 60)
    discard runtime.invoke(ToolCall(id: "a", name: "browser_content",
                                    input: %* {}, userId: "user-a"))
    runtime.byUser["user-a"][].lastUsed = epochTime() - 120
    runtime.evictIdle()
    check not runtime.byUser.hasKey("user-a")
    discard runtime.close()

  test "runtime reuses ports released by closeUser":
    let runtime = newBrowserToolRuntime(backend = bbOff, port = 19700)
    discard runtime.invoke(ToolCall(id: "a", name: "browser_content",
                                    input: %* {}, userId: "user-a"))
    let firstPort = runtime.byUser["user-a"][].port
    check runtime.closeUser("user-a").isOk
    discard runtime.invoke(ToolCall(id: "b", name: "browser_content",
                                    input: %* {}, userId: "user-b"))
    check runtime.byUser["user-b"][].port == firstPort
    discard runtime.close()

  test "runtime releases a single user":
    let runtime = newBrowserToolRuntime(backend = bbOff, port = 19600)
    for user in ["user-a", "user-b"]:
      discard runtime.invoke(ToolCall(id: user, name: "browser_content",
                                      input: %* {}, userId: user))
    check runtime.closeUser("user-a").isOk
    check not runtime.byUser.hasKey("user-a")
    check runtime.byUser.hasKey("user-b")
    discard runtime.close()

  test "toRuntimePort exposes the browser tools":
    let port = newBrowserTools(backend = bbOff).toRuntimePort()
    let tools = port.listTools().get()
    check tools.len == 3
    port.close()
