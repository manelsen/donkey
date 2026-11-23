# Media — images and voice

Two flows share one rule: a channel file is downloaded once, stored in the
paddock, and the model receives a bounded inline representation only when the
provider can take it.

## Image flow

```text
channel attachment (an album is several updates)
  -> paddock attachments/<name>
  -> applyInboundAttachment
       supported image, within encoded limit -> msg.mediaUrl = data URL
       supported image, over the limit       -> mediaUrl = "" + marker -> inspect_image
       unsupported image format              -> mediaUrl = "" + marker -> fs_read/text_read
       other file                            -> mediaUrl = "" + marker -> fs_read/text_read
  -> prompt building, per image of the turn
       first 4 data: URLs                    -> inline + "já acompanha esta mensagem"
       data: URL beyond 4, path available    -> path-only marker -> inspect_image
       album bounded at 10 attachments
  -> routing, per provider attempt (buildCompleteFn / buildAsyncCompleteFn)
       visionSupport(provider, model) = vsNo -> data: URLs dropped + one note
       vsYes / vsUnknown                     -> request unchanged
  -> provider profile (CompatProfile / Anthropic / Gemini)
       image part in the provider envelope (the transport never drops it)
  -> tool loop, on image rejection (once per turn, streaming included)
       demote history + retry without data: URLs + one removal note
  -> orchestrator, after the loop
       demoteInlineImages clears data: URLs, so later turns do not resend
```

- The inline decision is pure (`imageDataUrl`, `inlineImagesForTurn` in
  `domain/providers/media_pure.nim`).
- Saving an image to disk knows the path, not the final turn composition. The
  turn builder (`addUserTurnWithImages`) removes every save-time marker whose
  path is in `mediaPaths` and writes one marker per image of the turn:
  - an image the turn actually inlines (the first 4 `data:` URLs) keeps its path
    in the marker and adds that the image already accompanies the message;
  - an image beyond the inline cap but inside the album cap is **not dropped**:
    it stays in the turn as a path-only marker pointing at `inspect_image`, fed
    by the index-aligned `mediaPaths`;
  - a legacy payload without `mediaPaths` keeps the text marker untouched, since
    there is no trustworthy path to substitute.
- An unsupported image format (anything outside `SupportedImageMimes`: SVG, HEIC,
  BMP, TIFF, …) is saved and never inlined. Its marker points at
  `fs_read`/`text_read`, never at `inspect_image`, because that tool would
  reject the file.
- Vision is decided per provider **and model** before each attempt
  (`visionSupport` in `domain/providers/media_pure.nim`, review E3), in three
  states. Only a model known to be text only (`deepseek-chat`,
  `deepseek-reasoner`, the GLM models without a `v` after the version) loses
  its `data:` images, through `withoutInlineImages`, which rewrites the marker
  and adds the removal note. Claude, Gemini, NVIDIA, the GLM `v` models and
  Qwen-VL are `vsYes`; anything not verified is `vsUnknown` and gets the image.
  The compat transport used to drop images itself for profiles with
  unverified vision, silently, while the marker still promised them; it no
  longer does.
- Image rejection is handled inside the turn loop, not inside the provider
  builders: `buildCompleteFn`/`buildAsyncCompleteFn` report the error and the
  retry lives in `runToolLoop`. The flag is part of the loop state, so it is
  **once per turn**, not once per provider call:
  - the streaming branch retries too, with the same flag and the same history
    demotion;
  - the measured shape is the rejected call plus one extra text-only call, and
    exactly one `[imagem removida: provider sem visão]` note in that retry
    request — a turn with three tool rounds makes 5 calls (3 tool + final +
    retry), not 4 retries;
  - right after arming the retry the loop demotes the persistent history
    (`demoteInlineImagesForTurn`), so later rounds rebuild a text-only request
    and the note is not re-appended. An album of image-only turns keeps one
    note so the request still has a user turn.
- Every caller that drives a turn through `runToolLoop` (channel, HTTP API,
  subagents) inherits the same retry; there is no second retry site.
- Session transcripts never store the base64: `transcriptImageRef` writes the
  opaque `inline` marker instead.

### Limits

