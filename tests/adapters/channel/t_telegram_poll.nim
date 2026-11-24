## Telegram's update poll runs off the Chronos loop, on the shared blocking
## executor: the adapter gives plain data (the request) and a `nimcall` fetch,
## and keeps the offset and identities on the loop.

import std/[os, tempfiles, unittest]
import chronos
import chronos/asyncsync
import donkey/adapters/channel/telegram
import donkey/app/blocking_executor
import donkey/core/pipeops
import donkey/infra/thread_handle
import donkey/ports/http

const UpdateBody = """{"ok":true,"result":[{"update_id":9,"message":{"message_id":10,"from":{"id":42},"chat":{"id":42,"type":"private"},"text":"/status"}}]}"""

proc exercisePoll(dir: string):
    Future[tuple[servedWhilePending: bool, message: string, offset: int64]]
    {.async: (raises: [Exception]).} =
  ## The fake server lives on this same loop. It sees the request, waits,
  ## then answers: if the poll blocked the loop, it could not even accept.
  let started = newAsyncEvent()
  let respond = newAsyncEvent()
  proc serve(server: StreamServer; client: StreamTransport) {.async: (raises: []).} =
    try:
      discard await client.readLine(4096)
      while (await client.readLine(4096)).len > 0:
        discard
      started.fire()
      await respond.wait()
      discard await client.write("HTTP/1.1 200 OK\r\nContent-Length: " &
        $UpdateBody.len & "\r\nConnection: close\r\n\r\n" & UpdateBody)
    except CatchableError:
      discard
    finally:
      await client.closeWait()

  let server = createStreamServer(initTAddress("127.0.0.1:0"), serve)
  server.start()
  var adapter = newTelegramAdapter("test", dir / "identities.json",
    apiBase = "http://" & $server.localAddress(), pollTimeout = 0)
  try:
    let poll = runOffLoop(fetchTelegramUpdates, adapter.pollRequest())
    let deadline = Moment.now() + seconds(5)
    while not started.isSet():
      if Moment.now() >= deadline:
        raise newException(IOError, "the fake server never saw getUpdates")
      await sleepAsync(milliseconds(10))
    await sleepAsync(milliseconds(30))
    let servedWhilePending = not poll.finished and adapter.offset == 0
    respond.fire()
    let messages = adapter.acceptTelegramUpdates(await poll).get
    return (servedWhilePending, messages[0].text, adapter.offset)
  finally:
    respond.fire()
    server.stop()
    await server.closeWait()

proc runTests*() =
  suite "telegram poll off the loop":

    test "the poll request is plain data that a worker can take":
      check sharesNothing(TelegramPoll)
      var adapter = newTelegramAdapter("tok", getTempDir() / "donkey_tg_poll_ids.json",
                                       pollTimeout = 10)
      adapter.offset = 77
      let req = adapter.pollRequest()
      check req.url == "https://api.telegram.org/bottok/getUpdates?offset=77&timeout=10" &
                       "&allowed_updates=[\"message\",\"callback_query\"]"
      ## The HTTP deadline covers Telegram's wait plus the usual timeout.
      check req.timeoutSec > 10
      check req.allowlist == @["api.telegram.org"]

    test "a pending poll leaves the loop free; the offset moves only on accept":
      let dir = createTempDir("donkey_tg_poll_", "")
      defer: removeDir(dir)
      let (servedWhilePending, message, offset) = waitFor exercisePoll(dir)
      check servedWhilePending
      check message == "/status"
      check offset == 10

    test "a failed fetch is an error, and the offset stays":
      var adapter = newTelegramAdapter("tok", getTempDir() / "donkey_tg_poll_ids2.json")
      adapter.offset = 5
      let r = adapter.acceptTelegramUpdates(err(Result[HttpResponse, string], "timeout"))
      check r.isErr
      check adapter.offset == 5

when isMainModule:
  runTests()
