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
