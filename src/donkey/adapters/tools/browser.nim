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

import std/[json, net, options, os, osproc, strtabs, strutils, tables, times]
when defined(posix):
  import std/posix
import ../../ports/http
import ../../ports/tool
import ../../core/pipeops
import ../../domain/tools/browser_pure
import ../../domain/tools/web_fetch_helpers
import ../../adapters/channel/ws_client
import ../network/dns_resolver

const
  DefaultLightpandaPort* = 9222
  DefaultHost* = "127.0.0.1"
  DefaultTimeoutMs* = BrowserDefaultTimeoutMs
  DefaultMaxChars* = BrowserDefaultMaxContentChars
  BrowserBlockedUrlPatterns* = @[
    "ws://*", "wss://*", "ftp://*", "file://*", "filesystem://*",
  ]

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
    mainFrameId*: string          ## main frame, used for isolated evaluation
    currentUrl*: string           ## URL of loaded page
    inflightRequests*: int        ## Network.* events observed since navigation
    pendingRequestIds*: seq[string] ## requestId set, redirects keep the same id
    lastNetworkActivity*: float   ## epochTime of the last Network event
    lastUsed*: float              ## epochTime of the last tool invocation
    fetchEnabled*: bool           ## Fetch.requestPaused interception is active
    http*: HttpRuntimePort        ## transport for Chromium /json/list
    proxyServer*: string          ## optional filtering egress proxy
    timeoutMs*: int               ## per-CDP-command and navigation budget
    blockedRequests*: int         ## requests denied by URL/DNS policy
    blockedWebSockets*: int       ## WebSocket creations observed and denied
    blockedServiceWorkers*: int   ## service worker events observed and denied
    policyViolation*: string      ## non-empty closes the browser session
    lastBlockedUrl*: string       ## most recent denied destination
    hardeningWarnings*: seq[string] ## unsupported optional CDP hardening

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

proc cdpTimeoutMs*(bt: BrowserTools): int =
  clampBrowserTimeoutMs(bt.timeoutMs)

proc fireCdpCommand(bt: var BrowserTools; cdpMethod: string; params: JsonNode) =
  ## Sends a CDP command without waiting for its response. Used from inside the
  ## receive loop to answer Fetch.requestPaused events. A missing socket is
  ## possible only in unit tests that exercise event handling without a browser.
  if bt.ws.sock == nil:
    return
  let id = nextId()
  bt.ws.sendFrame($(%*{"id": id, "method": cdpMethod, "params": params}))

proc isAllowedBrowserRequest*(url: string;
                              kind = brkUnknown;
                              resolveDns = true): bool =
  ## Top-level navigation already requires HTTP(S). Subresources may be data/
  ## blob/about, but network destinations must not be private/internal and
  ## local file/chrome schemes are never allowed.
  ##
  ## The host is resolved here and every resolved address is validated. The
  ## browser resolves again when connecting, so a DNS-rebinding window remains;
  ## production deployments should route browser egress through a filtering
  ## proxy/firewall that pins connections to validated addresses.
  if not browserSchemeAllowedFor(url, kind):
    return false
  if isInlineBrowserUrl(url):
    return true
  if url.isPrivateUrl:
    return false
  let host = extractUrlHost(url)
  if host.len == 0:
    return false
  if not resolveDns:
    return true
  safeResolve(host).isOk

proc addHardeningWarning(bt: var BrowserTools; message: string) =
  if message.len > 0 and message notin bt.hardeningWarnings:
    bt.hardeningWarnings.add(message)

proc hardenProfileDir(path: string): Result[void, string] =
  when defined(posix):
    if path.len > 0 and posix.chmod(path.cstring, posix.Mode(0o700)) != 0:
      return err("cannot restrict browser profile permissions: " & path)
  ok()

