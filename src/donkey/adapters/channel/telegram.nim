## TelegramAdapter — ChannelPort via Bot API long polling.
##
## Auth: BOT_TOKEN in Authorization header / URL path.
## API base: https://api.telegram.org/bot{token}/
##
## Quirks absorbed here:
##   - getUpdates long-polling: offset, limit, timeout params
##   - sendMessage supports parse_mode=HTML (converted from Markdown)
##   - ack advances the offset (offset = update_id + 1)
##
## IdentityResolver is now in adapters/identity — maps telegram_user_id → UserId.

import std/[json, os, sequtils, strutils, sysrand, tables]
when defined(posix):
  import std/posix
import ../../core/types
import ../../core/pipeops
import ../../config/environment
import ../../core/commands/command_catalog
import ../../core/telegram_format
import ../../core/channels/flood_gate
import ../../core/media_download
import ../../domain/message
import ../../domain/channels/telegram_pure
import ../../domain/channels/telegram_split
import ../../domain/channels/telegram_policy
import ../../ports/http
import ../../ports/channel
import ../http/std_http
import ../filesystem/paths
import ../filesystem/confined_read
export confined_read
import ../identity/identity_resolver

export identity_resolver
export sanitizeForTelegram
export FileDownload

const
  TelegramApiBase*   = "https://api.telegram.org"
  DefaultPollTimeout = 1    ## 1 s: short enough for multi-channel fairness
  TelegramMaxChars*  = 4096 ## Telegram sendMessage hard limit
  TelegramCaptionLimit* = 1024 ## media caption limit
  TelegramMaxUploadBytes* = 50 * 1024 * 1024
    ## Bot API upload ceiling. The size is checked before any byte is read, so
    ## an oversized local file never allocates or travels.
  TelegramUploadReadChunk = 64 * 1024

const TelegramReactionFallbacks* = ["👍", "👌", "✅", "🔥", "👏"]

const MediaUnavailableText* = "não foi possível enviar o anexo"
  ## Final fallback for a failed local upload. It must never contain the path
  ## or the file name: the chat is not allowed to learn the host layout.

type
  TelegramSettings* = object
    ## Deployment knobs of the Telegram adapter, read once from the environment
    ## snapshot by `telegramSettings`.
    botUsername*:     string  ## without "@"; enables mention handling in groups
    requireMention*:  bool
    linkPreviews*:    bool
    httpTimeoutSec*:  int
    mediaTimeoutSec*: int
    proxyUrl*:        string

  TelegramAdapter* = object
    token*:       string
    configError*: string        ## invalid apiBase/proxy; sends fail closed
    apiBase*:     string        ## override for testing (e.g. mock server URL)
    offset*:      int64         ## getUpdates offset (mutable via receive)
    resolver*:    IdentityResolver
    http*:        StdHttpAdapter
    uploadHttp*:  HttpRuntimePort ## media uploads; same proxy/allowlist as http
    flood*:       FloodGate      ## per-chat penalty windows
    chatIds*:     Table[string, string] ## userId → source chat id
    pollTimeout*: int           ## seconds; 1 for multi-channel, up to 30 for solo
    settings*:    TelegramSettings
    mediaValidatedHook*: proc (canonicalPath: string) {.gcsafe, raises: [].}
      ## Test-only seam fired after confinement and before the descriptor read.
      ## Production adapters leave it nil.

# ── API helpers ───────────────────────────────────────────────────────────────

func apiBaseValue*(a: TelegramAdapter): string =
  ## Base used for Bot API calls. Empty keeps the official endpoint; a proxy
  ## can be supplied through DONKEY_TELEGRAM_API_BASE.
  if a.apiBase.len > 0: a.apiBase else: TelegramApiBase

proc chatIdFor(a: TelegramAdapter; userId: UserId): string =
  ## Behavior derived from hermes-agent (MIT) fix 1a9a2d7fe8; see
  ## docs/hermes-mining/telegram/CASES.md#tg-015
  ##
  ## In a group the chat id is not the sender id. The adapter remembers the
  ## chat each user last wrote from and uses it as the send target.
  let remembered = a.chatIds.getOrDefault($userId, "")
  if remembered.len > 0:
    return remembered
  a.resolver.reverseChannel(userId, ckTelegram)

func apiUrl(a: TelegramAdapter; meth: string): string =
  a.apiBaseValue & "/bot" & a.token & "/" & meth

func positiveSecondsOr(raw: string; fallback: int): int =
  let value = raw.strip
  if value.len == 0:
    return fallback
  let parsed = try:
    value.parseInt
  except ValueError:
    return fallback
  if parsed <= 0: fallback else: parsed

