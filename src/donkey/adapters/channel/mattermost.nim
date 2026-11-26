## mattermost — the Mattermost channel's adapter (second round, front 1).
##
## Inbound posts come from the socket thread (mattermost_socket) through a
## fixed-capacity queue; the daemon loop drains it (mattermost_runtime).
## Replies are `POST /api/v4/posts` with the bot's personal access token, in
## the thread they answer. A person's last channel is kept on disk, for sends
## without a target (reminders, schedules).

import std/[json, os, strutils, tables]
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/mattermost_pure
import ../../infra/event_queue
import ../../ports/http
import ../../ports/link_codes
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
  let remembered = a.state.channels.getOrDefault(sender)
  if sender.len == 0 or remembered.len == 0:
    return err("Mattermost: no channel known for user " & $msg.userId)
  ok(remembered)

func apiBase(serverUrl: string): string =
  result = serverUrl.strip
  while result.endsWith("/"): result.setLen(result.len - 1)

proc send*(a: MattermostAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text, in the thread it answers. Media and keyboards are not offered for
  ## Mattermost (channel_capability), so they are refused, not dropped.
  if a.configError.len > 0:
    return err("Mattermost: " & a.configError)
  if msg.mediaUrl.len > 0 or msg.keyboard.len > 0:
    return err("Mattermost: only text is supported")
  if msg.text.strip.len == 0:
    return ok()
  let target = ? a.targetFor(msg)
  let url = apiBase(a.serverUrl) & "/api/v4/posts"
  for piece in splitForMattermost(msg.text):
    let resp = ? a.http.post(url, postBody(target, piece),
      @[("Content-Type", "application/json"), ("Authorization", "Bearer " & a.token)])
    if resp.status notin 200 .. 299:
      return err("Mattermost: send status " & $resp.status)
  ok()

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
