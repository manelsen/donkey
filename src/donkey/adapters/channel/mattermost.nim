## mattermost — the Mattermost channel's adapter (second round, front 1).
##
## Inbound posts come from the socket thread (mattermost_socket) through a
## fixed-capacity queue; the daemon loop drains it (mattermost_runtime).
## Replies are `POST /api/v4/posts` with the bot's personal access token, in
## the thread they answer. A person's last channel is kept on disk, for sends
## without a target (reminders, schedules).

import std/[json, os, strutils, sysrand, tables]
import ../../core/media_download
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/mattermost_pure
import ../../domain/media/audio_pure
import ../../ports/channel
import ../../infra/event_queue
import ../../ports/http
import ../../ports/link_codes
import ../filesystem/confined_read
import ../filesystem/paths
import ../http/std_http
import ../identity/identity_resolver
import ../state/durable_file

export mattermost_pure

const
  MattermostQueueCapacity* = 256
  MattermostTimeoutSec = 30

# ── Posts to answer, from the socket thread to the daemon loop ───────────────

var gMattermostPosts* = initEventQueue[MattermostPost]("mattermost",
                                                       capacity = MattermostQueueCapacity)

proc pushPost*(p: MattermostPost): bool {.discardable.} =
  ## False when the queue is full (the post is lost; the socket logs it).
  gMattermostPosts.push(p)

proc tryRecvPost*(): (bool, MattermostPost) =
  gMattermostPosts.tryTake()

# ── Adapter ───────────────────────────────────────────────────────────────────

type
  MattermostState = ref object
    channels: Table[string, string]   ## sender id → last direct channel

  MattermostAdapter* = object
    serverUrl*:   string
    token:        string
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    http:         HttpRuntimePort
    channelsPath: string
    state:        MattermostState
    configError*: string

proc loadChannels(path: string): Table[string, string] =
  result = initTable[string, string]()
  if path.len == 0 or not fileExists(path):
    return
  try:
    let j = parseJson(readFile(path))
    if j.kind == JObject:
      for key, value in j.pairs:
        if value.kind == JString:
          result[key] = value.getStr
  except CatchableError:
    discard   ## an unreadable file only costs the sends without a target until the next message

proc rememberChannel*(a: MattermostAdapter; senderId, channelId: string): Result[void, string] {.discardable.} =
  ## Where a person last wrote from; the file is written only when it changes.
  if senderId.len == 0 or channelId.len == 0:
    return ok()
  if a.state.channels.getOrDefault(senderId) == channelId:
    return ok()
  a.state.channels[senderId] = channelId
  if a.channelsPath.len == 0:
    return ok()
  var j = newJObject()
  for key, value in a.state.channels:
    j[key] = %value
  atomicWriteText(a.channelsPath, $j, "w")

proc targetFor(a: MattermostAdapter; msg: OutboundMessage): Result[string, string] =
  if msg.replyTo.strip.len > 0:
    return ok(msg.replyTo.strip)
  let sender = a.resolver.reverseChannel(msg.userId, ckMattermost)
  if sender.len == 0:
    return err("Mattermost: no channel known for user " & $msg.userId)
  let remembered = a.state.channels.getOrDefault(sender)
  if remembered.len == 0:
    return err("Mattermost: no channel known for user " & $msg.userId)
  ok(remembered)

func apiBase(serverUrl: string): string =
  result = serverUrl.strip
  while result.endsWith("/"): result.setLen(result.len - 1)

const
  MattermostMaxUploadBytes* = 50 * 1024 * 1024
  MattermostMaxDownloadBytes* = 25 * 1024 * 1024
  MediaUnavailableNote = "(o arquivo não pôde ser enviado)"

proc uploadFile(a: MattermostAdapter; channelId, path, mediaRoot: string): Result[string, string] =
  ## A local file, read only inside the paddock (confined_read, the same rule
  ## as Telegram), uploaded to the channel; its new file id.
  let safePath = ? resolveConfinedMediaPath(mediaRoot, path)
  var opened = ? openPathComponent(mediaRoot, safePath)
  let data = opened.readPathComponent(MattermostMaxUploadBytes)
  opened.closeComponent()
  let bytes = ? data
  var raw: array[16, byte]
  if not urandom(raw):
    return err("Mattermost: no randomness for the upload boundary")
  var boundary = "donkey-"
  for b in raw: boundary.add b.toHex(2).toLowerAscii
  let body = buildMultipartBody(boundary, "files", opened.name,
    (let m = extractMimeType(opened.name); if m.len > 0: m else: "application/octet-stream"),
    bytes, @[("channel_id", channelId)])
  let resp = ? a.http.post(apiBase(a.serverUrl) & "/api/v4/files", body,
    @[("Content-Type", "multipart/form-data; boundary=" & boundary),
      ("Authorization", "Bearer " & a.token)])
  if resp.status notin 200 .. 299:
    return err("Mattermost: upload status " & $resp.status)
  uploadedFileId(resp.body)

