## Routing cost of inline images (Ferramentas US-001).

import std/[strutils, unittest]
import donkey/core/providers/smart_routing
import donkey/domain/message

func turn(text, imageUrl: string): ChatMessage =
  ChatMessage(role: roleUser, text: text, imageUrl: imageUrl)

proc runTests*() =
  suite "inline image routing cost":

    test "a large data URL costs a constant, not its size":
      let big = "data:image/png;base64," & repeat("A", 200_000)
      let req = CompletionRequest(messages: @[turn("o que é?", big)])
      check requestApproxChars(req) < LongContextChars

    test "three large images stay below the long-context threshold":
      let big = "data:image/jpeg;base64," & repeat("B", 200_000)
      let req = CompletionRequest(messages: @[
        turn("a", big), turn("b", big), turn("c", big)])
      check requestApproxChars(req) < LongContextChars

    test "long text still crosses the long-context threshold":
      let req = CompletionRequest(messages: @[
        turn(repeat("x", LongContextChars + 1), "")])
      check requestApproxChars(req) >= LongContextChars

    test "an http image still counts its URL length":
      let url = "https://example.test/" & repeat("a", 500)
      let req = CompletionRequest(messages: @[turn("a", url)])
      check requestApproxChars(req) >= url.len

when isMainModule:
  runTests()
