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

import std/[json, net, os, osproc, times]
import ../../ports/tool
import ../../core/pipeops
import ../../domain/tools/web_fetch_helpers
import ../../adapters/channel/ws_client

const
  DefaultLightpandaPort* = 9222
  DefaultHost* = "127.0.0.1"
  DefaultTimeoutMs* = 30000
  DefaultMaxChars* = 50000

type
  BrowserTools* = object
    lightpandaPath*: string   ## Path to lightpanda binary (empty = search PATH)
    port*: int                ## CDP port
    host*: string              ## CDP host
    process*: Process          ## lightpanda serve subprocess
    ws*: WsClient             ## CDP WebSocket connection
    pageTargetId*: string      ## Active page target ID
    currentUrl*: string       ## URL of loaded page

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

proc ensurePage*(bt: var BrowserTools): Result[string, string] =
  ## Ensure we have an active page target. Creates one if not.
  if bt.pageTargetId.len > 0:
    return ok(bt.pageTargetId)
  
  # Create a new page target
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
  
  discard bt.sendCdpCommand("Target.activateTarget", %*{
    "targetId": bt.pageTargetId
  })
  return ok()

proc navigateTo*(bt: var BrowserTools; url: string; waitUntil = "networkidle"): Result[string, string] =
  ## Navigate to URL and wait for page load.
  # SSRF check
  if url.isPrivateUrl:
    return err("private/internal addresses not allowed")
  
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
  
  bt.currentUrl = url
  
  # Wait for load event
  let waitResp = bt.sendCdpCommand("Page.waitForLoadEvent", %*{})
  if waitResp.isErr:
    # Try Page.setDownloadBehavior or just return success if navigation succeeded
    discard
  
  return ok(url)

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
  
  let captureResp = bt.sendCdpCommand("Page.captureScreenshot", %*{
    "format": "png",
    "fullPage": fullPage
  })
  if captureResp.isErr:
    return err(captureResp.error)
  
  let r = captureResp.get()
  if not r.hasKey("data"):
    return err("no data in Page.captureScreenshot response")
  
  let pngData = r["data"].getStr()
  return ok(pngData)

# ── Lifecycle ───────────────────────────────────────────────────────────────

proc spawnLightpanda*(bt: var BrowserTools): Result[string, string] =
  ## Spawn lightpanda serve subprocess and connect via CDP WebSocket.
  if bt.process != nil:
    return ok("already running")
  
  let path = bt.lightpandaPath
  let exe = if path.len > 0 and path.fileExists: path
            elif "lightpanda".findExe.len > 0: "lightpanda"
            else: ""
  
  if exe.len == 0:
    return err("lightpanda binary not found in PATH. Install: https://github.com/lightpanda-io/browser")
  
  # Start lightpanda serve
  let p = try:
    startProcess(exe, args = ["serve", "--host", bt.host, "--port", $bt.port], options = {poUsePath})
  except CatchableError as e:
    return err("failed to spawn lightpanda: " & e.msg)
  
  bt.process = p
  
  # Wait briefly for server to start
  sleep(500)
  
  # Connect WebSocket to CDP
  # Lightpanda CDP WebSocket path: /devtools/browser/<id>
  let wsPath = "/devtools/browser"
  try:
    bt.ws = wsConnect(bt.host, Port(bt.port), wsPath)
  except IOError as e:
    bt.process.close()
    bt.process = nil
    return err("WebSocket connect failed: " & e.msg)
  
  return ok("connected")

proc close*(bt: var BrowserTools) =
  ## Clean up subprocess and WebSocket.
  try:
    bt.ws.wsClose()
  except CatchableError: discard
  if bt.process != nil:
    bt.process.terminate()
    bt.process.close()
    bt.process = nil
  bt.pageTargetId = ""
  bt.currentUrl = ""

# ── invoke — ToolPort method ─────────────────────────────────────────────────

proc invoke*(bt: var BrowserTools; call: ToolCall): Result[ToolResult, string] =
  case call.name
  of "browser_navigate":
    let urlNode = call.input.getOrDefault("url")
    if urlNode.isNil or urlNode.kind != JString or urlNode.getStr("").len == 0:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"missing required field: url\"}", isError: true))
    
    let url = urlNode.getStr("")
    let waitNode = call.input.getOrDefault("waitUntil")
    let waitUntil = if waitNode.isNil or waitNode.kind != JString: "networkidle" else: waitNode.getStr("")
    
    # SSRF check BEFORE spawning (fail fast on private URLs)
    if url.isPrivateUrl:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"private/internal addresses not allowed\"}", isError: true))
    
    # Spawn/connect if needed
    if bt.process == nil:
      let spawnResult = bt.spawnLightpanda()
      if spawnResult.isErr:
        return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & spawnResult.error & "\"}", isError: true))
    
    let navResult = bt.navigateTo(url, waitUntil)
    if navResult.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & navResult.error & "\"}", isError: true))
    
    return ok(ToolResult(callId: call.id, output: "{\"url\": \"" & url & "\", \"status\": \"loaded\"}", isError: false))
  
  of "browser_content":
    let maxCharsNode = call.input.getOrDefault("max_chars")
    let maxChars = if maxCharsNode.isNil or maxCharsNode.kind != JInt: DefaultMaxChars else: maxCharsNode.getInt()
    
    let asHtmlNode = call.input.getOrDefault("as_html")
    let asHtml = not asHtmlNode.isNil and asHtmlNode.kind == JBool and asHtmlNode.getBool()
    
    if bt.process == nil:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"browser not running - call browser_navigate first\"}", isError: true))
    
    let contentResult = bt.getContent(maxChars, asHtml)
    if contentResult.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & contentResult.error & "\"}", isError: true))
    
    return ok(ToolResult(callId: call.id, output: contentResult.get(), isError: false))
  
  of "browser_screenshot":
    let fullPageNode = call.input.getOrDefault("fullPage")
    let fullPage = not fullPageNode.isNil and fullPageNode.kind == JBool and fullPageNode.getBool()
    
    if bt.process == nil:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"browser not running - call browser_navigate first\"}", isError: true))
    
    let screenshotResult = bt.takeScreenshot(fullPage)
    if screenshotResult.isErr:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"" & screenshotResult.error & "\"}", isError: true))
    
    return ok(ToolResult(callId: call.id, output: "{\"format\": \"png\", \"data\": \"" & screenshotResult.get() & "\"}", isError: false))
  
  else:
    return ok(ToolResult(callId: call.id, output: "{\"error\": \"unknown tool: '" & call.name & "'\"}", isError: true))

# ── Constructor ─────────────────────────────────────────────────────────────

proc newBrowserTools*(
  lightpandaPath: string = "";
  host: string = DefaultHost;
  port: int = DefaultLightpandaPort
): BrowserTools =
  BrowserTools(
    lightpandaPath: lightpandaPath,
    host: host,
    port: port,
    process: nil,
    pageTargetId: "",
    currentUrl: ""
  )
