## BrowserTools — ToolPort adapter for headless browser automation via Lightpanda CDP.
##
## Tools:
##   - browser_navigate — navigate to URL and wait for page load
##   - browser_content  — get page HTML content as text
##   - browser_screenshot — take screenshot as base64 PNG
##
## Lightpanda is a headless browser written in Zig with:
##   - 11x faster / 9x less memory vs Chrome headless
##   - Native CDP (Chrome DevTools Protocol) support
##   - Drop-in for Puppeteer/Playwright workflows
##
## Architecture:
##   - Spawns `lightpanda serve` subprocess on first use
##   - CDP commands sent over WebSocket via ws_client.nim
##   - JSON-RPC 2.0 protocol for command/response correlation

import std/[json, net, options, os, osproc, times]
import ../../ports/http
import ../../ports/tool
import ../../core/pipeops
import ../../domain/tools/browser_pure
import ../../domain/tools/web_fetch_helpers
import ../../adapters/channel/ws_client

const
  DefaultLightpandaPort* = 9222
  DefaultHost* = "127.0.0.1"
  DefaultTimeoutMs* = 30000
  DefaultMaxChars* = 50000

type
  BrowserTools* = object
    backend*: BrowserBackendKind  ## off/auto/lightpanda/edge/chromium
    executablePath*: string       ## explicit browser executable
    lightpandaPath*: string       ## legacy alias for executablePath
    profileDir*: string           ## Chromium/Edge user-data-dir
    ownsProfileDir*: bool         ## true when the adapter created it
    port*: int                    ## CDP port
    host*: string                 ## CDP host
    process*: Process             ## browser subprocess
    ws*: WsClient                 ## CDP WebSocket connection
    pageTargetId*: string         ## active page target ID
    currentUrl*: string           ## URL of loaded page
    inflightRequests*: int        ## Network.* events observed since navigation
    lastNetworkActivity*: float   ## epochTime of the last Network event
    http*: HttpRuntimePort        ## transport for Chromium /json/list

# ── Tool Schemas ─────────────────────────────────────────────────────────────

proc browserNavigateSchema*(): ToolSchema =
  ToolSchema(
    name: "browser_navigate",
    description: "Navigate to a URL in headless browser and wait for page load. " &
                 "Supports JavaScript-rendered pages.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "URL to navigate to (public HTTP/HTTPS only)"
        },
        "waitUntil": {
          "type": "string",
          "description": "When to consider navigation complete: networkidle, load, domcontentloaded (default: networkidle)"
        }
      },
      "required": ["url"]
    }
  )

proc browserContentSchema*(): ToolSchema =
  ToolSchema(
    name: "browser_content",
    description: "Get the HTML content of the currently loaded page as clean text.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "max_chars": {
          "type": "integer",
          "description": "Maximum characters to return (default: 50000)"
        },
        "as_html": {
          "type": "boolean",
          "description": "Return raw HTML instead of converted text (default: false)"
        }
      }
    }
  )

proc browserScreenshotSchema*(): ToolSchema =
  ToolSchema(
    name: "browser_screenshot",
    description: "Take a screenshot of the current page. Returns base64-encoded PNG.",
    inputSchema: %* {
      "type": "object",
      "properties": {
        "fullPage": {
          "type": "boolean",
          "description": "Capture full scrollable page (default: false)"
        }
      }
    }
  )

# ── ToolPort Conformance ─────────────────────────────────────────────────────

proc listTools*(bt: BrowserTools): Result[seq[ToolSchema], string] =
  ok(@[browserNavigateSchema(), browserContentSchema(), browserScreenshotSchema()])

# ── Internal CDP Helpers ─────────────────────────────────────────────────────

var cdpRequestCounter: int = 0

proc nextId*(): int =
  inc cdpRequestCounter
  result = cdpRequestCounter

