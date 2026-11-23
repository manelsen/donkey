## audio_pure.nim — wire helpers for speech-to-text and text-to-speech.
##
## The transcription endpoint takes a multipart upload; the speech endpoint
## takes JSON and returns audio bytes. Both shapes are built here so the tool
## layer is only transport and file I/O.

import std/[json, math, os, strutils]
import ../../core/pipeops

const
  MaxTranscriptionBytes* = 25 * 1024 * 1024
    ## OpenAI-compatible transcription endpoints reject larger uploads.
  SpeechFormats* = ["mp3", "opus", "wav", "aac", "flac"]
  SpeechWordsPerSecond* = 2.5
    ## Rough speaking rate used for the voice/audio `duration` field.

func audioMimeType*(path: string): string =
  ## MIME type from the file extension; "" when the extension is not audio the
  ## transcription endpoints accept.
  case splitFile(path).ext.toLowerAscii()
  of ".mp3":          "audio/mpeg"
  of ".ogg", ".opus": "audio/ogg"
  of ".wav":          "audio/wav"
  of ".m4a":          "audio/mp4"
  of ".webm":         "audio/webm"
  of ".flac":         "audio/flac"
  else:               ""

func speechExtension*(format: string): Result[string, string] =
  ## Normalised audio format for the speech endpoint and the file extension.
  let value = format.strip.toLowerAscii()
  if value in SpeechFormats:
    ok(value)
  else:
    err("unsupported speech format: " & format)

func estimateSpeechSeconds*(text: string): int =
  ## Spoken duration of `text` at the approximate reading rate, never below
  ## one second. Used for the `duration` field of voice/audio messages.
  let words = text.splitWhitespace().len
  if words == 0:
    return 1
  max(1, int(ceil(words.float / SpeechWordsPerSecond)))

proc buildMultipartBody*(boundary, fileField, fileName, mimeType, data: string;
                         fields: seq[(string, string)] = @[]): string =
  ## Multipart/form-data body. Fields first, then the file; CRLF framing as
  ## required by the endpoint. The payload is copied byte for byte.
  for (name, value) in fields:
    result.add("--" & boundary & "\r\n")
    result.add("Content-Disposition: form-data; name=\"" & name & "\"\r\n\r\n")
    result.add(value & "\r\n")
  result.add("--" & boundary & "\r\n")
  result.add("Content-Disposition: form-data; name=\"" & fileField &
             "\"; filename=\"" & fileName & "\"\r\n")
  result.add("Content-Type: " & mimeType & "\r\n\r\n")
  result.add(data)
  result.add("\r\n--" & boundary & "--\r\n")

proc parseTranscript*(raw: string): Result[string, string] =
  ## `{"text": "..."}` on success; an `error.message` object becomes the error.
  let node = try:
    parseJson(raw)
  except CatchableError:
    return err("transcription response is not valid JSON")
  if node.kind == JObject:
    let errorNode = node.getOrDefault("error")
    if not errorNode.isNil:
      let message =
        if errorNode.kind == JObject: errorNode.getOrDefault("message").getStr("")
        elif errorNode.kind == JString: errorNode.getStr("")
        else: ""
      return err(if message.len > 0: message else: "transcription failed")
  let text = node.getOrDefault("text").getStr("").strip
  if text.len == 0:
    return err("transcription response has no text")
  ok(text)

func buildSpeechPayload*(model, text, voice, format: string): string =
  ## OpenAI-compatible `/audio/speech` body. `format` is already normalised by
  ## `speechExtension`.
  $(%* {
    "model": model,
    "input": text,
    "voice": voice,
    "response_format": format,
  })
