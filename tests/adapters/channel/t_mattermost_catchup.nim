## Mattermost catch-up (open item of round 2): after a drop, the posts
## written meanwhile in the bot's channels are fetched and queued, under the
## live rules, oldest first, at most a day back.

import std/[json, strutils, unittest]
import donkey/adapters/channel/mattermost
import donkey/adapters/channel/mattermost_socket
import donkey/core/pipeops
import donkey/ports/http

proc fakeApi(seen: ref seq[string]): HttpRuntimePort =
  HttpRuntimePort(get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
    {.cast(gcsafe).}: seen[].add url
    if url.endsWith("/users/me/teams"):
      return ok(HttpResponse(status: 200, body: """[{"id":"t1"}]"""))
    if url.endsWith("/users/me/teams/t1/channels"):
      return ok(HttpResponse(status: 200, body: """[{"id":"d1","type":"D"},{"id":"c2","type":"O"}]"""))
    if "/channels/d1/posts" in url:
      return ok(HttpResponse(status: 200, body: $(%* {"order": ["a"], "posts": {"a":
        {"id": "a", "user_id": "alice", "channel_id": "d1", "message": "você viu?", "type": "", "create_at": 2000}}})))
    if "/channels/c2/posts" in url:
      return ok(HttpResponse(status: 200, body: $(%* {"order": ["b", "c"], "posts": {
        "b": {"id": "b", "user_id": "bob", "channel_id": "c2", "message": "@donkey ajuda", "type": "", "create_at": 1500},
        "c": {"id": "c", "user_id": "bob", "channel_id": "c2", "message": "sem menção", "type": "", "create_at": 1600}}})))
    ok(HttpResponse(status: 404, body: "")))

proc runTests*() =
  suite "mattermost catch-up":

    test "the posts written meanwhile, under the live rules, oldest first":
      let seen = new seq[string]
      let posts = catchUpPosts(fakeApi(seen), "https://chat.example.com", "tok",
                               MattermostMe(id: "botuid", username: "donkey"), sinceMs = 1000,
                               nowMs = 3000)
      check posts.len == 2
      check posts[0].id == "b" and posts[0].text == "ajuda"
      check posts[1].id == "a" and not posts[1].isGroup
      var since = false
      for u in seen[]:
        if "posts?since=1000" in u: since = true
      check since

    test "never more than a day back":
      let seen = new seq[string]
      discard catchUpPosts(fakeApi(seen), "https://chat.example.com", "tok",
                           MattermostMe(id: "botuid", username: "donkey"), sinceMs = 1,
                           nowMs = 100 * 86_400_000)
      var ok = false
      for u in seen[]:
        if "posts?since=" & $(99 * 86_400_000) in u: ok = true
      check ok

when isMainModule:
  runTests()
