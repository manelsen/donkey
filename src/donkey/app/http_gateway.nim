## HTTP gateway — embedded HTTP/1.1 server for browser/UI clients.
##
## Runs on the Chronos event loop of the thread that starts it (the daemon's
## main loop): no worker threads, no shared state, no global callbacks. The
## providers below are captured by the connection handler, and every wait
## (request reads, agent turns, event streams) is an `await`, so one slow
## client never holds up the others.
## Port: DONKEY_HTTP_PORT env var, default 8080.
##
## Endpoints:
##   GET /             → 200 OK, plain-text info (public health probe)
##   GET /health       → 200 OK, plain-text "ok" (public health probe)
##   GET /api/status   → DaemonStatus JSON
##   GET /api/logs     → recent log entries JSON (?n=N, default 50)
##   GET /api/events    → SSE stream of log events (long-lived connection)
##   POST /api/chat     → receive inbound message from web UI (bidirectional SSE)
##
## CORS: Access-Control-Allow-Origin: * for local browser access.
##
## Auth: `GET /`, `/health` and `/dashboard` are public (liveness probes plus a
## data-free shell that asks for the Bearer token and keeps it in
## sessionStorage). Every `/api/*` route, including `/api/sessions` and
## `/api/providers`, requires `Authorization: Bearer <DONKEY_HTTP_TOKEN>` even on
## loopback and even for `OPTIONS`: there is no unauthenticated mode for the
## data routes, so a gateway started without a token answers `401` there and the
## shell is the only thing left open. The `/v1/*` agent routes keep their
## historical local-only behaviour for an empty token; the agent itself already
## refuses to run without one.
##
## The token authenticates the client against the instance, never a user: the
## `user` field of a request is caller-asserted, so any token holder may act as
## any `api:<name>`. Per-user authentication is an explicit PRD non-goal and is
## pinned by `tests/app/t_http_gateway.nim` so the limitation stays deliberate.

import std/[json, os, strutils, times]
import chronos
import chronos/transports/stream
import ../core/pipeops
import ../core/types
import ../core/log
import ../ports/ipc
import ../core/agent_events
import ../domain/message
import ../domain/agent_message
import ../domain/providers/openai_compat
import ../domain/gateway/identity_pure
import ../domain/gateway/dashboard_pure
import ../domain/gateway/redact_pure
import ../domain/gateway/capacity_pure as capacity
import ../domain/gateway/chat_response
import ./metrics
import ./chat_bridge
import ./agent_chat_runtime

const
  GatewayDefaultPort* = 8080
  SseHeartbeatIntervalMs = 5000   ## ms between SSE heartbeat/push cycles
  SseMaxPollCycles = 60           ## bounded to ~5 minutes at 5s intervals
  MaxConcurrentHttpConnections = 32
  GatewayMaxRequestLine = 8192
  GatewayMaxHeaderLines = 64
  GatewayMaxHeaderBytes = 64 * 1024
  GatewayRequestDeadlineSec = 15

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

func parseBearerToken(header: string): string =
  ## Extracts the token from an "Authorization: Bearer <token>" value.
  let value = header.strip()
  const prefix = "bearer "
  if value.len > prefix.len and value.toLowerAscii().startsWith(prefix):
    value[prefix.len .. ^1].strip()
  else:
    ""

func constantTimeEq(a, b: string): bool =
  if a.len != b.len:
    return false
  var diff = 0
  for i in 0 ..< a.len:
    diff = diff or (ord(a[i]) xor ord(b[i]))
  diff == 0

func isAuthorized*(authHeader, token: string): bool =
  ## Empty token keeps the historical local-only behavior for the routes that
  ## accept it; `/api/*` asks `gatewayAuthVerdict` instead and never treats an
  ## empty token as authorized.
  if token.len == 0:
    return true
  constantTimeEq(parseBearerToken(authHeader), token)

func gatewayBindIsAllowed*(bindAddr, token: string;
                           allowInsecure = false): bool =
  ## Loopback is always allowed. Non-loopback requires a token AND an explicit
  ## opt-in because this gateway speaks cleartext HTTP.
  let host = bindAddr.strip().toLowerAscii()
  if host in ["127.0.0.1", "localhost", "::1", "[::1]"]:
    return true
  allowInsecure and token.len > 0

func isLocalOrigin*(origin: string): bool =
  let value = origin.strip().toLowerAscii()
  if value.len == 0:
    return true
  for scheme in ["http://", "https://"]:
    if value.startsWith(scheme):
      let authority = value[scheme.len .. ^1]
      if '/' in authority:
        return false
      var host = authority
      if host.startsWith("["):
        let close = host.find(']')
        if close < 0:
          return false
        host = host[0 .. close]
      else:
        host = host.split(':')[0]
      return host in ["localhost", "127.0.0.1", "[::1]"]
  false