proc sendCdpCommand*(bt: var BrowserTools; cdpMethod: string; params: JsonNode = %*{}): Result[JsonNode, string] =
  ## Send a CDP command and wait for response.
  let id = nextId()
  let cmd = %*{
    "id": id,
    "method": cdpMethod,
    "params": params
  }
  
  bt.ws.sendFrame($cmd)
  
  # Receive responses until we get our matching ID
  var deadline = epochTime() + float(DefaultTimeoutMs) / 1000.0
  while true:
    let now = epochTime()
    if now >= deadline:
      return err("CDP timeout waiting for " & cdpMethod & " response")
    
    let remainingMs = int((deadline - now) * 1000)
    let frame = try:
      bt.ws.recvFrame(remainingMs)
    except IOError as e:
      return err("WebSocket receive error: " & e.msg)
    
    if frame.opcode == WsOpcodeClose:
      return err("WebSocket closed during CDP command")
    
    if frame.opcode == WsOpcodeText or frame.opcode == WsOpcodeBin:
      let resp = parseJson(frame.data)
      if resp.kind == JObject:
        if resp.hasKey("id") and resp["id"].getInt() == id:
          if resp.hasKey("error"):
            return err("CDP error: " & resp["error"].pretty)
          return ok(resp.getOrDefault("result"))
        elif resp.hasKey("method"):
          let cdpMethod = resp["method"].getStr("")
          case cdpMethod
          of "Network.requestWillBeSent":
            inc bt.inflightRequests
            bt.lastNetworkActivity = epochTime()
          of "Network.loadingFinished", "Network.loadingFailed":
            if bt.inflightRequests > 0:
              dec bt.inflightRequests
            bt.lastNetworkActivity = epochTime()
          else:
            discard

proc ensurePage*(bt: var BrowserTools): Result[string, string] =
  ## Ensure we have an active page target. Creates one if not.
  if bt.pageTargetId.len > 0:
    return ok(bt.pageTargetId)

  if bt.backend.isChromiumBackend():
    return err("no page target available from Chromium /json/list")

  # Lightpanda: create a new page target on the browser endpoint.
  let resp = bt.sendCdpCommand("Target.createTarget", %*{
    "url": "about:blank"
  })
  if resp.isErr:
    return err(resp.error)
  
  let r = resp.get()
  if not r.hasKey("targetId"):
    return err("no targetId in Target.createTarget response")
  
  bt.pageTargetId = r["targetId"].getStr()
  return ok(bt.pageTargetId)

proc activatePage*(bt: var BrowserTools): Result[void, string] =
  ## Activate the page target for sending commands.
  if bt.pageTargetId.len == 0:
    return err("no active page target")

  ## Chromium page endpoints do not expose Target.activateTarget; the page
  ## target is already the one this WebSocket is attached to.
  if bt.backend.isChromiumBackend():
    return ok()

  discard bt.sendCdpCommand("Target.activateTarget", %*{
    "targetId": bt.pageTargetId
  })
  return ok()

proc navigateTo*(bt: var BrowserTools; url: string; waitUntil = "networkidle"): Result[string, string] =
  ## Navigate to URL and wait for page load.
  # Only HTTP(S): file://, data: and browser-internal schemes must never reach
  # Page.navigate (isPrivateUrl alone treats "file" as a host).
  if not url.isHttpUrl:
    return err("only http/https URLs are allowed")
  # SSRF check
  if url.isPrivateUrl:
    return err("private/internal addresses not allowed")

  bt.inflightRequests = 0
  bt.lastNetworkActivity = epochTime()
  if waitUntil == "networkidle":
    discard bt.sendCdpCommand("Network.enable")
  
  # Ensure we have a page target
  let targetId = ? ensurePage(bt)
  if targetId.len == 0:
    return err("empty targetId from ensurePage")
  ? activatePage(bt)
  
  # Enable Page domain events
  discard bt.sendCdpCommand("Page.enable")

  # Navigate
  let navResp = bt.sendCdpCommand("Page.navigate", %*{
    "url": url
  })
  if navResp.isErr:
    return err(navResp.error)
  let navNode = navResp.get()
  let navError = navNode{"errorText"}
  if navError != nil and navError.kind == JString and navError.getStr("").len > 0:
    return err("navigation failed: " & navError.getStr(""))

  bt.currentUrl = url

  # Poll document.readyState: supported by both Lightpanda and Chromium page
  # endpoints (Chromium does not implement Lightpanda's non-standard
  # Page.waitForLoadEvent).
  let deadline = epochTime() + float(DefaultTimeoutMs) / 1000.0
  let targetReady = if waitUntil == "domcontentloaded": "interactive"
                    else: "complete"
  while epochTime() < deadline:
    let evalResp = bt.sendCdpCommand("Runtime.evaluate", %*{
      "expression": "document.readyState",
      "returnByValue": true
    })
    if evalResp.isOk:
      let resultNode = evalResp.get(){"result"}
      if resultNode != nil:
        let valueNode = resultNode{"value"}
        let state =
          if valueNode != nil and valueNode.kind == JString: valueNode.getStr("")
          else: ""
        if state == "complete" or
           (targetReady == "interactive" and state == "interactive"):
          if waitUntil != "networkidle":
            return ok(url)
          ## Real network-idle approximation: wait until Network.* events show
          ## no in-flight requests and 500ms of silence.
          if bt.inflightRequests == 0 and
             epochTime() - bt.lastNetworkActivity >= 0.5:
            return ok(url)
    sleep(100)

  return err("timeout waiting for page load")

proc getContent*(bt: var BrowserTools; maxChars: int; asHtml: bool): Result[string, string] =
  ## Get page content (HTML or text).
  if bt.pageTargetId.len == 0:
    return err("no page loaded - use browser_navigate first")
  
  ? activatePage(bt)
  
  # Get HTML via Runtime.evaluate
  let evalResp = bt.sendCdpCommand("Runtime.evaluate", %*{
    "expression": "document.documentElement.outerHTML",
    "returnByValue": true
  })
  if evalResp.isErr:
    return err(evalResp.error)
  
  let r = evalResp.get()
  if not r.hasKey("result") or not r["result"].hasKey("value"):
    return err("no result in Runtime.evaluate response")
  
  var html = r["result"]["value"].getStr()
  
  if asHtml:
    if maxChars > 0 and html.len > maxChars:
      html = html[0 ..< maxChars] & "..."
    return ok(html)
  else:
    let text = htmlToText(html, maxChars)
    return ok(text)

proc takeScreenshot*(bt: var BrowserTools; fullPage: bool): Result[string, string] =
  ## Take screenshot and return base64-encoded PNG.
  if bt.pageTargetId.len == 0:
    return err("no page loaded - use browser_navigate first")
  
  ? activatePage(bt)
  
  let params =
    if bt.backend.isChromiumBackend():
      %*{"format": "png", "captureBeyondViewport": fullPage}
    else:
      %*{"format": "png", "fullPage": fullPage}
  let captureResp = bt.sendCdpCommand("Page.captureScreenshot", params)
  if captureResp.isErr:
    return err(captureResp.error)
  
  let r = captureResp.get()
  if not r.hasKey("data"):
    return err("no data in Page.captureScreenshot response")
  
  let pngData = r["data"].getStr()
  return ok(pngData)

# ── Lifecycle ───────────────────────────────────────────────────────────────

proc resolveBrowserExecutable(bt: BrowserTools): Result[tuple[kind: BrowserBackendKind, exe: string], string] =
  ## Resolve the concrete backend and executable. Explicit paths win; otherwise
  ## search the candidate names in PATH.
  var kind = bt.backend
  if kind == bbAuto and bt.lightpandaPath.len > 0:
    kind = bbLightpanda

  if kind == bbAuto and bt.executablePath.len > 0:
    let inferred = inferBrowserBackend(bt.executablePath)
    if inferred.isNone:
      return err("cannot infer browser backend from executable path: " &
                 bt.executablePath)
    kind = inferred.get()
    if fileExists(bt.executablePath):
      return ok((kind, bt.executablePath))
    return err("browser executable not found: " & bt.executablePath)

  if kind == bbAuto:
    for candidateKind in [bbLightpanda, bbEdge, bbChromium]:
      for name in browserExecutableCandidates(candidateKind):
        let found = findExe(name)
        if found.len > 0:
          return ok((candidateKind, found))
    return err("no browser executable found; install Lightpanda, Edge or Chromium, " &
               "or set DONKEY_BROWSER_PATH")

  if kind == bbOff:
    return err("browser backend is disabled; set DONKEY_BROWSER_BACKEND")

  let explicit =
    if bt.executablePath.len > 0: bt.executablePath
    elif kind == bbLightpanda and bt.lightpandaPath.len > 0: bt.lightpandaPath
    else: ""
  if explicit.len > 0:
    if fileExists(explicit):
      return ok((kind, explicit))
    return err("browser executable not found: " & explicit)

  for name in browserExecutableCandidates(kind):
    let found = findExe(name)
    if found.len > 0:
      return ok((kind, found))

  let hint = case kind
    of bbLightpanda: "install Lightpanda or set DONKEY_BROWSER_PATH"
    of bbEdge: "install Microsoft Edge or set DONKEY_BROWSER_PATH"
    of bbChromium: "install Chromium/Chrome or set DONKEY_BROWSER_PATH"
    else: "set DONKEY_BROWSER_PATH"
  err("browser executable not found for " & $kind & "; " & hint)

