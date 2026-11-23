## US-006 — `text_to_speech(as_voice=true)` delivers the reply as a voice note.
##
## `prepareVoiceReply` only synthesizes and describes the outbound message; the
## enqueue happens once in `executeNativeCategory`. HTTP is always fake: the
## counter proves channels without `cfSendVoice` never reach the TTS endpoint.

import std/[json, options, os, strutils, unittest]
import chronos
import chronos/asyncsync
import results
import donkey/config/environment
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/tools/audio_tools
import donkey/adapters/filesystem/fs_adapter

let testFs = newFsAdapter()
import donkey/core/log
import donkey/domain/media/audio_pure
import donkey/domain/message
import donkey/domain/more_tools
import donkey/ports/http

type
  PostCapture = ref object
    posts:    int
    url:      string
    body:     string
    status:   int
    response: string

proc fakeHttp(cap: PostCapture): HttpRuntimePort =
  HttpRuntimePort(
    post: proc (url, body: string; headers: seq[HttpHeader] = @[]):
              Result[HttpResponse, string] {.gcsafe.} =
      inc cap.posts
      cap.url = url
      cap.body = body
      ok(HttpResponse(status: cap.status, body: cap.response)),
  )

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_voice_reply_" & tag & "_" &
                           $getCurrentProcessId())
  removeDir(result)
  createDir(result)

proc ttsFiles(dir: string): seq[string] =
  ## Every `tts-*` file written under the paddock attachments.
  let attachments = dir / "attachments"
  if not dirExists(attachments):
    return @[]
  for kind, path in walkDir(attachments):
    if kind == pcFile and path.extractFilename.startsWith("tts-"):
      result.add(path)

proc stubComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "stub"))

proc baseCtx(paddock: string; http: HttpRuntimePort;
             channel = ckTelegram; replyTo = ""): NativeCtx =
  NativeCtx(
    env:        environmentOf({"DONKEY_TTS_API_KEY": "voice-key"}),
    uid:        UserId("voice-user"),
    channel:    channel,
    outbox:     newAsyncQueue[OutboundMessage](),
    completeFn: stubComplete,
    http:       http,
    log:        newLogger("test.voice", lvlError),
    paddockDir: paddock,
    replyTo:    replyTo,
    fs:         testFs,
  )

let voiceSpeech = speechSettings(environmentOf({"DONKEY_TTS_API_KEY": "voice-key"}))