func chatRequestAllowed*(origin, contentType, token: string): bool =
  ## Blocks simple cross-origin form posts; with a token the bearer check is
  ## the primary control. Without a token only local origins and JSON bodies.
  if token.len > 0:
    return true
  if not isLocalOrigin(origin):
    return false
  contentType.toLowerAscii().strip.startsWith("application/json")

type
  GatewayRequest* = object
    meth*: string
    path*: string

# ── StatusProvider / LogProvider (same types as ipc_server) ───────────────────

type
  GatewayStatusFn* = proc(): DaemonStatus {.gcsafe, raises: [CatchableError].}
  GatewayLogFn*    = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [CatchableError].}
  GatewayEventFn*  = proc(n: int): seq[AgentEvent] {.gcsafe, raises: [CatchableError].}
  GatewayAgentDispatchFn* = proc(msg: InboundMessage) {.gcsafe, raises: [CatchableError].}
    ## Starts one agent turn through the same ingress used by `/api/chat`.

  GatewayResponse* = object
    ## Status + body of a dashboard request, so the socket handler and the
    ## tests exercise the same code.
    status*: int
    contentType*: string
    body*: string

  GatewaySessionsFn* = proc(): seq[SessionDetail] {.gcsafe, raises: [CatchableError].}
    ## Returns every session; paging is applied by `buildSessionsJson`.

  GatewayProvidersFn* = proc(): string {.gcsafe, raises: [CatchableError].}
    ## Returns the provider-health JSON built by `buildProvidersJson`.

  GatewaySessionActionOutcome* = enum
    gsaoAccepted
    gsaoNotFound
    gsaoRevoked

  GatewaySessionActionFn* = proc(rawUserId: string; taskKind: TaskKind;
                                  payload: string): GatewaySessionActionOutcome
                                 {.gcsafe, raises: [CatchableError].}
    ## Performs the one management action. The raw id is the session key, not
    ## an `api:`-prefixed identity; the wiring owns lookup and revocation.

# ── Inbound handler ───────────────────────────────────────────────────────────

type
  GatewayInboundFn* = proc(msg: InboundMessage) {.gcsafe, raises: [CatchableError].}
    ## Callback to handle inbound messages from web UI POST /api/chat.
    ## Called on the event loop that runs the gateway.

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

func buildDashboardHtml*(): string =
  ## Dashboard shell. Public and data-free: the token is entered in the page
  ## and kept in sessionStorage, every table is filled at runtime through the
  ## Bearer-authenticated endpoints, and the CSP keeps script/connect local.
  result = """<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'">
<title>Donkey</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;margin:2rem;max-width:60rem;color:#1b1b1b}
h1{font-size:1.4rem;margin:0 0 1rem}
label{display:flex;gap:.5rem;align-items:center;margin-bottom:1rem;font-size:.9rem}
input{flex:1;padding:.4rem .6rem;border:1px solid #bbb;border-radius:6px}
button{padding:.4rem .9rem;border:1px solid #888;border-radius:6px;background:#f4f4f4;cursor:pointer}
pre{background:#f7f7f7;border:1px solid #e3e3e3;border-radius:8px;padding:.8rem;overflow:auto;max-height:20rem;font-size:.8rem}
h2{font-size:1rem;margin:1.2rem 0 .4rem}
table{width:100%;border-collapse:collapse;font-size:.8rem}
th,td{text-align:left;padding:.35rem .5rem;border-bottom:1px solid #e3e3e3;vertical-align:top}
</style>
</head>
<body>
<h1>Donkey</h1>
<label>Token <input id="token" type="password" autocomplete="off" placeholder="DONKEY_HTTP_TOKEN (obrigatório nas rotas /api)"></label>
<button id="save">Salvar e atualizar</button>
<h2>Status</h2>
<pre id="status">—</pre>
<h2>Sessões</h2>
<table>
<thead><tr><th>Sessão</th><th>Usuário</th><th>Canais</th><th>Último contato</th><th>Ativa</th></tr></thead>
<tbody id="sessions"><tr><td colspan="5">—</td></tr></tbody>
</table>
<h2>Providers</h2>
<table>
<thead><tr><th>Provider</th><th>Saúde</th><th>Cooldown</th><th>Chamadas</th><th>OK</th><th>Erros</th><th>Latência</th></tr></thead>
<tbody id="providers"><tr><td colspan="7">—</td></tr></tbody>
</table>
<h2>Nova conversa</h2>
<label>Usuário <input id="new-user" type="text" autocomplete="off" placeholder="userId (2ª coluna da tabela)"></label>
<button id="new-session">Nova conversa</button>
<pre id="action">—</pre>
<h2>Logs recentes</h2>
<pre id="logs">—</pre>
<script>
const $ = id => document.getElementById(id);
let token = sessionStorage.getItem('donkey_token') || '';
$('token').value = token;
function authHeaders() {
  const headers = {'Content-Type': 'application/json'};
  if (token) headers.Authorization = 'Bearer ' + token;
  return headers;
}
// A request without a token can never satisfy the mandatory bearer check on
// /api/sessions, /api/providers and the session action; the shell asks for the
// token first and does not hammer the endpoints with an answer it knows is 401.
function hasToken() {
  if (token) return true;
  $('token').focus();
  for (const id of ['sessions', 'providers']) {
    $(id).replaceChildren(row(['informe o token', '', '', '', '', '', '']));
  }
  return false;
}
async function get(path) {
  const headers = token ? {Authorization: 'Bearer ' + token} : {};
  const r = await fetch(path, {headers});
  return r.ok ? await r.text() : 'HTTP ' + r.status;
}
async function getJson(path) {
  const r = await fetch(path, {headers: authHeaders()});
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}
function row(cells) {
  const tr = document.createElement('tr');
  for (const text of cells) {
    const td = document.createElement('td');
    td.textContent = text;
    tr.appendChild(td);
  }
  return tr;
}
async function refreshSessions() {
  if (!hasToken()) return;
  try {
    const data = await getJson('/api/sessions');
    const body = $('sessions');
    body.replaceChildren();
    for (const s of (data.sessions || [])) {
      body.appendChild(row([
        s.sessionId || '', s.userId || '',
        (s.channels || []).join(', '),
        s.lastInboundAt || '—',
        s.live ? 'sim' : 'não',
      ]));
    }
    if (!body.firstChild) body.appendChild(row(['—', '—', '—', '—', '—']));
  } catch (e) {
    $('sessions').replaceChildren(row(['erro', String(e), '', '', '']));
  }
}
async function refreshProviders() {
  if (!hasToken()) return;
  try {
    const data = await getJson('/api/providers');
    const body = $('providers');
    body.replaceChildren();
    for (const p of data) {
      body.appendChild(row([
        p.id || '', p.health || '', p.cooldownUntil || '—',
        String(p.calls || 0), String(p.ok || 0), String(p.err || 0),
        String(p.avgLatencyMs || 0) + ' ms',
      ]));
    }
  } catch (e) {
    $('providers').replaceChildren(row(['erro', String(e), '', '', '', '', '']));
  }
}
async function refresh() {
  $('status').textContent = await get('/api/status');
  $('logs').textContent = await get('/api/logs?n=50');
  await refreshSessions();
  await refreshProviders();
}
$('save').onclick = () => {
  token = $('token').value.trim();
  sessionStorage.setItem('donkey_token', token);
  refresh();
};
$('new-session').addEventListener('click', async () => {
  const raw = $('new-user').value.trim();
  if (!raw) {
    $('action').textContent = 'informe o usuário';
    return;
  }
  if (!token) {
    $('action').textContent = 'informe o token';
    $('token').focus();
    return;
  }
  const r = await fetch('/api/sessions/' + encodeURIComponent(raw) + '/task', {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify({action: 'new'}),
  });
  $('action').textContent = r.ok ? 'aceito' : 'HTTP ' + r.status;
  refresh();
});
refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>
"""

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

