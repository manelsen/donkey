## mcp_oauth_pure.nim — MCP authorization, the pure part.
##
## MCP spec 2025-06-18, "Authorization": OAuth 2.1 with PKCE (S256), the
## protected resource's metadata (RFC 9728) pointing at the authorization
## server, whose metadata (RFC 8414) names the endpoints; a public client is
## registered dynamically (RFC 7591) and every authorization and token request
## names the MCP server as the `resource` (RFC 8707).
##
## Donkey runs headless, so the browser step is done by the operator: the CLI
## prints the authorization URL and reads back the URL the browser was sent
## to. `codeFromRedirect` takes the code from it only when the `state` matches.

import std/[base64, json, strutils, uri]
import nimcrypto/sha2
import ../../core/pipeops

const RefreshMarginSec* = 60'i64

type
  AuthServerMeta* = object
    issuer*:                string
    authorizationEndpoint*: string
    tokenEndpoint*:         string
    registrationEndpoint*:  string
    scopes*:                seq[string]
    tokenAuthMethods*:      seq[string]  ## token_endpoint_auth_methods_supported

  ClientAuthMethod* = enum
    ## How the client authenticates at the token endpoint (RFC 6749 2.3).
    camNone  = "none"                 ## public client: PKCE only
    camBasic = "client_secret_basic"  ## HTTP Basic with id and secret
    camPost  = "client_secret_post"   ## id and secret in the form

  OAuthTokens* = object
    accessToken*:  string
    refreshToken*: string
    expiresAt*:    int64   ## unix seconds; 0 = no expiry given

func base64Url(raw: string): string =
  base64.encode(raw, safe = true).strip(leading = false, chars = {'='})

func pkceChallenge*(verifier: string): string =
  ## RFC 7636 S256: BASE64URL(SHA256(verifier)) without padding.
  var ctx: sha256
  ctx.init()
  ctx.update(verifier)
  let digest = ctx.finish()
  ctx.clear()
  var raw = newString(digest.data.len)
  for i, b in digest.data:
    raw[i] = char(b)
  base64Url(raw)

func resourceMetadataFrom*(wwwAuthenticate: string): string =
  ## `resource_metadata="…"` from a 401's `WWW-Authenticate` (RFC 9728 §5.1).
  const key = "resource_metadata=\""
  let at = wwwAuthenticate.find(key)
  if at < 0: return ""
  let start = at + key.len
  let stop = wwwAuthenticate.find('"', start)
  if stop < 0: "" else: wwwAuthenticate[start ..< stop]

func originAndPath(url: string): (string, string) =
  let u = parseUri(url)
  let origin = u.scheme & "://" & u.hostname & (if u.port.len > 0: ":" & u.port else: "")
  (origin, u.path.strip(leading = false, chars = {'/'}))

func protectedResourceMetadataUrls*(serverUrl: string): seq[string] =
  ## RFC 9728 §3: the well-known segment goes between the host and the path;
  ## the root form is the fallback.
  let (origin, path) = originAndPath(serverUrl)
  if path.len > 0:
    result.add(origin & "/.well-known/oauth-protected-resource" & path)
  result.add(origin & "/.well-known/oauth-protected-resource")

func authServerMetadataUrls*(issuer: string): seq[string] =
  ## RFC 8414 §3 and OpenID Connect discovery, in the order MCP prescribes.
  let (origin, path) = originAndPath(issuer)
  if path.len > 0:
    result.add(origin & "/.well-known/oauth-authorization-server" & path)
    result.add(origin & "/.well-known/openid-configuration" & path)
    result.add(origin & path & "/.well-known/openid-configuration")
  else:
    result.add(origin & "/.well-known/oauth-authorization-server")
    result.add(origin & "/.well-known/openid-configuration")

proc parseAuthServerMeta*(j: JsonNode): Result[AuthServerMeta, string] =
  if j.isNil or j.kind != JObject:
    return err("oauth: metadata is not an object")
  let meta = AuthServerMeta(
    issuer: j{"issuer"}.getStr(""),
    authorizationEndpoint: j{"authorization_endpoint"}.getStr(""),
    tokenEndpoint: j{"token_endpoint"}.getStr(""),
    registrationEndpoint: j{"registration_endpoint"}.getStr(""),
    tokenAuthMethods: block:
      var methods: seq[string]
      let listed = j{"token_endpoint_auth_methods_supported"}
      if not listed.isNil and listed.kind == JArray:
        for m in listed: methods.add(m.getStr)
      methods)
  if meta.authorizationEndpoint.len == 0 or meta.tokenEndpoint.len == 0:
    return err("oauth: metadata without authorization or token endpoint")
  let methods = j{"code_challenge_methods_supported"}
  if not methods.isNil and methods.kind == JArray:
    var s256 = false
    for m in methods:
      if m.getStr == "S256": s256 = true
    if not s256:
      return err("oauth: the authorization server does not support PKCE S256")
  var withScopes = meta
  let scopes = j{"scopes_supported"}
  if not scopes.isNil and scopes.kind == JArray:
    for s in scopes: withScopes.scopes.add(s.getStr)
  ok(withScopes)

