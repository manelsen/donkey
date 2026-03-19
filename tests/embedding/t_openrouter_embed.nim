## OpenRouterEmbeddingAdapter unit tests.
## HTTP calls are not made; tests cover concept conformance and construction.

import std/unittest
import donkey/adapters/embedding/openrouter_embed
import donkey/ports/embedding

proc verifyEmbeddingPort[T: EmbeddingPort](e: T) {.used.} = discard

suite "newOpenRouterEmbeddingAdapter":

  test "default model is set":
    let a = newOpenRouterEmbeddingAdapter("key")
    check a.model == DefaultEmbedModel

  test "custom model is used":
    let a = newOpenRouterEmbeddingAdapter("key", model = "text-embedding-3-small")
    check a.model == "text-embedding-3-small"

  test "api key is stored":
    let a = newOpenRouterEmbeddingAdapter("my-secret-key")
    check a.apiKey == "my-secret-key"

suite "OpenRouterEmbeddingAdapter satisfies EmbeddingPort concept":

  test "compile-time concept check passes":
    let a = newOpenRouterEmbeddingAdapter("tok")
    verifyEmbeddingPort(a)
    check true
