## browser_pure — backend selection and launch/WS specifications.
##
## Pure functions only: no process spawning, no filesystem, no network. The
## adapter (`adapters/tools/browser.nim`) resolves executables and performs I/O;
## this module owns the policy so Edge/Chromium/Lightpanda do not leak into the
## tool invocation path.

import std/[options, os, strutils]

type
  BrowserBackendKind* = enum
    bbAuto
    bbOff
    bbLightpanda
    bbEdge
    bbChromium

  BrowserRequestKind* = enum
    brkUnknown
    brkDocument
    brkSubresource
    brkWebSocket
    brkServiceWorker

  BrowserWsMode* = enum
    wsmBrowserPath   ## Lightpanda: /devtools/browser
    wsmPageTarget    ## Chromium/Edge: page webSocketDebuggerUrl from /json/list

  BrowserLaunchSpec* = object
    kind*:   BrowserBackendKind
    exe*:    string
    args*:   seq[string]
    wsMode*: BrowserWsMode

  BrowserEndpoint* = object
    host*: string
    port*: int
    path*: string
    secure*: bool

const
  DefaultBrowserHost* = "127.0.0.1"
  DefaultBrowserPort* = 9222
  BrowserDefaultTimeoutMs* = 30_000
  BrowserMinTimeoutMs* = 1_000
  BrowserMaxTimeoutMs* = 120_000
  BrowserDefaultMaxContentChars* = 50_000
  BrowserMaxContentChars* = 500_000
  BrowserMaxScreenshotBytes* = 8 * 1024 * 1024
  BrowserMaxCdpFrameBytes* = 16 * 1024 * 1024

func parseBrowserBackend*(raw: string): Option[BrowserBackendKind] =
  ## Accepts the env spelling and a few common aliases. `none` means an
  ## invalid value, not the explicit `off` option.
  case raw.strip.toLowerAscii()
  of "", "off", "disabled", "none", "0":
    some(bbOff)
  of "auto":
    some(bbAuto)
  of "lightpanda":
    some(bbLightpanda)
  of "edge", "microsoft-edge", "msedge":
    some(bbEdge)
  of "chromium", "chrome", "google-chrome":
    some(bbChromium)
  else:
    none(BrowserBackendKind)

func isChromiumBackend*(kind: BrowserBackendKind): bool =
  kind in {bbEdge, bbChromium}

func browserExecutableCandidates*(kind: BrowserBackendKind): seq[string] =
  case kind
  of bbLightpanda:
    @["lightpanda"]
  of bbEdge:
    @["microsoft-edge", "microsoft-edge-stable", "microsoft-edge-beta", "msedge"]
  of bbChromium:
    @["chromium", "chromium-browser", "google-chrome", "google-chrome-stable"]
  of bbAuto:
    @["lightpanda", "microsoft-edge", "microsoft-edge-stable", "msedge",
      "chromium", "chromium-browser", "google-chrome", "google-chrome-stable"]
  of bbOff:
    @[]

func buildLaunchSpec*(kind: BrowserBackendKind;
                      exe, host: string;
                      port: int;
                      profileDir: string;
                      proxy = ""): Option[BrowserLaunchSpec] =
  ## Builds the launch argv for a concrete backend. `exe` must already be
  ## resolved by the adapter.
  if kind in {bbOff, bbAuto}:
    return none(BrowserLaunchSpec)
  if exe.len == 0 or host.len == 0 or port <= 0 or port > 65535:
    return none(BrowserLaunchSpec)

  case kind
  of bbLightpanda:
    some(BrowserLaunchSpec(
      kind: kind,
      exe: exe,
      args: @["serve", "--host", host, "--port", $port],
      wsMode: wsmBrowserPath,
    ))
  of bbEdge, bbChromium:
    var args = @[
      "--headless=new",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-default-apps",
      "--disable-domain-reliability",
      "--disable-extensions",
      "--disable-sync",
      "--dns-prefetch-disable",
      "--metrics-recording-only",
      "--no-pings",
      "--remote-allow-origins=*",
      "--remote-debugging-port=" & $port,
    ]
    if profileDir.len > 0:
      args.add("--user-data-dir=" & profileDir)
    if proxy.len > 0:
      args.add("--proxy-server=" & proxy)
      # Chromium bypasses proxies for loopback by default; <-loopback> removes
      # that bypass so the filtering proxy also sees internal destinations.
      args.add("--proxy-bypass-list=<-loopback>")
    args.add("about:blank")
    some(BrowserLaunchSpec(
      kind: kind,
      exe: exe,
      args: args,
      wsMode: wsmPageTarget,
    ))
  of bbOff, bbAuto:
    none(BrowserLaunchSpec)