proc handleCdpEvent*(bt: var BrowserTools; resp: JsonNode) =
  ## Applies one asynchronous CDP event received while waiting for a response.
  let cdpMethod = resp["method"].getStr("")
  let params = resp{"params"}
  case cdpMethod
  of "Fetch.requestPaused":
    if bt.fetchEnabled:
      let requestId = params{"requestId"}.getStr("")
      let requestNode = params{"request"}
      let requestUrl =
        if requestNode != nil and requestNode.kind == JObject:
          requestNode{"url"}.getStr("")
        else:
          ""
      let kind = browserResourceKind(params{"resourceType"}.getStr(""))
      if requestId.len > 0:
        if isAllowedBrowserRequest(requestUrl, kind):
          bt.fireCdpCommand("Fetch.continueRequest",
                            %*{"requestId": requestId})
        else:
          bt.fireCdpCommand("Fetch.failRequest", %*{
            "requestId": requestId,
            "errorReason": "BlockedByClient",
          })
          inc bt.blockedRequests
          bt.lastBlockedUrl = requestUrl
          ## A blocked document means the navigation itself was redirected to
          ## an internal destination. Abort the whole browser session instead
          ## of leaving a partially loaded page alive.
          if kind == brkDocument:
            bt.policyViolation = "document blocked: " & requestUrl
          elif kind == brkServiceWorker:
            bt.policyViolation = "service worker script blocked: " & requestUrl
        bt.lastNetworkActivity = epochTime()
  of "Network.requestWillBeSent":
    let requestId = params{"requestId"}.getStr("")
    let redirect = params{"redirectResponse"}
    let requestNode = params{"request"}
    let targetUrl =
      if requestNode != nil and requestNode.kind == JObject:
        requestNode{"url"}.getStr("")
      else:
        ""
    let requestKind = browserResourceKind(params{"type"}.getStr(""))
    if redirect != nil and targetUrl.len > 0 and
       not isAllowedBrowserRequest(targetUrl, requestKind, resolveDns = false):
      inc bt.blockedRequests
      bt.lastBlockedUrl = targetUrl
      if requestKind == brkDocument:
        bt.policyViolation = "redirect blocked: " & targetUrl
    if requestId.len > 0 and redirect == nil and
       requestId notin bt.pendingRequestIds:
      bt.pendingRequestIds.add(requestId)
      inc bt.inflightRequests
    bt.lastNetworkActivity = epochTime()
  of "Network.webSocketCreated":
    inc bt.blockedWebSockets
    bt.lastBlockedUrl = params{"url"}.getStr("")
    bt.policyViolation = "websocket blocked: " & bt.lastBlockedUrl
  of "Network.webTransportCreated":
    inc bt.blockedWebSockets
    bt.lastBlockedUrl = params{"url"}.getStr("")
    bt.policyViolation = "webtransport blocked: " & bt.lastBlockedUrl
  of "ServiceWorker.workerVersionUpdated":
    ## Enabling the domain emits an empty inventory notification on a fresh
    ## profile. Only an actual version is activity worth failing closed.
    let versions = params{"versions"}
    if versions != nil and versions.kind == JArray and versions.len > 0:
      inc bt.blockedServiceWorkers
      bt.policyViolation = "service worker activity blocked: " & cdpMethod
  of "ServiceWorker.workerRegistrationUpdated":
    let registrations = params{"registrations"}
    if registrations != nil and registrations.kind == JArray and
       registrations.len > 0:
      inc bt.blockedServiceWorkers
      bt.policyViolation = "service worker activity blocked: " & cdpMethod
  of "ServiceWorker.workerErrorReported":
    inc bt.blockedServiceWorkers
    bt.policyViolation = "service worker activity blocked: " & cdpMethod
  of "Network.loadingFinished", "Network.loadingFailed":
    let requestId = params{"requestId"}.getStr("")
    let idx = bt.pendingRequestIds.find(requestId)
    if idx >= 0:
      bt.pendingRequestIds.delete(idx)
      if bt.inflightRequests > 0:
        dec bt.inflightRequests
    bt.lastNetworkActivity = epochTime()
  else:
    discard

