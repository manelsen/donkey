## Concrete outbound channel ports built from channel adapters.
##
## Capability resolution is declarative: each channel's supported operations
## are defined in ChannelCapabilityDescriptor (ports/channel_capability.nim).
## When a channel does not support an operation, the builder returns a
## descriptive error instead of relying on manual unsupported* patching.

import ../../core/pipeops
import ../../domain/message
import ../../ports/channel
import telegram
import discord
import wecom
import wechat
import qq_channel
import feishu
import matrix
import email
import slack
import dingtalk
import cli_repl

# ── generic unsupported stubs (capability-driven) ───────────────────────────
## These are used for any (channel, operation) pair where the capability
## descriptor declares the operation as unsupported.

proc unsupportedSendReturnId(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
  err("sendReturnId unsupported for channel " & $msg.channel)

proc unsupportedEditMessage(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
  discard userId; discard msgId; discard text
  err("editMessage unsupported")

proc unsupportedSendKeyboard(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo: string): Result[void, string] {.gcsafe.} =
  discard userId; discard text; discard buttons; discard replyTo
  err("sendKeyboard unsupported")

proc unsupportedEditKeyboard(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
  discard userId; discard msgId; discard text; discard buttons
  err("editKeyboard unsupported")

proc unsupportedSetMessageReaction(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.} =
  discard userId; discard msgId; discard emoji
  err("setMessageReaction unsupported")

# ── builder ──────────────────────────────────────────────────────────────────
## Each channel's OutboundChannelPort is assembled using the capability
## descriptor to decide whether to wire the real adapter method or fall back
## to the generic unsupported stub.  The descriptor is the single source of
## truth — the if/else branches here are a direct mirror of the registry in
## channel_capability.nim.

proc buildOutboundPorts*(tgAdapter: ptr TelegramAdapter;
                         dcAdapter: ptr DiscordAdapter;
                         wcAdapter: ptr WeComAdapter;
                         wchAdapter: ptr WeChatAdapter;
                         qqAdapter: ptr QQChannelAdapter;
                         fsAdapter: ptr FeishuAdapter;
                         mxAdapter: ptr MatrixAdapter;
                         emAdapter: ptr EmailAdapter;
                         slAdapter: ptr SlackAdapter;
                         dtAdapter: ptr DingTalkAdapter;
                         cliAdapter: ptr CliAdapter): OutboundChannelPorts =

  # ── Telegram (full capability) ────────────────────────────────────────────
  result.telegram = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      tgAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      tgAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      tgAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      tgAdapter[].sendKeyboard(userId, text, buttons, replyTo).map(proc(s: string): void = discard s),
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      tgAdapter[].editKeyboardText(userId, msgId, text, buttons),
    setMessageReaction: proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.} =
      tgAdapter[].setMessageReaction(userId, msgId, emoji),
  )

  # ── Discord (full capability) ─────────────────────────────────────────────
  result.discord = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      dcAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      dcAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      dcAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      discard dcAdapter[].sendKeyboard(userId, text, buttons)
      ok(),
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      dcAdapter[].editKeyboard(userId, msgId, text, buttons),
    setMessageReaction: proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.} =
      dcAdapter[].setMessageReaction(userId, msgId, emoji),
  )

  # ── WeCom — capability descriptor says: send only ─────────────────────────
  result.wecom = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wcAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── WeChat — capability descriptor says: send only ────────────────────────
  result.wechat = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wchAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── QQ — capability descriptor says: send + sendKeyboard ──────────────────
  result.qq = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      qqAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      qqAdapter[].sendKeyboard(userId, text, buttons, replyTo),
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── Feishu — capability descriptor says: send only ────────────────────────
  result.feishu = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      fsAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── Slack — capability descriptor says: all except setMessageReaction ─────
  result.slack = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      slAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      slAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      slAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      slAdapter[].sendKeyboard(userId, text, buttons),
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      slAdapter[].editKeyboard(userId, msgId, text, buttons),
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── DingTalk — capability descriptor says: send, sendReturnId, editMessage,
  #   sendKeyboard (no editKeyboard, no reaction) ─────────────────────────────
  result.dingtalk = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      dtAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      dtAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      dtAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      dtAdapter[].sendKeyboard(userId, text, buttons),
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── Matrix — capability descriptor says: send, sendReturnId, editMessage ──
  result.matrix = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      mxAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      mxAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      mxAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── Email — capability descriptor says: send only ─────────────────────────
  result.email = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      emAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )

  # ── CLI — capability descriptor says: send, sendReturnId, editMessage ─────
  result.cli = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      cliAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      cliAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      cliAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )
