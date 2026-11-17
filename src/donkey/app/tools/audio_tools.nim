## audio_tools.nim — speech-to-text and text-to-speech tools.
##
## Both talk to an OpenAI-compatible audio endpoint through the injected HTTP
## port. Transcription uploads a multipart body and returns the text; speech
## writes the returned bytes under `{paddock}/attachments/` and returns the
## relative path, so the model can reference the file with the media tools.
##
## The endpoint is configurable because the same wire format is served by
## several providers; no provider-specific code lives here.

import std/[os, strutils]
import results
import ../../core/pipeops
import ../../domain/media/audio_pure
import ../../ports/http

const
  SttDefaultEndpoint* = "https://api.openai.com/v1/audio/transcriptions"
  SttDefaultModel*    = "whisper-1"
  TtsDefaultEndpoint* = "https://api.openai.com/v1/audio/speech"
  TtsDefaultModel*    = "tts-1"
  TtsDefaultVoice*    = "alloy"
  MaxErrorBodyChars*  = 300

var gSpeechSeq = 0

proc sttApiKey*(): string =
  let direct = getEnv("DONKEY_STT_API_KEY").strip
  if direct.len > 0: direct else: getEnv("OPENAI_API_KEY").strip

proc sttEndpoint*(): string =
  let value = getEnv("DONKEY_STT_URL").strip
  if value.len > 0: value else: SttDefaultEndpoint

proc sttModel*(): string =
  let value = getEnv("DONKEY_STT_MODEL").strip
  if value.len > 0: value else: SttDefaultModel

proc ttsApiKey*(): string =
  let direct = getEnv("DONKEY_TTS_API_KEY").strip
  if direct.len > 0: direct else: getEnv("OPENAI_API_KEY").strip

proc ttsEndpoint*(): string =
  let value = getEnv("DONKEY_TTS_URL").strip
  if value.len > 0: value else: TtsDefaultEndpoint

proc ttsModel*(): string =
  let value = getEnv("DONKEY_TTS_MODEL").strip
  if value.len > 0: value else: TtsDefaultModel

proc ttsVoice*(): string =
  let value = getEnv("DONKEY_TTS_VOICE").strip
  if value.len > 0: value else: TtsDefaultVoice

func clipBody(body: string): string =
  let trimmed = body.strip
  if trimmed.len <= MaxErrorBodyChars: trimmed
  else: trimmed[0 ..< MaxErrorBodyChars] & "…"

func errorText(prefix, detail: string): string =
  "Error: " & prefix & ": " & detail

proc performTranscribe*(path: string; http: HttpRuntimePort;
                        language = ""; prompt = "";
                        apiKey = sttApiKey(); endpoint = sttEndpoint();
                        model = sttModel();
                        maxBytes = MaxTranscriptionBytes): string {.gcsafe, raises: [].} =
  ## Reads `path` (inside the paddock, resolved by the caller) and returns the
  ## transcript, or a string starting with "Error: ".
  if apiKey.len == 0:
    return errorText("transcribe_audio", "no API key (set DONKEY_STT_API_KEY or OPENAI_API_KEY)")
  let mime = audioMimeType(path)
  if mime.len == 0:
    return errorText("transcribe_audio", "unsupported audio file: " & path)
  if not fileExists(path):
    return errorText("transcribe_audio", "file not found: " & path)
  let data = try:
    readFile(path)
  except Exception as e:
    return errorText("transcribe_audio", e.msg)
  if data.len > maxBytes:
    return errorText("transcribe_audio", "file too large (" & $data.len &
                     " bytes, limit " & $maxBytes & ")")

  var fields: seq[(string, string)] = @[("model", model)]
  if language.strip.len > 0:
    fields.add(("language", language.strip))
  if prompt.strip.len > 0:
    fields.add(("prompt", prompt.strip))
  let boundary = "----donkey-audio-" & $nowMs()
  let body = buildMultipartBody(boundary, "file", extractFilename(path),
                                mime, data, fields)
  let headers = @[
    ("Authorization", "Bearer " & apiKey),
    ("Content-Type", "multipart/form-data; boundary=" & boundary),
  ]
  let response = try:
    http.post(endpoint, body, headers)
  except Exception as e:
    return errorText("transcribe_audio", e.msg)
  if response.isErr:
    return errorText("transcribe_audio", response.error)
  if response.get().status < 200 or response.get().status >= 300:
    return errorText("transcribe_audio", "HTTP " & $response.get().status &
                     ": " & clipBody(response.get().body))
  let parsed = parseTranscript(response.get().body)
  if parsed.isErr:
    return errorText("transcribe_audio", parsed.error)
  parsed.get()

proc performSpeech*(text: string; paddockDir: string; http: HttpRuntimePort;
                    voice = ttsVoice(); format = "mp3";
                    apiKey = ttsApiKey(); endpoint = ttsEndpoint();
                    model = ttsModel()): Result[string, string]
                    {.gcsafe, raises: [].} =
  ## Sends `text` to the speech endpoint and stores the audio under the
  ## paddock's attachments. Returns the path relative to the paddock.
  if text.strip.len == 0:
    return err("text_to_speech: text is empty")
  if apiKey.len == 0:
    return err("text_to_speech: no API key (set DONKEY_TTS_API_KEY or OPENAI_API_KEY)")
  if paddockDir.len == 0:
    return err("text_to_speech: no paddock directory")
  let chosenFormat = if format.strip.len == 0: "mp3" else: format
  let chosenVoice = if voice.strip.len == 0: ttsVoice() else: voice.strip
  let extension = speechExtension(chosenFormat).valueOr:
    return err("text_to_speech: " & error)
  let payload = buildSpeechPayload(model, text, chosenVoice, extension)
  let headers = @[
    ("Authorization", "Bearer " & apiKey),
    ("Content-Type", "application/json"),
  ]
  let response = try:
    http.post(endpoint, payload, headers)
  except Exception as e:
    return err("text_to_speech: " & e.msg)
  if response.isErr:
    return err("text_to_speech: " & response.error)
  if response.get().status < 200 or response.get().status >= 300:
    return err("text_to_speech: HTTP " & $response.get().status & ": " &
               clipBody(response.get().body))
  let audio = response.get().body
  if audio.len == 0:
    return err("text_to_speech: endpoint returned no audio")
  try:
    inc gSpeechSeq
    let name = "tts-" & $nowMs() & "-" & $gSpeechSeq & "." & extension
    let dir = paddockDir / "attachments"
    createDir(dir)
    writeFile(dir / name, audio)
    ok("attachments/" & name)
  except Exception as e:
    err("text_to_speech: " & e.msg)
