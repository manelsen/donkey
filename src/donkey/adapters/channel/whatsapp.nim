## WhatsAppAdapter — ChannelPort for WhatsApp Cloud API (webhook).
##
## Receiving: Meta POSTs webhook events to the HTTP layer.
##   The HTTP layer calls pushEvent() with the parsed JSON payload.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## Webhook verification: Meta sends a GET with hub.mode, hub.challenge,
##   hub.verify_token.
##   Call verifyChallenge(mode, challenge, token, configToken) — non-empty
##   result means echo the challenge back; return 403 otherwise.
##
## Sending: Meta Graph API POST /{phone-number-id}/messages with Bearer token.
##   Target is a WhatsApp phone number in international format (no +).
##
## Media: The adapter must resolve a media ID to a URL via the Media API
##   (GET /{media-id}) before the InboundMessage mediaUrl is useful.

import std/[json, strutils]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/whatsapp_pure
import ../../ports/http
import ../../ports/channel
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver
export FileDownload

const
  WaApiBase*    = "https://graph.facebook.com/v19.0"
  WaMaxChars*   = 4096  ## Meta hard limit for text messages

# ── Public event type ──────────────────────────────────────────────────────────

type
  WaRawEventKind* = enum
    wrkText        ## text message
    wrkInteractive ## button_reply or list_reply
    wrkMedia       ## image / audio / video / document / sticker

  WaRawEvent* = object
    kind*:          WaRawEventKind
    waUserId*:      string  ## sender phone number (international, no +)
    text*:          string  ## body text, interactive id, or "" for media
    messageId*:     string  ## wamid — unique message id for dedup / ack
    phoneNumberId*: string  ## receiving business phone number id
    mediaId*:       string  ## non-empty for wrkMedia (resolve via Media API)

# ── Module-level event queue ───────────────────────────────────────────────────

## Thread-safe: chronos Channel uses internal synchronization.
## Opened once at daemon startup via openQueue().
var gWaEvents* {.global.}: Channel[WaRawEvent]

# ── Inbound helpers (called by HTTP layer) ─────────────────────────────────────

proc verifyChallenge*(hubMode, hubChallenge, hubVerifyToken,
                      configToken: string): string =
  ## Returns the challenge string if hub.mode == "subscribe" and the token
  ## matches.  Empty string means reject the request (return HTTP 403).
  if hubMode == "subscribe" and hubVerifyToken == configToken:
    hubChallenge
  else:
    ""

proc pushEvent*(payload: JsonNode) =
  ## Parses an incoming WhatsApp Cloud API webhook payload and enqueues events.
  ## Ignores status updates and unknown message types.
  let msgs = payload |> parseWebhook
  for r in msgs:
    case r.kind
    of wmkText:
      gWaEvents.send(WaRawEvent(
        kind:          wrkText,
        waUserId:      r.rawId,
        text:          r.text,
        messageId:     r.messageId,
        phoneNumberId: r.phoneNumberId,
      ))
    of wmkInteractive:
      gWaEvents.send(WaRawEvent(
        kind:          wrkInteractive,
        waUserId:      r.rawId,
        text:          r.text,
        messageId:     r.messageId,
        phoneNumberId: r.phoneNumberId,
      ))
    of wmkMedia:
      gWaEvents.send(WaRawEvent(
        kind:          wrkMedia,
        waUserId:      r.rawId,
        text:          "",
        messageId:     r.messageId,
        phoneNumberId: r.phoneNumberId,
        mediaId:       r.mediaId,
      ))
    of wmkUnknown:
      discard

# ── WhatsAppAdapter ────────────────────────────────────────────────────────────

type
  WhatsAppAdapter* = object
    accessToken*:    string
    phoneNumberId*:  string   ## business phone number id for sending
    apiBase*:        string   ## override for testing
    resolver*:       IdentityResolver
    http*:           StdHttpAdapter

func authHeader(a: WhatsAppAdapter): (string, string) =
  ("Authorization", "Bearer " & a.accessToken)