func isPublicGatewayAction*(action: string): bool =
  ## Liveness/readiness probes must not require credentials. Only static text is
  ## exposed here; every data-bearing endpoint stays behind the token.
  action in ["index", "health", "dashboard"]

type
  GatewayAuthVerdict* = enum
    gavPublic    ## No credential needed: index, health, dashboard shell.
    gavAllowed   ## Bearer token matched.
    gavNoToken   ## An `/api/*` route was reached with no token configured.
    gavRejected  ## `/api/*` without a matching Bearer token.

func isApiRouteAction*(action: string): bool =
  ## The `/api/*` data surface. A set of route actions, not a prefix test: the
  ## cross-origin and fail-closed checks must agree with `routeGatewayRequest`,
  ## which already enumerates every action.
  action in ["status", "logs", "events", "chat", "sessions", "providers",
             "session_task"]

func gatewayAuthVerdict*(action, authHeader, token: string): GatewayAuthVerdict =
  ## `/api/*` requires a matching Bearer token regardless of bind address; an
  ## unconfigured token closes those routes instead of opening them to loopback
  ## browsers. The `/v1/*` agent routes keep the historical empty-token
  ## behaviour (the agent itself already refuses to run without a token).
  if isPublicGatewayAction(action):
    return gavPublic
  if token.len == 0:
    if isApiRouteAction(action):
      return gavNoToken
    return gavAllowed
  if constantTimeEq(parseBearerToken(authHeader), token):
    return gavAllowed
  gavRejected

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

proc agentNowSeconds(): int64 {.gcsafe, raises: [].} =
  epochTime().int64

proc agentClockMs(): int64 {.gcsafe, raises: [].} =
  int64(epochTime() * 1000)

proc agentNap(ms: int) {.gcsafe, raises: [].} =
  ## Only for a bridge built here when the caller passes none; the turns
  ## themselves wait with `sleepAsync`.
  os.sleep(ms)

# ── HTTP helpers ──────────────────────────────────────────────────────────────

const CorsHeaders = "Access-Control-Allow-Origin: *\r\n" &
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" &
                    "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"

