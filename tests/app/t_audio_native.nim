## Native audio tool wiring: registration and dispatch.

import std/[json, os, sequtils, strutils, unittest]
import chronos
import donkey/config/environment
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/memory/md_file
import donkey/app/native_tools
import donkey/app/session_bootstrap
import donkey/app/session_state
import donkey/core/log
import donkey/core/pipeops
import donkey/domain/message

import donkey/ports/http

type Capture = ref object
  url:      string
  body:     string
  status:   int
  response: string

proc fakeHttp(cap: Capture): HttpRuntimePort =
  HttpRuntimePort(
    post: proc (url, body: string; headers: seq[HttpHeader] = @[]):
              Result[HttpResponse, string] {.gcsafe.} =
      cap.url = url
      cap.body = body
      ok(HttpResponse(status: cap.status, body: cap.response)),
  )

proc stubComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "stub"))

proc baseCtx(paddock: string; http: HttpRuntimePort): NativeCtx =
  NativeCtx(
    env:        environmentOf({"DONKEY_STT_API_KEY": "test-key",
                               "DONKEY_TTS_API_KEY": "test-key"}),
    uid:        UserId("audio-user"),
    channel:    ckTelegram,
    memory:     MdFileAdapter(paddocksDir: paddock).toRuntimePort(),
    completeFn: stubComplete,
    http:       http,
    log:        newLogger("test.audio", lvlError),
    paddockDir: paddock,
    fs:         newFsAdapter(),
  )

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_audio_native_" & tag & "_" &
                           $getCurrentProcessId())
  removeDir(result)
  createDir(result)

proc call(ctx: NativeCtx; name, input: string): Future[NativeToolResult] {.async.} =
  await executeNativeTool(
    ToolCallRequest(id: "1", name: name, inputJson: input),
    ctx, newSessionState(), newHistory())

proc runTests*() =
  suite "audio tool registration":

    test "both audio tools are advertised":
      let names = nativeSessionTools().mapIt(it.name)
      check "transcribe_audio" in names
      check "text_to_speech" in names

  suite "audio tool dispatch":

    test "transcribe_audio resolves the path and returns the text":
      let dir = freshDir("stt")
      defer: removeDir(dir)
      writeFile(dir / "nota.mp3", "AUDIO")
      let cap = Capture(status: 200, response: """{"text": "transcrição"}""")
      let res = waitFor call(baseCtx(dir, fakeHttp(cap)), "transcribe_audio",
                             """{"path": "nota.mp3"}""")
      check res.handled
      check res.text == "transcrição"
      check cap.body.contains("AUDIO")

    test "transcribe_audio rejects a path outside the paddock":
      let dir = freshDir("stt-escape")
      defer: removeDir(dir)
      let cap = Capture(status: 200, response: """{"text": "x"}""")
      let res = waitFor call(baseCtx(dir, fakeHttp(cap)), "transcribe_audio",
                             """{"path": "../outside.mp3"}""")
      check res.handled
      check res.text.startsWith("Error:")
      check cap.url == ""

    test "text_to_speech writes the file and returns its path":
      let dir = freshDir("tts")
      defer: removeDir(dir)
      let cap = Capture(status: 200, response: "MP3")
      let res = waitFor call(baseCtx(dir, fakeHttp(cap)), "text_to_speech",
                             """{"text": "olá"}""")
      check res.handled
      check res.text.startsWith("Audio saved: attachments/tts-")
      let rel = res.text.split(": ", 1)[1]
      check readFile(dir / rel) == "MP3"

    test "text_to_speech requires text":
      let dir = freshDir("tts-empty")
      defer: removeDir(dir)
      let cap = Capture()
      let res = waitFor call(baseCtx(dir, fakeHttp(cap)), "text_to_speech", "{}")
      check res.handled
      check res.text.startsWith("Error:")
      check cap.url == ""

when isMainModule:
  runTests()
