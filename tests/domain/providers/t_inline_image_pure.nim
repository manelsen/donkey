## Inline image policy tests (Ferramentas US-001).

import std/[strutils, unittest]
import donkey/core/pipeops
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

  suite "inline marker follows the chosen provider's capability":
    ## Review E3: the turn builder wrote "the image accompanies this message"
    ## from the media type alone, but a compat profile with `supportsImages =
    ## false` (Fireworks, Alibaba) strips `imageUrl` before the body is built. The
    ## model was then told about an image it never received.

    test "vision keeps the image and the inline promise":
      let filtered = filterImagesForCapability(@["data:image/png;base64,QQ=="],
                                               supportsImages = true)
      check filtered.len == 1
      check filtered[0] == "data:image/png;base64,QQ=="
      check inlineImageAccompanies(supportsImages = true)

    test "no vision drops the image and the promise together":
      let filtered = filterImagesForCapability(@["data:image/png;base64,QQ=="],
                                               supportsImages = false)
      check filtered.len == 0
      check not inlineImageAccompanies(supportsImages = false)

    test "no vision keeps http URLs and paths: the provider can still fetch them":
      let urls = @["https://example.test/a.png", "attachments/a.png"]
      let withVision = filterImagesForCapability(urls, supportsImages = true)
      let withoutVision = filterImagesForCapability(urls, supportsImages = false)
      check withVision == urls
      check withoutVision == urls

    test "the inline decision is the capability, not only the media type":
      let image = "data:image/png;base64,QQ=="
      let kept = filterImagesForCapability(@[image], supportsImages = true)
      let dropped = filterImagesForCapability(@[image], supportsImages = false)
      check kept.len == 1
      check dropped.len == 0
      check inlineImageAccompanies(supportsImages = true)
      check not inlineImageAccompanies(supportsImages = false)

  suite "the provider answers the inline question by its canonical id":

    test "the capability follows the descriptor, aliases included":
      check inlineSupportsImagesFor("nvidia")
      check inlineSupportsImagesFor("nvidia-nim")
      check not inlineSupportsImagesFor("fireworks")
      check not inlineSupportsImagesFor("fw")
      check not inlineSupportsImagesFor("alibaba-cloud")

    test "an unknown or non-compat provider makes no image promise":
      check not inlineSupportsImagesFor("does-not-exist")
      check not inlineSupportsImagesFor("")
      check not inlineSupportsImagesFor("anthropic")

  suite "a profile never promises an image the capability denies":

    test "the compat profiles report the same vision constant the turn reads":
      check fireworksCompatProfile().supportsImages ==
            inlineSupportsImagesFor("fireworks")
      check alibabaCompatProfile().supportsImages ==
            inlineSupportsImagesFor("alibaba")
      check nvidiaCompatProfile().supportsImages ==
            inlineSupportsImagesFor("nvidia")

when isMainModule:
  runTests()