proc remaining(deadline: Moment): chronos.Duration =
  let left = deadline - Moment.now()
  if left > chronos.ZeroDuration: left else: chronos.ZeroDuration

proc readHttpLine(conn: StreamTransport; deadline: Moment):
    Future[Result[string, string]] {.async: (raises: []).} =
  ## Reads one CRLF/LF line with a bounded length and the request deadline,
  ## which bounds the whole request (a slowloris client cannot stretch it).
  if Moment.now() >= deadline:
    return err("request deadline exceeded")
  let reading = conn.readLine(limit = GatewayMaxRequestLine + 1, sep = "\n")
  try:
    if not await reading.withTimeout(deadline.remaining):
      return err("request deadline exceeded")
    var line = reading.read()
    if line.len > GatewayMaxRequestLine:
      return err("request line too long")
    if line.endsWith("\r"):
      line.setLen(line.len - 1)
    if line.len == 0 and conn.atEof:
      return err("connection closed")
    return ok(line)
  except CancelledError:
    return err("request cancelled")
  except CatchableError as e:
    return err("connection closed or read failed: " & e.msg)

proc sendRaw(conn: StreamTransport; data: string): Future[bool] {.async: (raises: []).} =
  ## False when the client is gone.
  if data.len == 0:
    return true
  try:
    discard await conn.write(data)
    return true
  except CancelledError:
    return false
  except CatchableError:
    return false

proc sendResponse(conn: StreamTransport; status, contentType, body: string;
                  log: Logger): Future[void] {.async: (raises: []).} =
  let resp = "HTTP/1.1 " & status & "\r\n" &
             CorsHeaders &
             "Content-Type: " & contentType & "; charset=utf-8\r\n" &
             "Content-Length: " & $body.len & "\r\n" &
             "Connection: close\r\n\r\n" & body
  if not await conn.sendRaw(resp):
    log.warn("http_gateway: sendResponse failed: client gone")

proc sendJson(conn: StreamTransport; body: string; log: Logger): Future[void]
    {.async: (raises: []).} =
  await conn.sendResponse("200 OK", "application/json", body, log)

proc sendSseHeaders(conn: StreamTransport; log: Logger): Future[bool]
    {.async: (raises: []).} =
  ## Sends SSE-specific response headers, keeps connection open.
  ## Returns false when the client is already gone.
  let headers = "HTTP/1.1 200 OK\r\n" &
                CorsHeaders &
                "Content-Type: text/event-stream\r\n" &
                "Cache-Control: no-cache\r\n" &
                "Connection: keep-alive\r\n\r\n"
  result = await conn.sendRaw(headers)
  if not result:
    log.warn("http_gateway: sendSseHeaders failed: client gone")

proc sendSseData(conn: StreamTransport; event, data: string): Future[bool]
    {.async: (raises: []).} =
  ## Returns false if the connection is broken.
  return await conn.sendRaw(buildSseEvent(event, data))

# ── Query string parsing ──────────────────────────────────────────────────────

proc parseQueryInt(requestLine: string; key: string; default: int): int =
  let qmark = requestLine.find('?')
  if qmark < 0: return default
  let query = requestLine[qmark + 1 .. ^1]
  for pair in query.split('&'):
    let kv = pair.split('=', 1)
    if kv.len == 2 and kv[0] == key:
      try: return parseInt(kv[1])
      except ValueError: return default
  default

# ── Chat POST parsing ─────────────────────────────────────────────────────────

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

# ── Admission ─────────────────────────────────────────────────────────────────
#
# Everything runs on one event loop, so the counters are plain integers: no
# lock and no thread can touch them concurrently. The limits are resource
# caps (open connections, streams, waiting turns), decided by the pure
# `capacity.admitLongLived` policy.

var gActiveHttpConnections = 0
var gActiveSseConnections = 0
var gActiveAgentTurns = 0
  ## Non-streaming `/v1/chat/completions` turns. Streaming chat is counted
  ## as an SSE connection instead, so one request is never counted twice.

proc tryAcquireHttpConnection(): bool {.gcsafe, raises: [].} =
  if gActiveHttpConnections >= MaxConcurrentHttpConnections:
    return false
  inc gActiveHttpConnections
  true

proc releaseHttpConnection() {.gcsafe, raises: [].} =
  if gActiveHttpConnections > 0:
    dec gActiveHttpConnections

proc resetLongLivedCountersForTest*() {.gcsafe, raises: [].} =
  ## Test/diagnostic hook: clears both long-lived counters.
  gActiveAgentTurns = 0
  gActiveSseConnections = 0

proc longLivedOccupancy*(): capacity.LongLivedSnapshot {.gcsafe, raises: [].} =
  ## Occupancy before the next request is decided. `longLivedWorkers` is the
  ## sum of both classes, never just the larger one.
  capacity.LongLivedSnapshot(
    pendingTurns:     gActiveAgentTurns,
    sseConnections:   gActiveSseConnections,
    longLivedWorkers: gActiveAgentTurns + gActiveSseConnections,
  )

