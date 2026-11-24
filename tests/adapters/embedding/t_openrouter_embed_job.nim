## The embedding job that runs on a worker thread: its input and the vector
## it sends back as text.

import std/[json, unittest]
import donkey/adapters/embedding/openrouter_embed
import donkey/core/pipeops

proc runTests*() =
  suite "openrouter embedding job":

    test "a vector crosses the thread boundary as text and back":
      let v = @[0.25'f32, -1.5'f32, 3.0'f32]
      let back = decodeEmbedding(encodeEmbedding(v))
      check back.isOk
      check back.get == v
      check decodeEmbedding("not json").isErr
      check decodeEmbedding("""{"a":1}""").isErr
      ## A non-numeric element is no vector, not a zero: recall then falls
      ## back to literal terms instead of comparing against zeros.
      check decodeEmbedding("""[0.5, "x", 1]""").isErr
      check decodeEmbedding("""[0.5, null]""").isErr
      check decodeEmbedding("""[1, 2]""").get == @[1.0'f32, 2.0'f32]

    test "a job without a key or text is refused before any request":
      check openRouterEmbedJob("not json").isErr
      check openRouterEmbedJob($(%*{"key": "", "text": "oi"})).isErr
      check openRouterEmbedJob($(%*{"key": "k", "text": "  "})).isErr

when isMainModule:
  runTests()
