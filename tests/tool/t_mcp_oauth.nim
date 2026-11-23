## MCP authorization (MCP spec 2025-06-18, "Authorization"): OAuth 2.1 with
## PKCE, protected-resource metadata (RFC 9728), authorization-server metadata
## (RFC 8414), dynamic client registration (RFC 7591) and resource indicators
## (RFC 8707). The PKCE value is RFC 7636's own example (Appendix B).

import std/[json, os, posix, sequtils, strutils, unittest, uri]
import donkey/adapters/tool/mcp_http_client
import donkey/adapters/tool/mcp_oauth
import donkey/core/pipeops
import donkey/domain/tools/mcp_oauth_pure
import donkey/ports/http
import donkey/ports/tool

const
  Server = "https://mcp.example.test/mcp"
  Redirect = "http://127.0.0.1:8976/callback"
  StoreDir = "/tmp/donkey_t_mcp_oauth"

type FakeAuth = ref object
  posts: seq[(string, string, seq[HttpHeader])]
  gets:  seq[string]
  tokenCalls: int
  mcpAuthorized: string   ## the bearer the MCP endpoint accepts

func header(headers: seq[HttpHeader]; name: string): string =
  for h in headers:
    if h.name.toLowerAscii == name.toLowerAscii: return h.value

proc fakePort(f: FakeAuth): HttpRuntimePort =
  let get = proc (url: string; headers: seq[HttpHeader] = @[]):
               Result[HttpResponse, string] {.gcsafe.} =
    f.gets.add(url)
    if url == "https://mcp.example.test/.well-known/oauth-protected-resource/mcp":
      return ok(HttpResponse(status: 200, body: $(%* {
        "resource": Server, "authorization_servers": ["https://auth.example.test"]})))
    if url == "https://auth.example.test/.well-known/oauth-authorization-server":
      return ok(HttpResponse(status: 200, body: $(%* {
        "issuer": "https://auth.example.test",
        "authorization_endpoint": "https://auth.example.test/authorize",
        "token_endpoint": "https://auth.example.test/token",
        "registration_endpoint": "https://auth.example.test/register",
        "code_challenge_methods_supported": ["S256"]})))
    ok(HttpResponse(status: 404, body: ""))
  let post = proc (url, body: string; headers: seq[HttpHeader] = @[]):
                Result[HttpResponse, string] {.gcsafe.} =
    f.posts.add((url, body, headers))
    if url == Server:
      if f.mcpAuthorized.len > 0 and header(headers, "Authorization") == "Bearer " & f.mcpAuthorized:
        let id = parseJson(body){"id"}
        if id.isNil:
          return ok(HttpResponse(status: 202, body: ""))
        let res = if parseJson(body)["method"].getStr == "tools/list": %* {"tools": []}
                  else: %* {"protocolVersion": "2025-06-18", "capabilities": {}}
        return ok(HttpResponse(status: 200, body: $(%* {"jsonrpc": "2.0", "id": id, "result": res}),
          headers: @[(name: "Content-Type", value: "application/json")]))
      return ok(HttpResponse(status: 401, body: "", headers: @[(name: "WWW-Authenticate",
        value: "Bearer resource_metadata=\"https://mcp.example.test/.well-known/oauth-protected-resource/mcp\"")]))
    if url == "https://auth.example.test/register":
      return ok(HttpResponse(status: 201, body: $(%* {"client_id": "cid-1"})))
    if url == "https://auth.example.test/token":
      inc f.tokenCalls
      let form = body
      if "grant_type=refresh_token" in form:
        f.mcpAuthorized = "at-" & $f.tokenCalls
        return ok(HttpResponse(status: 200, body: $(%* {
          "access_token": f.mcpAuthorized, "expires_in": 3600})))
      f.mcpAuthorized = "at-1"
      return ok(HttpResponse(status: 200, body: $(%* {
        "access_token": "at-1", "refresh_token": "rt-1", "expires_in": 3600})))
    ok(HttpResponse(status: 404, body: ""))
  HttpRuntimePort(get: get, getNoRedirect: get, post: post, postNoRedirect: post)

