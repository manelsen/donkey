## telegram_policy.nim — outbound policies derived from the Bot API behavior.
##
## Pure functions only: the adapter decides when to call them, this module
## decides what the API contract requires.

import std/[json, strutils, unicode]
import ./telegram_split

func isEditNoopError*(message: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix 7ac9088d5c; see
  ## docs/hermes-mining/telegram/CASES.md#tg-002
  ##
  ## editMessageText answers 400 "message is not modified" when the new text is
  ## identical to the current one. The message is already what the caller
  ## wanted, so this is success, not a failure to retry.
  message.toLowerAscii().contains("message is not modified")

func isMissingReplyAnchorError*(message: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix b60cfd6ce6; see
  ## docs/hermes-mining/telegram/CASES.md#tg-005
  ##
  ## Replying to a message that was deleted answers 400 "message to be replied
  ## not found". The answer is still valid; only the anchor is gone.
  let lower = message.toLowerAscii()
  lower.contains("to be replied not found") or
    lower.contains("reply message not found")

func shouldSkipOutboundText*(text: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix 83dec2b3ec; see
  ## docs/hermes-mining/telegram/CASES.md#tg-006
  ##
  ## sendMessage refuses empty or whitespace-only text with 400 "message text
  ## is empty". Skipping the call keeps the turn from failing on nothing.
  text.strip.len == 0

func clipCaption*(text: string; limit = 1024): string =
  ## Behavior derived from hermes-agent (MIT) fix f828b087e7; see
  ## docs/hermes-mining/telegram/CASES.md#tg-007
  ##
  ## The media caption limit (1024) is smaller than the message body limit
  ## (4096). Clipping on a character boundary keeps the upload valid instead of
  ## letting the API refuse the whole media message.
  if limit <= 0:
    return ""
  var count = 0
  for _ in text.runes: inc count
  if count <= limit:
    return text
  var clipped = ""
  var kept = 0
  for r in text.runes:
    if kept + 1 > limit - 1:
      break
    clipped.add($r)
    inc kept
  clipped & "…"

func planEditChunks*(text: string; limit = 4096): seq[string] =
  ## Behavior derived from hermes-agent (MIT) fix bf1f40996f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-008
  ##
  ## editMessageText has the same 4096-unit limit as sendMessage. The first
  ## chunk replaces the current message; the rest must be delivered as new
  ## messages, or the tail is silently lost.
  splitForTelegram(text, limit)

func callbackDataError*(data: string): string =
  ## Behavior derived from hermes-agent (MIT) fix 6fb57bc9cf; see
  ## docs/hermes-mining/telegram/CASES.md#tg-009
  ##
  ## Telegram rejects a button whose callback_data is empty or exceeds 64
  ## bytes, and it rejects the whole message. Returning the reason keeps this
  ## pure; the adapter turns it into its own error.
  if data.len == 0:
    return "callback_data is empty"
  if data.len > 64:
    return "callback_data exceeds 64 bytes (" & $data.len & ")"
  ""

func splitCaption*(text: string; limit = 1024): tuple[head, tail: string] =
  ## Behavior derived from hermes-agent (MIT) fix f828b087e7; see
  ## docs/hermes-mining/telegram/CASES.md#tg-007
  ##
  ## The caption limit is 1024 characters. The head fits the media message; the
  ## tail must be delivered separately so no text is lost.
  var kept = 0
  var bytePos = 0
  for r in text.runes:
    if kept >= limit:
      break
    bytePos += r.size
    inc kept
  (text[0 ..< bytePos], text[bytePos .. ^1])

func withLinkPreviewPolicy*(body: JsonNode; previewsEnabled: bool): JsonNode =
  ## Behavior derived from hermes-agent (MIT) fix 00ff9a26cd; see
  ## docs/hermes-mining/telegram/CASES.md#tg-035
  ##
  ## Bot answers are usually technical text with URLs; an automatic preview
  ## card pushes the actual answer out of view. Previews stay off unless the
  ## operator opts in.
  result = body.copy()
  if not previewsEnabled:
    result["link_preview_options"] = %*{"is_disabled": true}

func linkPreviewsFromEnv*(value: string): bool =
  ## Parses the opt-in flag; anything but an explicit yes keeps previews off.
  value.strip.toLowerAscii in ["1", "true", "yes", "on"]

func asDocumentBody*(body: JsonNode): JsonNode =
  ## Behavior derived from hermes-agent (MIT) fix 6faa1965d7; see
  ## docs/hermes-mining/telegram/CASES.md#tg-027
  ##
  ## sendPhoto refuses images outside the dimension or size limits, while
  ## sendDocument accepts the same file. The fallback keeps the media instead
  ## of dropping it.
  result = body.copy()
  if result.hasKey("photo"):
    result["document"] = result["photo"]
    result.delete("photo")

func audioMethodFor*(url: string): string =
  ## Behavior derived from hermes-agent (MIT) fix b93996c35e; see
  ## docs/hermes-mining/telegram/CASES.md#tg-029
  ##
  ## Voice notes are OGG/OPUS and render as a bubble only through sendVoice;
  ## music files go through sendAudio so the client shows a player instead of
  ## a generic document.
  var lower = url.toLowerAscii()
  let cut = min(
    (if lower.find('?') >= 0: lower.find('?') else: lower.len),
    (if lower.find('#') >= 0: lower.find('#') else: lower.len))
  lower = lower[0 ..< cut]
  let dot = lower.rfind('.')
  if dot < 0:
    return ""
  let ext = lower[dot + 1 .. ^1]
  case ext
  of "ogg", "opus", "oga": "sendVoice"
  of "mp3", "m4a": "sendAudio"
  else: ""

func isPhotoRejectedError*(message: string): bool =
  ## Only the photo-specific refusals mean the file can still travel as a
  ## document. A timeout or any other error may have been accepted already, so
  ## retrying it as a different method would duplicate the media.
  let lower = message.toLowerAscii()
  lower.contains("image_process_failed") or
    lower.contains("photo_invalid_dimensions") or
    lower.contains("photo_save_file_invalid")

# ── apiBase policy ────────────────────────────────────────────────────────────

func bareTelegramHost(host: string): string =
  ## Host without brackets or port, used only for the loopback decision.
  if host.startsWith("["):
    let close = host.find(']')
    if close > 0:
      return host[1 ..< close]
  let colon = host.rfind(':')
  if colon >= 0: host[0 ..< colon] else: host

func telegramApiHost*(apiBase: string): string =
  ## Host exactly as the HTTP transport derives it from a URL (it includes the
  ## port), so the same string can be used as an allowlist entry.
  let base = apiBase.strip
  let marker = base.find("://")
  if marker < 0:
    return ""
  var host = base[marker + 3 .. ^1]
  let slash = host.find('/')
  if slash >= 0:
    host = host[0 ..< slash]
  let query = host.find('?')
  if query >= 0:
    host = host[0 ..< query]
  let fragment = host.find('#')
  if fragment >= 0:
    host = host[0 ..< fragment]
  let at = host.rfind('@')
  if at >= 0:
    host = host[at + 1 .. ^1]
  host.strip

func isLoopbackHost*(host: string): bool =
  ## A development proxy may speak plain http on the local machine only.
  let bare = bareTelegramHost(host).toLowerAscii()
  bare == "localhost" or bare == "::1" or bare.startsWith("127.")

func telegramApiBaseError*(apiBase: string): string =
  ## Reason a custom Base URL is refused; empty means it is acceptable.
  let base = apiBase.strip
  if base.len == 0:
    return ""
  let marker = base.find("://")
  if marker <= 0:
    return "apiBase must be an absolute https URL"
  let scheme = base[0 ..< marker].toLowerAscii()
  let host = telegramApiHost(base)
  if host.len == 0:
    return "apiBase has no host"
  if scheme == "https":
    return ""
  if scheme == "http":
    if isLoopbackHost(host):
      return ""
    return "apiBase must use https outside loopback"
  "apiBase must use https"

func telegramApiAllowlist*(apiBase: string): seq[string] =
  ## Egress is restricted to the configured Bot API host. An empty override
  ## keeps the official endpoint; a custom base contributes its own host
  ## instead of disabling the allowlist.
  let base = apiBase.strip
  if base.len == 0:
    return @["api.telegram.org"]
  let host = telegramApiHost(base)
  if host.len == 0: @[] else: @[host]


# ── local media upload ────────────────────────────────────────────────────────

const TelegramMultipartBoundaryPrefix* = "----donkey-tg-"
  ## Prefix for the random multipart delimiter. The random portion is supplied
  ## by the adapter (sysrand) so the boundary is not predictable from the clock.

func stripMultipartControls(value: string): string =
  ## Removes CR/LF so a field value can never start a new multipart part.
  for ch in value:
    if ch != '\r' and ch != '\n':
      result.add ch

func numericMultipartId(value: string): string =
  ## Telegram ids are signed integers. Anything else is dropped instead of
  ## being framed into the payload.
  let v = value.strip
  if v.len == 0:
    return ""
  var start = 0
  if v[0] == '-':
    start = 1
  if start >= v.len:
    return ""
  for i in start ..< v.len:
    if v[i] notin {'0' .. '9'}:
      return ""
  v

func pickMultipartBoundary*(randomHex, payload: string): string =
  ## Builds the boundary from caller-supplied randomness, then perturbs it
  ## deterministically until it does not occur in the payload. The candidate
  ## itself is never reused when the bytes happen to contain it.
  result = TelegramMultipartBoundaryPrefix & randomHex
  var salt = 0
  while payload.contains(result):
    inc salt
    result = TelegramMultipartBoundaryPrefix & randomHex & "-" & $salt

type
  MediaUpload* = object
    ## Everything a multipart `send*` call needs, decided without I/O.
    `method`*:    string  ## Bot API method: sendVoice, sendAudio, sendPhoto, sendDocument
    field*:       string  ## multipart field that carries the file
    mime*:        string
    chatId*:      int64
    caption*:     string
    threadId*:    string
    replyTo*:     string
    durationSec*: int     ## 0 → omitted; sendVoice/sendAudio only
    fileName*:    string

func mediaBaseName(path: string): string =
  ## Last path component without importing os: the policy stays pure.
  let cut = max(path.rfind('/'), path.rfind('\\'))
  if cut < 0: path else: path[cut + 1 .. ^1]

func mediaExtension(path: string): string =
  let name = mediaBaseName(path)
  let dot = name.rfind('.')
  if dot < 0: "" else: name[dot + 1 .. ^1].toLowerAscii()

func mediaMimeFor(ext: string): string =
  case ext
  of "jpg", "jpeg": "image/jpeg"
  of "png":         "image/png"
  of "gif":         "image/gif"
  of "webp":        "image/webp"
  of "pdf":         "application/pdf"
  else:             "application/octet-stream"

func mediaUploadSpec*(path: string; chatId: int64; caption: string;
                      threadId = ""; replyTo = ""; durationSec = 0): MediaUpload =
  ## Chooses the Bot API method from the file name. The adapter only reads the
  ## bytes and posts them; method, field and MIME are decided here. Every value
  ## that travels in the multipart envelope is sanitised at the boundary.
  let ext = mediaExtension(path)
  let audioMethod = audioMethodFor(path)
  result.fileName = stripMultipartControls(mediaBaseName(path)).replace("\"", "'")
  result.chatId = chatId
  result.caption = stripMultipartControls(caption)
  result.threadId = numericMultipartId(threadId)
  result.replyTo = numericMultipartId(replyTo)
  result.durationSec = max(0, durationSec)
  if audioMethod == "sendVoice":
    result.`method` = "sendVoice"
    result.field = "voice"
    result.mime = "audio/ogg"
  elif audioMethod == "sendAudio":
    result.`method` = "sendAudio"
    result.field = "audio"
    result.mime = if ext == "m4a": "audio/mp4" else: "audio/mpeg"
  elif ext in ["jpg", "jpeg", "png", "gif", "webp"]:
    result.`method` = "sendPhoto"
    result.field = "photo"
    result.mime = mediaMimeFor(ext)
  else:
    result.`method` = "sendDocument"
    result.field = "document"
    result.mime = mediaMimeFor(ext)

func mediaUploadBody*(spec: MediaUpload; data, boundary: string): string =
  ## Multipart/form-data framing for the Bot API. Optional fields are omitted
  ## instead of sent empty; `duration` only exists for the two audio methods
  ## the client renders with a clock (TG-029). Values are re-sanitised here so
  ## a directly constructed MediaUpload cannot inject framing either.
  let caption = stripMultipartControls(spec.caption)
  let threadId = numericMultipartId(spec.threadId)
  let replyTo = numericMultipartId(spec.replyTo)
  let fileName = stripMultipartControls(spec.fileName).replace("\"", "'")
  result = ""
  result.add("--" & boundary & "\r\n")
  result.add("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n")
  result.add($spec.chatId & "\r\n")
  if caption.len > 0:
    result.add("--" & boundary & "\r\n")
    result.add("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
    result.add(caption & "\r\n")
  if threadId.len > 0:
    result.add("--" & boundary & "\r\n")
    result.add("Content-Disposition: form-data; name=\"message_thread_id\"\r\n\r\n")
    result.add(threadId & "\r\n")
  if replyTo.len > 0:
    result.add("--" & boundary & "\r\n")
    result.add("Content-Disposition: form-data; name=\"reply_to_message_id\"\r\n\r\n")
    result.add(replyTo & "\r\n")
  if spec.durationSec > 0 and spec.`method` in ["sendVoice", "sendAudio"]:
    result.add("--" & boundary & "\r\n")
    result.add("Content-Disposition: form-data; name=\"duration\"\r\n\r\n")
    result.add($spec.durationSec & "\r\n")
  result.add("--" & boundary & "\r\n")
  result.add("Content-Disposition: form-data; name=\"" & spec.field &
             "\"; filename=\"" & fileName & "\"\r\n")
  result.add("Content-Type: " & spec.mime & "\r\n\r\n")
  result.add(data)
  result.add("\r\n--" & boundary & "--\r\n")

func isAddressedToBot*(text, botUsername: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix 1e18e0503f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-015
  ##
  ## A group message addresses the bot when it mentions @username as a word.
  ## Matching is case-insensitive and requires a boundary, so @mybot2 does not
  ## wake @mybot.
  if botUsername.len == 0 or text.len == 0:
    return false
  let needle = "@" & botUsername.toLowerAscii()
  let lower = text.toLowerAscii()
  ## Command form: `/cmd@bot` addresses the bot even though the mention is
  ## glued to the command name.
  if lower[0] == '/':
    let space = lower.find(' ')
    let token = if space < 0: lower else: lower[0 ..< space]
    if token.endsWith(needle):
      return true
  var start = 0
  while true:
    let at = lower.find(needle, start)
    if at < 0:
      return false
    let after = at + needle.len
    let beforeOk = at == 0 or lower[at - 1] notin {'a' .. 'z', '0' .. '9', '_', '@'}
    ## A trailing period ends the sentence; a period followed by a domain
    ## character is part of an address and does not address the bot.
    let afterOk =
      if after >= lower.len: true
      elif lower[after] == '.':
        after + 1 >= lower.len or
          lower[after + 1] notin {'a' .. 'z', '0' .. '9', '_'}
      else:
        lower[after] notin {'a' .. 'z', '0' .. '9', '_'}
    if beforeOk and afterOk:
      return true
    start = after

func mentionRequiredFromEnv*(value: string): bool =
  ## Opt-in gate; anything but an explicit yes keeps the previous behaviour.
  value.strip.toLowerAscii in ["1", "true", "yes", "on"]

func isMissingThreadError*(message: string): bool =
  ## Behavior derived from hermes-agent (MIT) fix 41d9d08078; see
  ## docs/hermes-mining/telegram/CASES.md#tg-026
  ##
  ## A deleted or stale forum topic answers 400 "message thread not found".
  ## The message is still valid for the chat root.
  let lower = message.toLowerAscii()
  lower.contains("thread not found") or
    lower.contains("message thread not found")

func albumKey*(chatId, mediaGroupId: string): string =
  ## Behavior derived from hermes-agent (MIT) fix 8fb618234f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-028
  ##
  ## An album's caption lives on one item only. The key groups the siblings of
  ## the same user action; the window that remembers them lives in the app.
  if mediaGroupId.len == 0: "" else: chatId & "|" & mediaGroupId
