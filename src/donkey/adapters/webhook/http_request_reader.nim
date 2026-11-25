## http_request_reader — bounded HTTP/1.1 request reader for embedded webhooks.
##
## Every embedded webhook server (the shared webhook_receiver plus the QQ
## OneBot, WeChat and WeCom listeners) reads requests through this module, so
## the same limits apply everywhere:
##   - per-line, total-header and header-count caps (no unbounded readLine)
##   - Content-Length validated and capped *before* allocating the body
##   - SO_RCVTIMEO/SO_SNDTIMEO on the client socket plus a monotonic deadline
##     for the whole request (slowloris cannot pin the listener thread)
##   - listeners must accept **unbuffered** sockets (`newSocket(buffered =
##     false)`), so each recv returns per packet and both limits apply
##
## Errors are plain strings; readErrorStatus maps them to an HTTP status.

import std/[monotimes, nativesockets, net, posix, strutils, tables, times]
import ../../core/pipeops
import ./webhook_ingress

export webhook_ingress.WebhookRequest

const
  MaxWebhookBodyBytes*       = 3 * 1024 * 1024
    ## Meta documents WhatsApp Cloud webhooks of up to 3 MB (hermes WA-002);
    ## LINE keeps its own 1 MiB per-route limit.
  MaxWebhookHeaderLines*     = 64
  MaxWebhookHeaderBytes*     = 64 * 1024
  MaxWebhookLineBytes*       = 8192
  WebhookClientTimeoutSec*   = 5
  WebhookRequestDeadlineSec* = 15

func percentDecode*(s: string): string =
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '%' and i + 2 < s.len:
      try:
        result.add(char(parseHexInt(s[i + 1 .. i + 2])))
        i += 3
        continue
      except ValueError:
        discard
    result.add(s[i])
    inc i

func parseQuery*(query: string): Table[string, string] =
  result = initTable[string, string]()
  if query.len == 0:
    return
  for pair in query.split('&'):
    if pair.len == 0:
      continue
    let kv = pair.split('=', 1)
    let key = percentDecode(kv[0])
    let value = if kv.len == 2: percentDecode(kv[1]) else: ""
    result[key] = value

func parseContentLength*(value: string): Result[int, string] =
  ## RFC 9110 Content-Length: 1*DIGIT. Signs, exponents and overflow are
  ## rejected rather than silently read as 0.
  let v = value.strip()
  if v.len == 0:
    return err("bad content-length")
  for c in v:
    if c notin Digits:
      return err("bad content-length")
  try:
    ok(parseInt(v))
  except ValueError:
    err("bad content-length")

func readErrorStatus*(error: string): int =
  ## The reader rejects before routing, so the status must describe the read
  ## failure: an oversized declared body is 413, everything else 400.
  if error == "body too large": 413 else: 400

proc applyWebhookClientTimeouts*(client: Socket;
                                 seconds = WebhookClientTimeoutSec): Result[void, string] =
  ## Bounds every blocking recv/send on a connected client.
  var tv: posix.Timeval
  tv.tv_sec = posix.Time(seconds)
  tv.tv_usec = posix.Suseconds(0)
  let r = posix.setsockopt(client.getFd, posix.SOL_SOCKET, posix.SO_RCVTIMEO,
                           addr tv, posix.SockLen(sizeof(tv)))
  let s = posix.setsockopt(client.getFd, posix.SOL_SOCKET, posix.SO_SNDTIMEO,
                           addr tv, posix.SockLen(sizeof(tv)))
  if r != 0 or s != 0: err("failed to set client socket timeouts")
  else: ok()

proc requestDeadline(seconds: int): MonoTime =
  ## Total time budget for one request, on the monotonic clock so a
  ## wall-clock jump cannot extend or shorten it.
  getMonoTime() + initDuration(seconds = seconds)

