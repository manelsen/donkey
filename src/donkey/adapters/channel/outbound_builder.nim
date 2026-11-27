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
import signal
import slack
import dingtalk
import line
import teams
import mattermost
import sms
import irc
import ntfy
import simplex
import google_chat
import cli_repl
import whatsapp

# ── generic unsupported stubs (capability-driven) ───────────────────────────
## These are used for any (channel, operation) pair where the capability
## descriptor declares the operation as unsupported.

proc unsupportedSend(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
  err("send unsupported for channel " & $msg.channel)

proc unsupportedSendReturnId(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
  err("sendReturnId unsupported for channel " & $msg.channel)

proc unsupportedEditMessage(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
  discard userId; discard msgId; discard text; discard isHtml
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

proc unsupportedSetMessageReaction(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} =
  discard userId; discard channelId; discard msgId; discard emoji
  err("setMessageReaction unsupported")

proc unsupportedDownloadFile(fileId: string): Result[FileDownload, string] {.gcsafe.} =
  discard fileId
  err("downloadFile unsupported")

# ── builder ──────────────────────────────────────────────────────────────────
## Each channel's OutboundChannelPort is assembled using the capability
## descriptor to decide whether to wire the real adapter method or fall back
## to the generic unsupported stub.  The descriptor is the single source of
## truth — the if/else branches here are a direct mirror of the registry in
## channel_capability.nim.
##
## Lifetime invariant: the closures capture raw `ptr` to each adapter, so the
## adapters must outlive every returned OutboundChannelPorts and must not move.
## The daemon satisfies this by keeping them in `DaemonContext.adapters`
## (a `ref object` alive for the whole process) and rebuilding the ports per
## tick instead of storing them. Never pass the address of a stack local
## whose ports escape the current scope.

type TelegramPick* = proc(userId: UserId): ptr TelegramAdapter {.gcsafe.}
  ## The adapter of the bot a person last wrote to (adapters/channel/
  ## telegram_bots); nil = one bot.

proc telegramOutboundPort*(tg: ptr TelegramAdapter;
                           pick: TelegramPick = nil): OutboundChannelPort =
  ## Every operation addressed to a person goes through that person's bot:
  ## the message ids, chats and keyboards of one bot mean nothing to another.
  ## A file is fetched by the adapter this port was built for (the bot whose
  ## update carried it).
  template forUser(userId: UserId): ptr TelegramAdapter =
    (if pick != nil: pick(userId) else: tg)
  OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      forUser(msg.userId)[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      forUser(msg.userId)[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
      forUser(userId)[].editMessage(userId, msgId, text, isHtml),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      forUser(userId)[].sendKeyboard(userId, text, buttons, replyTo).map(proc(s: string): void = discard s),
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      forUser(userId)[].editKeyboardText(userId, msgId, text, buttons),
    setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} =
      forUser(userId)[].setMessageReaction(userId, channelId, msgId, emoji),
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      tg[].downloadFile(fileId),
  )

type DiscordPick* = proc(userId: UserId): ptr DiscordAdapter {.gcsafe.}
  ## The adapter of the Discord bot a person last wrote to (discord_bots).

proc discordOutboundPort*(dc: ptr DiscordAdapter;
                          pick: DiscordPick = nil): OutboundChannelPort =
  ## As on Telegram: what is addressed to a person goes through their bot. An
  ## attachment is a CDN URL, fetched by the adapter the port was built for.
  template forUser(userId: UserId): ptr DiscordAdapter =
    (if pick != nil: pick(userId) else: dc)
  OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      forUser(msg.userId)[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      forUser(msg.userId)[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
      discard isHtml
      forUser(userId)[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      forUser(userId)[].sendKeyboard(userId, text, buttons).map(proc(s: string): void = discard s),
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      forUser(userId)[].editKeyboard(userId, msgId, text, buttons),
    setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string): Result[void, string] {.gcsafe.} =
      forUser(userId)[].setMessageReaction(userId, channelId, msgId, emoji),
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      dc[].downloadFile(fileId),
  )

type WhatsAppPick* = proc(userId: UserId): ptr WhatsAppAdapter {.gcsafe.}
  ## The adapter of the WhatsApp number a person last wrote to (whatsapp_bots).

proc whatsappOutboundPort*(wa: ptr WhatsAppAdapter;
                           pick: WhatsAppPick = nil): OutboundChannelPort =
  ## A message for a person goes from the number they wrote to; media ids
  ## belong to the account, so any of its numbers downloads them.
  template forUser(userId: UserId): ptr WhatsAppAdapter =
    (if pick != nil: pick(userId) else: wa)
  OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      forUser(msg.userId)[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      forUser(msg.userId)[].sendReturnId(msg),
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      wa[].downloadFile(fileId),
  )

proc mattermostOutboundPort*(mm: ptr MattermostAdapter): OutboundChannelPort =
  ## Text and attachments (E9.1), or unsupported without an adapter.
  OutboundChannelPort(
    send: if mm != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              mm[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: if mm != nil:
                    proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
                      mm[].downloadFile(fileId)
                  else:
                    unsupportedDownloadFile,
  )

proc smsOutboundPort*(a: ptr SmsAdapter): OutboundChannelPort =
  ## Send only, or unsupported without an adapter.
  OutboundChannelPort(
    send: if a != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              a[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: if a != nil:
                    proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
                      a[].downloadFile(fileId)
                  else:
                    unsupportedDownloadFile,
  )

proc ircOutboundPort*(a: ptr IrcAdapter): OutboundChannelPort =
  ## Send only, or unsupported without an adapter.
  OutboundChannelPort(
    send: if a != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              a[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )

proc ntfyOutboundPort*(a: ptr NtfyAdapter): OutboundChannelPort =
  ## Send only (E13.1), or unsupported without an adapter.
  OutboundChannelPort(
    send: if a != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              a[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )

proc simplexOutboundPort*(a: ptr SimplexAdapter): OutboundChannelPort =
  ## Send only (E13.2), or unsupported without an adapter.
  OutboundChannelPort(
    send: if a != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              a[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )

proc googleChatOutboundPort*(a: ptr GoogleChatAdapter): OutboundChannelPort =
  ## Text out, attachments in (E9.2), or unsupported without an adapter.
  OutboundChannelPort(
    send: if a != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              a[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: if a != nil:
                    proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
                      a[].downloadFile(fileId)
                  else:
                    unsupportedDownloadFile,
  )

type TeamsPick* = proc(userId: UserId): ptr TeamsAdapter {.gcsafe.}
  ## The adapter of the Teams app a person last wrote to (teams_bots).

proc teamsOutboundPort*(tm: ptr TeamsAdapter; pick: TeamsPick = nil): OutboundChannelPort =
  ## Text out through the person's app, attachments in (E9.4), or
  ## unsupported without an adapter. An inline image is fetched with the
  ## default app's token: the port does not know which app received it.
  OutboundChannelPort(
    send: if tm != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              (if pick != nil: pick(msg.userId) else: tm)[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: if tm != nil:
                    proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
                      tm[].downloadFile(fileId)
                  else:
                    unsupportedDownloadFile,
  )

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
                         waAdapter: ptr WhatsAppAdapter;
                         cliAdapter: ptr CliAdapter;
                         signalAdapter: ptr SignalAdapter = nil;
                         lineAdapter: ptr LineAdapter = nil;
                         teamsAdapter: ptr TeamsAdapter = nil;
                         mattermostAdapter: ptr MattermostAdapter = nil;
                         smsAdapter: ptr SmsAdapter = nil;
                         ircAdapter: ptr IrcAdapter = nil;
                         googleChatAdapter: ptr GoogleChatAdapter = nil;
                         ntfyAdapter: ptr NtfyAdapter = nil;
                         simplexAdapter: ptr SimplexAdapter = nil;
                         tgPick: TelegramPick = nil;
                         dcPick: DiscordPick = nil;
                         waPick: WhatsAppPick = nil;
                         teamsPick: TeamsPick = nil): OutboundChannelPorts =

  # ── Telegram (full capability) ────────────────────────────────────────────
  result.telegram = telegramOutboundPort(tgAdapter, tgPick)

  # ── Discord (full capability) ─────────────────────────────────────────────
  result.discord = discordOutboundPort(dcAdapter, dcPick)

  # ── WeCom — capability descriptor says: send only ─────────────────────────
  result.wecom = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wcAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )

  # ── WeChat — capability descriptor says: send, downloadFile ────────────────────────
  result.wechat = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      wchAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      wchAdapter[].downloadFile(fileId),
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
    downloadFile: unsupportedDownloadFile,
  )

  # ── Feishu — capability descriptor says: send, downloadFile ────────────────────────
  result.feishu = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      fsAdapter[].send(msg),
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      fsAdapter[].downloadFile(fileId),
  )

  # ── Slack — capability descriptor says: all except setMessageReaction ─────
  result.slack = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      slAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      slAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
      discard isHtml
      slAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      slAdapter[].sendKeyboard(userId, text, buttons),
    editKeyboard: proc(userId: UserId; msgId, text: string;
                        buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
      slAdapter[].editKeyboard(userId, msgId, text, buttons),
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )

  # ── DingTalk — capability descriptor says: send, sendReturnId, editMessage,
  #   sendKeyboard (no editKeyboard, no reaction) ─────────────────────────────
  result.dingtalk = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      dtAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      dtAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
      discard isHtml
      dtAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: proc(userId: UserId; text: string;
                        buttons: seq[seq[(string, string)]];
                        replyTo = ""): Result[void, string] {.gcsafe.} =
      dtAdapter[].sendKeyboard(userId, text, buttons),
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      dtAdapter[].downloadFile(fileId),
  )

  # ── WhatsApp — capability descriptor says: send + sendMedia + downloadFile ──
  result.whatsapp = whatsappOutboundPort(waAdapter, waPick)

  # ── Matrix — capability descriptor says: send, sendReturnId, editMessage ──
  result.matrix = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      mxAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      mxAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
      discard isHtml
      mxAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: proc(fileId: string): Result[FileDownload, string] {.gcsafe.} =
      mxAdapter[].downloadFile(fileId),
  )

  # ── Teams — capability descriptor says: send, downloadFile ─────────────────────────
  result.teams = teamsOutboundPort(teamsAdapter, teamsPick)
  result.mattermost = mattermostOutboundPort(mattermostAdapter)
  result.sms = smsOutboundPort(smsAdapter)
  result.irc = ircOutboundPort(ircAdapter)
  result.googleChat = googleChatOutboundPort(googleChatAdapter)
  result.ntfy = ntfyOutboundPort(ntfyAdapter)
  result.simplex = simplexOutboundPort(simplexAdapter)

  # ── LINE — capability descriptor says: send only ──────────────────────────
  result.line = OutboundChannelPort(
    send: if lineAdapter != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              lineAdapter[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
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
    downloadFile: unsupportedDownloadFile,
  )

  # ── Signal — capability descriptor says: send only ───────────────────────
  result.signal = OutboundChannelPort(
    send: if signalAdapter != nil:
            proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
              signalAdapter[].send(msg)
          else:
            unsupportedSend,
    sendReturnId: unsupportedSendReturnId,
    editMessage: unsupportedEditMessage,
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )

  # ── CLI — capability descriptor says: send, sendReturnId, editMessage ─────
  result.cli = OutboundChannelPort(
    send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
      cliAdapter[].send(msg),
    sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} =
      cliAdapter[].sendReturnId(msg),
    editMessage: proc(userId: UserId; msgId, text: string; isHtml: bool): Result[void, string] {.gcsafe.} =
      discard isHtml
      cliAdapter[].editMessage(userId, msgId, text),
    sendKeyboard: unsupportedSendKeyboard,
    editKeyboard: unsupportedEditKeyboard,
    setMessageReaction: unsupportedSetMessageReaction,
    downloadFile: unsupportedDownloadFile,
  )
