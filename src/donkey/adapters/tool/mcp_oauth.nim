## mcp_oauth.nim — OAuth for remote MCP servers: discovery, login, tokens.
##
## The pure rules are `domain/tools/mcp_oauth_pure`; this module does the
## HTTP and the storage.
##
## Login (operator, from the CLI):
##   1. probe the server without a token; a 401's `WWW-Authenticate` names the
##      protected-resource metadata (else the well-known URLs, RFC 9728);
##   2. that metadata names the authorization server, whose metadata names
##      the endpoints (RFC 8414);
##   3. register a public client (RFC 7591), or use a pre-registered one
##      (`--client-id`, with `--client-secret-env NAME` for a confidential
##      client: it authenticates at the token endpoint with Basic, or in the
##      form when the server takes only that; the secret stays in the
##      environment, the stored record names only its variable);
##   4. the operator opens the authorization URL (PKCE S256, state, resource)
##      in their own browser and pastes back the URL it was sent to;
##   5. the code is exchanged for tokens, stored 0600 under `state/mcp_oauth/`.
## Daemon: `mcpTokenSource` hands the MCP client a token, refreshing it when it
## is about to expire or when the server answered 401.

import std/[base64, json, strutils, sysrand, times]
import nimcrypto/sha2
import ../../core/app_meta
import ../../core/pipeops
import ../../domain/tools/mcp_oauth_pure
import ../../domain/tools/mcp_http_pure
import ../../ports/http
import ../filesystem/fs_adapter
import ../http/std_http

type
  McpOAuthRecord* = object
    serverUrl*:     string
    resource*:      string
    clientId*:      string
    tokenEndpoint*: string
    tokens*:        OAuthTokens
    clientSecretEnv*: string            ## the variable holding the secret
    authMethod*:    ClientAuthMethod    ## camNone for a public client

  PreregisteredClient* = object
    ## A client the operator registered with the authorization server.
    clientId*:  string
    secret*:    string   ## read from the environment by the caller
    secretEnv*: string   ## its variable's name, stored for refreshes

  McpLoginPending* = object
    serverUrl*:        string
    redirectUri*:      string
    clientId*:         string
    meta*:             AuthServerMeta
    verifier*:         string
    state*:            string
    authorizationUrl*: string
    secret*:           string
    secretEnv*:        string
    authMethod*:       ClientAuthMethod

  McpTokenFn* = proc(forceRefresh: bool): Result[string, string] {.gcsafe.}

const McpOAuthDirName* = "mcp_oauth"

proc productionOAuthPort*(): HttpRuntimePort =
  newStdHttpAdapter(timeout = 30, maxRetries = 1, retryNonIdempotent = false,
                    returnServerError = true).toRuntimePort()

func getter(http: HttpRuntimePort): auto =
  if http.getNoRedirect != nil: http.getNoRedirect else: http.get

func poster(http: HttpRuntimePort): auto =
  if http.postNoRedirect != nil: http.postNoRedirect else: http.post

proc randomToken(bytes: int): Result[string, string] =
  var raw = newString(bytes)
  if not urandom(raw.toOpenArrayByte(0, raw.high)):
    return err("oauth: no OS randomness")
  ok(base64.encode(raw, safe = true).strip(leading = false, chars = {'='}))

proc getJson(http: HttpRuntimePort; url: string): Result[JsonNode, string] =
  let resp = ? getter(http)(url, @[(name: "Accept", value: "application/json")])
  if resp.status != 200:
    return err("HTTP " & $resp.status)
  try: ok(parseJson(resp.body))
  except CatchableError as e: err(e.msg)

proc firstJson(http: HttpRuntimePort; urls: seq[string]): Result[JsonNode, string] =
  var last = "no URL"
  for url in urls:
    let r = getJson(http, url)
    if r.isOk: return r
    last = url & ": " & r.error
  err(last)