proc drainPendingEvents(bt: var BrowserTools; budgetMs = 50) =
  ## Processes events that arrived after the last command response. Without
  ## this, a request paused by Fetch after navigateTo returns would stay
  ## blocked until the next tool call sends another CDP command.
  let deadline = epochTime() + float(budgetMs) / 1000.0
  while epochTime() < deadline:
    let frame = try:
      bt.ws.recvFrame(10, maxPayloadBytes = BrowserMaxCdpFrameBytes)
    except TimeoutError:
      break
    except CatchableError:
      break
    if frame.opcode == WsOpcodeClose:
      break
    if frame.opcode == WsOpcodeText or frame.opcode == WsOpcodeBin:
      try:
        let resp = parseJson(frame.data)
        if resp.kind == JObject and resp.hasKey("method"):
          bt.handleCdpEvent(resp)
      except CatchableError:
        discard

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
  var deadline = epochTime() + float(bt.cdpTimeoutMs()) / 1000.0
  while true:
    let now = epochTime()
    if now >= deadline:
      return err("CDP timeout waiting for " & cdpMethod & " response")
    
    let remainingMs = max(1, int((deadline - now) * 1000))
    let frame = try:
      bt.ws.recvFrame(remainingMs, maxPayloadBytes = BrowserMaxCdpFrameBytes)
    except TimeoutError as e:
      return err("CDP timeout waiting for " & cdpMethod & " response: " & e.msg)
    except IOError as e:
      return err("WebSocket receive error: " & e.msg)
    
    if frame.opcode == WsOpcodeClose:
      return err("WebSocket closed during CDP command")
    
    if frame.opcode == WsOpcodeText or frame.opcode == WsOpcodeBin:
      let resp = try:
        parseJson(frame.data)
      except JsonParsingError as e:
        return err("malformed CDP frame: " & e.msg)
      if resp.kind == JObject:
        if resp.hasKey("id") and resp["id"].getInt() == id:
          if resp.hasKey("error"):
            return err("CDP error: " & resp["error"].pretty)
          return ok(resp.getOrDefault("result"))
        elif resp.hasKey("method"):
          bt.handleCdpEvent(resp)

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

proc resolveMainFrameId(bt: var BrowserTools): string =
  if bt.mainFrameId.len > 0:
    return bt.mainFrameId
  let tree = bt.sendCdpCommand("Page.getFrameTree")
  if tree.isOk:
    let frame = tree.get(){"frameTree"}{"frame"}
    if frame != nil and frame.kind == JObject:
      bt.mainFrameId = frame{"id"}.getStr("")
  bt.mainFrameId

proc evaluateWithIsolatedWorld(bt: var BrowserTools;
                               expression: string): Result[JsonNode, string] =
  ## Runs the content extraction in an isolated world on Chromium. Page code
  ## cannot replace String.prototype.slice there. If the world is unavailable
  ## (Lightpanda or an older engine), fall back to the main context; the
  ## Nim-side cap still bounds the payload.
  var contextId = 0
  if bt.backend.isChromiumBackend():
    let frameId = bt.resolveMainFrameId()
    if frameId.len > 0:
      let world = bt.sendCdpCommand("Page.createIsolatedWorld", %*{
        "frameId": frameId,
        "worldName": "donkey-browser-content",
      })
      if world.isOk:
        contextId = world.get(){"executionContextId"}.getInt(0)
  var params = %*{
    "expression": expression,
    "returnByValue": true,
  }
  if contextId > 0:
    params["contextId"] = %contextId
  bt.sendCdpCommand("Runtime.evaluate", params)