proc readHttpLine(s: Socket; deadline: MonoTime): Result[string, string] =
  ## Reads one CRLF/LF terminated line; bounded in length and in time.
  var line = ""
  while line.len < MaxWebhookLineBytes:
    if getMonoTime() > deadline:
      return err("request deadline exceeded")
    var c: char
    let n = try: s.recv(c.addr, 1) except CatchableError: -1
    if n <= 0:
      return err("connection closed or read timed out")
    if c == '\r':
      continue
    if c == '\n':
      return ok(line)
    line.add(c)
  err("header line too long")

proc readWebhookRequest*(client: Socket;
                         maxBodyBytes = MaxWebhookBodyBytes;
                         deadlineSec = WebhookRequestDeadlineSec): Result[WebhookRequest, string] =
  ## Reads one request. `client` must be an **unbuffered** socket with
  ## applyWebhookClientTimeouts applied: a buffered recv only returns once
  ## the full size arrived, which defeats both the idle timeout and the
  ## deadline check.
  let deadline = requestDeadline(deadlineSec)

  let requestLine = ? readHttpLine(client, deadline)
  if requestLine.len == 0:
    return err("empty request line")

  let parts = requestLine.split(' ')
  if parts.len < 2:
    return err("malformed request line")

  var path = parts[1]
  var query = initTable[string, string]()
  let qpos = path.find('?')
  if qpos >= 0:
    query = parseQuery(path[qpos + 1 .. ^1])
    path = path[0 ..< qpos]

  var headers = initTable[string, string]()
  var contentLength = 0
  var sawContentLength = false
  var headerLines = 0
  var headerBytes = 0
  while true:
    if headerLines >= MaxWebhookHeaderLines:
      return err("too many headers")
    let line = ? readHttpLine(client, deadline)
    inc headerLines
    headerBytes += line.len
    if headerBytes > MaxWebhookHeaderBytes:
      return err("headers too large")
    if line.len == 0:
      break
    let colon = line.find(':')
    if colon <= 0:
      continue
    let name = line[0 ..< colon].strip().toLowerAscii()
    let value = line[colon + 1 .. ^1].strip()
    headers[name] = value
    if name == "content-length":
      ## RFC 9112 §6.3: differing repeated lengths make framing ambiguous.
      let n = ? parseContentLength(value)
      if sawContentLength and n != contentLength:
        return err("conflicting content-length")
      contentLength = n
      sawContentLength = true

  var body = ""
  if contentLength > 0:
    if contentLength > maxBodyBytes:
      return err("body too large")
    body = newString(contentLength)
    var received = 0
    while received < contentLength:
      if getMonoTime() > deadline:
        return err("request deadline exceeded")
      ## Unbuffered socket: recv returns after one kernel read, so SO_RCVTIMEO
      ## is an idle timeout renewed by every packet, and this loop re-checks
      ## the total deadline between packets (slow-drip senders are cut).
      let n = try: client.recv(body[received].addr, contentLength - received)
              except CatchableError: -1
      if n <= 0:
        break
      received += n
    if received != contentLength:
      return err("truncated body")

  ok(WebhookRequest(
    httpMethod: parts[0],
    path:       path,
    query:      query,
    headers:    headers,
    body:       body,
  ))

const MaxDrainBytes = 64 * 1024

proc closeWebhookClient*(client: Socket) =
  ## Closes a client after the response was sent. The reader may stop
  ## mid-request (rejected header, oversized body), and closing a socket with
  ## unread input makes the kernel send RST, which can discard the response
  ## before the peer reads it. Drain what already arrived (non-blocking,
  ## bounded) first.
  var buf: array[4096, char]
  var drained = 0
  try: client.getFd.setBlocking(false) except CatchableError: discard
  while drained < MaxDrainBytes:
    let n = posix.recv(client.getFd, addr buf[0], buf.len, 0'i32)
    if n <= 0:
      break
    drained += n
  try: client.close() except CatchableError: discard

func statusLine*(code: int): string =
  ## "<code> <reason>" for the handful of statuses embedded listeners emit.
  case code
  of 200: "200 OK"
  of 400: "400 Bad Request"
  of 403: "403 Forbidden"
  of 404: "404 Not Found"
  of 405: "405 Method Not Allowed"
  of 413: "413 Payload Too Large"
  else:   $code & " Error"
