## Inline image policy tests (Ferramentas US-001).

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/domain/providers/profile_alibaba
import donkey/domain/providers/profile_fireworks
import donkey/domain/providers/profile_nvidia

func bytes(data: string): seq[byte] =
  for ch in data:
    result.add(byte(ord(ch)))

proc runTests*() =
  suite "imageDataUrl":

    test "builds a supported data URL":
      let res = imageDataUrl("image/png", bytes("abc"))
      check res.isOk
      check res.get().startsWith("data:image/png;base64,")

    test "rejects an unsupported media type":
      check imageDataUrl("image/svg+xml", bytes("<svg/>")).isErr

    test "rejects empty bytes":
      check imageDataUrl("image/png", newSeq[byte]()).isErr

    test "accepts exactly the encoded limit and rejects one byte past":
      ## "abc" -> 4 base64 chars. The limit includes the data URL prefix.
      let prefix = "data:image/png;base64,".len
      let exact = prefix + 4
      check imageDataUrl("image/png", bytes("abc"),
                         maxEncodedBytes = exact).isOk
      check imageDataUrl("image/png", bytes("abc"),
                         maxEncodedBytes = exact - 1).isErr

  suite "inlineImagesForTurn":

    test "caps only data URLs and preserves order":
      var urls: seq[string] = @[]
      for i in 0 ..< 6:
        urls.add("data:image/png;base64,AAAA" & $i)
      urls.add("https://example.test/a.png")
      urls.add("attachments/b.jpg")
      let kept = inlineImagesForTurn(urls)
      check kept.len == 6  # 4 data + 2 non-data
      check kept[0] == urls[0]
      check kept[3] == urls[3]
      check kept[4] == urls[6]
      check kept[5] == urls[7]

    test "25 http or path entries pass through untouched":
      var urls: seq[string] = @[]
      for i in 0 ..< 25:
        urls.add("photo-" & $i & ".jpg")
      check inlineImagesForTurn(urls) == urls

    test "no data URLs is the identity":
      let urls = @["a.png", "https://x/y.png"]
      check inlineImagesForTurn(urls) == urls

    test "an empty list stays empty":
      check inlineImagesForTurn(@[]).len == 0

  suite "vision support by provider and model (review E3)":
    ## Three states: only a model known to lack vision loses its inline images
    ## before the call. "Not verified" is unknown, not no: the image is sent and
    ## a refusal falls back to the turn's single text retry.

    test "families known to read images":
      check visionSupport("anthropic", "claude-sonnet-5-5") == vsYes
      check visionSupport("gemini", "gemini-3.8-flash") == vsYes
      check visionSupport("nvidia", "any-model") == vsYes
      check visionSupport("nvidia-nim", "any-model") == vsYes

    test "models known to be text only":
      check visionSupport("deepseek", "deepseek-chat") == vsNo
      check visionSupport("deepseek", "deepseek-reasoner") == vsNo
      check visionSupport("zai-coding", "glm-4.7") == vsNo
      check visionSupport("zai", "glm-4.6") == vsNo

    test "the vision variants of a text family":
      check visionSupport("zai", "glm-4.5v") == vsYes
      check visionSupport("zai", "glm-4v-plus") == vsYes
      check visionSupport("alibaba", "qwen-vl-max") == vsYes
      check visionSupport("dashscope", "qwen2.5-vl-72b-instruct") == vsYes
      check visionSupport("alibaba", "qvq-max") == vsYes

    test "anything not verified is unknown, not no":
      check visionSupport("alibaba", "qwen3.8-max") == vsUnknown
      check visionSupport("fireworks", "any-model") == vsUnknown
      check visionSupport("deepseek", "deepseek-4.1-flash") == vsUnknown
      check visionSupport("openrouter", "deepseek/deepseek-v4.1-flash") == vsUnknown
      check visionSupport("openai", "gpt-5") == vsUnknown
      check visionSupport("does-not-exist", "") == vsUnknown

    test "only a known text-only model loses the inline images, with the note":
      var h = newHistory()
      h.addUserWithImage("veja", "data:image/png;base64,QQ==")
      let req = CompletionRequest(messages: h)
      check requestForVision(req, vsYes) == req
      check requestForVision(req, vsUnknown) == req
      let stripped = requestForVision(req, vsNo)
      check not hasInlineImages(stripped)
      check InlineImageRemovedNote in stripped.messages[^1].text

  suite "the compat transport no longer drops images on its own":
    test "every compat profile sends the images it is given":
      ## The decision is made per model before the call, with the marker
      ## rewritten; the transport stripping them silently left the model told
      ## about an image it never received (and hid Qwen-VL's images).
      check fireworksCompatProfile().supportsImages
      check alibabaCompatProfile().supportsImages
      check nvidiaCompatProfile().supportsImages

when isMainModule:
  runTests()