proc send*(a: MattermostAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text, in the thread it answers; a local file goes up first and the post
  ## carries its id (E9.1). A file that cannot be read inside the paddock
  ## becomes a neutral note, never a path. Keyboards are not offered.
  if a.configError.len > 0:
    return err("Mattermost: " & a.configError)
  if msg.keyboard.len > 0:
    return err("Mattermost: keyboards are not supported")
  let target = ? a.targetFor(msg)
  var fileIds: seq[string]
  var text = msg.text
  if msg.mediaUrl.len > 0:
    let uploaded = a.uploadFile(channelOf(target), msg.mediaUrl, msg.mediaRoot)
    if uploaded.isOk:
      fileIds.add uploaded.get
    else:
      text = (if text.strip.len > 0: text & "\n\n" else: "") & MediaUnavailableNote
  if text.strip.len == 0 and fileIds.len == 0:
    return ok()
  let url = apiBase(a.serverUrl) & "/api/v4/posts"
  let pieces = if text.strip.len > 0: splitForMattermost(text) else: @[""]
  for i, piece in pieces:
    ## The files ride on the first post.
    let resp = ? a.http.post(url, postBody(target, piece, if i == 0: fileIds else: @[]),
      @[("Content-Type", "application/json"), ("Authorization", "Bearer " & a.token)])
    if resp.status notin 200 .. 299:
      return err("Mattermost: send status " & $resp.status)
  ok()

proc downloadFile*(a: MattermostAdapter; fileId: string): Result[FileDownload, string] =
  ## An attachment of a post, with the bot's token. Only a well-formed id
  ## reaches the URL.
  if a.configError.len > 0:
    return err("Mattermost: " & a.configError)
  if not validFileId(fileId):
    return err("Mattermost: not a file id")
  let resp = ? a.http.get(apiBase(a.serverUrl) & "/api/v4/files/" & fileId,
                          @[("Authorization", "Bearer " & a.token)])
  if resp.status != 200:
    return err("Mattermost: download status " & $resp.status)
  if resp.body.len > MattermostMaxDownloadBytes:
    return err("Mattermost: attachment larger than " &
               $(MattermostMaxDownloadBytes div (1024 * 1024)) & " MB")
  var data = newSeq[byte](resp.body.len)
  for i in 0 ..< resp.body.len: data[i] = byte(resp.body[i])
  ok(FileDownload(fileName: fileId, fileSize: data.len.int64, data: data))

func hostOf(serverUrl: string): string =
  var rest = apiBase(serverUrl)
  let scheme = rest.find("://")
  if scheme >= 0: rest = rest[scheme + 3 .. ^1]
  let slash = rest.find('/')
  if slash >= 0: rest = rest[0 ..< slash]
  let colon = rest.find(':')
  if colon >= 0: rest[0 ..< colon] else: rest

proc newMattermostAdapter*(serverUrl, token, identityPath, channelsPath: string;
                           http: HttpRuntimePort = HttpRuntimePort()): MattermostAdapter =
  ## `MATTERMOST_URL` and `MATTERMOST_TOKEN` (a bot's personal access token)
  ## from the environment snapshot. A missing or plain-HTTP setting does not
  ## stop the daemon: the adapter records why and every send fails with it.
  let url = serverUrl.strip
  var transport = http
  if transport.post.isNil:
    transport = newStdHttpAdapter(timeout = MattermostTimeoutSec,
      allowlist = @[hostOf(url)], retryNonIdempotent = false,
      retryConflict = false).toRuntimePort()
  let urlCheck = websocketUrl(url)
  result = MattermostAdapter(
    serverUrl: url, token: token.strip, resolver: newIdentityResolver(identityPath),
    http: transport, channelsPath: channelsPath,
    state: MattermostState(channels: loadChannels(channelsPath)),
    configError:
      if url.len == 0 or token.strip.len == 0: "MATTERMOST_URL and MATTERMOST_TOKEN are required"
      elif urlCheck.isErr: urlCheck.error
      else: "")
  result.linkCodes = result.resolver.linkCodePort()
