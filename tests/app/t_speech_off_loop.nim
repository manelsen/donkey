## transcribe_audio and text_to_speech off the event loop (second round, §3):
## each call becomes a SpeechJob of plain data that a worker runs with its
## own file, attachment and HTTP ports, answering as the in-place calls do.

import std/[json, os, strutils, unittest]
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/filesystem/attachment_store
import donkey/app/tools/audio_tools
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/infra/thread_handle
import donkey/ports/http

proc answering(status: int; body: string): HttpRuntimePort =
  HttpRuntimePort(post: proc(url, b: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
    ok(HttpResponse(status: status, body: body)))

let settings = SpeechSettings(sttApiKey: "k", sttEndpoint: SttDefaultEndpoint, sttModel: SttDefaultModel,
                              ttsApiKey: "k", ttsEndpoint: TtsDefaultEndpoint, ttsModel: TtsDefaultModel,
                              ttsVoice: TtsDefaultVoice)

proc runTests*() =
  suite "speech off the loop":

    test "the job and its result are plain data":
      check sharesNothing(SpeechJob)
      check sharesNothing(SpeechOutput)

    test "a transcription job answers like performTranscribe":
      let dir = getTempDir() / "donkey_speech_t"
      removeDir(dir); createDir(dir)
      writeFile(dir / "a.mp3", "ID3fake")
      let job = SpeechJob(kind: sjTranscribe, path: dir / "a.mp3", settings: settings,
                          maxBytes: 1_000_000)
      let o = runSpeechJob(job, newFsAdapter(), newAttachmentStore(), answering(200, """{"text":"olá"}"""))
      check o.text == "olá"

    test "a speech job saves the audio in the paddock's attachments":
      let dir = getTempDir() / "donkey_speech_s"
      removeDir(dir); createDir(dir)
      let job = SpeechJob(kind: sjSave, text: "oi", paddockDir: dir, format: "mp3", settings: settings)
      let o = runSpeechJob(job, newFsAdapter(), newAttachmentStore(), answering(200, "AUDIO"))
      check o.ok and o.saved.startsWith("attachments/")
      check fileExists(dir / o.saved)

    test "a voice reply job describes the outbound message; a failure says why":
      let dir = getTempDir() / "donkey_speech_v"
      removeDir(dir); createDir(dir)
      let job = SpeechJob(kind: sjVoiceReply, text: "oi", caption: "c", paddockDir: dir,
                          channel: ckTelegram, uid: UserId("u"), replyTo: "9", settings: settings)
      let o = runSpeechJob(job, newFsAdapter(), newAttachmentStore(), answering(200, "OPUS"))
      check o.ok and o.outbound.channel == ckTelegram and o.outbound.mediaUrl.len > 0
      let bad = runSpeechJob(job, newFsAdapter(), newAttachmentStore(), answering(500, "down"))
      check not bad.ok and "500" in bad.error

when isMainModule:
  runTests()
