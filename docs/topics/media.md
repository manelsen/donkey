# Media — images and voice

Two flows share one rule: a channel file is downloaded once, stored in the
paddock, and the model receives a bounded inline representation only when the
provider can take it.

## Image flow

```text
channel attachment
  -> paddock attachments/<name>
  -> applyInboundAttachment
       supported image + within limit -> msg.mediaUrl = data URL
       otherwise                      -> mediaUrl = "" + text marker (path)
  -> prompt building
       addUserTurnWithImages keeps at most 4 data: URLs (paths/http untouched)
  -> provider profile (CompatProfile / Anthropic / Gemini)
       image part in the provider envelope
  -> orchestrator, after the loop
       demoteInlineImages clears data: URLs, so later turns do not resend
```

- The inline decision is pure (`imageDataUrl`, `inlineImagesForTurn` in
  `domain/providers/media_pure.nim`).
- The text marker for a non-inlined image is unchanged; it points to the file
  and to `inspect_image`. Inlined images keep the same path in the marker and
  say the image already accompanies the turn.
- If every attempted provider rejects the image, `buildCompleteFn` /
  `buildAsyncCompleteFn` retry **once** with `withoutInlineImages` and append
  `[imagem removida: provider sem visão]` to the last user turn with text.
  This retry is global: channel, HTTP API and subagents share it.
- Session transcripts never store the base64: `transcriptImageRef` writes the
  opaque `inline` marker instead.

### Limits

| Constant | Value | Meaning |
|---|---:|---|
| `MaxInlineImageEncodedBytes` | 5 MiB | encoded data URL, not raw bytes (below Anthropic's 5 MB and OpenAI's 20 MB) |
| `MaxInlineImagesPerTurn` | 4 | only `data:` entries; paths/http are not capped here |
| `InlineImageApproxChars` | 1 024 | routing cost of an inline image |
| `MaxAttachmentsPerTurn` | 10 | whole-turn attachment cap (unchanged) |

## Voice flow

```text
text_to_speech(text, as_voice = true, caption)
  -> prepareVoiceReply
       supports(channel, cfSendVoice) checked BEFORE any TTS call
       performSpeech(format = "opus")
       OutboundMessage(mediaUrl absolute, text = caption,
                       mediaDurationSec = estimateSpeechSeconds)
  -> NativeToolResult.outbound
  -> async dispatcher awaits ctx.outbox.put
  -> channel adapter uploads local media as multipart
       Telegram: sendVoice for .ogg, sendAudio for .mp3/.m4a,
                 sendPhoto for images, sendDocument otherwise
```

- Without `as_voice`, the tool keeps the old behavior: the file is saved under
  `attachments/tts-*` and its path is returned as text.
- `duration` is sent for `sendVoice` and `sendAudio` when
  `mediaDurationSec > 0`; without it, clients show 0:00.
- A channel without `cfSendVoice`, a TTS error or empty audio leaves the outbox
  untouched and no `tts-*` file behind; the reply falls back to text.
- Local uploads preserve `message_thread_id`/`reply_to_message_id`, retry
  without the thread on the missing-thread error, and fall back from
  `sendPhoto` to `sendDocument`. The final failure is a neutral text with no
  path or file name.

## Tests

- Pure: `tests/domain/providers/t_inline_image_pure.nim`,
  `tests/core/t_routing_inline_image.nim`,
  `tests/domain/channels/t_telegram_upload_pure.nim`,
  `tests/domain/media/t_audio_pure.nim`.
- Flow: `tests/app/t_inline_image_turn.nim`,
  `tests/app/t_inline_image_retention.nim`,
  `tests/app/t_image_fallback.nim`, `tests/app/t_voice_reply.nim`.
- Transport: `tests/adapters/channel/t_telegram_media_upload.nim` (fake HTTP,
  real 1 s Ogg/Opus and MP3 fixtures; framing and MIME, not decoded audio).
