## pairing_store.nim — persistent pending pairing requests.
##
## Unknown senders in `DmPolicyPairing` create a pending request here. The
## operator approves it with `donkey ctl pair approve <code>`, which mints the
## identity and adds the resulting UUID to the DM allowlist. Requests expire
## and are rate-limited per raw identity.

import std/[json, os, times]
import ../../core/pipeops
import ../../core/security/dm_policy
import ../../core/types

type
  PairingRequest* = object
    code*:      string
    channel*:   ChannelKind
    rawId*:     string
    createdAt*: float
    expiresAt*: float
    attempts*:  int

  PairingStore* = object
    path*: string

const
  PairingRequestTtlSec*     = 600.0  ## 10 minutes
  PairingRequestCooldownSec* = 60.0  ## one request per raw identity per minute
  MaxPendingPerRawId*       = 3

func newPairingStore*(path: string): PairingStore =
  PairingStore(path: path)

func requestKey(kind: ChannelKind; rawId: string): string =
  $kind & "\t" & rawId

func parseChannelName(name: string; kind: var ChannelKind): bool =
  case name
  of "telegram": kind = ckTelegram
  of "discord":  kind = ckDiscord
  of "wecom":    kind = ckWeCom
  of "wechat":   kind = ckWeChat
  of "qq":       kind = ckQQ
  of "feishu":   kind = ckFeishu
  of "slack":    kind = ckSlack
  of "whatsapp": kind = ckWhatsApp
  of "signal":   kind = ckSignal
  of "dingtalk": kind = ckDingTalk
  of "matrix":   kind = ckMatrix
  of "email":    kind = ckEmail
  of "cli":      kind = ckCli
  else: return false
  true

func isExpired*(request: PairingRequest; now: float): bool =
  now >= request.expiresAt

proc pruneExpired(requests: seq[PairingRequest]; now: float): seq[PairingRequest] =
  for request in requests:
    if not request.isExpired(now):
      result.add(request)

proc load*(store: PairingStore; now = epochTime()): seq[PairingRequest] =
  ## Loads non-expired requests. Corrupt files are treated as empty so a bad
  ## state file cannot block the daemon or the CLI.
  if store.path.len == 0 or not fileExists(store.path):
    return @[]
  try:
    let root = parseJson(readFile(store.path))
    let items = root.getOrDefault("requests")
    if items == nil or items.kind != JArray:
      return @[]
    for item in items:
      let channelName = item.getOrDefault("channel").getStr("")
      var kind: ChannelKind
      if not parseChannelName(channelName, kind):
        continue
      result.add(PairingRequest(
        code:      item.getOrDefault("code").getStr(""),
        channel:   kind,
        rawId:     item.getOrDefault("rawId").getStr(""),
        createdAt: item.getOrDefault("createdAt").getFloat(0.0),
        expiresAt: item.getOrDefault("expiresAt").getFloat(0.0),
        attempts:  item.getOrDefault("attempts").getInt(0),
      ))
  except CatchableError:
    return @[]
  result = pruneExpired(result, now)

proc save*(store: PairingStore;
           requests: seq[PairingRequest]): Result[void, string] =
  if store.path.len == 0:
    return err("pairing store path is empty")
  var items = newJArray()
  for request in requests:
    items.add(%* {
      "code":      request.code,
      "channel":   $request.channel,
      "rawId":     request.rawId,
      "createdAt": request.createdAt,
      "expiresAt": request.expiresAt,
      "attempts":  request.attempts,
    })
  try:
    createDir(parentDir(store.path))
    let tmp = store.path & ".tmp"
    writeFile(tmp, $(%* {"requests": items}))
    moveFile(tmp, store.path)
    ok()
  except CatchableError as e:
    err("pairing store write failed: " & e.msg)

proc requestPairing*(store: PairingStore;
                     kind: ChannelKind;
                     rawId: string;
                     now = epochTime()): Result[PairingRequest, string] =
  ## Creates a pending request, enforcing the per-identity cooldown and the
  ## maximum number of pending requests.
  if rawId.len == 0:
    return err("empty pairing identity")
  var requests = store.load(now)
  let key = requestKey(kind, rawId)
  var pending = 0
  for request in requests:
    if requestKey(request.channel, request.rawId) == key:
      if now - request.createdAt < PairingRequestCooldownSec:
        return err("pairing request already pending")
      inc pending
  if pending >= MaxPendingPerRawId:
    return err("too many pending pairing requests")

  var code = generatePairingCode()
  var tries = 0
  while tries < 10:
    var collision = false
    for request in requests:
      if request.code == code:
        collision = true
        break
    if not collision:
      break
    code = generatePairingCode()
    inc tries

  let request = PairingRequest(
    code:      code,
    channel:   kind,
    rawId:     rawId,
    createdAt: now,
    expiresAt: now + PairingRequestTtlSec,
  )
  requests.add(request)
  ? store.save(requests)
  ok(request)

func findIndexByCode*(requests: seq[PairingRequest]; code: string): int =
  for i, request in requests:
    if request.code == code:
      return i
  -1

proc removeByCode*(store: PairingStore; code: string): Result[bool, string] =
  var requests = store.load()
  let idx = findIndexByCode(requests, code)
  if idx < 0:
    return ok(false)
  requests.delete(idx)
  ? store.save(requests)
  ok(true)
