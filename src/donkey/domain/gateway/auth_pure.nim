## Who may call the HTTP gateway: Bearer-token checks, the bind policy and
## the origin rules. Pure; the socket handler asks these before routing.

import std/strutils

func parseBearerToken*(header: string): string =
  ## Extracts the token from an "Authorization: Bearer <token>" value.
  let value = header.strip()
  const prefix = "bearer "
  if value.len > prefix.len and value.toLowerAscii().startsWith(prefix):
    value[prefix.len .. ^1].strip()
  else:
    ""

func constantTimeEq*(a, b: string): bool =
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
    gavEditor    ## An editor route (E10.2): its handler authenticates it,
                 ## by the pairing secret or the editor's credential.

func isEditorAction*(action: string): bool =
  ## The editor routes never take the operator's token: an editor holds only
  ## its own credential.
  action in ["acp_pair", "acp_pair_poll", "acp_chat"]

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
  if isEditorAction(action):
    return gavEditor
  if token.len == 0:
    if isApiRouteAction(action):
      return gavNoToken
    return gavAllowed
  if constantTimeEq(parseBearerToken(authHeader), token):
    return gavAllowed
  gavRejected
