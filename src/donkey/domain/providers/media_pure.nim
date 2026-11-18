## media_pure.nim — inline image helpers shared by provider wire formats.
##
## A `ChatMessage.imageUrl` is either an `http(s)` URL or a data URL produced
## by `inspect_image`. Each provider accepts a different envelope, but the
## decoding is the same: media type plus base64 payload.
##
## No I/O, no side effects.

import std/[base64, strutils]
import results

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
