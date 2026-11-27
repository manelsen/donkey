## ntfy as a channel (E13.1): HTTP publish and poll on a topic, pure halves.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/ntfy_pure

proc runTests*() =
  suite "ntfy":
    test "a topic is a plain name; the URLs to publish and to poll":
      check validNtfyTopic("donkey-ana_7x")
      check not validNtfyTopic("") and not validNtfyTopic("a/b") and not validNtfyTopic("a b")
      check not validNtfyTopic("x".repeat(65))
      check publishUrl("https://ntfy.sh/", "t") == "https://ntfy.sh/t"
      check pollUrl("https://ntfy.sh", "t", "abc123") == "https://ntfy.sh/t/json?poll=1&since=abc123"
      check pollUrl("https://ntfy.sh", "t", "") == "https://ntfy.sh/t/json?poll=1&since=10s"

    test "polled lines: messages in, Donkey's own and other events out":
      let body = """{"id":"k1","time":1,"event":"open","topic":"t"}
{"id":"m1","time":2,"event":"message","topic":"t","message":"oi"}
{"id":"m2","time":3,"event":"message","topic":"t","message":"resposta","tags":["donkey"]}
{"id":"m3","time":4,"event":"keepalive","topic":"t"}
not json
{"id":"m4","time":5,"event":"message","topic":"t","title":"T","message":"tudo bem?"}
"""
      let got = parseNtfyLines(body)
      check got.len == 2
      check got[0] == NtfyMessage(id: "m1", text: "oi")
      check got[1] == NtfyMessage(id: "m4", text: "tudo bem?")
      check lastNtfyId(body) == "m4"   ## the next poll starts after every line seen
      check lastNtfyId("") == ""

    test "publishing: Donkey's tag, a title, markdown, the token when there is one":
      check publishHeaders("") == @[("Title", "Donkey"), ("Tags", "donkey"), ("Markdown", "yes")]
      check ("Authorization", "Bearer tk_x") in publishHeaders("tk_x")

    test "a long answer goes in pieces ntfy accepts":
      let pieces = ntfyPieces("a".repeat(NtfyMaxMessageBytes * 2 + 10))
      check pieces.len == 3
      for p in pieces: check p.len <= NtfyMaxMessageBytes
      check ntfyPieces("").len == 0

when isMainModule:
  runTests()
