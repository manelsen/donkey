## Tests for adapters/channel/wecom — WeCom (企业微信) webhook adapter.
##
## Tests verify the adapter's contractual behavior:
##   - Constructor sets fields correctly
##   - tryRecvEvent returns (false, empty) when queue is empty
##   - send returns err for unmapped users (correct — no identity mapping)
##   - startWebhook compiles and runs without panic (stub no-op)

import std/[net, strutils, unittest]
import donkey/core/log
import donkey/core/pipeops
import donkey/domain/message
import donkey/adapters/channel/wecom

suite "WeComAdapter — contract":

  test "newWeComAdapter populates fields":
    let a = newWeComAdapter(
      corpId        = "wx123",
      corpSecret    = "secret456",
      callbackToken = "token789",
      agentId       = 1000001,
      identityPath  = "/tmp/donkey_test_wecom_identity",
    )
    check a.corpId        == "wx123"
    check a.corpSecret    == "secret456"
    check a.callbackToken == "token789"
    check a.agentId       == 1000001

  test "tryRecvEvent returns (false, empty) on fresh adapter":
    var a = newWeComAdapter("c", "s", "t", 42, "/tmp/dw_id")
    let (ok, ev) = a.tryRecvEvent()
    check not ok
    check ev.msgType == ""
    check ev.fromUser == ""
    check ev.msgId == ""
    check ev.content == ""

  test "tryRecvEvent is non-blocking (does not hang)":
    ## Calls tryRecvEvent 5 times in succession; should always return quickly.
    var a = newWeComAdapter("c", "s", "t", 1, "/tmp/dw_id2")
    for _ in 0 ..< 5:
      let (ok, _) = a.tryRecvEvent()
      check not ok

  test "send returns err for user with no WeCom mapping":
    ## send requires a resolved WeCom user ID; without an identity mapping it
    ## returns err rather than making a network call.
    var a = newWeComAdapter("c", "s", "t", 1, "/tmp/dw_id3")
    let msg = OutboundMessage(userId: UserId("u"), text: "hello", channel: ckWeCom)
    let r = a.send(msg)
    check r.isErr
    let errMsg = r.error
    check errMsg.contains("no WeCom ID")

  test "startWebhook is a no-op and does not panic":
    var a = newWeComAdapter("c", "s", "t", 1, "/tmp/dw_id4")
    let logger = newLogger("test.wecom")
    a.startWebhook(Port(8080), logger)
    check true  ## reached without panic

suite "WeComEvent — field accessors":

  test "WeComEvent zero-value is well-defined":
    let ev = WeComEvent()
    check ev.msgType  == ""
    check ev.fromUser == ""
    check ev.msgId    == ""
    check ev.content  == ""

  test "WeComEvent construction with fields":
    let ev = WeComEvent(
      msgType:  "text",
      fromUser: "user_abc",
      msgId:    "msg_001",
      content:  "Hello WeCom",
    )
    check ev.msgType  == "text"
    check ev.fromUser == "user_abc"
    check ev.content  == "Hello WeCom"