func base(a: WhatsAppAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: WaApiBase

# ── REST response helpers ──────────────────────────────────────────────────────

proc parseWaBody(resp: HttpResponse): Result[JsonNode, string]
                {.gcsafe, raises: [].} =
  ## Validates HTTP status and returns the parsed JSON body.
  ## Designed for >>= chaining.
  if resp.status < 200 or resp.status >= 300:
    return err("WhatsApp HTTP " & $resp.status & ": " & resp.body)
  try:
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc postJson(a: WhatsAppAdapter; path: string;
              body: JsonNode): Result[JsonNode, string] =
  ## POSTs JSON to a Meta Graph API endpoint; validates the response.
  let headers = @[a.authHeader(), ("Content-Type", "application/json")]
  a.http.post(a.base() & "/" & path, $body, headers) >>= parseWaBody

proc getJson(a: WhatsAppAdapter; path: string): Result[JsonNode, string] =
  ## GETs a Meta Graph API resource and returns the parsed JSON body.
  let headers = @[a.authHeader()]
  a.http.get(a.base() & "/" & path, headers) >>= parseWaBody

# ── Media URL resolution and download ──────────────────────────────────────────

proc resolveMediaUrl*(a: WhatsAppAdapter; mediaId: string): Result[string, string] =
  ## Resolves a WhatsApp media ID to a download URL via the Media API.
  ## GET /{media-id} → {"url": "https://..."}
  let j = ? a.getJson(mediaId)
  try:
    let url = j.getOrDefault("url").getStr("")
    if url.len == 0:
      return err("WhatsApp Media API: missing url field for id=" & mediaId)
    ok(url)
  except CatchableError as e:
    err(e.msg)

proc downloadMediaFile*(a: WhatsAppAdapter; mediaId: string): Result[seq[byte], string] =
  ## Resolves media ID and downloads the file content.
  ## Combines resolveMediaUrl with binary download.
  let url = ? a.resolveMediaUrl(mediaId)
  try:
    # WhatsApp media URLs need authorization header
    let authHeaders = @[a.authHeader()]
    let resp = ? a.http.get(url, authHeaders)

    var data = newSeq[byte](resp.body.len)
    for i in 0 ..< resp.body.len:
      data[i] = cast[byte](resp.body[i])
    ok(data)
  except CatchableError as e:
    err("downloadMediaFile: " & e.msg)

proc downloadFile*(a: WhatsAppAdapter; mediaId: string): Result[FileDownload, string] =
  ## Downloads a WhatsApp media file by its media ID.
  ## Returns FileDownload with metadata and content.
  let data = ? a.downloadMediaFile(mediaId)
  
  # Try to get file metadata from Media API
  let infoResult = a.getJson(mediaId)
  var fileName = "whatsapp_" & mediaId
  var fileSize = data.len.int64
  var mimeType = "application/octet-stream"
  
  if infoResult.isOk:
    let info = infoResult.value
    fileName = info.getOrDefault("filename").getStr(fileName)
    fileSize = info.getOrDefault("file_size").getInt(fileSize).int64
    mimeType = info.getOrDefault("mime_type").getStr(mimeType)
  
  ok(FileDownload(
    fileName: fileName,
    fileSize: fileSize,
    mimeType: mimeType,
    localPath: "",
    data: data,
  ))

# ── ChannelPort procs ──────────────────────────────────────────────────────────

proc sendChunk(a: WhatsAppAdapter; toPhone, text: string): Result[void, string] =
  discard ? a.postJson(a.phoneNumberId & "/messages", %* {
    "messaging_product": "whatsapp",
    "to":   toPhone,
    "type": "text",
    "text": {"body": text},
  })
  ok()

proc sendMedia*(a: WhatsAppAdapter; toPhone, url, caption: string): Result[void, string] =
  ## Sends media (image, video, document, audio) to a WhatsApp user.
  ## URL can be HTTP(S) link or local file path.
  ## WhatsApp Cloud API supports sending media by URL or by uploading directly.
  let isImage = url.endsWith(".jpg") or url.endsWith(".jpeg") or
                url.endsWith(".png") or url.endsWith(".gif") or
                url.endsWith(".webp")
  let isVideo = url.endsWith(".mp4") or url.endsWith(".webm")
  let isAudio = url.endsWith(".mp3") or url.endsWith(".ogg") or url.endsWith(".wav")
  
  let mediaType = 
    if isImage: "image"
    elif isVideo: "video"
    elif isAudio: "audio"
    else: "document"
  
  var body = %* {
    "messaging_product": "whatsapp",
    "to": toPhone,
    "type": mediaType,
  }
  
  # Check if URL is HTTP(S) or local file path
  if url.startsWith("http://") or url.startsWith("https://"):
    body[mediaType] = %* {"link": url, "caption": caption}
  else:
    # For local files, we'd need to upload via Media API first
    # For now, fall back to sending URL as text
    return err("WhatsApp sendMedia: local file paths not yet supported, use HTTP URL: " & url)
  
  discard ? a.postJson(a.phoneNumberId & "/messages", body)
  ok()

proc send*(a: WhatsAppAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user's WhatsApp phone number.
  ## Splits messages longer than WaMaxChars into multiple sends.
  ## If msg.mediaUrl is set, sends as media instead of text.
  let waPhone = a.resolver.reverseChannel(msg.userId, ckWhatsApp)
  if waPhone.len == 0:
    return err("WhatsAppAdapter.send: no WhatsApp ID for user " & $msg.userId)
  
  # Send media if URL is provided
  if msg.mediaUrl.len > 0:
    return a.sendMedia(waPhone, msg.mediaUrl, msg.text)
  
  for chunk in splitChunks(msg.text, WaMaxChars):
    ? a.sendChunk(waPhone, chunk)
  ok()

proc sendToPhone*(a: WhatsAppAdapter;
                  toPhone, text: string): Result[void, string] =
  ## Sends a message directly to a WhatsApp phone number.
  ## Used by the runtime for event-context replies.
  for chunk in splitChunks(text, WaMaxChars):
    ? a.sendChunk(toPhone, chunk)
  ok()

proc extractMsgId(j: JsonNode): Result[string, string]
                 {.gcsafe, raises: [].} =
  ## Extracts the wamid from a messages API response. Designed for >>= chaining.
  try:
    let msgs = j.getOrDefault("messages")
    if msgs == nil or msgs.kind != JArray or msgs.len == 0:
      return err("WhatsApp send response: no messages array")
    ok(msgs[0].getOrDefault("id").getStr(""))
  except CatchableError as e:
    err(e.msg)

proc sendReturnId*(a: WhatsAppAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends a single chunk and returns the wamid (message id).
  ## Used by the streaming machinery for subsequent edits.
  let waPhone = a.resolver.reverseChannel(msg.userId, ckWhatsApp)
  if waPhone.len == 0:
    return err("WhatsAppAdapter.sendReturnId: no WhatsApp ID for " & $msg.userId)
  let chunk = splitChunks(msg.text, WaMaxChars)[0]
  a.postJson(a.phoneNumberId & "/messages", %* {
    "messaging_product": "whatsapp",
    "to":   waPhone,
    "type": "text",
    "text": {"body": chunk},
  }) >>= extractMsgId

proc ack*(a: WhatsAppAdapter; phoneNumberId, messageId: string) =
  ## Marks a message as read via the Messages API status update.
  ## Errors are silently ignored — ack failures must not block processing.
  discard a.postJson(phoneNumberId & "/messages", %* {
    "messaging_product": "whatsapp",
    "status": "read",
    "message_id": messageId,
  })

# ── Queue management ───────────────────────────────────────────────────────────

proc openQueue*(a: WhatsAppAdapter) =
  ## Opens the module-level event queue. Call once at daemon startup.
  {.cast(gcsafe).}:
    gWaEvents.open()

proc tryRecvEvent*(a: WhatsAppAdapter): (bool, WaRawEvent) =
  ## Non-blocking poll for webhook events. Returns (false, default) when empty.
  gWaEvents.tryRecv()

# ── Constructor ────────────────────────────────────────────────────────────────

proc newWhatsAppAdapter*(accessToken:   string;
                         phoneNumberId: string;
                         identityPath:  string;
                         apiBase        = ""): WhatsAppAdapter =
  WhatsAppAdapter(
    accessToken:   accessToken,
    phoneNumberId: phoneNumberId,
    apiBase:       apiBase,
    resolver:      newIdentityResolver(identityPath),
    http:          newStdHttpAdapter(),
  )