proc runTests*() =
  suite "mcp_oauth_pure — PKCE and URLs":
    test "the S256 challenge of RFC 7636's example verifier":
      check pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") ==
        "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    test "the resource metadata URL from a 401's WWW-Authenticate":
      check resourceMetadataFrom(
        """Bearer realm="mcp", resource_metadata="https://mcp.example.test/.well-known/oauth-protected-resource"""") ==
        "https://mcp.example.test/.well-known/oauth-protected-resource"
      check resourceMetadataFrom("Bearer realm=\"x\"") == ""

    test "well-known URLs keep the path after the well-known segment":
      check protectedResourceMetadataUrls("https://h.test/v1/mcp") == @[
        "https://h.test/.well-known/oauth-protected-resource/v1/mcp",
        "https://h.test/.well-known/oauth-protected-resource"]
      check authServerMetadataUrls("https://auth.test/tenant") == @[
        "https://auth.test/.well-known/oauth-authorization-server/tenant",
        "https://auth.test/.well-known/openid-configuration/tenant",
        "https://auth.test/tenant/.well-known/openid-configuration"]
      check authServerMetadataUrls("https://auth.test") == @[
        "https://auth.test/.well-known/oauth-authorization-server",
        "https://auth.test/.well-known/openid-configuration"]

    test "the authorization URL carries PKCE, state and the resource":
      let meta = AuthServerMeta(authorizationEndpoint: "https://auth.test/authorize",
                                tokenEndpoint: "https://auth.test/token")
      let url = parseUri(authorizationUrl(meta, clientId = "cid",
        redirectUri = "http://127.0.0.1:8976/callback", challenge = "CH",
        state = "ST", resource = "https://h.test/mcp", scope = "read"))
      check url.hostname == "auth.test" and url.path == "/authorize"
      var params: seq[(string, string)]
      for kv in decodeQuery(url.query): params.add(kv)
      check ("response_type", "code") in params
      check ("client_id", "cid") in params
      check ("code_challenge", "CH") in params
      check ("code_challenge_method", "S256") in params
      check ("state", "ST") in params
      check ("resource", "https://h.test/mcp") in params
      check ("redirect_uri", "http://127.0.0.1:8976/callback") in params
      check ("scope", "read") in params

  suite "mcp_oauth_pure — the pasted redirect":
    test "the code comes from the pasted URL when the state matches":
      check codeFromRedirect("http://127.0.0.1:8976/callback?code=abc&state=ST", "ST").get == "abc"

    test "a different state is refused (another login, or a forged link)":
      check codeFromRedirect("http://127.0.0.1:8976/callback?code=abc&state=XX", "ST").isErr

    test "an error from the server is reported":
      let r = codeFromRedirect("http://127.0.0.1:8976/callback?error=access_denied&state=ST", "ST")
      check r.isErr and "access_denied" in r.error

    test "a bare code is not accepted without its state":
      check codeFromRedirect("abc", "ST").isErr

  suite "mcp_oauth_pure — metadata and tokens":
    test "authorization-server metadata":
      let meta = parseAuthServerMeta(%* {
        "issuer": "https://auth.test", "authorization_endpoint": "https://auth.test/a",
        "token_endpoint": "https://auth.test/t", "registration_endpoint": "https://auth.test/r",
        "code_challenge_methods_supported": ["S256"]})
      check meta.isOk
      check meta.get.registrationEndpoint == "https://auth.test/r"

    test "metadata without PKCE S256 is refused":
      check parseAuthServerMeta(%* {"authorization_endpoint": "a", "token_endpoint": "t",
        "code_challenge_methods_supported": ["plain"]}).isErr

    test "the token response and its expiry":
      let t = parseTokenResponse(%* {"access_token": "at", "refresh_token": "rt",
                                     "expires_in": 3600, "token_type": "Bearer"}, nowSec = 1000)
      check t.isOk
      check t.get.accessToken == "at" and t.get.refreshToken == "rt"
      check t.get.expiresAt == 4600
      check not needsRefresh(t.get, nowSec = 4000)
      check needsRefresh(t.get, nowSec = 4550)   ## inside the 60 s margin

    test "a token without expiry never needs a refresh":
      let t = parseTokenResponse(%* {"access_token": "at"}, nowSec = 1000).get
      check t.expiresAt == 0 and not needsRefresh(t, nowSec = 99999999)

    test "a refresh that returns no new refresh token keeps the old one":
      let old = OAuthTokens(accessToken: "a1", refreshToken: "r1", expiresAt: 1)
      let fresh = parseTokenResponse(%* {"access_token": "a2", "expires_in": 60}, nowSec = 10).get
      check mergeRefreshed(old, fresh).refreshToken == "r1"
      check mergeRefreshed(old, fresh).accessToken == "a2"

    test "form bodies are URL-encoded":
      let form = tokenRequestForm(code = "c d", verifier = "v", clientId = "cid",
        redirectUri = "http://127.0.0.1:8976/callback", resource = "https://h.test/mcp")
      check "grant_type=authorization_code" in form
      check "code=c+d" in form or "code=c%20d" in form
      check "code_verifier=v" in form
      check "resource=https%3A%2F%2Fh.test%2Fmcp" in form
      let refresh = refreshRequestForm("rt", "cid", "https://h.test/mcp")
      check "grant_type=refresh_token" in refresh and "refresh_token=rt" in refresh

  suite "mcp oauth — the login flow and the token source":
    test "discovery from the 401, registration, the URL, the code exchange":
      removeDir(StoreDir)
      let f = FakeAuth()
      let pending = beginMcpLogin(Server, Redirect, fakePort(f))
      check pending.isOk
      let p = pending.get
      check p.clientId == "cid-1"
      let auth = parseUri(p.authorizationUrl)
      check auth.hostname == "auth.example.test"
      check ("code_challenge", pkceChallenge(p.verifier)) in toSeq(decodeQuery(auth.query))
      check ("resource", Server) in toSeq(decodeQuery(auth.query))
      ## registration names a public client and our redirect
      let reg = parseJson(f.posts[1][1])
      check reg["redirect_uris"] == %* [Redirect]
      check reg["token_endpoint_auth_method"].getStr == "none"

      let rec = completeMcpLogin(p, Redirect & "?code=the-code&state=" & p.state,
                                 fakePort(f), nowSec = 1000)
      check rec.isOk
      check rec.get.tokens.accessToken == "at-1"
      let exchange = f.posts[^1][1]
      check "code=the-code" in exchange
      check "code_verifier=" & p.verifier in exchange

    test "a pasted URL from another login is refused before any token request":
      let f = FakeAuth()
      let p = beginMcpLogin(Server, Redirect, fakePort(f)).get
      let calls = f.tokenCalls
      check completeMcpLogin(p, Redirect & "?code=x&state=other", fakePort(f), 1000).isErr
      check f.tokenCalls == calls

    test "the record is stored privately and read back":
      removeDir(StoreDir)
      let rec = McpOAuthRecord(serverUrl: Server, clientId: "cid", resource: Server,
        tokenEndpoint: "https://auth.example.test/token",
        tokens: OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: 5))
      check saveMcpOAuth(StoreDir, rec).isOk
      let path = mcpOAuthPath(StoreDir, Server)
      var st: Stat
      check stat(path.cstring, st) == 0
      check (st.st_mode.int and 0o777) == 0o600
      let back = loadMcpOAuth(StoreDir, Server)
      check back.isOk and back.get.tokens.refreshToken == "r"

    test "the token source refreshes an expired token and stores it":
      removeDir(StoreDir)
      let f = FakeAuth()
      discard saveMcpOAuth(StoreDir, McpOAuthRecord(serverUrl: Server, clientId: "cid",
        resource: Server, tokenEndpoint: "https://auth.example.test/token",
        tokens: OAuthTokens(accessToken: "old", refreshToken: "rt-1", expiresAt: 10)))
      let source = mcpTokenSource(StoreDir, Server, fakePort(f), clock = proc(): int64 = 1000)
      let tok = source(false)
      check tok.isOk and tok.get.startsWith("at-")
      check loadMcpOAuth(StoreDir, Server).get.tokens.accessToken == tok.get
      check loadMcpOAuth(StoreDir, Server).get.tokens.refreshToken == "rt-1"

    test "a valid token is used without a refresh":
      removeDir(StoreDir)
      let f = FakeAuth()
      discard saveMcpOAuth(StoreDir, McpOAuthRecord(serverUrl: Server, clientId: "cid",
        resource: Server, tokenEndpoint: "https://auth.example.test/token",
        tokens: OAuthTokens(accessToken: "good", refreshToken: "rt", expiresAt: 99999)))
      let source = mcpTokenSource(StoreDir, Server, fakePort(f), clock = proc(): int64 = 1000)
      check source(false).get == "good"
      check f.tokenCalls == 0

    test "the MCP client refreshes once when the server answers 401":
      removeDir(StoreDir)
      let f = FakeAuth(mcpAuthorized: "")
      discard saveMcpOAuth(StoreDir, McpOAuthRecord(serverUrl: Server, clientId: "cid",
        resource: Server, tokenEndpoint: "https://auth.example.test/token",
        tokens: OAuthTokens(accessToken: "revoked", refreshToken: "rt", expiresAt: 99999)))
      var c = newMcpHttpClient(Server, http = fakePort(f),
        tokenFn = mcpTokenSource(StoreDir, Server, fakePort(f), clock = proc(): int64 = 1000))
      let tools = c.listTools()
      check tools.isOk
      check f.tokenCalls == 1

    test "without a stored login the token source says to log in":
      removeDir(StoreDir)
      let source = mcpTokenSource(StoreDir, Server, fakePort(FakeAuth()))
      let r = source(false)
      check r.isErr and "ctl mcp login" in r.error

when isMainModule:
  runTests()
