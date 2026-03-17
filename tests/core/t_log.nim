## Logger tests — verifies filtering, child loggers, and subsystem names

import std/[strutils, unittest]
import donkey/core/log
import donkey/core/types

suite "Logger":

  test "newLogger sets subsystem and level":
    let log = newLogger("test", lvlInfo)
    check log.subsystem == "test"
    check log.minLevel  == lvlInfo

  test "child logger inherits parent subsystem":
    let parent = newLogger("agent")
    let child  = parent.child("memory")
    check child.subsystem == "agent.memory"
    check child.minLevel  == parent.minLevel

  test "messages below minLevel are silently dropped":
    var written = 0
    let log = newLogger("filter", lvlWarn, sink = proc(e: LogEntry) = inc written)
    log.debug("should be dropped")
    log.info("should be dropped")
    log.warn("should pass")
    log.error("should pass")
    check written == 2

  test "message above minLevel reaches sink":
    var got: LogEntry
    let log = newLogger("sink_test", lvlDebug,
                        sink = proc(e: LogEntry) = got = e)
    log.info("hello donkey")
    check got.message   == "hello donkey"
    check got.level     == lvlInfo
    check got.subsystem == "sink_test"

  test "LogEntry has non-empty timestamp":
    var got: LogEntry
    let log = newLogger("ts_test", lvlDebug,
                        sink = proc(e: LogEntry) = got = e)
    log.debug("ts check")
    check got.timestamp.len > 0
