## Discord uploads a paddock file (E9, send_file): one multipart POST with
## the message as payload_json and the file as files[0], read only inside
## the paddock.

import std/[json, os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/channel_capability
import donkey/adapters/channel/discord

proc paddock(): string =
  result = getTempDir() / "donkey_discord_upload"
  removeDir(result)
  createDir(result / "attachments")
  writeFile(result / "attachments" / "relatorio.pdf", "%PDF-1.7")

proc runTests*() =
  suite "discord upload":
    test "a paddock file goes as files[0] with the text as payload_json":
      let dir = paddock()
      let a = newDiscordAdapter("tok", getTempDir() / "donkey_discord_upload_ids.tsv")
      let r = a.uploadRequest("chan-1", "segue o relatório",
                              dir / "attachments" / "relatorio.pdf", dir).get
      check r.url == "https://discord.com/api/v10/channels/chan-1/messages"
      var boundary = ""
      for (k, v) in r.headers:
        if k == "Content-Type" and v.startsWith("multipart/form-data; boundary="):
          boundary = v["multipart/form-data; boundary=".len .. ^1]
      check boundary.len > 0
      check ("Authorization", "Bot tok") in r.headers
      check "name=\"payload_json\"" in r.body and "segue o relat" in r.body
      check "name=\"files[0]\"; filename=\"relatorio.pdf\"" in r.body
      check "%PDF-1.7" in r.body
      check "\"allowed_mentions\"" in r.body   ## the same safe mentions as text

    test "a path outside the paddock is never read":
      let dir = paddock()
      let a = newDiscordAdapter("tok", getTempDir() / "donkey_discord_upload_ids2.tsv")
      check a.uploadRequest("chan-1", "", "/etc/passwd", dir).isErr

    test "Discord is offered send_file":
      check supports(ckDiscord, cfSendFile)

when isMainModule:
  runTests()
