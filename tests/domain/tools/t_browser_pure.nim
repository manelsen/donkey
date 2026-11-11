## Tests for pure browser backend policy.

import std/[sequtils, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/tools/browser_pure

suite "browser backend policy":

  test "parses backend names and aliases":
    check parseBrowserBackend("").get() == bbOff
    check parseBrowserBackend("off").get() == bbOff
    check parseBrowserBackend("auto").get() == bbAuto
    check parseBrowserBackend("lightpanda").get() == bbLightpanda
    check parseBrowserBackend("edge").get() == bbEdge
    check parseBrowserBackend("microsoft-edge").get() == bbEdge
    check parseBrowserBackend("chromium").get() == bbChromium
    check parseBrowserBackend("chrome").get() == bbChromium
    check parseBrowserBackend("bogus").isErr

  test "auto prefers Lightpanda, then Edge, then Chromium":
    let candidates = browserExecutableCandidates(bbAuto)
    check candidates[0] == "lightpanda"
    check candidates[1].contains("microsoft-edge")
    check candidates[^1].contains("google-chrome")

  test "Lightpanda launch spec uses the browser CDP endpoint":
    let spec = buildLaunchSpec(bbLightpanda, "/usr/bin/lightpanda",
                               "127.0.0.1", 9222, "").get()
    check spec.exe == "/usr/bin/lightpanda"
    check spec.wsMode == wsmBrowserPath
    check spec.args == @["serve", "--host", "127.0.0.1", "--port", "9222"]

  test "Edge launch spec is headless Chromium with a page target":
    let spec = buildLaunchSpec(bbEdge, "/usr/bin/microsoft-edge",
                               "127.0.0.1", 9333, "/tmp/profile").get()
    check spec.wsMode == wsmPageTarget
    check spec.args.contains("--headless=new")
    check spec.args.contains("--remote-debugging-port=9333")
    check spec.args.contains("--user-data-dir=/tmp/profile")
    check spec.args.contains("--remote-allow-origins=*")
    check spec.args[^1] == "about:blank"

  test "Chromium launch spec shares the Edge strategy":
    let spec = buildLaunchSpec(bbChromium, "/usr/bin/chromium",
                               "127.0.0.1", 9222, "").get()
    check spec.wsMode == wsmPageTarget
    check spec.args.contains("--headless=new")
    check not spec.args.anyIt(it.startsWith("--user-data-dir="))

  test "resolved backends are required for launch":
    check buildLaunchSpec(bbAuto, "/bin/x", "127.0.0.1", 9222, "").isErr
    check buildLaunchSpec(bbOff, "/bin/x", "127.0.0.1", 9222, "").isErr

  test "parses Chromium page websocket URLs":
    let page = parseWsDebuggerUrl(
      "ws://127.0.0.1:9222/devtools/page/ABC123").get()
    check page.host == "127.0.0.1"
    check page.port == 9222
    check page.path == "/devtools/page/ABC123"

    let browser = parseWsDebuggerUrl(
      "ws://localhost:9333/devtools/browser/XYZ").get()
    check browser.host == "localhost"
    check browser.port == 9333
    check browser.path == "/devtools/browser/XYZ"
    check not browser.secure

    let secure = parseWsDebuggerUrl(
      "wss://127.0.0.1:9222/devtools/page/SEC").get()
    check secure.secure

  test "rejects malformed websocket URLs":
    check parseWsDebuggerUrl("http://127.0.0.1:9222/json").isErr
    check parseWsDebuggerUrl("ws://127.0.0.1/devtools/page/x").isErr
    check parseWsDebuggerUrl("ws://127.0.0.1:notaport/x").isErr