func telegramSettings*(env: Environment): TelegramSettings =
  ## - `DONKEY_TELEGRAM_BOT_USERNAME`, `DONKEY_TELEGRAM_REQUIRE_MENTION`,
  ##   `DONKEY_TELEGRAM_LINK_PREVIEW`.
  ## - `DONKEY_TELEGRAM_TIMEOUT_SEC` (default 60) bounds Bot API calls and
  ##   `DONKEY_TELEGRAM_MEDIA_TIMEOUT_SEC` (default 300) uploads, which are
  ##   slower (hermes-agent (MIT) fixes 04057250a3 and 85e673b4a5; see
  ##   docs/hermes-mining/telegram/CASES.md#tg-030).
  ## - The Bot API may only be reachable through a proxy:
  ##   `DONKEY_TELEGRAM_PROXY` wins over `DONKEY_WEB_PROXY` (hermes-agent fix
  ##   d7c41f3cef; CASES.md#tg-022).
  TelegramSettings(
    botUsername: env.stripped("DONKEY_TELEGRAM_BOT_USERNAME").strip(chars = {'@'}),
    requireMention: mentionRequiredFromEnv(env.get("DONKEY_TELEGRAM_REQUIRE_MENTION")),
    linkPreviews: linkPreviewsFromEnv(env.get("DONKEY_TELEGRAM_LINK_PREVIEW")),
    httpTimeoutSec: positiveSecondsOr(env.get("DONKEY_TELEGRAM_TIMEOUT_SEC"), 60),
    mediaTimeoutSec: positiveSecondsOr(env.get("DONKEY_TELEGRAM_MEDIA_TIMEOUT_SEC"), 300),
    proxyUrl: env.stripped("DONKEY_TELEGRAM_PROXY", env.stripped("DONKEY_WEB_PROXY")))

proc parseTgResp(meth: string; resp: HttpResponse): Result[JsonNode, string]
                 {.gcsafe, raises: [].} =
  ## Validates a Telegram API HTTP response; designed for >>= chaining.
  try:
    let parsed = parseJson(resp.body)
    if not parsed["ok"].getBool(false):
      return err("Telegram API error [" & meth & "]: " & $parsed)
    ok(parsed)
  except CatchableError as e:
    err(e.msg)

proc postWith(a: TelegramAdapter; meth: string; body: JsonNode;
              timeoutSec: int): Result[JsonNode, string] {.gcsafe, raises: [].} =
  try:
    let headers = @[("Content-Type", "application/json")]
    let sent =
      if timeoutSec > 0:
        a.http.postWithTimeout(a.apiUrl(meth), $body, headers, timeoutSec)
      else:
        a.http.post(a.apiUrl(meth), $body, headers)
    sent >>=
      proc(resp: HttpResponse): Result[JsonNode, string] {.gcsafe, raises: [].} =
        parseTgResp(meth, resp)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)

proc post(a: TelegramAdapter; meth: string;
          body: JsonNode): Result[JsonNode, string] {.gcsafe, raises: [].} =
  a.postWith(meth, body, 0)

proc postMultipart(a: TelegramAdapter; meth, body, boundary: string;
                   chatId: int64): Result[JsonNode, string] {.gcsafe, raises: [].} =
  ## Local media travels as multipart/form-data. The upload port is the one the
  ## caller injected, so the transfer is testable without Telegram. Redirects
  ## are not followed when the port supports it: the bot token travels in the
  ## URL path and must not reach another origin.
  if a.uploadHttp.post.isNil and a.uploadHttp.postNoRedirect.isNil:
    return err("TelegramAdapter: no upload transport")
  try:
    let headers = @[("Content-Type", "multipart/form-data; boundary=" & boundary)]
    let waitMs = a.flood.remainingMs(chatId, epochMs())
    if waitMs > 0:
      sleep(int(min(waitMs, FloodMaxWaitMs)))
    let sent =
      if not a.uploadHttp.postNoRedirect.isNil:
        a.uploadHttp.postNoRedirect(a.apiUrl(meth), body, headers)
      else:
        a.uploadHttp.post(a.apiUrl(meth), body, headers)
    let res = sent >>=
      proc(resp: HttpResponse): Result[JsonNode, string] {.gcsafe, raises: [].} =
        parseTgResp(meth, resp)
    if res.isErr:
      let retryAfter = parseRetryAfterMs(res.error)
      if retryAfter > 0:
        a.flood.noteRetryAfter(chatId, retryAfter, epochMs())
    res
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)

proc randomBoundaryHex(bytes = 24): string =
  ## Cryptographically random delimiter seed (never the clock). An empty string
  ## means the OS random source failed; the caller must fail closed.
  var raw = newSeq[byte](bytes)
  if not urandom(raw):
    return ""
  for b in raw:
    result.add(toHex(b, 2).toLowerAscii())

func mediaScanText(spec: MediaUpload; data: string): string =
  ## Everything the multipart envelope will contain. The boundary must not
  ## occur here, or a value could be mistaken for a delimiter.
  data & "\n" & spec.caption & "\n" & spec.fileName & "\n" &
    spec.threadId & "\n" & spec.replyTo & "\n" & spec.field & "\n" & spec.mime

proc postMediaUpload(a: TelegramAdapter; spec: MediaUpload;
                     data: string): Result[JsonNode, string] =
  let seed = randomBoundaryHex()
  if seed.len == 0:
    return err(MediaUnavailableText)
  let boundary = pickMultipartBoundary(seed, mediaScanText(spec, data))
  if boundary.len == 0:
    return err(MediaUnavailableText)
  a.postMultipart(spec.`method`, mediaUploadBody(spec, data, boundary),
                  boundary, spec.chatId)