proc navigateTo*(bt: var BrowserTools; url: string; waitUntil = "networkidle"): Result[string, string] =
  ## Navigate to URL and wait for page load.
  if waitUntil notin ["networkidle", "load", "domcontentloaded"]:
    return err("invalid waitUntil; use networkidle, load or domcontentloaded")
  # Only HTTP(S): file://, data: and browser-internal schemes must never reach
  # Page.navigate (isPrivateUrl alone treats "file" as a host).
  if not url.isHttpUrl:
    return err("only http/https URLs are allowed")
  # SSRF check. The adapter resolves every address before the browser sees it.
  if url.isPrivateUrl:
    return err("private/internal addresses not allowed")
  if not isAllowedBrowserRequest(url, brkDocument):
    return err("URL blocked by browser policy")

  bt.inflightRequests = 0
  bt.pendingRequestIds.setLen(0)
  bt.lastNetworkActivity = epochTime()
  bt.blockedRequests = 0
  bt.blockedWebSockets = 0
  bt.blockedServiceWorkers = 0
  bt.policyViolation = ""
  bt.lastBlockedUrl = ""
  bt.hardeningWarnings.setLen(0)
  bt.mainFrameId = ""

  ## Network monitoring is always enabled: it is the second layer for redirects,
  ## WebSockets and service workers, even when waitUntil is not networkidle.
  let netResult = bt.sendCdpCommand("Network.enable")
  if netResult.isErr:
    return err("cannot enable network monitoring: " & netResult.error)
  let cacheDisabled = bt.sendCdpCommand("Network.setCacheDisabled",
                                        %*{"cacheDisabled": true})
  if cacheDisabled.isErr:
    bt.addHardeningWarning("cache disabling unsupported: " & cacheDisabled.error)

  ## Ask Chromium to bypass service workers. This is a required control on
  ## Chromium/Edge; Lightpanda may not implement the method, so it falls back to
  ## the injected script and event monitoring.
  let swBypass = bt.sendCdpCommand("Network.setBypassServiceWorker",
                                   %*{"bypass": true})
  if swBypass.isErr:
    bt.addHardeningWarning("service worker bypass unsupported: " & swBypass.error)
    if bt.backend.isChromiumBackend():
      return err("cannot bypass service workers: " & swBypass.error)

  ## Block non-HTTP channels at the network layer too. Fetch does not see
  ## WebSocket/WebTransport handshakes.
  let blockedUrls = bt.sendCdpCommand("Network.setBlockedURLs", %*{
    "urls": BrowserBlockedUrlPatterns
  })
  if blockedUrls.isErr:
    let legacyBlocked = bt.sendCdpCommand("Network.setBlockedURLs", %*{
      "urlPatterns": BrowserBlockedUrlPatterns
    })
    if legacyBlocked.isErr:
      bt.addHardeningWarning("URL blocking unsupported: " & legacyBlocked.error)
      if bt.backend.isChromiumBackend():
        return err("cannot block WebSocket/WebTransport URLs: " &
                   legacyBlocked.error)

  ## Intercept every request before it leaves the browser. This covers
  ## redirects and page subresources, not just the initial URL. Without
  ## interception redirects and subresources would bypass the URL policy, so
  ## navigation is aborted when it cannot be enabled.
  if not bt.fetchEnabled:
    let fetchResult = bt.sendCdpCommand("Fetch.enable", %*{
      "patterns": @[%*{"urlPattern": "*", "requestStage": "Request"}]
    })
    if fetchResult.isErr:
      return err("cannot enable request interception: " & fetchResult.error)
    bt.fetchEnabled = true
  
  # Ensure we have a page target
  let targetId = ? ensurePage(bt)
  if targetId.len == 0:
    return err("empty targetId from ensurePage")
  ? activatePage(bt)
  
  # Enable Page domain events before installing the per-document policy.
  let pageEnable = bt.sendCdpCommand("Page.enable")
  if pageEnable.isErr:
    return err("cannot enable Page domain: " & pageEnable.error)

  ## Inject the policy before any page script runs. Chromium supports
  ## `runImmediately`; older engines get the plain variant.
  var injection = bt.sendCdpCommand("Page.addScriptToEvaluateOnNewDocument", %*{
    "source": browserPolicyScript(),
    "runImmediately": true,
  })
  if injection.isErr:
    injection = bt.sendCdpCommand("Page.addScriptToEvaluateOnNewDocument", %*{
      "source": browserPolicyScript(),
    })
  if injection.isErr:
    bt.addHardeningWarning("policy script injection unsupported: " & injection.error)
    if bt.backend.isChromiumBackend():
      return err("cannot install browser policy script: " & injection.error)

  ## Downloads are never allowed. Chromium exposes Browser.setDownloadBehavior;
  ## older builds use the Page-domain variant.
  let downloadDenied = bt.sendCdpCommand("Browser.setDownloadBehavior", %*{
    "behavior": "deny",
    "eventsEnabled": false,
  })
  if downloadDenied.isErr:
    let pageDownloadDenied = bt.sendCdpCommand("Page.setDownloadBehavior", %*{
      "behavior": "deny",
    })
    if pageDownloadDenied.isErr:
      ## Download denial is best-effort: the CDP surface varies across
      ## Chromium/Edge builds. A download cannot execute scripts, so the
      ## absence of the method is a warning, not a navigation abort.
      bt.addHardeningWarning("download denial unsupported: " & pageDownloadDenied.error)

  ## ServiceWorker events feed the fail-closed monitor. A failure to enable the
  ## domain is not fatal because the bypass and injected unregister already
  ## cover registration on Chromium.
  if bt.backend.isChromiumBackend():
    let swEnable = bt.sendCdpCommand("ServiceWorker.enable")
    if swEnable.isErr:
      bt.addHardeningWarning("service worker events unavailable: " & swEnable.error)

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
  let frameIdNode = navNode{"frameId"}
  if frameIdNode != nil and frameIdNode.kind == JString:
    bt.mainFrameId = frameIdNode.getStr("")
  if bt.policyViolation.len > 0:
    return err("browser policy violation: " & bt.policyViolation)

  bt.currentUrl = url

  # Poll document.readyState: supported by both Lightpanda and Chromium page
  # endpoints (Chromium does not implement Lightpanda's non-standard
  # Page.waitForLoadEvent).
  let deadline = epochTime() + float(bt.cdpTimeoutMs()) / 1000.0
  let targetReady = if waitUntil == "domcontentloaded": "interactive"
                    else: "complete"
  while epochTime() < deadline:
    if bt.policyViolation.len > 0:
      return err("browser policy violation: " & bt.policyViolation)
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
            if bt.policyViolation.len > 0:
              return err("browser policy violation: " & bt.policyViolation)
            return ok(url)
          ## Real network-idle approximation: wait until Network.* events show
          ## no in-flight requests and 500ms of silence.
          if bt.inflightRequests == 0 and
             epochTime() - bt.lastNetworkActivity >= 0.5:
            if bt.policyViolation.len > 0:
              return err("browser policy violation: " & bt.policyViolation)
            return ok(url)
    sleep(100)

  if bt.policyViolation.len > 0:
    return err("browser policy violation: " & bt.policyViolation)
  return err("timeout waiting for page load")

