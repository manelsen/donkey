## send_file (E9.6): a file from the person's paddock goes to the channel of
## the conversation; where the channel cannot upload a local file, the agent
## is told so, to tell the person where the file is.

import std/[json, options, os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/channel_capability
import donkey/adapters/filesystem/fs_adapter
import donkey/app/tools/file_tools
import donkey/app/native_tools
import donkey/app/session_bootstrap

proc paddock(): string =
  result = getTempDir() / "donkey_send_file"
  removeDir(result)
  createDir(result / "attachments")
  writeFile(result / "attachments" / "relatorio.pdf", "%PDF")

proc runTests*() =
  suite "send_file":
    test "only the channels that upload a local file are offered it":
      check supports(ckTelegram, cfSendFile) and supports(ckMattermost, cfSendFile)
      check supports(ckDiscord, cfSendFile)       ## multipart upload since E9
      check supports(ckSlack, cfSendFile)         ## external upload since E9
      check supports(ckWhatsApp, cfSendFile)      ## media API upload since E9
      check not supports(ckSignal, cfSendFile)
      check not supports(ckSms, cfSendFile)

    test "on a channel that uploads: the file goes out with the reply's target":
      let dir = paddock()
      let r = prepareSendFile(newFsAdapter(), dir, dir / "attachments" / "relatorio.pdf",
        "segue", ckMattermost, UserId("u1"), "chan-1:root-9").get
      check r.outbound.isSome
      let o = r.outbound.get
      check o.mediaUrl == dir / "attachments" / "relatorio.pdf" and o.mediaRoot == dir
      check o.text == "segue" and o.replyTo == "chan-1:root-9" and o.channel == ckMattermost
      check "relatorio.pdf" in r.text

    test "on a channel that cannot: nothing goes out, the agent is told where the file is":
      let dir = paddock()
      let r = prepareSendFile(newFsAdapter(), dir, dir / "attachments" / "relatorio.pdf",
        "", ckSms, UserId("u1"), "").get
      check r.outbound.isNone
      check "attachments/relatorio.pdf" in r.text and "cannot" in r.text

    test "a missing file, or a directory, is an error":
      let dir = paddock()
      check prepareSendFile(newFsAdapter(), dir, dir / "nada.txt", "", ckTelegram,
                            UserId("u1"), "").isErr
      check prepareSendFile(newFsAdapter(), dir, dir / "attachments", "", ckTelegram,
                            UserId("u1"), "").isErr

proc runToolTests*() =
  suite "send_file — the tool":
    test "the path resolves inside the paddock; outside it is refused":
      let dir = paddock()
      let ok1 = parseSendFileContext(%* {"path": "attachments/relatorio.pdf", "caption": "oi"},
                                     dir, fs = newFsAdapter())
      check ok1.isOk and ok1.get.path == dir / "attachments" / "relatorio.pdf"
      check ok1.get.caption == "oi"
      check parseSendFileContext(%* {"path": "/etc/passwd"}, dir, fs = newFsAdapter()).isErr
      check parseSendFileContext(%* {"path": "../../etc/passwd"}, dir, fs = newFsAdapter()).isErr
      check parseSendFileContext(%* {}, dir, fs = newFsAdapter()).isErr

    test "the agent is offered the tool":
      var found = false
      for t in nativeSessionTools():
        if t.name == "send_file": found = true
      check found

when isMainModule:
  runTests()
  runToolTests()