proc postJsonOnUpload(a: TelegramAdapter; meth: string; body: JsonNode):
                      Result[JsonNode, string] {.gcsafe, raises: [].} =
  ## Last-resort text for a failed upload. It uses the same injected port (and
  ## therefore the same proxy/allowlist) so the fallback is observable in tests
  ## and never depends on a second transport.
  if a.uploadHttp.post.isNil:
    return err("TelegramAdapter: no upload transport")
  try:
    let headers = @[("Content-Type", "application/json")]
    let sent = a.uploadHttp.post(a.apiUrl(meth), $body, headers)
    sent >>=
      proc(resp: HttpResponse): Result[JsonNode, string] {.gcsafe, raises: [].} =
        parseTgResp(meth, resp)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err(e.msg)

func chatAllowedReactionEmojis*(chatInfo: JsonNode): tuple[restricted: bool, emojis: seq[string]]
                               {.gcsafe, raises: [].} =
  let available = chatInfo{"available_reactions"}
  if available.isNil or available.kind != JArray:
    return (false, @[])
  result.restricted = true
  for item in available:
    if item.getOrDefault("type").getStr("") != "emoji":
      continue
    let emoji = item.getOrDefault("emoji").getStr("")
    if emoji.len > 0:
      result.emojis.add(emoji)

func pickTelegramReactionEmoji*(desired: string; chatInfo: JsonNode): string
                               {.gcsafe, raises: [].} =
  if desired.len == 0:
    return ""
  let (restricted, emojis) = chatAllowedReactionEmojis(chatInfo)
  if not restricted:
    return desired
  if desired in emojis:
    return desired
  for fallback in TelegramReactionFallbacks:
    if fallback in emojis:
      return fallback
  if emojis.len > 0:
    return emojis[0]
  ""

func renderTelegramHtml*(text: string; isHtml = false): string =
  let sanitized = sanitizeForTelegram(text)
  if isHtml: sanitized
  else: markdownToTelegramHtml(sanitized)

# ── ChannelPort implementation ────────────────────────────────────────────────

proc applyReplyTarget(body: var JsonNode; replyTo: string; firstChunk: bool) =
  ## Splits the composite reply target into the message id and the forum
  ## thread. The anchor belongs to the first chunk only, but the thread belongs
  ## to every chunk, or the continuation lands in the general topic.
  if replyTo.len == 0:
    return
  let (chatId, messageId, threadId) = splitTelegramReplyTarget(replyTo)
  if chatId.len > 0:
    try:
      body["chat_id"] = %parseInt(chatId)
    except ValueError:
      discard
  if firstChunk and messageId.len > 0:
    try:
      body["reply_to_message_id"] = %parseInt(messageId)
    except ValueError:
      discard
  if threadId.len > 0:
    try:
      body["message_thread_id"] = %parseInt(threadId)
    except ValueError:
      discard

proc sendMessageBody(a: TelegramAdapter; body: JsonNode; replyTo: string;
                     firstChunk: bool): Result[JsonNode, string] {.gcsafe.} =
  ## Posts a sendMessage payload. When the reply anchor no longer exists, the
  ## API refuses the whole message; retry once without the anchor so the text
  ## still arrives. A per-chat flood window is respected before the call.
  let chatId = body.getOrDefault("chat_id").getBiggestInt(0)
  let waitMs = a.flood.remainingMs(chatId, epochMs())
  if waitMs > 0:
    sleep(int(min(waitMs, FloodMaxWaitMs)))
  let res = a.post("sendMessage", body)
  if res.isErr:
    let retryAfter = parseRetryAfterMs(res.error)
    if retryAfter > 0:
      a.flood.noteRetryAfter(chatId, retryAfter, epochMs())
  if res.isOk: return res
  if firstChunk and replyTo.len > 0 and isMissingReplyAnchorError(res.error):
    var retry = body
    retry.delete("reply_to_message_id")
    return a.post("sendMessage", retry)
  if body.hasKey("message_thread_id") and isMissingThreadError(res.error):
    ## The topic is gone; deliver to the chat root instead of dropping it.
    var retry = body
    retry.delete("message_thread_id")
    let second = a.post("sendMessage", retry)
    if second.isOk or not isMissingReplyAnchorError(second.error):
      return second
    retry.delete("reply_to_message_id")
    return a.post("sendMessage", retry)
  res

proc sendChunkOnce(a: TelegramAdapter; chatId: int64; text, replyTo: string;
                   firstChunk: bool;
                   isHtml = false): Result[void, string] =
  ## Sends one chunk with HTML (converted from MD), falling back to plain text.
  let html = renderTelegramHtml(text, isHtml)
  var body = %* {"chat_id": chatId, "text": html, "parse_mode": "HTML"}
  applyReplyTarget(body, replyTo, firstChunk)
  body = withLinkPreviewPolicy(body, a.settings.linkPreviews)
  let res = a.sendMessageBody(body, replyTo, firstChunk)
  if res.isOk: return ok()
  ## Fallback: plain text
  var plain = %* {"chat_id": chatId, "text": text}
  applyReplyTarget(plain, replyTo, firstChunk)
  plain = withLinkPreviewPolicy(plain, a.settings.linkPreviews)
  discard ? a.sendMessageBody(plain, replyTo, firstChunk)
  ok()

