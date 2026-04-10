## Concrete outbound channel ports built from channel adapters.

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

proc unsupportedSendReturnId(msg: OutboundMessage): Result[string, string] =
  err("sendReturnId unsupported for channel " & $msg.channel)

proc unsupportedEditMessage(userId: UserId; msgId, text: string): Result[void, string] =
  discard userId
  discard msgId
  discard text
  err("editMessage unsupported")

proc unsupportedSendKeyboard(userId: UserId; text: string;
                             buttons: seq[seq[(string, string)]];
                             replyTo = ""): Result[void, string] =
  discard userId
  discard text
  discard buttons
  discard replyTo
  err("sendKeyboard unsupported")

proc unsupportedEditKeyboard(userId: UserId; msgId, text: string;
                             buttons: seq[seq[(string, string)]]): Result[void, string] =
  discard userId
  discard msgId
  discard text
  discard buttons
  err("editKeyboard unsupported")

proc unsupportedSetMessageReaction(userId: UserId; msgId, emoji: string): Result[void, string] =
  discard userId
  discard msgId
  discard emoji
  err("setMessageReaction unsupported")

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
  result.wecom = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wcAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )
  result.wechat = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wchAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )
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
  result.feishu = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      fsAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )
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
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      dtAdapter[].editMessage(userId, msgId, text), ## DingTalk editMessage is text-only but used for kbd updates
    setMessageReaction: unsupportedSetMessageReaction,
  )
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
  result.email = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      emAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
  )
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