proc tryReserveLongLived*(kind: capacity.LongLivedKind):
    capacity.CapacityVerdict {.gcsafe, raises: [].} =
  ## Runs `admitLongLived` against the live counters and increments the class
  ## counter only on `cvAdmit`. A refusal leaves the snapshot untouched, so an
  ## over-capacity request never consumes (or releases) someone else's slot.
  result = capacity.admitLongLived(kind, longLivedOccupancy())
  if result.admitted:
    case kind
    of capacity.llChatTurn: inc gActiveAgentTurns
    of capacity.llSseConnection: inc gActiveSseConnections

proc releaseLongLived*(kind: capacity.LongLivedKind) {.gcsafe, raises: [].} =
  case kind
  of capacity.llChatTurn:
    if gActiveAgentTurns > 0:
      dec gActiveAgentTurns
  of capacity.llSseConnection:
    if gActiveSseConnections > 0:
      dec gActiveSseConnections

proc tryAcquireSseConnection(): bool {.gcsafe, raises: [].} =
  tryReserveLongLived(capacity.llSseConnection).admitted

proc releaseSseConnection() {.gcsafe, raises: [].} =
  releaseLongLived(capacity.llSseConnection)

proc runAdmittedAgentTurn*(body: string;
                           bridge: ChatBridge;
                           dispatch: GatewayAgentDispatchFn;
                           authorize: AuthorizeFn;
                           tokenConfigured: bool;
                           now: AgentNowFn;
                           timeoutMs: int;
                           model: string;
                           nap: AgentNapFn = nil): Future[AgentChatReply]
                          {.async.} =
  ## Non-streaming `/v1/chat/completions`: reserve one long-lived slot before
  ## the turn can register or dispatch. A refusal never reaches the dispatch
  ## hook and keeps the streaming path's mapping: `429` with a
  ## `rate_limit_error` body for both capacity verdicts (`cvNoWorker` is a
  ## backlog condition that clears on its own, not a server fault). The code
  ## still distinguishes a full turn queue from a full shared pool.
  ##
  ## `finally` releases the reservation on every exit: 200, 502 from a
  ## dispatch/turn error, 504 on the deadline, or an escaping exception. The
  ## release happens before the response is written, so a client abort cannot
  ## strand the slot.
  let verdict = tryReserveLongLived(capacity.llChatTurn)
  if not verdict.admitted:
    var code = "no_worker"
    var message = "no long-lived worker available"
    case verdict
    of capacity.cvTooManyPendingTurns:
      code = "too_many_pending_turns"
      message = "too many pending chat turns"
    of capacity.cvNoWorker:
      discard
    of capacity.cvTooManySseConnections:
      code = "sse_capacity"
      message = "too many concurrent streams"
    of capacity.cvAdmit:
      discard  # unreachable: cvAdmit was handled above
    return AgentChatReply(
      status: 429,
      body: buildAgentError(message, "rate_limit_error", code),
    )
  try:
    return await runAgentChat(
      body            = body,
      bridge          = bridge,
      dispatch        = dispatch,
      authorize       = authorize,
      tokenConfigured = tokenConfigured,
      now             = now,
      timeoutMs       = timeoutMs,
      model           = model,
      nap             = nap,
    )
  finally:
    releaseLongLived(capacity.llChatTurn)

# ── Connection handler ────────────────────────────────────────────────────────

type
  GatewayContext = ref object
    ## Everything a connection needs, captured by the handler closure.
    statusFn:        GatewayStatusFn
    logFn:           GatewayLogFn
    eventFn:         GatewayEventFn
    inboundFn:       GatewayInboundFn
    agentDispatchFn: GatewayAgentDispatchFn
    sessionsFn:      GatewaySessionsFn
    providersFn:     GatewayProvidersFn
    sessionActionFn: GatewaySessionActionFn
    authorizeFn:     AuthorizeFn
    chatBridge:      ChatBridge
    modelName:       string
    agentTimeoutMs:  int
    authToken:       string
    log:             Logger

  GatewayServer* = ref object
    ## A running gateway; `stopHttpGateway` closes it.
    server: StreamServer
    port*:  int

proc readRequestBody(conn: StreamTransport; contentLength: int;
                     deadline: Moment): Future[string] {.async: (raises: []).} =
  ## Reads at most `contentLength` bytes before the request deadline. Returns
  ## whatever arrived; the caller validates emptiness.
  if contentLength <= 0:
    return ""
  var buf = newString(contentLength)
  var received = 0
  while received < contentLength and Moment.now() < deadline:
    let reading = conn.readOnce(addr buf[received], contentLength - received)
    try:
      if not await reading.withTimeout(deadline.remaining):
        break
      let n = reading.read()
      if n <= 0:
        break
      received += n
    except CatchableError:
      break
  buf.setLen(received)
  return buf

