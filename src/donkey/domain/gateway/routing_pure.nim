## Request line to route, the status lines and the small parsers the HTTP
## gateway needs (port, agent deadline, query values, the web UI chat body).
## Pure: the socket handler reads the bytes, these decide what they mean.

import std/[json, strutils]
import results
import ../../core/types
import ../message

const
  GatewayDefaultPort* = 8080
  GatewayMaxRequestLine* = 8192
  CorsHeaders* = "Access-Control-Allow-Origin: *\r\n" &
                 "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" &
                 "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"

func httpResponseText*(status, contentType, body: string): string =
  ## A complete `Connection: close` response with the CORS headers.
  "HTTP/1.1 " & status & "\r\n" &
    CorsHeaders &
    "Content-Type: " & contentType & "; charset=utf-8\r\n" &
    "Content-Length: " & $body.len & "\r\n" &
    "Connection: close\r\n\r\n" & body

func sseResponseHeaders*(): string =
  ## The head of an event stream; the connection stays open after it.
  "HTTP/1.1 200 OK\r\n" &
    CorsHeaders &
    "Content-Type: text/event-stream\r\n" &
    "Cache-Control: no-cache\r\n" &
    "Connection: keep-alive\r\n\r\n"

func resolveGatewayPort*(raw: string): int =
  ## Parses DONKEY_HTTP_PORT semantics.
  ## Empty or invalid values fall back to GatewayDefaultPort.
  ## Zero or negative values disable the HTTP gateway entirely.
  if raw.len == 0:
    return GatewayDefaultPort
  try:
    let parsed = parseInt(raw)
    if parsed <= 0: 0 else: parsed
  except ValueError:
    GatewayDefaultPort

type
  GatewayRequest* = object
    meth*: string
    path*: string

func parseGatewayRequest*(requestLine: string): GatewayRequest =
  ## Parses the first line of an HTTP request into method + path.
  ## Strips query strings. Returns empty strings for malformed input.
  let parts = requestLine.splitWhitespace()
  if parts.len < 2:
    return GatewayRequest()
  let meth = parts[0]
  var path = parts[1]
  let qmark = path.find('?')
  if qmark >= 0:
    path = path[0 ..< qmark]
  GatewayRequest(meth: meth, path: path)

func buildSseEvent*(event, data: string): string =
  ## Formats an SSE event string (double newline terminated).
  if event.len > 0:
    result = "event: " & event & "\n"
  result.add("data: " & data & "\n\n")

func routeGatewayRequest*(req: GatewayRequest): string =
  case req.path
  of "/":              "index"
  of "/health":        "health"
  of "/api/status":    "status"
  of "/api/logs":      "logs"
  of "/api/events":    "events"
  of "/api/chat":      "chat"
  of "/api/sessions":  "sessions"
  of "/api/providers": "providers"
  of "/v1/chat/completions": "openai_chat"
  of "/v1/models":     "openai_models"
  of "/dashboard":     "dashboard"
  else:                "notfound"

func routeChatMethod*(meth: string): string =
  case meth
  of "POST":  "chat"
  of "GET":   "chat_get"
  else:       "method_not_allowed"

func httpStatusLine*(code: int): string =
  ## Status text for the codes the agent endpoint can produce.
  case code
  of 200: "200 OK"
  of 202: "202 Accepted"
  of 400: "400 Bad Request"
  of 401: "401 Unauthorized"
  of 403: "403 Forbidden"
  of 404: "404 Not Found"
  of 405: "405 Method Not Allowed"
  of 413: "413 Payload Too Large"
  of 429: "429 Too Many Requests"
  of 502: "502 Bad Gateway"
  of 503: "503 Service Unavailable"
  of 504: "504 Gateway Timeout"
  else:   $code

func resolveAgentTimeoutMs*(raw: string): int =
  ## `DONKEY_HTTP_AGENT_TIMEOUT_SEC`: default 120 s, capped at 600 s.
  ## Empty, invalid or non-positive values fall back to the default, so a bad
  ## env can never disable the turn deadline.
  const DefaultSec = 120
  const MaxSec = 600
  if raw.len == 0:
    return DefaultSec * 1000
  try:
    let parsed = parseInt(raw)
    if parsed <= 0: DefaultSec * 1000
    elif parsed > MaxSec: MaxSec * 1000
    else: parsed * 1000
  except ValueError:
    DefaultSec * 1000

func parseQueryInt*(requestLine: string; key: string; default: int): int =
  ## `key=<int>` from the query string of a request line, or `default`.
  let qmark = requestLine.find('?')
  if qmark < 0: return default
  let query = requestLine[qmark + 1 .. ^1]
  for pair in query.split('&'):
    let kv = pair.split('=', 1)
    if kv.len == 2 and kv[0] == key:
      try: return parseInt(kv[1])
      except ValueError: return default
  default

const
  CliDefaultUserId* = UserId("local:webui")
    ## Default user id for web UI messages.

proc parseChatPost*(body: string): Result[InboundMessage, string] =
  ## Parses a JSON body from POST /api/chat into an InboundMessage.
  ## Expected format: {"text": "message text", "userId": "optional-user-id"}
  if body.len == 0:
    return err("empty body")
  var jsonBody: JsonNode
  try:
    jsonBody = parseJson(body)
  except JsonParsingError as e:
    return err("invalid JSON: " & e.msg)
  if jsonBody.kind != JObject:
    return err("expected JSON object")
  let textNode = jsonBody.getOrDefault("text")
  if textNode.isNil or textNode.kind != JString or textNode.getStr().len == 0:
    return err("missing or empty 'text' field")
  let text = textNode.getStr()
  let userIdNode = jsonBody.getOrDefault("userId")
  var userId = CliDefaultUserId
  if not userIdNode.isNil and userIdNode.kind == JString:
    let uid = userIdNode.getStr()
    if uid.len > 0:
      ## `api:` is the namespace of `/v1/chat/completions`. Accepting it here
      ## would let a web-UI message mint an identity whose replies the API
      ## drainer intercepts (and could close another turn's reservation).
      if uid.startsWith("api:"):
        return err("'userId' must not use the reserved 'api:' prefix")
      userId = UserId(uid)
  ok(InboundMessage(
    userId:    userId,
    channelId: "webui",
    text:      text,
    mediaUrl:  "",
    channel:   ckCli,
  ))