func inferBrowserBackend*(exe: string): Option[BrowserBackendKind] =
  ## Infers a backend from an explicit executable path/name.
  let name = exe.extractFilename.toLowerAscii
  if "lightpanda" in name:
    some(bbLightpanda)
  elif "edge" in name or "msedge" in name:
    some(bbEdge)
  elif "chrom" in name or "chrome" in name:
    some(bbChromium)
  else:
    none(BrowserBackendKind)

func isHttpUrl*(url: string): bool =
  let value = url.strip.toLowerAscii
  value.startsWith("http://") or value.startsWith("https://")

func browserResourceKind*(resourceType: string): BrowserRequestKind =
  ## Maps the CDP `resourceType`/event family to the policy bucket. Unknown
  ## values are treated as subresources so they still get URL/DNS validation.
  case resourceType.strip.toLowerAscii
  of "document": brkDocument
  of "websocket": brkWebSocket
  of "serviceworker", "service_worker": brkServiceWorker
  of "": brkUnknown
  else: brkSubresource

func isInlineBrowserUrl*(url: string): bool =
  ## Inline content never reaches the network. It is allowed as a subresource
  ## but never as a top-level document.
  let value = url.strip.toLowerAscii
  value.startsWith("data:") or value.startsWith("blob:") or
    value.startsWith("about:")

func isNetworkBrowserUrl*(url: string): bool =
  isHttpUrl(url)

func browserSchemeAllowedFor*(url: string; kind: BrowserRequestKind): bool =
  ## Pure scheme gate. DNS/private-address checks live in the adapter because
  ## they perform I/O; this function is the single source of truth for which
  ## schemes may leave the browser at all.
  if kind in {brkWebSocket, brkServiceWorker}:
    return false
  if isInlineBrowserUrl(url):
    return kind != brkDocument
  if not isNetworkBrowserUrl(url):
    return false
  kind in {brkUnknown, brkDocument, brkSubresource}

func clampBrowserTimeoutMs*(raw: int): int =
  if raw <= 0:
    BrowserDefaultTimeoutMs
  elif raw < BrowserMinTimeoutMs:
    BrowserMinTimeoutMs
  elif raw > BrowserMaxTimeoutMs:
    BrowserMaxTimeoutMs
  else:
    raw

func parseBrowserTimeoutMs*(raw: string): int =
  let value = raw.strip
  if value.len == 0:
    return BrowserDefaultTimeoutMs
  try:
    clampBrowserTimeoutMs(parseInt(value))
  except ValueError:
    BrowserDefaultTimeoutMs

func clampBrowserContentChars*(requested: int): int =
  if requested <= 0:
    BrowserDefaultMaxContentChars
  elif requested > BrowserMaxContentChars:
    BrowserMaxContentChars
  else:
    requested

func browserContentExpression*(maxChars: int): string =
  ## Truncates inside the page before CDP serializes the DOM. A multi-megabyte
  ## document therefore never crosses the WebSocket just to be cut afterwards.
  let cap = clampBrowserContentChars(maxChars)
  "(() => { const h = document.documentElement ? " &
    "document.documentElement.outerHTML : ''; " &
    "return h.length > " & $cap & " ? h.slice(0, " & $cap &
    ") + \"\\n[truncated]\" : h; })()"

func browserTextExpression*(maxChars: int): string =
  ## Extracts visible text before serialization. This avoids losing body text
  ## behind long attributes/comments in outerHTML and skips script/style.
  let cap = clampBrowserContentChars(maxChars)
  "(() => { const root = document.body || document.documentElement; " &
    "if (!root) return ''; " &
    "const t = (root.innerText !== undefined ? root.innerText : root.textContent) || ''; " &
    "return t.length > " & $cap & " ? t.slice(0, " & $cap &
    ") + \"\\n[truncated]\" : t; })()"

