## Tests for pure browser backend policy.

import std/[options, sequtils, strutils, unicode, unittest]
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

  test "Chromium launch spec disables background egress":
    let spec = buildLaunchSpec(bbChromium, "/usr/bin/chromium",
                               "127.0.0.1", 9222, "").get()
    for flag in ["--disable-background-networking", "--disable-component-update",
                 "--disable-default-apps", "--disable-extensions", "--disable-sync",
                 "--dns-prefetch-disable", "--no-pings", "--metrics-recording-only"]:
      check spec.args.contains(flag)

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

suite "browser request policy":

  test "classifies CDP resource types":
    check browserResourceKind("Document") == brkDocument
    check browserResourceKind("document") == brkDocument
    check browserResourceKind("WebSocket") == brkWebSocket
    check browserResourceKind("ServiceWorker") == brkServiceWorker
    check browserResourceKind("Script") == brkSubresource
    check browserResourceKind("") == brkUnknown

  test "documents never use inline schemes":
    for url in ["data:text/html,hello", "blob:https://example.com/x", "about:blank"]:
      check not browserSchemeAllowedFor(url, brkDocument)
      check browserSchemeAllowedFor(url, brkSubresource)

  test "network subresources require HTTP(S)":
    check browserSchemeAllowedFor("https://example.com/a.js", brkSubresource)
    check browserSchemeAllowedFor("http://example.com/", brkDocument)
    for url in ["file:///etc/passwd", "chrome://settings", "ftp://example.com/x",
                "filesystem:https://example.com/temporary/x", "javascript:alert(1)"]:
      check not browserSchemeAllowedFor(url, brkSubresource)
      check not browserSchemeAllowedFor(url, brkDocument)

  test "WebSocket and service worker are always denied by the pure gate":
    check not browserSchemeAllowedFor("wss://example.com/socket", brkWebSocket)
    check not browserSchemeAllowedFor("ws://example.com/socket", brkWebSocket)
    check not browserSchemeAllowedFor("https://example.com/sw.js", brkServiceWorker)

  test "clamps browser timeouts at the documented bounds":
    check clampBrowserTimeoutMs(0) == BrowserDefaultTimeoutMs
    check clampBrowserTimeoutMs(-1) == BrowserDefaultTimeoutMs
    check clampBrowserTimeoutMs(1) == BrowserMinTimeoutMs
    check clampBrowserTimeoutMs(45_000) == 45_000
    check clampBrowserTimeoutMs(999_999) == BrowserMaxTimeoutMs
    check parseBrowserTimeoutMs("") == BrowserDefaultTimeoutMs
    check parseBrowserTimeoutMs("bogus") == BrowserDefaultTimeoutMs
    check parseBrowserTimeoutMs("15000") == 15_000

  test "clamps content requests and truncates before serialization":
    check clampBrowserContentChars(0) == BrowserDefaultMaxContentChars
    check clampBrowserContentChars(-1) == BrowserDefaultMaxContentChars
    check clampBrowserContentChars(10) == 10
    check clampBrowserContentChars(10_000_000) == BrowserMaxContentChars
    let expr = browserContentExpression(1234)
    check "document.documentElement.outerHTML" in expr
    check "slice(0, 1234)" in expr
    check "[truncated]" in expr
    check "slice(0, 1234)" notin browserContentExpression(BrowserMaxContentChars + 1)

  test "screenshot payload cap is inclusive":
    check not screenshotTooLarge("abc", 3)
    check screenshotTooLarge("abcd", 3)
    check not screenshotTooLarge("", 3)

  test "local content cap does not depend on page slice":
    check capBrowserContent("abc", 3) == "abc"
    let capped = capBrowserContent("abcdef", 3)
    check capped.startsWith("abc")
    check "[truncated]" in capped
    check capBrowserContent("abcdef", 0).len <= BrowserDefaultMaxContentChars + 12

  test "local content cap preserves UTF-8 boundaries":
    check capBrowserContent("é", 2) == "é"
    check validateUtf8(capBrowserContent("é", 1)) == -1
    check validateUtf8(capBrowserContent("a😀b", 2)) == -1
    check capBrowserContent("a😀b", 2).startsWith("a")
    check validateUtf8(capBrowserContent("ação", 4)) == -1

  test "text extraction avoids outerHTML and skips markup":
    let expr = browserTextExpression(1234)
    check "document.body" in expr
    check "innerText" in expr
    check "textContent" in expr
    check "slice(0, 1234)" in expr
    check "outerHTML" notin expr

  test "policy script blocks side channels and service workers":
    let script = browserPolicyScript()
    for needle in ["deny('WebSocket')", "deny('WebTransport')",
                   "deny('RTCPeerConnection')", "deny('webkitRTCPeerConnection')",
                   "deny('Worker')", "deny('SharedWorker')", "sendBeacon",
                   "ServiceWorkerContainer.prototype", "blockRegister",
                   "serviceWorker", "unregister",
                   "navigator.serviceWorker, 'register'"]:
      check needle in script
