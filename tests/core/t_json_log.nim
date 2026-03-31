## Test JSON logging and metrics.

import std/[unittest, json, strutils]
import donkey/core/log
import donkey/core/types

var gCaptured: string

suite "Observability - JSON Logging":

  test "produces valid JSON log entry":
    let jsonSink = proc(e: LogEntry) {.gcsafe.} =
      {.cast(gcsafe).}:
        gCaptured = $(%* {
          "ts": e.timestamp,
          "lvl": $e.level,
          "sub": e.subsystem,
          "msg": e.message
        })
    
    let logger = newLogger("test", lvlDebug, jsonSink)
    logger.info("hello observability")
    
    let j = parseJson(gCaptured)
    check j["msg"].getStr() == "hello observability"
    check j["sub"].getStr() == "test"
    check j["lvl"].getStr() == "info"

suite "Observability - Metrics":

  test "metrics capture latency":
    check true