func capBrowserContent*(text: string; maxChars: int): string =
  ## Local cap applied after CDP serialization. The in-page expression is the
  ## first layer; a page can override String.prototype.slice, so this Nim-side
  ## check is what actually bounds what reaches the tool consumer. The cut is
  ## moved back to a UTF-8 boundary so truncation never emits invalid bytes.
  let cap = clampBrowserContentChars(maxChars)
  if text.len <= cap:
    return text
  var cut = cap
  while cut > 0 and (ord(text[cut]) and 0xC0) == 0x80:
    dec cut
  text[0 ..< cut] & "\n[truncated]"

func screenshotTooLarge*(data: string;
                         maxBytes = BrowserMaxScreenshotBytes): bool =
  maxBytes > 0 and data.len > maxBytes

func browserPolicyScript*(): string =
  ## Installed before every document. CDP Fetch covers HTTP(S) requests, but
  ## WebSockets, WebRTC and service worker registration need an in-page gate.
  ## The Network domain remains a second layer for engines that ignore the
  ## script or create sockets from workers.
  result = """
(() => {
  const deny = (name) => { throw new Error(name + ' blocked by Donkey browser policy'); };
  try {
    Object.defineProperty(globalThis, 'WebSocket', {
      configurable: false, writable: false,
      value: function() { deny('WebSocket'); }
    });
  } catch (e) {}
  try {
    Object.defineProperty(globalThis, 'WebTransport', {
      configurable: false, writable: false,
      value: function() { deny('WebTransport'); }
    });
  } catch (e) {}
  try {
    Object.defineProperty(globalThis, 'RTCPeerConnection', {
      configurable: false, writable: false,
      value: function() { deny('RTCPeerConnection'); }
    });
  } catch (e) {}
  try {
    Object.defineProperty(globalThis, 'webkitRTCPeerConnection', {
      configurable: false, writable: false,
      value: function() { deny('webkitRTCPeerConnection'); }
    });
  } catch (e) {}
  try {
    Object.defineProperty(globalThis, 'Worker', {
      configurable: false, writable: false,
      value: function() { deny('Worker'); }
    });
  } catch (e) {}
  try {
    Object.defineProperty(globalThis, 'SharedWorker', {
      configurable: false, writable: false,
      value: function() { deny('SharedWorker'); }
    });
  } catch (e) {}
  try { globalThis.open = function() { return null; }; } catch (e) {}
  try { navigator.sendBeacon = function() { return false; }; } catch (e) {}
  try {
    if (navigator.serviceWorker) {
      navigator.serviceWorker.register = function() {
        return Promise.reject(new Error('service worker blocked by Donkey browser policy'));
      };
      navigator.serviceWorker.getRegistrations()
        .then(rs => rs.forEach(r => r.unregister()))
        .catch(() => {});
    }
  } catch (e) {}
})();
"""

func parseWsDebuggerUrl*(raw: string): Option[BrowserEndpoint] =
  ## Parses the `webSocketDebuggerUrl` returned by Chromium's /json/list.
  ## Accepts ws:// and wss://; only local CDP is used by the adapter.
  let value = raw.strip
  var rest = ""
  var secure = false
  if value.startsWith("ws://"):
    rest = value["ws://".len .. ^1]
  elif value.startsWith("wss://"):
    rest = value["wss://".len .. ^1]
    secure = true
  else:
    return none(BrowserEndpoint)

  let slash = rest.find('/')
  if slash <= 0:
    return none(BrowserEndpoint)
  let authority = rest[0 ..< slash]
  let path = rest[slash .. ^1]
  let colon = authority.rfind(':')
  if colon <= 0 or colon == authority.high:
    return none(BrowserEndpoint)
  let host = authority[0 ..< colon]
  var port: int
  try:
    port = parseInt(authority[colon + 1 .. ^1])
  except ValueError:
    return none(BrowserEndpoint)
  if port <= 0 or port > 65535:
    return none(BrowserEndpoint)
  some(BrowserEndpoint(host: host, port: port, path: path, secure: secure))