proc getContent*(bt: var BrowserTools; maxChars: int; asHtml: bool): Result[string, string] =
  ## Get page content (HTML or text). The browser truncates before serializing
  ## so a hostile DOM cannot force an unbounded CDP payload.
  if bt.pageTargetId.len == 0:
    return err("no page loaded - use browser_navigate first")
  if bt.policyViolation.len > 0:
    return err("browser policy violation: " & bt.policyViolation)
  
  ? activatePage(bt)
  let cap = clampBrowserContentChars(maxChars)
  
  # Get HTML/text via Runtime.evaluate. Chromium uses an isolated world; the
  # local cap is the guarantee even if the page replaces slice or the isolated
  # world is unavailable.
  let expression =
    if asHtml: browserContentExpression(cap)
    else: browserTextExpression(cap)
  let evalResp = bt.evaluateWithIsolatedWorld(expression)
  if evalResp.isErr:
    return err(evalResp.error)
  
  let r = evalResp.get()
  if not r.hasKey("result") or not r["result"].hasKey("value"):
    return err("no result in Runtime.evaluate response")
  
  let value = capBrowserContent(r["result"]["value"].getStr(), cap)
  if asHtml:
    return ok(value)
  else:
    let text = normalizeWhitespace(value)
    return ok(capBrowserContent(text, cap))

proc takeScreenshot*(bt: var BrowserTools; fullPage: bool): Result[string, string] =
  ## Take screenshot and return base64-encoded PNG.
  if bt.pageTargetId.len == 0:
    return err("no page loaded - use browser_navigate first")
  if bt.policyViolation.len > 0:
    return err("browser policy violation: " & bt.policyViolation)
  
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
  if screenshotTooLarge(pngData):
    return err("screenshot exceeds " & $BrowserMaxScreenshotBytes &
               " bytes; retry with fullPage=false or a smaller viewport")
  return ok(pngData)

# ── Lifecycle ───────────────────────────────────────────────────────────────

proc resolveBrowserExecutable(bt: BrowserTools): Result[tuple[kind: BrowserBackendKind, exe: string], string] =
  ## Resolve the concrete backend and executable. Explicit paths win; otherwise
  ## search the candidate names in PATH.
  var kind = bt.backend
  if kind == bbAuto and bt.lightpandaPath.len > 0:
    kind = bbLightpanda

  ## A filtering proxy only applies to Edge/Chromium; selecting Lightpanda
  ## would silently route traffic around it.
  let proxySet = bt.proxyServer.len > 0
  if proxySet and kind == bbLightpanda:
    return err("Lightpanda does not support DONKEY_BROWSER_PROXY; " &
               "use Edge or Chromium")

  if kind == bbAuto and bt.executablePath.len > 0:
    let inferred = inferBrowserBackend(bt.executablePath)
    if inferred.isNone:
      return err("cannot infer browser backend from executable path: " &
                 bt.executablePath)
    kind = inferred.get()
    if proxySet and not kind.isChromiumBackend():
      return err("configured browser does not support DONKEY_BROWSER_PROXY; " &
                 "use Edge or Chromium")
    if fileExists(bt.executablePath):
      return ok((kind, bt.executablePath))
    return err("browser executable not found: " & bt.executablePath)

  if kind == bbAuto:
    let candidates: seq[BrowserBackendKind] =
      if proxySet: @[bbEdge, bbChromium]
      else: @[bbLightpanda, bbEdge, bbChromium]
    for candidateKind in candidates:
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

