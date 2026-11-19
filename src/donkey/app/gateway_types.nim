## Shared types, constants and process-wide state of the HTTP gateway.
##
## Extracted from `http_gateway` so the auth helpers, the route builders and
## the socket server share one definition site without import cycles. The
## unqualified `g*` names stay importable so the wiring in `gateway_server`
## (and the facade's importers) keep their historical spelling.

import std/[net, nativesockets]
import locks
import ../core/types
import ../core/log
import ../core/agent_events
import ../ports/ipc
import ../domain/message
import ../domain/agent_message
import ../domain/gateway/dashboard_pure
import ../domain/gateway/identity_pure
import ./chat_bridge
import ./agent_chat_runtime

const
  GatewayDefaultPort* = 8080
  SseHeartbeatIntervalMs* = 5000   ## ms between SSE heartbeat/push cycles
  SseMaxPollCycles* = 60           ## bounded to ~5 minutes at 5s intervals
  MaxConcurrentHttpConnections* = 32
  ## SSE streams occupy a worker for their whole lifetime (up to ~5 minutes),
  ## so keep this well below GatewayWorkerCount: at least half of the workers
  ## must stay available for normal requests and 503 responses.
  MaxConcurrentSseConnections* = 4
  GatewayMaxRequestLine* = 8192
  GatewayMaxHeaderLines* = 64
  GatewayMaxHeaderBytes* = 64 * 1024
  GatewayRequestDeadlineSec* = 15

const CorsHeaders* = "Access-Control-Allow-Origin: *\r\n" &
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" &
                    "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"

const
  CliDefaultUserId* = UserId("local:webui")
    ## Default user id for web UI messages.

const GatewayWorkerCount = 8
const GatewayQueueDepth* = 64

type
  GatewayRequest* = object
    meth*: string
    path*: string

# ── StatusProvider / LogProvider (same types as ipc_server) ───────────────────

type
  GatewayStatusFn* = proc(): DaemonStatus {.gcsafe.}
  GatewayLogFn*    = proc(n: int): seq[IpcLogEntry] {.gcsafe.}
  GatewayEventFn*  = proc(n: int): seq[AgentEvent] {.gcsafe.}
  GatewayAgentDispatchFn* = proc(msg: InboundMessage) {.gcsafe.}
    ## Starts one agent turn through the same ingress used by `/api/chat`.

  GatewayResponse* = object
    ## Status + body of a dashboard request, so the socket handler and the
    ## tests exercise the same code.
    status*: int
    contentType*: string
    body*: string

  GatewaySessionsFn* = proc(): seq[SessionDetail] {.gcsafe.}
    ## Returns every session; paging is applied by `buildSessionsJson`.

  GatewayProvidersFn* = proc(): string {.gcsafe.}
    ## Returns the provider-health JSON built by `buildProvidersJson`.

  GatewaySessionActionOutcome* = enum
    gsaoAccepted
    gsaoNotFound
    gsaoRevoked

  GatewaySessionActionFn* = proc(rawUserId: string; taskKind: TaskKind;
                                  payload: string): GatewaySessionActionOutcome
                                 {.gcsafe.}
    ## Performs the one management action. The raw id is the session key, not
    ## an `api:`-prefixed identity; the wiring owns lookup and revocation.

# ── Inbound handler ───────────────────────────────────────────────────────────

type
  GatewayInboundFn* = proc(msg: InboundMessage) {.gcsafe.}
    ## Callback to handle inbound messages from web UI POST /api/chat.
    ## Called on the gateway thread; must be thread-safe.

type
  GatewayAuthVerdict* = enum
    gavPublic    ## No credential needed: index, health, dashboard shell.
    gavAllowed   ## Bearer token matched.
    gavNoToken   ## An `/api/*` route was reached with no token configured.
    gavRejected  ## `/api/*` without a matching Bearer token.

type GatewayArgs* = object
  port*:      int
  bindAddr*:  string
  authToken*: string
  statusFn*:  GatewayStatusFn
  logFn*:     GatewayLogFn
  eventFn*:   GatewayEventFn
  inboundFn*: GatewayInboundFn
  agentDispatchFn*: GatewayAgentDispatchFn
  sessionsFn*: GatewaySessionsFn
  providersFn*: GatewayProvidersFn
  sessionActionFn*: GatewaySessionActionFn
  authorizeFn*: AuthorizeFn
  chatBridge*: ChatBridge
  modelName*: string
  agentTimeoutMs*: int
  log*:       Logger

type HttpConnectionArgs* = object
  client*:    Socket
  statusFn*:  GatewayStatusFn
  logFn*:     GatewayLogFn
  eventFn*:   GatewayEventFn
  inboundFn*: GatewayInboundFn
  authToken*: string
  log*:       Logger

var gGatewayStatusFn*: GatewayStatusFn
var gGatewayLogFn*:    GatewayLogFn
var gGatewayEventFn*:  GatewayEventFn
var gGatewayInboundFn*: GatewayInboundFn
var gGatewayAgentDispatchFn*: GatewayAgentDispatchFn
var gGatewaySessionsFn*: GatewaySessionsFn
var gGatewayProvidersFn*: GatewayProvidersFn
var gGatewaySessionActionFn*: GatewaySessionActionFn
var gGatewayAuthorizeFn*: AuthorizeFn
var gGatewayChatBridge*: ChatBridge
var gGatewayModelName*: string
var gGatewayAgentTimeoutMs*: int
var gGatewayLog*:      Logger
var gGatewayAuthToken*: string

var
  gGatewayQueue* {.global.}: Channel[SocketHandle]
  gGatewayWorkers* {.global.}: array[GatewayWorkerCount, Thread[int]]
  gGatewayPoolStarted* = false
  gGatewayPoolAttempted* = false

var gGatewayListenerActive* = false
  ## The pool and the listener have different lifetimes: a failed bind leaves
  ## the pool usable, so a retry must be allowed once the port is free.

var gGatewayThread*: Thread[GatewayArgs]

var gActiveHttpConnections* = 0
var gActiveSseConnections* = 0
var gActiveAgentTurns* = 0
  ## Non-streaming `/v1/chat/completions` workers. Streaming chat is counted
  ## as an SSE connection instead, so one worker is never counted twice.
var gHttpConnLock*: Lock
initLock(gHttpConnLock)  # Module init runs before any gateway thread starts.

var gAgentStreamNap*: AgentStreamNapFn = nil
  ## The streaming path needs the same dispatcher pump as the non-streaming
  ## one: the turn's ingress actor runs on this gateway worker, so a plain
  ## sleep left SSE without events until the deadline. Injected by the daemon,
  ## which owns the chronos nanosecond loop for this thread.
