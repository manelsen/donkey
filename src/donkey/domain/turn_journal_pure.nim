## turn_journal_pure — what a turn in flight leaves behind, and what the next
## start does with it (PRD-roadmap E1).
##
## A user turn writes a record when it starts, adds each tool with an effect
## before that tool runs (write-ahead), and removes the record when it ends.
## A record still there at startup is a turn the daemon died in. It is replayed
## from the start only when nothing it did could be repeated: no effect, not
## replayed before (a message that brings the daemon down must not loop) and
## not older than a day. Otherwise the user is told what was interrupted and
## what had already been done.
##
## `proc` where JSON is built or parsed (ADR-007 allows it).

import std/[hashes, json, strutils, unicode]
import ../core/pipeops
import ../core/types
import ./builtin_tools
import ./more_tools

type
  TurnRecord* = object
    id*:        string
    userId*:    string
    channel*:   ChannelKind
    replyTo*:   string       ## the channel's reply target, as the turn had it
    payload*:   string       ## the session payload the turn was given
    preview*:   string       ## the start of the user's message, for the notice
    startedMs*: int64
    effects*:   seq[string]  ## tools with an effect that ran, in order
    resumes*:   int          ## times this turn was already replayed

  Recovery* = enum
    rcReplay   ## put the message back in the user's session
    rcNotify   ## tell the user the turn was interrupted

const
  ReadOnlyToolNames* = [
    SessionSearchToolName, CurrentTimeToolName, CalcToolName,
    WebSearchToolName, FetchToolName, WebFetchToolName,
    ReadFileToolName, FindToolName, GrepToolName, WcToolName, HeadToolName,
    TailToolName, FsListToolName, FsReadToolName, TextSearchToolName,
    TextReadToolName, JsonQueryToolName, TableQueryToolName,
    InspectImageToolName]
    ## Tools that only read. Any other tool, an MCP or skill tool included,
    ## counts as an effect: the safe side is a notice, never a repeat.
  ReplayMaxAgeMs* = 24 * 3_600_000'i64
    ## Older interrupted turns only get the notice: the moment has passed.
  PreviewMaxBytes* = 120

func isEffectfulTool*(name: string): bool =
  name notin ReadOnlyToolNames

func withEffect*(r: TurnRecord; toolName: string): TurnRecord =
  result = r
  if toolName notin result.effects:
    result.effects.add toolName

func newTurnId*(startedMs: int64; userId, msgId: string): string =
  ## Digits and a hex digest: safe as a file name whatever the ids hold.
  $startedMs & "-" & toHex(hash(userId & "\x1f" & msgId).uint64)

func journalFileName*(id: string): string = id & ".json"

func turnIdOfFile*(name: string): string =
  ## The turn id of a journal file name; "" for any other file.
  if not name.endsWith(".json") or name.len <= ".json".len:
    return ""
  let id = name[0 ..< name.len - ".json".len]
  for c in id:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '-'}:
      return ""
  id

func turnPreview*(text: string): string =
  ## The message on one line, clipped on a character boundary.
  let flat = text.replace('\n', ' ').replace('\r', ' ').strip
  if flat.len <= PreviewMaxBytes:
    return flat
  var stop = 0
  for r in flat.runes:
    let size = r.size
    if stop + size > PreviewMaxBytes:
      break
    stop += size
  flat[0 ..< stop].strip(leading = false) & "…"

proc recordJson*(r: TurnRecord): string =
  $(%* {"id": r.id, "user": r.userId, "channel": $r.channel,
        "reply_to": r.replyTo, "payload": r.payload, "preview": r.preview,
        "started_ms": r.startedMs, "effects": r.effects, "resumes": r.resumes})

func channelOf(name: string; kind: var ChannelKind): bool =
  for k in ChannelKind:
    if $k == name:
      kind = k
      return true
  false

proc parseTurnRecord*(text: string): Result[TurnRecord, string] =
  let j =
    try: parseJson(text)
    except CatchableError as e: return err("turn record: " & e.msg)
  if j.kind != JObject:
    return err("turn record: not an object")
  for key in ["id", "user", "channel"]:
    if j{key}.isNil or j{key}.kind != JString or j{key}.getStr.len == 0:
      return err("turn record: missing " & key)
  if j{"started_ms"}.isNil or j{"started_ms"}.kind != JInt:
    return err("turn record: missing started_ms")
  var r = TurnRecord(id: j["id"].getStr, userId: j["user"].getStr,
                     replyTo: j{"reply_to"}.getStr, payload: j{"payload"}.getStr,
                     preview: j{"preview"}.getStr,
                     startedMs: j["started_ms"].getBiggestInt,
                     resumes: j{"resumes"}.getInt)
  if not channelOf(j["channel"].getStr, r.channel):
    return err("turn record: unknown channel " & j["channel"].getStr)
  if not j{"effects"}.isNil and j{"effects"}.kind == JArray:
    for e in j["effects"]:
      if e.kind == JString:
        r.effects.add e.getStr
  ok(r)

func decideRecovery*(r: TurnRecord; nowMs: int64;
                     maxAgeMs = ReplayMaxAgeMs): Recovery =
  if r.effects.len > 0 or r.resumes > 0 or nowMs - r.startedMs > maxAgeMs:
    rcNotify
  else:
    rcReplay

func interruptedNotice*(r: TurnRecord): string =
  result = "Fui interrompido (o serviço reiniciou) enquanto respondia a “" &
           r.preview & "”."
  if r.effects.len > 0:
    result.add " Já tinha usado: " & r.effects.join(", ") &
               ". Não repeti nada; quer que eu continue?"
  else:
    result.add " Pode mandar de novo?"