proc runTests*() =
  suite "estimateSpeechSeconds":

    test "empty text still reports the one second minimum":
      check estimateSpeechSeconds("") == 1

    test "a single word is one second":
      check estimateSpeechSeconds("oi") == 1

    test "scales at about 2.5 words per second":
      check estimateSpeechSeconds("uma duas três quatro cinco") == 2
      check estimateSpeechSeconds(
        "a b c d e f g h i j k l m n o p q r s t u v w x y") == 10

    test "longer text never reports less than shorter text":
      check estimateSpeechSeconds(
        "a b c d e f g h i j k l m n o p q r s t u v w x y z") >=
        estimateSpeechSeconds("a b c")

  suite "prepareVoiceReply":

    test "telegram stores an opus file and describes the outbound voice":
      let dir = freshDir("ok")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "OPUSBYTES")
      let prepared = prepareVoiceReply(testFs, "olá mundo", "recado",
                                       dir, ckTelegram, UserId("u1"),
                                       fakeHttp(cap), voiceSpeech)
      check prepared.isOk
      check cap.posts == 1
      let body = parseJson(cap.body)
      check body["input"].getStr() == "olá mundo"
      check body["response_format"].getStr() == "opus"

      let msg = prepared.get()
      check msg.userId == UserId("u1")
      check msg.channel == ckTelegram
      check msg.text == "recado"
      check msg.mediaDurationSec == estimateSpeechSeconds("olá mundo")
      check msg.mediaDurationSec > 0
      check msg.mediaUrl.isAbsolute
      check msg.mediaUrl.startsWith(dir / "attachments")
      check msg.mediaUrl.extractFilename.startsWith("tts-")
      check msg.mediaUrl.endsWith(".opus")
      check msg.mediaRoot == dir
      check fileExists(msg.mediaUrl)
      check readFile(msg.mediaUrl) == "OPUSBYTES"

    test "the voice note keeps the forum thread":
      let dir = freshDir("replyto")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "OPUSBYTES")
      let prepared = prepareVoiceReply(testFs, "olá mundo", "recado",
                                       dir, ckTelegram, UserId("u1"),
                                       fakeHttp(cap), voiceSpeech,
                                       replyTo = "77")
      check prepared.isOk
      check prepared.get().replyTo == "77"

    test "a channel without cfSendVoice fails before any TTS request":
      let dir = freshDir("email")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "OPUSBYTES")
      let prepared = prepareVoiceReply(testFs, "olá mundo", "recado",
                                       dir, ckEmail, UserId("u1"),
                                       fakeHttp(cap), voiceSpeech)
      check prepared.isErr
      check prepared.error.len > 0
      check cap.posts == 0
      check ttsFiles(dir).len == 0

    test "a TTS failure is an error and leaves no file behind":
      let dir = freshDir("http500")
      defer: removeDir(dir)
      let cap = PostCapture(status: 500, response: "boom")
      let prepared = prepareVoiceReply(testFs, "olá mundo", "recado",
                                       dir, ckTelegram, UserId("u1"),
                                       fakeHttp(cap), voiceSpeech)
      check prepared.isErr
      check prepared.error.contains("500")
      check cap.posts == 1
      check ttsFiles(dir).len == 0

    test "an empty audio body is an error and leaves no file behind":
      let dir = freshDir("empty")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "")
      let prepared = prepareVoiceReply(testFs, "olá mundo", "recado",
                                       dir, ckTelegram, UserId("u1"),
                                       fakeHttp(cap), voiceSpeech)
      check prepared.isErr
      check ttsFiles(dir).len == 0

  suite "text_to_speech as_voice wiring":

    proc speak(ctx: NativeCtx; input: string): Future[NativeToolResult] {.async.} =
      await executeNativeTool(
        ToolCallRequest(id: "call-1", name: TextToSpeechToolName,
                        inputJson: input),
        ctx, newSessionState(), newHistory())

    test "telegram queues exactly one outbound message":
      let dir = freshDir("wiring-ok")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "OPUSBYTES")
      let ctx = baseCtx(dir, fakeHttp(cap))
      let res = waitFor speak(ctx,
        """{"text":"olá mundo","as_voice":true,"caption":"ouça"}""")
      check res.handled
      check res.resultKind == trkOutput
      check res.outbound.isSome
      check ctx.outbox.len == 1
      let msg = waitFor ctx.outbox.get()
      check msg.channel == ckTelegram
      check msg.text == "ouça"
      check msg.mediaUrl == res.outbound.get().mediaUrl
      check msg.mediaUrl.endsWith(".opus")
      check msg.mediaRoot == dir
      check fileExists(msg.mediaUrl)
      check msg.mediaDurationSec > 0
      check cap.posts == 1

    test "the queued voice note keeps the composite forum target":
      ## The app passes the composite `chat#cmsg#thread` anchor, not a bare id.
      let dir = freshDir("wiring-replyto")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "OPUSBYTES")
      let ctx = baseCtx(dir, fakeHttp(cap), replyTo = "123#c9#t7")
      let res = waitFor speak(ctx,
        """{"text":"olá mundo","as_voice":true,"caption":"ouça"}""")
      check res.handled
      check res.outbound.isSome
      check res.outbound.get().replyTo == "123#c9#t7"

    test "a channel without cfSendVoice queues nothing":
      let dir = freshDir("wiring-email")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "OPUSBYTES")
      let ctx = baseCtx(dir, fakeHttp(cap), ckEmail)
      let res = waitFor speak(ctx,
        """{"text":"olá mundo","as_voice":true,"caption":"ouça"}""")
      check res.handled
      check res.resultKind == trkOperationalError
      check res.outbound.isNone
      check ctx.outbox.len == 0
      check cap.posts == 0
      check ttsFiles(dir).len == 0

    test "a TTS failure queues nothing":
      let dir = freshDir("wiring-500")
      defer: removeDir(dir)
      let cap = PostCapture(status: 500, response: "boom")
      let ctx = baseCtx(dir, fakeHttp(cap))
      let res = waitFor speak(ctx,
        """{"text":"olá mundo","as_voice":true,"caption":"ouça"}""")
      check res.handled
      check res.resultKind == trkOperationalError
      check res.outbound.isNone
      check ctx.outbox.len == 0
      check ttsFiles(dir).len == 0

    test "without as_voice the file is saved and nothing is queued":
      let dir = freshDir("wiring-file")
      defer: removeDir(dir)
      let cap = PostCapture(status: 200, response: "MP3BYTES")
      let ctx = baseCtx(dir, fakeHttp(cap))
      let res = waitFor speak(ctx, """{"text":"olá mundo"}""")
      check res.handled
      check res.outbound.isNone
      check ctx.outbox.len == 0
      check res.text.startsWith("Audio saved: attachments/tts-")

when isMainModule:
  runTests()
