## Stress: webhook receiver TLS handshakes, restarts and slow clients.

import std/[monotimes, net, os, osproc, strutils, times, unittest]
import results
import donkey/core/log
import donkey/adapters/webhook/webhook_receiver

let stressDir = getTempDir() / ("donkey_stress_tls_" & $getCurrentProcessId())
let stressLog = newLogger("stress.tls", lvlError)

proc generateCert(prefix: string): tuple[cert: string, key: string] =
  if findExe("openssl").len == 0:
    return ("", "")
  let dir = prefix & "-" & $epochTime().int64 & "-" & $getCurrentProcessId()
  createDir(dir)
  let cert = dir / "cert.pem"
  let key = dir / "key.pem"
  let cmd = "openssl req -x509 -newkey rsa:2048 -nodes -keyout " & quoteShell(key) &
            " -out " & quoteShell(cert) & " -days 1 -subj /CN=localhost" &
            " -addext subjectAltName=DNS:localhost,IP:127.0.0.1 2>/dev/null"
  let exitCode = execCmd(cmd)
  if exitCode != 0:
    raise newException(OSError,
      "openssl req failed with exit code " & $exitCode & " (see cert dir " & dir & ")")
  (cert, key)

proc freePort(): int =
  var probe = newSocket()
  probe.setSockOpt(OptReuseAddr, true)
  probe.bindAddr(Port(0), "127.0.0.1")
  let (_, port) = probe.getLocalAddr()
  probe.close()
  int(port)

proc slackSignature(secret, timestamp, body: string): string =
  "v0=" & hmacSha256Hex(secret, "v0:" & timestamp & ":" & body)

proc requestChallenge(port: int; secret, challenge: string): string =
  let body = "{\"type\":\"url_verification\",\"challenge\":\"" & challenge & "\"}"
  let timestamp = $epochTime().int64
  let signature = slackSignature(secret, timestamp, body)
  let request = "POST " & SlackPath & " HTTP/1.1\r\n" &
                "Host: localhost\r\n" &
                "Content-Type: application/json\r\n" &
                "Content-Length: " & $body.len & "\r\n" &
                "X-Slack-Request-Timestamp: " & timestamp & "\r\n" &
                "X-Slack-Signature: " & signature & "\r\n" &
                "Connection: close\r\n\r\n" & body

  var client = newSocket()
  client.connect("127.0.0.1", Port(port))
  let ctx = newContext(verifyMode = CVerifyNone)
  try:
    ctx.wrapConnectedSocket(client, handshakeAsClient)
    client.send(request)
    var response = ""
    while true:
      var chunk = ""
      let n = client.recv(chunk, 4096, 5000)
      if n <= 0:
        break
      response.add(chunk)
    response
  finally:
    try: client.close() except CatchableError: discard

suite "webhook TLS stress":

  test "twenty sequential TLS handshakes are served":
    let (cert, key) = generateCert(stressDir / "sequential")
    if cert.len == 0:
      echo "skipping TLS stress: openssl unavailable"
    else:
      let port = freePort()
      let secret = "stress-secret"
      let cfg = WebhookConfig(slackSigningSecret: secret,
                              tlsCertFile: cert, tlsKeyFile: key)
      let started = startWebhookReceiver(cfg, port, "127.0.0.1", stressLog)
      check started.isOk
      defer: stopWebhookReceiver()

      for i in 0 ..< 20:
        let response = requestChallenge(port, secret, "ch-" & $i)
        check "200 OK" in response
        check "ch-" & $i in response

  test "five TLS start/stop cycles remain clean":
    let (cert, key) = generateCert(stressDir / "restart")
    if cert.len == 0:
      echo "skipping TLS restart stress: openssl unavailable"
    else:
      let port = freePort()
      let secret = "restart-secret"
      let cfg = WebhookConfig(slackSigningSecret: secret,
                              tlsCertFile: cert, tlsKeyFile: key)
      for i in 0 ..< 5:
        let started = startWebhookReceiver(cfg, port, "127.0.0.1", stressLog)
        check started.isOk
        let response = requestChallenge(port, secret, "restart-" & $i)
        check "200 OK" in response
        stopWebhookReceiver()

      let badCfg = WebhookConfig(
        slackSigningSecret: secret,
        tlsCertFile: cert & ".missing",
        tlsKeyFile: key & ".missing")
      let badStart = startWebhookReceiver(
        badCfg, freePort(), "127.0.0.1", stressLog)
      check badStart.isErr
      check "TLS certificate" in badStart.error

  test "invalid TLS rotation keeps serving with the old context":
    let (cert, key) = generateCert(stressDir / "rotation")
    if cert.len == 0:
      echo "skipping TLS rotation stress: openssl unavailable"
    else:
      let port = freePort()
      let secret = "rotation-secret"
      let cfg = WebhookConfig(slackSigningSecret: secret,
                              tlsCertFile: cert, tlsKeyFile: key)
      var logChan: Channel[string]
      logChan.open(16)
      let rotationLog = newLogger("stress.tls.rotation", lvlError,
        proc(entry: LogEntry) {.gcsafe.} =
          {.cast(gcsafe).}:
            {.cast(raises: []).}:
              logChan.send(entry.message))
      let started = startWebhookReceiver(cfg, port, "127.0.0.1", rotationLog)
      check started.isOk
      defer: stopWebhookReceiver()

      ## Break the files on disk. The worker must keep the previous context.
      writeFile(cert, "not a certificate")
      writeFile(key, "not a key")
      sleep(1100)
      let response = requestChallenge(port, secret, "rotation-ok")
      check "200 OK" in response
      check "rotation-ok" in response

      var sawReloadError = false
      while true:
        let (hasMessage, message) = logChan.tryRecv()
        if not hasMessage:
          break
        if "cannot load TLS certificate" in message:
          sawReloadError = true
      logChan.close()
      check sawReloadError

  test "a slow TLS client does not block shutdown forever":
    let (cert, key) = generateCert(stressDir / "slow")
    if cert.len == 0:
      echo "skipping TLS slow-client stress: openssl unavailable"
    else:
      let port = freePort()
      let secret = "slow-secret"
      let cfg = WebhookConfig(slackSigningSecret: secret,
                              tlsCertFile: cert, tlsKeyFile: key)
      let started = startWebhookReceiver(cfg, port, "127.0.0.1", stressLog)
      check started.isOk
      defer: stopWebhookReceiver()

      var slow = newSocket()
      slow.connect("127.0.0.1", Port(port))
      let slowCtx = newContext(verifyMode = CVerifyNone)
      slowCtx.wrapConnectedSocket(slow, handshakeAsClient)
      ## Deliberately send no HTTP request.

      let fastResponse = requestChallenge(port, secret, "fast")
      check "200 OK" in fastResponse

      let startedStop = getMonoTime()
      stopWebhookReceiver()
      let elapsed = inMilliseconds(getMonoTime() - startedStop)
      check elapsed < 10_000

      try: slow.close() except CatchableError: discard
