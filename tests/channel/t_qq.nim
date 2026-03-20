import std/unittest
import results
import donkey/adapters/channel/qq
import donkey/adapters/identity/identity_resolver as ids
import donkey/core/types

suite "QQAdapter":

  test "parseEventJson reads private message":
    let payload = """{
      "post_type":"message",
      "message_type":"private",
      "user_id":12345,
      "message_id":77,
      "raw_message":"hello"
    }"""
    let event = parseEventJson(payload).get()
    check event.messageType == "private"
    check event.userId == "12345"
    check event.messageId == "77"
    check event.content == "hello"

  test "targetFor uses group prefix when present":
    let path = "/tmp/qq_ids.tsv"
    var adapter = newQQAdapter("http://127.0.0.1:5700", "token", path)
    let uid = ids.resolve(adapter.resolver, ckQQ, "group:9988")
    let target = adapter.targetFor(uid).get()
    check target[0] == "send_group_msg"
    check target[1] == "9988"