proc sendChunk(a: TelegramAdapter; chatId: int64; text, replyTo: string;
               firstChunk: bool;
               isHtml = false): Result[void, string] =
  ## Behavior derived from hermes-agent (MIT) fix 595f3a289c; see
  ## docs/hermes-mining/telegram/CASES.md#tg-013
  ##
  ## Sends one chunk, retrying once when flood control refused it. The chunks
  ## already delivered are not resent: the retry starts at the refused chunk.
  var retried = false
  while true:
    let sent = a.sendChunkOnce(chatId, text, replyTo, firstChunk, isHtml)
    if sent.isOk:
      return ok()
    if not shouldRetryChunk(sent.error, retried):
      return sent
    retried = true

proc sendTyping*(a: TelegramAdapter; userId: UserId): Result[void, string] {.gcsafe.} =
  ## Sends a "typing…" indicator to the user's chat.
  ## For DM bots the chat_id equals the Telegram user ID.
  let rawId = a.chatIdFor(userId)
  if rawId.len == 0: return err("TelegramAdapter.sendTyping: no id for " & $userId)
  try:
    let tgId = parseBiggestInt(rawId).int64
    discard ? a.post("sendChatAction", %* {"chat_id": tgId, "action": "typing"})
    ok()
  except ValueError:
    err("TelegramAdapter.sendTyping: bad id: " & rawId)

func isRemoteMediaUrl(url: string): bool =
  ## Only an explicit http(s) URL is allowed to travel as JSON to Telegram.
  ## Everything else is treated as a local path: a missing, relative or
  ## directory path must never be sent to the chat as text.
  let lower = url.strip.toLowerAscii()
  lower.startsWith("http://") or lower.startsWith("https://")

func mediaChatId(tgId: int64; replyTo: string): int64 =
  ## The chat that owns the reply anchor is the destination, exactly like the
  ## text path (applyReplyTarget). `tgId` is only the fallback.
  let (chatId, _, _) = splitTelegramReplyTarget(replyTo)
  if chatId.len > 0:
    try:
      let parsed = parseBiggestInt(chatId).int64
      if parsed != 0:
        return parsed
    except ValueError:
      discard
  tgId

proc sendMediaFallbackText(a: TelegramAdapter; tgId: int64;
                           replyTo: string): Result[void, string] =
  ## Delivers a neutral line when every media attempt failed. Errors are
  ## replaced by the same line so no transport detail (and no path) leaks. A
  ## dead topic or reply anchor is dropped so the notice still arrives.
  var body = %* {"chat_id": tgId, "text": MediaUnavailableText}
  applyReplyTarget(body, replyTo, true)
  var res = a.postJsonOnUpload("sendMessage", body)
  if res.isErr and body.hasKey("message_thread_id") and
     isMissingThreadError(res.error):
    var retry = body
    retry.delete("message_thread_id")
    retry.delete("reply_to_message_id")
    body = retry
    res = a.postJsonOnUpload("sendMessage", body)
  if res.isErr and body.hasKey("reply_to_message_id") and
     isMissingReplyAnchorError(res.error):
    var retry = body
    retry.delete("reply_to_message_id")
    res = a.postJsonOnUpload("sendMessage", retry)
  if res.isOk: ok() else: err(MediaUnavailableText)

proc sendLocalMedia(a: TelegramAdapter; tgId: int64; path, caption,
                    replyTo, mediaRoot: string;
                    durationSec: int): Result[void, string] =
  ## Reads an existing local file and uploads it as multipart. The path is
  ## confined to the paddock before any byte is read and the bytes come from
  ## the descriptor validated against that confinement; a denial is the same
  ## neutral notice as a missing file and never deletes the target. The
  ## destination comes from the reply target (same rule as text), the topic and
  ## reply anchor are preserved, and a deleted topic/anchor is retried without
  ## the dead reference. A photo refused for its own limits is retried as a
  ## document; any other error is not duplicated.
  let chatId = mediaChatId(tgId, replyTo)
  let confined = resolveConfinedMediaPath(mediaRoot, path)
  if confined.isErr:
    return a.sendMediaFallbackText(chatId, replyTo)
  let safePath = confined.value
  if not a.mediaValidatedHook.isNil:
    ## Test seam: lets a test win the race between validation and the read.
    a.mediaValidatedHook(safePath)
  ## The bytes come from the descriptor opened one component at a time after
  ## validation, never from the name again: a link swapped in during the hook
  ## is opened as the link it now is and refused.
  var opened = openPathComponent(mediaRoot, safePath)
  if opened.isErr:
    return a.sendMediaFallbackText(chatId, replyTo)
  var component = opened.value
  let loaded = component.readPathComponent(TelegramMaxUploadBytes)
  component.closeComponent()
  if loaded.isErr:
    return a.sendMediaFallbackText(chatId, replyTo)
  let data = loaded.value
  let (_, replyId, threadId) = splitTelegramReplyTarget(replyTo)
  var spec = mediaUploadSpec(component.name, chatId,
                             clipCaption(caption, TelegramCaptionLimit),
                             threadId, replyId, durationSec)
  var res = a.postMediaUpload(spec, data)
  if res.isErr and spec.threadId.len > 0 and isMissingThreadError(res.error):
    ## The topic is gone; deliver to the chat root instead of dropping it.
    spec.threadId = ""
    spec.replyTo = ""
    res = a.postMediaUpload(spec, data)
  if res.isErr and spec.replyTo.len > 0 and
     isMissingReplyAnchorError(res.error):
    ## The anchor is gone; the media still belongs in the chat/topic.
    spec.replyTo = ""
    res = a.postMediaUpload(spec, data)
  if res.isOk: return ok()
  if spec.`method` == "sendPhoto" and isPhotoRejectedError(res.error):
    ## A photo outside the dimension/size limits is still a valid document.
    var docSpec = spec
    docSpec.`method` = "sendDocument"
    docSpec.field = "document"
    let docRes = a.postMediaUpload(docSpec, data)
    if docRes.isOk: return ok()
  a.sendMediaFallbackText(chatId, replyTo)

