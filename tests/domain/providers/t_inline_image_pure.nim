## Inline image policy tests (Ferramentas US-001).

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/providers/media_pure

func bytes(data: string): seq[byte] =
  for ch in data:
    result.add(byte(ord(ch)))

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
