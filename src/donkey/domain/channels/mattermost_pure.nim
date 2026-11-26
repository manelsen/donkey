## mattermost_pure — Mattermost, the pure half (PRD-roadmap, second round,
## front 1).
##
## Inbound comes over the WebSocket (`/api/v4/websocket`): after an
## `authentication_challenge` carrying the bot's token, each new post arrives
## as a `posted` event whose `data.post` is the post itself, JSON-encoded in a
## string, and whose `data.mentions`, when present, is a JSON-encoded list of
## the user ids mentioned. Replies are `POST /api/v4/posts`; in a channel they
## go into the post's thread (`root_id`). Formats from the Mattermost API
## reference ("WebSocket", "Create a post").

import std/[algorithm, json, options, strutils]
import ../../core/pipeops

const
  MattermostPostChars* = 16_000
    ## The server refuses messages over 16383 characters; a margin for the
    ## multi-byte ones.

type
  MattermostFile* = object
    id*, name*, mimeType*: string
    size*: int64

  MattermostPost* = object
    id*, userId*, channelId*, rootId*: string
    files*:     seq[MattermostFile]   ## attachments (E9.1), first is downloaded
    text*:      string
    senderName*: string
    isGroup*:   bool   ## any channel but a direct message
    mentioned*: bool   ## the bot is among the post's mentions
    createdMs*: int64  ## when it was written (create_at)

  MattermostMe* = object
    id*, username*: string

func validFileId*(id: string): bool =
  ## A Mattermost id: 26 lowercase letters and digits. Anything else never
  ## reaches a URL path.
  if id.len != 26: return false
  for c in id:
    if c notin {'a'..'z', '0'..'9'}: return false
  true

proc filesOf(post: JsonNode): seq[MattermostFile] =
  ## From `metadata.files` (name, type, size), else the bare `file_ids`.
  let meta = post{"metadata"}{"files"}
  if not meta.isNil and meta.kind == JArray and meta.len > 0:
    for f in meta:
      let id = f{"id"}.getStr
      if validFileId(id):
        result.add MattermostFile(id: id, name: f{"name"}.getStr,
                                  mimeType: f{"mime_type"}.getStr,
                                  size: f{"size"}.getBiggestInt)
    return
  for id in post{"file_ids"}.getElems:
    if validFileId(id.getStr): result.add MattermostFile(id: id.getStr)

proc parsePostedEvent*(frame, botUserId: string): Option[MattermostPost] =
  ## A post someone else wrote, with text; none for any other frame (the
  ## hello, replies to our requests, typing, the bot's own posts, system
  ## posts such as joins).
  let j =
    try: parseJson(frame)
    except CatchableError: return none(MattermostPost)
  if j.kind != JObject or j{"event"}.getStr != "posted":
    return none(MattermostPost)
  let data = j{"data"}
  let post =
    try: parseJson(data{"post"}.getStr)
    except CatchableError: return none(MattermostPost)
  if post.kind != JObject or post{"type"}.getStr.len > 0:
    return none(MattermostPost)
  let userId = post{"user_id"}.getStr
  let text = post{"message"}.getStr
  let files = filesOf(post)
  if userId.len == 0 or userId == botUserId or (text.strip.len == 0 and files.len == 0):
    return none(MattermostPost)
  var mentioned = false
  let mentions = data{"mentions"}.getStr
  if mentions.len > 0:
    try:
      for m in parseJson(mentions):
        if m.getStr == botUserId: mentioned = true
    except CatchableError: discard
  some(MattermostPost(
    id: post{"id"}.getStr, userId: userId, channelId: post{"channel_id"}.getStr,
    rootId: post{"root_id"}.getStr, text: text, files: files,
    senderName: data{"sender_name"}.getStr,
    isGroup: data{"channel_type"}.getStr != "D", mentioned: mentioned,
    createdMs: post{"create_at"}.getBiggestInt))

func shouldAnswer*(p: MattermostPost): bool =
  ## A direct message always; in a channel, only when the bot is mentioned.
  not p.isGroup or p.mentioned

func stripMention*(text, username: string): string =
  ## Takes out `@username` (any case) where it is a whole name, not the start
  ## of a longer one.
  if username.len == 0: return text.strip
  let needle = "@" & username.toLowerAscii
  let lower = text.toLowerAscii
  var i = 0
  while i < text.len:
    if lower.continuesWith(needle, i):
      let after = i + needle.len
      if after >= text.len or text[after] notin {'a'..'z', 'A'..'Z', '0'..'9', '.', '_', '-'}:
        i = after
        continue
    result.add text[i]
    inc i
  result = result.strip

func websocketUrl*(serverUrl: string): Result[string, string] =
  var base = serverUrl.strip
  while base.endsWith("/"): base.setLen(base.len - 1)
  ## Only TLS: the socket and every request carry the bot's token.
  if base.startsWith("https://"):
    ok("wss://" & base["https://".len .. ^1] & "/api/v4/websocket")
  else:
    err("the Mattermost URL must start with https://: " & serverUrl)