proc sendMedia*(a: TelegramAdapter; tgId: int64;
                url, caption, replyTo: string;
                durationSec = 0; mediaRoot = ""): Result[void, string] =
  ## Sends a photo (if URL looks like an image) or a document otherwise, or
  ## uploads a local file as multipart with the same routing. A local file must
  ## live inside `mediaRoot`; the confinement happens in `sendLocalMedia`.
  ## Falls back to neutral text if every attempt fails.
  if a.configError.len > 0:
    return err("TelegramAdapter: " & a.configError)
  if not isRemoteMediaUrl(url):
    return a.sendLocalMedia(tgId, url, caption, replyTo, mediaRoot, durationSec)
  let audioMethod = audioMethodFor(url)
  let isImage = url.endsWith(".jpg") or url.endsWith(".jpeg") or
                url.endsWith(".png") or url.endsWith(".gif") or
                url.endsWith(".webp")
  let meth =
    if audioMethod.len > 0: audioMethod
    elif isImage: "sendPhoto"
    else: "sendDocument"
  let fileKey =
    case meth
    of "sendPhoto": "photo"
    of "sendVoice": "voice"
    of "sendAudio": "audio"
    else: "document"
  var body = %* {"chat_id": tgId, fileKey: url}
  if caption.len > 0:
    body["caption"] = %clipCaption(caption, TelegramCaptionLimit)
  if durationSec > 0 and meth in ["sendVoice", "sendAudio"]:
    body["duration"] = %durationSec
  applyReplyTarget(body, replyTo, true)
  let mediaTimeout = a.settings.mediaTimeoutSec
  var res = a.postWith(meth, body, mediaTimeout)
  if res.isOk: return ok()
  if body.hasKey("message_thread_id") and isMissingThreadError(res.error):
    ## The topic is gone; retry the same media in the chat root.
    var retry = body
    retry.delete("message_thread_id")
    retry.delete("reply_to_message_id")
    let second = a.postWith(meth, retry, mediaTimeout)
    if second.isOk: return ok()
    body = retry
    res = second
  if meth == "sendPhoto" and isPhotoRejectedError(res.error):
    ## A photo outside the dimension/size limits is still a valid document.
    let docRes = a.postWith("sendDocument", asDocumentBody(body), mediaTimeout)
    if docRes.isOk: return ok()
  ## Fallback: send URL as text, in the same chat and topic.
  var textBody = %* {"chat_id": tgId, "text": url}
  applyReplyTarget(textBody, replyTo, true)
  textBody = withLinkPreviewPolicy(textBody, a.settings.linkPreviews)
  let textRes = a.sendMessageBody(textBody, replyTo, true)
  if textRes.isOk: return ok()
  err(textRes.error)

proc validateButtons(buttons: seq[seq[(string, string)]]): Result[void, string] =
  for row in buttons:
    for (_, data) in row:
      let reason = callbackDataError(data)
      if reason.len > 0:
        return err(reason)
  ok()

proc sendKeyboardRaw(a: TelegramAdapter; chatId: int64;
                     text: string;
                     buttons: seq[seq[(string, string)]];
                     replyTo: string;
                     isHtml = false): Result[string, string] =
  ## Internal helper: sends a keyboard message to a known chatId.
  ## Returns the Telegram message_id of the sent message.
  ? validateButtons(buttons)
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  let html = renderTelegramHtml(text, isHtml)
  var body = %* {
    "chat_id":    chatId,
    "text":       html,
    "parse_mode": "HTML",
    "reply_markup": {"inline_keyboard": rows},
  }
  body = withLinkPreviewPolicy(body, a.settings.linkPreviews)
  applyReplyTarget(body, replyTo, true)
  var res = a.post("sendMessage", body)
  if res.isErr and body.hasKey("message_thread_id") and
     isMissingThreadError(res.error):
    var retry = body
    retry.delete("message_thread_id")
    retry.delete("reply_to_message_id")
    res = a.post("sendMessage", retry)
  if res.isOk:
    return ok($res.value["result"]["message_id"].getInt())
  body.delete("parse_mode")
  body["text"] = %text
  let plain = ? a.post("sendMessage", body)
  ok($plain["result"]["message_id"].getInt())