| Constant | Value | Meaning |
|---|---:|---|
| `MaxInlineImageEncodedBytes` | 5 MiB | encoded data URL, not raw bytes (below Anthropic's 5 MB and OpenAI's 20 MB) |
| `MaxInlineImagesPerTurn` | 4 | only `data:` entries; paths/http are not capped here |
| `InlineImageApproxChars` | 1 024 | routing cost of an inline image |
| `MaxAttachmentsPerTurn` | 10 | whole-turn attachment cap (unchanged) |

The two caps are independent and both apply to the same album:

- the inline cap (`MaxInlineImagesPerTurn`) decides how many payloads travel as
  `data:`; the extras still appear as path-only `inspect_image` markers;
- the album cap (`MaxAttachmentsPerTurn`) decides how many attachments enter the
  turn at all. A 4-inline + 20-path album keeps 4 inline and 6 path entries; a
  6-inline album keeps 4 inline and 2 path-only markers.

## Voice flow

```text
text_to_speech(text, as_voice = true, caption)
  -> prepareVoiceReply(replyTo = ctx.replyTo)
       supports(channel, cfSendVoice) checked BEFORE any TTS call
       performSpeech(format = "opus")
       OutboundMessage(mediaUrl absolute, mediaRoot paddockDir, text = caption,
                       replyTo, mediaDurationSec = estimateSpeechSeconds)
  -> NativeToolResult.outbound
  -> async dispatcher awaits ctx.outbox.put
  -> channel adapter confines the path, then uploads local media as multipart
       denial -> neutral text, no path, file untouched
       Telegram: sendVoice for .ogg, sendAudio for .mp3/.m4a,
                 sendPhoto for images, sendDocument otherwise
```

- Without `as_voice`, the tool keeps the old behavior: the file is saved under
  `attachments/tts-*` and its path is returned as text. The attachment-store
  rework is deferred; nothing in this flow garbage-collects `attachments/`.
- `duration` is sent for `sendVoice` and `sendAudio` when
  `mediaDurationSec > 0`; without it, clients show 0:00.
- The voice note keeps the inbound anchor: the orchestrator copies the inbound
  `msg.replyTo` (the composite `chat#cmsg#thread` target) into the native
  context, and `prepareVoiceReply` puts it on the `OutboundMessage`. So
  `as_voice = true` stays in the forum topic and under the replied message
  instead of landing in the chat root.
- A channel without `cfSendVoice`, a TTS error or empty audio leaves the outbox
  untouched and no `tts-*` file behind; the reply falls back to text.
- Outbound media confinement: a local path is classified lexically
  (`classifyOutboundMediaPath`, pure) and then resolved with the canonical root
  and target (`resolveConfinedMediaPath`), so `..`, sibling directories sharing
  the paddock prefix and symlinks cannot move the read outside the producer's
  paddock. A denial produces the neutral `não foi possível enviar o anexo` text
  — never a path or file name — and the target file is not deleted. A missing
  or unreadable file gets the same notice.
- Local uploads preserve `message_thread_id`/`reply_to_message_id`, retry
  without the thread on the missing-thread error, and fall back from
  `sendPhoto` to `sendDocument`. The final failure is a neutral text with no
  path or file name.

## Tests

- Pure: `tests/domain/providers/t_inline_image_pure.nim`,
  `tests/core/t_routing_inline_image.nim`,
  `tests/domain/channels/t_telegram_upload_pure.nim`,
  `tests/domain/media/t_audio_pure.nim`,
  `tests/domain/tools/t_path_guard.nim`.
- Flow: `tests/app/t_inline_image_turn.nim` (album split, unsupported formats
  never pointing at `inspect_image`),
  `tests/app/t_inline_image_retention.nim`,
  `tests/app/t_image_fallback.nim` (turn-scoped retry: 5 calls and one note
  across three tool rounds), `tests/app/t_voice_reply.nim` (voice note keeps the
  composite forum target).
- Transport: `tests/adapters/channel/t_telegram_media_upload.nim` (fake HTTP,
  real 1 s Ogg/Opus and MP3 fixtures; framing and MIME, not decoded audio; a
  path outside the paddock becomes neutral text and the file survives) and
  `tests/adapters/filesystem/t_media_paths.nim`.
- Streaming retry: `tests/app/t_stream_tool_calls.nim` (2 calls, one note).
