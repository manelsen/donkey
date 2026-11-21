## webhook_receiver.nim — HTTP webhook receiver for callback-style channels.
##
## Adapter layer (I/O boundary). It owns the HTTP listener and payload parsing,
## then forwards each payload to the channel adapter's existing `pushEvent`. The
## application layer keeps draining the adapters' queues exactly as before;
## this module never imports app/.
##
## The shared ingress decision (`WebhookRequest`, `WebhookAuthSpec`,
## `decideIngress`) lives in `webhook_ingress` and is re-exported here, as are
## the core MAC primitives, so every existing import keeps working.
##
## Channels and authentication:
##   Slack    — X-Slack-Signature (v0 HMAC-SHA256) + replay window
##   Feishu   — verification token (url_verification challenge echoed back)
##   DingTalk — timestamp/sign HMAC-SHA256 signature
##   LINE     — X-Line-Signature: base64 HMAC-SHA256 of the raw body
##   Matrix   — shared bearer token (Authorization or ?access_token=)
##   WhatsApp — hub.verify_token challenge (GET) + X-Hub-Signature-256 (POST)
##
## A channel route is only mounted when its secret is configured, so no
## unauthenticated endpoint is ever exposed.

import std/[atomics, base64, json, monotimes, net, os, posix, strutils, tables, times]
import nimcrypto/[bcmode, rijndael, sha2]
import ../../core/log
import ../../core/pipeops
import ../../domain/channels/line_policy
import ./webhook_ingress
import ./http_request_reader
import ../channel/slack
import ../channel/feishu
import ../channel/dingtalk
import ../channel/line
import ../channel/matrix
import ../channel/whatsapp

export webhook_ingress
export http_request_reader.MaxWebhookBodyBytes

const
  SlackPath*    = "/webhook/slack"
  FeishuPath*   = "/webhook/feishu"
  DingTalkPath* = "/webhook/dingtalk"
  LinePath*     = "/webhook/line"
  MatrixPath*   = "/webhook/matrix"
  WhatsAppPath* = "/webhook/whatsapp"

  SlackReplayWindowSec*      = 300
  FeishuReplayWindowSec*     = 300
  DingTalkTimestampWindowMs* = 3_600_000
  LineMaxBodyBytes*          = 1 * 1024 * 1024
  WebhookTlsReloadIntervalMs = 1000

  WebhookWorkerCount        = 4
  WebhookQueueDepth         = 32

type
  WebhookResponse* = object
    status*:      int
    body*:        string
    contentType*: string

  WebhookConfig* = object
    slackSigningSecret*:      string
    feishuVerificationToken*: string
    feishuEncryptKey*:        string
    dingtalkAppSecret*:       string
    lineChannelSecret*:       string
    lineChannelAccessToken*:  string
    lineAllowedGroups*:       seq[string]
    lineAllowedUsers*:        seq[string]
    matrixToken*:             string
    whatsappVerifyToken*:     string
    whatsappAppSecret*:       string
    tlsCertFile*:             string
    tlsKeyFile*:              string

# ── Response helpers ──────────────────────────────────────────────────────────

func plainResp(status: int; body = ""): WebhookResponse =
  WebhookResponse(status: status, body: body, contentType: "text/plain")

func jsonResp(status: int; body: string): WebhookResponse =
  WebhookResponse(status: status, body: body, contentType: "application/json")

func notFound(): WebhookResponse = plainResp(404, "not found")
func forbidden(): WebhookResponse = plainResp(403, "forbidden")
func badRequest(): WebhookResponse = plainResp(400, "bad request")
func methodNotAllowed(): WebhookResponse = plainResp(405, "method not allowed")
func payloadTooLarge(): WebhookResponse = plainResp(413, "payload too large")
func serviceUnavailable(): WebhookResponse = plainResp(503, "server busy")

# ── Payload helpers ───────────────────────────────────────────────────────────

proc parsePayload(body: string): Result[JsonNode, string] =
  if body.len == 0:
    return err("empty body")
  try:
    ok(parseJson(body))
  except CatchableError:
    err("invalid JSON payload")

