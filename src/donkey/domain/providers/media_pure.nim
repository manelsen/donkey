## media_pure.nim — inline image helpers shared by provider wire formats.
##
## A `ChatMessage.imageUrl` is either an `http(s)` URL or a data URL produced
## by `inspect_image`. Each provider accepts a different envelope, but the
## decoding is the same: media type plus base64 payload.
##
## No I/O, no side effects.

import std/[base64, strutils]
import results
import ../message

type
  InlineImage* = object
    mimeType*: string  ## lower-case media type, e.g. "image/png"
    data*:     string  ## base64 payload without the `data:` prefix

const
  ## The encoded data URL is what the provider sees; 5 MiB of base64 is the
  ## practical Anthropic ceiling and keeps the JSON body bounded.
  MaxInlineImageEncodedBytes* = 5 * 1024 * 1024
  MaxInlineImagesPerTurn* = 4

  ## Anthropic, Gemini and the OpenAI-compatible vision models accept these.
  ## SVG is deliberately absent: it is a script-carrying document, not an
  ## image the providers agree to inline.
  SupportedImageMimes* = ["image/jpeg", "image/png", "image/gif", "image/webp"]

  ## Single source of the provider errors that mean "the image was refused".
  ## `genericProviderErrorText` and the inline-image retry both read this list.
  ImageRejectionMarkers* = ["image_url", "image url", "unsupported image",
                            "invalid content", "media type"]

  ## Appended to the text turn when the inline image had to be dropped.
  InlineImageRemovedNote* = "[imagem removida: provider sem visão]"

func isHttpUrl*(raw: string): bool =
  raw.startsWith("http://") or raw.startsWith("https://")

func parseDataUrl*(raw: string): Result[InlineImage, string] =
  ## `data:image/png;base64,QUJD` -> (image/png, QUJD). Anything that is not a
  ## base64 image data URL is an error; callers fall back to the text.
  if not raw.startsWith("data:"):
    return err("not a data URL")
  let comma = raw.find(',')
  if comma < 0:
    return err("data URL has no payload")
  let header = raw[5 ..< comma]
  if not header.endsWith(";base64"):
    return err("data URL is not base64")
  let mime = header[0 ..< header.len - 7].toLowerAscii()
  if mime notin SupportedImageMimes:
    return err("unsupported image media type: " & mime)
  let payload = raw[comma + 1 .. ^1]
  if payload.len == 0:
    return err("data URL has an empty payload")
  for ch in payload:
    if ch notin {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '+', '/', '='}:
      return err("data URL payload is not base64")
  ok(InlineImage(mimeType: mime, data: payload))

func imageDataUrl*(mime: string; data: openArray[byte];
                   maxEncodedBytes = MaxInlineImageEncodedBytes):
                     Result[string, string] =
  ## Builds an inline data URL for a supported image. The limit is measured on
  ## the encoded URL, not on the raw bytes, because that is what crosses the
  ## provider boundary.
  let mediaType = mime.strip.toLowerAscii()
  if mediaType notin SupportedImageMimes:
    return err("unsupported image media type: " & mediaType)
  if data.len == 0:
    return err("image is empty")
  let url = "data:" & mediaType & ";base64," & encode(data)
  if url.len > maxEncodedBytes:
    return err("inline image too large (" & $url.len & " encoded bytes)")
  ok(url)

func inlineImagesForTurn*(urls: seq[string]): seq[string] =
  ## Keeps http(s) URLs and paths untouched, in order. Only data URLs count
  ## against MaxInlineImagesPerTurn and are dropped beyond it.
  var inlined = 0
  for url in urls:
    if url.startsWith("data:"):
      if inlined < MaxInlineImagesPerTurn:
        result.add(url)
        inc inlined
    else:
      result.add(url)

func demoteInlineImages*(h: ConversationHistory): ConversationHistory =
  ## The live history after an inline turn: the photo was already sent to the
  ## provider, so `data:` payloads become text-only entries again. `http(s)`
  ## URLs and paths stay: they are cheap and may still be fetched.
  result = newSeq[ChatMessage](h.len)
  for i, msg in h:
    result[i] = msg
    if msg.imageUrl.startsWith("data:"):
      result[i].imageUrl = ""

func isImageRejection*(error: string): bool =
  ## True when the provider blamed the image payload. Case-insensitive; the
  ## markers are the only place this classification lives.
  let lower = error.toLowerAscii()
  for marker in ImageRejectionMarkers:
    if lower.contains(marker):
      return true

func hasInlineImages*(req: CompletionRequest): bool =
  ## True when the request still carries at least one `data:` image.
  for msg in req.messages:
    if msg.imageUrl.startsWith("data:"):
      return true

func withoutInlineImages*(req: CompletionRequest): CompletionRequest =
  ## The text-only twin of a request: drops `data:` images (http(s) URLs stay),
  ## notes the last user turn that still has text, and removes user turns left
  ## with neither text nor image. A request without inline images is returned
  ## unchanged. Tool-call turns are preserved even when their text is empty.
  if not hasInlineImages(req):
    return req
  result = req
  result.messages = @[]
  for msg in req.messages:
    var stripped = msg
    if stripped.imageUrl.startsWith("data:"):
      stripped.imageUrl = ""
    if stripped.role == roleUser and stripped.text.strip.len == 0 and
       stripped.imageUrl.len == 0:
      continue
    result.messages.add(stripped)
  var lastUserWithText = -1
  for i, msg in result.messages:
    if msg.role == roleUser and msg.text.strip.len > 0:
      lastUserWithText = i
  if lastUserWithText >= 0:
    result.messages[lastUserWithText].text =
      result.messages[lastUserWithText].text & "\n\n" & InlineImageRemovedNote
  else:
    ## An album of image-only turns would otherwise leave the request empty.
    result.messages.add(ChatMessage(role: roleUser, text: InlineImageRemovedNote))
