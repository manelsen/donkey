## Requester-only replies (link codes, /continue, /doctor, /memory, /whoami)
## never reach a shared space, on any channel. Discord has its own recorder
## test (t_discord_command_replies); this file covers the others.

import std/unittest
import donkey/core/commands/command_routing
import donkey/domain/message
import donkey/ports/channel_capability
import donkey/app/command_dispatch
import donkey/adapters/channel/qq_channel
import donkey/adapters/channel/qq_runtime
import donkey/adapters/channel/telegram_runtime

let secret = replied(rtLinkCode, "Your link code: `ABC123`").reply
let public = replied(rtStatus, "Status").reply

proc runTests*() =
  suite "requester-only routes":
    test "Telegram: a group gets the notice, never the content":
      let group = InboundMessage(userId: UserId("u"), channel: ckTelegram,
                                 channelId: "-100", isGroup: true)
      check telegramReplyRoute(group, secret) == rrNotice
      check telegramReplyRoute(group, public) == rrConversation

    test "Telegram: a private chat gets the content":
      let dm = InboundMessage(userId: UserId("u"), channel: ckTelegram, channelId: "42")
      check telegramReplyRoute(dm, secret) == rrConversation

    test "Telegram refuses requester-only commands in groups before dispatch":
      for kind in [cmdMyCode, cmdContinue, cmdDoctor, cmdMemory, cmdWhoami]:
        check requesterOnlyCommand(newCommandDecision(kind))
      for kind in [cmdHelp, cmdAbout, cmdStatus, cmdReset]:
        check not requesterOnlyCommand(newCommandDecision(kind))

    test "QQ: a group message is a shared space without a private path":
      let group = QQInboundEvent(messageType: "group", userId: "7", groupId: "99")
      let dm = QQInboundEvent(messageType: "private", userId: "7")
      check qqInSharedSpace(group)
      check not qqInSharedSpace(dm)
      let delivered = replyDelivery(secret, qqInSharedSpace(group), hasPrivatePath = false)
      check delivered.route == rrNotice
      check delivered.text == RequesterOnlyNotice
      check replyDelivery(secret, qqInSharedSpace(dm), false).text == secret.text

    test "channels that address every reply to the requester declare it":
      for kind in [ckFeishu, ckWeCom, ckWeChat, ckWhatsApp, ckSlack]:
        check capability(kind).repliesToRequester
      for kind in [ckTelegram, ckDiscord, ckQQ]:
        check not capability(kind).repliesToRequester

    test "a failed private send has no public fallback route":
      check routeReply(secret, inSharedSpace = true, hasPrivatePath = true) == rrPrivate
      check routeReply(secret, inSharedSpace = true, hasPrivatePath = false) == rrNotice

when isMainModule:
  runTests()
