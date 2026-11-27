## E12.3: Mattermost's socket as its own process — the glue on each side.

import std/unittest
import donkey/adapters/channel/mattermost
import donkey/adapters/channel/mattermost_socket
import donkey/core/types

proc runTests*() =
  suite "mattermost — as its own process (E12.3)":
    test "the daemon's side: the child's posts into the inbound queue; nothing goes back":
      let p = MattermostPost(id: "p1", userId: "u1", channelId: "c1", text: "oi")
      mattermostProcessSink(postToWire(p))
      let (has, got) = tryRecvPost()
      check has and got == p
      mattermostProcessSink("{not json")          ## dropped, not raised
      check not tryRecvPost()[0]
      check mattermostProcessSource() == (false, "")   ## replies go out by REST, here

    test "the child's side: the socket's posts out":
      let p = MattermostPost(id: "p2", userId: "u2", channelId: "c2", text: "e aí")
      check pushPost(p)
      check mattermostWorkerEvent() == (true, postToWire(p))
      check mattermostWorkerEvent() == (false, "")

    test "the command is this binary's channel-worker":
      let spec = mattermostWorkerSpec("/usr/bin/donkey")
      check spec.args == @["channel-worker", "mattermost"] and spec.channel == ckMattermost

when isMainModule:
  runTests()
