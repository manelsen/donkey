## Structured logger — nullclaw Observer pattern, Nim flavour.
##
## Usage:
##   let log = newLogger("agent.memory")
##   log.info("loaded 42 memories")
##   let child = log.child("retrieval")
##
## Tests pass a custom `sink` proc to capture output.
## In production the default sink writes to stderr.

import std/[locks, strformat, times]
import ./types

type
  LogEntry* = object
    timestamp*: string   ## ISO-8601 wall clock
    level*:     LogLevel
    subsystem*: string
    message*:   string

  LogSink* = proc(entry: LogEntry) {.closure, gcsafe.}

  Logger* = object
    subsystem*: string
    minLevel*:  LogLevel
    sink*:      LogSink

  RingEntry* = object   ## compact ring-buffer record (IPC-visible)
    ts*:    string
    level*: string   ## "DBG"|"INF"|"WRN"|"ERR"|"FTL"
    sub*:   string
    msg*:   string

# ── ring buffer (global, optional — init only in daemon) ──────────────────────

const RingCap* = 500

var gRingBuf:   array[RingCap, RingEntry]
var gRingHead:  int
var gRingCount: int
var gRingLock:  Lock
var gRingReady: bool   ## false until ringInit() called

proc ringInit*() =
  ## Call once in the daemon before creating the first Logger.
  ## CLI tools must NOT call this — the default sink remains stderr-only.
  initLock(gRingLock)
  gRingReady = true

proc ringPush(e: LogEntry) =
  ## Called from the default sink when gRingReady. GC-safe.
  {.gcsafe.}:
    if not gRingReady: return
    let tag = case e.level
      of lvlDebug: "DBG"
      of lvlInfo:  "INF"
      of lvlWarn:  "WRN"
      of lvlError: "ERR"
      of lvlFatal: "FTL"
    acquire(gRingLock)
    gRingBuf[gRingHead] = RingEntry(
      ts: e.timestamp, level: tag, sub: e.subsystem, msg: e.message)
    gRingHead  = (gRingHead + 1) mod RingCap
    if gRingCount < RingCap: inc gRingCount
    release(gRingLock)

proc ringSnapshot*(n: int): seq[RingEntry] {.gcsafe.} =
  ## Returns up to n most recent entries, oldest first.
  if not gRingReady: return @[]
  {.cast(gcsafe).}:
    acquire(gRingLock)
    defer: release(gRingLock)
    let take   = min(n, gRingCount)
    let offset = gRingCount - take
    let oldest = if gRingCount < RingCap: 0 else: gRingHead
    result = newSeq[RingEntry](take)
    for i in 0 ..< take:
      result[i] = gRingBuf[(oldest + offset + i) mod RingCap]

# ── human-friendly mode (TTY) ────────────────────────────────────────────────

var gHumanLog {.global.}: bool = false

proc enableHumanLog*() =
  ## Switch stderr output to compact, colored human format.
  ## Call once from main when stderr is a TTY.
  {.cast(gcsafe).}: gHumanLog = true

proc shortenUuids(s: string): string =
  ## Replace 36-char UUID strings with [first8chars].
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if i + 35 < s.len and
        s[i + 8] == '-' and s[i + 13] == '-' and
        s[i + 18] == '-' and s[i + 23] == '-':
      var ok = true
      for j in 0 .. 35:
        let c = s[i + j]
        if j in {8, 13, 18, 23}:
          if c != '-': ok = false; break
        elif not (c in '0'..'9' or c in 'a'..'f' or c in 'A'..'F'):
          ok = false; break
      if ok:
        result.add('[')
        result.add(s[i ..< i + 8])
        result.add(']')
        i += 36
        continue
    result.add(s[i])
    inc i

const
  Rst = "\e[0m"
  Dim = "\e[2m"
  Yel = "\e[33m"
  Red = "\e[31m"
  Mag = "\e[1m\e[35m"

proc humanLine(e: LogEntry) =
  let ts  = if e.timestamp.len >= 19: e.timestamp[11 .. 18] else: e.timestamp
  let msg = shortenUuids(e.message)
  case e.level
  of lvlDebug:
    stderr.writeLine(Dim & ts & "  · " & msg & Rst)
  of lvlInfo:
    stderr.writeLine(Dim & ts & Rst & "  " & msg)
  of lvlWarn:
    stderr.writeLine(Dim & ts & Rst & "  " & Yel & "!" & Rst & " " & msg)
  of lvlError:
    stderr.writeLine(Dim & ts & Rst & "  " & Red & "x" & Rst & " " & msg)
  of lvlFatal:
    stderr.writeLine(Dim & ts & Rst & "  " & Mag & "!!" & Rst & " " & msg)

# ── default sink ──────────────────────────────────────────────────────────────

proc stderrSink(e: LogEntry) =
  {.cast(gcsafe).}:
    if gHumanLog:
      humanLine(e)
    else:
      let tag = case e.level
        of lvlDebug: "DBG"
        of lvlInfo:  "INF"
        of lvlWarn:  "WRN"
        of lvlError: "ERR"
        of lvlFatal: "FTL"
      stderr.writeLine &"[{e.timestamp}] {tag} [{e.subsystem}] {e.message}"
    ringPush(e)

# ── constructors ──────────────────────────────────────────────────────────────

proc newLogger*(subsystem: string;
                level: LogLevel = lvlInfo;
                sink: LogSink = stderrSink): Logger =
  Logger(subsystem: subsystem, minLevel: level, sink: sink)

proc child*(logger: Logger; subsystem: string): Logger =
  Logger(subsystem: logger.subsystem & "." & subsystem,
         minLevel:  logger.minLevel,
         sink:      logger.sink)

# ── emit ──────────────────────────────────────────────────────────────────────

proc log*(logger: Logger; level: LogLevel; msg: string) {.raises: [].} =
  if level < logger.minLevel: return
  try:
    logger.sink(LogEntry(
      timestamp: now().format("yyyy-MM-dd'T'HH:mm:ss"),
      level:     level,
      subsystem: logger.subsystem,
      message:   msg,
    ))
  except: discard

template debug*(logger: Logger; msg: string) = logger.log(lvlDebug, msg)
template info*(logger: Logger; msg: string)  = logger.log(lvlInfo,  msg)
template warn*(logger: Logger; msg: string)  = logger.log(lvlWarn,  msg)
template error*(logger: Logger; msg: string) = logger.log(lvlError, msg)
template fatal*(logger: Logger; msg: string) = logger.log(lvlFatal, msg)
