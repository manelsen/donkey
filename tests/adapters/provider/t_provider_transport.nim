## Every provider adapter sends through `HttpRuntimePort`, never through a
## raw `std/httpclient` with no timeout. The production transport has a
## deadline, does not follow redirects (the API key must not reach another
## host) and does not repeat a POST (a retried completion is paid twice).

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/http
import donkey/ports/provider
import donkey/adapters/http/std_http
import donkey/adapters/provider/provider_http
import donkey/adapters/provider/anthropic
import donkey/adapters/provider/deepseek
import donkey/adapters/provider/gemini
import donkey/adapters/provider/minimax
import donkey/adapters/provider/ollama
import donkey/adapters/provider/openai
import donkey/adapters/provider/openrouter
import donkey/adapters/provider/zhipu

type Recorder = ref object
  urls: seq[string]
  headers: seq[seq[HttpHeader]]
  status: int
  body: string

proc port(r: Recorder): HttpRuntimePort =
  HttpRuntimePort(
    postNoRedirect: proc(url, body: string; headers: seq[HttpHeader] = @[]):
                    Result[HttpResponse, string] {.gcsafe.} =
      {.cast(gcsafe).}:
        r.urls.add(url)
        r.headers.add(headers)
        ok(HttpResponse(status: r.status, body: r.body)))

proc request(): CompletionRequest =
  var history = newHistory()
  history.addUser("hi")
  buildPrompt("system", history, "")

proc noop(tok: string) {.gcsafe.} = discard

proc failing(): Recorder = Recorder(status: 500, body: "{\"error\":\"boom\"}")

proc hasHeader(r: Recorder; name: string): bool =
  for (k, v) in r.headers[0]:
    if k.toLowerAscii == name.toLowerAscii: return true
  false

proc runTests*() =
  suite "provider transport":
    test "the production transport has a deadline and does not repeat a POST":
      let a = providerHttpAdapter()
      check a.timeout == ProviderHttpTimeoutSec
      check ProviderHttpTimeoutSec > 0
      check not a.retryNonIdempotent
      check a.circuitBreaker
      check a.returnServerError

    test "OpenRouter complete and stream go through the port":
      let r = failing()
      var a = newOpenRouterAdapter("k")
      a.http = r.port
      let res = a.complete(request())
      check res.isErr
      check "OpenRouter API error 500 Internal Server Error" in res.error
      check a.makeStreamFn()(request(), noop).isErr
      check r.urls.len == 2
      check r.hasHeader("Authorization")

    test "Anthropic complete and stream go through the port":
      let r = failing()
      var a = newAnthropicAdapter("k")
      a.http = r.port
      check "Anthropic API error 500" in a.complete(request()).error
      check a.makeStreamFn()(request(), noop).isErr
      check r.urls.len == 2
      check r.hasHeader("x-api-key")

    test "OpenAI complete and stream go through the port":
      let r = failing()
      var a = newOpenAIAdapter("k")
      a.http = r.port
      check "API error 500" in a.complete(request()).error
      check a.makeStreamFn()(request(), noop).isErr
      check r.urls.len == 2

    test "DeepSeek complete and stream go through the port":
      let r = failing()
      var a = newDeepSeekAdapter("k")
      a.http = r.port
      check "DeepSeek API error 500" in a.complete(request()).error
      check a.makeStreamFn()(request(), noop).isErr
      check r.urls.len == 2

    test "Ollama complete and stream go through the port":
      let r = failing()
      var a = newOllamaAdapter()
      a.http = r.port
      check "Ollama API error 500" in a.complete(request()).error
      check a.makeStreamFn()(request(), noop).isErr
      check r.urls.len == 2
      check r.urls[0].endsWith("/api/chat")

    test "Gemini, MiniMax and Zhipu complete go through the port":
      let r = failing()
      var g = newGeminiAdapter("k")
      g.http = r.port
      check "Gemini API error 500" in g.complete(request()).error
      var m = newMiniMaxAdapter("k")
      m.http = r.port
      check "MiniMax API error 500" in m.complete(request()).error
      var z = newZhipuAdapter("k")
      z.http = r.port
      check "Zhipu API error 500" in z.complete(request()).error
      check r.urls.len == 3

    test "a 2xx stream body is parsed from the port response":
      let r = Recorder(status: 200, body:
        "data: {\"choices\":[{\"delta\":{\"content\":\"po\"}}]}\n" &
        "data: {\"choices\":[{\"delta\":{\"content\":\"ng\"}}]}\n" &
        "data: [DONE]\n")
      var a = newOpenRouterAdapter("k")
      a.http = r.port
      var tokens: seq[string]
      let res = a.makeStreamFn()(request(), proc(tok: string) {.gcsafe.} =
        {.cast(gcsafe).}: tokens.add(tok))
      check res.isOk
      check res.get.text == "pong"
      check tokens == @["po", "ng"]

    test "no adapter keeps the untimed std/httpclient template":
      for kind, path in walkDir("src/donkey/adapters/provider"):
        if path.endsWith(".nim"):
          let source = readFile(path)
          check "withHttpClient:" notin source
          check "newHttpClient(" notin source

    test "no HTTP client in src is built without a timeout":
      for path in walkDirRec("src"):
        if path.endsWith(".nim"):
          if "newHttpClient()" in readFile(path):
            checkpoint(path)
            fail()

when isMainModule:
  runTests()