func feishuToken(payload: JsonNode): string =
  ## Feishu v1 carries `token` at top level; v2 carries it in `header.token`.
  var token = payload.getOrDefault("token").getStr("")
  if token.len == 0:
    let h = payload.getOrDefault("header")
    if h != nil and h.kind == JObject:
      token = h.getOrDefault("token").getStr("")
  token

proc parseForm(body: string): Table[string, string] =
  ## application/x-www-form-urlencoded decoder (Slack slash commands).
  result = initTable[string, string]()
  for pair in body.split('&'):
    if pair.len == 0:
      continue
    let kv = pair.split('=', 1)
    let key = percentDecode(kv[0].replace("+", " "))
    let value =
      if kv.len == 2: percentDecode(kv[1].replace("+", " "))
      else: ""
    result[key] = value

# ── Slack ─────────────────────────────────────────────────────────────────────

proc handleSlack(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  if cfg.slackSigningSecret.len == 0:
    return notFound()
  if req.httpMethod != "POST":
    return methodNotAllowed()

  let timestamp = req.header("x-slack-request-timestamp")
  let signature = req.header("x-slack-signature")
  if timestamp.len == 0 or signature.len == 0:
    return forbidden()
  var ts: int64
  try:
    ts = parseInt(timestamp)
  except ValueError:
    return forbidden()
  ## Lower/upper bounds instead of `abs()`: a hostile timestamp near int64.low
  ## would overflow the subtraction before the HMAC is ever checked.
  let now = epochTime().int64
  if ts < now - SlackReplayWindowSec.int64 or
     ts > now + SlackReplayWindowSec.int64:
    return forbidden()

  let expected = "v0=" & hmacSha256Hex(cfg.slackSigningSecret,
                                       "v0:" & timestamp & ":" & req.body)
  if not safeEquals(signature, expected):
    return forbidden()

  let contentType = req.header("content-type").toLowerAscii()
  if contentType.startsWith("application/x-www-form-urlencoded"):
    let form = parseForm(req.body)
    ## Interactive components (block actions) arrive as payload=<JSON>.
    if form.hasKey("payload"):
      let interactive = parsePayload(form["payload"]).valueOr:
        return badRequest()
      slack.pushEvent(interactive)
      return plainResp(200)
    ## Slack slash commands arrive form-encoded; normalize to the JSON shape
    ## slack_pure expects and mark the event type explicitly.
    var payload = newJObject()
    payload["type"] = %"slash_command"
    for key, value in form:
      payload[key] = %value
    slack.pushEvent(payload)
    return plainResp(200)

  let payload = parsePayload(req.body).valueOr:
    return badRequest()

  let challenge = slack.parseChallenge(payload)
  if challenge.len > 0:
    return plainResp(200, challenge)
  slack.pushEvent(payload)
  plainResp(200)

# ── Feishu ────────────────────────────────────────────────────────────────────

func feishuSignature*(timestamp, nonce, encryptKey, body: string): string =
  ## Feishu event signature: hex(SHA256(timestamp & nonce & encrypt_key & body)).
  var ctx: sha256
  ctx.init()
  ctx.update(timestamp & nonce & encryptKey & body)
  let digest = ctx.finish()
  for b in digest.data:
    result.add(b.toHex(2).toLowerAscii())

proc decryptFeishuBody(encryptKey, body: string): Result[JsonNode, string] {.raises: [].} =
  ## Decrypts Feishu's Encrypt Key envelope: base64(iv[16] || AES-256-CBC).
  ## The key is SHA256(encrypt_key); padding is PKCS#7.
  try:
    let outer = parseJson(body)
    let encrypted = outer.getOrDefault("encrypt").getStr("")
    if encrypted.len == 0:
      return err("missing encrypt field")
    let decoded = base64.decode(encrypted)
    if decoded.len <= 16 or (decoded.len - 16) mod 16 != 0:
      return err("invalid encrypted payload length")

    var key: array[32, byte]
    var sha: sha256
    sha.init()
    sha.update(encryptKey)
    let digest = sha.finish()
    for i in 0 ..< key.len:
      key[i] = digest.data[i]

    var iv: array[16, byte]
    for i in 0 ..< iv.len:
      iv[i] = byte(decoded[i])

    let cipherText = decoded[16 .. ^1]
    var plainText = newString(cipherText.len)
    var ctx: CBC[aes256]
    ctx.init(key, iv)
    ctx.decrypt(cipherText, plainText)
    ctx.clear()

    if plainText.len == 0:
      return err("empty decrypted payload")
    let pad = int(plainText[^1])
    if pad <= 0 or pad > 16 or pad > plainText.len:
      return err("invalid PKCS7 padding")
    for i in 0 ..< pad:
      if int(plainText[plainText.len - 1 - i]) != pad:
        return err("invalid PKCS7 padding")
    let jsonText = plainText[0 ..< plainText.len - pad]
    let inner = parseJson(jsonText)
    if inner.kind != JObject:
      return err("decrypted payload is not an object")
    ok(inner)
  except CatchableError as e:
    err("Feishu decrypt failed: " & e.msg)

proc handleFeishu(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  if cfg.feishuVerificationToken.len == 0 and cfg.feishuEncryptKey.len == 0:
    return notFound()
  if req.httpMethod != "POST":
    return methodNotAllowed()

  ## With an Encrypt Key, Feishu signs the raw body before encryption. Validate
  ## the signature and replay window before touching the ciphertext.
  if cfg.feishuEncryptKey.len > 0:
    let timestamp = req.header("x-lark-request-timestamp")
    let nonce = req.header("x-lark-request-nonce")
    let signature = req.header("x-lark-signature")
    if timestamp.len == 0 or nonce.len == 0 or signature.len == 0:
      return forbidden()
    var ts: int64
    try:
      ts = parseBiggestInt(timestamp)
    except ValueError:
      return forbidden()
    let now = epochTime().int64
    if ts < now - FeishuReplayWindowSec.int64 or
       ts > now + FeishuReplayWindowSec.int64:
      return forbidden()
    let expected = feishuSignature(timestamp, nonce, cfg.feishuEncryptKey,
                                   req.body)
    if not safeEquals(signature, expected):
      return forbidden()

  var payload = parsePayload(req.body).valueOr:
    return badRequest()

  if cfg.feishuEncryptKey.len > 0:
    payload = decryptFeishuBody(cfg.feishuEncryptKey, req.body).valueOr:
      return badRequest()

  if cfg.feishuVerificationToken.len > 0 and
     not safeEquals(feishuToken(payload), cfg.feishuVerificationToken):
    return forbidden()

  let challenge = feishu.parseChallenge(payload)
  if challenge.len > 0:
    return jsonResp(200, $ %* {"challenge": challenge})

  feishu.pushEvent(payload)
  plainResp(200)

# ── DingTalk ──────────────────────────────────────────────────────────────────

func dingTalkAuthSpec(cfg: WebhookConfig): WebhookAuthSpec =
  ## DingTalk signs `timestamp & "\n" & secret` (the body is not covered) and
  ## carries Unix milliseconds in `timestamp`/`sign`. The body limit matches
  ## the one already enforced while reading the request.
  WebhookAuthSpec(
    scheme:          wasHmacSha256Base64,
    signedPayload:   wspTimestampNewlineSecret,
    secret:          cfg.dingtalkAppSecret,
    signatureHeader: "sign",
    timestampHeader: "timestamp",
    replayWindowSec: DingTalkTimestampWindowMs div 1000,
    timestampScale:  wtsMilliseconds,
    maxBodyBytes:    MaxWebhookBodyBytes,
  )

proc handleDingTalk(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  let verdict = decideIngress(dingTalkAuthSpec(cfg), req,
                              nowUnixMs = (epochTime() * 1000).int64)
  case verdict
  of wioAccepted:
    discard
  of wioNotConfigured:
    return notFound()
  of wioMethodNotAllowed:
    return methodNotAllowed()
  of wioStale, wioForbidden:
    return forbidden()
  of wioTooLarge:
    return badRequest()

  let payload = parsePayload(req.body).valueOr:
    return badRequest()

  dingtalk.pushEvent(payload)
  plainResp(200)

# ── LINE ──────────────────────────────────────────────────────────────────────

func lineAuthSpec(cfg: WebhookConfig): WebhookAuthSpec =
  ## LINE signs the raw body: base64(HMAC-SHA256(channel secret, body)). There
  ## is no signed timestamp, so replay defence is the runtime's dedupe of
  ## `webhookEventId` (US-002/US-006), not an ingress window.
  WebhookAuthSpec(
    scheme:          wasHmacSha256Base64,
    signedPayload:   wspBody,
    secret:          cfg.lineChannelSecret,
    signatureHeader: LineSignatureHeader,
    timestampHeader: "",
    replayWindowSec: 0,
    timestampScale:  wtsNone,
    maxBodyBytes:    LineMaxBodyBytes,
  )

proc handleLine(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  let verdict = decideIngress(lineAuthSpec(cfg), req,
                              nowUnixMs = (epochTime() * 1000).int64)
  case verdict
  of wioAccepted:
    discard
  of wioNotConfigured:
    return notFound()
  of wioMethodNotAllowed:
    return methodNotAllowed()
  of wioStale, wioForbidden:
    return forbidden()
  of wioTooLarge:
    return payloadTooLarge()

  let payload = parsePayload(req.body).valueOr:
    return badRequest()

  ## The console "Verify" button posts `{"events":[]}`; answer 200 without
  ## touching the queue. Any real event is parsed here so an unusable shape
  ## never opens the adapter queue.
  if parseWebhook(payload).len > 0:
    if not line.pushEvent(payload):
      ## The bounded queue is full. Refusing is better than blocking this
      ## worker (which serves every channel) or acking an event the daemon will
      ## never see; LINE redelivers, and the replay cache drops duplicates it
      ## already accepted.
      return plainResp(503, "line queue is full")
  plainResp(200, "ok")

# ── Matrix ────────────────────────────────────────────────────────────────────

func matrixSuppliedToken(req: WebhookRequest): string =
  let auth = req.header("authorization")
  const bearer = "bearer "
  if auth.len > bearer.len and auth[0 ..< bearer.len].toLowerAscii() == bearer:
    return auth[bearer.len .. ^1].strip()
  req.query.getOrDefault("access_token")

proc handleMatrix(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  if cfg.matrixToken.len == 0:
    return notFound()
  if req.httpMethod != "POST":
    return methodNotAllowed()

  if not safeEquals(matrixSuppliedToken(req), cfg.matrixToken):
    return forbidden()

  let payload = parsePayload(req.body).valueOr:
    return badRequest()

  matrix.pushEvent(payload)
  jsonResp(200, "{}")

# ── WhatsApp ──────────────────────────────────────────────────────────────────

proc handleWhatsAppGet(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  let mode      = req.query.getOrDefault("hub.mode")
  let challenge = req.query.getOrDefault("hub.challenge")
  let token     = req.query.getOrDefault("hub.verify_token")
  let echoed = whatsapp.verifyChallenge(mode, challenge, token,
                                        cfg.whatsappVerifyToken)
  if echoed.len == 0:
    return forbidden()
  plainResp(200, echoed)

proc handleWhatsAppPost(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  ## POSTs cannot be trusted without an app secret for the payload MAC.
  if cfg.whatsappAppSecret.len == 0:
    return forbidden()

  let signature = req.header("x-hub-signature-256")
  let expected = "sha256=" & hmacSha256Hex(cfg.whatsappAppSecret, req.body)
  if not safeEquals(signature, expected):
    return forbidden()

  let payload = parsePayload(req.body).valueOr:
    return badRequest()

  whatsapp.pushEvent(payload)
  plainResp(200)

proc handleWhatsApp(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  if cfg.whatsappVerifyToken.len == 0:
    return notFound()
  case req.httpMethod
  of "GET":  handleWhatsAppGet(cfg, req)
  of "POST": handleWhatsAppPost(cfg, req)
  else:      methodNotAllowed()

# ── Dispatch ──────────────────────────────────────────────────────────────────

proc handleWebhookRequest*(cfg: WebhookConfig; req: WebhookRequest): WebhookResponse =
  ## Pure-ish request → response mapping (payload dispatch is the only effect).
  ## Never raises: malformed input maps to a 4xx response.
  case req.path
  of SlackPath:    handleSlack(cfg, req)
  of FeishuPath:   handleFeishu(cfg, req)
  of DingTalkPath: handleDingTalk(cfg, req)
  of LinePath:     handleLine(cfg, req)
  of MatrixPath:   handleMatrix(cfg, req)
  of WhatsAppPath: handleWhatsApp(cfg, req)
  else:            notFound()

func anyRouteConfigured*(cfg: WebhookConfig): bool =
  cfg.slackSigningSecret.len > 0 or
    cfg.feishuVerificationToken.len > 0 or
    cfg.feishuEncryptKey.len > 0 or
    cfg.dingtalkAppSecret.len > 0 or
    cfg.lineChannelSecret.len > 0 or
    cfg.matrixToken.len > 0 or
    cfg.whatsappVerifyToken.len > 0

# ── HTTP server ───────────────────────────────────────────────────────────────

func statusReason(status: int): string =
  case status
  of 200: "OK"
  of 400: "Bad Request"
  of 403: "Forbidden"
  of 404: "Not Found"
  of 405: "Method Not Allowed"
  of 413: "Payload Too Large"
  of 503: "Service Unavailable"
  else:  "Error"

proc sendResponse(client: Socket; resp: WebhookResponse) =
  let head = "HTTP/1.1 " & $resp.status & " " & statusReason(resp.status) & "\r\n" &
             "Content-Type: " & resp.contentType & "\r\n" &
             "Content-Length: " & $resp.body.len & "\r\n" &
             "Connection: close\r\n\r\n"
  try:
    client.send(head & resp.body)
  except CatchableError:
    discard

func readErrorResponse*(error: string): WebhookResponse =
  ## The socket reader rejects before routing, so the status must describe the
  ## read failure: an oversized declared body is 413, everything else 400.
  if readErrorStatus(error) == 413: payloadTooLarge() else: badRequest()

proc handleConnection(client: Socket; cfg: WebhookConfig; logger: Logger) =
  defer: closeWebhookClient(client)
  let req = readWebhookRequest(client).valueOr:
    logger.warn("webhook: " & error)
    sendResponse(client, readErrorResponse(error))
    return
  let resp = handleWebhookRequest(cfg, req)
  if resp.status != 200:
    logger.warn("webhook: " & req.httpMethod & " " & req.path &
                " rejected with " & $resp.status)
  sendResponse(client, resp)

type
  WebhookServerArgs = object
    port:      int
    host:      string
    cfg:       WebhookConfig
    logger:    Logger
    handshake: ptr Channel[string]

  WebhookWorkerArg = object
    cfg:    WebhookConfig
    logger: Logger
    ready:  ptr Channel[string]

var
  gWebhookThread: Thread[WebhookServerArgs]
  gWebhookWorkers {.global.}: array[WebhookWorkerCount, Thread[WebhookWorkerArg]]
  gWebhookQueue {.global.}: Channel[SocketHandle]
  gWebhookQueueOpened {.global.} = false
  gWebhookPoolStarted {.global.} = false
  gWebhookPoolAttempted {.global.} = false
  gWebhookWorkersStarted {.global.} = 0
  gWebhookStarted = false
  gWebhookStop: Atomic[bool]

proc newWebhookTlsContext(cfg: WebhookConfig; logger: Logger): SslContext =
  if cfg.tlsCertFile.len == 0:
    return nil
  try:
    newContext(verifyMode = CVerifyNone,
               certFile = cfg.tlsCertFile,
               keyFile = cfg.tlsKeyFile)
  except CatchableError as e:
    logger.error("webhook: cannot load TLS certificate: " & e.msg)
    nil

proc webhookWorker(arg: WebhookWorkerArg) {.thread.} =
  {.cast(gcsafe).}:
    var tlsContext: SslContext
    var lastTlsCheck: MonoTime
    var certMtime, keyMtime: times.Time
    var initError = ""
    if arg.cfg.tlsCertFile.len > 0:
      try:
        tlsContext = newWebhookTlsContext(arg.cfg, arg.logger)
        if tlsContext == nil:
          initError = "TLS certificate unavailable"
        else:
          certMtime = getLastModificationTime(arg.cfg.tlsCertFile)
          keyMtime = getLastModificationTime(arg.cfg.tlsKeyFile)
          lastTlsCheck = getMonoTime()
      except CatchableError as e:
        initError = "cannot stat TLS certificate: " & e.msg
    if arg.ready != nil:
      try:
        arg.ready[].send(initError)
      except CatchableError:
        discard
    if initError.len > 0:
      arg.logger.error("webhook: TLS worker stopped: " & initError)
      return

    while true:
      let fd = gWebhookQueue.recv()
      if fd == SocketHandle(-1):
        break
      var client: Socket
      try:
        ## Unbuffered: every recv returns after the kernel read, so the body
        ## loop observes the total request deadline even for trickle clients.
        client = newSocket(fd, buffered = false)
      except CatchableError:
        discard posix.close(cint(fd))
        continue
      try:
        ## Without SO_RCVTIMEO a silent client would hold this worker until
        ## the request deadline; refuse rather than serve it unbounded.
        applyWebhookClientTimeouts(client).isOkOr:
          arg.logger.warn("webhook: " & error)
          try: client.close() except CatchableError: discard
          continue
        if arg.cfg.tlsCertFile.len > 0:
          ## Reload the certificate when the files change, so rotation does
          ## not require a daemon restart. A failed reload keeps the old
          ## context and is retried on the next connection.
          let now = getMonoTime()
          if inMilliseconds(now - lastTlsCheck) >= WebhookTlsReloadIntervalMs:
            lastTlsCheck = now
            try:
              let newCertMtime = getLastModificationTime(arg.cfg.tlsCertFile)
              let newKeyMtime = getLastModificationTime(arg.cfg.tlsKeyFile)
              if newCertMtime != certMtime or newKeyMtime != keyMtime:
                let reloaded = newWebhookTlsContext(arg.cfg, arg.logger)
                if reloaded != nil:
                  tlsContext = reloaded
                  certMtime = newCertMtime
                  keyMtime = newKeyMtime
                  arg.logger.info("webhook: TLS certificate reloaded")
            except CatchableError as e:
              arg.logger.warn("webhook: TLS reload failed: " & e.msg)
          try:
            tlsContext.wrapConnectedSocket(client, handshakeAsServer)
          except CatchableError as e:
            arg.logger.warn("webhook: TLS handshake failed: " & e.msg)
            try: client.close() except CatchableError: discard
            continue
        handleConnection(client, arg.cfg, arg.logger)
      except CatchableError as e:
        arg.logger.warn("webhook: connection error: " & e.msg)
        try: client.close() except CatchableError: discard

proc startWebhookPool(cfg: WebhookConfig; logger: Logger): Result[void, string] =
  ## Opens the queue and starts every worker. After a failed worker
  ## initialization the sentinels are drained and a later attempt can retry
  ## without reopening the channel.
  if gWebhookPoolStarted:
    return ok()
  if gWebhookPoolAttempted:
    return err("webhook: worker pool initialization already failed; not retrying")
  gWebhookPoolAttempted = true
  if not gWebhookQueueOpened:
    gWebhookQueue.open(WebhookQueueDepth)
    gWebhookQueueOpened = true
  var ready: Channel[string]
  ready.open(WebhookWorkerCount)
  try:
    for i in 0 ..< WebhookWorkerCount:
      createThread(gWebhookWorkers[i], webhookWorker,
                   WebhookWorkerArg(cfg: cfg, logger: logger,
                                    ready: addr ready))
      inc gWebhookWorkersStarted
  except CatchableError as e:
    ## Stop the workers that were already created before reporting failure.
    for _ in 0 ..< gWebhookWorkersStarted:
      gWebhookQueue.send(SocketHandle(-1))
    for i in 0 ..< gWebhookWorkersStarted:
      joinThread(gWebhookWorkers[i])
    gWebhookWorkersStarted = 0
    while true:
      let (hasQueued, fd) = gWebhookQueue.tryRecv()
      if not hasQueued:
        break
      if fd != SocketHandle(-1):
        discard posix.close(cint(fd))
    ready.close()
    gWebhookPoolAttempted = false
    return err("cannot start webhook workers: " & e.msg)

  var initError = ""
  for _ in 0 ..< gWebhookWorkersStarted:
    let status = ready.recv()
    if status.len > 0 and initError.len == 0:
      initError = status
  ready.close()
  if initError.len > 0:
    for _ in 0 ..< gWebhookWorkersStarted:
      gWebhookQueue.send(SocketHandle(-1))
    for i in 0 ..< gWebhookWorkersStarted:
      joinThread(gWebhookWorkers[i])
    gWebhookWorkersStarted = 0
    while true:
      let (hasQueued, fd) = gWebhookQueue.tryRecv()
      if not hasQueued:
        break
      if fd != SocketHandle(-1):
        discard posix.close(cint(fd))
    gWebhookPoolAttempted = false
    return err("webhook worker initialization failed: " & initError)
  gWebhookPoolStarted = true
  ok()

proc sendHandshake(args: WebhookServerArgs; message: string) =
  ## Reports startup progress to `startWebhookReceiver`; never raises, so the
  ## server thread can always finish.
  try:
    args.handshake[].send(message)
  except CatchableError:
    discard

proc webhookServerThread(args: WebhookServerArgs) {.thread.} =
  {.cast(gcsafe).}:
    var server: Socket
    var handshakeSent = false
    try:
      server = newSocket()
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(Port(args.port), args.host)
      server.listen()

      ## Bound accept() so shutdown can be observed without closing the
      ## listening socket from another thread.
      var tv: posix.Timeval
      tv.tv_sec = posix.Time(1)
      tv.tv_usec = posix.Suseconds(0)
      discard posix.setsockopt(server.getFd, posix.SOL_SOCKET,
                               posix.SO_RCVTIMEO, addr tv,
                               posix.SockLen(sizeof(tv)))

      let pool = startWebhookPool(args.cfg, args.logger)
      if pool.isErr:
        args.logger.error("webhook: " & pool.error)
        args.sendHandshake(pool.error)
        return

      let scheme = if args.cfg.tlsCertFile.len > 0: "https" else: "http"
      args.logger.info("webhook receiver listening on " & scheme & "://" &
                       args.host & ":" & $args.port)
      args.sendHandshake("")
      handshakeSent = true

      while not gWebhookStop.load():
        var client: Socket
        try:
          server.accept(client)
        except TimeoutError:
          continue
        except OSError as e:
          if gWebhookStop.load():
            break
          if e.errorCode == EAGAIN or e.errorCode == EWOULDBLOCK:
            continue
          args.logger.warn("webhook: accept error: " & e.msg)
          ## Avoid a hot loop when accept fails persistently (e.g. EMFILE).
          sleep(50)
          continue
        except CatchableError as e:
          if gWebhookStop.load():
            break
          args.logger.warn("webhook: accept error: " & e.msg)
          sleep(50)
          continue
        applyWebhookClientTimeouts(client).isOkOr:
          args.logger.warn("webhook: " & error)
          try: client.close() except CatchableError: discard
          continue
        if not gWebhookQueue.trySend(client.getFd):
          sendResponse(client, serviceUnavailable())
          try: client.close() except CatchableError: discard
          # Ownership of the fd transfers to a worker only on a successful send.
    except CatchableError as e:
      if handshakeSent:
        args.logger.error("webhook: server error: " & e.msg)
      else:
        args.logger.error("webhook: cannot bind " & args.host & ":" & $args.port &
                          ": " & e.msg)
        args.sendHandshake("cannot bind " & args.host & ":" & $args.port &
                           ": " & e.msg)
    finally:
      if server != nil:
        try: server.close() except CatchableError: discard

proc startWebhookReceiver*(cfg: WebhookConfig;
                           port: int;
                           host = "0.0.0.0";
                           logger: Logger): Result[void, string] {.gcsafe.} =
  ## Starts the receiver on a dedicated OS thread. Refuses to start when no
  ## channel has authentication material — an open webhook is never exposed.
  ## Blocks until the server thread reports a successful bind/listen.
  if not anyRouteConfigured(cfg):
    return err("no webhook channel has authentication configured")
  if port <= 0 or port > 65535:
    return err("invalid webhook port " & $port)
  if host.len == 0:
    return err("empty webhook bind host")
  if (cfg.tlsCertFile.len > 0) != (cfg.tlsKeyFile.len > 0):
    return err("webhook TLS requires both a certificate and a key file")
  if cfg.tlsCertFile.len > 0:
    try:
      discard newContext(verifyMode = CVerifyNone,
                         certFile = cfg.tlsCertFile,
                         keyFile = cfg.tlsKeyFile)
    except CatchableError as e:
      return err("cannot load webhook TLS certificate: " & e.msg)
  if gWebhookStarted:
    return err("webhook receiver already started")

  gWebhookStop.store(false)
  var handshake: Channel[string]
  handshake.open(1)
  try:
    try:
      {.cast(gcsafe).}:
        createThread(gWebhookThread, webhookServerThread,
                     WebhookServerArgs(port: port, host: host, cfg: cfg,
                                       logger: logger, handshake: addr handshake))
    except CatchableError as e:
      return err("cannot start webhook thread: " & e.msg)

    let report = handshake.recv()
    if report.len > 0:
      ## The server thread has already left its accept loop; join it before the
      ## caller can retry and reuse the same global Thread object.
      {.cast(gcsafe).}:
        joinThread(gWebhookThread)
      return err(report)
  finally:
    handshake.close()

  gWebhookStarted = true
  ok()

proc stopWebhookReceiver*() {.gcsafe.} =
  ## Stops the listener and joins its workers. Safe to call when nothing is
  ## running. After this returns the receiver can be started again.
  if not gWebhookStarted:
    return
  gWebhookStop.store(true)
  {.cast(gcsafe).}:
    joinThread(gWebhookThread)
  ## The accept loop is the only producer and it has stopped. Close descriptors
  ## still waiting in the queue so a slow client cannot delay shutdown; only
  ## in-flight requests (at most one per worker) remain to be joined.
  while true:
    let (hasQueued, fd) = gWebhookQueue.tryRecv()
    if not hasQueued:
      break
    if fd != SocketHandle(-1):
      discard posix.close(cint(fd))
  if gWebhookWorkersStarted > 0:
    for _ in 0 ..< gWebhookWorkersStarted:
      gWebhookQueue.send(SocketHandle(-1))
    for i in 0 ..< gWebhookWorkersStarted:
      {.cast(gcsafe).}:
        joinThread(gWebhookWorkers[i])
    gWebhookWorkersStarted = 0
    ## A worker may have exited before consuming its sentinel; drain any
    ## leftovers so a later restart does not inherit a poison pill.
    while true:
      let (hasQueued, fd) = gWebhookQueue.tryRecv()
      if not hasQueued:
        break
      if fd != SocketHandle(-1):
        discard posix.close(cint(fd))
  gWebhookStarted = false
  gWebhookPoolStarted = false
  gWebhookPoolAttempted = false
  gWebhookStop.store(false)
