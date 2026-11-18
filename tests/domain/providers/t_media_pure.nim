## Tests for domain/providers/media_pure — inline image data URLs.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/providers/media_pure

suite "parseDataUrl":

  test "accepts a png data URL":
    let res = parseDataUrl("data:image/png;base64,QUJD")
    check res.isOk
    check res.get().mimeType == "image/png"
    check res.get().data == "QUJD"

  test "lowercases the media type":
    let res = parseDataUrl("data:IMAGE/PNG;base64,QUJD")
    check res.isOk
    check res.get().mimeType == "image/png"

  test "accepts base64 padding":
    check parseDataUrl("data:image/jpeg;base64,QUJD=").isOk

  test "rejects a plain URL":
    let res = parseDataUrl("https://example.test/a.png")
    check res.isErr
    check res.error.contains("data URL")

  test "rejects a data URL without the base64 marker":
    check parseDataUrl("data:image/png,QUJD").isErr

  test "rejects an empty payload":
    check parseDataUrl("data:image/png;base64,").isErr

  test "rejects a non-image type":
    check parseDataUrl("data:text/plain;base64,QUJD").isErr

  test "rejects an unsupported image type":
    check parseDataUrl("data:image/svg+xml;base64,PHN2Zz4=").isErr

  test "rejects characters outside base64":
    check parseDataUrl("data:image/png;base64,@@@").isErr

  test "recognises http and https URLs":
    check isHttpUrl("http://example.test/a.png")
    check isHttpUrl("https://example.test/a.png")
    check not isHttpUrl("data:image/png;base64,QUJD")
    check not isHttpUrl("")
