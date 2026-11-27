## The capability registry says what each channel's port does (drift found
## on 26/11): WeChat, Feishu and DingTalk download attachments though the
## registry said they did not, and Signal's port downloads nothing though the
## registry said it did.

import std/unittest
import donkey/core/types
import donkey/ports/channel_capability

const DownloadsAttachments = {ckTelegram, ckDiscord, ckWhatsApp, ckWeChat, ckFeishu,
                              ckDingTalk, ckMatrix, ckTeams, ckMattermost, ckSms,
                              ckGoogleChat}
  ## the channels whose outbound port wires downloadFile (outbound_builder)

proc runTests*() =
  suite "capability registry and ports":
    test "downloadFile is declared exactly where the port downloads":
      for k in ChannelKind:
        checkpoint($k)
        check supports(k, cfDownloadFile) == (k in DownloadsAttachments)

when isMainModule:
  runTests()