proc readRequestBodyStrict(conn: StreamTransport; contentLength: int;
                           deadline: Moment): Future[Result[string, string]]
                          {.async: (raises: []).} =
  ## Like `readRequestBody`, but refuses a short read: a JSON prefix is not the
  ## body the client declared, and acting on it would accept a truncated
  ## request.
  let body = await conn.readRequestBody(contentLength, deadline)
  if body.len != max(contentLength, 0):
    return err("request body incomplete")
  return ok(body)

proc handleGatewayConn(ctx: GatewayContext; client: StreamTransport)
    {.async: (raises: []).} =
  let log = ctx.log
  try:
    let deadline = Moment.now() + chronos.seconds(GatewayRequestDeadlineSec)
    let requestLineResult = await client.readHttpLine(deadline)
    if requestLineResult.isErr:
      if requestLineResult.error != "connection closed":
        await client.sendResponse("400 Bad Request", "text/plain",
                                  requestLineResult.error & "\n", log)
      return
    let requestLine = requestLineResult.get
    if requestLine.len == 0:
      return

    ## Drain headers with bounded line count/bytes and a total deadline.
    let rawPath = if requestLine.splitWhitespace().len >= 2: requestLine.splitWhitespace()[1] else: "/"
    var contentLength = 0
    var authHeader = ""
    var contentType = ""
    var origin = ""
    var headerLines = 0
    var headerBytes = 0
    while true:
      if headerLines >= GatewayMaxHeaderLines:
        await client.sendResponse("400 Bad Request", "text/plain", "too many headers\n", log)
        return
      let headerResult = await client.readHttpLine(deadline)
      if headerResult.isErr:
        await client.sendResponse("400 Bad Request", "text/plain",
                                  headerResult.error & "\n", log)
        return
      inc headerLines
      headerBytes += headerResult.value.len
      if headerBytes > GatewayMaxHeaderBytes:
        await client.sendResponse("400 Bad Request", "text/plain", "headers too large\n", log)
        return
      let h = headerResult.value
      if h.len == 0: break
      let lc = h.toLowerAscii()
      if lc.startsWith("content-length:"):
        let val = lc[15..^1].strip()
        try:
          let parsed = parseBiggestInt(val)
          if parsed > MaxApiRequestBytes:
            await client.sendResponse("413 Payload Too Large", "application/json",
                                      "{\"error\":{\"message\":\"body too large\"," &
                                      "\"type\":\"invalid_request_error\"," &
                                      "\"code\":\"payload_too_large\"}}\n", log)
            return
          contentLength = parsed.int
        except ValueError:
          discard
      elif lc.startsWith("authorization:"):
        authHeader = h[14..^1].strip()
      elif lc.startsWith("content-type:"):
        contentType = h[13..^1].strip()
      elif lc.startsWith("origin:"):
        origin = h[7..^1].strip()

    let req = parseGatewayRequest(requestLine)
    var action = routeGatewayRequest(req)
    if req.meth == "OPTIONS":
      ## Preflights are answered before the body is read, but `/api/*` still
      ## needs the bearer check: `Access-Control-Allow-Origin: *` would
      ## otherwise let any page probe the data routes from loopback.
      if isApiRouteAction(action) and
         not isAuthorized(authHeader, ctx.authToken):
        await client.sendResponse("401 Unauthorized", "application/json",
                                  "{\"error\":\"unauthorized\"}\n", log)
        return
      await client.sendResponse("204 No Content", "text/plain", "", log)
      return
    var sessionTaskUser = ""
    if action == "notfound" and req.meth == "POST":
      let parsedTaskPath = parseSessionTaskPath(req.path)
      if parsedTaskPath.isOk:
        action = "session_task"
        sessionTaskUser = parsedTaskPath.get()
    case gatewayAuthVerdict(action, authHeader, ctx.authToken)
    of gavRejected:
      await client.sendResponse("401 Unauthorized", "application/json",
                                "{\"error\":\"unauthorized\"}\n", log)
      return
    of gavNoToken:
      await client.sendResponse("401 Unauthorized", "application/json",
                                "{\"error\":\"api routes require DONKEY_HTTP_TOKEN\"}\n", log)
      return
    of gavPublic, gavAllowed:
      discard
    if not isPublicGatewayAction(action) and ctx.authToken.len == 0 and
       origin.len > 0 and not isLocalOrigin(origin):
      await client.sendResponse("403 Forbidden", "application/json",
                                "{\"error\":\"cross-origin access requires a token\"}\n", log)
      return

    case action
    of "index":
      await client.sendResponse("200 OK", "text/plain",
        "Donkey HTTP gateway\nEndpoints: /dashboard /api/status /api/logs /api/events /api/chat /v1/models /v1/chat/completions\n", log)

    of "health":
      await client.sendResponse("200 OK", "text/plain", "ok\n", log)

    of "dashboard":
      await client.sendResponse("200 OK", "text/html", buildDashboardHtml(), log)

    of "status":
      await client.sendJson(buildStatusBody(ctx.statusFn()), log)

    of "logs":
      let n = parseQueryInt(rawPath, "n", 50)
      await client.sendJson(buildLogsBody(ctx.logFn(n)), log)

    of "sessions":
      if req.meth != "GET":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let limit = parseQueryInt(rawPath, "limit", DashboardDefaultLimit)
        let offset = parseQueryInt(rawPath, "offset", 0)
        let res = handleSessionsRequest(ctx.sessionsFn, limit, offset)
        await client.sendResponse(httpStatusLine(res.status), res.contentType,
                                  res.body, log)

    of "providers":
      if req.meth != "GET":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let res = handleProvidersRequest(ctx.providersFn)
        await client.sendResponse(httpStatusLine(res.status), res.contentType,
                                  res.body, log)

    of "session_task":
      if req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let bodyResult = await client.readRequestBodyStrict(contentLength, deadline)
        if bodyResult.isErr:
          await client.sendResponse("400 Bad Request", "application/json",
                                    "{\"error\":\"request body incomplete\"}\n", log)
          return
        let res = handleSessionActionRequest(ctx.sessionActionFn, sessionTaskUser,
                                             bodyResult.get(), authHeader, ctx.authToken)
        await client.sendResponse(httpStatusLine(res.status), res.contentType,
                                  res.body, log)

    of "events":
      if not tryAcquireSseConnection():
        await client.sendResponse("503 Service Unavailable", "text/plain",
                                  "too many event streams\n", log)
        return
      try:
        if not await client.sendSseHeaders(log):
          return
        ## Push a heartbeat comment immediately to confirm stream started.
        if not await client.sendRaw(": connected\n\n"):
          return
        ## Poll loop: push log + agent event snapshots every SseHeartbeatIntervalMs.
        for _ in 0 ..< SseMaxPollCycles:
          await sleepAsync(chronos.milliseconds(SseHeartbeatIntervalMs))
          let entries = ctx.logFn(100)
          if entries.len > 0:
            if not await client.sendSseData("logs", buildLogsBody(entries)):
              break
          var agentEvents = 0
          if ctx.eventFn != nil:
            let evs = ctx.eventFn(100)
            agentEvents = evs.len
            if evs.len > 0:
              if not await client.sendSseData("agent", buildAgentEventsBody(evs)):
                break
          if entries.len == 0 and agentEvents == 0:
            ## Heartbeat comment to keep connection alive.
            if not await client.sendRaw(": heartbeat\n\n"):
              break
      finally:
        releaseSseConnection()

    of "chat":
      let methAction = routeChatMethod(req.meth)
      case methAction
      of "chat":
        if not chatRequestAllowed(origin, contentType, ctx.authToken):
          await client.sendResponse("403 Forbidden", "application/json",
                                    "{\"error\":\"cross-origin chat requires a token\"}\n", log)
        elif ctx.inboundFn == nil:
          await client.sendResponse("503 Service Unavailable", "application/json",
                                    "{\"error\":\"inbound handler not configured\"}\n", log)
        else:
          let body = await client.readRequestBody(contentLength, deadline)
          if body.len == 0:
            await client.sendResponse("400 Bad Request", "application/json",
                                      "{\"error\":\"empty body\"}\n", log)
          else:
            let msgResult = parseChatPost(body)
            if msgResult.isErr:
              await client.sendResponse("400 Bad Request", "application/json",
                                        "{\"error\":\"" & msgResult.error & "\"}\n", log)
            else:
              ctx.inboundFn(msgResult.get())
              await client.sendResponse("202 Accepted", "application/json",
                                        "{\"status\":\"accepted\"}\n", log)
      of "chat_get":
        await client.sendResponse("200 OK", "application/json",
                                  "{\"info\":\"POST to /api/chat to send messages\"}\n", log)
      else:
        await client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

    of "openai_chat":
      if req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let body = await client.readRequestBody(contentLength, deadline)
        if agentChatStreamRequested(body):
          let openSse: AgentStreamOpenFn = proc(): Future[bool] {.async.} =
            return await client.sendSseHeaders(log)
          let sendSse: AgentStreamSendFn = proc(chunk: string): Future[bool] {.async.} =
            return await client.sendRaw(chunk)
          let streamResult = await runAgentStream(
            body            = body,
            bridge          = ctx.chatBridge,
            dispatch        = ctx.agentDispatchFn,
            authorize       = ctx.authorizeFn,
            tokenConfigured = ctx.authToken.len > 0,
            now             = agentNowSeconds,
            openStream      = openSse,
            send            = sendSse,
            acquireSlot     = tryAcquireSseConnection,
            releaseSlot     = releaseSseConnection,
            streamNow       = agentClockMs,
            timeoutMs       = ctx.agentTimeoutMs,
            model           = ctx.modelName,
          )
          if streamResult.outcome == asPreflightError:
            await client.sendResponse(httpStatusLine(streamResult.reply.status),
                                      "application/json",
                                      streamResult.reply.body & "\n", log)
        else:
          let reply = await runAdmittedAgentTurn(
            body            = body,
            bridge          = ctx.chatBridge,
            dispatch        = ctx.agentDispatchFn,
            authorize       = ctx.authorizeFn,
            tokenConfigured = ctx.authToken.len > 0,
            now             = agentNowSeconds,
            timeoutMs       = ctx.agentTimeoutMs,
            model           = ctx.modelName,
          )
          await client.sendResponse(httpStatusLine(reply.status), "application/json",
                                    reply.body & "\n", log)

    of "openai_models":
      if req.meth != "GET":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        await client.sendJson(buildOpenAiModels(ctx.modelName, epochTime().int64), log)

    of "notfound":
      await client.sendResponse("404 Not Found", "text/plain", "Not found\n", log)

    else:
      await client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

  except CancelledError:
    discard
  except CatchableError as e:
    log.warn("http_gateway: connection handler error: " & e.msg)
    recordWebhookFailure("http_gateway", e.msg)