proc browserProcessEnv*(profileDir: string): StringTableRef =
  ## Do not leak daemon secrets (provider keys, web proxy credentials, tokens)
  ## into the browser process. Chromium does not need them and a renderer
  ## compromise should not inherit them.
  let homeDir =
    if profileDir.len > 0: profileDir
    else: getTempDir()
  result = newStringTable(mode = modeCaseSensitive)
  result["PATH"] = getEnv("PATH")
  result["HOME"] = homeDir
  result["TMPDIR"] = getEnv("TMPDIR", getTempDir())
  result["TMP"] = getEnv("TMP", getEnv("TMPDIR", getTempDir()))
  result["TEMP"] = getEnv("TEMP", getEnv("TMPDIR", getTempDir()))
  result["LANG"] = getEnv("LANG", "C.UTF-8")
  result["LC_ALL"] = getEnv("LC_ALL", getEnv("LANG", "C.UTF-8"))
  result["USER"] = getEnv("USER", "donkey")
  result["LOGNAME"] = getEnv("LOGNAME", getEnv("USER", "donkey"))
  for name in ["LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH"]:
    let value = getEnv(name)
    if value.len > 0:
      result[name] = value
  when defined(windows):
    for name in ["SystemRoot", "WINDIR", "COMSPEC", "PATHEXT"]:
      let value = getEnv(name)
      if value.len > 0:
        result[name] = value

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
    let hardened = hardenProfileDir(profileDir)
    if hardened.isErr:
      try: removeDir(profileDir) except CatchableError: discard
      bt.profileDir = ""
      bt.ownsProfileDir = false
      return err(hardened.error)

  let specOpt = buildLaunchSpec(kind, exe, bt.host, bt.port, profileDir,
                                bt.proxyServer)
  if specOpt.isNone:
    return err("invalid browser launch specification")
  let spec = specOpt.get()

  let p = try:
    startProcess(spec.exe, args = spec.args, env = browserProcessEnv(profileDir),
                 options = {poUsePath, poParentStreams})
  except CatchableError as e:
    if bt.ownsProfileDir:
      try: removeDir(bt.profileDir) except CatchableError: discard
    return err("failed to spawn " & $kind & ": " & e.msg)
  bt.process = p
  bt.backend = kind

  if kind == bbLightpanda:
    sleep(500)
    try:
      bt.ws = wsConnect(bt.host, Port(bt.port), "/devtools/browser",
                        useTls = false, timeoutMs = min(bt.cdpTimeoutMs(), 15_000))
    except IOError as e:
      bt.process.terminate()
      bt.process.close()
      bt.process = nil
      return err("WebSocket connect failed: " & e.msg)
    return ok("connected")

  let deadline = epochTime() + float(bt.cdpTimeoutMs()) / 1000.0
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
                      endpoint.path, useTls = endpoint.secure,
                      timeoutMs = min(bt.cdpTimeoutMs(), 15_000))
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
  bt.mainFrameId = ""
  bt.currentUrl = ""
  bt.inflightRequests = 0
  bt.pendingRequestIds.setLen(0)
  bt.lastNetworkActivity = 0.0
  bt.fetchEnabled = false
  bt.blockedRequests = 0
  bt.blockedWebSockets = 0
  bt.blockedServiceWorkers = 0
  bt.policyViolation = ""
  bt.lastBlockedUrl = ""
  bt.hardeningWarnings.setLen(0)

# ── invoke — ToolPort method ─────────────────────────────────────────────────

func browserError(callId, message: string): ToolResult =
  ToolResult(callId: callId, output: $(%*{"error": message}), isError: true)

