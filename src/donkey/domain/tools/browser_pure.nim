## browser_pure — backend selection and launch/WS specifications.
##
## Pure functions only: no process spawning, no filesystem, no network. The
## adapter (`adapters/tools/browser.nim`) resolves executables and performs I/O;
## this module owns the policy so Edge/Chromium/Lightpanda do not leak into the
## tool invocation path.

import std/[strutils]
import ../../core/pipeops

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

func parseBrowserBackend*(raw: string): Result[BrowserBackendKind, string] =
  ## Accepts the env spelling and a few common aliases.
  case raw.strip.toLowerAscii()
  of "", "off", "disabled", "none", "0":
    ok(bbOff)
  of "auto":
    ok(bbAuto)
  of "lightpanda":
    ok(bbLightpanda)
  of "edge", "microsoft-edge", "msedge":
    ok(bbEdge)
  of "chromium", "chrome", "google-chrome":
    ok(bbChromium)
  else:
    err("unknown browser backend: " & raw)

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
                      profileDir: string): Result[BrowserLaunchSpec, string] =
  ## Builds the launch argv for a concrete backend. `exe` must already be
  ## resolved by the adapter.
  if kind in {bbOff, bbAuto}:
    return err("browser backend must be resolved before launch")
  if exe.len == 0:
    return err("empty browser executable")
  if host.len == 0:
    return err("empty browser host")
  if port <= 0 or port > 65535:
    return err("invalid browser port")

  case kind
  of bbLightpanda:
    ok(BrowserLaunchSpec(
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
    args.add("about:blank")
    ok(BrowserLaunchSpec(
      kind: kind,
      exe: exe,
      args: args,
      wsMode: wsmPageTarget,
    ))
  of bbOff, bbAuto:
    err("unreachable browser backend")

func parseWsDebuggerUrl*(raw: string): Result[BrowserEndpoint, string] =
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
    return err("unsupported CDP websocket URL: " & raw)

  let slash = rest.find('/')
  if slash <= 0:
    return err("CDP websocket URL has no path: " & raw)
  let authority = rest[0 ..< slash]
  let path = rest[slash .. ^1]
  let colon = authority.rfind(':')
  if colon <= 0 or colon == authority.high:
    return err("CDP websocket URL has no port: " & raw)
  let host = authority[0 ..< colon]
  var port: int
  try:
    port = parseInt(authority[colon + 1 .. ^1])
  except ValueError:
    return err("CDP websocket URL has an invalid port: " & raw)
  if port <= 0 or port > 65535:
    return err("CDP websocket URL has an invalid port: " & raw)
  ok(BrowserEndpoint(host: host, port: port, path: path, secure: secure))