# ── Server ────────────────────────────────────────────────────────────────────

proc gatewayBindAddress*(bindAddr: string; port: int):
    Result[TransportAddress, string] =
  ## The address to listen on. A literal IP (`127.0.0.1`, `::1`, `[::1]`) is
  ## used as it is; a host name such as `localhost` is resolved over IPv4,
  ## as the previous `std/net` socket did for any address without a colon.
  let host =
    if bindAddr.startsWith("[") and bindAddr.endsWith("]"): bindAddr[1 .. ^2]
    else: bindAddr
  try:
    return ok(initTAddress(host, Port(port)))
  except CatchableError:
    discard
  try:
    let resolved = resolveTAddress(host, Port(port), Domain.AF_INET)
    if resolved.len > 0:
      return ok(resolved[0])
    err("cannot resolve " & host)
  except CatchableError as e:
    err("cannot resolve " & host & ": " & e.msg)

proc startHttpGateway*(port: int;
                       statusFn: GatewayStatusFn;
                       logFn:    GatewayLogFn;
                       eventFn:  GatewayEventFn = nil;
                       inboundFn: GatewayInboundFn = nil;
                       sessionsFn: GatewaySessionsFn = nil;
                       providersFn: GatewayProvidersFn = nil;
                       sessionActionFn: GatewaySessionActionFn = nil;
                       bindAddr = "127.0.0.1";
                       authToken = "";
                       agentDispatchFn: GatewayAgentDispatchFn = nil;
                       authorizeFn: AuthorizeFn = nil;
                       chatBridge: ChatBridge = nil;
                       modelName = "";
                       agentTimeoutMs = 0;
                       log:       Logger = newLogger("http_gateway")
                      ): Result[GatewayServer, string] =
  ## Binds and starts the gateway on the calling thread's Chronos loop; the
  ## connections are served while that loop runs (the daemon's main loop).
  ## The providers are called on that loop, so they need no locking.
  ## A private bridge is never fed by the daemon outbox drainer: every turn
  ## would register and poll a queue nobody drains, ending in 504.
  if agentDispatchFn != nil and chatBridge == nil:
    return err("http_gateway: the agent endpoint requires the shared ChatBridge")
  let ctx = GatewayContext(
    statusFn: statusFn, logFn: logFn, eventFn: eventFn, inboundFn: inboundFn,
    agentDispatchFn: agentDispatchFn, sessionsFn: sessionsFn,
    providersFn: providersFn, sessionActionFn: sessionActionFn,
    authorizeFn: authorizeFn,
    chatBridge: if chatBridge != nil: chatBridge
                else: newChatBridge(agentClockMs, agentNap),
    modelName: modelName,
    agentTimeoutMs:
      if agentTimeoutMs > 0: agentTimeoutMs
      else: resolveAgentTimeoutMs(""),
    authToken: authToken,
    log: log)

  proc onConnection(server: StreamServer; client: StreamTransport)
      {.async: (raises: []).} =
    if not tryAcquireHttpConnection():
      await client.sendResponse("503 Service Unavailable", "text/plain",
                                "too many connections\n", ctx.log)
      await client.closeWait()
      return
    try:
      await handleGatewayConn(ctx, client)
    finally:
      releaseHttpConnection()
      await client.closeWait()

  let address = gatewayBindAddress(bindAddr, port).valueOr:
    let msg = "http_gateway: bind " & bindAddr & ":" & $port & " failed — " & error
    log.error(msg)
    return err(msg)
  try:
    let server = createStreamServer(address, onConnection, {ServerFlags.ReuseAddr})
    server.start()
    ok(GatewayServer(server: server, port: port))
  except CatchableError as e:
    let msg = "http_gateway: bind " & bindAddr & ":" & $port & " failed — " & e.msg
    log.error(msg)
    err(msg)

proc stopHttpGateway*(gateway: GatewayServer): Future[void] {.async: (raises: []).} =
  ## Stops accepting and closes the listening socket. Connections already
  ## being served finish on their own.
  if gateway == nil or gateway.server == nil:
    return
  try:
    gateway.server.stop()
  except CatchableError:
    discard
  await gateway.server.closeWait()
