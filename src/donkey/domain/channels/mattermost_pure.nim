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

import std/[json, options, strutils]
import ../../core/pipeops

const
  MattermostPostChars* = 16_000
    ## The server refuses messages over 16383 characters; a margin for the
    ## multi-byte ones.

type
  MattermostPost* = object
    id*, userId*, channelId*, rootId*: string
    text*:      string
    senderName*: string
    isGroup*:   bool   ## any channel but a direct message
    mentioned*: bool   ## the bot is among the post's mentions

  MattermostMe* = object
    id*, username*: string

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
  if userId.len == 0 or userId == botUserId or text.strip.len == 0:
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
    rootId: post{"root_id"}.getStr, text: text,
    senderName: data{"sender_name"}.getStr,
    isGroup: data{"channel_type"}.getStr != "D", mentioned: mentioned))

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
  if p.text.len == 0: none(MattermostPost) else: some(p)

func replyTarget*(p: MattermostPost): string =
  ## `channel` for a direct message; `channel:root` in a channel, the root
  ## being the thread the post is in, or the post itself.
  if not p.isGroup: p.channelId
  else: p.channelId & ":" & (if p.rootId.len > 0: p.rootId else: p.id)

proc postBody*(target, text: string): string =
  let colon = target.find(':')
  var body = %* {"channel_id": (if colon >= 0: target[0 ..< colon] else: target),
                 "message": text}
  if colon >= 0 and colon < target.high:
    body["root_id"] = %target[colon + 1 .. ^1]
  $body

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