proc authChallenge*(token: string; seq: int): string =
  $(%* {"seq": seq, "action": "authentication_challenge", "data": {"token": token}})

proc inboundPost*(frame: string; me: MattermostMe): Option[MattermostPost] =
  ## What the socket queues: a post the bot should answer, with its mention
  ## taken out; none when nothing is left to answer.
  let parsed = parsePostedEvent(frame, me.id)
  if parsed.isNone or not shouldAnswer(parsed.get):
    return none(MattermostPost)
  var p = parsed.get
  p.text = stripMention(p.text, me.username)
  if p.text.len == 0 and p.files.len == 0: none(MattermostPost) else: some(p)

func replyTarget*(p: MattermostPost): string =
  ## `channel` for a direct message; `channel:root` in a channel, the root
  ## being the thread the post is in, or the post itself.
  if not p.isGroup: p.channelId
  else: p.channelId & ":" & (if p.rootId.len > 0: p.rootId else: p.id)

func channelOf*(target: string): string =
  let colon = target.find(':')
  if colon >= 0: target[0 ..< colon] else: target

proc postBody*(target, text: string; fileIds: seq[string] = @[]): string =
  let colon = target.find(':')
  var body = %* {"channel_id": channelOf(target), "message": text}
  if colon >= 0 and colon < target.high:
    body["root_id"] = %target[colon + 1 .. ^1]
  if fileIds.len > 0:
    body["file_ids"] = %fileIds
  $body

proc uploadedFileId*(body: string): Result[string, string] =
  ## `POST /files`: the id of the first file stored.
  try:
    let id = parseJson(body){"file_infos"}{0}{"id"}.getStr
    if validFileId(id): ok(id) else: err("Mattermost: upload without a file id")
  except CatchableError as e:
    err("Mattermost: upload answer unreadable: " & e.msg)

func splitForMattermost*(text: string): seq[string] =
  splitChunks(text, MattermostPostChars)

proc parseMe*(body: string): Result[MattermostMe, string] =
  let j =
    try: parseJson(body)
    except CatchableError: return err("users/me is not JSON")
  let id = j{"id"}.getStr
  if id.len == 0:
    return err("users/me: " & j{"message"}.getStr("no id"))
  ok(MattermostMe(id: id, username: j{"username"}.getStr))

proc authRefused*(frame: string; challengeSeq: int): bool =
  ## The server's answer to our authentication challenge says no (a bad or
  ## revoked token): reconnecting with the same token cannot help.
  let j =
    try: parseJson(frame)
    except CatchableError: return false
  j.kind == JObject and j{"seq_reply"}.getInt(-1) == challengeSeq and
    j{"status"}.getStr == "FAIL"

proc pingAction*(seq: int): string =
  ## The client-side keepalive; the server answers with a pong reply.
  $(%* {"seq": seq, "action": "ping"})

# ── Catching up after a drop ─────────────────────────────────────────────────

proc parseChannels*(body: string): seq[(string, string)] =
  ## `GET /users/me/teams/{team}/channels`: each channel's id and type
  ## (D direct, G group, O open, P private).
  try:
    for c in parseJson(body).getElems:
      let id = c{"id"}.getStr
      if id.len > 0: result.add (id, c{"type"}.getStr)
  except CatchableError: discard

func mentions(text, username: string): bool =
  stripMention(text, username) != text.strip

proc postsSince*(body, channelType: string; me: MattermostMe;
                 sinceMs: int64): seq[MattermostPost] =
  ## `GET /channels/{id}/posts?since=`: the posts written after `sinceMs`
  ## that the bot should answer, oldest first, under the live rules: none of
  ## its own, no system posts, a mention needed outside a direct message.
  let j =
    try: parseJson(body)
    except CatchableError: return @[]
  let isGroup = channelType != "D"
  for id in j{"order"}.getElems:
    let p = j{"posts"}{id.getStr}
    if p.isNil or p.kind != JObject: continue
    let userId = p{"user_id"}.getStr
    let text = p{"message"}.getStr
    let created = p{"create_at"}.getBiggestInt
    if created <= sinceMs or p{"type"}.getStr.len > 0 or userId.len == 0 or
        userId == me.id or (text.strip.len == 0 and filesOf(p).len == 0):
      continue
    let mentioned = mentions(text, me.username)
    if isGroup and not mentioned: continue
    let cleaned = stripMention(text, me.username)
    let files = filesOf(p)
    if cleaned.len == 0 and files.len == 0: continue
    result.add MattermostPost(id: p{"id"}.getStr, userId: userId,
      channelId: p{"channel_id"}.getStr, rootId: p{"root_id"}.getStr, text: cleaned,
      isGroup: isGroup, mentioned: mentioned, createdMs: created, files: files)
  result.sort(proc(a, b: MattermostPost): int = cmp(a.createdMs, b.createdMs))
