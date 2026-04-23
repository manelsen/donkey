## ChannelPort — concept for messaging channels (Telegram, Discord, WeChat…).
##
## `c` is immutable: send and ack work on a value or ref.
## `vc` is mutable: receive may advance internal state (offset, buffer, etc.).
##
## Discord's send() uses a ref Table internally for DM channel caching, so it
## works fine with an immutable receiver despite mutating the cache through the ref.
##
## Pure helpers follow the pipeops topology:
##   filterInbound   — last-arg for |>->  (msgs |>-> filterInbound(userId))
##   countInbound    — unary for |>       (msgs |> countInbound)
##   validateOutbound — Result for >>=    (build() >>= validateOutbound >>= send)

import ../domain/message
import ../core/pipeops

type
  ## File download result type (channel-agnostic)
  FileDownload* = object
    fileName*: string
    fileSize*: int64
    mimeType*: string
    localPath*: string  ## empty if not saved to disk yet
    data*: seq[byte]

  ChannelPort* = concept c, var vc
    c.send(OutboundMessage) is Result[void, string]
    vc.receive() is Result[seq[InboundMessage], string]
    c.ack(string)
    ## Media operations (optional - adapters may return "unsupported" error)
    c.downloadFile(string) is Result[FileDownload, string]

  OutboundChannelPort* = object
    send*:         proc(msg: OutboundMessage): Result[void, string] {.gcsafe.}
    sendReturnId*: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.}
    editMessage*:  proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.}
    sendKeyboard*: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.}
    editKeyboard*: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.}
    setMessageReaction*: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.}
    downloadFile*: proc(fileId: string): Result[FileDownload, string] {.gcsafe.}

  OutboundChannelPorts* = object
    telegram*: OutboundChannelPort
    discord*:  OutboundChannelPort
    wecom*:    OutboundChannelPort
    wechat*:   OutboundChannelPort
    qq*:       OutboundChannelPort
    feishu*:   OutboundChannelPort
    slack*:     OutboundChannelPort
    whatsapp*:  OutboundChannelPort
    signal*:    OutboundChannelPort
    dingtalk*:  OutboundChannelPort
    matrix*:    OutboundChannelPort
    email*:     OutboundChannelPort
    cli*:       OutboundChannelPort

# ── pure helpers ──────────────────────────────────────────────────────────────

func filterInbound*(userId: UserId; msgs: seq[InboundMessage]): seq[InboundMessage] =
  ## Keeps only messages addressed to `userId`. Designed for |>->.
  ## Usage: msgs |>-> filterInbound(userId)
  for m in msgs:
    if m.userId == userId:
      result.add(m)

func countInbound*(msgs: seq[InboundMessage]): int =
  ## Returns the count of inbound messages. Designed for |>.
  msgs.len

func validateOutbound*(msg: OutboundMessage): Result[OutboundMessage, string] =
  ## Validates that an outbound message has non-empty text. Designed for >>=.
  if msg.text.len == 0:
    err("outbound message has empty text")
  else:
    ok(msg)
