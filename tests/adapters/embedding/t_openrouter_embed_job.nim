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

    test "a job without a key or text is refused before any request":
      check openRouterEmbedJob("not json").isErr
      check openRouterEmbedJob($(%*{"key": "", "text": "oi"})).isErr
      check openRouterEmbedJob($(%*{"key": "k", "text": "  "})).isErr

when isMainModule:
  runTests()
