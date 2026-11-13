## web_tools.nim — HTTP fetch and Brave web search.
##
## performFetch retrieves and sanitises text from public URLs.
## performWebSearch queries the Brave Search API.

import std/[json, math, strutils, uri]
import results
import ../../config/types as cfgTypes
import ../../ports/http as httpPort
import ../../domain/builtin_tools
import ../../core/dns
import ../../core/tooling/structured_tool_result
import ./text_tools  # stripHtml

# ── fetch ─────────────────────────────────────────────────────────────────────

const FetchHardMax* = 20_000
const FetchDefaultMax* = 5_000
const MaxFetchRedirects = 5

func responseHeader(resp: httpPort.HttpResponse; name: string): string =
  for (key, value) in resp.headers:
    if key.toLowerAscii() == name.toLowerAscii():
      return value

proc fetchWithRedirectPolicy(http: httpPort.HttpRuntimePort;
                             url: string;
                             headers: seq[httpPort.HttpHeader];
                             allowRules: seq[cfgTypes.WebAccessRule];
                             fallbackAllowlist: seq[string];
                             policyLabel: string): Result[httpPort.HttpResponse, string] {.gcsafe.} =
  ## Follows redirects manually so every hop is checked by the URL/DNS policy.
  ## Ports without getNoRedirect are rejected: following redirects inside the
  ## transport would bypass the per-hop policy.
  ##
  ## DNS is validated here, but std/httpclient resolves again when dialing.
  ## Full connection pinning against DNS rebinding requires the filtering
  ## egress proxy (DONKEY_WEB_PROXY) or a firewall.
  if http.getNoRedirect == nil:
    return err("redirect-safe fetch unavailable: port lacks getNoRedirect")
  var current = url
  for _ in 0 .. MaxFetchRedirects:
    if not isAllowedPublicUrl(current, allowRules, fallbackAllowlist):
      return err(buildUrlAccessError(current, allowRules, fallbackAllowlist, policyLabel))
    let host = extractUrlHost(current)
    if host.len == 0:
      return err("invalid URL: " & current)
    if http.resolveHost != nil:
      let resolved = http.resolveHost(host)
      if resolved.isErr:
        return err("URL blocked: " & resolved.error)
      let checked = blockIfPrivate(resolved.get())
      if checked.isErr:
        return err("URL blocked: " & checked.error)
    let resp = http.getNoRedirect(current, headers)
    if resp.isErr:
      return resp
    let r = resp.get()
    if r.status in 300 .. 399:
      let location = responseHeader(r, "location")
      if location.len > 0:
        let nextUrl = $combine(parseUri(current), parseUri(location))
        if nextUrl == current:
          return err("redirect loop at " & current)
        current = nextUrl
        continue
    return ok(r)
  err("too many redirects (max " & $MaxFetchRedirects & ")")

proc performFetch*(http: httpPort.HttpRuntimePort;
                   url: string;
                   maxCh: int;
                   allowRules: seq[cfgTypes.WebAccessRule] = @[];
                   fallbackAllowlist: seq[string] = @[];
                   policyLabel = "web access"): string {.gcsafe, raises: [].} =
  try:
    let resp = fetchWithRedirectPolicy(http, url, @[], allowRules,
                                       fallbackAllowlist, policyLabel)
    if resp.isErr: return "Error: " & resp.error
    let r = resp.value
    if r.status < 200 or r.status >= 300:
      return "HTTP error " & $r.status
    let cap  = min(maxCh, FetchHardMax)
    var body = r.body.strip()
    if body.startsWith("{") or body.startsWith("["):
      try:
        let jj = parseJson(body)
        body = jj.pretty()
      except CatchableError: discard
    elif body.startsWith("<"):
      body = stripHtml(body)
    truncateBody(body, cap)
  except Exception as e:
    "Error: " & e.msg

proc performFetchStructured*(http: httpPort.HttpRuntimePort;
                             url: string;
                             expect = "text";
                             maxCh = FetchDefaultMax;
                             allowRules: seq[cfgTypes.WebAccessRule] = @[];
                             fallbackAllowlist: seq[string] = @[];
                             policyLabel = "web access"): StructuredToolResult {.gcsafe, raises: [].} =
  if url.strip().len == 0:
    return usageErrorToolResult("url is required")

  let normalizedExpect = expect.strip().toLowerAscii()
  if normalizedExpect notin ["text", "json"]:
    return usageErrorToolResult("unsupported expect format: " & expect)

  try:
    let r = fetchWithRedirectPolicy(http, url, @[], allowRules,
                                    fallbackAllowlist, policyLabel).valueOr:
      return operationalErrorToolResult(error)
    if r.status < 200 or r.status >= 300:
      return operationalErrorToolResult("HTTP error " & $r.status)

    var data = %*{
      "url": url,
      "status": r.status,
      "headers": [],
      "body_format": normalizedExpect,
    }

    if normalizedExpect == "json":
      try:
        data["body"] = parseJson(r.body)
      except CatchableError:
        return operationalErrorToolResult("response was not valid JSON")
    else:
      let cap = min(maxCh, FetchHardMax)
      var body = r.body.strip()
      if body.startsWith("<"):
        body = stripHtml(body)
      data["body"] = %truncateBody(body, cap)

    successToolResult(data)
  except Exception as e:
    operationalErrorToolResult(e.msg)

# ── web_search (Brave) ────────────────────────────────────────────────────────

const BraveSearchUrl = "https://api.search.brave.com/res/v1/web/search"

proc performWebSearch*(query: string; count: int;
                       apiKey: string;
                       http: httpPort.HttpRuntimePort;
                       allowRules: seq[cfgTypes.WebAccessRule] = @[];
                       fallbackAllowlist: seq[string] = @[]): string {.gcsafe, raises: [].} =
  if apiKey.len == 0:
    return "Error: BRAVE_API_KEY not configured. Set the environment variable."
  try:
    let url     = BraveSearchUrl & "?q=" & encodeUrl(query) & "&count=" & $min(count, 20)
    if not isAllowedPublicUrl(url, allowRules, fallbackAllowlist):
      return buildUrlAccessError(url, allowRules, fallbackAllowlist, "web_search")
    let headers = @[
      ("X-Subscription-Token", apiKey),
      ("Accept",               "application/json"),
    ]
    var resp: Result[HttpResponse, string]
    try: resp = http.get(url, headers)
    except Exception as e: return "Error: " & e.msg
    if resp.isErr: return "Error: " & resp.error
    if resp.value.status != 200:
      return "Brave API error " & $resp.value.status
    let j = parseJson(resp.value.body)
    let webResults = j.getOrDefault("web").getOrDefault("results")
    if webResults.kind != JArray or webResults.len == 0:
      return "(no results)"
    var lines: seq[string] = @[]
    for item in webResults:
      let title = item.getOrDefault("title").getStr("(no title)")
      let url2  = item.getOrDefault("url").getStr("")
      let desc  = item.getOrDefault("description").getStr("")
      lines.add(title & "\n" & url2 & "\n" & desc)
    lines.join("\n\n")
  except CatchableError as e:
    "Error: " & e.msg