func registrationBody*(redirectUri, clientName: string): JsonNode =
  ## A public client (no secret): PKCE protects the code.
  %* {"client_name": clientName, "redirect_uris": [redirectUri],
      "grant_types": ["authorization_code", "refresh_token"],
      "response_types": ["code"], "token_endpoint_auth_method": "none"}

func authorizationUrl*(meta: AuthServerMeta; clientId, redirectUri, challenge,
                       state, resource: string; scope = ""): string =
  var params = @[("response_type", "code"), ("client_id", clientId),
                 ("redirect_uri", redirectUri), ("code_challenge", challenge),
                 ("code_challenge_method", "S256"), ("state", state),
                 ("resource", resource)]
  if scope.len > 0:
    params.add(("scope", scope))
  let sep = if '?' in meta.authorizationEndpoint: "&" else: "?"
  meta.authorizationEndpoint & sep & encodeQuery(params)

func codeFromRedirect*(pasted, expectedState: string): Result[string, string] =
  ## The authorization code from the URL the browser was sent to. The state
  ## must be the one this login generated.
  let u = parseUri(pasted.strip)
  var code, state, error, description = ""
  for (key, value) in decodeQuery(u.query):
    case key
    of "code": code = value
    of "state": state = value
    of "error": error = value
    of "error_description": description = value
    else: discard
  if error.len > 0:
    return err("oauth: the server refused: " & error &
               (if description.len > 0: " (" & description & ")" else: ""))
  if state != expectedState:
    return err("oauth: the state does not match this login; paste the URL " &
               "the browser was sent to after this authorization")
  if code.len == 0:
    return err("oauth: no code in the pasted URL")
  ok(code)

func tokenRequestForm*(code, verifier, clientId, redirectUri, resource: string;
                       clientSecret = ""): string =
  ## `clientSecret` only for client_secret_post.
  var params = @[("grant_type", "authorization_code"), ("code", code),
                 ("redirect_uri", redirectUri), ("client_id", clientId),
                 ("code_verifier", verifier), ("resource", resource)]
  if clientSecret.len > 0: params.add(("client_secret", clientSecret))
  encodeQuery(params)

func refreshRequestForm*(refreshToken, clientId, resource: string;
                         clientSecret = ""): string =
  var params = @[("grant_type", "refresh_token"), ("refresh_token", refreshToken),
                 ("client_id", clientId), ("resource", resource)]
  if clientSecret.len > 0: params.add(("client_secret", clientSecret))
  encodeQuery(params)

proc parseTokenResponse*(j: JsonNode; nowSec: int64): Result[OAuthTokens, string] =
  if j.isNil or j.kind != JObject:
    return err("oauth: token response is not an object")
  if j.hasKey("error"):
    return err("oauth: " & j["error"].getStr & " " & j{"error_description"}.getStr(""))
  let access = j{"access_token"}.getStr("")
  if access.len == 0:
    return err("oauth: token response without access_token")
  let expiresIn = j{"expires_in"}.getBiggestInt(0)
  ok(OAuthTokens(accessToken: access,
                 refreshToken: j{"refresh_token"}.getStr(""),
                 expiresAt: (if expiresIn > 0: nowSec + expiresIn else: 0)))

func needsRefresh*(t: OAuthTokens; nowSec: int64): bool =
  t.expiresAt > 0 and nowSec >= t.expiresAt - RefreshMarginSec

func mergeRefreshed*(old, fresh: OAuthTokens): OAuthTokens =
  ## A refresh may or may not rotate the refresh token.
  result = fresh
  if result.refreshToken.len == 0:
    result.refreshToken = old.refreshToken

func clientAuthMethodFor*(meta: AuthServerMeta; hasSecret: bool): Result[ClientAuthMethod, string] =
  ## A pre-registered client with a secret authenticates as the server
  ## allows: client_secret_basic when listed or when nothing is listed (RFC
  ## 8414's default), else client_secret_post. Without a secret: public.
  if not hasSecret:
    return ok(camNone)
  if meta.tokenAuthMethods.len == 0 or $camBasic in meta.tokenAuthMethods:
    return ok(camBasic)
  if $camPost in meta.tokenAuthMethods:
    return ok(camPost)
  err("oauth: the token endpoint takes none of client_secret_basic, " &
      "client_secret_post (it lists " & meta.tokenAuthMethods.join(", ") & ")")

func basicClientAuth*(clientId, secret: string): string =
  ## RFC 6749 2.3.1: each part form-encoded, then Basic.
  "Basic " & base64.encode(encodeUrl(clientId, usePlus = true) & ":" &
                           encodeUrl(secret, usePlus = true))
