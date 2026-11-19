## Pure request parsing, route dispatch and response builders for the HTTP
## gateway. No sockets here: the server turns these values into bytes.

import std/[json, strutils]
import ../core/pipeops
import ../core/types
import ../core/agent_events
import ../ports/ipc
import ../domain/message
import ../domain/agent_message
import ../domain/gateway/dashboard_pure
import ../domain/gateway/redact_pure
import ../domain/gateway/identity_pure
import ./gateway_types
import ./gateway_auth

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

func buildStatusBody*(st: DaemonStatus): string =
  $st.toJson()

func buildLogsBody*(entries: seq[IpcLogEntry]): string =
  var arr = newJArray()
  for e in entries:
    arr.add(e.toJson())
  $arr

func buildAgentEventsBody*(events: seq[AgentEvent]): string =
  var arr = newJArray()
  for e in events:
    arr.add(e.toJson())
  $arr

func dashboardError*(status: int; message: string): GatewayResponse =
  ## Every dashboard error path leaves through `redactForClient`, so an echoed
  ## parser/provider message can never carry `Bearer`, `sk-`, `key=` or
  ## `token=` values to the browser.
  GatewayResponse(status: status, contentType: "application/json",
                  body: $(%*{"error": redactForClient(message)}))

proc handleSessionsRequest*(sessionsFn: GatewaySessionsFn;
                            rawLimit, rawOffset: int): GatewayResponse {.gcsafe.} =
  ## `GET /api/sessions`. The hook returns every row; paging/clamping is pure,
  ## so no query value can turn into a 500.
  if sessionsFn == nil:
    return dashboardError(503, "sessions hook not configured")
  GatewayResponse(status: 200, contentType: "application/json",
                  body: buildSessionsJson(sessionsFn(), rawLimit, rawOffset))

proc handleProvidersRequest*(providersFn: GatewayProvidersFn): GatewayResponse
                            {.gcsafe.} =
  ## `GET /api/providers`. The wiring builds the body with the pure provider
  ## builder, which derives health from availability, cooldowns and metrics.
  if providersFn == nil:
    return dashboardError(503, "providers hook not configured")
  GatewayResponse(status: 200, contentType: "application/json",
                  body: providersFn())

proc handleSessionActionRequest*(actionFn: GatewaySessionActionFn;
                                 rawUserId, body, authHeader,
                                 authToken: string): GatewayResponse {.gcsafe.} =
  ## `POST /api/sessions/{userId}/task`. The raw session key is never passed
  ## through `apiUserId`; auth is checked here as well as in the socket
  ## handler, and a missing hook fails closed. An empty token is a `401` here
  ## like in the socket handler: `/api/*` never runs unauthenticated.
  if authToken.len == 0:
    return dashboardError(401, "api routes require DONKEY_HTTP_TOKEN")
  if not isAuthorized(authHeader, authToken):
    return dashboardError(401, "unauthorized")
  if actionFn == nil:
    return dashboardError(503, "session action hook not configured")
  let parsed = parseSessionAction(body)
  if parsed.isErr:
    return dashboardError(400, parsed.error)
  case actionFn(rawUserId, tkNew, "")
  of gsaoAccepted:
    GatewayResponse(status: 202, contentType: "application/json",
                    body: "{\"status\":\"accepted\"}")
  of gsaoNotFound:
    dashboardError(404, "session not found")
  of gsaoRevoked:
    dashboardError(403, "access revoked")

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

proc parseQueryInt*(requestLine: string; key: string; default: int): int =
  let qmark = requestLine.find('?')
  if qmark < 0: return default
  let query = requestLine[qmark + 1 .. ^1]
  for pair in query.split('&'):
    let kv = pair.split('=', 1)
    if kv.len == 2 and kv[0] == key:
      try: return parseInt(kv[1])
      except ValueError: return default
  default

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