proc waitForChromiumPage(bt: var BrowserTools;
                         deadline: float): Result[tuple[wsUrl: string, targetId: string, url: string], string] =
  ## Poll /json/list until a page target exposes its debugger WebSocket.
  if bt.http.get == nil:
    return err("HTTP port not configured for Chromium CDP discovery")
  let endpoint = "http://" & bt.host & ":" & $bt.port & "/json/list"
  while epochTime() < deadline:
    try:
      let response = bt.http.get(endpoint, @[])
      if response.isErr or response.get().status != 200:
        sleep(100)
        continue
      let pages = parseJson(response.get().body)
      if pages.kind == JArray:
        for page in pages:
          let typeNode = page{"type"}
          if typeNode == nil or typeNode.kind != JString or
             typeNode.getStr("") != "page":
            continue
          let wsNode = page{"webSocketDebuggerUrl"}
          if wsNode == nil or wsNode.kind != JString:
            continue
          let wsUrl = wsNode.getStr("")
          if wsUrl.len > 0:
            let idNode = page{"id"}
            let urlNode = page{"url"}
            return ok((
              wsUrl,
              if idNode != nil and idNode.kind == JString: idNode.getStr("") else: "",
              if urlNode != nil and urlNode.kind == JString: urlNode.getStr("") else: "",
            ))
    except CatchableError:
      discard
    sleep(100)
  err("Chromium CDP endpoint did not expose a page target")

proc spawnBrowser*(bt: var BrowserTools): Result[string, string] =
  ## Spawn the configured browser backend and connect its CDP endpoint.
  if bt.process != nil:
    return ok("already running")

  let resolved = bt.resolveBrowserExecutable()
  if resolved.isErr:
    return err(resolved.error)
  let (kind, exe) = resolved.get()

  var profileDir = bt.profileDir
  if kind.isChromiumBackend() and profileDir.len == 0:
    profileDir = getTempDir() / ("donkey-browser-" & $getCurrentProcessId() &
                                 "-" & $epochMs())
    try:
      createDir(profileDir)
    except CatchableError as e:
      return err("cannot create browser profile dir: " & e.msg)
    bt.profileDir = profileDir
    bt.ownsProfileDir = true

  let specOpt = buildLaunchSpec(kind, exe, bt.host, bt.port, profileDir)
  if specOpt.isNone:
    return err("invalid browser launch specification")
  let spec = specOpt.get()

  let p = try:
    startProcess(spec.exe, args = spec.args, options = {poUsePath})
  except CatchableError as e:
    if bt.ownsProfileDir:
      try: removeDir(bt.profileDir) except CatchableError: discard
    return err("failed to spawn " & $kind & ": " & e.msg)
  bt.process = p
  bt.backend = kind

  if kind == bbLightpanda:
    sleep(500)
    try:
      bt.ws = wsConnect(bt.host, Port(bt.port), "/devtools/browser", useTls = false)
    except IOError as e:
      bt.process.terminate()
      bt.process.close()
      bt.process = nil
      return err("WebSocket connect failed: " & e.msg)
    return ok("connected")

  let deadline = epochTime() + float(DefaultTimeoutMs) / 1000.0
  let page = bt.waitForChromiumPage(deadline)
  if page.isErr:
    bt.process.terminate()
    bt.process.close()
    bt.process = nil
    if bt.ownsProfileDir:
      try: removeDir(bt.profileDir) except CatchableError: discard
    return err(page.error)

  let (wsUrl, targetId, pageUrl) = page.get()
  let endpointOpt = parseWsDebuggerUrl(wsUrl)
  if endpointOpt.isNone:
    bt.process.terminate()
    bt.process.close()
    bt.process = nil
    return err("invalid CDP websocket URL from Chromium")
  let endpoint = endpointOpt.get()
  try:
    bt.ws = wsConnect(endpoint.host, Port(endpoint.port),
                      endpoint.path, useTls = endpoint.secure)
  except IOError as e:
    bt.process.terminate()
    bt.process.close()
    bt.process = nil
    return err("WebSocket connect failed: " & e.msg)
  bt.pageTargetId = targetId
  bt.currentUrl = pageUrl
  ok("connected")

proc spawnLightpanda*(bt: var BrowserTools): Result[string, string] =
  ## Backward-compatible alias.
  bt.spawnBrowser()

proc close*(bt: var BrowserTools) =
  ## Clean up subprocess, WebSocket and adapter-owned profile directory.
  if bt.ws.sock != nil:
    try:
      bt.ws.wsClose()
    except CatchableError: discard
  if bt.process != nil:
    bt.process.terminate()
    bt.process.close()
    bt.process = nil
  if bt.ownsProfileDir and bt.profileDir.len > 0:
    try:
      removeDir(bt.profileDir)
    except CatchableError:
      discard
  bt.profileDir = ""
  bt.ownsProfileDir = false
  bt.pageTargetId = ""
  bt.currentUrl = ""
  bt.inflightRequests = 0
  bt.lastNetworkActivity = 0.0

