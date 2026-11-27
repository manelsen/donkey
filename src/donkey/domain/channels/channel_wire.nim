## channel_wire — the lines between the daemon and a channel run as its own
## process (E12.3).
##
## One JSON object per line, behind a mark so the child's log lines (its
## stderr goes to the same pipe) pass through as `wfLog`. From the child:
## `wfEvent` (an inbound message, the channel's own JSON), `wfUp`/`wfDown`
## (its connection). To the child: `wfOut` (an outbound line or message).

import std/[json, strutils]
import ../../core/pipeops
import ../../core/types

export strutils.startsWith

const WireMark* = "\x1edonkey:"

type
  WireKind* = enum
    wfEvent, wfUp, wfDown, wfOut, wfLog

  WireFrame* = object
    kind*: WireKind
    payload*: string

const Codes: array[WireKind, string] = ["event", "up", "down", "out", "log"]

proc encodeFrame*(f: WireFrame): string =
  ## `$` of a JsonNode escapes newlines: one frame is one line.
  WireMark & $(%*{"k": Codes[f.kind], "p": f.payload})

proc decodeFrame*(line: string): Result[WireFrame, string] =
  if not line.startsWith(WireMark):
    return ok(WireFrame(kind: wfLog, payload: line))
  let node =
    try: parseJson(line[WireMark.len .. ^1])
    except CatchableError as e: return err("channel wire: " & e.msg)
  if node.kind != JObject:
    return err("channel wire: not an object")
  let code = node{"k"}.getStr
  for k in WireKind:
    if Codes[k] == code and k != wfLog:
      return ok(WireFrame(kind: k, payload: node{"p"}.getStr))
  err("channel wire: unknown frame " & code)

const ProcessCapable* = {ckIrc, ckMattermost, ckDiscord}
  ## The channels that know how to run as their own process.

func processChannels*(value: string): Result[set[ChannelKind], string] =
  ## `DONKEY_CHANNEL_PROCESSES`: comma-separated channel names.
  var chosen: set[ChannelKind]
  for raw in value.split(','):
    let name = raw.strip.toLowerAscii
    if name.len == 0: continue
    var found = false
    for k in ProcessCapable:
      if $k == name:
        chosen.incl k
        found = true
    if not found:
      var known: seq[string]
      for k in ProcessCapable: known.add $k
      return err("DONKEY_CHANNEL_PROCESSES: " & name &
                 " cannot run as its own process (only " & known.join(", ") & ")")
  ok(chosen)
