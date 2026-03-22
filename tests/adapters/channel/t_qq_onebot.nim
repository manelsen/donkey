import std/unittest
import donkey/core/pipeops
import donkey/adapters/channel/qq

suite "QQAdapter OneBot":

  test "parseEventJson extracts private message":
    let json = """{"post_type":"message","message_type":"private",
                   "user_id":123456,"message_id":9,"raw_message":"hello"}"""
    let r = parseEventJson(json)
    check r.isOk
    check r.value.messageType == "private"
    check r.value.userId      == "123456"
    check r.value.content     == "hello"

  test "parseEventJson extracts group message":
    let json = """{"post_type":"message","message_type":"group",
                   "user_id":111,"group_id":999,"message_id":7,"raw_message":"hi"}"""
    let r = parseEventJson(json)
    check r.isOk
    check r.value.messageType == "group"
    check r.value.groupId     == "999"

  test "parseEventJson rejects non-message post_type":
    let json = """{"post_type":"notice","sub_type":"group_upload"}"""
    check parseEventJson(json).isErr

  test "parseEventJson rejects missing user_id":
    let json = """{"post_type":"message","message_type":"private","raw_message":"x"}"""
    check parseEventJson(json).isErr

  test "enqueueEventJson and tryRecvEvent round-trip":
    var a = newQQAdapter("", "", "/tmp/qq_test_ids.tsv")
    let json = """{"post_type":"message","message_type":"private",
                   "user_id":42,"message_id":1,"raw_message":"ping"}"""
    let r = a.enqueueEventJson(json)
    check r.isOk
    let (ok, event) = a.tryRecvEvent()
    check ok
    check event.content  == "ping"
    check event.userId   == "42"

  test "tryRecvEvent returns false on empty queue":
    var a = newQQAdapter("", "", "/tmp/qq_test_empty.tsv")
    let (ok, _) = a.tryRecvEvent()
    check not ok