proc send*(a: TelegramAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message with Markdown (plain-text fallback), split at 4096 chars.
  ## If msg.keyboard is non-empty, sends with an inline keyboard.
  ## If msg.mediaUrl is set, sends as photo/document (caption = msg.text).
  if a.configError.len > 0:
    return err("TelegramAdapter: " & a.configError)
  let rawId = a.chatIdFor(msg.userId)
  if rawId.len == 0: return err("TelegramAdapter.send: no id for " & $msg.userId)
  let chatId = parseBiggestInt(rawId).int64

  if shouldSkipOutboundText(msg.text) and msg.mediaUrl.len == 0:
    return ok()   ## the API refuses empty text; nothing to deliver

  if msg.keyboard.len > 0:
    discard ? a.sendKeyboardRaw(chatId, msg.text, msg.keyboard, msg.replyTo, msg.isHtml)
    return ok()

  if msg.mediaUrl.len > 0:
    let (head, tail) = splitCaption(msg.text, TelegramCaptionLimit)
    ? a.sendMedia(chatId, msg.mediaUrl, head, msg.replyTo,
                  msg.mediaDurationSec, msg.mediaRoot)
    if tail.strip.len > 0:
      for chunk in splitForTelegram(tail, TelegramMaxChars):
        ? a.sendChunk(chatId, chunk, msg.replyTo, false, msg.isHtml)
    return ok()

  for i, chunk in splitForTelegram(msg.text, TelegramMaxChars):
    ? a.sendChunk(chatId, chunk, msg.replyTo, i == 0, msg.isHtml)
  ok()

proc sendReturnId*(a: TelegramAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends and returns the message_id.
  if a.configError.len > 0:
    return err("TelegramAdapter: " & a.configError)
  let rawId = a.chatIdFor(msg.userId)
  if rawId.len == 0: return err("TelegramAdapter.sendReturnId: no id for " & $msg.userId)
  let chatId = parseBiggestInt(rawId).int64

  if msg.keyboard.len > 0:
    return a.sendKeyboardRaw(chatId, msg.text, msg.keyboard, msg.replyTo, msg.isHtml)

  if msg.mediaUrl.len > 0:
    let (head, tail) = splitCaption(msg.text, TelegramCaptionLimit)
    ? a.sendMedia(chatId, msg.mediaUrl, head, msg.replyTo,
                  msg.mediaDurationSec, msg.mediaRoot)
    if tail.strip.len > 0:
      for chunk in splitForTelegram(tail, TelegramMaxChars):
        ? a.sendChunk(chatId, chunk, msg.replyTo, false, msg.isHtml)
    return ok("")

  if shouldSkipOutboundText(msg.text):
    return ok("")   ## the API refuses empty text; nothing to deliver

  var lastId = ""
  for i, chunk in splitForTelegram(msg.text, TelegramMaxChars):
    let html = renderTelegramHtml(chunk, msg.isHtml)
    var body = %* {"chat_id": chatId, "text": html, "parse_mode": "HTML"}
    body = withLinkPreviewPolicy(body, a.settings.linkPreviews)
    applyReplyTarget(body, msg.replyTo, i == 0)
    let res = a.sendMessageBody(body, msg.replyTo, i == 0)
    if res.isOk:
      lastId = $res.value["result"]["message_id"].getInt()
    else:
      # Fallback
      body.delete("parse_mode")
      body["text"] = %chunk
      let res2 = ? a.sendMessageBody(body, msg.replyTo, i == 0)
      lastId = $res2["result"]["message_id"].getInt()
  ok(lastId)

proc editMessage*(a: TelegramAdapter; userId: UserId;
                  msgId, text: string;
                  isHtml = false): Result[void, string] =
  ## Edits an existing message's text.
  let rawId = a.chatIdFor(userId)
  if rawId.len == 0: return err("editMessage: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  let sanitizedText = sanitizeForTelegram(text)
  let chunks = planEditChunks(sanitizedText, TelegramMaxChars)
  let html = renderTelegramHtml(chunks[0], isHtml)
  var body = %* {"chat_id": chatId, "message_id": parseBiggestInt(msgId), "text": html, "parse_mode": "HTML"}
  let res = a.post("editMessageText", body)
  if res.isOk or isEditNoopError(res.error):
    ## The tail of an oversized edit cannot fit in the edited message, and a
    ## no-op edit still leaves the tail to deliver.
    for i in 1 ..< chunks.len:
      ? a.sendChunk(chatId, chunks[i], "", false, isHtml)
    return ok()
  # Fallback
  body.delete("parse_mode")
  body["text"] = %chunks[0]
  let plain = a.post("editMessageText", body)
  if plain.isOk or isEditNoopError(plain.error):
    for i in 1 ..< chunks.len:
      ? a.sendChunk(chatId, chunks[i], "", false, isHtml)
    return ok()
  err(plain.error)

proc sendKeyboard*(a: TelegramAdapter; userId: UserId;
                   text: string;
                   buttons: seq[seq[(string, string)]];  ## [[("label","data"),...],...]
                   replyTo = ""): Result[string, string] =
  ## Sends a message with an inline keyboard.
  ## Returns the Telegram message_id so the caller can later edit the message.
  let rawId = a.chatIdFor(userId)
  if rawId.len == 0: return err("sendKeyboard: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("sendKeyboard: bad id: " & rawId)
  a.sendKeyboardRaw(chatId, text, buttons, replyTo)

proc editKeyboard*(a: TelegramAdapter; userId: UserId;
                   msgId: string;
                   buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Replaces the inline keyboard of an existing message (e.g. to remove it after selection).
  let rawId = a.chatIdFor(userId)
  if rawId.len == 0: return err("editKeyboard: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  ? validateButtons(buttons)
  let markup = %* {"inline_keyboard": buttons.mapIt(it.mapIt(%* {"text": it[0], "callback_data": it[1]}))}
  discard ? a.post("editMessageReplyMarkup",
                   %* {"chat_id": chatId, "message_id": parseBiggestInt(msgId),
                       "reply_markup": markup})
  ok()

proc editKeyboardText*(a: TelegramAdapter; userId: UserId;
                       msgId, text: string;
                       buttons: seq[seq[(string, string)]];
                       isHtml = false): Result[void, string] =
  ## Edits both text AND keyboard.
  let rawId = a.chatIdFor(userId)
  if rawId.len == 0: return err("editKeyboardText: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  ? validateButtons(buttons)
  let markup = %* {"inline_keyboard": buttons.mapIt(it.mapIt(%* {"text": it[0], "callback_data": it[1]}))}
  let sanitizedText = sanitizeForTelegram(text)
  let html = renderTelegramHtml(sanitizedText, isHtml)
  var body = %* {
    "chat_id":    chatId,
    "message_id": parseBiggestInt(msgId),
    "text":       html,
    "parse_mode": "HTML",
    "reply_markup": markup
  }
  let res = a.post("editMessageText", body)
  if res.isOk: return ok()
  # Fallback
  body.delete("parse_mode")
  body["text"] = %sanitizedText
  discard ? a.post("editMessageText", body)
  ok()

proc setMessageReaction*(a: TelegramAdapter; userId: UserId;
                          channelId, msgId, emoji: string): Result[void, string] =
  ## Sets a reaction (emoji) on a message.
  discard channelId
  let rawId = a.chatIdFor(userId)
  if rawId.len == 0: return err("setMessageReaction: no id for " & $userId)

  try:
    let chatId = parseBiggestInt(rawId).int64
    let msgIdInt = parseBiggestInt(msgId).int64
    var selectedEmoji = emoji
    if emoji.len > 0:
      let chatRes = a.post("getChat", %* {"chat_id": chatId})
      if chatRes.isOk:
        selectedEmoji = pickTelegramReactionEmoji(emoji, chatRes.value.getOrDefault("result"))
        if selectedEmoji.len == 0:
          return ok()
    var reaction = newJArray()
    if selectedEmoji.len > 0:
      reaction.add(%* {"type": "emoji", "emoji": selectedEmoji})

    let res = a.post("setMessageReaction",
                     %* {"chat_id": chatId, "message_id": msgIdInt,
                         "reaction": reaction})
    if res.isErr:
      let errMsg = res.error
      let lowerErr = errMsg.toLowerAscii()
      if "reaction_invalid" in lowerErr or
         "message can't be reacted" in lowerErr or
         "reactions are unavailable" in lowerErr or
         "message reactions are not supported" in lowerErr:
        return ok()
      return err(errMsg)
    ok()
  except CatchableError as e:
    err(e.msg)

proc getFile*(a: TelegramAdapter; fileId: string): Result[string, string] =
  ## Gets file path from Telegram API using file_id.
  ## Returns the file_path that can be used to download the file.
  let res = a.post("getFile", %* {"file_id": fileId})
  if res.isOk:
    let resultNode = res.value["result"]
    let filePath = resultNode.getOrDefault("file_path").getStr("")
    if filePath.len == 0:
      return err("getFile: empty file_path for id=" & fileId)
    ok(filePath)
  else:
    err(res.error)

proc downloadFileBytes*(a: TelegramAdapter; filePath: string): Result[seq[byte], string] =
  ## Downloads file content from Telegram servers.
  ## filePath should be obtained from getFile() first.
  let url = a.apiBaseValue & "/file/bot" & a.token & "/" & filePath
  a.http.fetchBytes(url, @[])

proc downloadFile*(a: TelegramAdapter; fileId: string): Result[FileDownload, string] =
  ## Complete file download: gets file info and downloads content.
  ## Returns FileDownload with path, name, size and data.
  let filePath =
    if fileId.startsWith("tg://"):
      fileId["tg://".len .. ^1]
    else:
      ? a.getFile(fileId)
  let data = ? a.downloadFileBytes(filePath)
  
  # Extract file name from path
  let fileName = filePath.split('/')[^1]
  
  ok(FileDownload(
    fileName: fileName,
    fileSize: data.len.int64,
    mimeType: extractMimeType(filePath),
    localPath: "",
    data: data
  ))

proc registerBotCommands*(a: TelegramAdapter): Result[void, string] =
  ## Registers bot commands in the Telegram menu (the / hint list).
  let cmds = newCommandCatalog().toTelegramCommandsJson()
  discard ? a.post("setMyCommands", %* {"commands": cmds})
  ok()

type TelegramPoll* = object
  ## One getUpdates call as plain data, so it can run on a worker
  ## (app/blocking_executor) that builds its own HTTP client.
  url*:        string
  timeoutSec*: int          ## Telegram's wait plus the usual HTTP timeout
  proxyUrl*:   string
  allowlist*:  seq[string]

func pollRequest*(a: TelegramAdapter): TelegramPoll =
  ## The next getUpdates call, from the current offset.
  TelegramPoll(
    url: a.apiUrl("getUpdates") & "?offset=" & $a.offset &
         "&timeout=" & $a.pollTimeout &
         "&allowed_updates=[\"message\",\"callback_query\"]",
    timeoutSec: a.pollTimeout + max(a.settings.httpTimeoutSec, 1),
    proxyUrl: a.settings.proxyUrl,
    allowlist: telegramApiAllowlist(a.apiBaseValue))

proc fetchTelegramUpdates*(poll: TelegramPoll): Result[HttpResponse, string]
                          {.nimcall, gcsafe, raises: [].} =
  ## The blocking half, for a worker: one attempt, so a slow poll is simply
  ## the next one's turn.
  try:
    newStdHttpAdapter(timeout = poll.timeoutSec, maxRetries = 1,
                      proxy = poll.proxyUrl, allowlist = poll.allowlist,
                      retryNonIdempotent = false).get(poll.url)
  except CatchableError as e:
    err("TelegramAdapter.receive: " & e.msg)

proc acceptTelegramUpdates*(a: var TelegramAdapter;
                            response: Result[HttpResponse, string]):
                            Result[seq[InboundMessage], string] =
  ## The loop's half: parses the updates, advances the offset, resolves
  ## identities and remembers chat ids. Preserves Telegram file_id for later
  ## download via getFile.
  try:
    let resp = ? response
    let j = ? parseTgResp("getUpdates", resp)
    let updates = j["result"]
    var msgs: seq[InboundMessage]
    for u in updates:
      let updateId = u["update_id"].getBiggestInt()
      a.offset = updateId + 1
      let parsed = parseUpdate(u)
      if parsed.kind == tukUnknown: continue
      let uid = a.resolver.resolve(ckTelegram, parsed.rawId)
      if ($uid).len == 0:
        ## Identity storage is unreadable; drop rather than create an empty user.
        continue
      
      var msg = parsed.toInbound(uid)
      ## Remember where the update came from: in a group the chat id is not the
      ## sender id, and replies must go to the chat.
      if parsed.chatId.len > 0:
        a.chatIds[$uid] = parsed.chatId
      if parsed.hasMedia and parsed.mediaFileId.len > 0:
        msg.mediaUrl = parsed.mediaFileId
      msgs.add(msg)
    ok(msgs)
  except CatchableError as e:
    err("TelegramAdapter.receive: " & e.msg)

proc receive*(a: var TelegramAdapter): Result[seq[InboundMessage], string] =
  ## Both halves in one blocking call, for code that is not on the loop.
  a.acceptTelegramUpdates(a.http.get(a.pollRequest().url))

proc ack*(a: TelegramAdapter; msgId: string) =
  ## No-op: Telegram offset is advanced during receive().
  discard

proc answerCallback*(a: TelegramAdapter; callbackId: string): Result[void, string] =
  ## Acknowledges a callback query to remove the loading state in the client.
  if callbackId.len == 0: return ok()
  discard ? a.post("answerCallbackQuery", %* {"callback_query_id": callbackId})
  ok()

proc newTelegramAdapter*(token: string; identityPath: string;
                         apiBase = ""; pollTimeout = DefaultPollTimeout;
                         uploadHttp: HttpRuntimePort = HttpRuntimePort();
                         settings = telegramSettings(Environment())): TelegramAdapter =
  ## `uploadHttp` is optional so tests can inject a fake. When omitted, the
  ## media transport mirrors the text transport (proxy, allowlist, retry
  ## policy) and only the timeout differs: uploads use the media deadline.
  ## A custom base is only accepted over https, except on loopback, and its
  ## host becomes the egress allowlist instead of disabling it.
  let base = apiBase.strip
  let baseError = telegramApiBaseError(base)
  ## Do not raise: an invalid override would abort daemon startup and take
  ## every other channel with it. Record the reason and fail sends instead.
  let effectiveBase = if baseError.len > 0: "https://api.telegram.org" else: base
  let allowlist = telegramApiAllowlist(effectiveBase)
  let upload =
    if uploadHttp.post.isNil:
      newStdHttpAdapter(
        timeout = settings.mediaTimeoutSec,
        proxy = settings.proxyUrl,
        allowlist = allowlist,
        retryNonIdempotent = false,
        retryConflict = true).toRuntimePort()
    else:
      uploadHttp
  TelegramAdapter(
    token:       token,
    configError: baseError,
    apiBase:     base,
    offset:      0,
    resolver:    newIdentityResolver(identityPath),
    flood:       newFloodGate(),
    chatIds:     initTable[string, string](),
    http:        newStdHttpAdapter(
                   timeout = settings.httpTimeoutSec,
                   proxy = settings.proxyUrl,
                   allowlist = allowlist,
                   retryNonIdempotent = false,
                   retryConflict = true),
    uploadHttp:  upload,
    pollTimeout: pollTimeout,
    settings:    settings,
  )
