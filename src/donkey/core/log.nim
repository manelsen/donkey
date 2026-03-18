## Structured logger — nullclaw Observer pattern, Nim flavour.
##
## Usage:
##   let log = newLogger("agent.memory")
##   log.info("loaded 42 memories")
##   let child = log.child("retrieval")
##
## Tests pass a custom `sink` proc to capture output.
## In production the default sink writes to stderr.

import std/[strformat, times]
import ./types

type
  LogEntry* = object
    timestamp*: string   ## ISO-8601 wall clock
    level*:     LogLevel
    subsystem*: string
    message*:   string

  LogSink* = proc(entry: LogEntry) {.closure.}

  Logger* = object
    subsystem*: string
    minLevel*:  LogLevel
    sink*:      LogSink

# ── default sink ──────────────────────────────────────────────────────────────

func toTag(l: LogLevel): string =
  case l
  of lvlDebug: "DBG"
  of lvlInfo:  "INF"
  of lvlWarn:  "WRN"
  of lvlError: "ERR"
  of lvlFatal: "FTL"

proc stderrSink(e: LogEntry) {.gcsafe, raises: [].} =
  try: stderr.writeLine &"[{e.timestamp}] {e.level.toTag} [{e.subsystem}] {e.message}"
  except IOError: discard

# ── constructors ──────────────────────────────────────────────────────────────

func newLogger*(subsystem: string;
                level: LogLevel = lvlInfo;
                sink: LogSink = stderrSink): Logger =
  Logger(subsystem: subsystem, minLevel: level, sink: sink)

func child*(logger: Logger; subsystem: string): Logger =
  Logger(subsystem: logger.subsystem & "." & subsystem,
         minLevel:  logger.minLevel,
         sink:      logger.sink)

# ── emit ──────────────────────────────────────────────────────────────────────

proc log*(logger: Logger; level: LogLevel; msg: string) {.gcsafe, raises: [].} =
  if level < logger.minLevel: return
  {.cast(gcsafe).}:
    try:
      logger.sink(LogEntry(
        timestamp: now().format("yyyy-MM-dd'T'HH:mm:ss"),
        level:     level,
        subsystem: logger.subsystem,
        message:   msg,
      ))
    except Exception: discard

template debug*(logger: Logger; msg: string) = logger.log(lvlDebug, msg)
template info*(logger: Logger; msg: string)  = logger.log(lvlInfo,  msg)
template warn*(logger: Logger; msg: string)  = logger.log(lvlWarn,  msg)
template error*(logger: Logger; msg: string) = logger.log(lvlError, msg)
template fatal*(logger: Logger; msg: string) = logger.log(lvlFatal, msg)
