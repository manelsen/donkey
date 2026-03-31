## AgentMessage unit tests — pure domain types, no async.

import std/[strutils, unittest]
import donkey/domain/agent_message

suite "AgentMessage construction":

  test "task message carries kind and taskKind":
    let m = newTaskMsg(id = "t1", kind = tkUserMsg, userId = "u1", payload = "hello")
    check m.kind     == amkTask
    check m.taskKind == tkUserMsg
    check m.userId   == "u1"
    check m.payload  == "hello"
    check m.id       == "t1"

  test "result message carries text":
    let m = newResultMsg(id = "t1", text = "response")
    check m.kind == amkResult
    check m.id   == "t1"
    check m.text == "response"

  test "error message carries error string":
    let m = newErrorMsg(id = "t1", text = "timeout")
    check m.kind  == amkError
    check m.text == "timeout"

  test "cancel message has cancel kind":
    let m = newCancelMsg()
    check m.kind == amkCancel

suite "AgentMessage kind checks":

  test "isTask":
    check newTaskMsg("1", tkUserMsg, "u", "p").kind == amkTask

  test "isResult":
    check newResultMsg("1", "ok").kind == amkResult

  test "isCancel":
    check newCancelMsg().kind == amkCancel

suite "tkReset":

  test "tkReset message has task kind and reset taskKind":
    let m = newTaskMsg("r1", tkReset, "u1", "")
    check m.kind     == amkTask
    check m.taskKind == tkReset

  test "tkReset stringifies":
    check $tkReset == "tkReset"