proc discoverAuthServer*(serverUrl: string;
                         http: HttpRuntimePort): Result[AuthServerMeta, string] =
  ## The authorization server of an MCP server, by its protected-resource
  ## metadata.
  var metadataUrls: seq[string]
  let probe = poster(http)(serverUrl,
    $(%* {"jsonrpc": "2.0", "id": 0, "method": "initialize",
          "params": {"protocolVersion": McpProtocolVersion, "capabilities": {},
                     "clientInfo": {"name": AppSlug, "version": AppVersion}}}),
    mcpRequestHeaders("", "", ""))
  if probe.isOk and probe.get.status == 401:
    let named = resourceMetadataFrom(headerValue(probe.get.headers, "WWW-Authenticate"))
    if named.len > 0: metadataUrls.add(named)
  for url in protectedResourceMetadataUrls(serverUrl):
    if url notin metadataUrls: metadataUrls.add(url)
  let resource = ? firstJson(http, metadataUrls).mapErr(
    proc(e: string): string = "oauth: no protected-resource metadata (" & e & ")")
  let servers = resource{"authorization_servers"}
  if servers.isNil or servers.kind != JArray or servers.len == 0:
    return err("oauth: the server names no authorization server")
  let issuer = servers[0].getStr
  let metaJson = ? firstJson(http, authServerMetadataUrls(issuer)).mapErr(
    proc(e: string): string = "oauth: no authorization-server metadata (" & e & ")")
  parseAuthServerMeta(metaJson)

proc registerClient(meta: AuthServerMeta; redirectUri: string;
                    http: HttpRuntimePort): Result[string, string] =
  if meta.registrationEndpoint.len == 0:
    return err("oauth: the authorization server offers no dynamic client " &
               "registration; register a client with it and log in with " &
               "--client-id ID (and --client-secret-env NAME if it has a secret)")
  let reg = ? poster(http)(meta.registrationEndpoint,
    $registrationBody(redirectUri, AppName),
    @[(name: "Content-Type", value: "application/json"),
      (name: "Accept", value: "application/json")])
  if reg.status notin [200, 201]:
    return err("oauth: client registration refused (HTTP " & $reg.status & "): " & reg.body)
  let clientId = try: parseJson(reg.body){"client_id"}.getStr("")
                 except CatchableError: ""
  if clientId.len == 0:
    return err("oauth: registration returned no client_id")
  ok(clientId)

proc beginMcpLogin*(serverUrl, redirectUri: string; http: HttpRuntimePort;
                    client = PreregisteredClient()): Result[McpLoginPending, string] =
  ## `client` empty: register a public client. Otherwise use it, a public
  ## one (no secret) or a confidential one.
  let meta = ? discoverAuthServer(serverUrl, http)
  let clientId =
    if client.clientId.len > 0: client.clientId
    else: ? registerClient(meta, redirectUri, http)
  let authMethod = ? clientAuthMethodFor(meta, hasSecret = client.secret.len > 0)
  let verifier = ? randomToken(32)
  let state = ? randomToken(16)
  ok(McpLoginPending(
    serverUrl: serverUrl, redirectUri: redirectUri, clientId: clientId,
    secret: client.secret, secretEnv: client.secretEnv, authMethod: authMethod,
    meta: meta, verifier: verifier, state: state,
    authorizationUrl: authorizationUrl(meta, clientId, redirectUri,
      pkceChallenge(verifier), state, serverUrl,
      scope = meta.scopes.join(" "))))

proc postForm(http: HttpRuntimePort; url, form: string; nowSec: int64;
              authMethod = camNone; clientId = "", secret = ""): Result[OAuthTokens, string] =
  var headers = @[(name: "Content-Type", value: "application/x-www-form-urlencoded"),
                  (name: "Accept", value: "application/json")]
  if authMethod == camBasic:
    headers.add((name: "Authorization", value: basicClientAuth(clientId, secret)))
  let resp = ? poster(http)(url, form, headers)
  let body = try: parseJson(resp.body) except CatchableError: newJObject()
  if resp.status != 200 and not body.hasKey("error"):
    return err("oauth: token endpoint answered HTTP " & $resp.status)
  parseTokenResponse(body, nowSec)

proc completeMcpLogin*(p: McpLoginPending; pastedUrl: string; http: HttpRuntimePort;
                       nowSec: int64): Result[McpOAuthRecord, string] =
  let code = ? codeFromRedirect(pastedUrl, p.state)
  let tokens = ? postForm(http, p.meta.tokenEndpoint,
    tokenRequestForm(code, p.verifier, p.clientId, p.redirectUri, p.serverUrl,
                     clientSecret = (if p.authMethod == camPost: p.secret else: "")),
    nowSec, p.authMethod, p.clientId, p.secret)
  ok(McpOAuthRecord(serverUrl: p.serverUrl, resource: p.serverUrl,
                    clientId: p.clientId, tokenEndpoint: p.meta.tokenEndpoint,
                    clientSecretEnv: p.secretEnv, authMethod: p.authMethod,
                    tokens: tokens))

