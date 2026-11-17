## telegram_policy.nim — outbound policies derived from the Bot API behavior.
##
## Pure functions only: the adapter decides when to call them, this module
## decides what the API contract requires.

import std/[json, strutils, tables, unicode]
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
    let afterOk = after >= lower.len or
                  lower[after] notin {'a' .. 'z', '0' .. '9', '_', '.'}
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

type AlbumMentionGate* = ref object
  ## chatId|mediaGroupId → epoch ms until the album counts as addressed.
  untilMs*: Table[string, int64]

const AlbumMentionTtlMs* = 60_000'i64

func newAlbumMentionGate*(): AlbumMentionGate =
  AlbumMentionGate(untilMs: initTable[string, int64]())

func albumKey*(chatId, mediaGroupId: string): string =
  if mediaGroupId.len == 0: "" else: chatId & "|" & mediaGroupId

proc rememberAddressedAlbum*(gate: AlbumMentionGate; key: string;
                             nowMs: int64; ttlMs = AlbumMentionTtlMs) =
  ## Behavior derived from hermes-agent (MIT) fix 8fb618234f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-028
  ##
  ## An album's caption lives on one item only. Once that item is addressed,
  ## its siblings belong to the same user action and must not be dropped by the
  ## mention gate.
  if gate.isNil or key.len == 0:
    return
  gate.untilMs[key] = nowMs + ttlMs

func albumAddressed*(gate: AlbumMentionGate; key: string;
                     nowMs: int64): bool =
  if gate.isNil or key.len == 0:
    return false
  gate.untilMs.getOrDefault(key, 0'i64) > nowMs

proc clearExpiredAlbums*(gate: AlbumMentionGate; nowMs: int64) =
  if gate.isNil:
    return
  var expired: seq[string] = @[]
  for key, untilMs in gate.untilMs:
    if untilMs <= nowMs:
      expired.add(key)
  for key in expired:
    gate.untilMs.del(key)
