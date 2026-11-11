## Tests for pure browser backend policy.

import std/[options, sequtils, strutils, unittest]
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
    check parseBrowserBackend("bogus").isNone

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

  test "Chromium launch spec routes egress through a filtering proxy":
    let spec = buildLaunchSpec(bbChromium, "/usr/bin/chromium",
                               "127.0.0.1", 9222, "", "http://127.0.0.1:3128").get()
    check spec.args.contains("--proxy-server=http://127.0.0.1:3128")
    check spec.args.contains("--proxy-bypass-list=<-loopback>")

  test "Lightpanda ignores proxy configuration":
    let spec = buildLaunchSpec(bbLightpanda, "/usr/bin/lightpanda",
                               "127.0.0.1", 9222, "", "http://127.0.0.1:3128").get()
    check not spec.args.anyIt(it.startsWith("--proxy-server="))

  test "resolved backends are required for launch":
    check buildLaunchSpec(bbAuto, "/bin/x", "127.0.0.1", 9222, "").isNone
    check buildLaunchSpec(bbOff, "/bin/x", "127.0.0.1", 9222, "").isNone

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
    check parseWsDebuggerUrl("http://127.0.0.1:9222/json").isNone
    check parseWsDebuggerUrl("ws://127.0.0.1/devtools/page/x").isNone
    check parseWsDebuggerUrl("ws://127.0.0.1:notaport/x").isNone


  test "infers a backend from an explicit executable path":
    check inferBrowserBackend("/usr/bin/microsoft-edge").get() == bbEdge
    check inferBrowserBackend("/usr/bin/chromium").get() == bbChromium
    check inferBrowserBackend("/opt/lightpanda").get() == bbLightpanda
    check inferBrowserBackend("/usr/bin/firefox").isNone

  test "accepts only HTTP(S) navigation schemes":
    check isHttpUrl("https://example.com")
    check isHttpUrl("http://example.com")
    check not isHttpUrl("file:///etc/passwd")
    check not isHttpUrl("data:text/html,hello")
    check not isHttpUrl("chrome://settings")
