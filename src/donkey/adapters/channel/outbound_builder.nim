## Concrete outbound channel ports built from channel adapters.

import ../../core/pipeops
import ../../domain/message
import ../../ports/channel
import telegram
import discord
import wecom
import wechat
import qq
import feishu

proc unsupportedSendReturnId(msg: OutboundMessage): Result[string, string] =
  err("sendReturnId unsupported for channel " & $msg.channel)

proc unsupportedEditMessage(userId: UserId; msgId, text: string): Result[void, string] =
  discard userId
  discard msgId
  discard text
  err("editMessage unsupported")

proc buildOutboundPorts*(tgAdapter: ptr TelegramAdapter;
                         dcAdapter: ptr DiscordAdapter;
                         wcAdapter: ptr WeComAdapter;
                         wchAdapter: ptr WeChatAdapter;
                         qqAdapter: ptr QQAdapter;
                         fsAdapter: ptr FeishuAdapter): OutboundChannelPorts =
  result.telegram = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      tgAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      tgAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      tgAdapter[].editMessage(userId, msgId, text),
  )
  result.discord = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      dcAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      dcAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
      dcAdapter[].editMessage(userId, msgId, text),
  )
  result.wecom = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wcAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
  )
  result.wechat = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wchAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
  )
  result.qq = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      qqAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
  )
  result.feishu = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      fsAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
  )