# ── Storage ───────────────────────────────────────────────────────────────────

proc mcpOAuthPath*(dir, serverUrl: string): string =
  ## One file per server, named by a hash of its URL.
  var ctx: sha256
  ctx.init()
  ctx.update(serverUrl)
  let digest = ctx.finish()
  ctx.clear()
  var name = ""
  for b in digest.data[0 ..< 8]:
    name.add(b.toHex(2).toLowerAscii)
  dir & "/" & name & ".json"

proc saveMcpOAuth*(dir: string; rec: McpOAuthRecord): Result[void, string] =
  let fs = newFsAdapter()
  ? fs.createDir(dir)
  fs.writePrivate(mcpOAuthPath(dir, rec.serverUrl), $(%* {
    "server_url": rec.serverUrl, "resource": rec.resource,
    "client_id": rec.clientId, "token_endpoint": rec.tokenEndpoint,
    "client_secret_env": rec.clientSecretEnv, "auth_method": $rec.authMethod,
    "access_token": rec.tokens.accessToken,
    "refresh_token": rec.tokens.refreshToken,
    "expires_at": rec.tokens.expiresAt}))

proc loadMcpOAuth*(dir, serverUrl: string): Result[McpOAuthRecord, string] =
  let fs = newFsAdapter()
  let text = ? fs.readFile(mcpOAuthPath(dir, serverUrl))
  try:
    let j = parseJson(text)
    ok(McpOAuthRecord(
      serverUrl: j{"server_url"}.getStr, resource: j{"resource"}.getStr,
      clientId: j{"client_id"}.getStr, tokenEndpoint: j{"token_endpoint"}.getStr,
      clientSecretEnv: j{"client_secret_env"}.getStr(""),
      authMethod: parseEnum[ClientAuthMethod](j{"auth_method"}.getStr("none"), camNone),
      tokens: OAuthTokens(accessToken: j{"access_token"}.getStr,
                          refreshToken: j{"refresh_token"}.getStr,
                          expiresAt: j{"expires_at"}.getBiggestInt(0))))
  except CatchableError as e:
    err("oauth: unreadable token file: " & e.msg)

# ── Token source for the daemon ───────────────────────────────────────────────

proc nowUnix(): int64 {.gcsafe.} = getTime().toUnix

proc mcpTokenSource*(dir, serverUrl: string; http = HttpRuntimePort();
                     clock: proc(): int64 {.gcsafe.} = nil;
                     secretOf: proc(name: string): string {.gcsafe.} = nil): McpTokenFn =
  ## A token for `serverUrl`, refreshed (and stored) when it is about to
  ## expire or when `forceRefresh` says the server refused it. `secretOf`
  ## reads a confidential client's secret by its variable's name (the
  ## daemon gives the environment snapshot).
  let port = if http.postNoRedirect != nil or http.post != nil: http
             else: productionOAuthPort()
  let now = if clock != nil: clock else: nowUnix
  result = proc(forceRefresh: bool): Result[string, string] {.gcsafe.} =
    var rec = loadMcpOAuth(dir, serverUrl).valueOr:
      return err("oauth: no login for " & serverUrl &
                 "; run `donkey ctl mcp login " & serverUrl & "`")
    if not forceRefresh and not needsRefresh(rec.tokens, now()):
      return ok(rec.tokens.accessToken)
    if rec.tokens.refreshToken.len == 0:
      return err("oauth: the token expired and there is no refresh token; " &
                 "run `donkey ctl mcp login " & serverUrl & "`")
    var secret = ""
    if rec.authMethod != camNone:
      secret = if secretOf != nil: secretOf(rec.clientSecretEnv) else: ""
      if secret.len == 0:
        return err("oauth: the client secret variable " & rec.clientSecretEnv &
                   " is empty; set it to refresh the token for " & serverUrl)
    let fresh = ? postForm(port, rec.tokenEndpoint,
      refreshRequestForm(rec.tokens.refreshToken, rec.clientId, rec.resource,
                         clientSecret = (if rec.authMethod == camPost: secret else: "")),
      now(), rec.authMethod, rec.clientId, secret)
    rec.tokens = mergeRefreshed(rec.tokens, fresh)
    ? saveMcpOAuth(dir, rec)
    ok(rec.tokens.accessToken)
