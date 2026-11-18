## `inspect_image` must use the same inline-image policy as inbound media:
## supported MIME allowlist and the encoded-size cap (Ferramentas N3).
##
## Before, it encoded any file itself and labelled unknown extensions as
## `image/jpeg`, so an `.svg`/`.bmp`/`.heic` was sent as a fake JPEG and a
## huge file was read before being rejected.

import std/[os, strutils, unittest]
import results
import donkey/app/tools/utility_tools
import donkey/domain/message
import donkey/domain/providers/media_pure
import donkey/ports/provider

var gCalls: seq[CompletionRequest]

proc fakeComplete(req: CompletionRequest): Result[CompletionResponse, string]
    {.gcsafe.} =
  {.cast(gcsafe).}:
    gCalls.add(req)
  ok(CompletionResponse(text: "descrição"))

proc writeTemp(name: string; content: string): string =
  result = getTempDir() / name
  writeFile(result, content)

suite "inspect_image inline policy":

  setup:
    gCalls.setLen(0)

  test "a png is sent as a data URL with the right media type":
    let path = writeTemp("donkey_inspect_ok.png", "PNGDATA")
    defer: removeFile(path)
    let reply = performInspectImage(path, "o que é?", fakeComplete)
    check reply == "descrição"
    check gCalls.len == 1
    let msg = gCalls[0].messages[^1]
    check msg.imageUrl.startsWith("data:image/png;base64,")

  test "an unsupported extension is refused, not relabelled as jpeg":
    for ext in [".svg", ".bmp", ".heic"]:
      let path = writeTemp("donkey_inspect_bad" & ext, "<svg/>")
      defer: removeFile(path)
      let reply = performInspectImage(path, "", fakeComplete)
      check reply.toLowerAscii().contains("unsupported")
      check not reply.contains("data:")
    check gCalls.len == 0

  test "a file over the inline cap is refused before encoding":
    let path = getTempDir() / "donkey_inspect_big.png"
    let size = MaxInlineImageEncodedBytes  # raw > 3/4 of the encoded cap
    writeFile(path, repeat('A', size))
    defer: removeFile(path)
    let reply = performInspectImage(path, "", fakeComplete)
    check reply.toLowerAscii().contains("large") or
      reply.toLowerAscii().contains("too big")
    check gCalls.len == 0
