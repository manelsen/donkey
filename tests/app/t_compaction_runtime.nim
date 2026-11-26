## Compaction (E8.5), the shell: the model's context window from the catalog,
## and the session's own model writing the summary.

import std/[strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/domain/message
import donkey/app/compaction
import donkey/app/provider_executor

proc turns(n: int): ConversationHistory =
  var h = newHistory()
  for i in 0 ..< n:
    h.addUser("pergunta " & $i & " " & "x".repeat(400))
    h.addAssistant("resposta " & $i & " " & "y".repeat(400))
  h

proc summarizer(text: string): AsyncCompleteFn =
  result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
    return ok(CompletionResponse(text: text))

proc failing(): AsyncCompleteFn =
  result = proc(req: CompletionRequest): Future[Result[CompletionResponse, string]] {.async.} =
    return err(Result[CompletionResponse, string], "boom")

proc runTests*() =
  suite "compaction runtime":
    test "the context window of a known model, by name or by route label":
      check contextWindowOf("anthropic/claude-opus-5-5") == 1_000_000
      check contextWindowOf("openrouter/anthropic/claude-opus-5-5") == 1_000_000
      check contextWindowOf("auto") == 0
      check contextWindowOf("") == 0

    test "the old part becomes the model's summary, the tail stays":
      let h = turns(40)
      let r = waitFor compactHistory(summarizer("Decidimos usar Nim."), h, keepTokens = 1000)
      check r.isOk
      check r.get.len < h.len
      check "Decidimos usar Nim." in r.get[0].text and r.get[0].seq == SyntheticMessageSeq
      check r.get[^1] == h[^1]

    test "a failed or empty summary leaves the history as it was":
      let h = turns(40)
      check waitFor(compactHistory(failing(), h, keepTokens = 1000)).isErr
      check waitFor(compactHistory(summarizer("  "), h, keepTokens = 1000)).isErr

    test "nothing old to summarize is an error, not a call":
      check waitFor(compactHistory(failing(), turns(1), keepTokens = 100_000)).error.contains("nothing")

when isMainModule:
  runTests()
