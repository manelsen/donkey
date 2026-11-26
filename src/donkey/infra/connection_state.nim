## connection_state — how many sockets each channel runs and how many are
## connected (second round, §3). The connection threads (persistent_socket,
## IRC) write the counts; the daemon's status reads them. Plain atomics in a
## global array: no GC memory crosses threads.

import std/atomics
import ../core/types

var
  gRunning: array[ChannelKind, Atomic[int]]
  gConnected: array[ChannelKind, Atomic[int]]
  gLastInbound: array[ChannelKind, Atomic[int64]]   ## epoch ms of the last message

proc noteInbound*(k: ChannelKind; nowMs: int64) =
  ## A message from `k` reached a turn: for the channels whose connection is
  ## not counted (webhooks, long poll), the status says how long ago.
  gLastInbound[k].store(nowMs)

proc lastInboundMs*(k: ChannelKind): int64 = gLastInbound[k].load()

func activeLabel*(lastMs, nowMs: int64): string =
  if lastMs <= 0: return "active, no message yet"
  let s = max(0'i64, nowMs - lastMs) div 1000
  let ago =
    if s < 60: $s & "s"
    elif s < 3600: $(s div 60) & "m"
    elif s < 86_400: $(s div 3600) & "h"
    else: $(s div 86_400) & "d"
  "active, last message " & ago & " ago"

proc dec0(a: var Atomic[int]) =
  ## Down by one, never below zero.
  var current = a.load()
  while current > 0 and not a.compareExchange(current, current - 1):
    discard

proc socketStarted*(k: ChannelKind) = gRunning[k].atomicInc()
proc socketConnected*(k: ChannelKind) = gConnected[k].atomicInc()
proc socketDisconnected*(k: ChannelKind) = dec0(gConnected[k])
proc socketEnded*(k: ChannelKind) = dec0(gRunning[k])

proc connectionCounts*(k: ChannelKind): tuple[running, connected: int] =
  (running: gRunning[k].load(), connected: min(gConnected[k].load(), gRunning[k].load()))

proc resetConnections*() =
  ## For tests.
  for k in ChannelKind:
    gRunning[k].store(0)
    gConnected[k].store(0)
    gLastInbound[k].store(0)

func connectionLabel*(tracked: bool; running, connected: int): string =
  ## `tracked`: the channel's sockets are counted here (a webhook channel,
  ## Telegram's long poll or Feishu's own socket are not).
  if not tracked: "active"
  elif running == 0: "stopped"
  elif connected >= running: "connected"
  elif connected == 0: "connecting"
  else: "reconnecting " & $connected & "/" & $running