proc invokeCommand(bt: var BrowserTools; call: ToolCall): Result[ToolResult, string] =
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
    if not isAllowedBrowserRequest(url, brkDocument):
      return ok(browserError(call.id, "URL blocked by browser policy"))
    
    # Spawn/connect if needed
    if bt.process == nil:
      let spawnResult = bt.spawnBrowser()
      if spawnResult.isErr:
        return ok(browserError(call.id, spawnResult.error))
    
    let navResult = bt.navigateTo(url, waitUntil)
    if navResult.isErr:
      return ok(browserError(call.id, navResult.error))
    
    var payload = %*{"url": url, "status": "loaded"}
    if bt.hardeningWarnings.len > 0:
      payload["warnings"] = %bt.hardeningWarnings
    return ok(ToolResult(callId: call.id,
      output: $payload, isError: false))
  
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
    return err("unknown tool: '" & call.name & "'")

proc invoke*(bt: var BrowserTools; call: ToolCall): Result[ToolResult, string] =
  result = bt.invokeCommand(call)
  bt.lastUsed = epochTime()
  if bt.process != nil and bt.ws.sock != nil:
    bt.drainPendingEvents()
  ## A WebSocket, service worker or blocked document violation means the page
  ## may already have an egress channel. Tear the whole browser down instead of
  ## returning a partially trusted page.
  if bt.policyViolation.len > 0:
    let violation = bt.policyViolation
    bt.close()
    return ok(browserError(call.id, "blocked by browser policy: " & violation))

# ── Constructor ─────────────────────────────────────────────────────────────

proc newBrowserTools*(
  lightpandaPath: string = "";
  host: string = DefaultHost;
  port: int = DefaultLightpandaPort;
  backend: BrowserBackendKind = bbAuto;
  executablePath: string = "";
  profileDir: string = "";
  http: HttpRuntimePort = HttpRuntimePort();
  proxyServer: string = "";
  timeoutMs: int = BrowserDefaultTimeoutMs;
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
    proxyServer: proxyServer,
    timeoutMs: clampBrowserTimeoutMs(timeoutMs),
    process: nil,
    pageTargetId: "",
    currentUrl: ""
  )

type
  BrowserToolRuntime* = ref object
    ## One browser process/page/profile/CDP port per session owner. The global
    ## ToolRuntimePort routes by ToolCall.userId.
    backend: BrowserBackendKind
    executablePath: string
    lightpandaPath: string
    profileBaseDir: string
    host: string
    port: int
    proxyServer: string
    idleTimeoutSeconds: float
    timeoutMs: int
    http: HttpRuntimePort
    ownerThread: int
    byUser*: Table[string, ref BrowserTools]

func browserUserKey*(raw: string): string =
  ## Reversible, collision-free encoding safe for directory names. Characters
  ## outside [A-Za-z0-9-] (including '_') become _XX, so "alice:a" and
  ## "alice_a" map to different keys.
  if raw.len == 0:
    return "__default__"
  for c in raw:
    if c.isAlphaNumeric() or c == '-':
      result.add(c)
    else:
      result.add('_')
      result.add(toHex(ord(c), 2))

proc newBrowserToolRuntime*(backend: BrowserBackendKind = bbAuto;
                             executablePath = "";
                             lightpandaPath = "";
                             profileBaseDir = "";
                             host = DefaultHost;
                             port = DefaultLightpandaPort;
                             http: HttpRuntimePort = HttpRuntimePort();
                             proxyServer = "";
                             idleTimeoutSeconds = 900.0;
                             timeoutMs = BrowserDefaultTimeoutMs
                            ): BrowserToolRuntime =
  BrowserToolRuntime(
    backend: backend,
    executablePath: executablePath,
    lightpandaPath: lightpandaPath,
    profileBaseDir: profileBaseDir,
    host: host,
    port: port,
    proxyServer: proxyServer,
    idleTimeoutSeconds: idleTimeoutSeconds,
    timeoutMs: clampBrowserTimeoutMs(timeoutMs),
    http: http,
    ownerThread: getThreadId(),
    byUser: initTable[string, ref BrowserTools](),
  )

proc onOwnerThread(rt: BrowserToolRuntime): bool {.gcsafe, raises: [].} =
  ## ToolRuntimePort callbacks are declared `gcsafe` because the port type
  ## requires it. That annotation is only honest while the runtime is confined
  ## to the daemon event-loop thread; this guard turns the invariant into a
  ## check instead of a compiler promise.
  {.cast(gcsafe).}:
    ## `getThreadId` is a thread-local read and `ownerThread` is an int; this
    ## scope touches no GC-managed global state.
    getThreadId() == rt.ownerThread

