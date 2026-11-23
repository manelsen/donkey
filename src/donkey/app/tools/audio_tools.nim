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
import ../../config/environment
import ../../domain/media/audio_pure
import ../../domain/message
import ../../ports/channel_capability
import ../../ports/http
import ../../ports/fs

const
  SttDefaultEndpoint* = "https://api.openai.com/v1/audio/transcriptions"
  SttDefaultModel*    = "whisper-1"
  TtsDefaultEndpoint* = "https://api.openai.com/v1/audio/speech"
  TtsDefaultModel*    = "tts-1"
  TtsDefaultVoice*    = "alloy"
  MaxErrorBodyChars*  = 300

var gSpeechSeq = 0

type SpeechSettings* = object
  ## Speech endpoints and keys, read once from the environment snapshot.
  sttApiKey*, sttEndpoint*, sttModel*: string
  ttsApiKey*, ttsEndpoint*, ttsModel*, ttsVoice*: string

func speechSettings*(env: Environment): SpeechSettings =
  ## `DONKEY_STT_*` / `DONKEY_TTS_*`, with `OPENAI_API_KEY` as the key
  ## fallback and the OpenAI endpoints, models and voice as defaults.
  let openAiKey = env.stripped("OPENAI_API_KEY")
  SpeechSettings(
    sttApiKey: env.stripped("DONKEY_STT_API_KEY", openAiKey),
    sttEndpoint: env.stripped("DONKEY_STT_URL", SttDefaultEndpoint),
    sttModel: env.stripped("DONKEY_STT_MODEL", SttDefaultModel),
    ttsApiKey: env.stripped("DONKEY_TTS_API_KEY", openAiKey),
    ttsEndpoint: env.stripped("DONKEY_TTS_URL", TtsDefaultEndpoint),
    ttsModel: env.stripped("DONKEY_TTS_MODEL", TtsDefaultModel),
    ttsVoice: env.stripped("DONKEY_TTS_VOICE", TtsDefaultVoice))

func clipBody(body: string): string =
  let trimmed = body.strip
  if trimmed.len <= MaxErrorBodyChars: trimmed
  else: trimmed[0 ..< MaxErrorBodyChars] & "…"

func errorText(prefix, detail: string): string =
  "Error: " & prefix & ": " & detail

proc performTranscribe*(fs: FsRuntimePort; path: string; http: HttpRuntimePort;
                        language = ""; prompt = "";
                        apiKey = ""; endpoint = SttDefaultEndpoint;
                        model = SttDefaultModel;
                        maxBytes = MaxTranscriptionBytes): string {.gcsafe, raises: [].} =
  ## Reads `path` (inside the paddock, resolved by the caller) and returns the
  ## transcript, or a string starting with "Error: ".
  if apiKey.len == 0:
    return errorText("transcribe_audio", "no API key (set DONKEY_STT_API_KEY or OPENAI_API_KEY)")
  let mime = audioMimeType(path)
  if mime.len == 0:
    return errorText("transcribe_audio", "unsupported audio file: " & path)
  if fs.entryKind(path) != fekFile:
    return errorText("transcribe_audio", "file not found: " & path)
  ## The size is checked before the file is read into memory.
  let size = fs.fileSize(path).valueOr:
    return errorText("transcribe_audio", error)
  if size > maxBytes:
    return errorText("transcribe_audio", "file too large (" & $size &
                     " bytes, limit " & $maxBytes & ")")
  ## Capped too: the file may have grown since its size was read.
  let data = fs.readCapped(path, maxBytes).valueOr:
    return errorText("transcribe_audio", error)

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
  except Exception as e:  ## effect boundary: callee raises are unannotated
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

proc performSpeech*(fs: FsRuntimePort; text: string; paddockDir: string; http: HttpRuntimePort;
                    voice = TtsDefaultVoice; format = "mp3";
                    apiKey = ""; endpoint = TtsDefaultEndpoint;
                    model = TtsDefaultModel): Result[string, string]
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
  let chosenVoice = if voice.strip.len == 0: TtsDefaultVoice else: voice.strip
  let extension = speechExtension(chosenFormat).valueOr:
    return err("text_to_speech: " & error)
  let payload = buildSpeechPayload(model, text, chosenVoice, extension)
  let headers = @[
    ("Authorization", "Bearer " & apiKey),
    ("Content-Type", "application/json"),
  ]
  let response = try:
    http.post(endpoint, payload, headers)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    return err("text_to_speech: " & e.msg)
  if response.isErr:
    return err("text_to_speech: " & response.error)
  if response.get().status < 200 or response.get().status >= 300:
    return err("text_to_speech: HTTP " & $response.get().status & ": " &
               clipBody(response.get().body))
  let audio = response.get().body
  if audio.len == 0:
    return err("text_to_speech: endpoint returned no audio")
  inc gSpeechSeq
  let name = "tts-" & $nowMs() & "-" & $gSpeechSeq & "." & extension
  let dir = paddockDir / "attachments"
  let saved = fs.createDir(dir) and fs.writeFile(dir / name, audio)
  if saved.isErr:
    return err("text_to_speech: " & saved.error)
  ok("attachments/" & name)

proc prepareVoiceReply*(fs: FsRuntimePort; text, caption, paddockDir: string;
                        channel: ChannelKind; uid: UserId;
                        http: HttpRuntimePort; speech: SpeechSettings;
                        replyTo = ""): Result[OutboundMessage, string]
                        {.gcsafe, raises: [].} =
  ## Synthesizes `text` as an opus voice note and describes the outbound
  ## message; the caller enqueues it. The capability check comes first, so a
  ## channel without voice support falls back to text without paying for TTS.
  ## A failed synthesis leaves no file behind.
  if not supports(channel, cfSendVoice):
    return err("text_to_speech: channel " & $channel &
               " cannot deliver voice notes")
  let saved = performSpeech(fs, text, paddockDir, http, voice = speech.ttsVoice,
                            format = "opus", apiKey = speech.ttsApiKey,
                            endpoint = speech.ttsEndpoint, model = speech.ttsModel)
  if saved.isErr:
    return err(saved.error)
  ok(OutboundMessage(
    userId: uid,
    channel: channel,
    text: caption,
    replyTo: replyTo,
    mediaUrl: paddockDir / saved.get(),
    mediaRoot: paddockDir,
    mediaDurationSec: estimateSpeechSeconds(text),
  ))