# ── invoke — ToolPort method ─────────────────────────────────────────────────

func browserError(callId, message: string): ToolResult =
  ToolResult(callId: callId, output: $(%*{"error": message}), isError: true)

proc invoke*(bt: var BrowserTools; call: ToolCall): Result[ToolResult, string] =
  case call.name
  of "browser_navigate":
    let urlNode = call.input.getOrDefault("url")
    if urlNode.isNil or urlNode.kind != JString or urlNode.getStr("").len == 0:
      return ok(browserError(call.id, "missing required field: url"))
    
    let url = urlNode.getStr("")
    let waitNode = call.input.getOrDefault("waitUntil")
    let waitUntil = if waitNode.isNil or waitNode.kind != JString: "networkidle" else: waitNode.getStr("")
    
    # Scheme and SSRF checks BEFORE spawning.
    if not url.isHttpUrl:
      return ok(browserError(call.id, "only http/https URLs are allowed"))
    if url.isPrivateUrl:
      return ok(browserError(call.id, "private/internal addresses not allowed"))
    
    # Spawn/connect if needed
    if bt.process == nil:
      let spawnResult = bt.spawnBrowser()
      if spawnResult.isErr:
        return ok(browserError(call.id, spawnResult.error))
    
    let navResult = bt.navigateTo(url, waitUntil)
    if navResult.isErr:
      return ok(browserError(call.id, navResult.error))
    
    return ok(ToolResult(callId: call.id,
      output: $(%*{"url": url, "status": "loaded"}), isError: false))
  
  of "browser_content":
    let maxCharsNode = call.input.getOrDefault("max_chars")
    let maxChars = if maxCharsNode.isNil or maxCharsNode.kind != JInt: DefaultMaxChars else: maxCharsNode.getInt()
    
    let asHtmlNode = call.input.getOrDefault("as_html")
    let asHtml = not asHtmlNode.isNil and asHtmlNode.kind == JBool and asHtmlNode.getBool()
    
    if bt.process == nil:
      return ok(browserError(call.id, "browser not running - call browser_navigate first"))
    
    let contentResult = bt.getContent(maxChars, asHtml)
    if contentResult.isErr:
      return ok(browserError(call.id, contentResult.error))
    
    return ok(ToolResult(callId: call.id, output: contentResult.get(), isError: false))
  
  of "browser_screenshot":
    let fullPageNode = call.input.getOrDefault("fullPage")
    let fullPage = not fullPageNode.isNil and fullPageNode.kind == JBool and fullPageNode.getBool()
    
    if bt.process == nil:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"browser not running - call browser_navigate first\"}", isError: true))
    
    let screenshotResult = bt.takeScreenshot(fullPage)
    if screenshotResult.isErr:
      return ok(browserError(call.id, screenshotResult.error))
    
    return ok(ToolResult(callId: call.id,
      output: $(%*{"format": "png", "data": screenshotResult.get()}),
      isError: false))
  
  else:
    return ok(browserError(call.id, "unknown tool: '" & call.name & "'"))

# ── Constructor ─────────────────────────────────────────────────────────────

proc newBrowserTools*(
  lightpandaPath: string = "";
  host: string = DefaultHost;
  port: int = DefaultLightpandaPort;
  backend: BrowserBackendKind = bbAuto;
  executablePath: string = "";
  profileDir: string = "";
  http: HttpRuntimePort = HttpRuntimePort()
): BrowserTools =
  var resolvedBackend = backend
  if lightpandaPath.len > 0 and backend == bbAuto:
    resolvedBackend = bbLightpanda
  BrowserTools(
    backend: resolvedBackend,
    executablePath: executablePath,
    lightpandaPath: lightpandaPath,
    profileDir: profileDir,
    ownsProfileDir: false,
    host: host,
    port: port,
    http: http,
    process: nil,
    pageTargetId: "",
    currentUrl: ""
  )

proc toRuntimePort*(bt: BrowserTools): ToolRuntimePort =
  ## Each runtime port owns its BrowserTools state (process/WS/page).
  var browser = bt
  ToolRuntimePort(
    listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} =
      browser.listTools(),
    invoke: proc(call: ToolCall): Result[ToolResult, string] {.gcsafe.} =
      browser.invoke(call),
    close: proc() {.gcsafe.} =
      browser.close(),
  )