proc isPortAvailable(host: string; port: int): bool =
  ## Best-effort check for a free loopback port before spawning a browser.
  if port <= 0 or port > 65535:
    return false
  var sock = newSocket()
  try:
    sock.bindAddr(Port(port), host)
    result = true
  except CatchableError:
    result = false
  finally:
    sock.close()

proc allocatePort(rt: BrowserToolRuntime): int =
  ## Each user gets a distinct CDP endpoint; sharing one port would let a
  ## second runtime attach to the first user's page. Ports released by
  ## closeUser/evictIdle become available again.
  var used: Table[int, bool]
  for _, bt in rt.byUser:
    used[bt[].port] = true
  var candidate = rt.port
  while candidate <= 65535:
    if not used.hasKey(candidate) and isPortAvailable(rt.host, candidate):
      return candidate
    inc candidate
  0

proc listTools*(rt: BrowserToolRuntime): Result[seq[ToolSchema], string] =
  if not rt.onOwnerThread():
    return err("browser runtime used from a non-owner thread")
  newBrowserTools(
    backend = rt.backend,
    executablePath = rt.executablePath,
    lightpandaPath = rt.lightpandaPath,
    host = rt.host,
    port = rt.port,
    http = rt.http,
  ).listTools()

proc closeUser*(rt: BrowserToolRuntime; userId: string): Result[void, string] =
  ## Releases one user's browser process, page, profile and CDP port.
  if not rt.onOwnerThread():
    return err("browser runtime closeUser called from a non-owner thread")
  let key = browserUserKey(userId)
  if key in rt.byUser:
    rt.byUser[key][].close()
    rt.byUser.del(key)
  ok()

proc evictIdle*(rt: BrowserToolRuntime) =
  ## Bounds resource accumulation when no session-end callback is available.
  ## The daemon heartbeat calls this periodically, so idle browsers are closed
  ## even when no further tool invocation arrives.
  if not rt.onOwnerThread() or rt.idleTimeoutSeconds <= 0:
    return
  let now = epochTime()
  var stale: seq[string]
  for key, bt in rt.byUser:
    if now - bt[].lastUsed > rt.idleTimeoutSeconds:
      stale.add(key)
  for key in stale:
    rt.byUser[key][].close()
    rt.byUser.del(key)

proc invoke*(rt: BrowserToolRuntime; call: ToolCall): Result[ToolResult, string] =
  if not rt.onOwnerThread():
    return err("browser runtime used from a non-owner thread")
  rt.evictIdle()
  let key = browserUserKey(call.userId)
  if key notin rt.byUser:
    let userPort = rt.allocatePort()
    if userPort == 0:
      return err("no free CDP port available for browser session")
    var bt = newBrowserTools(
      backend = rt.backend,
      executablePath = rt.executablePath,
      lightpandaPath = rt.lightpandaPath,
      host = rt.host,
      port = userPort,
      http = rt.http,
      proxyServer = rt.proxyServer,
      timeoutMs = rt.timeoutMs,
    )
    if rt.profileBaseDir.len > 0:
      # Operator-provided profiles persist across runs; never delete them, but
      # keep cookies and local storage private to the daemon user.
      bt.profileDir = rt.profileBaseDir / key
      try:
        createDir(bt.profileDir)
      except CatchableError as e:
        return err("cannot prepare browser profile dir: " & e.msg)
      let hardened = hardenProfileDir(bt.profileDir)
      if hardened.isErr:
        return err(hardened.error)
      bt.ownsProfileDir = false
    let holder = new(BrowserTools)
    holder[] = bt
    rt.byUser[key] = holder
  rt.byUser[key][].invoke(call)

proc close*(rt: BrowserToolRuntime): Result[void, string] =
  if not rt.onOwnerThread():
    return err("browser runtime close called from a non-owner thread")
  for _, bt in rt.byUser.mpairs:
    bt[].close()
  rt.byUser.clear()
  ok()

proc toRuntimePort*(rt: BrowserToolRuntime): ToolRuntimePort =
  ToolRuntimePort(
    listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} =
      rt.listTools(),
    invoke: proc(call: ToolCall): Result[ToolResult, string] {.gcsafe.} =
      rt.invoke(call),
    close: proc() {.gcsafe.} =
      ## ToolRuntimePort.close is void; the Result is deliberately swallowed
      ## at this boundary. Wrong-thread refusal still happens without throwing.
      discard rt.close(),
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
